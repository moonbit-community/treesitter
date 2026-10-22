#include <tree_sitter/api.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
extern const TSLanguage *LANGUAGE(void);
int main(int argc, char **argv) {
  if (argc != 2) return 2;
  FILE *f = fopen(argv[1], "rb"); if (!f) return 3;
  fseek(f, 0, SEEK_END); long size = ftell(f); rewind(f);
  if (size < 0 || size > UINT32_MAX) return 4;
  char *text = malloc(size + 1); if (!text) return 5;
  if (fread(text, 1, size, f) != (size_t)size) return 6;
  fclose(f);
  TSParser *p = ts_parser_new();
  if (!ts_parser_set_language(p, LANGUAGE())) return 7;
  TSTree *t = ts_parser_parse_string(p, NULL, text, size);
  if (!t) return 8;
  TSNode root = ts_tree_root_node(t);
  char *s = ts_node_string(root); puts(s); free(s);
  int status = ts_node_has_error(root) ? 1 : 0;
  ts_tree_delete(t); ts_parser_delete(p); free(text);
  return status;
}
