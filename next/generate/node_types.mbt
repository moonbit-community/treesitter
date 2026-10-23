// Port of tree-sitter crates/generate/src/node_types.rs (variable info, the
// supertype symbol map and the error types). The `node-types.json` generation
// half lives in `node_types_json.mbt`.
//
// `ChildType`, `FieldInfo`, `VariableInfo` and `ChildQuantity` are defined in
// the foundation (`grammars.mbt`, `interfaces.mbt`). `ChildQuantity` is a
// `Copy` value upstream but a mutable record here, so every place where
// upstream copies one goes through `ChildQuantity::copy`.
//
// Upstream's `VariableInfo.fields` is an `FxHashMap`. Every loop over it below
// treats each field independently (per-field unions, per-field type merges,
// per-field JSON entries keyed by a sorted map), so its iteration order never
// reaches the output.

///|
pub impl Default for ChildQuantity with fn default() {
  ChildQuantity::one()
}

///|
fn ChildQuantity::zero() -> ChildQuantity {
  { exists: false, required: false, multiple: false, }
}

///|
fn ChildQuantity::one() -> ChildQuantity {
  { exists: true, required: true, multiple: false, }
}

///|
fn ChildQuantity::copy(self : ChildQuantity) -> ChildQuantity {
  { exists: self.exists, required: self.required, multiple: self.multiple, }
}

///|
fn ChildQuantity::append(self : ChildQuantity, other : ChildQuantity) -> Unit {
  if other.exists {
    if self.exists || other.multiple {
      self.multiple = true
    }
    if other.required {
      self.required = true
    }
    self.exists = true
  }
}

///|
fn ChildQuantity::union(self : ChildQuantity, other : ChildQuantity) -> Bool {
  let mut result = false
  if !self.exists && other.exists {
    result = true
    self.exists = true
  }
  if self.required && !other.required {
    result = true
    self.required = false
  }
  if !self.multiple && other.multiple {
    result = true
    self.multiple = true
  }
  result
}

///|
pub impl Default for FieldInfo with fn default() {
  { quantity: ChildQuantity::default(), types: [], }
}

///|
/// Upstream `FieldInfo::clone`.
fn FieldInfo::clone(self : FieldInfo) -> FieldInfo {
  { quantity: self.quantity.copy(), types: self.types.copy(), }
}

///|
pub impl Default for VariableInfo with fn default() {
  {
    fields: Map([]),
    children: FieldInfo::default(),
    children_without_fields: FieldInfo::default(),
    has_multi_step_production: false,
  }
}

///|
/// Upstream `VariableInfo::clone`.
fn VariableInfo::clone(self : VariableInfo) -> VariableInfo {
  let fields : Map[StrId, FieldInfo] = Map([])
  for name, info in self.fields {
    fields[name] = info.clone()
  }
  {
    fields,
    children: self.children.clone(),
    children_without_fields: self.children_without_fields.clone(),
    has_multi_step_production: self.has_multi_step_production,
  }
}

///|
/// `node_types::VariableInfoError`.
pub(all) suberror VariableInfoError {
  InvalidSupertype(InvalidSupertypeError)
  SupertypeAliasCollision(String)
} derive(Eq, Debug)

///|
pub impl Show for VariableInfoError with fn output(self, logger) {
  match self {
    // `#[error(transparent)]`
    InvalidSupertype(error) => error.output(logger)
    SupertypeAliasCollision(name) =>
      logger.write_string(
        "Named alias `\{name}` conflicts with a supertype of the same name.",
      )
  }
}

///|
/// `node_types::InvalidSupertypeError`.
pub(all) struct InvalidSupertypeError {
  supertype : String
  child : String?
} derive(Eq, Debug)

///|
pub impl Show for InvalidSupertypeError with fn output(self, logger) {
  let supertype = self.supertype
  logger.write_string(
    "Supertypes must have a single visible child, but `\{supertype}` can have multiple.",
  )
  if self.child is Some(child) {
    logger.write_string(
      " The hidden child `\{child}` can expand into multiple nodes. Consider making `\{child}` visible.",
    )
  }
}

