// Cross-module contracts of the generator port. Each `declare` is implemented
// in the file that ports the corresponding upstream module.

///|
/// `prepare_grammar::LexicalToken`: a token extracted from the input grammar
/// but not yet expanded into the lexical NFA.
pub(all) struct LexicalToken {
  /// Generated for anonymous tokens, the rule name for absorbed variables.
  name : StrId
  kind : VariableType
  /// Pool root defining this token.
  root : RuleId
} derive(Debug)

///|
/// `node_types::ChildQuantity`.
pub(all) struct ChildQuantity {
  mut exists : Bool
  mut required : Bool
  mut multiple : Bool
} derive(Eq, Debug)

///|
/// `node_types::FieldInfo`.
pub(all) struct FieldInfo {
  mut quantity : ChildQuantity
  mut types : Array[ChildType]
} derive(Eq, Debug)

///|
/// `node_types::VariableInfo`. Upstream's `fields` is an `FxHashMap`; its
/// iteration order must never influence output.
pub(all) struct VariableInfo {
  mut fields : Map[StrId, FieldInfo]
  mut children : FieldInfo
  mut children_without_fields : FieldInfo
  mut has_multi_step_production : Bool
} derive(Eq, Debug)

///|
/// `build_tables::Tables`.
pub(all) struct Tables {
  parse_table : ParseTable
  main_lex_table : LexTable
  keyword_lex_table : LexTable
  large_character_sets : Array[(Symbol?, CharacterSet)]
}

///|
/// `generate::Diagnostic`.
pub(all) enum Diagnostic {
  UnnecessaryConflicts(Array[Array[String]])
  UnaryChoice(name~ : String?)
  UnarySeq(name~ : String?)
  UnsupportedRegexFlag(flag~ : Char, pattern~ : String)
  SupertypeInlined(name~ : String)
} derive(Eq, Debug)

///|
/// Upstream's `Display` text for a diagnostic.
pub impl Show for Diagnostic with output(self, logger) {
  match self {
    UnnecessaryConflicts(conflicts) => {
      logger.write_string("unnecessary conflicts:\n")
      for i, conflict in conflicts {
        logger.write_string("  ")
        for j, symbol in conflict {
          logger.write_string("`\{symbol}`")
          if j < conflict.length() - 1 {
            logger.write_string(", ")
          }
        }
        if i < conflicts.length() - 1 {
          logger.write_string("\n")
        }
      }
    }
    UnaryChoice(name~) =>
      logger.write_string(
        "rule \{name.unwrap_or("<ANONYMOUS>")} contains a `choice` rule with a single element. this is unnecessary.",
      )
    UnarySeq(name~) =>
      logger.write_string(
        "rule \{name.unwrap_or("<ANONYMOUS>")} contains a `seq` rule with a single element. this is unnecessary.",
      )
    UnsupportedRegexFlag(flag~, pattern~) =>
      logger.write_string(
        "unsupported regex flag `\{flag}` in pattern `\{pattern}`",
      )
    SupertypeInlined(name~) =>
      logger.write_string(
        "rule `\{name}` is both a supertype and inlined. the supertype is ignored.",
      )
  }
}

///|
/// `generate::OptLevel`; upstream's only flag is `MergeStates`.
pub(all) struct OptLevel {
  merge_states : Bool
} derive(Eq, Debug)

///|
pub let default_opt_level : OptLevel = { merge_states: true }

///|
/// `prepare_grammar::PreparedGrammar`.
pub(all) struct PreparedGrammar {
  syntax_grammar : SyntaxGrammar
  lexical_grammar : LexicalGrammar
  inlines : InlinedProductionMap
  default_aliases : AliasMap
  str_pool : StrPool
}

