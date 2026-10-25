// Port of tree-sitter crates/generate/src/render.rs.
//
// Upstream's `Generator` prints `parser.c` directly. Here the same computation
// is split in two phases so that the C text and the portable `Language` cannot
// diverge:
//
// 1. `Generator::init` (as upstream) followed by `Generator::render_tables`
//    (render_tables.mbt, render_lex.mbt) computes every table that upstream's
//    `add_*` methods print, as a `RenderedParser` holding numeric symbol
//    values in emission order.
// 2. Either `RenderedParser::print_c` (render_c.mbt) prints exactly upstream's
//    `parser.c` from it, converting each symbol value back to its C
//    identifier, or `RenderedParser::to_language` (render_language.mbt)
//    places the same values into the `@language.Language` arrays.

///|
let small_state_threshold : Int32 = 64

///|
pub let abi_version_min : Int32 = 14

///|
pub let abi_version_max : Int32 = @language.language_version

///|
let abi_version_with_reserved_words : Int32 = 15

///|
/// `build_tables::LARGE_CHARACTER_RANGE_COUNT` (defined in
/// build_lex_table.rs upstream, which another file of this port owns).
let render_large_character_range_count : Int32 = 8

///|
/// Upstream `RenderError`.
pub suberror RenderError {
  ParseTable(Int32)
  ABI(Int32)
} derive(Eq, Debug)

///|
pub impl Show for RenderError with fn output(self, logger) {
  match self {
    ParseTable(count) =>
      logger.write_string(
        "Parse table action count \{count} exceeds maximum value of 65535",
      )
    ABI(version) =>
      logger.write_string(
        "This version of Tree-sitter can only generate parsers with ABI version \{abi_version_min} - \{abi_version_max}, not \{version}",
      )
  }
}

///|
priv struct LargeCharacterSetInfo {
  constant_name : String
}

///|
priv struct Generator {
  language_name : String
  parse_table : ParseTable
  main_lex_table : LexTable
  keyword_lex_table : LexTable
  large_character_sets : Array[(Symbol?, CharacterSet)]
  large_character_set_info : Array[LargeCharacterSetInfo]
  mut large_state_count : Int32
  syntax_grammar : SyntaxGrammar
  lexical_grammar : LexicalGrammar
  default_aliases : AliasMap
  /// Upstream fills this in `add_symbol_enum`; here `assign_symbol_order`
  /// does, before any table is computed. Lookup only.
  symbol_order : Map[Symbol, Int32]
  /// Lookup only (upstream `FxHashMap`).
  symbol_ids : Map[Symbol, String]
  /// Lookup only (upstream `FxHashMap`).
  alias_ids : Map[Alias, String]
  unique_aliases : Array[Alias]
  /// Lookup only (upstream `FxHashMap`).
  symbol_map : Map[Symbol, Symbol]
  reserved_word_sets : Array[TokenSet]
  reserved_word_set_ids_by_parse_state : Array[Int32]
  field_names : Array[StrId]
  supertype_symbol_map : @sorted_map.SortedMap[Symbol, Array[ChildType]]
  /// Upstream `BTreeMap<String, Vec<ChildType>>`: kept sorted by key, in
  /// Rust's byte-wise `str` order.
  supertype_map : Array[(String, Array[ChildType])]
  abi_version : Int32
  metadata : (Int32, Int32, Int32)?
  str_pool : StrPool
}

///|
/// Rust's `str` ordering (byte-wise UTF-8, i.e. code point order). MoonBit's
/// `String::compare` is shortlex over UTF-16 code units, so it can't be used
/// where upstream sorts strings.
fn Generator::compare_strs(a : String, b : String) -> Int32 {
  let ai = a.iter()
  let bi = b.iter()
  for ;; {
    match (ai.next(), bi.next()) {
      (None, None) => return 0
      (None, Some(_)) => return -1
      (Some(_), None) => return 1
      (Some(x), Some(y)) => if x != y { return x.to_int().compare(y.to_int()) }
    }
  }
}

