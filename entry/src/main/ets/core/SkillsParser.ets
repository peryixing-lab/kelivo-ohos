import { SkillRecord } from './Models';

export interface ParsedSkillMarkdown {
  name: string;
  description: string;
  body: string;
}

export function parseSkillMarkdown(rawMd: string, fallbackName: string = 'custom-skill'): ParsedSkillMarkdown {
  const normalized = rawMd.replace(/\r\n/g, '\n').trim();
  let name = fallbackName;
  let description = '';
  let body = normalized;

  if (normalized.startsWith('---')) {
    const endFence = normalized.indexOf('\n---', 3);
    if (endFence > 0) {
      const yamlBlock = normalized.slice(3, endFence).trim();
      body = normalized.slice(endFence + 4).trim();
      const lines = yamlBlock.split('\n');
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        const colonIdx = line.indexOf(':');
        if (colonIdx <= 0) {
          continue;
        }
        const k = line.slice(0, colonIdx).trim().toLowerCase();
        let v = line.slice(colonIdx + 1).trim();
        if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
          v = v.slice(1, v.length - 1);
        }
        if (k === 'name' && v.length > 0) {
          name = v;
        } else if (k === 'description' && v.length > 0) {
          description = v;
        }
      }
    }
  }

  if (description.length === 0) {
    const bodyLines = body.split('\n');
    for (let i = 0; i < bodyLines.length; i++) {
      const ln = bodyLines[i].replace(/^#+\s*/, '').trim();
      if (ln.length > 0) {
        description = ln.slice(0, 120);
        break;
      }
    }
  }

  return { name, description, body };
}

/**
 * Resolves GitHub repository, tree, or blob URLs into raw SKILL.md URLs.
 */
export function resolveGitHubSkillRawUrl(inputUrl: string): string {
  const trimmed = inputUrl.trim().replace(/\/+$/, '');
  if (trimmed.length === 0) {
    return '';
  }
  if (trimmed.indexOf('raw.githubusercontent.com/') >= 0) {
    return trimmed.toLowerCase().endsWith('.md') ? trimmed : `${trimmed}/SKILL.md`;
  }
  const ghPrefix = 'https://github.com/';
  if (!trimmed.startsWith(ghPrefix)) {
    return trimmed;
  }
  const rest = trimmed.slice(ghPrefix.length);
  const parts = rest.split('/').filter((s: string): boolean => s.length > 0);
  if (parts.length < 2) {
    return trimmed;
  }
  const owner = parts[0];
  const repo = parts[1];
  if (parts.length === 2) {
    return `https://raw.githubusercontent.com/${owner}/${repo}/main/SKILL.md`;
  }
  if (parts[2] === 'blob' && parts.length >= 5) {
    const branch = parts[3];
    const filePath = parts.slice(4).join('/');
    return `https://raw.githubusercontent.com/${owner}/${repo}/${branch}/${filePath}`;
  }
  if (parts[2] === 'tree' && parts.length >= 4) {
    const branch = parts[3];
    const subPath = parts.slice(4).join('/');
    const base = `https://raw.githubusercontent.com/${owner}/${repo}/${branch}`;
    return subPath.length > 0 ? `${base}/${subPath}/SKILL.md` : `${base}/SKILL.md`;
  }
  return `https://raw.githubusercontent.com/${owner}/${repo}/main/${parts.slice(2).join('/')}/SKILL.md`;
}

export function defaultBuiltinSkills(): SkillRecord[] {
  const now = 1763600000000;
  return [
    {
      id: 'builtin_skill_visualize',
      name: 'visualize',
      description: '使用 Kelivo 内置原生 GenUI DSL (kelivo-ui 代码块) 绘制可交互图表、卡片、状态看板与计算器组件。',
      source: 'builtin',
      enabled: true,
      updatedAt: now,
      markdown:
        '---\nname: visualize\ndescription: Build interactive charts, dashboards, forms and comparisons using kelivo-ui JSON DSL.\n---\n\n' +
        '# Visualize Skill (kelivo-ui)\n\n' +
        '当用户要求可视化数据、绘制对比图、制作可交互小工具时，优先输出一个 ```kelivo-ui fenced JSON 代码块。\n\n' +
        '## 支持组件\n' +
        '- 布局容器：`column`, `row`, `card`\n' +
        '- 展示元素：`text`, `metric`, `badge`, `progress`, `bar-chart`\n' +
        '- 交互控件：`button` (配合 `state` 和 `setState` action 更新界面)、`input`、`toggle`\n\n' +
        '## 示例结构\n' +
        '```json\n' +
        '{\n' +
        '  "state": { "budget": 100 },\n' +
        '  "root": {\n' +
        '    "type": "card",\n' +
        '    "title": "预算概览",\n' +
        '    "children": [\n' +
        '      { "type": "metric", "label": "当前预算", "value": "{{budget}}%" },\n' +
        '      { "type": "progress", "value": "{{budget}}", "max": 100 }\n' +
        '    ]\n' +
        '  }\n' +
        '}\n' +
        '```\n'
    },
    {
      id: 'builtin_skill_creator',
      name: 'skill-creator',
      description: '指导如何设计、编写并验证符合 SKILL.md 规范的 Agent Skill 技能包。',
      source: 'builtin',
      enabled: true,
      updatedAt: now,
      markdown:
        '---\nname: skill-creator\ndescription: Author high-clarity SKILL.md instructions with YAML frontmatter and concrete steps.\n---\n\n' +
        '# Skill Creator Guide\n\n' +
        '1. **Frontmatter 规范**：文件顶部包含 `---\\nname: skill-name\\ndescription: 何时触发该技能及核心能力\\n---`。\n' +
        '2. **渐进披露**：仅在 YAML 描述中保留触发判断所需关键词；在正文详细写出步骤、约束和输入输出示例。\n' +
        '3. **可执行性**：明确需调用的内置工具（如 `read_file`、`browser`、`web_search` 或 `kelivo-ui`）。\n'
    }
  ];
}

export function buildSkillsPromptSummary(skills: SkillRecord[], boundIds?: string[]): string {
  if (!skills || skills.length === 0) {
    return '';
  }
  const hasBound = Boolean(boundIds && boundIds.length > 0);
  const lines: string[] = [];
  for (let i = 0; i < skills.length; i++) {
    const sk = skills[i];
    if (!sk.enabled) {
      continue;
    }
    if (hasBound && boundIds && boundIds.indexOf(sk.id) < 0) {
      continue;
    }
    lines.push(`- ${sk.name}: ${sk.description}`);
  }
  if (lines.length === 0) {
    return '';
  }
  return (
    '# 可用 Agent Skills\n' +
    '如遇下述特定领域任务，请先调用 `read_skill` 工具加载完整 SKILL.md 指南后再执行：\n' +
    lines.join('\n')
  );
}
