defmodule EctoRollbackGuard.Impact do
  @moduledoc "Represents the rollback impact of a single migration."

  @type operation ::
          {:drop_table, atom()}
          | {:drop_table, atom(), non_neg_integer()}
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
          | {:drop_table, {:unresolved, String.t()}}

  @type t :: %__MODULE__{
          version: non_neg_integer(),
          name: String.t(),
          source_path: String.t() | nil,
          operations: [operation()],
          destructive?: boolean()
        }

  defstruct [:version, :name, :source_path, operations: [], destructive?: false]

  @destructive_types [
    :drop_table, :drop_column, :irreversible, :raw_sql,
    :non_reversible_execute, :non_reversible_remove,
    :non_reversible_modify, :raw_macro
  ]

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
