// serde's `Serialize` of upstream's `GenerateError` (generate.rs), for the
// errors the generation functions of this package raise: what `tree-sitter
// generate --json-summary` prints as `error`. Every error type derives
// `Serialize` upstream, so enums are externally tagged (a unit variant is its
// name, any other variant `{"Variant": payload}`), structs are objects with
// their fields in declaration order, and newtype structs are their field.
//
// The port raises each preparation pass's own error type instead of
// upstream's `PrepareGrammarError` wrapper; the wrapper's variant is restored
// here from the type.

///|
/// The `GenerateError` serialization of `e`, if `e` is an error of this
/// package's generation functions (`ParseGrammar`, `Prepare`, `VariableInfo`,
/// `BuildTables`, `Render` or `SuperTypeCycle`); `None` otherwise.
pub fn generate_error_json(e : Error) -> Json? {
  match e {
    ParseGrammarError::Serialization(message) =>
      Some(
        variant("ParseGrammar", variant("Serialization", Json::string(message))),
      )
    ParseGrammarError::InvalidExtra =>
      Some(variant("ParseGrammar", "InvalidExtra"))
    ParseGrammarError::Unexpected => Some(variant("ParseGrammar", "Unexpected"))
    ParseGrammarError::InvalidReservedWordSet =>
      Some(variant("ParseGrammar", "InvalidReservedWordSet"))
    ParseGrammarError::UnexpectedRule(name) =>
      Some(
        variant("ParseGrammar", variant("UnexpectedRule", Json::string(name))),
      )
    ValidatePrecedenceError::UndeclaredPrecedenceError(precedence~, rule~) =>
      Some(
        prepare(
          "ValidatePrecedences",
          variant("Undeclared", {
            "precedence": Json::string(precedence),
            "rule": Json::string(rule),
          }),
        ),
      )
    ValidatePrecedenceError::ConflictingPrecedenceOrderingError(
      precedence_1~,
      precedence_2~
    ) =>
      Some(
        prepare(
          "ValidatePrecedences",
          variant("Ordering", {
            "precedence_1": Json::string(precedence_1),
            "precedence_2": Json::string(precedence_2),
          }),
        ),
      )
    IndirectRecursionError(symbols) =>
      Some(prepare("ValidateIndirectRecursion", strings(symbols)))
    ExpandRepeatsError(name) =>
      Some(prepare("ExpandRepeats", Json::string(name)))
    InternSymbolsError::HiddenStartRule =>
      Some(prepare("InternSymbols", "HiddenStartRule"))
    InternSymbolsError::Undefined(name) =>
      Some(prepare("InternSymbols", variant("Undefined", Json::string(name))))
    InternSymbolsError::UndefinedSupertype(name) =>
      Some(
        prepare(
          "InternSymbols",
          variant("UndefinedSupertype", Json::string(name)),
        ),
      )
    InternSymbolsError::UndefinedConflict(name) =>
      Some(
        prepare(
          "InternSymbols",
          variant("UndefinedConflict", Json::string(name)),
        ),
      )
    InternSymbolsError::UndefinedWordToken(name) =>
      Some(
        prepare(
          "InternSymbols",
          variant("UndefinedWordToken", Json::string(name)),
        ),
      )
    ExtractTokensError::EmptyString(name) =>
      Some(prepare("ExtractTokens", variant("EmptyString", Json::string(name))))
    ExtractTokensError::SupertypeTerminal(name) =>
      Some(
        prepare(
          "ExtractTokens",
          variant("SupertypeTerminal", Json::string(name)),
        ),
      )
    ExtractTokensError::ExternalTokenNonTerminal(name) =>
      Some(
        prepare(
          "ExtractTokens",
          variant("ExternalTokenNonTerminal", Json::string(name)),
        ),
      )
    ExtractTokensError::NonSymbolExternalToken =>
      Some(prepare("ExtractTokens", "NonSymbolExternalToken"))
    ExtractTokensError::WordToken(error) =>
      Some(
        prepare(
          "ExtractTokens",
          variant("WordToken", {
            "symbol_name": Json::string(error.symbol_name),
            "conflicting_symbol_name": optional(error.conflicting_symbol_name),
          }),
        ),
      )
    ExtractTokensError::NonTokenReservedWord(name) =>
      Some(
        prepare(
          "ExtractTokens",
          variant("NonTokenReservedWord", Json::string(name)),
        ),
      )
    FlattenGrammarError::NoReservedWordSet(name) =>
      Some(
        prepare(
          "FlattenGrammar",
          variant("NoReservedWordSet", Json::string(name)),
        ),
      )
    FlattenGrammarError::TooManyReservedWordSets(count) =>
      Some(
        prepare(
          "FlattenGrammar",
          variant("TooManyReservedWordSets", Json::number(count.to_double())),
        ),
      )
    FlattenGrammarError::EmptyString(name) =>
      Some(
        prepare("FlattenGrammar", variant("EmptyString", Json::string(name))),
      )
    FlattenGrammarError::RecursiveInline(name) =>
      Some(
        prepare(
          "FlattenGrammar",
          variant("RecursiveInline", Json::string(name)),
        ),
      )
    FlattenGrammarError::NoReachableProductions(name) =>
      Some(
        prepare(
          "FlattenGrammar",
          variant("NoReachableProductions", Json::string(name)),
        ),
      )
    ExpandTokensError::EmptyString(name) =>
      Some(prepare("ExpandTokens", variant("EmptyString", Json::string(name))))
    ExpandTokensError::Processing(error) =>
      Some(
        prepare(
          "ExpandTokens",
          variant("Processing", {
            "rule": Json::string(error.rule),
            "error": expand_rule_error_json(error.error),
          }),
        ),
      )
    ExpandTokensError::ExpandRule(error) =>
      Some(
        prepare(
          "ExpandTokens",
          variant("ExpandRule", expand_rule_error_json(error)),
        ),
      )
    ProcessInlinesError::ExternalToken(name) =>
      Some(
        prepare("ProcessInlines", variant("ExternalToken", Json::string(name))),
      )
    ProcessInlinesError::Token(name) =>
      Some(prepare("ProcessInlines", variant("Token", Json::string(name))))
    ProcessInlinesError::FirstRule(name) =>
      Some(prepare("ProcessInlines", variant("FirstRule", Json::string(name))))
    ProcessInlinesError::NoReachableProductions(name) =>
      Some(
        prepare(
          "ProcessInlines",
          variant("NoReachableProductions", Json::string(name)),
        ),
      )
    EmptyStringExtraError(name) =>
      Some(prepare("ValidateExtras", Json::string(name)))
    VariableInfoError::InvalidSupertype(error) =>
      Some(
        variant(
          "VariableInfo",
          variant("InvalidSupertype", {
            "supertype": Json::string(error.supertype),
            "child": optional(error.child),
          }),
        ),
      )
    VariableInfoError::SupertypeAliasCollision(name) =>
      Some(
        variant(
          "VariableInfo",
          variant("SupertypeAliasCollision", Json::string(name)),
        ),
      )
    ParseTableBuilderError::Conflict(error) =>
      Some(
        variant("BuildTables", variant("Conflict", conflict_error_json(error))),
      )
    ParseTableBuilderError::AmbiguousExtra(error) =>
      Some(
        variant(
          "BuildTables",
          variant("AmbiguousExtra", {
            "parent_symbols": strings(error.parent_symbols),
          }),
        ),
      )
    ParseTableBuilderError::ImproperNonTerminalExtra(name) =>
      Some(
        variant(
          "BuildTables",
          variant("ImproperNonTerminalExtra", Json::string(name)),
        ),
      )
    ParseTableBuilderError::StateCount(count) =>
      Some(
        variant(
          "BuildTables",
          variant("StateCount", Json::number(count.to_double())),
        ),
      )
    RenderError::ParseTable(count) =>
      Some(
        variant(
          "Render",
          variant("ParseTable", Json::number(count.to_double())),
        ),
      )
    RenderError::ABI(version) =>
      Some(variant("Render", variant("ABI", Json::number(version.to_double()))))
    SuperTypeCycleError(items~) =>
      Some(variant("SuperTypeCycle", { "items": strings(items) }))
    _ => None
  }
}

