// Pure MoonBit ports of the C external scanners used by upstream's test
// grammars and fixture grammars. Each port lives in its own file and exposes
// an `@runtime.ExternalScannerFactory`.

///|
/// The external scanner for a grammar, by the grammar's `name`.
pub fn scanner_for(name : String) -> @runtime.ExternalScannerFactory? {
  match name {
    "bash" => Some(bash_scanner)
    "cpp" => Some(cpp_scanner)
    "css" => Some(css_scanner)
    "html" => Some(html_scanner)
    "javascript" => Some(javascript_scanner)
    "jsdoc" => Some(jsdoc_scanner)
    "julia" => Some(julia_scanner)
    "lua" => Some(lua_scanner)
    "toml" => Some(toml_scanner)
    "python" => Some(python_scanner)
    "ruby" => Some(ruby_scanner)
    "rust" => Some(rust_scanner)
    "php" => Some(php_scanner)
    "php_only" => Some(php_only_scanner)
    "typescript" => Some(typescript_scanner)
    "tsx" => Some(tsx_scanner)
    _ => test_grammar_scanner(name)
  }
}