///|
/// Compute a summary of the public-facing structure of each variable in the
/// grammar. Each variable in the grammar corresponds to a distinct public-facing
/// node type.
///
/// The information collected about each node type `N` is:
/// 1. `child_types` - The types of visible children that can appear within `N`.
/// 2. `fields` - The fields that `N` can have. Data regarding each field:
///    * `types` - The types of visible children the field can contain.
///    * `optional` - Do `N` nodes always have this field?
///    * `multiple` - Can `N` nodes have multiple children for this field?
/// 3. `children_without_fields` - The *other* named children of `N` that are not associated with
///    fields. Data regarding these children:
///    * `types` - The types of named children with no field.
///    * `optional` - Do `N` nodes always have at least one named child with no field?
///    * `multiple` - Can `N` nodes have multiple named children with no field?
///
/// Each summary must account for some indirect factors:
/// 1. hidden nodes. When a parent node `N` has a hidden child `C`, the visible children of `C`
///    *appear* to be direct children of `N`.
/// 2. aliases. If a parent node type `M` is aliased as some other type `N`, then nodes which
///    *appear* to have type `N` may have internal structure based on `M`.
pub fn get_variable_info(
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  default_aliases : AliasMap,
  inlines : InlinedProductionMap,
  str_pool : StrPool,
) -> Array[VariableInfo] raise {
  validate_supertype_aliases(syntax_grammar, default_aliases, inlines, str_pool)
  let result = compute_variable_info_fixed_point(
    syntax_grammar, lexical_grammar, default_aliases, inlines,
  )
  validate_supertype_structure(
    result, syntax_grammar, lexical_grammar, default_aliases, inlines, str_pool,
  )
  strip_hidden_child_types(result, syntax_grammar, lexical_grammar)
  result
}

///|
/// The production ids an original production stands for: its fully inlined
/// replacements, or itself (upstream's `unwrap_or(from_ref(&original_prod_id))`).
fn production_ids_for(
  inlines : InlinedProductionMap,
  original_prod_id : Int32,
) -> ArrayView[Int32] {
  match inlines.fully_inlined_prod_ids(original_prod_id) {
    Some(ids) => ids
    None => [original_prod_id][:]
  }
}

///|
/// Reject aliases that have the same public identity as a canonical supertype.
/// The node-types schema cannot represent one identity as both an abstract supertype
/// and a concrete aliased node.
fn validate_supertype_aliases(
  syntax_grammar : SyntaxGrammar,
  default_aliases : AliasMap,
  inlines : InlinedProductionMap,
  str_pool : StrPool,
) -> Unit raise VariableInfoError {
  let aliases_by_symbol = get_aliases_by_symbol(
    syntax_grammar, default_aliases, inlines,
  )
  for supertype_symbol in syntax_grammar.supertype_symbols {
    guard supertype_symbol.non_terminal_index() is Some(index) else {
      abort("unreachable")
    }
    let supertype = syntax_grammar.variables[index]
    let collision : Alias = { value: supertype.name, is_named: true, }
    if aliases_by_symbol
      .values()
      .any(aliases => aliases.contains(Some(collision))) {
      raise SupertypeAliasCollision(str_pool.resolve(supertype.name))
    }
  }
}

