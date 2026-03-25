# EctoRollbackGuard

[![Hex.pm](https://img.shields.io/hexpm/v/ecto_rollback_guard.svg)](https://hex.pm/packages/ecto_rollback_guard)

**Know what you'll lose before you rollback.**

EctoRollbackGuard analyzes Ecto migration source files to detect destructive
rollback operations — table drops, column removals, irreversible migrations —
before you execute them. Optionally enriches results with live row counts from
PostgreSQL.

## How it fits

[excellent_migrations](https://hex.pm/packages/excellent_migrations) guards the
**forward** path — "is this migration safe to deploy?"

EctoRollbackGuard guards the **reverse** path — "what will I lose if I revert?"

They're complementary.

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:ecto_rollback_guard, "~> 0.1"}
  ]
end
```

## Usage

### Mix task

Preview a rollback from the command line:

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
- `--no-enrich` — skip DB row count queries
- `--format json` — machine-readable output

### In a Release module

Log impact before executing a rollback in production:

```elixir
defmodule MyApp.Release do
  def rollback(repo, version) do
    EctoRollbackGuard.log_preview(repo, version)

    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
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

# Enrich with row counts
EctoRollbackGuard.enrich(operations, MyApp.Repo)
#=> [{:drop_table, :users, 1847}, {:drop_column, :entities, :mobile_number}]

# Full preview
EctoRollbackGuard.preview(MyApp.Repo, 20230101120000)
#=> {:ok, [%EctoRollbackGuard.Impact{...}]}
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
| `execute "some sql"` (no pattern match) | `{:raw_sql}` |
| `def down, do: :ok` | `{:irreversible}` |

Safe operations (indexes, renames, reversible removes) are detected but not
flagged as destructive.

When both `down/0` and `change/0` exist, `down/0` takes priority (matching
Ecto's behavior).

## How it works

EctoRollbackGuard parses migration source with `Code.string_to_quoted/1` and
pattern-matches on the AST. This is more reliable than regex:

- Multi-line expressions handled naturally
- `execute("one_arg")` vs `execute("up", "down")` distinguished by arity
- No false positives from comments or strings
- Conditional branches (`if`/`case`) walked to find all possible operations

Row count enrichment uses `pg_class.reltuples` for speed, with a bounded
`count(*)` fallback. PostgreSQL only for v0.1.

## License

MIT — see [LICENSE](LICENSE).
