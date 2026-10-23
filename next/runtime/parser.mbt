// Port of tree-sitter lib/src/parser.c.

///|
let max_version_count : Int32 = 6

///|
let max_version_count_overflow : Int32 = 4

///|
let max_summary_depth : Int32 = 16

///|
let max_cost_difference : UInt32 = 18U * error_cost_per_skipped_tree

///|
let op_count_per_parser_callback_check : Int32 = 100

///|
let ts_tree_state_none_lex : Int32 = 65535

///|
priv struct TokenCache {
  mut token : Subtree
  mut last_external_token : Subtree
  mut byte_index : UInt32
}

///|
pub struct Parser {
  priv lexer : Lexer
  priv stack : Stack
  priv mut language : @language.Language?
  priv mut scanner_factory : ExternalScannerFactory?
  priv reduce_actions : Array[ReduceAction]
  priv mut finished_tree : Subtree
  priv mut trailing_extras : Array[Subtree]
  priv mut trailing_extras2 : Array[Subtree]
  priv token_cache : TokenCache
  priv reusable_node : ReusableNode
  priv mut external_scanner_payload : ExternalScanner?
  priv scanner_buffer : FixedArray[Byte]
  priv mut dot_graph_file : ((String) -> Unit)?
  priv mut accept_count : Int32
  priv mut operation_count : Int32
  priv mut old_tree : Subtree
  priv included_range_differences : Array[Range]
  priv mut parse_options : ParseOptions
  priv mut parse_state : ParseState
  priv mut included_range_difference_index : Int32
  priv mut has_scanner_error : Bool
  priv mut canceled_balancing : Bool
  priv mut has_error : Bool
  /// `tree_pool.tree_stack`, used by subtree balancing.
  priv balance_stack : Array[Subtree]
}

///|
priv struct ErrorStatus {
  cost : UInt32
  node_count : UInt32
  dynamic_precedence : Int32
  is_in_error : Bool
}

///|
priv enum ErrorComparison {
  TakeLeft
  PreferLeft
  None
  PreferRight
  TakeRight
}

///|
fn Parser::lang(self : Parser) -> @language.Language {
  self.language.unwrap()
}

///|
fn Parser::sym_name(self : Parser, symbol : Int32) -> String {
  match self.lang().symbol_name(symbol) {
    Some(name) => name
    None => "(null)"
  }
}

///|
fn Parser::tree_name(self : Parser, tree : Subtree) -> String {
  self.sym_name(tree.symbol())
}

///|
fn Parser::logging(self : Parser) -> Bool {
  self.lexer.logger is Some(_) || self.dot_graph_file is Some(_)
}

///|
/// `LOG(...)` followed by `ts_parser__log`.
fn Parser::log(self : Parser, message : String) -> Unit {
  if self.logging() {
    self.lexer.write_debug_buffer(message)
  }
  // The C debug buffer holds at most 1023 characters.
  let message = truncate_debug_message(message)
  if self.lexer.logger is Some(log) {
    log(Parse, message)
  }
  if self.dot_graph_file is Some(write) {
    let buf = StringBuilder()
    buf.write_string("graph {\nlabel=\"")
    for chr in message {
      if chr == '"' || chr == '\\' {
        buf.write_char('\\')
      }
      buf.write_char(chr)
    }
    buf.write_string("\"\n}\n\n")
    write(buf.to_string())
  }
}

///|
fn truncate_debug_message(message : String) -> String {
  let bytes = @utf8.encode(message)
  if bytes.length() <= 1023 {
    message
  } else {
    @utf8.decode_lossy(bytes[0:1023])
  }
}

///|
/// `LOG_LOOKAHEAD`.
fn Parser::log_lookahead(
  self : Parser,
  symbol_name : String,
  size : UInt32,
) -> Unit {
  let buf = StringBuilder()
  buf.write_string("lexed_lookahead sym:")
  for chr in symbol_name {
    match chr {
      '\t' => buf.write_string("\\t")
      '\n' => buf.write_string("\\n")
      '\u{0B}' => buf.write_string("\\v")
      '\u{0C}' => buf.write_string("\\f")
      '\r' => buf.write_string("\\r")
      '\\' => buf.write_string("\\\\")
      _ => buf.write_char(chr)
    }
  }
  buf.write_string(", size:\{size}")
  self.log(buf.to_string())
}

///|
/// `LOG_STACK()`.
fn Parser::log_stack(self : Parser) -> Unit {
  if self.dot_graph_file is Some(write) {
    let buf = StringBuilder()
    ignore(self.stack.print_dot_graph(self.lang(), buf))
    buf.write_string("\n\n")
    write(buf.to_string())
  }
}

///|
/// `LOG_TREE(tree)`.
fn Parser::log_tree(self : Parser, tree : Subtree) -> Unit {
  if self.dot_graph_file is Some(write) {
    let buf = StringBuilder()
    tree.print_dot_graph(self.lang(), buf)
    buf.write_string("\n")
    write(buf.to_string())
  }
}

///|
fn Parser::breakdown_top_of_stack(self : Parser, version : Int32) -> Bool {
  let mut did_break_down = false
  let mut pending = false
  for ;; {
    let pop = self.stack.pop_pending(version)
    if pop.length() == 0 {
      break
    }
    did_break_down = true
    pending = false
    for i in 0..<pop.length() {
      let slice = pop[i]
      let mut state = self.stack.state(slice.version)
      let parent = slice.subtrees[0]
      for j in 0..<parent.child_count() {
        let child = parent.children()[j]
        pending = child.child_count() > 0
        if child.is_error() {
          state = error_state
        } else if !child.extra() {
          state = self.lang().next_state(state, child.symbol())
        }
        child.retain()
        self.stack.push(slice.version, child, pending, state)
      }
      for j in 1..<slice.subtrees.length() {
        let tree = slice.subtrees[j]
        self.stack.push(slice.version, tree, false, state)
      }
      parent.release()
      if self.logging() {
        self.log("breakdown_top_of_stack tree:\{self.tree_name(parent)}")
      }
      self.log_stack()
    }
    if !pending {
      break
    }
  }
  did_break_down
}

///|
fn Parser::breakdown_lookahead(
  self : Parser,
  lookahead : Subtree,
  state : Int32,
  reusable_node : ReusableNode,
) -> Subtree {
  let mut did_descend = false
  let mut tree = reusable_node.tree()
  while tree.child_count() > 0 && tree.parse_state() != state {
    if self.logging() {
      self.log("state_mismatch sym:\{self.tree_name(tree)}")
    }
    ignore(reusable_node.descend())
    tree = reusable_node.tree()
    did_descend = true
  }
  if did_descend {
    lookahead.release()
    tree.retain()
    tree
  } else {
    lookahead
  }
}

///|
fn compare_versions(a : ErrorStatus, b : ErrorStatus) -> ErrorComparison {
  if !a.is_in_error && b.is_in_error {
    if a.cost < b.cost {
      return TakeLeft
    } else {
      return PreferLeft
    }
  }
  if a.is_in_error && !b.is_in_error {
    if b.cost < a.cost {
      return TakeRight
    } else {
      return PreferRight
    }
  }
  if a.cost < b.cost {
    if (b.cost - a.cost) * (1 + a.node_count) > max_cost_difference {
      return TakeLeft
    } else {
      return PreferLeft
    }
  }
  if b.cost < a.cost {
    if (a.cost - b.cost) * (1 + b.node_count) > max_cost_difference {
      return TakeRight
    } else {
      return PreferRight
    }
  }
  if a.dynamic_precedence > b.dynamic_precedence {
    return PreferLeft
  }
  if b.dynamic_precedence > a.dynamic_precedence {
    return PreferRight
  }
  None
}

///|
fn Parser::version_status(self : Parser, version : Int32) -> ErrorStatus {
  let mut cost = self.stack.error_cost(version)
  let is_paused = self.stack.is_paused(version)
  if is_paused {
    cost += error_cost_per_skipped_tree
  }
  {
    cost,
    node_count: self.stack.node_count_since_error(version),
    dynamic_precedence: self.stack.dynamic_precedence(version),
    is_in_error: is_paused || self.stack.state(version) == error_state,
  }
}