///|
/// Rust's `binary_search_by` on a sorted array, returning the insertion
/// index when no element compares equal (`Err(i)`), and `None` otherwise.
fn[T] Generator::insertion_point(
  array : Array[T],
  cmp : (T) -> Int32,
) -> Int32? {
  let mut lo = 0
  let mut hi = array.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let c = cmp(array[mid])
    if c < 0 {
      lo = mid + 1
    } else if c > 0 {
      hi = mid
    } else {
      return None
    }
  }
  Some(lo)
}

///|
fn Generator::new(
  name : StrId,
  tables : Tables,
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  default_aliases : AliasMap,
  str_pool : StrPool,
  abi_version : Int32,
  semantic_version : (Int32, Int32, Int32)?,
  supertype_symbol_map : @sorted_map.SortedMap[Symbol, Array[ChildType]],
) -> Generator raise RenderError {
  if !(abi_version >= abi_version_min && abi_version <= abi_version_max) {
    raise ABI(abi_version)
  }
  {
    language_name: str_pool.resolve(name),
    parse_table: tables.parse_table,
    main_lex_table: tables.main_lex_table,
    keyword_lex_table: tables.keyword_lex_table,
    large_character_sets: tables.large_character_sets,
    large_character_set_info: [],
    large_state_count: 0,
    syntax_grammar,
    lexical_grammar,
    default_aliases,
    symbol_order: {},
    symbol_ids: {},
    alias_ids: {},
    unique_aliases: [],
    symbol_map: {},
    reserved_word_sets: [],
    reserved_word_set_ids_by_parse_state: [],
    field_names: [],
    supertype_symbol_map,
    supertype_map: [],
    abi_version,
    metadata: semantic_version,
    str_pool,
  }
}

