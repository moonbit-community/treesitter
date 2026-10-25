// The external scanner interface: the `external_scanner` callbacks of
// `TSLanguage`. A scanner object plays the role of the C payload; it is
// created per parse by an `ExternalScannerFactory`.

///|
pub(all) struct ExternalScanner {
  /// `scan(payload, lexer, valid_symbols)`.
  scan : (Lexer, ArrayView[Bool]) -> Bool
  /// `serialize(payload, buffer)`: write the state into the 1024-byte buffer
  /// and return the number of bytes written.
  serialize : (FixedArray[Byte]) -> Int32
  /// `deserialize(payload, buffer, length)`.
  deserialize : (BytesView) -> Unit
  /// `destroy(payload)`.
  destroy : () -> Unit
}

///|
/// `create()`.
pub type ExternalScannerFactory = () -> ExternalScanner
