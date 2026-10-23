// Port of tree-sitter crates/generate/src/node_types.rs (the `load`-feature
// half: `generate_node_types_json` and the `node-types.json` serializer).

///|
/// `Eq`/`Debug` are used by the white-box tests only.
#warnings("-unused_value")
priv struct NodeInfoJSON {
  kind : StrId
  named : Bool
  root : Bool
  extra : Bool
  fields : NodeFields?
  mut children : FieldInfoJSON?
  mut subtypes : Array[NodeTypeRef]?
} derive(Eq, Debug)

///|
priv struct NodeTypeRef {
  kind : StrId
  named : Bool
} derive(Eq, Hash, Compare, Debug)

///|
priv struct FieldInfoJSON {
  mut multiple : Bool
  mut required : Bool
  types : Array[NodeTypeRef]
} derive(Eq, Debug)

///|
/// Upstream `impl Default for FieldInfoJSON`.
fn FieldInfoJSON::default() -> FieldInfoJSON {
  { multiple: false, required: true, types: [], }
}

///|
/// Upstream `BTreeMap<StrId, FieldInfoJSON>`.
type NodeFields = @sorted_map.SortedMap[StrId, FieldInfoJSON]

///|
/// `node_types::SuperTypeCycleError`.
pub(all) suberror SuperTypeCycleError {
  SuperTypeCycleError(items~ : Array[String])
} derive(Eq, Debug)

///|
pub impl Show for SuperTypeCycleError with fn output(self, logger) {
  let SuperTypeCycleError(items~) = self
  logger.write_string("Dependency cycle detected in node types:")
  for i, item in items {
    logger.write_string(" \{item}")
    if i < items.length() - 1 {
      logger.write_string(",")
    }
  }
}

///|
/// `node_types::generate_node_types_json`: the exact `node-types.json` text
/// (`serde_json::to_string_pretty`).
pub fn generate_node_types_json(
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  default_aliases : AliasMap,
  variable_info : Array[VariableInfo],
  inlines : InlinedProductionMap,
  str_pool : StrPool,
) -> String raise {
  let nodes = generate_node_types(
    syntax_grammar, lexical_grammar, default_aliases, variable_info, inlines, str_pool,
  )
  to_string_pretty(serialize_node_infos(nodes, str_pool))
}

///|
fn generate_node_types(
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  default_aliases : AliasMap,
  variable_info : Array[VariableInfo],
  inlines : InlinedProductionMap,
  str_pool : StrPool,
) -> Array[NodeInfoJSON] raise SuperTypeCycleError {
  let aliases_by_symbol = get_aliases_by_symbol(
    syntax_grammar, default_aliases, inlines,
  )
  let extra_node_types = collect_extra_node_types(
    syntax_grammar, lexical_grammar, aliases_by_symbol,
  )
  let node_types_json : @sorted_map.SortedMap[NodeTypeRef, NodeInfoJSON] = @sorted_map.SortedMap([],
  )
  let subtype_map = build_supertype_entries(
    node_types_json, syntax_grammar, lexical_grammar, default_aliases, variable_info,
    str_pool, extra_node_types,
  )
  build_regular_entries(
    node_types_json, syntax_grammar, lexical_grammar, default_aliases, variable_info,
    str_pool, aliases_by_symbol, extra_node_types,
  )
  sort_subtype_map_topologically(subtype_map, str_pool)
  apply_supertype_collapsing(node_types_json, subtype_map)
  build_token_entries(
    node_types_json, syntax_grammar, lexical_grammar, aliases_by_symbol, extra_node_types,
  )
  let result = node_types_json.values().collect()
  // Upstream uses `sort_unstable_by`; entries have distinct `(kind, named)`
  // and distinct kinds resolve to distinct strings, so there are no ties.
  stable_sort_by(result, (a, b) => {
    let c = (b.subtypes is Some(_)).compare(a.subtypes is Some(_))
    if c != 0 {
      return c
    }
    let a_is_leaf = a.children is None && a.fields is None
    let b_is_leaf = b.children is None && b.fields is None
    let c = a_is_leaf.compare(b_is_leaf)
    if c != 0 {
      return c
    }
    let c = cmp_str_ids(a.kind, b.kind, str_pool)
    if c != 0 {
      return c
    }
    a.named.compare(b.named)
  })
  result
}

