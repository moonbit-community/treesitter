///|
/// The node a plain scalar gets under `schema`: run `adv_sch_stt` over its
/// characters as the scanner does, then `SGL_PLN_SYM`.
fn yaml_plain_scalar_kind(schema : YamlSchema, text : String) -> String {
  let state : YamlScanner = {
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
  for c in text {
    state.cur_chr = c.to_int()
    state.adv_sch_stt()
  }
  let kinds = ["null", "boolean", "integer", "float", "timestamp", "string"]
  kinds[state.sgl_pln_sym(0, 1, 2, 3, 4, 5)]
}

///|
test "yaml schemas (YAML_SCHEMA=core|json|legacy)" {
  // Expected: the value node of `flag: <text>` parsed with scanner.c
  // compiled with -DYAML_SCHEMA=core, json and legacy.
  let cases = [
    "yes", "True", "true", "~", "null", "0o17", "0x1F", "1_000", ".inf", "2001-12-14",
  ]
  let table = [Core, Json, Legacy].map(schema => {
    cases
    .map(text => "\{text}=\{yaml_plain_scalar_kind(schema, text)}")
    .join(" ")
  })
  inspect(
    table.join("\n"),
    content=(
      #|yes=string True=boolean true=boolean ~=null null=null 0o17=integer 0x1F=integer 1_000=string .inf=float 2001-12-14=string
      #|yes=string True=string true=boolean ~=string null=null 0o17=string 0x1F=string 1_000=string .inf=string 2001-12-14=string
      #|yes=boolean True=boolean true=boolean ~=null null=null 0o17=string 0x1F=integer 1_000=integer .inf=float 2001-12-14=timestamp
    ),
  )
}
