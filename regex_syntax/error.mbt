// Port of the `Error` type of regex-syntax 0.8.11 src/error.rs.
//
// The pretty `Formatter` of upstream is not ported: tree-sitter formats
// regex errors itself (see `generate/pattern.mbt`).

///|
/// This error type encompasses any error that can be returned by this crate.
pub(all) suberror SyntaxError {
  /// An error that occurred while translating concrete syntax into abstract
  /// syntax (AST).
  Parse(@ast.AstError)
  /// An error that occurred while translating abstract syntax into a high
  /// level intermediate representation (HIR).
  Translate(@hir.HirError)
} derive(Eq, Debug)

///|
/// Upstream `From<ast::Error> for Error`.
pub fn SyntaxError::from_ast(err : @ast.AstError) -> SyntaxError {
  Parse(err)
}

///|
/// Upstream `From<hir::Error> for Error`.
pub fn SyntaxError::from_hir(err : @hir.HirError) -> SyntaxError {
  Translate(err)
}
