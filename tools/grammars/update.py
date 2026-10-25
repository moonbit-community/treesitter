"""Regenerate the grammar modules under grammars/ from grammars/grammars.json.

For each grammar repository (pinned checkouts: the upstream fixture grammars in
.repos/ts-pinned, the others fetched by `tools/oracle/grammars.py fetch`),
grammars/<name> becomes the MoonBit module moonbit-community/tree-sitter-<name>:

- the language tables, generated from the pinned src/grammar.json by this
  port's generator (tools/grammar_modules) and embedded in the compact format
  of `@language.Language::from_compact_base64`;
- a package API mirroring the repository's Rust binding
  (bindings/rust/lib.rs): `LANGUAGE` -> `language()`, `HIGHLIGHTS_QUERY` ->
  `highlights_query`, and so on;
- src/grammar.json, the generated src/node-types.json, queries/*.scm, the
  test corpus and the license, copied from the pinned checkout (keeping the
  repository's layout, so multi-language repositories keep their language
  directories);
- README.mbt.md with a usage example (a test), a smoke test, and a native
  test running the corpus.

Run through tools/grammars/update.sh, which builds tools/grammar_modules
first and runs `moon info` afterwards. Output is a deterministic function of
the pinned checkouts and this script.

Usage: python3 tools/grammars/update.py [--jobs N] [name...]
"""
import concurrent.futures
import json
import os
import re
import shutil
import subprocess
import tempfile
import textwrap
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/oracle'))
import grammars as G  # noqa: E402

TOOL = ROOT / '_build/native/release/build/moonbit-community/treesitter/tools/grammar_modules/grammar_modules.exe'
CORE = 'moonbit-community/treesitter'
CORE_VERSION = '0.1.0'
ASYNC_VERSION = '0.20.2'
REPOSITORY = 'https://github.com/moonbit-community/treesitter'

# Grammars without a usable corpus entry: a small sample for the smoke test.
SAMPLES = {
    'zig': 'const std = @import("std");\n\npub fn main() void {\n    std.debug.print("Hello, {s}!\\n", .{"world"});\n}\n',
}

# Corpus entries whose expected tree the grammar's own parser does not
# produce (the trees are identical to the pinned C runtime's, which the
# differential oracle checks): (language, entry name) -> reason.
MARKDOWN_EXTENSIONS = ('the pinned src/grammar.json is generated without the EXTENSION_WIKI_LINK and '
                       'EXTENSION_TAGS options of grammar.js that this example needs')
CORPUS_SKIPS = {
    ('c-sharp', 'corpus - statements - Switch statements'):
        'the pinned C runtime, with the tables tree-sitter generate 0.28 builds, gives the same ERROR',
    **{('markdown_inline', f'corpus - {name}'): MARKDOWN_EXTENSIONS for name in [
        'extension_wikilink - Basic Wiki-link parsing.',
        'extension_wikilink - Wiki-link to a file',
        'extension_wikilink - Wiki-link to a heading in a note',
        'extension_wikilink - Wiki-link with title',
        'extension_wikilink - Wiki-link version of Example 556',
        'spec - Example 324 - https://github.github.com/gfm/#example-324',
        'spec - Example 638 - https://github.github.com/gfm/#example-638',
        'tags - Tags are working',
    ]},
}

HEADER = re.compile(r'^(={3,})([^=\r\n][^\r\n]*)?$')
DIVIDER = re.compile(r'^(-{3,})([^-\r\n][^\r\n]*)?$')


def doc(text):
    """A `///` doc comment of `text`, wrapped at 80 columns."""
    return ''.join(f'/// {line}\n' for line in textwrap.wrap(text, 76, break_long_words=False,
                                                            break_on_hyphens=False))


def mbt_ident(const_name):
    return const_name.lower()


def mbt_package_alias(name):
    return 'tree_sitter_' + name.replace('-', '_')


# ---------------------------------------------------------------------------
# Rust binding


