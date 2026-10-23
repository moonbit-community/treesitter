// Port of the query parser in tree-sitter lib/src/query.c
// (`ts_query__parse_*` and `ts_query_new`).

///|
/// `TSQueryError` codes as returned by the parser, plus `PARENT_DONE`.
let err_none : Int = 0

///|
let err_syntax : Int = 1

///|
let err_node_type : Int = 2

///|
let err_field : Int = 3

///|
let err_capture : Int = 4

///|
let err_structure : Int = 5

///|
let parent_done : Int = -1

///|
/// The UTF-8 bytes of each symbol name, cached per language.
fn symbol_name_bytes(language : @language.Language, symbol : Int) -> Bytes {
  @utf8.encode(language.symbol_names[symbol])
}

///|
/// `strncmp(name, string, length) == 0 && !name[length]` over bytes.
fn c_name_equals(name : Bytes, string : BytesView) -> Bool {
  let length = string.length()
  for i in 0..<length {
    let a = if i < name.length() { name[i] } else { b'\x00' }
    let b = string[i]
    if a != b {
      return false
    }
    if a == 0 {
      return true
    }
  }
  name.length() <= length || name[length] == 0
}

///|
/// `ts_language_symbol_for_name`, over the UTF-8 bytes of the name.
fn symbol_for_name(
  language : @language.Language,
  string : BytesView,
  is_named : Bool,
) -> Int {
  if is_named && string.length() == 5 && c_name_equals(b"ERROR", string) {
    return @language.ts_builtin_sym_error
  }
  let count = language.symbol_count_with_aliases() & 0xFFFF
  for i in 0..<count {
    let metadata = language.symbol_metadata_of(i)
    if (!metadata.visible && !metadata.supertype) || metadata.named != is_named {
      continue
    }
    if c_name_equals(symbol_name_bytes(language, i), string) {
      return language.public_symbol_map[i]
    }
  }
  0
}

///|
/// C `strncmp` returning the difference of the first differing bytes.
fn c_strncmp(a : BytesView, b : Bytes, n : Int) -> Int {
  for i in 0..<n {
    let ca = if i < a.length() { a[i].to_int() } else { 0 }
    let cb = if i < b.length() { b[i].to_int() } else { 0 }
    if ca != cb {
      return ca - cb
    }
    if ca == 0 {
      return 0
    }
  }
  0
}

///|
/// `ts_language_field_id_for_name`, over the UTF-8 bytes of the name.
fn field_id_for_name(language : @language.Language, name : BytesView) -> Int {
  let count = language.field_count & 0xFFFF
  for i in 1..<(count + 1) {
    let field_name = @utf8.encode(language.field_names[i])
    match c_strncmp(name, field_name, name.length()) {
      0 =>
        if name.length() >= field_name.length() ||
          field_name[name.length()] == 0 {
          return i
        }
      -1 => return 0
      _ => ()
    }
  }
  0
}

///|
fn Query::add_negated_fields(
  self : Query,
  step_index : Int,
  field_ids : Array[Int],
) -> Unit {
  let step = self.steps[step_index]
  let field_count = field_ids.length()
  // The negated field array stores a list of field lists, separated by
  // zeros. Try to find the start index of an existing list that matches this
  // new list.
  let mut failed_match = false
  let mut match_count = 0
  let mut start_i = 0
  for i, existing_field_id in self.negated_fields {
    // At each zero value, terminate the match attempt. If we've exactly
    // matched the new field list, then reuse this index. Otherwise, start
    // over the matching process.
    if existing_field_id == 0 {
      if match_count == field_count {
        step.negated_field_list_id = start_i & 0xFFFF
        return
      } else {
        start_i = i + 1
        match_count = 0
        failed_match = false
      }
    } else if match_count < field_count &&
      existing_field_id == field_ids[match_count] &&
      !failed_match {
      // If the existing list matches our new list so far, then advance to the
      // next element of the new list.
      match_count += 1
    } else {
      // Otherwise, this existing list has failed to match.
      match_count = 0
      failed_match = true
    }
  }
  step.negated_field_list_id = self.negated_fields.length() & 0xFFFF
  for id in field_ids {
    self.negated_fields.push(id)
  }
  self.negated_fields.push(0)
}

