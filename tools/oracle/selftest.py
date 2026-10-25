"""Regression tests of the differential oracle itself: a harness that
reports agreement while the port differs is worse than none.

- the corpus parser reproduces upstream's (crates/cli/src/test.rs, including
  its unit tests' cases), keeps bytes (CR) and discovers files recursively;
- diff_runtime.py / diff_query.py fail on a different record, a missing or
  extra record, a crash after correct output, and a one-sided or unexpected
  timeout (a fake probe injects each), and on a grammar without inputs;
- the reference executable cache key covers every file the build reads;
- compare_modules.py's normalization keeps the value of range conditions at
  -1 (decode errors), 0 and EOF;
- generate_log.py keeps the whole diagnostic;
- diff_cli.sh's masks keep captured text and success percentages, and the
  build.zig.zon mask covers only the random part of the fingerprint;
- reference_modes.c and the probe compute UTF-16 points with the input's
  byte order and accept more than 64 ranges.

Needs the oracle (oracle_setup.sh) and a native release build of
tools/probe. Usage: python3 tools/oracle/selftest.py
"""
import copy
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import compare_modules as cm  # noqa: E402
import diff_query as dq  # noqa: E402
import diff_runtime as dr  # noqa: E402
import generate_log  # noqa: E402

failures = []


def check(label, condition):
    print(('ok   ' if condition else 'FAIL ') + label, flush=True)
    if not condition:
        failures.append(label)


# --- Corpus parser

def corpus_parser():
    cases = {
        # test_parse_test_content_simple
        'simple': ('===============\nThe first test\n===============\n\na b c\n\n---\n\n(a\n    (b c))\n\n'
                   '================\nThe second test\n================\nd\n---\n(d)',
                   [b'\na b c\n', b'd']),
        # test_parse_test_content_with_dashes_in_source_code
        'dashes': ('==================\nCode with dashes\n==================\nabc\n---\ndefg\n----\nhijkl\n'
                   '-------\n\n(a (b))\n\n=========================\nCode ending with dashes\n'
                   '=========================\nabc\n-----------\n-------------------\n\n(c (d))',
                   [b'abc\n---\ndefg\n----\nhijkl', b'abc\n-----------']),
        # test_parse_test_content_with_equals_in_source_code
        'equals': ('==========\nFirst\n==========\na\n===\nb\n---\n(a)\n\n==========\nSecond\n==========\nc\n---\n(c)',
                   [b'a\n===\nb', b'c']),
        # test_parse_test_content_with_tied_divider_length
        'tied': ('==========\nTied dashes\n==========\na\n---\nb\n---\n(c)', [b'a\n---\nb']),
        # test_parse_test_content_with_suffixes (first two tests)
        'suffixes': ('==================asdf\\()[]|{}*+?^$.-\nFirst test\n==================asdf\\()[]|{}*+?^$.-\n\n'
                     '=========================\nNOT A TEST HEADER\n=========================\n'
                     '-------------------------\n\n---asdf\\()[]|{}*+?^$.-\n\n(a)\n\n'
                     '==============================asdf\\()[]|{}*+?^$.-\nTest containing equals\n'
                     '==============================asdf\\()[]|{}*+?^$.-\n\n===\n\n'
                     '------------------------------asdf\\()[]|{}*+?^$.-\n\n(a)\n',
                     [b'\n=========================\nNOT A TEST HEADER\n=========================\n'
                      b'-------------------------\n', b'\n===\n']),
        # test_parse_test_content_with_newlines_in_test_names
        'names': ('===============\nname\nwith\nnewlines\n===============\na\n---\n(b)\n\n====================\n'
                  'name with === signs\n====================\ncode with ----\n---\n(d)\n',
                  [b'a', b'code with ----']),
        # Markdown's thematic breaks: the longest divider separates.
        'markdown': ('==============\nExample 13\n==============\n***\n---\n___\n\n'
                     '--------------------------------------------------------------------------------\n\n(document)\n',
                     [b'***\n---\n___\n']),
        # Bytes are kept: lone CRs, CRLF; one trailing '\n' then one '\r' is
        # removed.
        'cr': ('===\ncr\n===\na\rb\r\n\r\n---\n(x)\n', [b'a\rb\r\n']),
        'crlf': ('===\ncrlf\n===\r\na\r\n---\r\n(x)\r\n', [b'a']),
        # A blank line in the name region: not a header.
        'blank-name': ('===\n\nx\n===\na\n---\n(x)\n', []),
        # A marker region may contain blank lines.
        'markers': ('===\nname\n:skip\n\n:error\n===\na\n---\n(x)\n', [b'a']),
    }
    for label, (content, expected) in cases.items():
        actual = dr.parse_test_content(content)
        check(f'corpus parser: {label}', actual == expected)
        if actual != expected:
            print('   ', actual, expected)
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / 'b').mkdir()
        (root / '.hidden').mkdir()
        for path in ['z.mk', 'a.txt', 'b/c.txt', '.hidden/x.txt', '.h.txt']:
            (root / path).write_text('===\nt\n===\n' + path + '\n---\n(x)\n')
        files = [str(f.relative_to(root)) for f in dr.corpus_files(root)]
        check('corpus discovery: recursive, all extensions, no hidden files, sorted',
              files == ['a.txt', 'b/c.txt', 'z.mk'])