///|
fn Parser::better_version_exists(
  self : Parser,
  version : Int32,
  is_in_error : Bool,
  cost : UInt32,
) -> Bool {
  if !self.finished_tree.is_null() && self.finished_tree.error_cost() <= cost {
    return true
  }
  let position = self.stack.position(version)
  let status : ErrorStatus = {
    cost,
    is_in_error,
    dynamic_precedence: self.stack.dynamic_precedence(version),
    node_count: self.stack.node_count_since_error(version),
  }
  let n = self.stack.version_count()
  for i in 0..<n {
    if i == version ||
      !self.stack.is_active(i) ||
      self.stack.position(i).bytes < position.bytes {
      continue
    }
    let status_i = self.version_status(i)
    match compare_versions(status, status_i) {
      TakeRight => return true
      PreferRight => if self.stack.can_merge(i, version) { return true }
      _ => ()
    }
  }
  false
}

///|
fn Parser::call_main_lex_fn(
  self : Parser,
  lex_mode : @language.LexMode,
) -> Bool {
  run_lex_program(self.lang().lex_fn, self.lexer, lex_mode.lex_state)
}

///|
fn Parser::call_keyword_lex_fn(self : Parser) -> Bool {
  match self.lang().keyword_lex_fn {
    Some(program) => run_lex_program(program, self.lexer, 0)
    None => false
  }
}

///|
fn Parser::external_scanner_create(self : Parser) -> Unit {
  if self.language is Some(language) &&
    language.external_token_count > 0 &&
    self.scanner_factory is Some(create) {
    self.external_scanner_payload = Some(create())
  }
}

///|
fn Parser::external_scanner_destroy(self : Parser) -> Unit {
  if self.language is Some(_) && self.external_scanner_payload is Some(scanner) {
    (scanner.destroy)()
  }
  self.external_scanner_payload = None
}

///|
fn Parser::external_scanner_serialize(self : Parser) -> Int32 {
  let scanner = self.external_scanner_payload.unwrap()
  let length = (scanner.serialize)(self.scanner_buffer)
  if length < 0 || length > @language.tree_sitter_serialization_buffer_size {
    abort("external scanner serialized more than 1024 bytes")
  }
  length
}

///|
fn Parser::external_scanner_deserialize(
  self : Parser,
  external_token : Subtree,
) -> Unit {
  let data = if external_token.is_null() {
    b""[:]
  } else {
    external_token.ptr().external_scanner_state[:]
  }
  (self.external_scanner_payload.unwrap().deserialize)(data)
}

///|
fn Parser::external_scanner_scan(
  self : Parser,
  external_lex_state : Int32,
) -> Bool {
  let valid_external_tokens = self
    .lang()
    .enabled_external_tokens(external_lex_state)
    .unwrap()
  (self.external_scanner_payload.unwrap().scan)(
    self.lexer,
    valid_external_tokens,
  )
}

///|
fn Parser::can_reuse_first_leaf(
  self : Parser,
  state : Int32,
  tree : Subtree,
  table_entry : @language.TableEntry,
) -> Bool {
  let language = self.lang()
  let leaf_symbol = tree.leaf_symbol()
  let leaf_state = tree.leaf_parse_state()
  let current_lex_mode = language.lex_mode_for_state(state)
  let leaf_lex_mode = language.lex_mode_for_state(leaf_state)
  // At the end of a non-terminal extra node, the lexer normally returns NULL,
  // which indicates that the parser should look for a reduce action at symbol
  // `0`. Avoid reusing tokens in this situation to ensure that the same thing
  // happens when incrementally reparsing.
  if current_lex_mode.lex_state == ts_tree_state_none_lex {
    return false
  }
  // If the token was created in a state with the same set of lookaheads, it
  // is reusable.
  if table_entry.action_count > 0 &&
    leaf_lex_mode == current_lex_mode &&
    (
      leaf_symbol != language.keyword_capture_token ||
      (!tree.is_keyword() && tree.parse_state() == state)
    ) {
    return true
  }
  // Empty tokens are not reusable in states with different lookaheads.
  if tree.size().bytes == 0 && leaf_symbol != @language.ts_builtin_sym_end {
    return false
  }
  // If the current state allows external tokens or other tokens that conflict
  // with this token, this token is not reusable.
  current_lex_mode.external_lex_state == 0 && table_entry.is_reusable
}

///|
fn Parser::lex(self : Parser, version : Int32, parse_state : Int32) -> Subtree {
  let language = self.lang()
  let mut lex_mode = language.lex_mode_for_state(parse_state)
  if lex_mode.lex_state == ts_tree_state_none_lex {
    if self.logging() {
      self.log("no_lookahead_after_non_terminal_extra")
    }
    return Null
  }
  let start_position = self.stack.position(version)
  let external_token = self.stack.last_external_token(version)
  let mut found_external_token = false
  let mut error_mode = parse_state == error_state
  let mut skipped_error = false
  let mut called_get_column = false
  let mut first_error_character = 0
  let mut error_start_position = length_zero()
  let mut error_end_position = length_zero()
  let mut lookahead_end_byte : UInt32 = 0
  let mut external_scanner_state_len = 0
  let mut external_scanner_state_changed = false
  self.lexer.reset(start_position)
  for ;; {
    let mut found_token = false
    let current_position = self.lexer.current_position
    let column_data_value = self.lexer.column_data.value
    let column_data_valid = self.lexer.column_data.valid
    if lex_mode.external_lex_state != 0 {
      if self.logging() {
        self.log(
          "lex_external state:\{lex_mode.external_lex_state}, row:\{current_position.extent.row}, column:\{current_position.extent.column}",
        )
      }
      self.lexer.start()
      self.external_scanner_deserialize(external_token)
      found_token = self.external_scanner_scan(lex_mode.external_lex_state)
      called_get_column = called_get_column || self.lexer.did_get_column
      if self.has_scanner_error {
        return Null
      }
      lookahead_end_byte = self.lexer.finish(lookahead_end_byte)
      if found_token {
        external_scanner_state_len = self.external_scanner_serialize()
        external_scanner_state_changed = !external_scanner_state_eq(
          external_token.external_scanner_state(),
          buffer_prefix(self.scanner_buffer, external_scanner_state_len),
        )
        // Avoid infinite loops caused by the external scanner returning empty
        // tokens. Empty tokens are needed in some circumstances, e.g.
        // indent/dedent tokens in Python. Ignore the following classes of
        // empty tokens:
        //
        // * Tokens produced during error recovery. When recovering from an
        //   error, all tokens are allowed, so it's easy to accidentally return
        //   unwanted empty tokens.
        // * Tokens that are marked as 'extra' in the grammar. These don't
        //   change the parse state, so they would definitely cause an infinite
        //   loop.
        if self.lexer.token_end_position.bytes <= current_position.bytes &&
          !external_scanner_state_changed {
          let symbol = language.external_scanner.symbol_map[self.lexer.result_symbol]
          let next_parse_state = language.next_state(parse_state, symbol)
          let token_is_extra = next_parse_state == parse_state
          if error_mode ||
            !self.stack.has_advanced_since_error(version) ||
            token_is_extra {
            if self.logging() {
              self.log(
                "ignore_empty_external_token symbol:\{self.sym_name(language.external_scanner.symbol_map[self.lexer.result_symbol])}",
              )
            }
            found_token = false
          }
        }
      }
      if found_token {
        found_external_token = true
        break
      }
      self.lexer.reset(current_position)
      self.lexer.column_data.value = column_data_value
      self.lexer.column_data.valid = column_data_valid
    }
    if self.logging() {
      self.log(
        "lex_internal state:\{lex_mode.lex_state}, row:\{current_position.extent.row}, column:\{current_position.extent.column}",
      )
    }
    self.lexer.start()
    found_token = self.call_main_lex_fn(lex_mode)
    lookahead_end_byte = self.lexer.finish(lookahead_end_byte)
    if found_token {
      break
    }
    if !error_mode {
      error_mode = true
      lex_mode = language.lex_mode_for_state(error_state)
      self.lexer.reset(start_position)
      continue
    }
    if !skipped_error {
      if self.logging() {
        self.log("skip_unrecognized_character")
      }
      skipped_error = true
      error_start_position = self.lexer.token_start_position
      error_end_position = self.lexer.token_start_position
      first_error_character = self.lexer.lookahead
    }
    if self.lexer.current_position.bytes == error_end_position.bytes {
      if self.lexer.eof() {
        self.lexer.result_symbol = @language.ts_builtin_sym_error
        break
      }
      self.lexer.advance(false)
    }
    error_end_position = self.lexer.current_position
  }
  let result = if skipped_error {
    let padding = length_sub(error_start_position, start_position)
    let size = length_sub(error_end_position, error_start_position)
    let lookahead_bytes = lookahead_end_byte - error_end_position.bytes
    Subtree::new_error(
      first_error_character, padding, size, lookahead_bytes, parse_state, language,
    )
  } else {
    let mut is_keyword = false
    let mut symbol = self.lexer.result_symbol
    let padding = length_sub(self.lexer.token_start_position, start_position)
    let size = length_sub(
      self.lexer.token_end_position,
      self.lexer.token_start_position,
    )
    let lookahead_bytes = lookahead_end_byte -
      self.lexer.token_end_position.bytes
    if found_external_token {
      symbol = language.external_scanner.symbol_map[symbol]
    } else if symbol == language.keyword_capture_token && symbol != 0 {
      let end_byte = self.lexer.token_end_position.bytes
      self.lexer.reset(self.lexer.token_start_position)
      self.lexer.start()
      is_keyword = self.call_keyword_lex_fn()
      if is_keyword &&
        self.lexer.token_end_position.bytes == end_byte &&
        (
          language.has_actions(parse_state, self.lexer.result_symbol) ||
          language.is_reserved_word(parse_state, self.lexer.result_symbol)
        ) {
        symbol = self.lexer.result_symbol
      }
    }
    let result = Subtree::new_leaf(
      symbol, padding, size, lookahead_bytes, parse_state, found_external_token,
      called_get_column, is_keyword, language,
    )
    if found_external_token {
      let data = result.ptr()
      data.external_scanner_state = buffer_prefix(
        self.scanner_buffer,
        external_scanner_state_len,
      )
      data.has_external_scanner_state_change = external_scanner_state_changed
    }
    result
  }
  if self.logging() {
    self.log_lookahead(self.tree_name(result), result.total_size().bytes)
  }
  result
}

