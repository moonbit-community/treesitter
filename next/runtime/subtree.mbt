// Port of tree-sitter lib/src/subtree.h and lib/src/subtree.c.
//
// C distinguishes small leaves stored inline in the `Subtree` word from
// heap-allocated subtrees. The distinction is observable (e.g. `.ptr`
// equality, which fields are stored, when `make_mut` copies), so it is kept:
// `Inline` holds a value, `Heap` a shared mutable record with an explicit
// reference count maintained exactly as upstream's retain/release calls do.

///|
let ts_tree_state_none : Int32 = 65535

///|
let ts_max_inline_tree_length : UInt32 = 255

///|
#valtype
pub(all) struct SubtreeInlineData {
  visible : Bool
  named : Bool
  extra : Bool
  has_changes : Bool
  is_missing : Bool
  is_keyword : Bool
  depends_on_column : Bool
  symbol : Int32
  parse_state : Int32
  padding_columns : UInt32
  padding_rows : UInt32
  lookahead_bytes : UInt32
  padding_bytes : UInt32
  size_bytes : UInt32
} derive(Eq, Debug)

///|
pub(all) struct SubtreeHeapData {
  mut ref_count : Int32
  mut padding : Length
  mut size : Length
  mut lookahead_bytes : UInt32
  mut error_cost : UInt32
  /// The children; `child_count` is its length. Leaves have none.
  mut children : Array[Subtree]
  mut symbol : Int32
  mut parse_state : Int32
  mut visible : Bool
  mut named : Bool
  mut extra : Bool
  mut fragile_left : Bool
  mut fragile_right : Bool
  mut has_changes : Bool
  mut has_external_tokens : Bool
  mut has_external_scanner_state_change : Bool
  mut depends_on_column : Bool
  mut is_missing : Bool
  mut is_keyword : Bool
  // Non-terminal subtrees (`child_count > 0`).
  mut visible_child_count : UInt32
  mut named_child_count : UInt32
  mut visible_descendant_count : UInt32
  mut dynamic_precedence : Int32
  mut repeat_depth : UInt32
  mut production_id : Int32
  mut first_leaf_symbol : Int32
  mut first_leaf_parse_state : Int32
  // External terminal subtrees (`child_count == 0 && has_external_tokens`).
  mut external_scanner_state : Bytes
  // Error terminal subtrees (`child_count == 0 && symbol == error`).
  mut lookahead_char : Int32
  /// Stands in for the C heap address: a unique, stable identity.
  address : Int32
}

///|
/// The fundamental building block of a syntax tree. `Null` is `NULL_SUBTREE`.
pub(all) enum Subtree {
  Null
  Inline(SubtreeInlineData)
  Heap(SubtreeHeapData)
}

///|
/// `MutableSubtree` has the same representation.
pub type MutableSubtree = Subtree

///|
let next_address : Ref[Int32] = Ref(1)

///|
fn fresh_address() -> Int32 {
  let address = next_address.val
  next_address.val += 1
  address
}

///|
fn SubtreeHeapData::empty() -> SubtreeHeapData {
  {
    ref_count: 1,
    padding: length_zero(),
    size: length_zero(),
    lookahead_bytes: 0,
    error_cost: 0,
    children: [],
    symbol: 0,
    parse_state: 0,
    visible: false,
    named: false,
    extra: false,
    fragile_left: false,
    fragile_right: false,
    has_changes: false,
    has_external_tokens: false,
    has_external_scanner_state_change: false,
    depends_on_column: false,
    is_missing: false,
    is_keyword: false,
    visible_child_count: 0,
    named_child_count: 0,
    visible_descendant_count: 0,
    dynamic_precedence: 0,
    repeat_depth: 0,
    production_id: 0,
    first_leaf_symbol: 0,
    first_leaf_parse_state: 0,
    external_scanner_state: b"",
    lookahead_char: 0,
    address: fresh_address(),
  }
}

///|
/// `self.ptr` for a heap subtree. Aborts for inline/null subtrees, which C
/// would dereference as an invalid pointer.
pub fn Subtree::ptr(self : Subtree) -> SubtreeHeapData {
  match self {
    Heap(data) => data
    _ => abort("subtree is not heap allocated")
  }
}