///|
/// `{"name": Json::string(payload)}`: a variant with data.
fn variant(name : String, payload : Json) -> Json {
  Json::object(Map::from_array([(name, payload)]))
}

///|
fn prepare(name : String, payload : Json) -> Json {
  variant("Prepare", variant(name, payload))
}

///|
fn strings(items : Array[String]) -> Json {
  Json::array(items.map(Json::string))
}

///|
fn optional(value : String?) -> Json {
  match value {
    Some(s) => Json::string(s)
    None => Json::null()
  }
}

///|
fn expand_rule_error_json(error : ExpandRuleError) -> Json {
  match error {
    UnexpectedSymbol(symbol) =>
      variant("UnexpectedSymbol", {
        "kind": symbol_type_debug(symbol.kind),
        "index": Json::number(symbol.index.to_double()),
      })
    UnexpectedReserved(name) =>
      variant("UnexpectedReserved", Json::string(name))
    UnexpectedEof => "UnexpectedEof"
    Parse(RegexError(pattern~, kind~, span~, aux_span~)) =>
      variant("Parse", {
        "pattern": Json::string(pattern),
        "kind": regex_error_kind_json(kind),
        "span": pattern_span_json(span),
        "aux_span": pattern_span_json(aux_span),
      })
    ExpandRegex(Utf8(message)) =>
      variant("ExpandRegex", variant("Utf8", Json::string(message)))
    ExpandRegex(Assertion) => variant("ExpandRegex", "Assertion")
    ExpandRegex(NonAsciiByteClass(error)) =>
      variant(
        "ExpandRegex",
        variant("NonAsciiByteClass", {
          "start": Json::number(error.start.to_int().to_double()),
          "end": Json::number(error.end.to_int().to_double()),
        }),
      )
  }
}