///|
fn Parser::get_cached_token(
  self : Parser,
  state : Int32,
  position : UInt32,
  last_external_token : Subtree,
) -> (Subtree, @language.TableEntry?) {
  let cache = self.token_cache
  if !cache.token.is_null() &&
    cache.byte_index == position &&
    cache.last_external_token.external_scanner_state_eq(last_external_token) {
    let table_entry = self.lang().table_entry(state, cache.token.symbol())
    if self.can_reuse_first_leaf(state, cache.token, table_entry) {
      cache.token.retain()
      return (cache.token, Some(table_entry))
    }
    return (Null, Some(table_entry))
  }
  (Null, None)
}

///|
fn Parser::set_cached_token(
  self : Parser,
  byte_index : UInt32,
  last_external_token : Subtree,
  token : Subtree,
) -> Unit {
  let cache = self.token_cache
  if !token.is_null() {
    token.retain()
  }
  if !last_external_token.is_null() {
    last_external_token.retain()
  }
  if !cache.token.is_null() {
    cache.token.release()
  }
  if !cache.last_external_token.is_null() {
    cache.last_external_token.release()
  }
  cache.token = token
  cache.byte_index = byte_index
  cache.last_external_token = last_external_token
}

///|
fn Parser::has_included_range_difference(
  self : Parser,
  start_position : UInt32,
  end_position : UInt32,
) -> Bool {
  range_array_intersects(
    self.included_range_differences,
    self.included_range_difference_index,
    start_position,
    end_position,
  )
}

///|
/// `ts_parser__reuse_node`. Returns the reused node, the possibly updated
/// state, and the table entry it computed (if any).
fn Parser::reuse_node(
  self : Parser,
  version : Int32,
  state : Int32,
  position : UInt32,
  last_external_token : Subtree,
) -> (Subtree, Int32, @language.TableEntry?) {
  let mut state = state
  let mut table_entry : @language.TableEntry? = None
  for ;; {
    let result = self.reusable_node.tree()
    if result.is_null() {
      break
    }
    let byte_offset = self.reusable_node.byte_offset()
    let mut end_byte_offset = byte_offset + result.total_bytes()
    // Do not reuse an EOF node if the included ranges array has changes later
    // on in the file.
    if result.is_eof() {
      end_byte_offset = 0xFFFFFFFFU
    }
    if byte_offset > position {
      if self.logging() {
        self.log("before_reusable_node symbol:\{self.tree_name(result)}")
      }
      break
    }
    if byte_offset < position {
      if self.logging() {
        self.log("past_reusable_node symbol:\{self.tree_name(result)}")
      }
      if end_byte_offset <= position || !self.reusable_node.descend() {
        self.reusable_node.advance()
      }
      continue
    }
    if !self.reusable_node.last_external_token.external_scanner_state_eq(
        last_external_token,
      ) {
      if self.logging() {
        self.log(
          "reusable_node_has_different_external_scanner_state symbol:\{self.tree_name(result)}",
        )
      }
      self.reusable_node.advance()
      continue
    }
    let reason = if result.has_changes() {
      Some("has_changes")
    } else if result.is_error() {
      Some("is_error")
    } else if result.missing() {
      Some("is_missing")
    } else if result.is_fragile() {
      Some("is_fragile")
    } else if self.has_included_range_difference(
        byte_offset,
        if result.is_eof() {
          end_byte_offset
        } else {
          end_byte_offset + result.lookahead_bytes()
        },
      ) {
      Some("contains_different_included_range")
    } else {
      None
    }
    if reason is Some(reason) {
      if self.logging() {
        self.log("cant_reuse_node_\{reason} tree:\{self.tree_name(result)}")
      }
      if !self.reusable_node.descend() {
        self.reusable_node.advance()
        ignore(self.breakdown_top_of_stack(version))
        state = self.stack.state(version)
      }
      continue
    }
    let leaf_symbol = result.leaf_symbol()
    let entry = self.lang().table_entry(state, leaf_symbol)
    table_entry = Some(entry)
    if !self.can_reuse_first_leaf(state, result, entry) {
      if self.logging() {
        self.log(
          "cant_reuse_node symbol:\{self.tree_name(result)}, first_leaf_symbol:\{self.sym_name(leaf_symbol)}",
        )
      }
      self.reusable_node.advance_past_leaf()
      break
    }
    if self.logging() {
      self.log("reuse_node symbol:\{self.tree_name(result)}")
    }
    result.retain()
    return (result, state, table_entry)
  }
  (Null, state, table_entry)
}

///|
/// Determine if a given tree should be replaced by an alternative tree.
///
/// The decision is based on the trees' error costs (if any), their dynamic
/// precedence, and finally, as a default, by a recursive comparison of the
/// trees' symbols.
fn Parser::select_tree(self : Parser, left : Subtree, right : Subtree) -> Bool {
  if left.is_null() {
    return true
  }
  if right.is_null() {
    return false
  }
  if right.error_cost() < left.error_cost() {
    if self.logging() {
      self.log(
        "select_smaller_error symbol:\{self.tree_name(right)}, over_symbol:\{self.tree_name(left)}",
      )
    }
    return true
  }
  if left.error_cost() < right.error_cost() {
    if self.logging() {
      self.log(
        "select_smaller_error symbol:\{self.tree_name(left)}, over_symbol:\{self.tree_name(right)}",
      )
    }
    return false
  }
  if right.dynamic_precedence() > left.dynamic_precedence() {
    if self.logging() {
      self.log(
        "select_higher_precedence symbol:\{self.tree_name(right)}, prec:\{right.dynamic_precedence()}, over_symbol:\{self.tree_name(left)}, other_prec:\{left.dynamic_precedence()}",
      )
    }
    return true
  }
  if left.dynamic_precedence() > right.dynamic_precedence() {
    if self.logging() {
      self.log(
        "select_higher_precedence symbol:\{self.tree_name(left)}, prec:\{left.dynamic_precedence()}, over_symbol:\{self.tree_name(right)}, other_prec:\{right.dynamic_precedence()}",
      )
    }
    return false
  }
  if left.error_cost() > 0 {
    return true
  }
  let comparison = Subtree::compare_to(left, right)
  match comparison {
    -1 => {
      if self.logging() {
        self.log(
          "select_earlier symbol:\{self.tree_name(left)}, over_symbol:\{self.tree_name(right)}",
        )
      }
      false
    }
    1 => {
      if self.logging() {
        self.log(
          "select_earlier symbol:\{self.tree_name(right)}, over_symbol:\{self.tree_name(left)}",
        )
      }
      true
    }
    _ => {
      if self.logging() {
        self.log(
          "select_existing symbol:\{self.tree_name(left)}, over_symbol:\{self.tree_name(right)}",
        )
      }
      false
    }
  }
}

