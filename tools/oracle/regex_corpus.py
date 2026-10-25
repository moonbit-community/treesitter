"""Development-only: build the differential corpus for regex.

Collects the regexes of every `#match?`-family predicate in the query files of
upstream's fixture grammars and in crates/cli/src/tests/*.rs, adds hand-written
edge cases, and pairs each pattern with a deterministic set of haystacks.

Output: JSON lines `{"p": pattern, "t": [hex-encoded haystack bytes...]}`.
Feed the file to both tools/oracle/regex_harness (Rust `regex::bytes::Regex`)
and regex/probe (MoonBit) and diff their outputs.

Usage: python3 tools/oracle/regex_corpus.py <upstream checkout> [random pattern count] > corpus.jsonl
"""
import json
import random
import re
import sys
from pathlib import Path

UPSTREAM = Path(sys.argv[1])

PRED = re.compile(r'#(?:any-)?(?:not-)?match\?\s*@[\w.-]+\s*"((?:[^"\\\n]|\\.)*)"')


def unescape_query(s):
    # ts_query__parse_string_literal: \n \r \t \0, other escapes keep the char.
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            n = s[i + 1]
            out.append({'n': '\n', 'r': '\r', 't': '\t', '0': '\0'}.get(n, n))
            i += 2
        else:
            out.append(c)
            i += 1
    return ''.join(out)


patterns = []
for scm in sorted(UPSTREAM.glob('test/fixtures/grammars/**/queries/*.scm')):
    for m in PRED.finditer(scm.read_text(errors='replace')):
        patterns.append(unescape_query(m.group(1)))

# Rust test sources: the query text is inside a Rust string, so a `\"` in the
# query appears as `\\\"` in normal literals; handle raw strings (r#"...")
# and normal strings separately.
RAW = re.compile(r'r#"(.*?)"#', re.S)
NORMAL = re.compile(r'(?<![r#])"((?:[^"\\]|\\.)*)"', re.S)
for rs in sorted(UPSTREAM.glob('crates/cli/src/tests/*.rs')):
    text = rs.read_text(errors='replace')
    for m in RAW.finditer(text):
        for p in PRED.finditer(m.group(1)):
            patterns.append(unescape_query(p.group(1)))
    for m in NORMAL.finditer(text):
        body = m.group(1)
        try:
            body = bytes(body, 'utf-8').decode('unicode_escape', 'ignore').encode('latin-1').decode('utf-8')
        except Exception:
            continue
        for p in PRED.finditer(body):
            patterns.append(unescape_query(p.group(1)))

EDGE = r'''
a
abc
^abc$
^$
\A\z
(?m)^b$
(?m:^)
(?m)$
(?R)^b$
(?Rm)^b$
(?Rm)$
\bfoo\b
\Bfoo\B
\B
\b
(?-u:\b)foo(?-u:\b)
(?-u:\B)
\b{start}foo\b{end}
\b{start-half}x\b{end-half}
\<foo\>
[a-z]+
[^a-z]+
[[:alpha:]]+
[[:^alpha:]]
[[:word:]]
\w+
\W
\d+
\D
\s+
\S
(?-u:\w)+
(?-u:\W)
(?-u:\d)
(?-u:\s)
.
(?s).
(?s:.)+
(?-u:.)
(?s-u:.)
(?i)foo
(?i)ǅ
(?i)k
(?i:straße)
(?i)[a-z]
(?i)[^a-z]
(?x) a b c
(?x)a\ b
a*
a+
a?
a{3}
a{2,}
a{2,4}
a{0}
(a|b)*c
(?:ab|cd)+
a*?b
(a*)*
(a|)*b
()+x
x|
|x
\p{Greek}+
\p{L}+
\P{L}
\p{Lu}
\pN
\p{Han}
\p{Script=Latin}
\p{gc=Nd}
\p{Alphabetic}
[\p{L}&&\p{Greek}]
[a-z--aeiou]+
[a-z~~m-z]
[\w&&[^\d]]
\x41
\x{1F600}
\u00e9
\u{e9}
\n
\t
\x00
\0
[\x00-\x7F]+
[^\x00-\x7F]
(?-u:\xFF)
(?-u:[\x80-\xFF])
(?-u:[^a])
é
[é]
[^é]
日本
[日本]+
^[A-Z][A-Z\d_]+$
^[A-Z][a-zA-Z\d]*$
^_*[A-Z][A-Z\d_]*$
^(require|load)$
^(self|super|crate)$
^#!/
^//
^[^\n]*$
\\
\.
\$
\^
a\Qb
[
(
a)
a{2,1}
a{
\p{Nope}
(?z)
[z-a]
\8
(?<name>a)
(?P<n>a)(?P<n>b)
(?P<n>a)
\k<n>
(a)\1
(?=a)
(?!a)
(?<=a)
a{1000}
\w{100}
\w{500}
\p{L}{1000}
.{2000}
a{1000}{1000}
(?:\w{50}){50}
a{100000}
[\s\S]
^\s*$
^\S+$
^(?:[0-9]+|0x[0-9a-fA-F]+)$
^(?i:true|false)$
^@
:$
(?m)^\s*//
\$\{
^-?\d+(\.\d+)?$
^[\p{Lu}]
^\p{Lu}
^[[:upper:]]
\b[A-Z]{2,}\b
(?u)\w
(?-u)a
'''.strip().split('\n')
patterns += EDGE

