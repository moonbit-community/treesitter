"""Freeze changed-range regressions using development-only upstream C code.
Requires the pinned .repos/tree-sitter and tree-sitter-json v0.24.8 checkouts.
Normal builds and portable tests require neither compiler nor reference source.
"""
from pathlib import Path
import os
import json
import subprocess
root = Path(__file__).resolve().parents[1]
os.chdir(root)
assert subprocess.check_output(['git', '-C', '.repos/tree-sitter', 'rev-parse', 'HEAD'], text=True).strip() == '4a412a01a0147d0f50bf7e749572fa632d1ab203'
assert json.loads(Path('.repos/tree-sitter-json/package.json').read_text())['version'] == '0.24.8'
output = Path('_build/reference-json')
output.mkdir(parents=True, exist_ok=True)
(output / "ranges.c").write_text('#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include "tree_sitter/api.h"\nconst TSLanguage *tree_sitter_json(void);\nint main(int argc,char **argv){if(argc!=6)return 2;TSParser*p=ts_parser_new();ts_parser_set_language(p,tree_sitter_json());TSTree*a=ts_parser_parse_string(p,0,argv[1],strlen(argv[1]));unsigned s=atoi(argv[3]),o=atoi(argv[4]),n=atoi(argv[5]);TSInputEdit e={s,o,n,{0,s},{0,o},{0,n}};ts_tree_edit(a,&e);TSTree*b=ts_parser_parse_string(p,a,argv[2],strlen(argv[2]));unsigned count;TSRange*r=ts_tree_get_changed_ranges(a,b,&count);for(unsigned i=0;i<count;i++)printf("%u..%u\\n",r[i].start_byte,r[i].end_byte);free(r);ts_tree_delete(a);ts_tree_delete(b);ts_parser_delete(p);}\n')
subprocess.run(['cc', '-O2', '-I.repos/tree-sitter/lib/include', '-I.repos/tree-sitter/lib/src', '-I.repos/tree-sitter-json/src', str(output / 'ranges.c'), '.repos/tree-sitter-json/src/parser.c', '.repos/tree-sitter/lib/src/lib.c', '-o', str(output / 'ranges')], check=True)
pairs=[('[1,2,3]','[1,2,3,4]'),('[1,2,3]','[1,3]'),('[1,2,3]','[1,true,3]'),('[1,2,3]','[1,200,3]'),('{}','{"a":1}'),('{"a":1}','{}'),('{"a":1}','{"b":1}'),('{"a":1}','{"a":true}'),('[1]','[ 1 ]'),('[1]',' [1] '),('1','true'),('true','1'),('1','12'),('[1]','[]'),('[]','[1]'),('[]','{}'),('[1,2]','[1,2,3,4]'),('[1,2,3]','[0,1,2,3]'),('[1,2,3]','[1,0,2,3]'),('[1,2]','[1,[2]]'),('[1,[2]]','[1,2]'),('"abc"','"abxc"'),('"abc"','"a\\nbc"'),('1','1 /*a*/'),('1 /*a*/','1'),('','1'),('1',''),('[1,2]','[1,,2]'),('[1,,2]','[1,2]')]
import random
rng=random.Random(17)
values=[None,True,False,0,1,100,"a","longer",[],[1,2],{}, {"a":[0,1]}]
for _ in range(200):
 old=[rng.choice(values) for _ in range(rng.randrange(1,8))]
 new=old.copy()
 i=rng.randrange(len(new))
 if rng.randrange(3)==0: new.pop(i)
 elif rng.randrange(2)==0: new.insert(i,rng.choice(values))
 else: new[i]=rng.choice(values)
 pairs.append((json.dumps(old,separators=(',',':')),json.dumps(new,separators=(',',':'))))
lines=['// Frozen against the pinned Tree-sitter runtime and JSON v0.24.8. See NOTICE.','///|','test "upstream JSON changed ranges" {','  let language = upstream_json_language()','  let parser = @ts.Parser::new(language)','  let cases : Array[(String, String, Int, Int, Int, Array[(Int, Int)])] = [']
for old,new in pairs:
 start=0
 while start<min(len(old),len(new)) and old[start]==new[start]: start+=1
 endold,endnew=len(old),len(new)
 while endold>start and endnew>start and old[endold-1]==new[endnew-1]: endold-=1;endnew-=1
 raw=subprocess.check_output(['_build/reference-json/ranges',old,new,str(start),str(endold),str(endnew)],text=True)
 ranges=[tuple(map(int,l.split('..'))) for l in raw.splitlines()]
 lines.append(f'    ({json.dumps(old)}, {json.dumps(new)}, {start}, {endold}, {endnew}, ['+', '.join(f'({a}, {b})' for a,b in ranges)+']),')
lines+=['  ]','  for (old_source, new_source, start, old_end, new_end, expected) in cases {','    let old = parser.parse_string(old_source)','    old.edit({ start_byte: start, old_end_byte: old_end, new_end_byte: new_end, start_point: {row: 0, column: start}, old_end_point: {row: 0, column: old_end}, new_end_point: {row: 0, column: new_end} })','    let new = parser.parse(@utf8.encode(new_source), old_tree=old)', '    assert_eq(new.root_node().to_sexp(), parser.parse_string(new_source).root_node().to_sexp())','    let actual = old.changed_ranges(new).map(r => (r.start_byte, r.end_byte))','    assert_eq(actual, expected, msg="\\{old_source} -> \\{new_source}")','  }','}']
open('compat/changed_ranges_test.mbt','w').write('\n'.join(lines)+'\n')