///|
fn Generator::init(self : Generator) -> Unit {
  let symbol_identifiers : Set[String] = Set([])
  for symbol in self.parse_table.symbols {
    self.assign_symbol_id(symbol, symbol_identifiers)
  }
  self.symbol_ids[symbol_end_of_nonterminal_extra] = self.symbol_ids[symbol_end]
  self.symbol_map.clear()
  for symbol in self.parse_table.symbols {
    let mut mapping = symbol

    // There can be multiple symbols in the grammar that have the same name and kind,
    // due to simple aliases. When that happens, ensure that they map to the same
    // public-facing symbol. If one of the symbols is not aliased, choose that one
    // to be the public-facing symbol. Otherwise, pick the symbol with the lowest
    // numeric value.
    if self.default_aliases.get(symbol) is Some(alias) {
      let kind = alias.kind()
      for other_symbol in self.parse_table.symbols {
        if self.default_aliases.get(other_symbol) is Some(other_alias) {
          if other_symbol < mapping && other_alias == alias {
            mapping = other_symbol
          }
        } else if self.metadata_for_symbol(other_symbol) == (alias.value, kind) {
          mapping = other_symbol
          break
        }
      }
    } else if symbol.kind is Terminal {
      // Two anonymous tokens with different flags but the same string value
      // should be represented with the same symbol in the public API. Examples:
      // * "<" and token(prec(1, "<"))
      // * "(" and token.immediate("(")
      let metadata = self.metadata_for_symbol(symbol)
      for other_symbol in self.parse_table.symbols {
        let other_metadata = self.metadata_for_symbol(other_symbol)
        if other_metadata == metadata {
          if self.symbol_map.get(other_symbol) is Some(mapped) &&
            mapped == symbol {
            break
          }
          mapping = other_symbol
          break
        }
      }
    }
    self.symbol_map[symbol] = mapping
  }
  for production_info in self.parse_table.production_infos {
    // Build a list of all field names
    for field_name in production_info.field_map.keys() {
      let field_name_str = self.str_pool.resolve(field_name)
      if Generator::insertion_point(self.field_names, sid => {
          Generator::compare_strs(self.str_pool.resolve(sid), field_name_str)
        })
        is Some(i) {
        self.field_names.insert(i, field_name)
      }
    }

    // Generate a mapping from aliases to C identifiers.
    for maybe_alias in production_info.alias_sequence {
      guard maybe_alias is Some(alias) else { continue }
      // Some aliases match an existing symbol in the grammar.
      let alias_id = match self.symbols_for_alias(alias).get(0) {
        Some(existing_symbol) =>
          self.symbol_ids[self.symbol_map[existing_symbol]]
        // Other aliases don't match any existing symbol, and need their own
        // identifiers.
        None => {
          let alias_str = self.str_pool.resolve(alias.value)
          if Generator::insertion_point(self.unique_aliases, candidate => {
              let c = Generator::compare_strs(
                self.str_pool.resolve(candidate.value),
                alias_str,
              )
              if c != 0 {
                c
              } else {
                candidate.is_named.compare(alias.is_named)
              }
            })
            is Some(i) {
            self.unique_aliases.insert(i, alias)
          }
          if alias.is_named {
            "alias_sym_\{self.sanitize_identifier(alias.value)}"
          } else {
            "anon_alias_sym_\{self.sanitize_identifier(alias.value)}"
          }
        }
      }
      if !self.alias_ids.contains(alias) {
        self.alias_ids[alias] = alias_id
      }
    }
  }
  for ix, entry in self.large_character_sets {
    let (symbol, _) = entry
    let mut count = 1
    for j in 0..<ix {
      if self.large_character_sets[j].0 == symbol {
        count += 1
      }
    }
    let constant_name = match symbol {
      Some(symbol) => "\{self.symbol_ids[symbol]}_character_set_\{count}"
      None => "extras_character_set_\{count}"
    }
    self.large_character_set_info.push({ constant_name, })
  }

  // Assign an id to each unique reserved word set
  self.reserved_word_sets.push(TokenSet::new())
  for state in self.parse_table.states {
    let id = match
      self.reserved_word_sets.search_by(set => set == state.reserved_words) {
      Some(ix) => ix
      None => {
        self.reserved_word_sets.push(state.reserved_words.copy())
        self.reserved_word_sets.length() - 1
      }
    }
    self.reserved_word_set_ids_by_parse_state.push(id)
  }
  if self.abi_version >= abi_version_with_reserved_words {
    let supertype_map : Map[String, Array[ChildType]] = Map([])
    for entry in self.supertype_symbol_map.iter() {
      let (supertype, subtypes) = entry
      if self.symbol_ids.get(supertype) is Some(supertype) &&
        !supertype_map.contains(supertype) {
        supertype_map[supertype] = subtypes.copy()
      }
    }
    let keys = supertype_map.keys().collect()
    stable_sort_by(keys, Generator::compare_strs)
    for key in keys {
      self.supertype_map.push((key, supertype_map[key]))
    }
    // Upstream clears `supertype_symbol_map` here to free it; it is never read
    // again, and clearing it would mutate the caller's map.
  }

  // Determine which states should use the "small state" representation, and which should
  // use the normal array representation.
  let threshold = if small_state_threshold <
    self.parse_table.symbols.length() / 2 {
    small_state_threshold
  } else {
    self.parse_table.symbols.length() / 2
  }
  let mut large_state_count = 0
  for i, s in self.parse_table.states {
    if i <= 1 ||
      s.terminal_entries.len() + s.nonterminal_entries.len() > threshold {
      large_state_count += 1
    } else {
      break
    }
  }
  self.large_state_count = large_state_count
}

///|
/// The symbol numbering of upstream's `add_symbol_enum`.
fn Generator::assign_symbol_order(self : Generator) -> Unit {
  self.symbol_order[symbol_end] = 0
  let mut i = 1
  for symbol in self.parse_table.symbols {
    if symbol != symbol_end {
      self.symbol_order[symbol] = i
      i += 1
    }
  }
}

///|
/// The numeric value of the C identifier `symbol_ids[symbol]`.
fn Generator::symbol_value(self : Generator, symbol : Symbol) -> Int32 {
  if symbol == symbol_end_of_nonterminal_extra {
    0
  } else {
    self.symbol_order[symbol]
  }
}

///|
fn Generator::external_token_id(self : Generator, token_idx : Int32) -> String {
  let token = self.syntax_grammar.external_tokens[token_idx]
  "ts_external_token_\{self.sanitize_identifier(token.name)}"
}

