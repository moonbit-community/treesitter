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
}

///|
pub let empty_str_id : StrId = StrId(1)

///|
pub let end_name_id : StrId = StrId(2)

///|
pub fn StrPool::new() -> StrPool {
  let pool = { strings: [], ids: {} }
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
