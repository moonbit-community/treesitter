// Port of the ocaml grammar's grammars/ocaml/src/scanner.c (v0.26.0). The
// scanning logic is in ocaml_common.mbt (common/scanner.h).

///|
fn ocaml_scanner() -> @runtime.ExternalScanner {
  ocaml_external_scanner()
}
