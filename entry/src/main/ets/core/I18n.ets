export type AppLanguageCode = 'zh-Hans' | 'zh-Hant' | 'en' | 'ko' | 'ru' | 'tr';

export interface LanguageOption {
  code: AppLanguageCode;
  label: string;
}

export const SUPPORTED_LANGUAGES: LanguageOption[] = [
  { code: 'zh-Hans', label: '简体中文' },
  { code: 'zh-Hant', label: '繁體中文' },
  { code: 'en', label: 'English' },
  { code: 'ko', label: '한국어' },
  { code: 'ru', label: 'Русский' },
  { code: 'tr', label: 'Türkçe' }
];

export interface UiStrings {
  appTitle: string;
  newChat: string;
  ephemeralChat: string;
  searchHint: string;
  inputPlaceholder: string;
  send: string;
  stop: string;
  thinkingLabel: string;
  settings: string;
  providers: string;
  assistants: string;
  memoryCenter: string;
  promptTools: string;
  translateTool: string;
  statsCenter: string;
  diagnostics: string;
  appearance: string;
  webSearch: string;
  mcpTools: string;
  voiceSettings: string;
  backupSync: string;
  skills: string;
  workspace: string;
  browser: string;
  scheduledTasks: string;
  close: string;
  noConversations: string;
  emptyHeroTitle: string;
  emptyHeroSubtitle: string;
}

const STRINGS_ZH_HANS: UiStrings = {
  appTitle: 'Kelivo',
  newChat: '新对话',
  ephemeralChat: '无痕对话',
  searchHint: '搜索对话标题或正文...',
  inputPlaceholder: '输入消息、@ 切换助手、支持多附件与工具调用...',
  send: '发送',
  stop: '停止',
  thinkingLabel: '深度思考',
  settings: '设置',
  providers: '模型与服务商',
  assistants: '助手与角色',
  memoryCenter: '长期记忆',
  promptTools: '世界书与指令卡',
  translateTool: '双语翻译',
  statsCenter: '用量统计',
  diagnostics: '诊断与存储',
  appearance: '外观与语言',
  webSearch: '联网搜索',
  mcpTools: '工具与 MCP',
  voiceSettings: '语音 TTS/ASR',
  backupSync: '备份与同步',
  skills: 'Agent Skills',
  workspace: '本地工作区',
  browser: '内置浏览器',
  scheduledTasks: '定时任务',
  close: '关闭',
  noConversations: '暂无历史对话',
  emptyHeroTitle: '开始一段新的智能对话',
  emptyHeroSubtitle: '支持多服务商、MCP 工具、长期记忆、世界书、Artifacts 与语音交互'
};

const STRINGS_ZH_HANT: UiStrings = {
  appTitle: 'Kelivo',
  newChat: '新對話',
  ephemeralChat: '無痕對話',
  searchHint: '搜尋對話標題或內文...',
  inputPlaceholder: '輸入訊息、支援多附件與工具呼叫...',
  send: '傳送',
  stop: '停止',
  thinkingLabel: '深度思考',
  settings: '設定',
  providers: '模型與供應商',
  assistants: '助手與角色',
  memoryCenter: '長期記憶',
  promptTools: '世界書與指令卡',
  translateTool: '雙語翻譯',
  statsCenter: '用量統計',
  diagnostics: '診斷與儲存',
  appearance: '外觀與語言',
  webSearch: '網路搜尋',
  mcpTools: '工具與 MCP',
  voiceSettings: '語音 TTS/ASR',
  backupSync: '備份與同步',
  skills: 'Agent Skills',
  workspace: '本機工作區',
  browser: '內建瀏覽器',
  scheduledTasks: '排程任務',
  close: '關閉',
  noConversations: '暫無歷史對話',
  emptyHeroTitle: '開始一段新的智慧對話',
  emptyHeroSubtitle: '支援多供應商、MCP 工具、長期記憶、世界書與語音互動'
};

const STRINGS_EN: UiStrings = {
  appTitle: 'Kelivo',
  newChat: 'New Chat',
  ephemeralChat: 'Incognito',
  searchHint: 'Search chats & messages...',
  inputPlaceholder: 'Message AI, attach files, or invoke tools...',
  send: 'Send',
  stop: 'Stop',
  thinkingLabel: 'Reasoning',
  settings: 'Settings',
  providers: 'Providers & Models',
  assistants: 'Assistants',
  memoryCenter: 'Long-term Memory',
  promptTools: 'WorldBook & Cards',
  translateTool: 'Translator',
  statsCenter: 'Usage Stats',
  diagnostics: 'Diagnostics',
  appearance: 'Appearance',
  webSearch: 'Web Search',
  mcpTools: 'Tools & MCP',
  voiceSettings: 'Voice TTS/ASR',
  backupSync: 'Backup & Sync',
  skills: 'Agent Skills',
  workspace: 'Workspace',
  browser: 'Browser',
  scheduledTasks: 'Schedules',
  close: 'Close',
  noConversations: 'No conversations yet',
  emptyHeroTitle: 'Start a new conversation',
  emptyHeroSubtitle: 'Multi-provider LLM client with MCP tools, memory, WorldBook & Artifacts'
};

