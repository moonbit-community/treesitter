// Port of tree-sitter lib/src/subtree.h and lib/src/subtree.c.
//
// C distinguishes small leaves stored inline in the `Subtree` word from
// heap-allocated subtrees. The distinction is observable (e.g. `.ptr`
// equality, which fields are stored, when `make_mut` copies), so it is kept:
// an inline subtree holds its packed `SubtreeInlineData` by value, a heap
// subtree a shared mutable record with an explicit reference count maintained
// exactly as upstream's retain/release calls do. `Subtree` itself is a value
// type, so inline leaves are not allocated, as in C.

///|
let ts_tree_state_none : Int32 = 65535

///|
let ts_max_inline_tree_length : UInt32 = 255

///|
/// The inline representation of a small leaf, packed into one word exactly
/// as upstream's `SubtreeInlineData` bitfields (little-endian layout):
///
/// | bits  | field                                                    |
/// |-------|----------------------------------------------------------|
/// | 0     | `is_inline` (always set)                                 |
/// | 1..7  | `visible`, `named`, `extra`, `has_changes`, `is_missing`, `is_keyword`, `depends_on_column` |
/// | 8-15  | `symbol` (`uint8_t`)                                     |
/// | 16-31 | `parse_state` (`uint16_t`)                               |
/// | 32-39 | `padding_columns` (`uint8_t`)                            |
/// | 40-43 | `padding_rows` (4 bits)                                  |
/// | 44-47 | `lookahead_bytes` (4 bits)                               |
/// | 48-55 | `padding_bytes` (`uint8_t`)                              |
/// | 56-63 | `size_bytes` (`uint8_t`)                                 |
///
/// Callers keep values within these widths (`subtree_can_inline` and the
/// `symbol <= 255` check), as upstream does.
#valtype
pub(all) struct SubtreeInlineData {
  bits : UInt64
} derive(Eq, Debug)

///|
fn inline_flag(value : Bool, bit : Int32) -> UInt64 {
  if value {
    1UL << bit
  } else {
    0
  }
}

///|
pub fn SubtreeInlineData::new(
  visible~ : Bool,
  named~ : Bool,
  extra~ : Bool,
  has_changes~ : Bool,
  is_missing~ : Bool,
  is_keyword~ : Bool,
  depends_on_column~ : Bool,
  symbol~ : Int32,
  parse_state~ : Int32,
  padding_columns~ : UInt32,
  padding_rows~ : UInt32,
  lookahead_bytes~ : UInt32,
  padding_bytes~ : UInt32,
  size_bytes~ : UInt32,
) -> SubtreeInlineData {
  {
    bits: 1UL |
    inline_flag(visible, 1) |
    inline_flag(named, 2) |
    inline_flag(extra, 3) |
    inline_flag(has_changes, 4) |
    inline_flag(is_missing, 5) |
    inline_flag(is_keyword, 6) |
    inline_flag(depends_on_column, 7) |
    ((symbol.reinterpret_as_uint().to_uint64() & 0xFF) << 8) |
    ((parse_state.reinterpret_as_uint().to_uint64() & 0xFFFF) << 16) |
    ((padding_columns.to_uint64() & 0xFF) << 32) |
    ((padding_rows.to_uint64() & 0xF) << 40) |
    ((lookahead_bytes.to_uint64() & 0xF) << 44) |
    ((padding_bytes.to_uint64() & 0xFF) << 48) |
    ((size_bytes.to_uint64() & 0xFF) << 56),
  }
}

///|
#inline
fn SubtreeInlineData::flag(self : SubtreeInlineData, bit : Int32) -> Bool {
  ((self.bits >> bit) & 1) != 0
}

///|
#inline
fn SubtreeInlineData::with_flag(
  self : SubtreeInlineData,
  bit : Int32,
  value : Bool,
) -> SubtreeInlineData {
  { bits: (self.bits & (1UL << bit).lnot()) | inline_flag(value, bit), }
}

