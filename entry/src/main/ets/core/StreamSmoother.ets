import { ResponseSpeedMode } from './Models';

export interface StreamStepResult {
  text: string;
  reasoning: string;
  textChanged: boolean;
  reasoningChanged: boolean;
  hasMore: boolean;
}

function isHighSurrogate(code: number): boolean {
  return code >= 0xD800 && code <= 0xDBFF;
}

function snapSafeCut(src: string, nextLen: number, minLen: number = 0): number {
  let cut = Math.max(0, Math.min(src.length, nextLen));
  if (cut <= 0 || cut >= src.length) {
    return cut;
  }
  const prevCode = src.charCodeAt(cut - 1);
  if (isHighSurrogate(prevCode)) {
    if (cut - 1 > minLen) {
      cut -= 1;
    } else if (cut < src.length) {
      cut += 1;
    }
    if (cut <= 0 || cut >= src.length) {
      return cut;
    }
  }
  // Avoid flashing partial Markdown marker pairs (*, `, $) when the closing marker is already buffered.
  const prevCh = src[cut - 1];
  if ((prevCh === '*' || prevCh === '`' || prevCh === '$') && src[cut] === prevCh) {
    let advanced = cut;
    let steps = 0;
    while (advanced < src.length && src[advanced] === prevCh && steps < 2) {
      advanced += 1;
      steps += 1;
    }
    cut = advanced;
  }
  return cut;
}

export class StreamTextSmoother {
  private readonly speed: ResponseSpeedMode;
  private readonly reduceMotion: boolean;
  private targetText: string = '';
  private shownTextLen: number = 0;
  private textCarry: number = 0;
  private targetReasoning: string = '';
  private shownReasoningLen: number = 0;
  private reasoningCarry: number = 0;

  constructor(speed: ResponseSpeedMode = 'standard', reduceMotion: boolean = false) {
    this.speed = speed;
    this.reduceMotion = reduceMotion;
  }

  setTarget(text: string, reasoning: string): void {
    const prevTextLen = this.targetText.length;
    if (!text.startsWith(this.targetText.slice(0, this.shownTextLen))) {
      this.shownTextLen = Math.min(this.shownTextLen, text.length);
      this.textCarry = 0;
    } else if (this.shownTextLen >= prevTextLen && text.length > prevTextLen) {
      this.textCarry = Math.max(this.textCarry, 1);
    }
    this.targetText = text;
    if (this.shownTextLen > text.length) {
      this.shownTextLen = text.length;
    }

    const prevReasonLen = this.targetReasoning.length;
    if (!reasoning.startsWith(this.targetReasoning.slice(0, this.shownReasoningLen))) {
      this.shownReasoningLen = Math.min(this.shownReasoningLen, reasoning.length);
      this.reasoningCarry = 0;
    } else if (this.shownReasoningLen >= prevReasonLen && reasoning.length > prevReasonLen) {
      this.reasoningCarry = Math.max(this.reasoningCarry, 1);
    }
    this.targetReasoning = reasoning;
    if (this.shownReasoningLen > reasoning.length) {
      this.shownReasoningLen = reasoning.length;
    }
  }

  hasPending(): boolean {
    return this.shownTextLen < this.targetText.length || this.shownReasoningLen < this.targetReasoning.length;
  }

  snapToTarget(): StreamStepResult {
    const textChanged = this.shownTextLen !== this.targetText.length;
    const reasoningChanged = this.shownReasoningLen !== this.targetReasoning.length;
    this.shownTextLen = this.targetText.length;
    this.shownReasoningLen = this.targetReasoning.length;
    this.textCarry = 0;
    this.reasoningCarry = 0;
    return {
      text: this.targetText,
      reasoning: this.targetReasoning,
      textChanged,
      reasoningChanged,
      hasMore: false
    };
  }

  step(dtMs: number): StreamStepResult {
    if (this.reduceMotion || this.speed === 'ultrafast') {
      return this.snapToTarget();
    }
    const dt = Math.max(8, Math.min(64, dtMs));
    const tauMs = this.speed === 'fast' ? 70 : 135;
    const minCharsPerSec = this.speed === 'fast' ? 120 : 55;

    const prevTextLen = this.shownTextLen;
    const prevReasonLen = this.shownReasoningLen;

    const remText = this.targetText.length - this.shownTextLen;
    if (remText > 0) {
      const delta = Math.max(remText * (dt / tauMs), minCharsPerSec * (dt / 1000));
      this.textCarry += delta;
      let count = Math.min(remText, Math.floor(this.textCarry));
      if (count <= 0 && this.textCarry >= 1) {
        count = 1;
      }
      if (count > 0) {
        const rawNext = this.shownTextLen + count;
        const safeNext = snapSafeCut(this.targetText, rawNext, this.shownTextLen);
        const nextLen = safeNext > this.shownTextLen ? safeNext : Math.min(this.targetText.length, rawNext);
        this.textCarry = Math.max(0, this.textCarry - (nextLen - this.shownTextLen));
        this.shownTextLen = nextLen;
      }
    } else {
      this.textCarry = 0;
    }

    const remReason = this.targetReasoning.length - this.shownReasoningLen;
    if (remReason > 0) {
      const deltaR = Math.max(remReason * (dt / tauMs), minCharsPerSec * (dt / 1000));
      this.reasoningCarry += deltaR;
      let countR = Math.min(remReason, Math.floor(this.reasoningCarry));
      if (countR <= 0 && this.reasoningCarry >= 1) {
        countR = 1;
      }
      if (countR > 0) {
        const rawNextR = this.shownReasoningLen + countR;
        const safeNextR = snapSafeCut(this.targetReasoning, rawNextR, this.shownReasoningLen);
        const nextLenR = safeNextR > this.shownReasoningLen
          ? safeNextR
          : Math.min(this.targetReasoning.length, rawNextR);
        this.reasoningCarry = Math.max(0, this.reasoningCarry - (nextLenR - this.shownReasoningLen));
        this.shownReasoningLen = nextLenR;
      }
    } else {
      this.reasoningCarry = 0;
    }

    const textChanged = this.shownTextLen !== prevTextLen;
    const reasoningChanged = this.shownReasoningLen !== prevReasonLen;
    return {
      text: this.targetText.slice(0, this.shownTextLen),
      reasoning: this.targetReasoning.slice(0, this.shownReasoningLen),
      textChanged,
      reasoningChanged,
      hasMore: this.hasPending()
    };
  }
}
