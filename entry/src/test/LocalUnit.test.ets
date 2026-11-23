import { describe, expect, it } from '@ohos/hypium';
import {
  ApiFamily,
  ApiKeyEntry,
  AppearanceConfig,
  ChatMessage,
  Conversation,
  InstructionCard,
  MemoryEntry,
  MemorySettings,
  Persona,
  RegexRule,
  ScheduledTask,
  SearchServiceConfig,
  UserProfileField,
  WorldBook,
  defaultAppearance,
  defaultChatItemDisplay,
  defaultGenerationParams,
  defaultModelSpec,
  estimateTokens,
  initialWorkspace,
  isProviderConfigured,
  normalizeAppearanceConfig,
  preset,
  resolveActiveModel
} from '../main/ets/core/Models';
import {
  activateWorldBooks,
  applyRegexRules,
  buildAssembledPrompt,
  expandPromptTemplates,
  parseWorldBookImportJson
} from '../main/ets/core/PromptEngine';
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
import { highlightCode, parseMarkdownBlocks, parseMdInlines } from '../main/ets/core/MarkdownParser';
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
import { ToolExecutionOutput, accumulateToolDeltas, runAgentToolLoop } from '../main/ets/core/ToolLoop';
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
      expect(call.body).assertContain('"web_search_preview"');
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
        provider: preset('openai', 'OpenAI', 'openai', 'https://api.openai.com/v1', 'gpt-4o-mini'),
        apiKey: 'k',
        modelId: 'gpt-4o-mini',
        systemPrompt: '',
        history: [{ id: 'u1', role: 'user', text: '查一下', model: '' }],
        genParams: defaultGenerationParams(),
        tools: [{
          declaration: { name: 'web_search', description: 'search', parametersJson: '{"type":"object"}' },
          source: 'builtin',
          requiresApproval: false
        }],
        permissionMode: 'ask',
        maxSteps: 4,
        runStream: async (_call: ChatCall, onFrag: (f: RichFragment) => void): Promise<void> => {
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
      const cl = preset('cl2', 'Claude', 'anthropic', 'https://api.anthropic.com/v1', 'claude-haiku-5-5');
      const u1: ChatMessage = { id: 'u1', role: 'user', text: 'first', model: '' };
      const u2: ChatMessage = { id: 'u2', role: 'user', text: 'second', model: '' };
      const clCall = makeAdvancedChatCall(cl, 'sk-cl', 'sys', [u1, u2], {
        params: { temperature: 0.7, topP: 1.0, reasoningEffort: 'off' }
      });
      expect(clCall.body).assertContain('"temperature":0.7');
      expect(clCall.body.includes('"top_p"')).assertFalse();
      expect(clCall.body).assertContain('first\\n\\nsecond');

      // 3. Gemini omits empty object parameters and does not mix googleSearch with functionDeclarations
      const gm = preset('gm2', 'Gemini', 'gemini', 'https://generativelanguage.googleapis.com/v1beta', 'gemini-2.5-flash');
      gm.builtinSearch = true;
      const gmCall = makeAdvancedChatCall(gm, 'AIza-test', 'sys', [u1], {
        tools: [{ name: 'get_time_info', description: 'time', parametersJson: '{"type":"object","properties":{}}' }]
      });
      expect(gmCall.body).assertContain('"functionDeclarations"');
      expect(gmCall.body.includes('"parameters"')).assertFalse();
      expect(gmCall.body.includes('"googleSearch"')).assertFalse();

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
      expect(claudeCall.body).assertContain('"max_tokens":8192');

      const xmlBlock = buildExistingMemoryXmlBlock(pool, { autoExtract: true, injectGlobal: true, maxInjectCount: 10 }, undefined, 'zh');
      expect(xmlBlock).assertContain('<user_memory type="identity">');
      const recallRules = buildMemoryRulesSystemPrompt({ autoExtract: true, injectGlobal: true, maxInjectCount: 10, promptLanguage: 'zh' }, 'zh-Hans', true);
      expect(recallRules).assertContain('chat_search');
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
      expect(dsMedium.body).assertContain('"reasoning_effort":"low"');

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
      expect(respOff.body).assertContain('"reasoning":{"effort":"none"}');

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
  });
}