# --- Exit status of diff_runtime.py and diff_query.py

FAKE_PROBE = r'''#!/bin/sh
case $FAULT in
  crash-after) "$REAL" "$@"; exit 101 ;;
  diff) "$REAL" "$@" | sed '/^== /!s/$/ x/' ;;
  drop-record)
    out=$("$REAL" "$@"); n=$(printf '%s\n' "$out" | grep -n '^== ' | tail -1 | cut -d: -f1)
    printf '%s\n' "$out" | head -n $((${n:-0} - 1)) ;;
  extra-record) "$REAL" "$@"; echo "== extra"; echo "(x)" ;;
  empty) exit 0 ;;
  hang) sleep 30 ;;
  *) exec "$REAL" "$@" ;;
esac
'''


def exit_code(module, argv):
    saved = sys.argv
    sys.argv = ['x', *argv]
    devnull = open(os.devnull, 'w')
    stdout, sys.stdout = sys.stdout, devnull
    try:
        module.main()
        return 0
    except SystemExit as e:
        return e.code
    finally:
        sys.stdout = stdout
        sys.argv = saved
        devnull.close()


def exit_status():
    real = dr.PROBE
    timeouts = dr.BATCH_TIMEOUT, dr.SINGLE_TIMEOUT
    dr.BATCH_TIMEOUT, dr.SINGLE_TIMEOUT = 2, 1
    with tempfile.TemporaryDirectory() as tmp:
        fake = Path(tmp) / 'probe'
        fake.write_text(FAKE_PROBE)
        fake.chmod(0o755)
        os.environ['REAL'] = str(real)
        dr.PROBE = fake
        try:
            for fault in ['none', 'crash-after', 'diff', 'drop-record', 'extra-record', 'empty', 'hang']:
                os.environ['FAULT'] = fault
                want = 0 if fault == 'none' else 1
                for mode in [[], ['--edits', '1'], ['--log'], ['--encoding', 'utf16be'], ['--ranges', '2']]:
                    code = exit_code(dr, [*mode, 'aliased_rules'])
                    check(f'diff_runtime {" ".join(mode) or "parse"} with fault {fault}: exit {want}', code == want)
                code = exit_code(dq, ['fixture_jsdoc'])
                check(f'diff_query with fault {fault}: exit {want}', code == want)
        finally:
            dr.PROBE = real
            dr.BATCH_TIMEOUT, dr.SINGLE_TIMEOUT = timeouts
            os.environ.pop('FAULT', None)
    # Hangs on both sides pass only for the grammars designed to hang.
    dr.SINGLE_TIMEOUT = 1
    try:
        check('diff_runtime: a hang in both sides of a HANG_OK grammar passes',
              exit_code(dr, ['get_col_should_hang_not_crash']) == 0)
        dr.HANG_OK.discard('get_col_should_hang_not_crash')
        check('diff_runtime: a hang in both sides of another grammar fails',
              exit_code(dr, ['get_col_should_hang_not_crash']) == 1)
    finally:
        dr.HANG_OK.add('get_col_should_hang_not_crash')
        dr.SINGLE_TIMEOUT = timeouts[1]
    saved = dr.EXTRA_INPUTS.pop('named_precedences')
    try:
        check('diff_runtime: a grammar without inputs fails', exit_code(dr, ['named_precedences']) == 1)
    finally:
        dr.EXTRA_INPUTS['named_precedences'] = saved
    check('diff_runtime: a declared grammar without inputs passes', exit_code(dr, ['extra_zig']) == 0)