///|
#inline
fn SubtreeInlineData::field(
  self : SubtreeInlineData,
  shift : Int32,
  mask : UInt64,
) -> UInt32 {
  ((self.bits >> shift) & mask).to_uint()
}

///|
pub fn SubtreeInlineData::is_inline(self : SubtreeInlineData) -> Bool {
  self.flag(0)
}

///|
pub fn SubtreeInlineData::visible(self : SubtreeInlineData) -> Bool {
  self.flag(1)
}

///|
pub fn SubtreeInlineData::named(self : SubtreeInlineData) -> Bool {
  self.flag(2)
}

///|
pub fn SubtreeInlineData::extra(self : SubtreeInlineData) -> Bool {
  self.flag(3)
}

///|
pub fn SubtreeInlineData::has_changes(self : SubtreeInlineData) -> Bool {
  self.flag(4)
}

///|
pub fn SubtreeInlineData::is_missing(self : SubtreeInlineData) -> Bool {
  self.flag(5)
}

///|
pub fn SubtreeInlineData::is_keyword(self : SubtreeInlineData) -> Bool {
  self.flag(6)
}

///|
pub fn SubtreeInlineData::depends_on_column(self : SubtreeInlineData) -> Bool {
  self.flag(7)
}

///|
pub fn SubtreeInlineData::symbol(self : SubtreeInlineData) -> Int32 {
  self.field(8, 0xFF).reinterpret_as_int()
}

///|
pub fn SubtreeInlineData::parse_state(self : SubtreeInlineData) -> Int32 {
  self.field(16, 0xFFFF).reinterpret_as_int()
}

///|
pub fn SubtreeInlineData::padding_columns(self : SubtreeInlineData) -> UInt32 {
  self.field(32, 0xFF)
}

///|
pub fn SubtreeInlineData::padding_rows(self : SubtreeInlineData) -> UInt32 {
  self.field(40, 0xF)
}

///|
pub fn SubtreeInlineData::lookahead_bytes(self : SubtreeInlineData) -> UInt32 {
  self.field(44, 0xF)
}

///|
pub fn SubtreeInlineData::padding_bytes(self : SubtreeInlineData) -> UInt32 {
  self.field(48, 0xFF)
}

///|
pub fn SubtreeInlineData::size_bytes(self : SubtreeInlineData) -> UInt32 {
  self.field(56, 0xFF)
}

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
/// The fundamental building block of a syntax tree: upstream's
/// `union { SubtreeInlineData data; const SubtreeHeapData *ptr; }`, stored
/// by value. An inline subtree has `data.is_inline()` set and no `ptr`; a heap
/// subtree has `ptr`; `Subtree::null()` (`NULL_SUBTREE`) has neither.
#valtype
pub(all) struct Subtree {
  data : SubtreeInlineData
  heap : SubtreeHeapData?
}

///|
/// `NULL_SUBTREE`.
pub fn Subtree::null() -> Subtree {
  { data: { bits: 0, }, heap: None, }
}

///|
pub fn Subtree::from_inline(data : SubtreeInlineData) -> Subtree {
  { data, heap: None, }
}

