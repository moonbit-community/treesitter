///|
pub extend Symbol with Eq::{equal, not_equal}

///|
pub extend Symbol with @debug.Debug::{to_repr}

///|
pub extend Token with Eq::{equal, not_equal}

///|
pub extend Token with @debug.Debug::{to_repr}

///|
pub extend Step with Eq::{equal, not_equal}

///|
pub extend Step with @debug.Debug::{to_repr}

///|
pub extend Production with Eq::{equal, not_equal}

///|
pub extend Production with @debug.Debug::{to_repr}

///|
pub extend Action with Eq::{equal, not_equal}

///|
pub extend Action with @debug.Debug::{to_repr}

///|
pub extend ParseState with Eq::{equal, not_equal}

///|
pub extend ParseState with @debug.Debug::{to_repr}

///|
pub extend Language with Eq::{equal, not_equal}

///|
pub extend Language with @debug.Debug::{to_repr}

///|
pub extend LanguageError with @debug.Debug::{to_repr}

///|
#deprecated
pub extend Symbol with ToJson::{to_json}

///|
#deprecated
pub extend Symbol with @json.FromJson::{from_json}

///|
#deprecated
pub extend Token with ToJson::{to_json}

///|
#deprecated
pub extend Token with @json.FromJson::{from_json}

///|
#deprecated
pub extend Step with ToJson::{to_json}

///|
#deprecated
pub extend Step with @json.FromJson::{from_json}

///|
#deprecated
pub extend Production with ToJson::{to_json}

///|
#deprecated
pub extend Production with @json.FromJson::{from_json}

///|
#deprecated
pub extend Action with ToJson::{to_json}

///|
#deprecated
pub extend Action with @json.FromJson::{from_json}
