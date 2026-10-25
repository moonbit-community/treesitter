// Port of the rule IR in tree-sitter crates/generate/src/rules.rs.

///|
pub(all) struct RuleId(Int) derive(Eq, Hash, Compare, Debug)

///|
pub fn RuleId::index(self : RuleId) -> Int {
  self.0
}

///|
pub(all) struct ParamsId(Int) derive(Eq, Hash, Debug)

///|
/// A `[start, start + len)` slice of `RulePool::children`.
pub(all) struct RuleIdRange {
  start : Int
  len : Int
} derive(Eq, Hash, Debug)

///|
pub(all) struct MetadataParams {
  precedence : Precedence
  associativity : Associativity?
  dynamic_precedence : Int
  alias : Alias?
  field : StrId?
  is_token : Bool
  is_main_token : Bool
} derive(Eq, Hash, Debug)

///|
pub let default_params : MetadataParams = {
  precedence: NoPrecedence,
  associativity: None,
  dynamic_precedence: 0,
  alias: None,
  field: None,
  is_token: false,
  is_main_token: false,
}

///|
/// A pooled rule node.
pub(all) enum Rule {
  Blank
  String(StrId)
  Pattern(StrId, StrId)
  NamedSymbol(StrId)
  Sym(Symbol)
  Seq(RuleIdRange)
  Choice(RuleIdRange)
  Repeat(RuleId)
  Eof
  Metadata(params~ : ParamsId, rule~ : RuleId)
  Reserved(rule~ : RuleId, ctx~ : StrId)
} derive(Eq, Hash, Debug)

///|
pub fn Rule::symbol(self : Rule) -> Symbol? {
  match self {
    Sym(symbol) => Some(symbol)
    _ => None
  }
}

///|
/// The arena: nodes, their pooled children/params, and the string interner.
/// Storage is append-only; passes rewrite nodes in place and may orphan subtrees.
pub struct RulePool {
  priv nodes : Array[Rule]
  priv children : Array[RuleId]
  priv params : Array[MetadataParams]
  str_pool : StrPool
}

///|
pub fn RulePool::new() -> RulePool {
  { nodes: [], children: [], params: [], str_pool: StrPool::new() }
}

///|
pub fn RulePool::node(self : RulePool, id : RuleId) -> Rule {
  self.nodes[id.0]
}

///|
pub fn RulePool::node_count(self : RulePool) -> Int {
  self.nodes.length()
}

///|
pub fn RulePool::set_node(self : RulePool, id : RuleId, node : Rule) -> Unit {
  self.nodes[id.0] = node
}

///|
pub fn RulePool::push_node(self : RulePool, node : Rule) -> RuleId {
  let id = RuleId(self.nodes.length())
  self.nodes.push(node)
  id
}

///|
pub fn RulePool::child_slice(
  self : RulePool,
  range : RuleIdRange,
) -> ArrayView[RuleId] {
  self.children[range.start:range.start + range.len]
}

///|
pub fn RulePool::push_children(
  self : RulePool,
  ids : ArrayView[RuleId],
) -> RuleIdRange {
  let start = self.children.length()
  for id in ids {
    self.children.push(id)
  }
  { start, len: ids.length() }
}

///|
pub fn RulePool::params(self : RulePool, id : ParamsId) -> MetadataParams {
  self.params[id.0]
}

///|
pub fn RulePool::push_params(
  self : RulePool,
  params : MetadataParams,
) -> ParamsId {
  let id = ParamsId(self.params.length())
  self.params.push(params)
  id
}

///|
pub fn RulePool::set_params(
  self : RulePool,
  id : ParamsId,
  params : MetadataParams,
) -> Unit {
  self.params[id.0] = params
}

///|
fn RulePool::metadata_with(
  self : RulePool,
  content : RuleId,
  f : (MetadataParams) -> MetadataParams,
) -> RuleId {
  if self.node(content) is Metadata(params~, ..) {
    let p = self.params(params)
    if !p.is_token {
      self.set_params(params, f(p))
      return content
    }
  }
  let params = self.push_params(f(default_params))
  self.push_node(Metadata(params~, rule=content))
}

///|
pub fn RulePool::blank(self : RulePool) -> RuleId {
  self.push_node(Blank)
}

///|
pub fn RulePool::string(self : RulePool, value : StrId) -> RuleId {
  self.push_node(String(value))
}

///|
pub fn RulePool::pattern(
  self : RulePool,
  value : StrId,
  flags : StrId,
) -> RuleId {
  self.push_node(Pattern(value, flags))
}

///|
pub fn RulePool::named_symbol(self : RulePool, name : StrId) -> RuleId {
  self.push_node(NamedSymbol(name))
}

///|
pub fn RulePool::field(
  self : RulePool,
  name : StrId,
  content : RuleId,
) -> RuleId {
  self.metadata_with(content, p => { ..p, field: Some(name) })
}

