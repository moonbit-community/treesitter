///|
pub extend Grammar with Eq::{equal, not_equal}

///|
pub extend Grammar with @debug.Debug::{to_repr}

///|
pub extend GrammarError with Eq::{equal, not_equal}

///|
pub extend GrammarError with @debug.Debug::{to_repr}

///|
pub extend Rule with Eq::{equal, not_equal}

///|
pub extend Rule with @debug.Debug::{to_repr}

///|
pub extend Precedence with Eq::{equal, not_equal}

///|
pub extend Precedence with @debug.Debug::{to_repr}

///|
#deprecated
pub extend Rule with ToJson::{to_json}

///|
#deprecated
pub extend Grammar with ToJson::{to_json}
