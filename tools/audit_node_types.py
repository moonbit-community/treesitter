"""Compare generated schema with the pinned upstream generator (development only)."""
from pathlib import Path
import json
import subprocess
ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'_build/reference-target/release/tree-sitter'
CLI=ROOT/'_build/native/debug/build/cmd/treesitter/treesitter.exe'
OUT=ROOT/'_build/node-types-audit'
OUT.mkdir(parents=True,exist_ok=True)
results=[]
for source in sorted((ROOT/'_build/audit').glob('*.grammar.json')):
    name=source.name.removesuffix('.grammar.json')
    dest=OUT/name
    dest.mkdir(exist_ok=True)
    language=dest/'language.json'
    reference=subprocess.run([str(REF),'generate','--no-parser','-o',str(dest/'src'),str(source)],capture_output=True,text=True)
    if reference.returncode: continue
    generated=subprocess.run([str(CLI),'generate',str(source),str(language)],capture_output=True,text=True)
    if generated.returncode: continue
    ours=subprocess.run([str(CLI),'node-types',str(language),str(dest/'ours.json')],capture_output=True,text=True)
    if ours.returncode: raise RuntimeError(ours.stderr)
    a=json.loads((dest/'ours.json').read_text());b=json.loads((dest/'src/node-types.json').read_text())
    differences=[]
    for identity in sorted({(x['type'],x['named']) for x in a+b}):
        left=next((x for x in a if (x['type'],x['named'])==identity),None)
        right=next((x for x in b if (x['type'],x['named'])==identity),None)
        if left!=right: differences.append({'type':identity,'ours':left,'reference':right})
    results.append({'name':name,'differences':differences,'order_equal':a==b})
    print(name, 'PASS' if a==b else f'{len(differences)} differences',flush=True)
(OUT/'results.json').write_text(json.dumps(results,indent=2))
print('exact:',sum(r['order_equal'] for r in results),'/',len(results))
