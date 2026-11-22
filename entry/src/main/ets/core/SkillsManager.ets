import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { readFileHandleBytes } from './AttachmentStore';
import { SkillRecord } from './Models';
import { parseSkillMarkdown, resolveGitHubSkillRawUrl } from './SkillsParser';
import { newId } from './Storage';
import { ToolExecutionOutput } from './ToolLoop';
import { RegisteredTool } from './ToolRegistry';
import { extractZipEntryText, listZipEntries } from './ZipReader';

async function httpGetText(url: string): Promise<string> {
  const req = http.createHttp();
  try {
    const resp = await req.request(url, {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 12000,
      readTimeout: 15000
    });
    if (resp.responseCode < 200 || resp.responseCode >= 300) {
      throw new Error(`HTTP ${resp.responseCode}`);
    }
    return typeof resp.result === 'string' ? resp.result : JSON.stringify(resp.result);
  } finally {
    req.destroy();
  }
}

export function createSkillFromMarkdown(
  rawMd: string,
  source: 'builtin' | 'local' | 'github',
  sourceUrl?: string,
  fallbackName: string = 'custom-skill'
): SkillRecord {
  const parsed = parseSkillMarkdown(rawMd, fallbackName);
  return {
    id: 'sk_' + newId(),
    name: parsed.name,
    description: parsed.description,
    markdown: rawMd,
    source,
    sourceUrl,
    enabled: true,
    updatedAt: Date.now()
  };
}

export async function fetchSkillFromUrl(inputUrl: string): Promise<SkillRecord> {
  const rawUrl = resolveGitHubSkillRawUrl(inputUrl);
  if (rawUrl.length === 0) {
    throw new Error('请输入有效的 GitHub 或 SKILL.md URL');
  }
  let md = '';
  try {
    md = await httpGetText(rawUrl);
  } catch (e) {
    if (rawUrl.indexOf('/main/') >= 0) {
      md = await httpGetText(rawUrl.replace('/main/', '/master/'));
    } else {
      throw e as Error;
    }
  }
  if (md.trim().length === 0) {
    throw new Error('下载的 SKILL.md 内容为空');
  }
  return createSkillFromMarkdown(md, 'github', inputUrl.trim());
}

export async function importSkillsFromPicker(ctx: common.UIAbilityContext): Promise<SkillRecord[]> {
  const uris = await new picker.DocumentViewPicker(ctx).select({
    maxSelectNumber: 5,
    fileSuffixFilters: ['Skill 文件|.md,.markdown,.zip']
  });
  if (!uris || uris.length === 0) {
    return [];
  }
  const imported: SkillRecord[] = [];
  for (let i = 0; i < uris.length; i++) {
    const uri = uris[i];
    const file = await fs.open(uri, fs.OpenMode.READ_ONLY);
    try {
      const bytes = await readFileHandleBytes(file);
      const lower = uri.toLowerCase();
      if (lower.endsWith('.zip')) {
        const entries = listZipEntries(bytes);
        for (let j = 0; j < entries.length; j++) {
          const entryName = entries[j].name;
          const base = entryName.split('/').pop()?.toLowerCase() || '';
          if (base === 'skill.md' || entryName.toLowerCase().endsWith('.md')) {
            try {
              const text = await extractZipEntryText(bytes, entryName);
              if (text.trim().length > 0) {
                const folderName = entryName.split('/').slice(-2, -1)[0] || base.replace(/\.md$/i, '');
                imported.push(createSkillFromMarkdown(text, 'local', undefined, folderName));
              }
            } catch (_) {}
          }
        }
      } else {
        const text = util.TextDecoder.create('utf-8').decodeToString(bytes);
        const fileName = decodeURIComponent(uri.split('/').pop() || 'skill').replace(/\.md$/i, '');
        if (text.trim().length > 0) {
          imported.push(createSkillFromMarkdown(text, 'local', undefined, fileName));
        }
      }
    } finally {
      await fs.close(file);
    }
  }
  return imported;
}

export function buildSkillTools(): RegisteredTool[] {
  return [
    {
      declaration: {
        name: 'read_skill',
        description: '加载指定 Agent Skill 的完整 SKILL.md 指导规范与工作流说明。',
        parametersJson:
          '{"type":"object","properties":{"name":{"type":"string","description":"Skill 名称"}},"required":["name"]}'
      },
      source: 'skill',
      requiresApproval: false
    }
  ];
}

export function executeSkillTool(argsJson: string, skills: SkillRecord[]): ToolExecutionOutput {
  let args: Record<string, Object> = {};
  try {
    args = JSON.parse(argsJson || '{}') as Record<string, Object>;
  } catch (_) {
    return { text: '参数 JSON 解析失败', isError: true };
  }
  const targetName = String(args['name'] || '').trim().toLowerCase();
  if (targetName.length === 0) {
    const names = skills.filter((s: SkillRecord): boolean => s.enabled).map((s: SkillRecord): string => s.name);
    return { text: `可用 Skills: ${names.join(', ')}` };
  }
  const found = skills.find((s: SkillRecord): boolean =>
    s.enabled && s.name.toLowerCase() === targetName
  ) ?? skills.find((s: SkillRecord): boolean =>
    s.enabled && s.name.toLowerCase().indexOf(targetName) >= 0
  );
  if (!found) {
    return { text: `未找到名为「${targetName}」的已启用 Skill`, isError: true };
  }
  return { text: `# Skill: ${found.name}\n\n${found.markdown}` };
}
