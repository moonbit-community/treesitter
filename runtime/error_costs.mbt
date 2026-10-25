// Port of tree-sitter lib/src/error_costs.h.

///|
pub let error_state : Int32 = 0

///|
pub let error_cost_per_recovery : UInt32 = 500

///|
pub let error_cost_per_missing_tree : UInt32 = 110

///|
pub let error_cost_per_skipped_tree : UInt32 = 100

///|
pub let error_cost_per_skipped_line : UInt32 = 30

///|
pub let error_cost_per_skipped_char : UInt32 = 1
