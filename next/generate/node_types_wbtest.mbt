// Port of the tests in tree-sitter crates/generate/src/node_types.rs.
//
// The `test_node_types_*` tests (and `test_supertype_and_inline_conflict`)
// build an `InputGrammar` and run it through `prepare_grammar`, which is still
// a `declare`d contract in `interfaces.mbt` (calling it aborts). Until it is
// ported they return early; flip `prepare_grammar_ported` when it lands. The
// prepared grammars of exactly these tests are also checked by the
// differential oracle (`tools/next/node_types_oracle.sh`).

///|
let prepare_grammar_ported : Bool = false

///|
test "test_node_types_simple" {
  if !prepare_grammar_ported {
    return
  }
  let pool = RulePool::new()
  let v1 = {
    let f1 = {
      let v2 = named(pool, "v2")
      field(pool, "f1", v2)
    }
    let f2 = {
      let semi = string(pool, ";")
      field(pool, "f2", semi)
    }
    pool.seq([f1, f2])
  }
  let v2 = string(pool, "x")
  let v3 = string(pool, "y")
  let v1_name = pool.intern("v1")
  let v2_name = pool.intern("v2")
  let semicolon = pool.intern(";")
  let f1_name = pool.intern("f1")
  let f2_name = pool.intern("f2")
  let node_types = get_node_types({
    ..InputGrammar::new(),
    variables: [
      { name: pool.intern("v1"), root: v1, },
      { name: pool.intern("v2"), root: v2, },
      // This rule is not reachable from the start symbol
      // so it won't be present in the node_types
      { name: pool.intern("v3"), root: v3, },
    ],
    pool,
  })
  assert_eq(node_types.length(), 3)
  assert_eq(node_types[0], {
    kind: v1_name,
    named: true,
    root: true,
    extra: false,
    subtypes: None,
    children: None,
    fields: Some(
      @sorted_map.SortedMap([
        (
          f1_name,
          {
            multiple: false,
            required: true,
            types: [{ kind: v2_name, named: true, }],
          },
        ),
        (
          f2_name,
          {
            multiple: false,
            required: true,
            types: [{ kind: semicolon, named: false, }],
          },
        ),
      ]),
    ),
  })
  assert_eq(node_types[1], {
    kind: semicolon,
    named: false,
    root: false,
    extra: false,
    subtypes: None,
    children: None,
    fields: None,
  })
  assert_eq(node_types[2], {
    kind: v2_name,
    named: true,
    root: false,
    extra: false,
    subtypes: None,
    children: None,
    fields: None,
  })
}

///|
test "test_node_types_simple_extras" {
  if !prepare_grammar_ported {
    return
  }
  let pool = RulePool::new()
  let v1 = {
    let f1 = {
      let v2 = named(pool, "v2")
      field(pool, "f1", v2)
    }
    let f2 = {
      let semi = string(pool, ";")
      field(pool, "f2", semi)
    }
    pool.seq([f1, f2])
  }
  let v2 = string(pool, "x")
  let v3 = string(pool, "y")
  let extra = named(pool, "v3")
  let v1_name = pool.intern("v1")
  let v2_name = pool.intern("v2")
  let v3_name = pool.intern("v3")
  let semicolon = pool.intern(";")
  let f1_name = pool.intern("f1")
  let f2_name = pool.intern("f2")
  let node_types = get_node_types({
    ..InputGrammar::new(),
    extra_roots: [extra],
    variables: [
      { name: pool.intern("v1"), root: v1, },
      { name: pool.intern("v2"), root: v2, },
      // This rule is not reachable from the start symbol, but
      // it is reachable from the 'extra_symbols' so it
      // should be present in the node_types.
      // But because it's only a literal, it will get replaced by
      // a lexical variable.
      { name: pool.intern("v3"), root: v3, },
    ],
    pool,
  })
  assert_eq(node_types.length(), 4)
  assert_eq(node_types[0], {
    kind: v1_name,
    named: true,
    root: true,
    extra: false,
    subtypes: None,
    children: None,
    fields: Some(
      @sorted_map.SortedMap([
        (
          f1_name,
          {
            multiple: false,
            required: true,
            types: [{ kind: v2_name, named: true, }],
          },
        ),
        (
          f2_name,
          {
            multiple: false,
            required: true,
            types: [{ kind: semicolon, named: false, }],
          },
        ),
      ]),
    ),
  })
  assert_eq(node_types[1], {
    kind: semicolon,
    named: false,
    root: false,
    extra: false,
    subtypes: None,
    children: None,
    fields: None,
  })
  assert_eq(node_types[2], {
    kind: v2_name,
    named: true,
    root: false,
    extra: false,
    subtypes: None,
    children: None,
    fields: None,
  })
  assert_eq(node_types[3], {
    kind: v3_name,
    named: true,
    root: false,
    extra: true,
    subtypes: None,
    children: None,
    fields: None,
  })
}

///|
test "test_node_types_deeper_extras" {
  if !prepare_grammar_ported {
    return
  }
  let pool = RulePool::new()
  let v1 = {
    let f1 = {
      let v2 = named(pool, "v2")
      field(pool, "f1", v2)
    }
    let f2 = {
      let semi = string(pool, ";")
      field(pool, "f2", semi)
    }
    pool.seq([f1, f2])
  }
  let v2 = string(pool, "x")
  let v3 = {
    let y = string(pool, "y")
    let z = {
      let z = string(pool, "z")
      pool.repeat(z)
    }
    pool.seq([y, z])
  }
  let extra = named(pool, "v3")
  let v1_name = pool.intern("v1")
  let v2_name = pool.intern("v2")
  let v3_name = pool.intern("v3")
  let semicolon = pool.intern(";")
  let f1_name = pool.intern("f1")
  let f2_name = pool.intern("f2")
  let node_types = get_node_types({
    ..InputGrammar::new(),
    extra_roots: [extra],
    variables: [
      { name: pool.intern("v1"), root: v1, },
      { name: pool.intern("v2"), root: v2, },
      // This rule is not reachable from the start symbol, but
      // it is reachable from the 'extra_symbols' so it
      // should be present in the node_types.
      // Because it is not just a literal, it won't get replaced
      // by a lexical variable.
      { name: pool.intern("v3"), root: v3, },
    ],
    pool,
  })
  assert_eq(node_types.length(), 6)
  assert_eq(node_types[0], {
    kind: v1_name,
    named: true,
    root: true,
    extra: false,
    subtypes: None,
    children: None,
    fields: Some(
      @sorted_map.SortedMap([
        (
          f1_name,
          {
            multiple: false,
            required: true,
            types: [{ kind: v2_name, named: true, }],
          },
        ),
        (
          f2_name,
          {
            multiple: false,
            required: true,
            types: [{ kind: semicolon, named: false, }],
          },
        ),
      ]),
    ),
  })
  assert_eq(node_types[1], {
    kind: v3_name,
    named: true,
    root: false,
    extra: true,
    subtypes: None,
    children: None,
    fields: Some(@sorted_map.SortedMap([])),
  })
  assert_eq(node_types[2], {
    kind: semicolon,
    named: false,
    root: false,
    extra: false,
    subtypes: None,
    children: None,
    fields: None,
  })
  assert_eq(node_types[3], {
    kind: v2_name,
    named: true,
    root: false,
    extra: false,
    subtypes: None,
    children: None,
    fields: None,
  })
}