def rust_binding(repo):
    """The Rust binding's languages and strings.

    Returns ([(rust const or fn, C symbol)], [(rust const, repo-relative path)]).
    """
    lib = (repo / 'bindings/rust/lib.rs').read_text()
    # Drop comments so that doc examples do not count.
    code = '\n'.join(line for line in lib.split('\n') if not line.lstrip().startswith('//'))
    languages = re.findall(
        r'pub const ([A-Z_]+): LanguageFn\s*=\s*unsafe\s*\{\s*LanguageFn::from_raw\((tree_sitter_\w+)\)', code)
    if not languages:
        # Pre-LanguageFn bindings (tree-sitter-regex 1.0): `pub fn language()`.
        m = re.search(r'pub fn language\(\) -> Language \{\s*unsafe \{ (tree_sitter_\w+)\(\) \}', code)
        if m:
            languages = [('LANGUAGE', m.group(1))]
    strings = []
    for name, path in re.findall(r"pub const ([A-Z_]+): &(?:'static )?str\s*=\s*include_str!\(\"([^\"]+)\"\)", code):
        rel = os.path.normpath(os.path.join('bindings/rust', path))
        # Optional queries are behind `#[cfg(with_*_query)]`, set by build.rs
        # when the file exists.
        if (repo / rel).is_file():
            strings.append((name, rel))
    return languages, strings


# ---------------------------------------------------------------------------
# Corpus


def corpus_entries(path):
    """(name, attributes, input) of each example of a corpus file."""
    lines = path.read_text().split('\n')
    i = 0
    result = []
    while i < len(lines):
        m = HEADER.match(lines[i])
        if not m:
            i += 1
            continue
        suffix = m.group(2) or ''
        j = i + 1
        name_lines = []
        while j < len(lines) and not HEADER.match(lines[j]):
            name_lines.append(lines[j])
            j += 1
        if j >= len(lines) or not name_lines:
            i = j
            continue
        name = name_lines[0].strip()
        attributes = [line.strip() for line in name_lines[1:] if line.strip()]
        k = j + 1
        input_lines = []
        while k < len(lines):
            d = DIVIDER.match(lines[k])
            if d and (d.group(2) or '') == suffix:
                break
            input_lines.append(lines[k])
            k += 1
        e = k + 1
        output_lines = []
        while e < len(lines) and not HEADER.match(lines[e]):
            output_lines.append(lines[e])
            e += 1
        result.append((name, attributes, '\n'.join(input_lines), '\n'.join(output_lines)))
        i = e
    return result


def entry_languages(attributes):
    langs = []
    for a in attributes:
        m = re.match(r':language\((.*)\)', a)
        if m:
            langs.append(m.group(1).strip())
    return langs


def count_examples(corpus_dirs, language, default_of):
    """The number of corpus examples applying to `language` (as the corpus
    test selects them)."""
    count = 0
    for d in corpus_dirs:
        for f in sorted(p for p in d.rglob('*') if p.is_file()):
            for name, attributes, text, output in corpus_entries(f):
                langs = entry_languages(attributes)
                if (language in langs if langs else default_of(d) == language) and ':skip' not in attributes:
                    count += 1
    return count


def pick_sample(corpus_dirs, language, default_of):
    for d in corpus_dirs:
        for f in sorted(p for p in d.rglob('*') if p.is_file()):
            for name, attributes, text, output in corpus_entries(f):
                langs = entry_languages(attributes)
                applies = language in langs if langs else default_of(d) == language
                if not applies or any(a in (':error', ':skip', ':fail-fast', ':cst') or a.startswith(':platform')
                                      for a in attributes):
                    continue
                if 'ERROR' in output or 'MISSING' in output or not text.strip() or '\r' in text:
                    continue
                if len(text.split('\n')) > 12 or len(text) > 600:
                    continue
                return text.strip('\n') + '\n'
    return None


# ---------------------------------------------------------------------------
# MoonBit source rendering


