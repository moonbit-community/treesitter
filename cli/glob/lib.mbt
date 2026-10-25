// Port of glob 0.3.4 src/lib.rs.
//
// Support for matching file paths against Unix shell style patterns.
//
// The `glob` and `glob_with` functions allow querying the filesystem for all
// files that match a particular pattern (similar to the libc `glob` function).
// The methods on the `Pattern` type provide functionality for checking if
// individual paths match a particular pattern (similar to the libc `fnmatch`
// function).
//
// Only the Unix code paths are ported (`/` is the only separator, there are
// no path prefixes and no verbatim paths). Rust `PathBuf`s are `String`s with
// `std::path` semantics (`@support.path_components`, `path_push` below);
// `char` indices (`PatternError::pos`) count Unicode scalar values, as Rust
// does, not UTF-16 code units.

///|
/// An iterator that yields `Path`s from the filesystem that match a particular
/// pattern.
///
/// Note that it yields `GlobResult` in order to report any `IoErrors` that may
/// arise during iteration. If a directory matches but is unreadable,
/// thereby preventing its contents from being checked for matches, a
/// `GlobError` is returned to express this.
///
/// See the `glob` function for more details.
pub struct Paths {
  priv dir_patterns : Array[Pattern]
  priv require_dir : Bool
  priv options : MatchOptions
  priv todo : Array[Result[(PathWrapper, Int32), GlobError]]
  priv mut scope : PathWrapper?
}

///|
/// `usize::MAX`: the index of a `todo` entry that `fill_todo` already
/// matched completely.
let usize_max : Int32 = -1

///|
/// Return an iterator that produces all the `Path`s that match the given
/// pattern using default match options, which may be absolute or relative to
/// the current working directory.
///
/// This may return an error if the pattern is invalid.
///
/// This method uses the default match options and is equivalent to calling
/// `glob_with(pattern, MatchOptions::new())`. Use `glob_with` directly if you
/// want to use non-default match options.
///
/// When iterating, each result is a `GlobResult` which expresses the
/// possibility that there was an `IoError` when attempting to read the contents
/// of the matched path.  In other words, each item returned by the iterator
/// will either be an `Ok(Path)` if the path matched, or an `Err(GlobError)` if
/// the path (partially) matched _but_ its contents could not be read in order
/// to determine if its contents matched.
///
/// See the `Paths` documentation for more information.
///
/// Paths are yielded in alphabetical order.
pub async fn glob(pattern : String) -> Paths {
  glob_with(pattern, MatchOptions::new())
}

///|
/// Return an iterator that produces all the `Path`s that match the given
/// pattern using the specified match options, which may be absolute or relative
/// to the current working directory.
///
/// This may return an error (a `PatternError`) if the pattern is invalid.
///
/// This function accepts Unix shell style patterns as described by
/// `Pattern::new(..)`.  The options given are passed through unchanged to
/// `Pattern::matches_with(..)` with the exception that
/// `require_literal_separator` is always set to `true` regardless of the value
/// passed to this function.
///
/// Paths are yielded in alphabetical order.
pub async fn glob_with(pattern : String, options : MatchOptions) -> Paths {
  // (`check_windows_verbatim` is always false and `to_scope` is the identity
  // on Unix.)

  // make sure that the pattern is valid first, else early return with error
  let _ = Pattern::new(pattern)
  let components = @support.path_components(pattern)
  let mut first = 0
  while first < components.length() && components[first] is RootDir {
    first += 1
  }
  let rest = collect_path(components[first:])
  let normalized_pattern = collect_path(components[:])
  let root_len = @support.utf8_len(normalized_pattern) - @support.utf8_len(rest)
  let root = if root_len > 0 {
    Some(pattern.unsafe_substring(start=0, end=utf8_index(pattern, root_len)))
  } else {
    None
  }
  let scope = root.unwrap_or(".")
  let scope = PathWrapper::from_path(scope)
  let dir_patterns = []
  let pattern_len = @support.utf8_len(pattern)
  let start = utf8_index(
    pattern,
    if root_len < pattern_len {
      root_len
    } else {
      pattern_len
    },
  )
  let components = split_terminator(
    pattern.unsafe_substring(start~, end=pattern.length()),
  )
  for component in components {
    dir_patterns.push(Pattern::new(component))
  }
  if root_len == pattern_len {
    dir_patterns.push({
      original: "",
      tokens: [],
      is_recursive: false,
      has_metachars: false,
    })
  }
  let require_dir = pattern.has_suffix("/")
  let todo = []
  { dir_patterns, require_dir, options, todo, scope: Some(scope), }
}