///|
/// Determine if a given tree's children should be replaced by an alternative
/// array of children.
fn Parser::select_children(
  self : Parser,
  left : Subtree,
  children : Array[Subtree],
) -> Bool {
  // A temporary node over a copy of the children. It is never released and
  // does not retain the children, like upstream's scratch tree.
  let scratch_tree = Subtree::new_node(
    left.symbol(),
    children.copy(),
    0,
    self.lang(),
  )
  self.select_tree(left, scratch_tree)
}

///|
fn Parser::shift(
  self : Parser,
  version : Int32,
  state : Int32,
  lookahead : Subtree,
  extra : Bool,
) -> Unit {
  let is_leaf = lookahead.child_count() == 0
  let mut subtree_to_push = lookahead
  if extra != lookahead.extra() && is_leaf {
    let result = lookahead.make_mut()
    subtree_to_push = result.set_extra(extra)
  }
  self.stack.push(version, subtree_to_push, !is_leaf, state)
  if subtree_to_push.has_external_tokens() {
    self.stack.set_last_external_token(
      version,
      subtree_to_push.last_external_token(),
    )
  }
}

///|
fn Parser::reduce(
  self : Parser,
  version : Int32,
  symbol : Int32,
  count : Int32,
  dynamic_precedence : Int32,
  production_id : Int32,
  is_fragile : Bool,
  end_of_non_terminal_extra : Bool,
) -> Int32 {
  let language = self.lang()
  let initial_version_count = self.stack.version_count()
  // Pop the given number of nodes from the given version of the parse stack.
  // If stack versions have previously merged, then there may be more than one
  // path back through the stack. For each path, create a new parent node to
  // contain the popped children, and push it onto the stack in place of the
  // children.
  let pop = self.stack.pop_count(version, count)
  let mut removed_version_count = 0
  let halted_version_count = self.stack.halted_version_count()
  let mut i = 0
  while i < pop.length() {
    let slice = pop[i]
    let slice_version = slice.version - removed_version_count
    // This is where new versions are added to the parse stack. The versions
    // will all be sorted and truncated at the end of the outer parsing loop.
    // Allow the maximum version count to be temporarily exceeded, but only by
    // a limited threshold.
    if slice_version >
      max_version_count + max_version_count_overflow + halted_version_count {
      self.stack.remove_version(slice_version)
      subtree_array_delete(slice.subtrees)
      removed_version_count += 1
      while i + 1 < pop.length() {
        if self.logging() {
          self.log("aborting reduce with too many versions")
        }
        let next_slice = pop[i + 1]
        if next_slice.version != slice.version {
          break
        }
        subtree_array_delete(next_slice.subtrees)
        i += 1
      }
      i += 1
      continue
    }
    // Extra tokens on top of the stack should not be included in this new
    // parent node. They will be re-pushed onto the stack after the parent node
    // is created and pushed.
    let children = slice.subtrees
    subtree_array_remove_trailing_extras(children, self.trailing_extras)
    let mut parent = Subtree::new_node(
      symbol, children, production_id, language,
    )
    // This pop operation may have caused multiple stack versions to collapse
    // into one, because they all diverged from a common state. In that case,
    // choose one of the arrays of trees to be the parent node's children, and
    // delete the rest of the tree arrays.
    while i + 1 < pop.length() {
      let next_slice = pop[i + 1]
      if next_slice.version != slice.version {
        break
      }
      i += 1
      let next_slice_children = next_slice.subtrees
      subtree_array_remove_trailing_extras(
        next_slice_children,
        self.trailing_extras2,
      )
      if self.select_children(parent, next_slice_children) {
        subtree_array_clear(self.trailing_extras)
        parent.release()
        let swap = self.trailing_extras
        self.trailing_extras = self.trailing_extras2
        self.trailing_extras2 = swap
        parent = Subtree::new_node(
          symbol, next_slice_children, production_id, language,
        )
      } else {
        self.trailing_extras2.clear()
        subtree_array_delete(next_slice.subtrees)
      }
    }
    let state = self.stack.state(slice_version)
    let next_state = language.next_state(state, symbol)
    let p = parent.ptr()
    if end_of_non_terminal_extra && next_state == state {
      p.extra = true
    }
    if is_fragile || pop.length() > 1 || initial_version_count > 1 {
      p.fragile_left = true
      p.fragile_right = true
      p.parse_state = ts_tree_state_none
    } else {
      p.parse_state = state
    }
    p.dynamic_precedence += dynamic_precedence
    // Push the parent node onto the stack, along with any extra tokens that
    // were previously on top of the stack.
    self.stack.push(slice_version, parent, false, next_state)
    for j in 0..<self.trailing_extras.length() {
      self.stack.push(slice_version, self.trailing_extras[j], false, next_state)
    }
    for j in 0..<slice_version {
      if j == version {
        continue
      }
      if self.stack.merge(j, slice_version) {
        removed_version_count += 1
        break
      }
    }
    i += 1
  }
  // Return the first new stack version that was created.
  if self.stack.version_count() > initial_version_count {
    initial_version_count
  } else {
    stack_version_none
  }
}

///|
fn Parser::accept(self : Parser, version : Int32, lookahead : Subtree) -> Unit {
  self.stack.push(version, lookahead, false, 1)
  let pop = self.stack.pop_all(version)
  for i in 0..<pop.length() {
    let trees = pop[i].subtrees
    let mut root = Subtree::Null
    for j = trees.length() - 1; j >= 0; j = j - 1 {
      let tree = trees[j]
      if !tree.extra() {
        let children = tree.children()
        for child in children {
          child.retain()
        }
        trees.remove(j) |> ignore
        for k, child in children {
          trees.insert(j + k, child)
        }
        root = Subtree::new_node(
          tree.symbol(),
          trees,
          tree.ptr().production_id,
          self.lang(),
        )
        tree.release()
        break
      }
    }
    self.accept_count += 1
    if !self.finished_tree.is_null() {
      if self.select_tree(self.finished_tree, root) {
        self.finished_tree.release()
        self.finished_tree = root
      } else {
        root.release()
      }
    } else {
      self.finished_tree = root
    }
  }
  self.stack.remove_version(pop[0].version)
  self.stack.halt(version)
}

///|
fn Parser::process_candidate_recovery_actions(
  self : Parser,
  actions : ArrayView[@language.ParseActionEntry],
) -> Bool {
  let mut has_shift_action = false
  for action in actions {
    match action {
      Shift(extra~, repetition~, ..) =>
        if !extra && !repetition {
          has_shift_action = true
        }
      Recover => has_shift_action = true
      Reduce(symbol~, child_count~, dynamic_precedence~, production_id~) =>
        if child_count > 0 {
          reduce_action_set_add(self.reduce_actions, {
            symbol,
            count: child_count,
            dynamic_precedence,
            production_id,
          })
        }
      _ => ()
    }
  }
  has_shift_action
}