///|
fn Query::parse_string_literal(self : Query, stream : Stream) -> Int {
  let string_start = stream.input
  if stream.next != '"' {
    return err_syntax
  }
  ignore(stream.advance())
  let mut prev_position = stream.input
  let mut is_escaped = false
  self.string_buffer.clear()
  let extend = (start : Int, length : Int) => {
    for i in start..<(start + length) {
      self.string_buffer.push(stream.source[i])
    }
  }
  for ;; {
    if is_escaped {
      is_escaped = false
      match stream.next {
        'n' => self.string_buffer.push(b'\n')
        'r' => self.string_buffer.push(b'\r')
        't' => self.string_buffer.push(b'\t')
        '0' => self.string_buffer.push(b'\x00')
        _ => extend(stream.input, stream.next_size)
      }
      prev_position = stream.input + stream.next_size
    } else if stream.next == '\\' {
      extend(prev_position, stream.input - prev_position)
      prev_position = stream.input + 1
      is_escaped = true
    } else if stream.next == '"' {
      extend(prev_position, stream.input - prev_position)
      ignore(stream.advance())
      return err_none
    } else if stream.next == '\n' {
      stream.reset(string_start)
      return err_syntax
    }
    if !stream.advance() {
      stream.reset(string_start)
      return err_syntax
    }
  }
}

///|
fn Query::string_buffer_view(self : Query) -> Bytes {
  Bytes::from_array(self.string_buffer)
}

///|
/// Parse a single predicate associated with a pattern, adding it to the
/// query's internal `predicate_steps` array. Predicates are arbitrary
/// S-expressions associated with a pattern which are meant to be handled at a
/// higher level of abstraction. They can contain '@'-prefixed capture names,
/// double-quoted strings, and bare symbols, which also represent strings.
fn Query::parse_predicate(self : Query, stream : Stream) -> Int {
  if !stream.is_ident_start() {
    return err_syntax
  }
  let predicate_name = stream.input
  stream.scan_identifier()
  if stream.next != '?' && stream.next != '!' {
    return err_syntax
  }
  ignore(stream.advance())
  let id = self.predicate_values.insert_name(
    stream.source[predicate_name:stream.input],
  )
  self.predicate_steps.push({ type_: String, value_id: id })
  stream.skip_whitespace()
  for ;; {
    if stream.next == ')' {
      ignore(stream.advance())
      stream.skip_whitespace()
      self.predicate_steps.push({ type_: Done, value_id: 0 })
      break
    } else if stream.next == '@' {
      // Parse an '@'-prefixed capture name
      ignore(stream.advance())
      // Parse the capture name
      if !stream.is_ident_start() {
        return err_syntax
      }
      let capture_name = stream.input
      stream.scan_identifier()
      // Add the capture id to the first step of the pattern
      let capture_id = self.captures.id_for_name(
        stream.source[capture_name:stream.input],
      )
      if capture_id == -1 {
        stream.reset(capture_name)
        return err_capture
      }
      self.predicate_steps.push({ type_: Capture, value_id: capture_id })
    } else if stream.next == '"' {
      // Parse a string literal
      let e = self.parse_string_literal(stream)
      if e != err_none {
        return e
      }
      let query_id = self.predicate_values.insert_name(self.string_buffer_view())
      self.predicate_steps.push({ type_: String, value_id: query_id })
    } else if stream.is_ident_start() {
      // Parse a bare symbol
      let symbol_start = stream.input
      stream.scan_identifier()
      let query_id = self.predicate_values.insert_name(
        stream.source[symbol_start:stream.input],
      )
      self.predicate_steps.push({ type_: String, value_id: query_id })
    } else {
      return err_syntax
    }
    stream.skip_whitespace()
  }
  err_none
}

