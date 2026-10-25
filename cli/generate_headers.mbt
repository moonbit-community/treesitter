// The C headers that `generate` writes to `src/tree_sitter/` (upstream
// crates/generate/src/templates/alloc.h, templates/array.h and parser.h.inc),
// embedded verbatim. Generated from the pinned checkout; do not edit.

///|
pub let alloc_header : String =
  #|#ifndef TREE_SITTER_ALLOC_H_
  #|#define TREE_SITTER_ALLOC_H_
  #|
  #|#ifdef __cplusplus
  #|extern "C" {
  #|#endif
  #|
  #|#include <stdbool.h>
  #|#include <stdio.h>
  #|#include <stdlib.h>
  #|
  #|// Allow clients to override allocation functions
  #|#ifdef TREE_SITTER_REUSE_ALLOCATOR
  #|
  #|extern void *(*ts_current_malloc)(size_t size);
  #|extern void *(*ts_current_calloc)(size_t count, size_t size);
  #|extern void *(*ts_current_realloc)(void *ptr, size_t size);
  #|extern void (*ts_current_free)(void *ptr);
  #|
  #|#ifndef ts_malloc
  #|#define ts_malloc  ts_current_malloc
  #|#endif
  #|#ifndef ts_calloc
  #|#define ts_calloc  ts_current_calloc
  #|#endif
  #|#ifndef ts_realloc
  #|#define ts_realloc ts_current_realloc
  #|#endif
  #|#ifndef ts_free
  #|#define ts_free    ts_current_free
  #|#endif
  #|
  #|#else
  #|
  #|#ifndef ts_malloc
  #|#define ts_malloc  malloc
  #|#endif
  #|#ifndef ts_calloc
  #|#define ts_calloc  calloc
  #|#endif
  #|#ifndef ts_realloc
  #|#define ts_realloc realloc
  #|#endif
  #|#ifndef ts_free
  #|#define ts_free    free
  #|#endif
  #|
  #|#endif
  #|
  #|#ifdef __cplusplus
  #|}
  #|#endif
  #|
  #|#endif // TREE_SITTER_ALLOC_H_
  #|

