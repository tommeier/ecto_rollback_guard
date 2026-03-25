# EctoRollbackGuard

[![Hex.pm](https://img.shields.io/hexpm/v/ecto_rollback_guard.svg)](https://hex.pm/packages/ecto_rollback_guard)
[![CI](https://github.com/tommeier/ecto_rollback_guard/actions/workflows/ci.yml/badge.svg)](https://github.com/tommeier/ecto_rollback_guard/actions/workflows/ci.yml)

**Know what you'll lose before you rollback.**

EctoRollbackGuard analyzes Ecto migration source files to detect destructive
rollback operations — table drops, column removals, irreversible migrations —
before you execute them. Optionally enriches results with live row counts from
PostgreSQL.

## Why

You deploy. Something goes wrong. You need to rollback.

Ecto's `change/0` migrations are reversible by design — but "reversible" doesn't
mean "safe". When you roll back a `create table(:users)` migration, Ecto drops
the table and every row in it. There's no confirmation, no warning, and no
indication of how much data you're about to lose.

In a production incident, that's exactly the moment you're least equipped to
manually review migration files. You need tooling that tells you **what will
happen** before it happens.

EctoRollbackGuard answers one question: **"What will I lose if I revert to
version X?"**

### Real-world deployment integration

EctoRollbackGuard is designed to plug into your deployment pipeline at multiple
points:

**1. Before rollback — in your Release module**

Log a full impact report with row counts before executing the rollback. This
gives operators visibility in production logs:

```
🔴 20260318_create_email_signups — DROP TABLE email_signups (~1,847 rows)
🟢 20260315_add_email_index — DROP INDEX (safe)
```

**2. At deploy time — in CI/CD**

Use the mix task or programmatic API to analyze migrations as part of your
rollback pipeline. Feed the results into Slack alerts, Buildkite annotations,
or PagerDuty:

```bash
# In your rollback script
mix ecto_rollback_guard.preview --to $ROLLBACK_VERSION --format json
```

**3. During development — in your terminal**

Preview what a rollback would do before you run it:

```bash
mix ecto_rollback_guard.preview --to 20230101120000
```

### Ecosystem position

[excellent_migrations](https://hex.pm/packages/excellent_migrations) guards the
**forward** path — "is this migration safe to deploy?"

EctoRollbackGuard guards the **reverse** path — "what will I lose if I revert?"

They're complementary. Use both.

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:ecto_rollback_guard, "~> 0.2"}
  ]
end
```

## Usage

### Mix task

```bash
$ mix ecto_rollback_guard.preview --to 20230101120000

Rollback Impact Preview
=======================

[destructive] 20260318_create_email_signups
  DROP TABLE email_signups (~1,847 rows)

[safe] 20260315_add_email_index
  DROP INDEX on users(email) (safe)

1 destructive operation(s). ~1,847 rows at risk.
```

Options:
- `--to VERSION` — target migration version (required)
- `--repo MyApp.Repo` — specify repo (defaults to configured repo)
- `--no-enrich` — skip DB row count queries (useful in CI without a DB)
- `--format json` — machine-readable output for pipeline integration

### In a Release module

```elixir
defmodule MyApp.Release do
  def rollback(repo, version) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, fn repo ->
        EctoRollbackGuard.log_preview(repo, version)
        Ecto.Migrator.run(repo, :down, to: version)
      end)
  end

  defp load_app do
    Application.load(:my_app)
  end
end
```

### Programmatic API

```elixir
# Detect from source text (pure function, no DB needed)
EctoRollbackGuard.detect(source)
#=> [{:drop_table, :users}, {:drop_column, :entities, :mobile_number}]

# Check if any operations are destructive
EctoRollbackGuard.destructive?(operations)
#=> true

# Enrich with approximate row counts
EctoRollbackGuard.enrich(operations, MyApp.Repo)
#=> [{:drop_table, :users, 1847}, {:drop_column, :entities, :mobile_number}]

# Full preview — discovers migrations, detects, enriches
{:ok, impacts} = EctoRollbackGuard.preview(MyApp.Repo, 20230101120000)
```

## What it detects

### In `change/0` (reversed on rollback)

| Migration code | Detected rollback operation |
|---|---|
| `create table(:users)` | `{:drop_table, :users}` |
| `create_if_not_exists table(:users)` | `{:drop_table, :users}` |
| `alter table(:users) do add :col` | `{:drop_column, :users, :col}` |
| `alter table(:users) do remove :col` (no type) | `{:non_reversible_remove, ...}` |
| `alter table(:users) do modify :col, :type` (no `:from`) | `{:non_reversible_modify, ...}` |
| `alter table(:users) do modify :col, :bigint, from: :integer` | `{:type_narrowing_risk, ...}` |
| `execute("up_sql", "DROP TABLE users")` | `{:drop_table, "users"}` |
| `execute("single_arg_sql")` | `{:non_reversible_execute}` |

### In `down/0` (executed directly)

| Migration code | Detected operation |
|---|---|
| `drop table(:users)` | `{:drop_table, :users}` |
| `alter table(:users) do remove :col` | `{:drop_column, :users, :col}` |
| `execute "DROP TABLE users"` | `{:drop_table, "users"}` |
| `execute "some sql"` (unrecognized) | `{:raw_sql}` |
| `def down, do: :ok` | `{:irreversible}` |

Safe operations (indexes, renames, reversible removes) are detected but not
flagged as destructive.

When both `down/0` and `change/0` exist, `down/0` takes priority — matching
Ecto's behavior.

## How it works

EctoRollbackGuard parses migration source with `Code.string_to_quoted/1` and
pattern-matches on the Elixir AST. This is more reliable than regex:

- Multi-line expressions handled naturally by tree structure
- `execute("one_arg")` vs `execute("up", "down")` distinguished by arity
- No false positives from comments or string contents
- Conditional branches (`if`/`case`) walked to find all possible operations

Row count enrichment queries `pg_class.reltuples` for speed, with a bounded
`count(*)` fallback for small tables. PostgreSQL only for v0.1.

## Limitations

- Static analysis is heuristic — dynamic table names from variables or function
  calls are flagged as "unresolved" for manual review
- Macros that generate migration DSL calls are detected but not expanded
- Row count enrichment is PostgreSQL-only (MySQL/SQLite planned for future)
- `execute` with non-string arguments is flagged for review but cannot be
  analyzed

## Contributing

```bash
# Clone and setup
git clone https://github.com/tommeier/ecto_rollback_guard.git
cd ecto_rollback_guard

# Install dependencies
mix deps.get

# Create test database (requires PostgreSQL running)
mix ecto.create

# Run the full suite
mix test              # 112 tests
mix credo --strict    # static analysis
mix format --check-formatted
mix dialyzer          # type checking (slow on first run)
```

PRs welcome. Please include tests for new detection patterns.

## License

MIT — see [LICENSE](LICENSE).
