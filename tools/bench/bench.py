"""Benchmark this port against the pinned upstream build.

  python3 tools/bench/bench.py parse [names...]     # ms/parse, MoonBit vs C (-O2)
  python3 tools/bench/bench.py generate [names...]  # s/generate, MoonBit vs tree-sitter generate

Needs the oracle set up (tools/oracle/oracle_setup.sh) and a release probe
(`moon build --target native --release tools/probe`). Each figure is the
minimum of K runs.
"""
import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COMMON = Path(subprocess.check_output(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'],
                                      cwd=ROOT, text=True).strip()).parent
UPSTREAM = COMMON / '.repos/ts-pinned'
PROBE = ROOT / '_build/native/release/build/moonbit-community/treesitter/tools/probe/probe.exe'
OUT = ROOT / '_build/bench'
FIXTURES = UPSTREAM / 'test/fixtures/grammars'
PARSE = {
    'c': UPSTREAM / 'lib/src/parser.c',
    'json': UPSTREAM / 'lib/binding_web/package-lock.json',
    'go': FIXTURES / 'go/examples/proc.go',
    'python': FIXTURES / 'python/examples/python3-grammar.py',
    'javascript': FIXTURES / 'javascript/examples/jquery.js',
    'rust': UPSTREAM / 'lib/binding_rust/lib.rs',
}
GENERATE = ['json', 'c', 'rust', 'typescript_typescript', 'cpp', 'ruby']
K = 5


def c_bench(name):
    exe = OUT / f'parse_{name}'
    src = ROOT / f'_build/ref/fixture_{name}/src'
    if exe.exists() and exe.stat().st_mtime > (src / 'parser.c').stat().st_mtime:
        return exe
    OUT.mkdir(parents=True, exist_ok=True)
    language = re.search(r'const TSLanguage \*tree_sitter_(\w+)\(void\)', (src / 'parser.c').read_text()).group(1)
    scanner = FIXTURES / name / 'src/scanner.c'
    cmd = ['cc', '-O2', '-w', '-I', str(UPSTREAM / 'lib/include'), '-I', str(UPSTREAM / 'lib/src'), '-I', str(src),
           f'-DLANGUAGE=tree_sitter_{language}', str(UPSTREAM / 'lib/src/lib.c'), str(src / 'parser.c'),
           *([str(scanner)] if scanner.exists() else []), str(Path(__file__).with_name('bench_parse.c')),
           '-o', str(exe)]
    subprocess.run(cmd, check=True)
    return exe


def ms_per_parse(cmd):
    out = subprocess.check_output(cmd, text=True)
    return float(re.search(r'\(([\d.]+) ms/parse\)', out).group(1))


def parse(names):
    for name in names or list(PARSE):
        n = '20'
        mb = min(ms_per_parse([str(PROBE), 'bench', str(ROOT / f'_build/reflang/fixture_{name}.json'),
                               str(PARSE[name]), n]) for _ in range(K))
        c = min(ms_per_parse([str(c_bench(name)), str(PARSE[name]), n]) for _ in range(K))
        print(f'{name:12} MoonBit {mb:8.2f} ms   C {c:7.2f} ms   ratio {mb / c:5.2f}x', flush=True)


def seconds(cmd, cwd):
    best = None
    for _ in range(K):
        start = time.perf_counter()
        subprocess.run(cmd, cwd=cwd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        t = time.perf_counter() - start
        best = t if best is None else min(best, t)
    return best


def generate(names):
    ts = UPSTREAM / 'target/release/tree-sitter'
    for name in names or GENERATE:
        grammar = ROOT / f'_build/ref/fixture_{name}/src/grammar.json'
        work = OUT / f'gen_{name}'
        work.mkdir(parents=True, exist_ok=True)
        mb = seconds([str(PROBE), 'generate', str(grammar), str(work)], ROOT)
        up = seconds([str(ts), 'generate', str(grammar), '-o', str(work / 'up')], work)
        print(f'{name:22} MoonBit {mb:6.2f} s   upstream {up:6.2f} s   ratio {mb / up:5.2f}x', flush=True)


if __name__ == '__main__':
    mode, names = sys.argv[1], sys.argv[2:]
    {'parse': parse, 'generate': generate}[mode](names)
