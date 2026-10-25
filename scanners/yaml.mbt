// Port of tree-sitter-yaml src/scanner.c (v0.7.2). The schema tables it
// #includes (schema.core.c by default) are in yaml_schema_*.mbt.
// tree-sitter-yaml is distributed under the MIT license (see NOTICE).

///|
/// `enum TokenType`.
const YAML_END_OF_FILE : Int32 = 0

///|
const YAML_S_DIR_YML_BGN : Int32 = 1

///|
const YAML_R_DIR_YML_VER : Int32 = 2

///|
const YAML_S_DIR_TAG_BGN : Int32 = 3

///|
const YAML_R_DIR_TAG_HDL : Int32 = 4

///|
const YAML_R_DIR_TAG_PFX : Int32 = 5

///|
const YAML_S_DIR_RSV_BGN : Int32 = 6

///|
const YAML_R_DIR_RSV_PRM : Int32 = 7

///|
const YAML_S_DRS_END : Int32 = 8

///|
const YAML_S_DOC_END : Int32 = 9

///|
const YAML_R_BLK_SEQ_BGN : Int32 = 10

///|
const YAML_BR_BLK_SEQ_BGN : Int32 = 11

///|
const YAML_B_BLK_SEQ_BGN : Int32 = 12

///|
const YAML_R_BLK_KEY_BGN : Int32 = 13

///|
const YAML_BR_BLK_KEY_BGN : Int32 = 14

///|
const YAML_B_BLK_KEY_BGN : Int32 = 15

///|
const YAML_R_BLK_VAL_BGN : Int32 = 16

///|
const YAML_BR_BLK_VAL_BGN : Int32 = 17

///|
const YAML_B_BLK_VAL_BGN : Int32 = 18

///|
const YAML_R_BLK_IMP_BGN : Int32 = 19

///|
const YAML_R_BLK_LIT_BGN : Int32 = 20

///|
const YAML_BR_BLK_LIT_BGN : Int32 = 21

///|
const YAML_R_BLK_FLD_BGN : Int32 = 22

///|
const YAML_BR_BLK_FLD_BGN : Int32 = 23

///|
const YAML_BR_BLK_STR_CTN : Int32 = 24

///|
const YAML_R_FLW_SEQ_BGN : Int32 = 25

///|
const YAML_BR_FLW_SEQ_BGN : Int32 = 26

///|
const YAML_B_FLW_SEQ_BGN : Int32 = 27

///|
const YAML_R_FLW_SEQ_END : Int32 = 28

///|
const YAML_BR_FLW_SEQ_END : Int32 = 29

///|
const YAML_B_FLW_SEQ_END : Int32 = 30

///|
const YAML_R_FLW_MAP_BGN : Int32 = 31

///|
const YAML_BR_FLW_MAP_BGN : Int32 = 32

///|
const YAML_B_FLW_MAP_BGN : Int32 = 33

///|
const YAML_R_FLW_MAP_END : Int32 = 34

///|
const YAML_BR_FLW_MAP_END : Int32 = 35

///|
const YAML_B_FLW_MAP_END : Int32 = 36

///|
const YAML_R_FLW_SEP_BGN : Int32 = 37

///|
const YAML_BR_FLW_SEP_BGN : Int32 = 38

///|
const YAML_R_FLW_KEY_BGN : Int32 = 39

///|
const YAML_BR_FLW_KEY_BGN : Int32 = 40

///|
const YAML_R_FLW_JSV_BGN : Int32 = 41

///|
const YAML_BR_FLW_JSV_BGN : Int32 = 42

///|
const YAML_R_FLW_NJV_BGN : Int32 = 43

///|
const YAML_BR_FLW_NJV_BGN : Int32 = 44

///|
const YAML_R_DQT_STR_BGN : Int32 = 45

///|
const YAML_BR_DQT_STR_BGN : Int32 = 46

///|
const YAML_B_DQT_STR_BGN : Int32 = 47

///|
const YAML_R_DQT_STR_CTN : Int32 = 48

///|
const YAML_BR_DQT_STR_CTN : Int32 = 49

///|
const YAML_R_DQT_ESC_NWL : Int32 = 50

///|
const YAML_BR_DQT_ESC_NWL : Int32 = 51

///|
const YAML_R_DQT_ESC_SEQ : Int32 = 52

///|
const YAML_BR_DQT_ESC_SEQ : Int32 = 53

///|
const YAML_R_DQT_STR_END : Int32 = 54

///|
const YAML_BR_DQT_STR_END : Int32 = 55

///|
const YAML_R_SQT_STR_BGN : Int32 = 56

///|
const YAML_BR_SQT_STR_BGN : Int32 = 57

///|
const YAML_B_SQT_STR_BGN : Int32 = 58

///|
const YAML_R_SQT_STR_CTN : Int32 = 59

///|
const YAML_BR_SQT_STR_CTN : Int32 = 60

///|
const YAML_R_SQT_ESC_SQT : Int32 = 61

///|
const YAML_BR_SQT_ESC_SQT : Int32 = 62

///|
const YAML_R_SQT_STR_END : Int32 = 63

///|
const YAML_BR_SQT_STR_END : Int32 = 64

///|
const YAML_R_SGL_PLN_NUL_BLK : Int32 = 65

///|
const YAML_BR_SGL_PLN_NUL_BLK : Int32 = 66

///|
const YAML_B_SGL_PLN_NUL_BLK : Int32 = 67

///|
const YAML_R_SGL_PLN_NUL_FLW : Int32 = 68

///|
const YAML_BR_SGL_PLN_NUL_FLW : Int32 = 69

///|
const YAML_R_SGL_PLN_BOL_BLK : Int32 = 70

///|
const YAML_BR_SGL_PLN_BOL_BLK : Int32 = 71

///|
const YAML_B_SGL_PLN_BOL_BLK : Int32 = 72

///|
const YAML_R_SGL_PLN_BOL_FLW : Int32 = 73

///|
const YAML_BR_SGL_PLN_BOL_FLW : Int32 = 74

///|
const YAML_R_SGL_PLN_INT_BLK : Int32 = 75

///|
const YAML_BR_SGL_PLN_INT_BLK : Int32 = 76

///|
const YAML_B_SGL_PLN_INT_BLK : Int32 = 77

///|
const YAML_R_SGL_PLN_INT_FLW : Int32 = 78

///|
const YAML_BR_SGL_PLN_INT_FLW : Int32 = 79

///|
const YAML_R_SGL_PLN_FLT_BLK : Int32 = 80

///|
const YAML_BR_SGL_PLN_FLT_BLK : Int32 = 81

///|
const YAML_B_SGL_PLN_FLT_BLK : Int32 = 82

///|
const YAML_R_SGL_PLN_FLT_FLW : Int32 = 83

///|
const YAML_BR_SGL_PLN_FLT_FLW : Int32 = 84

///|
const YAML_R_SGL_PLN_TMS_BLK : Int32 = 85

///|
const YAML_BR_SGL_PLN_TMS_BLK : Int32 = 86

///|
const YAML_B_SGL_PLN_TMS_BLK : Int32 = 87

///|
const YAML_R_SGL_PLN_TMS_FLW : Int32 = 88

///|
const YAML_BR_SGL_PLN_TMS_FLW : Int32 = 89

///|
const YAML_R_SGL_PLN_STR_BLK : Int32 = 90

///|
const YAML_BR_SGL_PLN_STR_BLK : Int32 = 91

///|
const YAML_B_SGL_PLN_STR_BLK : Int32 = 92

///|
const YAML_R_SGL_PLN_STR_FLW : Int32 = 93

///|
const YAML_BR_SGL_PLN_STR_FLW : Int32 = 94

///|
const YAML_R_MTL_PLN_STR_BLK : Int32 = 95

///|
const YAML_BR_MTL_PLN_STR_BLK : Int32 = 96

///|
const YAML_R_MTL_PLN_STR_FLW : Int32 = 97

///|
const YAML_BR_MTL_PLN_STR_FLW : Int32 = 98

///|
const YAML_R_TAG : Int32 = 99

///|
const YAML_BR_TAG : Int32 = 100

///|
const YAML_B_TAG : Int32 = 101

///|
const YAML_R_ACR_BGN : Int32 = 102

///|
const YAML_BR_ACR_BGN : Int32 = 103

///|
const YAML_B_ACR_BGN : Int32 = 104

///|
const YAML_R_ACR_CTN : Int32 = 105

///|
const YAML_R_ALS_BGN : Int32 = 106

///|
const YAML_BR_ALS_BGN : Int32 = 107

///|
const YAML_B_ALS_BGN : Int32 = 108

///|
const YAML_R_ALS_CTN : Int32 = 109

///|
const YAML_BL : Int32 = 110

///|
const YAML_COMMENT : Int32 = 111

///|
const YAML_ERR_REC : Int32 = 112

///|
const YAML_SCN_SUCC : Int32 = 1

///|
const YAML_SCN_STOP : Int32 = 0

///|
const YAML_SCN_FAIL : Int32 = -1