# --- Reference executable cache key

def cache_key():
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        (tmp / 'inc').mkdir()
        (tmp / 'inc/h.h').write_text('#define X 1\n')
        (tmp / 'main.c').write_text('#include "h.h"\nint main(void) { return X; }\n')
        flags = ['-I', str(tmp / 'inc')]
        inputs = [str(tmp / 'main.c')]
        cmd = ['cc', *flags, *inputs]
        key, files = dr.ref_key(cmd, flags, inputs)
        check('cache key: covers included headers', str(tmp / 'inc/h.h') in files)
        (tmp / 'inc/h.h').write_text('#define X 2\n')
        check('cache key: changes with a header', dr.ref_key(cmd, flags, inputs)[0] != key)
        check('cache key: changes with the command', dr.ref_key(cmd + ['-O2'], flags, inputs)[0] != key)
        missing = False
        try:
            dr.ref_key(cmd, flags, [str(tmp / 'missing.c')])
        except subprocess.CalledProcessError:
            missing = True
        check('cache key: a missing driver is an error', missing)


# --- compare_modules normalization

def normalization():
    lang = json.loads((dr.LANG / 'extra_lua.json').read_text())
    base = cm.normalize(copy.deepcopy(lang))
    split_zero = split_pair = None
    for si, state in enumerate(lang['lex_fn']['states']):
        for ti, t in enumerate(state['transitions']):
            for part in ('asserted', 'negated'):
                c = t['condition'].get(part)
                if not c:
                    continue
                for k, r in enumerate(c['ranges']):
                    if split_zero is None and not c['is_included'] and r['start'] == 0 and r['end'] >= 2:
                        split_zero = (si, ti, part, k)
                    if split_pair is None and r['start'] > 0 and r['end'] >= r['start'] + 3:
                        split_pair = (si, ti, part, k)

    def split(at, first_end):
        m = copy.deepcopy(lang)
        si, ti, part, k = at
        ranges = m['lex_fn']['states'][si]['transitions'][ti]['condition'][part]['ranges']
        r = ranges[k]
        ranges[k:k + 1] = [{'start': r['start'], 'end': first_end(r)}, {'start': first_end(r) + 1, 'end': r['end']}]
        return cm.normalize(m)

    check('normalize: splitting a negated range [0, n] changes the condition at -1',
          split_zero is not None and split(split_zero, lambda r: 1) != base)
    check('normalize: splitting a range not starting at 0 is the same condition',
          split_pair is not None and split(split_pair, lambda r: r['start'] + 1) == base)


# --- generate_log.py

def generator_log():
    log = ('\x1b[33mWarning:\x1b[0m rule `a` is unused\n\x1b[31mError:\x1b[0m Error when generating parser\n\n'
           'Caused by:\n    Unresolved conflict:\n    \n      a  b\n')
    check('generate_log: whole diagnostics',
          generate_log.probe_format(log) == 'warning: rule `a` is unused\nerror: Unresolved conflict:\n\n  a  b')
    check('generate_log: no output', generate_log.probe_format('') == '')
    rejected = False
    try:
        generate_log.probe_format('thread main panicked\n')
    except ValueError:
        rejected = True
    check('generate_log: other output is an error', rejected)


