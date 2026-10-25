"""Development-only differential test of runtime against the C runtime.

For every reference grammar in _build/ref (see ref_generate.sh) whose tables
were converted to _build/reflang/<name>.json (language_from_c.py), parse the
grammar's corpus inputs (and optional mutations) with both runtimes and
compare the S-expressions.

An input passes when both sides exit successfully and print the same record
for it. Everything else fails the run: a different record, a missing or
extra record, a non-zero exit (a crash) on either side, and a timeout, except
that an input on which both sides time out counts as a "hang in both" for
the grammars of HANG_OK, whose scanners loop forever by design. A grammar
with no inputs fails unless it is listed in NO_INPUTS.

Usage: python3 tools/oracle/diff_runtime.py [--mutate N] [names...]
"""
import argparse
import os
import hashlib
import itertools
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
PROBE = Path(os.environ.get('PROBE') or ROOT / '_build/native/release/build/moonbit-community/treesitter/tools/probe/probe.exe')

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
    'external_unicode_column_alignment': ['□ -\n-\n □-\n'.encode(), b'-\n -\n'],
    'external_lookahead_eof_boundary': [b'`', b'``', b'```', b'` `'],
    # Its corpus.txt has headers but no `---` dividers, so upstream's corpus
    # parser extracts no test from it; these are the inputs written there.
    'named_precedences': [b'A||B c = d;\nE.F g = h;', b'a || b.c;'],
}

# Grammars whose external scanners loop forever by design on some inputs: an
# input on which both runtimes time out counts as identical ("hang in both").
# A timeout of any other grammar, or of one side only, is a failure.
HANG_OK = {
    # Its scanner never advances past a column it cannot match (upstream's
    # test only checks that the parser does not crash).
    'get_col_should_hang_not_crash',
    # Percent strings unterminated at EOF.
    'external_tokens',
    # Strings unterminated at EOF (`while (lookahead != '\'') advance`).
    'external_and_internal_tokens',
    'external_and_internal_anonymous_tokens',
    # Comments unterminated at EOF (`while (lookahead != '\n') advance`).
    'external_extra_tokens',
    # Percent strings and comments unterminated at EOF.
    'uses_current_column',
}

# Grammars that have no corpus (and no EXTRA_INPUTS) upstream; any other
# grammar without inputs is a failure (a corpus that silently went missing).
NO_INPUTS = {
    'extra_zig',  # tree-sitter-zig has no test corpus
}

# Wall-clock limits. A batch may take BATCH_TIMEOUT seconds plus one per
# input; a batch that fails or times out is rerun one input at a time, each
# with SINGLE_TIMEOUT.
BATCH_TIMEOUT = 30
SINGLE_TIMEOUT = 10


def meta(name):
    """meta.json of an extra grammar (tools/oracle/grammars.py ref), if any."""
    path = REF / name / 'meta.json'
    return json.loads(path.read_text()) if path.exists() else None


# --- The corpus parser of upstream's `tree-sitter test`
# (crates/cli/src/test.rs: parse_tests, parse_test_content, parse_header,
# build_test_entry), reduced to the inputs it extracts.

# `char::is_whitespace` (Unicode White_Space), used by Rust's `str::trim`.
RUST_WHITESPACE = ('\t\n\x0b\x0c\r \x85\xa0 ' + ''.join(chr(c) for c in range(0x2000, 0x200b))
                   + '    　')


def corpus_files(path):
    """`parse_tests`: a file, or a directory's non-hidden entries sorted by
    file name, recursively."""
    if path.is_dir():
        children = sorted((c for c in path.iterdir() if not c.name.startswith('.')),
                          key=lambda c: os.fsencode(c.name))
        return [f for c in children for f in corpus_files(c)]
    return [path]


def split_inclusive(content):
    """`str::split_inclusive('\\n')`."""
    lines = content.split('\n')
    result = [line + '\n' for line in lines[:-1]]
    if lines[-1]:
        result.append(lines[-1])
    return result