///|
fn Parser::do_all_potential_reductions(
  self : Parser,
  starting_version : Int32,
  lookahead_symbol : Int32,
) -> Bool {
  let language = self.lang()
  let initial_version_count = self.stack.version_count()
  let mut can_shift_lookahead_symbol = false
  let mut version = starting_version
  let mut i = 0
  for ;; {
    let version_count = self.stack.version_count()
    if version >= version_count {
      break
    }
    let mut merged = false
    for j in initial_version_count..<version {
      if self.stack.merge(j, version) {
        merged = true
        break
      }
    }
    if merged {
      i += 1
      continue
    }
    let state = self.stack.state(version)
    let mut has_shift_action = false
    self.reduce_actions.clear()
    if lookahead_symbol != 0 {
      has_shift_action = self.process_candidate_recovery_actions(
        language.actions(state, lookahead_symbol),
      )
    } else {
      let iter = language.lookaheads(state)
      while iter.next() {
        // only terminal tokens are valid lookaheads for reduction decisions
        if iter.current_symbol() == @language.ts_builtin_sym_end ||
          iter.current_symbol() >= language.token_count {
          continue
        }
        if self.process_candidate_recovery_actions(iter.actions()) {
          has_shift_action = true
        }
      }
      // Sort reduce_actions by symbol descending to ensure deterministic
      // ordering (insertion sort, as upstream).
      let actions = self.reduce_actions
      for j in 1..<actions.length() {
        let key = actions[j]
        let mut k = j - 1
        while k >= 0 && actions[k].symbol < key.symbol {
          actions[k + 1] = actions[k]
          k -= 1
        }
        actions[k + 1] = key
      }
    }
    let mut reduction_version = stack_version_none
    for j in 0..<self.reduce_actions.length() {
      let action = self.reduce_actions[j]
      reduction_version = self.reduce(
        version,
        action.symbol,
        action.count,
        action.dynamic_precedence,
        action.production_id,
        true,
        false,
      )
    }
    if has_shift_action {
      can_shift_lookahead_symbol = true
    } else if reduction_version != stack_version_none && i < max_version_count {
      self.stack.renumber_version(reduction_version, version)
      i += 1
      continue
    } else if lookahead_symbol != 0 {
      self.stack.remove_version(version)
      // Removing this version shifts the next reduction version into its
      // slot. Check that version before advancing.
      i += 1
      continue
    }
    if version == starting_version {
      version = version_count
    } else {
      version += 1
    }
    i += 1
  }
  can_shift_lookahead_symbol
}

///|
fn Parser::recover_to_state(
  self : Parser,
  version : Int32,
  depth : Int32,
  goal_state : Int32,
) -> Bool {
  let pop = self.stack.pop_count(version, depth)
  let mut previous_version = stack_version_none
  let mut i = 0
  while i < pop.length() {
    let slice = pop[i]
    if slice.version == previous_version {
      subtree_array_delete(slice.subtrees)
      ignore(pop.remove(i))
      continue
    }
    if self.stack.state(slice.version) != goal_state {
      self.stack.halt(slice.version)
      subtree_array_delete(slice.subtrees)
      ignore(pop.remove(i))
      continue
    }
    let error_trees = self.stack.pop_error(slice.version)
    if error_trees.length() > 0 {
      let error_tree = error_trees[0]
      let error_child_count = error_tree.child_count()
      if error_child_count > 0 {
        let nested = []
        for j in 0..<error_child_count {
          let child = error_tree.children()[j]
          child.retain()
          nested.push(child)
        }
        let nested_error = Subtree::new_node(
          @language.ts_builtin_sym_error_repeat,
          nested,
          0,
          self.lang(),
        )
        slice.subtrees.insert(0, nested_error)
      }
      subtree_array_delete(error_trees)
    }
    subtree_array_remove_trailing_extras(slice.subtrees, self.trailing_extras)
    if slice.subtrees.length() > 0 {
      let error = Subtree::new_error_node(slice.subtrees, true, self.lang())
      self.stack.push(slice.version, error, false, goal_state)
    }
    for j in 0..<self.trailing_extras.length() {
      let tree = self.trailing_extras[j]
      self.stack.push(slice.version, tree, false, goal_state)
    }
    previous_version = slice.version
    i += 1
  }
  previous_version != stack_version_none
}

///|
fn Parser::recover(self : Parser, version : Int32, lookahead : Subtree) -> Unit {
  let language = self.lang()
  let mut lookahead = lookahead
  let mut did_recover = false
  let previous_version_count = self.stack.version_count()
  let position = self.stack.position(version)
  let summary = self.stack.get_summary(version)
  let node_count_since_error = self.stack.node_count_since_error(version)
  let current_error_cost = self.stack.error_cost(version)
  // When the parser is in the error state, there are two strategies for
  // recovering with a given lookahead token:
  // 1. Find a previous state on the stack in which that lookahead token would
  //    be valid. Then, create a new stack version that is in that state
  //    again. This entails popping all of the subtrees that have been pushed
  //    onto the stack since that previous state, and wrapping them in an
  //    ERROR node.
  // 2. Wrap the lookahead token in an ERROR node, push that ERROR node onto
  //    the stack, and move on to the next lookahead token, remaining in the
  //    error state.
  //
  // First, try the strategy 1. Upon entering the error state, the parser
  // recorded a summary of the previous parse states and their depths. Look at
  // each state in the summary, to see if the current lookahead token would be
  // valid in that state.
  if summary is Some(summary) && !lookahead.is_error() {
    for i in 0..<summary.length() {
      let entry = summary[i]
      if entry.state == error_state {
        continue
      }
      if entry.position.bytes == position.bytes {
        continue
      }
      let mut depth = entry.depth
      if node_count_since_error > 0 {
        depth += 1
      }
      // Do not recover in ways that create redundant stack versions.
      let mut would_merge = false
      for j in 0..<previous_version_count {
        if self.stack.state(j) == entry.state &&
          self.stack.position(j).bytes == position.bytes {
          would_merge = true
          break
        }
      }
      if would_merge {
        continue
      }
      // Do not recover if the result would clearly be worse than some
      // existing stack version.
      let new_cost = current_error_cost +
        entry.depth.reinterpret_as_uint() * error_cost_per_skipped_tree +
        (position.bytes - entry.position.bytes) * error_cost_per_skipped_char +
        (position.extent.row - entry.position.extent.row) *
        error_cost_per_skipped_line
      if self.better_version_exists(version, false, new_cost) {
        break
      }
      // If the current lookahead token is valid in some previous state,
      // recover to that state. Then stop looking for further recoveries.
      if language.has_actions(entry.state, lookahead.symbol()) {
        if self.recover_to_state(version, depth, entry.state) {
          did_recover = true
          if self.logging() {
            self.log("recover_to_previous state:\{entry.state}, depth:\{depth}")
          }
          self.log_stack()
          break
        }
      }
    }
  }
  // In the process of attempting to recover, some stack versions may have
  // been created and subsequently halted. Remove those versions.
  let mut i = previous_version_count
  while i < self.stack.version_count() {
    if !self.stack.is_active(i) {
      if self.logging() {
        self.log("removed paused version:\{i}")
      }
      self.stack.remove_version(i)
      i -= 1
      self.log_stack()
    }
    i += 1
  }
  // If the parser is still in the error state at the end of the file, just
  // wrap everything in an ERROR node and terminate.
  if lookahead.is_eof() {
    if self.logging() {
      self.log("recover_eof")
    }
    let parent = Subtree::new_error_node([], false, language)
    self.stack.push(version, parent, false, 1)
    self.accept(version, lookahead)
    return
  }
  // If strategy 1 succeeded, a new stack version will have been created which
  // is able to handle the current lookahead token. Now, in addition, try
  // strategy 2 described above: skip the current lookahead token by wrapping
  // it in an ERROR node.

  // Don't pursue this additional strategy if there are already too many
  // stack versions.
  if did_recover && self.stack.version_count() > max_version_count {
    self.stack.halt(version)
    lookahead.release()
    return
  }
  if did_recover && lookahead.has_external_scanner_state_change() {
    self.stack.halt(version)
    lookahead.release()
    return
  }
  // Do not recover if the result would clearly be worse than some existing
  // stack version.
  let new_cost = current_error_cost +
    error_cost_per_skipped_tree +
    lookahead.total_bytes() * error_cost_per_skipped_char +
    lookahead.total_size().extent.row * error_cost_per_skipped_line
  if self.better_version_exists(version, false, new_cost) {
    self.stack.halt(version)
    lookahead.release()
    return
  }
  // If the current lookahead token is an extra token, mark it as extra. This
  // means it won't be counted in error cost calculations.
  let actions = language.actions(1, lookahead.symbol())
  let n = actions.length()
  if n > 0 && actions[n - 1] is Shift(extra=true, ..) {
    let mutable_lookahead = lookahead.make_mut()
    lookahead = mutable_lookahead.set_extra(true)
  }
  // Wrap the lookahead token in an ERROR.
  if self.logging() {
    self.log("skip_token symbol:\{self.tree_name(lookahead)}")
  }
  let children = [lookahead]
  let mut error_repeat = Subtree::new_node(
    @language.ts_builtin_sym_error_repeat, children, 0, language,
  )
  // If other tokens have already been skipped, so there is already an ERROR
  // at the top of the stack, then pop that ERROR off the stack and wrap the
  // two ERRORs together into one larger ERROR.
  if node_count_since_error > 0 {
    let pop = self.stack.pop_count(version, 1)
    // If multiple stack versions have merged at this point, just pick one of
    // the errors arbitrarily and discard the rest.
    if pop.length() > 1 {
      for i in 1..<pop.length() {
        subtree_array_delete(pop[i].subtrees)
      }
      while self.stack.version_count() > pop[0].version + 1 {
        self.stack.remove_version(pop[0].version + 1)
      }
    }
    self.stack.renumber_version(pop[0].version, version)
    pop[0].subtrees.push(error_repeat)
    error_repeat = Subtree::new_node(
      @language.ts_builtin_sym_error_repeat,
      pop[0].subtrees,
      0,
      language,
    )
  }
  // Push the new ERROR onto the stack.
  self.stack.push(version, error_repeat, false, error_state)
  if lookahead.has_external_tokens() {
    self.stack.set_last_external_token(version, lookahead.last_external_token())
  }
  let mut has_error = true
  for i in 0..<self.stack.version_count() {
    let status = self.version_status(i)
    if !status.is_in_error {
      has_error = false
      break
    }
  }
  self.has_error = has_error
}