///|
/// `str::split_terminator(path::is_separator)`.
fn split_terminator(s : String) -> Array[String] {
  if s.is_empty() {
    return []
  }
  let parts = s.split("/").map(p => p.to_owned()).collect()
  if parts.last() is Some("") {
    parts.pop() |> ignore
  }
  parts
}

///|
/// The index in `s` of the character that starts at UTF-8 byte offset
/// `bytes` (Rust's `&s[..bytes]`).
fn utf8_index(s : String, bytes : Int32) -> Int32 {
  let mut n = 0
  let mut index = 0
  for c in s {
    if n >= bytes {
      break
    }
    let code = c.to_int()
    n += if code < 0x80 {
      1
    } else if code < 0x800 {
      2
    } else if code < 0x10000 {
      3
    } else {
      4
    }
    index += if code >= 0x10000 { 2 } else { 1 }
  }
  index
}

///|
/// `PathBuf::push` (Unix): an absolute `path` replaces `buf`; otherwise a
/// separator is added unless `buf` is empty or already ends with one.
fn path_push(buf : String, path : String) -> String {
  if path.has_prefix("/") {
    path
  } else if buf.is_empty() || buf.has_suffix("/") {
    buf + path
  } else {
    buf + "/" + path
  }
}

///|
/// `Path::join`.
fn path_join(base : String, path : String) -> String {
  path_push(base, path)
}

///|
/// `components.collect::<PathBuf>()`.
fn collect_path(components : ArrayView[@support.PathComponent]) -> String {
  let mut buf = ""
  for c in components {
    buf = path_push(buf, c.as_str())
  }
  buf
}

///|
/// A glob iteration error.
///
/// This is typically returned when a particular path cannot be read
/// to determine if its contents match the glob pattern. This is possible
/// if the program lacks the appropriate permissions, for example.
pub suberror GlobError {
  GlobError(path~ : String, error~ : Error)
}

///|
/// The Path that the error corresponds to.
pub fn GlobError::path(self : GlobError) -> String {
  let GlobError(path~, ..) = self
  path
}

///|
/// The error in question.
pub fn GlobError::error(self : GlobError) -> Error {
  let GlobError(error~, ..) = self
  error
}

///|
pub impl Show for GlobError with fn output(self, logger) {
  let GlobError(path~, error~) = self
  logger.write_string(
    "attempting to read `\{path}` resulted in an error: \{@support.io_error_message(error)}",
  )
}

///|
priv struct PathWrapper {
  path : String
  is_directory : Bool
}

///|
/// `PathWrapper::from_dir_entry`: `file_type` of a `DirEntry` is the type
/// of the entry itself (`lstat`); a symbolic link is resolved with
/// `fs::metadata`.
async fn PathWrapper::from_dir_entry(path : String) -> PathWrapper {
  let is_directory = match
    (@fs.kind(path, follow_symlink=false) catch { _ => @fs.FileKind::SymLink }) {
    // We need to use fs::metadata to resolve the actual path
    // if it's a symlink.
    SymLink => is_dir(path)
    kind => kind is Directory
  }
  { path, is_directory, }
}

///|
async fn PathWrapper::from_path(path : String) -> PathWrapper {
  let is_directory = is_dir(path)
  { path, is_directory, }
}

///|
fn PathWrapper::into_path(self : PathWrapper) -> String {
  self.path
}

///|
/// `fs::metadata(path).map(|m| m.is_dir()).unwrap_or(false)`.
async fn is_dir(path : String) -> Bool {
  (@fs.kind(path, follow_symlink=true) catch { _ => @fs.FileKind::Unknown })
  is Directory
}

///|
/// `fs::metadata(path).is_ok()` (`follow_symlink=true`) or
/// `fs::symlink_metadata(path).is_ok()`.
async fn metadata_ok(path : String, follow_symlink~ : Bool) -> Bool {
  try @fs.kind(path, follow_symlink~) catch {
    _ => false
  } noraise {
    _ => true
  }
}

