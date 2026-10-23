// Port of the html grammar's src/tag.h (v0.23.2).

///|
/// `TagType` values, in the C enum order. `HTML_TAG_NAMES[t]` is the name of
/// type `t`; the two marker values have no name.
let html_tag_names : FixedArray[String] = [
  "AREA", "BASE", "BASEFONT", "BGSOUND", "BR", "COL", "COMMAND", "EMBED", "FRAME",
  "HR", "IMAGE", "IMG", "INPUT", "ISINDEX", "KEYGEN", "LINK", "MENUITEM", "META",
  "NEXTID", "PARAM", "SOURCE", "TRACK", "WBR", "", "A", "ABBR", "ADDRESS", "ARTICLE",
  "ASIDE", "AUDIO", "B", "BDI", "BDO", "BLOCKQUOTE", "BODY", "BUTTON", "CANVAS",
  "CAPTION", "CITE", "CODE", "COLGROUP", "DATA", "DATALIST", "DD", "DEL", "DETAILS",
  "DFN", "DIALOG", "DIV", "DL", "DT", "EM", "FIELDSET", "FIGCAPTION", "FIGURE", "FOOTER",
  "FORM", "H1", "H2", "H3", "H4", "H5", "H6", "HEAD", "HEADER", "HGROUP", "HTML",
  "I", "IFRAME", "INS", "KBD", "LABEL", "LEGEND", "LI", "MAIN", "MAP", "MARK", "MATH",
  "MENU", "METER", "NAV", "NOSCRIPT", "OBJECT", "OL", "OPTGROUP", "OPTION", "OUTPUT",
  "P", "PICTURE", "PRE", "PROGRESS", "Q", "RB", "RP", "RT", "RTC", "RUBY", "S", "SAMP",
  "SCRIPT", "SECTION", "SELECT", "SLOT", "SMALL", "SPAN", "STRONG", "STYLE", "SUB",
  "SUMMARY", "SUP", "SVG", "TABLE", "TBODY", "TD", "TEMPLATE", "TEXTAREA", "TFOOT",
  "TH", "THEAD", "TIME", "TITLE", "TR", "U", "UL", "VAR", "VIDEO", "CUSTOM", "",
]

///|
const HTML_HR : Int32 = 9

///|
const HTML_END_OF_VOID_TAGS : Int32 = 23

///|
const HTML_ADDRESS : Int32 = 26

///|
const HTML_ARTICLE : Int32 = 27

///|
const HTML_ASIDE : Int32 = 28

///|
const HTML_BLOCKQUOTE : Int32 = 33

///|
const HTML_BODY : Int32 = 34

///|
const HTML_COL : Int32 = 5

///|
const HTML_COLGROUP : Int32 = 40

///|
const HTML_DD : Int32 = 43

///|
const HTML_DETAILS : Int32 = 45

///|
const HTML_DIV : Int32 = 48

///|
const HTML_DL : Int32 = 49

///|
const HTML_DT : Int32 = 50

///|
const HTML_FIELDSET : Int32 = 52

///|
const HTML_FIGCAPTION : Int32 = 53

///|
const HTML_FIGURE : Int32 = 54

///|
const HTML_FOOTER : Int32 = 55

///|
const HTML_FORM : Int32 = 56

///|
const HTML_H1 : Int32 = 57

///|
const HTML_H2 : Int32 = 58

///|
const HTML_H3 : Int32 = 59

///|
const HTML_H4 : Int32 = 60

///|
const HTML_H5 : Int32 = 61

///|
const HTML_H6 : Int32 = 62

///|
const HTML_HEAD : Int32 = 63

///|
const HTML_HEADER : Int32 = 64

///|
const HTML_HTML : Int32 = 66

///|
const HTML_LI : Int32 = 73

///|
const HTML_MAIN : Int32 = 74

///|
const HTML_NAV : Int32 = 80

///|
const HTML_OL : Int32 = 83

///|
const HTML_OPTGROUP : Int32 = 84

///|
const HTML_P : Int32 = 87

///|
const HTML_PRE : Int32 = 89

///|
const HTML_RB : Int32 = 92

