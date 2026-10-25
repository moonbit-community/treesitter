"""Development-only differential test of runtime against the C runtime.

For every reference grammar in _build/ref (see ref_generate.sh) whose tables
were converted to _build/reflang/<name>.json (language_from_c.py), parse the
grammar's corpus inputs (and optional mutations) with both runtimes and
compare the S-expressions.

Usage: python3 tools/oracle/diff_runtime.py [--mutate N] [names...]
"""
import argparse
import os
import hashlib
import json
import random
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REF = ROOT / '_build/ref'
LANG = Path(os.environ['NEXT_LANG_DIR']) if os.environ.get('NEXT_LANG_DIR') else ROOT / '_build/reflang'
BIN = ROOT / '_build/refbin'
TMP = ROOT / '_build/difftmp'
UPSTREAM = Path(subprocess.check_output(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], cwd=ROOT, text=True).strip()).parent / '.repos/ts-pinned'
PROBE = ROOT / '_build/native/release/build/moonbit-community/treesitter/tools/probe/probe.exe'

# Inputs for test grammars whose corpus is empty or does not reach the
# scanner's interesting paths, taken from upstream's crates/cli/src/tests.
EXTRA_INPUTS = {
    'get_col_eof': [b'a', b'ab', b'a\nb', b'\n', b''],
    'get_col_should_hang_not_crash': [b'\nHello'],
    'depends_on_column': [b'\n x', b'\n  x', b'\n\n  x'],
    'depends_on_column_failed_scan': [b'ax', b'\nx'],
    'depends_on_column_repetition': [b'\nax\na', b'\nax\n\na'],
    'utf16_surrogate_oob': [b'', b'\n  '],
    # Scanner edge cases: an indent one column deep (stored as -1), percent
    # strings and comments unterminated at EOF (the C scanners loop forever),
    # a line break followed by a member access, boxes before list items.
    'uses_current_column': [
        b'\na = b\nc = do d\n       e + f\n       g\nh + i\n    ',
        b'\na = b\nc1234 = do d\n       e + f\n       g\nh + i\n    ',
        b'do\n x\ny\n', b'do\n  a\n b\nc\n', b'a = do b\n c\n  d\ne\n',
    ],
    'external_tokens': [b'%(abc', b'%{a #{b} c', b'x + %[a [b] c] + y'],
    'external_extra_tokens': [b'x = # c', b'x = # a\n# b\ny'],
    'inverted_external_token': [b'a\n.b\nc\n', b'a\n\n  b\n.c'],
    'external_unicode_column_alignment': ['\u25a1 -\n-\n \u25a1-\n'.encode(), b'-\n -\n'],
    'external_lookahead_eof_boundary': [b'`', b'``', b'```', b'` `'],
}

# Wall-clock limits. Some test scanners loop forever by design (or on
# unterminated input, e.g. external_tokens at EOF); a batch that times out is
# rerun one input at a time, and an input on which both runtimes time out
# counts as identical ("hang").
# A batch may take BATCH_TIMEOUT seconds plus one per input.
BATCH_TIMEOUT = 30
SINGLE_TIMEOUT = 10

HEADER = re.compile(r'^(={3,})[^\n]*\n(.*?)\n\1[^\n]*\n(.*?)\n-{3,}[^\n]*\n', re.S | re.M)


def meta(name):
    """meta.json of an extra grammar (tools/oracle/grammars.py ref), if any."""
    path = REF / name / 'meta.json'
    return json.loads(path.read_text()) if path.exists() else None


def corpus_inputs(name):
    files = []
    if (m := meta(name)) is not None:
        for d in m['corpus']:
            files += sorted(Path(d).rglob('*.txt'))
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
    return inputs + EXTRA_INPUTS.get(name, [])