///|
pub fn Subtree::from_heap(ptr : SubtreeHeapData) -> Subtree {
  { data: { bits: 0, }, heap: Some(ptr), }
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
/// The children of every leaf. Leaves never gain children in place (a node
/// is always created with its own array), so one empty array is shared
/// instead of allocating one per leaf.
let empty_children : Array[Subtree] = []

///|
fn SubtreeHeapData::empty() -> SubtreeHeapData {
  {
    ref_count: 1,
    padding: length_zero(),
    size: length_zero(),
    lookahead_bytes: 0,
    error_cost: 0,
    children: empty_children,
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
  match self.heap {
    Some(data) => data
    None => abort("subtree is not heap allocated")
  }
}

///|
pub fn Subtree::is_inline(self : Subtree) -> Bool {
  self.data.is_inline()
}

///|
pub fn Subtree::is_null(self : Subtree) -> Bool {
  self.heap is None && !self.data.is_inline()
}

///|
/// `a.ptr == b.ptr`: identity for heap subtrees, bitwise equality for inline
/// subtrees (whose data occupies the pointer word).
pub fn Subtree::ptr_eq(self : Subtree, other : Subtree) -> Bool {
  match (self.heap, other.heap) {
    (Some(a), Some(b)) => physical_equal(a, b)
    (None, None) => self.data == other.data
    _ => false
  }
}

///|
/// A stable identity standing in for the pointer value (`ts_node_id`).
pub fn Subtree::address(self : Subtree) -> Int32 {
  match self.heap {
    Some(data) => data.address
    None => if self.data.is_inline() { -1 } else { 0 }
  }
}

///|
pub fn Subtree::symbol(self : Subtree) -> Int32 {
  if self.data.is_inline() {
    self.data.symbol()
  } else {
    self.ptr().symbol
  }
}

///|
pub fn Subtree::visible(self : Subtree) -> Bool {
  if self.data.is_inline() {
    self.data.visible()
  } else {
    self.ptr().visible
  }
}

///|
pub fn Subtree::named(self : Subtree) -> Bool {
  if self.data.is_inline() {
    self.data.named()
  } else {
    self.ptr().named
  }
}

///|
pub fn Subtree::extra(self : Subtree) -> Bool {
  if self.data.is_inline() {
    self.data.extra()
  } else {
    self.ptr().extra
  }
}

///|
pub fn Subtree::has_changes(self : Subtree) -> Bool {
  if self.data.is_inline() {
    self.data.has_changes()
  } else {
    self.ptr().has_changes
  }
}

///|
pub fn Subtree::missing(self : Subtree) -> Bool {
  if self.data.is_inline() {
    self.data.is_missing()
  } else {
    self.ptr().is_missing
  }
}

///|
pub fn Subtree::is_keyword(self : Subtree) -> Bool {
  if self.data.is_inline() {
    self.data.is_keyword()
  } else {
    self.ptr().is_keyword
  }
}

///|
pub fn Subtree::parse_state(self : Subtree) -> Int32 {
  if self.data.is_inline() {
    self.data.parse_state()
  } else {
    self.ptr().parse_state
  }
}

///|
pub fn Subtree::lookahead_bytes(self : Subtree) -> UInt32 {
  if self.data.is_inline() {
    self.data.lookahead_bytes()
  } else {
    self.ptr().lookahead_bytes
  }
}

///|
pub fn Subtree::children(self : Subtree) -> Array[Subtree] {
  match self.heap {
    Some(d) => d.children
    None => empty_children
  }
}

///|
/// `ts_subtree_set_extra`.
pub fn Subtree::set_extra(self : Subtree, is_extra : Bool) -> Subtree {
  if self.data.is_inline() {
    Subtree::from_inline(self.data.with_flag(3, is_extra))
  } else {
    self.ptr().extra = is_extra
    self
  }
}

///|
pub fn Subtree::leaf_symbol(self : Subtree) -> Int32 {
  if self.data.is_inline() {
    let d = self.data
    d.symbol()
  } else {
    let d = self.ptr()
    if d.children.is_empty() {
      d.symbol
    } else {
      d.first_leaf_symbol
    }
  }
}

///|
pub fn Subtree::leaf_parse_state(self : Subtree) -> Int32 {
  if self.data.is_inline() {
    let d = self.data
    d.parse_state()
  } else {
    let d = self.ptr()
    if d.children.is_empty() {
      d.parse_state
    } else {
      d.first_leaf_parse_state
    }
  }
}

///|
pub fn Subtree::padding(self : Subtree) -> Length {
  if self.data.is_inline() {
    let d = self.data
    {
      bytes: d.padding_bytes(),
      extent: { row: d.padding_rows(), column: d.padding_columns(), },
    }
  } else {
    let d = self.ptr()
    d.padding
  }
}

///|
pub fn Subtree::size(self : Subtree) -> Length {
  if self.data.is_inline() {
    let d = self.data
    { bytes: d.size_bytes(), extent: { row: 0, column: d.size_bytes(), }, }
  } else {
    let d = self.ptr()
    d.size
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
  match self.heap {
    Some(d) => d.children.length()
    None => 0
  }
}

///|
/// The `repeat_depth` of an external leaf whose scanner state is `state`.
///
/// Upstream stores the state in a union with the fields of non-terminals:
/// `short_data[24]` (states of at most 24 bytes; longer ones are on the
/// heap) overlaps `repeat_depth`, a `uint16_t` at offset 16, and
/// `ts_subtree_repeat_depth` reads it for leaves too. `ts_subtree_new_leaf`
/// zeroes the union and `ts_external_scanner_state_init` copies the state
/// into it, so bytes 16 and 17 of a short state (little-endian, as on the
/// supported hosts) become the leaf's repeat depth.
fn external_scanner_state_repeat_depth(state : Bytes) -> UInt32 {
  let length = state.length()
  if length > 24 || length <= 16 {
    return 0
  }
  let low = state[16].to_uint()
  let high = if length > 17 { state[17].to_uint() } else { 0 }
  low | (high << 8)
}

///|
pub fn Subtree::repeat_depth(self : Subtree) -> UInt32 {
  match self.heap {
    Some(d) => d.repeat_depth
    None => 0
  }
}

///|
pub fn Subtree::is_repetition(self : Subtree) -> Bool {
  match self.heap {
    Some(d) => !d.named && !d.visible && !d.children.is_empty()
    None => false
  }
}

///|
pub fn Subtree::visible_descendant_count(self : Subtree) -> UInt32 {
  match self.heap {
    Some(d) if !d.children.is_empty() => d.visible_descendant_count
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
    match self.heap {
      Some(d) => d.error_cost
      None => 0
    }
  }
}

///|
pub fn Subtree::dynamic_precedence(self : Subtree) -> Int32 {
  match self.heap {
    Some(d) if !d.children.is_empty() => d.dynamic_precedence
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
  match self.heap {
    Some(d) => d.fragile_left
    None => false
  }
}

///|
pub fn Subtree::fragile_right(self : Subtree) -> Bool {
  match self.heap {
    Some(d) => d.fragile_right
    None => false
  }
}

///|
pub fn Subtree::has_external_tokens(self : Subtree) -> Bool {
  match self.heap {
    Some(d) => d.has_external_tokens
    None => false
  }
}

///|
pub fn Subtree::has_external_scanner_state_change(self : Subtree) -> Bool {
  match self.heap {
    Some(d) => d.has_external_scanner_state_change
    None => false
  }
}

///|
pub fn Subtree::depends_on_column(self : Subtree) -> Bool {
  if self.data.is_inline() {
    self.data.depends_on_column()
  } else {
    self.ptr().depends_on_column
  }
}

///|
pub fn Subtree::is_fragile(self : Subtree) -> Bool {
  match self.heap {
    Some(d) => d.fragile_left || d.fragile_right
    None => false
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
      array.unsafe_pop() |> ignore
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
    Subtree::from_inline(
      SubtreeInlineData::new(
        parse_state~,
        symbol~,
        padding_bytes=padding.bytes,
        padding_rows=padding.extent.row,
        padding_columns=padding.extent.column,
        size_bytes=size.bytes,
        lookahead_bytes~,
        visible=metadata.visible,
        named=metadata.named,
        extra~,
        has_changes=false,
        is_missing=false,
        is_keyword~,
        depends_on_column~,
      ),
    )
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
    Subtree::from_heap(data)
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
  if self.data.is_inline() {
    let d = self.data
    Subtree::from_inline({
      bits: (d.bits & 0xFFFF_FFFF_FFFF_00F9UL) |
      ((symbol.reinterpret_as_uint().to_uint64() & 0xFF) << 8) |
      inline_flag(metadata.named, 2) |
      inline_flag(metadata.visible, 1),
    })
  } else {
    let d = self.ptr()
    d.symbol = symbol
    d.named = metadata.named
    d.visible = metadata.visible
    self
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
  Subtree::from_heap(result)
}

///|
/// `ts_subtree_make_mut`: take ownership of the subtree. If it has only one
/// owner it is converted directly; otherwise it is copied.
pub fn Subtree::make_mut(self : Subtree) -> Subtree {
  if self.data.is_inline() {
    return self
  }
  if self.ptr().ref_count == 1 {
    return self
  }
  let result = self.clone()
  self.release()
  result
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
    guard child.heap is Some(c) &&
      c.children.length() >= 2 &&
      c.ref_count <= 1 &&
      c.symbol == symbol else {
      break
    }
    let grandchild = c.children[0]
    guard grandchild.heap is Some(g) &&
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
    tree = stack.unsafe_pop()
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
  let result = Subtree::from_heap(data)
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
  if result.data.is_inline() {
    Subtree::from_inline(result.data.with_flag(5, true))
  } else {
    result.ptr().is_missing = true
    result
  }
}

///|
/// `ts_subtree_retain`.
pub fn Subtree::retain(self : Subtree) -> Unit {
  match self.heap {
    Some(d) => d.ref_count += 1
    None => ()
  }
}

///|
/// `pool->tree_stack` of `ts_subtree_release`: scratch space that is always
/// empty between calls. Each slot is reset to `Null` as it is popped, because
/// a native `Array::pop` leaves the popped value in the backing buffer, which
/// would keep a released tree reachable from this global.
let release_stack : Array[Subtree] = []

///|
/// `ts_subtree_release`. Memory is reclaimed by the GC; the counts are kept
/// so that `make_mut` and `compress` copy exactly when upstream does.
pub fn Subtree::release(self : Subtree) -> Unit {
  guard self.heap is Some(d) else { return }
  d.ref_count -= 1
  if d.ref_count != 0 {
    return
  }
  let stack = release_stack
  stack.push(self)
  while stack.length() > 0 {
    let top = stack.length() - 1
    let tree = stack[top]
    stack[top] = Subtree::null()
    stack.unsafe_pop() |> ignore
    let tree = tree.ptr()
    for child in tree.children {
      if child.heap is Some(c) {
        c.ref_count -= 1
        if c.ref_count == 0 {
          stack.push(child)
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
    let right = stack.unsafe_pop()
    let left = stack.unsafe_pop()
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
  match self.heap {
    Some(d) => {
      d.has_changes = true
      self
    }
    None =>
      if self.data.is_inline() {
        Subtree::from_inline(self.data.with_flag(4, true))
      } else {
        self
      }
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
    match result.heap {
      None if result.data.is_inline() => {
        let d = result.data
        if subtree_can_inline(padding, size, lookahead_bytes) {
          result = Subtree::from_inline(
            SubtreeInlineData::new(
              visible=d.visible(),
              named=d.named(),
              extra=d.extra(),
              has_changes=d.has_changes(),
              is_missing=d.is_missing(),
              is_keyword=d.is_keyword(),
              depends_on_column=d.depends_on_column(),
              symbol=d.symbol(),
              parse_state=d.parse_state(),
              padding_bytes=padding.bytes,
              padding_rows=padding.extent.row,
              padding_columns=padding.extent.column,
              size_bytes=size.bytes,
              lookahead_bytes=d.lookahead_bytes(),
            ),
          )
        } else {
          let data = SubtreeHeapData::empty()
          data.padding = padding
          data.size = size
          data.lookahead_bytes = lookahead_bytes
          data.symbol = d.symbol()
          data.parse_state = d.parse_state()
          data.visible = d.visible()
          data.named = d.named()
          data.extra = d.extra()
          data.depends_on_column = d.depends_on_column()
          data.is_missing = d.is_missing()
          data.is_keyword = d.is_keyword()
          result = Subtree::from_heap(data)
        }
      }
      Some(d) => {
        d.padding = padding
        d.size = size
      }
      None => ()
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
    return Subtree::null()
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
  match self.heap {
    Some(d) if d.has_external_tokens && d.children.is_empty() =>
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
