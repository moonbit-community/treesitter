// Port of the `ts_query_*` accessors in tree-sitter lib/src/query.c.

///|
/// `ts_query_copy`.
pub fn Query::copy(self : Query) -> Query {
  {
    captures: { names: self.captures.names.copy() },
    predicate_values: { names: self.predicate_values.names.copy() },
    capture_quantifiers: self.capture_quantifiers.map(q => q.copy()),
    steps: self.steps.map(s => s.copy()),
    pattern_map: self.pattern_map.copy(),
    predicate_steps: self.predicate_steps.copy(),
    patterns: self.patterns.map(p => { ..p }),
    step_offsets: self.step_offsets.copy(),
    negated_fields: self.negated_fields.copy(),
    string_buffer: self.string_buffer.copy(),
    repeat_symbols_with_rootless_patterns: self.repeat_symbols_with_rootless_patterns.copy(),
    language: self.language,
    wildcard_root_pattern_count: self.wildcard_root_pattern_count,
  }
}

///|
pub fn Query::language(self : Query) -> @language.Language {
  self.language
}

///|
/// `ts_query_pattern_count`.
pub fn Query::pattern_count(self : Query) -> Int {
  self.patterns.length()
}

///|
/// `ts_query_capture_count`.
pub fn Query::capture_count(self : Query) -> Int {
  self.captures.names.length()
}

///|
/// `ts_query_string_count`.
pub fn Query::string_count(self : Query) -> Int {
  self.predicate_values.names.length()
}

///|
/// `ts_query_capture_name_for_id` (the UTF-8 bytes of the name).
pub fn Query::capture_name_bytes_for_id(self : Query, index : Int) -> Bytes {
  self.captures.name_for_id(index)
}

///|
/// `ts_query_capture_name_for_id`.
pub fn Query::capture_name_for_id(self : Query, index : Int) -> String {
  @utf8.decode_lossy(self.captures.name_for_id(index))
}

///|
/// `ts_query_capture_quantifier_for_id`.
pub fn Query::capture_quantifier_for_id(
  self : Query,
  pattern_index : Int,
  capture_index : Int,
) -> Quantifier {
  capture_quantifier_for_id(
    self.capture_quantifiers[pattern_index],
    capture_index,
  )
}

///|
/// `ts_query_string_value_for_id` (the bytes of the value).
pub fn Query::string_value_bytes_for_id(self : Query, index : Int) -> Bytes {
  self.predicate_values.name_for_id(index)
}

///|
/// `ts_query_string_value_for_id`.
pub fn Query::string_value_for_id(self : Query, index : Int) -> String {
  @utf8.decode_lossy(self.predicate_values.name_for_id(index))
}

///|
/// `ts_query_predicates_for_pattern`.
pub fn Query::predicates_for_pattern(
  self : Query,
  pattern_index : Int,
) -> ArrayView[QueryPredicateStep] {
  let slice = self.patterns[pattern_index].predicate_steps
  self.predicate_steps[slice.offset:slice.offset + slice.length]
}

///|
/// `ts_query_start_byte_for_pattern`.
pub fn Query::start_byte_for_pattern(self : Query, pattern_index : Int) -> UInt {
  self.patterns[pattern_index].start_byte
}

///|
/// `ts_query_end_byte_for_pattern`.
pub fn Query::end_byte_for_pattern(self : Query, pattern_index : Int) -> UInt {
  self.patterns[pattern_index].end_byte
}

///|
/// `ts_query_is_pattern_rooted`.
pub fn Query::is_pattern_rooted(self : Query, pattern_index : Int) -> Bool {
  for entry in self.pattern_map {
    if entry.pattern_index == pattern_index {
      if !entry.is_rooted {
        return false
      }
    }
  }
  true
}

///|
/// `ts_query_is_pattern_non_local`.
pub fn Query::is_pattern_non_local(self : Query, pattern_index : Int) -> Bool {
  if pattern_index < self.patterns.length() {
    self.patterns[pattern_index].is_non_local
  } else {
    false
  }
}

///|
/// `ts_query_is_pattern_guaranteed_at_step`.
pub fn Query::is_pattern_guaranteed_at_step(
  self : Query,
  byte_offset : UInt,
) -> Bool {
  let mut step_index = -1
  for step_offset in self.step_offsets {
    if step_offset.byte_offset > byte_offset {
      break
    }
    step_index = step_offset.step_index
  }
  if step_index >= 0 && step_index < self.steps.length() {
    self.steps[step_index].root_pattern_guaranteed
  } else {
    false
  }
}

///|
/// `ts_query__step_is_fallible`.
fn Query::step_is_fallible(self : Query, step_index : Int) -> Bool {
  let mut i = 1
  let step = self.steps[step_index]
  let mut next_step = step
  for ;; {
    next_step = self.steps[step_index + i]
    i += 1
    if !next_step.is_pass_through {
      break
    }
  }
  next_step.depth != pattern_done_marker &&
  (next_step.depth > step.depth ||
  (next_step.depth == step.depth && next_step.is_immediate)) &&
  (!next_step.parent_pattern_guaranteed || step.symbol == wildcard_symbol)
}

///|
/// `ts_query_disable_capture`.
pub fn Query::disable_capture(self : Query, name : StringView) -> Unit {
  // Remove capture information for any pattern step that previously captured
  // with the given name.
  let id = self.captures.id_for_name(@utf8.encode(name))
  if id != -1 {
    for step in self.steps {
      step.remove_capture(id)
    }
  }
}

///|
/// `ts_query_disable_pattern`.
pub fn Query::disable_pattern(self : Query, pattern_index : Int) -> Unit {
  // Remove the given pattern from the pattern map. Its steps will still be
  // in the `steps` array, but they will never be read.
  let mut i = 0
  while i < self.pattern_map.length() {
    if self.pattern_map[i].pattern_index == pattern_index {
      ignore(self.pattern_map.remove(i))
    } else {
      i += 1
    }
  }
}
