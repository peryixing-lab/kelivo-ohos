interface MathToken {
  kind: 'num' | 'ident' | 'op' | 'lparen' | 'rparen' | 'comma';
  value: string;
}

function isDigitChar(ch: string): boolean {
  return ch >= '0' && ch <= '9';
}

function isAlphaChar(ch: string): boolean {
  return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch === '_';
}

function tokenizeMath(expr: string): MathToken[] {
  const tokens: MathToken[] = [];
  let i = 0;
  while (i < expr.length) {
    const ch = expr.charAt(i);
    if (ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r') {
      i += 1;
      continue;
    }
    if (isDigitChar(ch) || ch === '.') {
      let end = i + 1;
      let seenDot = ch === '.';
      while (end < expr.length) {
        const c = expr.charAt(end);
        if (isDigitChar(c)) {
          end += 1;
        } else if (c === '.' && !seenDot) {
          seenDot = true;
          end += 1;
        } else if ((c === 'e' || c === 'E') && end + 1 < expr.length) {
          const next = expr.charAt(end + 1);
          if (isDigitChar(next) || ((next === '+' || next === '-') && end + 2 < expr.length && isDigitChar(expr.charAt(end + 2)))) {
            end += next === '+' || next === '-' ? 3 : 2;
          } else {
            break;
          }
        } else {
          break;
        }
      }
      tokens.push({ kind: 'num', value: expr.slice(i, end) });
      i = end;
      continue;
    }
    if (isAlphaChar(ch)) {
      let end = i + 1;
      while (end < expr.length && (isAlphaChar(expr.charAt(end)) || isDigitChar(expr.charAt(end)))) {
        end += 1;
      }
      tokens.push({ kind: 'ident', value: expr.slice(i, end).toLowerCase() });
      i = end;
      continue;
    }
    if (ch === '(') {
      tokens.push({ kind: 'lparen', value: '(' });
      i += 1;
    } else if (ch === ')') {
      tokens.push({ kind: 'rparen', value: ')' });
      i += 1;
    } else if (ch === ',') {
      tokens.push({ kind: 'comma', value: ',' });
      i += 1;
    } else if ('+-*/%^'.indexOf(ch) >= 0) {
      tokens.push({ kind: 'op', value: ch });
      i += 1;
    } else {
      throw new Error(`不支持的字符: ${ch}`);
    }
  }
  return tokens;
}

class MathParser {
  private readonly tokens: MathToken[];
  private pos: number = 0;

  constructor(tokens: MathToken[]) {
    this.tokens = tokens;
  }

  private peek(): MathToken | undefined {
    return this.pos < this.tokens.length ? this.tokens[this.pos] : undefined;
  }

  private consume(): MathToken {
    const t = this.tokens[this.pos];
    this.pos += 1;
    return t;
  }

  parseRoot(): number {
    if (this.tokens.length === 0) {
      throw new Error('数学表达式为空');
    }
    const val = this.parseAddSub();
    if (this.pos < this.tokens.length) {
      throw new Error(`多余的符号: ${this.tokens[this.pos].value}`);
    }
    return val;
  }

  private parseAddSub(): number {
    let left = this.parseMulDiv();
    while (true) {
      const t = this.peek();
      if (!t || t.kind !== 'op' || (t.value !== '+' && t.value !== '-')) {
        break;
      }
      this.consume();
      const right = this.parseMulDiv();
      left = t.value === '+' ? left + right : left - right;
    }
    return left;
  }

  private parseMulDiv(): number {
    let left = this.parsePower();
    while (true) {
      const t = this.peek();
      if (!t || t.kind !== 'op' || (t.value !== '*' && t.value !== '/' && t.value !== '%')) {
        break;
      }
      this.consume();
      const right = this.parsePower();
      if (t.value === '*') {
        left = left * right;
      } else if (t.value === '/') {
        if (right === 0) {
          throw new Error('除数不能为 0');
        }
        left = left / right;
      } else {
        if (right === 0) {
          throw new Error('取模除数不能为 0');
        }
        left = left % right;
      }
    }
    return left;
  }