///|
test "test_node_types_with_supertypes" {
  if !prepare_grammar_ported {
    return
  }
  let pool = RulePool::new()
  let v1 = {
    let inner = named(pool, "_v2")
    field(pool, "f1", inner)
  }
  let v2 = {
    let (a, b, c) = (named(pool, "v3"), named(pool, "v4"), string(pool, "*"))
    pool.choice([a, b, c])
  }
  let v3 = string(pool, "x")
  let v4 = string(pool, "y")
  let v1_name = pool.intern("v1")
  let v2_name = pool.intern("_v2")
  let v3_name = pool.intern("v3")
  let v4_name = pool.intern("v4")
  let asterisk = pool.intern("*")
  let f1_name = pool.intern("f1")
  let node_types = get_node_types({
    ..InputGrammar::new(),
    supertype_names: [pool.intern("_v2")],
    variables: [
      { name: pool.intern("v1"), root: v1, },
      { name: pool.intern("_v2"), root: v2, },
      { name: pool.intern("v3"), root: v3, },
      { name: pool.intern("v4"), root: v4, },
    ],
    pool,
  })
  assert_eq(node_types[0], {
    kind: v2_name,
    named: true,
    root: false,
    extra: false,
    fields: None,
    children: None,
    subtypes: Some([
      { kind: asterisk, named: false, },
      { kind: v3_name, named: true, },
      { kind: v4_name, named: true, },
    ]),
  })
  assert_eq(node_types[1], {
    kind: v1_name,
    named: true,
    root: true,
    extra: false,
    subtypes: None,
    children: None,
    fields: Some(
      @sorted_map.SortedMap([
        (
          f1_name,
          {
            multiple: false,
            required: true,
            types: [{ kind: v2_name, named: true, }],
          },
        ),
      ]),
    ),
  })
}

///|
test "test_node_types_with_aliased_supertype" {
  if !prepare_grammar_ported {
    return
  }
  let pool = RulePool::new()
  let expression = named(pool, "_expression")
  let document = alias(pool, expression, "expression_target", true)
  let expression = named(pool, "identifier")
  let identifier = pattern(pool, "[a-z]+")
  let expression_name = pool.intern("_expression")
  let expression_target_name = pool.intern("expression_target")
  let identifier_name = pool.intern("identifier")
  let node_types = get_node_types({
    ..InputGrammar::new(),
    supertype_names: [expression_name],
    variables: [
      { name: pool.intern("document"), root: document, },
      { name: expression_name, root: expression, },
      { name: identifier_name, root: identifier, },
    ],
    pool,
  })
  guard node_types.search_by(node_type => {
      node_type.kind == expression_target_name
    })
    is Some(index) else {
    fail("the aliased supertype should have its own node-types entry")
  }
  let alias = node_types[index]
  assert_true(alias.named)
  assert_true(alias.subtypes is None)
  assert_eq(alias.children.unwrap().types, [
    { kind: identifier_name, named: true, },
  ])
}

///|
test "test_node_types_distinguish_named_and_anonymous_aliases" {
  if !prepare_grammar_ported {
    return
  }
  let pool = RulePool::new()
  let node = named(pool, "_node")
  let named_alias = alias(pool, node, "same", true)
  let anonymous_alias = alias(pool, node, "same", false)
  let document = pool.choice([named_alias, anonymous_alias])
  let node = {
    let value = named(pool, "value")
    let suffix = string(pool, "!")
    pool.seq([value, suffix])
  }
  let value = pattern(pool, "[a-z]+")
  let same_name = pool.intern("same")
  let node_types = get_node_types({
    ..InputGrammar::new(),
    variables: [
      { name: pool.intern("document"), root: document, },
      { name: pool.intern("_node"), root: node, },
      { name: pool.intern("value"), root: value, },
    ],
    pool,
  })
  let named = node_types
    .filter(node_type => node_type.kind == same_name)
    .map(node_type => node_type.named)
  assert_eq(named, [false, true])
}

///|
test "test_node_types_merge_anonymous_node_and_token_aliases" {
  if !prepare_grammar_ported {
    return
  }
  let pool = RulePool::new()
  let node = named(pool, "_node")
  let node = alias(pool, node, "same", false)
  let token = string(pool, "!")
  let token = alias(pool, token, "same", false)
  let document = pool.choice([node, token])
  let node = {
    let (value1, value2) = (named(pool, "value"), named(pool, "value"))
    let suffix = string(pool, "?")
    pool.seq([value1, value2, suffix])
  }
  let value = pattern(pool, "[a-z]+")
  let same_name = pool.intern("same")
  let value_name = pool.intern("value")
  let node_types = get_node_types({
    ..InputGrammar::new(),
    variables: [
      { name: pool.intern("document"), root: document, },
      { name: pool.intern("_node"), root: node, },
      { name: value_name, root: value, },
    ],
    pool,
  })
  let aliases = node_types.filter(node_type => {
    node_type.kind == same_name && !node_type.named
  })
  assert_eq(aliases.length(), 1)
  let children = aliases[0].children.unwrap()
  assert_true(children.multiple)
  assert_true(!children.required)
  assert_eq(children.types, [{ kind: value_name, named: true, }])
}