const STRINGS_KO: UiStrings = {
  appTitle: 'Kelivo',
  newChat: '새 대화',
  ephemeralChat: '시크릿 대화',
  searchHint: '대화 및 메시지 검색...',
  inputPlaceholder: '메시지 입력, 첨부 및 도구 호출...',
  send: '전송',
  stop: '중지',
  thinkingLabel: '추론',
  settings: '설정',
  providers: '제공자 및 모델',
  assistants: '어시스턴트',
  memoryCenter: '장기 기억',
  promptTools: '월드북 및 카드',
  translateTool: '번역기',
  statsCenter: '사용량 통계',
  diagnostics: '진단 및 저장소',
  appearance: '테마 및 언어',
  webSearch: '웹 검색',
  mcpTools: '도구 및 MCP',
  voiceSettings: '음성 TTS/ASR',
  backupSync: '백업 및 동기화',
  skills: 'Agent Skills',
  workspace: '로컬 작업공간',
  browser: '내장 브라우저',
  scheduledTasks: '예약 작업',
  close: '닫기',
  noConversations: '대화 내역이 없습니다',
  emptyHeroTitle: '새로운 대화를 시작하세요',
  emptyHeroSubtitle: '다중 모델, MCP 도구, 장기 기억, 월드북 및 아티팩트 지원'
};

const STRINGS_RU: UiStrings = {
  appTitle: 'Kelivo',
  newChat: 'Новый чат',
  ephemeralChat: 'Инкогнито',
  searchHint: 'Поиск по чатам...',
  inputPlaceholder: 'Введите сообщение или вызовите инструмент...',
  send: 'Отправить',
  stop: 'Стоп',
  thinkingLabel: 'Размышление',
  settings: 'Настройки',
  providers: 'Провайдеры',
  assistants: 'Ассистенты',
  memoryCenter: 'Долгая память',
  promptTools: 'Миры и карточки',
  translateTool: 'Переводчик',
  statsCenter: 'Статистика',
  diagnostics: 'Диагностика',
  appearance: 'Внешний вид',
  webSearch: 'Веб-поиск',
  mcpTools: 'Инструменты MCP',
  voiceSettings: 'Голос TTS/ASR',
  backupSync: 'Бэкап и Sync',
  skills: 'Agent Skills',
  workspace: 'Рабочая папка',
  browser: 'Браузер',
  scheduledTasks: 'Расписание',
  close: 'Закрыть',
  noConversations: 'История чатов пуста',
  emptyHeroTitle: 'Начните новый диалог',
  emptyHeroSubtitle: 'Мульти-провайдеры, MCP, долгая память, WorldBook и артефакты'
};

const STRINGS_TR: UiStrings = {
  appTitle: 'Kelivo',
  newChat: 'Yeni Sohbet',
  ephemeralChat: 'Gizli',
  searchHint: 'Sohbetlerde ara...',
  inputPlaceholder: 'Mesaj yazın, dosya ekleyin veya araç kullanın...',
  send: 'Gönder',
  stop: 'Durdur',
  thinkingLabel: 'Düşünme',
  settings: 'Ayarlar',
  providers: 'Sağlayıcılar',
  assistants: 'Asistanlar',
  memoryCenter: 'Uzun Süreli Bellek',
  promptTools: 'WorldBook ve Kartlar',
  translateTool: 'Çevirmen',
  statsCenter: 'Kullanım İstatistikleri',
  diagnostics: 'Tanılama',
  appearance: 'Görünüm ve Dil',
  webSearch: 'Web Arama',
  mcpTools: 'Araçlar ve MCP',
  voiceSettings: 'Ses TTS/ASR',
  backupSync: 'Yedekleme',
  skills: 'Agent Skills',
  workspace: 'Çalışma Alanı',
  browser: 'Tarayıcı',
  scheduledTasks: 'Zamanlanmış Görevler',
  close: 'Kapat',
  noConversations: 'Henüz sohbet yok',
  emptyHeroTitle: 'Yeni bir sohbet başlatın',
  emptyHeroSubtitle: 'Çoklu sağlayıcı, MCP araçları, bellek, WorldBook ve Artifacts'
};

export function normalizeLanguageCode(lang?: string): AppLanguageCode {
  if (lang === 'zh-Hant' || lang === 'en' || lang === 'ko' || lang === 'ru' || lang === 'tr') {
    return lang;
  }
  return 'zh-Hans';
}

export function getUiStrings(lang?: string): UiStrings {
  const code = normalizeLanguageCode(lang);
  if (code === 'zh-Hant') {
    return STRINGS_ZH_HANT;
  }
  if (code === 'en') {
    return STRINGS_EN;
  }
  if (code === 'ko') {
    return STRINGS_KO;
  }
  if (code === 'ru') {
    return STRINGS_RU;
  }
  if (code === 'tr') {
    return STRINGS_TR;
  }
  return STRINGS_ZH_HANS;
}

export function tr(lang: string | undefined, key: string): string {
  const s = getUiStrings(lang);
  if (key === 'newChat') {
    return s.newChat;
  }
  if (key === 'send') {
    return s.send;
  }
  if (key === 'stop') {
    return s.stop;
  }
  if (key === 'settings') {
    return s.settings;
  }
  if (key === 'close') {
    return s.close;
  }
  if (key === 'emptyHeroTitle') {
    return s.emptyHeroTitle;
  }
  if (key === 'appearance') {
    return s.appearance;
  }
  return s.appTitle;
}
