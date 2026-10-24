"""Development-only differential test of next/query against the C query engine.

For every fixture grammar without (or with ported) external scanners, compile
each queries/*.scm file of the grammar with both implementations and compare
metadata, matches and captures over the grammar's corpus inputs.

Usage: python3 tools/next/diff_query.py [--externals] [--extra queries.txt] [names...]
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import diff_runtime as dr  # noqa: E402


def query_files(name):
    if not name.startswith('fixture_'):
        return []
    parts = name[len('fixture_'):].split('_', 1)
    base = dr.UPSTREAM / 'test/fixtures/grammars' / parts[0]
    dirs = [base / 'queries']
    if len(parts) > 1:
        dirs.insert(0, base / parts[1] / 'queries')
    for d in dirs:
        if d.is_dir():
            return sorted(d.glob('*.scm'))
    return []


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--externals', action='store_true')
    ap.add_argument('--show', type=int, default=3)
    ap.add_argument('--queries', help='directory of extra .scm files to run against every grammar')
    ap.add_argument('names', nargs='*')
    args = ap.parse_args()
    names = args.names or sorted(p.stem for p in dr.LANG.glob('*.json'))
    total = same = 0
    for name in names:
        lang = json.loads((dr.LANG / f'{name}.json').read_text())
        if lang['external_token_count'] and not args.names and not args.externals:
            continue
        queries = query_files(name)
        if args.queries:
            queries += sorted(Path(args.queries).glob('*.scm'))
        inputs = dr.corpus_inputs(name)
        if not queries or not inputs:
            continue
        work = dr.TMP / name
        work.mkdir(parents=True, exist_ok=True)
        paths = []
        for i, data in enumerate(inputs):
            p = work / f'{i}.txt'
            p.write_bytes(data)
            paths.append(str(p))
        ref = dr.build_ref(name, 'reference_query.c', '.query')
        for q in queries:
            (expected, _), (actual, code) = dr.run(
                [[str(ref), str(q), *paths], [str(dr.PROBE), 'query', str(dr.LANG / f'{name}.json'), str(q), *paths]],
                dr.BATCH_TIMEOUT + len(paths))
            expected, actual = expected or '', actual or ''
            exp = expected.split('\n== ')
            act = actual.split('\n== ')
            n_same = sum(1 for a, b in zip(exp, act) if a == b)
            total += len(exp)
            same += n_same
            ok = n_same == len(exp) and len(act) == len(exp)
            print(f'{name} {q.name}: {n_same}/{len(exp)} {"ok" if ok else "DIFF"}' + ('' if code == 0 else f' (probe exit {code})'), flush=True)
            shown = 0
            for a, b in zip(exp, act):
                if a != b and shown < args.show:
                    shown += 1
                    al, bl = a.split('\n'), b.split('\n')
                    for k, (x, y) in enumerate(zip(al, bl)):
                        if x != y:
                            print('  first diff at line', k, 'of', al[0][:80])
                            print('  expected:', x[:300])
                            print('  actual:  ', y[:300])
                            break
                    else:
                        print('  length differs', len(al), len(bl))
            if len(act) < len(exp):
                print('  probe output truncated:', actual[-400:])
    print(f'TOTAL {same}/{total}')
    sys.exit(0 if same == total else 1)


if __name__ == '__main__':
    main()