///|
test "test_node_types_distinguish_extra_metadata_by_namedness" {
  if !prepare_grammar_ported {
    return
  }
  let pool = RulePool::new()
  let node = named(pool, "_node")
  let node = alias(pool, node, "same", false)
  let extra = named(pool, "_extra")
  let extra_alias = alias(pool, extra, "same", true)
  let document = pool.choice([node, extra_alias])
  let node = {
    let value = named(pool, "value")
    let suffix = string(pool, "?")
    pool.seq([value, suffix])
  }
  let extra_rule = {
    let prefix = string(pool, "#")
    let value = named(pool, "extra_value")
    pool.seq([prefix, value])
  }
  let value = pattern(pool, "[a-z]+")
  let extra_value = pattern(pool, "[A-Z]+")
  let same_name = pool.intern("same")
  let node_types = get_node_types({
    ..InputGrammar::new(),
    extra_roots: [extra],
    variables: [
      { name: pool.intern("document"), root: document, },
      { name: pool.intern("_node"), root: node, },
      { name: pool.intern("_extra"), root: extra_rule, },
      { name: pool.intern("value"), root: value, },
      { name: pool.intern("extra_value"), root: extra_value, },
    ],
    pool,
  })
  let aliases = node_types.filter(node_type => node_type.kind == same_name)
  stable_sort_by_key(aliases, node_type => node_type.named)
  assert_eq(aliases.length(), 2)
  assert_true(!aliases[0].named)
  assert_true(!aliases[0].extra)
  assert_true(aliases[1].named)
  assert_true(aliases[1].extra)
}

///|
test "test_node_types_distinguish_supertype_dependencies_by_namedness" {
  if !prepare_grammar_ported {
    return
  }
  let pool = RulePool::new()
  let document = named(pool, "_super")
  let supertype = {
    let item = named(pool, "item")
    let item = alias(pool, item, "_super", false)
    let other = named(pool, "other")
    pool.choice([item, other])
  }
  let item = string(pool, "x")
  let other = string(pool, "y")
  let super_name = pool.intern("_super")
  let node_types = get_node_types({
    ..InputGrammar::new(),
    supertype_names: [super_name],
    variables: [
      { name: pool.intern("document"), root: document, },
      { name: super_name, root: supertype, },
      { name: pool.intern("item"), root: item, },
      { name: pool.intern("other"), root: other, },
    ],
    pool,
  })
  let named = node_types
    .filter(node_type => node_type.kind == super_name)
    .map(node_type => node_type.named)
  named.sort()
  assert_eq(named, [false, true])
}

///|
test "test_node_types_with_alias_matching_canonical_supertype" {
  if !prepare_grammar_ported {
    return
  }
  let pool = RulePool::new()
  let document = {
    let node = named(pool, "_node")
    let node = alias(pool, node, "_super", true)
    let supertype = named(pool, "_super")
    pool.choice([node, supertype])
  }
  let supertype = {
    let (one, two) = (named(pool, "one"), named(pool, "two"))
    pool.choice([one, two])
  }
  let node = {
    let value = named(pool, "value")
    let suffix = string(pool, "?")
    pool.seq([value, suffix])
  }
  let one = string(pool, "1")
  let two = string(pool, "2")
  let value = pattern(pool, "[a-z]+")
  let super_name = pool.intern("_super")
  let grammar = {
    ..InputGrammar::new(),
    supertype_names: [super_name],
    variables: [
      { name: pool.intern("document"), root: document, },
      { name: super_name, root: supertype, },
      { name: pool.intern("_node"), root: node, },
      { name: pool.intern("one"), root: one, },
      { name: pool.intern("two"), root: two, },
      { name: pool.intern("value"), root: value, },
    ],
    pool,
  }
  let { syntax_grammar, lexical_grammar, inlines, default_aliases, str_pool, } = prepare_grammar(
    grammar,
    [],
  )
  try
    get_variable_info(
      syntax_grammar, lexical_grammar, default_aliases, inlines, str_pool,
    )
  catch {
    VariableInfoError::SupertypeAliasCollision(name) =>
      assert_eq(name, "_super")
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected an error")
  }
}

///|
/// A supertype whose only child is a hidden external token must not cause
/// generation to panic. The subtype map must skip entries with empty subtypes
/// to avoid a lookup failure in the topological sort.
test "test_node_types_supertype_with_only_hidden_child" {
  if !prepare_grammar_ported {
    return
  }
  let pool = RulePool::new()
  let v1 = {
    let (a, b) = (named(pool, "_type_a"), named(pool, "_type_b"))
    pool.seq([a, b])
  }
  let type_a = {
    let (a, b) = (named(pool, "v2"), named(pool, "v3"))
    pool.choice([a, b])
  }
  let v2 = string(pool, "x")
  let v3 = string(pool, "y")
  let type_b = external(pool, 0)
  let hidden_ext = named(pool, "_hidden_ext")
  let node_types : Result[Array[NodeInfoJSON], Error] = try
    get_node_types({
      ..InputGrammar::new(),
      supertype_names: [pool.intern("_type_a"), pool.intern("_type_b")],
      external_roots: [hidden_ext],
      variables: [
        { name: pool.intern("v1"), root: v1, },
        // Supertype A: a normal choice of named subtypes
        { name: pool.intern("_type_a"), root: type_a, },
        { name: pool.intern("v2"), root: v2, },
        { name: pool.intern("v3"), root: v3, },
        // Supertype B: a hidden external token with no subtypes
        { name: pool.intern("_type_b"), root: type_b, },
      ],
      pool,
    })
  catch {
    e => Err(e)
  } noraise {
    node_types => Ok(node_types)
  }
  assert_true(node_types is Ok(_))
}