///|
/// An alias for a glob iteration result.
///
/// This represents either a matched path or a glob iteration error,
/// such as failing to read a particular directory's contents.
pub type GlobResult = Result[String, GlobError]

///|
/// `Iterator::next`.
pub async fn Paths::next(self : Paths) -> GlobResult? {
  // the todo buffer hasn't been initialized yet, so it's done at this
  // point rather than in glob() so that the errors are unified that is,
  // failing to fill the buffer is an iteration error construction of the
  // iterator (i.e. glob()) only fails if it fails to compile the Pattern
  if self.scope is Some(scope) {
    self.scope = None
    if !self.dir_patterns.is_empty() {
      fill_todo(self.todo, self.dir_patterns, 0, scope, self.options)
    }
  }
  for ;; {
    if self.dir_patterns.is_empty() || self.todo.is_empty() {
      return None
    }
    let (path, idx) = match self.todo.pop().unwrap() {
      Ok(pair) => pair
      Err(e) => return Some(Err(e))
    }
    let mut idx = idx

    // idx -1: was already checked by fill_todo, maybe path was '.' or
    // '..' that we can't match here because of normalization.
    if idx == usize_max {
      if self.require_dir && !path.is_directory {
        continue
      }
      return Some(Ok(path.into_path()))
    }
    if self.dir_patterns[idx].is_recursive {
      let mut next = idx

      // collapse consecutive recursive patterns
      while next + 1 < self.dir_patterns.length() &&
            self.dir_patterns[next + 1].is_recursive {
        next += 1
      }
      if path.is_directory {
        // the path is a directory, so it's a match

        // push this directory's contents
        fill_todo(self.todo, self.dir_patterns, next, path, self.options)
        if next == self.dir_patterns.length() - 1 {
          // pattern ends in recursive pattern, so return this
          // directory as a result
          return Some(Ok(path.into_path()))
        } else {
          // advanced to the next pattern for this path
          idx = next + 1
        }
      } else if next == self.dir_patterns.length() - 1 {
        // not a directory and it's the last pattern, meaning no
        // match
        continue
      } else {
        // advanced to the next pattern for this path
        idx = next + 1
      }
    }

    // not recursive, so match normally
    let file_name = match @support.path_file_name(path.path) {
      // FIXME (#9639): How do we handle non-utf8 filenames?
      // Ignore them for now; ideally we'd still match them
      // against a *
      None => continue
      Some(x) => x
    }
    if self.dir_patterns[idx].matches_with(file_name, self.options) {
      if idx == self.dir_patterns.length() - 1 {
        // it is not possible for a pattern to match a directory
        // *AND* its children so we don't need to check the
        // children

        if !self.require_dir || path.is_directory {
          return Some(Ok(path.into_path()))
        }
      } else {
        fill_todo(self.todo, self.dir_patterns, idx + 1, path, self.options)
      }
    }
  }
}

///|
/// A pattern parsing error.
pub suberror PatternError {
  PatternError(pos~ : Int32, msg~ : String)
} derive(Debug)

///|
/// The approximate character index of where the error occurred.
pub fn PatternError::pos(self : PatternError) -> Int32 {
  let PatternError(pos~, ..) = self
  pos
}

///|
/// A message describing the error.
pub fn PatternError::msg(self : PatternError) -> String {
  let PatternError(msg~, ..) = self
  msg
}

///|
pub impl Show for PatternError with fn output(self, logger) {
  let PatternError(pos~, msg~) = self
  logger.write_string("Pattern syntax error near position \{pos}: \{msg}")
}