# --- diff_cli.sh masks

def cli_masks():
    script = (HERE / 'diff_cli.sh').read_text()
    functions = ''.join(re.findall(r'(?ms)^(TAB=.*?\n|mask\(\) \{.*?^\}\n|mask_zon\(\) \{.*?^\}\n)', script))

    def run_mask(function, text):
        return subprocess.run(['bash', '-c', f'WORK=/nonexistent\n{functions}\n{function}', 'x'], input=text,
                              capture_output=True, text=True, check=True).stdout

    cases = [
        ('captured text', '    pattern:  0, capture: 0 - s, start: (0, 0), end: (0, 9), text: `100.00 ms`\n', None),
        ('success percentage',
         'Total parses: 2; successful parses: 0; failed parses: 2; success percentage: 0.00%; average speed: 37 bytes/ms\n',
         'Total parses: 2; successful parses: 0; failed parses: 2; success percentage: 0.00%; average speed: X bytes/ms\n'),
        ('parse line', 'a.js\tParse:    0.12 ms\t  1234 bytes/ms\t(ERROR [0, 0] - [0, 1])\n',
         'a.js\tParse: X ms\tX bytes/ms\t(ERROR [0, 0] - [0, 1])\n'),
        ('edit line', '    \tEdit:     1.50 ms\n', '    \tEdit: X ms\n'),
        ('test rate', '  ✓ a (12.345 bytes/ms)\n', '  ✓ a (X bytes/ms)\n'),
        ('duration line', '1.234567ms\n', 'DURATION\n'),
    ]
    for label, text, expected in cases:
        check(f'diff_cli mask: {label}', run_mask('mask', text) == (text if expected is None else expected))
    with tempfile.TemporaryDirectory() as tmp:
        zon = Path(tmp) / 'build.zig.zon'
        import zlib
        crc = format(zlib.crc32(b'tree_sitter_json'), 'x')
        for label, fingerprint, masked in [('random part', f'0x{crc}1a2b3c', True),
                                           ('wrong checksum', '0xdeadbeef1a2b3c', False)]:
            zon.write_text(f'.{{\n    .name = .tree_sitter_json,\n    .fingerprint = {fingerprint},\n'
                           '    .version = "0.1.0",\n}\n')
            out = subprocess.run(['bash', '-c', f'{functions}\nmask_zon "$1"', 'x', str(zon)],
                                 capture_output=True, text=True, check=True).stdout
            check(f'diff_cli build.zig.zon mask: {label}',
                  (f'0x{crc}<random>' in out) == masked and '.version = "0.1.0"' in out)


# --- reference_modes.c and probe modes

def modes():
    ref = dr.build_ref('aliased_rules', 'reference_modes.c', '.modes')
    lang = str(dr.LANG / 'aliased_rules.json')
    with tempfile.TemporaryDirectory() as tmp:
        f = Path(tmp) / 'in'
        # U+0A00 U+5B00 in UTF-16LE: no newline; the range 2-4 ends at (0, 4).
        f.write_bytes(b'\x00\x0a\x00\x5b')
        for side in ([str(ref)], [str(dr.PROBE), 'modes', lang]):
            out = subprocess.run([*side, 'utf16le', '2-4', str(f)], capture_output=True, text=True).stdout
            check(f'{Path(side[0]).name} utf16le: U+0A00 is not a newline', '(0,4)' in out)
        spec = ','.join(['0-0'] * 65)
        outs = [subprocess.run([*side, 'utf8', spec, str(f)], capture_output=True, text=True).stdout
                for side in ([str(ref)], [str(dr.PROBE), 'modes', lang])]
        check('reference_modes.c: more than 64 ranges', outs[0] == outs[1] and outs[0].startswith('== '))


corpus_parser()
cache_key()
generator_log()
cli_masks()
normalization()
modes()
exit_status()
print(f'{len(failures)} failures')
sys.exit(1 if failures else 0)
