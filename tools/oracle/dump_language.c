// Development-only oracle: dump a compiled upstream TSLanguage (from a
// generated parser.c) as JSON in the shape of next/language's derived ToJson.
// The lex functions are not dumped here; tools/oracle/language_from_c.py parses
// them from the parser.c text.
#include "tree_sitter/parser.h"
#include <stdio.h>
#include <string.h>

extern const TSLanguage *LANGUAGE(void);

#define WEAK __attribute__((weak))
WEAK void *SCANNER_PREFIX(create)(void) { return NULL; }
WEAK void SCANNER_PREFIX(destroy)(void *p) { (void)p; }
WEAK bool SCANNER_PREFIX(scan)(void *p, TSLexer *l, const bool *v) { (void)p; (void)l; (void)v; return false; }
WEAK unsigned SCANNER_PREFIX(serialize)(void *p, char *b) { (void)p; (void)b; return 0; }
WEAK void SCANNER_PREFIX(deserialize)(void *p, const char *b, unsigned n) { (void)p; (void)b; (void)n; }

static void str(const char *s) {
  putchar('"');
  for (const unsigned char *c = (const unsigned char *)s; *c; c++) {
    if (*c == '"' || *c == '\\') printf("\\%c", *c);
    else if (*c == '\n') printf("\\n");
    else if (*c == '\t') printf("\\t");
    else if (*c == '\r') printf("\\r");
    else if (*c < 0x20) printf("\\u%04x", *c);
    else putchar(*c);
  }
  putchar('"');
}

static void u16s(const char *name, const uint16_t *a, uint32_t n) {
  printf("\"%s\":[", name);
  for (uint32_t i = 0; i < n; i++) printf(i ? ",%u" : "%u", a[i]);
  printf("],");
}