///|
test "test_node_types_for_children_without_fields" {
  if !prepare_grammar_ported {
    return
  }
  let pool = RulePool::new()
  let v1 = {
    let a = named(pool, "v2")
    let f1 = {
      let v3 = named(pool, "v3")
      field(pool, "f1", v3)
    }
    let c = named(pool, "v4")
    pool.seq([a, f1, c])
  }
  let v2 = {
    let open = string(pool, "{")
    let mid = {
      let v3 = named(pool, "v3")
      let blank = pool.blank()
      pool.choice([v3, blank])
    }
    let close = string(pool, "}")
    pool.seq([open, mid, close])
  }
  let v3 = string(pool, "x")
  let v4 = string(pool, "y")
  let v1_name = pool.intern("v1")
  let v2_name = pool.intern("v2")
  let v3_name = pool.intern("v3")
  let v4_name = pool.intern("v4")
  let f1_name = pool.intern("f1")
  let node_types = get_node_types({
    ..InputGrammar::new(),
    variables: [
      { name: pool.intern("v1"), root: v1, },
      { name: pool.intern("v2"), root: v2, },
      { name: pool.intern("v3"), root: v3, },
      { name: pool.intern("v4"), root: v4, },
    ],
    pool,
  })
  assert_eq(node_types[0], {
    kind: v1_name,
    named: true,
    root: true,
    extra: false,
    subtypes: None,
    children: Some({
      multiple: true,
      required: true,
      types: [{ kind: v2_name, named: true, }, { kind: v4_name, named: true, }],
    }),
    fields: Some(
      @sorted_map.SortedMap([
        (
          f1_name,
          {
            multiple: false,
            required: true,
            types: [{ kind: v3_name, named: true, }],
          },
        ),
      ]),
    ),
  })
  assert_eq(node_types[1], {
    kind: v2_name,
    named: true,
    root: false,
    extra: false,
    subtypes: None,
    children: Some({
      multiple: false,
      required: false,
      types: [{ kind: v3_name, named: true, }],
    }),
    fields: Some(@sorted_map.SortedMap([])),
  })
}

///|
test "test_node_types_with_inlined_rules" {
  if !prepare_grammar_ported {
    return
  }
  let pool = RulePool::new()
  let v1 = {
    let (a, b) = (named(pool, "v2"), named(pool, "v3"))
    pool.seq([a, b])
  }
  let v2 = {
    let a = string(pool, "a")
    alias(pool, a, "x", true)
  }
  let v3 = string(pool, "b")
  let v1_name = pool.intern("v1")
  let v3_name = pool.intern("v3")
  let x_name = pool.intern("x")
  let node_types = get_node_types({
    ..InputGrammar::new(),
    inline_names: [pool.intern("v2")],
    variables: [
      { name: pool.intern("v1"), root: v1, },
      // v2 should not appear in the node types, since it is inlined
      { name: pool.intern("v2"), root: v2, },
      { name: pool.intern("v3"), root: v3, },
    ],
    pool,
  })
  assert_eq(node_types[0], {
    kind: v1_name,
    named: true,
    root: true,
    extra: false,
    subtypes: None,
    children: Some({
      multiple: true,
      required: true,
      types: [{ kind: v3_name, named: true, }, { kind: x_name, named: true, }],
    }),
    fields: Some(@sorted_map.SortedMap([])),
  })
}

///|
test "test_node_types_aliased_inline_unit_shape" {
  if !prepare_grammar_ported {
    return
  }
  let pool = RulePool::new()
  let source_file_name = pool.intern("source_file")
  let inlined_name = pool.intern("inlined")
  let wrapper_name = pool.intern("_wrapper")
  let value_name = pool.intern("_value")
  let name_name = pool.intern("name")
  let number_name = pool.intern("number")
  let thing_name = pool.intern("thing")
  let inlined_symbol = named(pool, "inlined")
  let source_file = pool.repeat(inlined_symbol)
  let inlined_token = string(pool, "inlined")
  let wrapper_symbol = named(pool, "_wrapper")
  let aliased_wrapper = alias(pool, wrapper_symbol, "thing", true)
  let inlined = pool.seq([inlined_token, aliased_wrapper])
  let wrapper = named(pool, "_value")
  let value_name_symbol = named(pool, "name")
  let number_name_symbol = named(pool, "number")
  let value = pool.choice([value_name_symbol, number_name_symbol])
  let name_root = pattern(pool, "[a-z]+")
  let number_root = pattern(pool, "[0-9]+")
  let nodes = get_node_types({
    ..InputGrammar::new(),
    inline_names: [wrapper_name],
    variables: [
      { name: source_file_name, root: source_file, },
      { name: inlined_name, root: inlined, },
      { name: wrapper_name, root: wrapper, },
      { name: value_name, root: value, },
      { name: name_name, root: name_root, },
      { name: number_name, root: number_root, },
    ],
    pool,
  })
  let expected : NodeInfoJSON = {
    kind: thing_name,
    named: true,
    root: false,
    extra: false,
    fields: Some(@sorted_map.SortedMap([])),
    children: Some({
      multiple: false,
      required: true,
      types: [
        { kind: name_name, named: true, },
        { kind: number_name, named: true, },
      ],
    }),
    subtypes: None,
  }
  assert_eq(find_node(nodes, thing_name), Some(expected))
}

///|
test "test_node_types_inlined_field_overrides_inner_field" {
  if !prepare_grammar_ported {
    return
  }
  let pool = RulePool::new()
  let source_file_name = pool.intern("source_file")
  let pair_name = pool.intern("_pair")
  let name_name = pool.intern("name")
  let outer_name = pool.intern("outer")
  let name = named(pool, "name")
  let head = field(pool, "inner", name)
  let pair = pool.seq([head, name])
  let pair_symbol = named(pool, "_pair")
  let source_file = field(pool, "outer", pair_symbol)
  let name_root = pattern(pool, "[a-z]+")
  let nodes = get_node_types({
    ..InputGrammar::new(),
    inline_names: [pair_name],
    variables: [
      { name: source_file_name, root: source_file, },
      { name: pair_name, root: pair, },
      { name: name_name, root: name_root, },
    ],
    pool,
  })
  let expected : NodeInfoJSON = {
    kind: source_file_name,
    named: true,
    root: true,
    extra: false,
    fields: Some(
      @sorted_map.SortedMap([
        (
          outer_name,
          {
            multiple: true,
            required: true,
            types: [{ kind: name_name, named: true, }],
          },
        ),
      ]),
    ),
    children: None,
    subtypes: None,
  }
  assert_eq(find_node(nodes, source_file_name), Some(expected))
}

