#include <tree_sitter/api.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
extern const TSLanguage *LANGUAGE(void);
int main(int argc, char **argv) {
  TSParser *p = ts_parser_new();
  ts_parser_set_language(p, LANGUAGE());
  FILE *f = fopen(argv[1], "rb");
  fseek(f, 0, SEEK_END); long size = ftell(f); rewind(f);
  char *text = malloc(size + 1);
  fread(text, 1, size, f); fclose(f);
  int n = atoi(argv[2]);
  struct timespec a, b; clock_gettime(CLOCK_MONOTONIC, &a);
  for (int i = 0; i < n; i++) { TSTree *t = ts_parser_parse_string(p, NULL, text, size); ts_tree_delete(t); }
  clock_gettime(CLOCK_MONOTONIC, &b);
  double ms = (b.tv_sec - a.tv_sec) * 1e3 + (b.tv_nsec - a.tv_nsec) / 1e6;
  printf("%d parses in %.1f ms (%.3f ms/parse)\n", n, ms, ms / n);
  return 0;
}
