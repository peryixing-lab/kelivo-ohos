export type GenUiScalar = string | number | boolean;

export interface GenUiSelectOption {
  label: string;
  value: string;
}

export interface GenUiChartPoint {
  label: string;
  valueExpr: string;
}

export interface GenUiNode {
  type: string;
  id?: string;
  title?: string;
  text?: string;
  expr?: string;
  bind?: string;
  label?: string;
  unit?: string;
  min?: number;
  max?: number;
  step?: number;
  options?: GenUiSelectOption[];
  headers?: string[];
  rows?: string[][];
  points?: GenUiChartPoint[];
  variant?: 'info' | 'warn' | 'success';
  askDraft?: string;
  visibleIf?: string;
  children?: GenUiNode[];
}

export interface GenUiDocument {
  title: string;
  state: Record<string, GenUiScalar>;
  nodes: GenUiNode[];
  error?: string;
}

interface RawGenUiJson {
  title?: string;
  state?: Record<string, Object>;
  root?: GenUiNode;
  nodes?: GenUiNode[];
  children?: GenUiNode[];
}

export function parseGenUiDocument(raw: string): GenUiDocument {
  const trimmed = raw.trim();
  if (!trimmed) {
    return { title: '', state: {}, nodes: [], error: '空界面定义' };
  }
  try {
    const obj = JSON.parse(trimmed) as RawGenUiJson;
    const state: Record<string, GenUiScalar> = {};
    if (obj.state && typeof obj.state === 'object') {
      Object.keys(obj.state).forEach((k: string) => {
        const v = obj.state![k];
        if (typeof v === 'number' || typeof v === 'boolean' || typeof v === 'string') {
          state[k] = v;
        }
      });
    }
    let nodes: GenUiNode[] = [];
    if (Array.isArray(obj.nodes)) nodes = obj.nodes;
    else if (obj.root) nodes = [obj.root];
    else if (Array.isArray(obj.children)) nodes = obj.children;
    return { title: obj.title || '', state, nodes };
  } catch (e) {
    return { title: '', state: {}, nodes: [], error: (e as Error).message || 'kelivo-ui 解析失败' };
  }
}

interface ExprToken {
  kind: 'num' | 'str' | 'ident' | 'op' | 'lparen' | 'rparen' | 'comma' | 'qmark' | 'colon';
  val: string;
}

function tokenizeExpr(expr: string): ExprToken[] {
  const tokens: ExprToken[] = [];
  let i = 0;
  while (i < expr.length) {
    const ch = expr[i];
    if (/\s/.test(ch)) { i++; continue; }
    if (/[0-9.]/.test(ch)) {
      let end = i + 1;
      while (end < expr.length && /[0-9.]/.test(expr[end])) end++;
      tokens.push({ kind: 'num', val: expr.slice(i, end) });
      i = end;
      continue;
    }
    if (ch === '"' || ch === '\'') {
      const q = ch;
      let end = i + 1;
      let out = '';
      while (end < expr.length && expr[end] !== q) {
        if (expr[end] === '\\' && end + 1 < expr.length) {
          out += expr[end + 1];
          end += 2;
        } else {
          out += expr[end];
          end++;
        }
      }
      tokens.push({ kind: 'str', val: out });
      i = end + 1;
      continue;
    }
    if (/[a-zA-Z_]/.test(ch)) {
      let end = i + 1;
      while (end < expr.length && /[a-zA-Z0-9_.]/.test(expr[end])) end++;
      tokens.push({ kind: 'ident', val: expr.slice(i, end) });
      i = end;
      continue;
    }
    const two = expr.slice(i, i + 2);
    if (['==', '!=', '<=', '>=', '&&', '||'].includes(two)) {
      tokens.push({ kind: 'op', val: two });
      i += 2;
      continue;
    }
    if (ch === '(') { tokens.push({ kind: 'lparen', val: '(' }); i++; continue; }
    if (ch === ')') { tokens.push({ kind: 'rparen', val: ')' }); i++; continue; }
    if (ch === ',') { tokens.push({ kind: 'comma', val: ',' }); i++; continue; }
    if (ch === '?') { tokens.push({ kind: 'qmark', val: '?' }); i++; continue; }
    if (ch === ':') { tokens.push({ kind: 'colon', val: ':' }); i++; continue; }
    if ('+-*/%^<>!'.includes(ch)) {
      tokens.push({ kind: 'op', val: ch });
      i++;
      continue;
    }
    i++;
  }
  return tokens;
}