def raw_string(text, indent):
    """A MoonBit multi-line raw string (`#|` lines) with value `text`."""
    if '\r' in text:
        raise ValueError('carriage return in embedded text')
    if text == '':
        return '""'
    pad = ' ' * indent
    return '\n'.join(pad + '#|' + line for line in text.split('\n'))


def string_file(ident, text, source, const):
    return (f'// Generated by tools/grammars/update.sh from {source}. Do not edit.\n'
            f'\n'
            f'///|\n'
            f'/// The content of `{source}` (`{const}` in the Rust binding).\n'
            f'pub let {ident} : String =\n'
            f'{raw_string(text, 2)}\n')


def binding_file(entry, languages, version):
    out = [f'// Generated by tools/grammars/update.sh. Do not edit.\n'
           f'//\n'
           f'// The equivalent of bindings/rust/lib.rs of {entry["repo"]} {entry["tag"]}:\n'
           f'// the languages of the grammar (`LanguageFn` constants there) as functions\n'
           f'// returning a `@treesitter.Language`, decoded on first use; the string\n'
           f'// constants (queries, node types) are in the other files of the package.\n']
    for lang in languages:
        fn = lang['fn']
        text = (f'The tree-sitter language for {lang["display"]} (`{lang["const"]}` in the Rust '
                f'binding), generated from `{lang["grammar_json"]}`.')
        if lang['externals']:
            text += (f' Its external scanner is `@scanners.scanner_for("{lang["grammar_name"]}")`; '
                     'without one (a scanner not ported yet) the language is not parseable '
                     '(`@treesitter.Language::is_parseable`).')
        out.append(f'\n///|\n'
                   f'let {fn}_cache : Ref[@treesitter.Language?] = Ref(None)\n'
                   f'\n///|\n'
                   f'{doc(text)}'
                   f'pub fn {fn}() -> @treesitter.Language {{\n'
                   f'  load({fn}_cache, {fn}_tables)\n'
                   f'}}\n')
    any_externals = any(lang['externals'] for lang in languages)
    if any_externals:
        make = ('  let language = if raw.external_token_count > 0 {\n'
                '    @treesitter.Language::new(\n'
                '      raw,\n'
                '      external_scanner?=@scanners.scanner_for(raw.name),\n'
                '    )\n'
                '  } else {\n'
                '    @treesitter.Language::new(raw)\n'
                '  }\n')
    else:
        make = '  let language = @treesitter.Language::new(raw)\n'
    out.append('\n///|\n'
               'fn load(\n'
               '  cache : Ref[@treesitter.Language?],\n'
               '  tables : String,\n'
               ') -> @treesitter.Language {\n'
               '  if cache.val is Some(language) {\n'
               '    return language\n'
               '  }\n'
               '  let raw = @language.Language::from_compact_base64(tables) catch {\n'
               '    e => abort(e.to_string())\n'
               '  }\n'
               f'{make}'
               '  cache.val = Some(language)\n'
               '  language\n'
               '}\n')
    return ''.join(out)


def moon_mod(entry, version, description, keywords):
    kw = ', '.join(json.dumps(k) for k in keywords)
    return (f'name = "moonbit-community/tree-sitter-{entry["name"]}"\n'
            f'\n'
            f'version = "{version}"\n'
            f'\n'
            f'readme = "README.mbt.md"\n'
            f'\n'
            f'repository = "{REPOSITORY}"\n'
            f'\n'
            f'license = "MIT"\n'
            f'\n'
            f'keywords = [{kw}]\n'
            f'\n'
            f'description = {json.dumps(description)}\n'
            f'\n'
            f'import {{\n'
            f'  "{CORE}@{CORE_VERSION}",\n'
            f'  "moonbitlang/async@{ASYNC_VERSION}",\n'
            f'}}\n')


