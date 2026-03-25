defmodule EctoRollbackGuard.Impact do
  @moduledoc """
  Represents the rollback impact of a single migration.

  An `Impact` struct holds the migration version, name, detected operations,
  and whether any of those operations are destructive.
  """

  @typedoc "A detected rollback operation."
  @type operation ::
          {:drop_table, atom() | String.t()}
          | {:drop_table, atom() | String.t(), non_neg_integer()}
          | {:drop_table, {:unresolved, String.t()}}
          | {:drop_column, atom(), atom()}
          | {:irreversible}
          | {:raw_sql}
          | {:non_reversible_execute}
          | {:non_reversible_remove, atom(), atom()}
          | {:non_reversible_modify, atom(), atom()}
          | {:type_narrowing_risk, atom(), atom(), atom(), atom()}
          | {:drop_index, atom(), list()}
          | {:rename, atom(), atom()}
          | {:raw_macro, atom()}

  @type t :: %__MODULE__{
          version: non_neg_integer(),
          name: String.t(),
          source_path: String.t() | nil,
          operations: [operation()],
          destructive?: boolean()
        }

  defstruct [:version, :name, :source_path, operations: [], destructive?: false]

  @destructive_types [
    :drop_table,
    :drop_column,
    :irreversible,
    :raw_sql,
    :non_reversible_execute,
    :non_reversible_remove,
    :non_reversible_modify,
    :raw_macro
  ]

  @doc """
  Build an Impact struct from a version, name, and list of operations.

  Automatically sets `destructive?` based on the operation types.

  ## Options

  - `:source_path` — path to the migration source file
  """
  @spec from_operations(non_neg_integer(), String.t(), [operation()], keyword()) :: t()
  def from_operations(version, name, operations, opts \\ []) do
    %__MODULE__{
      version: version,
      name: name,
      source_path: Keyword.get(opts, :source_path),
      operations: operations,
      destructive?: Enum.any?(operations, &destructive_op?/1)
    }
  end

  defp destructive_op?(op) when is_tuple(op), do: elem(op, 0) in @destructive_types
  defp destructive_op?(_), do: false
end
