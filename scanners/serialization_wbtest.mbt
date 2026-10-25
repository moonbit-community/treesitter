// Tests of the C integer arithmetic of the scanners' serialization guards:
// lengths near 2^31 would need gigabytes of heredoc text, so the guards are
// tested directly.

///|
test "php heredoc guard uses unsigned arithmetic" {
  // `word_size` wraps modulo 2^32.
  inspect(php_word_size(536870912), content="2147483648")
  inspect(php_word_size(1073741824), content="0")
  inspect(php_heredoc_overflows(1, php_word_size(536870912)), content="true")
  // A wrapped word size of 0 passes the guard (and nothing is copied).
  inspect(php_heredoc_overflows(1, php_word_size(1073741824)), content="false")
  inspect(php_heredoc_overflows(1, php_word_size(254)), content="false")
  inspect(php_heredoc_overflows(1, php_word_size(255)), content="true")
}

///|
test "bash heredoc guard uses size_t arithmetic" {
  inspect(bash_heredoc_overflows(4, 2147483637), content="true")
  inspect(bash_heredoc_overflows(4, 1012), content="false")
  inspect(bash_heredoc_overflows(4, 1013), content="true")
}

///|
test "ruby guards use unsigned arithmetic" {
  inspect(ruby_heredoc_overflows(2, 2147483644), content="true")
  inspect(ruby_heredoc_overflows(2, 1019), content="false")
  inspect(ruby_heredoc_overflows(2, 1020), content="true")
  inspect(ruby_literals_overflow(204), content="false")
  inspect(ruby_literals_overflow(205), content="true")
  // 858993460 * 5 wraps to 4.
  inspect(ruby_literals_overflow(858993460), content="false")
}

///|
test "panic ruby deserialize assertion" {
  // One heredoc with an empty word, followed by a stray byte: the C scanner
  // fails `assert(size == length)`.
  let scanner : RubyScanner = {
    has_leading_whitespace: false,
    literal_stack: [],
    open_heredocs: [],
  }
  scanner.deserialize(b"\x00\x01\x00\x00\x00\x00x")
}