///|
/// Iteratively compute variable info for every syntax variable until a fixed
/// point is reached. Each variable's summary can depend on the summaries of
/// other hidden variables, and variables can have mutually recursive structure,
/// so we loop until no more changes occur.
fn compute_variable_info_fixed_point(
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  default_aliases : AliasMap,
  inlines : InlinedProductionMap,
) -> Array[VariableInfo] {
  let child_type_is_visible = (t : ChildType) => {
    variable_type_for_child_type(t, syntax_grammar, lexical_grammar) >=
    VariableType::Anonymous
  }
  let child_type_is_named = (t : ChildType) => {
    variable_type_for_child_type(t, syntax_grammar, lexical_grammar) ==
    VariableType::Named
  }
  let mut did_change = true
  let mut all_initialized = false
  let result = Array::makei(syntax_grammar.variables.length(), _ => {
    VariableInfo::default()
  })
  while did_change {
    did_change = false
    for i in 0..<syntax_grammar.variables.length() {
      if syntax_grammar.variables_to_inline.contains(Symbol::non_terminal(i)) {
        continue
      }
      let variable_info = result[i].clone()

      // Examine each of the variable's productions. The variable's child types can be
      // immediately combined across all productions, but the child quantities must be
      // recorded separately for each production.
      let production_field_quantities : Map[StrId, ChildQuantity] = Map([])
      let (prod_start, prod_end) = syntax_grammar.variable_prod_ids(i)
      for original_prod_id in prod_start..<prod_end {
        let production_ids = production_ids_for(inlines, original_prod_id)
        for prod_id in production_ids {
          production_field_quantities.clear()
          let production = syntax_grammar.production(prod_id)
          let production_children_quantity = ChildQuantity::zero()
          let production_children_without_fields_quantity = ChildQuantity::zero()
          let mut production_has_uninitialized_invisible_children = false
          if production.steps.length() > 1 {
            variable_info.has_multi_step_production = true
          }
          for step in production.steps {
            let child_symbol = step.symbol
            let child_type = step.child_type(default_aliases)
            let child_is_hidden = !child_type_is_visible(child_type) &&
              !syntax_grammar.supertype_symbols.contains(child_symbol)

            // Maintain the set of all child types for this variable, and the quantity
            // of visible children in this production.
            if extend_sorted(variable_info.children.types, [child_type]) {
              did_change = true
            }
            if !child_is_hidden {
              production_children_quantity.append(ChildQuantity::one())
            }

            // Maintain the set of child types associated with each field, and the
            // quantity of children associated with each field
            // in this production.
            if step.field is Some(field_name) {
              let field_info = variable_info.fields.get_or_init(field_name, () => {
                FieldInfo::default()
              })
              if extend_sorted(field_info.types, [child_type]) {
                did_change = true
              }
              let production_field_quantity = production_field_quantities.get_or_init(
                field_name,
                ChildQuantity::zero,
              )

              // Inherit the types and quantities of hidden children associated with
              // fields.
              if child_is_hidden &&
                child_symbol.non_terminal_index() is Some(index) {
                let child_variable_info = result[index]
                if extend_sorted(
                    field_info.types,
                    child_variable_info.children.types,
                  ) {
                  did_change = true
                }
                production_field_quantity.append(
                  child_variable_info.children.quantity,
                )
              } else {
                production_field_quantity.append(ChildQuantity::one())
              }
            } else if child_type_is_named(child_type) {
              // Maintain the set of named children without fields within this variable.
              production_children_without_fields_quantity.append(
                ChildQuantity::one(),
              )
              if extend_sorted(variable_info.children_without_fields.types, [
                  child_type,
                ]) {
                did_change = true
              }
            }

            // Inherit all child information from hidden children.
            if child_is_hidden &&
              child_symbol.non_terminal_index() is Some(index) {
              if inherit_hidden_child_info(
                  result[index],
                  step.field is None,
                  variable_info,
                  production_field_quantities,
                  production_children_quantity,
                  production_children_without_fields_quantity,
                ) {
                did_change = true
              }
            } else if child_type is Normal(_) &&
              syntax_grammar.supertype_symbols.contains(child_symbol) &&
              child_symbol.non_terminal_index() is Some(index) {
              // An unaliased supertype remains an abstract child type,
              // but its fields belong to the parent.
              if inherit_hidden_child_fields(
                  result[index],
                  step.field,
                  variable_info,
                  production_field_quantities,
                ) {
                did_change = true
              }
            }

            // Note whether or not this production contains children whose summaries
            // have not yet been computed.
            let child_index = match child_symbol.kind {
              External | Terminal | NonTerminal => child_symbol.index
              End | EndOfNonTerminalExtra => abort("unreachable")
            }
            if child_index >= i && !all_initialized {
              production_has_uninitialized_invisible_children = true
            }
          }

          // If this production's children all have had their summaries initialized,
          // then expand the quantity information with all of the possibilities introduced
          // by this production.
          if !production_has_uninitialized_invisible_children {
            if variable_info.children.quantity.union(
                production_children_quantity,
              ) {
              did_change = true
            }
            if variable_info.children_without_fields.quantity.union(
                production_children_without_fields_quantity,
              ) {
              did_change = true
            }
            for field_name, info in variable_info.fields {
              let quantity = match production_field_quantities.get(field_name) {
                Some(quantity) => quantity.copy()
                None => ChildQuantity::zero()
              }
              if info.quantity.union(quantity) {
                did_change = true
              }
            }
          }
        }
      }
      result[i] = variable_info
    }
    all_initialized = true
  }
  result
}

