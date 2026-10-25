// Port of the php grammar's php_only/src/scanner.c (v0.24.2). The scanning
// logic is in php_common.mbt (common/scanner.h).

///|
fn php_only_scanner() -> @runtime.ExternalScanner {
  php_external_scanner()
}