def moon_pkg(entry, any_externals):
    imports = [f'"{CORE}"', f'"{CORE}/language"']
    if any_externals:
        imports.append(f'"{CORE}/scanners"')
    alias = mbt_package_alias(entry['name'])
    return ('import {\n' + ''.join(f'  {i},\n' for i in imports) + '}\n'
            '\n'
            'import {\n'
            f'  "moonbit-community/tree-sitter-{entry["name"]}" @{alias},\n'
            '  "moonbitlang/core/encoding/utf8",\n'
            '} for "test"\n')


def tests_moon_pkg(entry):
    alias = mbt_package_alias(entry['name'])
    return ('import {\n'
            f'  "moonbit-community/tree-sitter-{entry["name"]}" @{alias},\n'
            f'  "{CORE}",\n'
            f'  "{CORE}/cli_test",\n'
            '  "moonbitlang/async",\n'
            '  "moonbitlang/async/fs",\n'
            '} for "test"\n'
            '\n'
            'supported_targets = "+native"\n')


def corpus_test_file(entry, languages):
    alias = mbt_package_alias(entry['name'])
    tests = []
    for lang in languages:
        if not lang['corpus'] or lang['corpus_count'] == 0:
            continue
        dirs = ', '.join(f'("{d}", "{default}")' for d, default in lang['corpus'])
        skips = sorted(name for (l, name) in CORPUS_SKIPS if l == lang['name'])
        skip_list = '[' + ', '.join(json.dumps(s) for s in skips) + ']'
        reasons = sorted({reason for (l, _), reason in CORPUS_SKIPS.items() if l == lang['name']})
        comment = ''.join(
            ''.join(f'  // {line}\n' for line in textwrap.wrap(
                f'Skipped examples, whose expected trees upstream does not produce either: {r}.', 76))
            for r in reasons)
        tests.append(f'\n///|\n'
                     f'async test "corpus of {lang["name"]}" {{\n'
                     f'{comment}'
                     f'  check_corpus(@{alias}.{lang["fn"]}(), "{lang["name"]}", [{dirs}], {skip_list})\n'
                     f'}}\n')
    if not tests:
        return None
    module_dir = f'grammars/{entry["name"]}'
    return ('// Generated by tools/grammars/update.sh. Do not edit.\n'
            '//\n'
            '// Parse every example of the grammar\'s corpus (copied from the pinned\n'
            '// grammar repository) and compare the trees with the expected ones, like\n'
            '// `tree-sitter test`. An example applies to the languages named by its\n'
            '// `:language(...)` attributes, or else to the default language of its\n'
            '// corpus directory.\n'
            '\n'
            '///|\n'
            '/// `path` (relative to the module root) from the module root, this\n'
            '/// package\'s directory or the workspace root.\n'
            'async fn find_dir(path : String) -> String? {\n'
            f'  for prefix in ["", "../", "{module_dir}/"] {{\n'
            '    if @fs.exists(prefix + path) {\n'
            '      return Some(prefix + path)\n'
            '    }\n'
            '  }\n'
            '  None\n'
            '}\n'
            '\n'
            '///|\n'
            'async fn check_corpus(\n'
            '  language : @treesitter.Language,\n'
            '  name : String,\n'
            '  corpus_dirs : Array[(String, String)],\n'
            '  skipped : Array[String],\n'
            ') -> Unit {\n'
            '  guard language.is_parseable() else {\n'
            '    println(\n'
            '      "note: skipping the \\{name} corpus: the external scanner of \\{name} is not ported yet",\n'
            '    )\n'
            '    return\n'
            '  }\n'
            '  let mut count = 0\n'
            '  let mut failures = 0\n'
            '  for corpus in corpus_dirs {\n'
            '    let (path, default_language) = corpus\n'
            '    guard find_dir(path) is Some(dir) else {\n'
            '      fail("corpus directory \\{path} not found")\n'
            '    }\n'
            '    let tests = @cli_test.flatten_tests(\n'
            '      @cli_test.parse_tests(dir),\n'
            '      None,\n'
            '      None,\n'
            '    )\n'
            '    for test_case in tests {\n'
            '      let applies = if test_case.languages[0].is_empty() {\n'
            '        default_language == name\n'
            '      } else {\n'
            '        test_case.languages.contains(name)\n'
            '      }\n'
            '      if !applies ||\n'
            '        test_case.expectation is Skip ||\n'
            '        skipped.contains(test_case.name) {\n'
            '        continue\n'
            '      }\n'
            '      count += 1\n'
            '      let check_output = !(test_case.expectation is Error)\n'
            '      if !test_case.check_initial_parse(\n'
            '          language,\n'
            '          "\\{name} - \\{test_case.name}",\n'
            '          check_output,\n'
            '        ) {\n'
            '        failures += 1\n'
            '      }\n'
            '    }\n'
            '  }\n'
            '  if count == 0 {\n'
            '    fail("no \\{name} corpus examples found")\n'
            '  }\n'
            '  if failures > 0 {\n'
            '    fail("\\{failures} of \\{count} \\{name} corpus examples failed")\n'
            '  }\n'
            '}\n' + ''.join(tests))