///|
/// Propagate fields, children, and children-without-fields from a hidden
/// child variable into the parent variable info. This returns whether
/// anything changed.
fn inherit_hidden_child_info(
  child_variable_info : VariableInfo,
  step_has_no_field : Bool,
  variable_info : VariableInfo,
  production_field_quantities : Map[StrId, ChildQuantity],
  production_children_quantity : ChildQuantity,
  production_children_without_fields_quantity : ChildQuantity,
) -> Bool {
  let mut did_change = false

  // If a hidden child can have multiple children, then its parent node can
  // appear to have multiple children.
  if child_variable_info.has_multi_step_production {
    variable_info.has_multi_step_production = true
  }
  if inherit_hidden_child_fields(
      child_variable_info,
      None,
      variable_info,
      production_field_quantities,
    ) {
    did_change = true
  }

  // If a hidden child has children, then the parent node can appear to have
  // those same children.
  production_children_quantity.append(child_variable_info.children.quantity)
  if extend_sorted(
      variable_info.children.types,
      child_variable_info.children.types,
    ) {
    did_change = true
  }

  // If a hidden child can have named children without fields, then the parent
  // node can appear to have those same children.
  if step_has_no_field {
    let grandchildren_info = child_variable_info.children_without_fields
    if !grandchildren_info.types.is_empty() {
      production_children_without_fields_quantity.append(
        child_variable_info.children_without_fields.quantity,
      )
      if extend_sorted(
          variable_info.children_without_fields.types,
          child_variable_info.children_without_fields.types,
        ) {
        did_change = true
      }
    }
  }
  did_change
}

///|
fn inherit_hidden_child_fields(
  child_variable_info : VariableInfo,
  skipped_field : StrId?,
  variable_info : VariableInfo,
  production_field_quantities : Map[StrId, ChildQuantity],
) -> Bool {
  let mut did_change = false

  // If a hidden child has fields, then the parent node can appear to have
  // those same fields.
  for field_name, child_field_info in child_variable_info.fields {
    if Some(field_name) == skipped_field {
      continue
    }
    production_field_quantities
    .get_or_init(field_name, ChildQuantity::zero)
    .append(child_field_info.quantity)
    if extend_sorted(
        variable_info.fields.get_or_init(field_name, () => FieldInfo::default()).types,
        child_field_info.types,
      ) {
      did_change = true
    }
  }
  did_change
}

