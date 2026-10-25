// Port of tree-sitter crates/generate/src/strpool.rs.

///|
/// Interned string id: a 1-based index into the pool's string table.
pub(all) struct StrId(Int) derive(Eq, Hash, Compare, Debug)

///|
pub fn StrId::index(self : StrId) -> Int {
  self.0 - 1
}

///|
pub fn StrId::raw(self : StrId) -> Int {
  self.0
}

///|
/// An append-only pool of strings. Ids are assigned in intern order, which is
/// observable through `StrId` comparisons and must therefore match upstream.
pub struct StrPool {
  priv strings : Array[String]
  priv ids : Map[String, StrId]
  /// The length of upstream's `buf`: the UTF-8 bytes of all the strings.
  priv mut buf_len : Int64
}

///|
pub let empty_str_id : StrId = StrId(1)

///|
pub let end_name_id : StrId = StrId(2)

///|
pub fn StrPool::new() -> StrPool {
  let pool = { strings: [], ids: {}, buf_len: 0 }
  ignore(pool.intern(""))
  ignore(pool.intern("end"))
  pool
}

///|
pub fn StrPool::intern(self : StrPool, s : StringView) -> StrId {
  let s = s.to_owned()
  match self.ids.get(s) {
    Some(id) => id
    None => {
      // The pool is specialized for use only in the generate crate. A
      // pool that has accumulated more than 4GB of data is not a use
      // case we support.
      let end = self.buf_len + utf8_length(s)
      if end > 0xFFFFFFFFL {
        abort("called `Option::unwrap()` on a `None` value")
      }
      self.buf_len = end
      self.strings.push(s)
      let id = StrId(self.strings.length())
      self.ids[s] = id
      id
    }
  }
}

///|
pub fn StrPool::resolve(self : StrPool, id : StrId) -> String {
  self.strings[id.index()]
}

///|
pub fn StrPool::get(self : StrPool, s : String) -> StrId? {
  self.ids.get(s)
}

///|
/// The number of bytes of `s` in UTF-8.
fn utf8_length(s : String) -> Int64 {
  let mut n = 0L
  for c in s {
    let cp = c.to_int()
    n += if cp < 0x80 {
      1
    } else if cp < 0x800 {
      2
    } else if cp < 0x10000 {
      3
    } else {
      4
    }
  }
  n
}