///|
fn Parser::handle_error(
  self : Parser,
  version : Int32,
  lookahead : Subtree,
) -> Unit {
  let language = self.lang()
  let mut lookahead = lookahead
  let previous_version_count = self.stack.version_count()
  // Perform any reductions that can happen in this state, regardless of the
  // lookahead. After skipping one or more invalid tokens, the parser might
  // find a token that would have allowed a reduction to take place.
  ignore(self.do_all_potential_reductions(version, 0))
  let version_count = self.stack.version_count()
  let position = self.stack.position(version)
  // Push a discontinuity onto the stack. Merge all of the stack versions that
  // were created in the previous step.
  let mut did_insert_missing_token = false
  let mut v = version
  while v < version_count {
    if !did_insert_missing_token {
      let state = self.stack.state(v)
      let token_count = language.token_count & 0xFFFF
      for missing_symbol in 1..<token_count {
        let state_after_missing_symbol = language.next_state(
          state, missing_symbol,
        )
        if state_after_missing_symbol == 0 ||
          state_after_missing_symbol == state {
          continue
        }
        if language.has_reduce_action(
            state_after_missing_symbol,
            lookahead.leaf_symbol(),
          ) {
          // In case the parser is currently outside of any included range, the
          // lexer will snap to the beginning of the next included range. The
          // missing token's padding must be assigned to position it within the
          // next included range.
          self.lexer.reset(position)
          self.lexer.mark_end()
          let padding = length_sub(self.lexer.token_end_position, position)
          let lookahead_bytes = lookahead.total_bytes() +
            lookahead.lookahead_bytes()
          let version_with_missing_tree = self.stack.copy_version(v)
          let missing_tree = Subtree::new_missing_leaf(
            missing_symbol, state, padding, lookahead_bytes, language,
          )
          self.stack.push(
            version_with_missing_tree, missing_tree, false, state_after_missing_symbol,
          )
          if self.do_all_potential_reductions(
              version_with_missing_tree,
              lookahead.leaf_symbol(),
            ) {
            if self.logging() {
              self.log(
                "recover_with_missing symbol:\{self.sym_name(missing_symbol)}, state:\{self.stack.state(version_with_missing_tree)}",
              )
            }
            did_insert_missing_token = true
            break
          }
        }
      }
    }
    self.stack.push(v, Null, false, error_state)
    v = if v == version { previous_version_count } else { v + 1 }
  }
  for _ in previous_version_count..<version_count {
    let did_merge = self.stack.merge(version, previous_version_count)
    ignore(did_merge)
  }
  self.stack.record_summary(version, max_summary_depth)
  // Begin recovery with the current lookahead node, rather than waiting for
  // the next turn of the parse loop. This ensures that the tree accounts for
  // the current lookahead token's "lookahead bytes" value, which describes how
  // far the lexer needed to look ahead beyond the content of the token in
  // order to recognize it.
  if lookahead.child_count() > 0 {
    lookahead = self.breakdown_lookahead(
      lookahead,
      error_state,
      self.reusable_node,
    )
  }
  self.recover(version, lookahead)
  self.log_stack()
}

///|
fn Parser::check_progress(
  self : Parser,
  lookahead : Subtree?,
  position : UInt32?,
  operations : Int32,
) -> Bool {
  self.operation_count += operations
  if self.operation_count >= op_count_per_parser_callback_check {
    self.operation_count = 0
  }
  if position is Some(position) {
    self.parse_state = {
      current_byte_offset: position,
      has_error: self.has_error,
    }
  }
  if self.operation_count == 0 &&
    self.parse_options.progress_callback is Some(callback) &&
    callback(self.parse_state) {
    if lookahead is Some(lookahead) && !lookahead.is_null() {
      lookahead.release()
    }
    return false
  }
  true
}

