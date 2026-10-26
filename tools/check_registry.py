"""Verify a published version from the registry, without the local checkout.

Usage: python3 tools/check_registry.py VERSION [GRAMMAR_MODULE@VERSION ...]

Creates a consumer module outside this repository that depends on
moonbit-community/treesitter@VERSION (and the given grammar modules, e.g.
moonbit-community/tree-sitter-json@0.24.8), and runs a test that generates a
grammar, parses, queries and, for each grammar module, parses with every
language constructor it exports (`pub fn ...() -> @treesitter.Language` in the
installed module's pkg.generated.mbti).
"""
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

TEST_CORE = '''///|
test "core" {
  let grammar = @grammar.Grammar::new("words", [
    ("document", Repeat(Symbol("word"))),
    ("word", @grammar.pattern("[a-z]+")),
  ])
  let generated = @generate.generate_from_grammar_json(
    grammar.to_json().stringify(),
  )
  let language = @treesitter.Language::new(generated.language)
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let source = @utf8.encode("hello moonbit")
  guard parser.parse(source) is Some(tree) else { fail("parse failed") }
  inspect(tree.root_node().to_sexp(), content="(document (word) (word))")
}
'''

TEST_GRAMMAR = '''///|
test "{alias}.{function}" {
  let parser = @treesitter.Parser::new()
  parser.set_language(@{alias}.{function}())
  guard parser.parse(@utf8.encode("")) is Some(tree) else { fail("parse failed") }
  ignore(tree.root_node().to_sexp())
}
'''


def main():
    if len(sys.argv) < 2 or not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', sys.argv[1]):
        sys.exit(__doc__)
    version = sys.argv[1]
    grammars = sys.argv[2:]
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix='treesitter-registry-') as tmp:
        project = Path(tmp).resolve() / 'consumer'
        if project.is_relative_to(root):
            sys.exit('the temporary directory must be outside the checkout')
        project.mkdir()
        deps = [f'"moonbit-community/treesitter@{version}"'] + [f'"{g}"' for g in grammars]
        (project / 'moon.mod').write_text(
            'name = "check/consumer"\nversion = "0.0.1"\nimport {\n  '
            + ',\n  '.join(deps) + ',\n}\n')
        imports = ['"moonbit-community/treesitter"', '"moonbit-community/treesitter/grammar"',
                   '"moonbit-community/treesitter/generate"', '"moonbitlang/core/encoding/utf8"']
        aliases = []
        for g in grammars:
            name = g.split('@')[0]
            alias = name.split('/')[-1].replace('-', '_')
            imports.append(f'"{name}" @{alias}')
            aliases.append((name, alias))
        (project / 'moon.pkg').write_text(
            'import {\n  ' + ',\n  '.join(imports) + ',\n} for "test"\n')
        (project / 'consumer_test.mbt').write_text(TEST_CORE)
        env = dict(os.environ)
        run = lambda *command: (print('$', ' '.join(command), flush=True),
                                subprocess.run(command, cwd=project, env=env, check=True))
        run('moon', 'update')
        # Download the dependencies, then test every language constructor
        # the installed grammar modules export.
        run('moon', 'check', '--target', 'native')
        tests = TEST_CORE
        for name, alias in aliases:
            mbti = project / '.mooncakes' / name / 'pkg.generated.mbti'
            functions = re.findall(r'^pub fn (\w+)\(\) -> @treesitter\.Language$', mbti.read_text(), re.M)
            if not functions:
                sys.exit(f'{name} exports no language constructor ({mbti})')
            for function in functions:
                print(f'checking {name} {function}()')
                tests += TEST_GRAMMAR.replace('{alias}', alias).replace('{function}', function)
        (project / 'consumer_test.mbt').write_text(tests)
        run('moon', 'test', '--target', 'native')
    print('registry check passed')


if __name__ == '__main__':
    main()