///|
pub fn RulePool::alias(
  self : RulePool,
  content : RuleId,
  value : StrId,
  is_named : Bool,
) -> RuleId {
  self.metadata_with(content, p => { ..p, alias: Some({ value, is_named }) })
}

///|
pub fn RulePool::token(self : RulePool, content : RuleId) -> RuleId {
  self.metadata_with(content, p => { ..p, is_token: true })
}

///|
pub fn RulePool::immediate_token(self : RulePool, content : RuleId) -> RuleId {
  self.metadata_with(content, p => { ..p, is_token: true, is_main_token: true })
}

///|
pub fn RulePool::prec(
  self : RulePool,
  value : Precedence,
  content : RuleId,
) -> RuleId {
  self.metadata_with(content, p => { ..p, precedence: value })
}

///|
pub fn RulePool::prec_left(
  self : RulePool,
  value : Precedence,
  content : RuleId,
) -> RuleId {
  self.metadata_with(content, p => {
    { ..p, associativity: Some(Left), precedence: value }
  })
}

///|
pub fn RulePool::prec_right(
  self : RulePool,
  value : Precedence,
  content : RuleId,
) -> RuleId {
  self.metadata_with(content, p => {
    { ..p, associativity: Some(Right), precedence: value }
  })
}

///|
pub fn RulePool::prec_dynamic(
  self : RulePool,
  value : Int,
  content : RuleId,
) -> RuleId {
  self.metadata_with(content, p => { ..p, dynamic_precedence: value })
}

///|
pub fn RulePool::repeat(self : RulePool, content : RuleId) -> RuleId {
  self.push_node(Repeat(content))
}

///|
pub fn RulePool::eof(self : RulePool) -> RuleId {
  self.push_node(Eof)
}

///|
pub fn RulePool::seq(self : RulePool, ids : ArrayView[RuleId]) -> RuleId {
  let range = self.push_children(ids)
  self.push_node(Seq(range))
}

///|
/// Build a sequence whose elements are produced by `f`, reserving the child
/// slots before any element is built (matching upstream's `try_seq`).
pub fn[T, E : Error] RulePool::try_seq(
  self : RulePool,
  items : ArrayView[T],
  f : (RulePool, T) -> RuleId raise E,
) -> RuleId raise E {
  let len = items.length()
  let start = self.children.length()
  for _ in 0..<len {
    self.children.push(RuleId(0))
  }
  for i, item in items {
    let id = f(self, item)
    self.children[start + i] = id
  }
  self.push_node(Seq({ start, len }))
}

///|
/// Flatten nested choices and de-dup structurally, keeping a `Choice` node
/// even for a single element.
pub fn RulePool::choice(self : RulePool, ids : ArrayView[RuleId]) -> RuleId {
  let start = self.children.length()
  let stack : Array[RuleId] = []
  for i = ids.length() - 1; i >= 0; i = i - 1 {
    stack.push(ids[i])
  }
  while stack.pop() is Some(id) {
    if self.node(id) is Choice(range) {
      let slice = self.child_slice(range)
      for i = slice.length() - 1; i >= 0; i = i - 1 {
        stack.push(slice[i])
      }
    } else {
      let mut found = false
      for i in start..<self.children.length() {
        if self.subtree_eq(self.children[i], id) {
          found = true
          break
        }
      }
      if !found {
        self.children.push(id)
      }
    }
  }
  let range = { start, len: self.children.length() - start }
  self.push_node(Choice(range))
}

///|
pub fn RulePool::reserved(
  self : RulePool,
  content : RuleId,
  ctx : StrId,
) -> RuleId {
  self.push_node(Reserved(rule=content, ctx~))
}

///|
pub fn RulePool::intern(self : RulePool, s : StringView) -> StrId {
  self.str_pool.intern(s)
}

///|
pub fn RulePool::resolve(self : RulePool, id : StrId) -> String {
  self.str_pool.resolve(id)
}

///|
/// Structural hash of a subtree. Only used for bucketing; any equality decision
/// goes through `subtree_eq`.
pub fn RulePool::subtree_hash(self : RulePool, root : RuleId) -> Int {
  let hasher = Hasher()
  let stack = [root]
  while stack.pop() is Some(id) {
    let node = self.node(id)
    match node {
      Blank => hasher.combine_int(0)
      Eof => hasher.combine_int(8)
      String(s) => {
        hasher.combine_int(1)
        hasher.combine(s)
      }
      NamedSymbol(s) => {
        hasher.combine_int(3)
        hasher.combine(s)
      }
      Pattern(p, f) => {
        hasher.combine_int(2)
        hasher.combine(p)
        hasher.combine(f)
      }
      Sym(symbol) => {
        hasher.combine_int(4)
        hasher.combine(symbol)
      }
      Seq(range) | Choice(range) => {
        hasher.combine_int(if node is Seq(_) { 5 } else { 6 })
        hasher.combine_int(range.len)
        let slice = self.child_slice(range)
        for i = slice.length() - 1; i >= 0; i = i - 1 {
          stack.push(slice[i])
        }
      }
      Repeat(inner) => {
        hasher.combine_int(7)
        stack.push(inner)
      }
      Metadata(params~, rule~) => {
        hasher.combine_int(9)
        hasher.combine(self.params(params))
        stack.push(rule)
      }
      Reserved(rule~, ctx~) => {
        hasher.combine_int(10)
        hasher.combine(ctx)
        stack.push(rule)
      }
    }
  }
  hasher.finalize()
}

