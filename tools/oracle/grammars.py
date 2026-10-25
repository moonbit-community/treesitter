"""The grammar repositories of grammars/grammars.json.

Fixture grammars live in the pinned upstream checkout (fetched by
`cargo xtask fetch-fixtures`); the others are cloned at their pinned tags into
.repos/grammars/<name> by `fetch`. `ref` generates their reference outputs
with the pinned upstream CLI into _build/ref/extra_<language>, with a
meta.json describing where their corpus, queries and scanner are, which
diff_runtime.py and diff_query.py read.

Usage: python3 tools/oracle/grammars.py fetch|ref|list
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COMMON = Path(subprocess.check_output(
    ['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], cwd=ROOT, text=True).strip()).parent
UPSTREAM = COMMON / '.repos/ts-pinned'
EXTRA = COMMON / '.repos/grammars'
REF = ROOT / '_build/ref'


def entries():
    return json.loads((ROOT / 'grammars/grammars.json').read_text())['grammars']


def repo_dir(entry):
    if entry.get('fixture'):
        return UPSTREAM / 'test/fixtures/grammars' / entry['name']
    return EXTRA / entry['name']


def languages(entry):
    """(language name, language directory) pairs of a grammar repository."""
    base = repo_dir(entry)
    config = base / 'tree-sitter.json'
    if config.exists():
        result = []
        for grammar in json.loads(config.read_text())['grammars']:
            result.append((grammar['name'], base / grammar.get('path', '.')))
        return result
    name = json.loads((base / 'src/grammar.json').read_text())['name']
    return [(name, base)]


def unique_languages(entry):
    """`languages`, keeping only the first language of each directory (the
    others share its grammar: tree-sitter-embedded-template lists its grammar
    three times, tree-sitter-typescript's `flow` is the tsx grammar)."""
    result = {}
    for language, lang_dir in languages(entry):
        result.setdefault(lang_dir, language)
    return [(language, lang_dir) for lang_dir, language in result.items()]


def ref_name(language):
    return 'extra_' + language.replace('-', '_')


def fetch():
    for entry in entries():
        if entry.get('fixture'):
            continue
        dest = repo_dir(entry)
        if dest.exists():
            tag = subprocess.run(['git', 'describe', '--tags', '--exact-match'], cwd=dest,
                                 capture_output=True, text=True).stdout.strip()
            if tag == entry['tag']:
                continue
            shutil.rmtree(dest)
        dest.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(['git', 'clone', '-q', '--depth', '1', '--branch', entry['tag'],
                        f"https://github.com/{entry['repo']}.git", str(dest)], check=True)
        print(f"fetched {entry['name']} {entry['tag']}")


def ref():
    ts = UPSTREAM / 'target/release/tree-sitter'
    for entry in entries():
        if entry.get('fixture'):
            continue
        base = repo_dir(entry)
        for language, lang_dir in languages(entry):
            name = ref_name(language)
            out = REF / name
            shutil.rmtree(out, ignore_errors=True)
            (out / 'src').mkdir(parents=True)
            shutil.copy(lang_dir / 'src/grammar.json', out / 'src/grammar.json')
            corpus = [str(d) for d in [lang_dir / 'test/corpus', lang_dir / 'corpus',
                                      base / 'test/corpus', base / 'corpus'] if d.is_dir()]
            queries = next((str(d) for d in [lang_dir / 'queries', base / 'queries'] if d.is_dir()), None)
            scanner = next((str(p) for p in [lang_dir / 'src/scanner.c'] if p.exists()), None)
            meta = {'grammar': entry['name'], 'language': language, 'dir': str(lang_dir),
                    'corpus': sorted(set(corpus), key=corpus.index), 'queries': queries, 'scanner': scanner}
            (out / 'meta.json').write_text(json.dumps(meta, indent=2) + '\n')
            with open(out / 'generate.log', 'w') as log:
                ok = subprocess.run([str(ts), 'generate', 'src/grammar.json'], cwd=out,
                                    stdout=log, stderr=subprocess.STDOUT).returncode == 0
            print(f"{name} {'ok' if ok else 'FAILED'}")


def list_languages():
    for entry in entries():
        for language, lang_dir in languages(entry):
            print(entry['name'], language, lang_dir)


if __name__ == '__main__':
    {'fetch': fetch, 'ref': ref, 'list': list_languages}[sys.argv[1]]()
