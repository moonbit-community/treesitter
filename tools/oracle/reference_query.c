// Development-only: run a query with the C runtime and print matches and
// captures in the same format as `tools/probe query`.
#include <tree_sitter/api.h>
#include <stdio.h>
#include <stdlib.h>
extern const TSLanguage *LANGUAGE(void);
static char *read_file(const char *path, long *size) {
  FILE *f = fopen(path, "rb");
  fseek(f, 0, SEEK_END); *size = ftell(f); rewind(f);
  char *text = malloc(*size + 1);
  fread(text, 1, *size, f); fclose(f);
  return text;
}
int main(int argc, char **argv) {
  long qsize;
  char *qsrc = read_file(argv[1], &qsize);
  uint32_t error_offset; TSQueryError error_type;
  TSQuery *q = ts_query_new(LANGUAGE(), qsrc, qsize, &error_offset, &error_type);
  if (!q) { printf("error %d %u\n", error_type, error_offset); return 0; }
  printf("patterns %u captures %u strings %u\n", ts_query_pattern_count(q), ts_query_capture_count(q), ts_query_string_count(q));
  for (uint32_t i = 0; i < ts_query_pattern_count(q); i++) {
    printf("pattern %u rooted %d nonlocal %d start %u end %u\n", i, ts_query_is_pattern_rooted(q, i),
           ts_query_is_pattern_non_local(q, i), ts_query_start_byte_for_pattern(q, i), ts_query_end_byte_for_pattern(q, i));
  }
  for (uint32_t b = 0; b < (uint32_t)qsize; b++) {
    if (ts_query_is_pattern_guaranteed_at_step(q, b)) printf("guaranteed %u\n", b);
  }
  TSParser *p = ts_parser_new();
  ts_parser_set_language(p, LANGUAGE());
  TSQueryCursor *c = ts_query_cursor_new();
  for (int i = 2; i < argc; i++) {
    long size;
    char *text = read_file(argv[i], &size);
    printf("== %s\n", argv[i]);
    TSTree *t = ts_parser_parse_string(p, NULL, text, size);
    ts_query_cursor_exec(c, q, ts_tree_root_node(t));
    TSQueryMatch m;
    while (ts_query_cursor_next_match(c, &m)) {
      printf("M %u %u", m.pattern_index, m.id);
      for (uint32_t k = 0; k < m.capture_count; k++)
        printf(" %u:%u-%u", m.captures[k].index, ts_node_start_byte(m.captures[k].node), ts_node_end_byte(m.captures[k].node));
      printf("\n");
    }
    ts_query_cursor_exec(c, q, ts_tree_root_node(t));
    uint32_t ci;
    while (ts_query_cursor_next_capture(c, &m, &ci)) {
      printf("C %u %u %u %u-%u\n", m.pattern_index, ci, m.captures[ci].index,
             ts_node_start_byte(m.captures[ci].node), ts_node_end_byte(m.captures[ci].node));
    }
    printf("exceeded %d\n", ts_query_cursor_did_exceed_match_limit(c));
    ts_tree_delete(t); free(text);
  }
  return 0;
}
