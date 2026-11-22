# Kelivo 鸿蒙原生版

Kelivo 是基于 HarmonyOS NEXT（ArkTS、ArkUI 与 Stage 模型）打造的原生多模型 AI 对话、Agent 工具与自动化工作台客户端。工程包名沿用 `com.lovexjy.lexikelivo`，交互体验、协议能力与生态格式全面对齐上游 [Chevey339/kelivo](https://github.com/Chevey339/kelivo)，针对鸿蒙手机与平板形态（宽屏三栏分栏、系统安全沙箱、Asset Store、RelationalStore SQLite、ArkWeb 等）进行了原生重构与适配。

## 核心特性总览

### 1. 多协议模型服务与订阅认证
- **全协议族支持**：OpenAI Chat Completions、OpenAI Responses API (`/responses`)、Anthropic Messages（含 Prompt Caching）、Google Gemini、Vertex AI（含生图模式 `generateImages`）。
- **多模型与多密钥池**：单服务商多模型管理（视觉/工具/推理/生图能力标注与自动识别）、Ollama 本地能力探测；多 API Key 轮询池（轮询 / 优先级 / 最少使用 / 随机 + 429 自动冷却退避）。
- **企业网络与自定义**：HTTP Proxy 代理配置、自定义请求头 / Body JSON、自动指数退避重试、API 余额查询、服务商 `ai-provider:v1:` 二维码扫码/生成。
- **订阅 OAuth 登录（PKCE S256）**：内置 ArkWeb 回调拦截与手动授权码/Token 绑定，支持 ChatGPT、Claude、Grok、Kimi 订阅账号一键创建服务商。

### 2. 对话工作台与富交互渲染
- **SQLite 持久化架构**：基于 `@kit.ArkData` `relationalStore` 存储会话、消息、HTTP 请求日志、上下文发送快照及每日 Token 统计，首次启动自动迁移旧版 JSON 数据；敏感密钥全程托管于 `@kit.AssetStoreKit`。
- **完整 Markdown + GenUI 引擎**：支持 H1–H6、GFM 表格、任务列表、代码语法高亮与一键复制、块级/行内数学公式，以及上游特色 **`kelivo-ui` 原生可交互组件渲染（卡片、指标、进度条、柱状图、状态按钮）**。
- **Artifacts 与网页预览**：内置 ArkWeb Rich Preview 支持 HTML、SVG、Mermaid、PlantUML、LaTeX 与 `*.app.html` 持久化应用桥接（`kelivo.readJson` / `saveJson`）。
- **高级消息操作**：多版本重新生成与 `< ›` 切换、行内/全文编辑、消息引用回复、会话分支（Fork）、单条/多选导出（Markdown/纯文本）、无痕对话（Ephemeral）、对话内搜索、大纲 Mini-map、AI 自动命名与猜你想问建议、PDF/DOCX/图片/音频/代码多附件及图片 OCR。
- **上下文工程**：上下文环形预算监控、就地摘要压缩、撤销压缩、压缩派生新对话，以及分角色默认模型（对话/命名/翻译/OCR/记忆）。

### 3. 联网搜索、MCP 与设备生态工具
- **26 种搜索引擎适配器**：免密钥引擎（DuckDuckGo、Bing HTML 等）及商业/自建引擎（Tavily、SearXNG、Exa、Brave、Perplexity 等），支持多 Key 轮询、`pre_search` 预搜索与 `agent_tool` 模型自主调用模式切换，配合 `web_fetch` 抓取正文。
- **多 MCP 服务商中心**：同时托管多个 Streamable HTTP 与 Legacy SSE 服务器，兼容 `mcpServers` JSON 导入，内置 `kelivo_fetch_url`，支持单工具启停、免审批开关与 Agent 多轮工具调用循环（含 Unified Diff 预览、内联审批卡片、完全访问模式）。
- **本地沙箱工作区（Sandbox Workspaces）**：在应用沙箱 `filesDir/workspaces/` 下建立隔离工作区，支持本地文件导入与浏览/编辑，向模型开放 `read_file`、`write_file`、`edit_file`（返回 Unified Diff）、`list_dir`、`glob`、`grep`、`view_image`，并在输出中自动脱敏环境变量密钥（`***`）。
- **Agent Skills 技能包**：内置 `visualize`（`kelivo-ui`）与 `skill-creator`，支持从 GitHub 仓库/链接、`SKILL.md` 与 ZIP 压缩包导入技能，通过渐进式披露按需调用 `read_skill`。
- **多标签内置浏览器 + 平板三栏分栏**：最多同时保持 8 个 live `Web` 标签页与书签管理，支持 `kelivo://workspace/...` 本地预览及 **19 个浏览器控制动作**（`open` / `render` / `extract` / `snapshot` / `click` / `type` / `select_option` / `press` / `scroll` / `wait` / `evaluate` 等）；960vp 及以上平板宽屏可开启三栏（历史 + 对话 + 浏览器/工作区）工作台。
- **设备与交互工具**：`get_time_info`、`calculate`（无 `eval()` 安全递归下降数学求值器）、`clipboard_tool`、`text_to_speech`、`read_chat_context`、交互式卡片挂起提问 `ask_user_input`、授权后访问系统日历（`calendar_query` / `calendar_create`）与位置（`get_current_location`）。

### 4. 记忆、提示词工程、语音、同步与个性化
- **长期记忆中心**：对话后门控自动提炼身份/工作流/语气/指令与用户画像、相似度去重合并、缓存友好系统块注入，并向模型提供 `memory_search` / `memory_save` / `memory_delete` 工具。
- **高级助手与角色工程**：4 标签页助手编辑器（头像、标签、专属模型、背景色调、模板变量 `{{date}}` / `{{user_name}}` 等、Few-shot 预设消息、专属 MCP/Skill/世界书/工作区绑定、正则 `input/output/display` 规则、快捷短语），以及 SillyTavern/Kelivo 世界书 JSON 导入导出和指令注入卡片（含苏格拉底学习模式）。
- **语音 TTS / ASR**：系统离线朗读 + 11 种云端 TTS 播放器（悬浮控制栏）+ 原生实时麦克风听写与云端语音转文字。
- **全量同步、备份与第三方迁移**：WebDAV 与 S3（AWS SigV4）云备份、AES-256-GCM + PBKDF2-SHA256 加密、范围勾选备份、本地快照（恢复前自动安全快照），以及 Flutter Kelivo 全版本 / Cherry Studio / Chatbox 导入器。
- **统计、诊断、定时任务与系统集成**：91 天 Token 热力图、14 天分布柱状图、模型/助手排行；HTTP 与上下文抓包日志、沙箱空间分析清理、工具 Schema 描述覆写；自动化定时任务与启动补运行；双语翻译面板；6 套双模调色盘、气泡质感、壁纸、字体缩放与 **6 国语言（简中/繁中/English/한국어/Русский/Türkçe）**；震动反馈、屏幕常亮、完成通知与系统分享文本接收入口。

## 鸿蒙沙箱安全与权限说明

受 HarmonyOS NEXT 安全机制限制，应用不直接访问主机任意终端 Shell 或根目录文件系统：
1. 代码与文件工作区严格限制于应用内部沙箱目录（`filesDir/workspaces/<id>/`），并通过路径规范化拦截越界访问。
2. 涉及敏感硬件或隐私的权限（麦克风、日历读写、精确定位、通知）均仅在用户主动开启对应功能或模型调用对应工具触发运行时授权对话框时申请，并可在系统设置中随时撤回。

### 5. HarmonyOS 沉浸光感与全屏窗口适配
- **全局光感材质方案 (`ohos.arkui.UIMaterial.state = "enable"`)**：主对话页通过 `WithTheme` + `Navigation` (`BarStyle.STACK` + `ScrollEffectType.GRADUAL_BLUR`) 实现标题栏与对话列表的纵向渐进模糊融合；顶部标题栏圆形按键使用 `ButtonType.Circle` + `ButtonStyleMode.TEXTUAL` + `ImmersiveMaterial` (`ULTRA_THIN` / `colorInvert`)，仅附着在 `Navigation` 标题栏、弹出菜单 (`bindMenu`)、`promptAction.showToast`、`bindSheet`（互斥分支切换系统材质或 API < 26 降级模糊）及 `Toggle`/`Slider` 控件等官方支持作用域，避免越界失效。
- **全屏沉浸窗口与多形态避让 (`WindowController`)**：在 `EntryAbility` 窗口加载后启用 `setWindowLayoutFullScreen(true)`，统一计算系统栏、手势导航条、屏幕挖孔（横竖屏/双挖孔）及悬浮窗/自由多窗右上角标题避让矩形 (`getTitleButtonRect()`，`vp`)，并将 `windowTopInsetVp`、`windowBottomInsetVp`、`windowTitleRightAvoidVp`、`reduceMotionEnabled` 等发布至 `AppStorage`；同步响应系统深浅色切换与减弱动画无障碍设置，并在窗口销毁时还原系统栏属性与注销命名监听。
- **能力探测与优雅降级**：在 `ImmersiveMaterialStyle` 中先判断 `typeof deviceInfo.apiAvailable === 'function' && deviceInfo.apiAvailable('26.0.0')` 及 `uiMaterial.isImmersiveMaterialSupported()`，同时通过 `hdsMaterial.getSystemMaterialTypes()`（API 23+）探测设备实时支持等级；低于 API 26、设备不支持或用户在 **外观 -> 沉浸光感与空间视觉** 关闭开关时，自动退回到 `BlurStyle.COMPONENT_THICK` / `COMPONENT_ULTRA_THICK` 与标准半透明玻璃层，窗口安全区避让与极性随系统深浅色切换继续生效。

## 构建与单元测试

工程使用 HarmonyOS SDK `26.0.0`，`compatibleSdkVersion: 6.1.0(23)`，声明支持 `phone` 与 `tablet`。

在 macOS 默认 DevEco Studio 安装目录下执行：

```sh
studio=/Applications/DevEco-Studio.app/Contents
export JAVA_HOME="$studio/jbr/Contents/Home"
export DEVECO_SDK_HOME="$studio/sdk"
export PATH="$JAVA_HOME/bin:$studio/tools/node/bin:$PATH"

# 构建 HAP 调试包
"$studio/tools/hvigor/bin/hvigorw" --mode module -p product=default -p module=entry@default assembleHap --no-daemon

# 运行本地 ArkTS 单元测试 (entry/src/test/LocalUnit.test.ets)
"$studio/tools/hvigor/bin/hvigorw" --mode module -p product=default -p module=entry@default test --no-daemon
```
