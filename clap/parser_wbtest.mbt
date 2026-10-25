///|
/// Expected values: Rust 1.97.1 `str::parse::<i64>()` and `::<u64>()` with
/// the errors' `Display` texts.
test "parse_i64 and parse_u64 follow Rust's from_str" {
  let lines = []
  for
    s in [
      "", "+", "-", "-0", "+0", "--1", "-+1", "+-1", "0012", "-0012", "9223372036854775807",
      "9223372036854775808", "-9223372036854775808", "-9223372036854775809", "1x",
      "99999999999999999999x", "-99999999999999999999x", "x99999999999999999999",
      "\u{663}", "18446744073709551615", "18446744073709551616",
    ] {
    lines.push(
      "\{Repr(s)}: i64=\{Repr(parse_i64(s))} u64=\{Repr(parse_u64(s))}",
    )
  }
  inspect(
    lines.join("\n"),
    content=(
      #|"": i64=Err("cannot parse integer from empty string") u64=Err("cannot parse integer from empty string")
      #|"+": i64=Err("invalid digit found in string") u64=Err("invalid digit found in string")
      #|"-": i64=Err("invalid digit found in string") u64=Err("invalid digit found in string")
      #|"-0": i64=Ok(0) u64=Err("invalid digit found in string")
      #|"+0": i64=Ok(0) u64=Ok(0)
      #|"--1": i64=Err("invalid digit found in string") u64=Err("invalid digit found in string")
      #|"-+1": i64=Err("invalid digit found in string") u64=Err("invalid digit found in string")
      #|"+-1": i64=Err("invalid digit found in string") u64=Err("invalid digit found in string")
      #|"0012": i64=Ok(12) u64=Ok(12)
      #|"-0012": i64=Ok(-12) u64=Err("invalid digit found in string")
      #|"9223372036854775807": i64=Ok(9223372036854775807) u64=Ok(9223372036854775807)
      #|"9223372036854775808": i64=Err("number too large to fit in target type") u64=Ok(9223372036854775808)
      #|"-9223372036854775808": i64=Ok(-9223372036854775808) u64=Err("invalid digit found in string")
      #|"-9223372036854775809": i64=Err("number too small to fit in target type") u64=Err("invalid digit found in string")
      #|"1x": i64=Err("invalid digit found in string") u64=Err("invalid digit found in string")
      #|"99999999999999999999x": i64=Err("number too large to fit in target type") u64=Err("number too large to fit in target type")
      #|"-99999999999999999999x": i64=Err("number too small to fit in target type") u64=Err("invalid digit found in string")
      #|"x99999999999999999999": i64=Err("invalid digit found in string") u64=Err("invalid digit found in string")
      #|"٣": i64=Err("invalid digit found in string") u64=Err("invalid digit found in string")
      #|"18446744073709551615": i64=Err("number too large to fit in target type") u64=Ok(18446744073709551615)
      #|"18446744073709551616": i64=Err("number too large to fit in target type") u64=Err("number too large to fit in target type")
    ),
  )
}
