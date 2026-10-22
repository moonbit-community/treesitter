"""Freeze selected upstream grammar/corpus tests as portable MoonBit tests.
Node is used only to evaluate the reference JavaScript DSL during migration.
Generated tests and the production compiler/runtime use no JavaScript evaluator.
"""
from pathlib import Path
import os
import subprocess
import json

root = Path('.repos/tree-sitter').resolve()
expected = '4a412a01a0147d0f50bf7e749572fa632d1ab203'
assert subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'], text=True).strip() == expected
names = ['associativity_left','associativity_right','aliases_in_root','aliased_rules',
         'aliased_token_rules','dynamic_precedence','field_on_hidden_rule','immediate_tokens',
         'inline_rules','start_rule_is_blank','start_rule_is_token','precedence_on_token',
         'anonymous_tokens_with_escaped_chars','aliased_unit_reductions']
parts=['// Ported from Tree-sitter '+expected+'. See LICENSE.\n']
for name in names:
    fixture=root/'test/fixtures/test_grammars'/name
    env=dict(os.environ, TREE_SITTER_GRAMMAR_PATH=str(fixture/'grammar.js'))
    raw=subprocess.check_output(['node','--no-warnings','--input-type=module'],input=(root/'crates/generate/src/dsl.js').read_text(), env=env, text=True)
    grammar=json.dumps(json.loads(raw),ensure_ascii=False,separators=(',',':'))
    corpus=(fixture/'corpus.txt').open(newline='').read()
    def multiline(s): return '\n'.join('    #|'+line for line in s.splitlines())
    parts.append(f'\n///|\ntest "upstream {name}" {{\n  let grammar =\n{multiline(grammar)}\n  let corpus = {json.dumps(corpus, ensure_ascii=False)}\n  let language = @generate.generate(@grammar.Grammar::parse(grammar))\n  for result in @corpus.run(language, @corpus.parse(corpus)) {{\n    assert_true(result.passed, msg="'+name+': \\{result.name}\\nexpected: \\{result.expected}\\nactual: \\{result.actual}")\n  }\n}\n')
Path('compat/upstream_test.mbt').write_text(''.join(parts))