///|
pub fn Subtree::is_inline(self : Subtree) -> Bool {
  self is Inline(_)
}

///|
pub fn Subtree::is_null(self : Subtree) -> Bool {
  self is Null
}

///|
/// `a.ptr == b.ptr`: identity for heap subtrees, bitwise equality for inline
/// subtrees (whose data occupies the pointer word).
pub fn Subtree::ptr_eq(self : Subtree, other : Subtree) -> Bool {
  match (self, other) {
    (Null, Null) => true
    (Inline(a), Inline(b)) => a == b
    (Heap(a), Heap(b)) => physical_equal(a, b)
    _ => false
  }
}

///|
/// A stable identity standing in for the pointer value (`ts_node_id`).
pub fn Subtree::address(self : Subtree) -> Int32 {
  match self {
    Null => 0
    Inline(_) => -1
    Heap(data) => data.address
  }
}

///|
pub fn Subtree::symbol(self : Subtree) -> Int32 {
  match self {
    Inline(d) => d.symbol
    Heap(d) => d.symbol
    Null => abort("null subtree")
  }
}

///|
pub fn Subtree::visible(self : Subtree) -> Bool {
  match self {
    Inline(d) => d.visible
    Heap(d) => d.visible
    Null => abort("null subtree")
  }
}

///|
pub fn Subtree::named(self : Subtree) -> Bool {
  match self {
    Inline(d) => d.named
    Heap(d) => d.named
    Null => abort("null subtree")
  }
}

///|
pub fn Subtree::extra(self : Subtree) -> Bool {
  match self {
    Inline(d) => d.extra
    Heap(d) => d.extra
    Null => abort("null subtree")
  }
}

///|
pub fn Subtree::has_changes(self : Subtree) -> Bool {
  match self {
    Inline(d) => d.has_changes
    Heap(d) => d.has_changes
    Null => abort("null subtree")
  }
}

///|
pub fn Subtree::missing(self : Subtree) -> Bool {
  match self {
    Inline(d) => d.is_missing
    Heap(d) => d.is_missing
    Null => abort("null subtree")
  }
}

///|
pub fn Subtree::is_keyword(self : Subtree) -> Bool {
  match self {
    Inline(d) => d.is_keyword
    Heap(d) => d.is_keyword
    Null => abort("null subtree")
  }
}

///|
pub fn Subtree::parse_state(self : Subtree) -> Int32 {
  match self {
    Inline(d) => d.parse_state
    Heap(d) => d.parse_state
    Null => abort("null subtree")
  }
}

///|
pub fn Subtree::lookahead_bytes(self : Subtree) -> UInt32 {
  match self {
    Inline(d) => d.lookahead_bytes
    Heap(d) => d.lookahead_bytes
    Null => abort("null subtree")
  }
}

///|
pub fn Subtree::children(self : Subtree) -> Array[Subtree] {
  match self {
    Heap(d) => d.children
    _ => []
  }
}

///|
/// `ts_subtree_set_extra`.
pub fn Subtree::set_extra(self : Subtree, is_extra : Bool) -> Subtree {
  match self {
    Inline(d) => Inline({ ..d, extra: is_extra, })
    Heap(d) => {
      d.extra = is_extra
      self
    }
    Null => abort("null subtree")
  }
}

///|
pub fn Subtree::leaf_symbol(self : Subtree) -> Int32 {
  match self {
    Inline(d) => d.symbol
    Heap(d) =>
      if d.children.is_empty() {
        d.symbol
      } else {
        d.first_leaf_symbol
      }
    Null => abort("null subtree")
  }
}

///|
pub fn Subtree::leaf_parse_state(self : Subtree) -> Int32 {
  match self {
    Inline(d) => d.parse_state
    Heap(d) =>
      if d.children.is_empty() {
        d.parse_state
      } else {
        d.first_leaf_parse_state
      }
    Null => abort("null subtree")
  }
}

///|
pub fn Subtree::padding(self : Subtree) -> Length {
  match self {
    Inline(d) =>
      {
        bytes: d.padding_bytes,
        extent: { row: d.padding_rows, column: d.padding_columns, },
      }
    Heap(d) => d.padding
    Null => abort("null subtree")
  }
}

