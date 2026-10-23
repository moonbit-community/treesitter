// Port of tree-sitter lib/src/query.c: the `TSQuery` structure and its
// pattern map.

///|
/// A `[offset, offset + length)` slice of one of the query's arrays.
priv struct Slice {
  offset : Int
  length : Int
}

///|
/// PatternEntry - Information about the starting point for matching a
/// particular pattern. These entries are stored in a 'pattern map' - a sorted
/// array that makes it possible to efficiently lookup patterns based on the
/// symbol for their first step.
priv struct PatternEntry {
  step_index : Int
  pattern_index : Int
  is_rooted : Bool
}

///|
priv struct QueryPattern {
  steps : Slice
  predicate_steps : Slice
  start_byte : UInt
  end_byte : UInt
  mut is_non_local : Bool
}

///|
priv struct StepOffset {
  byte_offset : UInt
  step_index : Int
}

///|
/// `TSQueryPredicateStepType`.
pub(all) enum QueryPredicateStepType {
  Done
  Capture
  String
} derive(Eq, Debug)

///|
/// `TSQueryPredicateStep`.
pub(all) struct QueryPredicateStep {
  type_ : QueryPredicateStepType
  value_id : Int
} derive(Eq, Debug)

///|
/// `TSQueryError`.
pub(all) enum QueryErrorKind {
  Syntax
  NodeType
  Field
  Capture
  Structure
  Language
} derive(Eq, Debug)

///|
/// A query compilation error: its kind and the byte offset in the source.
pub suberror QueryError {
  QueryError(kind~ : QueryErrorKind, offset~ : UInt)
} derive(Debug)

///|
/// TSQuery - A tree query, compiled from a string of S-expressions. The query
/// itself is immutable. The mutable state used in the process of executing the
/// query is stored in a `QueryCursor`.
pub struct Query {
  priv captures : SymbolTable
  priv predicate_values : SymbolTable
  priv capture_quantifiers : Array[Array[Quantifier]]
  priv steps : Array[QueryStep]
  priv pattern_map : Array[PatternEntry]
  priv predicate_steps : Array[QueryPredicateStep]
  priv patterns : Array[QueryPattern]
  priv step_offsets : Array[StepOffset]
  priv negated_fields : Array[Int]
  priv string_buffer : Array[Byte]
  priv repeat_symbols_with_rootless_patterns : Array[Int]
  priv language : @language.Language
  priv mut wildcard_root_pattern_count : Int
}

///|
/// The `pattern_map` contains a mapping from symbol values to indices in the
/// `steps` array. For a given syntax node, the `pattern_map` makes it possible
/// to quickly find the starting steps of all of the patterns whose root
/// matches that node.
///
/// The entries are sorted by the patterns' root symbols, and lookups use a
/// binary search. Returns whether the symbol is present, and the index where
/// it is or should be inserted.
fn Query::pattern_map_search(self : Query, needle : Int) -> (Bool, Int) {
  let mut base_index = self.wildcard_root_pattern_count
  let mut size = self.pattern_map.length() - base_index
  if size == 0 {
    return (false, base_index)
  }
  while size > 1 {
    let half_size = size / 2
    let mid_index = base_index + half_size
    let mid_symbol = self.steps[self.pattern_map[mid_index].step_index].symbol
    if needle > mid_symbol {
      base_index = mid_index
    }
    size -= half_size
  }
  let mut symbol = self.steps[self.pattern_map[base_index].step_index].symbol
  if needle > symbol {
    base_index += 1
    if base_index < self.pattern_map.length() {
      symbol = self.steps[self.pattern_map[base_index].step_index].symbol
    }
  }
  (needle == symbol, base_index)
}

///|
/// Insert a new pattern's start index into the pattern map, maintaining the
/// pattern map's ordering invariant.
fn Query::pattern_map_insert(
  self : Query,
  symbol : Int,
  new_entry : PatternEntry,
) -> Unit {
  let (_, found_index) = self.pattern_map_search(symbol)
  let mut index = found_index
  // Ensure that the entries are sorted not only by symbol, but also by
  // pattern_index. This way, states for earlier patterns will be initiated
  // first, which allows the ordering of the states array to be maintained
  // more efficiently.
  while index < self.pattern_map.length() {
    let entry = self.pattern_map[index]
    if self.steps[entry.step_index].symbol == symbol &&
      entry.pattern_index < new_entry.pattern_index {
      index += 1
    } else {
      break
    }
  }
  self.pattern_map.insert(index, new_entry)
}

///|
/// `_array__search_sorted` with an integer key.
fn[T] search_sorted_by(
  array : Array[T],
  key : (T) -> Int,
  needle : Int,
) -> (Int, Bool) {
  search_sorted_with(array, item => key(item) - needle)
}

///|
/// `_array__search_sorted`: `compare(item)` compares an item with the needle.
fn[T] search_sorted_with(array : Array[T], compare : (T) -> Int) -> (Int, Bool) {
  let mut index = 0
  let mut size = array.length()
  if size == 0 {
    return (0, false)
  }
  while size > 1 {
    let half_size = size / 2
    let mid_index = index + half_size
    if compare(array[mid_index]) <= 0 {
      index = mid_index
    }
    size -= half_size
  }
  let comparison = compare(array[index])
  if comparison == 0 {
    (index, true)
  } else if comparison < 0 {
    (index + 1, false)
  } else {
    (index, false)
  }
}

///|
/// `array_insert_sorted_by` for an array of integers.
fn insert_sorted_int(array : Array[Int], value : Int) -> Unit {
  let (index, exists) = search_sorted_by(array, x => x, value)
  if !exists {
    array.insert(index, value)
  }
}