///|
test "test_node_types_aliased_inline_repetition" {
  if !prepare_grammar_ported {
    return
  }
  for with_head_field in [false, true] {
    let pool = RulePool::new()
    let source_file_name = pool.intern("source_file")
    let inline_name = pool.intern("_path")
    let path_name = pool.intern("path")
    let name_name = pool.intern("name")
    let head_name = pool.intern("head")
    let name = named(pool, "name")
    let dot = string(pool, ".")
    let tail = pool.seq([dot, name])
    let tail = pool.repeat(tail)
    let blank = pool.blank()
    let tail = pool.choice([tail, blank])
    let head = named(pool, "name")
    let head = if with_head_field { field(pool, "head", head) } else { head }
    let path = pool.seq([head, tail])
    let path_symbol = named(pool, "_path")
    let source_file = alias(pool, path_symbol, "path", true)
    let name_root = pattern(pool, "[a-z]+")
    let nodes = get_node_types({
      ..InputGrammar::new(),
      inline_names: [inline_name],
      variables: [
        { name: source_file_name, root: source_file, },
        { name: inline_name, root: path, },
        { name: name_name, root: name_root, },
      ],
      pool,
    })
    let expected_source_file : NodeInfoJSON = {
      kind: source_file_name,
      named: true,
      root: true,
      extra: false,
      fields: Some(
        if with_head_field {
          @sorted_map.SortedMap([
            (
              head_name,
              {
                multiple: false,
                required: true,
                types: [{ kind: path_name, named: true, }],
              },
            ),
          ])
        } else {
          @sorted_map.SortedMap([])
        },
      ),
      children: Some({
        multiple: !with_head_field,
        required: !with_head_field,
        types: [{ kind: path_name, named: true, }],
      }),
      subtypes: None,
    }
    assert_eq(
      find_node(nodes, source_file_name),
      Some(expected_source_file),
      msg="with_head_field=\{with_head_field}",
    )
    let expected_path : NodeInfoJSON = {
      kind: path_name,
      named: true,
      root: false,
      extra: false,
      fields: Some(@sorted_map.SortedMap([])),
      children: Some({
        multiple: true,
        required: false,
        types: [{ kind: name_name, named: true, }],
      }),
      subtypes: None,
    }
    assert_eq(
      find_node(nodes, path_name),
      Some(expected_path),
      msg="with_head_field=\{with_head_field}",
    )
  }
}

///|
test "test_node_types_for_aliased_nodes" {
  if !prepare_grammar_ported {
    return
  }
  let pool = RulePool::new()
  let thing = {
    let (a, b) = (named(pool, "type"), named(pool, "expression"))
    pool.choice([a, b])
  }
  let ty = {
    let id = {
      let inner = named(pool, "identifier")
      alias(pool, inner, "type_identifier", true)
    }
    let void = string(pool, "void")
    pool.choice([id, void])
  }
  let expression = {
    let id = named(pool, "identifier")
    let foo = {
      let inner = named(pool, "foo_identifier")
      alias(pool, inner, "identifier", true)
    }
    pool.choice([id, foo])
  }
  let identifier = pattern(pool, "\\w+")
  let foo_identifier = pattern(pool, "[\\w-]+")
  let identifier_name = pool.intern("identifier")
  let foo_identifier_name = pool.intern("foo_identifier")
  let type_identifier_name = pool.intern("type_identifier")
  let node_types = get_node_types({
    ..InputGrammar::new(),
    variables: [
      { name: pool.intern("thing"), root: thing, },
      { name: pool.intern("type"), root: ty, },
      { name: pool.intern("expression"), root: expression, },
      { name: pool.intern("identifier"), root: identifier, },
      { name: pool.intern("foo_identifier"), root: foo_identifier, },
    ],
    pool,
  })
  assert_eq(find_node(node_types, foo_identifier_name), None)
  let expected_identifier : NodeInfoJSON = {
    kind: identifier_name,
    named: true,
    root: false,
    extra: false,
    subtypes: None,
    children: None,
    fields: None,
  }
  assert_eq(find_node(node_types, identifier_name), Some(expected_identifier))
  let expected_type_identifier : NodeInfoJSON = {
    kind: type_identifier_name,
    named: true,
    root: false,
    extra: false,
    subtypes: None,
    children: None,
    fields: None,
  }
  assert_eq(
    find_node(node_types, type_identifier_name),
    Some(expected_type_identifier),
  )
}

///|
test "test_node_types_with_multiple_valued_fields" {
  if !prepare_grammar_ported {
    return
  }
  let pool = RulePool::new()
  let a = {
    let first = {
      let blank = pool.blank()
      let rep = {
        let f1 = {
          let b = named(pool, "b")
          field(pool, "f1", b)
        }
        pool.repeat(f1)
      }
      pool.choice([blank, rep])
    }
    let second = {
      let c = named(pool, "c")
      pool.repeat(c)
    }
    pool.seq([first, second])
  }
  let b = string(pool, "b")
  let c = string(pool, "c")
  let a_name = pool.intern("a")
  let b_name = pool.intern("b")
  let c_name = pool.intern("c")
  let f1_name = pool.intern("f1")
  let node_types = get_node_types({
    ..InputGrammar::new(),
    variables: [
      { name: pool.intern("a"), root: a, },
      { name: pool.intern("b"), root: b, },
      { name: pool.intern("c"), root: c, },
    ],
    pool,
  })
  assert_eq(node_types[0], {
    kind: a_name,
    named: true,
    root: true,
    extra: false,
    subtypes: None,
    children: Some({
      multiple: true,
      required: true,
      types: [{ kind: c_name, named: true, }],
    }),
    fields: Some(
      @sorted_map.SortedMap([
        (
          f1_name,
          {
            multiple: true,
            required: false,
            types: [{ kind: b_name, named: true, }],
          },
        ),
      ]),
    ),
  })
}