///|
pub fn Subtree::size(self : Subtree) -> Length {
  match self {
    Inline(d) =>
      { bytes: d.size_bytes, extent: { row: 0, column: d.size_bytes, }, }
    Heap(d) => d.size
    Null => abort("null subtree")
  }
}

///|
pub fn Subtree::total_size(self : Subtree) -> Length {
  length_add(self.padding(), self.size())
}

///|
pub fn Subtree::total_bytes(self : Subtree) -> UInt32 {
  self.total_size().bytes
}

///|
pub fn Subtree::child_count(self : Subtree) -> Int32 {
  match self {
    Heap(d) => d.children.length()
    _ => 0
  }
}

///|
pub fn Subtree::repeat_depth(self : Subtree) -> UInt32 {
  match self {
    Heap(d) => d.repeat_depth
    _ => 0
  }
}

///|
pub fn Subtree::is_repetition(self : Subtree) -> Bool {
  match self {
    Heap(d) => !d.named && !d.visible && !d.children.is_empty()
    _ => false
  }
}

///|
pub fn Subtree::visible_descendant_count(self : Subtree) -> UInt32 {
  match self {
    Heap(d) if !d.children.is_empty() => d.visible_descendant_count
    _ => 0
  }
}

///|
pub fn Subtree::visible_child_count(self : Subtree) -> UInt32 {
  if self.child_count() > 0 {
    self.ptr().visible_child_count
  } else {
    0
  }
}

///|
pub fn Subtree::error_cost(self : Subtree) -> UInt32 {
  if self.missing() {
    error_cost_per_missing_tree + error_cost_per_recovery
  } else {
    match self {
      Heap(d) => d.error_cost
      _ => 0
    }
  }
}

///|
pub fn Subtree::dynamic_precedence(self : Subtree) -> Int32 {
  match self {
    Heap(d) if !d.children.is_empty() => d.dynamic_precedence
    _ => 0
  }
}

///|
pub fn Subtree::production_id(self : Subtree) -> Int32 {
  if self.child_count() > 0 {
    self.ptr().production_id
  } else {
    0
  }
}

///|
pub fn Subtree::fragile_left(self : Subtree) -> Bool {
  match self {
    Heap(d) => d.fragile_left
    _ => false
  }
}

///|
pub fn Subtree::fragile_right(self : Subtree) -> Bool {
  match self {
    Heap(d) => d.fragile_right
    _ => false
  }
}

///|
pub fn Subtree::has_external_tokens(self : Subtree) -> Bool {
  match self {
    Heap(d) => d.has_external_tokens
    _ => false
  }
}

///|
pub fn Subtree::has_external_scanner_state_change(self : Subtree) -> Bool {
  match self {
    Heap(d) => d.has_external_scanner_state_change
    _ => false
  }
}

///|
pub fn Subtree::depends_on_column(self : Subtree) -> Bool {
  match self {
    Inline(d) => d.depends_on_column
    Heap(d) => d.depends_on_column
    Null => abort("null subtree")
  }
}

///|
pub fn Subtree::is_fragile(self : Subtree) -> Bool {
  match self {
    Heap(d) => d.fragile_left || d.fragile_right
    _ => false
  }
}

///|
pub fn Subtree::is_error(self : Subtree) -> Bool {
  self.symbol() == @language.ts_builtin_sym_error
}

///|
pub fn Subtree::is_eof(self : Subtree) -> Bool {
  self.symbol() == @language.ts_builtin_sym_end
}

// ExternalScannerState: stored as `Bytes`; upstream's short/long storage is
// an allocation detail.

///|
/// `ts_external_scanner_state_eq`.
pub fn external_scanner_state_eq(state : Bytes, buffer : BytesView) -> Bool {
  state.length() == buffer.length() && state[:] == buffer
}

// SubtreeArray

///|
/// `ts_subtree_array_copy`.
pub fn subtree_array_copy(array : Array[Subtree]) -> Array[Subtree] {
  let dest = array.copy()
  for child in dest {
    child.retain()
  }
  dest
}

///|
/// `ts_subtree_array_clear`.
pub fn subtree_array_clear(array : Array[Subtree]) -> Unit {
  for child in array {
    child.release()
  }
  array.clear()
}