///|
fn Generator::assign_symbol_id(
  self : Generator,
  symbol : Symbol,
  used_identifiers : Set[String],
) -> Unit {
  let mut id = ""
  if symbol == symbol_end {
    id = "ts_builtin_sym_end"
  } else {
    let (name, kind) = self.metadata_for_symbol(symbol)
    id = match kind {
      Auxiliary => "aux_sym_\{self.sanitize_identifier(name)}"
      Anonymous => "anon_sym_\{self.sanitize_identifier(name)}"
      Hidden | Named => "sym_\{self.sanitize_identifier(name)}"
    }
    let base = id
    let mut suffix_number = 1
    while used_identifiers.contains(id) {
      suffix_number += 1
      id = base + suffix_number.to_string()
    }
  }
  used_identifiers.add(id)
  self.symbol_ids[symbol] = id
}

///|
fn Generator::field_id(field_name : String) -> String {
  "field_\{field_name}"
}

///|
fn Generator::metadata_for_symbol(
  self : Generator,
  symbol : Symbol,
) -> (StrId, VariableType) {
  match symbol.kind {
    End | EndOfNonTerminalExtra => (end_name_id, Hidden)
    NonTerminal => {
      let variable = self.syntax_grammar.variables[symbol.index]
      (variable.name, variable.kind)
    }
    Terminal => {
      let variable = self.lexical_grammar.variables[symbol.index]
      (variable.name, variable.kind)
    }
    External => {
      let token = self.syntax_grammar.external_tokens[symbol.index]
      (token.name, token.kind)
    }
  }
}

///|
fn Generator::symbols_for_alias(
  self : Generator,
  alias : Alias,
) -> Array[Symbol] {
  self.parse_table.symbols.filter(symbol => {
    match self.default_aliases.get(symbol) {
      Some(default_alias) => default_alias == alias
      None => {
        let (name, kind) = self.metadata_for_symbol(symbol)
        name == alias.value && kind == alias.kind()
      }
    }
  })
}

///|
/// Rust's `{:0width$x}`.
fn Generator::hex(value : Int32, width : Int32) -> String {
  let digits = value.to_string(radix=16)
  if digits.length() >= width {
    digits
  } else {
    "0".repeat(width - digits.length()) + digits
  }
}

///|
fn Generator::sanitize_identifier(self : Generator, name : StrId) -> String {
  let name = self.str_pool.resolve(name)
  let result = StringBuilder()
  // Upstream checks `result.ends_with('_')`; track the last pushed character.
  let mut last : Char? = None
  for c in name {
    if (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' {
      result.write_char(c)
      last = Some(c)
    } else {
      let code = c.to_int()
      let replacement = match c {
        ' ' if name.length() == 1 => "SPACE"
        '~' => "TILDE"
        '`' => "BQUOTE"
        '!' => "BANG"
        '@' => "AT"
        '#' => "POUND"
        '$' => "DOLLAR"
        '%' => "PERCENT"
        '^' => "CARET"
        '&' => "AMP"
        '*' => "STAR"
        '(' => "LPAREN"
        ')' => "RPAREN"
        '-' => "DASH"
        '+' => "PLUS"
        '=' => "EQ"
        '{' => "LBRACE"
        '}' => "RBRACE"
        '[' => "LBRACK"
        ']' => "RBRACK"
        '\\' => "BSLASH"
        '|' => "PIPE"
        ':' => "COLON"
        ';' => "SEMI"
        '"' => "DQUOTE"
        '\'' => "SQUOTE"
        '<' => "LT"
        '>' => "GT"
        ',' => "COMMA"
        '.' => "DOT"
        '?' => "QMARK"
        '/' => "SLASH"
        '\n' => "LF"
        '\r' => "CR"
        '\t' => "TAB"
        '\u{0}' => "NULL"
        '\u{1}' => "SOH"
        '\u{2}' => "STX"
        '\u{3}' => "ETX"
        '\u{4}' => "EOT"
        '\u{5}' => "ENQ"
        '\u{6}' => "ACK"
        '\u{7}' => "BEL"
        '\u{8}' => "BS"
        '\u{b}' => "VTAB"
        '\u{c}' => "FF"
        '\u{e}' => "SO"
        '\u{f}' => "SI"
        '\u{10}' => "DLE"
        '\u{11}' => "DC1"
        '\u{12}' => "DC2"
        '\u{13}' => "DC3"
        '\u{14}' => "DC4"
        '\u{15}' => "NAK"
        '\u{16}' => "SYN"
        '\u{17}' => "ETB"
        '\u{18}' => "CAN"
        '\u{19}' => "EM"
        '\u{1a}' => "SUB"
        '\u{1b}' => "ESC"
        '\u{1c}' => "FS"
        '\u{1d}' => "GS"
        '\u{1e}' => "RS"
        '\u{1f}' => "US"
        '\u{7f}' => "DEL"
        '\u{feff}' => "BOM"
        _ if code >= 0x80 && code <= 0xFFFF => {
          result.write_string("u\{Generator::hex(code, 4)}")
          last = Some('0')
          continue
        }
        _ if code >= 0x10000 => {
          result.write_string("U\{Generator::hex(code, 8)}")
          last = Some('0')
          continue
        }
        // ' ' in a longer name
        _ => continue
      }
      if last is Some(l) && l != '_' {
        result.write_char('_')
      }
      result.write_string(replacement)
      last = Some('A')
    }
  }
  result.to_string()
}

