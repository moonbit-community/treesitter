"""Development-only differential test of query against the C query engine.

For every fixture grammar without (or with ported) external scanners, compile
each queries/*.scm file of the grammar with both implementations and compare
metadata, matches and captures over the grammar's corpus inputs.

Usage: python3 tools/oracle/diff_query.py [--externals] [--extra queries.txt] [names...]
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import diff_runtime as dr  # noqa: E402


def query_files(name):
    if (m := dr.meta(name)) is not None:
        return sorted(Path(m['queries']).glob('*.scm')) if m['queries'] else []
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
    ap.add_argument('--exclude', action='append', default=[], help='skip this grammar (repeatable)')
    ap.add_argument('names', nargs='*')
    args = ap.parse_args()
    names = [n for n in (args.names or sorted(p.stem for p in dr.LANG.glob('*.json'))) if n not in args.exclude]
    total = same = 0
    failed = False
    for name in names:
        lang = json.loads((dr.LANG / f'{name}.json').read_text())
        if lang['external_token_count'] and not args.names and not args.externals:
            continue
        queries = query_files(name)
        if args.queries:
            queries += sorted(Path(args.queries).glob('*.scm'))
        if not queries:
            continue
        inputs = dr.corpus_inputs(name)
        if not inputs:
            if name not in dr.NO_INPUTS:
                print(f'{name}: 0/0 DIFF (no inputs)')
                failed = True
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
            # The first record is the query's metadata (or compile error).
            pairs = dr.run_pair([str(ref), str(q)], [str(dr.PROBE), 'query', str(dr.LANG / f'{name}.json'), str(q)],
                                [[p] for p in paths], paths, preamble=True)
            passed, hangs, failures = dr.judge(name, pairs)
            total += len(pairs)
            same += passed
            status = 'ok' if not failures else 'DIFF'
            if hangs:
                status += f' ({hangs} hang in both)'
            kinds = sorted({f'ref {es}' for _, es, _, _ in failures if es != 0}
                           | {f'probe {as_}' for _, _, _, as_ in failures if as_ != 0}, key=str)
            if kinds:
                status += ' (' + ', '.join(kinds) + ')'
            print(f'{name} {q.name}: {passed}/{len(pairs)} {status}', flush=True)
            for a, _, b, _ in failures[:args.show]:
                al, bl = a.split('\n'), b.split('\n')
                for k, (x, y) in enumerate(zip(al, bl)):
                    if x != y:
                        print('  first diff at line', k, 'of', al[0][:80])
                        print('  expected:', x[:300])
                        print('  actual:  ', y[:300])
                        break
                else:
                    print('  length differs', len(al), len(bl))
    print(f'TOTAL {same}/{total}')
    sys.exit(0 if same == total and not failed else 1)


if __name__ == '__main__':
    main()
