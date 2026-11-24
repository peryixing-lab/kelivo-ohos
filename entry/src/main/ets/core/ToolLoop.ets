import {
  Attachment,
  ChatMessage,
  GenerationParams,
  HeaderEntry,
  ModelSpec,
  PresetMessage,
  Provider,
  ProxyConfig,
  SearchHit,
  TokenUsage,
  ToolCallRecord,
  ToolPermissionMode
} from './Models';
import { mergeDeduplicatedCitations } from './BuiltinSearch';
import {
  ChatCall,
  ChatCallOptions,
  RichFragment,
  ToolCallDelta,
  ToolDeclaration,
  WireToolTurn,
  makeAdvancedChatCall
} from './Protocol';
import { RegisteredTool } from './ToolRegistry';

export interface ToolExecutionOutput {
  text: string;
  diffText?: string;
  images?: Attachment[];
  isError?: boolean;
}

export interface AgentLoopParams {
  provider: Provider;
  apiKey: string;
  modelId: string;
  modelSpec?: ModelSpec;
  conversationId?: string;
  stream?: boolean;
  systemPrompt: string;
  history: ChatMessage[];
  genParams: GenerationParams;
  presetMessages?: PresetMessage[];
  customHeaders?: HeaderEntry[];
  customBodyJson?: string;
  builtinSearch?: boolean;
  claudeDynamicSearch?: boolean;
  tools: RegisteredTool[];
  permissionMode: ToolPermissionMode;
  maxSteps: number;
  proxy?: ProxyConfig;
  proxyPassword?: string;
  runStream: (call: ChatCall, onFrag: (f: RichFragment) => void) => Promise<void>;
  executeTool: (tool: RegisteredTool, argsJson: string) => Promise<ToolExecutionOutput>;
  requestApproval: (tool: RegisteredTool, argsJson: string) => Promise<'allow_once' | 'allow_all' | 'deny'>;
  onUpdate: (liveText: string, liveReasoning: string, records: ToolCallRecord[]) => void;
  onContextLog?: (payloadJson: string) => void;
  isStopped: () => boolean;
}

export interface AgentLoopResult {
  text: string;
  reasoning: string;
  toolCalls: ToolCallRecord[];
  generatedImages: Attachment[];
  citations: SearchHit[];
  usage?: TokenUsage;
}

export interface ToolCallGroup {
  name: string;
  records: ToolCallRecord[];
  count: number;
  status: 'pending' | 'running' | 'done' | 'error' | 'denied';
  failedCount: number;
  totalDurationMs: number;
}

function resolveGroupStatus(records: ToolCallRecord[]): 'pending' | 'running' | 'done' | 'error' | 'denied' {
  let hasPending = false;
  let hasRunning = false;
  let hasDone = false;
  let hasError = false;
  let hasDenied = false;
  for (let i = 0; i < records.length; i++) {
    const st = records[i].status;
    if (st === 'pending') hasPending = true;
    else if (st === 'running') hasRunning = true;
    else if (st === 'done') hasDone = true;
    else if (st === 'error') hasError = true;
    else if (st === 'denied') hasDenied = true;
  }
  if (hasPending) return 'pending';
  if (hasRunning) return 'running';
  if (hasDenied && !hasDone && !hasError && !hasPending && !hasRunning) return 'denied';
  if ((hasError || hasDenied) && !hasDone) return 'error';
  return 'done';
}

/**
 * Collapses repeated tool calls with the same tool name into ordered groups.
 */
export function groupToolCallRecords(records: ToolCallRecord[]): ToolCallGroup[] {
  const groups: ToolCallGroup[] = [];
  const indexByName = new Map<string, number>();

  for (let i = 0; i < records.length; i++) {
    const rec = records[i];
    const existingIdx = indexByName.get(rec.name);
    if (existingIdx !== undefined) {
      groups[existingIdx].records.push(rec);
    } else {
      indexByName.set(rec.name, groups.length);
      groups.push({
        name: rec.name,
        records: [rec],
        count: 1,
        status: rec.status,
        failedCount: 0,
        totalDurationMs: 0
      });
    }
  }

  for (let i = 0; i < groups.length; i++) {
    const grp = groups[i];
    let failed = 0;
    let totalMs = 0;
    for (let j = 0; j < grp.records.length; j++) {
      const item = grp.records[j];
      totalMs += item.durationMs;
      if (item.status === 'error' || item.status === 'denied') {
        failed += 1;
      }
    }
    grp.count = grp.records.length;
    grp.failedCount = failed;
    grp.totalDurationMs = totalMs;
    grp.status = resolveGroupStatus(grp.records);
  }
  return groups;
}