///|
fn pattern_span_json(span : PatternSpan?) -> Json {
  match span {
    Some(span) =>
      {
        "start": Json::number(span.start.to_double()),
        "end": Json::number(span.end.to_double()),
      }
    None => Json::null()
  }
}

///|
fn regex_error_kind_json(kind : RegexErrorKind) -> Json {
  match kind {
    NestLimitExceeded(limit) =>
      variant("NestLimitExceeded", Json::number(limit.to_double()))
    Other(message) => variant("Other", Json::string(message))
    kind => Json::string(regex_error_kind_name(kind))
  }
}

///|
/// The variant name of a unit `RegexErrorKind`.
fn regex_error_kind_name(kind : RegexErrorKind) -> String {
  match kind {
    CaptureLimitExceeded => "CaptureLimitExceeded"
    ClassEscapeInvalid => "ClassEscapeInvalid"
    ClassRangeInvalid => "ClassRangeInvalid"
    ClassRangeLiteral => "ClassRangeLiteral"
    ClassUnclosed => "ClassUnclosed"
    DecimalEmpty => "DecimalEmpty"
    DecimalInvalid => "DecimalInvalid"
    EscapeHexEmpty => "EscapeHexEmpty"
    EscapeHexInvalid => "EscapeHexInvalid"
    EscapeHexInvalidDigit => "EscapeHexInvalidDigit"
    EscapeUnexpectedEof => "EscapeUnexpectedEof"
    EscapeUnrecognized => "EscapeUnrecognized"
    FlagDanglingNegation => "FlagDanglingNegation"
    FlagUnexpectedEof => "FlagUnexpectedEof"
    FlagUnrecognized => "FlagUnrecognized"
    GroupNameEmpty => "GroupNameEmpty"
    GroupNameInvalid => "GroupNameInvalid"
    GroupNameUnexpectedEof => "GroupNameUnexpectedEof"
    GroupUnclosed => "GroupUnclosed"
    GroupUnopened => "GroupUnopened"
    RepetitionCountInvalid => "RepetitionCountInvalid"
    RepetitionCountDecimalEmpty => "RepetitionCountDecimalEmpty"
    RepetitionCountUnclosed => "RepetitionCountUnclosed"
    RepetitionMissing => "RepetitionMissing"
    SpecialWordBoundaryUnclosed => "SpecialWordBoundaryUnclosed"
    SpecialWordBoundaryUnrecognized => "SpecialWordBoundaryUnrecognized"
    SpecialWordOrRepetitionUnexpectedEof =>
      "SpecialWordOrRepetitionUnexpectedEof"
    UnicodeClassInvalid => "UnicodeClassInvalid"
    UnsupportedBackreference => "UnsupportedBackreference"
    UnsupportedLookAround => "UnsupportedLookAround"
    UnicodeNotAllowed => "UnicodeNotAllowed"
    InvalidUtf8 => "InvalidUtf8"
    InvalidLineTerminator => "InvalidLineTerminator"
    UnicodePropertyNotFound => "UnicodePropertyNotFound"
    UnicodePropertyValueNotFound => "UnicodePropertyValueNotFound"
    UnicodePerlClassNotFound => "UnicodePerlClassNotFound"
    UnicodeCaseUnavailable => "UnicodeCaseUnavailable"
    FlagDuplicate => "FlagDuplicate"
    FlagRepeatedNegation => "FlagRepeatedNegation"
    GroupNameDuplicate => "GroupNameDuplicate"
    NestLimitExceeded(_) => "NestLimitExceeded"
    Other(_) => "Other"
  }
}

///|
fn conflict_error_json(error : ConflictError) -> Json {
  {
    "symbol_sequence": strings(error.symbol_sequence),
    "conflicting_lookahead": Json::string(error.conflicting_lookahead),
    "possible_interpretations": Json::array(
      error.possible_interpretations.map(i => {
        "preceding_symbols": strings(i.preceding_symbols),
        "variable_name": Json::string(i.variable_name),
        "production_step_symbols": strings(i.production_step_symbols),
        "step_index": Json::number(i.step_index.to_double()),
        "done": Json::boolean(i.done),
        "conflicting_lookahead": Json::string(i.conflicting_lookahead),
        "precedence": optional(i.precedence),
        "associativity": optional(i.associativity),
        "requires_eof_lookahead": Json::boolean(i.requires_eof_lookahead),
      }),
    ),
    "possible_resolutions": Json::array(
      error.possible_resolutions.map(r => {
        match r {
          Precedence(symbols~) =>
            variant("Precedence", { "symbols": strings(symbols) })
          Associativity(symbols~) =>
            variant("Associativity", { "symbols": strings(symbols) })
          AddConflict(symbols~) =>
            variant("AddConflict", { "symbols": strings(symbols) })
        }
      }),
    ),
  }
}