///|
pub let array_header : String =
  #|#ifndef TREE_SITTER_ARRAY_H_
  #|#define TREE_SITTER_ARRAY_H_
  #|
  #|#ifdef __cplusplus
  #|extern "C" {
  #|#endif
  #|
  #|#include "./alloc.h"
  #|
  #|#include <assert.h>
  #|#include <stdbool.h>
  #|#include <stdint.h>
  #|#include <stdlib.h>
  #|#include <string.h>
  #|
  #|#ifdef _MSC_VER
  #|#pragma warning(push)
  #|#pragma warning(disable : 4101)
  #|#elif defined(__GNUC__) || defined(__clang__)
  #|#pragma GCC diagnostic push
  #|#pragma GCC diagnostic ignored "-Wunused-variable"
  #|#endif
  #|
  #|#define Array(T)       \
  #|  struct {             \
  #|    T *contents;       \
  #|    uint32_t size;     \
  #|    uint32_t capacity; \
  #|  }
  #|
  #|/// Initialize an array.
  #|#define array_init(self) \
  #|  ((self)->size = 0, (self)->capacity = 0, (self)->contents = NULL)
  #|
  #|/// Create an empty array.
  #|#define array_new() \
  #|  { NULL, 0, 0 }
  #|
  #|/// Get a pointer to the element at a given `index` in the array.
  #|#define array_get(self, _index) \
  #|  (assert((uint32_t)(_index) < (self)->size), &(self)->contents[_index])
  #|
  #|/// Get a pointer to the first element in the array.
  #|#define array_front(self) array_get(self, 0)
  #|
  #|/// Get a pointer to the last element in the array.
  #|#define array_back(self) array_get(self, (self)->size - 1)
  #|
  #|/// Clear the array, setting its size to zero. Note that this does not free any
  #|/// memory allocated for the array's contents.
  #|#define array_clear(self) ((self)->size = 0)
  #|
  #|#ifdef __cplusplus
  #|#define _array__cast(self, expr) (decltype((self)->contents))(expr)
  #|#else
  #|#define _array__cast(self, expr) (expr)
  #|#endif
  #|
  #|/// Reserve `new_capacity` elements of space in the array. If `new_capacity` is
  #|/// less than the array's current capacity, this function has no effect.
  #|#define array_reserve(self, new_capacity)                 \
  #|  ((self)->contents = _array__cast(self, _array__reserve( \
  #|    (void *)(self)->contents, &(self)->capacity,          \
  #|    array_elem_size(self), new_capacity))                 \
  #|  )
  #|
  #|/// Free any memory allocated for this array. Note that this does not free any
  #|/// memory allocated for the array's contents.
  #|#define array_delete(self)                           \
  #|  do {                                               \
  #|    if ((self)->contents) ts_free((self)->contents); \
  #|    (self)->contents = NULL;                         \
  #|    (self)->size = 0;                                \
  #|    (self)->capacity = 0;                            \
  #|  } while (0)
  #|
  #|/// Push a new `element` onto the end of the array.
  #|#define array_push(self, element)                                 \
  #|  do {                                                            \
  #|    (self)->contents = _array__cast(self, _array__grow(           \
  #|      (void *)(self)->contents, (self)->size, &(self)->capacity,  \
  #|      1, array_elem_size(self)                                    \
  #|    ));                                                           \
  #|   (self)->contents[(self)->size++] = (element);                  \
  #|  } while(0)
  #|
  #|/// Increase the array's size by `count` elements.
  #|/// New elements are zero-initialized.
  #|#define array_grow_by(self, count)                                               \
  #|  do {                                                                           \
  #|    if ((count) == 0) break;                                                     \
  #|    (self)->contents = _array__cast(self, _array__grow(                          \
  #|      (self)->contents, (self)->size, &(self)->capacity,                         \
  #|      count, array_elem_size(self)                                               \
  #|    ));                                                                          \
  #|    memset((self)->contents + (self)->size, 0, (count) * array_elem_size(self)); \
  #|    (self)->size += (count);                                                     \
  #|  } while (0)
  #|
  #|/// Append all elements from one array to the end of another.
  #|#define array_push_all(self, other) \
  #|  array_extend((self), (other)->size, (other)->contents)
  #|
  #|/// Append `count` elements to the end of the array, reading their values from the
  #|/// `contents` pointer.
  #|#define array_extend(self, count, other_contents)                 \
  #|  ((self)->contents = _array__cast(self, _array__splice(          \
  #|    (void*)(self)->contents, &(self)->size, &(self)->capacity,    \
  #|    array_elem_size(self), (self)->size, 0, count, other_contents \
  #|  )))
  #|
  #|/// Remove `old_count` elements from the array starting at the given `index`. At
  #|/// the same index, insert `new_count` new elements, reading their values from the
  #|/// `new_contents` pointer.
  #|#define array_splice(self, _index, old_count, new_count, new_contents) \
  #|  ((self)->contents = _array__cast(self, _array__splice(              \
  #|    (void *)(self)->contents, &(self)->size, &(self)->capacity,        \
  #|    array_elem_size(self), _index, old_count, new_count, new_contents  \
  #|  )))
  #|
  #|/// Insert one `element` into the array at the given `index`.
  #|#define array_insert(self, _index, element)                     \
  #|  ((self)->contents = _array__cast(self, _array__splice(        \
  #|    (void *)(self)->contents, &(self)->size, &(self)->capacity, \
  #|    array_elem_size(self), _index, 0, 1, &(element)             \
  #|  )))
  #|
  #|/// Remove one element from the array at the given `index`.
  #|#define array_erase(self, _index) \
  #|  _array__erase((void *)(self)->contents, &(self)->size, array_elem_size(self), _index)
  #|
  #|/// Pop the last element off the array, returning the element by value.
  #|#define array_pop(self) ((self)->contents[--(self)->size])
  #|
  #|/// Assign the contents of one array to another, reallocating if necessary.
  #|#define array_assign(self, other)                                   \
  #|  ((self)->contents = _array__cast(self, _array__assign(            \
  #|    (void *)(self)->contents, &(self)->size, &(self)->capacity,     \
  #|    (const void *)(other)->contents, (other)->size, array_elem_size(self) \
  #|  )))
  #|
  #|/// Swap one array with another
  #|#define array_swap(self, other)                                     \
  #|  do {                                                              \
  #|    void *_array_swap_tmp = (void *)(self)->contents;               \
  #|    (self)->contents = (other)->contents;                           \
  #|    (other)->contents = _array__cast(other, _array_swap_tmp);       \
  #|    _array__swap(&(self)->size, &(self)->capacity,                  \
  #|                 &(other)->size, &(other)->capacity);               \
  #|  } while (0)
  #|
  #|/// Get the size of the array contents
  #|#define array_elem_size(self) (sizeof *(self)->contents)
  #|
  #|/// Search a sorted array for a given `needle` value, using the given `compare`
  #|/// callback to determine the order.
  #|///
  #|/// If an existing element is found to be equal to `needle`, then the `index`
  #|/// out-parameter is set to the existing value's index, and the `exists`
  #|/// out-parameter is set to true. Otherwise, `index` is set to an index where
  #|/// `needle` should be inserted in order to preserve the sorting, and `exists`
  #|/// is set to false.
  #|#define array_search_sorted_with(self, compare, needle, _index, _exists) \
  #|  _array__search_sorted(self, 0, compare, , needle, _index, _exists)
  #|
  #|/// Search a sorted array for a given `needle` value, using integer comparisons
  #|/// of a given struct field (specified with a leading dot) to determine the order.
  #|///
  #|/// See also `array_search_sorted_with`.
  #|#define array_search_sorted_by(self, field, needle, _index, _exists) \
  #|  _array__search_sorted(self, 0, _compare_int, field, needle, _index, _exists)
  #|
  #|/// Insert a given `value` into a sorted array, using the given `compare`
  #|/// callback to determine the order.
  #|#define array_insert_sorted_with(self, compare, value) \
  #|  do { \
  #|    unsigned _index, _exists; \
  #|    array_search_sorted_with(self, compare, &(value), &_index, &_exists); \
  #|    if (!_exists) array_insert(self, _index, value); \
  #|  } while (0)
  #|
  #|/// Insert a given `value` into a sorted array, using integer comparisons of
  #|/// a given struct field (specified with a leading dot) to determine the order.
  #|///
  #|/// See also `array_search_sorted_by`.
  #|#define array_insert_sorted_by(self, field, value) \
  #|  do { \
  #|    unsigned _index, _exists; \
  #|    array_search_sorted_by(self, field, (value) field, &_index, &_exists); \
  #|    if (!_exists) array_insert(self, _index, value); \
  #|  } while (0)
  #|
  #|// Private
  #|
  #|// Pointers to individual `Array` fields (rather than the entire `Array` itself)
  #|// are passed to the various `_array__*` functions below to address strict aliasing
  #|// violations that arises when the _entire_ `Array` struct is passed as `Array(void)*`.
  #|//
  #|// The `Array` type itself was not altered as a solution in order to avoid breakage
  #|// with existing consumers (in particular, parsers with external scanners).
  #|
  #|/// This is not what you're looking for, see `array_erase`.
  #|static inline void _array__erase(void* self_contents, uint32_t *size,
  #|                                size_t element_size, uint32_t index) {
  #|  assert(index < *size);
  #|  char *contents = (char *)self_contents;
  #|  memmove(contents + index * element_size, contents + (index + 1) * element_size,
  #|          (*size - index - 1) * element_size);
  #|  (*size)--;
  #|}
  #|
  #|/// This is not what you're looking for, see `array_reserve`.
  #|static inline void *_array__reserve(void *contents, uint32_t *capacity,
  #|                                  size_t element_size, uint32_t new_capacity) {
  #|  void *new_contents = contents;
  #|  if (new_capacity > *capacity) {
  #|    if (contents) {
  #|      new_contents = ts_realloc(contents, new_capacity * element_size);
  #|    } else {
  #|      new_contents = ts_malloc(new_capacity * element_size);
  #|    }
  #|    *capacity = new_capacity;
  #|  }
  #|  return new_contents;
  #|}
  #|
  #|/// This is not what you're looking for, see `array_assign`.
  #|static inline void *_array__assign(void* self_contents, uint32_t *self_size, uint32_t *self_capacity,
  #|                                 const void *other_contents, uint32_t other_size, size_t element_size) {
  #|  void *new_contents = _array__reserve(self_contents, self_capacity, element_size, other_size);
  #|  *self_size = other_size;
  #|  memcpy(new_contents, other_contents, *self_size * element_size);
  #|  return new_contents;
  #|}
  #|
  #|/// This is not what you're looking for, see `array_swap`.
  #|static inline void _array__swap(uint32_t *self_size, uint32_t *self_capacity,
  #|                               uint32_t *other_size, uint32_t *other_capacity) {
  #|  uint32_t tmp_size = *self_size;
  #|  uint32_t tmp_capacity = *self_capacity;
  #|  *self_size = *other_size;
  #|  *self_capacity = *other_capacity;
  #|  *other_size = tmp_size;
  #|  *other_capacity = tmp_capacity;
  #|}
  #|
  #|/// This is not what you're looking for, see `array_push` or `array_grow_by`.
  #|static inline void *_array__grow(void *contents, uint32_t size, uint32_t *capacity,
  #|                               uint32_t count, size_t element_size) {
  #|  void *new_contents = contents;
  #|  uint32_t new_size = size + count;
  #|  if (new_size > *capacity) {
  #|    uint32_t new_capacity = *capacity * 2;
  #|    if (new_capacity < 8) new_capacity = 8;
  #|    if (new_capacity < new_size) new_capacity = new_size;
  #|    new_contents = _array__reserve(contents, capacity, element_size, new_capacity);
  #|  }
  #|  return new_contents;
  #|}
  #|
  #|/// This is not what you're looking for, see `array_splice`.
  #|static inline void *_array__splice(void *self_contents, uint32_t *size, uint32_t *capacity,
  #|                                 size_t element_size,
  #|                                 uint32_t index, uint32_t old_count,
  #|                                 uint32_t new_count, const void *elements) {
  #|  uint32_t new_size = *size + new_count - old_count;
  #|  uint32_t old_end = index + old_count;
  #|  uint32_t new_end = index + new_count;
  #|  assert(old_end <= *size);
  #|
  #|  void *new_contents = _array__reserve(self_contents, capacity, element_size, new_size);
  #|
  #|  char *contents = (char *)new_contents;
  #|  if (*size > old_end) {
  #|    memmove(
  #|      contents + new_end * element_size,
  #|      contents + old_end * element_size,
  #|      (*size - old_end) * element_size
  #|    );
  #|  }
  #|  if (new_count > 0) {
  #|    if (elements) {
  #|      memcpy(
  #|        (contents + index * element_size),
  #|        elements,
  #|        new_count * element_size
  #|      );
  #|    } else {
  #|      memset(
  #|        (contents + index * element_size),
  #|        0,
  #|        new_count * element_size
  #|      );
  #|    }
  #|  }
  #|  *size += new_count - old_count;
  #|
  #|  return new_contents;
  #|}
  #|
  #|/// A binary search routine, based on Rust's `std::slice::binary_search_by`.
  #|/// This is not what you're looking for, see `array_search_sorted_with` or `array_search_sorted_by`.
  #|#define _array__search_sorted(self, start, compare, suffix, needle, _index, _exists) \
  #|  do { \
  #|    *(_index) = start; \
  #|    *(_exists) = false; \
  #|    uint32_t size = (self)->size - *(_index); \
  #|    if (size == 0) break; \
  #|    int comparison; \
  #|    while (size > 1) { \
  #|      uint32_t half_size = size / 2; \
  #|      uint32_t mid_index = *(_index) + half_size; \
  #|      comparison = compare(&((self)->contents[mid_index] suffix), (needle)); \
  #|      if (comparison <= 0) *(_index) = mid_index; \
  #|      size -= half_size; \
  #|    } \
  #|    comparison = compare(&((self)->contents[*(_index)] suffix), (needle)); \
  #|    if (comparison == 0) *(_exists) = true; \
  #|    else if (comparison < 0) *(_index) += 1; \
  #|  } while (0)
  #|
  #|/// Helper macro for the `_sorted_by` routines below. This takes the left (existing)
  #|/// parameter by reference in order to work with the generic sorting function above.
  #|#define _compare_int(a, b) ((int)*(a) - (int)(b))
  #|
  #|#ifdef _MSC_VER
  #|#pragma warning(pop)
  #|#elif defined(__GNUC__) || defined(__clang__)
  #|#pragma GCC diagnostic pop
  #|#endif
  #|
  #|#ifdef __cplusplus
  #|}
  #|#endif
  #|
  #|#endif  // TREE_SITTER_ARRAY_H_
  #|

