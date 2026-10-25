// Tests of random.rs and edits.rs: the values that `Rand` and
// `get_random_edit` draw must be those of upstream (rand 0.10.3 `StdRng`).

///|
/// The sequence of calls the verifier program made (see the test below).
fn rand_sample_sequence(seed : UInt64) -> (String, String, String) raise {
  let r = @cli_test.Rand::new(seed)
  let maxes : Array[UInt64] = [
    0,
    1,
    3,
    5,
    8,
    10,
    30,
    0xFFFF_FFFF,
    0x1_0000_0000,
    0x1_0000_0005,
    1UL << 63,
    0xFFFF_FFFF_FFFF_FFFE,
    0xFFFF_FFFF_FFFF_FFFF,
  ]
  let unsigned = []
  for _ in 0..<3 {
    for max in maxes {
      unsigned.push(r.unsigned(max).to_string())
    }
  }
  let words = []
  for _ in 0..<4 {
    words.push(
      @utf8.decode(Bytes::from_array(r.words(8))).replace_all(old="\n", new="~"),
    )
  }
  let input = @utf8.encode("fn main() {\n  let x = 1;\n}\n").to_array()
  let edits = []
  for _ in 0..<12 {
    let edit = @cli_test.get_random_edit(r, input)
    let text = @utf8.decode(Bytes::from_array(edit.inserted_text)).replace_all(
      old="\n",
      new="~",
    )
    edits.push("\{edit.position}:\{edit.deleted_length}:\{text}")
    // `input.splice(position..position + deleted_length, inserted_text)`
    let tail = input[edit.position + edit.deleted_length:].to_owned()
    input.truncate(edit.position)
    input.append(edit.inserted_text)
    input.append(tail)
  }
  (unsigned.join(","), words.join("|"), edits.join("|"))
}

