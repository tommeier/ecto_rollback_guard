defmodule EctoRollbackGuard.ReporterTest do
  use ExUnit.Case, async: true

  alias EctoRollbackGuard.{Impact, Reporter}

  @destructive Impact.from_operations(20_240_915, "create_orders", [
                 {:drop_table, :orders, 1847}
               ])

  @safe Impact.from_operations(20_240_910, "add_email_index", [
          {:drop_index, :users, [:email]}
        ])

  # --- format_terminal/1 ---

  describe "format_terminal/1" do
    test "formats destructive impact with row count" do
      output = Reporter.format_terminal([@destructive])
      assert output =~ "destructive"
      assert output =~ "create_orders"
      assert output =~ "1,847"
      assert output =~ "DROP TABLE"
    end

    test "formats safe impact" do
      output = Reporter.format_terminal([@safe])
      assert output =~ "safe"
      assert output =~ "add_email_index"
    end

    test "includes summary line" do
      output = Reporter.format_terminal([@destructive, @safe])
      assert output =~ "1 destructive"
      assert output =~ "1,847 rows"
    end

    test "handles empty list" do
      output = Reporter.format_terminal([])
      assert output =~ "No migrations"
    end

    test "summary with zero rows at risk omits row count" do
      impact = Impact.from_operations(1, "drop_col", [{:drop_column, :users, :email}])
      output = Reporter.format_terminal([impact])
      assert output =~ "1 destructive"
      refute output =~ "rows at risk"
    end
  end

  # --- format_terminal: all operation types ---

  describe "format_terminal — all operation types" do
    test "drop_table with count" do
      i = Impact.from_operations(1, "m", [{:drop_table, :users, 5000}])
      output = Reporter.format_terminal([i])
      assert output =~ "DROP TABLE users (~5,000 rows)"
    end

    test "drop_table without count" do
      i = Impact.from_operations(1, "m", [{:drop_table, :users}])
      output = Reporter.format_terminal([i])
      assert output =~ "DROP TABLE users"
    end

    test "drop_table unresolved" do
      i = Impact.from_operations(1, "m", [{:drop_table, {:unresolved, "@table_name"}}])
      output = Reporter.format_terminal([i])
      assert output =~ "DROP TABLE @table_name (unresolved)"
    end

    test "drop_column" do
      i = Impact.from_operations(1, "m", [{:drop_column, :users, :email}])
      output = Reporter.format_terminal([i])
      assert output =~ "DROP COLUMN users.email"
    end

    test "irreversible" do
      i = Impact.from_operations(1, "m", [{:irreversible}])
      output = Reporter.format_terminal([i])
      assert output =~ "IRREVERSIBLE"
    end

    test "raw_sql" do
      i = Impact.from_operations(1, "m", [{:raw_sql}])
      output = Reporter.format_terminal([i])
      assert output =~ "Raw SQL in down"
    end

    test "non_reversible_execute" do
      i = Impact.from_operations(1, "m", [{:non_reversible_execute}])
      output = Reporter.format_terminal([i])
      assert output =~ "Non-reversible execute()"
    end

    test "non_reversible_remove" do
      i = Impact.from_operations(1, "m", [{:non_reversible_remove, :users, :legacy}])
      output = Reporter.format_terminal([i])
      assert output =~ "Non-reversible remove users.legacy"
    end

    test "non_reversible_modify" do
      i = Impact.from_operations(1, "m", [{:non_reversible_modify, :users, :amount}])
      output = Reporter.format_terminal([i])
      assert output =~ "Non-reversible modify users.amount"
    end

    test "type_narrowing_risk" do
      i =
        Impact.from_operations(1, "m", [
          {:type_narrowing_risk, :users, :amount, :bigint, :integer}
        ])

      output = Reporter.format_terminal([i])
      assert output =~ "Type narrowing users.amount: integer -> bigint"
    end

    test "drop_index" do
      i = Impact.from_operations(1, "m", [{:drop_index, :users, [:email, :name]}])
      output = Reporter.format_terminal([i])
      assert output =~ "DROP INDEX on users(email, name) (safe)"
    end

    test "rename" do
      i = Impact.from_operations(1, "m", [{:rename, :old_table, :new_table}])
      output = Reporter.format_terminal([i])
      assert output =~ "RENAME old_table -> new_table (safe)"
    end

    test "raw_macro" do
      i = Impact.from_operations(1, "m", [{:raw_macro, :my_macro}])
      output = Reporter.format_terminal([i])
      assert output =~ "Macro my_macro"
    end

    test "unknown operation falls back to inspect" do
      i = Impact.from_operations(1, "m", [{:something_unexpected, :arg1, :arg2}])
      output = Reporter.format_terminal([i])
      assert output =~ "something_unexpected"
    end
  end

  # --- format_number edge cases ---

  describe "format_terminal — number formatting" do
    test "numbers under 1000 have no commas" do
      i = Impact.from_operations(1, "m", [{:drop_table, :t, 999}])
      output = Reporter.format_terminal([i])
      assert output =~ "~999 rows"
      refute output =~ ","
    end

    test "exactly 1000 gets comma" do
      i = Impact.from_operations(1, "m", [{:drop_table, :t, 1000}])
      output = Reporter.format_terminal([i])
      assert output =~ "1,000"
    end

    test "large numbers formatted correctly" do
      i = Impact.from_operations(1, "m", [{:drop_table, :t, 1_234_567}])
      output = Reporter.format_terminal([i])
      assert output =~ "1,234,567"
    end
  end

  # --- format_json/1 ---

  describe "format_json/1" do
    test "produces valid JSON" do
      json = Reporter.format_json([@destructive])
      assert {:ok, decoded} = Jason.decode(json)
      assert is_list(decoded["migrations"])
      assert hd(decoded["migrations"])["destructive"] == true
    end

    test "empty list produces valid JSON" do
      json = Reporter.format_json([])
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["migrations"] == []
    end

    test "summary includes total and destructive counts" do
      json = Reporter.format_json([@destructive, @safe])
      {:ok, decoded} = Jason.decode(json)
      assert decoded["summary"]["total"] == 2
      assert decoded["summary"]["destructive"] == 1
    end
  end

  # --- format_json: all operation types ---

  describe "format_json — all operation types" do
    test "drop_table with count" do
      i = Impact.from_operations(1, "m", [{:drop_table, :users, 100}])
      assert_json_op(i, %{"type" => "drop_table", "table" => "users", "rows" => 100})
    end

    test "drop_table without count" do
      i = Impact.from_operations(1, "m", [{:drop_table, :users}])
      assert_json_op(i, %{"type" => "drop_table", "table" => "users"})
    end

    test "drop_table unresolved" do
      i = Impact.from_operations(1, "m", [{:drop_table, {:unresolved, "@attr"}}])
      assert_json_op(i, %{"type" => "drop_table", "table" => "@attr", "unresolved" => true})
    end

    test "drop_column" do
      i = Impact.from_operations(1, "m", [{:drop_column, :users, :email}])
      assert_json_op(i, %{"type" => "drop_column", "table" => "users", "column" => "email"})
    end

    test "non_reversible_remove" do
      i = Impact.from_operations(1, "m", [{:non_reversible_remove, :users, :legacy}])

      assert_json_op(i, %{
        "type" => "non_reversible_remove",
        "table" => "users",
        "column" => "legacy"
      })
    end

    test "non_reversible_modify" do
      i = Impact.from_operations(1, "m", [{:non_reversible_modify, :users, :amount}])

      assert_json_op(i, %{
        "type" => "non_reversible_modify",
        "table" => "users",
        "column" => "amount"
      })
    end

    test "type_narrowing_risk" do
      i =
        Impact.from_operations(1, "m", [{:type_narrowing_risk, :users, :col, :bigint, :integer}])

      assert_json_op(i, %{
        "type" => "type_narrowing_risk",
        "table" => "users",
        "column" => "col",
        "new_type" => "bigint",
        "from_type" => "integer"
      })
    end

    test "drop_index" do
      i = Impact.from_operations(1, "m", [{:drop_index, :users, [:email]}])
      assert_json_op(i, %{"type" => "drop_index", "table" => "users", "columns" => ["email"]})
    end

    test "rename" do
      i = Impact.from_operations(1, "m", [{:rename, :old, :new}])
      assert_json_op(i, %{"type" => "rename", "from" => "old", "to" => "new"})
    end

    test "raw_macro" do
      i = Impact.from_operations(1, "m", [{:raw_macro, :my_macro}])
      assert_json_op(i, %{"type" => "raw_macro", "name" => "my_macro"})
    end

    test "single-element tuple ops (irreversible, raw_sql, etc.)" do
      for op <- [{:irreversible}, {:raw_sql}, {:non_reversible_execute}] do
        i = Impact.from_operations(1, "m", [op])
        type = op |> elem(0) |> to_string()
        assert_json_op(i, %{"type" => type})
      end
    end

    test "unknown op falls back to raw inspect" do
      i = Impact.from_operations(1, "m", [{:something_weird, :a, :b}])
      assert_json_op(i, %{"type" => "unknown"})
    end
  end

  defp assert_json_op(impact, expected_op) do
    json = Reporter.format_json([impact])
    {:ok, decoded} = Jason.decode(json)
    [migration] = decoded["migrations"]
    [op] = migration["operations"]

    for {key, val} <- expected_op do
      assert op[key] == val,
             "Expected #{key} to be #{inspect(val)}, got #{inspect(op[key])} in #{inspect(op)}"
    end
  end
end