///|
/// Convert a child type into its JSON representation, resolving any alias.
fn child_type_to_node_type(
  child_type : ChildType,
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  default_aliases : AliasMap,
) -> NodeTypeRef {
  match child_type {
    Aliased(alias) => { kind: alias.value, named: alias.is_named, }
    Normal(symbol) =>
      match default_aliases.get(symbol) {
        Some(alias) => { kind: alias.value, named: alias.is_named, }
        None =>
          match symbol.kind {
            NonTerminal => {
              let variable = syntax_grammar.variables[symbol.index]
              { kind: variable.name, named: variable.kind != Anonymous, }
            }
            Terminal => {
              let variable = lexical_grammar.variables[symbol.index]
              { kind: variable.name, named: variable.kind != Anonymous, }
            }
            External => {
              let variable = syntax_grammar.external_tokens[symbol.index]
              { kind: variable.name, named: variable.kind != Anonymous, }
            }
            End | EndOfNonTerminalExtra => abort("Unexpected symbol type")
          }
      }
  }
}

///|
/// Merge a field's computed info into its JSON representation. No types
/// means the field is absent from this rule, so it can't be required.
fn populate_field_info_json(
  json : FieldInfoJSON,
  info : FieldInfo,
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  default_aliases : AliasMap,
  str_pool : StrPool,
) -> Unit {
  if info.types.is_empty() {
    json.required = false
  } else {
    json.multiple = json.multiple || info.quantity.multiple
    json.required = json.required && info.quantity.required
    for t in info.types {
      json.types.push(
        child_type_to_node_type(
          t, syntax_grammar, lexical_grammar, default_aliases,
        ),
      )
    }
    sort_node_type_refs(json.types, str_pool)
    dedup(json.types)
  }
}

///|
/// Collect every node identity an `extra` symbol can appear under, including aliases.
/// Upstream collects into an `FxHashSet`, used only for membership tests.
fn collect_extra_node_types(
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  aliases_by_symbol : Map[Symbol, @sorted_set.SortedSet[Alias?]],
) -> Map[NodeTypeRef, Unit] {
  let result : Map[NodeTypeRef, Unit] = Map([])
  for symbol in syntax_grammar.extra_symbols {
    guard aliases_by_symbol.get(symbol) is Some(aliases) else { continue }
    for alias in aliases {
      let (kind, variable_type) = match alias {
        None =>
          match symbol.kind {
            NonTerminal => {
              let variable = syntax_grammar.variables[symbol.index]
              (variable.name, variable.kind)
            }
            Terminal => {
              let variable = lexical_grammar.variables[symbol.index]
              (variable.name, variable.kind)
            }
            External => {
              let variable = syntax_grammar.external_tokens[symbol.index]
              (variable.name, variable.kind)
            }
            // `eof()` in an extra is rejected during lexical separator expansion, so
            // `End` cannot reach `SyntaxGrammar::extra_symbols`.
            // Lookahead marker that `build_parse_table` inserts for nonterminal
            // extras _after_ this pass runs.
            End | EndOfNonTerminalExtra => abort("unreachable")
          }
        Some(alias) => (alias.value, alias.kind())
      }
      result[{ kind, named: variable_type != Anonymous, }] = ()
    }
  }
  result
}

///|
/// Add one JSON entry per supertype and build the supertype-to-subtypes map.
fn build_supertype_entries(
  node_types_json : @sorted_map.SortedMap[NodeTypeRef, NodeInfoJSON],
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  default_aliases : AliasMap,
  variable_info : Array[VariableInfo],
  str_pool : StrPool,
  extra_node_types : Map[NodeTypeRef, Unit],
) -> Array[(NodeTypeRef, Array[NodeTypeRef])] {
  let subtype_map = []
  for i, info in variable_info {
    let symbol = Symbol::non_terminal(i)
    if !syntax_grammar.supertype_symbols.contains(symbol) {
      continue
    }
    let variable = syntax_grammar.variables[i]
    let node_type : NodeTypeRef = { kind: variable.name, named: true, }
    let node_type_json = node_types_json.get_or_init(node_type, () => {
      kind: variable.name,
      named: true,
      root: false,
      extra: extra_node_types.contains(node_type),
      fields: None,
      children: None,
      subtypes: None,
    })
    let subtypes = info.children.types.map(t => {
      child_type_to_node_type(
        t, syntax_grammar, lexical_grammar, default_aliases,
      )
    })
    sort_node_type_refs(subtypes, str_pool)
    dedup(subtypes)
    let supertype : NodeTypeRef = { kind: node_type_json.kind, named: true, }

    // We only add to the subtype map if there are visible subtypes.
    // A supertype may have zero subtypes if its children are all
    // hidden (e.g., wrapping a hidden external token).
    if !subtypes.is_empty() {
      subtype_map.push((supertype, subtypes.copy()))
    }
    node_type_json.subtypes = Some(subtypes)
  }
  subtype_map
}