///|
fn Parser::advance(
  self : Parser,
  version : Int32,
  allow_node_reuse : Bool,
) -> Bool {
  let language = self.lang()
  let mut state = self.stack.state(version)
  let position = self.stack.position(version).bytes
  let last_external_token = self.stack.last_external_token(version)
  let mut did_reuse = true
  let mut lookahead = Subtree::Null
  let mut table_entry : @language.TableEntry = {
    actions_start: 0,
    action_count: 0,
    is_reusable: false,
  }
  // If possible, reuse a node from the previous syntax tree.
  if allow_node_reuse {
    let (result, new_state, entry) = self.reuse_node(
      version, state, position, last_external_token,
    )
    lookahead = result
    state = new_state
    if entry is Some(entry) {
      table_entry = entry
    }
  }
  // If no node from the previous syntax tree could be reused, then try to
  // reuse the token previously returned by the lexer.
  if lookahead.is_null() {
    did_reuse = false
    let (result, entry) = self.get_cached_token(
      state, position, last_external_token,
    )
    lookahead = result
    if entry is Some(entry) {
      table_entry = entry
    }
  }
  let mut needs_lex = lookahead.is_null()
  for ;; {
    // Otherwise, re-run the lexer.
    if needs_lex {
      needs_lex = false
      lookahead = self.lex(version, state)
      if self.has_scanner_error {
        return false
      }
      if !lookahead.is_null() {
        self.set_cached_token(position, last_external_token, lookahead)
        table_entry = language.table_entry(state, lookahead.symbol())
      } else {
        // When parsing a non-terminal extra, a null lookahead indicates the
        // end of the rule. The reduction is stored in the EOF table entry.
        // After the reduction, the lexer needs to be run again.
        table_entry = language.table_entry(state, @language.ts_builtin_sym_end)
      }
    }
    // If a progress callback was provided, then check every time a fixed
    // number of parse actions has been processed.
    if !self.check_progress(Some(lookahead), Some(position), 1) {
      return false
    }
    // Process each parse action for the current lookahead token in the
    // current state. If there are multiple actions, then this is an ambiguous
    // state. REDUCE actions always create a new stack version, whereas SHIFT
    // actions update the existing stack version and terminate this loop.
    let mut did_reduce = false
    let mut last_reduction_version = stack_version_none
    let actions = language.actions_of(table_entry)
    for i in 0..<table_entry.action_count {
      match actions[i] {
        Shift(state=shift_state, extra~, repetition~) => {
          if repetition {
            continue
          }
          let mut next_state = 0
          if extra {
            next_state = state
            if self.logging() {
              self.log("shift_extra")
            }
          } else {
            next_state = shift_state
            if self.logging() {
              self.log("shift state:\{next_state}")
            }
          }
          if lookahead.child_count() > 0 {
            lookahead = self.breakdown_lookahead(
              lookahead,
              state,
              self.reusable_node,
            )
            next_state = language.next_state(state, lookahead.symbol())
          }
          self.shift(version, next_state, lookahead, extra)
          if did_reuse {
            self.reusable_node.advance()
          }
          return true
        }
        Reduce(symbol~, child_count~, dynamic_precedence~, production_id~) => {
          let is_fragile = table_entry.action_count > 1
          let end_of_non_terminal_extra = lookahead.is_null()
          if self.logging() {
            self.log(
              "reduce sym:\{self.sym_name(symbol)}, child_count:\{child_count}",
            )
          }
          let reduction_version = self.reduce(
            version, symbol, child_count, dynamic_precedence, production_id, is_fragile,
            end_of_non_terminal_extra,
          )
          did_reduce = true
          if reduction_version != stack_version_none {
            last_reduction_version = reduction_version
          }
        }
        Accept => {
          if self.logging() {
            self.log("accept")
          }
          self.accept(version, lookahead)
          return true
        }
        Recover => {
          if lookahead.child_count() > 0 {
            lookahead = self.breakdown_lookahead(
              lookahead,
              error_state,
              self.reusable_node,
            )
          }
          self.recover(version, lookahead)
          if did_reuse {
            self.reusable_node.advance()
          }
          return true
        }
        Entry(..) => ()
      }
    }
    // If a reduction was performed, then replace the current stack version
    // with one of the stack versions created by a reduction, and continue
    // processing this version of the stack with the same lookahead symbol.
    if last_reduction_version != stack_version_none {
      self.stack.renumber_version(last_reduction_version, version)
      self.log_stack()
      state = self.stack.state(version)
      // At the end of a non-terminal extra rule, the lexer will return a null
      // subtree, because the parser needs to perform a fixed reduction
      // regardless of the lookahead node. After performing that reduction,
      // (and completing the non-terminal extra rule) run the lexer again based
      // on the current parse state.
      if lookahead.is_null() {
        needs_lex = true
      } else {
        table_entry = language.table_entry(state, lookahead.leaf_symbol())
      }
      continue
    }
    // A reduction was performed, but was merged into an existing stack
    // version. This version can be discarded.
    if did_reduce {
      if !lookahead.is_null() {
        lookahead.release()
      }
      self.stack.halt(version)
      return true
    }
    // If the current lookahead token is a keyword that is not valid, but the
    // default word token *is* valid, then treat the lookahead token as the
    // word token instead.
    if lookahead.is_keyword() &&
      lookahead.symbol() != language.keyword_capture_token &&
      !language.is_reserved_word(state, lookahead.symbol()) {
      table_entry = language.table_entry(state, language.keyword_capture_token)
      if table_entry.action_count > 0 {
        if self.logging() {
          self.log(
            "switch from_keyword:\{self.tree_name(lookahead)}, to_word_token:\{self.sym_name(language.keyword_capture_token)}",
          )
        }
        let mutable_lookahead = lookahead.make_mut()
        lookahead = mutable_lookahead.set_symbol(
          language.keyword_capture_token,
          language,
        )
        continue
      }
    }
    // If the current lookahead token is not valid and the parser is already
    // in the error state, restart the error recovery process.
    if state == error_state {
      self.recover(version, lookahead)
      return true
    }
    // If the current lookahead token is not valid and the previous subtree on
    // the stack was reused from an old tree, then it wasn't actually valid to
    // reuse that previous subtree. Remove it from the stack, and in its place,
    // push each of its children. Then try again to process the current
    // lookahead.
    if self.breakdown_top_of_stack(version) {
      state = self.stack.state(version)
      lookahead.release()
      needs_lex = true
      continue
    }
    // Otherwise, there is definitely an error in this version of the parse
    // stack. Mark this version as paused and continue processing any other
    // stack versions that exist. If some other version advances successfully,
    // then this version can simply be removed. But if all versions end up
    // paused, then error recovery is needed.
    if self.logging() {
      self.log("detect_error lookahead:\{self.tree_name(lookahead)}")
    }
    self.stack.pause(version, lookahead)
    return true
  }
}

///|
fn Parser::condense_stack(self : Parser) -> UInt32 {
  let mut made_changes = false
  let mut min_error_cost = 0xFFFFFFFFU
  let mut i = 0
  while i < self.stack.version_count() {
    // Prune any versions that have been marked for removal.
    if self.stack.is_halted(i) {
      self.stack.remove_version(i)
      continue
    }
    // Keep track of the minimum error cost of any stack version so that it
    // can be returned.
    let status_i = self.version_status(i)
    if !status_i.is_in_error && status_i.cost < min_error_cost {
      min_error_cost = status_i.cost
    }
    // Examine each pair of stack versions, removing any versions that are
    // clearly worse than another version. Ensure that the versions are
    // ordered from most promising to least promising.
    let mut j = 0
    while j < i {
      let status_j = self.version_status(j)
      match compare_versions(status_j, status_i) {
        TakeLeft => {
          made_changes = true
          self.stack.remove_version(i)
          i -= 1
          j = i
        }
        PreferLeft | None =>
          if self.stack.merge(j, i) {
            made_changes = true
            i -= 1
            j = i
          }
        PreferRight => {
          made_changes = true
          if self.stack.merge(j, i) {
            i -= 1
            j = i
          } else {
            self.stack.swap_versions(i, j)
          }
        }
        TakeRight => {
          made_changes = true
          self.stack.remove_version(j)
          i -= 1
          j -= 1
        }
      }
      j += 1
    }
    i += 1
  }
  // Enforce a hard upper bound on the number of stack versions by discarding
  // the least promising versions.
  while self.stack.version_count() > max_version_count {
    self.stack.remove_version(max_version_count)
    made_changes = true
  }
  // If the best-performing stack version is currently paused, or all versions
  // are paused, then resume the best paused version and begin the error
  // recovery process. Otherwise, remove the paused versions.
  if self.stack.version_count() > 0 {
    let mut has_unpaused_version = false
    let mut i = 0
    let mut n = self.stack.version_count()
    while i < n {
      if self.stack.is_paused(i) {
        if !has_unpaused_version && self.accept_count < max_version_count {
          if self.logging() {
            self.log("resume version:\{i}")
          }
          min_error_cost = self.stack.error_cost(i)
          let lookahead = self.stack.resume(i)
          self.handle_error(i, lookahead)
          has_unpaused_version = true
        } else {
          self.stack.remove_version(i)
          made_changes = true
          i -= 1
          n -= 1
        }
      } else {
        has_unpaused_version = true
      }
      i += 1
    }
  }
  if made_changes {
    if self.logging() {
      self.log("condense")
    }
    self.log_stack()
  }
  min_error_cost
}

///|
fn Parser::balance_subtree(self : Parser) -> Bool {
  let finished_tree = self.finished_tree
  // If we haven't canceled balancing in progress before, then we want to
  // clear the tree stack and push the initial finished tree onto it.
  // Otherwise, if we're resuming balancing after a cancellation, we don't want
  // to clear the tree stack.
  if !self.canceled_balancing {
    self.balance_stack.clear()
    if finished_tree.child_count() > 0 && finished_tree.ptr().ref_count == 1 {
      self.balance_stack.push(finished_tree)
    }
  }
  while self.balance_stack.length() > 0 {
    if !self.check_progress(None, None, 1) {
      return false
    }
    let tree = self.balance_stack[self.balance_stack.length() - 1]
    let t = tree.ptr()
    if t.repeat_depth > 0 {
      let child1 = t.children[0]
      let child2 = t.children[t.children.length() - 1]
      let repeat_delta = child1.repeat_depth().to_int64() -
        child2.repeat_depth().to_int64()
      if repeat_delta > 0 {
        let mut n = repeat_delta.to_int()
        let mut i = n / 2
        while i > 0 {
          tree.compress(i, self.lang(), self.balance_stack)
          n -= i
          // Scale the operation count increment proportionately to the
          // compression size.
          let operations = if i >> 4 > 0 { (i >> 4) & 0xFF } else { 1 }
          if !self.check_progress(None, None, operations) {
            return false
          }
          i /= 2
        }
      }
    }
    ignore(self.balance_stack.pop())
    for child in t.children {
      if child.child_count() > 0 && child.ptr().ref_count == 1 {
        self.balance_stack.push(child)
      }
    }
  }
  true
}

///|
fn Parser::has_outstanding_parse(self : Parser) -> Bool {
  self.canceled_balancing ||
  self.external_scanner_payload is Some(_) ||
  self.stack.state(0) != 1 ||
  self.stack.node_count_since_error(0) != 0
}

// Parser - Public

