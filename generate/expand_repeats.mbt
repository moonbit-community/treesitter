// Port of tree-sitter crates/generate/src/prepare_grammar/expand_repeats.rs.

///|
priv struct Expander {
  preceding : Int32
  aux : Array[Variable]
  /// Keyed by `subtree_hash`; only used for lookups. The contents in a bucket
  /// are pairwise distinct, so at most one candidate can match.
  memo : Map[Int32, Array[(RuleId, Symbol)]]
  stack : Array[ExpandTask]
  zero_width : ZeroWidth
}

///|
priv enum ExpandTask {
  Visit(RuleId)
  Expand(id~ : RuleId, content~ : RuleId)
}

///|
pub(all) suberror ExpandRepeatsError {
  ExpandRepeatsError(String)
} derive(Eq, Debug)

///|
pub impl Show for ExpandRepeatsError with fn output(self, logger) {
  let ExpandRepeatsError(name) = self
  logger.write_string(
    "Rule `\{name}` contains a repetition that can match the empty string at end of input",
  )
}

///|
/// Post-order repeat expansion over one root. Children expand first, and `Reserved`
/// nodes are not descended.
fn Expander::expand_root(
  self : Expander,
  pool : RulePool,
  root : RuleId,
  var_name : StrId,
  aux_repeat_counter : Ref[Int32],
) -> Unit raise ExpandRepeatsError {
  self.stack.clear()
  self.stack.push(Visit(root))
  while self.stack.pop() is Some(task) {
    match task {
      Visit(id) =>
        match pool.node(id) {
          Repeat(content) => {
            self.stack.push(Expand(id~, content~))
            self.stack.push(Visit(content))
          }
          // For choices, sequences, and metadata, descend into the child rules,
          // replacing any nested repetitions.
          Seq(range) | Choice(range) => {
            let children = pool.child_slice(range)
            for i = children.length() - 1; i >= 0; i = i - 1 {
              self.stack.push(Visit(children[i]))
            }
          }
          Metadata(rule~, ..) => self.stack.push(Visit(rule))
          _ => () // For primitive rules, don't change anything.
        }
      Expand(id~, content~) => {
        let width = self.zero_width.eval(pool, content)
        if width.eof_nullable {
          raise ExpandRepeatsError(pool.resolve(var_name))
        }
        // For repetitions, introduce an auxiliary rule that contains the
        // repeated content, but can also contain a recursive binary tree structure.
        let hash = pool.subtree_hash(content)
        let existing = match self.memo.get(hash) {
          Some(candidates) =>
            for candidate in candidates {
              let (node, symbol) = candidate
              if pool.subtree_eq(node, content) {
                break Some(symbol)
              }
            } nobreak {
              None
            }
          None => None
        }
        if existing is Some(symbol) {
          pool.set_node(id, Sym(symbol))
          continue
        }
        aux_repeat_counter.val += 1
        let name = "\{pool.resolve(var_name)}_repeat\{aux_repeat_counter.val}"
        let name = pool.intern(name)
        // Aux rules are appended after the original variables, so they occupy
        // non-terminal indices `preceding..`. The aux stands for `Repeat(content)`,
        // which matches zero width exactly when `content` does.
        let symbol = Symbol::non_terminal(self.preceding + self.aux.length())
        self.zero_width.push_variable(width)
        match self.memo.get(hash) {
          Some(candidates) => candidates.push((content, symbol))
          None => self.memo[hash] = [(content, symbol)]
        }
        let root = wrap_in_binary_tree(pool, symbol, content)
        self.aux.push({ name, root, })
        pool.set_node(id, Sym(symbol))
      }
    }
  }
}

///|
/// Whether a rule can match zero characters, with and without crossing an `eof()`.
priv struct Width {
  nullable : Bool
  eof_nullable : Bool
} derive(Eq)

///|
let width_default : Width = { nullable: false, eof_nullable: false, }

///|
/// Fold `other` in, reporting whether that set anything new to `true`.
fn Width::merge(self : Width, other : Width) -> (Width, Bool) {
  let merged = {
    nullable: self.nullable || other.nullable,
    eof_nullable: self.eof_nullable || other.eof_nullable,
  }
  (merged, merged != self)
}