///|
/// `ts_subtree_array_delete`.
pub fn subtree_array_delete(array : Array[Subtree]) -> Unit {
  subtree_array_clear(array)
}

///|
/// `ts_subtree_array_remove_trailing_extras`.
pub fn subtree_array_remove_trailing_extras(
  array : Array[Subtree],
  destination : Array[Subtree],
) -> Unit {
  destination.clear()
  while array.length() > 0 {
    let last = array[array.length() - 1]
    if last.extra() {
      ignore(array.pop())
      destination.push(last)
    } else {
      break
    }
  }
  destination.rev_in_place()
}

///|
/// `ts_subtree_array_reverse`.
pub fn subtree_array_reverse(array : Array[Subtree]) -> Unit {
  array.rev_in_place()
}

// Subtree

///|
fn subtree_can_inline(
  padding : Length,
  size : Length,
  lookahead_bytes : UInt32,
) -> Bool {
  padding.bytes < ts_max_inline_tree_length &&
  padding.extent.row < 16 &&
  padding.extent.column < ts_max_inline_tree_length &&
  size.bytes < ts_max_inline_tree_length &&
  size.extent.row == 0 &&
  size.extent.column < ts_max_inline_tree_length &&
  lookahead_bytes < 16
}

///|
/// `ts_subtree_new_leaf`.
pub fn Subtree::new_leaf(
  symbol : Int32,
  padding : Length,
  size : Length,
  lookahead_bytes : UInt32,
  parse_state : Int32,
  has_external_tokens : Bool,
  depends_on_column : Bool,
  is_keyword : Bool,
  language : @language.Language,
) -> Subtree {
  let metadata = language.symbol_metadata_of(symbol)
  let extra = symbol == @language.ts_builtin_sym_end
  let is_inline = symbol <= 255 &&
    !has_external_tokens &&
    subtree_can_inline(padding, size, lookahead_bytes)
  if is_inline {
    Inline({
      parse_state,
      symbol,
      padding_bytes: padding.bytes,
      padding_rows: padding.extent.row,
      padding_columns: padding.extent.column,
      size_bytes: size.bytes,
      lookahead_bytes,
      visible: metadata.visible,
      named: metadata.named,
      extra,
      has_changes: false,
      is_missing: false,
      is_keyword,
      depends_on_column,
    })
  } else {
    let data = SubtreeHeapData::empty()
    data.padding = padding
    data.size = size
    data.lookahead_bytes = lookahead_bytes
    data.symbol = symbol
    data.parse_state = parse_state
    data.visible = metadata.visible
    data.named = metadata.named
    data.extra = extra
    data.has_external_tokens = has_external_tokens
    data.depends_on_column = depends_on_column
    data.is_keyword = is_keyword
    Heap(data)
  }
}

///|
/// `ts_subtree_set_symbol`.
pub fn Subtree::set_symbol(
  self : Subtree,
  symbol : Int32,
  language : @language.Language,
) -> Subtree {
  let metadata = language.symbol_metadata_of(symbol)
  match self {
    Inline(d) =>
      Inline({ ..d, symbol, named: metadata.named, visible: metadata.visible, })
    Heap(d) => {
      d.symbol = symbol
      d.named = metadata.named
      d.visible = metadata.visible
      self
    }
    Null => abort("null subtree")
  }
}

///|
/// `ts_subtree_new_error`.
pub fn Subtree::new_error(
  lookahead_char : Int32,
  padding : Length,
  size : Length,
  bytes_scanned : UInt32,
  parse_state : Int32,
  language : @language.Language,
) -> Subtree {
  let result = Subtree::new_leaf(
    @language.ts_builtin_sym_error, padding, size, bytes_scanned, parse_state, false,
    false, false, language,
  )
  let data = result.ptr()
  data.fragile_left = true
  data.fragile_right = true
  data.lookahead_char = lookahead_char
  result
}

///|
/// `ts_subtree_clone`.
pub fn Subtree::clone(self : Subtree) -> Subtree {
  let d = self.ptr()
  let result : SubtreeHeapData = { ..d, address: fresh_address(), }
  result.children = d.children.copy()
  if !d.children.is_empty() {
    for child in result.children {
      child.retain()
    }
  }
  result.ref_count = 1
  Heap(result)
}

