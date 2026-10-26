///|
/// Released stack records kept for reuse must not keep the released graph
/// alive: upstream frees everything past its bounded pools.
test "stack pools drop references to released nodes" {
  let stack = Stack::new()
  for i in 0..<100 {
    stack.push(0, Subtree::null(), false, i + 2)
  }
  let version = stack.copy_version(0)
  stack.push(version, Subtree::null(), false, 200)
  ignore(stack.pop_count(version, 3))
  stack.clear()
  assert_eq(stack.node_pool.length(), max_node_pool_size)
  for node in stack.node_pool {
    for i in 0..<node.links.length() {
      assert_true(physical_equal(node.links[i].node, stack_node_detached))
      assert_true(node.links[i].subtree.is_null())
    }
  }
  assert_true(stack.head_pool.length() > 0)
  for head in stack.head_pool {
    assert_true(physical_equal(head.node, stack.base_node))
    assert_true(head.last_external_token.is_null())
    assert_true(head.lookahead_when_paused.is_null())
  }
  assert_true(stack.iterator_pool.length() > 0)
  for iterator in stack.iterator_pool {
    assert_true(physical_equal(iterator.node, stack.base_node))
    assert_eq(iterator.subtrees.length(), 0)
  }
  // The recycled records still work.
  stack.push(0, Subtree::null(), false, 7)
  assert_eq(stack.state(0), 7)
  assert_eq(stack.pop_count(0, 1).length(), 1)
}