def readme(entry, version, description, languages, strings, upstream_url):
    alias = mbt_package_alias(entry['name'])
    first = languages[0]
    rows = []
    for lang in languages:
        rows.append(f'| `{lang["fn"]}() -> @treesitter.Language` | `{lang["const"]}` |')
    for const, ident, source in strings:
        rows.append(f'| `{ident} : String` | `{const}` (`{source}`) |')
    table = '\n'.join(rows)
    pending = [lang for lang in languages if lang['externals'] and not lang['scanner']]
    note = ''
    if pending:
        names = ', '.join(f'`{lang["grammar_name"]}`' for lang in pending)
        note = (f'\nThe external scanner of {names} is not ported to MoonBit yet: until\n'
                f'`@scanners.scanner_for` provides it, the language cannot be used for\n'
                f'parsing (`is_parseable()` is false) and the tests below skip.\n')
    scanner_text = ''
    if any(lang['externals'] for lang in languages):
        scanner_text = (' External scanners come from `@scanners.scanner_for` in\n'
                        f'`{CORE}/scanners`, the MoonBit ports of the C scanners.')
    guard = ''
    if first['externals'] and not first['scanner']:
        guard = ('  // The external scanner is not ported yet.\n'
                 '  guard language.is_parseable() else { return }\n')
    sample = raw_string(first['sample'], 4)
    return ('<!-- Generated by tools/grammars/update.sh. Do not edit. -->\n'
            '\n'
            f'# tree-sitter-{entry["name"]} for MoonBit\n'
            f'\n'
            f'{description}.\n'
            f'\n'
            f'This module packages [{entry["repo"]}]({upstream_url}) {entry["tag"]} for\n'
            f'[moonbit-community/treesitter]({REPOSITORY}), the pure MoonBit\n'
            f'port of Tree-sitter. The parse tables are generated from the grammar\'s\n'
            f'`src/grammar.json` by the port\'s generator, which produces the same tables\n'
            f'as `tree-sitter generate` 0.28.0.{scanner_text}\n'
            f'{note}'
            f'\n'
            f'## API\n'
            f'\n'
            f'The package mirrors the grammar\'s Rust binding (`bindings/rust/lib.rs`):\n'
            f'\n'
            f'| MoonBit | Rust |\n'
            f'| --- | --- |\n'
            f'{table}\n'
            f'\n'
            f'## Usage\n'
            f'\n'
            f'```sh\n'
            f'moon add moonbit-community/tree-sitter-{entry["name"]}\n'
            f'```\n'
            f'\n'
            f'In `moon.pkg`:\n'
            f'\n'
            f'```text\n'
            f'import {{\n'
            f'  "{CORE}",\n'
            f'  "moonbit-community/tree-sitter-{entry["name"]}" @{alias},\n'
            f'}}\n'
            f'```\n'
            f'\n'
            f'```mbt check\n'
            f'///|\n'
            f'test "parse {first["name"]}" {{\n'
            f'  let language = @{alias}.{first["fn"]}()\n'
            f'{guard}'
            f'  let parser = @treesitter.Parser::new()\n'
            f'  parser.set_language(language)\n'
            f'  let source =\n'
            f'{sample}\n'
            f'  guard parser.parse(@utf8.encode(source)) is Some(tree) else {{\n'
            f'    fail("parse failed")\n'
            f'  }}\n'
            f'  let root = tree.root_node()\n'
            f'  assert_false(root.has_error())\n'
            f'  assert_false(root.to_sexp().contains("ERROR"))\n'
            f'}}\n'
            f'```\n'
            f'\n'
            f'## License\n'
            f'\n'
            f'The grammar and the files copied from it (`src/grammar.json`, queries,\n'
            f'test corpus) are under the license of {entry["repo"]}, in\n'
            f'[{entry["license_file"]}]({entry["license_file"]}).\n')