///|
/// A compiled Unix shell style pattern.
///
/// - `?` matches any single character.
///
/// - `*` matches any (possibly empty) sequence of characters.
///
/// - `**` matches the current directory and arbitrary
///   subdirectories. To match files in arbitrary subdirectories, use
///   `**/*`.
///
///   This sequence **must** form a single path component, so both
///   `**a` and `b**` are invalid and will result in an error.  A
///   sequence of more than two consecutive `*` characters is also
///   invalid.
///
/// - `[...]` matches any character inside the brackets.  Character sequences
///   can also specify ranges of characters, as ordered by Unicode, so e.g.
///   `[0-9]` specifies any character between 0 and 9 inclusive. An unclosed
///   bracket is invalid.
///
/// - `[!...]` is the negation of `[...]`, i.e. it matches any characters
///   **not** in the brackets.
///
/// - The metacharacters `?`, `*`, `[`, `]` can be matched by using brackets
///   (e.g. `[?]`).  When a `]` occurs immediately following `[` or `[!` then it
///   is interpreted as being part of, rather then ending, the character set, so
///   `]` and NOT `]` can be matched by `[]]` and `[!]]` respectively.  The `-`
///   character can be specified inside a character sequence pattern by placing
///   it at the start or the end, e.g. `[abc-]`.
pub struct Pattern {
  priv original : String
  priv tokens : Array[PatternToken]
  priv is_recursive : Bool
  /// A bool value that indicates whether the pattern contains any metacharacters.
  /// We use this information for some fast path optimizations.
  priv has_metachars : Bool
} derive(Eq, Debug)

///|
/// Show the original glob pattern.
pub impl Show for Pattern with fn output(self, logger) {
  logger.write_string(self.original)
}

///|
priv enum PatternToken {
  Char(Char)
  AnyChar
  AnySequence
  AnyRecursiveSequence
  AnyWithin(Array[CharSpecifier])
  AnyExcept(Array[CharSpecifier])
} derive(Eq, Debug)

///|
priv enum CharSpecifier {
  SingleChar(Char)
  CharRange(Char, Char)
} derive(Eq, Debug)

///|
priv enum MatchResult {
  Match
  SubPatternDoesntMatch
  EntirePatternDoesntMatch
} derive(Eq)

///|
let error_wildcards : String = "wildcards are either regular `*` or recursive `**`"

///|
let error_recursive_wildcards : String = "recursive wildcards must form a single path component"

///|
let error_invalid_range : String = "invalid range pattern"

///|
/// `path::is_separator` (Unix).
fn is_separator(c : Char) -> Bool {
  c == '/'
}

///|
/// This function compiles Unix shell style patterns.
///
/// An invalid glob pattern will yield a `PatternError`.
pub fn Pattern::new(pattern : String) -> Pattern raise PatternError {
  let chars : Array[Char] = pattern.iter().collect()
  let tokens = []
  let mut is_recursive = false
  let mut has_metachars = false
  let mut i = 0
  while i < chars.length() {
    match chars[i] {
      '?' => {
        has_metachars = true
        tokens.push(AnyChar)
        i += 1
      }
      '*' => {
        has_metachars = true
        let old = i
        while i < chars.length() && chars[i] == '*' {
          i += 1
        }
        let count = i - old
        if count > 2 {
          raise PatternError(pos=old + 2, msg=error_wildcards)
        } else if count == 2 {
          // ** can only be an entire path component
          // i.e. a/**/b is valid, but a**/b or a/**b is not
          // invalid matches are treated literally
          let is_valid = if i == 2 || is_separator(chars[i - count - 1]) {
            // it ends in a '/'
            if i < chars.length() && is_separator(chars[i]) {
              i += 1
              true
              // or the pattern ends here
              // this enables the existing globbing mechanism
            } else if i == chars.length() {
              true
              // `**` ends in non-separator
            } else {
              raise PatternError(pos=i, msg=error_recursive_wildcards)
            }
            // `**` begins with non-separator
          } else {
            raise PatternError(pos=old - 1, msg=error_recursive_wildcards)
          }
          if is_valid {
            // collapse consecutive AnyRecursiveSequence to a
            // single one

            let tokens_len = tokens.length()
            if !(tokens_len > 1 &&
              tokens[tokens_len - 1] == AnyRecursiveSequence) {
              is_recursive = true
              tokens.push(AnyRecursiveSequence)
            }
          }
        } else {
          tokens.push(AnySequence)
        }
      }
      '[' => {
        has_metachars = true
        if i + 4 <= chars.length() && chars[i + 1] == '!' {
          match position(chars, i + 3, ']') {
            None => ()
            Some(j) => {
              let cs = parse_char_specifiers(chars[i + 2:i + 3 + j])
              tokens.push(AnyExcept(cs))
              i += j + 4
              continue
            }
          }
        } else if i + 3 <= chars.length() && chars[i + 1] != '!' {
          match position(chars, i + 2, ']') {
            None => ()
            Some(j) => {
              let cs = parse_char_specifiers(chars[i + 1:i + 2 + j])
              tokens.push(AnyWithin(cs))
              i += j + 3
              continue
            }
          }
        }

        // if we get here then this is not a valid range pattern
        raise PatternError(pos=i, msg=error_invalid_range)
      }
      c => {
        tokens.push(Char(c))
        i += 1
      }
    }
  }
  { tokens, original: pattern, is_recursive, has_metachars, }
}

