// Expected results generated with serde_json 1.0.154 (preserve_order).

///|
fn kinds(v : @support.Value) -> String {
  match v {
    Null => "null"
    Bool(b) => b.to_string()
    Number(PosInt(_) as n) => "u\{n}"
    Number(NegInt(_) as n) => "i\{n}"
    Number(Float(_) as n) => "f\{n}"
    String(s) => @support.rust_debug_str(s)
    Array(a) => "[" + a.map(kinds).join(",") + "]"
    Object(o) => {
      let parts = []
      for k, x in o {
        parts.push(@support.rust_debug_str(k) + ":" + kinds(x))
      }
      "{" + parts.join(",") + "}"
    }
  }
}

///|
fn parse_value(doc : String) -> String {
  try "ok " + kinds(@support.from_str(doc)) catch {
    e => "err \{e}"
  }
}

///|
test "from_str::<Value> matches serde_json" {
  let cases : Array[(String, String)] = [
    ("{", "err EOF while parsing an object at line 1 column 1"),
    ("[", "err EOF while parsing a list at line 1 column 1"),
    ("{\"a\":1", "err EOF while parsing an object at line 1 column 6"),
    ("[1,]", "err trailing comma at line 1 column 4"),
    ("{\"a\":1,}", "err trailing comma at line 1 column 8"),
    ("1.0", "ok f1.0"),
    ("-0", "ok f-0.0"),
    ("-0.0", "ok f-0.0"),
    ("1e400", "err number out of range at line 1 column 5"),
    ("-1e400", "err number out of range at line 1 column 6"),
    ("1e-400", "ok f0.0"),
    ("18446744073709551615", "ok u18446744073709551615"),
    ("18446744073709551616", "ok f1.8446744073709552e+19"),
    ("-9223372036854775808", "ok i-9223372036854775808"),
    ("-9223372036854775809", "ok f-9.223372036854776e+18"),
    ("0.1", "ok f0.1"),
    ("123456789012345678901234567890", "ok f1.2345678901234568e+29"),
    ("1.7976931348623157e308", "ok f1.7976931348623157e+308"),
    ("2.2250738585072014e-308", "ok f2.2250738585072014e-308"),
    ("4.9e-324", "ok f5e-324"),
    ("1e23", "ok f1e+23"),
    ("\"\\ud800\"", "err unexpected end of hex escape at line 1 column 8"),
    (
      "\"\\udc00\"", "err lone leading surrogate in hex escape at line 1 column 7",
    ),
    ("\"\\ud800\\udc00\"", "ok \"𐀀\""),
    ("\"\\ud800x\"", "err unexpected end of hex escape at line 1 column 8"),
    ("\"\\ud800\\x\"", "err unexpected end of hex escape at line 1 column 9"),
    (
      "\"\\ud800\\u0041\"", "err lone leading surrogate in hex escape at line 1 column 13",
    ),
    ("\"\\u12\"", "err EOF while parsing a string at line 1 column 6"),
    ("\"\\u12G4\"", "err invalid escape at line 1 column 7"),
    ("\"abc", "err EOF while parsing a string at line 1 column 4"),
    (
      "\"a\u{1}b\"", "err control character (\\u0000-\\u001F) found while parsing a string at line 1 column 3",
    ),
    ("tru", "err EOF while parsing a value at line 1 column 3"),
    ("nul", "err EOF while parsing a value at line 1 column 3"),
    ("nulx", "err expected ident at line 1 column 4"),
    ("[1 2]", "err expected `,` or `]` at line 1 column 4"),
    ("{\"a\" 1}", "err expected `:` at line 1 column 6"),
    ("{1:2}", "err key must be a string at line 1 column 2"),
    ("[01]", "err invalid number at line 1 column 3"),
    ("1.", "err EOF while parsing a value at line 1 column 2"),
    ("1.e5", "err invalid number at line 1 column 3"),
    ("1e", "err EOF while parsing a value at line 1 column 2"),
    ("1e+", "err EOF while parsing a value at line 1 column 3"),
    ("-", "err EOF while parsing a value at line 1 column 1"),
    ("--1", "err invalid number at line 1 column 2"),
    (" ", "err EOF while parsing a value at line 1 column 1"),
    ("", "err EOF while parsing a value at line 1 column 0"),
    ("[]x", "err trailing characters at line 1 column 3"),
    ("[] ", "ok []"),
    ("{\"a\":[{\"b\":", "err EOF while parsing a value at line 1 column 11"),
    (
      "{\n  \"a\": 1,\n  \"b\": [1, 2,\n    x]\n}", "err expected value at line 4 column 5",
    ),
    ("{\"é\": 1, \"ü\": tru}", "err expected ident at line 1 column 20"),
    ("\"é\\q\"", "err invalid escape at line 1 column 5"),
    ("{\"a\":1,\"a\":2,\"b\":3}", "ok {\"a\":u2,\"b\":u3}"),
    ("1e2147483648", "err number out of range at line 1 column 12"),
    ("0e2147483648", "ok f0.0"),
    ("1e-2147483649", "ok f0.0"),
    ("1.5e999999999999", "err number out of range at line 1 column 14"),
    ("0.1234567890123456789012345678901234567890", "ok f0.12345678901234568"),
    ("12345678901234567890.5", "ok f1.2345678901234567e+19"),
    ("12345678901234567890e-5", "ok f123456789012345.67"),
    ("99999999999999999999e300", "err number out of range at line 1 column 24"),
    ("1e308", "ok f1e+308"),
    ("1e309", "err number out of range at line 1 column 5"),
    ("10e308", "err number out of range at line 1 column 6"),
    ("0.0000001e-320", "ok f0.0"),
    ("\"\\b\\f\\n\\r\\t\\/\\\\\\\"\"", "ok \"\\u{8}\\u{c}\\n\\r\\t/\\\\\\\"\""),
    ("\"\u{2028}­\u{301}x​\"", "ok \"\\u{2028}\\u{ad}\\u{301}x\\u{200b}\""),
    ("{\"a\":}", "err expected value at line 1 column 6"),
    ("{\"a\"", "err EOF while parsing an object at line 1 column 4"),
    ("{\"a\":1 \"b\":2}", "err expected `,` or `}` at line 1 column 8"),
    ("[1,,2]", "err expected value at line 1 column 4"),
    ("[,1]", "err expected value at line 1 column 2"),
    ("{,}", "err key must be a string at line 1 column 2"),
    ("{\"a\":1,,}", "err key must be a string at line 1 column 8"),
    ("true false", "err trailing characters at line 1 column 6"),
    ("\u{feff}{}", "err expected value at line 1 column 1"),
    ("{\"k\\u0000\":1}", "ok {\"k\\0\":u1}"),
    ("1E5", "ok f100000.0"),
    ("1e05", "ok f100000.0"),
    ("-1.5E-3", "ok f-0.0015"),
    ("[[[]]]", "ok [[[]]]"),
    ("{\"a\":{\"b\":{\"c\":null}}}", "ok {\"a\":{\"b\":{\"c\":null}}}"),
    ("  \t\r\n  42  \n", "ok u42"),
    ("nan", "err expected ident at line 1 column 2"),
    ("NaN", "err expected value at line 1 column 1"),
    ("Infinity", "err expected value at line 1 column 1"),
    (
      "[1.0, 2.50, -3.25e10, 1e-7, 1e16, 1e15, 123.456e-2]", "ok [f1.0,f2.5,f-32500000000.0,f1e-7,f1e+16,f1000000000000000.0,f1.23456]",
    ),
    (
      "[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]",
      "ok [[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]",
    ),
    (
      "[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[",
      "err EOF while parsing a list at line 1 column 126",
    ),
    (
      "[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]",
      "ok [[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]",
    ),
    (
      "[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[",
      "err EOF while parsing a list at line 1 column 127",
    ),
    (
      "[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]",
      "err recursion limit exceeded at line 1 column 128",
    ),
    (
      "[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[",
      "err recursion limit exceeded at line 1 column 128",
    ),
    (
      "[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]",
      "err recursion limit exceeded at line 1 column 128",
    ),
    (
      "[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[",
      "err recursion limit exceeded at line 1 column 128",
    ),
    (
      "[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]",
      "err recursion limit exceeded at line 1 column 128",
    ),
    (
      "[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[",
      "err recursion limit exceeded at line 1 column 128",
    ),
    ("[\r\n ]", "ok []"),
    ("\n[\n-6907439150008\n]  ", "ok [i-6907439150008]"),
    (
      "\" \\ud800\\ud800x😀\\u12\\n\"", "err lone leading surrogate in hex escape at line 1 column 15",
    ),
    (
      "\t[  { \"é\":\n23489029401491e+220,  \"scope\":[ {\t},\t{\t\"b\"\r\n: [\"- c\"\r\n],  \"scope\":-102843552146590807E-199,  \"scope\" :\r\n[ \t],  \"a\"  :  -1037135.789837610149734\n}]  }\t]  ",
      "ok [{\"é\":f2.3489029401491e+233,\"scope\":[{},{\"b\":[\"- c\"],\"scope\":[],\"a\":f-1037135.7898376102}]}]",
    ),
    (
      "\t{ \"b\"\r\n:\r\n{\n\"a\":  {  \"scope\"\r\n:-12931562493335095984\t},\"scope\":\r\n[181523359.0914982085948207825985867,{\r\n\"a\":\r\n90953966006949511525.673082,\r\n\"a\"  :  -990137406463711333026775.655E-285,\r\n\"a\"  :\"\\u12\\ud800_b\\x\"  },\"x\",-2658141772390803359.69567485328481756]  }}",
      "err invalid escape at line 10 column 13",
    ),
    ("\r\n", "err EOF while parsing a value at line 2 column 0"),
    (
      "-9534308.6420533979280897 6960419 ", "err trailing characters at line 1 column 27",
    ),
    ("\tfalse\r\n", "ok false"),
    ("\"_\\\"", "err EOF while parsing a string at line 1 column 4"),
    (
      "{\"a\":  -558503414", "err EOF while parsing an object at line 1 column 17",
    ),
    (
      "\n[ null, {\r\n }, { }, [false, az-\"]\r\n]", "err expected value at line 3 column 18",
    ),
    (
      "\r\n[  \"z\\/ \u{1}\" ]\r", "err control character (\\u0000-\\u001F) found while parsing a string at line 2 column 9",
    ),
    (
      "  {\r\n\"name\":\r\n-5487797959097939e+234,\t\"a\" :  \"\",\t\"a\"\n:\r\nnull\t\r\n",
      "err EOF while parsing an object at line 6 column 0",
    ),
    (" 105 ", "ok u105"),
    ("  [\r\n\r\n] ", "ok []"),
    ("null", "ok null"),
    ("\n{\t }", "ok {}"),
    ("698E+294  ", "ok f6.980000000000001e+296"),
    ("\tnul,l\n", "err expected ident at line 1 column 5"),
    (
      "{\"name\"\n: 1106272669217861599865e-145, \"scope\"\n: [  \"\",  {\n\"é\"\n:\t{\"a\"\n:  15907065E-270}\t},  44028174144214062312], \"scope\":\n54772261836293792645, \"a\":false\t} ",
      "ok {\"name\":f1.1062726692178617e-124,\"scope\":f5.47722618362938e+19,\"a\":false}",
    ),
    (
      "  [  [\r\n-481.5643E319,  [  -287753100024188730463.729578278E-11\t],  [ {\n}\t],  \"za \"],\r\n-14032361960109714062,\r\n[\t{\n\"a\"\t:{  \"é\"  :\t[  false,\t-7496,\t\"\u{1}\"],\"a\"  :  [\t],\"scope\":\t{  ",
      "err number out of range at line 2 column 13",
    ),
    (
      "  {\"é\"  :  58905600856539459629,\r\n\"b\"  :[  {\n\"scope\":  { \"b\" :\r\n[\r\n\"\",  false\t],\"scope\"\r\n:\t[  true,null ],\"scope\"\t:{  \"scope\"\r\n: \"x  a\",\r\n\"scope\"\t:\" c\",\r\n\"a\"\t:-499E-295,\r\n\"é\":\ttrue},\"scope\":\r\ntrue  },\"é\":false,\"é\":[ [\tfalse],\r\n-2.918200419424151844937217,\r\n{  \"a\"\r\n:\" \u{1}z​\\/\\xü\",\"scope\"\t:false,\"é\"\t:\tnull,\"é\":  42995495991744902394\n} ]},-45243232688886960712.480E+328\r\n]}\r\n",
      "err control character (\\u0000-\\u001F) found while parsing a string at line 14 column 4",
    ),
    ("{\t}", "ok {}"),
    ("  -72541085232463390483\n", "ok f-7.254108523246339e+19"),
    (
      "\n[\n{\r\n\"b\":\t1513309e147  },880456112800863541-,true,{  \"a\"\r\n:\ttrue,  \"a\" :  {\n}\t}]\t",
      "err expected `,` or `]` at line 4 column 39",
    ),
    (" {   }\t", "ok {}"),
    ("\n\"\\n-\\ty]\"\r\n", "ok \"\\n-\\ty]\""),
    (
      "\r\n[\r\n{\r\n\r\n},\r\n\"\u{1}c_\\u12\\u00e9\",\r\n{\"scope\"\t: [  {\t\"é\": -298100153.142110532e-111,  \"a\"\n:  null,  \"name\":[\r\nnull\r\n],  \"a\"\n: \"___y -\\u00e9\\ud83d\\ude00\"\t}],\n\"scope\" :[\r\n],\n\"a\"  :  false  },\r\n\"b\\u12-üü_​\" ]",
      "err control character (\\u0000-\\u001F) found while parsing a string at line 6 column 2",
    ),
    ("[  \t]\r\n", "ok []"),
    (" -54493122730742879164\n", "ok f-5.4493122730742874e+19"),
    ("\r\n\"\"\r\n", "ok \"\""),
    (
      "{\n\"a\" :\r\n-267398}70750645338413,\r\n\"b\"\n:\n\"übx\\ud800 \\ud83d\\ude00\"}",
      "err trailing characters at line 3 column 9",
    ),
    ("e  {\t\"scope\"\n:[\n]}\n", "err expected value at line 1 column 1"),
    ("\r\n65339421E+124", "ok f6.5339420999999994e+131"),
    (
      " {\t\"a\"\t:\"_a-\\tyy\\ud83d\\ude00\",\t\"scope\"\r\n:  \"b\"  }\r\n", "ok {\"a\":\"_a-\\tyy😀\",\"scope\":\"b\"}",
    ),
    ("\t{\r\n}  ", "ok {}"),
    ("[\r\n\n]\n", "ok []"),
    (
      "[[ {  \"é\": 177955138630234917027e270,\"name\":\t85604149703149473511,\"é\"\r\n: [ \"\\ud800-\",[\r\n\" ccyayc\\ud800\",\r\n-46703872002891877136,\r\nfalse\n]\t]}\n],  [\n\t],  {\n\"a\"\r\n:  { \"name\"  :\r\n{\n\"a\"\n:{\n\"name\" :-6039643090.0552026773661166939884e-201,\r\n\"é\":\n2112235589455074260E160,\r\n\"b\" :\t28E43},\"é\"\r\n:\"\"},\"é\"\n: { \"é\":\"c_b\",\r\n\"scope\"  : \"\u{1}b\",\r\n\"b\"\t:  false\r\n}\t},  \"a\" :\r\n{  \"name\":\n500E261} }]",
      "err unexpected end of hex escape at line 2 column 12",
    ),
    ("{\"b\":\r\n840634", "err EOF while parsing an object at line 2 column 6"),
    ("  [\r\n\"c_zz\\\\é\"\t]  ", "ok [\"c_zz\\\\é\"]"),
    ("false\n", "ok false"),
    ("18904382997539086\n863  ", "err trailing characters at line 2 column 1"),
    ("-9e-4  ", "ok f-0.0009"),
    ("[\n[\t{ }  ]\r\n]", "ok [[{}]]"),
    ("\n-96888174143450.997203399246152967\t", "ok f-96888174143451.0"),
    ("\n{\t}", "ok {}"),
    ("\t8219997627273579.80389\t", "ok f8219997627273580.0"),
    ("\nnull  ", "ok null"),
    (" \"y_-zy​​​\"", "ok \"y_-zy\\u{200b}\\u{200b}\\u{200b}\""),
    ("\n{\t}  ", "ok {}"),
    (
      "{ \"a\"\r\n: 45163E+131,  \"name\" :false,  \"a\"  :{  \"name\"\n:\n\"ab\\ud800a\\t\\\\\" }\r\n} ",
      "err unexpected end of hex escape at line 4 column 10",
    ),
    ("25547502959789300659\r\n", "ok f2.55475029597893e+19"),
    ("  { } ", "ok {}"),
    ("\r\n87186.88235E+260", "ok f8.718688235e+264"),
    ("\t{\t\"-scope\"\n:true\t}", "ok {\"-scope\":true}"),
    (" { \r\n}\t", "ok {}"),
    (
      "{\t\"name\"\r\n:  \"\\/ü\\x x\", \"b\":  null, \"scope\":\nnull, \"scope\":{\"name\"\r\n:[\r\n-77814468700814462396,\n[\t],\n-996356220394113730524182E-262\r\n]\t}\t}\r\n",
      "err invalid escape at line 2 column 10",
    ),
    (
      "[35949581651.5135042283e-215,  {  } ]  ", "ok [f3.59495816515135e-205,{}]",
    ),
    ("20697000360E+3", "ok f20697000360000.0"),
    ("\t{  } ", "ok {}"),
    ("false  ", "ok false"),
    (
      "[ {\"scope\":  {\n\"b\"\t:{\n\"scope\" : [  49611826690697870578,true],\n\"a\"\r\n:{ \n},\n\"name\":-4083629805635},  \"b\"\n: 54688378522804233591,  \"a\":[\n{\r\n\"b\" :\r\n496925109165359994162.51327427184369010957676\n},  [false,\r\n\"z\\\\\\\\x\u{1}\",\r\ntrue,\r\n\"ü-_\\u00e9cé\" ]\t]  },  \"b\"\t:\r\n{\t\"name\"\t:\r\n[[\r\n\"\\ud83d\\ude00ü\",false,null\t],\r\n[\r\n3235.5352447,true\t]],\t\"scope\":[\r\n[552219129358.9287636879\r\n] ],\t\"é\"\n:\t635141.408492  }}  ]",
      "err control character (\\u0000-\\u001F) found while parsing a string at line 13 column 8",
    ),
    (" fals]e\n", "err expected ident at line 1 column 6"),
    ("3321814642.114476456029041e29 ", "ok f3.3218146421144765e+38"),
    (
      "\n{\"name\"\n:{\r\n\"é\":\r\n[  {\n\t},\r\n\"中zx\\ud800-\\u12\",\r\nnull\r\n]\n},\r\n\"b\" : {\"a\":\"\" }\r\n}\r\n",
      "err unexpected end of hex escape at line 7 column 13",
    ),
    ("\r\n5872560557062432656", "ok u5872560557062432656"),
    ("-1879812247709834115E-188 ", "ok f-1.8798122477098342e-170"),
    (
      "  [70356e+36,{\t},nul", "err EOF while parsing a value at line 1 column 20",
    ),
    (
      "\t{664892911070124959.307034\n", "err key must be a string at line 1 column 3",
    ),
    ("\t{0 }\n", "err key must be a string at line 1 column 3"),
    (
      "  {\t\"scope\" : 91797582478626009540.08524304397449.  }\r\n", "err expected `,` or `}` at line 1 column 50",
    ),
    (
      " {\"scope\"\r\n:  [\n{\t\"é\" :\t[\ttrue,\n[\n\r\n],\ntrue,\nnull ],\"é\"\r\n:\t{\t\"name\"  :  {  \"scope\"\n:\t876075728684.75881423675640558765E+172, \"scope\":  -91508745612978525696, \"nae\"\r\n:\r\ntrue, \"name\"\t:true  },\r\n\"scope\"\r\n: {\r\n\r\n},\r\n\"scope\"\n: 1758e-117,\r\n\"name\"  :67755273655826174769  } }],\"b\"\t: -2795973615754E+117\n}\t",
      "ok {\"scope\":[{\"é\":{\"name\":f6.775527365582618e+19,\"scope\":f1.7579999999999998e-114}}],\"b\":f-2.795973615754e+129}",
    ),
    ("\t[\\ ]\n", "err expected value at line 1 column 3"),
    ("[ \t\t]\n]", "err trailing characters at line 2 column 1"),
    (" {\"a\"\r\n:{\n}}", "ok {\"a\":{}}"),
    (
      "\n396x61952394887548589\r\n", "err trailing characters at line 2 column 4",
    ),
    (
      "\r\n{\r\n\"é\"\r\n:  [\t\n],\n\"é\" :\t[\t{\r\n\"é\":\r\n{\t\n}\t},true],\n\"a\" :\r\n7669990.9e+292 }",
      "ok {\"é\":[{\"é\":{}},true],\"a\":f7.6699909e+298}",
    ),
    ("\t{}", "ok {}"),
    ("  415324368963996694.40294751624e+143  ", "ok f4.153243689639967e+160"),
    (
      "{\"name\"  :\n[\r\n[[\r\n[-\n146179269698E27, 15401895701427043425, 326037349916985.49891683653373135414661E238],\t1766422.5574418613157\n]\r\n],\r\nfalse,\r\n\"ac\"],\t\"scope\":\"\\/xé-\u{301}\",\t\"b\"  : 47823170808200112914\t}\t",
      "err invalid number at line 5 column 0",
    ),
    (
      " {\r\n\"scope\"\t:  61309028.10081335712850749540815e+72}\t", "ok {\"scope\":f6.130902810081335e+79}",
    ),
    (
      "[true,\n{\n\"é\"\t:  \"中_\\u12\\ud83d\\ue00 \\nbx\", \"a\":\t\"\u{301}\", \"a\": [null\n] },\n28624959333183692918]",
      "err invalid escape at line 3 column 19",
    ),
    (" {\"a\"\r\n:-9152990478173579601}  ", "ok {\"a\":i-9152990478173579601}"),
    (
      "\n[[\n[  [],  8205644894]\r\n],\n83.65901423e+205\r\n]  ", "ok [[[[],u8205644894]],f8.365901423e+206]",
    ),
    ("\n[  \t]\r\n", "ok []"),
    (
      "\r\n{\t\"é\":\n[\t\r\n],  \"a\"\t:{\"scope\"\t:\t4746713497240645.261108527607869E-36}}\n",
      "ok {\"é\":[],\"a\":{\"scope\":f4.746713497240646e-21}}",
    ),
    (" \"\u{301}üzx\\\"\"", "ok \"\\u{301}üzx\\\"\""),
    (
      "\r\n{\t\"scope\":\n[\r\n{\t\"name\":\t-4.887534547151744,\"scope\":{\r\n\"scope\"\r\n:\r\n[  \"é\\\"\u{1}_\",  false,  \"ayac\" ],\n\"name\"\n:\"b\\u12\",\n\"scope\"  :  [\t\"\\n\u{301}__a\\xy\",\r\n\"x\\xyb \",\r\n63052724273802041389589.11311153\t],\n\"a\"\n:\n[ ]\t}\n},\t\"ac😀c \\\"😀\",\t{\n},\tfalse],\"a\":\n{  \"é\"\n: {  }, \"scope\"\r\n:  {\r\n\"b\" :\r\n[\t[\n\t]\r\n],\r\n\"a\"\n: -543819862488E-214}, \"b\"\n:  null\t}} ",
      "err control character (\\u0000-\\u001F) found while parsing a string at line 7 column 9",
    ),
    ("{}\n", "ok {}"),
    ("7240819611528957537385685e-218", "ok f7.240819611528958e-194"),
    (
      "[67648337, [\t[[ {  },\n[  \"baa_y\\u12\"  ]\t],[\r\n[51271331061302506558,\n-37195054110584560116,\n-14917285156845014657]\t],{   },null],{   },{\t\"é\"\r\n:[  [\r\ntrue,\t7123750243.38007187381269235527e+303\t], true\t],\t\"scope\" :true,\t\"a\"\n:{  \"scope\":\n{ \"a\":\r\ntrue}\n} }\r\n], {\"é\" :{\r\n\"é\"\r\n:  [\"x\",  \"c\",  64438.2941320479488722409e-80]\n}\t} ]\r\n",
      "err invalid escape at line 2 column 15",
    ),
    ("\r\n-4248892487365888897038876.0519E+209 ", "ok f-4.248892487365889e+233"),
    (
      "{  \"b\" :  [\n89736986112402190761,\r\n{\n}\t]  }  ", "ok {\"b\":[f8.97369861124022e+19,{}]}",
    ),
    (" 2.147305417615714058816\n", "ok f2.1473054176157143"),
    (
      "{ \"é\":\t[\t{\"b\"\r\n: {\"a\" : [\r\n  ],  \"name\" :\ttrue,  \"é\"  :\t[\t\"\\t\u{1}z ayc\",-58625531007098390 8184128.5150,\" x\",60253860270768e102]  }\r\n},\r\n{ \"a\":  true  },\r\n{  \"name\"\t:[  [  -2666556.768059e+146\n], [-395.848684e+260, \"y\", null\t], -94521424841368527053, \"yc a\\\"\"]}  ]\n}\t",
      "err control character (\\u0000-\\u001F) found while parsing a string at line 3 column 36",
    ),
    ("  [\n]\r\n", "ok []"),
    (
      "{\r\n\"name\"\n:  [{}, [\n{\t\"a\"\t:\tnull}], [ \"\\ud800中\\u12\", [  [false,  null,  4068320317135853132892092.3243779306833711244966E232,  717870534565930311  ],\r\n[\n19502984231541737108  ],\r\n{\"b\"  :  -83503348141620392210,  \"name\"\t:770878398e+184,  \"b\" :\"x-_éaycz\",  \"name\" :  55992403376323380427\t}]\n]\t],\r\n\"b\":false}\t",
      "err unexpected end of hex escape at line 4 column 26",
    ),
    (
      "\t{  \"a\" :\r\n[\t ],\r\n\"é\"\r\n:\n\"ybyy\\tc\"}", "ok {\"a\":[],\"é\":\"ybyy\\tc\"}",
    ),
    ("\n15079597149394360787\n", "ok u15079597149394360787"),
    ("  \"é \"\t", "ok \"é \""),
    ("\t850E251\t", "ok f8.5e+253"),
    ("\"z\" ", "ok \"z\""),
    (
      "\n{\"a\":  [\n{  \"é\"\n:\r\n98731494.459613364104426933110E-284,\"b\" : [  ],\"a\"\n:\n{\n\r\n}\t},  {  \"scope\"  :\t{\n\"b\" :{ },\t\"scope\"  : -46382224",
      "err EOF while parsing an object at line 10 column 30",
    ),
    (
      "\n{\r\n\"b\":\n\"中x \\u00e9x\\ud800\",\t\"name\"\n:\n{ \"scope\":{\"b\"\t: [\nnull]\t},\"é\":13856,\"a\"  :\t279651368498E-289},\t\"b\":\t{ }}-\t",
      "err unexpected end of hex escape at line 4 column 20",
    ),
    ("  94114867", "ok u94114867"),
    (" -11328.2371461700E293\r\n", "ok f-1.132823714617e+297"),
    (
      "  {\n\"a\"  :  \"\\u00e9​\\ud800axa_\"}", "err unexpected end of hex escape at line 2 column 25",
    ),
    ("  [  ]\r\n", "ok []"),
    ("false\r\n", "ok false"),
    ("\r\n", "err EOF while parsing a value at line 2 column 0"),
    (
      "  { \"\"scope\"\r\n:\r\nnull,\n\"name\"\n:\n[\r\n{\n },\n{    },\nfalse  ],\n\"name\"\r\n:{},\n\"é\"\n: [  {\n},  14091110e+35,  8518725983417766340.98680980219421085e220,  { \"scope\":\t{}\r\n} ]}\r\n",
      "err expected `:` at line 1 column 7",
    ),
    ("[\r\n\t", "err EOF while parsing a list at line 2 column 1"),
    ("\t[\"bc\\n\\ud83d\\ude00y_\"]", "ok [\"bc\\n😀y_\"]"),
    ("\t\"😀\\u00e9\\\\\"\r\n", "ok \"😀é\\\\\""),
    (" \"\\u12cxé中_b\"", "err invalid escape at line 1 column 8"),
    ("-4982154356377200017  ", "ok i-4982154356377200017"),
    ("{\n\r\n}", "ok {}"),
    ("95883769965759603603  ", "ok f9.588376996575961e+19"),
    (
      "\t{\"b\"  :\t{  \t}, \"b\"\n:3127953282849e+114, \"scope\"\t,:\t85433711729569360992.5156918494027816e+54  }",
      "err expected `:` at line 2 column 30",
    ),
    (
      "\t154577914272994346848559.072743214012979196347 ", "ok f1.5457791427299434e+23",
    ),
    ("\r\n{\r", "err EOF while parsing an object at line 2 column 2"),
    (
      "\n[false,\n{  \"é\":  [  [  740616186607.38576,\t[  614442083746033e-143 ],\t2687377.1645619381222588E-198] ]}\n]  ",
      "ok [false,{\"é\":[[f740616186607.3857,[f6.14442083746033e-129],f2.687377164561938e-192]]}]",
    ),
    ("\"z_\\u12\"\t", "err invalid escape at line 1 column 9"),
    (" \"caa\u{301}z", "err EOF while parsing a string at line 1 column 8"),
    ("\"a中-a\"\r\n", "ok \"a中-a\""),
    (
      "  {\r\n\"name\" :49266e281,  \"a\"\n:\r\n4.19130921930099745E301,  \"a\":true}\r\n",
      "ok {\"name\":f4.9266e+285,\"a\":true}",
    ),
    (
      "{\n\"é\":\n[ -91327007878977462383,\r\n{\t\"é\" :  [ {\t\"a\"\n:  \"\\\\-\\\"\"},[  \t]],  \"name\"\t: {  \"a\":\r\n[  36578546041376544.9826e170],\"é\"\r\n:\t{\r\n\"name\": null,\t\"a\":\t15939.171512e+87,\t\"scope\"  :  67253501328425e189\r\n},\"name\"\t:\t{\"name\"\n: 77.384360e28, \"é\" :\r\ntrue, \"name\"\t:  624.90947682873126676, \"a\" :90680675031070185024},\"a\": [\t56565.453\n] }  },\r\n3122.8008501065231200730834138 ],\n\"scope\"  :28457818374}\n",
      "ok {\"é\":[f-9.132700787897747e+19,{\"é\":[{\"a\":\"\\\\-\\\"\"},[]],\"name\":{\"a\":[f56565.453],\"é\":{\"name\":null,\"a\":f1.5939171511999999e+91,\"scope\":f6.7253501328425e+202},\"name\":{\"name\":f624.9094768287313,\"é\":true,\"a\":f9.068067503107018e+19}}},f3122.8008501065233],\"scope\":u28457818374}",
    ),
    ("-49073438676964466E248", "ok f-4.907343867696446e+264"),
    (" tr", "err EOF while parsing a value at line 1 column 3"),
    (
      " {\n\"scope\"  : [\r\n[\n[\t[\n3864390247602090989431,\r\n\"\\u00e9y\"  ] ]\n],\t{\"scope\"  : {\"b\":null,\r\n\"b\" :[ false, \"c \\nbé \\u00e9\", null, false]\t},\r\n\"a\"\t:\n[{ }],\r\n\"a\" :79778405009087726871} ],\t\"a\"\t:  {\"é\"\t:[\n[  {\n\"b\"\t:  96624030121, \"name\":  -14, \"é\":95460715687420938299 }],  9626793409523810783e+273\r\n],\t\"é\"  :  [\n[\t\n],\r\n{  }\n],\t\"a\":  625316080.5068144426442355397} }\n",
      "ok {\"scope\":[[[[f3.864390247602091e+21,\"éy\"]]],{\"scope\":{\"b\":[false,\"c \\nbé\\u{a0}é\",null,false]},\"a\":f7.977840500908773e+19}],\"a\":{\"é\":[[],{}],\"a\":f625316080.5068145}}",
    ),
  ]
  for case in cases {
    let (doc, expected) = case
    assert_eq(parse_value(doc), expected)
  }
}