///|
/// `ts_subtree_make_mut`: take ownership of the subtree. If it has only one
/// owner it is converted directly; otherwise it is copied.
pub fn Subtree::make_mut(self : Subtree) -> Subtree {
  match self {
    Inline(_) => self
    Heap(d) if d.ref_count == 1 => self
    _ => {
      let result = self.clone()
      self.release()
      result
    }
  }
}

///|
/// `ts_subtree_compress`.
pub fn Subtree::compress(
  self : Subtree,
  count : Int32,
  language : @language.Language,
  stack : Array[Subtree],
) -> Unit {
  let initial_stack_size = stack.length()
  let mut tree = self
  let symbol = tree.ptr().symbol
  for _ in 0..<count {
    let t = tree.ptr()
    if t.ref_count > 1 || t.children.length() < 2 {
      break
    }
    let child = t.children[0]
    guard child is Heap(c) &&
      c.children.length() >= 2 &&
      c.ref_count <= 1 &&
      c.symbol == symbol else {
      break
    }
    let grandchild = c.children[0]
    guard grandchild is Heap(g) &&
      g.children.length() >= 2 &&
      g.ref_count <= 1 &&
      g.symbol == symbol else {
      break
    }
    t.children[0] = grandchild
    c.children[0] = g.children[g.children.length() - 1]
    g.children[g.children.length() - 1] = child
    stack.push(tree)
    tree = grandchild
  }
  while stack.length() > initial_stack_size {
    tree = stack.pop().unwrap()
    let child = tree.ptr().children[0]
    let c = child.ptr()
    let grandchild = c.children[c.children.length() - 1]
    grandchild.summarize_children(language)
    child.summarize_children(language)
    tree.summarize_children(language)
  }
}

///|
/// The part of an error node's cost that penalizes the extent it spans, as
/// opposed to the cost of its contents.
fn subtree_error_extent_cost(size : Length) -> UInt32 {
  error_cost_per_recovery +
  error_cost_per_skipped_char * size.bytes +
  error_cost_per_skipped_line * size.extent.row
}

