///|
/// A stateless scalar decoder for an application's input encoding. The callback
/// receives the remaining nonempty input and returns (Unicode scalar, byte count).
/// It must give the same answer on repeated calls: decoding is also used for
/// node text, points, scanner columns, and incremental validation.
pub struct InputDecoder {
  priv decode : (BytesView) -> (Int32, Int32)
}

///|
/// Invalid scalars become U+FFFD. Invalid lengths consume one byte as U+FFFD,
/// guaranteeing progress even on malformed or truncated encoded input.
pub fn InputDecoder::new(
  decode : (BytesView) -> (Int32, Int32),
) -> InputDecoder {
  { decode, }
}

///|
/// Decoder identity defines encoding compatibility for incremental reuse.
pub impl Eq for InputDecoder with fn equal(left, right) {
  physical_equal(left, right)
}

///|
pub impl Debug for InputDecoder with fn to_repr(_) {
  Repr("InputDecoder")
}

///|
pub extend InputDecoder with Eq::{equal, not_equal}

///|
pub extend InputDecoder with Debug::{to_repr}
