// Port of regex-syntax 0.8.11 src/ast/visitor.rs.

///|
/// A trait for visiting an abstract syntax tree (AST) in depth first order.
///
/// Typical usage of this trait involves providing an implementation and then
/// running it using the [`visit`] function. Upstream's `finish` (which yields
/// the visitor's output) is left to the caller after `visit` returns.
pub(open) trait Visitor {
  /// This method is called before beginning traversal of the AST.
  fn start(Self) -> Unit = _
  /// This method is called on an `Ast` before descending into child `Ast`
  /// nodes.
  fn visit_pre(Self, Ast) -> Unit raise = _
  /// This method is called on an `Ast` after descending all of its child
  /// `Ast` nodes.
  fn visit_post(Self, Ast) -> Unit raise = _
  /// This method is called between child nodes of an `Alternation`.
  fn visit_alternation_in(Self) -> Unit raise = _
  /// This method is called between child nodes of a concatenation.
  fn visit_concat_in(Self) -> Unit raise = _
  /// This method is called on every `ClassSetItem` before descending into
  /// child nodes.
  fn visit_class_set_item_pre(Self, ClassSetItem) -> Unit raise = _
  /// This method is called on every `ClassSetItem` after descending into
  /// child nodes.
  fn visit_class_set_item_post(Self, ClassSetItem) -> Unit raise = _
  /// This method is called on every `ClassSetBinaryOp` before descending into
  /// child nodes.
  fn visit_class_set_binary_op_pre(Self, ClassSetBinaryOp) -> Unit raise = _
  /// This method is called on every `ClassSetBinaryOp` after descending into
  /// child nodes.
  fn visit_class_set_binary_op_post(Self, ClassSetBinaryOp) -> Unit raise = _
  /// This method is called between the left hand and right hand child nodes
  /// of a `ClassSetBinaryOp`.
  fn visit_class_set_binary_op_in(Self, ClassSetBinaryOp) -> Unit raise = _
}

///|
impl Visitor with fn start(_self) {
  ()
}

///|
impl Visitor with fn visit_pre(_self, _ast) {
  ()
}

///|
impl Visitor with fn visit_post(_self, _ast) {
  ()
}

///|
impl Visitor with fn visit_alternation_in(_self) {
  ()
}

///|
impl Visitor with fn visit_concat_in(_self) {
  ()
}

///|
impl Visitor with fn visit_class_set_item_pre(_self, _ast) {
  ()
}

///|
impl Visitor with fn visit_class_set_item_post(_self, _ast) {
  ()
}

///|
impl Visitor with fn visit_class_set_binary_op_pre(_self, _ast) {
  ()
}

///|
impl Visitor with fn visit_class_set_binary_op_post(_self, _ast) {
  ()
}

///|
impl Visitor with fn visit_class_set_binary_op_in(_self, _ast) {
  ()
}

///|
/// Executes an implementation of `Visitor` in constant stack space.
///
/// This function will visit every node in the given `Ast` while calling the
/// appropriate methods provided by the [`Visitor`] trait.
///
/// If the visitor returns an error at any point, then visiting is stopped and
/// the error is returned.
pub fn[V : Visitor] visit(ast : Ast, visitor : V) -> Unit raise {
  HeapVisitor::new().visit(ast, visitor)
}

///|
/// HeapVisitor visits every item in an `Ast` recursively using constant stack
/// size and a heap size proportional to the size of the `Ast`.
priv struct HeapVisitor {
  /// A stack of `Ast` nodes. This is roughly analogous to the call stack
  /// used in a typical recursive visitor.
  stack : Array[(Ast, Frame)]
  /// Similar to the `Ast` stack above, but is used only for character
  /// classes. In particular, character classes embed their own mini
  /// recursive syntax.
  stack_class : Array[(ClassInduct, ClassFrame)]
}

///|
/// Represents a single stack frame while performing structural induction over
/// an `Ast`. Upstream's `head`/`tail` slices are an array and the index of
/// `head`.
priv enum Frame {
  /// A stack frame allocated just before descending into a repetition
  /// operator's child node.
  Repetition(Repetition)
  /// A stack frame allocated just before descending into a group's child
  /// node.
  Group(Group)
  /// The stack frame used while visiting every child node of a concatenation
  /// of expressions.
  Concat(Array[Ast], Int32)
  /// The stack frame used while visiting every child node of an alternation
  /// of expressions.
  Alternation(Array[Ast], Int32)
}

