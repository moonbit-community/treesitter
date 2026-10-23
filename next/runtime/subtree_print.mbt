// Port of `ts_subtree_string` and `ts_subtree_print_dot_graph` from
// tree-sitter lib/src/subtree.c.

///|
fn write_char_to_string(buf : StringBuilder, chr : Int32) -> Unit {
  if chr == -1 {
    buf.write_string("INVALID")
  } else if chr == 0 {
    buf.write_string("'\\0'")
  } else if chr == '\n' {
    buf.write_string("'\\n'")
  } else if chr == '\t' {
    buf.write_string("'\\t'")
  } else if chr == '\r' {
    buf.write_string("'\\r'")
  } else if 0 < chr && chr < 128 && chr >= 32 && chr < 127 {
    // `isprint` in the C locale.
    buf.write_string("'\{Int::unsafe_to_char(chr)}'")
  } else {
    buf.write_string("\{chr}")
  }
}

///|
priv struct WriteToStringFrame {
  subtree : Subtree
  alias_symbol : Int32
  alias_is_named : Bool
  field_name : String?
  is_root : Bool
  mut pre_written : Bool
  mut is_visible : Bool
  mut child_index : Int32
  mut structural_child_index : Int32
  mut alias_sequence : Int32?
  mut field_map : (Int32, Int32)
}

///|
/// `ts_subtree_string`: the S-expression for a subtree.
pub fn Subtree::to_sexp(
  self : Subtree,
  alias_symbol : Int32,
  alias_is_named : Bool,
  language : @language.Language,
  include_all : Bool,
) -> String {
  let buf = StringBuilder()
  let stack : Array[WriteToStringFrame] = [
    {
      subtree: self,
      alias_symbol,
      alias_is_named,
      field_name: None,
      is_root: true,
      pre_written: false,
      is_visible: false,
      child_index: 0,
      structural_child_index: 0,
      alias_sequence: None,
      field_map: (0, 0),
    },
  ]
  while stack.length() > 0 {
    let frame = stack[stack.length() - 1]
    let node = frame.subtree
    if node.is_null() {
      if !frame.is_root {
        buf.write_string(" ")
        if frame.field_name is Some(field_name) {
          buf.write_string("\{field_name}: ")
        }
      }
      buf.write_string("(NULL)")
      ignore(stack.pop())
      continue
    }
    if !frame.pre_written {
      let is_visible = include_all ||
        node.missing() ||
        (if frame.alias_symbol != 0 {
          frame.alias_is_named
        } else {
          node.visible() && node.named()
        })
      if is_visible {
        if !frame.is_root {
          buf.write_string(" ")
          if frame.field_name is Some(field_name) {
            buf.write_string("\{field_name}: ")
          }
        }
        if node.is_error() &&
          node.child_count() == 0 &&
          node.ptr().size.bytes > 0 {
          buf.write_string("(UNEXPECTED ")
          write_char_to_string(buf, node.ptr().lookahead_char)
        } else {
          let symbol = if frame.alias_symbol != 0 {
            frame.alias_symbol
          } else {
            node.symbol()
          }
          let symbol_name = language.symbol_name(symbol).unwrap_or("(null)")
          if node.missing() {
            buf.write_string("(MISSING ")
            if frame.alias_is_named || node.named() {
              buf.write_string(symbol_name)
            } else {
              buf.write_string("\"\{symbol_name}\"")
            }
          } else {
            buf.write_string("(\{symbol_name}")
          }
        }
      } else if frame.is_root {
        let symbol = if frame.alias_symbol != 0 {
          frame.alias_symbol
        } else {
          node.symbol()
        }
        let symbol_name = language.symbol_name(symbol).unwrap_or("(null)")
        if node.child_count() > 0 {
          buf.write_string("(\{symbol_name}")
        } else if node.named() {
          buf.write_string("(\{symbol_name})")
        } else {
          buf.write_string("(\"\{symbol_name}\")")
        }
      }
      if node.child_count() > 0 {
        frame.alias_sequence = language.alias_sequence(node.ptr().production_id)
        frame.field_map = language.field_map(node.ptr().production_id)
      }
      frame.is_visible = is_visible
      frame.pre_written = true
    }
    if frame.child_index < node.child_count() {
      let child = node.children()[frame.child_index]
      let mut child_alias_symbol = 0
      let mut child_alias_is_named = false
      let mut child_field_name : String? = None
      if !child.extra() {
        let subtree_alias_symbol = match frame.alias_sequence {
          Some(offset) =>
            language.alias_sequence_value(offset + frame.structural_child_index)
          None => 0
        }
        let subtree_alias_is_named = if subtree_alias_symbol != 0 {
          language.symbol_metadata_of(subtree_alias_symbol).named
        } else {
          false
        }
        child_field_name = if frame.is_visible {
          None
        } else {
          frame.field_name
        }
        let (start, end) = frame.field_map
        for i in start..<end {
          let map = language.field_map_entries[i]
          if !map.inherited && map.child_index == frame.structural_child_index {
            child_field_name = Some(language.field_names[map.field_id])
            break
          }
        }
        child_alias_symbol = subtree_alias_symbol
        child_alias_is_named = subtree_alias_is_named
        frame.structural_child_index += 1
      }
      frame.child_index += 1
      stack.push({
        subtree: child,
        alias_symbol: child_alias_symbol,
        alias_is_named: child_alias_is_named,
        field_name: child_field_name,
        is_root: false,
        pre_written: false,
        is_visible: false,
        child_index: 0,
        structural_child_index: 0,
        alias_sequence: None,
        field_map: (0, 0),
      })
      continue
    }
    if frame.is_visible {
      buf.write_string(")")
    }
    ignore(stack.pop())
  }
  buf.to_string()
}