int main(void) {
  const TSLanguage *l = LANGUAGE();
  uint32_t symbols = l->symbol_count + l->alias_count;
  uint32_t small_count = l->state_count - l->large_state_count;
  // Extent of the small parse table and the parse actions.
  uint32_t small_end = 0, actions_end = 1;
  for (uint32_t s = 0; s < small_count; s++) {
    uint32_t i = l->small_parse_table_map[s];
    uint16_t groups = l->small_parse_table[i++];
    for (uint16_t g = 0; g < groups; g++) {
      uint16_t value = l->small_parse_table[i++];
      uint16_t count = l->small_parse_table[i++];
      for (uint16_t k = 0; k < count; k++) {
        uint16_t sym = l->small_parse_table[i++];
        if (sym < l->token_count) {
          uint32_t end = value + 1 + l->parse_actions[value].entry.count;
          if (end > actions_end) actions_end = end;
        }
      }
    }
    if (i > small_end) small_end = i;
  }
  for (uint32_t s = 0; s < l->large_state_count; s++) {
    for (uint32_t sym = 0; sym < l->token_count; sym++) {
      uint16_t value = l->parse_table[s * l->symbol_count + sym];
      uint32_t end = value + 1 + l->parse_actions[value].entry.count;
      if (end > actions_end) actions_end = end;
    }
  }
  printf("{");
  printf("\"abi_version\":%u,\"symbol_count\":%u,\"alias_count\":%u,\"token_count\":%u,"
         "\"external_token_count\":%u,\"state_count\":%u,\"large_state_count\":%u,"
         "\"production_id_count\":%u,\"field_count\":%u,\"max_alias_sequence_length\":%u,",
         l->abi_version, l->symbol_count, l->alias_count, l->token_count,
         l->external_token_count, l->state_count, l->large_state_count,
         l->production_id_count, l->field_count, l->max_alias_sequence_length);
  u16s("parse_table", l->parse_table, l->large_state_count * l->symbol_count);
  u16s("small_parse_table", l->small_parse_table, small_end);
  printf("\"small_parse_table_map\":[");
  for (uint32_t i = 0; i < small_count; i++) printf(i ? ",%u" : "%u", l->small_parse_table_map[i]);
  printf("],\"parse_actions\":[");
  for (uint32_t i = 0; i < actions_end;) {
    TSParseActionEntry e = l->parse_actions[i];
    printf(i ? "," : "");
    printf("[\"Entry\",{\"count\":%u,\"reusable\":%s}]", e.entry.count, e.entry.reusable ? "true" : "false");
    for (uint32_t k = 1; k <= e.entry.count; k++) {
      TSParseAction a = l->parse_actions[i + k].action;
      switch (a.type) {
        case TSParseActionTypeShift:
          printf(",[\"Shift\",{\"state\":%u,\"extra\":%s,\"repetition\":%s}]", a.shift.state,
                 a.shift.extra ? "true" : "false", a.shift.repetition ? "true" : "false");
          break;
        case TSParseActionTypeReduce:
          printf(",[\"Reduce\",{\"symbol\":%u,\"child_count\":%u,\"dynamic_precedence\":%d,\"production_id\":%u}]",
                 a.reduce.symbol, a.reduce.child_count, a.reduce.dynamic_precedence, a.reduce.production_id);
          break;
        case TSParseActionTypeAccept: printf(",\"Accept\""); break;
        case TSParseActionTypeRecover: printf(",\"Recover\""); break;
      }
    }
    i += 1 + e.entry.count;
  }
  printf("],\"symbol_names\":[");
  for (uint32_t i = 0; i < symbols; i++) { if (i) putchar(','); str(l->symbol_names[i]); }
  printf("],\"field_names\":[\"\"");
  for (uint32_t i = 1; i <= l->field_count; i++) { putchar(','); str(l->field_names[i]); }
  printf("],\"field_map_slices\":[");
  uint32_t entries_end = 0;
  if (l->field_count) {
    for (uint32_t i = 0; i < l->production_id_count; i++) {
      TSMapSlice s = l->field_map_slices[i];
      printf(i ? ",{\"index\":%u,\"length\":%u}" : "{\"index\":%u,\"length\":%u}", s.index, s.length);
      if (s.index + s.length > entries_end) entries_end = s.index + s.length;
    }
  }
  printf("],\"field_map_entries\":[");
  for (uint32_t i = 0; i < entries_end; i++) {
    TSFieldMapEntry e = l->field_map_entries[i];
    printf(i ? ",{\"field_id\":%u,\"child_index\":%u,\"inherited\":%s}" : "{\"field_id\":%u,\"child_index\":%u,\"inherited\":%s}",
           e.field_id, e.child_index, e.inherited ? "true" : "false");
  }
  printf("],\"symbol_metadata\":[");
  for (uint32_t i = 0; i < symbols; i++) {
    TSSymbolMetadata m = l->symbol_metadata[i];
    printf(i ? "," : "");
    printf("{\"visible\":%s,\"named\":%s,\"supertype\":%s}", m.visible ? "true" : "false",
           m.named ? "true" : "false", m.supertype ? "true" : "false");
  }
  printf("],");
  u16s("public_symbol_map", l->public_symbol_map, symbols);
  uint32_t alias_end = 0;
  while (l->alias_map[alias_end]) alias_end += 2 + l->alias_map[alias_end + 1];
  u16s("alias_map", l->alias_map, alias_end + 1);
  u16s("alias_sequences", l->alias_sequences, l->production_id_count * l->max_alias_sequence_length);
  uint32_t ext_states = 1, reserved_sets = 1;
  printf("\"lex_modes\":[");
  for (uint32_t i = 0; i < l->state_count; i++) {
    TSLexerMode m = l->lex_modes[i];
    printf(i ? "," : "");
    printf("{\"lex_state\":%u,\"external_lex_state\":%u,\"reserved_word_set_id\":%u}",
           m.lex_state, m.external_lex_state, m.reserved_word_set_id);
    if (m.external_lex_state + 1u > ext_states) ext_states = m.external_lex_state + 1u;
    if (m.reserved_word_set_id + 1u > reserved_sets) reserved_sets = m.reserved_word_set_id + 1u;
  }
  printf("],\"keyword_capture_token\":%u,", l->keyword_capture_token);
  printf("\"external_scanner\":{\"states\":[");
  if (l->external_token_count) {
    for (uint32_t i = 0; i < ext_states * l->external_token_count; i++)
      printf(i ? ",%s" : "%s", l->external_scanner.states[i] ? "true" : "false");
  }
  printf("],\"symbol_map\":[");
  for (uint32_t i = 0; i < l->external_token_count; i++) printf(i ? ",%u" : "%u", l->external_scanner.symbol_map[i]);
  printf("]},");
  u16s("primary_state_ids", l->primary_state_ids, l->state_count);
  printf("\"name\":"); str(l->name); printf(",");
  if (l->max_reserved_word_set_size) {
    u16s("reserved_words", l->reserved_words, reserved_sets * l->max_reserved_word_set_size);
  } else {
    printf("\"reserved_words\":[],");
  }
  printf("\"max_reserved_word_set_size\":%u,\"supertype_count\":%u,", l->max_reserved_word_set_size, l->supertype_count);
  u16s("supertype_symbols", l->supertype_symbols, l->supertype_count);
  printf("\"supertype_map_slices\":[");
  uint32_t super_end = 0;
  if (l->supertype_count) {
    // ts_supertype_map_slices is rendered with designated initializers, so it
    // ends at the largest supertype symbol; the slices after it are empty.
    uint32_t slices_end = 0;
    for (uint32_t i = 0; i < l->supertype_count; i++)
      if (l->supertype_symbols[i] + 1u > slices_end) slices_end = l->supertype_symbols[i] + 1u;
    for (uint32_t i = 0; i < symbols; i++) {
      TSMapSlice s = i < slices_end ? l->supertype_map_slices[i] : (TSMapSlice){0, 0};
      printf(i ? ",{\"index\":%u,\"length\":%u}" : "{\"index\":%u,\"length\":%u}", s.index, s.length);
      if (s.index + s.length > super_end) super_end = s.index + s.length;
    }
  }
  printf("],");
  u16s("supertype_map_entries", l->supertype_map_entries, super_end);
  printf("\"metadata\":{\"major_version\":%u,\"minor_version\":%u,\"patch_version\":%u}",
         l->metadata.major_version, l->metadata.minor_version, l->metadata.patch_version);
  printf("}\n");
  return 0;
}
