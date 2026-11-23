import { ChatStream } from './ChatClient';
import { ApiFamily, ToolCallRecord } from './Models';
import { WebSearch } from './WebSearch';

export class ChatGenerationJob {
  readonly chatId: string;
  title: string;
  liveMessageId: string;
  regeneratingMsgId: string;
  modelId: string;
  providerName: string;
  providerFamily: ApiFamily;
  personaId: string;
  liveText: string = '';
  liveReasoning: string = '';
  liveThinking: boolean = false;
  liveReasoningMs: number = 0;
  liveToolCalls: ToolCallRecord[] = [];
  fetchingSources: boolean = false;
  pendingApprovalTool: string = '';
  pendingApprovalArgs: string = '';
  approvalResolver?: (choice: 'allow_once' | 'allow_all' | 'deny') => void;
  askQuestionText: string = '';
  askQuestionOptions: string[] = [];
  askQuestionPlaceholder: string = '';
  askQuestionAnswer: string = '';
  askUserResolver?: (val: string) => void;
  stream?: ChatStream;
  searcher?: WebSearch;
  stopped: boolean = false;
  deleted: boolean = false;
  flushTimer: number = -1;

  constructor(
    chatId: string,
    title: string,
    liveMessageId: string,
    regeneratingMsgId: string,
    modelId: string,
    providerName: string,
    providerFamily: ApiFamily,
    personaId: string
  ) {
    this.chatId = chatId;
    this.title = title;
    this.liveMessageId = liveMessageId;
    this.regeneratingMsgId = regeneratingMsgId;
    this.modelId = modelId;
    this.providerName = providerName;
    this.providerFamily = providerFamily;
    this.personaId = personaId;
  }

  stop(): void {
    this.stopped = true;
    this.stream?.stop();
    this.searcher?.stop();
    if (this.approvalResolver) {
      const res = this.approvalResolver;
      this.approvalResolver = undefined;
      this.pendingApprovalTool = '';
      this.pendingApprovalArgs = '';
      res('deny');
    }
    if (this.askUserResolver) {
      const res = this.askUserResolver;
      this.askUserResolver = undefined;
      this.askQuestionText = '';
      this.askQuestionOptions = [];
      this.askQuestionPlaceholder = '';
      this.askQuestionAnswer = '';
      res('');
    }
  }

  clearTimer(): void {
    if (this.flushTimer >= 0) {
      clearTimeout(this.flushTimer);
      this.flushTimer = -1;
    }
  }

  hasPendingPrompt(): boolean {
    return this.pendingApprovalTool.length > 0 || this.askQuestionText.length > 0;
  }
}

export interface GenerationViewProjection {
  working: boolean;
  liveMessageId: string;
  liveText: string;
  liveReasoning: string;
  liveThinking: boolean;
  liveReasoningMs: number;
  liveToolCalls: ToolCallRecord[];
  fetchingSources: boolean;
  regeneratingMsgId: string;
  pendingApprovalTool: string;
  pendingApprovalArgs: string;
  askQuestionText: string;
  askQuestionOptions: string[];
  askQuestionPlaceholder: string;
  askQuestionAnswer: string;
  lastSendError: string;
  lastSendErrorChatId: string;
}

export interface OtherPendingPromptInfo {
  chatId: string;
  label: string;
}

export class GenerationSessionRegistry {
  private jobs: Map<string, ChatGenerationJob> = new Map<string, ChatGenerationJob>();
  private errors: Map<string, string> = new Map<string, string>();

  get(chatId: string): ChatGenerationJob | undefined {
    if (!chatId) {
      return undefined;
    }
    return this.jobs.get(chatId);
  }

  isGenerating(chatId: string): boolean {
    if (!chatId) {
      return false;
    }
    return this.jobs.has(chatId);
  }

  hasAny(): boolean {
    return this.jobs.size > 0;
  }

  activeChatIds(): string[] {
    return Array.from(this.jobs.keys());
  }

