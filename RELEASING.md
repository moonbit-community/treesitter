# Releasing

The module is `moonbit-community/treesitter`. Initial releases are experimental;
keep the README and [compatibility document](COMPATIBILITY.md) explicit about
the remaining porting work.

## Validate a release

1. Update `moon.mod` and the versioned dependency that `loader/mbtx.mbt`
   writes into the workspaces of `.mbtx` grammars and scanner drivers
   together. The CLI reports the upstream version it ports
   (`cli/commands/commands.mbt`), which changes only with the upstream
   baseline. Update installation examples and compatibility notes.
2. Run `sh tools/check.sh`, `moon info`, `moon info --target native`, and the
   differential oracle (`CARGO="cargo +1.97.1" sh tools/oracle/oracle_setup.sh`,
   `sh tools/oracle/oracle.sh`, `sh tools/oracle/diff_cli.sh`). Review generated
   interface changes.
3. Run `moon package --list` and inspect the package contents. `moon publish
   --dry-run` also validates the extracted package and authenticates with
   Mooncakes; it needs credentials for the module's namespace.
4. Run the requested Codex CLI ultra release review, resolve actionable
   findings, push the release commit, and wait for all hosted CI jobs to pass.

## Publish

The GitHub Actions workflow [publish.yml](.github/workflows/publish.yml) runs
when a GitHub release is published, or can be dispatched with an existing tag.
The tag must be exactly `v` plus the version in `moon.mod`, for example `v0.1.0`.
Publish only a commit whose CI checks passed.

The workflow uses the existing organization Actions secret
`MOONCAKES_MOONBIT_COMMUNITY_TOKEN`, with repository secret `MOONCAKES_TOKEN` as
a fallback. The value must be the complete Mooncakes credentials JSON for the
`moonbit-community` account. Credentials for a different namespace are rejected
by the registry. Do not commit credentials
or paste them into issues or logs. The workflow writes the secret to a temporary
credentials file with restricted permissions and removes it after publication.

Create a GitHub prerelease for an experimental version, linking its compatibility
document in the release notes. The workflow validates the tag and package, runs
the test suite, then performs a dry run followed by `moon publish`. Check its
result before claiming that the version is available on Mooncakes. Do not rerun
a successful publish for an already published version.

## Verify the registry artifact

From a fresh directory outside this checkout, with `TREESITTER_MBT_ROOT` unset:

The publish workflow runs `python3 tools/check_registry.py VERSION` to automate
the checks below. This can also be run locally after publication.

1. Create a MoonBit project and add `moonbit-community/treesitter@VERSION`.
   Import the runtime, compile a small grammar, and parse sample text.
2. Run `moon install moonbit-community/treesitter/cmd/treesitter@VERSION` into
   a separate temporary binary directory. Use that installed executable, not
   one inside this checkout.
3. Run `treesitter init words ./words`, then generate and test its grammar.
   This exercises the loader's versioned registry dependency.
4. Copy the quoted-language example to the temporary directory and run its
   grammar and scanner through the installed CLI. This also exercises scanner
   compilation without a checkout fallback.

Record the release URL, Mooncakes result, CI run and installation checks in
`PLAN.md`. An unfinished compatibility milestone stays unfinished after release.
