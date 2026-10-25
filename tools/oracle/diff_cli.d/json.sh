# serde_json fidelity: number kinds and type errors of `config.json`
# themes, CST color tuples, syntax errors with their positions, the
# recursion limit, invalid UTF-8, and the typed deserialization of
# `tree-sitter.json` (duplicate and invalid fields, positions).
section_json() {
  local J="$WORK/json"
  rm -rf "$J"
  mkdir -p "$J"
  printf '// c\nfunction f(a) { return "s" + 1.5 + a.b; }\nvar x = true;\n' > "$J/a.js"

  # json_config NAME CONTENT: $J/NAME/config.json with the fixture grammars
  # as parser directories (CONTENT is spliced after them).
  json_config() {
    mkdir -p "$J/$1"
    printf '{\n  "parser-directories": ["%s"]%s\n}\n' "$GRAMMARS" "$2" > "$J/$1/config.json"
  }
  # json_raw NAME CONTENT: $J/NAME/config.json with exactly CONTENT.
  json_raw() {
    mkdir -p "$J/$1"
    printf '%s' "$2" > "$J/$1/config.json"
  }
  json_hl() {
    run_case "json-$1" "$J" env TREE_SITTER_DIR="$J/$1" NO_COLOR= -- highlight a.js
    run_case "json-$1-html" "$J" env TREE_SITTER_DIR="$J/$1" -- highlight --html a.js
  }
  json_cst() {
    run_case "json-$1" "$J" env TREE_SITTER_DIR="$J/$1" NO_COLOR= -- parse --cst a.js
  }

  # Theme colors: only unsigned integers are ANSI colors (`as u8`), floats
  # are not; hex colors are checked on bytes.
  json_config theme-numbers ',
  "theme": {"keyword": 1.0, "string": 4294967296, "number": 257, "comment": -1,
            "function": 18446744073709551615, "variable": 1e2, "property": 0.0,
            "operator": 22, "punctuation.bracket": 3.5}'
  json_hl theme-numbers
  json_config theme-strings ',
  "theme": {"keyword": "#éabcd", "string": "#+f+f+f", "number": "#FFaa00",
            "comment": "#ff00ff00", "function": "BLUE", "variable": "#12345",
            "property": "#ÉÉÉ", "operator": "#gg0000", "punctuation.bracket": "#-10000"}'
  json_hl theme-strings
  json_config theme-styles ',
  "theme": {"keyword": {"color": 1.0, "bold": true}, "string": {"color": 300, "italic": 1},
            "number": {"underline": true, "color": "#102030", "color": 5},
            "comment": [1, 2, 3], "function": null, "variable": true}'
  json_hl theme-styles
  run_case json-theme-truecolor "$J" env TREE_SITTER_DIR="$J/theme-strings" NO_COLOR= COLORTERM=truecolor -- highlight a.js
  json_config theme-not-object ',
  "theme": 5'
  json_hl theme-not-object
  json_config theme-array ',
  "theme": [1, 2]'
  json_hl theme-array

  # The configuration as a whole: structs also deserialize from arrays.
  json_raw top-integer '1'
  json_hl top-integer
  json_raw top-empty-array '[]'
  run_case json-top-empty-array "$J" env TREE_SITTER_DIR="$J/top-empty-array" -- dump-languages
  json_raw top-array-long '[[], {}, 3]'
  run_case json-top-array-long "$J" env TREE_SITTER_DIR="$J/top-array-long" -- dump-languages
  json_raw top-array-map '[{}]'
  run_case json-top-array-map "$J" env TREE_SITTER_DIR="$J/top-array-map" -- dump-languages
  json_raw parser-dirs-float '{"parser-directories": 1.0}'
  run_case json-parser-dirs-float "$J" env TREE_SITTER_DIR="$J/parser-dirs-float" -- dump-languages
  json_raw parser-dirs-int '{"parser-directories": ["a", 12]}'
  run_case json-parser-dirs-int "$J" env TREE_SITTER_DIR="$J/parser-dirs-int" -- dump-languages
  json_raw parser-dirs-neg '{"parser-directories": -7}'
  run_case json-parser-dirs-neg "$J" env TREE_SITTER_DIR="$J/parser-dirs-neg" -- dump-languages
  json_raw parser-dirs-big '{"parser-directories": 18446744073709551616}'
  run_case json-parser-dirs-big "$J" env TREE_SITTER_DIR="$J/parser-dirs-big" -- dump-languages
  json_raw parser-dirs-string '{"parser-directories": "a\"b\u0001é́"}'
  run_case json-parser-dirs-string "$J" env TREE_SITTER_DIR="$J/parser-dirs-string" -- dump-languages
  json_raw parser-dirs-null '{"parser-directories": null}'
  run_case json-parser-dirs-null "$J" env TREE_SITTER_DIR="$J/parser-dirs-null" -- dump-languages
  json_raw parser-dirs-dup '{"parser-directories": [1], "parser-directories": []}'
  run_case json-parser-dirs-dup "$J" env TREE_SITTER_DIR="$J/parser-dirs-dup" -- dump-languages

  # `parse --cst` colors: `Rgb(u8, u8, u8)` tuples.
  json_config cst-ok ',
  "parse-theme": {"node-kind": [1, 2, 3], "field": null, "literal": [255, 0, 255], "x": 1}'
  json_cst cst-ok
  json_config cst-256 ',
  "parse-theme": {"node-kind": [256, 0, 0]}'
  json_cst cst-256
  json_config cst-float ',
  "parse-theme": {"node-text": [1.0, 0, 0]}'
  json_cst cst-float
  json_config cst-neg ',
  "parse-theme": {"field": [0, -1, 0]}'
  json_cst cst-neg
  json_config cst-short ',
  "parse-theme": {"error": [1, 2]}'
  json_cst cst-short
  json_config cst-long ',
  "parse-theme": {"error": [1, 2, 3, 4]}'
  json_cst cst-long
  json_config cst-string ',
  "parse-theme": {"missing": "red"}'
  json_cst cst-string
  json_config cst-map ',
  "parse-theme": {"extra": {"r": 1}}'
  json_cst cst-map
  json_config cst-theme-array ',
  "parse-theme": [[1, 2, 3]]'
  json_cst cst-theme-array
  json_config cst-theme-int ',
  "parse-theme": 7'
  json_cst cst-theme-int
  json_config cst-big ',
  "parse-theme": {"backtick": [18446744073709551615, 0, 0]}'
  json_cst cst-big

  # Syntax errors, with serde_json's context and positions.
  json_raw syntax-open '{'
  json_hl syntax-open
  json_raw syntax-trailing-comma '{"a": [1, 2,], "b": 1}'
  json_hl syntax-trailing-comma
  json_raw syntax-trailing-chars $'{}\n  x'
  json_hl syntax-trailing-chars
  json_raw syntax-number $'{\n  "a": 1.e5\n}'
  json_hl syntax-number
  json_raw syntax-range '{"a": 1e400}'
  json_hl syntax-range
  json_raw syntax-utf8-column $'{"é": "ü",\n "ö": tru}'
  json_hl syntax-utf8-column
  json_raw syntax-escape '{"a": "\ud800"}'
  json_hl syntax-escape
  json_raw syntax-control $'{"a": "x\ty"}'
  json_hl syntax-control
  json_raw syntax-bom $'\xef\xbb\xbf{}'
  json_hl syntax-bom
  json_raw invalid-utf8 $'{"a": "\xff"}'
  json_hl invalid-utf8
  json_raw empty ''
  json_hl empty
  # The recursion limit: 127 nested arrays are accepted, 128 are not.
  json_raw depth-127 "{\"x\": $(printf '[%.0s' {1..127})$(printf ']%.0s' {1..127}), \"parser-directories\": [\"$GRAMMARS\"]}"
  json_hl depth-127
  json_raw depth-128 "{\"x\": $(printf '[%.0s' {1..128})$(printf ']%.0s' {1..128})}"
  json_hl depth-128
  json_raw depth-130 "{\"x\": $(printf '[%.0s' {1..130})$(printf ']%.0s' {1..130})}"
  json_hl depth-130
  json_raw depth-objects "{\"x\": $(printf '{"a":%.0s' {1..127})1$(printf '}%.0s' {1..127})}"
  json_hl depth-objects
  run_case json-config-path "$J" highlight --config-path syntax-open/config.json a.js

  # tree-sitter.json of a grammar directory, parsed with `from_str` (data
  # errors carry positions). Each case has its own parser directory.
  json_grammar() {
    local g="$J/grammar-$1"
    mkdir -p "$g/tree-sitter-$1"
    printf '%s' "$2" > "$g/tree-sitter-$1/tree-sitter.json"
    printf '{"parser-directories": ["%s"]}' "$g" > "$g/config.json"
    run_case "json-grammar-$1" "$J" env TREE_SITTER_DIR="$g" -- dump-languages
  }
  local meta='"metadata": {"version": "1.0.0"}'
  json_grammar dup-scope "{\"grammars\": [{\"name\": \"x\", \"scope\": \"a\", \"scope\": \"b\"}], $meta}"
  json_grammar fields-order "{\"grammars\": [{\"name\": 1, \"file-types\": 2, \"scope\": 3}], $meta}"
  json_grammar fields-order2 "{\"grammars\": [{\"file-types\": 2, \"name\": 1}], $meta}"
  json_grammar missing-scope "{\"grammars\": [{\"name\": \"x\"}], $meta}"
  json_grammar missing-metadata '{"grammars": []}'
  json_grammar paths-bad "{\"grammars\": [{\"name\": \"x\", \"scope\": \"a\", \"highlights\": [\"a\", 1]}], $meta}"
  json_grammar paths-map "{\"grammars\": [{\"name\": \"x\", \"scope\": \"a\", \"tags\": {}}, 5], $meta}"
  json_grammar version-bad '{"grammars": [], "metadata": {"version": "1.x"}}'
  json_grammar version-int '{"grammars": [], "metadata": {"version": 1}}'
  json_grammar bindings-bad "{\"grammars\": [], $meta, \"bindings\": {\"c\": \"yes\"}}"
  json_grammar bindings-dup "{\"grammars\": [], $meta, \"bindings\": {\"c\": true, \"c\": false}}"
  json_grammar seq-grammar "{\"grammars\": [[\"x\", null, null, \"a\"]], $meta}"
  json_grammar seq-top '[null, []]'
  json_grammar seq-top-long '[null, [], {"version": "1.0.0"}, {}, 5]'
  json_grammar authors-bad "{\"grammars\": [], \"metadata\": {\"version\": \"1.0.0\", \"authors\": [{\"email\": \"e\"}]}}"
  json_grammar links-bad "{\"grammars\": [], \"metadata\": {\"version\": \"1.0.0\", \"links\": 3}}"
  json_grammar unknown-deep "{\"grammars\": [], $meta, \"zz\": $(printf '[%.0s' {1..200})$(printf ']%.0s' {1..200})}"
  json_grammar trailing "{\"grammars\": [], $meta} x"
  json_grammar not-utf8 $'{"grammars": [], "x": "\xc3"}'
  json_grammar schema-int '{"$schema": 1}'
}
