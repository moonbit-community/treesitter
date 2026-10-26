///|
/// A hash map from non-negative `Int64` keys to `Int32` values, for hot memo tables:
/// open addressing over flat arrays, so lookups don't chase entries and the map
/// has no per-entry objects to allocate or free. (Not iterable: memo tables are only
/// looked up.)
priv struct Int64Map {
  /// The key in each slot, or `-1` for an empty slot.
  mut keys : FixedArray[Int64]
  mut values : FixedArray[Int32]
  mut len : Int32
}

///|
fn Int64Map::new() -> Int64Map {
  { keys: FixedArray::make(16, -1L), values: FixedArray::make(16, 0), len: 0 }
}

///|
/// The first slot to probe for `key`, in a table of `capacity` (a power of two) slots.
fn int64_map_slot(key : Int64, capacity : Int32) -> Int32 {
  let h = key.reinterpret_as_uint64() * 0x9E3779B97F4A7C15UL
  (h >> 32).to_int() & (capacity - 1)
}

///|
/// The value of `key`, or `-1` if it has none.
fn Int64Map::get(self : Int64Map, key : Int64) -> Int32 {
  let keys = self.keys
  let mask = keys.length() - 1
  let mut slot = int64_map_slot(key, keys.length())
  while true {
    let k = keys[slot]
    if k == key {
      return self.values[slot]
    }
    if k == -1L {
      return -1
    }
    slot = (slot + 1) & mask
  }
  -1
}

///|
/// Sets the value of `key`, which must not have one yet.
fn Int64Map::insert_new(self : Int64Map, key : Int64, value : Int32) -> Unit {
  // Keep the load factor at most 1/2.
  if (self.len + 1) * 2 > self.keys.length() {
    self.grow()
  }
  self.place(key, value)
  self.len += 1
}

///|
fn Int64Map::place(self : Int64Map, key : Int64, value : Int32) -> Unit {
  let keys = self.keys
  let mask = keys.length() - 1
  let mut slot = int64_map_slot(key, keys.length())
  while keys[slot] != -1L {
    slot = (slot + 1) & mask
  }
  keys[slot] = key
  self.values[slot] = value
}

///|
fn Int64Map::grow(self : Int64Map) -> Unit {
  let old_keys = self.keys
  let old_values = self.values
  let capacity = old_keys.length() * 2
  self.keys = FixedArray::make(capacity, -1L)
  self.values = FixedArray::make(capacity, 0)
  for i in 0..<old_keys.length() {
    if old_keys[i] != -1L {
      self.place(old_keys[i], old_values[i])
    }
  }
}