///|
pub let parser_header : String =
  #|#ifndef TREE_SITTER_PARSER_H_
  #|#define TREE_SITTER_PARSER_H_
  #|
  #|#ifdef __cplusplus
  #|extern "C" {
  #|#endif
  #|
  #|#include <stdbool.h>
  #|#include <stdint.h>
  #|#include <stdlib.h>
  #|
  #|#define ts_builtin_sym_error ((TSSymbol)-1)
  #|#define ts_builtin_sym_end 0
  #|#define TREE_SITTER_SERIALIZATION_BUFFER_SIZE 1024
  #|
  #|#ifndef TREE_SITTER_API_H_
  #|typedef uint16_t TSStateId;
  #|typedef uint16_t TSSymbol;
  #|typedef uint16_t TSFieldId;
  #|typedef struct TSLanguage TSLanguage;
  #|typedef struct TSLanguageMetadata {
  #|  uint8_t major_version;
  #|  uint8_t minor_version;
  #|  uint8_t patch_version;
  #|} TSLanguageMetadata;
  #|#endif
  #|
  #|typedef struct {
  #|  TSFieldId field_id;
  #|  uint8_t child_index;
  #|  bool inherited;
  #|} TSFieldMapEntry;
  #|
  #|// Used to index the field and supertype maps.
  #|typedef struct {
  #|  uint16_t index;
  #|  uint16_t length;
  #|} TSMapSlice;
  #|
  #|typedef struct {
  #|  bool visible;
  #|  bool named;
  #|  bool supertype;
  #|} TSSymbolMetadata;
  #|
  #|typedef struct TSLexer TSLexer;
  #|
  #|struct TSLexer {
  #|  int32_t lookahead;
  #|  TSSymbol result_symbol;
  #|  void (*advance)(TSLexer *, bool);
  #|  void (*mark_end)(TSLexer *);
  #|  uint32_t (*get_column)(TSLexer *);
  #|  bool (*is_at_included_range_start)(const TSLexer *);
  #|  bool (*eof)(const TSLexer *);
  #|  void (*log)(const TSLexer *, const char *, ...);
  #|};
  #|
  #|typedef enum {
  #|  TSParseActionTypeShift,
  #|  TSParseActionTypeReduce,
  #|  TSParseActionTypeAccept,
  #|  TSParseActionTypeRecover,
  #|} TSParseActionType;
  #|
  #|typedef union {
  #|  struct {
  #|    uint8_t type;
  #|    TSStateId state;
  #|    bool extra;
  #|    bool repetition;
  #|  } shift;
  #|  struct {
  #|    uint8_t type;
  #|    uint8_t child_count;
  #|    TSSymbol symbol;
  #|    int16_t dynamic_precedence;
  #|    uint16_t production_id;
  #|  } reduce;
  #|  uint8_t type;
  #|} TSParseAction;
  #|
  #|typedef struct {
  #|  uint16_t lex_state;
  #|  uint16_t external_lex_state;
  #|} TSLexMode;
  #|
  #|typedef struct {
  #|  uint16_t lex_state;
  #|  uint16_t external_lex_state;
  #|  uint16_t reserved_word_set_id;
  #|} TSLexerMode;
  #|
  #|typedef union {
  #|  TSParseAction action;
  #|  struct {
  #|    uint8_t count;
  #|    bool reusable;
  #|  } entry;
  #|} TSParseActionEntry;
  #|
  #|typedef struct {
  #|  int32_t start;
  #|  int32_t end;
  #|} TSCharacterRange;
  #|
  #|struct TSLanguage {
  #|  uint32_t abi_version;
  #|  uint32_t symbol_count;
  #|  uint32_t alias_count;
  #|  uint32_t token_count;
  #|  uint32_t external_token_count;
  #|  uint32_t state_count;
  #|  uint32_t large_state_count;
  #|  uint32_t production_id_count;
  #|  uint32_t field_count;
  #|  uint16_t max_alias_sequence_length;
  #|  const uint16_t *parse_table;
  #|  const uint16_t *small_parse_table;
  #|  const uint32_t *small_parse_table_map;
  #|  const TSParseActionEntry *parse_actions;
  #|  const char * const *symbol_names;
  #|  const char * const *field_names;
  #|  const TSMapSlice *field_map_slices;
  #|  const TSFieldMapEntry *field_map_entries;
  #|  const TSSymbolMetadata *symbol_metadata;
  #|  const TSSymbol *public_symbol_map;
  #|  const uint16_t *alias_map;
  #|  const TSSymbol *alias_sequences;
  #|  const TSLexerMode *lex_modes;
  #|  bool (*lex_fn)(TSLexer *, TSStateId);
  #|  bool (*keyword_lex_fn)(TSLexer *, TSStateId);
  #|  TSSymbol keyword_capture_token;
  #|  struct {
  #|    const bool *states;
  #|    const TSSymbol *symbol_map;
  #|    void *(*create)(void);
  #|    void (*destroy)(void *);
  #|    bool (*scan)(void *, TSLexer *, const bool *symbol_whitelist);
  #|    unsigned (*serialize)(void *, char *);
  #|    void (*deserialize)(void *, const char *, unsigned);
  #|  } external_scanner;
  #|  const TSStateId *primary_state_ids;
  #|  const char *name;
  #|  const TSSymbol *reserved_words;
  #|  uint16_t max_reserved_word_set_size;
  #|  uint32_t supertype_count;
  #|  const TSSymbol *supertype_symbols;
  #|  const TSMapSlice *supertype_map_slices;
  #|  const TSSymbol *supertype_map_entries;
  #|  TSLanguageMetadata metadata;
  #|};
  #|
  #|static inline bool set_contains(const TSCharacterRange *ranges, uint32_t len, int32_t lookahead) {
  #|  uint32_t index = 0;
  #|  uint32_t size = len - index;
  #|  while (size > 1) {
  #|    uint32_t half_size = size / 2;
  #|    uint32_t mid_index = index + half_size;
  #|    const TSCharacterRange *range = &ranges[mid_index];
  #|    if (lookahead >= range->start && lookahead <= range->end) {
  #|      return true;
  #|    } else if (lookahead > range->end) {
  #|      index = mid_index;
  #|    }
  #|    size -= half_size;
  #|  }
  #|  const TSCharacterRange *range = &ranges[index];
  #|  return (lookahead >= range->start && lookahead <= range->end);
  #|}
  #|
  #|/*
  #| *  Lexer Macros
  #| */
  #|
  #|#ifdef _MSC_VER
  #|#define UNUSED __pragma(warning(suppress : 4101))
  #|#else
  #|#define UNUSED __attribute__((unused))
  #|#endif
  #|
  #|#define START_LEXER()           \
  #|  bool result = false;          \
  #|  bool skip = false;            \
  #|  UNUSED                        \
  #|  bool eof = false;             \
  #|  int32_t lookahead;            \
  #|  goto start;                   \
  #|  next_state:                   \
  #|  lexer->advance(lexer, skip);  \
  #|  start:                        \
  #|  skip = false;                 \
  #|  lookahead = lexer->lookahead;
  #|
  #|#define ADVANCE(state_value) \
  #|  {                          \
  #|    state = state_value;     \
  #|    goto next_state;         \
  #|  }
  #|
  #|#define ADVANCE_MAP(...)                                              \
  #|  {                                                                   \
  #|    static const uint16_t map[] = { __VA_ARGS__ };                    \
  #|    for (uint32_t i = 0; i < sizeof(map) / sizeof(map[0]); i += 2) {  \
  #|      if (map[i] == lookahead) {                                      \
  #|        state = map[i + 1];                                           \
  #|        goto next_state;                                              \
  #|      }                                                               \
  #|    }                                                                 \
  #|  }
  #|
  #|#define SKIP(state_value) \
  #|  {                       \
  #|    skip = true;          \
  #|    state = state_value;  \
  #|    goto next_state;      \
  #|  }
  #|
  #|#define ACCEPT_TOKEN(symbol_value)     \
  #|  result = true;                       \
  #|  lexer->result_symbol = symbol_value; \
  #|  lexer->mark_end(lexer);
  #|
  #|#define END_STATE() return result;
  #|
  #|/*
  #| *  Parse Table Macros
  #| */
  #|
  #|#define SMALL_STATE(id) ((id) - LARGE_STATE_COUNT)
  #|
  #|#define STATE(id) id
  #|
  #|#define ACTIONS(id) id
  #|
  #|#define SHIFT(state_value)            \
  #|  {{                                  \
  #|    .shift = {                        \
  #|      .type = TSParseActionTypeShift, \
  #|      .state = (state_value)          \
  #|    }                                 \
  #|  }}
  #|
  #|#define SHIFT_REPEAT(state_value)     \
  #|  {{                                  \
  #|    .shift = {                        \
  #|      .type = TSParseActionTypeShift, \
  #|      .state = (state_value),         \
  #|      .repetition = true              \
  #|    }                                 \
  #|  }}
  #|
  #|#define SHIFT_EXTRA()                 \
  #|  {{                                  \
  #|    .shift = {                        \
  #|      .type = TSParseActionTypeShift, \
  #|      .extra = true                   \
  #|    }                                 \
  #|  }}
  #|
  #|#define REDUCE(symbol_name, children, precedence, prod_id) \
  #|  {{                                                       \
  #|    .reduce = {                                            \
  #|      .type = TSParseActionTypeReduce,                     \
  #|      .symbol = symbol_name,                               \
  #|      .child_count = children,                             \
  #|      .dynamic_precedence = precedence,                    \
  #|      .production_id = prod_id                             \
  #|    },                                                     \
  #|  }}
  #|
  #|#define RECOVER()                    \
  #|  {{                                 \
  #|    .type = TSParseActionTypeRecover \
  #|  }}
  #|
  #|#define ACCEPT_INPUT()              \
  #|  {{                                \
  #|    .type = TSParseActionTypeAccept \
  #|  }}
  #|
  #|#ifdef __cplusplus
  #|}
  #|#endif
  #|
  #|#endif  // TREE_SITTER_PARSER_H_
  #|