///|
/// Upstream `sanitize_string`, applied to the resolved string.
fn Generator::sanitize_str(name : String) -> String {
  let result = StringBuilder()
  for c in name {
    let code = c.to_int()
    match c {
      '"' => result.write_string("\\\"")
      '?' => result.write_string("\\?")
      '\\' => result.write_string("\\\\")
      '\u{7}' => result.write_string("\\a")
      '\u{8}' => result.write_string("\\b")
      '\u{b}' => result.write_string("\\v")
      '\u{c}' => result.write_string("\\f")
      '\n' => result.write_string("\\n")
      '\r' => result.write_string("\\r")
      '\t' => result.write_string("\\t")
      '\u{0}' => result.write_string("\\0")
      _ if code >= 0x01 && code <= 0x1f =>
        result.write_string("\\x\{Generator::hex(code, 2)}")
      _ if code >= 0x7f && code <= 0xFFFF =>
        result.write_string("\\u\{Generator::hex(code, 4)}")
      _ if code >= 0x10000 =>
        result.write_string("\\U\{Generator::hex(code, 8)}")
      _ => result.write_char(c)
    }
  }
  result.to_string()
}

///|
/// Returns a String of C code for the given components of a parser.
///
/// * `name` - the name of the language
/// * `tables` - the generated parse and lex tables for the language
/// * `syntax_grammar` - the syntax grammar extracted from the language's grammar
/// * `lexical_grammar` - the lexical grammar extracted from the language's grammar
/// * `default_aliases` - the global rename rules: the keys are symbols that are
///   *always* aliased in the same way, and the values are the aliases that are
///   applied to those symbols.
/// * `str_pool` - the backing pool for `StrId`-identified strings within
///   `syntax_grammar`, `lexical_grammar`, and `default_aliases`.
/// * `abi_version` - the language ABI version that should be generated.
pub fn render_c_code(
  name : StrId,
  tables : Tables,
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  default_aliases : AliasMap,
  str_pool : StrPool,
  abi_version : Int32,
  semantic_version : (Int32, Int32, Int32)?,
  supertype_symbol_map : @sorted_map.SortedMap[Symbol, Array[ChildType]],
) -> String raise {
  Generator::new(
    name, tables, syntax_grammar, lexical_grammar, default_aliases, str_pool, abi_version,
    semantic_version, supertype_symbol_map,
  )
  .generate()
  .print_c()
}

///|
/// The portable equivalent of `render_c_code`: the same tables, computed by the
/// same code, as a `@language.Language` value instead of C source.
pub fn render_language(
  name : StrId,
  tables : Tables,
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  default_aliases : AliasMap,
  str_pool : StrPool,
  abi_version : Int32,
  semantic_version : (Int32, Int32, Int32)?,
  supertype_symbol_map : @sorted_map.SortedMap[Symbol, Array[ChildType]],
) -> @language.Language raise {
  Generator::new(
    name, tables, syntax_grammar, lexical_grammar, default_aliases, str_pool, abi_version,
    semantic_version, supertype_symbol_map,
  )
  .generate()
  .to_language()
}
