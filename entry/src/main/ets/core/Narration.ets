import { textToSpeech } from '@kit.CoreSpeechKit';
import { http } from '@kit.NetworkKit';
import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { TtsConfig, checkEndpoint } from './Models';

interface CloudTtsPayload {
  url: string;
  headers: Record<string, string>;
  body: string | ArrayBuffer;
  isJsonAudio?: boolean;
}

interface GeminiInlineData { data?: string; mimeType?: string }
interface GeminiAudioPart { inlineData?: GeminiInlineData }
interface GeminiAudioContent { parts?: GeminiAudioPart[] }
interface GeminiAudioCand { content?: GeminiAudioContent }
interface GeminiAudioResp { candidates?: GeminiAudioCand[] }
interface MiniMaxData { audio?: string }
interface MiniMaxResp { data?: MiniMaxData }
interface QwenAudioOutput { audio?: QwenAudioData }
interface QwenAudioData { data?: string; url?: string }
interface QwenTtsResp { output?: QwenAudioOutput }
interface GeminiTtsPart { text: string }
interface GeminiTtsContent { parts: GeminiTtsPart[] }

function stripMarkdownForSpeech(raw: string): string {
  return raw
    .replace(/```[\s\S]*?```/g, ' 代码块已略过。 ')
    .replace(/`([^`]+)`/g, '$1')
    .replace(/!\[[^\]]*\]\([^)]+\)/g, '')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/[#>*_~|]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function buildCloudTtsRequest(cfg: TtsConfig, apiKey: string, text: string): CloudTtsPayload {
  const voice = cfg.voice.trim() || 'alloy';
  const speed = Math.max(0.5, Math.min(2.0, cfg.speed || 1.0));
  const model = cfg.model.trim() || 'tts-1';

  if (cfg.engine === 'openai' || cfg.engine === 'groq' || cfg.engine === 'xai' || cfg.engine === 'mimo' || cfg.engine === 'stepfun') {
    let defaultUrl = 'https://api.openai.com/v1/audio/speech';
    if (cfg.engine === 'groq') defaultUrl = 'https://api.groq.com/openai/v1/audio/speech';
    else if (cfg.engine === 'xai') defaultUrl = 'https://api.x.ai/v1/audio/speech';
    else if (cfg.engine === 'mimo') defaultUrl = 'https://api.xiaomimimo.com/v1/audio/speech';
    else if (cfg.engine === 'stepfun') defaultUrl = 'https://api.stepfun.com/v1/audio/speech';
    const url = cfg.endpoint.trim() ? checkEndpoint(cfg.endpoint) + '/audio/speech' : defaultUrl;
    return {
      url,
      headers: { 'Authorization': 'Bearer ' + apiKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model, input: text, voice, speed, response_format: 'mp3' })
    };
  }
  if (cfg.engine === 'azure') {
    const region = (cfg.region || 'eastasia').trim();
    const url = cfg.endpoint.trim() || ('https://' + region + '.tts.speech.microsoft.com/cognitiveservices/v1');
    const ssml = '<speak version="1.0" xml:lang="' + (cfg.language || 'zh-CN') + '"><voice name="' + voice + '">' +
      text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;') + '</voice></speak>';
    return {
      url,
      headers: {
        'Ocp-Apim-Subscription-Key': apiKey,
        'Content-Type': 'application/ssml+xml',
        'X-Microsoft-OutputFormat': 'audio-24khz-48kbitrate-mono-mp3'
      },
      body: ssml
    };
  }
  if (cfg.engine === 'elevenlabs') {
    const url = (cfg.endpoint.trim() || 'https://api.elevenlabs.io/v1') + '/text-to-speech/' + encodeURIComponent(voice);
    return {
      url,
      headers: { 'xi-api-key': apiKey, 'Content-Type': 'application/json', 'Accept': 'audio/mpeg' },
      body: JSON.stringify({ text, model_id: model || 'eleven_multilingual_v2' })
    };
  }
  if (cfg.engine === 'fishaudio') {
    const url = cfg.endpoint.trim() || 'https://api.fish.audio/v1/tts';
    return {
      url,
      headers: { 'Authorization': 'Bearer ' + apiKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({ text, reference_id: voice, format: 'mp3' })
    };
  }
  if (cfg.engine === 'minimax') {
    const url = cfg.endpoint.trim() || 'https://api.minimax.chat/v1/t2a_v2';
    const bodyObj: Record<string, Object> = {};
    bodyObj['model'] = model || 'speech-02-turbo';
    bodyObj['text'] = text;
    const vs: Record<string, Object> = {};
    vs['voice_id'] = voice || 'male-qn-qingse';
    vs['speed'] = speed;
    bodyObj['voice_setting'] = vs;
    return {
      url,
      headers: { 'Authorization': 'Bearer ' + apiKey, 'Content-Type': 'application/json' },
      body: JSON.stringify(bodyObj),
      isJsonAudio: true
    };
  }
  if (cfg.engine === 'qwen') {
    const url = cfg.endpoint.trim() || 'https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation';
    const bodyObj: Record<string, Object> = {};
    bodyObj['model'] = model || 'qwen-tts';
    const inp: Record<string, Object> = {};
    inp['text'] = text;
    inp['voice'] = voice || 'Cherry';
    bodyObj['input'] = inp;
    return {
      url,
      headers: { 'Authorization': 'Bearer ' + apiKey, 'Content-Type': 'application/json' },
      body: JSON.stringify(bodyObj),
      isJsonAudio: true
    };
  }
  // gemini TTS
  const gemBase = cfg.endpoint.trim() ? checkEndpoint(cfg.endpoint) : 'https://generativelanguage.googleapis.com/v1beta';
  const gemModel = encodeURIComponent(model || 'gemini-2.5-flash-preview-tts');
  const gemBody: Record<string, Object> = {};
  const gemContents: GeminiTtsContent[] = [{ parts: [{ text }] }];
  gemBody['contents'] = gemContents;
  const gCfg: Record<string, Object> = {};
  gCfg['responseModalities'] = ['AUDIO'];
  gemBody['generationConfig'] = gCfg;
  return {
    url: gemBase + '/models/' + gemModel + ':generateContent',
    headers: { 'x-goog-api-key': apiKey, 'Content-Type': 'application/json' },
    body: JSON.stringify(gemBody),
    isJsonAudio: true
  };
}

export class Narration {
  private engine?: textToSpeech.TextToSpeechEngine;
  private player?: media.AVPlayer;
  private openFd?: fs.File;
  private sequence: number = 0;
  private paused: boolean = false;

  isPaused(): boolean { return this.paused; }

  stop(): void {
    this.sequence++;
    this.paused = false;
    const engine = this.engine;
    this.engine = undefined;
    if (engine) {
      try { engine.stop(); } catch (_) {}
      try { engine.shutdown(); } catch (_) {}
    }
    const p = this.player;
    this.player = undefined;
    if (p) {
      p.stop().catch(() => {});
      p.release().catch(() => {});
    }
    if (this.openFd) {
      fs.close(this.openFd).catch(() => {});
      this.openFd = undefined;
    }
  }

  async togglePause(): Promise<boolean> {
    if (!this.player) return false;
    if (this.paused) {
      await this.player.play();
      this.paused = false;
    } else {
      await this.player.pause();
      this.paused = true;
    }
    return this.paused;
  }

  async play(text: string, ended: (message: string) => void): Promise<void> {
    await this.playSystem(text, 'zh-CN', 1.0, ended);
  }

  async playWithConfig(
    text: string,
    config: TtsConfig,
    apiKey: string,
    cacheDir: string,
    ended: (message: string) => void
  ): Promise<void> {
    const cleanText = stripMarkdownForSpeech(text);
    if (!cleanText) {
      ended('没有可朗读的文本内容');
      return;
    }
    if (config.engine === 'system' || !apiKey.trim()) {
      await this.playSystem(cleanText, config.language || 'zh-CN', config.speed || 1.0, ended);
      return;
    }
    await this.playCloud(cleanText, config, apiKey, cacheDir, ended);
  }

  private async playSystem(
    text: string,
    language: string,
    speed: number,
    ended: (message: string) => void
  ): Promise<void> {
    this.stop();
    const token = this.sequence;
    const lang = language === 'en-US' ? 'en-US' : 'zh-CN';
    const person = lang === 'en-US' ? 8 : 13;
    const engine = await textToSpeech.createEngine({ language: lang, person, online: 1 });
    if (token !== this.sequence) { engine.shutdown(); return; }
    this.engine = engine;
    let offset = 0;
    const finish = (message: string): void => {
      if (token !== this.sequence) return;
      this.sequence++;
      this.engine = undefined;
      try { engine.shutdown(); } catch (_) {}
      ended(message);
    };
    const next = (): void => {
      if (offset >= text.length) { finish(''); return; }
      const part = text.slice(offset, offset + 3500);
      offset += part.length;
      const extra: Record<string, Object> = {};
      extra['speed'] = Math.max(0.5, Math.min(2.0, speed));
      try { engine.speak(part, { requestId: token + '-' + offset, extraParams: extra }); }
      catch (_) { finish('系统朗读失败，请检查离线语音资源'); }
    };
    engine.setListener({
      onStart: () => {},
      onStop: () => {},
      onComplete: (_id: string, result: textToSpeech.CompleteResponse) => {
        if (token === this.sequence && result.type === 1) next();
      },
      onError: () => finish('系统朗读失败，请检查离线语音资源')
    });
    next();
  }

  private async playCloud(
    text: string,
    config: TtsConfig,
    apiKey: string,
    cacheDir: string,
    ended: (message: string) => void
  ): Promise<void> {
    this.stop();
    const token = this.sequence;
    const reqSpec = buildCloudTtsRequest(config, apiKey, text.slice(0, 4000));
    const req = http.createHttp();
    try {
      const resp = await req.request(reqSpec.url, {
        method: http.RequestMethod.POST,
        header: reqSpec.headers,
        extraData: reqSpec.body,
        expectDataType: reqSpec.isJsonAudio ? http.HttpDataType.STRING : http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 45000,
        usingCache: false
      });
      if (token !== this.sequence) return;
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error('云端 TTS 返回 HTTP ' + resp.responseCode);
      }

      let audioBytes: Uint8Array;
      if (reqSpec.isJsonAudio) {
        const raw = resp.result as string;
        if (config.engine === 'gemini') {
          const g = JSON.parse(raw) as GeminiAudioResp;
          const b64 = g.candidates?.[0]?.content?.parts?.[0]?.inlineData?.data || '';
          if (!b64) throw new Error('Gemini 未返回音频数据');
          audioBytes = new util.Base64Helper().decodeSync(b64);
        } else if (config.engine === 'minimax') {
          const m = JSON.parse(raw) as MiniMaxResp;
          const hex = m.data?.audio || '';
          if (!hex) throw new Error('MiniMax 未返回音频数据');
          audioBytes = new Uint8Array(Math.floor(hex.length / 2));
          for (let i = 0; i < audioBytes.length; i++) {
            audioBytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
          }
        } else {
          const q = JSON.parse(raw) as QwenTtsResp;
          const b64 = q.output?.audio?.data || '';
          if (!b64) throw new Error('Qwen TTS 未返回音频数据');
          audioBytes = new util.Base64Helper().decodeSync(b64);
        }
      } else {
        audioBytes = new Uint8Array(resp.result as ArrayBuffer);
      }

      const clipPath = cacheDir + '/tts_playback_' + token + '.mp3';
      const outFile = await fs.open(clipPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        await fs.write(outFile.fd, audioBytes.buffer);
      } finally {
        await fs.close(outFile);
      }

      if (token !== this.sequence) return;
      const playFd = await fs.open(clipPath, fs.OpenMode.READ_ONLY);
      this.openFd = playFd;
      const size = (await fs.stat(playFd.fd)).size;
      const player = await media.createAVPlayer();
      this.player = player;
      player.on('stateChange', (state: string) => {
        if (token !== this.sequence) return;
        if (state === 'initialized') {
          player.prepare().catch(() => {});
        } else if (state === 'prepared') {
          player.play().catch(() => {});
        } else if (state === 'completed' || state === 'error') {
          this.stop();
          ended(state === 'error' ? '音频播放失败' : '');
        }
      });
      player.fdSrc = { fd: playFd.fd, offset: 0, length: size };
    } catch (e) {
      if (token === this.sequence) {
        this.stop();
        ended((e as Error).message || '云端朗读失败');
      }
    } finally {
      req.destroy();
    }
  }
}