class ExprParser {
  private tokens: ExprToken[];
  private pos: number = 0;
  private state: Record<string, GenUiScalar>;

  constructor(tokens: ExprToken[], state: Record<string, GenUiScalar>) {
    this.tokens = tokens;
    this.state = state;
  }

  private peek(): ExprToken | undefined {
    return this.pos < this.tokens.length ? this.tokens[this.pos] : undefined;
  }

  private consume(): ExprToken | undefined {
    return this.pos < this.tokens.length ? this.tokens[this.pos++] : undefined;
  }

  parseTernary(): GenUiScalar {
    const cond = this.parseOr();
    if (this.peek()?.kind === 'qmark') {
      this.consume();
      const whenTrue = this.parseTernary();
      if (this.peek()?.kind === 'colon') this.consume();
      const whenFalse = this.parseTernary();
      return Boolean(cond) ? whenTrue : whenFalse;
    }
    return cond;
  }

  private parseOr(): GenUiScalar {
    let left = this.parseAnd();
    while (this.peek()?.kind === 'op' && this.peek()?.val === '||') {
      this.consume();
      const right = this.parseAnd();
      left = Boolean(left) || Boolean(right);
    }
    return left;
  }

  private parseAnd(): GenUiScalar {
    let left = this.parseEq();
    while (this.peek()?.kind === 'op' && this.peek()?.val === '&&') {
      this.consume();
      const right = this.parseEq();
      left = Boolean(left) && Boolean(right);
    }
    return left;
  }

  private parseEq(): GenUiScalar {
    let left = this.parseRel();
    while (this.peek()?.kind === 'op' && (this.peek()?.val === '==' || this.peek()?.val === '!=')) {
      const op = this.consume()!.val;
      const right = this.parseRel();
      left = op === '==' ? left === right : left !== right;
    }
    return left;
  }

  private parseRel(): GenUiScalar {
    let left = this.parseAdd();
    while (this.peek()?.kind === 'op' && ['<', '<=', '>', '>='].includes(this.peek()!.val)) {
      const op = this.consume()!.val;
      const right = this.parseAdd();
      const l = Number(left);
      const r = Number(right);
      if (op === '<') left = l < r;
      else if (op === '<=') left = l <= r;
      else if (op === '>') left = l > r;
      else left = l >= r;
    }
    return left;
  }

  private parseAdd(): GenUiScalar {
    let left = this.parseMul();
    while (this.peek()?.kind === 'op' && (this.peek()?.val === '+' || this.peek()?.val === '-')) {
      const op = this.consume()!.val;
      const right = this.parseMul();
      if (op === '+' && (typeof left === 'string' || typeof right === 'string')) {
        left = String(left) + String(right);
      } else {
        left = op === '+' ? Number(left) + Number(right) : Number(left) - Number(right);
      }
    }
    return left;
  }

  private parseMul(): GenUiScalar {
    let left = this.parsePow();
    while (this.peek()?.kind === 'op' && ['*', '/', '%'].includes(this.peek()!.val)) {
      const op = this.consume()!.val;
      const right = this.parsePow();
      const l = Number(left);
      const r = Number(right);
      if (op === '*') left = l * r;
      else if (op === '/') left = r === 0 ? 0 : l / r;
      else left = r === 0 ? 0 : l % r;
    }
    return left;
  }

  private parsePow(): GenUiScalar {
    const base = this.parseUnary();
    if (this.peek()?.kind === 'op' && this.peek()?.val === '^') {
      this.consume();
      const exp = this.parsePow();
      return Math.pow(Number(base), Number(exp));
    }
    return base;
  }

