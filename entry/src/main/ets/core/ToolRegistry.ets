import { McpServerConfig, SearchServiceConfig, SystemSettings, ToolSchemaOverride } from './Models';
import { ToolDeclaration } from './Protocol';

export type ToolSourceKind = 'builtin' | 'mcp' | 'workspace' | 'browser' | 'memory' | 'skill' | 'device';

export interface RegisteredTool {
  declaration: ToolDeclaration;
  source: ToolSourceKind;
  serverId?: string;
  requiresApproval: boolean;
}

export interface ToolBuildInputs {
  searchService?: SearchServiceConfig;
  searchEnabled: boolean;
  builtinFetchEnabled: boolean;
  mcpTools: McpDiscoveredDescriptor[];
  mcpServers: McpServerConfig[];
  extraTools: RegisteredTool[];
  overrides: ToolSchemaOverride[];
}

export interface McpDiscoveredDescriptor {
  serverId: string;
  name: string;
  description: string;
  parametersJson: string;
}

export function buildWebSearchToolDecl(): ToolDeclaration {
  return {
    name: 'web_search',
    description: '使用联网搜索引擎检索最新公开网页信息并返回标题、URL 和摘要。当需要实时资讯、核查事实或用户询问近期事件时调用。',
    parametersJson: '{"type":"object","properties":{"query":{"type":"string","description":"搜索关键词"}},"required":["query"]}'
  };
}

export function buildWebFetchToolDecl(): ToolDeclaration {
  return {
    name: 'web_fetch',
    description: '抓取指定 HTTP/HTTPS 网页的正文并转为纯文本，支持分页读取。',
    parametersJson: '{"type":"object","properties":{"url":{"type":"string","description":"完整网页 URL"},"max_chars":{"type":"integer","description":"最大字符数，默认 8000"},"offset":{"type":"integer","description":"起始偏移，默认 0"}},"required":["url"]}'
  };
}

export function applyToolSchemaOverrides(
  tools: RegisteredTool[],
  overrides: ToolSchemaOverride[]
): RegisteredTool[] {
  const overrideMap = new Map<string, ToolSchemaOverride>();
  for (let i = 0; i < overrides.length; i++) {
    overrideMap.set(overrides[i].toolName, overrides[i]);
  }
  const out: RegisteredTool[] = [];
  for (let i = 0; i < tools.length; i++) {
    const t = tools[i];
    const ov = overrideMap.get(t.declaration.name);
    if (ov && !ov.enabled) continue;
    const decl: ToolDeclaration = ov && ov.customDescription.trim()
      ? {
          name: t.declaration.name,
          description: ov.customDescription.trim(),
          parametersJson: t.declaration.parametersJson
        }
      : t.declaration;
    out.push({
      declaration: decl,
      source: t.source,
      serverId: t.serverId,
      requiresApproval: t.requiresApproval
    });
  }
  return out;
}

export function assembleToolRegistry(inputs: ToolBuildInputs): RegisteredTool[] {
  const list: RegisteredTool[] = [];
  const usedNames = new Set<string>();

  const pushUnique = (item: RegisteredTool): void => {
    if (usedNames.has(item.declaration.name)) return;
    usedNames.add(item.declaration.name);
    list.push(item);
  };

  if (inputs.searchEnabled && inputs.searchService?.mode === 'agent_tool') {
    pushUnique({
      declaration: buildWebSearchToolDecl(),
      source: 'builtin',
      requiresApproval: false
    });
  }
  if (inputs.builtinFetchEnabled || (inputs.searchEnabled && inputs.searchService?.webFetchEnabled)) {
    pushUnique({
      declaration: buildWebFetchToolDecl(),
      source: 'builtin',
      requiresApproval: false
    });
  }

  for (let i = 0; i < inputs.mcpTools.length; i++) {
    const mt = inputs.mcpTools[i];
    const srv = inputs.mcpServers.find((s: McpServerConfig): boolean => s.id === mt.serverId);
    const autoApprove = srv ? srv.autoApproveTools.includes(mt.name) : false;
    pushUnique({
      declaration: {
        name: mt.name,
        description: mt.description || mt.name,
        parametersJson: mt.parametersJson || '{"type":"object","properties":{}}'
      },
      source: 'mcp',
      serverId: mt.serverId,
      requiresApproval: !autoApprove
    });
  }

  for (let i = 0; i < inputs.extraTools.length; i++) {
    pushUnique(inputs.extraTools[i]);
  }

  return applyToolSchemaOverrides(list, inputs.overrides);
}

export function defaultMaxToolSteps(settings?: SystemSettings): number {
  return Math.max(1, Math.min(24, settings?.maxToolSteps || 10));
}
