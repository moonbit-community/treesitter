"""Development-only: compare the outputs of tools/next/regex_harness and
regex/probe on the same corpus and report agreement.

Usage: python3 tools/next/regex_compare.py corpus.jsonl rust.out mbt.out
"""
import json
import sys

corpus = [json.loads(l) for l in open(sys.argv[1])]
rust = open(sys.argv[2]).read().split('\n')
mbt = open(sys.argv[3]).read().split('\n')
patterns = agree_patterns = cases = agree_cases = 0
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
    for i, (a, b) in enumerate(zip(r, m)):
        cases += 1
        if a == b:
            agree_cases += 1
        else:
            print(f'mismatch {case["p"]!r} on {bytes.fromhex(case["t"][i])!r}: rust={a} mbt={b}')
print(f'patterns: {agree_patterns}/{patterns} agree; '
      f'cases (compile results + is_match calls): {agree_cases}/{cases} agree')
