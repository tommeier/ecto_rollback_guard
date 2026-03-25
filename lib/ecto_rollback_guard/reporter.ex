defmodule EctoRollbackGuard.Reporter do
  @moduledoc "Formats rollback impact results for terminal and JSON output."

  alias EctoRollbackGuard.Impact

  @spec format_terminal([Impact.t()]) :: String.t()
  def format_terminal([]), do: "No migrations to revert."

  def format_terminal(impacts) do
    header = "Rollback Impact Preview\n=======================\n"
    body = Enum.map_join(impacts, "\n", &format_impact/1)
    summary = format_summary(impacts)
    header <> "\n" <> body <> "\n\n" <> summary
  end

  @spec format_json([Impact.t()]) :: String.t()
  def format_json(impacts) do
    %{
      migrations: Enum.map(impacts, &impact_to_map/1),
      summary: summary_map(impacts)
    }
    |> Jason.encode!(pretty: true)
  end

  defp format_impact(%Impact{} = impact) do
    tag = if impact.destructive?, do: "[destructive]", else: "[safe]"
    header = "#{tag} #{impact.version}_#{impact.name}"
    ops = Enum.map_join(impact.operations, "\n", &("  " <> format_op(&1)))
    header <> "\n" <> ops
  end

  defp format_op({:drop_table, table, count}),
    do: "DROP TABLE #{table} (~#{format_number(count)} rows)"

  defp format_op({:drop_table, {:unresolved, ref}}), do: "DROP TABLE #{ref} (unresolved)"
  defp format_op({:drop_table, table}), do: "DROP TABLE #{table}"
  defp format_op({:drop_column, table, col}), do: "DROP COLUMN #{table}.#{col}"
  defp format_op({:irreversible}), do: "IRREVERSIBLE — no-op down"
  defp format_op({:raw_sql}), do: "Raw SQL in down — review manually"
  defp format_op({:non_reversible_execute}), do: "Non-reversible execute() in change"

  defp format_op({:non_reversible_remove, table, col}),
    do: "Non-reversible remove #{table}.#{col}"

  defp format_op({:non_reversible_modify, table, col}),
    do: "Non-reversible modify #{table}.#{col}"

  defp format_op({:type_narrowing_risk, table, col, new, old}),
    do: "Type narrowing #{table}.#{col}: #{old} -> #{new}"

  defp format_op({:drop_index, table, cols}),
    do: "DROP INDEX on #{table}(#{Enum.join(cols, ", ")}) (safe)"

  defp format_op({:rename, from, to}), do: "RENAME #{from} -> #{to} (safe)"
  defp format_op({:raw_macro, name}), do: "Macro #{name} — review manually"
  defp format_op(op), do: inspect(op)

  defp format_summary(impacts) do
    destructive_count = Enum.count(impacts, & &1.destructive?)

    total_rows =
      impacts
      |> Enum.flat_map(& &1.operations)
      |> Enum.reduce(0, fn
        {:drop_table, _, count}, acc -> acc + count
        _, acc -> acc
      end)

    parts = ["#{destructive_count} destructive operation(s)."]

    parts =
      if total_rows > 0, do: parts ++ ["~#{format_number(total_rows)} rows at risk."], else: parts

    Enum.join(parts, " ")
  end

  defp impact_to_map(%Impact{} = i) do
    %{
      version: i.version,
      name: i.name,
      destructive: i.destructive?,
      operations: Enum.map(i.operations, &op_to_map/1)
    }
  end

  defp op_to_map({:drop_table, table, count}),
    do: %{type: "drop_table", table: to_string(table), rows: count}

  defp op_to_map({:drop_table, {:unresolved, ref}}),
    do: %{type: "drop_table", table: ref, unresolved: true}

  defp op_to_map({:drop_table, table}),
    do: %{type: "drop_table", table: to_string(table)}

  defp op_to_map({:drop_column, table, col}),
    do: %{type: "drop_column", table: to_string(table), column: to_string(col)}

  defp op_to_map({:non_reversible_remove, table, col}),
    do: %{type: "non_reversible_remove", table: to_string(table), column: to_string(col)}

  defp op_to_map({:non_reversible_modify, table, col}),
    do: %{type: "non_reversible_modify", table: to_string(table), column: to_string(col)}

  defp op_to_map({:type_narrowing_risk, table, col, new_type, from_type}),
    do: %{
      type: "type_narrowing_risk",
      table: to_string(table),
      column: to_string(col),
      new_type: to_string(new_type),
      from_type: to_string(from_type)
    }

  defp op_to_map({:drop_index, table, cols}),
    do: %{type: "drop_index", table: to_string(table), columns: Enum.map(cols, &to_string/1)}

  defp op_to_map({:rename, from, to}),
    do: %{type: "rename", from: to_string(from), to: to_string(to)}

  defp op_to_map({:raw_macro, name}),
    do: %{type: "raw_macro", name: to_string(name)}

  defp op_to_map({type}) when is_atom(type), do: %{type: to_string(type)}
  defp op_to_map(op), do: %{type: "unknown", raw: inspect(op)}

  defp summary_map(impacts),
    do: %{total: length(impacts), destructive: Enum.count(impacts, & &1.destructive?)}

  defp format_number(n) when n >= 1000 do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end

  defp format_number(n), do: Integer.to_string(n)
end