///|
/// Add JSON entries for visible non-supertype rules and aliased supertypes (treated
/// as regular, concrete nodes), merged into every regular name they can appear under.
fn build_regular_entries(
  node_types_json : @sorted_map.SortedMap[NodeTypeRef, NodeInfoJSON],
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  default_aliases : AliasMap,
  variable_info : Array[VariableInfo],
  str_pool : StrPool,
  aliases_by_symbol : Map[Symbol, @sorted_set.SortedSet[Alias?]],
  extra_node_types : Map[NodeTypeRef, Unit],
) -> Unit {
  for i, info in variable_info {
    let symbol = Symbol::non_terminal(i)
    // Inlined symbols don't have their own node-types entries.
    if syntax_grammar.variables_to_inline.contains(symbol) {
      continue
    }
    let is_supertype = syntax_grammar.supertype_symbols.contains(symbol)
    let variable = syntax_grammar.variables[i]

    // If a rule is aliased under multiple names, then its information
    // contributes to multiple entries in the final JSON.
    guard aliases_by_symbol.get(symbol) is Some(aliases) else { continue }
    for alias in aliases {
      // The canonical supertype is emitted separately with its subtypes.
      // An alias of that supertype is treated as a regular, visible node
      // and handled here.
      if is_supertype && alias is None {
        continue
      }
      let (kind, is_named) = if alias is Some(alias) {
        (alias.value, alias.is_named)
      } else if variable.kind.is_visible() {
        (variable.name, variable.kind == Named)
      } else {
        continue
      }

      // There may already be an entry with this node identity, because multiple
      // rules may be aliased with the same name and namedness.
      let mut node_type_existed = true
      let node_type : NodeTypeRef = { kind, named: is_named, }
      let node_type_json = node_types_json.get_or_init(node_type, () => {
        node_type_existed = false
        {
          kind,
          named: is_named,
          root: i == 0,
          extra: extra_node_types.contains(node_type),
          fields: Some(@sorted_map.SortedMap([])),
          children: None,
          subtypes: None,
        }
      })
      let fields_json = node_type_json.fields.unwrap()
      for new_field, field_info in info.fields {
        let field_json = fields_json.get_or_init(new_field, () => {
          // If another rule is aliased with the same node identity, and
          // does *not* have this field, then this field cannot be required.
          let field_json = FieldInfoJSON::default()
          if node_type_existed {
            field_json.required = false
          }
          field_json
        })
        populate_field_info_json(
          field_json, field_info, syntax_grammar, lexical_grammar, default_aliases,
          str_pool,
        )
      }

      // If another rule is aliased with the same node identity, any fields
      // that aren't present in this cannot be required.
      for existing_field, field_json in fields_json {
        if !info.fields.contains(existing_field) {
          field_json.required = false
        }
      }
      let children = match node_type_json.children {
        Some(children) => children
        None => {
          let children = FieldInfoJSON::default()
          node_type_json.children = Some(children)
          children
        }
      }
      populate_field_info_json(
        children,
        info.children_without_fields,
        syntax_grammar,
        lexical_grammar,
        default_aliases,
        str_pool,
      )
    }
  }
}