///|
test "test_node_types_with_fields_on_hidden_tokens" {
  if !prepare_grammar_ported {
    return
  }
  let pool = RulePool::new()
  let script = {
    let a = {
      let pat = pattern(pool, "hi")
      field(pool, "a", pat)
    }
    let b = {
      let pat = pattern(pool, "bye")
      field(pool, "b", pat)
    }
    pool.seq([a, b])
  }
  let script_name = pool.intern("script")
  let node_types = get_node_types({
    ..InputGrammar::new(),
    variables: [{ name: pool.intern("script"), root: script, }],
    pool,
  })
  let expected : Array[NodeInfoJSON] = [
    {
      kind: script_name,
      named: true,
      root: true,
      extra: false,
      fields: Some(@sorted_map.SortedMap([])),
      children: None,
      subtypes: None,
    },
  ]
  assert_eq(node_types, expected)
}

///|
test "test_node_types_with_multiple_rules_same_alias_name" {
  if !prepare_grammar_ported {
    return
  }
  let pool = RulePool::new()
  let script = {
    let a = named(pool, "a")
    let b = {
      let inner = named(pool, "b")
      alias(pool, inner, "a", true)
    }
    pool.choice([a, b])
  }
  let a = {
    let f1 = {
      let s = string(pool, "1")
      field(pool, "f1", s)
    }
    let f2 = {
      let s = string(pool, "2")
      field(pool, "f2", s)
    }
    pool.seq([f1, f2])
  }
  let b = {
    let f2a = {
      let s = string(pool, "22")
      field(pool, "f2", s)
    }
    let f2b = {
      let s = string(pool, "222")
      field(pool, "f2", s)
    }
    let f3 = {
      let s = string(pool, "3")
      field(pool, "f3", s)
    }
    pool.seq([f2a, f2b, f3])
  }
  let a_name = pool.intern("a")
  let script_name = pool.intern("script")
  let name_1 = pool.intern("1")
  let name_2 = pool.intern("2")
  let name_22 = pool.intern("22")
  let name_222 = pool.intern("222")
  let name_3 = pool.intern("3")
  let f1_name = pool.intern("f1")
  let f2_name = pool.intern("f2")
  let f3_name = pool.intern("f3")
  let node_types = get_node_types({
    ..InputGrammar::new(),
    variables: [
      { name: pool.intern("script"), root: script, },
      { name: pool.intern("a"), root: a, },
      { name: pool.intern("b"), root: b, },
    ],
    pool,
  })
  assert_eq(node_types.map(t => t.kind), [
    a_name, script_name, name_1, name_2, name_22, name_222, name_3,
  ])
  let expected : Array[NodeInfoJSON] = [
    // A combination of the types for `a` and `b`.
    {
      kind: a_name,
      named: true,
      root: false,
      extra: false,
      subtypes: None,
      children: None,
      fields: Some(
        @sorted_map.SortedMap([
          (
            f1_name,
            {
              multiple: false,
              required: false,
              types: [{ kind: name_1, named: false, }],
            },
          ),
          (
            f2_name,
            {
              multiple: true,
              required: true,
              types: [
                { kind: name_2, named: false, },
                { kind: name_22, named: false, },
                { kind: name_222, named: false, },
              ],
            },
          ),
          (
            f3_name,
            {
              multiple: false,
              required: false,
              types: [{ kind: name_3, named: false, }],
            },
          ),
        ]),
      ),
    },
    {
      kind: script_name,
      named: true,
      root: true,
      extra: false,
      subtypes: None,
      // Only one node
      children: Some({
        multiple: false,
        required: true,
        types: [{ kind: a_name, named: true, }],
      }),
      fields: Some(@sorted_map.SortedMap([])),
    },
  ]
  assert_eq(node_types[0:2].to_owned(), expected)
}

///|
test "test_node_types_with_tokens_aliased_to_match_rules" {
  if !prepare_grammar_ported {
    return
  }
  let pool = RulePool::new()
  let a = {
    let (b, c) = (named(pool, "b"), named(pool, "c"))
    pool.seq([b, c])
  }
  let b = {
    let (c1, mid, c2) = (named(pool, "c"), string(pool, "B"), named(pool, "c"))
    pool.seq([c1, mid, c2])
  }
  let c = {
    let cc = string(pool, "C")
    let d = {
      // This token is aliased as a `b`, which will produce a `b` node
      // with no children.
      let inner = string(pool, "D")
      alias(pool, inner, "b", true)
    }
    pool.choice([cc, d])
  }
  let name_a = pool.intern("a")
  let name_b = pool.intern("b")
  let name_c = pool.intern("c")
  let name_capital_b = pool.intern("B")
  let name_capital_c = pool.intern("C")
  // above Alias D
  let node_types = get_node_types({
    ..InputGrammar::new(),
    variables: [
      { name: pool.intern("a"), root: a, },
      // Ordinarily, `b` nodes have two named `c` children.
      { name: pool.intern("b"), root: b, },
      { name: pool.intern("c"), root: c, },
    ],
    pool,
  })
  assert_eq(node_types.map(n => n.kind), [
    name_a, name_b, name_c, name_capital_b, name_capital_c,
  ])
  assert_eq(node_types[1], {
    kind: name_b,
    named: true,
    root: false,
    extra: false,
    subtypes: None,
    children: Some({
      multiple: true,
      required: false,
      types: [{ kind: name_c, named: true, }],
    }),
    fields: Some(@sorted_map.SortedMap([])),
  })
}

///|
test "test_get_variable_info" {
  let interner = StrPool::new()
  let field1 = interner.intern("field1")
  let field2 = interner.intern("field2")
  let lexical_grammar = build_lexical_grammar(interner)
  let grammar = build_syntax_grammar(
    interner,
    [
      // Required field `field1` has only one node type.
      (
        "rule0",
        Named,
        [
          [
            step(Symbol::terminal(0), None),
            step(Symbol::non_terminal(1), Some(field1)),
          ],
        ],
      ),
      // Hidden node
      ("_rule1", Hidden, [[step(Symbol::terminal(1), None)]]),
      // Optional field `field2` can have two possible node types.
      (
        "rule2",
        Named,
        [
          [step(Symbol::terminal(0), None)],
          [
            step(Symbol::terminal(0), None),
            step(Symbol::terminal(2), Some(field2)),
          ],
          [
            step(Symbol::terminal(0), None),
            step(Symbol::terminal(3), Some(field2)),
          ],
        ],
      ),
    ],
    [],
  )
  let variable_info = get_variable_info(
    grammar,
    lexical_grammar,
    @sorted_map.SortedMap([]),
    InlinedProductionMap::new(),
    interner,
  )
  assert_eq(
    variable_info[0].fields,
    Map::from_array([
      (
        field1,
        {
          quantity: { exists: true, required: true, multiple: false, },
          types: [Normal(Symbol::terminal(1))],
        },
      ),
    ]),
  )
  assert_eq(
    variable_info[2].fields,
    Map::from_array([
      (
        field2,
        {
          quantity: { exists: true, required: false, multiple: false, },
          types: [Normal(Symbol::terminal(2)), Normal(Symbol::terminal(3))],
        },
      ),
    ]),
  )
}