///|
/// Represents a single stack frame while performing structural induction over
/// a character class.
priv enum ClassFrame {
  /// The stack frame used while visiting every child node of a union of
  /// character class items.
  Union(Array[ClassSetItem], Int32)
  /// The stack frame used while a binary class operation.
  Binary(ClassSetBinaryOp)
  /// A stack frame allocated just before descending into a binary operator's
  /// left hand child node.
  BinaryLHS(ClassSetBinaryOp)
  /// A stack frame allocated just before descending into a binary operator's
  /// right hand child node.
  BinaryRHS(ClassSetBinaryOp)
}

///|
/// A representation of the inductive step when performing structural induction
/// over a character class.
priv enum ClassInduct {
  Item(ClassSetItem)
  BinaryOp(ClassSetBinaryOp)
}

///|
fn HeapVisitor::new() -> HeapVisitor {
  { stack: [], stack_class: [], }
}

///|
fn[V : Visitor] HeapVisitor::visit(
  self : HeapVisitor,
  ast : Ast,
  visitor : V,
) -> Unit raise {
  self.stack.clear()
  self.stack_class.clear()
  visitor.start()
  let mut ast = ast
  while true {
    visitor.visit_pre(ast)
    if self.induct(ast, visitor) is Some(x) {
      let child = x.child()
      self.stack.push((ast, x))
      ast = child
      continue
    }
    // No induction means we have a base case, so we can post visit
    // it now.
    visitor.visit_post(ast)

    // At this point, we now try to pop our call stack until it is
    // either empty or we hit another inductive case.
    while true {
      let (post_ast, frame) = match self.stack.pop() {
        None => return
        Some(item) => item
      }
      // If this is a concat/alternate, then we might have additional
      // inductive steps to process.
      if self.pop(frame) is Some(x) {
        match x {
          Alternation(_, _) => visitor.visit_alternation_in()
          Concat(_, _) => visitor.visit_concat_in()
          _ => ()
        }
        ast = x.child()
        self.stack.push((post_ast, x))
        break
      }
      // Otherwise, we've finished visiting all the child nodes for
      // this AST, so we can post visit it now.
      visitor.visit_post(post_ast)
    }
  }
}

///|
/// Build a stack frame for the given AST if one is needed (which occurs if
/// and only if there are child nodes in the AST). Otherwise, return None.
///
/// If this visits a class, then the underlying visitor implementation may
/// return an error which will be passed on here.
fn[V : Visitor] HeapVisitor::induct(
  self : HeapVisitor,
  ast : Ast,
  visitor : V,
) -> Frame? raise {
  match ast {
    ClassBracketed(x) => {
      self.visit_class(x, visitor)
      None
    }
    Repetition(x) => Some(Frame::Repetition(x))
    Group(x) => Some(Frame::Group(x))
    Concat(x) if x.asts.is_empty() => None
    Concat(x) => Some(Frame::Concat(x.asts, 0))
    Alternation(x) if x.asts.is_empty() => None
    Alternation(x) => Some(Frame::Alternation(x.asts, 0))
    _ => None
  }
}

///|
/// Pops the given frame. If the frame has an additional inductive step,
/// then return it, otherwise return `None`.
fn HeapVisitor::pop(_self : HeapVisitor, induct : Frame) -> Frame? {
  match induct {
    Repetition(_) => None
    Group(_) => None
    Concat(asts, i) =>
      if i + 1 >= asts.length() {
        None
      } else {
        Some(Concat(asts, i + 1))
      }
    Alternation(asts, i) =>
      if i + 1 >= asts.length() {
        None
      } else {
        Some(Alternation(asts, i + 1))
      }
  }
}