  private parseUnary(): GenUiScalar {
    const p = this.peek();
    if (p?.kind === 'op' && (p.val === '-' || p.val === '+' || p.val === '!')) {
      this.consume();
      const v = this.parseUnary();
      if (p.val === '-') return -Number(v);
      if (p.val === '!') return !Boolean(v);
      return Number(v);
    }
    return this.parsePrimary();
  }

  private callFn(name: string, args: GenUiScalar[]): GenUiScalar {
    const nums = args.map((a: GenUiScalar): number => Number(a) || 0);
    if (name === 'min') return nums.length ? Math.min(...nums) : 0;
    if (name === 'max') return nums.length ? Math.max(...nums) : 0;
    if (name === 'round') return nums.length >= 2 ? Number(nums[0].toFixed(Math.max(0, Math.min(8, Math.round(nums[1]))))) : Math.round(nums[0] || 0);
    if (name === 'floor') return Math.floor(nums[0] || 0);
    if (name === 'ceil') return Math.ceil(nums[0] || 0);
    if (name === 'abs') return Math.abs(nums[0] || 0);
    if (name === 'sqrt') return Math.sqrt(Math.max(0, nums[0] || 0));
    if (name === 'pow') return Math.pow(nums[0] || 0, nums[1] || 0);
    if (name === 'sin') return Math.sin(nums[0] || 0);
    if (name === 'cos') return Math.cos(nums[0] || 0);
    if (name === 'tan') return Math.tan(nums[0] || 0);
    if (name === 'log' || name === 'ln') return Math.log(Math.max(1e-12, nums[0] || 1));
    if (name === 'sum') return nums.reduce((acc: number, v: number): number => acc + v, 0);
    if (name === 'avg') return nums.length ? nums.reduce((acc: number, v: number): number => acc + v, 0) / nums.length : 0;
    if (name === 'fixed') return (nums[0] || 0).toFixed(Math.max(0, Math.min(6, Math.round(nums[1] ?? 2))));
    return 0;
  }

  private parsePrimary(): GenUiScalar {
    const tok = this.consume();
    if (!tok) return 0;
    if (tok.kind === 'num') return Number(tok.val) || 0;
    if (tok.kind === 'str') return tok.val;
    if (tok.kind === 'lparen') {
      const inner = this.parseTernary();
      if (this.peek()?.kind === 'rparen') this.consume();
      return inner;
    }
    if (tok.kind === 'ident') {
      if (this.peek()?.kind === 'lparen') {
        this.consume();
        const args: GenUiScalar[] = [];
        while (this.peek() && this.peek()?.kind !== 'rparen') {
          args.push(this.parseTernary());
          if (this.peek()?.kind === 'comma') this.consume();
          else break;
        }
        if (this.peek()?.kind === 'rparen') this.consume();
        return this.callFn(tok.val, args);
      }
      if (tok.val === 'true') return true;
      if (tok.val === 'false') return false;
      if (tok.val === 'pi' || tok.val === 'PI') return Math.PI;
      if (tok.val === 'e' || tok.val === 'E') return Math.E;
      const found = this.state[tok.val];
      return found !== undefined ? found : 0;
    }
    return 0;
  }
}

export function evalGenUiExpr(expr: string, state: Record<string, GenUiScalar>): GenUiScalar {
  if (!expr || !expr.trim()) return '';
  try {
    const tokens = tokenizeExpr(expr);
    if (!tokens.length) return '';
    return new ExprParser(tokens, state).parseTernary();
  } catch (_) {
    return 0;
  }
}

export function formatGenUiScalar(val: GenUiScalar): string {
  if (typeof val === 'number') {
    if (!Number.isFinite(val)) return '0';
    return Number.isInteger(val) ? String(val) : String(Number(val.toFixed(4)));
  }
  return String(val);
}

export function interpolateGenUi(template: string, state: Record<string, GenUiScalar>): string {
  if (!template) return '';
  return template.replace(/\{\{([^}]+)\}\}/g, (_match: string, expr: string): string => {
    return formatGenUiScalar(evalGenUiExpr(expr, state));
  });
}
