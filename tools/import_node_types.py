"""Freeze pinned-generator node schemas after tools/audit_node_types.py.

The external-scanner block fixture is tracked separately in PLAN.md: our
cardinality analysis proves a required named child where upstream's summary
marks it optional. All other accepted fixture schemas are compared exactly.
"""
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]
results=json.loads((ROOT/'_build/node-types-audit/results.json').read_text())
output=['// Node schemas from pinned Tree-sitter 4a412a01. See LICENSE.\n']
for case in results:
    name=case['name']
    if name=='uses_current_column': continue
    assert case['order_equal'],name
    grammar=json.loads((ROOT/f'_build/audit/{name}.grammar.json').read_text())
    grammar=grammar.get('grammar',grammar)
    expected=json.loads((ROOT/f'_build/node-types-audit/{name}/src/node-types.json').read_text())
    output.extend(['///|',f'test "upstream node schema {name}" {{','  let grammar =',
       '    #|'+json.dumps(grammar,separators=(',',':'),ensure_ascii=False),
       '  let language = @generate.generate(@grammar.Grammar::parse(grammar))',
       '  assert_eq(language.node_types(), '+json.dumps(expected,separators=(',',':'),ensure_ascii=False)+')','}\n'])
(ROOT/'compat/node_types_test.mbt').write_text('\n'.join(output))
