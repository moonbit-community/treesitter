"""Development-only oracle: convert an upstream-generated parser.c into the
JSON form of next/language's `Language`.

The parse tables come from compiling parser.c with tools/next/dump_language.c
(so every array is exactly what the C runtime reads); the lex functions are
parsed from the C text into `LexProgram`s.

Usage: python3 tools/next/language_from_c.py <src dir containing parser.c> <out.json>
"""
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent


def c_char(tok):
    if tok.startswith("'"):
        body = tok[1:-1]
        if body.startswith('\\'):
            return {"'": 39, '\\': 92, 'f': 12, 'n': 10, 't': 9, 'r': 13, '0': 0}[body[1]]
        return ord(body)
    if tok.startswith('0x'):
        return int(tok, 16)
    return int(tok)


TOKEN = re.compile(r"\s*(set_contains|lookahead|eof|&&|\|\||==|!=|<=|>=|<|>|!|\(|\)|,|'(?:\\.|[^'\\])'|0x[0-9a-fA-F]+|\d+|[A-Za-z_][A-Za-z_0-9]*)")


def tokenize(text):
    pos, out = 0, []
    text = text.strip()
    while pos < len(text):
        m = TOKEN.match(text, pos)
        if not m:
            raise ValueError('cannot tokenize: ' + text[pos:pos + 40])
        out.append(m.group(1))
        pos = m.end()
    return out


class P:
    def __init__(self, toks):
        self.t, self.i = toks, 0

    def peek(self):
        return self.t[self.i] if self.i < len(self.t) else None

    def take(self, expected=None):
        tok = self.t[self.i]
        if expected and tok != expected:
            raise ValueError(f'expected {expected}, got {tok}')
        self.i += 1
        return tok

    def expr(self):
        items = [self.conj()]
        while self.peek() == '||':
            self.take()
            items.append(self.conj())
        return items[0] if len(items) == 1 else ('or', items)

    def conj(self):
        items = [self.atom()]
        while self.peek() == '&&':
            self.take()
            items.append(self.atom())
        return items[0] if len(items) == 1 else ('and', items)

    def atom(self):
        tok = self.peek()
        if tok == '(':
            self.take()
            inner = self.expr()
            self.take(')')
            return ('paren', inner)
        if tok == '!':
            self.take()
            self.take('eof')
            return ('noteof',)
        if tok == 'set_contains':
            self.take()
            self.take('(')
            name = self.take()
            self.take(',')
            self.take()
            self.take(',')
            self.take('lookahead')
            self.take(')')
            return ('set', name)
        left = self.take()
        op = self.take()
        right = self.take()
        return ('cmp', left, op, right)


def term(node):
    """Classify a single range test: ('in'|'out', start, end, eof_guard)."""
    if node[0] == 'cmp':
        _, l, op, r = node
        if l == 'lookahead' and op == '==':
            c = c_char(r)
            return ('in', c, c)
        if l == 'lookahead' and op == '!=':
            c = c_char(r)
            return ('out', c, c)
        if l == 'lookahead' and op == '>':
            return ('out', 0, c_char(r))
    if node[0] == 'paren':
        inner = node[1]
        if inner[0] == 'and' and len(inner[1]) == 2 and inner[1][0] == ('noteof',):
            if inner[1][1][0] != 'cmp':
                return None
            _, l, op, r = inner[1][1]
            if op == '==':
                return ('in', 0, 0)
            return ('in', 0, c_char(r))
        if inner[0] == 'and' and len(inner[1]) == 2:
            a, b = inner[1]
            if a[0] == 'cmp' and a[3] == 'lookahead' and a[2] == '<=':
                return ('in', c_char(a[1]), c_char(b[3]))
        if inner[0] == 'or' and len(inner[1]) == 2:
            a, b = inner[1]
            if a[0] == 'cmp' and a[1] == 'lookahead' and a[2] == '<':
                return ('out', c_char(a[3]), c_char(b[1]))
    return None


def ranges(kind, nodes):
    result = []
    for n in nodes:
        t = term(n)
        if t is None or t[0] != kind:
            raise ValueError(f'unexpected term {n}')
        result.append({'start': t[1], 'end': t[2]})
    return result


def flat(node, kind):
    return node[1] if node[0] == kind else [node]


def large(node, set_index):
    if node[0] == 'set':
        return [set_index[node[1]], False]
    if node[0] == 'paren' and node[1][0] == 'and' and node[1][1][0] == ('noteof',) and node[1][1][1][0] == 'set':
        return [set_index[node[1][1][1][1]], True]
    return None


def positive(node, set_index, cond):
    disjuncts = flat(node, 'or')
    if large(disjuncts[0], set_index) is not None:
        cond['large_set'] = large(disjuncts[0], set_index)
        disjuncts = disjuncts[1:]
    if not disjuncts:
        return
    if len(disjuncts) == 1 and disjuncts[0][0] == 'and':
        cond['asserted'] = {'ranges': ranges('out', disjuncts[0][1]), 'is_included': False}
    elif len(disjuncts) == 1 and term(disjuncts[0]) and term(disjuncts[0])[0] == 'out':
        cond['asserted'] = {'ranges': ranges('out', disjuncts), 'is_included': False}
    else:
        cond['asserted'] = {'ranges': ranges('in', disjuncts), 'is_included': True}


