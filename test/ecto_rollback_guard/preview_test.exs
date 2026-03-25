defmodule EctoRollbackGuard.PreviewTest do
  use ExUnit.Case

  alias EctoRollbackGuard.Preview
  alias EctoRollbackGuard.TestRepo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TestRepo)
    :ok
  end

  describe "preview/3" do
    test "returns impacts for migrations above target version" do
      # The test repo has migration 20260101000000_create_test_table
      # Rolling back to 0 should detect it as a create table (drop on rollback)
      {:ok, impacts} = Preview.preview(TestRepo, 0)
      assert length(impacts) >= 1

      impact = Enum.find(impacts, &(&1.name =~ "create_test_table"))
      assert impact != nil
      assert impact.destructive?

      assert Enum.any?(impact.operations, fn
               {:drop_table, _, _} -> true
               {:drop_table, _} -> true
               _ -> false
             end)
    end

    test "returns empty list when no migrations to revert" do
      {:ok, impacts} = Preview.preview(TestRepo, 99_999_999_999_999)
      assert impacts == []
    end

    test "enrich: false skips row count queries" do
      {:ok, impacts} = Preview.preview(TestRepo, 0, enrich: false)

      for impact <- impacts, op <- impact.operations do
        refute match?({:drop_table, _, _count}, op),
               "Expected no enriched 3-tuples, got: #{inspect(op)}"
      end
    end
  end
end
