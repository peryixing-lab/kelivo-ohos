import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import {
  clearDirectoryFiles,
  ensureDir,
  readBinaryFile,
  readFileHandleBytes,
  writeBinaryFile
} from './AttachmentStore';
import { Attachment, EnvVar, LocalWorkspace } from './Models';
import { readKey } from './Storage';
import { ToolExecutionOutput } from './ToolLoop';
import { RegisteredTool } from './ToolRegistry';
import { buildUnifiedDiff, matchSimpleGlob, redactEnvSecrets, resolveSafeWorkspacePath } from './WorkspaceDiff';

export interface WorkspaceFileItem {
  name: string;
  relPath: string;
  isDir: boolean;
  sizeBytes: number;
}

export function getWorkspacesBaseDir(filesDir: string): string {
  return `${filesDir}/workspaces`;
}

export async function createSandboxWorkspace(filesDir: string, id: string, name: string): Promise<LocalWorkspace> {
  const root = `${getWorkspacesBaseDir(filesDir)}/${id}`;
  await ensureDir(root);
  return {
    id,
    name: name.trim().length > 0 ? name.trim() : '工作区',
    rootPath: root,
    createdAt: Date.now()
  };
}

export async function listWorkspaceTree(
  rootPath: string,
  relDir: string = '',
  recursive: boolean = false
): Promise<WorkspaceFileItem[]> {
  const targetDir = resolveSafeWorkspacePath(rootPath, relDir);
  await ensureDir(targetDir);
  const out: WorkspaceFileItem[] = [];
  await walkDir(targetDir, relDir.replace(/^\/+|\/+$/g, ''), recursive, out, 0);
  out.sort((a: WorkspaceFileItem, b: WorkspaceFileItem): number => {
    if (a.isDir !== b.isDir) {
      return a.isDir ? -1 : 1;
    }
    return a.relPath < b.relPath ? -1 : (a.relPath > b.relPath ? 1 : 0);
  });
  return out;
}

async function walkDir(
  absDir: string,
  relPrefix: string,
  recursive: boolean,
  out: WorkspaceFileItem[],
  depth: number
): Promise<void> {
  if (depth > 8 || out.length >= 600) {
    return;
  }
  let names: string[] = [];
  try {
    names = await fs.listFile(absDir);
  } catch (_) {
    return;
  }
  for (let i = 0; i < names.length; i++) {
    if (out.length >= 600) {
      break;
    }
    const name = names[i];
    const absChild = `${absDir}/${name}`;
    const relChild = relPrefix.length > 0 ? `${relPrefix}/${name}` : name;
    try {
      const st = await fs.stat(absChild);
      const isDir = st.isDirectory();
      out.push({ name, relPath: relChild, isDir, sizeBytes: isDir ? 0 : st.size });
      if (isDir && recursive) {
        await walkDir(absChild, relChild, true, out, depth + 1);
      }
    } catch (_) {}
  }
}

export async function readWorkspaceText(rootPath: string, relPath: string): Promise<string> {
  const abs = resolveSafeWorkspacePath(rootPath, relPath);
  const bytes = await readBinaryFile(abs);
  return util.TextDecoder.create('utf-8').decodeToString(bytes);
}

export async function writeWorkspaceText(rootPath: string, relPath: string, content: string): Promise<void> {
  const abs = resolveSafeWorkspacePath(rootPath, relPath);
  const slashIdx = abs.lastIndexOf('/');
  if (slashIdx > 0) {
    await ensureDir(abs.slice(0, slashIdx));
  }
  const bytes = util.TextEncoder.create().encodeInto(content);
  await writeBinaryFile(abs, bytes);
}

export async function deleteWorkspaceItem(rootPath: string, relPath: string): Promise<void> {
  const abs = resolveSafeWorkspacePath(rootPath, relPath);
  if (abs === rootPath.replace(/\/+$/, '')) {
    throw new Error('不能删除工作区根目录');
  }
  const st = await fs.stat(abs);
  if (st.isDirectory()) {
    await clearDirectoryFiles(abs);
    await fs.rmdir(abs);
  } else {
    await fs.unlink(abs);
  }
}

