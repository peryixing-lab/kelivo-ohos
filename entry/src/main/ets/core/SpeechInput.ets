import { speechRecognizer } from '@kit.CoreSpeechKit';
import { audio } from '@kit.AudioKit';
import { abilityAccessCtrl, bundleManager, common, Permissions } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { AsrConfig, checkEndpoint } from './Models';

interface OpenAiAsrResp { text?: string; error?: AsrErrorDetail }
interface AsrErrorDetail { message?: string }

export async function ensurePermissionGranted(
  context: common.UIAbilityContext,
  permission: Permissions
): Promise<boolean> {
  const at = abilityAccessCtrl.createAtManager();
  try {
    const bundleInfo = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    const tokenId = bundleInfo.appInfo.accessTokenId;
    const status = at.checkAccessTokenSync(tokenId, permission);
    if (status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) return true;
  } catch (_) {}
  try {
    const res = await at.requestPermissionsFromUser(context, [permission]);
    return res.authResults.length > 0 && res.authResults[0] === 0;
  } catch (_) {
    return false;
  }
}

export class SpeechInputController {
  private engine?: speechRecognizer.SpeechRecognitionEngine;
  private capturer?: audio.AudioCapturer;
  private sessionId: string = '';
  private active: boolean = false;
  private pcmBuffer: Uint8Array = new Uint8Array(0);

  isRecording(): boolean { return this.active; }

  async startSystemDictation(
    context: common.UIAbilityContext,
    language: string,
    onResult: (text: string, isFinal: boolean) => void,
    onError: (msg: string) => void
  ): Promise<void> {
    if (this.active) return;
    const ok = await ensurePermissionGranted(context, 'ohos.permission.MICROPHONE');
    if (!ok) {
      throw new Error('未获得麦克风权限，请在系统设置中授权');
    }
    this.active = true;
    this.sessionId = 'kelivo-' + Date.now();
    this.pcmBuffer = new Uint8Array(0);

    const recExtra: Record<string, Object> = {};
    recExtra['locate'] = 'CN';
    recExtra['recognizerMode'] = 'long';
    const engine = await speechRecognizer.createEngine({
      language: language === 'en-US' ? 'zh-CN' : 'zh-CN',
      online: 1,
      extraParams: recExtra
    });
    this.engine = engine;

    engine.setListener({
      onStart: (_sid: string, _msg: string) => {},
      onEvent: (_sid: string, _code: number, _msg: string) => {},
      onResult: (_sid: string, res: speechRecognizer.SpeechRecognitionResult) => {
        if (res.result) onResult(res.result, res.isFinal);
      },
      onComplete: (_sid: string, _msg: string) => {},
      onError: (_sid: string, _code: number, errMsg: string) => {
        onError(errMsg || '语音识别异常');
      }
    });

    engine.startListening({
      sessionId: this.sessionId,
      audioInfo: {
        audioType: 'pcm',
        sampleRate: 16000,
        soundChannel: 1,
        sampleBit: 16
      }
    });

    const capturer = await audio.createAudioCapturer({
      streamInfo: {
        samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
        channels: audio.AudioChannel.CHANNEL_1,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
      },
      capturerInfo: {
        source: audio.SourceType.SOURCE_TYPE_MIC,
        capturerFlags: 0
      }
    });
    this.capturer = capturer;

    capturer.on('readData', (buf: ArrayBuffer) => {
      if (!this.active || !this.engine) return;
      const chunk = new Uint8Array(buf);
      const merged = new Uint8Array(this.pcmBuffer.length + chunk.length);
      merged.set(this.pcmBuffer, 0);
      merged.set(chunk, this.pcmBuffer.length);
      let offset = 0;
      while (offset + 1280 <= merged.length) {
        try {
          this.engine.writeAudio(this.sessionId, merged.subarray(offset, offset + 1280));
        } catch (_) {}
        offset += 1280;
      }
      this.pcmBuffer = merged.slice(offset);
    });

    await capturer.start();
  }

