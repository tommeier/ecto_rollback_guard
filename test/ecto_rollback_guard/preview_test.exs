defmodule EctoRollbackGuard.PreviewTest do
  use ExUnit.Case

  alias Ecto.Adapters.SQL.Sandbox
  alias EctoRollbackGuard.{Preview, TestRepo}

  setup do
    :ok = Sandbox.checkout(TestRepo)
    :ok
  end

  describe "preview/3" do
    test "returns impacts for migrations above target version" do
      {:ok, impacts} = Preview.preview(TestRepo, 0)
      assert impacts != []

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

    test "sets source_path on returned impacts" do
      {:ok, impacts} = Preview.preview(TestRepo, 0, enrich: false)

      for impact <- impacts do
        if impact.source_path do
          assert String.ends_with?(impact.source_path, ".exs")
        end
      end
    end

    test "custom migrations_path where files are missing returns safe impacts" do
      # Ecto.Migrator still sees DB-tracked migrations but can't find the source files,
      # so operations will be empty and impacts will be non-destructive
      {:ok, impacts} =
        Preview.preview(TestRepo, 0, migrations_path: "/tmp/nonexistent_migrations")

      for impact <- impacts do
        assert impact.operations == []
        refute impact.destructive?
      end
    end
  end
end
