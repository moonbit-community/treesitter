///|
/// Return an index into the grammar's `externals` list and the next serialized
/// state. The runtime supplies the previous state independently on every GLR
/// branch; callbacks must not retain mutable state outside this byte snapshot.
pub(all) struct ScanResult {
  token : Int32
  state : Bytes
}

///|
pub struct ExternalScanner {
  priv scan : (ScannerInput, Array[Bool], Bytes) -> ScanResult?
}

///|
pub fn ExternalScanner::new(
  scan : (ScannerInput, Array[Bool], Bytes) -> ScanResult?,
) -> ExternalScanner {
  { scan, }
}

///|
priv struct Projection {
  source : Bytes
  starts : Array[Int32]
  ends : Array[Int32]
  lines : Array[Int32]
}

///|
pub struct ScannerInput {
  priv source : Bytes
  priv mut offset : Int32
  priv mut start : Int32
  priv mut marked_end : Int32?
  priv lines : Array[Int32]
  priv projection : Projection?
  priv cancelled : () -> Bool
}

///|
pub fn ScannerInput::lookahead(self : ScannerInput) -> Int32 {
  if self.eof() {
    0
  } else {
    @lex.decode(self.source, self.offset).0
  }
}

///|
pub fn ScannerInput::eof(self : ScannerInput) -> Bool {
  self.offset == self.source.length()
}

///|
pub fn ScannerInput::advance(self : ScannerInput, skip~ : Bool = false) -> Unit {
  if !self.eof() {
    self.offset += @lex.decode(self.source, self.offset).1
    if skip {
      self.start = self.offset
    }
  }
}

///|
pub fn ScannerInput::mark_end(self : ScannerInput) -> Unit {
  self.marked_end = Some(self.offset)
}

///|
pub fn ScannerInput::is_cancelled(self : ScannerInput) -> Bool {
  (self.cancelled)()
}

///|
pub fn ScannerInput::is_at_included_range_start(self : ScannerInput) -> Bool {
  match self.projection {
    None => self.offset == 0
    Some(p) => self.offset == 0 || p.starts[self.offset] != p.ends[self.offset]
  }
}

///|
/// Like Tree-sitter's scanner API, columns count Unicode scalars, not bytes.
pub fn ScannerInput::get_column(self : ScannerInput) -> Int32 {
  let (source, offset, lines) = match self.projection {
    None => (self.source, self.offset, self.lines)
    Some(p) => (p.source, p.starts[self.offset], p.lines)
  }
  let mut cursor = offset - point_at(lines, offset).column
  let mut column = 0
  while cursor < offset {
    cursor += @lex.decode(source, cursor).1
    column += 1
  }
  column
}

///|
fn same_scanner(a : ExternalScanner?, b : ExternalScanner?) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(a), Some(b)) => physical_equal(a, b)
    _ => false
  }
}
