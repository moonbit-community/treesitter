"""Freeze selected upstream grammar/corpus tests as portable MoonBit tests.
Node is used only to evaluate the reference JavaScript DSL during migration.
Generated tests and the production compiler/runtime use no JavaScript evaluator.
"""
from pathlib import Path
import os
import subprocess
import json
import re

root = Path('.repos/tree-sitter').resolve()
expected = '4a412a01a0147d0f50bf7e749572fa632d1ab203'
assert subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'], text=True).strip() == expected
# Native allocator faults and a deliberately non-returning C callback cannot be
# executed by the pure MoonBit scanner protocol. Their grammar generation is
# audited separately; all remaining reference fixtures are frozen below.
excluded = {'wasm_realloc_clobber_region', 'wasm_realloc_overflow_heap', 'get_col_should_hang_not_crash'}
names = sorted(p.name for p in (root/'test/fixtures/test_grammars').iterdir() if (p/'grammar.js').exists() and p.name not in excluded)

parts=['// Ported from Tree-sitter '+expected+'. See LICENSE.\n']
for name in names:
    fixture=root/'test/fixtures/test_grammars'/name
    env=dict(os.environ, TREE_SITTER_GRAMMAR_PATH=str(fixture/'grammar.js'))
    raw=subprocess.check_output(['node','--no-warnings','--input-type=module'],input=(root/'crates/generate/src/dsl.js').read_text(), env=env, text=True)
    grammar=json.dumps(json.loads(raw),ensure_ascii=False,separators=(',',':'))
    corpus=(fixture/'corpus.txt').open(newline='').read() if (fixture/'corpus.txt').exists() else ''
    def multiline(s): return '\n'.join('    #|'+line for line in s.splitlines())
    if (fixture/'expected_error.txt').exists():
        error_pattern = 'InvalidGrammar(_)' if name in ('terminal_supertype', 'eof_misplaced', 'invisible_start_rule', 'epsilon_rules', 'eof_repeat_via_nullable_rule', 'conflicting_precedence') else 'Conflict(_, _, _)'
        parts.append(f'\n///|\ntest "upstream rejection {name}" {{\n  let grammar =\n{multiline(grammar)}\n  let grammar = @grammar.Grammar::parse(grammar)\n  try @generate.generate(grammar) catch {{\n    @generate.{error_pattern} => ()\n    error => fail("unexpected error: \\{{error}}")\n  }} noraise {{ _ => fail("accepted an upstream conflict fixture") }}\n}}\n')
    elif not re.search(r'^-{3,}\r?$', corpus, re.M):
        parts.append(f'\n///|\ntest "upstream generation {name}" {{\n  // Upstream supplies no corpus expectations for this grammar.\n  let grammar =\n{multiline(grammar)}\n  let language = @generate.generate(@grammar.Grammar::parse(grammar))\n  language.validate()\n}}\n')
    else:
        scanner_arg = ', scanner=scanner_' + name + '()' if (fixture/'scanner.c').exists() else ''
        parts.append(f'\n///|\ntest "upstream {name}" {{\n  let grammar =\n{multiline(grammar)}\n  let corpus = {json.dumps(corpus, ensure_ascii=False)}\n  let language = @generate.generate(@grammar.Grammar::parse(grammar))\n  for result in @corpus.run(language, @corpus.parse(corpus){scanner_arg}) {{\n    assert_true(result.passed, msg="'+name+': \\{result.name}\\nexpected: \\{result.expected}\\nactual: \\{result.actual}")\n  }\n}\n')
Path('compat/upstream_test.mbt').write_text(''.join(parts))
