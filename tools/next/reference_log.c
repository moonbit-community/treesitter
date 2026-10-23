// Development-only: print the parse/lex log of each file using the C runtime.
#include <tree_sitter/api.h>
#include <stdio.h>
#include <stdlib.h>
extern const TSLanguage *LANGUAGE(void);
static void log_fn(void *payload, TSLogType type, const char *msg) {
  (void)payload;
  printf("%s %s\n", type == TSLogTypeParse ? "P" : "L", msg);
}
int main(int argc, char **argv) {
  TSParser *p = ts_parser_new();
  ts_parser_set_language(p, LANGUAGE());
  ts_parser_set_logger(p, (TSLogger){NULL, log_fn});
  for (int i = 1; i < argc; i++) {
    FILE *f = fopen(argv[i], "rb");
    fseek(f, 0, SEEK_END); long size = ftell(f); rewind(f);
    char *text = malloc(size + 1);
    fread(text, 1, size, f); fclose(f);
    printf("== %s\n", argv[i]);
    TSTree *t = ts_parser_parse_string(p, NULL, text, size);
    if (t) ts_tree_delete(t);
    free(text);
  }
  ts_parser_delete(p);
  return 0;
}
