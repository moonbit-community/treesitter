"""Development-only differential test of next/runtime against the C runtime.

For every reference grammar in _build/ref (see ref_generate.sh) whose tables
were converted to _build/reflang/<name>.json (language_from_c.py), parse the
grammar's corpus inputs (and optional mutations) with both runtimes and
compare the S-expressions.

Usage: python3 tools/next/diff_runtime.py [--mutate N] [names...]
"""
import argparse
import hashlib
import json
import random
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REF = ROOT / '_build/ref'
LANG = ROOT / '_build/reflang'
BIN = ROOT / '_build/refbin'
TMP = ROOT / '_build/difftmp'
UPSTREAM = Path(subprocess.check_output(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], cwd=ROOT, text=True).strip()).parent / '.repos/ts-pinned'
PROBE = ROOT / '_build/native/debug/build/next/probe/probe.exe'

HEADER = re.compile(r'^(={3,})[^\n]*\n(.*?)\n\1[^\n]*\n(.*?)\n-{3,}[^\n]*\n', re.S | re.M)


def corpus_inputs(name):
    files = []
    test_dir = UPSTREAM / 'test/fixtures/test_grammars' / name
    if (test_dir / 'corpus.txt').exists():
        files.append(test_dir / 'corpus.txt')
    if name.startswith('fixture_'):
        parts = name[len('fixture_'):].split('_')
        for base in [UPSTREAM / 'test/fixtures/grammars' / parts[0]]:
            for sub in ['test/corpus', '/'.join(parts[1:]) + '/test/corpus' if len(parts) > 1 else None]:
                if sub and (base / sub).is_dir():
                    files += sorted((base / sub).glob('*.txt'))
    inputs = []
    for f in files:
        text = f.read_text(errors='replace')
        for m in HEADER.finditer(text):
            inputs.append(m.group(3).encode())
    return inputs


def build_ref(name):
    exe = BIN / name
    src = REF / name / 'src'
    if exe.exists() and exe.stat().st_mtime > (src / 'parser.c').stat().st_mtime:
        return exe
    BIN.mkdir(parents=True, exist_ok=True)
    language = re.search(r'const TSLanguage \*tree_sitter_(\w+)\(void\)', (src / 'parser.c').read_text()).group(1)
    sources = [str(src / 'parser.c')]
    for scanner in ['scanner.c', 'scanner.cc']:
        if (src / scanner).exists():
            sources.append(str(src / scanner))
    cmd = ['cc', '-O1', '-w', '-I', str(UPSTREAM / 'lib/include'), '-I', str(UPSTREAM / 'lib/src'), '-I', str(src),
           f'-DLANGUAGE=tree_sitter_{language}', str(UPSTREAM / 'lib/src/lib.c'), *sources,
           str(ROOT / 'tools/next/reference_parse.c'), '-o', str(exe)]
    subprocess.run(cmd, check=True)
    return exe


def mutate(data, rng):
    data = bytearray(data)
    for _ in range(rng.randint(1, 3)):
        op = rng.randrange(3)
        pos = rng.randrange(len(data) + 1)
        if op == 0 and data:
            del data[pos % len(data)]
        elif op == 1:
            data[pos:pos] = bytes([rng.choice(b'(){}[];,.=+-*/"\'\n x1')])
        elif data:
            end = min(len(data), pos + rng.randint(1, 8))
            data[pos:end] = b''
    return bytes(data)


def run(cmd):
    p = subprocess.run(cmd, capture_output=True, timeout=600)
    return p.stdout.decode(errors='replace'), p.returncode


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--mutate', type=int, default=0)
    ap.add_argument('--show', type=int, default=3)
    ap.add_argument('names', nargs='*')
    args = ap.parse_args()
    names = args.names or sorted(p.stem for p in LANG.glob('*.json'))
    total = same = 0
    for name in names:
        lang = json.loads((LANG / f'{name}.json').read_text())
        if lang['external_token_count'] and not args.names:
            continue
        inputs = corpus_inputs(name)
        rng = random.Random(name)
        inputs += [mutate(i, rng) for i in inputs for _ in range(args.mutate)]
        if not inputs:
            continue
        work = TMP / name
        work.mkdir(parents=True, exist_ok=True)
        paths = []
        for i, data in enumerate(inputs):
            p = work / f'{i}.txt'
            p.write_bytes(data)
            paths.append(str(p))
        ref = build_ref(name)
        expected, _ = run([str(ref), *paths])
        actual, code = run([str(PROBE), 'parse', str(LANG / f'{name}.json'), *paths])
        exp = expected.split('== ')[1:]
        act = actual.split('== ')[1:]
        n_same = sum(1 for a, b in zip(exp, act) if a == b)
        total += len(exp)
        same += n_same
        status = 'ok' if n_same == len(exp) and len(act) == len(exp) else 'DIFF'
        print(f'{name}: {n_same}/{len(exp)} {status}' + ('' if code == 0 else f' (probe exit {code})'), flush=True)
        shown = 0
        for a, b in zip(exp, act):
            if a != b and shown < args.show:
                shown += 1
                print('  expected:', a.strip()[:400])
                print('  actual:  ', b.strip()[:400])
        if len(act) < len(exp):
            print('  probe output truncated:', actual[-500:])
    print(f'TOTAL {same}/{total}')


if __name__ == '__main__':
    main()
