// Port of tree-sitter lib/src/query.c: streams, capture list pool, finished
// state heap, quantifiers, symbol tables, query steps and the state
// predecessor map.

///|
let max_step_capture_count : Int = 3

///|
let max_negated_field_count : Int = 8

///|
let max_state_predecessor_count : Int = 256

///|
let max_analysis_state_depth : Int = 8

///|
let max_analysis_iteration_count : Int = 256

///|
let pattern_done_marker : Int = 65535

///|
let none : Int = 65535

///|
let capture_list_none : UInt = 0xFFFFFFFFU

///|
let wildcard_symbol : Int = 0

///|
/// The cursor calls the progress callback once it has done this much work.
/// Entering or leaving a node costs one, plus one for each in-progress state,
/// because every step visits all of them.
let work_per_query_callback_check : Int = 1000

///|
let max_query_pattern_depth : Int = 100

///|
/// C `iswspace` in the "C" locale: ASCII only.
fn iswspace(c : Int) -> Bool {
  (c >= 9 && c <= 13) || c == 32
}

///|
/// C `iswalnum` in the "C" locale: ASCII only.
fn iswalnum(c : Int) -> Bool {
  (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
/// Stream - A sequence of unicode characters derived from a UTF8 string. This
/// struct is used in parsing queries from S-expressions. Positions are byte
/// offsets into `source`.
priv struct Stream {
  source : Bytes
  mut input : Int
  start : Int
  end : Int
  mut next : Int
  mut next_size : Int
}

///|
/// Advance to the next unicode code point in the stream.
fn Stream::advance(self : Stream) -> Bool {
  self.input += self.next_size
  if self.input < self.end {
    let (size, code_point) = @runtime.decode_utf8(
      self.source[self.input:self.end],
    )
    self.next = code_point
    if size > 0 {
      self.next_size = size.reinterpret_as_int()
      return true
    }
  } else {
    self.next_size = 0
    self.next = 0
  }
  false
}

///|
/// Reset the stream to the given input position.
fn Stream::reset(self : Stream, input : Int) -> Unit {
  self.input = input
  self.next_size = 0
  ignore(self.advance())
}

///|
fn Stream::new(source : Bytes) -> Stream {
  let stream = {
    source,
    next: 0,
    next_size: 0,
    input: 0,
    start: 0,
    end: source.length(),
  }
  ignore(stream.advance())
  stream
}

///|
fn Stream::skip_whitespace(self : Stream) -> Unit {
  for ;; {
    if iswspace(self.next) {
      ignore(self.advance())
    } else if self.next == ';' {
      // skip over comments
      ignore(self.advance())
      while self.next != 0 && self.next != '\n' {
        if !self.advance() {
          break
        }
      }
    } else {
      break
    }
  }
}

///|
fn Stream::is_ident_start(self : Stream) -> Bool {
  iswalnum(self.next) || self.next == '_' || self.next == '-'
}

///|
fn Stream::scan_identifier(self : Stream) -> Unit {
  ignore(self.advance())
  while iswalnum(self.next) ||
        self.next == '_' ||
        self.next == '-' ||
        self.next == '.' {
    ignore(self.advance())
  }
}

///|
fn Stream::offset(self : Stream) -> Int {
  self.input - self.start
}

///|
/// `TSQueryCapture`.
pub(all) struct QueryCapture {
  node : @runtime.Node
  index : Int
}

///|
/// A capture list. `in_use == false` stands for upstream's `UINT32_MAX` size.
///
/// The captures are `items[0:size]`. Elements are only ever written at index
/// `size` or later, and growing copies them into a new array, so a view of the
/// list that `next_match`/`next_capture` hand out (upstream returns a pointer
/// to the list's contents) keeps its elements however the list grows. A list
/// that was handed out gets a new array when it is cleared instead of being
/// overwritten. `serial` changes whenever the list is cleared, so the id and
/// the serial together identify a list's current contents.
priv struct CaptureList {
  mut items : FixedArray[QueryCapture]
  mut size : Int
  mut in_use : Bool
  mut exposed : Bool
  mut serial : Int
}

///|
fn CaptureList::new() -> CaptureList {
  { items: [], size: 0, in_use: true, exposed: false, serial: 0 }
}

///|
fn CaptureList::view(self : CaptureList) -> ArrayView[QueryCapture] {
  self.items[0:self.size]
}

///|
fn CaptureList::push(self : CaptureList, capture : QueryCapture) -> Unit {
  if self.size == self.items.length() {
    let items = FixedArray::make(
      if self.size < 2 {
        4
      } else {
        self.size * 2
      },
      null_capture,
    )
    self.items.blit_to(items, len=self.size)
    self.items = items
  }
  self.items[self.size] = capture
  self.size += 1
}

///|
/// The list's captures, as handed out by `next_match` and `next_capture`.
fn CaptureList::expose(self : CaptureList) -> ArrayView[QueryCapture] {
  self.exposed = true
  self.view()
}

///|
/// Empties the list. Upstream's captures hold non-owning node pointers, but a
/// MoonBit `Node` keeps its `Tree` alive, so lists that are cleared for reuse
/// or no longer in use must not keep referring to their previous nodes: the
/// elements are overwritten (capacity is retained), unless the list was handed
/// out, in which case its array is left to the views of it.
fn CaptureList::clear(self : CaptureList) -> Unit {
  self.serial += 1
  if self.exposed {
    self.items = []
    self.exposed = false
  } else {
    for i in 0..<self.size {
      self.items[i] = null_capture
    }
  }
  self.size = 0
}

///|
let null_capture : QueryCapture = {
  node: @runtime.Node::new(None, None, @runtime.length_zero(), 0),
  index: 0,
}

///|
/// CaptureListPool - A collection of *lists* of captures. Each query state
/// needs to maintain its own list of captures. To avoid repeated allocations,
/// this struct maintains a fixed set of capture lists, and keeps track of
/// which ones are currently in use by a query state.
priv struct CaptureListPool {
  list : Array[CaptureList]
  empty_list : CaptureList
  // The maximum number of capture lists that we are allowed to allocate. We
  // never allow `list` to allocate more entries than this, dropping pending
  // matches if needed to stay under the limit.
  mut max_capture_list_count : UInt
  // The ids of the capture lists allocated in `list` that are not currently
  // in use.
  free_id_stack : Array[Int]
}

///|
fn CaptureListPool::new() -> CaptureListPool {
  {
    list: [],
    empty_list: CaptureList::new(),
    max_capture_list_count: 0xFFFFFFFFU,
    free_id_stack: [],
  }
}

///|
fn CaptureListPool::reset(self : CaptureListPool) -> Unit {
  self.free_id_stack.clear()
  for i, list in self.list {
    // This invalid size means that the list is not in use.
    list.in_use = false
    list.clear()
    self.free_id_stack.push(i)
  }
}

///|
fn CaptureListPool::get(
  self : CaptureListPool,
  id : UInt,
) -> ArrayView[QueryCapture] {
  self.get_list(id).view()
}

///|
fn CaptureListPool::get_list(self : CaptureListPool, id : UInt) -> CaptureList {
  if id >= self.list.length().reinterpret_as_uint() {
    return self.empty_list
  }
  self.list[id.reinterpret_as_int()]
}

///|
fn CaptureListPool::is_empty(self : CaptureListPool) -> Bool {
  // The capture list pool is empty if all allocated lists are in use, and we
  // have reached the maximum allowed number of allocated lists.
  self.free_id_stack.length() == 0 &&
  self.list.length().reinterpret_as_uint() >= self.max_capture_list_count
}

///|
fn CaptureListPool::acquire(self : CaptureListPool) -> UInt {
  // First see if any already allocated capture list is currently unused.
  if self.free_id_stack.pop() is Some(id) {
    self.list[id].clear()
    self.list[id].in_use = true
    return id.reinterpret_as_uint()
  }
  // Otherwise allocate and initialize a new capture list, as long as that
  // doesn't put us over the requested maximum.
  let i = self.list.length()
  if i.reinterpret_as_uint() >= self.max_capture_list_count {
    return capture_list_none
  }
  self.list.push(CaptureList::new())
  i.reinterpret_as_uint()
}

///|
fn CaptureListPool::release(self : CaptureListPool, id : UInt) -> Unit {
  if id >= self.list.length().reinterpret_as_uint() {
    return
  }
  let list = self.list[id.reinterpret_as_int()]
  if !list.in_use {
    return // Guard against releasing a list twice
  }
  list.in_use = false
  list.clear()
  self.free_id_stack.push(id.reinterpret_as_int())
}

///|
/// QueryState - The state of an in-progress match of a particular pattern in
/// a query. `consumed_capture_count` is a 12-bit field upstream; it is kept
/// truncated to 12 bits here.
priv struct QueryState {
  mut id : UInt
  mut capture_list_id : UInt
  mut heap_insert_order : UInt
  start_depth : Int
  mut step_index : Int
  pattern_index : Int
  mut consumed_capture_count : Int
  mut seeking_immediate_match : Bool
  mut has_in_progress_alternatives : Bool
  mut dead : Bool
  mut needs_parent : Bool
  mut skipped_quantifier : Bool
}

///|
fn QueryState::copy(self : QueryState) -> QueryState {
  { ..self }
}

///|
fn QueryState::set_consumed_capture_count(self : QueryState, value : Int) -> Unit {
  self.consumed_capture_count = value & 0xFFF
}

///|
/// Compare two finished states by (byte offset of next unconsumed capture,
/// pattern_index, insertion order).
fn finished_state_precedes(
  a : QueryState,
  b : QueryState,
  pool : CaptureListPool,
) -> Bool {
  let a_caps = pool.get(a.capture_list_id)
  let b_caps = pool.get(b.capture_list_id)
  if a.consumed_capture_count >= a_caps.length() {
    return false
  }
  if b.consumed_capture_count >= b_caps.length() {
    return true
  }
  let a_byte = a_caps[a.consumed_capture_count].node.start_byte()
  let b_byte = b_caps[b.consumed_capture_count].node.start_byte()
  if a_byte != b_byte {
    return a_byte < b_byte
  }
  if a.pattern_index != b.pattern_index {
    return a.pattern_index < b.pattern_index
  }
  a.heap_insert_order < b.heap_insert_order
}

///|
fn finished_state_swap(states : Array[QueryState], a : Int, b : Int) -> Unit {
  let tmp = states[a]
  states[a] = states[b]
  states[b] = tmp
}

///|
fn finished_state_sift_down(
  states : Array[QueryState],
  index : Int,
  pool : CaptureListPool,
) -> Unit {
  let size = states.length()
  let mut index = index
  for ;; {
    let mut smallest = index
    let left = 2 * index + 1
    let right = 2 * index + 2
    if left < size && finished_state_precedes(states[left], states[smallest], pool) {
      smallest = left
    }
    if right < size &&
      finished_state_precedes(states[right], states[smallest], pool) {
      smallest = right
    }
    if smallest == index {
      break
    }
    finished_state_swap(states, index, smallest)
    index = smallest
  }
}

///|
fn finished_state_sift_up(
  states : Array[QueryState],
  index : Int,
  pool : CaptureListPool,
) -> Unit {
  let mut index = index
  while index > 0 {
    let parent = (index - 1) / 2
    if finished_state_precedes(states[index], states[parent], pool) {
      finished_state_swap(states, index, parent)
      index = parent
    } else {
      break
    }
  }
}

///|
fn finished_state_pop(states : Array[QueryState], pool : CaptureListPool) -> Unit {
  if states.length() > 1 {
    states[0] = states[states.length() - 1]
  }
  ignore(states.pop())
  if states.length() > 0 {
    finished_state_sift_down(states, 0, pool)
  }
}

///|
/// Remove an element at an arbitrary index and restore heap order.
fn finished_state_erase(
  states : Array[QueryState],
  index : Int,
  pool : CaptureListPool,
) -> Unit {
  if index == states.length() - 1 {
    ignore(states.pop())
    return
  }
  states[index] = states[states.length() - 1]
  ignore(states.pop())
  // The replacement element may need to go up or down.
  if index > 0 &&
    finished_state_precedes(states[index], states[(index - 1) / 2], pool) {
    finished_state_sift_up(states, index, pool)
  } else {
    finished_state_sift_down(states, index, pool)
  }
}

///|
/// `TSQuantifier`; declaration order matches the C enum values.
pub(all) enum Quantifier {
  Zero
  ZeroOrOne
  ZeroOrMore
  One
  OneOrMore
} derive(Eq, Debug)

///|
fn quantifier_mul(left : Quantifier, right : Quantifier) -> Quantifier {
  match left {
    Zero => Zero
    ZeroOrOne =>
      match right {
        Zero => Zero
        ZeroOrOne | One => ZeroOrOne
        ZeroOrMore | OneOrMore => ZeroOrMore
      }
    ZeroOrMore =>
      match right {
        Zero => Zero
        _ => ZeroOrMore
      }
    One => right
    OneOrMore =>
      match right {
        Zero => Zero
        ZeroOrOne | ZeroOrMore => ZeroOrMore
        One | OneOrMore => OneOrMore
      }
  }
}

///|
fn quantifier_join(left : Quantifier, right : Quantifier) -> Quantifier {
  match left {
    Zero =>
      match right {
        Zero => Zero
        ZeroOrOne | One => ZeroOrOne
        ZeroOrMore | OneOrMore => ZeroOrMore
      }
    ZeroOrOne =>
      match right {
        Zero | ZeroOrOne | One => ZeroOrOne
        ZeroOrMore | OneOrMore => ZeroOrMore
      }
    ZeroOrMore => ZeroOrMore
    One =>
      match right {
        Zero | ZeroOrOne => ZeroOrOne
        ZeroOrMore => ZeroOrMore
        One => One
        OneOrMore => OneOrMore
      }
    OneOrMore =>
      match right {
        Zero | ZeroOrOne | ZeroOrMore => ZeroOrMore
        One | OneOrMore => OneOrMore
      }
  }
}

///|
fn quantifier_add(left : Quantifier, right : Quantifier) -> Quantifier {
  match left {
    Zero => right
    ZeroOrOne =>
      match right {
        Zero => ZeroOrOne
        ZeroOrOne | ZeroOrMore => ZeroOrMore
        One | OneOrMore => OneOrMore
      }
    ZeroOrMore =>
      match right {
        Zero | ZeroOrOne | ZeroOrMore => ZeroOrMore
        One | OneOrMore => OneOrMore
      }
    One =>
      match right {
        Zero => One
        _ => OneOrMore
      }
    OneOrMore => OneOrMore
  }
}

///|
/// CaptureQuantifiers - the quantifiers of a pattern's captures, by capture id.
priv type CaptureQuantifiers = Array[Quantifier]

///|
fn capture_quantifiers_replace(
  qs : Array[Quantifier],
  quantifiers : Array[Quantifier],
) -> Unit {
  qs.clear()
  for q in quantifiers {
    qs.push(q)
  }
}

///|
fn capture_quantifier_for_id(qs : Array[Quantifier], id : Int) -> Quantifier {
  let id = id & 0xFFFF // `uint16_t id`
  if qs.length() <= id {
    Zero
  } else {
    qs[id]
  }
}

///|
fn capture_quantifiers_add_for_id(
  qs : Array[Quantifier],
  id : Int,
  quantifier : Quantifier,
) -> Unit {
  let id = id & 0xFFFF // `uint16_t id`
  while qs.length() <= id {
    qs.push(Zero)
  }
  qs[id] = quantifier_add(qs[id], quantifier)
}

///|
fn capture_quantifiers_add_all(
  qs : Array[Quantifier],
  quantifiers : Array[Quantifier],
) -> Unit {
  while qs.length() < quantifiers.length() {
    qs.push(Zero)
  }
  for id in 0..<(quantifiers.length() & 0xFFFF) {
    qs[id] = quantifier_add(qs[id], quantifiers[id])
  }
}

///|
fn capture_quantifiers_mul(
  qs : Array[Quantifier],
  quantifier : Quantifier,
) -> Unit {
  for id in 0..<(qs.length() & 0xFFFF) {
    qs[id] = quantifier_mul(qs[id], quantifier)
  }
}

///|
fn capture_quantifiers_join_all(
  qs : Array[Quantifier],
  quantifiers : Array[Quantifier],
) -> Unit {
  while qs.length() < quantifiers.length() {
    qs.push(Zero)
  }
  for id in 0..<quantifiers.length() {
    qs[id] = quantifier_join(qs[id], quantifiers[id])
  }
  for id in quantifiers.length()..<qs.length() {
    qs[id] = quantifier_join(qs[id], Zero)
  }
}

///|
/// SymbolTable - a two-way mapping of strings to ids. Names are byte strings;
/// as upstream compares them with `strncmp`, bytes after an embedded NUL are
/// ignored when looking names up.
priv struct SymbolTable {
  names : Array[Bytes]
}

///|
fn SymbolTable::new() -> SymbolTable {
  { names: [] }
}

///|
/// `slice.length == length && !strncmp(characters + offset, name, length)`.
fn symbol_name_matches(existing : Bytes, name : BytesView) -> Bool {
  if existing.length() != name.length() {
    return false
  }
  for i in 0..<name.length() {
    if existing[i] != name[i] {
      return false
    }
    if name[i] == 0 {
      return true
    }
  }
  true
}

///|
fn SymbolTable::id_for_name(self : SymbolTable, name : BytesView) -> Int {
  for i, existing in self.names {
    if symbol_name_matches(existing, name) {
      return i
    }
  }
  -1
}

///|
fn SymbolTable::name_for_id(self : SymbolTable, id : Int) -> Bytes {
  self.names[id & 0xFFFF] // `uint16_t id`
}

///|
fn SymbolTable::insert_name(self : SymbolTable, name : BytesView) -> Int {
  let id = self.id_for_name(name)
  if id >= 0 {
    return id & 0xFFFF
  }
  self.names.push(name.to_owned())
  (self.names.length() - 1) & 0xFFFF
}

///|
/// QueryStep - A step in the process of matching a query. Each node within a
/// query S-expression corresponds to one of these steps.
priv struct QueryStep {
  mut symbol : Int
  mut supertype_symbol : Int
  mut field : Int
  capture_ids : FixedArray[Int]
  depth : Int
  mut alternative_index : Int
  mut negated_field_list_id : Int
  mut is_named : Bool
  is_immediate : Bool
  mut is_last_child : Bool
  mut is_pass_through : Bool
  mut is_dead_end : Bool
  mut is_inside_alternation : Bool
  mut contains_captures : Bool
  mut root_pattern_guaranteed : Bool
  mut parent_pattern_guaranteed : Bool
  mut is_missing : Bool
  mut alternative_is_skip : Bool
}

///|
fn QueryStep::new(symbol : Int, depth : Int, is_immediate : Bool) -> QueryStep {
  {
    symbol,
    supertype_symbol: 0,
    field: 0,
    capture_ids: FixedArray::make(max_step_capture_count, none),
    depth,
    alternative_index: none,
    negated_field_list_id: 0,
    is_named: false,
    is_immediate,
    is_last_child: false,
    is_pass_through: false,
    is_dead_end: false,
    is_inside_alternation: false,
    contains_captures: false,
    root_pattern_guaranteed: false,
    parent_pattern_guaranteed: false,
    is_missing: false,
    alternative_is_skip: false,
  }
}

///|
/// A value copy of a step (steps are plain structs upstream).
fn QueryStep::copy(self : QueryStep) -> QueryStep {
  { ..self, capture_ids: self.capture_ids.copy() }
}

///|
fn QueryStep::add_capture(self : QueryStep, capture_id : Int) -> Unit {
  let capture_id = capture_id & 0xFFFF // `uint16_t capture_id`
  for i in 0..<max_step_capture_count {
    if self.capture_ids[i] == none {
      self.capture_ids[i] = capture_id
      break
    }
  }
}

///|
fn QueryStep::remove_capture(self : QueryStep, capture_id : Int) -> Unit {
  let capture_id = capture_id & 0xFFFF // `uint16_t capture_id`
  for i in 0..<max_step_capture_count {
    if self.capture_ids[i] == capture_id {
      self.capture_ids[i] = none
      let mut j = i
      while j + 1 < max_step_capture_count {
        if self.capture_ids[j + 1] == none {
          break
        }
        self.capture_ids[j] = self.capture_ids[j + 1]
        self.capture_ids[j + 1] = none
        j += 1
      }
      break
    }
  }
}

///|
/// StatePredecessorMap - A map that stores the predecessors of each parse
/// state. This is used during query analysis to determine which parse states
/// can lead to which reduce actions.
priv struct StatePredecessorMap {
  contents : FixedArray[Int]
}

///|
fn StatePredecessorMap::new(language : @language.Language) -> StatePredecessorMap {
  {
    contents: FixedArray::make(
      language.state_count * (max_state_predecessor_count + 1),
      0,
    ),
  }
}

///|
fn StatePredecessorMap::add(
  self : StatePredecessorMap,
  state : Int,
  predecessor : Int,
) -> Unit {
  let index = state * (max_state_predecessor_count + 1)
  let count = self.contents[index]
  if count == 0 ||
    (count < max_state_predecessor_count &&
    self.contents[index + count] != predecessor) {
    self.contents[index] = count + 1
    self.contents[index + count + 1] = predecessor
  }
}

///|
/// The predecessors of `state`.
fn StatePredecessorMap::get(
  self : StatePredecessorMap,
  state : Int,
) -> ArrayView[Int] {
  let index = state * (max_state_predecessor_count + 1)
  let count = self.contents[index]
  self.contents[index + 1:index + 1 + count]
}
