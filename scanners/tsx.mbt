// Port of the typescript grammar's tsx/src/scanner.c (v0.23.2). The scanning
// logic is in typescript_common.mbt (common/scanner.h).

///|
/// `tree_sitter_tsx_external_scanner_create` returns NULL; the scanner is
/// stateless and serializes nothing.
fn tsx_scanner() -> @runtime.ExternalScanner {
  {
    scan: typescript_external_scanner_scan,
    serialize: _ => 0,
    deserialize: _ => (),
    destroy: () => (),
  }
}
