"""Check the grammar modules under grammars/ against upstream.

For every language of every repository in grammars/grammars.json:

- the Language embedded in grammars/<name>/<fn>_tables.mbt (decoded by
  `grammar_modules dump`, i.e. `@language.Language::from_compact_base64`)
  must equal _build/reflang/<ref>.json, the tables that language_from_c.py
  reads from the parser.c the pinned upstream CLI generates (oracle_setup.sh),
  up to the representation differences listed in `normalize`. The reference is generated outside the grammar repository, without its
  tree-sitter.json, so its metadata is 0.0.0; the module's metadata must be
  the version in tree-sitter.json (what `tree-sitter generate` stores there);
- the module's src/node-types.json must equal the one upstream generates
  (_build/ref/<ref>/src/node-types.json);
- the module's src/grammar.json must equal the pinned checkout's.

<ref> is fixture_<path> for upstream fixture grammars (the language directory
under test/fixtures/grammars, with / replaced by _) and extra_<language>
otherwise (tools/oracle/grammars.py).

Usage: python3 tools/oracle/compare_modules.py [name...]
Needs the oracle (oracle_setup.sh) and a native build of tools/grammar_modules.
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/oracle'))
import grammars as G  # noqa: E402

TOOL = ROOT / '_build/native/release/build/moonbit-community/treesitter/tools/grammar_modules/grammar_modules.exe'


def normalize(language):
    """Remove the differences between the generator's `Language` and the one
    language_from_c.py reconstructs from parser.c that do not change what the
    runtime reads:

    - field_names: dump_language.c always prints the `NULL` entry 0 (`""`);
      the generator leaves the array empty when there are no fields;
    - supertype_map_slices / entries: parser.c initializes the slices up to the
      largest supertype; dump_language.c reads `symbol_count` of them (past the
      array for other symbols) and the entries they span. Keep the slices up
      to the largest supertype and the entries they reference;
    - lex conditions: a lone negative character test can be read from C as
      either the asserted (`is_included: false`) or the negated part of a
      condition (`((large || asserted) && negated)` with the other parts
      absent); use the negated part;
    - character ranges: C tests `lookahead == 'a' || lookahead == 'b'` are
      read as two ranges where the generator has one; merge adjacent ranges;
    - large character sets: the generator's `LexProgram` holds every large
      set of the grammar, parser.c only the ones used; replace set indices by
      the sets.
    """
    if language['field_count'] == 0 and language['field_names'] == ['']:
        language['field_names'] = []
    supertypes = language['supertype_symbols']
    if supertypes:
        slices = language['supertype_map_slices'][:max(supertypes) + 1]
        language['supertype_map_slices'] = slices
        end = max((s['index'] + s['length'] for s in slices), default=0)
        language['supertype_map_entries'] = language['supertype_map_entries'][:end]
    for program in [language['lex_fn'], language.get('keyword_lex_fn')]:
        if program is None:
            continue
        sets = program.pop('large_character_sets')
        for state in program['states']:
            for transition in state['transitions']:
                c = transition['condition']
                asserted = c.get('asserted')
                if (asserted is not None and not asserted['is_included'] and c.get('large_set') is None
                        and c.get('negated') is None):
                    c['negated'] = c.pop('asserted')
                for part in ('asserted', 'negated'):
                    if part in c:
                        c[part]['ranges'] = merge_ranges(c[part]['ranges'])
                if 'large_set' in c:
                    index, guarded = c['large_set']
                    c['large_set'] = [merge_ranges(sets[index]), guarded]
    return language


def merge_ranges(ranges):
    """The same set of characters with adjacent ranges merged: C tests
    `lookahead == 'a' || lookahead == 'b'` and the generator's range
    ['a', 'b'] are the same condition."""
    result = []
    for r in ranges:
        if result and r['start'] <= result[-1]['end'] + 1:
            result[-1] = {'start': result[-1]['start'], 'end': max(result[-1]['end'], r['end'])}
        else:
            result.append(dict(r))
    return result


def ref_name(entry, language, lang_dir):
    if entry.get('fixture'):
        rel = os.path.relpath(lang_dir, G.UPSTREAM / 'test/fixtures/grammars')
        return 'fixture_' + rel.replace('/', '_')
    return G.ref_name(language)


def main():
    names = sys.argv[1:]
    ok = 0
    failures = []
    with tempfile.TemporaryDirectory() as scratch:
        for entry in G.entries():
            if names and entry['name'] not in names:
                continue
            repo = G.repo_dir(entry)
            module = ROOT / 'grammars' / entry['name']
            tsj = repo / 'tree-sitter.json'
            version = json.loads(tsj.read_text()).get('metadata', {}).get('version') if tsj.exists() else None
            major, minor, patch = (int(x) for x in version.split('.')) if version else (0, 0, 0)
            # The embedded languages, by grammar name.
            embedded = {}
            for tables in sorted(module.glob('*_tables.mbt')):
                out = Path(scratch) / (entry['name'] + '_' + tables.stem + '.json')
                subprocess.run([str(TOOL), 'dump', str(tables), str(out)], check=True)
                language = json.loads(out.read_text())
                embedded[language['name']] = (tables.name, language)
            for language_name, lang_dir in G.unique_languages(entry):
                grammar = json.loads((lang_dir / 'src/grammar.json').read_text())
                ref = ref_name(entry, language_name, lang_dir)
                label = f'{entry["name"]}/{language_name} ({ref})'
                problems = []
                if grammar['name'] not in embedded:
                    failures.append(f'{label}: no embedded language named {grammar["name"]}')
                    continue
                tables_file, actual = embedded.pop(grammar['name'])
                expected = json.loads((ROOT / '_build/reflang' / f'{ref}.json').read_text())
                metadata = actual.get('metadata')
                if metadata != {'major_version': major, 'minor_version': minor, 'patch_version': patch}:
                    problems.append(f'metadata {metadata} is not {version}')
                actual['metadata'] = expected['metadata']
                actual, expected = normalize(actual), normalize(expected)
                if actual != expected:
                    fields = [k for k in expected if actual.get(k) != expected[k]]
                    problems.append(f'{tables_file} differs from _build/reflang/{ref}.json in {fields}')
                rel = os.path.relpath(lang_dir, repo)
                prefix = module if rel == '.' else module / rel
                node_types = (prefix / 'src/node-types.json').read_bytes()
                if node_types != (ROOT / '_build/ref' / ref / 'src/node-types.json').read_bytes():
                    problems.append('src/node-types.json differs from upstream generate')
                if (prefix / 'src/grammar.json').read_bytes() != (lang_dir / 'src/grammar.json').read_bytes():
                    problems.append('src/grammar.json differs from the pinned checkout')
                if problems:
                    failures.extend(f'{label}: {p}' for p in problems)
                else:
                    ok += 1
                    print(f'ok {label}')
            for name, (tables_file, _) in embedded.items():
                failures.append(f'{entry["name"]}: unexpected embedded language {name} ({tables_file})')
    for f in failures:
        print('FAIL ' + f)
    print(f'identical={ok} different={len(failures)}')
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
