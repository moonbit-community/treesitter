"""The diagnostics of an upstream `tree-sitter generate` run (its combined
output, _build/ref/<name>/generate.log) in the format of `probe generate`:
one `warning: <message>` per diagnostic, then `error: <message>` if the
grammar is rejected. Only the CLI's presentation is removed: colors, the
`Warning:` prefix, and the `Error: Error when generating parser` / `Caused
by:` wrapper with its four-space indentation of the message.

Usage: python3 tools/oracle/generate_log.py LOG
"""
import re
import sys

WRAPPER = 'Error: Error when generating parser\n\nCaused by:\n'


def probe_format(log):
    """`log` in the probe's format; raises ValueError on output that is not
    a warning or a wrapped generator error."""
    log = re.sub(r'\x1b\[[0-9;]*m', '', log)
    error = None
    if WRAPPER in log:
        log, cause = log.split(WRAPPER, 1)
        lines = cause.rstrip('\n').split('\n')
        if not all(line.startswith('    ') or line == '' for line in lines):
            raise ValueError('unexpected error format: ' + cause[:200])
        error = 'error: ' + '\n'.join(line[4:] for line in lines)
    out = []
    # Warnings start with `Warning: ` and may span several lines.
    text = log.rstrip('\n')
    if text:
        if not text.startswith('Warning: '):
            raise ValueError('unexpected output: ' + text[:200])
        out.append(re.sub(r'(?m)^Warning: ', 'warning: ', text))
    if error is not None:
        out.append(error)
    return '\n'.join(out)


if __name__ == '__main__':
    try:
        print(probe_format(open(sys.argv[1], encoding='utf-8').read()))
    except ValueError as e:
        sys.exit(f'{sys.argv[1]}: {e}')