def parse_delimiter_line(line, c):
    delim_len = len(line) - len(line.lstrip(c))
    if delim_len < 3:
        return None
    return delim_len, line[delim_len:].rstrip('\r\n')


def suffix_matches(first_suffix, suffix):
    if first_suffix is None:
        return suffix == ''
    return suffix != '' and first_suffix == suffix


def parse_header(lines, first_suffix, start):
    """The index of the first body line of the header starting at
    `lines[start]`, or None."""
    delim = parse_delimiter_line(lines[start], '=')
    if delim is None or not suffix_matches(first_suffix, delim[1]):
        return None
    seen_marker = False
    i = start + 1
    while i < len(lines):
        closing = parse_delimiter_line(lines[i], '=')
        if closing is not None and suffix_matches(first_suffix, closing[1]):
            break
        trimmed = lines[i].strip(RUST_WHITESPACE)
        if not trimmed and not seen_marker:
            return None
        head = trimmed.split('(')[0]
        if head in (':skip', ':fail-fast', ':error', ':cst'):
            seen_marker = True
        elif head in (':platform', ':language'):
            prefix = head + '('
            if trimmed.startswith(prefix) and trimmed[len(prefix):].endswith(')'):
                seen_marker = True
        i += 1
    if i >= len(lines):
        return None
    return i + 1


def test_input(body, first_suffix):
    """`build_test_entry`: the input before the longest matching `---`
    divider (the later one on ties), or None without a divider."""
    best = None
    best_total_len = 0
    for j, line in enumerate(body):
        delim = parse_delimiter_line(line, '-')
        if delim is not None and suffix_matches(first_suffix, delim[1]):
            total_len = delim[0] + len(delim[1].encode())
            if total_len >= best_total_len:
                best, best_total_len = j, total_len
    if best is None:
        return None
    data = ''.join(body[:best]).encode()
    if data.endswith(b'\n'):
        data = data[:-1]
    if data.endswith(b'\r'):
        data = data[:-1]
    return data


def parse_test_content(content):
    """The inputs of the tests of one corpus file, in order."""
    lines = split_inclusive(content)
    first_suffix = None
    for line in lines:
        delim = parse_delimiter_line(line, '=')
        if delim is not None and delim[1]:
            first_suffix = delim[1]
            break
    inputs = []
    i = 0
    prev = None
    while i < len(lines):
        body_start = parse_header(lines, first_suffix, i)
        if body_start is None:
            i += 1
            continue
        if prev is not None and (data := test_input(lines[prev:i], first_suffix)) is not None:
            inputs.append(data)
        prev = i = body_start
    if prev is not None and (data := test_input(lines[prev:], first_suffix)) is not None:
        inputs.append(data)
    return inputs


def corpus_inputs(name):
    roots = []
    if (m := meta(name)) is not None:
        roots += [Path(d) for d in m['corpus']]
    test_dir = UPSTREAM / 'test/fixtures/test_grammars' / name
    if (test_dir / 'corpus.txt').exists():
        roots.append(test_dir / 'corpus.txt')
    if name.startswith('fixture_'):
        # fixture_<dir>[_<language dir>]: the corpus is the repository's.
        corpus = UPSTREAM / 'test/fixtures/grammars' / name[len('fixture_'):].split('_')[0] / 'test/corpus'
        if corpus.is_dir():
            roots.append(corpus)
    inputs = []
    for root in roots:
        for f in corpus_files(root):
            # `fs::read_to_string`: the file must be UTF-8; no newline
            # translation.
            inputs += parse_test_content(f.read_bytes().decode('utf-8'))
    return inputs + EXTRA_INPUTS.get(name, [])


# --- C reference executables

