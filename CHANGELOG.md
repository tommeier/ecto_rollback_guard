# Changelog

## v0.2.0

### Bug Fixes

- Fix `log_preview/3` crash when preview returns an error
- Fix SQL regex to capture schema-qualified table names (e.g., `DROP TABLE public.users`)
- Fix detector missing `def down, do: nil` as irreversible (nil body detection)
- `preview/3` now returns `{:error, reason}` instead of crashing on failures

### Improvements

- Comprehensive test suite: 112 tests covering all public API, detector branches,
  reporter operation types, enricher edge cases, mix task, and preview paths

## v0.1.0

- Initial release
- AST-based detection of destructive rollback operations
- PostgreSQL row count enrichment
- `mix ecto_rollback_guard.preview` task
- Terminal and JSON output formats