///|
test "test_get_variable_info_with_repetitions_inside_fields" {
  let interner = StrPool::new()
  let field1 = interner.intern("field1")
  let lexical_grammar = build_lexical_grammar(interner)
  let grammar = build_syntax_grammar(
    interner,
    [
      // Field associated with a repetiation.
      ("rule0", Named, [[step(Symbol::non_terminal(1), Some(field1))], []]),
      (
        "_rule0_repeat",
        Hidden,
        [
          [step(Symbol::terminal(1), None)],
          [
            step(Symbol::non_terminal(1), None),
            step(Symbol::non_terminal(1), None),
          ],
        ],
      ),
    ],
    [],
  )
  let variable_info = get_variable_info(
    grammar,
    lexical_grammar,
    @sorted_map.SortedMap([]),
    InlinedProductionMap::new(),
    interner,
  )
  assert_eq(
    variable_info[0].fields,
    Map::from_array([
      (
        field1,
        {
          quantity: { exists: true, required: false, multiple: true, },
          types: [Normal(Symbol::terminal(1))],
        },
      ),
    ]),
  )
}

///|
test "test_get_variable_info_with_inherited_fields" {
  let interner = StrPool::new()
  let field1 = interner.intern("field1")
  let dot = interner.intern(".")
  let lexical_grammar = build_lexical_grammar(interner)
  let grammar = build_syntax_grammar(
    interner,
    [
      (
        "rule0",
        Named,
        [
          [
            step(Symbol::terminal(0), None),
            step(Symbol::non_terminal(1), None),
            step(Symbol::terminal(1), None),
          ],
          [step(Symbol::non_terminal(1), None)],
        ],
      ),
      // Hidden node with fields
      (
        "_rule1",
        Hidden,
        [
          [
            ProductionStep::pack(
              Symbol::terminal(2),
              NoPrecedence,
              None,
              Some({ value: dot, is_named: false, }),
              None,
              no_reserved_words,
            ),
            step(Symbol::terminal(3), Some(field1)),
          ],
        ],
      ),
    ],
    [],
  )
  let variable_info = get_variable_info(
    grammar,
    lexical_grammar,
    @sorted_map.SortedMap([]),
    InlinedProductionMap::new(),
    interner,
  )
  assert_eq(
    variable_info[0].fields,
    Map::from_array([
      (
        field1,
        {
          quantity: { exists: true, required: true, multiple: false, },
          types: [Normal(Symbol::terminal(3))],
        },
      ),
    ]),
  )
  assert_eq(variable_info[0].children_without_fields, {
    quantity: { exists: true, required: false, multiple: true, },
    types: [Normal(Symbol::terminal(0)), Normal(Symbol::terminal(1))],
  })
}

///|
test "test_get_variable_info_with_supertypes" {
  let interner = StrPool::new()
  let field1 = interner.intern("field1")
  let lexical_grammar = build_lexical_grammar(interner)
  let grammar = build_syntax_grammar(
    interner,
    [
      (
        "rule0",
        Named,
        [
          [
            step(Symbol::terminal(0), None),
            step(Symbol::non_terminal(1), Some(field1)),
            step(Symbol::terminal(1), None),
          ],
        ],
      ),
      (
        "_rule1",
        Hidden,
        [[step(Symbol::terminal(2), None)], [step(Symbol::terminal(3), None)]],
      ),
    ],
    // _rule1 is a supertype
    [Symbol::non_terminal(1)],
  )
  let variable_info = get_variable_info(
    grammar,
    lexical_grammar,
    @sorted_map.SortedMap([]),
    InlinedProductionMap::new(),
    interner,
  )
  assert_eq(
    variable_info[0].fields,
    Map::from_array([
      (
        field1,
        {
          quantity: { exists: true, required: true, multiple: false, },
          types: [Normal(Symbol::non_terminal(1))],
        },
      ),
    ]),
  )
}

///|
test "test_get_variable_info_with_fields_inside_supertypes" {
  let interner = StrPool::new()
  let field = interner.intern("value")
  let lexical_grammar = build_lexical_grammar(interner)
  for parent_field in [None, Some(field)] {
    let grammar = build_syntax_grammar(
      interner,
      [
        ("parent", Named, [[step(Symbol::non_terminal(1), None)]]),
        ("_hidden", Hidden, [[step(Symbol::non_terminal(2), parent_field)]]),
        ("_supertype", Hidden, [[step(Symbol::terminal(0), Some(field))]]),
      ],
      [Symbol::non_terminal(2)],
    )
    let info = get_variable_info(
      grammar,
      lexical_grammar,
      @sorted_map.SortedMap([]),
      InlinedProductionMap::new(),
      interner,
    )
    // Fields cross the supertype and hidden rule, while the supertype
    // remains an abstract child type. Assigning the same field on the
    // supertype step must not count the child twice.
    assert_eq(info[0].fields[field].quantity, ChildQuantity::one())
    assert_eq(info[0].fields[field].types, [
      Normal(
        if parent_field is Some(_) {
          Symbol::non_terminal(2)
        } else {
          Symbol::terminal(0)
        },
      ),
    ])
    assert_true(
      info[0].children.types.contains(Normal(Symbol::non_terminal(2))),
    )
    assert_true(!info[0].children.types.contains(Normal(Symbol::terminal(0))))
  }
}

