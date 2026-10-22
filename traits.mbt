///|
pub extend Point with Eq::{equal, not_equal}

///|
pub extend Point with @debug.Debug::{to_repr}

///|
#deprecated
pub extend Point with ToJson::{to_json}

///|
pub extend Range with Eq::{equal, not_equal}

///|
pub extend Range with @debug.Debug::{to_repr}

///|
#deprecated
pub extend Range with ToJson::{to_json}

///|
pub extend Point with Compare::{compare, op_lt, op_le, op_gt, op_ge}
