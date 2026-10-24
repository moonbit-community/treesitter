// MoonBit-specific entry points of the loader for language table files
// (the port's equivalent of compiled parser libraries).

///|
/// The language tables of the grammar in `src_path` (without binding a
/// scanner), for `tree-sitter build`.
pub async fn Loader::language_tables_at_path(
  self : Loader,
  src_path : String,
) -> @language.Language {
  let grammar_path = @support.path_join(src_path, "grammar.json")
  let name = Loader::grammar_json_name(grammar_path)
  self.load_language_tables(src_path, name, None)
}

///|
/// `Loader::load_language(path, function_name)`: the MoonBit port's "parser
/// library" is a language table file (`language.json`), loaded with the
/// external scanner registered for `language_name`, if any.
pub async fn Loader::load_language_file(
  self : Loader,
  path : String,
  language_name : String,
) -> @api.Language {
  let raw = read_language_json(path)
  let registry = self.scanners
  let scanner = if raw.external_token_count == 0 {
    None
  } else {
    match registry(language_name) {
      Some(f) => Some(f)
      None => @scanners.scanner_for(language_name)
    }
  }
  @api.Language::new(raw, external_scanner?=scanner)
}