///|
/// `ts_subtree_summarize_children`: assign all of the node's properties that
/// depend on its children.
pub fn Subtree::summarize_children(
  self : Subtree,
  language : @language.Language,
) -> Unit {
  let s = self.ptr()
  s.named_child_count = 0
  s.visible_child_count = 0
  s.error_cost = 0
  s.repeat_depth = 0
  s.visible_descendant_count = 0
  s.has_external_tokens = false
  s.depends_on_column = false
  s.has_external_scanner_state_change = false
  s.dynamic_precedence = 0
  let mut structural_index = 0
  let alias_sequence = language.alias_sequence(s.production_id)
  let mut lookahead_end_byte : UInt32 = 0
  let children = s.children
  for i, child in children {
    if (i == 0 || s.size.extent.row == 0) && child.depends_on_column() {
      s.depends_on_column = true
    }
    if child.has_external_scanner_state_change() {
      s.has_external_scanner_state_change = true
    }
    if i == 0 {
      s.padding = child.padding()
      s.size = child.size()
    } else {
      s.size = length_add(s.size, child.total_size())
    }
    let child_lookahead_end_byte = s.padding.bytes +
      s.size.bytes +
      child.lookahead_bytes()
    if child_lookahead_end_byte > lookahead_end_byte {
      lookahead_end_byte = child_lookahead_end_byte
    }
    let grandchild_count = child.child_count()
    if child.symbol() == @language.ts_builtin_sym_error_repeat {
      // Refund an `_ERROR` child's extent penalty, which this node re-charges
      // as part of its own extent below, so that the grouping is cost-neutral.
      let extent_cost = subtree_error_extent_cost(child.size())
      s.error_cost += child.error_cost() - extent_cost
    } else {
      s.error_cost += child.error_cost()
      if s.symbol == @language.ts_builtin_sym_error ||
        s.symbol == @language.ts_builtin_sym_error_repeat {
        if !child.extra() && !(child.is_error() && grandchild_count == 0) {
          if child.visible() {
            s.error_cost += error_cost_per_skipped_tree
          } else if grandchild_count > 0 {
            s.error_cost += error_cost_per_skipped_tree *
              child.ptr().visible_child_count
          }
        }
      }
    }
    s.dynamic_precedence += child.dynamic_precedence()
    s.visible_descendant_count += child.visible_descendant_count()
    if !child.extra() &&
      child.symbol() != 0 &&
      alias_sequence is Some(offset) &&
      language.alias_sequence_value(offset + structural_index) != 0 {
      s.visible_descendant_count += 1
      s.visible_child_count += 1
      if language.symbol_metadata_of(
          language.alias_sequence_value(offset + structural_index),
        ).named {
        s.named_child_count += 1
      }
    } else if child.visible() {
      s.visible_descendant_count += 1
      s.visible_child_count += 1
      if child.named() {
        s.named_child_count += 1
      }
    } else if grandchild_count > 0 {
      s.visible_child_count += child.ptr().visible_child_count
      s.named_child_count += child.ptr().named_child_count
    }
    if child.has_external_tokens() {
      s.has_external_tokens = true
    }
    if child.is_error() {
      s.fragile_left = true
      s.fragile_right = true
      s.parse_state = ts_tree_state_none
    }
    if !child.extra() {
      structural_index += 1
    }
  }
  s.lookahead_bytes = lookahead_end_byte - s.size.bytes - s.padding.bytes
  if s.symbol == @language.ts_builtin_sym_error ||
    s.symbol == @language.ts_builtin_sym_error_repeat {
    s.error_cost += subtree_error_extent_cost(s.size)
  }
  if children.length() > 0 {
    let first_child = children[0]
    let last_child = children[children.length() - 1]
    s.first_leaf_symbol = first_child.leaf_symbol()
    s.first_leaf_parse_state = first_child.leaf_parse_state()
    if first_child.fragile_left() {
      s.fragile_left = true
    }
    if last_child.fragile_right() {
      s.fragile_right = true
    }
    if children.length() >= 2 &&
      !s.visible &&
      !s.named &&
      first_child.symbol() == s.symbol {
      // `repeat_depth` is a `uint16_t` upstream.
      if first_child.repeat_depth() > last_child.repeat_depth() {
        s.repeat_depth = (first_child.repeat_depth() + 1) & 0xFFFFU
      } else {
        s.repeat_depth = (last_child.repeat_depth() + 1) & 0xFFFFU
      }
    }
  }
}

///|
/// `ts_subtree_new_node`: create a new parent node with the given children.
/// This takes ownership of the children array.
pub fn Subtree::new_node(
  symbol : Int32,
  children : Array[Subtree],
  production_id : Int32,
  language : @language.Language,
) -> Subtree {
  let metadata = language.symbol_metadata_of(symbol)
  let fragile = symbol == @language.ts_builtin_sym_error ||
    symbol == @language.ts_builtin_sym_error_repeat
  let data = SubtreeHeapData::empty()
  data.symbol = symbol
  data.children = children
  data.visible = metadata.visible
  data.named = metadata.named
  data.fragile_left = fragile
  data.fragile_right = fragile
  data.production_id = production_id
  let result = Heap(data)
  result.summarize_children(language)
  result
}

///|
/// `ts_subtree_new_error_node`: this node is treated as 'extra'. Its children
/// are prevented from having any effect on the parse state.
pub fn Subtree::new_error_node(
  children : Array[Subtree],
  extra : Bool,
  language : @language.Language,
) -> Subtree {
  let result = Subtree::new_node(
    @language.ts_builtin_sym_error, children, 0, language,
  )
  result.ptr().extra = extra
  result
}

///|
/// `ts_subtree_new_missing_leaf`.
pub fn Subtree::new_missing_leaf(
  symbol : Int32,
  state : Int32,
  padding : Length,
  lookahead_bytes : UInt32,
  language : @language.Language,
) -> Subtree {
  let result = Subtree::new_leaf(
    symbol,
    padding,
    length_zero(),
    lookahead_bytes,
    state,
    false,
    false,
    false,
    language,
  )
  match result {
    Inline(d) => Inline({ ..d, is_missing: true, })
    Heap(d) => {
      d.is_missing = true
      result
    }
    Null => result
  }
}