///|
pub let dsl_js : String =
  #|function alias(rule, value) {
  #|  const result = {
  #|    type: "ALIAS",
  #|    content: normalize(rule),
  #|    named: false,
  #|    value: null
  #|  };
  #|
  #|  switch (value.constructor) {
  #|    case String:
  #|      result.named = false;
  #|      result.value = value;
  #|      return result;
  #|    case ReferenceError:
  #|      result.named = true;
  #|      result.value = value.symbol.name;
  #|      return result;
  #|    case Object:
  #|    case GrammarSymbol:
  #|      if (typeof value.type === 'string' && value.type === 'SYMBOL') {
  #|        result.named = true;
  #|        result.value = value.name;
  #|        return result;
  #|      }
  #|  }
  #|
  #|  throw new Error(`Invalid alias value ${value}`);
  #|}
  #|
  #|function blank() {
  #|  return {
  #|    type: "BLANK"
  #|  };
  #|}
  #|
  #|function eof() {
  #|  return {
  #|    type: "EOF"
  #|  };
  #|}
  #|
  #|function field(name, rule) {
  #|  if (typeof name !== "string" || !/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(name)) {
  #|    throw new Error(`Invalid field name '${name}': field names must start with a letter or underscore, followed by letters, digits, or underscores`);
  #|  }
  #|  return {
  #|    type: "FIELD",
  #|    name,
  #|    content: normalize(rule)
  #|  }
  #|}
  #|
  #|function choice(...elements) {
  #|  return {
  #|    type: "CHOICE",
  #|    members: elements.map(normalize)
  #|  };
  #|}
  #|
  #|function optional(value) {
  #|  checkArguments(arguments, arguments.length, optional, 'optional');
  #|  return choice(value, blank());
  #|}
  #|
  #|function prec(number, rule) {
  #|  checkPrecedence(number);
  #|  checkArguments(
  #|    arguments,
  #|    arguments.length - 1,
  #|    prec,
  #|    'prec',
  #|    ' and a precedence argument'
  #|  );
  #|
  #|  return {
  #|    type: "PREC",
  #|    value: number,
  #|    content: normalize(rule)
  #|  };
  #|}
  #|
  #|prec.left = function (number, rule) {
  #|  if (rule == null) {
  #|    rule = number;
  #|    number = 0;
  #|  }
  #|
  #|  checkPrecedence(number);
  #|  checkArguments(
  #|    arguments,
  #|    arguments.length - 1,
  #|    prec.left,
  #|    'prec.left',
  #|    ' and an optional precedence argument'
  #|  );
  #|
  #|  return {
  #|    type: "PREC_LEFT",
  #|    value: number,
  #|    content: normalize(rule)
  #|  };
  #|}
  #|
  #|prec.right = function (number, rule) {
  #|  if (rule == null) {
  #|    rule = number;
  #|    number = 0;
  #|  }
  #|
  #|  checkPrecedence(number);
  #|  checkArguments(
  #|    arguments,
  #|    arguments.length - 1,
  #|    prec.right,
  #|    'prec.right',
  #|    ' and an optional precedence argument'
  #|  );
  #|
  #|  return {
  #|    type: "PREC_RIGHT",
  #|    value: number,
  #|    content: normalize(rule)
  #|  };
  #|}
  #|
  #|prec.dynamic = function (number, rule) {
  #|  checkPrecedence(number);
  #|  checkArguments(
  #|    arguments,
  #|    arguments.length - 1,
  #|    prec.dynamic,
  #|    'prec.dynamic',
  #|    ' and a precedence argument'
  #|  );
  #|
  #|  return {
  #|    type: "PREC_DYNAMIC",
  #|    value: number,
  #|    content: normalize(rule)
  #|  };
  #|}
  #|
  #|function repeat(rule) {
  #|  checkArguments(arguments, arguments.length, repeat, 'repeat');
  #|  return {
  #|    type: "REPEAT",
  #|    content: normalize(rule)
  #|  };
  #|}
  #|
  #|function repeat1(rule) {
  #|  checkArguments(arguments, arguments.length, repeat1, 'repeat1');
  #|  return {
  #|    type: "REPEAT1",
  #|    content: normalize(rule)
  #|  };
  #|}
  #|
  #|function seq(...elements) {
  #|  return {
  #|    type: "SEQ",
  #|    members: elements.map(normalize)
  #|  };
  #|}
  #|
  #|class GrammarSymbol {
  #|  constructor(name) {
  #|    this.type = "SYMBOL";
  #|    this.name = name;
  #|  }
  #|}
  #|
  #|function reserved(wordset, rule) {
  #|  if (typeof wordset !== 'string') {
  #|    throw new Error('Invalid reserved word set name: ' + wordset)
  #|  }
  #|  return {
  #|    type: "RESERVED",
  #|    content: normalize(rule),
  #|    context_name: wordset,
  #|  }
  #|}
  #|
  #|function sym(name) {
  #|  return new GrammarSymbol(name);
  #|}
  #|
  #|function token(value) {
  #|  checkArguments(arguments, arguments.length, token, 'token', '', 'literal');
  #|  return {
  #|    type: "TOKEN",
  #|    content: normalize(value)
  #|  };
  #|}
  #|
  #|token.immediate = function (value) {
  #|  checkArguments(arguments, arguments.length, token.immediate, 'token.immediate', '', 'literal');
  #|  return {
  #|    type: "IMMEDIATE_TOKEN",
  #|    content: normalize(value)
  #|  };
  #|}
  #|
  #|function normalize(value) {
  #|  if (typeof value == "undefined")
  #|    throw new Error("Undefined symbol");
  #|
  #|  switch (value.constructor) {
  #|    case String:
  #|      return {
  #|        type: 'STRING',
  #|        value
  #|      };
  #|    case RegExp:
  #|      return value.flags ? {
  #|        type: 'PATTERN',
  #|        value: value.source,
  #|        flags: value.flags
  #|      } : {
  #|        type: 'PATTERN',
  #|        value: value.source
  #|      };
  #|    case RustRegex:
  #|      return {
  #|        type: 'PATTERN',
  #|        value: value.value
  #|      };
  #|    case ReferenceError:
  #|      throw value
  #|    default:
  #|      if (typeof value.type === 'string') {
  #|        return value;
  #|      } else {
  #|        throw new TypeError(`Invalid rule: ${value}`);
  #|      }
  #|  }
  #|}
  #|
  #|function RuleBuilder(ruleMap) {
  #|  return new Proxy({}, {
  #|    get(_, propertyName) {
  #|      const symbol = sym(propertyName);
  #|
  #|      if (!ruleMap || Object.prototype.hasOwnProperty.call(ruleMap, propertyName)) {
  #|        return symbol;
  #|      } else {
  #|        const error = new ReferenceError(`Undefined symbol '${propertyName}'`);
  #|        error.symbol = symbol;
  #|        return error;
  #|      }
  #|    }
  #|  })
  #|}
  #|
  #|function grammar(baseGrammar, options) {
  #|  let inherits = undefined;
  #|
  #|  if (!options) {
  #|    options = baseGrammar;
  #|    baseGrammar = {
  #|      name: null,
  #|      rules: {},
  #|      extras: [normalize(/\s/)],
  #|      conflicts: [],
  #|      externals: [],
  #|      inline: [],
  #|      supertypes: [],
  #|      precedences: [],
  #|      reserved: {},
  #|    };
  #|  } else {
  #|    baseGrammar = baseGrammar.grammar;
  #|    inherits = baseGrammar.name;
  #|  }
  #|
  #|  let externals = baseGrammar.externals;
  #|  if (options.externals) {
  #|    if (typeof options.externals !== "function") {
  #|      throw new Error("Grammar's 'externals' property must be a function.");
  #|    }
  #|
  #|    const externalsRuleBuilder = RuleBuilder(null)
  #|    const externalRules = options.externals.call(externalsRuleBuilder, externalsRuleBuilder, baseGrammar.externals);
  #|
  #|    if (!Array.isArray(externalRules)) {
  #|      throw new Error("Grammar's 'externals' property must return an array of rules.");
  #|    }
  #|
  #|    externals = externalRules.map(normalize);
  #|  }
  #|
  #|  const ruleMap = {};
  #|  for (const key of Object.keys(options.rules)) {
  #|    ruleMap[key] = true;
  #|  }
  #|  for (const key of Object.keys(baseGrammar.rules)) {
  #|    ruleMap[key] = true;
  #|  }
  #|  for (const external of externals) {
  #|    if (typeof external.name === 'string') {
  #|      ruleMap[external.name] = true;
  #|    }
  #|  }
  #|
  #|  const ruleBuilder = RuleBuilder(ruleMap);
  #|
  #|  const name = options.name;
  #|  if (typeof name !== "string") {
  #|    throw new Error("Grammar's 'name' property must be a string.");
  #|  }
  #|
  #|  if (!/^[a-zA-Z_]\w*$/.test(name)) {
  #|    throw new Error("Grammar's 'name' property must not start with a digit and cannot contain non-word characters.");
  #|  }
  #|
  #|  if (inherits && typeof inherits !== "string") {
  #|    throw new Error("Base grammar's 'name' property must be a string.");
  #|  }
  #|
  #|  if (inherits && !/^[a-zA-Z_]\w*$/.test(name)) {
  #|    throw new Error("Base grammar's 'name' property must not start with a digit and cannot contain non-word characters.");
  #|  }
  #|
  #|  const rules = Object.assign({}, baseGrammar.rules);
  #|  if (options.rules) {
  #|    if (typeof options.rules !== "object") {
  #|      throw new Error("Grammar's 'rules' property must be an object.");
  #|    }
  #|
  #|    for (const ruleName of Object.keys(options.rules)) {
  #|      const ruleFn = options.rules[ruleName];
  #|      if (typeof ruleFn !== "function") {
  #|        throw new Error(`Grammar rules must all be functions. '${ruleName}' rule is not.`);
  #|      }
  #|      const rule = ruleFn.call(ruleBuilder, ruleBuilder, baseGrammar.rules[ruleName]);
  #|      if (rule === undefined) {
  #|        throw new Error(`Rule '${ruleName}' returned undefined.`);
  #|      }
  #|      rules[ruleName] = normalize(rule);
  #|    }
  #|  }
  #|
  #|  let reserved = { ...baseGrammar.reserved };
  #|  if (options.reserved) {
  #|    if (typeof options.reserved !== "object") {
  #|      throw new Error("Grammar's 'reserved' property must be an object.");
  #|    }
  #|
  #|    for (const reservedWordSetName of Object.keys(options.reserved)) {
  #|      const reservedWordSetFn = options.reserved[reservedWordSetName]
  #|      if (typeof reservedWordSetFn !== "function") {
  #|        throw new Error(`Grammar reserved word sets must all be functions. '${reservedWordSetName}' is not.`);
  #|      }
  #|
  #|      const reservedTokens = reservedWordSetFn.call(ruleBuilder, ruleBuilder, baseGrammar.reserved[reservedWordSetName]);
  #|
  #|      if (!Array.isArray(reservedTokens)) {
  #|        throw new Error(`Grammar's reserved word set functions must all return arrays of rules. '${reservedWordSetName}' does not.`);
  #|      }
  #|
  #|      reserved[reservedWordSetName] = reservedTokens.map(normalize);
  #|    }
  #|  }
  #|
  #|  let extras = baseGrammar.extras.slice();
  #|  if (options.extras) {
  #|    if (typeof options.extras !== "function") {
  #|      throw new Error("Grammar's 'extras' property must be a function.");
  #|    }
  #|
  #|    extras = options.extras
  #|      .call(ruleBuilder, ruleBuilder, baseGrammar.extras)
  #|
  #|    if (!Array.isArray(extras)) {
  #|      throw new Error("Grammar's 'extras' function must return an array.")
  #|    }
  #|
  #|    extras = extras.map(normalize);
  #|  }
  #|
  #|  let word = baseGrammar.word;
  #|  if (options.word) {
  #|    const wordRule = options.word.call(ruleBuilder, ruleBuilder);
  #|    if (wordRule?.name === 'ReferenceError') {
  #|      throw new Error("Grammar's 'word' property must be a valid named rule.");
  #|    }
  #|
  #|    if (wordRule?.type !== 'SYMBOL' || typeof wordRule.name !== 'string') {
  #|      throw new Error("Grammar's 'word' property must be a named rule.");
  #|    }
  #|
  #|    word = wordRule.name;
  #|  }
  #|
  #|  let conflicts = baseGrammar.conflicts;
  #|  if (options.conflicts) {
  #|    if (typeof options.conflicts !== "function") {
  #|      throw new Error("Grammar's 'conflicts' property must be a function.");
  #|    }
  #|
  #|    const baseConflictRules = baseGrammar.conflicts.map(conflict => conflict.map(sym));
  #|    const conflictRules = options.conflicts.call(ruleBuilder, ruleBuilder, baseConflictRules);
  #|
  #|    if (!Array.isArray(conflictRules)) {
  #|      throw new Error("Grammar's conflicts must be an array of arrays of rules.");
  #|    }
  #|
  #|    conflicts = conflictRules.map(conflictSet => {
  #|      if (!Array.isArray(conflictSet)) {
  #|        throw new Error("Grammar's conflicts must be an array of arrays of rules.");
  #|      }
  #|
  #|      return conflictSet.map(symbol => {
  #|        const rule = normalize(symbol);
  #|        if (rule.type !== 'SYMBOL') {
  #|          throw new Error("Grammar's conflicts must contain only named rules.");
  #|        }
  #|        return rule.name;
  #|      });
  #|    });
  #|  }
  #|
  #|  let inline = baseGrammar.inline;
  #|  if (options.inline) {
  #|    if (typeof options.inline !== "function") {
  #|      throw new Error("Grammar's 'inline' property must be a function.");
  #|    }
  #|
  #|    const baseInlineRules = baseGrammar.inline.map(sym);
  #|    const inlineRules = options.inline.call(ruleBuilder, ruleBuilder, baseInlineRules);
  #|
  #|    if (!Array.isArray(inlineRules)) {
  #|      throw new Error("Grammar's inline must be an array of rules.");
  #|    }
  #|
  #|    inline = inlineRules.filter((symbol, index, self) => {
  #|      if (symbol?.name === 'ReferenceError') {
  #|        console.log(`Warning: inline rule '${symbol.symbol.name}' is not defined.`);
  #|        return false;
  #|      }
  #|      if (symbol?.type !== 'SYMBOL' || typeof symbol.name !== 'string') {
  #|        throw new Error("Grammar's inline property must contain only named rules.");
  #|      }
  #|      if (self.findIndex(s => s?.name === symbol.name) !== index) {
  #|        console.log(`Warning: duplicate inline rule '${symbol.name}'`);
  #|        return false;
  #|      }
  #|      return true;
  #|    }).map(symbol => symbol.name);
  #|  }
  #|
  #|  let supertypes = baseGrammar.supertypes;
  #|  if (options.supertypes) {
  #|    if (typeof options.supertypes !== "function") {
  #|      throw new Error("Grammar's 'supertypes' property must be a function.");
  #|    }
  #|
  #|    const baseSupertypeRules = baseGrammar.supertypes.map(sym);
  #|    const supertypeRules = options.supertypes.call(ruleBuilder, ruleBuilder, baseSupertypeRules);
  #|
  #|    if (!Array.isArray(supertypeRules)) {
  #|      throw new Error("Grammar's supertypes must be an array of rules.");
  #|    }
  #|
  #|    supertypes = supertypeRules.map(symbol => {
  #|      if (symbol?.name === 'ReferenceError') {
  #|        throw new Error(`Supertype rule \`${symbol.symbol.name}\` is not defined.`);
  #|      }
  #|      if (symbol?.type !== 'SYMBOL' || typeof symbol.name !== 'string') {
  #|        throw new Error("Grammar's supertypes property must contain only named rules.");
  #|      }
  #|      return symbol.name;
  #|    });
  #|  }
  #|
  #|  let precedences = baseGrammar.precedences;
  #|  if (options.precedences) {
  #|    if (typeof options.precedences !== "function") {
  #|      throw new Error("Grammar's 'precedences' property must be a function");
  #|    }
  #|    precedences = options.precedences.call(ruleBuilder, ruleBuilder, baseGrammar.precedences);
  #|    if (!Array.isArray(precedences)) {
  #|      throw new Error("Grammar's precedences must be an array of arrays of rules.");
  #|    }
  #|    precedences = precedences.map(list => {
  #|      if (!Array.isArray(list)) {
  #|        throw new Error("Grammar's precedences must be an array of arrays of rules.");
  #|      }
  #|      return list.map(entry => {
  #|        const rule = normalize(entry);
  #|        if (rule.type !== 'STRING' && rule.type !== 'SYMBOL') {
  #|          throw new Error(
  #|            "Grammar's precedences must contain only precedence names or named rules."
  #|          );
  #|        }
  #|        return rule;
  #|      });
  #|    });
  #|  }
  #|
  #|  if (Object.keys(rules).length === 0) {
  #|    throw new Error("Grammar must have at least one rule.");
  #|  }
  #|
  #|  return {
  #|    grammar: {
  #|      name,
  #|      inherits,
  #|      word,
  #|      rules,
  #|      extras,
  #|      conflicts,
  #|      precedences,
  #|      externals,
  #|      inline,
  #|      supertypes,
  #|      reserved,
  #|    },
  #|  };
  #|}
  #|
  #|class RustRegex {
  #|  constructor(value) {
  #|    this.value = value;
  #|  }
  #|}
  #|
  #|function checkArguments(args, ruleCount, caller, callerName, suffix = '', argType = 'rule') {
  #|  // Allow for .map() usage where additional arguments are index and the entire array.
  #|  const isMapCall = ruleCount === 3 && typeof args[1] === 'number' && Array.isArray(args[2]);
  #|  if (isMapCall) {
  #|    ruleCount = typeof args[2] === 'number' ? 1 : args[2].length;
  #|  }
  #|  if (ruleCount > 1 && !isMapCall) {
  #|    const error = new Error([
  #|      `The \`${callerName}\` function only takes one ${argType} argument${suffix}.`,
  #|      `You passed in multiple ${argType}s. Did you mean to call \`seq\`?\n`
  #|    ].join('\n'));
  #|    Error.captureStackTrace(error, caller);
  #|    throw error
  #|  }
  #|}
  #|
  #|function checkPrecedence(value) {
  #|  if (value == null) {
  #|    throw new Error('Missing precedence value');
  #|  }
  #|}
  #|
  #|function getEnv(name) {
  #|  if (globalThis.native) return globalThis.__ts_grammar_path;
  #|  if (globalThis.process) return process.env[name]; // Node/Bun
  #|  if (globalThis.Deno) return Deno.env.get(name); // Deno
  #|  throw Error("Unsupported JS runtime");
  #|}
  #|
  #|globalThis.alias = alias;
  #|globalThis.blank = blank;
  #|globalThis.eof = eof;
  #|globalThis.choice = choice;
  #|globalThis.optional = optional;
  #|globalThis.prec = prec;
  #|globalThis.repeat = repeat;
  #|globalThis.repeat1 = repeat1;
  #|globalThis.reserved = reserved;
  #|globalThis.seq = seq;
  #|globalThis.sym = sym;
  #|globalThis.token = token;
  #|globalThis.grammar = grammar;
  #|globalThis.field = field;
  #|globalThis.RustRegex = RustRegex;
  #|
  #|const grammarPath = getEnv("TREE_SITTER_GRAMMAR_PATH");
  #|let result = await import(grammarPath);
  #|let grammarObj = result.default?.grammar ?? result.grammar;
  #|
  #|if (globalThis.native && !grammarObj) {
  #|  grammarObj = module.exports.grammar;
  #|}
  #|
  #|const object = {
  #|  "$schema": "https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json",
  #|  ...grammarObj,
  #|};
  #|const output = JSON.stringify(object);
  #|
  #|if (globalThis.native) {
  #|  globalThis.output = output;
  #|} else if (globalThis.process) { // Node/Bun
  #|  process.stdout.write(output);
  #|} else if (globalThis.Deno) { // Deno
  #|  Deno.stdout.writeSync(new TextEncoder().encode(output));
  #|} else {
  #|  throw Error("Unsupported JS runtime");
  #|}
  #|
