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
names = ['associativity_left','associativity_right','aliases_in_root','aliased_rules',
         'aliased_token_rules','dynamic_precedence','field_on_hidden_rule','immediate_tokens',
         'inline_rules','start_rule_is_blank','start_rule_is_token','precedence_on_token',
         'anonymous_tokens_with_escaped_chars','aliased_unit_reductions', 'named_precedences',
         'associativity_left_with_lower_precedence_shift',
         'associativity_right_with_lower_precedence_shift',
         'aliased_inlined_rules', 'inlined_aliased_rules', 'nested_inlined_rules',
         'precedence_on_single_child_missing', 'precedence_on_single_child_negative',
         'precedence_on_single_child_positive', 'precedence_on_subsequence',
         'unused_rules', 'lexical_conflicts_due_to_state_merging', 'terminal_supertype', 'external_extra_tokens', 'epsilon_external_extra_tokens', 'external_unicode_column_alignment', 'epsilon_external_tokens', 'external_and_internal_anonymous_tokens', 'extra_non_terminals', 'extra_non_terminals_with_shared_rules', 'field_lookup_through_hidden_nodes', 'anonymous_error', 'duplicate_reduction_precedence', 'eof_basic', 'eof_dropped_branch', 'eof_duplicate_reduction', 'eof_misplaced', 'invisible_start_rule', 'last_child_anchor_past_hidden_repeat', 'named_rule_aliased_as_anonymous', 'next_sibling_from_zwt', 'readme_grammar', 'unicode_classes', 'depends_on_column', 'depends_on_column_failed_scan', 'depends_on_column_repetition', 'external_word_token', 'external_and_internal_tokens', 'inverted_external_token', 'external_lookahead_eof_boundary', 'external_tokens', 'get_col_eof', 'utf16_surrogate_oob', 'basic_cst']
parts=['// Ported from Tree-sitter '+expected+'. See LICENSE.\n']
for name in names:
    fixture=root/'test/fixtures/test_grammars'/name
    env=dict(os.environ, TREE_SITTER_GRAMMAR_PATH=str(fixture/'grammar.js'))
    raw=subprocess.check_output(['node','--no-warnings','--input-type=module'],input=(root/'crates/generate/src/dsl.js').read_text(), env=env, text=True)
    grammar=json.dumps(json.loads(raw),ensure_ascii=False,separators=(',',':'))
    corpus=(fixture/'corpus.txt').open(newline='').read() if (fixture/'corpus.txt').exists() else ''
    def multiline(s): return '\n'.join('    #|'+line for line in s.splitlines())
    if (fixture/'expected_error.txt').exists():
        error_pattern = 'InvalidGrammar(_)' if name in ('terminal_supertype', 'eof_misplaced', 'invisible_start_rule') else 'Conflict(_, _, _)'
        parts.append(f'\n///|\ntest "upstream rejection {name}" {{\n  let grammar =\n{multiline(grammar)}\n  let grammar = @grammar.Grammar::parse(grammar)\n  try @generate.generate(grammar) catch {{\n    @generate.{error_pattern} => ()\n    error => fail("unexpected error: \\{{error}}")\n  }} noraise {{ _ => fail("accepted an upstream conflict fixture") }}\n}}\n')
    elif not re.search(r'^-{3,}\r?$', corpus, re.M):
        parts.append(f'\n///|\ntest "upstream generation {name}" {{\n  // Upstream supplies no corpus expectations for this grammar.\n  let grammar =\n{multiline(grammar)}\n  let language = @generate.generate(@grammar.Grammar::parse(grammar))\n  language.validate()\n}}\n')
    else:
        scanner_arg = ', scanner=scanner_' + name + '()' if (fixture/'scanner.c').exists() else ''
        parts.append(f'\n///|\ntest "upstream {name}" {{\n  let grammar =\n{multiline(grammar)}\n  let corpus = {json.dumps(corpus, ensure_ascii=False)}\n  let language = @generate.generate(@grammar.Grammar::parse(grammar))\n  for result in @corpus.run(language, @corpus.parse(corpus){scanner_arg}) {{\n    assert_true(result.passed, msg="'+name+': \\{result.name}\\nexpected: \\{result.expected}\\nactual: \\{result.actual}")\n  }\n}\n')
Path('compat/upstream_test.mbt').write_text(''.join(parts))
