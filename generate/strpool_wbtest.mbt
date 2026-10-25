///|
test "StrPool tracks its UTF-8 size" {
  let pool = StrPool::new()
  inspect(pool.buf_len, content="3")
  ignore(pool.intern("é😀"))
  inspect(pool.buf_len, content="9")
  // Interning a string again does not grow the buffer.
  ignore(pool.intern("é😀"))
  inspect(pool.buf_len, content="9")
  // Up to `u32::MAX` bytes are accepted.
  pool.buf_len = 0xFFFFFFFEL
  ignore(pool.intern("a"))
  inspect(pool.buf_len, content="4294967295")
}

///|
test "panic StrPool rejects more than u32::MAX bytes" {
  let pool = StrPool::new()
  pool.buf_len = 0xFFFFFFFEL
  ignore(pool.intern("ab"))
}