def condition(text, set_index):
    if text is None:
        return {}
    ast = P(tokenize(text)).expr()
    cond = {}
    if ast[0] == 'and' and ast[1][0][0] == 'paren' and term(ast[1][0]) is None and large(ast[1][0], set_index) is None:
        positive(ast[1][0][1], set_index, cond)
        cond['negated'] = {'ranges': ranges('out', ast[1][1:]), 'is_included': False}
        return cond
    conj = flat(ast, 'and')
    if all(term(n) and term(n)[0] == 'out' for n in conj):
        cond['negated'] = {'ranges': ranges('out', conj), 'is_included': False}
        return cond
    positive(ast, set_index, cond)
    return cond


def lex_program(source, fn, symbol_ids, set_index, sets):
    m = re.search(r'static bool ' + fn + r'\(TSLexer \*lexer, TSStateId state\) \{(.*?)\n\}\n', source, re.S)
    if not m:
        return None
    body = m.group(1)
    states = []
    for case in re.split(r'\n    case (\d+):\n', body)[1:]:
        if case.strip().isdigit():
            states.append({'accept_token': None, 'eof_advance': None, 'advance_map': [], 'transitions': []})
            continue
        st = states[-1]
        text = case.split('END_STATE();')[0]
        m2 = re.search(r'ACCEPT_TOKEN\((\w+)\);', text)
        if m2:
            st['accept_token'] = symbol_ids[m2.group(1)]
        m2 = re.search(r'if \(eof\) ADVANCE\((\d+)\);', text)
        if m2:
            st['eof_advance'] = int(m2.group(1))
        m2 = re.search(r'ADVANCE_MAP\((.*?)\);', text, re.S)
        if m2:
            items = [x.strip() for x in re.findall(r"('(?:\\.|[^'\\])'|0x[0-9a-fA-F]+|\d+)\s*,", m2.group(1))]
            st['advance_map'] = [[c_char(items[i]), int(items[i + 1])] for i in range(0, len(items), 2)]
            text = text[:m2.start()] + text[m2.end():]
        text = re.sub(r'ACCEPT_TOKEN\(\w+\);', '', text)
        text = re.sub(r'if \(eof\) ADVANCE\(\d+\);', '', text)
        for t in re.finditer(r'(?:if \((.*?)\) )?(ADVANCE|SKIP)\((\d+)\);', text, re.S):
            st['transitions'].append({
                'condition': condition(t.group(1), set_index),
                'state': int(t.group(3)),
                'skip': t.group(2) == 'SKIP',
            })
    for st in states:
        if st['accept_token'] is None:
            del st['accept_token']
        if st['eof_advance'] is None:
            del st['eof_advance']
    return {'states': states, 'large_character_sets': sets}


def main():
    src = Path(sys.argv[1]).resolve()
    out = Path(sys.argv[2])
    source = (src / 'parser.c').read_text()
    name = re.search(r'const TSLanguage \*tree_sitter_(\w+)\(void\)', source).group(1)
    symbol_ids = {'ts_builtin_sym_end': 0}
    enum = re.search(r'enum ts_symbol_identifiers \{(.*?)\};', source, re.S)
    for ident, value in re.findall(r'(\w+) = (\d+),', enum.group(1)):
        symbol_ids[ident] = int(value)
    reserved_rows = re.search(r'ts_reserved_words\[(\d+)\]', source)
    with tempfile.TemporaryDirectory() as tmp:
        exe = os.path.join(tmp, 'dump')
        cmd = ['cc', '-O0', '-w', '-I', str(src),
               f'-DLANGUAGE=tree_sitter_{name}',
               f'-DSCANNER_PREFIX(x)=tree_sitter_{name}_external_scanner_##x',
               str(src / 'parser.c'), str(HERE / 'dump_language.c'), '-o', exe]
        subprocess.run(cmd, check=True)
        data = json.loads(subprocess.run([exe], check=True, capture_output=True, text=True).stdout)
    if reserved_rows and data['max_reserved_word_set_size']:
        rows = int(reserved_rows.group(1))
        # Re-dump is unnecessary: unreferenced rows are zero-filled in C.
        need = rows * data['max_reserved_word_set_size']
        data['reserved_words'] += [0] * (need - len(data['reserved_words']))
    sets, set_index = [], {}
    for m in re.finditer(r'static const TSCharacterRange (\w+)\[\] = \{(.*?)\};', source, re.S):
        set_index[m.group(1)] = len(sets)
        pairs = re.findall(r"\{('(?:\\.|[^'\\])'|0x[0-9a-fA-F]+|\d+), ('(?:\\.|[^'\\])'|0x[0-9a-fA-F]+|\d+)\}", m.group(2))
        sets.append([{'start': c_char(a), 'end': c_char(b)} for a, b in pairs])
    data['lex_fn'] = lex_program(source, 'ts_lex', symbol_ids, set_index, sets)
    keyword = lex_program(source, 'ts_lex_keywords', symbol_ids, set_index, sets)
    if keyword is not None:
        data['keyword_lex_fn'] = keyword
    out.write_text(json.dumps(data))


if __name__ == '__main__':
    main()
