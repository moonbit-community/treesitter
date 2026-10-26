"""Development-only: compare the outputs of tools/oracle/regex_harness and
regex/probe on the same corpus and report agreement.

Usage: python3 tools/oracle/regex_compare.py corpus.jsonl rust.out mbt.out

Works for every mode of the harness: `is_match` lines have one character per
haystack, the `find` modes one space-separated field per haystack.
"""
import json
import sys

corpus = [json.loads(l) for l in open(sys.argv[1])]
rust = open(sys.argv[2]).read().split('\n')
mbt = open(sys.argv[3]).read().split('\n')
patterns = agree_patterns = cases = agree_cases = 0


def fields(line):
    return list(line) if set(line) <= set('01') else line.split(' ')


for case, r, m in zip(corpus, rust, mbt):
    patterns += 1
    if r == m:
        agree_patterns += 1
    if r == 'ERR' or m == 'ERR':
        cases += 1
        if r == m:
            agree_cases += 1
        else:
            print(f'compile mismatch {case["p"]!r}: rust={r[:3]} mbt={m[:3]}')
        continue
    for i, (a, b) in enumerate(zip(fields(r), fields(m))):
        cases += 1
        if a == b:
            agree_cases += 1
        else:
            print(f'mismatch {case["p"]!r} on {bytes.fromhex(case["t"][i])!r}: rust={a} mbt={b}')
print(f'patterns: {agree_patterns}/{patterns} agree; '
      f'cases (compile results + per-haystack results): {agree_cases}/{cases} agree')
