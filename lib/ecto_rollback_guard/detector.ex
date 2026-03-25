defmodule EctoRollbackGuard.Detector do
  @moduledoc """
  AST-based detection of destructive rollback operations in Ecto migrations.

  Parses migration source with `Code.string_to_quoted/1` and pattern-matches
  on Ecto migration DSL nodes to identify operations that would cause data
  loss on rollback.
  """

  @spec detect(String.t()) :: [EctoRollbackGuard.Impact.operation()] | {:error, term()}
  def detect(""), do: []

  def detect(source) when is_binary(source) do
    case Code.string_to_quoted(source) do
      {:ok, ast} ->
        {down_body, change_body} = extract_function_bodies(ast)

        cond do
          down_body != nil -> detect_down_ops(down_body)
          change_body != nil -> detect_change_ops(change_body)
          true -> []
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- AST extraction ---

  defp extract_function_bodies(ast) do
    case ast do
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} -> find_functions(body)
      {:defmodule, _, [_, [do: body]]} -> find_functions(List.wrap(body))
      _ -> {nil, nil}
    end
  end

  defp find_functions(body_list) do
    Enum.reduce(body_list, {nil, nil}, fn
      {:def, _, [{:down, _, _}, [do: body]]}, {_down, change} -> {body, change}
      {:def, _, [{:change, _, _}, [do: body]]}, {down, _change} -> {down, body}
      _, acc -> acc
    end)
  end

  # --- change/0 detection ---

  defp detect_change_ops(body) do
    body |> normalize_body() |> Enum.flat_map(&detect_change_node/1)
  end

  # create table(:name) / create table(:name, opts) — with do block
  defp detect_change_node({:create, _, [{:table, _, [name | _]} | _]}) when is_atom(name) do
    [{:drop_table, name}]
  end

  defp detect_change_node({:create_if_not_exists, _, [{:table, _, [name | _]} | _]})
       when is_atom(name) do
    [{:drop_table, name}]
  end

  # Unresolved table name (module attribute, variable)
  defp detect_change_node({create, _, [{:table, _, [name_expr | _]} | _]})
       when create in [:create, :create_if_not_exists] and not is_atom(name_expr) do
    [{:drop_table, {:unresolved, Macro.to_string(name_expr)}}]
  end

  # alter table
  defp detect_change_node({:alter, _, [{:table, _, [name | _]}, [do: body]]})
       when is_atom(name) do
    body
    |> normalize_body()
    |> Enum.flat_map(fn
      {:add, _, [col | _]} when is_atom(col) ->
        [{:drop_column, name, col}]

      {:remove, _, [col]} when is_atom(col) ->
        [{:non_reversible_remove, name, col}]

      {:remove, _, [_col, _type | _]} ->
        []

      {:modify, _, [col, new_type | rest]} when is_atom(col) ->
        case extract_from_opt(rest) do
          nil -> [{:non_reversible_modify, name, col}]
          from_type -> [{:type_narrowing_risk, name, col, new_type, from_type}]
        end

      _ ->
        []
    end)
  end

  # Two-arg execute: check down SQL for DROP TABLE
  defp detect_change_node({:execute, _, [_up_sql, down_sql]}) when is_binary(down_sql) do
    extract_drops_from_sql(down_sql)
  end

  # Two-arg execute where down is not a string literal (function call, variable, etc.)
  # — cannot analyze statically, flag for review
  defp detect_change_node({:execute, _, [_, _non_string_down]}) do
    [{:raw_sql}]
  end

  # Single-arg execute — not auto-reversible
  defp detect_change_node({:execute, _, [_single_arg]}) do
    [{:non_reversible_execute}]
  end

  # Walk if/case/cond branches
  defp detect_change_node({:if, _, [_cond, branches]}) do
    walk_branches(branches)
  end

  defp detect_change_node({:case, _, [_expr, [do: branches]]}) do
    Enum.flat_map(branches, fn {:->, _, [_pattern, body]} ->
      body |> normalize_body() |> Enum.flat_map(&detect_change_node/1)
    end)
  end

  defp detect_change_node({:cond, _, [[do: branches]]}) do
    Enum.flat_map(branches, fn {:->, _, [_cond, body]} ->
      body |> normalize_body() |> Enum.flat_map(&detect_change_node/1)
    end)
  end

  defp detect_change_node(_), do: []

  defp walk_branches(branches) when is_list(branches) do
    Enum.flat_map(branches, fn
      {_key, body} -> body |> normalize_body() |> Enum.flat_map(&detect_change_node/1)
    end)
  end

  # --- down/0 detection ---

  defp detect_down_ops(body) do
    if irreversible_body?(body) do
      [{:irreversible}]
    else
      statements = normalize_body(body)
      ops = Enum.flat_map(statements, &detect_down_node/1)
      has_execute? = Enum.any?(statements, &execute_node?/1)

      if Enum.empty?(ops) and has_execute? do
        [{:raw_sql}]
      else
        ops
      end
    end
  end

  # Comments are stripped from AST, so a down with only comments + :ok
  # will just have :ok as the body
  defp irreversible_body?(:ok), do: true
  defp irreversible_body?(nil), do: true
  defp irreversible_body?(_), do: false

  defp detect_down_node({:drop, _, [{:table, _, [name | _]} | _]}) when is_atom(name) do
    [{:drop_table, name}]
  end

  defp detect_down_node({:drop_if_exists, _, [{:table, _, [name | _]} | _]})
       when is_atom(name) do
    [{:drop_table, name}]
  end

  defp detect_down_node({:alter, _, [{:table, _, [name | _]}, [do: body]]})
       when is_atom(name) do
    body
    |> normalize_body()
    |> Enum.flat_map(fn
      {:remove, _, [col | _]} when is_atom(col) -> [{:drop_column, name, col}]
      _ -> []
    end)
  end

  defp detect_down_node({:execute, _, [sql]}) when is_binary(sql) do
    drops = extract_drops_from_sql(sql)
    if Enum.empty?(drops), do: [], else: drops
  end

  defp detect_down_node(_), do: []

  defp execute_node?({:execute, _, _}), do: true
  defp execute_node?(_), do: false

  # --- Helpers ---

  defp normalize_body({:__block__, _, statements}), do: statements
  defp normalize_body(statement), do: [statement]

  defp extract_drops_from_sql(sql) when is_binary(sql) do
    ~r/DROP\s+TABLE\s+(?:IF\s+EXISTS\s+)?(\w+)/i
    |> Regex.scan(sql)
    |> Enum.map(fn [_, table] -> {:drop_table, table} end)
  end

  defp extract_from_opt([]), do: nil
  defp extract_from_opt([opts]) when is_list(opts), do: Keyword.get(opts, :from)
  defp extract_from_opt(_), do: nil
end