  private parsePower(): number {
    const base = this.parseUnary();
    const t = this.peek();
    if (t && t.kind === 'op' && t.value === '^') {
      this.consume();
      const exp = this.parsePower();
      return Math.pow(base, exp);
    }
    return base;
  }

  private parseUnary(): number {
    const t = this.peek();
    if (t && t.kind === 'op' && (t.value === '+' || t.value === '-')) {
      this.consume();
      const v = this.parseUnary();
      return t.value === '-' ? -v : v;
    }
    return this.parsePrimary();
  }

  private parsePrimary(): number {
    const t = this.peek();
    if (!t) {
      throw new Error('表达式意外结束');
    }
    if (t.kind === 'num') {
      this.consume();
      const n = Number(t.value);
      if (Number.isNaN(n)) {
        throw new Error(`无效数字: ${t.value}`);
      }
      return n;
    }
    if (t.kind === 'lparen') {
      this.consume();
      const v = this.parseAddSub();
      const close = this.peek();
      if (!close || close.kind !== 'rparen') {
        throw new Error('缺少右括号 )');
      }
      this.consume();
      return v;
    }
    if (t.kind === 'ident') {
      this.consume();
      const next = this.peek();
      if (next && next.kind === 'lparen') {
        this.consume();
        const args: number[] = [];
        const after = this.peek();
        if (after && after.kind !== 'rparen') {
          while (true) {
            args.push(this.parseAddSub());
            const sep = this.peek();
            if (sep && sep.kind === 'comma') {
              this.consume();
            } else {
              break;
            }
          }
        }
        const close = this.peek();
        if (!close || close.kind !== 'rparen') {
          throw new Error(`函数 ${t.value} 缺少右括号`);
        }
        this.consume();
        return this.evalFunc(t.value, args);
      }
      if (t.value === 'pi') {
        return Math.PI;
      }
      if (t.value === 'e') {
        return Math.E;
      }
      throw new Error(`未知常量或函数: ${t.value}`);
    }
    throw new Error(`意外符号: ${t.value}`);
  }

  private evalFunc(name: string, args: number[]): number {
    if (name === 'sin' && args.length === 1) return Math.sin(args[0]);
    if (name === 'cos' && args.length === 1) return Math.cos(args[0]);
    if (name === 'tan' && args.length === 1) return Math.tan(args[0]);
    if (name === 'asin' && args.length === 1) return Math.asin(args[0]);
    if (name === 'acos' && args.length === 1) return Math.acos(args[0]);
    if (name === 'atan' && args.length === 1) return Math.atan(args[0]);
    if (name === 'sqrt' && args.length === 1) return Math.sqrt(args[0]);
    if (name === 'abs' && args.length === 1) return Math.abs(args[0]);
    if ((name === 'ln' || name === 'log') && args.length === 1) return Math.log(args[0]);
    if (name === 'log10' && args.length === 1) return Math.log10(args[0]);
    if (name === 'exp' && args.length === 1) return Math.exp(args[0]);
    if (name === 'round' && args.length === 1) return Math.round(args[0]);
    if (name === 'floor' && args.length === 1) return Math.floor(args[0]);
    if (name === 'ceil' && args.length === 1) return Math.ceil(args[0]);
    if (name === 'pow' && args.length === 2) return Math.pow(args[0], args[1]);
    if (name === 'min' && args.length >= 1) {
      let m = args[0];
      for (let i = 1; i < args.length; i++) if (args[i] < m) m = args[i];
      return m;
    }
    if (name === 'max' && args.length >= 1) {
      let m = args[0];
      for (let i = 1; i < args.length; i++) if (args[i] > m) m = args[i];
      return m;
    }
    throw new Error(`不支持的函数或参数数量错误: ${name}`);
  }
}

/**
 * Safely evaluates arithmetic & scientific math expressions without eval().
 */
export function evaluateMathExpression(expr: string): number {
  const clean = expr.replace(/×/g, '*').replace(/÷/g, '/').trim();
  const parser = new MathParser(tokenizeMath(clean));
  const val = parser.parseRoot();
  if (!Number.isFinite(val)) {
    throw new Error('计算结果溢出或非有限实数');
  }
  return val;
}