def smoke_test_file(entry, languages, strings):
    alias = mbt_package_alias(entry['name'])
    out = ['// Generated by tools/grammars/update.sh. Do not edit.\n']
    for lang in languages:
        guard = ''
        if lang['externals']:
            guard = ('  guard language.is_parseable() else {\n'
                     '    println(\n'
                     f'      "note: skipping {lang["name"]}: its external scanner is not ported yet",\n'
                     '    )\n'
                     '    return\n'
                     '  }\n')
        out.append(f'\n///|\n'
                   f'test "{lang["fn"]} parses a sample" {{\n'
                   f'  let language = @{alias}.{lang["fn"]}()\n'
                   f'  // Decoded once.\n'
                   f'  assert_true(language == @{alias}.{lang["fn"]}())\n'
                   f'  assert_eq(language.name(), Some("{lang["grammar_name"]}"))\n'
                   f'  assert_eq(language.abi_version(), 15)\n'
                   f'{guard}'
                   f'  let parser = @treesitter.Parser::new()\n'
                   f'  parser.set_language(language)\n'
                   f'  let source =\n'
                   f'{raw_string(lang["sample"], 4)}\n'
                   f'  guard parser.parse(@utf8.encode(source)) is Some(tree) else {{\n'
                   f'    fail("parse failed")\n'
                   f'  }}\n'
                   f'  let sexp = tree.root_node().to_sexp()\n'
                   f'  assert_false(sexp.contains("ERROR") || sexp.contains("MISSING"), msg=sexp)\n'
                   f'}}\n')
    for lang in languages:
        queries = [(c, i, s) for c, i, s in strings if s.endswith('.scm') and lang['queries'](s)]
        if not queries:
            continue
        lines = ''.join(f'  ignore(@treesitter.Query::new(language, @{alias}.{i}))\n' for c, i, s in queries)
        out.append(f'\n///|\n'
                   f'test "{lang["fn"]} queries compile" {{\n'
                   f'  let language = @{alias}.{lang["fn"]}()\n'
                   f'{lines}'
                   f'}}\n')
    node_types = [(c, i, s) for c, i, s in strings if s.endswith('node-types.json')]
    if node_types:
        lines = ''.join(f'  assert_true(@{alias}.{i}.has_prefix("["))\n' for c, i, s in node_types)
        out.append(f'\n///|\n'
                   f'test "node types" {{\n'
                   f'{lines}'
                   f'}}\n')
    return ''.join(out)


# ---------------------------------------------------------------------------


def copy_file(src, dst):
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)


def generate(entry):
    name = entry['name']
    repo = G.repo_dir(entry)
    final = ROOT / 'grammars' / name
    # Generate next to the module and swap it in at the end, so that a failure
    # leaves the workspace intact.
    out = ROOT / 'grammars' / f'.{name}.tmp'
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    try:
        generate_into(entry, repo, out)
        format_module(out)
    except BaseException:
        shutil.rmtree(out, ignore_errors=True)
        raise
    if final.exists():
        shutil.rmtree(final)
    out.rename(final)
    return name