///|
priv enum ZeroWidthVisit {
  Enter(RuleId)
  Exit(RuleId)
}

///|
/// Zero width analysis over the rule pool.
///
/// `by_variable` is seeded by a fixpoint over the whole grammar before any expansion,
/// which makes results indepedent of the order in which rules are declared.
priv struct ZeroWidth {
  by_variable : Array[Width]
  stack : Array[ZeroWidthVisit]
  values : Array[Width]
}

///|
/// Seed `by_variable` with every rule's width, as a least fixpoint.
///
/// [`Self::eval`] reads a nonterminal's width from this table, but rules can
/// reference each other cyclically. Every rule starts at "matches nothing", and
/// all of them are re-evaluated against the current table until a full pass
/// changes nothing. Starting there prevents a cycle from marking itself. A rule
/// that reaches itself reads back  "matches nothing", so flags are only set by
/// a path that truly matches zero width.
fn ZeroWidth::new(pool : RulePool, variables : Array[Variable]) -> ZeroWidth {
  let this : ZeroWidth = {
    by_variable: Array::make(variables.length(), width_default),
    stack: [],
    values: [],
  }
  for ;; {
    let mut changed = false
    for i, v in variables {
      let width = this.eval(pool, v.root)
      let (merged, did_change) = this.by_variable[i].merge(width)
      this.by_variable[i] = merged
      changed = changed || did_change
    }
    if !changed {
      break
    }
  }
  this
}

///|
/// Record the width of a newly created auxiliary rule.
fn ZeroWidth::push_variable(self : ZeroWidth, width : Width) -> Unit {
  self.by_variable.push(width)
}

///|
/// Post-order walk of the subtree at `root`, combining children into their parent.
fn ZeroWidth::eval(self : ZeroWidth, pool : RulePool, root : RuleId) -> Width {
  self.stack.clear()
  self.values.clear()
  self.stack.push(Enter(root))
  while self.stack.pop() is Some(step) {
    match step {
      Enter(id) =>
        match pool.node(id) {
          Seq(range) | Choice(range) => {
            self.stack.push(Exit(id))
            for c in pool.child_slice(range) {
              self.stack.push(Enter(c))
            }
          }
          Repeat(rule) | Metadata(rule~, ..) | Reserved(rule~, ..) => {
            self.stack.push(Exit(id))
            self.stack.push(Enter(rule))
          }
          Blank => self.values.push({ nullable: true, eof_nullable: false, })
          String(s) =>
            self.values.push({
              nullable: s == empty_str_id,
              eof_nullable: false,
            })
          Eof => self.values.push({ nullable: false, eof_nullable: true, })
          Sym(symbol) => {
            let width : Width = match symbol.kind {
              End => { nullable: false, eof_nullable: true, }
              NonTerminal =>
                self.by_variable.get(symbol.index).unwrap_or(width_default)
              // External scanners decide at runtime how far to advance
              // and may return a zero width token, so this must count
              // as nullable.
              //
              // A scanner may gate itself on `lexer->eof`, but there's
              // no way to determine that here. Assuming so would reject
              // every grammar that `repeat`s an external.
              External => { nullable: true, eof_nullable: false, }
              // `expand_tokens` rejects tokens that match the empty string
              Terminal => width_default
              // Lookahead marker that `build_parse_table` inserts for nonterminal
              // extras _after_ this pass runs.
              EndOfNonTerminalExtra => abort("unreachable")
            }
            self.values.push(width)
          }
          // `extract_tokens` hoists every `Pattern` into the lexical grammar and
          // leaves a terminal symbol in its place. Only syntactic  (non
          // lexical grammar) rules are walked here.
          Pattern(_, _)
          // `intern_symbols` resolves every `NamedSymbol` to a `Sym`
          | NamedSymbol(_) => abort("unreachable")
        }
      Exit(id) =>
        match pool.node(id) {
          Choice(range) => {
            let base = self.values.length() - range.len
            let mut nullable = false
            let mut eof_nullable = false
            for i in base..<self.values.length() {
              let child = self.values[i]
              nullable = nullable || child.nullable
              eof_nullable = eof_nullable || child.eof_nullable
            }
            self.values.truncate(base)
            self.values.push({ nullable, eof_nullable, })
          }
          Seq(range) => {
            let base = self.values.length() - range.len
            let mut nullable = true // matches empty iff every element does
            let mut any_eof = false // matches eof if any element does
            let mut all_zero_width = true // every element matches empty or via `eof()`
            for i in base..<self.values.length() {
              let child = self.values[i]
              nullable = nullable && child.nullable
              any_eof = any_eof || child.eof_nullable
              all_zero_width = all_zero_width &&
                (child.nullable || child.eof_nullable)
            }
            self.values.truncate(base)
            self.values.push({
              nullable,
              eof_nullable: all_zero_width && any_eof,
            })
          }
          // Each of these wraps a single child whose width is both already on the
          // stack and exactly this (the wrapper) node's width:
          //
          // - `Repeat` is one or more, so it matches zero width exactly when its content
          //   does. Zero or more comes in  as `Choice(Repeat, Blank)` from
          //   `parse_grammar`, so that blank gives the nullable case instead of here.
          // - `Metadata` carries wrapping data that doesn't change how much input is
          //   matched. Its `token` forms are already replaced by terminals in
          //   `extrac_tokens`.
          // - `Reserved` only names the reserved word set for a its child.
          Repeat(_) | Metadata(_) | Reserved(_) => ()
          // Every other rule is a leaf. `Enter` pushed its width directly and
          // never queued an `Exit`.
          _ => abort("unreachable")
        }
    }
  }
  self.values.pop().unwrap_or(width_default)
}

