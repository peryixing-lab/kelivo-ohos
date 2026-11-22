export interface WorkspaceDiffLine {
  kind: 'context' | 'del' | 'add';
  text: string;
}

/**
 * Resolves a relative path safely inside workspaceRoot and throws if it escapes the sandbox.
 */
export function resolveSafeWorkspacePath(workspaceRoot: string, relativePath: string): string {
  const cleanRoot = workspaceRoot.replace(/\\/g, '/').replace(/\/+$/, '');
  if (cleanRoot.length === 0) {
    throw new Error('工作区根目录不能为空');
  }
  const rawRel = (relativePath || '.').replace(/\\/g, '/').trim();
  if (rawRel.startsWith('/') || /^[A-Za-z]:/.test(rawRel)) {
    throw new Error('禁止访问绝对路径，请使用工作区相对路径');
  }
  const segments = rawRel.split('/');
  const stack: string[] = [];
  for (let i = 0; i < segments.length; i++) {
    const seg = segments[i].trim();
    if (seg.length === 0 || seg === '.') {
      continue;
    }
    if (seg === '..') {
      if (stack.length === 0) {
        throw new Error(`路径越界拒绝访问: ${relativePath}`);
      }
      stack.pop();
    } else {
      stack.push(seg);
    }
  }
  if (stack.length === 0) {
    return cleanRoot;
  }
  return `${cleanRoot}/${stack.join('/')}`;
}

export function matchSimpleGlob(relPath: string, pattern: string): boolean {
  const cleanPattern = pattern.trim().replace(/\\/g, '/');
  if (cleanPattern.length === 0 || cleanPattern === '*' || cleanPattern === '**' || cleanPattern === '**/*') {
    return true;
  }
  let reStr = '^';
  let i = 0;
  while (i < cleanPattern.length) {
    const ch = cleanPattern.charAt(i);
    if (ch === '*') {
      if (i + 1 < cleanPattern.length && cleanPattern.charAt(i + 1) === '*') {
        if (i + 2 < cleanPattern.length && cleanPattern.charAt(i + 2) === '/') {
          reStr += '(?:.*/)?';
          i += 3;
        } else {
          reStr += '.*';
          i += 2;
        }
      } else {
        reStr += '[^/]*';
        i += 1;
      }
    } else if (ch === '?') {
      reStr += '[^/]';
      i += 1;
    } else if ('\\^$.|+()[]{}'.indexOf(ch) >= 0) {
      reStr += '\\' + ch;
      i += 1;
    } else {
      reStr += ch;
      i += 1;
    }
  }
  reStr += '$';
  try {
    return new RegExp(reStr, 'i').test(relPath.replace(/\\/g, '/'));
  } catch (_) {
    return relPath.indexOf(pattern) >= 0;
  }
}

export function redactEnvSecrets(text: string, secretValues: string[]): string {
  let out = text;
  for (let i = 0; i < secretValues.length; i++) {
    const val = secretValues[i];
    if (val && val.length >= 4) {
      out = out.split(val).join('***');
    }
  }
  return out;
}

/**
 * Generates a standard unified diff string between oldText and newText.
 */
export function buildUnifiedDiff(relPath: string, oldText: string, newText: string): string {
  if (oldText === newText) {
    return '';
  }
  const oldLines = oldText.length === 0 ? [] : oldText.split('\n');
  const newLines = newText.length === 0 ? [] : newText.split('\n');

  // Trim common prefix and suffix for compact, fast LCS on bounded files.
  let prefix = 0;
  while (prefix < oldLines.length && prefix < newLines.length && oldLines[prefix] === newLines[prefix]) {
    prefix += 1;
  }
  let suffix = 0;
  while (
    suffix < oldLines.length - prefix &&
    suffix < newLines.length - prefix &&
    oldLines[oldLines.length - 1 - suffix] === newLines[newLines.length - 1 - suffix]
  ) {
    suffix += 1;
  }

  const midOld = oldLines.slice(prefix, oldLines.length - suffix);
  const midNew = newLines.slice(prefix, newLines.length - suffix);
  const ops: WorkspaceDiffLine[] = [];

  const ctxStart = Math.max(0, prefix - 2);
  for (let i = ctxStart; i < prefix; i++) {
    ops.push({ kind: 'context', text: oldLines[i] });
  }

  if (midOld.length * midNew.length <= 40000) {
    const m = midOld.length;
    const n = midNew.length;
    const dp: number[][] = [];
    for (let i = 0; i <= m; i++) {
      dp.push(new Array<number>(n + 1).fill(0));
    }
    for (let i = m - 1; i >= 0; i--) {
      for (let j = n - 1; j >= 0; j--) {
        if (midOld[i] === midNew[j]) {
          dp[i][j] = dp[i + 1][j + 1] + 1;
        } else {
          dp[i][j] = dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1];
        }
      }
    }
    let i = 0;
    let j = 0;
    while (i < m && j < n) {
      if (midOld[i] === midNew[j]) {
        ops.push({ kind: 'context', text: midOld[i] });
        i += 1;
        j += 1;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        ops.push({ kind: 'del', text: midOld[i] });
        i += 1;
      } else {
        ops.push({ kind: 'add', text: midNew[j] });
        j += 1;
      }
    }
    while (i < m) {
      ops.push({ kind: 'del', text: midOld[i] });
      i += 1;
    }
    while (j < n) {
      ops.push({ kind: 'add', text: midNew[j] });
      j += 1;
    }
  } else {
    for (let i = 0; i < midOld.length; i++) {
      ops.push({ kind: 'del', text: midOld[i] });
    }
    for (let j = 0; j < midNew.length; j++) {
      ops.push({ kind: 'add', text: midNew[j] });
    }
  }

  const tailStart = oldLines.length - suffix;
  const tailEnd = Math.min(oldLines.length, tailStart + 2);
  for (let i = tailStart; i < tailEnd; i++) {
    ops.push({ kind: 'context', text: oldLines[i] });
  }

  const hunkOldCount = (prefix - ctxStart) + midOld.length + (tailEnd - tailStart);
  const hunkNewCount = (prefix - ctxStart) + midNew.length + (tailEnd - tailStart);
  const header =
    `--- a/${relPath}\n+++ b/${relPath}\n@@ -${ctxStart + 1},${hunkOldCount} +${ctxStart + 1},${hunkNewCount} @@`;
  const body = ops.map((op: WorkspaceDiffLine): string => {
    const ch = op.kind === 'del' ? '-' : (op.kind === 'add' ? '+' : ' ');
    return `${ch}${op.text}`;
  });
  return `${header}\n${body.join('\n')}`;
}