///|
/// Expected values printed by this program (upstream's `fuzz/random.rs`
/// and `get_random_edit` of `fuzz/edits.rs`, copied verbatim, with this
/// `main`), built against rand 0.10.3 with `cargo +1.97.1 build --offline`:
///
/// ```rust
/// fn main() {
///     let seeds: [usize; 5] = [0, 1, 42, usize::MAX, (1usize << 40) + 3];
///     let maxes: [usize; 13] = [0, 1, 3, 5, 8, 10, 30, (1 << 32) - 1, 1 << 32,
///         (1 << 32) + 5, 1 << 63, usize::MAX - 1, usize::MAX];
///     for seed in seeds {
///         let mut r = Rand::new(seed);
///         let mut out: Vec<String> = Vec::new();
///         for _ in 0..3 {
///             for m in maxes { out.push(format!("{}", r.unsigned(m))); }
///         }
///         println!("{}", out.join(","));
///         let mut out: Vec<String> = Vec::new();
///         for _ in 0..4 {
///             out.push(String::from_utf8(r.words(8)).unwrap().replace('\n', "~"));
///         }
///         println!("{}", out.join("|"));
///         let mut input = b"fn main() {\n  let x = 1;\n}\n".to_vec();
///         let mut out: Vec<String> = Vec::new();
///         for _ in 0..12 {
///             let e = get_random_edit(&mut r, &input);
///             out.push(format!("{}:{}:{}", e.position, e.deleted_length,
///                 String::from_utf8(e.inserted_text.clone()).unwrap().replace('\n', "~")));
///             input.splice(e.position..e.position + e.deleted_length, e.inserted_text);
///         }
///         println!("{}", out.join("|"));
///     }
/// }
/// ```
test "Rand and get_random_edit match upstream" {
  let seeds : Array[UInt64] = [0, 1, 42, 0xFFFF_FFFF_FFFF_FFFF, (1UL << 40) + 3]
  let expected = [
    (
      [
        "0,1,2,4,7,0,20,2508944925,1126014293,3315658517,2017122970434124938,13822854226189844396,18378811288308973438",
        "0,0,0,0,8,10,6,212171618,1828376452,1978174566,8524818344127779221,10317859705648061692,15412246435463340132",
        "0,0,0,3,7,7,23,2056642569,3762722536,3739457922,583207443122684075,18204917730788549396,18023453960276049415",
      ].join(","),
      "rYA ,|qyUq3~ wQ3KFPW . aQZQeqGr|Szo6C6~< lDL3Nu njM |< CC cK  0W1z",
      "26:1:(|24:0:/ vxC V|22:0:|34:0:US|11:24:|9:0:|3:5:|0:7:|0:0:|0:0:ULjQlWRS mLMe|3:0:) By|11:0:c7NQY",
    ),
    (
      [
        "0,1,3,4,1,4,6,754136343,1093291491,4134347463,3584274678365186038,13069671960883416006,7111212021632567530",
        "0,0,1,0,7,10,24,1858639106,834459173,610328118,8229917091383032677,7203786980853150884,792718116624849113",
        "0,1,1,1,2,10,19,2524165064,2717204072,534048476,2421434182115459125,3506992076740808482,6481455407914116990",
      ].join(","),
      " % DZ F < RNsyMm1 ) emOD9sf|||083AI hqKD6KOi",
      "21:2:,|24:2:|10:14:|7:3:|1:0:wo91T9Q|1:13:|0:0:|0:1:|0:0:wf qcky|7:0:|3:0:NHyCJc J ! nUqsZYKZ|16:0:2L6db",
    ),
    (
      [
        "0,1,0,3,7,7,30,1743334776,147501280,1782226086,6801539845966806142,15665927001465599798,59990589126097438",
        "0,1,2,3,7,4,22,605074967,2246435969,939333357,116149927234738149,9578448464351515634,11924907057293251871",
        "0,1,1,2,8,5,12,251233087,1507580003,1922253345,7326907280323496043,3754557543903678404,12075250104723286995",
      ].join(","),
      "4 3pp ( mEG % cPB4JQY~9f28i8x|k2PYZ4O9 Te798 JioH PSk2rS~9ny3 f 7|> jUeVSY rYkmFLZ 7QFJ2Okq LUfKPy UvJ8S57 RqIh1|| ) 4NJ ew M5BH ",
      "27:0:lI8l4WMF |16:20:|0:16:|0:0:*|1:0:|0:0:|1:0:spUJHIKH|6:1:|0:8:|0:0:|0:0:|0:0:",
    ),
    (
      [
        "0,0,1,0,3,0,9,1560817553,823411923,2399843210,7586870011694559821,2657624914398962950,2655924558283175357",
        "0,1,1,3,0,10,11,3506812296,2486588894,1715169501,6713592342028441175,10980779039912926299,14549025170214726100",
        "0,1,1,4,1,4,23,3402314265,3231173495,2136876680,605009985204043701,3954033498596936978,12734275721224733959",
      ].join(","),
      "Y3fU ZaT 63a4Ou~% 0yFtE~laFYG TeAwTj|<  R If~GiJdK0 OydRmc w2SATCL||+ pffiEv 6ARO % QOvYLdLc",
      "25:2:|3:0:|13:8:~) nJAOnxDg blaQxwG|33:1:b ved|14:0:|18:22:|0:18:|0:0:%|1:0:iL2 -|0:6:|0:0:|0:0:",
    ),
    (
      [
        "0,0,0,3,2,7,4,200795822,1814555092,3267573561,480717745624427801,11874562332717352069,9143502592219070163",
        "0,1,2,5,2,9,14,2689954952,958436819,370367737,5335925680353765137,1084384928112810738,13768291720078058554",
        "0,0,1,3,2,0,4,2076972182,633742986,4257619229,8930105904760206488,3639916977791378903,9938913602213691127",
      ].join(","),
      "N9KJ U8w~Dn j6qHh tA67lKAV ~>|x9cp~|~> 6wVmL4Fu dv76Hl > )| + rB76 VXQxN oVczs ( ) &|<~ MLkOa28 IDPzX6p",
      "2:0:3Vmt|21:0:il~. GOly|35:0:stqc|20:8:j lGfvpJX|21:0:> 2|48:0:*|2:27:. |11:11:7uAmeL  Wt4SnSK lwyoD1z|20:16:|13:0:/|13:8:|4:8:",
    ),
  ]
  for i, seed in seeds {
    assert_eq(rand_sample_sequence(seed), expected[i])
  }
}