///|
/// Sort the subtype map topologically so that subtypes are listed before
/// their supertypes.
fn sort_subtype_map_topologically(
  subtype_map : Array[(NodeTypeRef, Array[NodeTypeRef])],
  str_pool : StrPool,
) -> Unit raise SuperTypeCycleError {
  let sorted_node_types = []
  let top_sort : TopologicalSort[NodeTypeRef] = TopologicalSort::new()
  for entry in subtype_map {
    let (supertype, subtypes) = entry
    for subtype in subtypes {
      top_sort.add_dependency(subtype, supertype)
    }
  }
  while true {
    let next_node_types = top_sort.pop_all()
    match (next_node_types.is_empty(), top_sort.is_empty()) {
      (true, true) => break
      (true, false) => {
        // Upstream maps the `TopologicalSort` iterator, which pops nodes with
        // no remaining predecessors. In a cycle there are none, so this
        // yields nothing, exactly as upstream.
        let items = []
        while top_sort.pop() is Some(node_type) {
          items.push(str_pool.resolve(node_type.kind))
        }
        stable_sort_by(items, cmp_str)
        raise SuperTypeCycleError(items~)
      }
      (false, _) => {
        sort_node_type_refs(next_node_types, str_pool)
        sorted_node_types.append(next_node_types)
      }
    }
  }
  stable_sort_by_key(subtype_map, entry => {
    sorted_node_types.search(entry.0).unwrap()
  })
}

///|
/// Collapse a supertype's subtypes into the supertype itself in child and
/// field type lists.
fn apply_supertype_collapsing(
  node_types_json : @sorted_map.SortedMap[NodeTypeRef, NodeInfoJSON],
  subtype_map : Array[(NodeTypeRef, Array[NodeTypeRef])],
) -> Unit {
  for node_type_json in node_types_json.values() {
    if node_type_json.children is Some(c) && c.types.is_empty() {
      node_type_json.children = None
    }
    if node_type_json.children is Some(children) {
      process_supertypes(children, subtype_map)
    }
    if node_type_json.fields is Some(fields) {
      for field_info in fields.values() {
        process_supertypes(field_info, subtype_map)
      }
    }
  }
}

///|
/// Add JSON entries for visible tokens.
fn build_token_entries(
  node_types_json : @sorted_map.SortedMap[NodeTypeRef, NodeInfoJSON],
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  aliases_by_symbol : Map[Symbol, @sorted_set.SortedSet[Alias?]],
  extra_node_types : Map[NodeTypeRef, Unit],
) -> Unit {
  let tokens : Array[(StrId, VariableType)] = []
  for i, variable in lexical_grammar.variables {
    guard aliases_by_symbol.get(Symbol::terminal(i)) is Some(aliases) else {
      continue
    }
    for alias in aliases {
      tokens.push(
        match alias {
          None => (variable.name, variable.kind)
          Some(alias) => (alias.value, alias.kind())
        },
      )
    }
  }
  for i, token in syntax_grammar.external_tokens {
    guard aliases_by_symbol.get(Symbol::external(i)) is Some(aliases) else {
      continue
    }
    for alias in aliases {
      tokens.push(
        match alias {
          None => (token.name, token.kind)
          Some(alias) => (alias.value, alias.kind())
        },
      )
    }
  }
  for entry in tokens {
    let (name, kind) = entry
    match kind {
      Named | Anonymous => {
        let named = kind == Named
        let node_type : NodeTypeRef = { kind: name, named, }
        match node_types_json.get(node_type) {
          Some(node_type_json) => {
            // This token is a leaf appearance of an existing node identity,
            // so children and fields from other appearances are optional.
            if node_type_json.children is Some(children) {
              children.required = false
            }
            if node_type_json.fields is Some(fields) {
              for field in fields.values() {
                field.required = false
              }
            }
          }
          None =>
            node_types_json[node_type] = {
              kind: name,
              named,
              root: false,
              extra: extra_node_types.contains(node_type),
              fields: None,
              children: None,
              subtypes: None,
            }
        }
      }
      _ => ()
    }
  }
}

///|
fn process_supertypes(
  info : FieldInfoJSON,
  subtype_map : Array[(NodeTypeRef, Array[NodeTypeRef])],
) -> Unit {
  for entry in subtype_map {
    let (supertype, subtypes) = entry
    if info.types.contains(supertype) {
      info.types.retain(t => !subtypes.contains(t))
    }
  }
}

