defmodule EctoRollbackGuard.Enricher do
  @moduledoc """
  Enriches detected operations with approximate row counts from PostgreSQL.

  Uses `pg_class.reltuples` for fast approximate counts. Runs `ANALYZE` only
  when statistics are unavailable. Falls back to a bounded `count(*)`.
  """

  @spec enrich([EctoRollbackGuard.Impact.operation()], Ecto.Repo.t()) ::
          [EctoRollbackGuard.Impact.operation()]
  def enrich(operations, repo) do
    Enum.map(operations, fn
      {:drop_table, table} when is_atom(table) ->
        {:drop_table, table, query_row_count(repo, Atom.to_string(table))}

      {:drop_table, table} when is_binary(table) ->
        {:drop_table, table, query_row_count(repo, table)}

      other ->
        other
    end)
  end

  @bounded_limit 100_001

  @spec query_row_count(Ecto.Repo.t(), String.t()) :: non_neg_integer()
  def query_row_count(repo, table_name) do
    validate_table_name!(table_name)

    case bounded_count(repo, table_name) do
      count when count < @bounded_limit -> count
      _ -> approximate_count(repo, table_name)
    end
  end

  defp approximate_count(repo, table_name) do
    case query_reltuples(repo, table_name) do
      count when is_integer(count) and count > 0 -> count
      _ ->
        repo.query("ANALYZE #{table_name}", [], log: false)

        case query_reltuples(repo, table_name) do
          count when is_integer(count) and count > 0 -> count
          _ -> @bounded_limit
        end
    end
  end

  defp query_reltuples(repo, table_name) do
    case repo.query(
           "SELECT reltuples::bigint FROM pg_class WHERE relname = $1",
           [table_name],
           log: false
         ) do
      {:ok, %{rows: [[count]]}} when is_integer(count) and count >= 0 -> count
      _ -> -1
    end
  end

  defp bounded_count(repo, table_name) do
    case repo.query(
           "SELECT count(*) FROM (SELECT 1 FROM #{table_name} LIMIT #{@bounded_limit}) t",
           [],
           log: false
         ) do
      {:ok, %{rows: [[count]]}} when is_integer(count) -> count
      _ -> 0
    end
  rescue
    _ -> 0
  end

  defp validate_table_name!(name) do
    unless name =~ ~r/\A\w+\z/ do
      raise ArgumentError, "Invalid table name: #{inspect(name)}"
    end
  end
end