def build_ref(name, main='reference_parse.c', suffix=''):
    """Compile the C runtime, the grammar's parser (and scanner) and the
    driver `main`; cached under _build/refbin, keyed by the command and the
    contents of every file it reads (including headers, from `cc -MM`)."""
    exe = BIN / (name + suffix)
    src = REF / name / 'src'
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
    flags = ['-O1', '-w', '-I', str(UPSTREAM / 'lib/include'), '-I', str(UPSTREAM / 'lib/src'), '-I', str(src),
             f'-DLANGUAGE=tree_sitter_{language}']
    inputs = [str(UPSTREAM / 'lib/src/lib.c'), *sources, str(ROOT / 'tools/oracle' / main)]
    cmd = ['cc', *flags, *inputs, '-o', str(exe)]
    key, _ = ref_key(cmd, flags, inputs)
    stamp = exe.with_name(exe.name + '.key')
    if exe.exists() and stamp.exists() and stamp.read_text() == key:
        return exe
    BIN.mkdir(parents=True, exist_ok=True)
    stamp.unlink(missing_ok=True)
    subprocess.run(cmd, check=True)
    stamp.write_text(key)
    return exe


def ref_key(cmd, flags, inputs):
    """The cache key of a reference executable: a hash of the compile
    command, the compiler's version and the contents of every file the
    compilation reads (the inputs and their headers, from `cc -MM`), with the
    list of those files."""
    deps = subprocess.run(['cc', '-MM', *flags, *inputs], check=True, capture_output=True, text=True).stdout
    files = sorted({f for f in re.split(r'\s+', deps.replace('\\\n', ' ')) if f and not f.endswith(':')})
    key = hashlib.sha256('\0'.join(cmd).encode())
    key.update(subprocess.run(['cc', '--version'], check=True, capture_output=True).stdout)
    for f in files:
        key.update(f.encode() + b'\0' + Path(f).read_bytes() + b'\0')
    return key.hexdigest(), files


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


# --- Running both sides

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


def split_records(out, labels, preamble=False):
    """The records of `out` (each starts with a line `== <label>`), or None
    unless there is exactly one per label, in order. With `preamble`, the
    text before the first record is returned as an extra first record."""
    parts = re.split(r'(?m)^== ', out)
    head, parts = parts[0], parts[1:]
    if preamble and head.startswith('error ') and not parts:
        # A query that does not compile: no records.
        return [head]
    if len(parts) != len(labels) or (head and not preamble):
        return None
    for part, label in zip(parts, labels):
        if part.split('\n', 1)[0] != label:
            return None
    return [head] + parts if preamble else parts


def side(out, code, labels, preamble):
    """One side's per-record (text, status) list for one run. status is 0,
    'timeout', or the exit code / 'bad output' of a run that failed."""
    n = len(labels) + (1 if preamble else 0)
    if out is None:
        return [('<hang>', 'timeout')] * n
    records = split_records(out, labels, preamble)
    if code == 0 and records is not None:
        return [(r, 0) for r in records]
    status = code if code != 0 else 'bad output'
    return [(f'<exit {status}> ' + out[-2000:], status)] * n


def run_pair(ref_cmd, probe_cmd, groups, labels, preamble=False):
    """Run both commands over `groups` (argument lists, one per output
    record, labelled `labels`); if either side fails or times out, rerun
    each group alone. Returns [((expected, status), (actual, status))]."""
    args = [a for g in groups for a in g]
    (e, ec), (a, ac) = run([ref_cmd + args, probe_cmd + args], BATCH_TIMEOUT + len(groups))
    pairs = pair(side(e, ec, labels, preamble), side(a, ac, labels, preamble))
    if all(es == as_ == 0 for (_, es), (_, as_) in pairs):
        return pairs
    pairs = []
    for g, label in zip(groups, labels):
        (e, ec), (a, ac) = run([ref_cmd + g, probe_cmd + g], SINGLE_TIMEOUT)
        exp, act = side(e, ec, [label], preamble), side(a, ac, [label], preamble)
        if preamble:
            # One record per group: the preamble and the group's record.
            exp, act = ([(''.join(t for t, _ in r), 0)] if r[0][1] == 0 else r[:1] for r in (exp, act))
        pairs += pair(exp, act)
    return pairs