///|
test "from_str::<Value> nesting limit" {
  let nested = (n : Int32) => "[".repeat(n) + "]".repeat(n)
  inspect(parse_value(nested(127)).length() > 0, content="true")
  assert_true(parse_value(nested(127)).has_prefix("ok "))
  inspect(
    parse_value(nested(128)),
    content="err recursion limit exceeded at line 1 column 128",
  )
  inspect(
    parse_value("{\"x\": " + nested(130) + "}"),
    content="err recursion limit exceeded at line 1 column 133",
  )
}

///|
test "zmij_format matches zmij" {
  let cases : Array[(UInt64, String)] = [
    (0x17B6AF7D213ED6D2UL, "1.9422772553975967e-194"),
    (0x44AD0DD7FF960D87UL, "6.8602e+22"),
    (0xB8F7ED82BD456EE2UL, "-2.880201289759044e-34"),
    (0x0002056598D475D3UL, "2.81065975314993e-309"),
    (0x71579C7D5FE9FDAAUL, "9.6094e+237"),
    (0xED89FF66E2AC2790UL, "-4.588610316361374e+219"),
    (0x24F146D04A8960D0UL, "9.736e-131"),
    (0x15E98A3FAE8A45FEUL, "4.073e-203"),
    (0x0002474C1032C163UL, "3.168650337582493e-309"),
    (0xFBA8CEFB7C2751A9UL, "-4.72200907974898e+287"),
    (0x41221AC184B67662UL, "593248.7592045779"),
    (0xC80408CEE00D0772UL, "-8.52169414978741e+38"),
    (0x4126004F275B682AUL, "720935.5768692542"),
    (0x7970132C4F8C8304UL, "8.9048e+276"),
    (0xC1226573ECABC085UL, "-602809.962247864"),
    (0x1DE0C10FA5A4E7FDUL, "9.0919e-165"),
    (0xBC74F20F8F32825AUL, "-1.816736857918422e-17"),
    (0x1D8823F47D2D3710UL, "2.0469053276729075e-166"),
    (0xD3E186779B93B889UL, "-1.169804176516259e+96"),
    (0x000DB12DA350B252UL, "1.9041212268553015e-308"),
    (0xE5D6F5711F5A7C6DUL, "-3.8107088446272166e+182"),
    (0x000E1ED046C45768UL, "1.9636785155835155e-308"),
    (0x43EFFB3D2418B6B1UL, "1.843602287658307e+19"),
    (0x3E6E72EE30CEAD34UL, "5.671558343049225e-8"),
    (0xC12D13A3B9AADDCBUL, "-952785.862631732"),
    (0x870D7A91226B923EUL, "-1.0642984517000105e-274"),
    (0x37FF128953A69442UL, "5.7071e-39"),
    (0x3E8E4C7D163D5A78UL, "2.257435297535356e-7"),
    (0x45442766E9394E9FUL, "4.8729174117139895e+25"),
    (0xDC7DDC1E942C2F24UL, "-3.4725262676645434e+137"),
    (0x0003F0CD5EDD301DUL, "5.480125653363474e-309"),
    (0x1C5EACD6D46E32F7UL, "4.961e-172"),
    (0x57982CCCF526C159UL, "9.302183540671767e+113"),
    (0xC12AD4BEA3E9093EUL, "-879199.3201372994"),
    (0x109B988D0E0ED64CUL, "1.1375955988519756e-228"),
    (0xC3D814A82EB1EF0EUL, "-6.940786699806718e+18"),
    (0x8238F97CB1211FA4UL, "-5.966808885062519e-298"),
    (0x42A0A675BCA93017UL, "9153562956952.045"),
    (0x000A477F67100D41UL, "1.429510904820524e-308"),
    (0xC126EF5D65B188AAUL, "-751534.6986201007"),
    (0x48D102EC7FF51BF4UL, "5.92761515109551e+42"),
    (0x34488FDE43AF3A23UL, "7.8259e-57"),
    (0x20F49419D656D3C8UL, "6.28660667495552e-150"),
    (0xC684276A2C4CC796UL, "-5.109636867218105e+31"),
    (0x4718D63BE0B69539UL, "3.224007606674426e+34"),
    (0x4C13437FB4BE8D9CUL, "3.023e+58"),
    (0xC7D838FCE90DBFC8UL, "-1.2878948061821229e+38"),
    (0x65E50E0BC9E8E44AUL, "6.9894e+182"),
    (0x0000B94AD19ACE72UL, "1.006564857717636e-309"),
    (0xC1068D601FDD6FE8UL, "-184748.01555907656"),
    (0x00028266C3B1E08CUL, "3.489723179308834e-309"),
    (0x41F53EA632280938UL, "5702837026.502251"),
    (0x533A3236E2FD20B5UL, "8.538e+92"),
    (0x4117B2652C6645E8UL, "388249.2933588908"),
    (0x08882794F2AEA5ACUL, "1.4631e-267"),
    (0xBFE63769111F8B99UL, "-0.6942639669836012"),
    (0xFB1ECB5720BC2391UL, "-1.1447910532901044e+285"),
    (0x1EAC64846142CF41UL, "6.311e-161"),
    (0x8D7C297FE561A0EFUL, "-1.0311187334681912e-243"),
    (0xBEF476870218F89FUL, "-0.000019515035211130888"),
    (0x31C5A1D4294BE8BFUL, "6.2686e-69"),
    (0x000EF82A5F69FDFEUL, "2.0817508096851297e-308"),
    (0x7E6D46E9A01786B3UL, "9.8033e+300"),
    (0x92124B9EE09B8BA8UL, "-1.2653333172932462e-221"),
    (0xF381026D0B0BAD48UL, "-2.378577926563769e+248"),
    (0x61F0810513A553A7UL, "5.94e+163"),
    (0x0006618003ED16ADUL, "8.873677444265434e-309"),
    (0x0007D31004C66DD3UL, "1.08812552925547e-308"),
    (0x4110E2E502DE3778UL, "276665.25280081434"),
    (0x446007D5D7FF7EB3UL, "2.3657e+21"),
    (0xC1228D68AF02AB86UL, "-607924.3418172456"),
    (0x412A3E384F668D12UL, "859932.1550792775"),
    (0x034F18B2374BC3E1UL, "9.7379e-293"),
    (0x0B7CC4D95F4FE163UL, "2.4524917088227127e-253"),
    (0x41132B7A8976B0F8UL, "314078.6342418338"),
    (0xC125230E6057BBE8UL, "-692615.1881693574"),
    (0x0002521CABD0E4DBUL, "3.22740008030162e-309"),
    (0x4113743221C2C800UL, "318732.532969594"),
    (0xC5830375540AFB17UL, "-7.355495039075812e+26"),
    (0x00000378C795EC89UL, "1.885986636944e-311"),
    (0xC12C3541928BD8CDUL, "-924320.786223197"),
    (0x34DEF2CD06A8C2DCUL, "5.0487e-54"),
    (0x411AEDF69431B91CUL, "441213.6447209285"),
    (0x2E40094399D5450EUL, "6.449e-86"),
    (0x566A3E7822DEA875UL, "1.9261e+108"),
    (0x000EA4B30A8DA018UL, "2.0364094222044305e-308"),
    (0x8A5D0CF8ACD9DECAUL, "-9.447129811141588e-259"),
    (0x5464F734C87CB45AUL, "3.582588383920638e+98"),
    (0xE1A064F25250749AUL, "-1.843916094927575e+162"),
    (0xBF7F92C6B9FA2EA2UL, "-0.0077083361389999345"),
    (0x436F7EA645B66D4FUL, "7.0919815018277496e+16"),
    (0x49A4D0EE503590C6UL, "5.941956521780653e+46"),
    (0x22DD3913307C98FAUL, "9.585749573380871e-141"),
    (0x000F7771BF718A9BUL, "2.1508925945350113e-308"),
    (0x5033D7B9F70DE470UL, "2.2976255297672782e+78"),
    (0x4118D81EDC5D3D60UL, "407047.7151994314"),
    (0xCF0074D1EC09663BUL, "-3.634476887387848e+72"),
    (0xC97B39F158150158UL, "-9.714682332639908e+45"),
    (0x1720DD3FCED5FA37UL, "2.8200707637498204e-197"),
    (0x60AB10A7D6F65037UL, "4.644904190839582e+157"),
    (0x43D168561A778E0AUL, "5.017388671590476e+18"),
    (0x3F42334AFC7C3CA1UL, "0.0005554309982204361"),
    (0xC5CFA2CE854F366BUL, "-1.9581713107719134e+28"),
    (0xD01B1198F03A6A11UL, "-7.835864866453173e+77"),
    (0xF401061777B78B1BUL, "-6.094285577097303e+250"),
    (0xC1503EA005FF5447UL, "-4258432.093709058"),
    (0xC7EB063220E814B2UL, "-2.873706111596069e+38"),
    (0x1B5E51487A08A43BUL, "7.481628140202727e-177"),
    (0x6FAF054F0B4C74B3UL, "9.4063e+229"),
    (0x1CC81A661B6C7169UL, "4.9896e-170"),
    (0x80962EA5BF82D32BUL, "-7.89713125025563e-306"),
    (0x412803EC6F94DB0CUL, "786934.2179325535"),
    (0x4128E415E3CCCD08UL, "815626.9449218819"),
    (0x08121C5C3229E51DUL, "8.5704e-270"),
    (0x346FB5CB5FD23B1FUL, "4.041372701265068e-56"),
    (0x4117E3CACBE61FB4UL, "391410.6991200403"),
    (0x1963E0DBE34A6B54UL, "2.2843e-186"),
    (0x412851F8B4195E16UL, "796924.3517560388"),
    (0x0005651D9DC7EA70UL, "7.502647496859577e-309"),
    (0xC12216E54848670EUL, "-592754.6411773877"),
    (0x0000000000000000UL, "0.0"),
    (0x8000000000000000UL, "-0.0"),
    (0x430C6BF526340000UL, "1000000000000000.0"),
    (0x4341C37937E08000UL, "1e+16"),
    (0x3EE4F8B588E368F1UL, "0.00001"),
    (0x3EB0C6F7A0B5ED8DUL, "1e-6"),
    (0x4340000000000000UL, "9007199254740992.0"),
    (0x0000000000000001UL, "5e-324"),
    (0x7FEFFFFFFFFFFFFFUL, "1.7976931348623157e+308"),
  ]
  for case in cases {
    let (bits, expected) = case
    assert_eq(@support.zmij_format(bits.reinterpret_as_double()), expected)
  }
}
