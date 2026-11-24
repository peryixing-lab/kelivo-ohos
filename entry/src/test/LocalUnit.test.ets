import { describe, expect, it } from '@ohos/hypium';
import {
  ApiFamily,
  ApiKeyEntry,
  AppearanceConfig,
  Attachment,
  ChatMessage,
  Conversation,
  HeaderEntry,
  InstructionCard,
  MemoryEntry,
  MemorySettings,
  ModelSpec,
  Persona,
  Provider,
  ReasoningEffort,
  QuickPhrase,
  RegexRule,
  ScheduledTask,
  SearchHit,
  SearchServiceConfig,
  ToolCallRecord,
  UserProfileField,
  UsageStatRow,
  WorldBook,
  cloneModelSpec,
  defaultAppearance,
  defaultChatItemDisplay,
  defaultGenerationParams,
  defaultModelSpec,
  estimateTokens,
  initialWorkspace,
  isProviderConfigured,
  messageText,
  normalizeAppearanceConfig,
  normalizeInstructionCards,
  normalizeQuickPhrases,
  normalizeWorldBooks,
  preset,
  resolveActiveModel
} from '../main/ets/core/Models';
import { reasoningBulbRayCount, reasoningControl, withReasoning } from '../main/ets/core/Reasoning';
import {
  activateWorldBooks,
  applyRegexRules,
  assembleInstructionCards,
  buildAssembledPrompt,
  expandPromptTemplates,
  parseWorldBookImportJson
} from '../main/ets/core/PromptEngine';
import {
  resolveEffectiveProxy,
  setGlobalHttpProxy,
  shouldBypassProxy
} from '../main/ets/core/ChatClient';
import {
  SmartAddDecision,
  applySmartAddDecisions,
  buildExistingMemoryXmlBlock,
  buildMemoryInjectionBlock,
  buildMemoryRulesSystemPrompt,
  buildProfileBlock,
  findOrphanedMemories,
  findSmartAddCandidates,
  memoryDate,
  mergeMemoryCandidates,
  mergeProfileFields,
  normalizeMemoryTimestamp,
  normalizeUserProfileFields,
  parseExtractedMemoriesResult,
  parseExtractedMemoriesXml,
  parseGatekeeperResult,
  parseGatekeeperXml,
  parseMemoryExtractionResponse,
  parseProfileDistillerResponse,
  parseSmartAddBatchResponse,
  searchMemories
} from '../main/ets/core/MemoryLogic';
import {
  buildMemoryOrganizeBatch,
  buildMemoryTools,
  executeMemoryToolCall,
  memoryTurnBatch
} from '../main/ets/core/MemoryEngine';
import { BUILTIN_PALETTES, normalizePaletteId, parseCustomThemeJson, resolveThemeTokens } from '../main/ets/core/ThemeManager';
import { formatContextWindowShort, resolveBrandIconId, splitAssistantParagraphs } from '../main/ets/core/BrandIcons';
import { getUiStrings } from '../main/ets/core/I18n';
import {
  ChatCall,
  EventReader,
  RichFragment,
  ReplyReasoningTimer,
  ThinkTagStreamParser,
  makeAdvancedChatCall,
  makeChatCall,
  parseReply,
  parseRichReply
} from '../main/ets/core/Protocol';
import { decodeArchive, encodeArchive } from '../main/ets/core/ChatArchive';
import { fromProviderLink, fromProviderText, toProviderLink } from '../main/ets/core/ProviderLink';
import { markKeyError, markKeySuccess, selectApiKey } from '../main/ets/core/KeyPool';
import {
  findStableMarkdownPrefixEnd,
  highlightCode,
  parseMarkdownBlocks,
  parseMdInlines,
  splitInlineTail
} from '../main/ets/core/MarkdownParser';
import { StreamTextSmoother } from '../main/ets/core/StreamSmoother';
import { evalGenUiExpr, interpolateGenUi, parseGenUiDocument } from '../main/ets/core/GenUiParser';
import {
  appendMessageVersion,
  applyContextCompression,
  deleteMessageVersion,
  switchMessageVersion,
  undoContextCompression,
  updateActiveMessageVersionText,
  updateActiveMessageVersionTranslation
} from '../main/ets/core/ContextUtils';
import {
  SEARCH_ENGINE_CATALOG,
  buildSearchRequestSpec,
  extractHtmlReadableText,
  parseSearchResponse
} from '../main/ets/core/SearchAdapters';
import { parseMcpConfigJson } from '../main/ets/core/McpConfigParser';
import { RegisteredTool, assembleToolRegistry } from '../main/ets/core/ToolRegistry';
import { ToolCallGroup, ToolExecutionOutput, accumulateToolDeltas, groupToolCallRecords, runAgentToolLoop } from '../main/ets/core/ToolLoop';
import {
  applyChatCompletionsBuiltInSearch,
  isBuiltInSearchEnabled,
  needsMoonshotBuiltinSearchLoop,
  requiresResponsesApiForBuiltInSearch,
  supportsBuiltInSearch,
  supportsClaudeDynamicWebSearch
} from '../main/ets/core/BuiltinSearch';
import {
  computeStackedBarPcts,
  computeUsageDashboard,
  formatLocalDay,
  formatLocalTime,
  formatUsageCount
} from '../main/ets/core/UsageStatsLogic';
import {
  BackupScopeConfig,
  countSelectedBackupScope,
  defaultBackupScope,
  defaultBackupConfig,
  normalizeBackupScope
} from '../main/ets/core/Models';
import { argon2id } from '../main/ets/core/Argon2id';
import {
  applyScopedRestore,
  buildAndroidChatsJson,
  buildAndroidSettingsJson,
  buildHarmonyBackupJson,
  parseAndroidChatsJson,
  parseAndroidSettingsJson,
  parseHarmonyBackupJson
} from '../main/ets/core/BackupCodec';
import { buildS3CanonicalRequest, parseS3ListXml } from '../main/ets/core/S3SigV4';
import {
  assembleChatboxZipV2Json,
  detectAndImportThirdPartyJson,
  detectAndParseThirdPartyJson,
  importFlutterFullArchive
} from '../main/ets/core/ThirdPartyImport';
import {
  buildUnifiedDiff,
  matchSimpleGlob,
  redactEnvSecrets,
  resolveSafeWorkspacePath
} from '../main/ets/core/WorkspaceDiff';
import { GenerationTaskTracker } from '../main/ets/core/BackgroundGeneration';
import { ChatGenerationJob, GenerationSessionRegistry } from '../main/ets/core/GenerationSession';
import {
  buildSkillsPromptSummary,
  defaultBuiltinSkills,
  parseSkillMarkdown,
  resolveGitHubSkillRawUrl
} from '../main/ets/core/SkillsParser';
import { evaluateMathExpression } from '../main/ets/core/MathEval';
import { computeNextRunMs, isTaskDue } from '../main/ets/core/ScheduleCalc';
import {
  findZipEntry,
  listZipEntries,
  normalizeZipEntryPath
} from '../main/ets/core/ZipDirectory';
import {
  computeCutoutSafeInsets,
  mergeSafeAreaInsets,
  normalizeHexColor,
  hexWithAlpha,
  computeFloatingBottomInsetVp
} from '../main/ets/core/ImmersiveUtils';

const user: ChatMessage = {
  id: 'question',
  role: 'user',
  text: '图中是什么？',
  model: '',
  attachment: { name: 'image.png', mime: 'image/png', data: 'aW1n' }
};

function callFor(family: ApiFamily) {
  return makeChatCall(preset('p', 'P', family, 'https://example.com/v1/', 'model-a'), 'test-key', '请用中文回答', [user]);
}