interface PendingToolCall {
  index: number;
  id: string;
  name: string;
  argsJson: string;
}

export function accumulateToolDeltas(existing: PendingToolCall[], incoming: ToolCallDelta[]): PendingToolCall[] {
  const next = existing.slice();
  for (let i = 0; i < incoming.length; i++) {
    const d = incoming[i];
    let found = next.find((item: PendingToolCall): boolean =>
      (d.id && item.id === d.id) || item.index === d.index
    );
    if (!found) {
      found = { index: d.index, id: d.id || ('call_' + d.index + '_' + next.length), name: d.name || '', argsJson: '' };
      next.push(found);
    }
    if (d.id) found.id = d.id;
    if (d.name) found.name = d.name;
    if (d.argsDelta) found.argsJson += d.argsDelta;
  }
  return next;
}

export async function runAgentToolLoop(params: AgentLoopParams): Promise<AgentLoopResult> {
  const toolTurns: WireToolTurn[] = [];
  const allToolRecords: ToolCallRecord[] = [];
  const allGeneratedImages: Attachment[] = [];
  let allCitations: SearchHit[] = [];
  const decls: ToolDeclaration[] = params.tools.map((t: RegisteredTool): ToolDeclaration => t.declaration);
  let permMode: ToolPermissionMode = params.permissionMode;
  let totalText = '';
  let totalReasoning = '';
  let lastUsage: TokenUsage | undefined = undefined;
  let totalPrompt = 0;
  let totalCompletion = 0;
  let totalCached = 0;

  for (let step = 0; step < params.maxSteps; step++) {
    if (params.isStopped()) break;
    const callOpts: ChatCallOptions = {
      modelId: params.modelId,
      modelSpec: params.modelSpec,
      conversationId: params.conversationId,
      stream: params.stream,
      params: params.genParams,
      tools: decls,
      toolTurns,
      presetMessages: params.presetMessages,
      customHeaders: params.customHeaders,
      customBodyJson: params.customBodyJson,
      promptCaching: params.provider.promptCaching,
      builtinSearch: params.builtinSearch,
      claudeDynamicSearch: params.claudeDynamicSearch,
      builtinUrlContext: params.modelSpec?.builtinUrlContext ?? params.provider.builtinUrlContext,
      builtinCodeExec: params.modelSpec?.builtinCodeExec ?? params.provider.builtinCodeExec
    };
    const call = makeAdvancedChatCall(params.provider, params.apiKey, params.systemPrompt, params.history, callOpts);
    params.onContextLog?.(call.body);

    let stepText = '';
    let stepReasoning = '';
    let pendingCalls: PendingToolCall[] = [];
    const stepUsage: TokenUsage = { promptTokens: 0, completionTokens: 0, cachedTokens: 0, totalTokens: 0, durationMs: 0 };
    let hasStepUsage = false;

    await params.runStream(call, (frag: RichFragment) => {
      if (frag.text) {
        stepText += frag.text;
        totalText += frag.text;
      }
      if (frag.reasoning) {
        stepReasoning += frag.reasoning;
        totalReasoning += frag.reasoning;
      }
      if (frag.toolCalls.length > 0) {
        pendingCalls = accumulateToolDeltas(pendingCalls, frag.toolCalls);
      }
      if (frag.generatedImages.length > 0) {
        allGeneratedImages.push(...frag.generatedImages);
      }
      if (frag.citations && frag.citations.length > 0) {
        allCitations = mergeDeduplicatedCitations(allCitations, frag.citations);
      }
      if (frag.usage) {
        stepUsage.promptTokens = frag.usage.promptTokens;
        stepUsage.completionTokens = frag.usage.completionTokens;
        stepUsage.cachedTokens = frag.usage.cachedTokens;
        stepUsage.totalTokens = frag.usage.totalTokens;
        hasStepUsage = true;
      }
      params.onUpdate(totalText, totalReasoning, allToolRecords);
    });

    if (hasStepUsage) {
      totalPrompt += stepUsage.promptTokens;
      totalCompletion += stepUsage.completionTokens;
      totalCached += stepUsage.cachedTokens;
      lastUsage = {
        promptTokens: totalPrompt,
        completionTokens: totalCompletion,
        cachedTokens: totalCached,
        totalTokens: totalPrompt + totalCompletion,
        durationMs: 0
      };
    }

    if (params.isStopped() || !pendingCalls.length) {
      break;
    }

    // Record assistant tool-call turn
    const turnCalls: ToolCallDelta[] = pendingCalls.map((pc: PendingToolCall): ToolCallDelta => {
      return {
        index: pc.index,
        id: pc.id,
        name: pc.name,
        argsDelta: pc.argsJson.trim() || '{}',
        done: true
      };
    });
    toolTurns.push({ role: 'assistant', text: stepText, reasoning: stepReasoning || undefined, toolCalls: turnCalls });

    // Execute each tool call
    for (let i = 0; i < pendingCalls.length; i++) {
      if (params.isStopped()) break;
      const pc = pendingCalls[i];
      const argsJson = pc.argsJson.trim() || '{}';
      const registered = params.tools.find((t: RegisteredTool): boolean => t.declaration.name === pc.name);
      const record: ToolCallRecord = {
        id: pc.id,
        name: pc.name,
        argsJson,
        status: 'running',
        resultText: '',
        durationMs: 0
      };
      allToolRecords.push(record);
      params.onUpdate(totalText, totalReasoning, allToolRecords);

      const tStart = Date.now();
      if (pc.name === '$web_search' && params.builtinSearch) {
        record.status = 'done';
        record.resultText = '已触发模型内置联网搜索';
        record.durationMs = Date.now() - tStart;
        params.onUpdate(totalText, totalReasoning, allToolRecords);
        toolTurns.push({ role: 'tool', toolCallId: pc.id, toolName: pc.name, toolResult: argsJson });
        continue;
      }
      if (!registered) {
        record.status = 'error';
        record.resultText = '未找到工具: ' + pc.name;
        record.durationMs = Date.now() - tStart;
        toolTurns.push({ role: 'tool', toolCallId: pc.id, toolName: pc.name, toolResult: record.resultText });
        continue;
      }

      if (permMode === 'ask' && registered.requiresApproval) {
        record.status = 'pending';
        params.onUpdate(totalText, totalReasoning, allToolRecords);
        const decision = await params.requestApproval(registered, argsJson);
        if (decision === 'allow_all') permMode = 'full';
        if (decision === 'deny') {
          record.status = 'denied';
          record.resultText = '用户拒绝执行此工具调用';
          record.durationMs = Date.now() - tStart;
          params.onUpdate(totalText, totalReasoning, allToolRecords);
          toolTurns.push({ role: 'tool', toolCallId: pc.id, toolName: pc.name, toolResult: record.resultText });
          continue;
        }
        record.status = 'running';
        params.onUpdate(totalText, totalReasoning, allToolRecords);
      }

      try {
        const out = await params.executeTool(registered, argsJson);
        record.status = out.isError ? 'error' : 'done';
        record.resultText = out.text;
        record.diffText = out.diffText;
        record.imageAttachments = out.images;
        if (out.images?.length) allGeneratedImages.push(...out.images);
      } catch (err) {
        record.status = 'error';
        record.resultText = '工具执行失败: ' + ((err as Error).message || '未知错误');
      }
      record.durationMs = Date.now() - tStart;
      params.onUpdate(totalText, totalReasoning, allToolRecords);

      toolTurns.push({
        role: 'tool',
        toolCallId: pc.id,
        toolName: pc.name,
        toolResult: record.resultText.slice(0, 24000)
      });
    }

    if (totalText && !totalText.endsWith('\n')) {
      totalText += '\n\n';
    }
  }

  return {
    text: totalText,
    reasoning: totalReasoning,
    toolCalls: allToolRecords,
    generatedImages: allGeneratedImages,
    citations: allCitations,
    usage: lastUsage
  };
}
