///|
priv struct Scope {
  node : @ts.Node
  inherits : Bool
}

///|
priv struct Definition {
  node : @ts.Node
  name : String
  scope : Int32
  visible_after : Int32
}

///|
/// Resolved lexical definitions and references from a Tree-sitter locals query.
pub struct Locals {
  priv bindings : Map[(Int32, Int32), @ts.Node]
}

///|
pub fn Locals::new(query : Query, tree : @ts.Tree) -> Locals raise QueryError {
  let matches = query.matches(tree.root_node(), tree.source)
  let scopes : Array[Scope] = [{ node: tree.root_node(), inherits: false, }]
  for matched in matches {
    for capture in matched.captures {
      if capture.name == "local.scope" {
        scopes.push({
          node: capture.node,
          inherits: matched.properties.get("local.scope-inherits") !=
          Some("false"),
        })
      }
    }
  }
  scopes.sort_by((a, b) => {
    let by_start = a.node.start_byte().compare(b.node.start_byte())
    if by_start != 0 {
      by_start
    } else {
      b.node.end_byte().compare(a.node.end_byte())
    }
  })
  let scope_for = fn(node : @ts.Node) {
    let mut result = 0
    for i, scope in scopes {
      if scope.node.start_byte() <= node.start_byte() &&
        scope.node.end_byte() >= node.end_byte() {
        result = i
      }
    }
    result
  }
  let definitions : Array[Definition] = []
  let bindings : Map[(Int32, Int32), @ts.Node] = Map([])
  for matched in matches {
    let values = matched.captures.filter(c => c.name == "local.definition-value")
    for capture in matched.captures {
      if capture.name == "local.definition" {
        let node = capture.node
        definitions.push({
          node,
          name: node.text(tree.source),
          scope: scope_for(node),
          visible_after: values.fold(init=node.end_byte(), (end, c) => {
            Int32::max(end, c.node.end_byte())
          }),
        })
        bindings[(node.start_byte(), node.end_byte())] = node
      }
    }
  }
  definitions.sort_by_key(d => d.visible_after)
  for matched in matches {
    for capture in matched.captures {
      if capture.name != "local.reference" {
        continue
      }
      let node = capture.node
      let key = (node.start_byte(), node.end_byte())
      if bindings.contains(key) {
        continue
      }
      let name = node.text(tree.source)
      let mut scope = scope_for(node)
      for ;; {
        let mut found = None
        for definition in definitions {
          if definition.scope == scope &&
            definition.name == name &&
            definition.visible_after <= node.start_byte() {
            found = Some(definition.node)
          }
        }
        if found is Some(definition) {
          bindings[key] = definition
          break
        }
        if scope == 0 || !scopes[scope].inherits {
          break
        }
        let current = scopes[scope].node
        let mut parent = 0
        for i in 0..<scope {
          if scopes[i].node.start_byte() <= current.start_byte() &&
            scopes[i].node.end_byte() >= current.end_byte() {
            parent = i
          }
        }
        scope = parent
      }
    }
  }
  { bindings, }
}

///|
pub fn Locals::definition(self : Locals, node : @ts.Node) -> @ts.Node? {
  self.bindings.get((node.start_byte(), node.end_byte()))
}

///|
pub fn Locals::is_local(self : Locals, node : @ts.Node) -> Bool {
  self.definition(node) is Some(_)
}