seen, unique = set(), []
for p in patterns:
    if p not in seen:
        seen.add(p)
        unique.append(p)

BASE = [
    b'', b'a', b'abc', b'ABC', b'Abc', b'foo', b'FOO', b'Foo', b'foo bar', b'foobar',
    b'xfoo', b'foox', b'foo_bar', b'_', b'__init__', b'x1', b'1x', b'123', b'0x1F',
    b'-12.5', b'TODO', b'FIXME', b'self', b'super', b'crate', b'require', b'load',
    b'true', b'TRUE', b'False', b'a\nb', b'a\r\nb', b'b\r', b'\n', b'\r\n', b'line1\nline2\n',
    b' ', b'  x  ', b'\t', b'#!/bin/sh', b'// comment', b'/* c */', b'@param', b'name:',
    b'${x}', b'$x', b'a.b', b'a\\b', b'Q', b'aaa', b'aab', b'abab', b'cdcd', b'ac', b'c',
    'héllo'.encode(), 'É'.encode(), 'straße'.encode(), 'STRASSE'.encode(), 'ǅ'.encode(),
    'ǆ'.encode(), 'K'.encode(), 'k'.encode(), 'Ω'.encode(), 'αβγ'.encode(), '日本語'.encode(),
    '😀'.encode(), 'a😀b'.encode(), 'Москва'.encode(), '١٢٣'.encode(), '٣x'.encode(),
    b'\xff', b'a\xffb', b'\xc3', b'\xc3\xa9\x80', b'\xe2\x82', b'\xed\xa0\x80', b'\xf4\x90\x80\x80',
    b'\xc0\xaf', b'\x00', b'a\x00b', b'\x80abc\x80', b'\xffabc\xff', b'x' * 50, b'ab' * 30,
    b'A' * 3 + b'_1', b'SCREAMING_CASE', b'CamelCase', b'snake_case', b'kebab-case',
]

rng = random.Random(1234)
ALPH = list(b'abcxyzABCXYZ019_ -.\n\t$@#/\\') + list('é日😀'.encode()) + [0xff, 0x80]

# Random patterns built from regex constructs (deterministic).
ATOMS = ['a', 'b', 'x', 'é', '日', '.', r'\w', r'\W', r'\d', r'\s', r'\S', '[a-c]', '[^a]',
         r'\p{L}', r'\p{Lu}', '[[:digit:]]', r'(?-u:\w)', r'(?-u:.)', r'\x{e9}', r'\n', ' ',
         '^', '$', r'\b', r'\B', r'\A', r'\z', '(?m:^)', '(?m:$)', r'(?-u:\b)', r'\b{start}',
         r'\b{end}', '(?i:a)', '(?i:É)', '(?s:.)', '_', '-', r'\.', '[é日]', r'[^\s]']
OPS = ['', '', '', '*', '+', '?', '{2}', '{1,3}', '{0,2}', '*?', '+?']


def rand_pattern(depth=0):
    parts = []
    for _ in range(rng.randint(1, 4)):
        if depth < 2 and rng.random() < 0.2:
            inner = '|'.join(rand_pattern(depth + 1) for _ in range(rng.randint(1, 3)))
            atom = rng.choice(['(', '(?:']) + inner + ')'
        else:
            atom = rng.choice(ATOMS)
        if atom not in ('^', '$', r'\b', r'\B', r'\A', r'\z', '(?m:^)', '(?m:$)', r'(?-u:\b)',
                        r'\b{start}', r'\b{end}'):
            atom += rng.choice(OPS)
        parts.append(atom)
    return ''.join(parts)


if len(sys.argv) > 2:
    for _ in range(int(sys.argv[2])):
        p = rand_pattern()
        if p not in seen:
            seen.add(p)
            unique.append(p)

out = sys.stdout
for p in unique:
    lits = re.sub(r'\\.|[\[\](){}^$*+?|.]', ' ', p)
    extra = [lits.encode('utf-8', 'replace'), lits.strip().encode('utf-8', 'replace')]
    chars = list(set(lits.encode('utf-8', 'replace'))) or [ord('a')]
    for _ in range(20):
        n = rng.randint(0, 12)
        pool = chars + ALPH
        extra.append(bytes(rng.choice(pool) for _ in range(n)))
    texts = BASE + extra
    out.write(json.dumps({'p': p, 't': [t.hex() for t in texts]}) + '\n')
