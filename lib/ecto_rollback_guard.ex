defmodule EctoRollbackGuard do
  @moduledoc """
  Detect destructive operations before rolling back Ecto migrations.

  Analyzes migration source files via AST to identify operations that would
  cause data loss when reverted — table drops, column removals, irreversible
  migrations — and optionally enriches results with live row counts from
  PostgreSQL.
  """
end