///|
const HTML_RP : Int32 = 93

///|
const HTML_RT : Int32 = 94

///|
const HTML_SCRIPT : Int32 = 99

///|
const HTML_SECTION : Int32 = 100

///|
const HTML_STYLE : Int32 = 106

///|
const HTML_TD : Int32 = 113

///|
const HTML_TH : Int32 = 117

///|
const HTML_TR : Int32 = 121

///|
const HTML_CUSTOM : Int32 = 126

///|
const HTML_END_ : Int32 = 127

///|
/// `TAG_TYPES_NOT_ALLOWED_IN_PARAGRAPHS`.
let html_tag_types_not_allowed_in_paragraphs : FixedArray[Int32] = [
  HTML_ADDRESS,
  HTML_ARTICLE,
  HTML_ASIDE,
  HTML_BLOCKQUOTE,
  HTML_DETAILS,
  HTML_DIV,
  HTML_DL,
  HTML_FIELDSET,
  HTML_FIGCAPTION,
  HTML_FIGURE,
  HTML_FOOTER,
  HTML_FORM,
  HTML_H1,
  HTML_H2,
  HTML_H3,
  HTML_H4,
  HTML_H5,
  HTML_H6,
  HTML_HEADER,
  HTML_HR,
  HTML_MAIN,
  HTML_NAV,
  HTML_OL,
  HTML_P,
  HTML_PRE,
  HTML_SECTION,
]

///|
/// `Tag`. `custom_tag_name` is the C `Array(char)`.
priv struct HtmlTag {
  type_ : Int32
  custom_tag_name : Array[Byte]
}

///|
/// `tag_type_for_name`: a linear search of `TAG_TYPES_BY_TAG_NAME`, whose
/// entries are every named type in enum order.
fn html_tag_type_for_name(tag_name : Array[Byte]) -> Int32 {
  for t in 0..<html_tag_names.length() {
    let entry = html_tag_names[t]
    if entry.length() == 0 || entry.length() != tag_name.length() {
      continue
    }
    let mut equal = true
    for i in 0..<entry.length() {
      if entry[i].to_int() != tag_name[i].to_int() {
        equal = false
        break
      }
    }
    if equal {
      return t
    }
  }
  HTML_CUSTOM
}

///|
fn html_tag_new() -> HtmlTag {
  { type_: HTML_END_, custom_tag_name: [], }
}

///|
fn html_tag_for_name(name : Array[Byte]) -> HtmlTag {
  let type_ = html_tag_type_for_name(name)
  if type_ == HTML_CUSTOM {
    { type_, custom_tag_name: name, }
  } else {
    { type_, custom_tag_name: [], }
  }
}

///|
fn HtmlTag::is_void(self : HtmlTag) -> Bool {
  self.type_ < HTML_END_OF_VOID_TAGS
}

///|
fn HtmlTag::eq(self : HtmlTag, other : HtmlTag) -> Bool {
  if self.type_ != other.type_ {
    return false
  }
  if self.type_ == HTML_CUSTOM {
    if self.custom_tag_name.length() != other.custom_tag_name.length() {
      return false
    }
    for i in 0..<self.custom_tag_name.length() {
      if self.custom_tag_name[i] != other.custom_tag_name[i] {
        return false
      }
    }
  }
  true
}

///|
fn HtmlTag::can_contain(self : HtmlTag, other : HtmlTag) -> Bool {
  let child = other.type_
  match self.type_ {
    HTML_LI => child != HTML_LI
    HTML_DT | HTML_DD => child != HTML_DT && child != HTML_DD
    HTML_P => {
      for i in 0..<26 {
        if child == html_tag_types_not_allowed_in_paragraphs[i] {
          return false
        }
      }
      true
    }
    HTML_COLGROUP => child == HTML_COL
    HTML_RB | HTML_RT | HTML_RP =>
      child != HTML_RB && child != HTML_RT && child != HTML_RP
    HTML_OPTGROUP => child != HTML_OPTGROUP
    HTML_TR => child != HTML_TR
    HTML_TD | HTML_TH =>
      child != HTML_TD && child != HTML_TH && child != HTML_TR
    _ => true
  }
}