///|
fn[V : Visitor] HeapVisitor::visit_class(
  self : HeapVisitor,
  ast : ClassBracketed,
  visitor : V,
) -> Unit raise {
  let mut ast = ClassInduct::from_bracketed(ast)
  while true {
    self.visit_class_pre(ast, visitor)
    if self.induct_class(ast) is Some(x) {
      let child = x.child()
      self.stack_class.push((ast, x))
      ast = child
      continue
    }
    self.visit_class_post(ast, visitor)

    // At this point, we now try to pop our call stack until it is
    // either empty or we hit another inductive case.
    while true {
      let (post_ast, frame) = match self.stack_class.pop() {
        None => return
        Some(item) => item
      }
      // If this is a union or a binary op, then we might have
      // additional inductive steps to process.
      if self.pop_class(frame) is Some(x) {
        if x is BinaryRHS(op) {
          visitor.visit_class_set_binary_op_in(op)
        }
        ast = x.child()
        self.stack_class.push((post_ast, x))
        break
      }
      // Otherwise, we've finished visiting all the child nodes for
      // this class node, so we can post visit it now.
      self.visit_class_post(post_ast, visitor)
    }
  }
}

///|
/// Call the appropriate `Visitor` methods given an inductive step.
fn[V : Visitor] HeapVisitor::visit_class_pre(
  _self : HeapVisitor,
  ast : ClassInduct,
  visitor : V,
) -> Unit raise {
  match ast {
    Item(item) => visitor.visit_class_set_item_pre(item)
    BinaryOp(op) => visitor.visit_class_set_binary_op_pre(op)
  }
}

///|
/// Call the appropriate `Visitor` methods given an inductive step.
fn[V : Visitor] HeapVisitor::visit_class_post(
  _self : HeapVisitor,
  ast : ClassInduct,
  visitor : V,
) -> Unit raise {
  match ast {
    Item(item) => visitor.visit_class_set_item_post(item)
    BinaryOp(op) => visitor.visit_class_set_binary_op_post(op)
  }
}

///|
/// Build a stack frame for the given class node if one is needed (which
/// occurs if and only if there are child nodes). Otherwise, return None.
fn HeapVisitor::induct_class(
  _self : HeapVisitor,
  ast : ClassInduct,
) -> ClassFrame? {
  match ast {
    Item(Bracketed(x)) =>
      match x.kind {
        Item(item) => Some(ClassFrame::Union([item], 0))
        BinaryOp(op) => Some(ClassFrame::Binary(op))
      }
    Item(Union(x)) =>
      if x.items.is_empty() {
        None
      } else {
        Some(ClassFrame::Union(x.items, 0))
      }
    BinaryOp(op) => Some(ClassFrame::BinaryLHS(op))
    _ => None
  }
}

///|
/// Pops the given frame. If the frame has an additional inductive step,
/// then return it, otherwise return `None`.
fn HeapVisitor::pop_class(
  _self : HeapVisitor,
  induct : ClassFrame,
) -> ClassFrame? {
  match induct {
    Union(items, i) =>
      if i + 1 >= items.length() {
        None
      } else {
        Some(Union(items, i + 1))
      }
    Binary(_) => None
    BinaryLHS(op) => Some(BinaryRHS(op))
    BinaryRHS(_) => None
  }
}

///|
/// Perform the next inductive step on this frame and return the next
/// child AST node to visit.
fn Frame::child(self : Frame) -> Ast {
  match self {
    Repetition(rep) => rep.ast
    Group(group) => group.ast
    Concat(asts, i) => asts[i]
    Alternation(asts, i) => asts[i]
  }
}

///|
/// Perform the next inductive step on this frame and return the next
/// child class node to visit.
fn ClassFrame::child(self : ClassFrame) -> ClassInduct {
  match self {
    Union(items, i) => Item(items[i])
    Binary(op) => BinaryOp(op)
    BinaryLHS(op) => ClassInduct::from_set(op.lhs)
    BinaryRHS(op) => ClassInduct::from_set(op.rhs)
  }
}

///|
fn ClassInduct::from_bracketed(ast : ClassBracketed) -> ClassInduct {
  ClassInduct::from_set(ast.kind)
}

///|
fn ClassInduct::from_set(ast : ClassSet) -> ClassInduct {
  match ast {
    Item(item) => Item(item)
    BinaryOp(op) => BinaryOp(op)
  }
}