///|
test "test_get_variable_info_with_aliased_supertype_fields" {
  let interner = StrPool::new()
  let field = interner.intern("inner")
  let lexical_grammar = build_lexical_grammar(interner)
  let child = step(Symbol::non_terminal(1), None).with_alias(
    Some({ value: interner.intern("wrapper"), is_named: true, }),
  )
  let grammar = build_syntax_grammar(
    interner,
    [
      ("parent", Named, [[child]]),
      ("_supertype", Hidden, [[step(Symbol::terminal(0), Some(field))]]),
    ],
    [Symbol::non_terminal(1)],
  )
  let info = get_variable_info(
    grammar,
    lexical_grammar,
    @sorted_map.SortedMap([]),
    InlinedProductionMap::new(),
    interner,
  )
  assert_true(info[1].fields.contains(field))
  assert_true(info[0].fields.is_empty())
}

///|
test "test_supertype_and_inline_conflict" {
  if !prepare_grammar_ported {
    return
  }
  // v1: field("f1", _v2)
  // _v2: choice(v3, v4)
  // supertypes: [_v2]
  // inline: [_v2]
  let pool = RulePool::new()
  let v1_name = pool.intern("v1")
  let v2_name = pool.intern("_v2")
  let v3_name = pool.intern("v3")
  let v4_name = pool.intern("v4")
  let f1_name = pool.intern("f1")
  let v1_root = {
    let v2 = pool.named_symbol(v2_name)
    field(pool, "f1", v2)
  }
  let v2_root = {
    let v3 = named(pool, "v3")
    let v4 = named(pool, "v4")
    pool.choice([v3, v4])
  }
  let v3_root = string(pool, "x")
  let v4_root = string(pool, "y")
  let grammar = {
    ..InputGrammar::new(),
    variables: [
      { name: v1_name, root: v1_root, },
      { name: v2_name, root: v2_root, },
      { name: v3_name, root: v3_root, },
      { name: v4_name, root: v4_root, },
    ],
    supertype_names: [v2_name],
    inline_names: [v2_name],
    pool,
  }
  let node_types = get_node_types(grammar)

  // The supertype entry for `_v2` is dropped, since the rule is inlined
  // away and can never appear in a tree. Previously a phantom `_v2`
  // entry with subtypes was emitted.
  assert_true(node_types.iter().all(n => n.kind != v2_name))
  let v1 = find_node(node_types, v1_name).unwrap()
  assert_eq(v1.fields.unwrap()[f1_name].types, [
    { kind: v3_name, named: true, },
    { kind: v4_name, named: true, },
  ])
}

// Error display texts (upstream `Display` impls).

///|
test "node_types error display" {
  inspect(
    VariableInfoError::SupertypeAliasCollision("_super"),
    content="Named alias `_super` conflicts with a supertype of the same name.",
  )
  inspect(
    VariableInfoError::InvalidSupertype({ supertype: "_sup", child: None, }),
    content="Supertypes must have a single visible child, but `_sup` can have multiple.",
  )
  inspect(
    VariableInfoError::InvalidSupertype({
      supertype: "_sup",
      child: Some("_pair"),
    }),
    content="Supertypes must have a single visible child, but `_sup` can have multiple. The hidden child `_pair` can expand into multiple nodes. Consider making `_pair` visible.",
  )
  inspect(
    SuperTypeCycleError(items=[]),
    content="Dependency cycle detected in node types:",
  )
  inspect(
    SuperTypeCycleError(items=["a", "b"]),
    content="Dependency cycle detected in node types: a, b",
  )
}

// Helpers (upstream `mod tests` helper functions).

///|
fn get_node_types(grammar : InputGrammar) -> Array[NodeInfoJSON] raise {
  let { syntax_grammar, lexical_grammar, inlines, default_aliases, str_pool, } = prepare_grammar(
    grammar,
    [],
  )
  let variable_info = get_variable_info(
    syntax_grammar, lexical_grammar, default_aliases, inlines, str_pool,
  )
  generate_node_types(
    syntax_grammar, lexical_grammar, default_aliases, variable_info, inlines, str_pool,
  )
}

///|
/// `nodes.iter().find(|node| node.kind == kind)`.
fn find_node(nodes : Array[NodeInfoJSON], kind : StrId) -> NodeInfoJSON? {
  for node in nodes {
    if node.kind == kind {
      return Some(node)
    }
  }
  None
}


///|
fn string(p : RulePool, value : String) -> RuleId {
  let value = p.intern(value)
  p.string(value)
}


///|
fn field(p : RulePool, name : String, content : RuleId) -> RuleId {
  let name = p.intern(name)
  p.field(name, content)
}

///|
fn alias(
  p : RulePool,
  content : RuleId,
  value : String,
  is_named : Bool,
) -> RuleId {
  let value = p.intern(value)
  p.alias(content, value, is_named)
}

///|
fn external(p : RulePool, index : Int32) -> RuleId {
  p.push_node(Sym(Symbol::external(index)))
}

///|
fn build_syntax_grammar(
  interner : StrPool,
  variables : Array[(String, VariableType, Array[Array[ProductionStep]])],
  supertype_symbols : Array[Symbol],
) -> SyntaxGrammar {
  let (steps, productions, var_prods, vars) = ([], [], [], [])
  for variable in variables {
    let (name, kind, prods) = variable
    let prod_start = productions.length()
    for prod_steps in prods {
      let steps_start = steps.length()
      steps.append(prod_steps)
      productions.push({
        steps_start,
        steps_len: steps.length() - steps_start,
        dynamic_precedence: 0,
        requires_eof_lookahead: false,
      })
    }
    var_prods.push((prod_start, productions.length()))
    vars.push({ name: interner.intern(name), kind, })
  }
  {
    variables: vars,
    extra_symbols: [],
    expected_conflicts: [],
    external_tokens: [],
    supertype_symbols,
    variables_to_inline: [],
    word_token: None,
    precedence_orderings: [],
    reserved_word_sets: [],
    steps,
    productions,
    var_prods,
  }
}

///|
fn build_lexical_grammar(interner : StrPool) -> LexicalGrammar {
  let lexical_grammar = LexicalGrammar::new()
  for i in 0..<10 {
    lexical_grammar.variables.push({
      name: interner.intern("token_\{i}"),
      kind: Named,
      implicit_precedence: 0,
      start_state: 0,
    })
  }
  lexical_grammar
}

///|
fn step(symbol : Symbol, field : StrId?) -> ProductionStep {
  ProductionStep::pack(
    symbol,
    NoPrecedence,
    None,
    None,
    field,
    no_reserved_words,
  )
}
