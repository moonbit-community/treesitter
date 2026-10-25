// Development-only: parse with an encoding and included ranges using the C
// runtime. Usage: ref_modes <utf8|utf16le|utf16be> <ranges "s-e,..." or "-"> files...
#include <tree_sitter/api.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
extern const TSLanguage *LANGUAGE(void);
// The point of a byte offset: rows end at a '\n' code unit (in the input's
// encoding), columns count bytes.
static TSPoint point_at(const char *text, uint32_t byte, TSInputEncoding enc) {
  TSPoint p = {0, 0};
  int unit = enc == TSInputEncodingUTF8 ? 1 : 2;
  for (uint32_t i = 0; i < byte; i += unit) {
    int nl = enc == TSInputEncodingUTF8 ? text[i] == '\n'
           : enc == TSInputEncodingUTF16LE ? text[i] == '\n' && text[i+1] == 0
           : text[i] == 0 && text[i+1] == '\n';
    if (nl) { p.row++; p.column = 0; } else p.column += unit;
  }
  return p;
}
int main(int argc, char **argv) {
  TSParser *p = ts_parser_new();
  ts_parser_set_language(p, LANGUAGE());
  TSInputEncoding enc = !strcmp(argv[1], "utf16le") ? TSInputEncodingUTF16LE : !strcmp(argv[1], "utf16be") ? TSInputEncodingUTF16BE : TSInputEncodingUTF8;
  for (int i = 3; i < argc; i++) {
    FILE *f = fopen(argv[i], "rb");
    fseek(f, 0, SEEK_END); long size = ftell(f); rewind(f);
    char *text = malloc(size + 2);
    fread(text, 1, size, f); fclose(f);
    text[size] = text[size+1] = 0;
    printf("== %s\n", argv[i]);
    // At most one range per character of the specification.
    TSRange *ranges = malloc((strlen(argv[2]) + 1) * sizeof(TSRange)); uint32_t count = 0;
    if (strcmp(argv[2], "-")) {
      char *s = strdup(argv[2]); char *tok = strtok(s, ",");
      while (tok) {
        uint32_t a, b; sscanf(tok, "%u-%u", &a, &b);
        if (a > (uint32_t)size) a = size; if (b > (uint32_t)size) b = size;
        ranges[count].start_byte = a; ranges[count].end_byte = b;
        ranges[count].start_point = point_at(text, a, enc); ranges[count].end_point = point_at(text, b, enc);
        count++; tok = strtok(NULL, ",");
      }
      free(s);
    }
    printf("set %d\n", ts_parser_set_included_ranges(p, count ? ranges : NULL, count));
    free(ranges);
    TSTree *t = ts_parser_parse_string_encoding(p, NULL, text, size, enc);
    if (!t) { printf("(no tree)\n"); free(text); continue; }
    char *str = ts_node_string(ts_tree_root_node(t));
    TSNode root = ts_tree_root_node(t);
    printf("%s\nroot %u-%u (%u,%u)\n", str, ts_node_start_byte(root), ts_node_end_byte(root), ts_node_end_point(root).row, ts_node_end_point(root).column);
    uint32_t n; TSRange *r = ts_tree_included_ranges(t, &n);
    for (uint32_t k = 0; k < n; k++) printf("incl %u-%u\n", r[k].start_byte, r[k].end_byte);
    free(r); free(str); ts_tree_delete(t); free(text);
  }
  ts_parser_delete(p);
  return 0;
}