def format_module(out):
    """Run `moon fmt` on the generated code (except the embedded data, which is
    emitted in formatted form) in a scratch copy outside the workspace, so that
    no other module is touched."""
    small = [p for p in out.rglob('*')
             if p.is_file() and p.name in ('moon.mod', 'moon.pkg', 'binding.mbt', 'binding_test.mbt',
                                           'README.mbt.md', 'corpus_test.mbt')]
    with tempfile.TemporaryDirectory() as scratch:
        scratch = Path(scratch)
        for p in small:
            copy_file(p, scratch / p.relative_to(out))
        subprocess.run(['moon', 'fmt'], cwd=scratch, check=True, capture_output=True)
        for p in small:
            shutil.copyfile(scratch / p.relative_to(out), p)


def generate_into(entry, repo, out):
    name = entry['name']
    version = entry['tag'].lstrip('v')
    tsj = repo / 'tree-sitter.json'
    tsj_data = json.loads(tsj.read_text()) if tsj.exists() else {}
    metadata = tsj_data.get('metadata', {})
    semantic_version = metadata.get('version', '-')
    description = metadata.get('description') or f'{name} grammar for tree-sitter'
    upstream_url = f'https://github.com/{entry["repo"]}'

    licenses = sorted(p.name for p in repo.iterdir() if p.is_file() and re.match(r'(?i)licen[cs]e', p.name))
    if not licenses:
        raise SystemExit(f'{name}: no license file')
    for lic in licenses:
        copy_file(repo / lic, out / lic)
    entry = dict(entry, license_file=licenses[0])

    rust_languages, rust_strings = rust_binding(repo)
    languages_by_symbol = {}
    repo_languages = G.unique_languages(entry)
    first_language = repo_languages[0][0]
    for language, lang_dir in repo_languages:
        grammar = json.loads((lang_dir / 'src/grammar.json').read_text())
        languages_by_symbol['tree_sitter_' + grammar['name']] = (language, lang_dir, grammar)

    # Corpus directories and their default languages (see grammars.py ref()).
    def corpus_dirs_of(lang_dir):
        return [d for d in [lang_dir / 'test/corpus', lang_dir / 'corpus', repo / 'test/corpus', repo / 'corpus']
                if d.is_dir()]

    def default_language(corpus_dir):
        for language, lang_dir in repo_languages:
            if lang_dir != repo and repo in corpus_dir.parents and lang_dir in corpus_dir.parents:
                return language
        return first_language

    languages = []
    for const, symbol in rust_languages:
        language, lang_dir, grammar = languages_by_symbol[symbol]
        rel = os.path.relpath(lang_dir, repo)
        prefix = '' if rel == '.' else rel + '/'
        fn = mbt_ident(const)
        copy_file(lang_dir / 'src/grammar.json', out / prefix / 'src/grammar.json')
        corpus = []
        for d in corpus_dirs_of(lang_dir):
            corpus_rel = os.path.relpath(d, repo)
            if not (out / corpus_rel).exists():
                shutil.copytree(d, out / corpus_rel)
            corpus.append((corpus_rel, default_language(d)))
        # Seen by the moon test of this module, so keep corpus dirs deduplicated.
        seen = set()
        corpus = [c for c in corpus if not (c[0] in seen or seen.add(c[0]))]
        languages.append({
            'const': const, 'fn': fn, 'name': language, 'lang_dir': lang_dir, 'prefix': prefix,
            'grammar_name': grammar['name'], 'grammar_json': prefix + 'src/grammar.json',
            'display': f'`{language}`' if len(rust_languages) > 1 else f'the {language} grammar',
            'corpus': corpus, 'corpus_paths': corpus_dirs_of(lang_dir),
        })
    if len(languages) != len(repo_languages):
        raise SystemExit(f'{name}: the Rust binding has {len(languages)} languages, tree-sitter.json {len(repo_languages)}')

    def emit(lang):
        result = subprocess.run(
            [str(TOOL), 'emit', str(out / lang['grammar_json']), str(out / f'{lang["fn"]}_tables.mbt'),
             f'{lang["fn"]}_tables', semantic_version, str(out / lang['prefix'] / 'src/node-types.json'),
             lang['grammar_json']],
            capture_output=True, text=True)
        if result.returncode != 0:
            raise SystemExit(f'{name}: emit failed:\n{result.stdout}{result.stderr}')
        return json.loads(result.stdout.strip().split('\n')[-1])

    for lang in languages:
        info = emit(lang)
        lang['externals'] = info['external_token_count'] > 0
        lang['scanner'] = info['scanner']
        sample = pick_sample(lang['corpus_paths'], lang['name'], default_language)
        if sample is None:
            sample = SAMPLES.get(lang['name'])
        if sample is None:
            raise SystemExit(f'{name}: no sample for {lang["name"]}')
        lang['sample'] = sample
        lang['corpus_count'] = count_examples(lang['corpus_paths'], lang['name'], default_language)

    # Queries: every .scm file of the repository's queries directories.
    query_dirs = [repo / 'queries'] + [lang['lang_dir'] / 'queries' for lang in languages]
    for qd in query_dirs:
        if qd.is_dir():
            for f in sorted(qd.rglob('*.scm')):
                copy_file(f, out / os.path.relpath(f, repo))

    strings = []
    for const, rel in rust_strings:
        ident = mbt_ident(const)
        target = out / rel
        if not target.exists():
            copy_file(repo / rel, target)
        text = target.read_text()
        (out / f'{ident}.mbt').write_text(string_file(ident, text, rel, const))
        strings.append((const, ident, rel))

    for lang in languages:
        # The queries of a language: those in its own directory, or shared ones.
        own = lang['prefix']
        others = [l['prefix'] for l in languages if l['prefix'] and l is not lang]
        lang['queries'] = (lambda own, others: lambda s: (own and s.startswith(own)) or
                           not any(s.startswith(o) for o in others))(own, others)

    any_externals = any(lang['externals'] for lang in languages)
    keywords = ['tree-sitter', 'parser', 'grammar'] + sorted({lang['name'] for lang in languages})
    mod_description = (f'{description} ({entry["repo"]} {entry["tag"]}), for the MoonBit port of '
                       'Tree-sitter (moonbit-community/treesitter).')
    (out / 'moon.mod').write_text(moon_mod(entry, version, mod_description, keywords))
    (out / 'moon.pkg').write_text(moon_pkg(entry, any_externals))
    (out / 'binding.mbt').write_text(binding_file(entry, languages, version))
    (out / 'binding_test.mbt').write_text(smoke_test_file(entry, languages, strings))
    (out / 'README.mbt.md').write_text(readme(entry, version, description, languages, strings, upstream_url))
    corpus_test = corpus_test_file(entry, languages)
    if corpus_test:
        (out / 'tests').mkdir()
        (out / 'tests/moon.pkg').write_text(tests_moon_pkg(entry))
        (out / 'tests/corpus_test.mbt').write_text(corpus_test)
    return name


def main():
    args = sys.argv[1:]
    jobs = os.cpu_count() or 4
    if args[:1] == ['--jobs']:
        jobs = int(args[1])
        args = args[2:]
    entries = [e for e in G.entries() if not args or e['name'] in args]
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        for name in pool.map(generate, entries):
            print(f'grammars/{name}')
    # The workspace: the core module and every grammar module.
    members = ['.'] + [f'./grammars/{e["name"]}' for e in G.entries() if (ROOT / 'grammars' / e['name']).is_dir()]
    (ROOT / 'moon.work').write_text('members = [\n' + ''.join(f'  "{m}",\n' for m in members) + ']\n')


if __name__ == '__main__':
    main()
