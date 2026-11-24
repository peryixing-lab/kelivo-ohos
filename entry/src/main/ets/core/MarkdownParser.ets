export type MdBlockKind =
  'heading' | 'paragraph' | 'code' | 'table' | 'blockquote' | 'list' | 'hr' | 'math_block' | 'image' | 'gen_ui';

export interface MdListItem {
  text: string;
  ordered: boolean;
  index: number;
  checked?: boolean;
}

export interface MdBlock {
  kind: MdBlockKind;
  text: string;
  level: number;
  language: string;
  headers: string[];
  rows: string[][];
  items: MdListItem[];
  imageUrl: string;
  imageAlt: string;
}

export type MdInlineKind =
  'text' | 'bold' | 'italic' | 'bold_italic' | 'strike' | 'code' | 'link' | 'math_inline';

export interface MdInline {
  kind: MdInlineKind;
  text: string;
  url: string;
}

export type CodeTokenKind = 'keyword' | 'string' | 'number' | 'comment' | 'type' | 'plain';

export interface CodeToken {
  kind: CodeTokenKind;
  text: string;
}

export interface CodeLine {
  tokens: CodeToken[];
}

function splitTableRow(line: string): string[] {
  let trimmed = line.trim();
  if (trimmed.startsWith('|')) trimmed = trimmed.slice(1);
  if (trimmed.endsWith('|')) trimmed = trimmed.slice(0, -1);
  const cells = trimmed.split('|');
  return cells.map((c: string): string => c.trim());
}

function isTableSeparator(line: string): boolean {
  const trimmed = line.trim();
  if (!trimmed.includes('-')) return false;
  return /^\|?(\s*:?-+:?\s*\|)+\s*:?-+:?\s*\|?$/.test(trimmed) || /^\|?\s*:?-+:?\s*\|?$/.test(trimmed);
}

function isListLine(line: string): boolean {
  return /^\s*(?:[-*+]\s+(?:\[[ xX]\]\s+)?|\d+\.\s+)/.test(line);
}

function parseListItem(line: string, fallbackIndex: number): MdListItem {
  const taskMatch = line.match(/^\s*[-*+]\s+\[([ xX])\]\s+(.*)$/);
  if (taskMatch) {
    return {
      text: taskMatch[2],
      ordered: false,
      index: fallbackIndex,
      checked: taskMatch[1].toLowerCase() === 'x'
    };
  }
  const ordMatch = line.match(/^\s*(\d+)\.\s+(.*)$/);
  if (ordMatch) {
    return {
      text: ordMatch[2],
      ordered: true,
      index: Number(ordMatch[1]) || fallbackIndex
    };
  }
  const unordMatch = line.match(/^\s*[-*+]\s+(.*)$/);
  return {
    text: unordMatch ? unordMatch[1] : line.trim(),
    ordered: false,
    index: fallbackIndex
  };
}