///|
/// Rust's `str::cmp`: lexicographic UTF-8 byte order, which equals Unicode
/// scalar value order. MoonBit's `String::compare` orders by length first.
fn cmp_str(a : String, b : String) -> Int32 {
  let ai = a.iter()
  let bi = b.iter()
  while true {
    match (ai.next(), bi.next()) {
      (None, None) => return 0
      (None, Some(_)) => return -1
      (Some(_), None) => return 1
      (Some(x), Some(y)) => {
        let c = x.compare(y)
        if c != 0 {
          return c
        }
      }
    }
  }
  0
}

///|
fn cmp_str_ids(a : StrId, b : StrId, str_pool : StrPool) -> Int32 {
  cmp_str(str_pool.resolve(a), str_pool.resolve(b))
}

///|
/// Upstream uses `sort_unstable_by`; elements comparing equal are identical.
fn sort_node_type_refs(types : Array[NodeTypeRef], str_pool : StrPool) -> Unit {
  stable_sort_by(types, (a, b) => {
    let c = cmp_str_ids(a.kind, b.kind, str_pool)
    if c != 0 {
      c
    } else {
      a.named.compare(b.named)
    }
  })
}

// The `topological-sort 0.2.2` crate, reduced to the operations used above.

///|
priv struct Dependency[T] {
  mut num_prec : Int32
  succ : Map[T, Unit]
}

///|
priv struct TopologicalSort[T] {
  top : Map[T, Dependency[T]]
}

///|
fn[T : Hash + Eq] TopologicalSort::new() -> TopologicalSort[T] {
  { top: Map([]), }
}

///|
fn[T] TopologicalSort::is_empty(self : TopologicalSort[T]) -> Bool {
  self.top.is_empty()
}

///|
fn[T : Hash + Eq] TopologicalSort::add_dependency(
  self : TopologicalSort[T],
  prec : T,
  succ : T,
) -> Unit {
  match self.top.get(prec) {
    None => {
      let dep = { num_prec: 0, succ: Map([]), }
      dep.succ[succ] = ()
      self.top[prec] = dep
    }
    Some(dep) => {
      if dep.succ.contains(succ) {
        return
      }
      dep.succ[succ] = ()
    }
  }
  match self.top.get(succ) {
    None => self.top[succ] = { num_prec: 1, succ: Map([]), }
    Some(dep) => dep.num_prec += 1
  }
}

///|
/// All nodes without predecessors, removed. Upstream returns them in hash
/// order; the only caller sorts them.
fn[T : Hash + Eq] TopologicalSort::pop_all(
  self : TopologicalSort[T],
) -> Array[T] {
  let keys = []
  for k, v in self.top {
    if v.num_prec == 0 {
      keys.push(k)
    }
  }
  for k in keys {
    self.remove(k)
  }
  keys
}

///|
fn[T : Hash + Eq] TopologicalSort::pop(self : TopologicalSort[T]) -> T? {
  let mut key = None
  for k, v in self.top {
    if v.num_prec == 0 {
      key = Some(k)
      break
    }
  }
  if key is Some(k) {
    self.remove(k)
  }
  key
}

///|
fn[T : Hash + Eq] TopologicalSort::remove(
  self : TopologicalSort[T],
  prec : T,
) -> Unit {
  guard self.top.get(prec) is Some(p) else { return }
  self.top.remove(prec)
  for s, _ in p.succ {
    if self.top.get(s) is Some(y) {
      y.num_prec -= 1
    }
  }
}

// `SerializeWithPool` impls: build a JSON tree in serde's field order, then
// print it exactly as `serde_json::to_string_pretty` does.

///|
priv enum PrettyJson {
  Bool(Bool)
  Str(String)
  Arr(Array[PrettyJson])
  Obj(Array[(String, PrettyJson)])
}

///|
fn serialize_node_infos(
  nodes : Array[NodeInfoJSON],
  str_pool : StrPool,
) -> PrettyJson {
  Arr(nodes.map(node => serialize_node_info(node, str_pool)))
}

///|
fn serialize_node_type_ref(
  node_type : NodeTypeRef,
  str_pool : StrPool,
) -> PrettyJson {
  Obj([
    ("type", Str(str_pool.resolve(node_type.kind))),
    ("named", Bool(node_type.named)),
  ])
}

