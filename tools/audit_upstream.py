"""Audit every pinned upstream grammar fixture without changing its expectations.

The frozen cross-target tests are the shipping compatibility tests. This broader
native development audit inventories generators, corpus mismatches, scanners,
and fixtures requiring special test modes. Results are written under _build.
"""
from pathlib import Path
import json
import os
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = ROOT / '.repos/tree-sitter'
REVISION = '4a412a01a0147d0f50bf7e749572fa632d1ab203'
assert subprocess.check_output(['git', '-C', str(UPSTREAM), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
OUT = ROOT / '_build/audit'
OUT.mkdir(parents=True, exist_ok=True)
CLI = ROOT / '_build/native/debug/build/cmd/treesitter/treesitter.exe'
DSL = (UPSTREAM / 'crates/generate/src/dsl.js').read_text()
results = []
for grammar in sorted((UPSTREAM / 'test/fixtures/test_grammars').glob('*/grammar.js')):
    name = grammar.parent.name
    result = {'name': name}
    try:
        raw = subprocess.run(['node', '--no-warnings', '--input-type=module'], input=DSL,
            env=dict(os.environ, TREE_SITTER_GRAMMAR_PATH=str(grammar)), capture_output=True, text=True, timeout=15)
        if raw.returncode:
            result.update(status='reference-dsl-error', detail=raw.stderr)
        else:
            source = OUT / (name + '.grammar.json')
            language = OUT / (name + '.language.json')
            source.write_text(raw.stdout)
            data = json.loads(raw.stdout)
            data = data.get('grammar', data)
            corpus = grammar.parent / 'corpus.txt'
            generated = subprocess.run([str(CLI), 'generate', str(source), str(language)], capture_output=True, text=True, timeout=30)
            if (grammar.parent / 'expected_error.txt').exists():
                result.update(status='rejection-pass' if generated.returncode else 'unexpected-accept', detail=generated.stderr)
            elif generated.returncode:
                result.update(status='generation-fail', detail=generated.stderr)
            elif data.get('externals'):
                result.update(status='scanner-required')
            elif corpus.exists() and re.search(r'^-{3,}\r?$', corpus.read_text(), re.M):
                tested = subprocess.run([str(CLI), 'test', str(language), str(grammar.parent / 'corpus.txt')], capture_output=True, text=True, timeout=30)
                result.update(status='corpus-pass' if tested.returncode == 0 else 'corpus-fail', detail=tested.stdout + tested.stderr)
            else:
                result.update(status='generation-pass')
    except subprocess.TimeoutExpired:
        result.update(status='timeout')
    results.append(result)
    print(name, result['status'], flush=True)
    (OUT / 'results.json').write_text(json.dumps(results, indent=2))
print(json.dumps({s: sum(r['status'] == s for r in results) for s in sorted({r['status'] for r in results})}, indent=2))