  hasOtherGenerating(activeChatId: string): boolean {
    let found = false;
    this.jobs.forEach((_job: ChatGenerationJob, id: string) => {
      if (id !== activeChatId) {
        found = true;
      }
    });
    return found;
  }

  start(job: ChatGenerationJob): void {
    this.errors.delete(job.chatId);
    this.jobs.set(job.chatId, job);
  }

  finish(chatId: string, job: ChatGenerationJob): void {
    job.clearTimer();
    if (this.jobs.get(chatId) === job) {
      this.jobs.delete(chatId);
    }
  }

  setError(chatId: string, errMsg: string): void {
    if (!chatId) {
      return;
    }
    if (errMsg) {
      this.errors.set(chatId, errMsg);
    } else {
      this.errors.delete(chatId);
    }
  }

  clearError(chatId: string): void {
    if (!chatId) {
      return;
    }
    this.errors.delete(chatId);
  }

  getError(chatId: string): string {
    if (!chatId) {
      return '';
    }
    return this.errors.get(chatId) || '';
  }

  stopChat(chatId: string): boolean {
    const job = this.jobs.get(chatId);
    if (!job) {
      return false;
    }
    job.stop();
    return true;
  }

  markDeletedAndStop(chatId: string): void {
    this.errors.delete(chatId);
    const job = this.jobs.get(chatId);
    if (job) {
      job.deleted = true;
      job.stop();
    }
  }

  stopAll(markDeleted: boolean = false): void {
    this.jobs.forEach((job: ChatGenerationJob) => {
      if (markDeleted) {
        job.deleted = true;
      }
      job.stop();
    });
  }

  findOtherPendingPrompt(activeChatId: string): OtherPendingPromptInfo | undefined {
    let found: OtherPendingPromptInfo | undefined = undefined;
    this.jobs.forEach((job: ChatGenerationJob) => {
      if (found || job.chatId === activeChatId || !job.hasPendingPrompt()) {
        return;
      }
      const chatLabel = (job.title.trim() || '对话').slice(0, 18);
      if (job.pendingApprovalTool.length > 0) {
        found = {
          chatId: job.chatId,
          label: `「${chatLabel}」等待工具授权`
        };
      } else {
        found = {
          chatId: job.chatId,
          label: `「${chatLabel}」等待您的确认`
        };
      }
    });
    return found;
  }

  projectForChat(activeChatId: string): GenerationViewProjection {
    const job = activeChatId ? this.jobs.get(activeChatId) : undefined;
    const err = activeChatId ? (this.errors.get(activeChatId) || '') : '';
    if (!job) {
      return {
        working: false,
        liveMessageId: '',
        liveText: '',
        liveReasoning: '',
        liveThinking: false,
        liveReasoningMs: 0,
        liveToolCalls: [],
        fetchingSources: false,
        regeneratingMsgId: '',
        pendingApprovalTool: '',
        pendingApprovalArgs: '',
        askQuestionText: '',
        askQuestionOptions: [],
        askQuestionPlaceholder: '',
        askQuestionAnswer: '',
        lastSendError: err,
        lastSendErrorChatId: err ? activeChatId : ''
      };
    }
    return {
      working: true,
      liveMessageId: job.liveMessageId,
      liveText: job.liveText,
      liveReasoning: job.liveReasoning,
      liveThinking: job.liveThinking,
      liveReasoningMs: job.liveReasoningMs,
      liveToolCalls: job.liveToolCalls.slice(),
      fetchingSources: job.fetchingSources,
      regeneratingMsgId: job.regeneratingMsgId,
      pendingApprovalTool: job.pendingApprovalTool,
      pendingApprovalArgs: job.pendingApprovalArgs,
      askQuestionText: job.askQuestionText,
      askQuestionOptions: job.askQuestionOptions.slice(),
      askQuestionPlaceholder: job.askQuestionPlaceholder,
      askQuestionAnswer: job.askQuestionAnswer,
      lastSendError: err,
      lastSendErrorChatId: err ? activeChatId : ''
    };
  }
}