///|
fn write_dot_node(
  tree : Subtree,
  id : String,
  start_offset : UInt32,
  language : @language.Language,
  alias_symbol : Int32,
  f : StringBuilder,
) -> Unit {
  let subtree_symbol = tree.symbol()
  let symbol = if alias_symbol != 0 { alias_symbol } else { subtree_symbol }
  let end_offset = start_offset + tree.total_bytes()
  f.write_string("tree_\{id} [label=\"")
  write_symbol_as_dot_string(language, f, symbol)
  f.write_string("\"")
  if tree.child_count() == 0 {
    f.write_string(", shape=plaintext")
  }
  if tree.extra() {
    f.write_string(", fontcolor=gray")
  }
  if tree.has_changes() {
    f.write_string(", color=green, penwidth=2")
  }
  let b = (x : Bool) => if x { 1 } else { 0 }
  f.write_string(
    ", tooltip=\"range: \{start_offset} - \{end_offset}\nstate: \{tree.parse_state()}\nerror-cost: \{tree.error_cost()}\nhas-changes: \{b(tree.has_changes())}\ndepends-on-column: \{b(tree.depends_on_column())}\ndescendant-count: \{tree.visible_descendant_count()}\nrepeat-depth: \{tree.repeat_depth()}\nlookahead-bytes: \{tree.lookahead_bytes()}",
  )
  if tree.is_error() &&
    tree.child_count() == 0 &&
    tree.ptr().lookahead_char != 0 {
    let chr = tree.ptr().lookahead_char
    f.write_string("\ncharacter: '\{Int::unsafe_to_char(chr & 0xFF)}'")
  }
  f.write_string("\"]\n")
}

///|
priv struct DotGraphFrame {
  subtree : Subtree
  id : Int
  // The id of the child written last (C prints its address).
  mut last_child_id : Int
  mut child_index : Int32
  mut child_start_offset : UInt32
  mut child_info_offset : Int32
}

///|
/// `ts_subtree_print_dot_graph`. Node addresses are replaced by sequence
/// numbers (paths would make the output quadratic in the tree depth).
pub fn Subtree::print_dot_graph(
  self : Subtree,
  language : @language.Language,
  f : StringBuilder,
) -> Unit {
  f.write_string("digraph tree {\n")
  f.write_string("edge [arrowhead=none]\n")
  write_dot_node(self, "0", 0, language, 0, f)
  let mut next_id = 1
  let stack : Array[DotGraphFrame] = [
    {
      subtree: self,
      id: 0,
      last_child_id: 0,
      child_index: 0,
      child_start_offset: 0,
      child_info_offset: language.max_alias_sequence_length *
      self.production_id(),
    },
  ]
  while stack.length() > 0 {
    let frame = stack[stack.length() - 1]
    let subtree = frame.subtree
    let i = frame.child_index
    if i > 0 {
      f.write_string(
        "tree_\{frame.id} -> tree_\{frame.last_child_id} [tooltip=\{i - 1}]\n",
      )
    }
    if i == subtree.child_count() {
      ignore(stack.pop())
      continue
    }
    let child = subtree.children()[i]
    let mut subtree_alias_symbol = 0
    if !child.extra() && frame.child_info_offset != 0 {
      subtree_alias_symbol = language.alias_sequence_value(
        frame.child_info_offset,
      )
      frame.child_info_offset += 1
    }
    let child_id = next_id
    next_id += 1
    frame.last_child_id = child_id
    write_dot_node(
      child,
      child_id.to_string(),
      frame.child_start_offset,
      language,
      subtree_alias_symbol,
      f,
    )
    let child_frame : DotGraphFrame = {
      subtree: child,
      id: child_id,
      last_child_id: 0,
      child_index: 0,
      child_start_offset: frame.child_start_offset,
      child_info_offset: language.max_alias_sequence_length *
      child.production_id(),
    }
    frame.child_start_offset += child.total_bytes()
    frame.child_index += 1
    stack.push(child_frame)
  }
  f.write_string("}\n")
}