///|
pub fn RulePool::subtree_eq(self : RulePool, a : RuleId, b : RuleId) -> Bool {
  let stack = [(a, b)]
  while stack.pop() is Some((a, b)) {
    match (self.node(a), self.node(b)) {
      (Blank, Blank) | (Eof, Eof) => ()
      (String(x), String(y)) | (NamedSymbol(x), NamedSymbol(y)) =>
        if x != y {
          return false
        }
      (Pattern(p1, f1), Pattern(p2, f2)) =>
        if p1 != p2 || f1 != f2 {
          return false
        }
      (Sym(s1), Sym(s2)) => if s1 != s2 { return false }
      (Seq(r1), Seq(r2)) | (Choice(r1), Choice(r2)) => {
        if r1.len != r2.len {
          return false
        }
        let s1 = self.child_slice(r1)
        let s2 = self.child_slice(r2)
        for i in 0..<s1.length() {
          stack.push((s1[i], s2[i]))
        }
      }
      (Repeat(i1), Repeat(i2)) => stack.push((i1, i2))
      (Metadata(params=p1, rule=r1), Metadata(params=p2, rule=r2)) => {
        if self.params(p1) != self.params(p2) {
          return false
        }
        stack.push((r1, r2))
      }
      (Reserved(rule=r1, ctx=c1), Reserved(rule=r2, ctx=c2)) => {
        if c1 != c2 {
          return false
        }
        stack.push((r1, r2))
      }
      _ => return false
    }
  }
  true
}

///|
/// Whether the subtree at `id` can only match the empty string.
pub fn RulePool::subtree_matches_empty_str(self : RulePool, id : RuleId) -> Bool {
  match self.node(id) {
    String(sid) => self.resolve(sid).is_empty()
    Metadata(rule~, ..) | Repeat(rule) | Reserved(rule~, ..) =>
      self.subtree_matches_empty_str(rule)
    Choice(range) =>
      self.child_slice(range).iter().any(c => self.subtree_matches_empty_str(c))
    Seq(range) =>
      self.child_slice(range).iter().all(c => self.subtree_matches_empty_str(c))
    _ => false
  }
}

///|
/// Check if a rule is referenced by another rule. `is_external` means that a
/// top-level named symbol equal to `target` names the external itself.
pub fn RulePool::rule_is_referenced(
  self : RulePool,
  id : RuleId,
  target : StrId,
  is_external : Bool,
) -> Bool {
  match self.node(id) {
    NamedSymbol(name) => name == target && !is_external
    Choice(range) | Seq(range) =>
      self
      .child_slice(range)
      .iter()
      .any(c => self.rule_is_referenced(c, target, false))
    Metadata(rule~, ..) | Reserved(rule~, ..) =>
      self.rule_is_referenced(rule, target, is_external)
    Repeat(inner) => self.rule_is_referenced(inner, target, false)
    Blank | Eof | String(_) | Pattern(_, _) | Sym(_) => false
  }
}

///|
/// Append every `NamedSymbol` name reachable in `id` to `out`. If
/// `skip_top_level` is true, a `NamedSymbol` at the root is ignored.
pub fn RulePool::collect_referenced_ids(
  self : RulePool,
  id : RuleId,
  skip_top_level : Bool,
  out : Array[StrId],
) -> Unit {
  match self.node(id) {
    NamedSymbol(name) => if !skip_top_level { out.push(name) }
    Choice(range) | Seq(range) =>
      for c in self.child_slice(range) {
        self.collect_referenced_ids(c, false, out)
      }
    Metadata(rule~, ..) | Reserved(rule~, ..) =>
      self.collect_referenced_ids(rule, skip_top_level, out)
    Repeat(inner) => self.collect_referenced_ids(inner, false, out)
    Blank | Eof | String(_) | Pattern(_, _) | Sym(_) => ()
  }
}

///|
/// Upstream `AliasMap` is a `BTreeMap<Symbol, Alias>`; iteration is sorted by symbol.
pub type AliasMap = @sorted_map.SortedMap[Symbol, Alias]
