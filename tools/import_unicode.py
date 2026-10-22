"""Import Unicode DATA (not Rust code) from the pinned regex-syntax source.
Usage: python3 tools/import_unicode.py .repos/regex-syntax/regex-syntax-0.8.11
Development-only; generated tables have no Python or Rust runtime dependency.
"""
from pathlib import Path
import re
import sys
import ast
import shutil

root = Path(sys.argv[1])
source = root / 'src/unicode_tables'
CHAR = r"'(?:\\u\{[0-9a-fA-F]+\}|\\.|[^'\\])'"

def cp(text):
    if text.startswith("'\\u{"):
        return int(text[4:-2], 16)
    return ord(ast.literal_eval(text))

def norm(s):
    return s.lower().replace('_', '').replace('-', '').replace(' ', '')

out = Path('lex/unicode_data.mbt')
parts = ['// Generated from regex-syntax 0.8.11 Unicode 16.0.0 data.\n// Source crate SHA256: d6f6ff9a378485b298a5286656da665ba74413d36db0979633275d2e708145d4\n// See tools/import_unicode.py and licenses/UNICODE.txt.\n']
for filename, func in [('perl_decimal', 'unicode_digits'), ('perl_space', 'unicode_space'), ('perl_word', 'unicode_word')]:
    data = (source / (filename + '.rs')).read_text()
    pairs = re.findall(r'\((' + CHAR + r'),\s*(' + CHAR + r')\)', data)
    parts += ['///|\nfn ' + func + '() -> CharSet {\n  CharSet::new([\n']
    parts += [f'    ({cp(a)}, {cp(b)}),\n' for a,b in pairs]
    parts += ['  ])\n}\n\n']
fold = (source/'case_folding_simple.rs').read_text()
pairs=[]
for a, targets in re.findall(r'\((' + CHAR + r'),\s*&\[([^]]*)\]\)', fold):
    for b in re.findall(CHAR, targets):
        # Match upstream's deliberate exclusion of long-s and Kelvin sign.
        if cp(a) not in (0x17f, 0x212a) and cp(b) not in (0x17f, 0x212a):
            pairs.append((cp(a), cp(b)))
parts += ['///|\nlet unicode_folds : Array[(Int, Int)] = [\n']
parts += [f'  ({a}, {b}),\n' for a,b in pairs]
parts += [']\n']
out.write_text(''.join(parts))

# Canonical aliases for general categories and scripts.
values = (source/'property_values.rs').read_text()
value_aliases={}
for name, body in re.findall(r'\(\s*"([^"]+)",\s*&\[(.*?)\],\s*\)',values,re.S):
    value_aliases[name]={a:b for a,b in re.findall(r'\("([^"]+)",\s*"([^"]+)"\)',body)}
prop_aliases={a:b for a,b in re.findall(r'\("([^"]+)",\s*"([^"]+)"\)',(source/'property_names.rs').read_text())}
for filename, group in [('general_category', 'General_Category'), ('script','Script'), ('script_extension','Script_Extensions'), ('property_bool', 'Binary')]:
    text=(source/(filename+'.rs')).read_text()
    names={const:name for name,const in re.findall(r'\("([^"]+)",\s*([A-Z_0-9]+)\)',text)}
    parts=['// Generated Unicode 16.0.0 data; see unicode_data.mbt and licenses/UNICODE.txt.\n\n///|\nfn unicode_'+filename+'(name : String) -> CharSet? {\n  match name {\n']
    for const, body in re.findall(r'pub const ([A-Z_0-9]+):[^=]*=\s*&\[(.*?)\];',text,re.S):
        if const not in names: continue
        name=names[const]
        aliases={norm(name)}
        aliases |= {norm(a) for a,b in value_aliases.get(group,{}).items() if b == name}
        if group=='Binary': aliases |= {norm(a) for a,b in prop_aliases.items() if b==name}
        pairs=re.findall(r'\((' + CHAR + r'),\s*(' + CHAR + r')\)',body)
        parts += ['    '+' | '.join('"'+a+'"' for a in sorted(aliases))+' => Some(CharSet::new([\n']
        parts += [f'      ({cp(a)}, {cp(b)}),\n' for a,b in pairs]
        parts += ['    ]))\n']
    parts += ['    _ => None\n  }\n}\n']
    Path('lex/unicode_'+filename+'.mbt').write_text(''.join(parts))
shutil.copyfile(source/'LICENSE-UNICODE', 'licenses/UNICODE.txt')