///|
/// `IND_ROT` ('r').
const YAML_IND_ROT : Int32 = 114

///|
/// `IND_MAP` ('m').
const YAML_IND_MAP : Int32 = 109

///|
/// `IND_SEQ` ('q').
const YAML_IND_SEQ : Int32 = 113

///|
/// `IND_STR` ('s').
const YAML_IND_STR : Int32 = 115

///|
/// `SCH_STT_FRZ`, defined identically by every schema.*.c.
const YAML_SCH_STT_FRZ : Int32 = -1

///|
/// `ResultSchema`. Each schema.*.c declares its own enum (with different
/// orders); the values are only compared by name, so one MoonBit enum
/// serves all of them.
priv enum YamlResultSchema {
  RsStr
  RsInt
  RsNull
  RsBool
  RsFloat
  RsTimestamp
}

///|
/// The YAML schema that decides the type of plain scalars (null, bool, int,
/// float, timestamp or string). Upstream selects it when the scanner is
/// compiled, `-DYAML_SCHEMA=core|json|legacy` (`YAML_SCHEMA` in the Makefile
/// and CMakeLists.txt, core by default), which picks the
/// `schema.<name>.c` that `scanner.c` includes.
pub(all) enum YamlSchema {
  /// The YAML 1.2 core schema (schema.core.c, the default).
  Core
  /// The YAML 1.2 JSON schema (schema.json.c).
  Json
  /// The YAML 1.1 types (schema.legacy.c), including timestamps.
  Legacy
} derive(Eq, Debug)

///|
/// `HAS_TIMESTAMP` of the included schema.
fn YamlSchema::has_timestamp(self : YamlSchema) -> Bool {
  match self {
    Core => YAML_CORE_HAS_TIMESTAMP
    Json => YAML_JSON_HAS_TIMESTAMP
    Legacy => YAML_LEGACY_HAS_TIMESTAMP
  }
}

///|
/// `adv_sch_stt` of the included schema.
fn YamlSchema::adv_sch_stt(
  self : YamlSchema,
  sch_stt : Int32,
  cur_chr : Int32,
  rlt_sch : Ref[YamlResultSchema],
) -> Int32 {
  match self {
    Core => yaml_core_adv_sch_stt(sch_stt, cur_chr, rlt_sch)
    Json => yaml_json_adv_sch_stt(sch_stt, cur_chr, rlt_sch)
    Legacy => yaml_legacy_adv_sch_stt(sch_stt, cur_chr, rlt_sch)
  }
}

///|
/// C `(int16_t)x`.
fn yaml_i16(x : Int32) -> Int32 {
  ((x & 0xFFFF) ^ 0x8000) - 0x8000
}

///|
priv struct YamlScanner {
  /// The `int16_t` fields hold values in -32768..=32767.
  mut row : Int32
  mut col : Int32
  mut blk_imp_row : Int32
  mut blk_imp_col : Int32
  mut blk_imp_tab : Int32
  /// `Array(int16_t)`.
  ind_typ_stk : Array[Int32]
  /// `Array(int16_t)`.
  ind_len_stk : Array[Int32]
  // temp
  mut end_row : Int32
  mut end_col : Int32
  mut cur_row : Int32
  mut cur_col : Int32
  mut cur_chr : Int32
  /// `int8_t`.
  mut sch_stt : Int32
  /// `ResultSchema rlt_sch`, passed by address to `adv_sch_stt`.
  rlt_sch : Ref[YamlResultSchema]
  /// The schema compiled in (`YAML_SCHEMA`).
  schema : YamlSchema
}

///|
fn yaml_write_i16(buffer : FixedArray[Byte], at : Int32, value : Int32) -> Unit {
  buffer[at] = value.to_byte()
  buffer[at + 1] = (value >> 8).to_byte()
}

///|
fn yaml_read_i16(buffer : BytesView, at : Int32) -> Int32 {
  yaml_i16(buffer[at].to_int() | (buffer[at + 1].to_int() << 8))
}

///|
/// Like C, the loop may write up to 2 bytes past
/// `TREE_SITTER_SERIALIZATION_BUFFER_SIZE` (size 1022 passes the guard); the
/// C runtime would then fail its length assertion, while here the
/// out-of-bounds write aborts.
fn YamlScanner::serialize(
  self : YamlScanner,
  buffer : FixedArray[Byte],
) -> Int32 {
  let mut size = 0
  yaml_write_i16(buffer, size, self.row)
  size += 2
  yaml_write_i16(buffer, size, self.col)
  size += 2
  yaml_write_i16(buffer, size, self.blk_imp_row)
  size += 2
  yaml_write_i16(buffer, size, self.blk_imp_col)
  size += 2
  yaml_write_i16(buffer, size, self.blk_imp_tab)
  size += 2
  let mut itr = 1
  while itr != self.ind_typ_stk.length() && size < SERIALIZATION_BUFFER_SIZE {
    yaml_write_i16(buffer, size, self.ind_typ_stk[itr])
    size += 2
    yaml_write_i16(buffer, size, self.ind_len_stk[itr])
    size += 2
    itr += 1
  }
  size
}

///|
fn YamlScanner::deserialize(self : YamlScanner, buffer : BytesView) -> Unit {
  let length = buffer.length()
  self.row = 0
  self.col = 0
  self.blk_imp_row = -1
  self.blk_imp_col = -1
  self.blk_imp_tab = 0
  self.ind_typ_stk.clear()
  self.ind_typ_stk.push(YAML_IND_ROT)
  self.ind_len_stk.clear()
  self.ind_len_stk.push(-1)
  if length > 0 {
    let mut size = 0
    self.row = yaml_read_i16(buffer, size)
    size += 2
    self.col = yaml_read_i16(buffer, size)
    size += 2
    self.blk_imp_row = yaml_read_i16(buffer, size)
    size += 2
    self.blk_imp_col = yaml_read_i16(buffer, size)
    size += 2
    self.blk_imp_tab = yaml_read_i16(buffer, size)
    size += 2
    while size < length {
      self.ind_typ_stk.push(yaml_read_i16(buffer, size))
      size += 2
      self.ind_len_stk.push(yaml_read_i16(buffer, size))
      size += 2
    }
    if size != length {
      abort("assert(size == length)")
    }
  }
}

///|
fn YamlScanner::adv(self : YamlScanner, lexer : @runtime.Lexer) -> Unit {
  self.cur_col = yaml_i16(self.cur_col + 1)
  self.cur_chr = lexer.lookahead
  lexer.advance(false)
}

///|
fn YamlScanner::adv_nwl(self : YamlScanner, lexer : @runtime.Lexer) -> Unit {
  self.cur_row = yaml_i16(self.cur_row + 1)
  self.cur_col = 0
  self.cur_chr = lexer.lookahead
  lexer.advance(false)
}

///|
fn YamlScanner::skp(self : YamlScanner, lexer : @runtime.Lexer) -> Unit {
  self.cur_col = yaml_i16(self.cur_col + 1)
  self.cur_chr = lexer.lookahead
  lexer.advance(true)
}

///|
fn YamlScanner::skp_nwl(self : YamlScanner, lexer : @runtime.Lexer) -> Unit {
  self.cur_row = yaml_i16(self.cur_row + 1)
  self.cur_col = 0
  self.cur_chr = lexer.lookahead
  lexer.advance(true)
}

///|
fn YamlScanner::mrk_end(self : YamlScanner, lexer : @runtime.Lexer) -> Unit {
  self.end_row = self.cur_row
  self.end_col = self.cur_col
  lexer.mark_end()
}

///|
fn YamlScanner::init(self : YamlScanner) -> Unit {
  self.cur_row = self.row
  self.cur_col = self.col
  self.cur_chr = 0
  self.sch_stt = 0
  self.rlt_sch.val = RsStr
}

///|
fn YamlScanner::flush(self : YamlScanner) -> Unit {
  self.row = self.end_row
  self.col = self.end_col
}

///|
fn YamlScanner::pop_ind(self : YamlScanner) -> Unit {
  ignore(self.ind_len_stk.pop())
  ignore(self.ind_typ_stk.pop())
}

///|
fn YamlScanner::push_ind(self : YamlScanner, typ : Int32, len : Int32) -> Unit {
  self.ind_len_stk.push(yaml_i16(len))
  self.ind_typ_stk.push(yaml_i16(typ))
}

///|
/// `RET_SYM(RESULT_SYMBOL)`; callers `return` its result.
fn YamlScanner::ret_sym(
  self : YamlScanner,
  lexer : @runtime.Lexer,
  result_symbol : Int32,
) -> Bool {
  self.flush()
  lexer.result_symbol = result_symbol
  true
}

///|
/// `POP_IND()`: false when the C macro returns false (incorrect status caused
/// by error recovering), true after popping.
fn YamlScanner::pop_ind_checked(self : YamlScanner) -> Bool {
  // incorrect status caused by error recovering
  if self.ind_typ_stk.length() == 1 {
    return false
  }
  self.pop_ind()
  true
}