///|
/// Verify that no supertype symbol has multi-step productions, which would
/// mean it can have more than one visible child.
fn validate_supertype_structure(
  result : Array[VariableInfo],
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  default_aliases : AliasMap,
  inlines : InlinedProductionMap,
  str_pool : StrPool,
) -> Unit raise VariableInfoError {
  let child_type_is_visible = (t : ChildType) => {
    variable_type_for_child_type(t, syntax_grammar, lexical_grammar) >=
    VariableType::Anonymous
  }
  for supertype_symbol in syntax_grammar.supertype_symbols {
    guard supertype_symbol.non_terminal_index() is Some(supertype_index) else {
      abort("unreachable")
    }
    if result[supertype_index].has_multi_step_production {
      let variable = syntax_grammar.variables[supertype_index]
      // A production can expand to multiple nodes directly or through a hidden child.
      // In the latter case, include that child's name in the diagnostic.

      let mut hidden_child_name : String? = None
      let (prod_start, prod_end) = syntax_grammar.variable_prod_ids(
        supertype_index,
      )
      // Upstream breaks out of the labeled `'productions` loop; `found` plays
      // that role here.
      let mut found = false
      for original_prod_id in prod_start..<prod_end {
        let production_ids = production_ids_for(inlines, original_prod_id)
        for prod_id in production_ids {
          if syntax_grammar.production(prod_id).steps.length() != 1 {
            continue
          }
          let step = syntax_grammar.production(prod_id).steps[0]
          let child_symbol = step.symbol
          let child_type = step.child_type(default_aliases)
          let child_is_hidden = !child_type_is_visible(child_type) &&
            !syntax_grammar.supertype_symbols.contains(child_symbol)
          let hidden_child_index = match child_symbol.non_terminal_index() {
            Some(index) if child_is_hidden => Some(index)
            _ => None
          }
          hidden_child_name = match hidden_child_index {
            Some(index) if result[index].has_multi_step_production =>
              Some(str_pool.resolve(syntax_grammar.variables[index].name))
            _ => None
          }
          if hidden_child_name is Some(_) {
            found = true
            break
          }
        }
        if found {
          break
        }
      }
      raise InvalidSupertype({
        supertype: str_pool.resolve(variable.name),
        child: hidden_child_name,
      })
    }
  }
}

///|
/// Remove hidden child types from supertype children lists, field type lists,
/// and children-without-fields lists, and drop fields that become empty.
fn strip_hidden_child_types(
  result : Array[VariableInfo],
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
) -> Unit {
  let child_type_is_visible = (t : ChildType) => {
    variable_type_for_child_type(t, syntax_grammar, lexical_grammar) >=
    VariableType::Anonymous
  }
  for supertype_symbol in syntax_grammar.supertype_symbols {
    guard supertype_symbol.non_terminal_index() is Some(index) else {
      abort("unreachable")
    }
    result[index].children.types.retain(child_type_is_visible)
  }
  for variable_info in result {
    for _, field_info in variable_info.fields {
      field_info.types.retain(child_type_is_visible)
    }
    variable_info.fields.retain((_, v) => !v.types.is_empty())
    variable_info.children_without_fields.types.retain(child_type_is_visible)
  }
}

///|
/// Upstream returns an `FxHashMap<Symbol, BTreeSet<Option<Alias>>>`. The outer
/// map is only used for lookups (and an order-insensitive `any`); the inner
/// sets are iterated, so they are sorted sets here too.
fn get_aliases_by_symbol(
  syntax_grammar : SyntaxGrammar,
  default_aliases : AliasMap,
  inlines : InlinedProductionMap,
) -> Map[Symbol, @sorted_set.SortedSet[Alias?]] {
  let aliases_by_symbol : Map[Symbol, @sorted_set.SortedSet[Alias?]] = Map([])
  for symbol, alias in default_aliases {
    aliases_by_symbol[symbol] = {
      let aliases = @sorted_set.SortedSet([])
      aliases.add(Some(alias))
      aliases
    }
  }
  for extra_symbol in syntax_grammar.extra_symbols {
    if !default_aliases.contains(extra_symbol) {
      aliases_by_symbol
      .get_or_init(extra_symbol, () => @sorted_set.SortedSet([]))
      .add(None)
    }
  }
  for i in 0..<syntax_grammar.variables.length() {
    if syntax_grammar.variables_to_inline.contains(Symbol::non_terminal(i)) {
      continue
    }
    let (prod_start, prod_end) = syntax_grammar.variable_prod_ids(i)
    for original_prod_id in prod_start..<prod_end {
      let production_ids = production_ids_for(inlines, original_prod_id)
      for prod_id in production_ids {
        for step in syntax_grammar.production(prod_id).steps {
          aliases_by_symbol
          .get_or_init(step.symbol, () => @sorted_set.SortedSet([]))
          .add(
            match step.alias {
              Some(alias) => Some(alias)
              None => default_aliases.get(step.symbol)
            },
          )
        }
      }
    }
  }
  aliases_by_symbol[Symbol::non_terminal(0)] = {
    let aliases = @sorted_set.SortedSet([])
    aliases.add(None)
    aliases
  }
  aliases_by_symbol
}