///|
/// `ts_parser_new`.
pub fn Parser::new() -> Parser {
  let lexer = Lexer::new()
  let self : Parser = {
    lexer,
    stack: Stack::new(),
    language: None,
    scanner_factory: None,
    reduce_actions: [],
    finished_tree: Null,
    trailing_extras: [],
    trailing_extras2: [],
    token_cache: { token: Null, last_external_token: Null, byte_index: 0, },
    reusable_node: ReusableNode::new(),
    external_scanner_payload: None,
    // C serializes external scanner state into `self->lexer.debug_buffer`.
    scanner_buffer: lexer.debug_buffer,
    dot_graph_file: None,
    accept_count: 0,
    operation_count: 0,
    old_tree: Null,
    included_range_differences: [],
    parse_options: { progress_callback: None, },
    parse_state: { current_byte_offset: 0, has_error: false, },
    included_range_difference_index: 0,
    has_scanner_error: false,
    canceled_balancing: false,
    has_error: false,
    balance_stack: [],
  }
  self.set_cached_token(0, Null, Null)
  self
}

///|
/// `ts_parser_language`.
pub fn Parser::language(self : Parser) -> @language.Language? {
  self.language
}

///|
/// `ts_parser_set_language`. A language with external tokens needs the
/// factory for its external scanner.
pub fn Parser::set_language(
  self : Parser,
  language : @language.Language?,
  scanner? : ExternalScannerFactory,
) -> Bool {
  self.reset()
  self.language = None
  self.scanner_factory = None
  if language is Some(language) {
    if language.abi_version > @language.language_version ||
      language.abi_version < min_compatible_language_version {
      return false
    }
    if language.external_token_count > 0 && scanner is None {
      return false
    }
  }
  self.language = language
  self.scanner_factory = scanner
  true
}

///|
pub let min_compatible_language_version : Int32 = 13

///|
/// `ts_parser_logger`.
pub fn Parser::logger(self : Parser) -> Logger? {
  self.lexer.logger
}

///|
/// `ts_parser_set_logger`.
pub fn Parser::set_logger(self : Parser, logger : Logger?) -> Unit {
  self.lexer.logger = logger
}

///|
/// `ts_parser_print_dot_graphs`: write parser debugging graphs to `writer`,
/// or stop with `None`.
pub fn Parser::print_dot_graphs(
  self : Parser,
  writer : ((String) -> Unit)?,
) -> Unit {
  self.dot_graph_file = writer
}

///|
/// `ts_parser_set_included_ranges`.
pub fn Parser::set_included_ranges(
  self : Parser,
  ranges : Array[Range],
) -> Bool {
  self.lexer.set_included_ranges(ranges)
}

///|
/// `ts_parser_included_ranges`.
pub fn Parser::included_ranges(self : Parser) -> Array[Range] {
  self.lexer.included_ranges.copy()
}

///|
/// `ts_parser_reset`.
pub fn Parser::reset(self : Parser) -> Unit {
  self.external_scanner_destroy()
  if !self.old_tree.is_null() {
    self.old_tree.release()
    self.old_tree = Null
  }
  self.reusable_node.clear()
  self.lexer.reset(length_zero())
  self.stack.clear()
  self.set_cached_token(0, Null, Null)
  if !self.finished_tree.is_null() {
    self.finished_tree.release()
    self.finished_tree = Null
  }
  self.accept_count = 0
  self.has_scanner_error = false
  self.has_error = false
  self.canceled_balancing = false
  self.parse_options = { progress_callback: None, }
  self.parse_state = { current_byte_offset: 0, has_error: false, }
}

///|
/// `ts_parser_parse`.
pub fn Parser::parse(self : Parser, old_tree : Tree?, input : Input) -> Tree? {
  guard self.language is Some(language) else { return None }
  if old_tree is Some(old) && !physical_equal(old.language, language) {
    return None
  }
  self.lexer.set_input(input)
  self.included_range_differences.clear()
  self.included_range_difference_index = 0
  self.operation_count = 0
  let mut skip_to_balance = false
  if self.has_outstanding_parse() {
    if self.logging() {
      self.log("resume_parsing")
    }
    if self.canceled_balancing {
      skip_to_balance = true
    }
  } else {
    self.external_scanner_create()
    if self.has_scanner_error {
      self.reset()
      return None
    }
    match old_tree {
      Some(old_tree) => {
        old_tree.root().retain()
        self.old_tree = old_tree.root()
        range_array_get_changed_ranges(
          old_tree.included_ranges_ref(),
          self.lexer.included_ranges,
          self.included_range_differences,
        )
        self.reusable_node.reset(old_tree.root())
        if self.logging() {
          self.log("parse_after_edit")
        }
        self.log_tree(self.old_tree)
        for range in self.included_range_differences {
          if self.logging() {
            self.log(
              "different_included_range \{range.start_byte} - \{range.end_byte}",
            )
          }
        }
      }
      None => {
        self.reusable_node.clear()
        if self.logging() {
          self.log("new_parse")
        }
      }
    }
  }
  if !skip_to_balance {
    let mut position : UInt32 = 0
    let mut last_position : UInt32 = 0
    let mut version_count = 0
    for ;; {
      let mut version = 0
      for ;; {
        version_count = self.stack.version_count()
        if version >= version_count {
          break
        }
        let allow_node_reuse = version_count == 1
        while self.stack.is_active(version) {
          if self.logging() {
            self.log(
              "process version:\{version}, version_count:\{self.stack.version_count()}, state:\{self.stack.state(version)}, row:\{self.stack.position(version).extent.row}, col:\{self.stack.position(version).extent.column}",
            )
          }
          if !self.advance(version, allow_node_reuse) {
            if self.has_scanner_error {
              self.reset()
              return None
            }
            return None
          }
          self.log_stack()
          position = self.stack.position(version).bytes
          if position > last_position ||
            (version > 0 && position == last_position) {
            last_position = position
            break
          }
        }
        version += 1
      }
      // After advancing each version of the stack, re-sort the versions by
      // their cost, removing any versions that are no longer worth pursuing.
      let min_error_cost = self.condense_stack()
      // If there's already a finished parse tree that's better than any
      // in-progress version, then terminate parsing. Clear the parse stack to
      // remove any extra references to subtrees within the finished tree,
      // ensuring that these subtrees can be safely mutated in-place for
      // rebalancing.
      if !self.finished_tree.is_null() &&
        self.finished_tree.error_cost() < min_error_cost {
        self.stack.clear()
        break
      }
      while self.included_range_difference_index <
            self.included_range_differences.length() {
        let range = self.included_range_differences[self.included_range_difference_index]
        if range.end_byte <= position {
          self.included_range_difference_index += 1
        } else {
          break
        }
      }
      if version_count == 0 {
        break
      }
    }
  }
  // balance:
  if !self.balance_subtree() {
    self.canceled_balancing = true
    return None
  }
  self.canceled_balancing = false
  if self.logging() {
    self.log("done")
  }
  self.log_tree(self.finished_tree)
  let result = Tree::new(
    self.finished_tree,
    language,
    self.lexer.included_ranges,
  )
  self.finished_tree = Null
  self.reset()
  Some(result)
}

///|
/// `ts_parser_parse_with_options`.
pub fn Parser::parse_with_options(
  self : Parser,
  old_tree : Tree?,
  input : Input,
  parse_options : ParseOptions,
) -> Tree? {
  self.parse_options = parse_options
  let result = self.parse(old_tree, input)
  // Reset parser options before further parse calls.
  self.parse_options = { progress_callback: None, }
  result
}

///|
/// `ts_parser_parse_string_encoding`.
pub fn Parser::parse_string_encoding(
  self : Parser,
  old_tree : Tree?,
  string : Bytes,
  encoding : InputEncoding,
) -> Tree? {
  let length = string.length().reinterpret_as_uint()
  self.parse(old_tree, {
    read: (byte, _) => {
      if byte >= length {
        b""
      } else {
        string[byte.reinterpret_as_int():]
      }
    },
    encoding,
    decode: None,
  })
}

///|
/// `ts_parser_parse_string`.
pub fn Parser::parse_string(
  self : Parser,
  old_tree : Tree?,
  string : Bytes,
) -> Tree? {
  self.parse_string_encoding(old_tree, string, UTF8)
}

///|
fn buffer_prefix(buffer : FixedArray[Byte], length : Int32) -> Bytes {
  Bytes::makei(length, i => buffer[i])
}