def build_ref(name, main='reference_parse.c', suffix=''):
    exe = BIN / (name + suffix)
    src = REF / name / 'src'
    if exe.exists() and exe.stat().st_mtime > (src / 'parser.c').stat().st_mtime:
        return exe
    BIN.mkdir(parents=True, exist_ok=True)
    language = re.search(r'const TSLanguage \*tree_sitter_(\w+)\(void\)', (src / 'parser.c').read_text()).group(1)
    sources = [str(src / 'parser.c')]
    candidates = [REF / name / 'scanner.c', src / 'scanner.c']
    if (m := meta(name)) is not None and m['scanner']:
        candidates.append(Path(m['scanner']))
    if name.startswith('fixture_'):
        parts = name[len('fixture_'):].split('_', 1)
        fixture = UPSTREAM / 'test/fixtures/grammars' / parts[0]
        if len(parts) > 1:
            fixture = fixture / parts[1]
        candidates.append(fixture / 'src/scanner.c')
    for scanner in candidates:
        if scanner.exists():
            sources.append(str(scanner))
            break
    cmd = ['cc', '-O1', '-w', '-I', str(UPSTREAM / 'lib/include'), '-I', str(UPSTREAM / 'lib/src'), '-I', str(src),
           f'-DLANGUAGE=tree_sitter_{language}', str(UPSTREAM / 'lib/src/lib.c'), *sources,
           str(ROOT / 'tools/oracle' / main), '-o', str(exe)]
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


def run(cmds, timeout):
    """Run the commands concurrently; returns [(stdout or None on timeout,
    exit code or 'timeout')]."""
    procs = [subprocess.Popen(c, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL) for c in cmds]
    # All commands share one deadline (they run concurrently).
    deadline = time.monotonic() + timeout
    results = []
    for p in procs:
        try:
            out, _ = p.communicate(timeout=max(0.1, deadline - time.monotonic()))
            results.append((out.decode(errors='replace'), p.returncode))
        except subprocess.TimeoutExpired:
            p.kill()
            p.communicate()
            results.append((None, 'timeout'))
    return results