export async function importPickerFilesToWorkspace(
  ctx: common.UIAbilityContext,
  rootPath: string
): Promise<number> {
  await ensureDir(rootPath);
  const uris = await new picker.DocumentViewPicker(ctx).select({ maxSelectNumber: 10 });
  if (!uris || uris.length === 0) {
    return 0;
  }
  let count = 0;
  for (let i = 0; i < uris.length; i++) {
    const uri = uris[i];
    const parts = uri.split('/');
    const rawName = parts[parts.length - 1] || `import_${Date.now()}_${i}`;
    const safeName = decodeURIComponent(rawName).replace(/[\\/:*?"<>|]/g, '_');
    const file = await fs.open(uri, fs.OpenMode.READ_ONLY);
    try {
      const bytes = await readFileHandleBytes(file);
      const dest = resolveSafeWorkspacePath(rootPath, safeName);
      await writeBinaryFile(dest, bytes);
      count += 1;
    } finally {
      await fs.close(file);
    }
  }
  return count;
}

export function buildWorkspaceTools(): RegisteredTool[] {
  return [
    {
      declaration: {
        name: 'read_file',
        description: '读取绑定沙箱工作区内的文本文件内容，支持指定起止行号（1-based）。',
        parametersJson:
          '{"type":"object","properties":{"path":{"type":"string","description":"工作区相对路径"},"start_line":{"type":"integer","description":"起始行号(从1开始)"},"end_line":{"type":"integer","description":"结束行号"}},"required":["path"]}'
      },
      source: 'workspace',
      requiresApproval: false
    },
    {
      declaration: {
        name: 'write_file',
        description: '在绑定沙箱工作区内创建或覆写文件，并生成统一 Diff 变更预览。',
        parametersJson:
          '{"type":"object","properties":{"path":{"type":"string","description":"相对路径"},"content":{"type":"string","description":"完整文件内容"}},"required":["path","content"]}'
      },
      source: 'workspace',
      requiresApproval: true
    },
    {
      declaration: {
        name: 'edit_file',
        description: '精确替换工作区文件内的指定文本块，并返回 Unified Diff 变更对比。',
        parametersJson:
          '{"type":"object","properties":{"path":{"type":"string","description":"相对路径"},"old_text":{"type":"string","description":"待替换的原文本"},"new_text":{"type":"string","description":"替换后的新文本"},"replace_all":{"type":"boolean","description":"是否替换全部匹配项"}},"required":["path","old_text","new_text"]}'
      },
      source: 'workspace',
      requiresApproval: true
    },
    {
      declaration: {
        name: 'list_dir',
        description: '列出绑定沙箱工作区目录下的文件和子目录。',
        parametersJson:
          '{"type":"object","properties":{"path":{"type":"string","description":"子目录相对路径，默认为根目录"},"recursive":{"type":"boolean","description":"是否递归列出"}}}'
      },
      source: 'workspace',
      requiresApproval: false
    },
    {
      declaration: {
        name: 'glob',
        description: '按通配符模式（如 **/*.ets, *.json）检索沙箱工作区内的文件列表。',
        parametersJson:
          '{"type":"object","properties":{"pattern":{"type":"string","description":"Glob 匹配模式"},"path":{"type":"string","description":"起始子目录"}},"required":["pattern"]}'
      },
      source: 'workspace',
      requiresApproval: false
    },
    {
      declaration: {
        name: 'grep',
        description: '在沙箱工作区文本文件中搜索指定关键词或正则表达式，返回匹配文件名与行号。',
        parametersJson:
          '{"type":"object","properties":{"pattern":{"type":"string","description":"关键词或正则表达式"},"path":{"type":"string","description":"限定子目录或单文件"},"regex":{"type":"boolean","description":"是否按正则匹配"}},"required":["pattern"]}'
      },
      source: 'workspace',
      requiresApproval: false
    },
    {
      declaration: {
        name: 'view_image',
        description: '读取工作区中的图片文件并作为视觉图像返回给模型查看。',
        parametersJson:
          '{"type":"object","properties":{"path":{"type":"string","description":"工作区图片相对路径"}},"required":["path"]}'
      },
      source: 'workspace',
      requiresApproval: false
    }
  ];
}

async function resolveAllEnvSecretValues(envVars: EnvVar[]): Promise<string[]> {
  const secrets: string[] = [];
  for (let i = 0; i < envVars.length; i++) {
    const val = await readKey(envVars[i].secretRef);
    if (val && val.length >= 4) {
      secrets.push(val);
    }
  }
  return secrets;
}

export async function executeWorkspaceTool(
  toolName: string,
  argsJson: string,
  workspace: LocalWorkspace | undefined,
  envVars: EnvVar[]
): Promise<ToolExecutionOutput> {
  if (!workspace) {
    return { text: '当前对话未绑定本地沙箱工作区，请在工作区设置或助手绑定中启用后再调用此工具。', isError: true };
  }
  let args: Record<string, Object> = {};
  try {
    args = JSON.parse(argsJson || '{}') as Record<string, Object>;
  } catch (_) {
    return { text: '参数 JSON 解析失败', isError: true };
  }
  const secretValues = await resolveAllEnvSecretValues(envVars);
  const root = workspace.rootPath;

  try {
    if (toolName === 'list_dir') {
      const sub = typeof args['path'] === 'string' ? (args['path'] as string) : '';
      const rec = Boolean(args['recursive']);
      const items = await listWorkspaceTree(root, sub, rec);
      if (items.length === 0) {
        return { text: '目录为空' };
      }
      const lines = items.map((it: WorkspaceFileItem): string =>
        it.isDir ? `[DIR]  ${it.relPath}/` : `[FILE] ${it.relPath} (${it.sizeBytes} B)`
      );
      return { text: redactEnvSecrets(lines.join('\n'), secretValues) };
    }

    if (toolName === 'read_file') {
      const rel = String(args['path'] || '');
      const full = await readWorkspaceText(root, rel);
      const lines = full.split('\n');
      const start = typeof args['start_line'] === 'number' ? Math.max(1, args['start_line'] as number) : 1;
      const end = typeof args['end_line'] === 'number' ? Math.min(lines.length, args['end_line'] as number) : lines.length;
      const chunk: string[] = [];
      for (let i = start - 1; i < end && i < lines.length; i++) {
        chunk.push(`${i + 1}: ${lines[i]}`);
      }
      return { text: redactEnvSecrets(chunk.join('\n').slice(0, 24000), secretValues) };
    }

    if (toolName === 'write_file') {
      const rel = String(args['path'] || '');
      const nextText = String(args['content'] ?? '');
      let oldText = '';
      try {
        oldText = await readWorkspaceText(root, rel);
      } catch (_) {}
      await writeWorkspaceText(root, rel, nextText);
      const diff = redactEnvSecrets(buildUnifiedDiff(rel, oldText, nextText), secretValues);
      return {
        text: `已写入 ${rel} (${nextText.length} 字符)`,
        diffText: diff.length > 0 ? diff : undefined
      };
    }

    if (toolName === 'edit_file') {
      const rel = String(args['path'] || '');
      const oldPart = String(args['old_text'] || '');
      const newPart = String(args['new_text'] ?? '');
      const replaceAll = Boolean(args['replace_all']);
      const current = await readWorkspaceText(root, rel);
      if (oldPart.length === 0 || current.indexOf(oldPart) < 0) {
        return { text: `未在 ${rel} 中找到指定的 old_text 原文`, isError: true };
      }
      const updated = replaceAll ? current.split(oldPart).join(newPart) : current.replace(oldPart, newPart);
      await writeWorkspaceText(root, rel, updated);
      const diff = redactEnvSecrets(buildUnifiedDiff(rel, current, updated), secretValues);
      return {
        text: `已局部更新 ${rel}`,
        diffText: diff.length > 0 ? diff : undefined
      };
    }

    if (toolName === 'glob') {
      const pattern = String(args['pattern'] || '**/*');
      const sub = typeof args['path'] === 'string' ? (args['path'] as string) : '';
      const all = await listWorkspaceTree(root, sub, true);
      const hits: string[] = [];
      for (let i = 0; i < all.length; i++) {
        if (!all[i].isDir && matchSimpleGlob(all[i].relPath, pattern)) {
          hits.push(all[i].relPath);
        }
      }
      return { text: hits.length > 0 ? hits.join('\n') : '未匹配到任何文件' };
    }

    if (toolName === 'grep') {
      const rawPat = String(args['pattern'] || '');
      const sub = typeof args['path'] === 'string' ? (args['path'] as string) : '';
      const useRegex = Boolean(args['regex']);
      if (rawPat.length === 0) {
        return { text: 'pattern 不能为空', isError: true };
      }
      const all = await listWorkspaceTree(root, sub, true);
      const matches: string[] = [];
      const re = useRegex ? new RegExp(rawPat, 'i') : undefined;
      for (let i = 0; i < all.length && matches.length < 150; i++) {
        const item = all[i];
        if (item.isDir || item.sizeBytes > 512000) {
          continue;
        }
        try {
          const text = await readWorkspaceText(root, item.relPath);
          const lines = text.split('\n');
          for (let ln = 0; ln < lines.length && matches.length < 150; ln++) {
            const line = lines[ln];
            const hit = re ? re.test(line) : line.toLowerCase().indexOf(rawPat.toLowerCase()) >= 0;
            if (hit) {
              matches.push(`${item.relPath}:${ln + 1}: ${line.slice(0, 180)}`);
            }
          }
        } catch (_) {}
      }
      return {
        text: matches.length > 0 ? redactEnvSecrets(matches.join('\n'), secretValues) : '未找到匹配内容'
      };
    }

    if (toolName === 'view_image') {
      const rel = String(args['path'] || '');
      const abs = resolveSafeWorkspacePath(root, rel);
      const bytes = await readBinaryFile(abs);
      const lower = rel.toLowerCase();
      const mime = lower.endsWith('.png') ? 'image/png' : (lower.endsWith('.webp') ? 'image/webp' : 'image/jpeg');
      const b64 = new util.Base64Helper().encodeToStringSync(bytes);
      const att: Attachment = {
        name: rel,
        mime,
        data: b64,
        filePath: abs,
        sizeBytes: bytes.length,
        kind: 'image'
      };
      return { text: `已读取图像 ${rel} (${bytes.length} B)`, images: [att] };
    }
  } catch (e) {
    return { text: `工作区操作失败: ${(e as Error).message || String(e)}`, isError: true };
  }

  return { text: `未知工作区工具: ${toolName}`, isError: true };
}