///|
/// `chars[start..].iter().position(|x| *x == c)`.
fn position(chars : Array[Char], start : Int32, c : Char) -> Int32? {
  for k in start..<chars.length() {
    if chars[k] == c {
      return Some(k - start)
    }
  }
  None
}

///|
/// Escape metacharacters within the given string by surrounding them in
/// brackets. The resulting string will, when compiled into a `Pattern`,
/// match the input string and nothing else.
pub fn Pattern::escape(s : String) -> String {
  let escaped = StringBuilder()
  for c in s {
    match c {
      // note that ! does not need escaping because it is only special
      // inside brackets
      '?' | '*' | '[' | ']' => {
        escaped.write_char('[')
        escaped.write_char(c)
        escaped.write_char(']')
      }
      c => escaped.write_char(c)
    }
  }
  escaped.to_string()
}

///|
/// Return if the given `str` matches this `Pattern` using the default
/// match options (i.e. `MatchOptions::new()`).
pub fn Pattern::matches(self : Pattern, str : String) -> Bool {
  self.matches_with(str, MatchOptions::new())
}

///|
/// Return if the given `Path`, when converted to a `str`, matches this
/// `Pattern` using the default match options (i.e. `MatchOptions::new()`).
pub fn Pattern::matches_path(self : Pattern, path : String) -> Bool {
  self.matches(path)
}

///|
/// Return if the given `str` matches this `Pattern` using the specified
/// match options.
pub fn Pattern::matches_with(
  self : Pattern,
  str : String,
  options : MatchOptions,
) -> Bool {
  let file : Array[Char] = str.iter().collect()
  self.matches_from(true, file, 0, 0, options) == Match
}

///|
/// Return if the given `Path`, when converted to a `str`, matches this
/// `Pattern` using the specified match options.
pub fn Pattern::matches_path_with(
  self : Pattern,
  path : String,
  options : MatchOptions,
) -> Bool {
  self.matches_with(path, options)
}

///|
/// Access the original glob pattern.
pub fn Pattern::as_str(self : Pattern) -> String {
  self.original
}

///|
/// `file` is the `Chars` iterator of the Rust code: the characters of
/// `chars` from index `pos` on.
fn Pattern::matches_from(
  self : Pattern,
  follows_separator : Bool,
  chars : Array[Char],
  pos : Int32,
  i : Int32,
  options : MatchOptions,
) -> MatchResult {
  let mut follows_separator = follows_separator
  let mut pos = pos
  for ti in 0..<(self.tokens.length() - i) {
    let token = self.tokens[i + ti]
    match token {
      AnySequence | AnyRecursiveSequence => {
        // ** must be at the start.

        // Empty match
        match
          self.matches_from(follows_separator, chars, pos, i + ti + 1, options) {
          SubPatternDoesntMatch => () // keep trying
          m => return m
        }
        while pos < chars.length() {
          let c = chars[pos]
          pos += 1
          if follows_separator &&
            options.require_literal_leading_dot &&
            c == '.' {
            return SubPatternDoesntMatch
          }
          follows_separator = is_separator(c)
          match token {
            AnyRecursiveSequence if !follows_separator => continue
            AnySequence if options.require_literal_separator &&
              follows_separator => return SubPatternDoesntMatch
            _ => ()
          }
          match
            self.matches_from(
              follows_separator,
              chars,
              pos,
              i + ti + 1,
              options,
            ) {
            SubPatternDoesntMatch => () // keep trying
            m => return m
          }
        }
      }
      _ => {
        guard pos < chars.length() else { return EntirePatternDoesntMatch }
        let c = chars[pos]
        pos += 1
        let is_sep = is_separator(c)
        let matched = match token {
          AnyChar | AnyWithin(_) | AnyExcept(_) if (
              options.require_literal_separator && is_sep
            ) ||
            (
              follows_separator &&
              options.require_literal_leading_dot &&
              c == '.'
            ) => false
          AnyChar => true
          AnyWithin(specifiers) => in_char_specifiers(specifiers, c, options)
          AnyExcept(specifiers) => !in_char_specifiers(specifiers, c, options)
          Char(c2) => chars_eq(c, c2, options.case_sensitive)
          AnySequence | AnyRecursiveSequence => panic()
        }
        if !matched {
          return SubPatternDoesntMatch
        }
        follows_separator = is_sep
      }
    }
  }

  // Iter is fused.
  if pos >= chars.length() {
    Match
  } else {
    SubPatternDoesntMatch
  }
}