  async stopSystemDictation(): Promise<void> {
    if (!this.active) return;
    this.active = false;
    const cap = this.capturer;
    this.capturer = undefined;
    if (cap) {
      try { await cap.stop(); } catch (_) {}
      try { await cap.release(); } catch (_) {}
    }
    const eng = this.engine;
    this.engine = undefined;
    if (eng) {
      try {
        if (this.pcmBuffer.length > 0 && this.pcmBuffer.length <= 1280) {
          const padded = new Uint8Array(1280);
          padded.set(this.pcmBuffer, 0);
          eng.writeAudio(this.sessionId, padded);
        }
        eng.finish(this.sessionId);
      } catch (_) {}
      try { eng.shutdown(); } catch (_) {}
    }
    this.pcmBuffer = new Uint8Array(0);
  }
}

export async function transcribeAudioCloud(
  cfg: AsrConfig,
  apiKey: string,
  fileName: string,
  audioBytes: Uint8Array
): Promise<string> {
  if (!apiKey.trim()) throw new Error('请先配置云端语音识别 API 密钥');
  let url = cfg.endpoint.trim();
  if (!url) {
    if (cfg.engine === 'groq') url = 'https://api.groq.com/openai/v1/audio/transcriptions';
    else if (cfg.engine === 'mimo') url = 'https://api.xiaomimimo.com/v1/audio/transcriptions';
    else if (cfg.engine === 'stepfun') url = 'https://api.stepfun.com/v1/audio/transcriptions';
    else if (cfg.engine === 'dashscope') url = 'https://dashscope.aliyuncs.com/compatible-mode/v1/audio/transcriptions';
    else if (cfg.engine === 'volcengine') url = 'https://openspeech.bytedance.com/api/v1/asr';
    else url = 'https://api.openai.com/v1/audio/transcriptions';
  } else {
    url = checkEndpoint(url);
    if (!url.endsWith('/transcriptions')) url += '/audio/transcriptions';
  }

  const boundary = '----KelivoBoundary' + Date.now();
  const encoder = util.TextEncoder.create();
  const headStr =
    '--' + boundary + '\r\n' +
    'Content-Disposition: form-data; name="model"\r\n\r\n' +
    (cfg.model || 'whisper-1') + '\r\n' +
    '--' + boundary + '\r\n' +
    'Content-Disposition: form-data; name="file"; filename="' + fileName.replace(/"/g, '_') + '"\r\n' +
    'Content-Type: application/octet-stream\r\n\r\n';
  const tailStr = '\r\n--' + boundary + '--\r\n';
  const headBytes = encoder.encodeInto(headStr);
  const tailBytes = encoder.encodeInto(tailStr);
  const bodyBytes = new Uint8Array(headBytes.length + audioBytes.length + tailBytes.length);
  bodyBytes.set(headBytes, 0);
  bodyBytes.set(audioBytes, headBytes.length);
  bodyBytes.set(tailBytes, headBytes.length + audioBytes.length);

  const req = http.createHttp();
  try {
    const resp = await req.request(url, {
      method: http.RequestMethod.POST,
      header: {
        'Authorization': 'Bearer ' + apiKey.trim(),
        'Content-Type': 'multipart/form-data; boundary=' + boundary
      },
      extraData: bodyBytes.buffer,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 60000,
      usingCache: false
    });
    const raw = resp.result as string;
    if (resp.responseCode < 200 || resp.responseCode >= 300) {
      throw new Error('云端 ASR 返回 HTTP ' + resp.responseCode + ': ' + raw.slice(0, 200));
    }
    const parsed = JSON.parse(raw) as OpenAiAsrResp;
    if (parsed.error?.message) throw new Error(parsed.error.message);
    return (parsed.text || '').trim();
  } finally {
    req.destroy();
  }
}
