defmodule EctoRollbackGuard.EnricherTest do
  use ExUnit.Case

  alias EctoRollbackGuard.{Enricher, TestRepo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TestRepo)
    :ok
  end

  describe "query_row_count/2" do
    test "returns count for table with rows" do
      TestRepo.query!("INSERT INTO enricher_test_rows (data) VALUES ('a'), ('b'), ('c')")
      count = Enricher.query_row_count(TestRepo, "enricher_test_rows")
      assert count >= 3
    end

    test "returns 0 for empty table" do
      count = Enricher.query_row_count(TestRepo, "enricher_test_rows")
      assert count == 0
    end

    test "returns 0 for non-existent table" do
      count = Enricher.query_row_count(TestRepo, "nonexistent_xyz_table")
      assert count == 0
    end

    test "raises on SQL injection attempt" do
      assert_raise ArgumentError, fn ->
        Enricher.query_row_count(TestRepo, "users; DROP TABLE users")
      end
    end
  end

  describe "enrich/2" do
    test "adds row counts to drop_table operations" do
      TestRepo.query!("INSERT INTO enricher_test_rows (data) VALUES ('x')")
      ops = [{:drop_table, :enricher_test_rows}, {:drop_column, :users, :email}]
      enriched = Enricher.enrich(ops, TestRepo)

      assert [{:drop_table, :enricher_test_rows, count}, {:drop_column, :users, :email}] =
               enriched

      assert count >= 1
    end

    test "passes through non-drop_table operations unchanged" do
      ops = [{:irreversible}, {:raw_sql}, {:non_reversible_execute}]
      assert ^ops = Enricher.enrich(ops, TestRepo)
    end
  end
end
