import { common } from '@kit.AbilityKit';
import { completeOnce } from './ChatClient';
import { selectApiKey } from './KeyPool';
import { ChatMessage, Conversation, Persona, Provider, ScheduledTask, Workspace } from './Models';
import { expandPromptTemplates } from './PromptEngine';
import { isTaskDue } from './ScheduleCalc';
import { newId, readKey } from './Storage';
import { notifyGenerationComplete } from './SystemBridge';

export interface ScheduledTaskHost {
  getWorkspace: () => Workspace;
  getContext: () => common.UIAbilityContext | undefined;
  onTaskResult: (updatedTask: ScheduledTask, newConversation?: Conversation) => Promise<void>;
}

export class ScheduledTaskRunner {
  private timerId: number = -1;
  private host?: ScheduledTaskHost;
  private busy: boolean = false;

  start(host: ScheduledTaskHost): void {
    this.stop();
    this.host = host;
    this.checkDueTasks().catch(() => {});
    this.timerId = setInterval(() => {
      this.checkDueTasks().catch(() => {});
    }, 60000);
  }

  stop(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  async checkDueTasks(): Promise<void> {
    if (this.busy || !this.host) {
      return;
    }
    const ws = this.host.getWorkspace();
    const tasks = ws.scheduledTasks || [];
    const now = Date.now();
    for (let i = 0; i < tasks.length; i++) {
      if (isTaskDue(tasks[i], now)) {
        await this.executeTask(tasks[i]);
      }
    }
  }

  async executeTask(task: ScheduledTask): Promise<void> {
    if (this.busy || !this.host) {
      return;
    }
    this.busy = true;
    const startedAt = Date.now();
    try {
      const ws = this.host.getWorkspace();
      const prov = ws.providers.find((p: Provider): boolean => p.id === task.providerId)
        ?? ws.providers.find((p: Provider): boolean => p.id === ws.activeProvider)
        ?? ws.providers[0];
      if (!prov) {
        throw new Error('未找到可用模型服务商');
      }
      const persona = ws.personas.find((p: Persona): boolean => p.id === task.personaId) ?? ws.personas[0];
      const modelId = task.modelId.trim().length > 0 ? task.modelId.trim() : prov.model;

      let apiKey = '';
      if (prov.apiKeys && prov.apiKeys.length > 0) {
        const picked = selectApiKey(prov.id, prov.apiKeys, prov.keyStrategy || 'round_robin');
        if (picked) {
          apiKey = await readKey(picked.secretRef);
        }
      }
      if (!apiKey && prov.secretRef) {
        apiKey = await readKey(prov.secretRef);
      }
      const proxyPass = prov.proxy?.passwordRef ? await readKey(prov.proxy.passwordRef) : '';

      const expandedPrompt = expandPromptTemplates(task.prompt, {
        assistantName: persona?.name || 'Assistant',
        modelName: modelId,
        providerName: prov.name,
        conversationTitle: task.name
      });
      const sysPrompt = persona ? expandPromptTemplates(persona.prompt, {
        assistantName: persona.name,
        modelName: modelId,
        providerName: prov.name
      }) : '';

      const reply = await completeOnce(prov, apiKey, sysPrompt, expandedPrompt, modelId, 2048, proxyPass);
      const chatId = 'sched_chat_' + newId();
      const userMsg: ChatMessage = {
        id: 'm_' + newId(),
        role: 'user',
        text: expandedPrompt,
        model: '',
        createdAt: startedAt
      };
      const aiMsg: ChatMessage = {
        id: 'm_' + newId(),
        role: 'assistant',
        text: reply,
        model: modelId,
        createdAt: Date.now()
      };
      const conv: Conversation = {
        id: chatId,
        title: `[定时] ${task.name}`,
        updated: Date.now(),
        messages: [userMsg, aiMsg],
        personaId: persona ? persona.id : 'default'
      };
      const updatedTask: ScheduledTask = {
        id: task.id,
        name: task.name,
        personaId: task.personaId,
        providerId: task.providerId,
        modelId: task.modelId,
        prompt: task.prompt,
        scheduleType: task.scheduleType,
        timeHHMM: task.timeHHMM,
        weekdays: task.weekdays.slice(),
        intervalMinutes: task.intervalMinutes,
        runAtMs: task.runAtMs,
        enabled: task.scheduleType === 'once' ? false : task.enabled,
        lastRunAt: Date.now(),
        lastStatus: '运行成功',
        lastConversationId: chatId
      };
      await this.host.onTaskResult(updatedTask, conv);
      const notifyOn = ws.systemSettings?.backgroundNotifyEnabled !== false;
      await notifyGenerationComplete(this.host.getContext(), notifyOn, `定时任务：${task.name}`, reply);
    } catch (e) {
      const updatedTask: ScheduledTask = {
        id: task.id,
        name: task.name,
        personaId: task.personaId,
        providerId: task.providerId,
        modelId: task.modelId,
        prompt: task.prompt,
        scheduleType: task.scheduleType,
        timeHHMM: task.timeHHMM,
        weekdays: task.weekdays.slice(),
        intervalMinutes: task.intervalMinutes,
        runAtMs: task.runAtMs,
        enabled: task.enabled,
        lastRunAt: Date.now(),
        lastStatus: `失败: ${(e as Error).message || String(e)}`,
        lastConversationId: task.lastConversationId
      };
      await this.host.onTaskResult(updatedTask, undefined);
    } finally {
      this.busy = false;
    }
  }
}
