///|
/// An open-addressing hash index of ids, for keys that are stored elsewhere by id: a
/// lookup probes the slots of a hash, and the caller compares its key with the
/// stored key of each id found. Flat arrays, so it has no per-entry objects.
priv struct HashIndex {
  /// The id in each slot, or `-1` for an empty slot.
  mut ids : FixedArray[Int32]
  /// The hash of each slot's key.
  mut hashes : FixedArray[Int32]
  mut len : Int32
}

///|
fn HashIndex::new() -> HashIndex {
  { ids: FixedArray::make(16, -1), hashes: FixedArray::make(16, 0), len: 0 }
}

///|
/// The first slot to probe for `hash`.
fn HashIndex::first_slot(self : HashIndex, hash : Int32) -> Int32 {
  // `hash_finish` mixes its bits, so the low bits do.
  hash & (self.ids.length() - 1)
}

///|
/// The slot after `slot`.
fn HashIndex::next_slot(self : HashIndex, slot : Int32) -> Int32 {
  (slot + 1) & (self.ids.length() - 1)
}

///|
/// Adds `id`, whose key has hash `hash` and isn't in the index yet.
fn HashIndex::insert_new(self : HashIndex, hash : Int32, id : Int32) -> Unit {
  // Keep the load factor at most 1/2.
  if (self.len + 1) * 2 > self.ids.length() {
    let old_ids = self.ids
    let old_hashes = self.hashes
    self.ids = FixedArray::make(old_ids.length() * 2, -1)
    self.hashes = FixedArray::make(old_ids.length() * 2, 0)
    for i in 0..<old_ids.length() {
      if old_ids[i] >= 0 {
        self.place(old_hashes[i], old_ids[i])
      }
    }
  }
  self.place(hash, id)
  self.len += 1
}

///|
fn HashIndex::place(self : HashIndex, hash : Int32, id : Int32) -> Unit {
  let mut slot = self.first_slot(hash)
  while self.ids[slot] >= 0 {
    slot = self.next_slot(slot)
  }
  self.ids[slot] = id
  self.hashes[slot] = hash
}