///|
fn yaml_is_wsp(c : Int32) -> Bool {
  c == ' ' || c == '\t'
}

///|
fn yaml_is_nwl(c : Int32) -> Bool {
  c == '\r' || c == '\n'
}

///|
fn yaml_is_wht(c : Int32) -> Bool {
  yaml_is_wsp(c) || yaml_is_nwl(c) || c == 0
}

///|
fn yaml_is_ns_dec_digit(c : Int32) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn yaml_is_ns_hex_digit(c : Int32) -> Bool {
  yaml_is_ns_dec_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

///|
fn yaml_is_ns_word_char(c : Int32) -> Bool {
  c == '-' ||
  (c >= '0' && c <= '9') ||
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z')
}

///|
fn yaml_is_nb_json(c : Int32) -> Bool {
  c == 0x09 || (c >= 0x20 && c <= 0x10ffff)
}

///|
fn yaml_is_nb_double_char(c : Int32) -> Bool {
  yaml_is_nb_json(c) && c != '\\' && c != '"'
}

///|
fn yaml_is_nb_single_char(c : Int32) -> Bool {
  yaml_is_nb_json(c) && c != '\''
}

///|
fn yaml_is_ns_char(c : Int32) -> Bool {
  (c >= 0x21 && c <= 0x7e) ||
  c == 0x85 ||
  (c >= 0xa0 && c <= 0xd7ff) ||
  (c >= 0xe000 && c <= 0xfefe) ||
  (c >= 0xff00 && c <= 0xfffd) ||
  (c >= 0x10000 && c <= 0x10ffff)
}

///|
fn yaml_is_c_indicator(c : Int32) -> Bool {
  c == '-' ||
  c == '?' ||
  c == ':' ||
  c == ',' ||
  c == '[' ||
  c == ']' ||
  c == '{' ||
  c == '}' ||
  c == '#' ||
  c == '&' ||
  c == '*' ||
  c == '!' ||
  c == '|' ||
  c == '>' ||
  c == '\'' ||
  c == '"' ||
  c == '%' ||
  c == '@' ||
  c == '`'
}

///|
fn yaml_is_c_flow_indicator(c : Int32) -> Bool {
  c == ',' || c == '[' || c == ']' || c == '{' || c == '}'
}

///|
fn yaml_is_plain_safe_in_block(c : Int32) -> Bool {
  yaml_is_ns_char(c)
}

///|
fn yaml_is_plain_safe_in_flow(c : Int32) -> Bool {
  yaml_is_ns_char(c) && !yaml_is_c_flow_indicator(c)
}

///|
fn yaml_is_ns_uri_char(c : Int32) -> Bool {
  yaml_is_ns_word_char(c) ||
  c == '#' ||
  c == ';' ||
  c == '/' ||
  c == '?' ||
  c == ':' ||
  c == '@' ||
  c == '&' ||
  c == '=' ||
  c == '+' ||
  c == '$' ||
  c == ',' ||
  c == '_' ||
  c == '.' ||
  c == '!' ||
  c == '~' ||
  c == '*' ||
  c == '\'' ||
  c == '(' ||
  c == ')' ||
  c == '[' ||
  c == ']'
}

///|
fn yaml_is_ns_tag_char(c : Int32) -> Bool {
  yaml_is_ns_word_char(c) ||
  c == '#' ||
  c == ';' ||
  c == '/' ||
  c == '?' ||
  c == ':' ||
  c == '@' ||
  c == '&' ||
  c == '=' ||
  c == '+' ||
  c == '$' ||
  c == '_' ||
  c == '.' ||
  c == '~' ||
  c == '*' ||
  c == '\'' ||
  c == '(' ||
  c == ')'
}

///|
fn yaml_is_ns_anchor_char(c : Int32) -> Bool {
  yaml_is_ns_char(c) && !yaml_is_c_flow_indicator(c)
}

///|
fn YamlScanner::scn_uri_esc(
  self : YamlScanner,
  lexer : @runtime.Lexer,
) -> Int32 {
  if lexer.lookahead != '%' {
    return YAML_SCN_STOP
  }
  self.mrk_end(lexer)
  self.adv(lexer)
  if !yaml_is_ns_hex_digit(lexer.lookahead) {
    return YAML_SCN_FAIL
  }
  self.adv(lexer)
  if !yaml_is_ns_hex_digit(lexer.lookahead) {
    return YAML_SCN_FAIL
  }
  self.adv(lexer)
  YAML_SCN_SUCC
}

///|
fn YamlScanner::scn_ns_uri_char(
  self : YamlScanner,
  lexer : @runtime.Lexer,
) -> Int32 {
  if yaml_is_ns_uri_char(lexer.lookahead) {
    self.adv(lexer)
    return YAML_SCN_SUCC
  }
  self.scn_uri_esc(lexer)
}

///|
fn YamlScanner::scn_ns_tag_char(
  self : YamlScanner,
  lexer : @runtime.Lexer,
) -> Int32 {
  if yaml_is_ns_tag_char(lexer.lookahead) {
    self.adv(lexer)
    return YAML_SCN_SUCC
  }
  self.scn_uri_esc(lexer)
}

///|
fn YamlScanner::scn_dir_bgn(self : YamlScanner, lexer : @runtime.Lexer) -> Bool {
  self.adv(lexer)
  if lexer.lookahead == 'Y' {
    self.adv(lexer)
    if lexer.lookahead == 'A' {
      self.adv(lexer)
      if lexer.lookahead == 'M' {
        self.adv(lexer)
        if lexer.lookahead == 'L' {
          self.adv(lexer)
          if yaml_is_wht(lexer.lookahead) {
            self.mrk_end(lexer)
            return self.ret_sym(lexer, YAML_S_DIR_YML_BGN)
          }
        }
      }
    }
  } else if lexer.lookahead == 'T' {
    self.adv(lexer)
    if lexer.lookahead == 'A' {
      self.adv(lexer)
      if lexer.lookahead == 'G' {
        self.adv(lexer)
        if yaml_is_wht(lexer.lookahead) {
          self.mrk_end(lexer)
          return self.ret_sym(lexer, YAML_S_DIR_TAG_BGN)
        }
      }
    }
  }
  for ;; {
    if !yaml_is_ns_char(lexer.lookahead) {
      break
    }
    self.adv(lexer)
  }
  if self.cur_col > 1 && yaml_is_wht(lexer.lookahead) {
    self.mrk_end(lexer)
    return self.ret_sym(lexer, YAML_S_DIR_RSV_BGN)
  }
  false
}

///|
fn YamlScanner::scn_dir_yml_ver(
  self : YamlScanner,
  lexer : @runtime.Lexer,
  result_symbol : Int32,
) -> Bool {
  // `uint16_t n1, n2`.
  let mut n1 = 0
  let mut n2 = 0
  while yaml_is_ns_dec_digit(lexer.lookahead) {
    self.adv(lexer)
    n1 = (n1 + 1) & 0xFFFF
  }
  if lexer.lookahead != '.' {
    return false
  }
  self.adv(lexer)
  while yaml_is_ns_dec_digit(lexer.lookahead) {
    self.adv(lexer)
    n2 = (n2 + 1) & 0xFFFF
  }
  if n1 == 0 || n2 == 0 {
    return false
  }
  self.mrk_end(lexer)
  self.ret_sym(lexer, result_symbol)
}

///|
fn YamlScanner::scn_tag_hdl_tal(
  self : YamlScanner,
  lexer : @runtime.Lexer,
) -> Bool {
  if lexer.lookahead == '!' {
    self.adv(lexer)
    return true
  }
  // `uint16_t n`.
  let mut n = 0
  while yaml_is_ns_word_char(lexer.lookahead) {
    self.adv(lexer)
    n = (n + 1) & 0xFFFF
  }
  if n == 0 {
    return true
  }
  if lexer.lookahead == '!' {
    self.adv(lexer)
    return true
  }
  false
}

///|
fn YamlScanner::scn_dir_tag_hdl(
  self : YamlScanner,
  lexer : @runtime.Lexer,
  result_symbol : Int32,
) -> Bool {
  if lexer.lookahead == '!' {
    self.adv(lexer)
    if self.scn_tag_hdl_tal(lexer) {
      self.mrk_end(lexer)
      return self.ret_sym(lexer, result_symbol)
    }
  }
  false
}

///|
fn YamlScanner::scn_dir_tag_pfx(
  self : YamlScanner,
  lexer : @runtime.Lexer,
  result_symbol : Int32,
) -> Bool {
  if lexer.lookahead == '!' {
    self.adv(lexer)
  } else if self.scn_ns_tag_char(lexer) == YAML_SCN_SUCC {
    ()
  } else {
    return false
  }
  for ;; {
    match self.scn_ns_uri_char(lexer) {
      YAML_SCN_STOP => {
        self.mrk_end(lexer)
        // fall through to SCN_FAIL
        return self.ret_sym(lexer, result_symbol)
      }
      YAML_SCN_FAIL => return self.ret_sym(lexer, result_symbol)
      _ => ()
    }
  }
}

///|
fn YamlScanner::scn_dir_rsv_prm(
  self : YamlScanner,
  lexer : @runtime.Lexer,
  result_symbol : Int32,
) -> Bool {
  if !yaml_is_ns_char(lexer.lookahead) {
    return false
  }
  self.adv(lexer)
  while yaml_is_ns_char(lexer.lookahead) {
    self.adv(lexer)
  }
  self.mrk_end(lexer)
  self.ret_sym(lexer, result_symbol)
}

///|
fn YamlScanner::scn_tag(
  self : YamlScanner,
  lexer : @runtime.Lexer,
  result_symbol : Int32,
) -> Bool {
  if lexer.lookahead != '!' {
    return false
  }
  self.adv(lexer)
  if yaml_is_wht(lexer.lookahead) {
    self.mrk_end(lexer)
    return self.ret_sym(lexer, result_symbol)
  }
  if lexer.lookahead == '<' {
    self.adv(lexer)
    if self.scn_ns_uri_char(lexer) != YAML_SCN_SUCC {
      return false
    }
    for ;; {
      match self.scn_ns_uri_char(lexer) {
        YAML_SCN_STOP => {
          if lexer.lookahead == '>' {
            self.adv(lexer)
            self.mrk_end(lexer)
            return self.ret_sym(lexer, result_symbol)
          }
          // fall through to SCN_FAIL
          return false
        }
        YAML_SCN_FAIL => return false
        _ => ()
      }
    }
  } else {
    if self.scn_tag_hdl_tal(lexer) &&
      self.scn_ns_tag_char(lexer) != YAML_SCN_SUCC {
      return false
    }
    for ;; {
      match self.scn_ns_tag_char(lexer) {
        YAML_SCN_STOP => {
          self.mrk_end(lexer)
          // fall through to SCN_FAIL
          return self.ret_sym(lexer, result_symbol)
        }
        YAML_SCN_FAIL => return self.ret_sym(lexer, result_symbol)
        _ => ()
      }
    }
  }
}

///|
fn YamlScanner::scn_acr_bgn(
  self : YamlScanner,
  lexer : @runtime.Lexer,
  result_symbol : Int32,
) -> Bool {
  if lexer.lookahead != '&' {
    return false
  }
  self.adv(lexer)
  if !yaml_is_ns_anchor_char(lexer.lookahead) {
    return false
  }
  self.mrk_end(lexer)
  self.ret_sym(lexer, result_symbol)
}

///|
fn YamlScanner::scn_acr_ctn(
  self : YamlScanner,
  lexer : @runtime.Lexer,
  result_symbol : Int32,
) -> Bool {
  while yaml_is_ns_anchor_char(lexer.lookahead) {
    self.adv(lexer)
  }
  self.mrk_end(lexer)
  self.ret_sym(lexer, result_symbol)
}

///|
fn YamlScanner::scn_als_bgn(
  self : YamlScanner,
  lexer : @runtime.Lexer,
  result_symbol : Int32,
) -> Bool {
  if lexer.lookahead != '*' {
    return false
  }
  self.adv(lexer)
  if !yaml_is_ns_anchor_char(lexer.lookahead) {
    return false
  }
  self.mrk_end(lexer)
  self.ret_sym(lexer, result_symbol)
}

///|
fn YamlScanner::scn_als_ctn(
  self : YamlScanner,
  lexer : @runtime.Lexer,
  result_symbol : Int32,
) -> Bool {
  while yaml_is_ns_anchor_char(lexer.lookahead) {
    self.adv(lexer)
  }
  self.mrk_end(lexer)
  self.ret_sym(lexer, result_symbol)
}

///|
fn YamlScanner::scn_dqt_esc_seq(
  self : YamlScanner,
  lexer : @runtime.Lexer,
  result_symbol : Int32,
) -> Bool {
  match lexer.lookahead {
    '0'
    | 'a'
    | 'b'
    | 't'
    | '\t'
    | 'n'
    | 'v'
    | 'r'
    | 'e'
    | 'f'
    | ' '
    | '"'
    | '/'
    | '\\'
    | 'N'
    | '_'
    | 'L'
    | 'P' => self.adv(lexer)
    'U' => {
      self.adv(lexer)
      for _ in 0..<8 {
        if yaml_is_ns_hex_digit(lexer.lookahead) {
          self.adv(lexer)
        } else {
          return false
        }
      }
    }
    'u' => {
      self.adv(lexer)
      for _ in 0..<4 {
        if yaml_is_ns_hex_digit(lexer.lookahead) {
          self.adv(lexer)
        } else {
          return false
        }
      }
    }
    'x' => {
      self.adv(lexer)
      for _ in 0..<2 {
        if yaml_is_ns_hex_digit(lexer.lookahead) {
          self.adv(lexer)
        } else {
          return false
        }
      }
    }
    _ => return false
  }
  self.mrk_end(lexer)
  self.ret_sym(lexer, result_symbol)
}

///|
fn YamlScanner::scn_drs_doc_end(
  self : YamlScanner,
  lexer : @runtime.Lexer,
) -> Bool {
  if lexer.lookahead != '-' && lexer.lookahead != '.' {
    return false
  }
  let delimeter = lexer.lookahead
  self.adv(lexer)
  if lexer.lookahead == delimeter {
    self.adv(lexer)
    if lexer.lookahead == delimeter {
      self.adv(lexer)
      if yaml_is_wht(lexer.lookahead) {
        return true
      }
    }
  }
  self.mrk_end(lexer)
  false
}

///|
fn YamlScanner::scn_dqt_str_cnt(
  self : YamlScanner,
  lexer : @runtime.Lexer,
  result_symbol : Int32,
) -> Bool {
  if !yaml_is_nb_double_char(lexer.lookahead) {
    return false
  }
  if self.cur_col == 0 && self.scn_drs_doc_end(lexer) {
    self.mrk_end(lexer)
    return self.ret_sym(
      lexer,
      if self.cur_chr == '-' {
        YAML_S_DRS_END
      } else {
        YAML_S_DOC_END
      },
    )
  } else {
    self.adv(lexer)
  }
  while yaml_is_nb_double_char(lexer.lookahead) {
    self.adv(lexer)
  }
  self.mrk_end(lexer)
  self.ret_sym(lexer, result_symbol)
}

///|
fn YamlScanner::scn_sqt_str_cnt(
  self : YamlScanner,
  lexer : @runtime.Lexer,
  result_symbol : Int32,
) -> Bool {
  if !yaml_is_nb_single_char(lexer.lookahead) {
    return false
  }
  if self.cur_col == 0 && self.scn_drs_doc_end(lexer) {
    self.mrk_end(lexer)
    return self.ret_sym(
      lexer,
      if self.cur_chr == '-' {
        YAML_S_DRS_END
      } else {
        YAML_S_DOC_END
      },
    )
  } else {
    self.adv(lexer)
  }
  while yaml_is_nb_single_char(lexer.lookahead) {
    self.adv(lexer)
  }
  self.mrk_end(lexer)
  self.ret_sym(lexer, result_symbol)
}

///|
fn YamlScanner::scn_blk_str_bgn(
  self : YamlScanner,
  lexer : @runtime.Lexer,
  result_symbol : Int32,
) -> Bool {
  if lexer.lookahead != '|' && lexer.lookahead != '>' {
    return false
  }
  self.adv(lexer)
  let cur_ind = self.ind_len_stk[self.ind_len_stk.length() - 1]
  // `int16_t ind`.
  let mut ind = -1
  if lexer.lookahead >= '1' && lexer.lookahead <= '9' {
    ind = yaml_i16(lexer.lookahead - '1')
    self.adv(lexer)
    if lexer.lookahead == '+' || lexer.lookahead == '-' {
      self.adv(lexer)
    }
  } else if lexer.lookahead == '+' || lexer.lookahead == '-' {
    self.adv(lexer)
    if lexer.lookahead >= '1' && lexer.lookahead <= '9' {
      ind = yaml_i16(lexer.lookahead - '1')
      self.adv(lexer)
    }
  }
  if !yaml_is_wht(lexer.lookahead) {
    return false
  }
  self.mrk_end(lexer)
  if ind != -1 {
    ind = yaml_i16(ind + cur_ind)
  } else {
    ind = cur_ind
    while yaml_is_wsp(lexer.lookahead) {
      self.adv(lexer)
    }
    if lexer.lookahead == '#' {
      self.adv(lexer)
      while !yaml_is_nwl(lexer.lookahead) && lexer.lookahead != 0 {
        self.adv(lexer)
      }
    }
    if yaml_is_nwl(lexer.lookahead) {
      self.adv_nwl(lexer)
    }
    while lexer.lookahead != 0 {
      if lexer.lookahead == ' ' {
        self.adv(lexer)
      } else if yaml_is_nwl(lexer.lookahead) {
        if self.cur_col - 1 < ind {
          break
        }
        ind = yaml_i16(self.cur_col - 1)
        self.adv_nwl(lexer)
      } else {
        if self.cur_col - 1 > ind {
          ind = yaml_i16(self.cur_col - 1)
        }
        break
      }
    }
  }
  self.push_ind(YAML_IND_STR, ind)
  self.ret_sym(lexer, result_symbol)
}

///|
fn YamlScanner::scn_blk_str_cnt(
  self : YamlScanner,
  lexer : @runtime.Lexer,
  result_symbol : Int32,
) -> Bool {
  if !yaml_is_ns_char(lexer.lookahead) {
    return false
  }
  if self.cur_col == 0 && self.scn_drs_doc_end(lexer) {
    if !self.pop_ind_checked() {
      return false
    }
    return self.ret_sym(lexer, YAML_BL)
  } else {
    self.adv(lexer)
  }
  self.mrk_end(lexer)
  for ;; {
    if yaml_is_ns_char(lexer.lookahead) {
      self.adv(lexer)
      while yaml_is_ns_char(lexer.lookahead) {
        self.adv(lexer)
      }
      self.mrk_end(lexer)
    }
    if yaml_is_wsp(lexer.lookahead) {
      self.adv(lexer)
      while yaml_is_wsp(lexer.lookahead) {
        self.adv(lexer)
      }
    } else {
      break
    }
  }
  self.ret_sym(lexer, result_symbol)
}

///|
fn YamlScanner::adv_sch_stt(self : YamlScanner) -> Unit {
  self.sch_stt = self.schema.adv_sch_stt(
    self.sch_stt,
    self.cur_chr,
    self.rlt_sch,
  )
}

///|
fn YamlScanner::scn_pln_cnt(
  self : YamlScanner,
  lexer : @runtime.Lexer,
  is_plain_safe : (Int32) -> Bool,
) -> Int32 {
  let mut is_cur_wsp = yaml_is_wsp(self.cur_chr)
  let mut is_cur_saf = is_plain_safe(self.cur_chr)
  let mut is_lka_wsp = yaml_is_wsp(lexer.lookahead)
  let mut is_lka_saf = is_plain_safe(lexer.lookahead)
  if is_lka_saf || is_lka_wsp {
    for ;; {
      if is_lka_saf && lexer.lookahead != '#' && lexer.lookahead != ':' {
        self.adv(lexer)
        self.mrk_end(lexer)
        self.adv_sch_stt()
      } else if is_cur_saf && lexer.lookahead == '#' {
        self.adv(lexer)
        self.mrk_end(lexer)
        self.adv_sch_stt()
      } else if is_lka_wsp {
        self.adv(lexer)
        self.adv_sch_stt()
      } else if lexer.lookahead == ':' {
        self.adv(lexer) // check later
      } else {
        break
      }
      is_cur_wsp = is_lka_wsp
      is_cur_saf = is_lka_saf
      is_lka_wsp = yaml_is_wsp(lexer.lookahead)
      is_lka_saf = is_plain_safe(lexer.lookahead)
      if self.cur_chr == ':' {
        if is_lka_saf {
          self.mrk_end(lexer)
          self.adv_sch_stt()
        } else {
          return YAML_SCN_FAIL
        }
      }
    }
  } else {
    return YAML_SCN_STOP
  }
  ignore(is_cur_wsp)
  YAML_SCN_SUCC
}

///|
/// `SGL_PLN_SYM(POS, CTX)`, given the `POS##_SGL_PLN_*_##CTX` symbols.
fn YamlScanner::sgl_pln_sym(
  self : YamlScanner,
  nul : Int32,
  bol : Int32,
  int : Int32,
  flt : Int32,
  tms : Int32,
  str : Int32,
) -> Int32 {
  match self.rlt_sch.val {
    RsNull => nul
    RsBool => bol
    RsInt => int
    RsFloat => flt
    RsTimestamp if self.schema.has_timestamp() => tms
    _ => str
  }
}

///|
fn YamlScanner::scan(
  self : YamlScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  self.init()
  self.mrk_end(lexer)
  let allow_comment = !(valid_symbols[YAML_R_DQT_STR_CTN] ||
    valid_symbols[YAML_BR_DQT_STR_CTN] ||
    valid_symbols[YAML_R_SQT_STR_CTN] ||
    valid_symbols[YAML_BR_SQT_STR_CTN])
  // `ind_ptr` walks down `ind_len_stk`; `ind_end` is one before its start.
  let ind_ptr = self.ind_len_stk.length() - 1
  let cur_ind = self.ind_len_stk[ind_ptr]
  let prt_ind = if ind_ptr - 1 == -1 {
    -1
  } else {
    self.ind_len_stk[ind_ptr - 1]
  }
  let cur_ind_typ = self.ind_typ_stk[self.ind_typ_stk.length() - 1]
  let mut has_tab_ind = false
  // `int16_t leading_spaces`.
  let mut leading_spaces = 0
  for ;; {
    if lexer.lookahead == ' ' {
      if !has_tab_ind {
        leading_spaces = yaml_i16(leading_spaces + 1)
      }
      self.skp(lexer)
    } else if lexer.lookahead == '\t' {
      has_tab_ind = true
      self.skp(lexer)
    } else if yaml_is_nwl(lexer.lookahead) {
      has_tab_ind = false
      leading_spaces = 0
      self.skp_nwl(lexer)
    } else if allow_comment && lexer.lookahead == '#' {
      if valid_symbols[YAML_BR_BLK_STR_CTN] &&
        valid_symbols[YAML_BL] &&
        self.cur_col <= cur_ind {
        if !self.pop_ind_checked() {
          return false
        }
        return self.ret_sym(lexer, YAML_BL)
      }
      if (if valid_symbols[YAML_BR_BLK_STR_CTN] {
          self.cur_row == self.row
        } else {
          self.cur_col == 0 ||
          self.cur_row != self.row ||
          self.cur_col > self.col
        }) {
        self.adv(lexer)
        while !yaml_is_nwl(lexer.lookahead) && lexer.lookahead != 0 {
          self.adv(lexer)
        }
        self.mrk_end(lexer)
        return self.ret_sym(lexer, YAML_COMMENT)
      } else {
        break
      }
    } else {
      break
    }
  }
  if lexer.lookahead == 0 {
    if valid_symbols[YAML_BL] {
      self.mrk_end(lexer)
      if !self.pop_ind_checked() {
        return false
      }
      return self.ret_sym(lexer, YAML_BL)
    }
    if valid_symbols[YAML_END_OF_FILE] {
      self.mrk_end(lexer)
      return self.ret_sym(lexer, YAML_END_OF_FILE)
    }
    return false
  }
  let bgn_row = self.cur_row
  let bgn_col = self.cur_col
  let bgn_chr = lexer.lookahead
  if valid_symbols[YAML_BL] && bgn_col <= cur_ind && !has_tab_ind {
    if (if cur_ind == prt_ind && cur_ind_typ == YAML_IND_SEQ {
        bgn_col < cur_ind || lexer.lookahead != '-'
      } else {
        bgn_col <= prt_ind || cur_ind_typ == YAML_IND_STR
      }) {
      if !self.pop_ind_checked() {
        return false
      }
      return self.ret_sym(lexer, YAML_BL)
    }
  }
  let has_nwl = self.cur_row > self.row
  let is_r = !has_nwl
  let is_br = has_nwl && leading_spaces > cur_ind
  let is_b = has_nwl && leading_spaces == cur_ind && !has_tab_ind
  let is_s = bgn_col == 0
  // `MAY_UPD_IMP_COL()`.
  fn may_upd_imp_col() {
    if self.blk_imp_row != bgn_row {
      self.blk_imp_row = bgn_row
      self.blk_imp_col = bgn_col
      self.blk_imp_tab = if has_tab_ind { 1 } else { 0 }
    }
  }

  if valid_symbols[YAML_R_DIR_YML_VER] && is_r {
    return self.scn_dir_yml_ver(lexer, YAML_R_DIR_YML_VER)
  }
  if valid_symbols[YAML_R_DIR_TAG_HDL] && is_r {
    return self.scn_dir_tag_hdl(lexer, YAML_R_DIR_TAG_HDL)
  }
  if valid_symbols[YAML_R_DIR_TAG_PFX] && is_r {
    return self.scn_dir_tag_pfx(lexer, YAML_R_DIR_TAG_PFX)
  }
  if valid_symbols[YAML_R_DIR_RSV_PRM] && is_r {
    return self.scn_dir_rsv_prm(lexer, YAML_R_DIR_RSV_PRM)
  }
  if valid_symbols[YAML_BR_BLK_STR_CTN] &&
    is_br &&
    self.scn_blk_str_cnt(lexer, YAML_BR_BLK_STR_CTN) {
    return true
  }
  if (
      valid_symbols[YAML_R_DQT_STR_CTN] &&
      is_r &&
      self.scn_dqt_str_cnt(lexer, YAML_R_DQT_STR_CTN)
    ) ||
    (
      valid_symbols[YAML_BR_DQT_STR_CTN] &&
      is_br &&
      self.scn_dqt_str_cnt(lexer, YAML_BR_DQT_STR_CTN)
    ) {
    return true
  }
  if (
      valid_symbols[YAML_R_SQT_STR_CTN] &&
      is_r &&
      self.scn_sqt_str_cnt(lexer, YAML_R_SQT_STR_CTN)
    ) ||
    (
      valid_symbols[YAML_BR_SQT_STR_CTN] &&
      is_br &&
      self.scn_sqt_str_cnt(lexer, YAML_BR_SQT_STR_CTN)
    ) {
    return true
  }
  if valid_symbols[YAML_R_ACR_CTN] && is_r {
    return self.scn_acr_ctn(lexer, YAML_R_ACR_CTN)
  }
  if valid_symbols[YAML_R_ALS_CTN] && is_r {
    return self.scn_als_ctn(lexer, YAML_R_ALS_CTN)
  }
  if lexer.lookahead == '%' {
    if valid_symbols[YAML_S_DIR_YML_BGN] && is_s {
      return self.scn_dir_bgn(lexer)
    }
  } else if lexer.lookahead == '*' {
    if valid_symbols[YAML_R_ALS_BGN] && is_r {
      may_upd_imp_col()
      return self.scn_als_bgn(lexer, YAML_R_ALS_BGN)
    }
    if valid_symbols[YAML_BR_ALS_BGN] && is_br {
      may_upd_imp_col()
      return self.scn_als_bgn(lexer, YAML_BR_ALS_BGN)
    }
    if valid_symbols[YAML_B_ALS_BGN] && is_b {
      may_upd_imp_col()
      return self.scn_als_bgn(lexer, YAML_B_ALS_BGN)
    }
  } else if lexer.lookahead == '&' {
    if valid_symbols[YAML_R_ACR_BGN] && is_r {
      may_upd_imp_col()
      return self.scn_acr_bgn(lexer, YAML_R_ACR_BGN)
    }
    if valid_symbols[YAML_BR_ACR_BGN] && is_br {
      may_upd_imp_col()
      return self.scn_acr_bgn(lexer, YAML_BR_ACR_BGN)
    }
    if valid_symbols[YAML_B_ACR_BGN] && is_b {
      may_upd_imp_col()
      return self.scn_acr_bgn(lexer, YAML_B_ACR_BGN)
    }
  } else if lexer.lookahead == '!' {
    if valid_symbols[YAML_R_TAG] && is_r {
      may_upd_imp_col()
      return self.scn_tag(lexer, YAML_R_TAG)
    }
    if valid_symbols[YAML_BR_TAG] && is_br {
      may_upd_imp_col()
      return self.scn_tag(lexer, YAML_BR_TAG)
    }
    if valid_symbols[YAML_B_TAG] && is_b {
      may_upd_imp_col()
      return self.scn_tag(lexer, YAML_B_TAG)
    }
  } else if lexer.lookahead == '[' {
    if valid_symbols[YAML_R_FLW_SEQ_BGN] && is_r {
      may_upd_imp_col()
      self.adv(lexer)
      self.mrk_end(lexer)
      return self.ret_sym(lexer, YAML_R_FLW_SEQ_BGN)
    }
    if valid_symbols[YAML_BR_FLW_SEQ_BGN] && is_br {
      may_upd_imp_col()
      self.adv(lexer)
      self.mrk_end(lexer)
      return self.ret_sym(lexer, YAML_BR_FLW_SEQ_BGN)
    }
    if valid_symbols[YAML_B_FLW_SEQ_BGN] && is_b {
      may_upd_imp_col()
      self.adv(lexer)
      self.mrk_end(lexer)
      return self.ret_sym(lexer, YAML_B_FLW_SEQ_BGN)
    }
  } else if lexer.lookahead == ']' {
    if valid_symbols[YAML_R_FLW_SEQ_END] && is_r {
      self.adv(lexer)
      self.mrk_end(lexer)
      return self.ret_sym(lexer, YAML_R_FLW_SEQ_END)
    }
    if valid_symbols[YAML_BR_FLW_SEQ_END] && is_br {
      self.adv(lexer)
      self.mrk_end(lexer)
      return self.ret_sym(lexer, YAML_BR_FLW_SEQ_END)
    }
    if valid_symbols[YAML_B_FLW_SEQ_END] && is_b {
      self.adv(lexer)
      self.mrk_end(lexer)
      // Upstream returns BR_FLW_SEQ_END here.
      return self.ret_sym(lexer, YAML_BR_FLW_SEQ_END)
    }
  } else if lexer.lookahead == '{' {
    if valid_symbols[YAML_R_FLW_MAP_BGN] && is_r {
      may_upd_imp_col()
      self.adv(lexer)
      self.mrk_end(lexer)
      return self.ret_sym(lexer, YAML_R_FLW_MAP_BGN)
    }
    if valid_symbols[YAML_BR_FLW_MAP_BGN] && is_br {
      may_upd_imp_col()
      self.adv(lexer)
      self.mrk_end(lexer)
      return self.ret_sym(lexer, YAML_BR_FLW_MAP_BGN)
    }
    if valid_symbols[YAML_B_FLW_MAP_BGN] && is_b {
      may_upd_imp_col()
      self.adv(lexer)
      self.mrk_end(lexer)
      return self.ret_sym(lexer, YAML_B_FLW_MAP_BGN)
    }
  } else if lexer.lookahead == '}' {
    if valid_symbols[YAML_R_FLW_MAP_END] && is_r {
      self.adv(lexer)
      self.mrk_end(lexer)
      return self.ret_sym(lexer, YAML_R_FLW_MAP_END)
    }
    if valid_symbols[YAML_BR_FLW_MAP_END] && is_br {
      self.adv(lexer)
      self.mrk_end(lexer)
      return self.ret_sym(lexer, YAML_BR_FLW_MAP_END)
    }
    if valid_symbols[YAML_B_FLW_MAP_END] && is_b {
      self.adv(lexer)
      self.mrk_end(lexer)
      // Upstream returns BR_FLW_MAP_END here.
      return self.ret_sym(lexer, YAML_BR_FLW_MAP_END)
    }
  } else if lexer.lookahead == ',' {
    if valid_symbols[YAML_R_FLW_SEP_BGN] && is_r {
      self.adv(lexer)
      self.mrk_end(lexer)
      return self.ret_sym(lexer, YAML_R_FLW_SEP_BGN)
    }
    if valid_symbols[YAML_BR_FLW_SEP_BGN] && is_br {
      self.adv(lexer)
      self.mrk_end(lexer)
      return self.ret_sym(lexer, YAML_BR_FLW_SEP_BGN)
    }
  } else if lexer.lookahead == '"' {
    if valid_symbols[YAML_R_DQT_STR_BGN] && is_r {
      may_upd_imp_col()
      self.adv(lexer)
      self.mrk_end(lexer)
      return self.ret_sym(lexer, YAML_R_DQT_STR_BGN)
    }
    if valid_symbols[YAML_BR_DQT_STR_BGN] && is_br {
      may_upd_imp_col()
      self.adv(lexer)
      self.mrk_end(lexer)
      return self.ret_sym(lexer, YAML_BR_DQT_STR_BGN)
    }
    if valid_symbols[YAML_B_DQT_STR_BGN] && is_b {
      may_upd_imp_col()
      self.adv(lexer)
      self.mrk_end(lexer)
      return self.ret_sym(lexer, YAML_B_DQT_STR_BGN)
    }
    if valid_symbols[YAML_R_DQT_STR_END] && is_r {
      self.adv(lexer)
      self.mrk_end(lexer)
      return self.ret_sym(lexer, YAML_R_DQT_STR_END)
    }
    if valid_symbols[YAML_BR_DQT_STR_END] && is_br {
      self.adv(lexer)
      self.mrk_end(lexer)
      return self.ret_sym(lexer, YAML_BR_DQT_STR_END)
    }
  } else if lexer.lookahead == '\'' {
    if valid_symbols[YAML_R_SQT_STR_BGN] && is_r {
      may_upd_imp_col()
      self.adv(lexer)
      self.mrk_end(lexer)
      return self.ret_sym(lexer, YAML_R_SQT_STR_BGN)
    }
    if valid_symbols[YAML_BR_SQT_STR_BGN] && is_br {
      may_upd_imp_col()
      self.adv(lexer)
      self.mrk_end(lexer)
      return self.ret_sym(lexer, YAML_BR_SQT_STR_BGN)
    }
    if valid_symbols[YAML_B_SQT_STR_BGN] && is_b {
      may_upd_imp_col()
      self.adv(lexer)
      self.mrk_end(lexer)
      return self.ret_sym(lexer, YAML_B_SQT_STR_BGN)
    }
    if valid_symbols[YAML_R_SQT_STR_END] && is_r {
      self.adv(lexer)
      if lexer.lookahead == '\'' {
        self.adv(lexer)
        self.mrk_end(lexer)
        return self.ret_sym(lexer, YAML_R_SQT_ESC_SQT)
      } else {
        self.mrk_end(lexer)
        return self.ret_sym(lexer, YAML_R_SQT_STR_END)
      }
    }
    if valid_symbols[YAML_BR_SQT_STR_END] && is_br {
      self.adv(lexer)
      if lexer.lookahead == '\'' {
        self.adv(lexer)
        self.mrk_end(lexer)
        return self.ret_sym(lexer, YAML_BR_SQT_ESC_SQT)
      } else {
        self.mrk_end(lexer)
        return self.ret_sym(lexer, YAML_BR_SQT_STR_END)
      }
    }
  } else if lexer.lookahead == '?' {
    let is_r_blk_key_bgn = valid_symbols[YAML_R_BLK_KEY_BGN] && is_r
    let is_br_blk_key_bgn = valid_symbols[YAML_BR_BLK_KEY_BGN] && is_br
    let is_b_blk_key_bgn = valid_symbols[YAML_B_BLK_KEY_BGN] && is_b
    let is_r_flw_key_bgn = valid_symbols[YAML_R_FLW_KEY_BGN] && is_r
    let is_br_flw_key_bgn = valid_symbols[YAML_BR_FLW_KEY_BGN] && is_br
    if is_r_blk_key_bgn ||
      is_br_blk_key_bgn ||
      is_b_blk_key_bgn ||
      is_r_flw_key_bgn ||
      is_br_flw_key_bgn {
      self.adv(lexer)
      if yaml_is_wht(lexer.lookahead) {
        self.mrk_end(lexer)
        if is_r_blk_key_bgn {
          // `PUSH_BGN_IND(IND_MAP)`.
          if has_tab_ind {
            return false
          }
          self.push_ind(YAML_IND_MAP, bgn_col)
          return self.ret_sym(lexer, YAML_R_BLK_KEY_BGN)
        }
        if is_br_blk_key_bgn {
          if has_tab_ind {
            return false
          }
          self.push_ind(YAML_IND_MAP, bgn_col)
          return self.ret_sym(lexer, YAML_BR_BLK_KEY_BGN)
        }
        if is_b_blk_key_bgn {
          return self.ret_sym(lexer, YAML_B_BLK_KEY_BGN)
        }
        if is_r_flw_key_bgn {
          return self.ret_sym(lexer, YAML_R_FLW_KEY_BGN)
        }
        if is_br_flw_key_bgn {
          return self.ret_sym(lexer, YAML_BR_FLW_KEY_BGN)
        }
      }
    }
  } else if lexer.lookahead == ':' {
    if valid_symbols[YAML_R_FLW_JSV_BGN] && is_r {
      self.adv(lexer)
      self.mrk_end(lexer)
      return self.ret_sym(lexer, YAML_R_FLW_JSV_BGN)
    }
    if valid_symbols[YAML_BR_FLW_JSV_BGN] && is_br {
      self.adv(lexer)
      self.mrk_end(lexer)
      return self.ret_sym(lexer, YAML_BR_FLW_JSV_BGN)
    }
    let is_r_blk_val_bgn = valid_symbols[YAML_R_BLK_VAL_BGN] && is_r
    let is_br_blk_val_bgn = valid_symbols[YAML_BR_BLK_VAL_BGN] && is_br
    let is_b_blk_val_bgn = valid_symbols[YAML_B_BLK_VAL_BGN] && is_b
    let is_r_blk_imp_bgn = valid_symbols[YAML_R_BLK_IMP_BGN] && is_r
    let is_r_flw_njv_bgn = valid_symbols[YAML_R_FLW_NJV_BGN] && is_r
    let is_br_flw_njv_bgn = valid_symbols[YAML_BR_FLW_NJV_BGN] && is_br
    if is_r_blk_val_bgn ||
      is_br_blk_val_bgn ||
      is_b_blk_val_bgn ||
      is_r_blk_imp_bgn ||
      is_r_flw_njv_bgn ||
      is_br_flw_njv_bgn {
      self.adv(lexer)
      let is_lka_wht = yaml_is_wht(lexer.lookahead)
      if is_lka_wht {
        if is_r_blk_val_bgn {
          if has_tab_ind {
            return false
          }
          self.push_ind(YAML_IND_MAP, bgn_col)
          self.mrk_end(lexer)
          return self.ret_sym(lexer, YAML_R_BLK_VAL_BGN)
        }
        if is_br_blk_val_bgn {
          if has_tab_ind {
            return false
          }
          self.push_ind(YAML_IND_MAP, bgn_col)
          self.mrk_end(lexer)
          return self.ret_sym(lexer, YAML_BR_BLK_VAL_BGN)
        }
        if is_b_blk_val_bgn {
          self.mrk_end(lexer)
          return self.ret_sym(lexer, YAML_B_BLK_VAL_BGN)
        }
        if is_r_blk_imp_bgn {
          // `MAY_PUSH_IMP_IND()`.
          if cur_ind != self.blk_imp_col {
            if self.blk_imp_tab != 0 {
              return false
            }
            self.push_ind(YAML_IND_MAP, self.blk_imp_col)
          }
          self.mrk_end(lexer)
          return self.ret_sym(lexer, YAML_R_BLK_IMP_BGN)
        }
      }
      if is_lka_wht ||
        lexer.lookahead == ',' ||
        lexer.lookahead == ']' ||
        lexer.lookahead == '}' {
        if is_r_flw_njv_bgn {
          self.mrk_end(lexer)
          return self.ret_sym(lexer, YAML_R_FLW_NJV_BGN)
        }
        if is_br_flw_njv_bgn {
          self.mrk_end(lexer)
          return self.ret_sym(lexer, YAML_BR_FLW_NJV_BGN)
        }
      }
    }
  } else if lexer.lookahead == '-' {
    let is_r_blk_seq_bgn = valid_symbols[YAML_R_BLK_SEQ_BGN] && is_r
    let is_br_blk_seq_bgn = valid_symbols[YAML_BR_BLK_SEQ_BGN] && is_br
    let is_b_blk_seq_bgn = valid_symbols[YAML_B_BLK_SEQ_BGN] && is_b
    let is_s_drs_end = is_s
    if is_r_blk_seq_bgn || is_br_blk_seq_bgn || is_b_blk_seq_bgn || is_s_drs_end {
      self.adv(lexer)
      if yaml_is_wht(lexer.lookahead) {
        if is_r_blk_seq_bgn {
          if has_tab_ind {
            return false
          }
          self.push_ind(YAML_IND_SEQ, bgn_col)
          self.mrk_end(lexer)
          return self.ret_sym(lexer, YAML_R_BLK_SEQ_BGN)
        }
        if is_br_blk_seq_bgn {
          if has_tab_ind {
            return false
          }
          self.push_ind(YAML_IND_SEQ, bgn_col)
          self.mrk_end(lexer)
          return self.ret_sym(lexer, YAML_BR_BLK_SEQ_BGN)
        }
        if is_b_blk_seq_bgn {
          // `MAY_PUSH_SPC_SEQ_IND()`.
          if cur_ind_typ == YAML_IND_MAP {
            self.push_ind(YAML_IND_SEQ, bgn_col)
          }
          self.mrk_end(lexer)
          return self.ret_sym(lexer, YAML_B_BLK_SEQ_BGN)
        }
      } else if lexer.lookahead == '-' && is_s_drs_end {
        self.adv(lexer)
        if lexer.lookahead == '-' {
          self.adv(lexer)
          if yaml_is_wht(lexer.lookahead) {
            if valid_symbols[YAML_BL] {
              if !self.pop_ind_checked() {
                return false
              }
              return self.ret_sym(lexer, YAML_BL)
            }
            self.mrk_end(lexer)
            return self.ret_sym(lexer, YAML_S_DRS_END)
          }
        }
      }
    }
  } else if lexer.lookahead == '.' {
    if is_s {
      self.adv(lexer)
      if lexer.lookahead == '.' {
        self.adv(lexer)
        if lexer.lookahead == '.' {
          self.adv(lexer)
          if yaml_is_wht(lexer.lookahead) {
            if valid_symbols[YAML_BL] {
              if !self.pop_ind_checked() {
                return false
              }
              return self.ret_sym(lexer, YAML_BL)
            }
            self.mrk_end(lexer)
            return self.ret_sym(lexer, YAML_S_DOC_END)
          }
        }
      }
    }
  } else if lexer.lookahead == '\\' {
    let is_r_dqt_esc_nwl = valid_symbols[YAML_R_DQT_ESC_NWL] && is_r
    let is_br_dqt_esc_nwl = valid_symbols[YAML_BR_DQT_ESC_NWL] && is_br
    let is_r_dqt_esc_seq = valid_symbols[YAML_R_DQT_ESC_SEQ] && is_r
    let is_br_dqt_esc_seq = valid_symbols[YAML_BR_DQT_ESC_SEQ] && is_br
    if is_r_dqt_esc_nwl ||
      is_br_dqt_esc_nwl ||
      is_r_dqt_esc_seq ||
      is_br_dqt_esc_seq {
      self.adv(lexer)
      if yaml_is_nwl(lexer.lookahead) {
        if is_r_dqt_esc_nwl {
          self.mrk_end(lexer)
          return self.ret_sym(lexer, YAML_R_DQT_ESC_NWL)
        }
        if is_br_dqt_esc_nwl {
          self.mrk_end(lexer)
          return self.ret_sym(lexer, YAML_BR_DQT_ESC_NWL)
        }
      }
      if is_r_dqt_esc_seq {
        return self.scn_dqt_esc_seq(lexer, YAML_R_DQT_ESC_SEQ)
      }
      if is_br_dqt_esc_seq {
        return self.scn_dqt_esc_seq(lexer, YAML_BR_DQT_ESC_SEQ)
      }
      return false
    }
  } else if lexer.lookahead == '|' {
    if valid_symbols[YAML_R_BLK_LIT_BGN] && is_r {
      return self.scn_blk_str_bgn(lexer, YAML_R_BLK_LIT_BGN)
    }
    if valid_symbols[YAML_BR_BLK_LIT_BGN] && is_br {
      return self.scn_blk_str_bgn(lexer, YAML_BR_BLK_LIT_BGN)
    }
  } else if lexer.lookahead == '>' {
    if valid_symbols[YAML_R_BLK_FLD_BGN] && is_r {
      return self.scn_blk_str_bgn(lexer, YAML_R_BLK_FLD_BGN)
    }
    if valid_symbols[YAML_BR_BLK_FLD_BGN] && is_br {
      return self.scn_blk_str_bgn(lexer, YAML_BR_BLK_FLD_BGN)
    }
  }
  let maybe_sgl_pln_blk = (valid_symbols[YAML_R_SGL_PLN_STR_BLK] && is_r) ||
    (valid_symbols[YAML_BR_SGL_PLN_STR_BLK] && is_br) ||
    (valid_symbols[YAML_B_SGL_PLN_STR_BLK] && is_b)
  let maybe_sgl_pln_flw = (valid_symbols[YAML_R_SGL_PLN_STR_FLW] && is_r) ||
    (valid_symbols[YAML_BR_SGL_PLN_STR_FLW] && is_br)
  let maybe_mtl_pln_blk = (valid_symbols[YAML_R_MTL_PLN_STR_BLK] && is_r) ||
    (valid_symbols[YAML_BR_MTL_PLN_STR_BLK] && is_br)
  let maybe_mtl_pln_flw = (valid_symbols[YAML_R_MTL_PLN_STR_FLW] && is_r) ||
    (valid_symbols[YAML_BR_MTL_PLN_STR_FLW] && is_br)
  if maybe_sgl_pln_blk ||
    maybe_sgl_pln_flw ||
    maybe_mtl_pln_blk ||
    maybe_mtl_pln_flw {
    let is_in_blk = maybe_sgl_pln_blk || maybe_mtl_pln_blk
    let is_plain_safe : (Int32) -> Bool = if is_in_blk {
      yaml_is_plain_safe_in_block
    } else {
      yaml_is_plain_safe_in_flow
    }
    if self.cur_col - bgn_col == 0 {
      self.adv(lexer)
    }
    if self.cur_col - bgn_col == 1 {
      let is_plain_first = (
          yaml_is_ns_char(bgn_chr) && !yaml_is_c_indicator(bgn_chr)
        ) ||
        (
          (bgn_chr == '-' || bgn_chr == '?' || bgn_chr == ':') &&
          is_plain_safe(lexer.lookahead)
        )
      if !is_plain_first {
        return false
      }
      self.adv_sch_stt()
    } else {
      // no need to check the following cases:
      // ..X
      // ...X
      // --X
      // ---X
      // X: lookahead
      self.sch_stt = YAML_SCH_STT_FRZ // must be RS_STR
    }
    self.mrk_end(lexer)
    for ;; {
      if !yaml_is_nwl(lexer.lookahead) {
        if self.scn_pln_cnt(lexer, is_plain_safe) != YAML_SCN_SUCC {
          break
        }
      }
      if lexer.lookahead == 0 || !yaml_is_nwl(lexer.lookahead) {
        break
      }
      for ;; {
        if yaml_is_nwl(lexer.lookahead) {
          self.adv_nwl(lexer)
        } else if yaml_is_wsp(lexer.lookahead) {
          self.adv(lexer)
        } else {
          break
        }
      }
      if lexer.lookahead == 0 || self.cur_col <= cur_ind {
        break
      }
      if self.cur_col == 0 && self.scn_drs_doc_end(lexer) {
        break
      }
    }
    if self.end_row == bgn_row {
      if maybe_sgl_pln_blk {
        may_upd_imp_col()
        return self.ret_sym(
          lexer,
          if is_r {
            self.sgl_pln_sym(
              YAML_R_SGL_PLN_NUL_BLK,
              YAML_R_SGL_PLN_BOL_BLK,
              YAML_R_SGL_PLN_INT_BLK,
              YAML_R_SGL_PLN_FLT_BLK,
              YAML_R_SGL_PLN_TMS_BLK,
              YAML_R_SGL_PLN_STR_BLK,
            )
          } else if is_br {
            self.sgl_pln_sym(
              YAML_BR_SGL_PLN_NUL_BLK,
              YAML_BR_SGL_PLN_BOL_BLK,
              YAML_BR_SGL_PLN_INT_BLK,
              YAML_BR_SGL_PLN_FLT_BLK,
              YAML_BR_SGL_PLN_TMS_BLK,
              YAML_BR_SGL_PLN_STR_BLK,
            )
          } else {
            self.sgl_pln_sym(
              YAML_B_SGL_PLN_NUL_BLK,
              YAML_B_SGL_PLN_BOL_BLK,
              YAML_B_SGL_PLN_INT_BLK,
              YAML_B_SGL_PLN_FLT_BLK,
              YAML_B_SGL_PLN_TMS_BLK,
              YAML_B_SGL_PLN_STR_BLK,
            )
          },
        )
      }
      if maybe_sgl_pln_flw {
        return self.ret_sym(
          lexer,
          if is_r {
            self.sgl_pln_sym(
              YAML_R_SGL_PLN_NUL_FLW,
              YAML_R_SGL_PLN_BOL_FLW,
              YAML_R_SGL_PLN_INT_FLW,
              YAML_R_SGL_PLN_FLT_FLW,
              YAML_R_SGL_PLN_TMS_FLW,
              YAML_R_SGL_PLN_STR_FLW,
            )
          } else {
            self.sgl_pln_sym(
              YAML_BR_SGL_PLN_NUL_FLW,
              YAML_BR_SGL_PLN_BOL_FLW,
              YAML_BR_SGL_PLN_INT_FLW,
              YAML_BR_SGL_PLN_FLT_FLW,
              YAML_BR_SGL_PLN_TMS_FLW,
              YAML_BR_SGL_PLN_STR_FLW,
            )
          },
        )
      }
    } else {
      if maybe_mtl_pln_blk {
        may_upd_imp_col()
        return self.ret_sym(
          lexer,
          if is_r {
            YAML_R_MTL_PLN_STR_BLK
          } else {
            YAML_BR_MTL_PLN_STR_BLK
          },
        )
      }
      if maybe_mtl_pln_flw {
        return self.ret_sym(
          lexer,
          if is_r {
            YAML_R_MTL_PLN_STR_FLW
          } else {
            YAML_BR_MTL_PLN_STR_FLW
          },
        )
      }
    }
    return false
  }
  !valid_symbols[YAML_ERR_REC]
}

///|
/// The YAML external scanner with the core schema (`scanner_for("yaml")`).
fn yaml_scanner() -> @runtime.ExternalScanner {
  yaml_scanner_create(Core)
}

///|
/// The factory of the YAML external scanner built with `schema`, the
/// equivalent of compiling tree-sitter-yaml's scanner.c with
/// `-DYAML_SCHEMA=core|json|legacy`. `scanner_for("yaml")` uses `Core`, the
/// upstream default.
pub fn yaml_scanner_with_schema(
  schema : YamlSchema,
) -> @runtime.ExternalScannerFactory {
  () => yaml_scanner_create(schema)
}

///|
fn yaml_scanner_create(schema : YamlSchema) -> @runtime.ExternalScanner {
  // `ts_calloc`: every field starts at zero.
  let scanner : YamlScanner = {
    row: 0,
    col: 0,
    blk_imp_row: 0,
    blk_imp_col: 0,
    blk_imp_tab: 0,
    ind_typ_stk: [],
    ind_len_stk: [],
    end_row: 0,
    end_col: 0,
    cur_row: 0,
    cur_col: 0,
    cur_chr: 0,
    sch_stt: 0,
    rlt_sch: Ref(RsStr),
    schema,
  }
  scanner.deserialize(b""[:])
  {
    scan: (lexer, valid_symbols) => scanner.scan(lexer, valid_symbols),
    serialize: buffer => scanner.serialize(buffer),
    deserialize: buffer => scanner.deserialize(buffer),
    destroy: () => {
      scanner.ind_len_stk.clear()
      scanner.ind_typ_stk.clear()
    },
  }
}
