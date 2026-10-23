// Port of tree-sitter crates/generate/src/prepare_grammar/extract_default_aliases.rs.

///|
priv struct SymbolStatus {
  aliases : Array[(Alias, Int32)]
  mut appears_unaliased : Bool
}

///|
fn SymbolStatus::new() -> SymbolStatus {
  { aliases: [], appears_unaliased: false, }
}

///|
fn symbol_status_list(len : Int32) -> Array[SymbolStatus] {
  Array::makei(len, _ => SymbolStatus::new())
}

///|
// Update the grammar by finding symbols that always are aliased, and for each such symbol,
// promoting one of its aliases to a "default alias", which is applied globally instead
// of in a context-specific way.
//
// This has two benefits:
// * It reduces the overhead of storing production-specific alias info in the parse table.
// * Within an `ERROR` node, no context-specific aliases will be applied. This transformation
//   ensures that the children of an `ERROR` node have symbols that are consistent with the way that
//   they would appear in a valid syntax tree.
fn extract_default_aliases(
  g : InputGrammar,
  meta : ExtractedGrammarMeta,
  lexical_variables : Array[LexicalVariable],
  out : ProductionStore,
) -> AliasMap {
  let terminal_status_list = symbol_status_list(lexical_variables.length())
  let non_terminal_status_list = symbol_status_list(g.variables.length())
  let external_status_list = symbol_status_list(meta.external_tokens.length())
  fn status_for(symbol : Symbol) -> SymbolStatus {
    match symbol.kind {
      External => external_status_list[symbol.index]
      NonTerminal => non_terminal_status_list[symbol.index]
      Terminal => terminal_status_list[symbol.index]
      End | EndOfNonTerminalExtra => abort("Unexpected end token")
    }
  }

  // For each grammar symbol, find all of the aliases under which the symbol appears,
  // and determine whether or not the symbol ever appears *unaliased*.
  for prod in out.productions {
    for step in out.steps[prod.steps_start:prod.steps_start + prod.steps_len] {
      let symbol = step.symbol
      let status = status_for(symbol)

      // Default aliases don't work for inlined variables.
      if meta.inline.contains(symbol) {
        continue
      }
      if step.alias is Some(alias) {
        let found = for i, entry in status.aliases {
          if entry.0 == alias {
            break Some(i)
          }
        } nobreak {
          None
        }
        match found {
          Some(i) => {
            let (a, count) = status.aliases[i]
            status.aliases[i] = (a, count + 1)
          }
          None => status.aliases.push((alias, 1))
        }
      } else {
        status.appears_unaliased = true
      }
    }
  }
  for symbol in meta.extra_symbols {
    status_for(symbol).appears_unaliased = true
  }
  let symbols_with_statuses : Array[(Symbol, SymbolStatus)] = []
  for i, status in terminal_status_list {
    symbols_with_statuses.push((Symbol::terminal(i), status))
  }
  for i, status in non_terminal_status_list {
    symbols_with_statuses.push((Symbol::non_terminal(i), status))
  }
  for i, status in external_status_list {
    symbols_with_statuses.push((Symbol::external(i), status))
  }

  // For each symbol that always appears aliased, find the alias that occurs most often,
  // and designate that alias as the symbol's "default alias". Store all of these
  // default aliases in a map that will be returned.
  let result : AliasMap = @sorted_map.SortedMap([])
  for entry in symbols_with_statuses {
    let (symbol, status) = entry
    if status.appears_unaliased {
      status.aliases.clear()
    } else if !status.aliases.is_empty() {
      // `max_by_key(|(i, (_, count))| (count, -i))`: the highest count, and the
      // earliest alias among equal counts.
      let mut best = 0
      for i in 1..<status.aliases.length() {
        if status.aliases[i].1 > status.aliases[best].1 {
          best = i
        }
      }
      let default_entry = status.aliases[best]
      status.aliases.clear()
      status.aliases.push(default_entry)
      result.set(symbol, default_entry.0)
    }
  }

  // Wherever a symbol is aliased as its default alias, remove the usage of the alias,
  // because it will now be redundant.
  let alias_positions_to_clear = []
  for range in out.var_prods {
    let (p_start, p_end) = range
    alias_positions_to_clear.clear()
    let productions = out.productions[p_start:p_end]
    for i, prod in productions {
      for j in 0..<prod.steps_len {
        let step = out.steps[prod.steps_start + j]
        let symbol = step.symbol
        let status = status_for(symbol)

        // If this step is aliased as the symbol's default alias, then remove that alias.
        let default_alias = match status.aliases.get(0) {
          Some(t) => Some(t.0)
          None => None
        }
        if step.alias is Some(_) && step.alias == default_alias {
          let mut other_productions_must_use_this_alias_at_this_index = false
          for other_i, other_prod in productions {
            if other_i != i &&
              other_prod.steps_len > j &&
              out.steps[other_prod.steps_start + j].alias == step.alias &&
              result.get(out.steps[other_prod.steps_start + j].symbol) !=
              step.alias {
              other_productions_must_use_this_alias_at_this_index = true
              break
            }
          }
          if !other_productions_must_use_this_alias_at_this_index {
            alias_positions_to_clear.push(prod.steps_start + j)
          }
        }
      }
    }
    for step_index in alias_positions_to_clear {
      out.steps[step_index] = out.steps[step_index].with_alias(None)
    }
  }
  result
}
