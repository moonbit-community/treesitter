///|
test "Stats keeps usize counters and u128 throughput" {
  let stats = Stats::default()
  inspect(
    stats,
    content="Total parses: 0; successful parses: 0; failed parses: 0; success percentage: N/A; average speed: N/A\n",
  )
  stats.total_parses = 32
  stats.successful_parses = 1
  stats.total_bytes = 3000000000
  stats.total_duration = 2500000000
  inspect(
    stats,
    content="Total parses: 32; successful parses: 1; failed parses: 31; success percentage: 3.12%; average speed: 1200000 bytes/ms\n",
  )
  stats.total_bytes = 18446744073709551615
  stats.total_duration = 7000
  inspect(
    stats,
    content="Total parses: 32; successful parses: 1; failed parses: 31; success percentage: 3.12%; average speed: 2635249153387078802142 bytes/ms\n",
  )
  stats.total_duration = 1999
  inspect(
    stats,
    content="Total parses: 32; successful parses: 1; failed parses: 31; success percentage: 3.12%; average speed: 18446744073709551615000 bytes/ms\n",
  )
  stats.total_duration = 999
  inspect(
    stats,
    content="Total parses: 32; successful parses: 1; failed parses: 31; success percentage: 3.12%; average speed: 0 bytes/ms\n",
  )
  inspect(
    @support.to_string(stats.to_json()),
    content=(
      #|{"successful_parses":1,"total_parses":32,"total_bytes":18446744073709551615,"total_duration":{"secs":0,"nanos":999}}
    ),
  )
}