def pair(exp, act):
    """The records of both sides side by side; a record missing on one
    side is a failure."""
    missing = ('<missing record>', 'missing')
    return list(itertools.zip_longest(exp, act, fillvalue=missing))


def judge(name, pairs):
    """(passed, hangs, failures) of the record pairs of one grammar."""
    passed, hangs, failures = 0, 0, []
    for (e, es), (a, as_) in pairs:
        if es == as_ == 0 and e == a:
            passed += 1
        elif es == as_ == 'timeout' and name in HANG_OK:
            passed += 1
            hangs += 1
        else:
            failures.append((e, es, a, as_))
    return passed, hangs, failures


def report(label, pairs, name, show):
    """Print the status line of `pairs`; returns (passed, total)."""
    passed, hangs, failures = judge(name, pairs)
    status = 'ok' if not failures else 'DIFF'
    if hangs:
        status += f' ({hangs} hang in both)'
    kinds = sorted({f'ref {es}' for _, es, _, _ in failures if es != 0}
                   | {f'probe {as_}' for _, _, _, as_ in failures if as_ != 0}, key=str)
    if kinds:
        status += ' (' + ', '.join(kinds) + ')'
    print(f'{label}: {passed}/{len(pairs)} {status}', flush=True)
    for e, es, a, as_ in failures[:show]:
        print('  expected:', e.strip()[:400])
        print('  actual:  ', a.strip()[:400])
    return passed, len(pairs)


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
    failed = False
    for name in names:
        lang = json.loads((LANG / f'{name}.json').read_text())
        if lang['external_token_count'] and not args.names and not args.externals:
            continue
        inputs = corpus_inputs(name)
        rng = random.Random(name)
        inputs += [mutate(i, rng) for i in inputs for _ in range(args.mutate)]
        if not inputs:
            if name in NO_INPUTS:
                print(f'{name}: no inputs (declared)')
            else:
                print(f'{name}: 0/0 DIFF (no inputs)')
                failed = True
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
            groups = []
            for i, data in enumerate(inputs):
                for k in range(args.edits):
                    start = rng.randrange(len(data) + 1)
                    old_end = min(len(data), start + rng.choice([0, 0, 1, 2, 5]))
                    insert = bytes(rng.choice(b'(){}[];,.=+-*/"\'\n x1abc') for _ in range(rng.choice([0, 1, 1, 3])))
                    new = data[:start] + insert + data[old_end:]
                    q = work / f'{i}.{k}.new'
                    q.write_bytes(new)
                    groups.append([paths[i], str(q), str(start), str(old_end), str(start + len(insert))])
            pairs = run_pair([str(ref)], [str(PROBE), 'edit', str(LANG / f'{name}.json')], groups,
                             [g[1] for g in groups])
        elif args.encoding or args.ranges:
            ref = build_ref(name, 'reference_modes.c', '.modes')
            enc = args.encoding or 'utf8'
            pairs = []
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
                (e, ec), (a, ac) = run([[str(ref), enc, spec, str(q)],
                                        [str(PROBE), 'modes', str(LANG / f'{name}.json'), enc, spec, str(q)]],
                                       BATCH_TIMEOUT)
                pairs += pair(side(e, ec, [str(q)], False), side(a, ac, [str(q)], False))
        elif args.log:
            ref = build_ref(name, 'reference_log.c', '.log')
            pairs = run_pair([str(ref)], [str(PROBE), 'log', str(LANG / f'{name}.json')], [[p] for p in paths], paths)
        else:
            ref = build_ref(name)
            pairs = run_pair([str(ref)], [str(PROBE), 'parse', str(LANG / f'{name}.json')], [[p] for p in paths], paths)
        n_same, n = report(name, pairs, name, args.show)
        same += n_same
        total += n
    print(f'TOTAL {same}/{total}')
    sys.exit(0 if same == total and not failed else 1)


if __name__ == '__main__':
    main()