///|
/// Read one S-expression pattern from the stream, and incorporate it into the
/// query's internal state machine representation. For nested patterns, this
/// function calls itself recursively.
///
/// The caller is responsible for passing in a dedicated array of capture
/// quantifiers, not shared between different calls.
fn Query::parse_pattern(
  self : Query,
  stream : Stream,
  depth : Int,
  nesting_depth : Int,
  is_immediate : Bool,
  is_inside_alternation : Bool,
  capture_quantifiers : Array[Quantifier],
) -> Int {
  if stream.next == 0 {
    return err_syntax
  }
  if stream.next == ')' || stream.next == ']' {
    return parent_done
  }
  if nesting_depth >= max_query_pattern_depth {
    return err_structure
  }
  let starting_step_index = self.steps.length()
  // Store the byte offset of each step in the query.
  if self.step_offsets.length() == 0 ||
    self.step_offsets[self.step_offsets.length() - 1].step_index !=
    starting_step_index {
    self.step_offsets.push({
      step_index: starting_step_index & 0xFFFF,
      byte_offset: stream.offset().reinterpret_as_uint(),
    })
  }
  if stream.next == '[' {
    // An open bracket is the start of an alternation.
    ignore(stream.advance())
    stream.skip_whitespace()
    // Parse each branch, and add a placeholder step in between the branches.
    let branch_step_indices : Array[Int] = []
    let branch_capture_quantifiers : Array[Quantifier] = []
    for ;; {
      let start_index = self.steps.length()
      let mut e = self.parse_pattern(
        stream,
        depth,
        nesting_depth + 1,
        is_immediate,
        true,
        branch_capture_quantifiers,
      )
      if e == parent_done {
        if stream.next == ']' && branch_step_indices.length() > 0 {
          ignore(stream.advance())
          break
        }
        e = err_syntax
      }
      if e != err_none {
        return e
      }
      if start_index == starting_step_index {
        capture_quantifiers_replace(
          capture_quantifiers,
          branch_capture_quantifiers,
        )
      } else {
        capture_quantifiers_join_all(
          capture_quantifiers,
          branch_capture_quantifiers,
        )
      }
      branch_step_indices.push(start_index)
      self.steps.push(QueryStep::new(0, depth, false))
      branch_capture_quantifiers.clear()
    }
    ignore(self.steps.pop())
    // For all of the branches except for the last one, add the subsequent
    // branch as an alternative, and link the end of the branch to the current
    // end of the steps.
    for i in 0..<(branch_step_indices.length() - 1) {
      let step_index = branch_step_indices[i]
      let next_step_index = branch_step_indices[i + 1]
      let start_step = self.steps[step_index]
      let end_step = self.steps[next_step_index - 1]
      start_step.alternative_index = next_step_index & 0xFFFF
      end_step.alternative_index = self.steps.length() & 0xFFFF
      end_step.is_dead_end = true
    }
  } else if stream.next == '(' {
    // An open parenthesis can be the start of three possible constructs:
    // * A grouped sequence
    // * A predicate
    // * A named node
    ignore(stream.advance())
    stream.skip_whitespace()
    if stream.next == '(' || stream.next == '"' || stream.next == '[' {
      // If this parenthesis is followed by a node, then it represents a
      // grouped sequence.
      let mut child_is_immediate = is_immediate
      let child_capture_quantifiers : Array[Quantifier] = []
      for ;; {
        if stream.next == '.' {
          let anchor_start = stream.input
          child_is_immediate = true
          ignore(stream.advance())
          stream.skip_whitespace()
          // A `.` at a group's end has no sibling to anchor, and a group is
          // not a node, so there is no last child to anchor against.
          if stream.next == ')' {
            stream.reset(anchor_start)
            return err_syntax
          }
        }
        let mut e = self.parse_pattern(
          stream,
          depth,
          nesting_depth + 1,
          child_is_immediate,
          is_inside_alternation,
          child_capture_quantifiers,
        )
        if e == parent_done {
          if stream.next == ')' {
            ignore(stream.advance())
            break
          }
          e = err_syntax
        }
        if e != err_none {
          return e
        }
        capture_quantifiers_add_all(
          capture_quantifiers,
          child_capture_quantifiers,
        )
        child_capture_quantifiers.clear()
        child_is_immediate = false
      }
    } else if stream.next == '.' || stream.next == '#' {
      // A dot/pound character indicates the start of a predicate.
      ignore(stream.advance())
      return self.parse_predicate(stream)
    } else {
      // Otherwise, this parenthesis is the start of a named node.
      let mut symbol = 0
      let mut is_missing = false
      let node_name = stream.input
      if stream.is_ident_start() {
        // Parse a normal node name
        stream.scan_identifier()
        let length = stream.input - node_name
        let name = stream.source[node_name:stream.input]
        if length == 1 && name[0] == '_' {
          // Parse the wildcard symbol
          symbol = wildcard_symbol
        } else if length == 7 && c_strncmp(name, b"MISSING", length) == 0 {
          is_missing = true
          stream.skip_whitespace()
          if stream.is_ident_start() {
            let missing_node_name = stream.input
            stream.scan_identifier()
            symbol = symbol_for_name(
              self.language,
              stream.source[missing_node_name:stream.input],
              true,
            )
            if symbol == 0 {
              stream.reset(missing_node_name)
              return err_node_type
            }
          } else if stream.next == '"' {
            let string_start = stream.input
            let e = self.parse_string_literal(stream)
            if e != err_none {
              return e
            }
            symbol = symbol_for_name(
              self.language,
              self.string_buffer_view(),
              false,
            )
            if symbol == 0 {
              stream.reset(string_start + 1)
              return err_node_type
            }
          } else if stream.next == ')' {
            symbol = wildcard_symbol
          } else {
            stream.reset(stream.input)
            return err_syntax
          }
        } else {
          symbol = symbol_for_name(self.language, name, true)
          if symbol == 0 {
            stream.reset(node_name)
            return err_node_type
          }
        }
      } else {
        return err_syntax
      }
      // Add a step for the node.
      self.steps.push(QueryStep::new(symbol, depth, is_immediate))
      let step = self.steps[self.steps.length() - 1]
      if self.language.symbol_metadata_of(symbol).supertype {
        step.supertype_symbol = step.symbol
        step.symbol = wildcard_symbol
      }
      if is_missing {
        step.is_missing = true
      }
      if symbol == wildcard_symbol {
        step.is_named = true
      }
      // Parse a supertype symbol
      if stream.next == '/' {
        if step.supertype_symbol == 0 {
          stream.reset(node_name - 1) // reset to the start of the node
          return err_structure
        }
        ignore(stream.advance())
        let subtype_node_name = stream.input
        if stream.is_ident_start() {
          // Named node
          stream.scan_identifier()
          step.symbol = symbol_for_name(
            self.language,
            stream.source[subtype_node_name:stream.input],
            true,
          )
        } else if stream.next == '"' {
          // Anonymous leaf node
          let e = self.parse_string_literal(stream)
          if e != err_none {
            return e
          }
          step.symbol = symbol_for_name(
            self.language,
            self.string_buffer_view(),
            false,
          )
        } else {
          return err_syntax
        }
        if step.symbol == 0 {
          stream.reset(subtype_node_name)
          return err_node_type
        }
        // Get all the possible subtypes for the given supertype, and check if
        // the given subtype is valid.
        if self.language.abi_version >=
          @language.language_version_with_reserved_words {
          let subtypes = self.language.subtypes(step.supertype_symbol)
          let subtype_is_valid = subtypes.iter().any(s => s == step.symbol)
          // This subtype is not valid for the given supertype.
          if !subtype_is_valid {
            stream.reset(node_name - 1) // reset to the start of the node
            return err_structure
          }
        }
      }
      stream.skip_whitespace()
      // Parse the child patterns
      let mut child_is_immediate = false
      let mut last_child_step_index = 0
      let negated_field_ids : Array[Int] = []
      let child_capture_quantifiers : Array[Quantifier] = []
      for ;; {
        // Parse a negated field assertion
        if stream.next == '!' {
          ignore(stream.advance())
          stream.skip_whitespace()
          if !stream.is_ident_start() {
            return err_syntax
          }
          let field_name = stream.input
          stream.scan_identifier()
          let field_end = stream.input
          stream.skip_whitespace()
          let field_id = field_id_for_name(
            self.language,
            stream.source[field_name:field_end],
          )
          if field_id == 0 {
            stream.input = field_name
            return err_field
          }
          // Keep the field ids sorted.
          if negated_field_ids.length() < max_negated_field_count {
            negated_field_ids.push(field_id)
          }
          continue
        }
        // Parse a sibling anchor
        if stream.next == '.' {
          child_is_immediate = true
          ignore(stream.advance())
          stream.skip_whitespace()
        }
        let mut step_index = self.steps.length() & 0xFFFF
        let mut e = self.parse_pattern(
          stream,
          depth + 1,
          nesting_depth + 1,
          child_is_immediate,
          is_inside_alternation,
          child_capture_quantifiers,
        )
        // In the event we only parsed a predicate, meaning no new steps were
        // added, then subtract one so we're not indexing past the end of the
        // array
        if step_index == self.steps.length() {
          step_index = (step_index - 1) & 0xFFFF
        }
        if e == parent_done {
          if stream.next == ')' {
            if child_is_immediate {
              if last_child_step_index == 0 {
                return err_syntax
              }
              // Mark this step *and* its alternatives as the last child of
              // the parent.
              let last_child_step = self.steps[last_child_step_index]
              last_child_step.is_last_child = true
              if last_child_step.alternative_index != none &&
                last_child_step.alternative_index < self.steps.length() {
                let mut alternative_step = self.steps[last_child_step.alternative_index]
                alternative_step.is_last_child = true
                while alternative_step.alternative_index != none &&
                      alternative_step.alternative_index < self.steps.length() {
                  alternative_step = self.steps[alternative_step.alternative_index]
                  alternative_step.is_last_child = true
                }
              }
            }
            if negated_field_ids.length() > 0 {
              self.add_negated_fields(starting_step_index, negated_field_ids)
            }
            ignore(stream.advance())
            break
          }
          e = err_syntax
        }
        if e != err_none {
          return e
        }
        capture_quantifiers_add_all(
          capture_quantifiers,
          child_capture_quantifiers,
        )
        last_child_step_index = step_index
        child_is_immediate = false
        child_capture_quantifiers.clear()
      }
    }
  } else if stream.next == '_' {
    // Parse a wildcard pattern
    ignore(stream.advance())
    stream.skip_whitespace()
    // Add a step that matches any kind of node
    self.steps.push(QueryStep::new(wildcard_symbol, depth, is_immediate))
  } else if stream.next == '"' {
    // Parse a double-quoted anonymous leaf node expression
    let string_start = stream.input
    let e = self.parse_string_literal(stream)
    if e != err_none {
      return e
    }
    // Add a step for the node
    let symbol = symbol_for_name(self.language, self.string_buffer_view(), false)
    if symbol == 0 {
      stream.reset(string_start + 1)
      return err_node_type
    }
    self.steps.push(QueryStep::new(symbol, depth, is_immediate))
  } else if stream.is_ident_start() {
    // Parse a field-prefixed pattern
    let field_name = stream.input
    stream.scan_identifier()
    let field_end = stream.input
    stream.skip_whitespace()
    if stream.next != ':' {
      stream.reset(field_name)
      return err_syntax
    }
    ignore(stream.advance())
    stream.skip_whitespace()
    // Parse the pattern
    let field_capture_quantifiers : Array[Quantifier] = []
    let e = self.parse_pattern(
      stream,
      depth,
      nesting_depth + 1,
      is_immediate,
      is_inside_alternation,
      field_capture_quantifiers,
    )
    if e != err_none {
      return if e == parent_done { err_syntax } else { e }
    }
    // Add the field name to the first step of the pattern
    let field_id = field_id_for_name(
      self.language,
      stream.source[field_name:field_end],
    )
    if field_id == 0 {
      stream.input = field_name
      return err_field
    }
    let mut step_index = starting_step_index
    let mut step = self.steps[step_index]
    for ;; {
      step.field = field_id
      if step.alternative_index != none &&
        step.alternative_index > step_index &&
        step.alternative_index < self.steps.length() {
        step_index = step.alternative_index
        step = self.steps[step_index]
      } else {
        break
      }
    }
    capture_quantifiers_add_all(capture_quantifiers, field_capture_quantifiers)
  } else {
    return err_syntax
  }
  stream.skip_whitespace()
  // Parse suffixes modifiers for this pattern
  let mut quantifier = One
  for ;; {
    if stream.next == '+' {
      // Parse the one-or-more operator.
      quantifier = quantifier_join(OneOrMore, quantifier)
      ignore(stream.advance())
      stream.skip_whitespace()
    } else if stream.next == '*' {
      // Parse the zero-or-more repetition operator.
      quantifier = quantifier_join(ZeroOrMore, quantifier)
      ignore(stream.advance())
      stream.skip_whitespace()
    } else if stream.next == '?' {
      // Parse the optional operator.
      quantifier = quantifier_join(ZeroOrOne, quantifier)
      ignore(stream.advance())
      stream.skip_whitespace()
    } else if stream.next == '@' {
      // Parse an '@'-prefixed capture pattern
      ignore(stream.advance())
      if !stream.is_ident_start() {
        return err_syntax
      }
      let capture_name = stream.input
      stream.scan_identifier()
      let capture_end = stream.input
      stream.skip_whitespace()
      // Add the capture id to the first step of the pattern
      let capture_id = self.captures.insert_name(
        stream.source[capture_name:capture_end],
      )
      // Add the capture quantifier
      capture_quantifiers_add_for_id(capture_quantifiers, capture_id, One)
      let mut step_index = starting_step_index
      for ;; {
        let step = self.steps[step_index]
        step.add_capture(capture_id)
        if step.alternative_index != none &&
          step.alternative_index > step_index &&
          step.alternative_index < self.steps.length() {
          step_index = step.alternative_index
        } else {
          break
        }
      }
    } else {
      // No more suffix modifiers
      break
    }
  }
  match quantifier {
    OneOrMore => {
      let repeat_step = QueryStep::new(wildcard_symbol, depth, false)
      repeat_step.is_inside_alternation = is_inside_alternation
      repeat_step.alternative_index = starting_step_index & 0xFFFF
      repeat_step.is_pass_through = true
      self.steps.push(repeat_step)
    }
    ZeroOrMore => {
      let repeat_step = QueryStep::new(wildcard_symbol, depth, false)
      repeat_step.is_inside_alternation = is_inside_alternation
      repeat_step.alternative_index = starting_step_index & 0xFFFF
      repeat_step.is_pass_through = true
      self.steps.push(repeat_step)
      // Stop when `step.alternative_index` is `NONE` or it points to
      // `repeat_step` or beyond. Note that having just been pushed,
      // `repeat_step` occupies slot `self.steps.length() - 1`.
      let mut step = self.steps[starting_step_index]
      while step.alternative_index != none &&
            step.alternative_index < self.steps.length() - 1 {
        step = self.steps[step.alternative_index]
      }
      step.alternative_index = self.steps.length() & 0xFFFF
      step.alternative_is_skip = true
    }
    ZeroOrOne => {
      let mut step = self.steps[starting_step_index]
      while step.alternative_index != none &&
            step.alternative_index < self.steps.length() {
        step = self.steps[step.alternative_index]
      }
      step.alternative_index = self.steps.length() & 0xFFFF
      step.alternative_is_skip = true
    }
    _ => ()
  }
  capture_quantifiers_mul(capture_quantifiers, quantifier)
  err_none
}

