// Development-only: print the S-expression of each file parsed with the C
// runtime, in the same format as next/probe.
#include <tree_sitter/api.h>
#include <stdio.h>
#include <stdlib.h>
extern const TSLanguage *LANGUAGE(void);
int main(int argc, char **argv) {
  TSParser *p = ts_parser_new();
  ts_parser_set_language(p, LANGUAGE());
  for (int i = 1; i < argc; i++) {
    FILE *f = fopen(argv[i], "rb");
    fseek(f, 0, SEEK_END); long size = ftell(f); rewind(f);
    char *text = malloc(size + 1);
    fread(text, 1, size, f); fclose(f);
    printf("== %s\n", argv[i]);
    TSTree *t = ts_parser_parse_string(p, NULL, text, size);
    if (!t) { printf("(no tree)\n"); free(text); continue; }
    char *s = ts_node_string(ts_tree_root_node(t));
    printf("%s\n", s);
    free(s); ts_tree_delete(t); free(text);
  }
  ts_parser_delete(p);
  return 0;
}