export default function localUnitTest() {
  describe('KelivoProtocolAndMigration', () => {
    it('OpenAICompatibleVision', 0, () => {
      const call = callFor('openai');
      expect(call.address).assertEqual('https://example.com/v1/chat/completions');
      expect(call.headers['Authorization']).assertEqual('Bearer test-key');
      expect(call.body).assertContain('"role":"system"');
      expect(call.body).assertContain('data:image/png;base64,aW1n');
      expect(parseReply('{"choices":[{"delta":{"content":"回答","reasoning_content":"推理"}}]}').reasoning).assertEqual('推理');
    });
    it('AnthropicMessages', 0, () => {
      const call = callFor('anthropic');
      expect(call.address).assertEqual('https://example.com/v1/messages');
      expect(call.headers['x-api-key']).assertEqual('test-key');
      expect(call.body).assertContain('"system":"请用中文回答"');
      expect(call.body).assertContain('"media_type":"image/png"');
      expect(parseReply('{"type":"content_block_delta","delta":{"type":"text_delta","text":"你好"}}').text).assertEqual('你好');
    });
    it('GeminiParts', 0, () => {
      const call = callFor('gemini');
      expect(call.address).assertEqual('https://example.com/v1/models/model-a:streamGenerateContent?alt=sse');
      expect(call.headers['x-goog-api-key']).assertEqual('test-key');
      expect(call.body).assertContain('"systemInstruction"');
      expect(call.body).assertContain('"inlineData"');
      const f = parseReply('{"candidates":[{"content":{"parts":[{"text":"想法","thought":true},{"text":"你好"}]}}]}');
      expect(f.reasoning).assertEqual('想法');
      expect(f.text).assertEqual('你好');
    });
    it('SseEverySplitAndFinalLine', 0, () => {
      const wire = ': keep-alive\r\ndata: {"choices":[\r\ndata: {"delta":{"content":"你"}}]}\r\n\r\ndata: [DONE]';
      for (let cut = 0; cut <= wire.length; cut++) {
        const data: string[] = [];
        const reader = new EventReader((s: string) => { data.push(s); });
        reader.push(wire.slice(0, cut)); reader.push(wire.slice(cut)); reader.finish();
        expect(data.length).assertEqual(2);
        expect(parseReply(data[0]).text).assertEqual('你');
        expect(parseReply(data[1]).text).assertEqual('');
      }
    });
    it('NativeArchiveRoundTrip', 0, () => {
      const chat: Conversation = { id: 'c', title: '图', updated: 1, messages: [user], personaId: 'default' };
      const imported = decodeArchive(encodeArchive([chat]));
      expect(imported[0].messages[0].attachment?.data).assertEqual('aW1n');
      expect(imported[0].id).assertEqual(chat.id);
    });
    it('FlutterHistoryUsesSelectedVersionAndMessageOrder', 0, () => {
      const raw = '{"version":1,"conversations":[{"id":"c","title":"旧对话","updatedAt":"2025-09-01T00:00:00Z",' +
        '"messageIds":["u","a","b"],"versionSelections":{"g":0}}],"messages":[' +
        '{"id":"b","conversationId":"c","role":"assistant","content":"第二版","version":1,"groupId":"g"},' +
        '{"id":"u","conversationId":"c","role":"user","content":"请翻译"},' +
        '{"id":"a","conversationId":"c","role":"assistant","content":"第一版","version":0,"groupId":"g"}]}';
      const messages = decodeArchive(raw)[0].messages;
      expect(messages.length).assertEqual(2);
      expect(messages[0].text).assertEqual('请翻译');
      expect(messages[1].text).assertEqual('第一版');
    });
    it('RejectsInvalidBackupBeforeMerge', 0, () => {
      let invalid = false;
      try { decodeArchive('{"version":1,"format":"kelivo-arkui-chats","conversations":[{}]}'); }
      catch (_) { invalid = true; }
      expect(invalid).assertTrue();
    });

    // Phase 1 tests
    it('ResponsesApiAndToolCallProtocol', 0, () => {
      const p = preset('resp', 'Resp', 'openai-responses', 'https://api.openai.com/v1', 'gpt-5');
      const call = makeAdvancedChatCall(p, 'k1', 'Be concise', [user], {
        params: { reasoningEffort: 'high' },
        tools: [{ name: 'web_search', description: 'search', parametersJson: '{"type":"object","properties":{"q":{"type":"string"}}}' }],
        builtinSearch: true
      });
      expect(call.address).assertEqual('https://api.openai.com/v1/responses');
      expect(call.body).assertContain('"instructions":"Be concise"');
      expect(call.body).assertContain('"type":"web_search"');
      const frag = parseRichReply('{"type":"response.output_text.delta","delta":"hello"}');
      expect(frag.text).assertEqual('hello');
      const tc = parseRichReply('{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"calc","arguments":"{\\"x\\":1}"}}]}}]}');
      expect(tc.toolCalls.length).assertEqual(1);
      expect(tc.toolCalls[0].name).assertEqual('calc');
    });

    it('ThinkTagStreamParserSplitsAcrossChunks', 0, () => {
      const parser = new ThinkTagStreamParser();
      const wire = '前文<thi' + 'nk>推理过程</th' + 'ink>正式回答';
      let outText = '';
      let outReason = '';
      for (let i = 0; i < wire.length; i += 3) {
        const f = parser.push(wire.slice(i, i + 3));
        outText += f.text;
        outReason += f.reasoning;
      }
      const tail = parser.flush();
      outText += tail.text;
      outReason += tail.reasoning;
      expect(outReason).assertEqual('推理过程');
      expect(outText).assertEqual('前文正式回答');
    });

    it('ReasoningClosesBeforeTheReplyFinishes', 0, () => {
      const timer = new ReplyReasoningTimer();
      const thought = parseRichReply('{"choices":[{"delta":{"reasoning_content":"考虑一下"}}]}');
      timer.update(thought, 100);
      timer.update(parseRichReply('{"usage":{"completion_tokens":2}}'), 400);
      expect(timer.active).assertTrue();
      const tool = parseRichReply('{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"memory_update"}}]}}]}');
      timer.update(tool, 1900);
      expect(timer.active).assertFalse();
      expect(timer.elapsedMs).assertEqual(1800);
      timer.update(thought, 7000);
      expect(timer.active).assertTrue();
      timer.update(parseRichReply('{"choices":[{"delta":{"content":"答案"}}]}'), 7300);
      expect(timer.active).assertFalse();
      timer.finish(11000);
      expect(timer.elapsedMs).assertEqual(2100);

      const boundaries: string[] = [
        '{"type":"content_block_stop","index":0}',
        '{"type":"response.output_item.done","item":{"type":"reasoning"}}',
        '[DONE]'
      ];
      for (let i = 0; i < boundaries.length; i++) {
        timer.update(thought, 12000);
        timer.update(parseRichReply(boundaries[i]), 12100);
        expect(timer.active).assertFalse();
      }
      const parser = new ThinkTagStreamParser();
      const start = parser.push('前言<think>推理</thi');
      timer.update({ text: start.text, reasoning: start.reasoning, reasoningPhase: start.reasoningPhase,
        done: false, generatedImages: [], toolCalls: [] }, 13000);
      expect(timer.active).assertTrue();
      const close = parser.push('nk>');
      expect(close.text).assertEqual('');
      expect(close.reasoningPhase).assertEqual('finished');
    });

    it('KeyPoolRotationAndCooldown', 0, () => {
      let pool: ApiKeyEntry[] = [
        { id: 'k1', label: 'A', secretRef: 'r1', priority: 2, usageCount: 5, errorCount: 0, disabledUntil: 0 },
        { id: 'k2', label: 'B', secretRef: 'r2', priority: 1, usageCount: 1, errorCount: 0, disabledUntil: 0 }
      ];
      const byPrio = selectApiKey('p1', pool, 'priority', 1000);
      expect(byPrio?.id).assertEqual('k2');
      pool = markKeyError(pool, 'k2', 429, 1000);
      const next = selectApiKey('p1', pool, 'priority', 2000);
      expect(next?.id).assertEqual('k1');
      pool = markKeySuccess(pool, 'k1');
      expect(pool[0].usageCount).assertEqual(6);
    });

    it('MarkdownAstAndSyntaxHighlight', 0, () => {
      const md = '# 标题\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\n```ts\nconst x = 42;\n```\n\n$$E=mc^2$$';
      const blocks = parseMarkdownBlocks(md);
      expect(blocks[0].kind).assertEqual('heading');
      expect(blocks[1].kind).assertEqual('table');
      expect(blocks[1].rows[0][1]).assertEqual('2');
      expect(blocks[2].kind).assertEqual('code');
      expect(blocks[3].kind).assertEqual('math_block');
      const inlines = parseMdInlines('**粗体** 与 [链接](https://kelivo.psycheas.top)');
      expect(inlines[0].kind).assertEqual('bold');
      expect(inlines[2].kind).assertEqual('link');
      const highlighted = highlightCode('const x = 42; // hi', 'ts');
      expect(highlighted[0].tokens[0].kind).assertEqual('keyword');
    });

    it('GenUiParserAndExpressionEvaluator', 0, () => {
      const json = '{"title":"复利计算","state":{"p":1000,"r":0.1,"n":2},"nodes":[{"type":"metric","label":"终值","expr":"round(p * pow(1 + r, n), 2)"}]}';
      const doc = parseGenUiDocument(json);
      expect(doc.title).assertEqual('复利计算');
      expect(evalGenUiExpr('round(p * pow(1 + r, n), 2)', doc.state)).assertEqual(1210);
      expect(interpolateGenUi('共 {{p * 2}} 元', doc.state)).assertEqual('共 2000 元');
    });

    it('ContextCompressionUndoAndVersioning', 0, () => {
      const msgs: ChatMessage[] = [
        { id: 'u1', role: 'user', text: '问题一', model: '' },
        { id: 'a1', role: 'assistant', text: '回答一', model: 'm1' }
      ];
      const compressed = applyContextCompression(msgs, '摘要内容', 'sum1', 'm1');
      expect(compressed.length).assertEqual(1);
      expect(compressed[0].isSummary).assertTrue();
      const restored = undoContextCompression(compressed);
      expect(restored.length).assertEqual(2);
      expect(restored[1].text).assertEqual('回答一');

      const v2 = appendMessageVersion(msgs[1], { id: 'v2', text: '回答二', reasoning: '思考', reasoningDurationMs: 1500, model: 'm1', createdAt: 2 });
      expect(v2.text).assertEqual('回答二');
      expect(v2.reasoningDurationMs).assertEqual(1500);
      const switched = switchMessageVersion(v2, 0);
      expect(switched.text).assertEqual('回答一');
      expect(switched.reasoningDurationMs === undefined).assertTrue();
      expect(estimateTokens('Hello 世界') > 0).assertTrue();
    });

    // Phase 2 tests
    it('SearchAdaptersAndHtmlExtractor', 0, () => {
      expect(SEARCH_ENGINE_CATALOG.length >= 24).assertTrue();
      const svc: SearchServiceConfig = {
        id: 's1', kind: 'brave', name: 'Brave', endpoint: '', apiKeys: [],
        keyStrategy: 'round_robin', maxResults: 5, enabled: true, mode: 'agent_tool', webFetchEnabled: true
      };
      const wire = buildSearchRequestSpec(svc, 'brave-key', 'HarmonyOS');
      expect(wire.headers['X-Subscription-Token']).assertEqual('brave-key');
      const hits = parseSearchResponse('brave_json', '{"web":{"results":[{"title":"Doc","url":"https://example.com","description":"Hi"}]}}', 5);
      expect(hits.length).assertEqual(1);
      expect(hits[0].title).assertEqual('Doc');
      const text = extractHtmlReadableText('<html><script>bad()</script><body><h1>Hello</h1><p>World &amp; Kelivo</p></body></html>');
      expect(text).assertContain('Hello');
      expect(text).assertContain('World & Kelivo');
    });

    it('McpConfigJsonAndToolRegistry', 0, () => {
      const json = '{"mcpServers":{"fetch":{"url":"https://mcp.example.com/sse","headers":{"Authorization":"Bearer tok"}}}}';
      let seq = 0;
      const imported = parseMcpConfigJson(json, (): string => 'id-' + (++seq));
      expect(imported.length).assertEqual(1);
      expect(imported[0].config.transport).assertEqual('sse');
      expect(imported[0].bearerToken).assertEqual('tok');

      const tools = assembleToolRegistry({
        searchService: {
          id: 's1', kind: 'duckduckgo', name: 'DDG', endpoint: '', apiKeys: [],
          keyStrategy: 'round_robin', maxResults: 5, enabled: true, mode: 'agent_tool', webFetchEnabled: true
        },
        searchEnabled: true,
        builtinFetchEnabled: true,
        mcpTools: [{ serverId: 'id-1', name: 'my_tool', description: 'orig', parametersJson: '{}' }],
        mcpServers: [imported[0].config],
        extraTools: [],
        overrides: [{ toolName: 'my_tool', customDescription: 'custom desc', enabled: true }]
      });
      expect(tools.some((t: RegisteredTool): boolean => t.declaration.name === 'web_search')).assertTrue();
      const custom = tools.find((t: RegisteredTool): boolean => t.declaration.name === 'my_tool');
      expect(custom?.declaration.description).assertEqual('custom desc');
    });

    it('AgentToolLoopMultiStepMock', 0, async () => {
      let round = 0;
      const out = await runAgentToolLoop({
        provider: preset('openai', 'OpenAI', 'openai', 'https://api.openai.com/v1', 'gpt-5.4'),
        apiKey: 'k',
        modelId: 'gpt-5.4',
        systemPrompt: '',
        history: [{ id: 'u1', role: 'user', text: '查一下', model: '' }],
        genParams: withReasoning(defaultGenerationParams(), 'xhigh'),
        tools: [{
          declaration: { name: 'web_search', description: 'search', parametersJson: '{"type":"object"}' },
          source: 'builtin',
          requiresApproval: false
        }],
        permissionMode: 'ask',
        maxSteps: 4,
        runStream: async (call: ChatCall, onFrag: (f: RichFragment) => void): Promise<void> => {
          expect(call.body).assertContain('"reasoning_effort":"xhigh"');
          round++;
          if (round === 1) {
            onFrag({
              text: '', reasoning: '', generatedImages: [], done: false,
              toolCalls: [{ index: 0, id: 'call_1', name: 'web_search', argsDelta: '{"query":"hi"}', done: false }]
            });
          } else {
            onFrag({ text: '最终答案', reasoning: '', toolCalls: [], generatedImages: [], done: true });
          }
        },
        executeTool: async (_tool: RegisteredTool, args: string): Promise<ToolExecutionOutput> => {
          return { text: '搜索结果:' + args };
        },
        requestApproval: async (): Promise<'allow_once' | 'allow_all' | 'deny'> => 'allow_once',
        onUpdate: () => {},
        isStopped: () => false
      });
      expect(round).assertEqual(2);
      expect(out.toolCalls.length).assertEqual(1);
      expect(out.toolCalls[0].status).assertEqual('done');
      expect(out.text).assertContain('最终答案');
    });

    it('S3SigV4AndThirdPartyImporters', 0, () => {
      const canonical = buildS3CanonicalRequest(
        'GET', '/mybucket/a b.json', { 'list-type': '2' },
        { 'host': 's3.example.com', 'x-amz-date': '20261120T100000Z' },
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
      );
      expect(canonical.canonicalUri).assertEqual('/mybucket/a%20b.json');
      expect(canonical.signedHeaders).assertEqual('host;x-amz-date');

      const s3List = parseS3ListXml('<ListBucketResult><Contents><Key>kelivo/b1.json</Key><Size>2048</Size><LastModified>2026-11-20</LastModified></Contents></ListBucketResult>');
      expect(s3List.length).assertEqual(1);
      expect(s3List[0].size).assertEqual(2048);

      const flutterRaw = '{"version":1,"conversations":[{"id":"c1","title":"FlutterChat","messageIds":["u1","a1","a2"],"versionSelections":{"g1":1}}],"messages":[{"id":"u1","conversationId":"c1","role":"user","content":"Hi"},{"id":"a1","conversationId":"c1","role":"assistant","content":"V1","groupId":"g1","version":0},{"id":"a2","conversationId":"c1","role":"assistant","content":"V2","groupId":"g1","version":1}]}';
      const flBundle = importFlutterFullArchive(flutterRaw);
      expect(flBundle.conversations[0].messages[1].versions?.length).assertEqual(2);
      expect(flBundle.conversations[0].messages[1].text).assertEqual('V2');

      const cherry = detectAndImportThirdPartyJson('{"indexedDB":{"topics":[{"id":"t1","name":"CherryTopic","messages":[{"id":"m1","role":"user","content":"Hello"}]}]}}');
      expect(cherry.sourceName).assertEqual('Cherry Studio');
      expect(cherry.conversations[0].title).assertEqual('CherryTopic');

      const chatbox = detectAndImportThirdPartyJson('{"chat-sessions":[{"id":"cb1","name":"CB","messages":[{"id":"m1","role":"user","content":"Hey"}]}]}');
      expect(chatbox.sourceName).assertEqual('Chatbox');
      expect(chatbox.conversations[0].messages[0].text).assertEqual('Hey');
    });

    it('PromptEngineTemplatesRegexAndWorldBook', 0, () => {
      const expanded = expandPromptTemplates('Hi {{user_name}}, I am {{assistant_name}} on {{date}} ({{model}}).', {
        userName: 'Alice',
        assistantName: 'Coder',
        modelName: 'gpt-5',
        now: new Date(2026, 10, 20, 9, 30, 0)
      });
      expect(expanded).assertEqual('Hi Alice, I am Coder on 2026-11-20 (gpt-5).');

      const rules: RegexRule[] = [
        { id: 'r1', name: 'cleanSecret', pattern: 'SECRET_[0-9]+', replacement: '[REDACTED]', flags: 'g', scope: 'input', enabled: true },
        { id: 'r2', name: 'tagStrip', pattern: '<debug>.*?</debug>', replacement: '', flags: 'g', scope: 'display', enabled: true }
      ];
      expect(applyRegexRules('key is SECRET_1234', rules, 'input')).assertEqual('key is [REDACTED]');
      expect(applyRegexRules('hello <debug>tmp</debug>world', rules, 'display')).assertEqual('hello world');

      const importedWb = parseWorldBookImportJson(
        '{"name":"Lore","entries":{"0":{"comment":"ArkUI","key":["arkui","harmony"],"content":"Use ArkTS V1.","position":"before_last_user","role":"system"}}}'
      );
      expect(importedWb.name).assertEqual('Lore');
      expect(importedWb.entries.length).assertEqual(1);

      const books: WorldBook[] = [
        {
          id: 'wb1',
          name: 'DevBook',
          description: '',
          enabled: true,
          entries: [
            {
              id: 'e1', name: 'Rule1', keys: ['harmony'], useRegex: false,
              content: 'Follow HarmonyOS stage model.', position: 'after_system',
              role: 'system', depth: 1, enabled: true, alwaysActive: false
            },
            importedWb.entries[0]
          ]
        }
      ];
      const msgs: ChatMessage[] = [
        { id: 'u1', role: 'user', text: 'Explain harmony state', model: '' }
      ];
      const act = activateWorldBooks(books, undefined, msgs);
      expect(act.afterSystem.length).assertEqual(1);

      const cards: InstructionCard[] = [
        { id: 'c1', title: 'Concise', description: '', content: 'Keep it brief.', builtin: true }
      ];
      const assembled = buildAssembledPrompt({
        baseSystemPrompt: 'Base {{user_name}}',
        presetMessages: [{ id: 'p1', role: 'user', content: 'Demo prompt' }],
        historyMessages: msgs,
        worldBooks: books,
        instructionCards: cards,
        activeInstructionIds: ['c1'],
        memoryBlock: '# Memory\n- Prefers TypeScript',
        templateContext: { userName: 'Bob', assistantName: 'Kelivo' }
      });
      expect(assembled.systemPrompt).assertContain('Base Bob');
      expect(assembled.systemPrompt).assertContain('Keep it brief.');
      expect(assembled.systemPrompt).assertContain('Follow HarmonyOS stage model.');
      expect(assembled.messages.length).assertEqual(3);
      expect(assembled.messages[1].text).assertContain('Use ArkTS V1.');
      expect(assembled.systemPrompt.indexOf('Prefers TypeScript')).assertEqual(-1);
      const wireUser = assembled.messages.find((message: ChatMessage): boolean => message.id === 'u1');
      expect(wireUser?.text.startsWith('# Memory')).assertTrue();
      expect(msgs[0].text.startsWith('# Memory')).assertFalse();
    });

    it('MemoryLogicInjectionSearchAndMerge', 0, () => {
      const mems: MemoryEntry[] = [
        { id: 'm2', category: 'workflow', content: 'Uses hvigorw CLI for builds', archived: false, createdAt: 200, updatedAt: 200 },
        { id: 'm1', category: 'identity', content: 'HarmonyOS engineer', archived: false, createdAt: 100, updatedAt: 100 },
        { id: 'm3', category: 'tone', content: 'Old archived note', archived: true, createdAt: 50, updatedAt: 50 }
      ];
      const profile: UserProfileField[] = [
        { id: 'pf1', key: '称呼', value: '千帆', updatedAt: 100 }
      ];
      const settings: MemorySettings = { autoExtract: true, injectGlobal: true, maxInjectCount: 10 };
      const block = buildMemoryInjectionBlock(mems, profile, settings);
      expect(block).assertContain('千帆');
      expect(block).assertContain('HarmonyOS engineer');
      expect(block).assertContain('<custom name="称呼">千帆</custom>');
      expect(block.indexOf('HarmonyOS engineer') < block.indexOf('Uses hvigorw')).assertTrue();
      expect(block.indexOf('Old archived') < 0).assertTrue();

      const hits = searchMemories(mems, 'hvigorw');
      expect(hits.length).assertEqual(1);
      expect(hits[0].id).assertEqual('m2');

      const parsed = parseMemoryExtractionResponse(
        '```json\n{"shouldSave":true,"summary":"记录语言偏好","memories":[{"category":"workflow","content":"Uses hvigorw CLI for builds cleanly"},{"category":"tone","content":"Prefers concise answers"}],"profile":[{"key":"称呼","value":"千帆同学"}]}\n```'
      );
      expect(parsed.shouldSave).assertTrue();
      expect(parsed.memories.length).assertEqual(2);
      const merged = mergeMemoryCandidates(mems, parsed.memories, 'chat1');
      expect(merged.mergedCount).assertEqual(1);
      expect(merged.addedCount).assertEqual(1);
      const pMerged = mergeProfileFields(profile, parsed.profile);
      expect(pMerged.fields[0].value).assertEqual('千帆同学');
    });

    it('ThemeManagerAndSixLanguageI18n', 0, () => {
      const appCfg = defaultAppearance();
      appCfg.themeMode = 'dark';
      appCfg.paletteId = 'emerald';
      const darkTokens = resolveThemeTokens(appCfg, false);
      expect(darkTokens.accent).assertEqual('#87D7AA');

      const custom = parseCustomThemeJson('{"accent":"#FF5500","invalid":"nothex"}', darkTokens);
      expect(custom?.accent).assertEqual('#FF5500');
      expect(custom?.canvas).assertEqual(darkTokens.canvas);

      expect(getUiStrings('zh-Hans').newChat).assertEqual('新对话');
      expect(getUiStrings('zh-Hant').newChat).assertEqual('新對話');
      expect(getUiStrings('en').newChat).assertEqual('New Chat');
      expect(getUiStrings('ko').newChat).assertEqual('새 대화');
      expect(getUiStrings('ru').newChat).assertEqual('Новый чат');
      expect(getUiStrings('tr').newChat).assertEqual('Yeni Sohbet');
    });

    it('WorkspaceDiffGlobAndRedaction', 0, () => {
      expect(resolveSafeWorkspacePath('/sandbox/ws1', 'src/main.ets')).assertEqual('/sandbox/ws1/src/main.ets');
      let blocked = false;
      try {
        resolveSafeWorkspacePath('/sandbox/ws1', '../../etc/passwd');
      } catch (_) {
        blocked = true;
      }
      expect(blocked).assertTrue();

      expect(matchSimpleGlob('entry/src/Index.ets', '**/*.ets')).assertTrue();
      expect(matchSimpleGlob('entry/src/Index.json', '**/*.ets')).assertFalse();

      const diff = buildUnifiedDiff('app.ts', 'line1\nline2\nline3', 'line1\nline2_edited\nline3\nline4');
      expect(diff).assertContain('--- a/app.ts');
      expect(diff).assertContain('+++ b/app.ts');
      expect(diff).assertContain('-line2');
      expect(diff).assertContain('+line2_edited');
      expect(diff).assertContain('+line4');

      expect(redactEnvSecrets('token=ghp_superSecret123456', ['ghp_superSecret123456'])).assertEqual('token=***');
    });

    it('SkillsParserGitHubAndMathAndSchedule', 0, () => {
      const parsed = parseSkillMarkdown('---\nname: pdf-reader\ndescription: Extract PDF charts cleanly\n---\n\n# Steps\nRead file.');
      expect(parsed.name).assertEqual('pdf-reader');
      expect(parsed.description).assertEqual('Extract PDF charts cleanly');

      expect(resolveGitHubSkillRawUrl('https://github.com/Chevey339/kelivo'))
        .assertEqual('https://raw.githubusercontent.com/Chevey339/kelivo/main/SKILL.md');
      expect(resolveGitHubSkillRawUrl('https://github.com/org/repo/blob/dev/skills/demo/SKILL.md'))
        .assertEqual('https://raw.githubusercontent.com/org/repo/dev/skills/demo/SKILL.md');

      const builtins = defaultBuiltinSkills();
      expect(builtins.length).assertEqual(2);
      const summary = buildSkillsPromptSummary(builtins);
      expect(summary).assertContain('visualize');
      expect(summary).assertContain('skill-creator');

      expect(Math.abs(evaluateMathExpression('2 + 3 * (4 ^ 2 - 6) / 5') - 8) < 1e-9).assertTrue();
      expect(Math.abs(evaluateMathExpression('sqrt(16) + pow(2, 3) - -3') - 15) < 1e-9).assertTrue();
      expect(Math.abs(evaluateMathExpression('sin(pi / 2) + round(3.6)') - 5) < 1e-9).assertTrue();

      const baseNow = new Date(2026, 10, 20, 10, 0, 0).getTime(); // Fri Nov 20, 2026 10:00
      const dailyTask: ScheduledTask = {
        id: 't1', name: 'Daily', personaId: 'default', providerId: 'p1', modelId: 'm1',
        prompt: 'Hi', scheduleType: 'daily', timeHHMM: '09:00', weekdays: [], intervalMinutes: 60,
        runAtMs: 0, enabled: true, lastRunAt: new Date(2026, 10, 19, 9, 5, 0).getTime(),
        lastStatus: '', lastConversationId: ''
      };
      expect(isTaskDue(dailyTask, baseNow)).assertTrue();
      const nextDaily = computeNextRunMs(dailyTask, baseNow);
      expect(new Date(nextDaily).getDate()).assertEqual(21);

      const intervalTask: ScheduledTask = {
        id: 't2', name: 'Interval', personaId: 'default', providerId: 'p1', modelId: 'm1',
        prompt: 'Ping', scheduleType: 'interval', timeHHMM: '09:00', weekdays: [], intervalMinutes: 30,
        runAtMs: 0, enabled: true, lastRunAt: baseNow - 31 * 60000, lastStatus: '', lastConversationId: ''
      };
      expect(isTaskDue(intervalTask, baseNow)).assertTrue();
    });

    it('immersiveUtilsAndSafeAreaInsets', 0, () => {
      const cutout = computeCutoutSafeInsets(
        1200,
        2600,
        { left: 500, top: 0, width: 200, height: 96 },
        undefined,
        { left: 0, top: 400, width: 48, height: 180 },
        { left: 1160, top: 400, width: 40, height: 180 }
      );
      expect(cutout.top).assertEqual(96);
      expect(cutout.bottom).assertEqual(0);
      expect(cutout.left).assertEqual(48);
      expect(cutout.right).assertEqual(40);

      const merged = mergeSafeAreaInsets(
        cutout,
        { top: 120, bottom: 84, left: 0, right: 64 }
      );
      expect(merged.top).assertEqual(120);
      expect(merged.bottom).assertEqual(84);
      expect(merged.left).assertEqual(48);
      expect(merged.right).assertEqual(64);

      expect(normalizeHexColor('abc', '#112233')).assertEqual('#AABBCC');
      expect(normalizeHexColor('#ff123456', '#112233')).assertEqual('#123456');
      expect(normalizeHexColor('not-a-color', '#112233')).assertEqual('#112233');

      expect(hexWithAlpha('#0A84FF', '14')).assertEqual('#140A84FF');
      expect(hexWithAlpha('#0A84FF', 'FF')).assertEqual('#CC0A84FF');

      expect(computeFloatingBottomInsetVp(28, false, false)).assertEqual(28);
      expect(computeFloatingBottomInsetVp(28, true, false)).assertEqual(0);
      expect(computeFloatingBottomInsetVp(28, true, true)).assertEqual(8);
    });

    it('AndroidAlignmentPalettesBrandsAndDisplayDefaults', 0, () => {
      expect(BUILTIN_PALETTES.length).assertEqual(9);
      const ids = BUILTIN_PALETTES.map((p) => p.id);
      const expected = ['default', 'blue', 'green', 'purple', 'yellow', 'smoky_rose', 'terracotta', 'monochrome', 'doc_theme'];
      for (let i = 0; i < expected.length; i++) {
        expect(ids.includes(expected[i])).assertTrue();
      }

      expect(normalizePaletteId('kelivo-indigo')).assertEqual('default');
      expect(normalizePaletteId('azure')).assertEqual('blue');
      expect(normalizePaletteId('emerald')).assertEqual('green');
      expect(normalizePaletteId('violet')).assertEqual('purple');
      expect(normalizePaletteId('amber')).assertEqual('yellow');
      expect(normalizePaletteId('rose')).assertEqual('smoky_rose');
      expect(normalizePaletteId('slate')).assertEqual('monochrome');

      const pureLightCfg = defaultAppearance();
      pureLightCfg.themeMode = 'light';
      pureLightCfg.pureBackground = true;
      expect(resolveThemeTokens(pureLightCfg, false).canvas).assertEqual('#FFFFFF');

      const pureDarkCfg = defaultAppearance();
      pureDarkCfg.themeMode = 'dark';
      pureDarkCfg.pureBackground = true;
      expect(resolveThemeTokens(pureDarkCfg, true).canvas).assertEqual('#000000');

      expect(resolveBrandIconId('gpt-4o', 'openai')).assertEqual('openai');
      expect(resolveBrandIconId('gemini-2.5-pro', 'gemini')).assertEqual('gemini');
      expect(resolveBrandIconId('claude-3-7-sonnet', 'anthropic')).assertEqual('claude');
      expect(resolveBrandIconId('deepseek-r1', 'openai')).assertEqual('deepseek');
      expect(resolveBrandIconId('qwen3-coder', 'openai')).assertEqual('qwen');
      expect(resolveBrandIconId('llama3.3 Ollama', 'openai')).assertEqual('ollama');
      expect(resolveBrandIconId('tavily')).assertEqual('tavily');
      expect(resolveBrandIconId('mcp-server')).assertEqual('mcp');

      expect(formatContextWindowShort(128000)).assertEqual('128k');
      expect(formatContextWindowShort(1000000)).assertEqual('1M');
      expect(formatContextWindowShort(1048576)).assertEqual('1.0M');

      const split = splitAssistantParagraphs('Intro paragraph.\n\n```ts\nconst a = 1;\n\nconst b = 2;\n```\n\nConclusion.');
      expect(split.length).assertEqual(3);
      expect(split[1]).assertContain('const b = 2;');

      const disp = defaultChatItemDisplay();
      expect(disp.showModelIcon).assertTrue();
      expect(disp.showUserAvatar).assertTrue();
      expect(disp.showToolCards).assertTrue();
      expect(disp.showReasoningLevelOnButton).assertFalse();

      const rawApp = defaultAppearance();
      rawApp.paletteId = 'azure';
      rawApp.enableUserMarkdown = false;
      const norm = normalizeAppearanceConfig(rawApp);
      expect(norm.paletteId).assertEqual('azure');
      expect(norm.enableAssistantMarkdown).assertTrue();
      expect(norm.enableUserMarkdown).assertFalse();
      expect(norm.chatItemDisplay !== undefined).assertTrue();
    });

    it('ProviderLinkBidirectionalAndMultiFormatImport', 0, () => {
      const openaiCode = 'ai-provider:v1:eyJ0eXBlIjogIm9wZW5haSIsICJuYW1lIjogIuehheWfuua1geWKqCIsICJhcGlLZXkiOiAic2stYW5kcm9pZC10ZXN0IiwgImJhc2VVcmwiOiAiaHR0cHM6Ly9hcGkuc2lsaWNvbmZsb3cuY24vdjEifQ==';
      const claudeCode = 'ai-provider:v1:eyJ0eXBlIjogImNsYXVkZSIsICJuYW1lIjogIkNsYXVkZVdvcmsiLCAiYXBpS2V5IjogInNrLWFudC0xMjMiLCAiYmFzZVVybCI6ICJodHRwczovL2FwaS5hbnRocm9waWMuY29tL3YxIn0=';
      const googleCode = 'ai-provider:v1:eyJ0eXBlIjogImdvb2dsZSIsICJuYW1lIjogIkdlbWluaUZyZWUiLCAiYXBpS2V5IjogIkFJemFUZXN0MTIzIn0=';
      const oauthCode = 'ai-provider:v1:eyJ0eXBlIjogIm9hdXRoIiwgImNvbmZpZyI6IHsibmFtZSI6ICJDaGF0R1BUIFBsdXMiLCAib2F1dGhQcm92aWRlciI6ICJjaGF0Z3B0IiwgInByb3ZpZGVyVHlwZSI6ICJvcGVuYWkiLCAiYmFzZVVybCI6ICJodHRwczovL2NoYXRncHQuY29tL2JhY2tlbmQtYXBpL2NvZGV4IiwgIm1vZGVscyI6IFsiZ3B0LTUuMSJdLCAib2F1dGhDcmVkZW50aWFscyI6IHsiYWNjZXNzVG9rZW4iOiAidG9rLW9hdXRoLTk5IiwgImVtYWlsIjogInVzZXJAZXhhbXBsZS5jb20ifX19';
      const legacyCompatCode = 'ai-provider:v1:eyJ0eXBlIjoib3BlbmFpLWNvbXBhdCIsIm5hbWUiOiJMZWdhY3lOb2RlIiwiYXBpS2V5Ijoic2stbGVnYWN5IiwiYmFzZVVybCI6Imh0dHBzOi8vbGVnYWN5LmV4YW1wbGUuY29tL3YxIn0=';

      const decOpenAi = fromProviderLink(openaiCode, 'id_1');
      expect(decOpenAi.provider.name).assertEqual('硅基流动');
      expect(decOpenAi.provider.family).assertEqual('openai');
      expect(decOpenAi.provider.baseUrl).assertEqual('https://api.siliconflow.cn/v1');
      expect(decOpenAi.key).assertEqual('sk-android-test');

      const decClaude = fromProviderLink(claudeCode, 'id_2');
      expect(decClaude.provider.family).assertEqual('anthropic');
      expect(decClaude.provider.name).assertEqual('ClaudeWork');
      expect(decClaude.key).assertEqual('sk-ant-123');

      const decGoogle = fromProviderLink(googleCode, 'id_3');
      expect(decGoogle.provider.family).assertEqual('gemini');
      expect(decGoogle.provider.baseUrl).assertEqual('https://generativelanguage.googleapis.com/v1beta');
      expect(decGoogle.key).assertEqual('AIzaTest123');

      const decOAuth = fromProviderLink(oauthCode, 'id_4');
      expect(decOAuth.provider.name).assertEqual('ChatGPT Plus');
      expect(decOAuth.provider.oauth?.kind).assertEqual('chatgpt');
      expect(decOAuth.provider.oauth?.accountEmail).assertEqual('user@example.com');
      expect(decOAuth.provider.model).assertEqual('gpt-5.1');
      expect(decOAuth.key).assertEqual('tok-oauth-99');

      const decLegacy = fromProviderLink(legacyCompatCode, 'id_5');
      expect(decLegacy.provider.family).assertEqual('openai');
      expect(decLegacy.provider.name).assertEqual('LegacyNode');
      expect(decLegacy.key).assertEqual('sk-legacy');

      const sfProv = preset('id_rt', '硅基流动', 'openai', 'https://api.siliconflow.cn/v1', '');
      const encoded = toProviderLink(sfProv, 'sk-round');
      expect(encoded).assertEqual('ai-provider:v1:eyJ0eXBlIjoib3BlbmFpIiwibmFtZSI6IuehheWfuua1geWKqCIsImFwaUtleSI6InNrLXJvdW5kIiwiYmFzZVVybCI6Imh0dHBzOi8vYXBpLnNpbGljb25mbG93LmNuL3YxIn0=');

      let seq = 0;
      const multi = fromProviderText(`${openaiCode}\n  invalid-line \n${claudeCode}\n${googleCode}`, (): string => `m_${++seq}`);
      expect(multi.length).assertEqual(3);
      expect(multi[0].provider.id).assertEqual('m_1');
      expect(multi[1].provider.family).assertEqual('anthropic');
      expect(multi[2].provider.family).assertEqual('gemini');

      const chatBoxRaw = '{"providers":{"openai":{"name":"BoxOpenAI","apiKey":"sk-cb-1","baseUrl":"https://api.openai.com/v1"},"claude":{"apiKey":"sk-cb-2"},"gemini":{"apiKey":"AIza-cb-3"}}}';
      const chatBoxItems = fromProviderText(chatBoxRaw, (): string => `cb_${++seq}`);
      expect(chatBoxItems.length).assertEqual(3);
      expect(chatBoxItems[0].provider.name).assertEqual('BoxOpenAI');
      expect(chatBoxItems[1].provider.family).assertEqual('anthropic');
      expect(chatBoxItems[2].provider.family).assertEqual('gemini');
    });

    it('AssistantMemoryScopesRecallAndTemporaryChats', 0, () => {
      const chat: Conversation = { id: 'current', title: '当前', updated: 1, personaId: 'a', messages: [] };
      const persona: Persona = {
        id: 'a', name: 'A', prompt: '', memoryEnabled: true, autoOrganizeMemory: false,
        allowPastConversationRecall: true, memoryWriteScope: 'alwaysAssistant'
      };
      const memories: MemoryEntry[] = [
        { id: 'same', category: 'tone', content: '旧偏好', assistantId: 'a', archived: false, createdAt: 1, updatedAt: 1 },
        { id: 'other', category: 'tone', content: '其他助手偏好', assistantId: 'b', archived: false, createdAt: 2, updatedAt: 2 },
        { id: 'global', category: 'tone', content: '全局 & 较新', archived: false, createdAt: 3, updatedAt: 3 }
      ];
      const settings: MemorySettings = { autoExtract: false, injectGlobal: true, maxInjectCount: 1 };
      const block = buildMemoryInjectionBlock(memories, [], settings, 'a');
      expect(block).assertContain('<user_memory type="voice" mode="summary" total="2" shown="1">');
      expect(block).assertContain('全局 &amp; 较新');
      expect(block.includes('其他助手偏好')).assertFalse();
      expect(buildMemoryInjectionBlock(memories, [], settings, 'a', ['tone'])).assertContain('旧偏好');

      const tools = buildMemoryTools(true, true, false, 'alwaysAssistant');
      expect(tools.some((item): boolean => item.declaration.name === 'memory_read')).assertTrue();
      expect(tools.some((item): boolean => item.declaration.name === 'chat_search')).assertTrue();
      expect(tools.some((item): boolean => item.declaration.name === 'memory_update')).assertFalse();

      const writeArgs: Record<string, Object> = {};
      writeArgs['type'] = 'voice';
      writeArgs['content'] = '使用简洁的工程说明';
      writeArgs['scope'] = 'global';
      const written = executeMemoryToolCall('memory_update', writeArgs, memories, [], [], chat, persona, true);
      expect(written.memories?.[3].assistantId).assertEqual('a');
      const deleteArgs: Record<string, Object> = {};
      deleteArgs['id'] = 'other';
      const denied = executeMemoryToolCall('memory_delete', deleteArgs, memories, [], [], chat, persona, true);
      expect(denied.isError).assertTrue();
      chat.ephemeral = true;
      const tempWrite = executeMemoryToolCall('memory_update', writeArgs, memories, [], [], chat, persona, true);
      expect(tempWrite.isError).assertTrue();

      const past: Conversation = {
        id: 'past', title: '旧对话', updated: 1, personaId: 'a', messages: [{ id: 'q', role: 'user', text: '苹果派', model: '' }]
      };
      const other: Conversation = {
        id: 'foreign', title: '其他对话', updated: 2, personaId: 'b', messages: past.messages
      };
      const queryArgs: Record<string, Object> = {};
      queryArgs['query'] = '苹果派';
      const recall = executeMemoryToolCall('chat_search', queryArgs, [], [], [past, other], chat, persona, true);
      expect(recall.text).assertContain('旧对话');
      expect(recall.text.includes('其他对话')).assertFalse();
      expect(memoryTurnBatch(past.messages, 2)).assertEqual('');
    });

    it('ProviderHeadersReasoningAndPathSafety', 0, () => {
      const openCode = preset('oc', 'opencode', 'openai', 'https://opencode.ai/zen/go/v1', 'deepseek-v4.1-flash');
      openCode.secretRef = 'sec_oc';
      openCode.customHeaders = [{ key: 'X-Custom', value: 'yes' }, { key: 'X-OpenCode-Session', value: '' }];
      openCode.chatPath = 'v2/chat';
      openCode.sendConversationCacheKey = true;

      const call = makeAdvancedChatCall(openCode, 'k-oc', 'sys', [user], {
        conversationId: 'conv-42',
        customHeaders: [{ key: 'x-opencode-session', value: 'stale' }],
        params: { reasoningEffort: 'high', temperature: 0.7 }
      });
      expect(call.address).assertEqual('https://opencode.ai/zen/go/v1/v2/chat');
      expect(call.headers['x-opencode-session']).assertEqual('conv-42');
      expect(Object.keys(call.headers).filter((key: string): boolean =>
        key.toLowerCase() === 'x-opencode-session').length).assertEqual(1);
      expect(call.headers['User-Agent']).assertContain('kelivo');
      expect(call.headers['X-Custom']).assertEqual('yes');
      expect(call.body).assertContain('"thinking":{"type":"enabled"}');
      expect(call.body).assertContain('"reasoning_effort":"high"');
      expect(call.body).assertContain('"prompt_cache_key":"conv-42"');

      const autoUuidCall = makeAdvancedChatCall(openCode, 'k-oc', '', [user], {});
      expect(autoUuidCall.headers['x-opencode-session'].length).assertEqual(36);

      const importedGo = preset('go', 'OpenCode Go', 'openai-responses',
        'https://opencode.ai/zen/go/v1', 'deepseek-v4.1-flash');
      importedGo.chatPath = '/chat/completions';
      const chatCompletion = makeAdvancedChatCall(importedGo, 'test-key', '', [user], { conversationId: 'conv-42' });
      expect(chatCompletion.address).assertEqual('https://opencode.ai/zen/go/v1/chat/completions');
      expect(chatCompletion.body).assertContain('"messages"');
      expect(chatCompletion.body.includes('"input"')).assertFalse();
      expect(chatCompletion.headers['x-opencode-session']).assertEqual('conv-42');
      importedGo.chatPath = '/responses';
      const responseCall = makeAdvancedChatCall(importedGo, 'test-key', '', [user]);
      expect(responseCall.body).assertContain('"input"');

      const orProv = preset('or', 'OpenRouter', 'openai', 'https://openrouter.ai/api/v1', 'gpt-4o');
      const orCall = makeAdvancedChatCall(orProv, 'k-or', '', [user], {});
      expect(orCall.headers['X-OpenRouter-Title']).assertEqual('Kelivo');
      expect(orCall.headers['HTTP-Referer']).assertContain('kelivo');

      const claudeProv = preset('cl', 'Claude', 'anthropic', 'https://api.anthropic.com/v1', 'claude-sonnet-4');
      const reasonSpec = defaultModelSpec('claude-sonnet-4');
      const clCall = makeAdvancedChatCall(claudeProv, 'k-cl', 'sys', [user], {
        modelSpec: reasonSpec,
        params: { reasoningEffort: 'high', temperature: 0.7, topP: 0.9 },
        stream: false
      });
      expect(clCall.body).assertContain('"thinking"');
      expect(clCall.body).assertContain('"stream":false');
      expect(clCall.body.indexOf('"temperature"') < 0).assertTrue();
      expect(clCall.body.indexOf('"top_p"') < 0).assertTrue();

      const gemProv = preset('gm', 'Gemini', 'gemini', 'https://generativelanguage.googleapis.com/v1beta', 'gemini-2.0-flash');
      const gmCall = makeAdvancedChatCall(gemProv, 'k-gm', '', [user], {
        modelSpec: defaultModelSpec('gemini-2.0-flash'),
        params: { reasoningEffort: 'high' },
        stream: false
      });
      expect(gmCall.address).assertEqual('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent');
      expect(gmCall.body.indexOf('"thinkingConfig"') < 0).assertTrue();

      const nonStreamOpen = makeAdvancedChatCall(orProv, 'k-or', '', [user], { stream: false });
      expect(nonStreamOpen.body.indexOf('"stream_options"') < 0).assertTrue();

      const ws = initialWorkspace();
      const ollama = ws.providers.find((p) => p.id === 'ollama')!;
      expect(isProviderConfigured(ollama)).assertFalse();
      expect(isProviderConfigured(openCode)).assertTrue();

      ws.providers = [openCode, ...ws.providers];
      ws.modelDefaults!.chatProviderId = 'oc';
      ws.modelDefaults!.chatModelId = 'deepseek-v4.1-flash';
      const resolved = resolveActiveModel(ws);
      expect(resolved.provider.id).assertEqual('oc');
      expect(resolved.modelId).assertEqual('deepseek-v4.1-flash');
    });

    it('Argon2idRfc9106AndKelivoVector', 0, () => {
      const hex = (arr: Uint8Array): string => {
        const chars = '0123456789abcdef';
        let out = '';
        for (let i = 0; i < arr.length; i++) {
          const b = arr[i];
          out += chars.charAt((b >> 4) & 0xf) + chars.charAt(b & 0xf);
        }
        return out;
      };
      const pwd1 = new Uint8Array(32).fill(1);
      const salt1 = new Uint8Array(16).fill(2);
      const out1 = argon2id(pwd1, salt1, 32, 3, 4, 32);
      expect(hex(out1)).assertEqual('03aab965c12001c9d7d0d2de33192c0494b684bb148196d73c1df1acaf6d0c2e');

      const asciiBytes = (s: string): Uint8Array => {
        const b = new Uint8Array(s.length);
        for (let i = 0; i < s.length; i++) b[i] = s.charCodeAt(i);
        return b;
      };
      const out2 = argon2id(asciiBytes('password'), asciiBytes('somesalt12345678'), 19456, 2, 1, 32);
      expect(hex(out2)).assertEqual('0c4c0b6db219194b6006e078818a24eabea136f7af619a31930310e7f2d749a5');
    });

    it('BackupCodecScopeAndSecretsRoundTrip', 0, () => {
      const fullScope = defaultBackupScope();
      expect(countSelectedBackupScope(fullScope)).assertEqual(15);

      const src = initialWorkspace();
      const customProv = preset('my-custom', 'MyCustom', 'openai', 'https://api.example.com/v1', 'gpt-4o');
      customProv.secretRef = 'ref-main';
      customProv.apiKeys = [
        { id: 'k1', label: 'KeyA', secretRef: 'ref-pool-1', priority: 1, usageCount: 0, errorCount: 0, disabledUntil: 0 }
      ];
      customProv.proxy = { enabled: true, host: '127.0.0.1', port: 7890, username: 'u', passwordRef: 'ref-proxy' };
      src.providers = [customProv];
      src.mcpServers = [{
        id: 'mcp1', name: 'FS', transport: 'sse', endpoint: 'https://mcp.example.com/sse',
        bearerSecretRef: 'ref-mcp', customHeaders: [], enabled: true, disabledTools: [], autoApproveTools: []
      }];
      src.envVars = [{ id: 'ev1', key: 'GITHUB_TOKEN', secretRef: 'ref-env', masked: true }];
      src.conversations = [{
        id: 'conv-1', title: '测试对话', updated: 1700000000000, personaId: 'default',
        messages: [{ id: 'm1', role: 'user', text: 'hello', model: '', createdAt: 1700000000000 }]
      }];

      const secrets: Record<string, string> = {};
      secrets['ref-main'] = 'sk-primary-secret';
      secrets['ref-pool-1'] = 'sk-pool-secret';
      secrets['ref-proxy'] = 'proxy-pass';
      secrets['ref-mcp'] = 'mcp-token';
      secrets['ref-env'] = 'ghp_12345';

      // Export with chats excluded!
      const partialScope: BackupScopeConfig = normalizeBackupScope({ chats: false });
      expect(countSelectedBackupScope(partialScope)).assertEqual(14);
      const rawJson = buildHarmonyBackupJson(src, partialScope, secrets);
      const parsed = parseHarmonyBackupJson(rawJson);
      expect(parsed.sourceScope?.chats).assertFalse();
      expect(parsed.conversations === undefined).assertTrue();
      expect(parsed.secretsToStore['ref-main']).assertEqual('sk-primary-secret');

      // Target workspace already has a local conversation that must be preserved even in overwrite mode because chats wasn't backed up
      const dst = initialWorkspace();
      dst.conversations = [{
        id: 'local-only', title: '本地会话', updated: 1700000100000, personaId: 'default',
        messages: [{ id: 'lm1', role: 'user', text: 'keep me', model: '' }]
      }];
      let seq = 0;
      const res = applyScopedRestore(dst, parsed, defaultBackupScope(), 'overwrite', (): string => 'new-ref-' + (++seq));
      expect(res.workspace.conversations.length).assertEqual(1);
      expect(res.workspace.conversations[0].id).assertEqual('local-only');
      expect(res.workspace.providers[0].id).assertEqual('my-custom');
      const newMainRef = res.workspace.providers[0].secretRef;
      expect(newMainRef.startsWith('new-ref-')).assertTrue();
      expect(res.secretsToStore[newMainRef]).assertEqual('sk-primary-secret');
      const newEnvRef = res.workspace.envVars![0].secretRef;
      expect(res.secretsToStore[newEnvRef]).assertEqual('ghp_12345');

      // Verify full merge collision remaps conflicting conversation id instead of dropping
      const fullRaw = buildHarmonyBackupJson(src, defaultBackupScope(), secrets);
      const fullParsed = parseHarmonyBackupJson(fullRaw);
      const conflictTarget = initialWorkspace();
      conflictTarget.conversations = [{
        id: 'conv-1', title: '不同内容本地对话', updated: 1700000200000, personaId: 'default',
        messages: [
          { id: 'lx1', role: 'user', text: 'local prompt', model: '' },
          { id: 'lx2', role: 'assistant', text: 'local reply', model: 'm' }
        ]
      }];
      const merged = applyScopedRestore(conflictTarget, fullParsed, defaultBackupScope(), 'merge', (): string => 'm-' + (++seq));
      expect(merged.workspace.conversations.length).assertEqual(2);
      expect(merged.workspace.conversations[1].id.startsWith('conv-m-')).assertTrue();
    });

    it('BackupCodecAndroidSettingsAndChatsInterop', 0, () => {
      const ws = initialWorkspace();
      const prov = preset('opencode', 'opencode', 'openai', 'https://opencode.ai/zen/go/v1', 'deepseek-v4.1-flash');
      prov.secretRef = 'sec-oc';
      ws.providers = [prov];
      ws.personas[0].params = { reasoningEffort: 'high', reasoningBudget: 4096 };
      ws.personas[1].params = { reasoningEffort: 'off' };
      ws.personas[0].memoryEnabled = true;
      ws.personas[0].autoOrganizeMemory = true;
      ws.personas[0].memoryOrganizeEveryNTurns = 3;
      ws.personas[0].memoryFullInjectionTypes = ['tone'];
      ws.personas[0].memoryWriteScope = 'alwaysAssistant';
      ws.personas[0].allowPastConversationRecall = true;
      if (ws.memorySettings) ws.memorySettings.legacyMemories = ['请用中文'];
      ws.searchServices![2].endpoint = 'https://search.example.com';
      ws.memories = [{
        id: 'mem1', category: 'tone', content: '用中文', assistantId: 'default', archived: false,
        createdAt: 1700000001000, updatedAt: 1700000002000
      }];
      ws.userProfile = [{ id: 'profile1', key: 'preferred_name', value: 'Kelivo', updatedAt: 1700000003000 }];
      ws.envVars = [{ id: 'e1', key: 'API_TOKEN', secretRef: 'sec-env', masked: true }];
      ws.conversations = [{
        id: 'c-and', title: '跨端同步', updated: 1700000000000, pinned: true, personaId: 'default',
        messages: [
          { id: 'u1', role: 'user', text: '你好', model: '', createdAt: 1700000001000 },
          { id: 'a1', role: 'assistant', text: '哈喽', reasoning: '思考中', model: 'deepseek-v4.1-flash', createdAt: 1700000002000 }
        ]
      }];
      const secrets: Record<string, string> = {};
      secrets['sec-oc'] = 'oc-live-key';
      secrets['sec-env'] = 'tok-999';

      const settingsJson = buildAndroidSettingsJson(ws, defaultBackupScope(), secrets);
      const chatsJson = buildAndroidChatsJson(ws.conversations);

      const settings = JSON.parse(settingsJson) as Record<string, Object>;
      const assistants = JSON.parse(settings['assistants_v1'] as string) as Record<string, Object | null>[];
      const highReasoning = assistants[0]['reasoning'] as Record<string, Object>;
      expect(highReasoning['level']).assertEqual('high');
      expect(highReasoning['budgetTokens']).assertEqual(4096);
      const offReasoning = assistants[1]['reasoning'] as Record<string, Object | null>;
      expect(offReasoning['level']).assertEqual('off');
      expect(offReasoning['budgetTokens']).assertEqual(null);
      expect(assistants[2]['reasoning']).assertEqual(null);
      const searchServices = JSON.parse(settings['search_services_v1'] as string) as Record<string, Object>[];
      expect(searchServices[1]['type']).assertEqual('bing_local');
      expect(searchServices[2]['type']).assertEqual('searxng');
      expect(searchServices[2]['url']).assertEqual('https://search.example.com');
      const legacyMemories = JSON.parse(settings['assistant_memories_v1'] as string) as Record<string, Object>[];
      expect(legacyMemories.length).assertEqual(ws.personas.length);
      expect(legacyMemories[0]['id']).assertEqual(1);
      expect(legacyMemories[0]['assistantId']).assertEqual(ws.personas[0].id);
      expect(legacyMemories[0]['content']).assertEqual('请用中文');

      const parsedSettings = parseAndroidSettingsJson(settingsJson);
      expect(parsedSettings.providers?.length).assertEqual(1);
      expect(parsedSettings.personas?.[0].params?.reasoningEffort).assertEqual('high');
      expect(parsedSettings.personas?.[0].params?.reasoningBudget).assertEqual(4096);
      expect(parsedSettings.personas?.[1].params?.reasoningEffort).assertEqual('off');
      expect(parsedSettings.personas?.[2].params?.reasoningEffort).assertEqual(undefined);
      expect(parsedSettings.searchServices?.[1].kind).assertEqual('bing');
      expect(parsedSettings.searchServices?.[2].endpoint).assertEqual('https://search.example.com');
      expect(parsedSettings.memorySettings?.legacyMemories?.length).assertEqual(1);
      expect(parsedSettings.memorySettings?.legacyMemories?.[0]).assertEqual('请用中文');
      expect(parsedSettings.personas?.[0].memoryWriteScope).assertEqual('alwaysAssistant');
      expect(parsedSettings.personas?.[0].memoryFullInjectionTypes?.[0]).assertEqual('tone');
      expect(parsedSettings.personas?.[0].memoryOrganizeEveryNTurns).assertEqual(3);
      expect(parsedSettings.personas?.[0].allowPastConversationRecall).assertTrue();
      expect(parsedSettings.memories?.[0].updatedAt).assertEqual(1700000002000);
      expect(parsedSettings.memories?.[0].assistantId).assertEqual('default');
      expect(parsedSettings.userProfile?.[0].key).assertEqual('preferred_name');
      expect(parsedSettings.providers![0].id).assertEqual('opencode');
      const stagedRef = parsedSettings.providers![0].secretRef;
      expect(parsedSettings.secretsToStore[stagedRef]).assertEqual('oc-live-key');
      expect(parsedSettings.envVars?.length).assertEqual(1);
      expect(parsedSettings.secretsToStore[parsedSettings.envVars![0].secretRef]).assertEqual('tok-999');

      const parsedChats = parseAndroidChatsJson(chatsJson);
      expect(parsedChats.length).assertEqual(1);
      expect(parsedChats[0].pinned).assertTrue();
      expect(parsedChats[0].messages.length).assertEqual(2);
      expect(parsedChats[0].messages[1].text).assertEqual('哈喽');
      expect(parsedChats[0].messages[1].reasoning).assertEqual('思考中');
    });

    it('ThirdPartyCherryAndChatboxEnhancedImport', 0, () => {
      const cherryPersistMap: Record<string, string> = {};
      cherryPersistMap['llm'] = '{"providers":[{"id":"cs-ds","name":"CherryDeepSeek","type":"openai","apiKey":"sk-1, sk-2","apiHost":"https://api.deepseek.com","models":[{"id":"deepseek-chat"}]}]}';
      cherryPersistMap['assistants'] = '{"assistants":[{"id":"cs-asst","name":"翻译专家","prompt":"Translate cleanly","topics":[{"id":"tp-1","name":"英文润色"}]}]}';
      const cherryPersist = JSON.stringify(cherryPersistMap);
      const cherryRaw = '{"version":5,"localStorage":{"persist:cherry-studio":' + JSON.stringify(cherryPersist) + '},' +
        '"indexedDB":{"topics":[{"id":"tp-1","messages":[{"id":"cm1","role":"assistant","model":{"id":"deepseek-chat"}}]}],' +
        '"message_blocks":[{"type":"thinking","messageId":"cm1","content":"analyze grammar"},{"type":"main_text","messageId":"cm1","content":"Polished text"}]}}';
      const cherryParsed = detectAndParseThirdPartyJson(cherryRaw);
      expect(cherryParsed.providers?.length).assertEqual(1);
      expect(cherryParsed.providers![0].baseUrl).assertEqual('https://api.deepseek.com/v1');
      expect(cherryParsed.providers![0].apiKeys?.length).assertEqual(2);
      expect(cherryParsed.personas?.length).assertEqual(1);
      expect(cherryParsed.conversations![0].personaId).assertEqual('cs-asst');
      expect(cherryParsed.conversations![0].messages[0].text).assertEqual('Polished text');
      expect(cherryParsed.conversations![0].messages[0].reasoning).assertEqual('analyze grammar');

      const v2Files: Record<string, string> = {};
      v2Files['manifest.json'] = '{"format":"chatbox-backup","formatVersion":2,"exportedAt":"2026-01-01T00:00:00Z",' +
        '"data":{"settings":{"path":"settings.json"}},"sessions":[{"id":"cb-s1","path":"sessions/cb-s1.json","name":"编程对话","starred":true}]}';
      v2Files['settings.json'] = '{"providers":{"openai":{"apiKey":"sk-cb-v2","apiHost":"https://api.openai.com/v1","models":[{"modelId":"gpt-4o"}]}}}';
      v2Files['sessions/cb-s1.json'] = '{"id":"cb-s1","name":"编程对话","settings":{"provider":"openai","modelId":"gpt-4o"},' +
        '"messages":[{"id":"u1","role":"system","content":"Be helpful"},{"id":"u2","role":"user","content":"Write ArkTS"}]}';
      const assembled = assembleChatboxZipV2Json(v2Files);
      const cbParsed = detectAndParseThirdPartyJson(assembled);
      expect(cbParsed.providers?.length).assertEqual(1);
      expect(cbParsed.secretsToStore[cbParsed.providers![0].secretRef]).assertEqual('sk-cb-v2');
      expect(cbParsed.personas![0].prompt).assertEqual('Be helpful');
      expect(cbParsed.conversations![0].pinned).assertTrue();
      expect(cbParsed.conversations![0].messages[0].text).assertEqual('Write ArkTS');
    });

    it('S3SigV4SessionTokenAndXmlOrder', 0, () => {
      const hdrs: Record<string, string> = {};
      hdrs['host'] = 's3.example.com';
      hdrs['x-amz-date'] = '20260101T000000Z';
      hdrs['x-amz-security-token'] = 'sts-tok-123';
      const canonical = buildS3CanonicalRequest('GET', '/bucket/file.zip', { 'list-type': '2' }, hdrs, 'UNSIGNED-PAYLOAD');
      expect(canonical.signedHeaders).assertContain('x-amz-security-token');
      expect(canonical.canonicalHeaders).assertContain('x-amz-security-token:sts-tok-123');
      const parsedXml = parseS3ListXml('<ListBucketResult><Contents><Key>a.kbackup</Key><Size>42</Size><LastModified>2026-01-01T00:00:00Z</LastModified></Contents></ListBucketResult>');
      expect(parsedXml.length).assertEqual(1);
      expect(parsedXml[0].key).assertEqual('a.kbackup');
      expect(parsedXml[0].size).assertEqual(42);
    });

    it('Zip64AndroidStreamingDirectoryParsing', 0, () => {
      // 1. Android Kelivo _StreamingZipWriter ZIP64 EOCD + ZIP64 Locator + sentinel EOCD + UTF-8 filename
      // "upload/对话延续摘要(1).md" UTF-8 bytes
      const nameBytes = new Uint8Array([
        0x75, 0x70, 0x6c, 0x6f, 0x61, 0x64, 0x2f,
        0xe5, 0xaf, 0xb9, 0xe8, 0xaf, 0x9d, 0xe5, 0xbb, 0xb6, 0xe7, 0xbb, 0xad,
        0xe6, 0x91, 0x98, 0xe8, 0xa6, 0x81, 0x28, 0x31, 0x29, 0x2e, 0x6d, 0x64
      ]);
      // ZIP64 extra field (0x0001): header(4) + 8-byte uncompSize + 8-byte compSize + 8-byte localOffset = 28 bytes
      const cdEntryLen = 46 + nameBytes.length + 28;
      const cdOffset = 30; // pretend 30 bytes local data before CD
      const zip64EocdOff = cdOffset + cdEntryLen;
      const locatorOff = zip64EocdOff + 56;
      const eocdOff = locatorOff + 20;
      const z64 = new Uint8Array(eocdOff + 22);
      const dv = new DataView(z64.buffer);

      // Central Directory Header with 0xffffffff sentinels pointing to ZIP64 extra field
      dv.setUint32(cdOffset, 0x02014b50, true);
      dv.setUint16(cdOffset + 4, 45, true);
      dv.setUint16(cdOffset + 6, 45, true);
      dv.setUint16(cdOffset + 8, 0x0808, true);
      dv.setUint16(cdOffset + 10, 8, true);
      dv.setUint32(cdOffset + 16, 0x12345678, true);
      dv.setUint32(cdOffset + 20, 0xffffffff, true);
      dv.setUint32(cdOffset + 24, 0xffffffff, true);
      dv.setUint16(cdOffset + 28, nameBytes.length, true);
      dv.setUint16(cdOffset + 30, 28, true);
      dv.setUint32(cdOffset + 42, 0xffffffff, true);
      z64.set(nameBytes, cdOffset + 46);
      const exOff = cdOffset + 46 + nameBytes.length;
      dv.setUint16(exOff, 0x0001, true);
      dv.setUint16(exOff + 2, 24, true);
      dv.setUint32(exOff + 4, 56086528, true); // uncomp lo
      dv.setUint32(exOff + 8, 0, true);
      dv.setUint32(exOff + 12, 21897823, true); // comp lo
      dv.setUint32(exOff + 16, 0, true);
      dv.setUint32(exOff + 20, 174286, true); // localOffset lo
      dv.setUint32(exOff + 24, 0, true);

      // ZIP64 EOCD (56 bytes)
      dv.setUint32(zip64EocdOff, 0x06064b50, true);
      dv.setUint32(zip64EocdOff + 4, 44, true);
      dv.setUint16(zip64EocdOff + 12, 45, true);
      dv.setUint16(zip64EocdOff + 14, 45, true);
      dv.setUint32(zip64EocdOff + 16, 0, true);
      dv.setUint32(zip64EocdOff + 20, 0, true);
      dv.setUint32(zip64EocdOff + 24, 1, true);
      dv.setUint32(zip64EocdOff + 32, 1, true);
      dv.setUint32(zip64EocdOff + 40, cdEntryLen, true);
      dv.setUint32(zip64EocdOff + 48, cdOffset, true);

      // ZIP64 EOCD Locator (20 bytes)
      dv.setUint32(locatorOff, 0x07064b50, true);
      dv.setUint32(locatorOff + 4, 0, true);
      dv.setUint32(locatorOff + 8, zip64EocdOff, true);
      dv.setUint32(locatorOff + 16, 1, true);

      // Standard EOCD with 0xffff / 0xffffffff sentinels (exact Android Kelivo behavior)
      dv.setUint32(eocdOff, 0x06054b50, true);
      dv.setUint16(eocdOff + 4, 0, true);
      dv.setUint16(eocdOff + 6, 0xffff, true);
      dv.setUint16(eocdOff + 8, 0xffff, true);
      dv.setUint16(eocdOff + 10, 0xffff, true);
      dv.setUint32(eocdOff + 12, 0xffffffff, true);
      dv.setUint32(eocdOff + 16, 0xffffffff, true);

      const z64Entries = listZipEntries(z64);
      expect(z64Entries.length).assertEqual(1);
      expect(z64Entries[0].name).assertEqual('upload/对话延续摘要(1).md');
      expect(z64Entries[0].size).assertEqual(56086528);
      expect(z64Entries[0].compressedSize).assertEqual(21897823);
      expect(z64Entries[0].localOffset).assertEqual(174286);
      expect(findZipEntry(z64Entries, './upload/对话延续摘要(1).md')?.method).assertEqual(8);
      expect(normalizeZipEntryPath('/database\\kelivo.db')).assertEqual('database/kelivo.db');

      // 2. Standard ZIP32 entry listing
      const cdName = new Uint8Array([0x73, 0x65, 0x74, 0x74, 0x69, 0x6e, 0x67, 0x73, 0x2e, 0x6a, 0x73, 0x6f, 0x6e]);
      const z32CdLen = 46 + cdName.length;
      const z32 = new Uint8Array(z32CdLen + 22);
      const dv32 = new DataView(z32.buffer);
      dv32.setUint32(0, 0x02014b50, true);
      dv32.setUint16(10, 0, true);
      dv32.setUint32(20, 12, true);
      dv32.setUint32(24, 12, true);
      dv32.setUint16(28, cdName.length, true);
      z32.set(cdName, 46);
      dv32.setUint32(z32CdLen, 0x06054b50, true);
      dv32.setUint16(z32CdLen + 8, 1, true);
      dv32.setUint16(z32CdLen + 10, 1, true);
      dv32.setUint32(z32CdLen + 12, z32CdLen, true);
      dv32.setUint32(z32CdLen + 16, 0, true);
      const z32Entries = listZipEntries(z32);
      expect(z32Entries.length).assertEqual(1);
      expect(z32Entries[0].name).assertEqual('settings.json');
      expect(z32Entries[0].size).assertEqual(12);

      // 3. Multi-disk ZIP32 rejected & corrupt buffer rejected
      let rejectedSplit = false;
      dv32.setUint16(z32CdLen + 6, 1, true);
      try { listZipEntries(z32); } catch (_) { rejectedSplit = true; }
      expect(rejectedSplit).assertTrue();

      let rejectedCorrupt = false;
      try { listZipEntries(new Uint8Array([0x50, 0x4b, 0x03, 0x04, 0x00, 0x00])); } catch (_) { rejectedCorrupt = true; }
      expect(rejectedCorrupt).assertTrue();
    });

    it('ApiHttp400HardeningAndToolSchema', 0, () => {
      // 1. DeepSeek imported as openai-responses with /chat/completions path must send Chat Completions body
      const ds = preset('ds', 'DeepSeek', 'openai-responses', 'https://api.deepseek.com/v1', 'deepseek-v4-pro');
      ds.chatPath = '/chat/completions';
      const dsCall = makeAdvancedChatCall(ds, 'sk-ds', 'sys', [user], {
        params: { reasoningEffort: 'high', temperature: 0.7 }
      });
      expect(dsCall.address).assertEqual('https://api.deepseek.com/v1/chat/completions');
      expect(dsCall.body).assertContain('"messages"');
      expect(dsCall.body.includes('"input"')).assertFalse();
      expect(dsCall.body).assertContain('"thinking":{"type":"enabled"}');
      expect(dsCall.body).assertContain('"reasoning_effort":"high"');
      expect(dsCall.body.includes('"reasoning":{')).assertFalse();

      // 2. Anthropic must not send both temperature and top_p, and merges consecutive same-role turns
      const cl = preset('cl2', 'Claude', 'anthropic', 'https://api.anthropic.com/v1', 'claude-haiku-4-5');
      const u1: ChatMessage = { id: 'u1', role: 'user', text: 'first', model: '' };
      const u2: ChatMessage = { id: 'u2', role: 'user', text: 'second', model: '' };
      const clCall = makeAdvancedChatCall(cl, 'sk-cl', 'sys', [u1, u2], {
        params: { temperature: 0.7, topP: 1.0, reasoningEffort: 'off' }
      });
      expect(clCall.body).assertContain('"temperature":0.7');
      expect(clCall.body.includes('"top_p"')).assertFalse();
      expect(clCall.body).assertContain('first\\n\\nsecond');

      // 3. Gemini 2.x omits empty object parameters, prioritizes googleSearch when builtinSearch is on, and does not mix with functionDeclarations
      const gm = preset('gm2', 'Gemini', 'gemini', 'https://generativelanguage.googleapis.com/v1beta', 'gemini-2.5-flash');
      gm.builtinSearch = false;
      const gmFnCall = makeAdvancedChatCall(gm, 'AIza-test', 'sys', [u1], {
        tools: [{ name: 'get_time_info', description: 'time', parametersJson: '{"type":"object","properties":{}}' }]
      });
      expect(gmFnCall.body).assertContain('"functionDeclarations"');
      expect(gmFnCall.body.includes('"parameters"')).assertFalse();
      expect(gmFnCall.body.includes('"googleSearch"')).assertFalse();

      gm.builtinSearch = true;
      const gmSearchCall = makeAdvancedChatCall(gm, 'AIza-test', 'sys', [u1], {
        tools: [{ name: 'get_time_info', description: 'time', parametersJson: '{"type":"object","properties":{}}' }]
      });
      expect(gmSearchCall.body).assertContain('"googleSearch"');
      expect(gmSearchCall.body.includes('"functionDeclarations"')).assertFalse();

      // 4. OpenAI Responses ChatGPT codex sets store:false, omits temp/top_p/summary, preserves call_id across deltas
      const codex = preset('cg', 'ChatGPT', 'openai-responses', 'https://chatgpt.com/backend-api/codex', 'gpt-5.4');
      const codexCall = makeAdvancedChatCall(codex, 'tok', '', [u1], {
        params: { temperature: 0.7, topP: 1.0, reasoningEffort: 'medium', maxTokens: 4096 }
      });
      expect(codexCall.body).assertContain('"store":false');
      expect(codexCall.body).assertContain('"instructions"');
      expect(codexCall.body.includes('"temperature"')).assertFalse();
      expect(codexCall.body.includes('"top_p"')).assertFalse();
      expect(codexCall.body.includes('"summary"')).assertFalse();
      expect(codexCall.body.includes('"max_output_tokens"')).assertFalse();

      const added = parseRichReply('{"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","id":"fc_1","call_id":"call_real_9","name":"search","arguments":""}}');
      const delta = parseRichReply('{"type":"response.function_call_arguments.delta","output_index":0,"item_id":"fc_1","delta":"{\\"q\\":\\"x\\"}"}');
      const acc = accumulateToolDeltas(accumulateToolDeltas([], added.toolCalls), delta.toolCalls);
      expect(acc[0].id).assertEqual('call_real_9');
      expect(acc[0].argsJson).assertEqual('{"q":"x"}');
    });

    it('MemoryPipelineAndAndroidAlignment', 0, () => {
      // 1. Microsecond timestamp normalization & missing profile key recovery
      expect(normalizeMemoryTimestamp(1791646106563900)).assertEqual(1791646106563);
      expect(memoryDate(1791646106563900)).assertEqual('2026-10-10');

      const androidProfile: UserProfileField[] = [
        { id: 'gender', key: '', value: '男', updatedAt: 1791646106563900 },
        { id: 'location', key: '', value: '北京', updatedAt: 1791686884105712 }
      ];
      const normProf = normalizeUserProfileFields(androidProfile);
      expect(normProf[0].key).assertEqual('gender');
      expect(normProf[0].updatedAt).assertEqual(1791646106563);
      const profXml = buildProfileBlock(androidProfile);
      expect(profXml).assertContain('<gender>男</gender>');
      expect(profXml).assertContain('<location>北京</location>');

      // 2. XML Gatekeeper / Extract / Smart Add / Profile Distiller parsers
      expect(parseGatekeeperXml('<gate><user_memory>true</user_memory></gate>')).assertTrue();
      expect(parseGatekeeperXml('<gate><user_memory>false</user_memory></gate>')).assertFalse();

      const ext = parseExtractedMemoriesXml('<extracted><item type="identity">用户在上海从事软件工程</item><item type="voice">用户偏好简洁的代码回复</item></extracted>');
      expect(ext.length).assertEqual(2);
      expect(ext[0].category).assertEqual('identity');
      expect(ext[1].category).assertEqual('tone');

      const decisions = parseSmartAddBatchResponse('{"results":[{"index":1,"action":"CONFLICT","targetId":"m_old","mergedContent":null,"relatedIds":["m_rel"]},{"index":2,"action":"SKIP","targetId":"m_same","mergedContent":null,"relatedIds":[]}]}');
      expect(decisions.get(1)?.action).assertEqual('CONFLICT');
      const existing: MemoryEntry[] = [
        { id: 'm_old', category: 'identity', content: '用户在北京工作', archived: false, createdAt: 1000, updatedAt: 1000 },
        { id: 'm_same', category: 'tone', content: '用户偏好简洁的代码回复', archived: false, createdAt: 1000, updatedAt: 1000 },
        { id: 'm_orphan', category: 'instruction', content: '孤立条目', assistantId: 'deleted_asst', archived: false, createdAt: 1000, updatedAt: 1000 }
      ];
      const applied = applySmartAddDecisions(existing, ext, decisions, 'conv_1', undefined, 'extracted');
      expect(applied.addedCount).assertEqual(1);
      expect(applied.conflictCount).assertEqual(1);
      expect(applied.skippedCount).assertEqual(1);
      expect(applied.entries.find((e): boolean => e.id === 'm_old')?.archived).assertTrue();

      const distilled = parseProfileDistillerResponse('{"fields":[{"key":"location","value":"上海"}]}');
      expect(distilled.length).assertEqual(1);
      expect(distilled[0].value).assertEqual('上海');

      const orphans = findOrphanedMemories(existing, [{ id: 'a1', name: 'A1', prompt: '' }]);
      expect(orphans.length).assertEqual(1);
      expect(orphans[0].id).assertEqual('m_orphan');

      const rulesZh = buildMemoryRulesSystemPrompt({ autoExtract: false, injectGlobal: true, maxInjectCount: 100, promptLanguage: 'zh' }, 'en');
      expect(rulesZh).assertContain('## 长期记忆');

      // 3. Android settings.json memory & assistant fields import
      const rawSettings = JSON.stringify({
        memory_injection_max_items_v1: 100,
        memory_legacy_mode_v1: false,
        memory_model_thinking_enabled_v1: true,
        memory_model_v1: 'OpenAI - openCode::deepseek-v4.1-flash',
        memory_gate_prompt_zh_v1: '<gate>{{conversation}}</gate>',
        assistants_v1: JSON.stringify([{
          id: 'a1',
          name: '故事助手',
          reasoning: 'medium',
          enableMemory: true,
          autoOrganizeMemory: true,
          memoryOrganizeEveryNTurns: 2,
          memorySmartAddMode: 'batched',
          memoryWriteScope: 'alwaysAssistant',
          allowPastConversationRecall: true,
          generateConversationSummary: true,
          recentChatsSummaryMessageCount: 3,
          allowConversationSystemPrompt: true,
          allowConversationPromptInjection: true,
          appendCurrentTimeToUserMessage: true,
          useGradientBackground: true,
          limitContextMessages: false,
          contextMessageSize: 64,
          localToolIds: ['ask_user_input_v0', 'calculator', 'time_info']
        }]),
        user_profile_fields_v1: JSON.stringify([{ id: 'gender', value: '男', source: 'distilled', updatedAt: 1791646106563900 }])
      });
      const parsedBackup = parseAndroidSettingsJson(rawSettings);
      expect(parsedBackup.memorySettings?.maxInjectCount).assertEqual(100);
      expect(parsedBackup.memorySettings?.enableThinking).assertTrue();
      expect(parsedBackup.memorySettings?.templates?.gateZh).assertEqual('<gate>{{conversation}}</gate>');
      expect(parsedBackup.modelDefaults?.memoryProviderId).assertEqual('OpenAI - openCode');
      expect(parsedBackup.modelDefaults?.memoryModelId).assertEqual('deepseek-v4.1-flash');
      expect(parsedBackup.personas?.[0].memorySmartAddMode).assertEqual('batched');
      expect(parsedBackup.personas?.[0].generateConversationSummary).assertTrue();
      expect(parsedBackup.personas?.[0].recentChatsSummaryMessageCount).assertEqual(3);
      expect(parsedBackup.personas?.[0].allowConversationSystemPrompt).assertTrue();
      expect(parsedBackup.personas?.[0].appendCurrentTimeToUserMessage).assertTrue();
      expect(parsedBackup.personas?.[0].params?.contextLimit).assertEqual(undefined);
      expect(parsedBackup.personas?.[0].params?.reasoningEffort).assertEqual('medium');
      expect(parsedBackup.personas?.[0].builtinTools?.includes('ask_user_input')).assertTrue();
      expect(parsedBackup.personas?.[0].builtinTools?.includes('calculate')).assertTrue();
      expect(parsedBackup.userProfile?.[0].key).assertEqual('gender');

      // 4. Single-brace Android prompt variable expansion
      const fixedNow = new Date(2026, 10, 22, 14, 5, 9);
      const expanded = expandPromptTemplates(
        'Date:{cur_date} Time:{cur_time} DT:{cur_datetime} Model:{model_id} User:{nickname} Asst:{assistant_name}',
        { now: fixedNow, userName: 'Miles', assistantName: '故事1.4', modelName: 'deepseek-v4.1-flash' }
      );
      expect(expanded).assertEqual('Date:2026-11-22 Time:14:05:09 DT:2026-11-22 14:05:09 Model:deepseek-v4.1-flash User:Miles Asst:故事1.4');
    });

    it('MessageVersionDeleteEditAndTranslation', 0, () => {
      const base: ChatMessage = {
        id: 'm_v1',
        role: 'assistant',
        text: '版本一',
        reasoning: '思考一',
        model: 'deepseek-v4.1-flash',
        createdAt: 1000,
        usage: { promptTokens: 100, completionTokens: 20, cachedTokens: 0, totalTokens: 120, durationMs: 300 }
      };
      expect(deleteMessageVersion(base)).assertEqual(undefined);

      const twoVers = appendMessageVersion(base, {
        id: 'm_v2',
        text: '版本二',
        reasoning: '思考二',
        model: 'deepseek-v4.1-flash',
        createdAt: 2000,
        usage: { promptTokens: 110, completionTokens: 25, cachedTokens: 0, totalTokens: 135, durationMs: 250 }
      });
      expect(twoVers.versions?.length).assertEqual(2);
      expect(twoVers.activeVersion).assertEqual(1);
      expect(twoVers.text).assertEqual('版本二');

      const editedTwo = updateActiveMessageVersionText(twoVers, '版本二已编辑');
      expect(editedTwo.text).assertEqual('版本二已编辑');
      expect(editedTwo.versions?.[1].text).assertEqual('版本二已编辑');
      expect(editedTwo.versions?.[0].text).assertEqual('版本一');

      const translatedTwo = updateActiveMessageVersionTranslation(editedTwo, 'Version two edited');
      expect(translatedTwo.translation).assertEqual('Version two edited');
      expect(translatedTwo.versions?.[1].translation).assertEqual('Version two edited');

      // Delete active version (index 1) -> returns single remaining version 1 with multi-version array cleared
      const afterDel2 = deleteMessageVersion(translatedTwo);
      expect(afterDel2 !== undefined).assertTrue();
      expect(afterDel2!.text).assertEqual('版本一');
      expect(afterDel2!.versions).assertEqual(undefined);
      expect(afterDel2!.activeVersion).assertEqual(undefined);

      // Delete first of 3 versions -> stays multi-version (2 remaining) focused on index 0 ('版本二')
      const threeVers = appendMessageVersion(twoVers, {
        id: 'm_v3',
        text: '版本三',
        reasoning: '',
        model: 'deepseek-v4.1-flash',
        createdAt: 3000
      });
      const switched0 = switchMessageVersion(threeVers, 0);
      expect(switched0.text).assertEqual('版本一');
      const afterDel0 = deleteMessageVersion(switched0);
      expect(afterDel0 !== undefined).assertTrue();
      expect(afterDel0!.versions?.length).assertEqual(2);
      expect(afterDel0!.activeVersion).assertEqual(0);
      expect(afterDel0!.text).assertEqual('版本二');
    });

    it('MemoryPipelineRobustnessAndCompleteness', 0, () => {
      // 1. 3-state Gatekeeper parsing
      expect(parseGatekeeperResult('<gate><user_memory>true</user_memory></gate>')).assertEqual('worthRemembering');
      expect(parseGatekeeperResult('<gate><user_memory>false</user_memory></gate>')).assertEqual('skip');
      expect(parseGatekeeperResult('')).assertEqual('malformed');
      expect(parseGatekeeperResult('我来帮你分析一下这段对话')).assertEqual('malformed');
      expect(parseGatekeeperResult('<gate>\n  <user_memory>true')).assertEqual('worthRemembering');

      // 2. Extract parsing: self-closing valid empty, malformed prose/empty, attribute ordering + scope
      const selfClosing = parseExtractedMemoriesResult('<extracted/>');
      expect(selfClosing.ok).assertTrue();
      expect(selfClosing.items.length).assertEqual(0);
      expect(parseExtractedMemoriesResult('').ok).assertFalse();
      expect(parseExtractedMemoriesResult('没有找到').ok).assertFalse();

      const scopedExt = parseExtractedMemoriesResult(
        '<extracted><item scope="assistant" type="identity">用户正在撰写北京故事</item><item type="voice">偏好克制平实的文风</item></extracted>'
      );
      expect(scopedExt.ok).assertTrue();
      expect(scopedExt.items.length).assertEqual(2);
      expect(scopedExt.items[0].category).assertEqual('identity');
      expect(scopedExt.items[0].scope).assertEqual('assistant');
      expect(scopedExt.items[1].category).assertEqual('tone');
      expect(scopedExt.items[1].scope).assertEqual(undefined);

      // 3. Batch windowing: trailing user turn, manual already-organized fallback, 2000-char & 12000-char caps, English prefix
      const msgs: ChatMessage[] = [
        { id: 'u1', role: 'user', text: '喜欢喝冰美式', model: '' },
        { id: 'a1', role: 'assistant', text: '好的，记住了。', model: 'm' },
        { id: 'u2', role: 'user', text: '晚上十点后写稿', model: '' }
      ];
      // Auto mode stops at last assistant message and ignores trailing un-replied user message
      const autoWithTrailingUser = buildMemoryOrganizeBatch(msgs, 1, '', false, 'zh');
      expect(autoWithTrailingUser.endMessageId).assertEqual('a1');
      expect(autoWithTrailingUser.snippet).assertContain('用户：喜欢喝冰美式');
      expect(autoWithTrailingUser.snippet.includes('晚上十点后写稿')).assertFalse();

      // Auto mode returns empty when pending only has a trailing user message
      expect(buildMemoryOrganizeBatch(msgs, 1, 'a1', false, 'zh').snippet).assertEqual('');

      // Manual mode succeeds even when trailing user exists or watermark is already at the latest message
      const manualTrailing = buildMemoryOrganizeBatch(msgs, 1, '', true, 'zh');
      expect(manualTrailing.endMessageId).assertEqual('u2');
      expect(manualTrailing.snippet).assertContain('晚上十点后写稿');

      const allComplete: ChatMessage[] = msgs.slice(0, 2);
      const manualAlreadyDone = buildMemoryOrganizeBatch(allComplete, 1, 'a1', true, 'en');
      expect(manualAlreadyDone.endMessageId).assertEqual('a1');
      expect(manualAlreadyDone.snippet).assertContain('User: 喜欢喝冰美式');
      expect(manualAlreadyDone.snippet).assertContain('Assistant: 好的，记住了。');

      const longUserText = '甲'.repeat(2100);
      const longTurn: ChatMessage[] = [
        { id: 'lu1', role: 'user', text: longUserText, model: '' },
        { id: 'la1', role: 'assistant', text: '收到', model: 'm' }
      ];
      const clippedBatch = buildMemoryOrganizeBatch(longTurn, 1, '', false, 'zh');
      expect(clippedBatch.snippet).assertContain(`${'甲'.repeat(2000)}…`);

      // 4. Smart Add candidates: pads to 5 recent same-category entries even on low token similarity
      const pool: MemoryEntry[] = [
        { id: 'm1', category: 'identity', content: '居住城市为北京', archived: false, createdAt: 100, updatedAt: 100 },
        { id: 'm2', category: 'identity', content: '职业是产品设计师', archived: false, createdAt: 200, updatedAt: 200 },
        { id: 'm3', category: 'identity', content: '养了一只狸花猫', archived: false, createdAt: 300, updatedAt: 300 },
        { id: 'm4', category: 'identity', content: '周末喜欢爬山', archived: false, createdAt: 400, updatedAt: 400 },
        { id: 'm5', category: 'identity', content: '早起会喝黑咖啡', archived: false, createdAt: 500, updatedAt: 500 },
        { id: 'm6', category: 'identity', content: '最近在学摄影', archived: false, createdAt: 600, updatedAt: 600 },
        { id: 'mw1', category: 'workflow', content: '习惯用键盘快捷键', archived: false, createdAt: 700, updatedAt: 700 }
      ];
      const smartCands = findSmartAddCandidates(pool, '日常使用左手写字', 'identity', undefined, true, 5);
      expect(smartCands.length).assertEqual(5);
      expect(smartCands.some((e: MemoryEntry): boolean => e.id === 'mw1')).assertFalse();

      // 5. Scope isolation + identityChanged tracking in applySmartAddDecisions
      const crossScopeDecisions = new Map<number, SmartAddDecision>();
      crossScopeDecisions.set(1, { action: 'MERGE', targetId: 'm1', mergedContent: '不应该篡改全局', relatedIds: [] });
      const crossApplied = applySmartAddDecisions(
        pool,
        [{ category: 'identity', content: '助手内独有身份信息', scope: 'assistant' }],
        crossScopeDecisions,
        'conv_x',
        'asst_a',
        'extracted',
        ['asst_a']
      );
      expect(crossApplied.entries.find((e: MemoryEntry): boolean => e.id === 'm1')?.content).assertEqual('居住城市为北京');
      expect(crossApplied.addedCount).assertEqual(1);
      expect(crossApplied.identityChanged).assertTrue();

      const skipDecs = new Map<number, SmartAddDecision>();
      skipDecs.set(1, { action: 'SKIP', targetId: 'm1', relatedIds: [] });
      const skipApplied = applySmartAddDecisions(
        pool,
        [{ category: 'identity', content: '居住城市为北京' }],
        skipDecs,
        'conv_x',
        undefined,
        'extracted',
        [undefined]
      );
      expect(skipApplied.identityChanged).assertFalse();

      // 6. Unlimited max_tokens for OpenAI reasoning vs Anthropic default; past-recall rules prompt
      const reasoningProv = preset('ds', 'DeepSeek', 'openai', 'https://api.deepseek.com/v1', 'deepseek-v4.1-flash');
      const unlimitedCall = makeAdvancedChatCall(reasoningProv, 'k-ds', '', [{ id: 'u', role: 'user', text: 'hi', model: '' }], {
        modelId: 'deepseek-v4.1-flash',
        params: { reasoningEffort: 'medium' }
      });
      expect(unlimitedCall.body.indexOf('"max_tokens"') < 0).assertTrue();
      expect(unlimitedCall.body.indexOf('"temperature"') < 0).assertTrue();

      const claudeProv = preset('cl', 'Claude', 'anthropic', 'https://api.anthropic.com/v1', 'claude-haiku-5-5');
      const claudeCall = makeAdvancedChatCall(claudeProv, 'k-cl', '', [{ id: 'u', role: 'user', text: 'hi', model: '' }], {
        modelId: 'claude-haiku-5-5',
        params: { reasoningEffort: 'medium' }
      });
      expect(claudeCall.body).assertContain('"max_tokens":4096');
      expect(claudeCall.body).assertContain('"output_config":{"effort":"medium"}');

      const xmlBlock = buildExistingMemoryXmlBlock(pool, { autoExtract: true, injectGlobal: true, maxInjectCount: 10 }, undefined, 'zh');
      expect(xmlBlock).assertContain('<user_memory type="identity">');
      const recallRules = buildMemoryRulesSystemPrompt({ autoExtract: true, injectGlobal: true, maxInjectCount: 10, promptLanguage: 'zh' }, 'zh-Hans', true);
      expect(recallRules).assertContain('chat_search');
    });

    it('ReasoningPresetsReplaceCustomBudgetInOutgoingRequests', 0, () => {
      const legacy = withReasoning(defaultGenerationParams(), 'medium', 8192);
      const options = (p: Provider, effort: ReasoningEffort, budget?: number): string => {
        return makeAdvancedChatCall(p, 'test', '', [user], {
          params: withReasoning(legacy, effort, budget)
        }).body;
      };
      const claude = preset('cl', 'Claude', 'anthropic', 'https://api.anthropic.com/v1', 'claude-sonnet-4');
      expect(options(claude, 'low')).assertContain('"budget_tokens":1024');
      expect(options(claude, 'medium')).assertContain('"budget_tokens":4096');
      expect(options(claude, 'high')).assertContain('"budget_tokens":8192');
      expect(options(claude, 'high', 6144)).assertContain('"budget_tokens":6144');
      expect(options(claude, 'off')).assertContain('"thinking":{"type":"disabled"}');
      const gem = preset('gem', 'Gemini', 'gemini', 'https://model.test', 'gemini-2.5-flash');
      expect(options(gem, 'low')).assertContain('"thinkingBudget":1024');
      expect(options(gem, 'max', 32768)).assertContain('"thinkingBudget":24576');
      gem.customBodyJson = '{"generationConfig":{"responseMimeType":"application/json"}}';
      expect(options(gem, 'high')).assertContain('"thinkingBudget":8192');
      const qwen = preset('qw', 'Qwen', 'openai', 'https://dashscope.aliyuncs.com/v1', 'qwen3-32b');
      expect(options(qwen, 'low')).assertContain('"thinking_budget":1024');
      expect(options(qwen, 'high')).assertContain('"thinking_budget":8192');
      expect(options(qwen, 'off').includes('"thinking_budget"')).assertFalse();
    });

    it('ModelReasoningControlsMatchWireProtocol', 0, () => {
      const request = (p: Provider, effort: ReasoningEffort): string => makeAdvancedChatCall(p, 'test', '', [user], {
        params: withReasoning(defaultGenerationParams(), effort, 8192), stream: false
      }).body;
      const gpt = preset('oa', 'OpenAI', 'openai', 'https://api.openai.com/v1', 'gpt-5.4');
      const chat = request(gpt, 'max');
      expect(chat).assertContain('"reasoning_effort":"xhigh"');
      expect(chat).assertContain('"max_completion_tokens":4096');
      expect(chat.includes('"temperature"')).assertFalse();
      gpt.family = 'openai-responses';
      expect(request(gpt, 'max')).assertContain('"reasoning":{"effort":"xhigh"}');
      expect(request(gpt, 'off')).assertContain('"reasoning":{"effort":"none"}');
      const cl = preset('cl', 'Claude', 'anthropic', 'https://api.anthropic.com/v1', 'claude-sonnet-4-6');
      expect(request(cl, 'max')).assertContain('"output_config":{"effort":"max"}');
      expect(request(cl, 'low')).assertContain('"thinking":{"type":"adaptive"}');
      expect(request(cl, 'high').includes('budget_tokens')).assertFalse();
      const gem = preset('g', 'Gemini', 'vertex', 'https://model.test', 'gemini-3-flash-preview');
      expect(request(gem, 'low')).assertContain('"thinkingLevel":"LOW"');
      expect(request(gem, 'high')).assertContain('"thinkingLevel":"HIGH"');
      expect(request(gem, 'off')).assertContain('"thinkingLevel":"MINIMAL"');
      expect(request(gem, 'max').includes('thinkingBudget')).assertFalse();
      const ds = preset('ds', 'DeepSeek', 'openai-responses', 'https://api.deepseek.com/v1', 'deepseek-v4-pro');
      expect(request(ds, 'max')).assertContain('"reasoning":{"effort":"max"}');
      ds.family = 'anthropic';
      expect(request(ds, 'max')).assertContain('"output_config":{"effort":"max"}');
      const glm = preset('z', 'GLM', 'openai', 'https://model.test', 'glm-4.7');
      const control = reasoningControl(glm, glm.model, defaultModelSpec(glm.model));
      expect(control.levels.join(',')).assertEqual('off,high');
      expect(control.budgetLimit).assertEqual(0);
      expect(request(glm, 'low')).assertContain('"thinking":{"type":"enabled"}');
      expect(request(glm, 'low').includes('reasoning_effort')).assertFalse();
      const ollama = preset('ollama', 'Ollama', 'openai', 'http://localhost:11434/v1', 'qwen3:8b');
      expect(request(ollama, 'off')).assertContain('"reasoning_effort":"none"');
      expect(request(ollama, 'high')).assertContain('"reasoning_effort":"high"');
      const alias = preset('alias', 'Custom', 'openai', 'https://model.test', 'private-model');
      expect(request(alias, 'high').includes('reasoning_effort')).assertFalse();
      alias.models![0].reasoning = true;
      expect(request(alias, 'high')).assertContain('"reasoning_effort":"high"');
    });

    it('ReasoningDialectsAndMemorySpeedOptimization', 0, () => {
      const msg: ChatMessage = { id: 'u1', role: 'user', text: 'hello', model: '' };

      // 1. DeepSeek thinkingType dialect & thinking-only protection
      const dsProv = preset('oc', 'opencode1', 'openai-responses', 'https://opencode.ai/zen/go/v1', 'deepseek-v4.1-flash');
      dsProv.chatPath = '/chat/completions';
      const dsOff = makeAdvancedChatCall(dsProv, 'k-oc', '', [msg], {
        modelId: 'deepseek-v4.1-flash',
        params: { reasoningEffort: 'off' }
      });
      expect(dsOff.body).assertContain('"thinking":{"type":"disabled"}');
      expect(dsOff.body.indexOf('"reasoning_effort"') < 0).assertTrue();

      const dsLow = makeAdvancedChatCall(dsProv, 'k-oc', '', [msg], {
        modelId: 'deepseek-v4.1-flash',
        params: { reasoningEffort: 'low' }
      });
      expect(dsLow.body).assertContain('"thinking":{"type":"enabled"}');
      expect(dsLow.body).assertContain('"reasoning_effort":"low"');

      const dsMedium = makeAdvancedChatCall(dsProv, 'k-oc', '', [msg], {
        modelId: 'deepseek-v4.1-flash',
        params: { reasoningEffort: 'medium' }
      });
      expect(dsMedium.body).assertContain('"thinking":{"type":"enabled"}');
      expect(dsMedium.body).assertContain('"reasoning_effort":"high"');

      const r1Off = makeAdvancedChatCall(dsProv, 'k-oc', '', [msg], {
        modelId: 'deepseek-r1',
        params: { reasoningEffort: 'off' }
      });
      expect(r1Off.body.indexOf('"disabled"') < 0).assertTrue();

      // 2. Qwen & QwQ
      const qwenProv = preset('qw', 'DashScope', 'openai', 'https://dashscope.aliyuncs.com/compatible-mode/v1', 'qwen3-32b');
      const qwenOff = makeAdvancedChatCall(qwenProv, 'k-qw', '', [msg], {
        modelId: 'qwen3-32b',
        params: { reasoningEffort: 'off' }
      });
      expect(qwenOff.body).assertContain('"enable_thinking":false');
      const qwenLow = makeAdvancedChatCall(qwenProv, 'k-qw', '', [msg], {
        modelId: 'qwen3-32b',
        params: { reasoningEffort: 'low' }
      });
      expect(qwenLow.body).assertContain('"enable_thinking":true');
      const qwqOff = makeAdvancedChatCall(qwenProv, 'k-qw', '', [msg], {
        modelId: 'qwq-32b',
        params: { reasoningEffort: 'off' }
      });
      expect(qwqOff.body.indexOf('"enable_thinking"') < 0).assertTrue();

      // 3. Gemini 2.5 Flash vs Pro & OpenAI Responses off
      const gemProv = preset('gm', 'Gemini', 'gemini', 'https://generativelanguage.googleapis.com/v1beta', 'gemini-2.5-flash');
      const gemFlashOff = makeAdvancedChatCall(gemProv, 'k-gm', '', [msg], {
        modelId: 'gemini-2.5-flash',
        params: { reasoningEffort: 'off' }
      });
      expect(gemFlashOff.body).assertContain('"thinkingBudget":0');
      expect(gemFlashOff.body).assertContain('"includeThoughts":false');
      const gemProOff = makeAdvancedChatCall(gemProv, 'k-gm', '', [msg], {
        modelId: 'gemini-2.5-pro',
        params: { reasoningEffort: 'off' }
      });
      expect(gemProOff.body.indexOf('"thinkingBudget":0') < 0).assertTrue();

      const respProv = preset('oa', 'OpenAI', 'openai-responses', 'https://api.openai.com/v1', 'gpt-5');
      const respOff = makeAdvancedChatCall(respProv, 'k-oa', '', [msg], {
        modelId: 'gpt-5',
        params: { reasoningEffort: 'off' }
      });
      expect(respOff.body).assertContain('"reasoning":{"effort":"minimal"}');

      // 4. Compact batch caps: <=10 msgs / 6000 chars initial auto, <=4 msgs / 4000 chars manual fallback
      const manyMsgs: ChatMessage[] = [];
      for (let i = 0; i < 14; i++) {
        manyMsgs.push({
          id: `m${i}`,
          role: i % 2 === 0 ? 'user' : 'assistant',
          text: `条目${i}: ` + '内容'.repeat(300),
          model: i % 2 === 0 ? '' : 'm'
        });
      }
      const initialAuto = buildMemoryOrganizeBatch(manyMsgs, 1, '', false, 'zh');
      expect(initialAuto.windowSize).assertEqual(10);
      expect(initialAuto.snippet.length <= 6001).assertTrue();

      const manualFallback = buildMemoryOrganizeBatch(manyMsgs, 1, 'm13', true, 'zh');
      expect(manualFallback.windowSize).assertEqual(4);
      expect(manualFallback.snippet.length <= 4001).assertTrue();

      // 5. buildExistingMemoryXmlBlock maxPerCategoryOverride = 25
      const largePool: MemoryEntry[] = [];
      for (let i = 0; i < 40; i++) {
        largePool.push({
          id: `id_${i}`,
          category: 'identity',
          content: `用户特征_${i}`,
          archived: false,
          createdAt: 1000 + i,
          updatedAt: 1000 + i
        });
      }
      const compactXml = buildExistingMemoryXmlBlock(
        largePool,
        { autoExtract: true, injectGlobal: true, maxInjectCount: 100 },
        undefined,
        'zh',
        [],
        25
      );
      expect(compactXml).assertContain('total="40" shown="25"');
    });

    it('background_generation_task_tracker_lifecycle_and_progress', 0, () => {
      const tracker = new GenerationTaskTracker();
      expect(tracker.activeCount()).assertEqual(0);
      expect(tracker.buildLiveProgressSummary(1000).activeCount).assertEqual(0);

      tracker.register('chat-a', '周报整理', 1000);
      expect(tracker.activeCount()).assertEqual(1);
      expect(tracker.has('chat-a')).assertTrue();

      tracker.update('chat-a', '周报整理', 'searching', 0, 2000);
      const sSearch = tracker.buildLiveProgressSummary(2000);
      expect(sSearch.title).assertEqual('正在后台生成 · 周报整理');
      expect(sSearch.detail).assertEqual('正在联网检索…');
      expect(sSearch.progressValue >= 1 && sSearch.progressValue <= 95).assertTrue();

      tracker.update('chat-a', '周报整理', 'thinking', 120, 4000);
      const sThink = tracker.buildLiveProgressSummary(4000);
      expect(sThink.detail).assertEqual('正在深度思考 · 已生成 120 字');
      expect(sThink.progressValue >= sSearch.progressValue).assertTrue();

      tracker.update('chat-a', '周报整理', 'tool', 120, 5000);
      expect(tracker.buildLiveProgressSummary(5000).detail).assertEqual('正在执行工具…');

      tracker.update('chat-a', '周报整理', 'image', 120, 6000);
      expect(tracker.buildLiveProgressSummary(6000).detail).assertEqual('正在生成图片…');

      tracker.update('chat-a', '周报整理', 'streaming', 640, 8000);
      const sStream = tracker.buildLiveProgressSummary(8000);
      expect(sStream.detail).assertEqual('已生成 640 字');
      expect(sStream.progressValue >= 1 && sStream.progressValue <= 95).assertTrue();

      // Multi-task aggregation
      tracker.register('chat-b', '代码分析', 9000);
      tracker.update('chat-b', '代码分析', 'streaming', 360, 10000);
      const sMulti = tracker.buildLiveProgressSummary(10000);
      expect(sMulti.activeCount).assertEqual(2);
      expect(sMulti.title).assertEqual('2 个对话正在后台生成');
      expect(sMulti.detail).assertEqual('已累计生成 1000 字');
      expect(sMulti.progressValue >= 1 && sMulti.progressValue <= 95).assertTrue();

      // Progress remains bounded <= 95 even under high elapsed time, large char count, and many ticks
      tracker.update('chat-b', '代码分析', 'streaming', 500000, 9999999);
      const sMax = tracker.buildLiveProgressSummary(9999999);
      expect(sMax.progressValue >= 85 && sMax.progressValue <= 95).assertTrue();
      let sCapped = sMax;
      for (let i = 0; i < 20; i++) {
        sCapped = tracker.buildLiveProgressSummary(9999999 + i * 1000);
      }
      expect(sCapped.progressValue).assertEqual(95);

      tracker.unregister('chat-a');
      expect(tracker.activeCount()).assertEqual(1);
      expect(tracker.has('chat-a')).assertFalse();
      expect(tracker.has('chat-b')).assertTrue();

      tracker.unregister('chat-b');
      expect(tracker.activeCount()).assertEqual(0);
    });

    it('generation_session_registry_isolates_concurrent_chats_and_prompts', 0, () => {
      const reg = new GenerationSessionRegistry();
      const jobA = new ChatGenerationJob('chat-a', '助手A对话', 'msg-a', '', 'gpt-5', 'OpenAI', 'openai', 'default');
      jobA.liveText = '正在输出A';
      jobA.liveReasoning = '思考A';
      jobA.liveThinking = true;
      jobA.liveReasoningMs = 1500;

      const jobB = new ChatGenerationJob('chat-b', '助手B对话', 'msg-b', 'msg-old-b', 'claude-4', 'Anthropic', 'anthropic', 'coder');
      jobB.liveText = '正在输出B';
      jobB.fetchingSources = true;

      reg.start(jobA);
      reg.start(jobB);
      expect(reg.hasAny()).assertTrue();
      expect(reg.isGenerating('chat-a')).assertTrue();
      expect(reg.isGenerating('chat-b')).assertTrue();
      expect(reg.hasOtherGenerating('chat-a')).assertTrue();
      expect(reg.hasOtherGenerating('')).assertTrue();
      expect(reg.activeChatIds().length).assertEqual(2);

      // View projections remain isolated when switching chats
      const projA = reg.projectForChat('chat-a');
      expect(projA.working).assertTrue();
      expect(projA.liveMessageId).assertEqual('msg-a');
      expect(projA.liveText).assertEqual('正在输出A');
      expect(projA.liveThinking).assertTrue();
      expect(projA.regeneratingMsgId).assertEqual('');

      const projB = reg.projectForChat('chat-b');
      expect(projB.working).assertTrue();
      expect(projB.liveMessageId).assertEqual('msg-b');
      expect(projB.liveText).assertEqual('正在输出B');
      expect(projB.fetchingSources).assertTrue();
      expect(projB.regeneratingMsgId).assertEqual('msg-old-b');

      const projEmpty = reg.projectForChat('');
      expect(projEmpty.working).assertFalse();
      expect(projEmpty.liveText).assertEqual('');

      // Pending prompt detection across chats
      let approvalChoice = '';
      jobA.pendingApprovalTool = 'workspace_write';
      jobA.pendingApprovalArgs = '{"path":"a.txt"}';
      jobA.approvalResolver = (choice: 'allow_once' | 'allow_all' | 'deny'): void => {
        approvalChoice = choice;
      };
      expect(reg.findOtherPendingPrompt('chat-a') === undefined).assertTrue();
      const promptForB = reg.findOtherPendingPrompt('chat-b');
      expect(promptForB !== undefined).assertTrue();
      expect(promptForB!.chatId).assertEqual('chat-a');
      expect(promptForB!.label).assertContain('等待工具授权');

      // Stop only chat-a while chat-b continues
      expect(reg.stopChat('chat-a')).assertTrue();
      expect(jobA.stopped).assertTrue();
      expect(approvalChoice).assertEqual('deny');
      expect(jobB.stopped).assertFalse();
      reg.finish('chat-a', jobA);
      expect(reg.isGenerating('chat-a')).assertFalse();
      expect(reg.isGenerating('chat-b')).assertTrue();
      expect(reg.hasOtherGenerating('chat-b')).assertFalse();

      // Per-chat error retention across switches, cleared on new start
      reg.setError('chat-c', '网络超时');
      expect(reg.projectForChat('chat-b').lastSendError).assertEqual('');
      expect(reg.projectForChat('chat-c').lastSendError).assertEqual('网络超时');
      expect(reg.projectForChat('chat-c').lastSendErrorChatId).assertEqual('chat-c');

      const jobC = new ChatGenerationJob('chat-c', '对话C', 'msg-c', '', 'gpt-5', 'OpenAI', 'openai', 'default');
      reg.start(jobC);
      expect(reg.getError('chat-c')).assertEqual('');

      // Deleting an active chat marks deleted, stops job, and clears error
      let askResolved = 'unset';
      jobB.askQuestionText = '是否继续？';
      jobB.askUserResolver = (val: string): void => {
        askResolved = val;
      };
      reg.markDeletedAndStop('chat-b');
      expect(jobB.deleted).assertTrue();
      expect(jobB.stopped).assertTrue();
      expect(askResolved).assertEqual('');

      reg.stopChat('chat-c');
      reg.finish('chat-b', jobB);
      reg.finish('chat-c', jobC);
      expect(reg.hasAny()).assertFalse();
    });

    it('instruction_injection_android_backup_normalization_and_assembly', 0, () => {
      // Simulate Kelivo Android/Flutter backup payload: { id, title, prompt, group } without description/content
      const androidCardsRaw = '[{"id":"c1","title":"角色设定卡","prompt":"严格按角色设定回复。","group":"RP"},{"id":"c2","title":"","prompt":"保持输出简洁。"}]';
      const androidPayload: Record<string, Object> = {};
      androidPayload['instruction_injections_v1'] = androidCardsRaw;
      const androidSettings = JSON.stringify(androidPayload);

      const parsed = parseAndroidSettingsJson(androidSettings);
      expect(parsed.instructionCards !== undefined).assertTrue();
      expect(parsed.instructionCards!.length).assertEqual(2);
      expect(parsed.instructionCards![0].content).assertEqual('严格按角色设定回复。');
      expect(parsed.instructionCards![0].description).assertEqual('');
      expect(parsed.instructionCards![0].group).assertEqual('RP');
      expect(parsed.instructionCards![0].description.length).assertEqual(0);
      expect(parsed.instructionCards![1].title).assertEqual('学习模式');
      expect(parsed.instructionCards![1].content).assertEqual('保持输出简洁。');

      // Direct call to normalizeInstructionCards with legacy partial record shape
      const rawLegacy = JSON.parse('[{"id":"x1","title":"旧卡","prompt":"正文提示","group":"分组A"}]') as InstructionCard[];
      const normed = normalizeInstructionCards(rawLegacy);
      expect(normed.length).assertEqual(1);
      expect(normed[0].description).assertEqual('');
      expect(normed[0].content).assertEqual('正文提示');
      expect(normed[0].group).assertEqual('分组A');

      // Prompt assembly works on both normalized cards and raw partial cards without throwing
      const assembled = assembleInstructionCards(normed, ['x1']);
      expect(assembled).assertEqual('[旧卡]\n正文提示');
      const assembledRaw = assembleInstructionCards(rawLegacy, ['x1']);
      expect(assembledRaw).assertEqual('[旧卡]\n正文提示');

      // Export back to Android settings preserves both Android (prompt/group) and Harmony (content/description) keys
      const ws = initialWorkspace();
      ws.instructionCards = parsed.instructionCards;
      const exported = JSON.parse(buildAndroidSettingsJson(ws, defaultBackupScope(), {})) as Record<string, Object>;
      const exportedCards = JSON.parse(exported['instruction_injections_v1'] as string) as Record<string, Object>[];
      expect(exportedCards.length).assertEqual(2);
      expect(exportedCards[0]['prompt']).assertEqual('严格按角色设定回复。');
      expect(exportedCards[0]['group']).assertEqual('RP');
      expect(exportedCards[0]['content']).assertEqual('严格按角色设定回复。');

      // QuickPhrase & WorldBook Android shapes normalize safely
      const qpNorm = normalizeQuickPhrases(
        JSON.parse('[{"id":"q1","title":"润色","content":"请润色：","isGlobal":true}]') as QuickPhrase[]
      );
      expect(qpNorm[0].scope).assertEqual('global');
      const wbNorm = normalizeWorldBooks(
        JSON.parse('[{"id":"wb1","name":"测试书","enabled":true,"entries":[{"id":"e1","name":"词条","position":"BEFORE_SYSTEM_PROMPT","role":"USER","content":"世界背景","keywords":["触发"],"injectDepth":2,"constantActive":true}]}]') as WorldBook[]
      );
      expect(wbNorm.length).assertEqual(1);
      expect(wbNorm[0].entries[0].position).assertEqual('before_system');
      expect(wbNorm[0].entries[0].role).assertEqual('user');
      expect(wbNorm[0].entries[0].keys[0]).assertEqual('触发');
      expect(wbNorm[0].entries[0].depth).assertEqual(2);
      expect(wbNorm[0].entries[0].alwaysActive).assertTrue();
    });

    it('network_proxy_priority_bypass_and_backup_roundtrip', 0, () => {
      const bypass = 'localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,*.local,::1';
      expect(shouldBypassProxy('http://localhost:11434/v1/chat/completions', bypass)).assertTrue();
      expect(shouldBypassProxy('http://127.0.0.1:8080/models', bypass)).assertTrue();
      expect(shouldBypassProxy('http://192.168.31.10:11434/v1', bypass)).assertTrue();
      expect(shouldBypassProxy('http://172.20.1.5:8000/v1', bypass)).assertTrue();
      expect(shouldBypassProxy('http://macbook.local:11434/v1', bypass)).assertTrue();
      expect(shouldBypassProxy('https://api.openai.com/v1/chat/completions', bypass)).assertFalse();

      // Configure global proxy and test precedence against provider proxy
      setGlobalHttpProxy({
        enabled: true,
        type: 'socks5',
        host: '127.0.0.1',
        port: 7890,
        username: 'u1',
        bypass
      }, 'p1');

      // Bypassed local URL skips global proxy
      const localRes = resolveEffectiveProxy(undefined, '', 'http://192.168.1.50:11434/v1/models');
      expect(localRes === undefined).assertTrue();

      // External URL uses global proxy when provider proxy is unset/disabled
      const globalRes = resolveEffectiveProxy(
        { enabled: false, host: '127.0.0.1', port: 9999 },
        '',
        'https://api.openai.com/v1/chat/completions'
      );
      expect(globalRes !== undefined).assertTrue();
      expect(globalRes!.source).assertEqual('global');
      expect(globalRes!.proxy.type).assertEqual('socks5');
      expect(globalRes!.proxy.port).assertEqual(7890);

      // Enabled provider proxy overrides global proxy
      const provRes = resolveEffectiveProxy(
        { enabled: true, type: 'http', host: '10.0.0.2', port: 8888, username: 'pu' },
        'ppass',
        'https://api.openai.com/v1/chat/completions'
      );
      expect(provRes !== undefined).assertTrue();
      expect(provRes!.source).assertEqual('provider');
      expect(provRes!.proxy.host).assertEqual('10.0.0.2');
      expect(provRes!.proxy.port).assertEqual(8888);
      expect(provRes!.password).assertEqual('ppass');

      // Backup round-trip for globalProxy via Android & scoped restore
      const ws = initialWorkspace();
      ws.globalProxy = {
        enabled: true,
        type: 'socks5',
        host: 'proxy.example.com',
        port: 1080,
        username: 'alice',
        passwordRef: 'gp_sec_1',
        bypass: 'localhost,192.168.0.0/16'
      };
      const secMap: Record<string, string> = {};
      secMap['gp_sec_1'] = 's3cr3t';
      const exportedRaw = buildAndroidSettingsJson(ws, defaultBackupScope(), secMap);
      const exportedMap = JSON.parse(exportedRaw) as Record<string, Object>;
      expect(exportedMap['global_proxy_enabled_v1']).assertEqual(true);
      expect(exportedMap['global_proxy_type_v1']).assertEqual('socks5');
      expect(exportedMap['global_proxy_host_v1']).assertEqual('proxy.example.com');
      expect(exportedMap['global_proxy_port_v1']).assertEqual('1080');
      expect(exportedMap['global_proxy_password_v1']).assertEqual('s3cr3t');

      const imported = parseAndroidSettingsJson(exportedRaw);
      expect(imported.globalProxy !== undefined).assertTrue();
      expect(imported.globalProxy!.enabled).assertTrue();
      expect(imported.globalProxy!.type).assertEqual('socks5');
      expect(imported.globalProxy!.host).assertEqual('proxy.example.com');
      expect(imported.globalProxy!.port).assertEqual(1080);
      expect(imported.globalProxy!.bypass).assertEqual('localhost,192.168.0.0/16');

      let seq = 0;
      const restored = applyScopedRestore(initialWorkspace(), imported, defaultBackupScope(), 'overwrite', () => 'r_' + (++seq));
      expect(restored.workspace.globalProxy?.enabled).assertTrue();
      expect(restored.workspace.globalProxy?.type).assertEqual('socks5');
      const restoredPassRef = restored.workspace.globalProxy?.passwordRef || '';
      expect(restoredPassRef.length > 0).assertTrue();
      expect(restored.secretsToStore[restoredPassRef]).assertEqual('s3cr3t');

      // Clear module-level global proxy state
      setGlobalHttpProxy(undefined, '');
    });

    it('reasoning_bulb_ray_count_scales_by_supported_levels', 0, () => {
      const toggleCtrl = reasoningControl(
        preset('zhipu', 'Zhipu', 'openai', 'https://open.bigmodel.cn/api/paas/v4', 'glm-4.5'),
        'glm-4.5',
        defaultModelSpec('glm-4.5')
      );
      expect(reasoningBulbRayCount(toggleCtrl, 'off')).assertEqual(0);
      expect(reasoningBulbRayCount(toggleCtrl, 'high')).assertEqual(3);

      const standardCtrl = reasoningControl(
        preset('openai', 'OpenAI', 'openai', 'https://api.openai.com/v1', 'gpt-4o'),
        'custom-reasoner',
        {
          id: 'custom-reasoner',
          displayName: 'custom-reasoner',
          vision: false,
          tools: true,
          reasoning: true,
          imageGen: false,
          contextWindow: 128000,
          maxOutputTokens: 8192,
          enabled: true
        }
      );
      expect(reasoningBulbRayCount(standardCtrl, 'off')).assertEqual(0);
      expect(reasoningBulbRayCount(standardCtrl, 'low')).assertEqual(1);
      expect(reasoningBulbRayCount(standardCtrl, 'medium')).assertEqual(2);
      expect(reasoningBulbRayCount(standardCtrl, 'high')).assertEqual(3);

      const extendedCtrl = reasoningControl(
        preset('openai', 'OpenAI', 'openai', 'https://api.openai.com/v1', 'gpt-5.2'),
        'gpt-5.2',
        defaultModelSpec('gpt-5.2')
      );
      expect(reasoningBulbRayCount(extendedCtrl, 'off')).assertEqual(0);
      expect(reasoningBulbRayCount(extendedCtrl, 'low')).assertEqual(1);
      expect(reasoningBulbRayCount(extendedCtrl, 'medium')).assertEqual(2);
      expect(reasoningBulbRayCount(extendedCtrl, 'high')).assertEqual(3);
      expect(reasoningBulbRayCount(extendedCtrl, 'xhigh')).assertEqual(4);

      const sixLevelCtrl = reasoningControl(
        preset('anthropic', 'Anthropic', 'anthropic', 'https://api.anthropic.com/v1', 'claude-opus-5'),
        'claude-opus-5',
        defaultModelSpec('claude-opus-5')
      );
      expect(reasoningBulbRayCount(sixLevelCtrl, 'off')).assertEqual(0);
      expect(reasoningBulbRayCount(sixLevelCtrl, 'low')).assertEqual(1);
      expect(reasoningBulbRayCount(sixLevelCtrl, 'medium')).assertEqual(2);
      expect(reasoningBulbRayCount(sixLevelCtrl, 'high')).assertEqual(3);
      expect(reasoningBulbRayCount(sixLevelCtrl, 'xhigh')).assertEqual(4);
      expect(reasoningBulbRayCount(sixLevelCtrl, 'max')).assertEqual(5);

      const gpt56Ctrl = reasoningControl(
        preset('openai', 'OpenAI', 'openai', 'https://api.openai.com/v1', 'gpt-5.6'),
        'gpt-5.6',
        defaultModelSpec('gpt-5.6')
      );
      expect(reasoningBulbRayCount(gpt56Ctrl, 'off')).assertEqual(0);
      expect(reasoningBulbRayCount(gpt56Ctrl, 'low')).assertEqual(1);
      expect(reasoningBulbRayCount(gpt56Ctrl, 'medium')).assertEqual(2);
      expect(reasoningBulbRayCount(gpt56Ctrl, 'high')).assertEqual(3);
      expect(reasoningBulbRayCount(gpt56Ctrl, 'xhigh')).assertEqual(4);
      expect(reasoningBulbRayCount(gpt56Ctrl, 'max')).assertEqual(5);

      const geminiFlashCtrl = reasoningControl(
        preset('gemini', 'Gemini', 'gemini', 'https://generativelanguage.googleapis.com/v1beta', 'gemini-3-flash'),
        'gemini-3-flash',
        defaultModelSpec('gemini-3-flash')
      );
      expect(reasoningBulbRayCount(geminiFlashCtrl, 'minimal')).assertEqual(1);
      expect(reasoningBulbRayCount(geminiFlashCtrl, 'low')).assertEqual(2);
      expect(reasoningBulbRayCount(geminiFlashCtrl, 'medium')).assertEqual(3);
      expect(reasoningBulbRayCount(geminiFlashCtrl, 'high')).assertEqual(4);
    });

    it('stream_text_smoother_adaptive_pacing_and_safe_cut', 0, () => {
      // Standard mode paces smoothly and wakes up with >= 1 char immediately
      const std = new StreamTextSmoother('standard', false);
      std.setTarget('Hello streaming world!', '');
      const f1 = std.step(16);
      expect(f1.textChanged).assertTrue();
      expect(f1.text.length >= 1 && f1.text.length < 'Hello streaming world!'.length).assertTrue();
      expect(f1.hasMore).assertTrue();

      let guard = 0;
      let prevLen = f1.text.length;
      while (std.hasPending() && guard < 120) {
        const next = std.step(16);
        expect(next.text.length >= prevLen).assertTrue();
        prevLen = next.text.length;
        guard += 1;
      }
      expect(std.hasPending()).assertFalse();
      expect(prevLen).assertEqual('Hello streaming world!'.length);

      // Large burst adapts pace faster than minimum rate
      const burstText = 'A'.repeat(400);
      const fast = new StreamTextSmoother('fast', false);
      const slowBurst = new StreamTextSmoother('standard', false);
      fast.setTarget(burstText, '');
      slowBurst.setTarget(burstText, '');
      const fastStep = fast.step(16);
      const slowStep = slowBurst.step(16);
      expect(fastStep.text.length > slowStep.text.length).assertTrue();
      expect(slowStep.text.length > 20).assertTrue();

      // UTF-16 surrogate pair safety: never leave trailing high surrogate
      const emojiSample = 'A😀B😀C😀D😀E😀F😀G';
      const emojiSmoother = new StreamTextSmoother('standard', false);
      emojiSmoother.setTarget(emojiSample, '');
      while (emojiSmoother.hasPending()) {
        const st = emojiSmoother.step(16);
        if (st.text.length > 0) {
          const tailCode = st.text.charCodeAt(st.text.length - 1);
          expect(tailCode >= 0xD800 && tailCode <= 0xDBFF).assertFalse();
        }
      }

      // Markdown double-marker pair safety: avoid stopping mid-marker '**'
      const mdPairSmoother = new StreamTextSmoother('standard', false);
      mdPairSmoother.setTarget('**bold**', '');
      const mdFirst = mdPairSmoother.step(16);
      expect(mdFirst.text === '*').assertFalse();

      // Ultrafast and reduceMotion snap immediately
      const ultra = new StreamTextSmoother('ultrafast', false);
      ultra.setTarget('Instant output', 'Instant thoughts');
      const ultraRes = ultra.step(16);
      expect(ultraRes.text).assertEqual('Instant output');
      expect(ultraRes.reasoning).assertEqual('Instant thoughts');
      expect(ultraRes.hasMore).assertFalse();

      const reduced = new StreamTextSmoother('standard', true);
      reduced.setTarget('Reduced motion text', '');
      const reducedRes = reduced.step(16);
      expect(reducedRes.text).assertEqual('Reduced motion text');
      expect(reducedRes.hasMore).assertFalse();

      // snapToTarget immediately flushes remainder
      const snapper = new StreamTextSmoother('standard', false);
      snapper.setTarget('Pending tail', 'Pending reasoning');
      snapper.step(16);
      const snapped = snapper.snapToTarget();
      expect(snapped.text).assertEqual('Pending tail');
      expect(snapped.reasoning).assertEqual('Pending reasoning');
      expect(snapped.hasMore).assertFalse();
      expect(snapper.hasPending()).assertFalse();
    });

    it('markdown_incremental_stable_prefix_and_inline_tail_equivalence', 0, () => {
      // Must NOT split inside an open fenced code block even across blank lines
      const openFenceDoc = '# Title\n\n```ts\nconst a = 1;\n\nconst b = 2;';
      const openCut = findStableMarkdownPrefixEnd(openFenceDoc);
      expect(openCut).assertEqual('# Title\n\n'.length);

      // Once fence closes and another block follows after a blank line, whole code block freezes
      const fullDoc = [
        '# Title',
        '',
        'Intro paragraph with **bold**.',
        '',
        '```ts',
        'const a = 1;',
        '',
        'const b = 2;',
        '```',
        '',
        '$$',
        'x = 1',
        '',
        'y = 2',
        '$$',
        '',
        '- item one',
        '- item two',
        '',
        '| A | B |',
        '|---|---|',
        '| 1 | 2 |',
        '',
        'Tail **styled** plain suffix'
      ].join('\n');

      const cut = findStableMarkdownPrefixEnd(fullDoc);
      expect(cut > 0 && cut < fullDoc.length).assertTrue();
      const prefixBlocks = parseMarkdownBlocks(fullDoc.slice(0, cut));
      const tailBlocks = parseMarkdownBlocks(fullDoc.slice(cut));
      const combinedJson = JSON.stringify([...prefixBlocks, ...tailBlocks]);
      const expectedJson = JSON.stringify(parseMarkdownBlocks(fullDoc));
      expect(combinedJson).assertEqual(expectedJson);
      expect(tailBlocks.length).assertEqual(1);
      expect(tailBlocks[0].kind).assertEqual('paragraph');

      // Inline tail splitting isolates changing trailing plain text
      const split1 = splitInlineTail('Hello **world** and trailing text');
      expect(split1.prefix.length).assertEqual(2);
      expect(split1.prefix[1].kind).assertEqual('bold');
      expect(split1.prefix[1].text).assertEqual('world');
      expect(split1.suffix).assertEqual(' and trailing text');

      const split2 = splitInlineTail('**onlyBold**');
      expect(split2.prefix.length).assertEqual(1);
      expect(split2.suffix).assertEqual('');
    });

    it('usage_stats_dashboard_calendar_bars_and_ranks', 0, () => {
      // Local date and time formatting with zero-padding (never shifts on local midnight)
      const earlyJan = new Date(2026, 0, 5, 1, 2, 3);
      expect(formatLocalDay(earlyJan)).assertEqual('2026-01-05');
      expect(formatLocalTime(earlyJan)).assertEqual('01:02:03');

      const refTuesdayMidnight = new Date(2026, 10, 24, 0, 15, 0); // 2026-11-24 is Tuesday
      expect(formatLocalDay(refTuesdayMidnight)).assertEqual('2026-11-24');

      expect(formatUsageCount(0)).assertEqual('0');
      expect(formatUsageCount(98900)).assertEqual('98.9K');
      expect(formatUsageCount(8810000)).assertEqual('8.81M');

      // Stacked bar percentages never exceed 100 and preserve zero components
      const zeroBar = computeStackedBarPcts(0, 0, 1000);
      expect(zeroBar.promptPct).assertEqual(0);
      expect(zeroBar.compPct).assertEqual(0);

      const onlyPrompt = computeStackedBarPcts(500, 0, 1000);
      expect(onlyPrompt.promptPct).assertEqual(50);
      expect(onlyPrompt.compPct).assertEqual(0);

      const skewed = computeStackedBarPcts(999, 1, 1000);
      expect(skewed.promptPct + skewed.compPct).assertEqual(100);
      expect(skewed.compPct).assertEqual(2);
      expect(skewed.promptPct).assertEqual(98);

      // Dashboard aggregation, Mon-Sun alignment, future masking, and rankings
      const personas: Persona[] = [
        { id: 'default', name: '通用助手', prompt: '', avatar: '', tags: [], memoryEnabled: true },
        { id: 'coder', name: '编程专家', prompt: '', avatar: '', tags: [], memoryEnabled: true }
      ];
      const rows: UsageStatRow[] = [
        {
          id: '2026-11-23::deepseek-v4.1-flash::default',
          day: '2026-11-23',
          model: 'deepseek-v4.1-flash',
          personaId: 'default',
          promptTokens: 5800000,
          completionTokens: 130000,
          cachedTokens: 3000000,
          msgCount: 50
        },
        {
          id: '2026-11-24::deepseek-v4.1-flash::coder',
          day: '2026-11-24',
          model: 'deepseek-v4.1-flash',
          personaId: 'coder',
          promptTokens: 160000,
          completionTokens: 10400,
          cachedTokens: 40000,
          msgCount: 4
        },
        {
          id: '2026-11-24::gpt-5.2::',
          day: '2026-11-24',
          model: 'gpt-5.2',
          personaId: '',
          promptTokens: 200000,
          completionTokens: 100000,
          cachedTokens: 0,
          msgCount: 6
        }
      ];

      const dash = computeUsageDashboard(rows, personas, refTuesdayMidnight);
      expect(dash.promptTokens).assertEqual(6160000);
      expect(dash.completionTokens).assertEqual(240400);
      expect(dash.totalTokens).assertEqual(6400400);
      expect(dash.cachedTokens).assertEqual(3040000);
      expect(dash.totalMessages).assertEqual(60);
      expect(dash.activeDays).assertEqual(2);
      expect(dash.heatmapEndDay).assertEqual('2026-11-24');

      // Heatmap is 7 weekday rows x 13 week columns
      expect(dash.heatmapRows.length).assertEqual(7);
      expect(dash.heatmapRows[0].label).assertEqual('一');
      expect(dash.heatmapRows[6].label).assertEqual('日');
      expect(dash.heatmapRows[0].cells.length).assertEqual(13);

      // Week 12 Monday = 2026-11-23 (active), Tuesday = 2026-11-24 (today), Wed..Sun = -1 future
      const monTodayWeek = dash.heatmapRows[0].cells[12];
      const tueTodayCell = dash.heatmapRows[1].cells[12];
      const wedFutureCell = dash.heatmapRows[2].cells[12];
      const sunFutureCell = dash.heatmapRows[6].cells[12];
      expect(monTodayWeek.day).assertEqual('2026-11-23');
      expect(monTodayWeek.level).assertEqual(4);
      expect(tueTodayCell.day).assertEqual('2026-11-24');
      expect(tueTodayCell.isToday).assertTrue();
      expect(tueTodayCell.totalTokens).assertEqual(470400);
      expect(tueTodayCell.level > 0).assertTrue();
      expect(wedFutureCell.level).assertEqual(-1);
      expect(sunFutureCell.level).assertEqual(-1);

      // 14 daily bars end on today and every bar sums <= 100%
      expect(dash.recentBars.length).assertEqual(14);
      expect(dash.recentBars[13].day).assertEqual('2026-11-24');
      expect(dash.recentBars[13].isToday).assertTrue();
      for (let i = 0; i < dash.recentBars.length; i++) {
        const b = dash.recentBars[i];
        expect(b.promptPct + b.compPct <= 100).assertTrue();
      }
      expect(dash.recentBars[12].promptPct + dash.recentBars[12].compPct).assertEqual(100);

      // Model & persona rankings sorted descending with ratioPct in [4, 100]
      expect(dash.modelRanks.length).assertEqual(2);
      expect(dash.modelRanks[0].key).assertEqual('deepseek-v4.1-flash');
      expect(dash.modelRanks[0].ratioPct).assertEqual(100);
      expect(dash.modelRanks[1].key).assertEqual('gpt-5.2');
      expect(dash.modelRanks[1].ratioPct >= 4 && dash.modelRanks[1].ratioPct <= 100).assertTrue();

      expect(dash.personaRanks.length).assertEqual(2);
      expect(dash.personaRanks[0].key).assertEqual('default');
      expect(dash.personaRanks[0].label).assertEqual('通用助手');
      expect(dash.personaRanks[0].ratioPct).assertEqual(100);
      expect(dash.personaRanks[1].key).assertEqual('coder');
      expect(dash.personaRanks[1].label).assertEqual('编程专家');
    });

    it('builtin_search_support_payloads_citations_and_moonshot_loop', 0, async () => {
      // 1. Provider / model built-in search capability matrix
      const geminiProv = preset('gm', 'Google Gemini', 'gemini', 'https://generativelanguage.googleapis.com/v1beta', 'gemini-3-pro-preview');
      const vertexProv = preset('vx', 'Vertex AI', 'vertex', 'https://aiplatform.googleapis.com/v1', 'gemini-2.5-flash');
      const claudeProv = preset('cl', 'Anthropic', 'anthropic', 'https://api.anthropic.com/v1', 'claude-sonnet-4-6');
      const deepseekAnthropic = preset('deepseek', 'DeepSeek', 'anthropic', 'https://api.deepseek.com/anthropic', 'deepseek-chat');
      const openaiChat = preset('oai-c', 'OpenAI Chat', 'openai', 'https://api.openai.com/v1', 'gpt-5');
      const openaiChatSearch = preset('oai-cs', 'OpenAI Search', 'openai', 'https://api.openai.com/v1', 'gpt-4o-search-preview');
      const openaiResp = preset('oai-r', 'OpenAI Resp', 'openai-responses', 'https://api.openai.com/v1', 'gpt-5');
      const grokChat = preset('xai-c', 'xAI Grok', 'openai', 'https://api.x.ai/v1', 'grok-4');
      const grokResp = preset('xai-r', 'xAI Grok', 'openai-responses', 'https://api.x.ai/v1', 'grok-4');
      const orChat = preset('openrouter', 'OpenRouter', 'openai', 'https://openrouter.ai/api/v1', 'openai/gpt-5');
      const qwenChat = preset('qwen', '阿里云百炼', 'openai', 'https://dashscope.aliyuncs.com/compatible-mode/v1', 'qwen3-max');
      const zhipuChat = preset('zhipu', '智谱 GLM', 'openai', 'https://open.bigmodel.cn/api/paas/v4', 'glm-4.5');
      const kimiChat = preset('kimi', 'Moonshot', 'openai', 'https://api.moonshot.cn/v1', 'kimi-k2');
      const mimoChat = preset('mimo', 'MiMo', 'openai', 'https://api.xiaomimimo.com/v1', 'mimo-v2');
      const ollamaChat = preset('ollama', 'Ollama', 'openai', 'http://127.0.0.1:11434/v1', 'llama3.3');

      expect(supportsBuiltInSearch(geminiProv, 'gemini-3-pro-preview')).assertTrue();
      expect(supportsBuiltInSearch(vertexProv, 'gemini-2.5-flash')).assertTrue();
      expect(supportsBuiltInSearch(claudeProv, 'claude-sonnet-4-6')).assertTrue();
      expect(supportsClaudeDynamicWebSearch(claudeProv, 'claude-sonnet-4-6')).assertTrue();
      expect(supportsClaudeDynamicWebSearch(claudeProv, 'claude-3-7-sonnet')).assertFalse();
      expect(supportsBuiltInSearch(deepseekAnthropic, 'deepseek-chat')).assertFalse();
      expect(supportsBuiltInSearch(openaiChat, 'gpt-5')).assertFalse();
      expect(requiresResponsesApiForBuiltInSearch(openaiChat, 'gpt-5')).assertTrue();
      expect(supportsBuiltInSearch(openaiChatSearch, 'gpt-4o-search-preview')).assertTrue();
      expect(supportsBuiltInSearch(openaiResp, 'gpt-5')).assertTrue();
      expect(supportsBuiltInSearch(grokChat, 'grok-4')).assertFalse();
      expect(requiresResponsesApiForBuiltInSearch(grokChat, 'grok-4')).assertTrue();
      expect(supportsBuiltInSearch(grokResp, 'grok-4')).assertTrue();
      expect(supportsBuiltInSearch(orChat, 'openai/gpt-5')).assertTrue();
      expect(supportsBuiltInSearch(qwenChat, 'qwen3-max')).assertTrue();
      expect(supportsBuiltInSearch(zhipuChat, 'glm-4.5')).assertTrue();
      expect(supportsBuiltInSearch(kimiChat, 'kimi-k2')).assertTrue();
      expect(supportsBuiltInSearch(mimoChat, 'mimo-v2')).assertTrue();
      expect(supportsBuiltInSearch(ollamaChat, 'llama3.3')).assertFalse();
      expect(supportsBuiltInSearch(geminiProv, 'imagen-3.0-generate-002')).assertFalse();
      expect(supportsBuiltInSearch(openaiResp, 'text-embedding-3-large')).assertFalse();

      // 2. Per-model ModelSpec.builtinSearch overrides provider.builtinSearch fallback
      const gm3Spec: ModelSpec = defaultModelSpec('gemini-3-pro-preview');
      gm3Spec.builtinSearch = false;
      geminiProv.builtinSearch = true;
      geminiProv.models = [gm3Spec];
      expect(isBuiltInSearchEnabled(geminiProv, 'gemini-3-pro-preview')).assertFalse();
      gm3Spec.builtinSearch = true;
      expect(isBuiltInSearchEnabled(geminiProv, 'gemini-3-pro-preview')).assertTrue();

      const uMsg: ChatMessage = { id: 'u1', role: 'user', text: '今天有什么新闻', model: '' };

      // 3. Gemini 3 Pro coexists googleSearch + functionDeclarations with VALIDATED toolConfig
      const g3Call = makeAdvancedChatCall(geminiProv, 'AIza-key', '', [uMsg], {
        modelId: 'gemini-3-pro-preview',
        tools: [{ name: 'memory_read', description: 'read mem', parametersJson: '{"type":"object","properties":{"q":{"type":"string"}}}' }]
      });
      expect(g3Call.body).assertContain('"googleSearch"');
      expect(g3Call.body).assertContain('"functionDeclarations"');
      expect(g3Call.body).assertContain('"VALIDATED"');
      expect(g3Call.body).assertContain('"includeServerSideToolInvocations":true');

      // 4. Anthropic basic vs dynamic search and client tool name deduplication
      const clDynamicSpec: ModelSpec = defaultModelSpec('claude-sonnet-4-6');
      clDynamicSpec.builtinSearch = true;
      clDynamicSpec.claudeDynamicSearch = true;
      claudeProv.models = [clDynamicSpec];
      const clDynCall = makeAdvancedChatCall(claudeProv, 'sk-ant', '', [uMsg]);
      expect(clDynCall.body).assertContain('"type":"web_search_20260318"');
      expect(clDynCall.body).assertContain('"name":"web_search"');

      const clBasicCall = makeAdvancedChatCall(claudeProv, 'sk-ant', '', [uMsg], { claudeDynamicSearch: false });
      expect(clBasicCall.body).assertContain('"type":"web_search_20250305"');

      const clCollisionCall = makeAdvancedChatCall(claudeProv, 'sk-ant', '', [uMsg], {
        tools: [{ name: 'web_search', description: 'ext', parametersJson: '{"type":"object","properties":{"q":{"type":"string"}}}' }]
      });
      expect(clCollisionCall.body.includes('"web_search_20260318"')).assertFalse();

      // 5. Responses / Grok / OpenRouter / DashScope / Zhipu / Moonshot / OpenAI search payloads
      const grokCall = makeAdvancedChatCall(grokResp, 'xai-key', '', [uMsg], { builtinSearch: true });
      expect(grokCall.body).assertContain('"type":"web_search"');
      expect(grokCall.body).assertContain('"type":"x_search"');

      const orBody: Record<string, Object> = {};
      orBody['model'] = 'openai/gpt-5';
      const legacyWebPlugin: Record<string, Object> = {};
      legacyWebPlugin['id'] = 'web';
      const pdfPlugin: Record<string, Object> = {};
      pdfPlugin['id'] = 'file-parser';
      orBody['plugins'] = [legacyWebPlugin, pdfPlugin];
      const orFinal = applyChatCompletionsBuiltInSearch(orBody, orChat, 'openai/gpt-5');
      const orJson = JSON.stringify(orFinal);
      expect(orJson).assertContain('"openrouter:web_search"');
      expect(orJson).assertContain('"file-parser"');
      expect(orJson.includes('"id":"web"')).assertFalse();

      // When only web plugin was present, plugins key is omitted completely
      const orOnlyWebBody: Record<string, Object> = {};
      orOnlyWebBody['plugins'] = [legacyWebPlugin];
      const orStripped = applyChatCompletionsBuiltInSearch(orOnlyWebBody, orChat, 'openai/gpt-5');
      expect(JSON.stringify(orStripped).includes('"plugins"')).assertFalse();

      const qwenCall = makeAdvancedChatCall(qwenChat, 'q-key', '', [uMsg], { builtinSearch: true });
      expect(qwenCall.body).assertContain('"enable_search":true');

      const zhipuCall = makeAdvancedChatCall(zhipuChat, 'z-key', '', [uMsg], { builtinSearch: true });
      expect(zhipuCall.body).assertContain('"search_result":true');

      const kimiCall = makeAdvancedChatCall(kimiChat, 'k-key', '', [uMsg], { builtinSearch: true });
      expect(kimiCall.body).assertContain('"type":"builtin_function"');
      expect(kimiCall.body).assertContain('"$web_search"');
      expect(needsMoonshotBuiltinSearchLoop(kimiChat, 'kimi-k2', true)).assertTrue();

      const oaiSearchCall = makeAdvancedChatCall(openaiChatSearch, 'o-key', '', [uMsg], { builtinSearch: true });
      expect(oaiSearchCall.body).assertContain('"web_search_options"');

      // 6. Citation extraction across all formats
      const gemCitations = parseRichReply(
        '{"candidates":[{"content":{"parts":[{"text":"answer"}]},"groundingMetadata":{"groundingChunks":[{"web":{"uri":"https://example.com/a","title":"Site A"}},{"web":{"uri":"https://example.com/a","title":"Site A"}}]}}]}'
      );
      expect(gemCitations.citations?.length).assertEqual(1);
      expect(gemCitations.citations?.[0].title).assertEqual('Site A');

      const clStartCitations = parseRichReply(
        '{"type":"content_block_start","index":1,"content_block":{"type":"web_search_tool_result","content":[{"type":"web_search_result","title":"Claude Doc","url":"https://docs.anthropic.com"}]}}'
      );
      expect(clStartCitations.citations?.length).assertEqual(1);
      expect(clStartCitations.citations?.[0].url).assertEqual('https://docs.anthropic.com');

      const clDeltaCitations = parseRichReply(
        '{"type":"content_block_delta","index":2,"delta":{"type":"citations_delta","citation":{"title":"Cited Page","url":"https://example.com/cite","cited_text":"snippet"}}}'
      );
      expect(clDeltaCitations.citations?.[0].excerpt).assertEqual('snippet');

      const respAnn = parseRichReply(
        '{"type":"response.output_text.annotation.added","annotation":{"type":"url_citation","url":"https://openai.com/news","title":"OpenAI News"}}'
      );
      expect(respAnn.citations?.[0].title).assertEqual('OpenAI News');

      const respDone = parseRichReply(
        '{"type":"response.completed","response":{"output":[{"type":"message","content":[{"type":"output_text","annotations":[{"type":"url_citation","url":"https://openai.com/done","title":"Done Ref"}]}]}]}}'
      );
      expect(respDone.citations?.[0].url).assertEqual('https://openai.com/done');

      const chatCite = parseRichReply(
        '{"citations":["https://perplexity.ai/post"],"web_search":[{"title":"Zhipu Result","link":"https://bigmodel.cn/info","content":"body"}]}'
      );
      expect(chatCite.citations?.length).assertEqual(2);

      // 7. Assistant messages with sources do NOT get user pre-search prompt appended
      const aMsgWithSources: ChatMessage = {
        id: 'a1',
        role: 'assistant',
        text: '结论如下',
        model: 'gpt-5',
        sources: [{ title: 'Source', url: 'https://example.com', excerpt: 'detail' }]
      };
      expect(messageText(aMsgWithSources)).assertEqual('结论如下');
      const uMsgWithSources: ChatMessage = {
        id: 'u2',
        role: 'user',
        text: '查询这个问题',
        model: '',
        sources: [{ title: 'UserSource', url: 'https://example.com/u', excerpt: 'detail' }]
      };
      expect(messageText(uMsgWithSources)).assertContain('以下为网页检索资料');

      // 8. Moonshot $web_search tool loop auto-echoes arguments without external executeTool
      let externalToolExecuted = false;
      let kimiRound = 0;
      const kimiLoopOut = await runAgentToolLoop({
        provider: kimiChat,
        apiKey: 'k-key',
        modelId: 'kimi-k2',
        systemPrompt: '',
        history: [uMsg],
        genParams: defaultGenerationParams(),
        builtinSearch: true,
        tools: [],
        permissionMode: 'ask',
        maxSteps: 4,
        runStream: async (call: ChatCall, onFrag: (f: RichFragment) => void): Promise<void> => {
          expect(call.body).assertContain('"$web_search"');
          kimiRound++;
          if (kimiRound === 1) {
            onFrag({
              text: '', reasoning: '', generatedImages: [], done: false,
              toolCalls: [{ index: 0, id: 'ws_1', name: '$web_search', argsDelta: '{"query":"OpenHarmony"}', done: false }]
            });
          } else {
            expect(call.body).assertContain('OpenHarmony');
            onFrag({
              text: '搜索完成', reasoning: '', toolCalls: [], generatedImages: [],
              citations: [{ title: 'Harmony', url: 'https://developer.huawei.com', excerpt: '' }],
              done: true
            });
          }
        },
        executeTool: async (): Promise<ToolExecutionOutput> => {
          externalToolExecuted = true;
          return { text: 'should not run' };
        },
        requestApproval: async (): Promise<'allow_once' | 'allow_all' | 'deny'> => 'deny',
        onUpdate: () => {},
        isStopped: () => false
      });
      expect(externalToolExecuted).assertFalse();
      expect(kimiRound).assertEqual(2);
      expect(kimiLoopOut.text).assertEqual('搜索完成');
      expect(kimiLoopOut.toolCalls[0].name).assertEqual('$web_search');
      expect(kimiLoopOut.toolCalls[0].status).assertEqual('done');
      expect(kimiLoopOut.citations.length).assertEqual(1);
      const firstHit: SearchHit = kimiLoopOut.citations[0];
      expect(firstHit.url).assertEqual('https://developer.huawei.com');
    });

    it('tool_call_record_grouping_deduplicates_and_aggregates_status', 0, () => {
      const makeRec = (
        id: string,
        name: string,
        status: 'pending' | 'running' | 'done' | 'error' | 'denied',
        durationMs: number
      ): ToolCallRecord => {
        return { id, name, argsJson: '{}', status, resultText: '', durationMs };
      };
      const records: ToolCallRecord[] = [
        makeRec('s1', 'web_search', 'done', 120),
        makeRec('s2', 'web_search', 'done', 140),
        makeRec('f1', 'web_fetch', 'done', 200),
        makeRec('f2', 'web_fetch', 'error', 300),
        makeRec('f3', 'web_fetch', 'done', 180),
        makeRec('f4', 'web_fetch', 'error', 90),
        makeRec('x1', 'bad_tool', 'error', 50),
        makeRec('x2', 'bad_tool', 'error', 60)
      ];
      const groups: ToolCallGroup[] = groupToolCallRecords(records);
      expect(groups.length).assertEqual(3);
      expect(groups[0].name).assertEqual('web_search');
      expect(groups[0].count).assertEqual(2);
      expect(groups[0].failedCount).assertEqual(0);
      expect(groups[0].status).assertEqual('done');
      expect(groups[0].totalDurationMs).assertEqual(260);
      expect(groups[1].name).assertEqual('web_fetch');
      expect(groups[1].count).assertEqual(4);
      expect(groups[1].failedCount).assertEqual(2);
      expect(groups[1].status).assertEqual('done');
      expect(groups[1].records.length).assertEqual(4);
      expect(groups[2].name).assertEqual('bad_tool');
      expect(groups[2].count).assertEqual(2);
      expect(groups[2].failedCount).assertEqual(2);
      expect(groups[2].status).assertEqual('error');

      const runningRecords: ToolCallRecord[] = [
        makeRec('r1', 'web_fetch', 'done', 50),
        makeRec('r2', 'web_fetch', 'error', 60),
        makeRec('r3', 'web_fetch', 'running', 0)
      ];
      const runningGroups: ToolCallGroup[] = groupToolCallRecords(runningRecords);
      expect(runningGroups.length).assertEqual(1);
      expect(runningGroups[0].status).assertEqual('running');
      expect(runningGroups[0].failedCount).assertEqual(1);
      expect(runningGroups[0].count).assertEqual(3);
    });

    it('model_spec_editor_overrides_reasoning_sampling_headers_body_and_tools', 0, () => {
      const spec: ModelSpec = defaultModelSpec('custom-think-model');
      spec.displayName = 'Custom Think';
      spec.modelType = 'chat';
      spec.inputModalities = ['text', 'image', 'pdf'];
      spec.outputModalities = ['text', 'image'];
      spec.vision = true;
      spec.tools = true;
      spec.reasoning = true;
      spec.imageGen = true;
      spec.structuredOutput = true;
      spec.pricing = { inputPerMillion: 0.12, outputPerMillion: 0.48, cacheReadPerMillion: 0.0024, currency: 'USD' };
      spec.reasoningDialect = 'thinkingType';
      spec.reasoningLevels = ['low', 'high', 'max'];
      spec.reasoningAllowOff = false;
      spec.reasoningDefaultLevel = 'high';
      spec.samplingPolicy = 'never';
      spec.reasoningReplay = 'all';
      spec.reasoningReplayField = 'reasoning';
      const h1: HeaderEntry = { key: 'X-Model-Header', value: 'model-v1' };
      spec.customHeaders = [h1];
      const b1: HeaderEntry = { key: 'seed', value: '42' };
      const b2: HeaderEntry = { key: 'strict', value: 'true' };
      const b3: HeaderEntry = { key: 'meta', value: '{"tag":"t1"}' };
      spec.customBodyEntries = [b1, b2, b3];
      spec.allowRemoteImageUrls = false;
      spec.builtinCodeInterpreter = true;
      spec.builtinImageGen = true;
      spec.builtinUrlContext = true;

      const cloned = cloneModelSpec(spec);
      cloned.displayName = 'Changed';
      cloned.customHeaders![0].value = 'mutated';
      expect(spec.displayName).assertEqual('Custom Think');
      expect(spec.customHeaders![0].value).assertEqual('model-v1');
      expect(cloned.reasoningDefaultLevel).assertEqual('high');
      expect(cloned.pricing?.cacheReadPerMillion).assertEqual(0.0024);

      const openaiProv = preset('oai-custom', 'OpenAI Custom', 'openai', 'https://api.openai.com/v1', spec.id);
      openaiProv.models = [spec];
      const ctrl = reasoningControl(openaiProv, spec.id, spec);
      expect(ctrl.dialect).assertEqual('thinkingType');
      expect(ctrl.levels.join(',')).assertEqual('low,high,max');

      const attRemote: Attachment = { id: 'a1', name: 'remote.png', mime: 'image/png', data: 'https://example.com/a.png' };
      const attLocal: Attachment = { id: 'a2', name: 'local.png', mime: 'image/png', data: 'AAAA' };
      const atts: Attachment[] = [attRemote, attLocal];
      const m1: ChatMessage = { id: 'm1', role: 'user', text: 'first question', model: spec.id, createdAt: 1000 };
      const m2: ChatMessage = { id: 'm2', role: 'assistant', text: 'first reply', model: spec.id, reasoning: 'prior chain', createdAt: 1001 };
      const m3: ChatMessage = { id: 'm3', role: 'user', text: 'check image', model: spec.id, createdAt: 1002, attachments: atts };
      const history: ChatMessage[] = [m1, m2, m3];
      const call = makeAdvancedChatCall(openaiProv, 'sk-test', 'sys', history, {
        modelId: spec.id,
        modelSpec: spec,
        stream: false,
        params: withReasoning(defaultGenerationParams(), 'high')
      });
      expect(call.headers['X-Model-Header']).assertEqual('model-v1');
      const parsedBody = JSON.parse(call.body) as Record<string, Object>;
      expect(parsedBody['seed']).assertEqual(42);
      expect(parsedBody['strict']).assertEqual(true);
      expect((parsedBody['meta'] as Record<string, Object>)['tag']).assertEqual('t1');
      expect(parsedBody['temperature'] === undefined).assertTrue();
      expect(parsedBody['top_p'] === undefined).assertTrue();
      const wireMsgs = parsedBody['messages'] as Array<Record<string, Object>>;
      expect(wireMsgs[2]['reasoning']).assertEqual('prior chain');
      const userParts = wireMsgs[3]['content'] as Array<Record<string, Object>>;
      expect(userParts.length).assertEqual(2);
      const localImgObj = userParts[1]['image_url'] as Record<string, Object>;
      expect(localImgObj['url']).assertEqual('data:image/png;base64,AAAA');

      const respProv = preset('oai-resp', 'OpenAI Responses', 'openai-responses', 'https://api.openai.com/v1', spec.id);
      respProv.models = [spec];
      const respCall = makeAdvancedChatCall(respProv, 'sk-test', '', [m1], {
        modelId: spec.id,
        modelSpec: spec,
        stream: false,
        params: withReasoning(defaultGenerationParams(), 'high')
      });
      const respBody = JSON.parse(respCall.body) as Record<string, Object>;
      const respTools = respBody['tools'] as Array<Record<string, Object>>;
      const respToolTypes = respTools.map((t: Record<string, Object>): string => String(t['type'] || '')).join(',');
      expect(respToolTypes.includes('code_interpreter')).assertTrue();
      expect(respToolTypes.includes('image_generation')).assertTrue();

      const gemProv = preset('gem-spec', 'Gemini', 'gemini', 'https://generativelanguage.googleapis.com/v1beta', spec.id);
      const gemSpec = cloneModelSpec(spec);
      gemSpec.builtinCodeExec = false;
      gemProv.models = [gemSpec];
      const gemUrlCall = makeAdvancedChatCall(gemProv, 'gm-key', '', [m1], {
        modelId: gemSpec.id,
        modelSpec: gemSpec,
        stream: false,
        builtinUrlContext: true
      });
      expect(gemUrlCall.body.includes('"urlContext"')).assertTrue();

      gemSpec.builtinCodeExec = true;
      const gemCodeCall = makeAdvancedChatCall(gemProv, 'gm-key', '', [m1], {
        modelId: gemSpec.id,
        modelSpec: gemSpec,
        stream: false,
        builtinCodeExec: true
      });
      expect(gemCodeCall.body.includes('"codeExecution"')).assertTrue();
    });
  });
}