///|
/// `node_types::get_supertype_symbol_map`.
pub fn get_supertype_symbol_map(
  syntax_grammar : SyntaxGrammar,
  default_aliases : AliasMap,
  variable_info : Array[VariableInfo],
  inlines : InlinedProductionMap,
) -> @sorted_map.SortedMap[Symbol, Array[ChildType]] {
  let aliases_by_symbol = get_aliases_by_symbol(
    syntax_grammar, default_aliases, inlines,
  )
  let supertype_symbol_map : @sorted_map.SortedMap[Symbol, Array[ChildType]] = @sorted_map.SortedMap([],
  )

  // Upstream builds this map and never reads it; it is kept for structural
  // fidelity. Its (hash) order is unobservable.
  let symbols_by_alias : Map[Alias, Array[Symbol]] = Map([])
  for symbol, aliases in aliases_by_symbol {
    for alias in aliases {
      if alias is Some(alias) {
        symbols_by_alias.get_or_init(alias, () => []).push(symbol)
      }
    }
  }
  ignore(symbols_by_alias)
  for i, info in variable_info {
    let symbol = Symbol::non_terminal(i)
    if syntax_grammar.supertype_symbols.contains(symbol) {
      let subtypes = info.children.types.copy()
      supertype_symbol_map[symbol] = subtypes
    }
  }
  supertype_symbol_map
}

///|
/// Determine the visibility of a child type in the node-types output.
///
/// Priority chain: aliases override everything, then supertypes are always
/// `Named`, inlined rules are always `Hidden`, and everything else falls
/// back to the variable's declared kind. A symbol is never both a supertype
/// and inlined, since `intern_symbols` drops the supertype of such rules.
fn variable_type_for_child_type(
  child_type : ChildType,
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
) -> VariableType {
  match child_type {
    Aliased(alias) => alias.kind()
    Normal(symbol) => {
      let is_supertype = syntax_grammar.supertype_symbols.contains(symbol)
      let is_inline = syntax_grammar.variables_to_inline.contains(symbol)
      // Upstream: `debug_assert!(!(is_supertype && is_inline))` (debug builds only).
      if is_supertype {
        Named
      } else if is_inline {
        Hidden
      } else {
        match symbol.kind {
          NonTerminal => syntax_grammar.variables[symbol.index].kind
          Terminal => lexical_grammar.variables[symbol.index].kind
          External => syntax_grammar.external_tokens[symbol.index].kind
          End | EndOfNonTerminalExtra => Hidden
        }
      }
    }
  }
}

///|
/// Insert each value into the sorted `vec` unless already present; returns
/// whether anything was inserted.
fn[T : Compare] extend_sorted(vec : Array[T], values : ArrayView[T]) -> Bool {
  values.fold(init=false, (acc, value) => {
    match vec.binary_search(value) {
      Err(i) => {
        vec.insert(i, value)
        true
      }
      Ok(_) => acc
    }
  })
}