///|
/// Build a repeat aux body of `choice(seq(sym, sym), inner)`
fn wrap_in_binary_tree(
  pool : RulePool,
  symbol : Symbol,
  inner : RuleId,
) -> RuleId {
  let s1 = pool.push_node(Sym(symbol))
  let s2 = pool.push_node(Sym(symbol))
  let range = pool.push_children([s1, s2])
  let seq = pool.push_node(Seq(range))
  let elements = [seq]
  let stack = [inner]
  while stack.pop() is Some(id) {
    if pool.node(id) is Choice(range) {
      let children = pool.child_slice(range)
      for i = children.length() - 1; i >= 0; i = i - 1 {
        stack.push(children[i])
      }
    } else if !elements.iter().any(e => pool.subtree_eq(e, id)) {
      elements.push(id)
    }
  }
  if elements.length() == 1 {
    elements[0]
  } else {
    let range = pool.push_children(elements)
    pool.push_node(Choice(range))
  }
}

///|
fn expand_repeats(
  grammar : InputGrammar,
  meta : ExtractedGrammarMeta,
) -> Unit raise ExpandRepeatsError {
  let expander : Expander = {
    preceding: grammar.variables.length(),
    zero_width: ZeroWidth::new(grammar.pool, grammar.variables),
    aux: [],
    memo: Map([]),
    stack: [],
  }
  for i in 0..<grammar.variables.length() {
    let { name, root, } = grammar.variables[i]
    let aux_repeat_count : Ref[Int32] = { val: 0, }

    // A hidden variable with a top level repetition becomes its own recursive binary
    // tree instead of gaining an auxiliary rule, and can no longer be inlined.
    if meta.kinds[i] == Hidden && grammar.pool.node(root) is Repeat(content) {
      if expander.zero_width.eval(grammar.pool, content).eof_nullable {
        raise ExpandRepeatsError(grammar.pool.resolve(name))
      }
      expander.expand_root(grammar.pool, content, name, aux_repeat_count)
      grammar.variables[i] = {
        name,
        root: wrap_in_binary_tree(
          grammar.pool,
          Symbol::non_terminal(i),
          content,
        ),
      }
      meta.kinds[i] = Auxiliary
      meta.inline.retain(s => s != Symbol::non_terminal(i))
      continue
    }
    expander.expand_root(grammar.pool, root, name, aux_repeat_count)
  }
  for variable in expander.aux {
    grammar.variables.push(variable)
    meta.kinds.push(Auxiliary)
  }
}
