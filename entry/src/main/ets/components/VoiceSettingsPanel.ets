import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { AsrConfig, AsrEngineKind, TtsConfig, TtsEngineKind } from '../core/Models';
import { forgetKey, newId, storeKey } from '../core/Storage';

const TTS_ENGINES: string[] = [
  'system', 'openai', 'gemini', 'azure', 'elevenlabs', 'minimax',
  'qwen', 'groq', 'xai', 'mimo', 'stepfun', 'fishaudio'
];

const ASR_ENGINES: string[] = [
  'system', 'openai', 'groq', 'dashscope', 'volcengine', 'mimo', 'stepfun'
];

@Component
export struct VoiceSettingsPanel {
  @Prop tts: TtsConfig = {
    engine: 'system', endpoint: '', secretRef: '', model: 'tts-1', voice: 'alloy', speed: 1.0, language: 'zh-CN'
  };
  @Prop asr: AsrConfig = {
    engine: 'system', endpoint: '', secretRef: '', model: 'whisper-1', language: 'zh-CN'
  };
  @Prop embeddedInNav: boolean = false;
  onSave: (tts: TtsConfig, asr: AsrConfig) => void = () => {};
  onClose: () => void = () => {};

  @StorageProp('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
  @StorageProp('windowTopInsetVp') winTopInset: number = 0;

  @State ttsEngine: string = 'system';
  @State ttsEndpoint: string = '';
  @State ttsModel: string = '';
  @State ttsVoice: string = '';
  @State ttsSpeed: number = 1.0;
  @State ttsLang: string = 'zh-CN';
  @State ttsRegion: string = 'eastasia';
  @State ttsKeyInput: string = '';
  @State asrEngine: string = 'system';
  @State asrEndpoint: string = '';
  @State asrModel: string = '';
  @State asrLang: string = 'zh-CN';
  @State asrKeyInput: string = '';
  @State saving: boolean = false;
  @State statusMsg: string = '';

  aboutToAppear(): void {
    this.ttsEngine = this.tts.engine;
    this.ttsEndpoint = this.tts.endpoint;
    this.ttsModel = this.tts.model;
    this.ttsVoice = this.tts.voice;
    this.ttsSpeed = this.tts.speed || 1.0;
    this.ttsLang = this.tts.language || 'zh-CN';
    this.ttsRegion = this.tts.region || 'eastasia';
    this.asrEngine = this.asr.engine;
    this.asrEndpoint = this.asr.endpoint;
    this.asrModel = this.asr.model;
    this.asrLang = this.asr.language || 'zh-CN';
  }

  private ttsOptions(): SelectOption[] {
    return TTS_ENGINES.map((e: string): SelectOption => {
      return { value: e === 'system' ? '系统离线 TTS' : e.toUpperCase() };
    });
  }

  private asrOptions(): SelectOption[] {
    return ASR_ENGINES.map((e: string): SelectOption => {
      return { value: e === 'system' ? '系统离线语音识别' : e.toUpperCase() };
    });
  }

  private async saveAll(): Promise<void> {
    if (this.saving) return;
    this.saving = true;
    try {
      let ttsRef = this.tts.secretRef;
      if (this.ttsKeyInput.trim()) {
        const nextRef = newId();
        await storeKey(nextRef, this.ttsKeyInput.trim());
        if (ttsRef) await forgetKey(ttsRef).catch(() => {});
        ttsRef = nextRef;
      }
      let asrRef = this.asr.secretRef;
      if (this.asrKeyInput.trim()) {
        const nextRef = newId();
        await storeKey(nextRef, this.asrKeyInput.trim());
        if (asrRef) await forgetKey(asrRef).catch(() => {});
        asrRef = nextRef;
      }
      const nextTts: TtsConfig = {
        engine: this.ttsEngine as TtsEngineKind,
        endpoint: this.ttsEndpoint.trim(),
        secretRef: ttsRef,
        model: this.ttsModel.trim() || 'tts-1',
        voice: this.ttsVoice.trim() || 'alloy',
        speed: this.ttsSpeed,
        language: this.ttsLang,
        region: this.ttsRegion.trim()
      };
      const nextAsr: AsrConfig = {
        engine: this.asrEngine as AsrEngineKind,
        endpoint: this.asrEndpoint.trim(),
        secretRef: asrRef,
        model: this.asrModel.trim() || 'whisper-1',
        language: this.asrLang
      };
      this.onSave(nextTts, nextAsr);
      this.onClose();
    } catch (e) {
      this.statusMsg = (e as Error).message || '保存失败';
    } finally {
      this.saving = false;
    }
  }

  build() {
    Column() {
      if (!this.embeddedInNav) {
        Row({ space: 8 }) {
          Button('返回').backgroundColor(Color.Transparent).fontColor($r('app.color.accent'))
            .enabled(!this.saving).onClick(() => this.onClose())
          Text('语音朗读与识别').fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink')).layoutWeight(1)
          Button('保存').height(34).backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
            .enabled(!this.saving).onClick(() => { this.saveAll(); })
        }.width('100%').height(58).padding({ left: 6, right: 14 })
      }

      Scroll() {
        Column({ space: 14 }) {
          Column({ space: 8 }) {
            Text('文本转语音 (TTS)').fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink'))
            Select(this.ttsOptions()).value(this.ttsEngine === 'system' ? '系统离线 TTS' : this.ttsEngine.toUpperCase())
              .onSelect((i: number) => { this.ttsEngine = TTS_ENGINES[i]; })
              .menuSystemMaterial(ImmersiveMaterialStyle.selectMenuMaterial(this.immersiveLightEnabled))
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
            Row({ space: 8 }) {
              Text('语速: ' + this.ttsSpeed.toFixed(2) + 'x').fontSize(13).fontColor($r('app.color.ink')).layoutWeight(1)
              Slider({ value: Math.round(this.ttsSpeed * 10), min: 5, max: 20, step: 1 }).width(160)
                .selectedColor($r('app.color.accent')).onChange((v: number) => { this.ttsSpeed = v / 10; })
                .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
            }.width('100%')
            Row({ space: 8 }) {
              Button('中文 zh-CN').height(30).fontSize(12)
                .backgroundColor(this.ttsLang === 'zh-CN' ? $r('app.color.tint') : $r('app.color.panel'))
                .fontColor(this.ttsLang === 'zh-CN' ? $r('app.color.accent') : $r('app.color.ink'))
                .onClick(() => { this.ttsLang = 'zh-CN'; })
              Button('英文 en-US').height(30).fontSize(12)
                .backgroundColor(this.ttsLang === 'en-US' ? $r('app.color.tint') : $r('app.color.panel'))
                .fontColor(this.ttsLang === 'en-US' ? $r('app.color.accent') : $r('app.color.ink'))
                .onClick(() => { this.ttsLang = 'en-US'; })
            }.width('100%')
            if (this.ttsEngine !== 'system') {
              TextInput({ text: this.ttsEndpoint, placeholder: '自定义接口地址（留空用官方默认）' })
                .onChange((v: string) => { this.ttsEndpoint = v; })
              Row({ space: 8 }) {
                TextInput({ text: this.ttsModel, placeholder: '模型（如 tts-1）' }).layoutWeight(1)
                  .onChange((v: string) => { this.ttsModel = v; })
                TextInput({ text: this.ttsVoice, placeholder: '音色（如 alloy）' }).layoutWeight(1)
                  .onChange((v: string) => { this.ttsVoice = v; })
              }.width('100%')
              if (this.ttsEngine === 'azure') {
                TextInput({ text: this.ttsRegion, placeholder: 'Azure Region（如 eastasia）' })
                  .onChange((v: string) => { this.ttsRegion = v; })
              }
              TextInput({
                text: this.ttsKeyInput,
                placeholder: this.tts.secretRef ? 'TTS 密钥已保存（输入可替换）' : 'TTS API 密钥'
              }).type(InputType.Password).onChange((v: string) => { this.ttsKeyInput = v; })
            }
          }.width('100%').padding(12).borderRadius(12).backgroundColor($r('app.color.surface'))
            .border({ width: 1, color: $r('app.color.line') }).alignItems(HorizontalAlign.Start)

          Column({ space: 8 }) {
            Text('语音识别 (ASR)').fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink'))
            Select(this.asrOptions()).value(this.asrEngine === 'system' ? '系统离线语音识别' : this.asrEngine.toUpperCase())
              .onSelect((i: number) => { this.asrEngine = ASR_ENGINES[i]; })
              .menuSystemMaterial(ImmersiveMaterialStyle.selectMenuMaterial(this.immersiveLightEnabled))
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
            Text('聊天输入栏点击麦克风按钮即可启用实时语音输入；云端引擎用于音频文件转写。')
              .fontSize(12).fontColor($r('app.color.muted'))
            if (this.asrEngine !== 'system') {
              TextInput({ text: this.asrEndpoint, placeholder: '自定义 ASR 接口地址（可选）' })
                .onChange((v: string) => { this.asrEndpoint = v; })
              TextInput({ text: this.asrModel, placeholder: '模型（如 whisper-1）' })
                .onChange((v: string) => { this.asrModel = v; })
              TextInput({
                text: this.asrKeyInput,
                placeholder: this.asr.secretRef ? 'ASR 密钥已保存（输入可替换）' : 'ASR API 密钥'
              }).type(InputType.Password).onChange((v: string) => { this.asrKeyInput = v; })
            }
          }.width('100%').padding(12).borderRadius(12).backgroundColor($r('app.color.surface'))
            .border({ width: 1, color: $r('app.color.line') }).alignItems(HorizontalAlign.Start)

          if (this.statusMsg) {
            Text(this.statusMsg).fontSize(13).fontColor($r('app.color.warning'))
          }

          if (this.embeddedInNav) {
            Button(this.saving ? '保存中…' : '保存语音设置')
              .width('100%').height(42).borderRadius(12)
              .backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
              .enabled(!this.saving).onClick(() => { this.saveAll(); })
          }
        }.padding({ left: 16, right: 16, top: this.embeddedInNav ? (56 + this.winTopInset + 4) : 16, bottom: 48 }).width('100%').constraintSize({ maxWidth: 620 }).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').align(Alignment.Top)
    }.width('100%').height('100%').backgroundColor(Color.Transparent)
  }
}