///|
fn query_error_kind(code : Int) -> QueryErrorKind {
  match code {
    1 => Syntax
    2 => NodeType
    3 => Field
    4 => Capture
    5 => Structure
    _ => Language
  }
}

///|
/// `ts_query_new`: compile a query from its source (UTF-8 bytes).
pub fn Query::new(
  language : @language.Language,
  source : Bytes,
) -> Query raise QueryError {
  if language.abi_version > @language.language_version ||
    language.abi_version < @runtime.min_compatible_language_version {
    raise QueryError(kind=Language, offset=0)
  }
  let self : Query = {
    steps: [],
    pattern_map: [],
    captures: SymbolTable::new(),
    capture_quantifiers: [],
    predicate_values: SymbolTable::new(),
    predicate_steps: [],
    patterns: [],
    step_offsets: [],
    string_buffer: [],
    negated_fields: [0],
    repeat_symbols_with_rootless_patterns: [],
    wildcard_root_pattern_count: 0,
    language,
  }
  // Parse all of the S-expressions in the given string.
  let stream = Stream::new(source)
  stream.skip_whitespace()
  while stream.input < stream.end {
    let pattern_index = self.patterns.length()
    let mut start_step_index = self.steps.length()
    let start_predicate_step_index = self.predicate_steps.length()
    self.patterns.push({
      steps: { offset: start_step_index, length: 0 },
      predicate_steps: { offset: start_predicate_step_index, length: 0 },
      start_byte: stream.offset().reinterpret_as_uint(),
      end_byte: 0,
      is_non_local: false,
    })
    let capture_quantifiers : Array[Quantifier] = []
    let mut error_type = self.parse_pattern(
      stream, 0, 0, false, false, capture_quantifiers,
    )
    self.steps.push(QueryStep::new(0, pattern_done_marker, false))
    let pattern = self.patterns[self.patterns.length() - 1]
    self.patterns[self.patterns.length() - 1] = {
      ..pattern,
      steps: { offset: start_step_index, length: self.steps.length() - start_step_index },
      predicate_steps: {
        offset: start_predicate_step_index,
        length: self.predicate_steps.length() - start_predicate_step_index,
      },
      end_byte: stream.offset().reinterpret_as_uint(),
    }
    let pattern = self.patterns[self.patterns.length() - 1]
    // If any pattern could not be parsed, then report the error information
    // and terminate.
    if error_type != err_none {
      if error_type == parent_done {
        error_type = err_syntax
      }
      raise QueryError(
        kind=query_error_kind(error_type),
        offset=stream.offset().reinterpret_as_uint(),
      )
    }
    // Maintain a list of capture quantifiers for each pattern
    self.capture_quantifiers.push(capture_quantifiers)
    // Maintain a map that can look up patterns for a given root symbol.
    let mut wildcard_root_alternative_index = none
    for ;; {
      let mut step = self.steps[start_step_index]
      // If a pattern has a wildcard at its root, but it has a non-wildcard
      // child, then optimize the matching process by skipping matching the
      // wildcard. Later, during the matching process, the query cursor will
      // check that there is a parent node, and capture it if necessary.
      if step.symbol == wildcard_symbol && step.depth == 0 && step.field == 0 {
        let second_step = self.steps[start_step_index + 1]
        if second_step.symbol != wildcard_symbol &&
          second_step.depth == 1 &&
          !second_step.is_immediate {
          wildcard_root_alternative_index = step.alternative_index
          start_step_index += 1
          step = second_step
        }
      }
      // Determine whether the pattern has a single root node. This affects
      // decisions about whether or not to start matching the pattern when a
      // query cursor has a range restriction or when immediately within an
      // error node.
      let start_depth = step.depth
      let mut is_rooted = start_depth == 0
      for step_index in (start_step_index + 1)..<self.steps.length() {
        let child_step = self.steps[step_index]
        if child_step.is_dead_end {
          break
        }
        if child_step.depth == start_depth {
          is_rooted = false
          break
        }
      }
      self.pattern_map_insert(step.symbol, {
        step_index: start_step_index & 0xFFFF,
        pattern_index: pattern_index & 0xFFFF,
        is_rooted,
      })
      if step.symbol == wildcard_symbol {
        self.wildcard_root_pattern_count = (self.wildcard_root_pattern_count +
          1) &
          0xFFFF
      }
      // If there are alternatives or options at the root of the pattern, then
      // add multiple entries to the pattern map.
      if step.alternative_index != none {
        start_step_index = step.alternative_index
      } else if wildcard_root_alternative_index != none {
        start_step_index = wildcard_root_alternative_index
        wildcard_root_alternative_index = none
      } else {
        break
      }
    }
    // Fix up quantifier loop-backs within alternations. When a branch of an
    // alternation has a + or * quantifier, the quantifier's pass_through step
    // loops back to the branch's first step. However, the alternation linking
    // assigns that same step's `alternative_index` to point to the _next_
    // branch. This causes the quantifier loop to incorrectly explore other
    // alternation branches, when a quantified branch matches, loops back, and
    // then fails to match. To correct this, we create "clean" copies of the
    // branches' first steps without the link to the next branch. After a
    // quantified branch matches, it loops back to the cleaned copy.
    let pat_start = pattern.steps.offset
    let pat_end = pat_start + pattern.steps.length - 1 // exclude DONE
    for i in pat_start..<pat_end {
      let s = self.steps[i]
      // Ensure this step is a pass_through with a _backward_ alternative (a
      // quantifier loop-back)
      if !s.is_pass_through ||
        !s.is_inside_alternation ||
        s.alternative_index == none ||
        s.alternative_index >= i {
        continue
      }
      let target_idx = s.alternative_index
      let target = self.steps[target_idx]
      // Check if the target has a forward alternative from alternation linking
      let target_alt_index = target.alternative_index
      if target_alt_index == none ||
        target_alt_index <= target_idx ||
        target_alt_index >= pat_end {
        continue
      }
      // Create a clean copy of the target step without the alternation
      // alternative.
      let copy_idx = self.steps.length()
      let copy = target.copy()
      copy.alternative_index = none
      let target_depth = target.depth
      self.steps.push(copy)
      // Add a dead_end that redirects to the pass through step after the
      // target, so the pattern continues correctly after the cleaned copy
      // matches.
      let redirect = QueryStep::new(0, target_depth, false)
      redirect.is_dead_end = true
      redirect.alternative_index = (target_idx + 1) & 0xFFFF
      self.steps.push(redirect)
      // Update the pass_through to loop back to the copy.
      self.steps[i].alternative_index = copy_idx & 0xFFFF
    }
  }
  match self.analyze_patterns() {
    Some(error_offset) => raise QueryError(kind=Structure, offset=error_offset)
    None => ()
  }
  self.string_buffer.clear()
  self
}