///|
/// `ts_subtree_retain`.
pub fn Subtree::retain(self : Subtree) -> Unit {
  match self {
    Heap(d) => d.ref_count += 1
    _ => ()
  }
}

///|
/// `pool->tree_stack` of `ts_subtree_release`: scratch space that is always
/// empty between calls.
let release_stack : Array[SubtreeHeapData] = []

///|
/// `ts_subtree_release`. Memory is reclaimed by the GC; the counts are kept
/// so that `make_mut` and `compress` copy exactly when upstream does.
pub fn Subtree::release(self : Subtree) -> Unit {
  guard self is Heap(d) else { return }
  d.ref_count -= 1
  if d.ref_count != 0 {
    return
  }
  let stack = release_stack
  stack.push(d)
  while stack.pop() is Some(tree) {
    for child in tree.children {
      if child is Heap(c) {
        c.ref_count -= 1
        if c.ref_count == 0 {
          stack.push(c)
        }
      }
    }
  }
}

///|
/// `ts_subtree_compare`.
pub fn Subtree::compare_to(left : Subtree, right : Subtree) -> Int32 {
  let stack = [left, right]
  while stack.length() > 0 {
    let right = stack.pop().unwrap()
    let left = stack.pop().unwrap()
    let mut result = 0
    if left.symbol() < right.symbol() {
      result = -1
    } else if right.symbol() < left.symbol() {
      result = 1
    } else if left.child_count() < right.child_count() {
      result = -1
    } else if right.child_count() < left.child_count() {
      result = 1
    }
    if result != 0 {
      return result
    }
    for i = left.child_count(); i > 0; i = i - 1 {
      stack.push(left.children()[i - 1])
      stack.push(right.children()[i - 1])
    }
  }
  0
}

///|
fn Subtree::set_has_changes(self : Subtree) -> Subtree {
  match self {
    Inline(d) => Inline({ ..d, has_changes: true, })
    Heap(d) => {
      d.has_changes = true
      self
    }
    Null => self
  }
}

///|
priv struct Edit {
  start : Length
  old_end : Length
  new_end : Length
}