export function parseMarkdownBlocks(source: string): MdBlock[] {
  const blocks: MdBlock[] = [];
  if (!source) return blocks;
  const lines = source.replace(/\r\n/g, '\n').split('\n');
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];
    const trimmed = line.trim();

    if (!trimmed) {
      i++;
      continue;
    }

    // Fenced code / gen_ui / math block
    const fenceMatch = trimmed.match(/^(```|~~~)(.*)$/);
    if (fenceMatch) {
      const fence = fenceMatch[1];
      const lang = fenceMatch[2].trim();
      const bodyLines: string[] = [];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith(fence)) {
        bodyLines.push(lines[i]);
        i++;
      }
      if (i < lines.length) i++;
      const body = bodyLines.join('\n');
      const lowerLang = lang.toLowerCase();
      if (lowerLang === 'kelivo-ui') {
        blocks.push({
          kind: 'gen_ui', text: body, level: 0, language: lang,
          headers: [], rows: [], items: [], imageUrl: '', imageAlt: ''
        });
      } else if (lowerLang === 'math' || lowerLang === 'latex') {
        blocks.push({
          kind: 'math_block', text: body, level: 0, language: lang,
          headers: [], rows: [], items: [], imageUrl: '', imageAlt: ''
        });
      } else {
        blocks.push({
          kind: 'code', text: body, level: 0, language: lang,
          headers: [], rows: [], items: [], imageUrl: '', imageAlt: ''
        });
      }
      continue;
    }

    // Display math $$ ... $$
    if (trimmed.startsWith('$$')) {
      if (trimmed.length > 4 && trimmed.endsWith('$$')) {
        blocks.push({
          kind: 'math_block', text: trimmed.slice(2, -2).trim(), level: 0, language: 'latex',
          headers: [], rows: [], items: [], imageUrl: '', imageAlt: ''
        });
        i++;
        continue;
      }
      const mathLines: string[] = [];
      const firstRest = trimmed.slice(2).trim();
      if (firstRest) mathLines.push(firstRest);
      i++;
      while (i < lines.length && !lines[i].trim().endsWith('$$')) {
        mathLines.push(lines[i]);
        i++;
      }
      if (i < lines.length) {
        const endLine = lines[i].trim();
        const endRest = endLine.slice(0, -2).trim();
        if (endRest) mathLines.push(endRest);
        i++;
      }
      blocks.push({
        kind: 'math_block', text: mathLines.join('\n'), level: 0, language: 'latex',
        headers: [], rows: [], items: [], imageUrl: '', imageAlt: ''
      });
      continue;
    }

    // Horizontal rule
    if (/^(?:---+|\*\*\*+|___+)$/.test(trimmed)) {
      blocks.push({
        kind: 'hr', text: '', level: 0, language: '',
        headers: [], rows: [], items: [], imageUrl: '', imageAlt: ''
      });
      i++;
      continue;
    }

    // Heading
    const headingMatch = trimmed.match(/^(#{1,6})\s+(.*)$/);
    if (headingMatch) {
      blocks.push({
        kind: 'heading', text: headingMatch[2], level: headingMatch[1].length, language: '',
        headers: [], rows: [], items: [], imageUrl: '', imageAlt: ''
      });
      i++;
      continue;
    }

    // Standalone Markdown image
    const imgMatch = trimmed.match(/^!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)$/);
    if (imgMatch) {
      blocks.push({
        kind: 'image', text: imgMatch[1], level: 0, language: '',
        headers: [], rows: [], items: [], imageUrl: imgMatch[2], imageAlt: imgMatch[1]
      });
      i++;
      continue;
    }

    // GFM Table
    if (trimmed.includes('|') && i + 1 < lines.length && isTableSeparator(lines[i + 1])) {
      const headers = splitTableRow(trimmed);
      i += 2;
      const rows: string[][] = [];
      while (i < lines.length && lines[i].trim().includes('|') && !lines[i].trim().startsWith('```')) {
        rows.push(splitTableRow(lines[i]));
        i++;
      }
      blocks.push({
        kind: 'table', text: '', level: 0, language: '',
        headers, rows, items: [], imageUrl: '', imageAlt: ''
      });
      continue;
    }

    // Blockquote
    if (trimmed.startsWith('>')) {
      const qLines: string[] = [];
      while (i < lines.length && lines[i].trim().startsWith('>')) {
        qLines.push(lines[i].trim().replace(/^>\s?/, ''));
        i++;
      }
      blocks.push({
        kind: 'blockquote', text: qLines.join('\n'), level: 0, language: '',
        headers: [], rows: [], items: [], imageUrl: '', imageAlt: ''
      });
      continue;
    }

    // List
    if (isListLine(line)) {
      const items: MdListItem[] = [];
      let idx = 1;
      while (i < lines.length && isListLine(lines[i])) {
        items.push(parseListItem(lines[i], idx));
        idx++;
        i++;
      }
      blocks.push({
        kind: 'list', text: '', level: 0, language: '',
        headers: [], rows: [], items, imageUrl: '', imageAlt: ''
      });
      continue;
    }

    // Paragraph
    const pLines: string[] = [line];
    i++;
    while (i < lines.length) {
      const next = lines[i];
      const nextTrim = next.trim();
      if (!nextTrim || /^(```|~~~|\$\$|#{1,6}\s|>|---+|\*\*\*+|___+)/.test(nextTrim) ||
        isListLine(next) || (nextTrim.includes('|') && i + 1 < lines.length && isTableSeparator(lines[i + 1]))) {
        break;
      }
      pLines.push(next);
      i++;
    }
    blocks.push({
      kind: 'paragraph', text: pLines.join('\n'), level: 0, language: '',
      headers: [], rows: [], items: [], imageUrl: '', imageAlt: ''
    });
  }

  return blocks;
}

export interface InlineTailSplit {
  prefix: MdInline[];
  suffix: string;
}

export function splitInlineTail(source: string): InlineTailSplit {
  const runs = parseMdInlines(source);
  if (runs.length > 0 && runs[runs.length - 1].kind === 'text') {
    return {
      prefix: runs.slice(0, runs.length - 1),
      suffix: runs[runs.length - 1].text
    };
  }
  return {
    prefix: runs,
    suffix: ''
  };
}

export function findStableMarkdownPrefixEnd(source: string): number {
  if (!source) return 0;
  let pos = 0;
  let inFence = false;
  let fencePrefix = '';
  let inMath = false;
  let sawContent = false;
  let candidateCut = 0;
  let lastConfirmedCut = 0;

  while (pos < source.length) {
    const nlIdx = source.indexOf('\n', pos);
    const hasNewline = nlIdx >= 0;
    const rawLineEnd = hasNewline ? nlIdx : source.length;
    const contentEnd = (rawLineEnd > pos && source[rawLineEnd - 1] === '\r') ? rawLineEnd - 1 : rawLineEnd;
    const trimmed = source.slice(pos, contentEnd).trim();
    const lineEndPos = hasNewline ? nlIdx + 1 : source.length;

    if (inFence) {
      if (trimmed.startsWith(fencePrefix)) {
        inFence = false;
        fencePrefix = '';
      }
    } else if (inMath) {
      if (trimmed.endsWith('$$')) {
        inMath = false;
      }
    } else if (!trimmed) {
      if (sawContent && hasNewline) {
        candidateCut = lineEndPos;
      }
    } else {
      if (candidateCut > lastConfirmedCut) {
        lastConfirmedCut = candidateCut;
      }
      sawContent = true;
      const fenceMatch = trimmed.match(/^(```|~~~)(.*)$/);
      if (fenceMatch) {
        inFence = true;
        fencePrefix = fenceMatch[1];
      } else if (trimmed.startsWith('$$')) {
        if (!(trimmed.length > 4 && trimmed.endsWith('$$'))) {
          inMath = true;
        }
      }
    }

    pos = lineEndPos;
  }

  return lastConfirmedCut;
}