///|
/// Fills `todo` with paths under `path` to be matched by `patterns[idx]`,
/// special-casing patterns to match `.` and `..`, and avoiding `readdir()`
/// calls when there are no metacharacters in the pattern.
async fn fill_todo(
  todo : Array[Result[(PathWrapper, Int32), GlobError]],
  patterns : Array[Pattern],
  idx : Int32,
  path : PathWrapper,
  options : MatchOptions,
) -> Unit {
  async fn add(
    todo : Array[Result[(PathWrapper, Int32), GlobError]],
    next_path : PathWrapper,
  ) -> Unit {
    if idx + 1 == patterns.length() {
      // We know it's good, so don't make the iterator match this path
      // against the pattern again. In particular, it can't match
      // . or .. globs since these never show up as path components.
      todo.push(Ok((next_path, usize_max)))
    } else {
      fill_todo(todo, patterns, idx + 1, next_path, options)
    }
  }

  let pattern = patterns[idx]
  let is_dir = path.is_directory
  let curdir = @support.path_eq(path.path, ".")
  match (pattern.has_metachars, is_dir) {
    (false, _) => {
      let s = pattern.as_str()

      // This pattern component doesn't have any metacharacters, so we
      // don't need to read the current directory to know where to
      // continue. So instead of passing control back to the iterator,
      // we can just check for that one entry and potentially recurse
      // right away.
      let special = "." == s || ".." == s
      let next_path = if curdir { s } else { path_join(path.path, s) }
      let next_path = PathWrapper::from_path(next_path)
      if (special && is_dir) ||
        (
          !special &&
          (
            metadata_ok(next_path.path, follow_symlink=true) ||
            metadata_ok(next_path.path, follow_symlink=false)
          )
        ) {
        add(todo, next_path)
      }
    }
    (true, true) => {
      let dirs : Result[Array[(PathWrapper, String)], Error] = try
        @fs.readdir(path.path)
      catch {
        e => Err(e)
      } noraise {
        names => {
          let children = []
          for name in names {
            // We sort by filename a few lines below. However, it is actually quite
            // expensive to extract the filename from PathBuf. Since we already know the
            // filename from `DirEntry` here, we store it proactively (we still
            // have to heap allocate it).
            // Then we use this cached filename for sorting, and further on work only
            // with the full path.
            let child = if curdir { name } else { path_join(path.path, name) }
            children.push((PathWrapper::from_dir_entry(child), name))
          }
          Ok(children)
        }
      }
      match dirs {
        Ok(children) => {
          let children = if options.require_literal_leading_dot {
            children.filter(x => !x.1.has_prefix("."))
          } else {
            children
          }
          // Rust's stable `sort_by` on `OsString`s (bytes, descending); the
          // names in one directory are distinct, so there are no ties.
          children.sort_by((p1, p2) => compare_os_str(p2.1, p1.1))
          for x in children {
            todo.push(Ok((x.0, idx)))
          }

          // Matching the special directory entries . and .. that
          // refer to the current and parent directory respectively
          // requires that the pattern has a leading dot, even if the
          // `MatchOptions` field `require_literal_leading_dot` is not
          // set.
          if !pattern.tokens.is_empty() && pattern.tokens[0] == Char('.') {
            for special in [".", ".."] {
              if pattern.matches_with(special, options) {
                add(todo, PathWrapper::from_path(path_join(path.path, special)))
              }
            }
          }
        }
        Err(e) => todo.push(Err(GlobError(path=path.path, error=e)))
      }
    }
    (true, false) => () // not a directory, nothing more to find
  }
}