///|
/// `ts_subtree_edit`.
pub fn Subtree::edit(self : Subtree, input_edit : InputEdit) -> Subtree {
  let root = [self]
  let stack : Array[(SubtreeSlot, Edit)] = [
    (
      { array: root, index: 0, owner: 0, },
      {
        start: { bytes: input_edit.start_byte, extent: input_edit.start_point, },
        old_end: {
          bytes: input_edit.old_end_byte,
          extent: input_edit.old_end_point,
        },
        new_end: {
          bytes: input_edit.new_end_byte,
          extent: input_edit.new_end_point,
        },
      },
    ),
  ]
  while stack.pop() is Some((slot, edit0)) {
    let mut edit = edit0
    let tree = slot.array[slot.index]
    let is_noop = edit.old_end.bytes == edit.start.bytes &&
      edit.new_end.bytes == edit.start.bytes
    let is_pure_insertion = edit.old_end.bytes == edit.start.bytes
    let parent_depends_on_column = tree.depends_on_column()
    let column_shifted = edit.new_end.extent.column !=
      edit.old_end.extent.column
    let mut size = tree.size()
    let mut padding = tree.padding()
    let total_size = length_add(padding, size)
    let lookahead_bytes = tree.lookahead_bytes()
    let end_byte = total_size.bytes + lookahead_bytes
    if edit.start.bytes > end_byte || (is_noop && edit.start.bytes == end_byte) {
      continue
    }
    if edit.old_end.bytes <= padding.bytes {
      // If the edit is entirely within the space before this subtree, then
      // shift this subtree over according to the edit without changing its size.
      padding = length_add(edit.new_end, length_sub(padding, edit.old_end))
    } else if edit.start.bytes < padding.bytes {
      // If the edit starts in the space before this subtree and extends into
      // this subtree, shrink the subtree's content to compensate for the
      // change in the space before it.
      size = length_saturating_sub(size, length_sub(edit.old_end, padding))
      padding = edit.new_end
    } else if edit.start.bytes < total_size.bytes ||
      (edit.start.bytes == total_size.bytes && is_pure_insertion) {
      // If the edit is within this subtree, resize the subtree to reflect the edit.
      size = length_add(
        length_sub(edit.new_end, padding),
        length_saturating_sub(total_size, edit.old_end),
      )
    }
    let mut result = tree.make_mut()
    match result {
      Inline(d) =>
        if subtree_can_inline(padding, size, lookahead_bytes) {
          result = Inline({
            ..d,
            padding_bytes: padding.bytes,
            padding_rows: padding.extent.row,
            padding_columns: padding.extent.column,
            size_bytes: size.bytes,
          })
        } else {
          let data = SubtreeHeapData::empty()
          data.padding = padding
          data.size = size
          data.lookahead_bytes = lookahead_bytes
          data.symbol = d.symbol
          data.parse_state = d.parse_state
          data.visible = d.visible
          data.named = d.named
          data.extra = d.extra
          data.depends_on_column = d.depends_on_column
          data.is_missing = d.is_missing
          data.is_keyword = d.is_keyword
          result = Heap(data)
        }
      Heap(d) => {
        d.padding = padding
        d.size = size
      }
      Null => ()
    }
    result = result.set_has_changes()
    slot.array[slot.index] = result
    let mut child_left = length_zero()
    let mut child_right = length_zero()
    let children = result.children()
    for i in 0..<children.length() {
      let child = children[i]
      let child_size = child.total_size()
      child_left = child_right
      child_right = length_add(child_left, child_size)
      // If this child ends before the edit, it is not affected.
      if child_right.bytes + child.lookahead_bytes() < edit.start.bytes {
        continue
      }
      // Keep editing child nodes until a node is reached that starts after
      // the edit. Also, if this node's validity depends on its column
      // position, then continue invalidating child nodes until reaching a
      // line break.
      if (
          child_left.bytes > edit.old_end.bytes ||
          (
            child_left.bytes == edit.old_end.bytes &&
            child_size.bytes > 0 &&
            i > 0
          )
        ) &&
        (
          !parent_depends_on_column ||
          child_left.extent.row > padding.extent.row
        ) &&
        (
          !child.depends_on_column() ||
          !column_shifted ||
          child_left.extent.row > edit.old_end.extent.row
        ) {
        break
      }
      // Transform edit into the child's coordinate space.
      let mut child_edit : Edit = {
        start: length_saturating_sub(edit.start, child_left),
        old_end: length_saturating_sub(edit.old_end, child_left),
        new_end: length_saturating_sub(edit.new_end, child_left),
      }
      // Interpret all inserted text as applying to the *first* child that
      // touches the edit. Subsequent children never have any text inserted
      // into them; they are only shrunk to compensate for the edit.
      if child_right.bytes > edit.start.bytes ||
        (child_right.bytes == edit.start.bytes && is_pure_insertion) {
        edit = { ..edit, new_end: edit.start, }
      } else {
        // Children that occur before the edit are not reshaped by the edit.
        child_edit = {
          ..child_edit,
          old_end: child_edit.start,
          new_end: child_edit.start,
        }
      }
      // Queue processing of this child's subtree.
      stack.push(({ array: children, index: i, owner: 0, }, child_edit))
    }
  }
  root[0]
}

///|
/// `ts_subtree_last_external_token`.
pub fn Subtree::last_external_token(self : Subtree) -> Subtree {
  if !self.has_external_tokens() {
    return Null
  }
  let mut tree = self
  while tree.ptr().children.length() > 0 {
    let children = tree.ptr().children
    for i = children.length() - 1; i >= 0; i = i - 1 {
      let child = children[i]
      if child.has_external_tokens() {
        tree = child
        break
      }
    }
  }
  tree
}

///|
/// `ts_subtree_external_scanner_state`.
pub fn Subtree::external_scanner_state(self : Subtree) -> Bytes {
  match self {
    Heap(d) if d.has_external_tokens && d.children.is_empty() =>
      d.external_scanner_state
    _ => b""
  }
}

///|
/// `ts_subtree_external_scanner_state_eq`.
pub fn Subtree::external_scanner_state_eq(
  self : Subtree,
  other : Subtree,
) -> Bool {
  external_scanner_state_eq(
    self.external_scanner_state(),
    other.external_scanner_state(),
  )
}