const INLINE_PATTERN = /(\*\*\*[^*\n]+\*\*\*|\*\*[^*\n]+\*\*|__[^_\n]+__|~~[^~\n]+~~|`[^`\n]+`|\$[^$\n]+\$|\[[^\]\n]+\]\(https?:\/\/[^)\s]+\)|https?:\/\/[^\s<>()]+|\*[^*\n]+\*)/g;

export function parseMdInlines(source: string): MdInline[] {
  if (!source) return [];
  const parts = source.split(INLINE_PATTERN);
  const runs: MdInline[] = [];
  for (let i = 0; i < parts.length; i++) {
    const s = parts[i];
    if (!s) continue;
    if (s.startsWith('***') && s.endsWith('***') && s.length > 6) {
      runs.push({ kind: 'bold_italic', text: s.slice(3, -3), url: '' });
    } else if ((s.startsWith('**') && s.endsWith('**') && s.length > 4) ||
      (s.startsWith('__') && s.endsWith('__') && s.length > 4)) {
      runs.push({ kind: 'bold', text: s.slice(2, -2), url: '' });
    } else if (s.startsWith('*') && s.endsWith('*') && s.length > 2) {
      runs.push({ kind: 'italic', text: s.slice(1, -1), url: '' });
    } else if (s.startsWith('~~') && s.endsWith('~~') && s.length > 4) {
      runs.push({ kind: 'strike', text: s.slice(2, -2), url: '' });
    } else if (s.startsWith('`') && s.endsWith('`') && s.length > 2) {
      runs.push({ kind: 'code', text: s.slice(1, -1), url: '' });
    } else if (s.startsWith('$') && s.endsWith('$') && s.length > 2) {
      runs.push({ kind: 'math_inline', text: s.slice(1, -1), url: '' });
    } else if (s.startsWith('[') && s.includes('](') && s.endsWith(')')) {
      const mid = s.indexOf('](');
      runs.push({ kind: 'link', text: s.slice(1, mid), url: s.slice(mid + 2, -1) });
    } else if (/^https?:\/\//.test(s)) {
      runs.push({ kind: 'link', text: s, url: s });
    } else {
      runs.push({ kind: 'text', text: s, url: '' });
    }
  }
  return runs;
}

const CODE_KEYWORDS = new Set<string>([
  'import', 'export', 'from', 'as', 'default', 'const', 'let', 'var', 'function', 'return',
  'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'break', 'continue', 'try', 'catch',
  'finally', 'throw', 'new', 'class', 'interface', 'struct', 'enum', 'type', 'extends',
  'implements', 'public', 'private', 'protected', 'static', 'readonly', 'async', 'await',
  'true', 'false', 'null', 'undefined', 'void', 'this', 'super', 'in', 'of', 'typeof',
  'instanceof', 'def', 'elif', 'pass', 'with', 'lambda', 'yield', 'None', 'True', 'False',
  'fn', 'pub', 'mut', 'impl', 'match', 'use', 'mod', 'package', 'func', 'go', 'defer',
  'select', 'SELECT', 'FROM', 'WHERE', 'INSERT', 'INTO', 'VALUES', 'UPDATE', 'SET',
  'DELETE', 'CREATE', 'TABLE', 'JOIN', 'LEFT', 'RIGHT', 'ORDER', 'BY', 'LIMIT', 'AND', 'OR'
]);

const CODE_TYPES = new Set<string>([
  'string', 'number', 'boolean', 'object', 'Array', 'Map', 'Set', 'Promise', 'Error',
  'int', 'float', 'double', 'bool', 'char', 'String', 'List', 'Widget', 'Column', 'Row',
  'Text', 'Button', 'Stack', 'Scroll', 'State', 'Prop', 'Link', 'Component', 'Entry',
  'Uint8Array', 'ArrayBuffer', 'Record', 'Object', 'Color', 'FontWeight'
]);

export function highlightCode(code: string, _lang: string): CodeLine[] {
  const lines = code.replace(/\r\n/g, '\n').split('\n');
  const out: CodeLine[] = [];
  for (let li = 0; li < lines.length; li++) {
    const line = lines[li];
    const tokens: CodeToken[] = [];
    let i = 0;
    while (i < line.length) {
      const ch = line[i];
      // Single-line comments // or # or --
      if ((ch === '/' && line[i + 1] === '/') || (ch === '#' && (i === 0 || line[i - 1] === ' ')) ||
        (ch === '-' && line[i + 1] === '-' && line[i + 2] === ' ')) {
        tokens.push({ kind: 'comment', text: line.slice(i) });
        break;
      }
      // Strings
      if (ch === '"' || ch === '\'' || ch === '`') {
        const quote = ch;
        let end = i + 1;
        while (end < line.length) {
          if (line[end] === '\\') { end += 2; continue; }
          if (line[end] === quote) { end++; break; }
          end++;
        }
        tokens.push({ kind: 'string', text: line.slice(i, end) });
        i = end;
        continue;
      }
      // Numbers
      if (/[0-9]/.test(ch) && (i === 0 || !/[a-zA-Z0-9_]/.test(line[i - 1]))) {
        let end = i + 1;
        while (end < line.length && /[0-9a-fA-FxXbBoO._]/.test(line[end])) end++;
        tokens.push({ kind: 'number', text: line.slice(i, end) });
        i = end;
        continue;
      }
      // Identifiers
      if (/[a-zA-Z_@$]/.test(ch)) {
        let end = i + 1;
        while (end < line.length && /[a-zA-Z0-9_$]/.test(line[end])) end++;
        const word = line.slice(i, end);
        const kind: CodeTokenKind = CODE_KEYWORDS.has(word) ? 'keyword' : CODE_TYPES.has(word) ? 'type' : 'plain';
        tokens.push({ kind, text: word });
        i = end;
        continue;
      }
      // Other punctuation / whitespace: batch consecutive plain chars
      let end = i + 1;
      while (end < line.length && !/[a-zA-Z0-9_@$"'`/#-]/.test(line[end])) end++;
      tokens.push({ kind: 'plain', text: line.slice(i, end) });
      i = end;
    }
    out.push({ tokens });
  }
  return out;
}