///|
fn serialize_node_type_refs(
  node_types : Array[NodeTypeRef],
  str_pool : StrPool,
) -> PrettyJson {
  Arr(node_types.map(t => serialize_node_type_ref(t, str_pool)))
}

///|
fn serialize_field_info(info : FieldInfoJSON, str_pool : StrPool) -> PrettyJson {
  Obj([
    ("multiple", Bool(info.multiple)),
    ("required", Bool(info.required)),
    ("types", serialize_node_type_refs(info.types, str_pool)),
  ])
}

///|
fn serialize_node_fields(fields : NodeFields, str_pool : StrPool) -> PrettyJson {
  let fields = fields.to_array()
  // Upstream `sort_unstable_by` on distinct field names.
  stable_sort_by(fields, (a, b) => cmp_str_ids(a.0, b.0, str_pool))
  Obj(
    fields.map(entry => {
      let (name, field_info) = entry
      (str_pool.resolve(name), serialize_field_info(field_info, str_pool))
    }),
  )
}

///|
fn serialize_node_info(node : NodeInfoJSON, str_pool : StrPool) -> PrettyJson {
  let state = [
    ("type", Str(str_pool.resolve(node.kind))),
    ("named", Bool(node.named)),
  ]
  if node.root {
    state.push(("root", Bool(node.root)))
  }
  if node.extra {
    state.push(("extra", Bool(node.extra)))
  }
  if node.fields is Some(fields) {
    state.push(("fields", serialize_node_fields(fields, str_pool)))
  }
  if node.children is Some(children) {
    state.push(("children", serialize_field_info(children, str_pool)))
  }
  if node.subtypes is Some(subtypes) {
    state.push(("subtypes", serialize_node_type_refs(subtypes, str_pool)))
  }
  Obj(state)
}

///|
/// `serde_json::to_string_pretty`: two-space indentation, `": "` after keys,
/// empty containers printed as `[]`/`{}`, no trailing newline.
fn to_string_pretty(value : PrettyJson) -> String {
  let buf = StringBuilder()
  write_pretty(buf, value, 0)
  buf.to_string()
}

///|
fn write_indent(buf : StringBuilder, level : Int32) -> Unit {
  for _ in 0..<level {
    buf.write_string("  ")
  }
}

///|
fn write_pretty(buf : StringBuilder, value : PrettyJson, level : Int32) -> Unit {
  match value {
    Bool(b) => buf.write_string(if b { "true" } else { "false" })
    Str(s) => write_json_string(buf, s)
    Arr(items) => {
      buf.write_char('[')
      for i, item in items {
        buf.write_string(if i == 0 { "\n" } else { ",\n" })
        write_indent(buf, level + 1)
        write_pretty(buf, item, level + 1)
      }
      if !items.is_empty() {
        buf.write_char('\n')
        write_indent(buf, level)
      }
      buf.write_char(']')
    }
    Obj(entries) => {
      buf.write_char('{')
      for i, entry in entries {
        let (key, item) = entry
        buf.write_string(if i == 0 { "\n" } else { ",\n" })
        write_indent(buf, level + 1)
        write_json_string(buf, key)
        buf.write_string(": ")
        write_pretty(buf, item, level + 1)
      }
      if !entries.is_empty() {
        buf.write_char('\n')
        write_indent(buf, level)
      }
      buf.write_char('}')
    }
  }
}

///|
/// serde_json's `format_escaped_str`: escape `"`, `\` and C0 controls (the
/// usual short forms, otherwise `\u00xx` with lowercase hex); everything else,
/// including DEL and non-ASCII, is written verbatim.
fn write_json_string(buf : StringBuilder, s : String) -> Unit {
  let hex = "0123456789abcdef"
  buf.write_char('"')
  for c in s {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\u{08}' => buf.write_string("\\b")
      '\u{0C}' => buf.write_string("\\f")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ =>
        if c.to_int() < 0x20 {
          let n = c.to_int()
          buf.write_string("\\u00")
          buf.write_char(hex.get_char(n >> 4).unwrap())
          buf.write_char(hex.get_char(n & 0xf).unwrap())
        } else {
          buf.write_char(c)
        }
    }
  }
  buf.write_char('"')
}
