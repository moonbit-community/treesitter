// Port of the loader-driven directory walks of tree-sitter
// crates/cli/src/test_highlight.rs and test_tags.rs (`test_highlights`,
// `test_tags`). The assertion checks are query_testing.

///|
/// `fs::read_dir` order (the order the file system returns entries).
async fn read_dir_paths(directory : String) -> Array[(String, String)] {
  @fs.readdir(directory, include_hidden=true).map(name => {
    (@support.path_join(directory, name), name)
  })
}

///|
async fn is_nonempty_dir(path : String) -> Bool {
  let kind = @fs.kind(path, follow_symlink=true) catch { _ => return false }
  kind is Directory && !@fs.readdir(path, include_hidden=true).is_empty()
}

///|
/// `test_highlight` with injected languages loaded on demand.
async fn test_highlight_loading(
  loader : @loader.Loader,
  highlighter : @highlight.Highlighter,
  config : @highlight.HighlightConfiguration,
  source : Bytes,
) -> Int32 {
  for ;; {
    let result = try
      @query_testing.test_highlight(
        highlighter,
        config,
        loader.highlight_names(),
        loader.injection_callback(),
        source,
      )
    catch {
      e => if loader.has_pending_injections() { None } else { raise e }
    } noraise {
      count => Some(count)
    }
    if loader.has_pending_injections() {
      loader.resolve_pending_injections()
      continue
    }
    return result.unwrap()
  }
}

///|
pub async fn test_highlights(
  loader : @loader.Loader,
  loader_config : @loader.LoaderConfig,
  highlighter : @highlight.Highlighter,
  directory : String,
  test_summary : TestSummary,
) -> Unit {
  let mut failed = false
  for entry in read_dir_paths(directory) {
    let (test_file_path, test_file_name) = entry
    if is_nonempty_dir(test_file_path) {
      test_summary.highlight_results.add_group(test_file_name)
      test_highlights(
        loader, loader_config, highlighter, test_file_path, test_summary,
      ) catch {
        _ => failed = true
      }
      test_summary.highlight_results.pop_traversal()
    } else {
      guard loader.language_configuration_for_file_name(test_file_path)
        is Some((language, language_config)) else {
        raise anyhow(lang_not_found_for_path(test_file_path, loader_config))
      }
      guard language_config.highlight_config(language, None)
        is Some(highlight_config) else {
        raise anyhow("No highlighting config found for \{test_file_path}")
      }
      let source = @fs.read_file(test_file_path).binary()
      let outcome = try
        test_highlight_loading(loader, highlighter, highlight_config, source)
      catch {
        e => {
          failed = true
          AssertionFailed(error=error_message(e))
        }
      } noraise {
        assertion_count => AssertionPassed(assertion_count~)
      }
      test_summary.highlight_results.add_case({
        name: test_file_name,
        info: AssertionTest(outcome~, test_num=test_summary.test_num),
      })
      test_summary.test_num += 1
    }
  }
  if failed {
    raise anyhow("")
  }
}

///|
pub async fn test_tags(
  loader : @loader.Loader,
  loader_config : @loader.LoaderConfig,
  tags_context : @tags.TagsContext,
  directory : String,
  test_summary : TestSummary,
) -> Unit {
  let mut failed = false
  for entry in read_dir_paths(directory) {
    let (test_file_path, test_file_name) = entry
    if is_nonempty_dir(test_file_path) {
      test_summary.tag_results.add_group(test_file_name)
      test_tags(
        loader, loader_config, tags_context, test_file_path, test_summary,
      ) catch {
        _ => failed = true
      }
      test_summary.tag_results.pop_traversal()
    } else {
      guard loader.language_configuration_for_file_name(test_file_path)
        is Some((language, language_config)) else {
        raise anyhow(lang_not_found_for_path(test_file_path, loader_config))
      }
      guard language_config.tags_config(language) is Some(tags_config) else {
        raise anyhow("No tags config found for \{test_file_path}")
      }
      let source = @fs.read_file(test_file_path).binary()
      let outcome = try
        @query_testing.test_tag(tags_context, tags_config, source)
      catch {
        e => {
          failed = true
          AssertionFailed(error=error_message(e))
        }
      } noraise {
        assertion_count => AssertionPassed(assertion_count~)
      }
      test_summary.tag_results.add_case({
        name: test_file_name,
        info: AssertionTest(outcome~, test_num=test_summary.test_num),
      })
      test_summary.test_num += 1
    }
  }
  if failed {
    raise anyhow("")
  }
}