///|
/// `Ord for OsStr` on Unix: byte-wise comparison of the UTF-8 encodings,
/// which orders like a comparison of the Unicode scalar values.
fn compare_os_str(a : String, b : String) -> Int32 {
  let a : Array[Char] = a.iter().collect()
  let b : Array[Char] = b.iter().collect()
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    let c = a[i].compare(b[i])
    if c != 0 {
      return c
    }
  }
  a.length().compare(b.length())
}

///|
fn parse_char_specifiers(s : ArrayView[Char]) -> Array[CharSpecifier] {
  let cs = []
  let mut i = 0
  while i < s.length() {
    if i + 3 <= s.length() && s[i + 1] == '-' {
      cs.push(CharRange(s[i], s[i + 2]))
      i += 3
    } else {
      cs.push(SingleChar(s[i]))
      i += 1
    }
  }
  cs
}

///|
fn in_char_specifiers(
  specifiers : Array[CharSpecifier],
  c : Char,
  options : MatchOptions,
) -> Bool {
  for specifier in specifiers {
    match specifier {
      SingleChar(sc) =>
        if chars_eq(c, sc, options.case_sensitive) {
          return true
        }
      CharRange(start, end) => {
        // FIXME: work with non-ascii chars properly (issue #1347)
        if !options.case_sensitive &&
          c.is_ascii() &&
          start.is_ascii() &&
          end.is_ascii() {
          let start = ascii_lowercase(start)
          let end = ascii_lowercase(end)
          let start_up = ascii_uppercase(start)
          let end_up = ascii_uppercase(end)

          // only allow case insensitive matching when
          // both start and end are within a-z or A-Z
          if start != start_up && end != end_up {
            let c = ascii_lowercase(c)
            if c >= start && c <= end {
              return true
            }
          }
        }
        if c >= start && c <= end {
          return true
        }
      }
    }
  }
  false
}

///|
fn ascii_lowercase(c : Char) -> Char {
  if c >= 'A' && c <= 'Z' {
    (c.to_int() + 32).unsafe_to_char()
  } else {
    c
  }
}

///|
fn ascii_uppercase(c : Char) -> Char {
  if c >= 'a' && c <= 'z' {
    (c.to_int() - 32).unsafe_to_char()
  } else {
    c
  }
}

///|
/// A helper function to determine if two chars are (possibly case-insensitively) equal.
fn chars_eq(a : Char, b : Char, case_sensitive : Bool) -> Bool {
  if !case_sensitive && a.is_ascii() && b.is_ascii() {
    // FIXME: work with non-ascii chars properly (issue #9084)
    ascii_lowercase(a) == ascii_lowercase(b)
  } else {
    a == b
  }
}

///|
/// Configuration options to modify the behaviour of `Pattern::matches_with(..)`.
pub(all) struct MatchOptions {
  /// Whether or not patterns should be matched in a case-sensitive manner.
  /// This currently only considers upper/lower case relationships between
  /// ASCII characters, but in future this might be extended to work with
  /// Unicode.
  case_sensitive : Bool
  /// Whether or not path-component separator characters (e.g. `/` on
  /// Posix) must be matched by a literal `/`, rather than by `*` or `?` or
  /// `[...]`.
  require_literal_separator : Bool
  /// Whether or not paths that contain components that start with a `.`
  /// will require that `.` appears literally in the pattern; `*`, `?`, `**`,
  /// or `[...]` will not match. This is useful because such files are
  /// conventionally considered hidden on Unix systems and it might be
  /// desirable to skip them when listing files.
  require_literal_leading_dot : Bool
} derive(Eq, Debug)

///|
/// Constructs a new `MatchOptions` with default field values. This is used
/// when calling functions that do not take an explicit `MatchOptions`
/// parameter.
///
/// This function always returns this value:
///
/// ```mbt nocheck
/// {
///   case_sensitive: true,
///   require_literal_separator: false,
///   require_literal_leading_dot: false,
/// }
/// ```
///
/// # Note
/// The behavior of this method doesn't match `default()`'s. This returns
/// `case_sensitive` as `true` while `default()` does it as `false`.
pub fn MatchOptions::new() -> MatchOptions {
  {
    case_sensitive: true,
    require_literal_separator: false,
    require_literal_leading_dot: false,
  }
}