def run_pair(ref_cmd, probe_cmd, groups):
    """Run both commands over `groups` (argument lists, one per output
    record); on a timeout, rerun each group alone. Returns the per-record
    outputs of both sides and the probe's exit code."""
    args = [a for g in groups for a in g]
    (expected, ref_code), (actual, code) = run([ref_cmd + args, probe_cmd + args], BATCH_TIMEOUT + len(groups))
    if ref_code == 0 and code == 0:
        return expected.split('== ')[1:], actual.split('== ')[1:], code
    exp, act, code = [], [], 0
    for g in groups:
        (e, ec), (a, c) = run([ref_cmd + g, probe_cmd + g], SINGLE_TIMEOUT)
        e = ['<hang>'] if e is None else e.split('== ')[1:]
        a = ['<hang>'] if a is None else a.split('== ')[1:]
        # Keep the records aligned when a side crashed before printing.
        if len(e) != 1:
            e = [f'<exit {ec}> ' + ''.join(e)]
        if len(a) != 1:
            a = [f'<exit {c}> ' + ''.join(a)]
        if c not in (0, 'timeout'):
            code = c
        exp += e
        act += a
    return exp, act, code


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--mutate', type=int, default=0)
    ap.add_argument('--show', type=int, default=3)
    ap.add_argument('--externals', action='store_true', help='include grammars with external scanners')
    ap.add_argument('--encoding', choices=['utf8', 'utf16le', 'utf16be'], help='re-encode inputs and parse with this encoding')
    ap.add_argument('--ranges', type=int, default=0, help='random included ranges per input')
    ap.add_argument('--log', action='store_true', help='compare parser logs')
    ap.add_argument('--edits', type=int, default=0, help='random edits per input (incremental mode)')
    ap.add_argument('--exclude', action='append', default=[], help='skip this grammar (repeatable)')
    ap.add_argument('names', nargs='*')
    args = ap.parse_args()
    names = [n for n in (args.names or sorted(p.stem for p in LANG.glob('*.json'))) if n not in args.exclude]
    total = same = 0
    for name in names:
        lang = json.loads((LANG / f'{name}.json').read_text())
        if lang['external_token_count'] and not args.names and not args.externals:
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
        if args.edits:
            ref = build_ref(name, 'reference_edit.c', '.edit')
            eargs = []
            for i, data in enumerate(inputs):
                for k in range(args.edits):
                    start = rng.randrange(len(data) + 1)
                    old_end = min(len(data), start + rng.choice([0, 0, 1, 2, 5]))
                    insert = bytes(rng.choice(b'(){}[];,.=+-*/"\'\n x1abc') for _ in range(rng.choice([0, 1, 1, 3])))
                    new = data[:start] + insert + data[old_end:]
                    q = work / f'{i}.{k}.new'
                    q.write_bytes(new)
                    eargs += [paths[i], str(q), str(start), str(old_end), str(start + len(insert))]
            groups = [eargs[k:k + 5] for k in range(0, len(eargs), 5)]
            exp, act, code = run_pair([str(ref)], [str(PROBE), 'edit', str(LANG / f'{name}.json')], groups)
        elif args.encoding or args.ranges:
            ref = build_ref(name, 'reference_modes.c', '.modes')
            enc = args.encoding or 'utf8'
            expected_parts, actual_parts = [], []
            for i, data in enumerate(inputs):
                text = data.decode('utf-8', errors='replace')
                if enc == 'utf16le':
                    data = text.encode('utf-16-le')
                elif enc == 'utf16be':
                    data = text.encode('utf-16-be')
                q = work / f'{i}.{enc}'
                q.write_bytes(data)
                spec = '-'
                if args.ranges:
                    unit = 1 if enc == 'utf8' else 2
                    cuts = sorted(rng.randrange(len(data) + 2) // unit * unit for _ in range(2 * args.ranges))
                    spec = ','.join(f'{cuts[k]}-{cuts[k + 1]}' for k in range(0, len(cuts), 2))
                (e, _), (a, code) = run([[str(ref), enc, spec, str(q)],
                                         [str(PROBE), 'modes', str(LANG / f'{name}.json'), enc, spec, str(q)]],
                                        BATCH_TIMEOUT)
                expected_parts.append('== <hang>' if e is None else e)
                actual_parts.append('== <hang>' if a is None else a)
            exp = ''.join(expected_parts).split('== ')[1:]
            act = ''.join(actual_parts).split('== ')[1:]
        elif args.log:
            ref = build_ref(name, 'reference_log.c', '.log')
            exp, act, code = run_pair([str(ref)], [str(PROBE), 'log', str(LANG / f'{name}.json')], [[p] for p in paths])
        else:
            ref = build_ref(name)
            exp, act, code = run_pair([str(ref)], [str(PROBE), 'parse', str(LANG / f'{name}.json')], [[p] for p in paths])
        n_same = sum(1 for a, b in zip(exp, act) if a == b)
        total += len(exp)
        same += n_same
        status = 'ok' if n_same == len(exp) and len(act) == len(exp) else 'DIFF'
        hangs = sum(1 for a, b in zip(exp, act) if a == b == '<hang>')
        if hangs:
            status += f' ({hangs} hang in both)'
        print(f'{name}: {n_same}/{len(exp)} {status}' + ('' if code == 0 else f' (probe exit {code})'), flush=True)
        shown = 0
        for a, b in zip(exp, act):
            if a != b and shown < args.show:
                shown += 1
                print('  expected:', a.strip()[:400])
                print('  actual:  ', b.strip()[:400])
        if len(act) < len(exp):
            print('  probe output truncated:', ''.join(act)[-500:])
    print(f'TOTAL {same}/{total}')
    sys.exit(0 if same == total else 1)


if __name__ == '__main__':
    main()
