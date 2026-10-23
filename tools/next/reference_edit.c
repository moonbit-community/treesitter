// Development-only: incremental reparse oracle using the C runtime.
// Usage: ref_edit <old file> <new file> <start> <old_end> <new_end> [...]
// Prints the reparsed tree, the changed ranges and a fresh parse.
#include <tree_sitter/api.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
extern const TSLanguage *LANGUAGE(void);

static char *read_file(const char *path, long *size) {
  FILE *f = fopen(path, "rb");
  fseek(f, 0, SEEK_END); *size = ftell(f); rewind(f);
  char *text = malloc(*size + 1);
  fread(text, 1, *size, f); fclose(f);
  return text;
}

static TSPoint point_at(const char *text, uint32_t byte) {
  TSPoint p = {0, 0};
  for (uint32_t i = 0; i < byte; i++) {
    if (text[i] == '\n') { p.row++; p.column = 0; } else p.column++;
  }
  return p;
}

int main(int argc, char **argv) {
  TSParser *p = ts_parser_new();
  ts_parser_set_language(p, LANGUAGE());
  for (int a = 1; a + 4 < argc; a += 5) {
    long old_size, new_size;
    char *old_text = read_file(argv[a], &old_size);
    char *new_text = read_file(argv[a + 1], &new_size);
    uint32_t start = atoi(argv[a + 2]), old_end = atoi(argv[a + 3]), new_end = atoi(argv[a + 4]);
    TSTree *old_tree = ts_parser_parse_string(p, NULL, old_text, old_size);
    TSInputEdit edit = {
      start, old_end, new_end,
      point_at(old_text, start), point_at(old_text, old_end), point_at(new_text, new_end),
    };
    ts_tree_edit(old_tree, &edit);
    TSTree *new_tree = ts_parser_parse_string(p, old_tree, new_text, new_size);
    printf("== %s\n", argv[a + 1]);
    char *s = ts_node_string(ts_tree_root_node(new_tree));
    printf("%s\n", s); free(s);
    uint32_t count;
    TSRange *ranges = ts_tree_get_changed_ranges(old_tree, new_tree, &count);
    for (uint32_t i = 0; i < count; i++) {
      printf("range %u %u (%u,%u)-(%u,%u)\n", ranges[i].start_byte, ranges[i].end_byte,
             ranges[i].start_point.row, ranges[i].start_point.column,
             ranges[i].end_point.row, ranges[i].end_point.column);
    }
    free(ranges);
    TSTree *fresh = ts_parser_parse_string(p, NULL, new_text, new_size);
    s = ts_node_string(ts_tree_root_node(fresh));
    printf("fresh %s\n", s); free(s);
    ts_tree_delete(fresh); ts_tree_delete(new_tree); ts_tree_delete(old_tree);
    free(old_text); free(new_text);
  }
  ts_parser_delete(p);
  return 0;
}
