defmodule EctoRollbackGuardTest do
  use ExUnit.Case

  alias Ecto.Adapters.SQL.Sandbox
  alias EctoRollbackGuard.TestRepo

  setup do
    :ok = Sandbox.checkout(TestRepo)
    :ok
  end

  @create_table_source ~S"""
  defmodule M do
    use Ecto.Migration
    def change do
      create table(:users) do
        add :email, :string
      end
    end
  end
  """

  @safe_source ~S"""
  defmodule M do
    use Ecto.Migration
    def change do
      create unique_index(:users, [:email])
    end
  end
  """

  describe "detect/1" do
    test "delegates to Detector" do
      assert [{:drop_table, :users}] = EctoRollbackGuard.detect(@create_table_source)
    end

    test "returns empty list for safe migration" do
      assert [] = EctoRollbackGuard.detect(@safe_source)
    end

    test "returns error for unparseable source" do
      assert {:error, _} = EctoRollbackGuard.detect("defmodule Bad do {")
    end
  end

  describe "destructive?/1" do
    test "returns true for destructive operations" do
      assert EctoRollbackGuard.destructive?([{:drop_table, :users}])
      assert EctoRollbackGuard.destructive?([{:irreversible}])
      assert EctoRollbackGuard.destructive?([{:drop_column, :users, :email}])
    end

    test "returns false for safe operations" do
      refute EctoRollbackGuard.destructive?([])
      refute EctoRollbackGuard.destructive?([{:drop_index, :users, [:email]}])
      refute EctoRollbackGuard.destructive?([{:rename, :old, :new}])
    end

    test "returns true when mix of safe and destructive" do
      assert EctoRollbackGuard.destructive?([
               {:drop_index, :users, [:email]},
               {:drop_table, :users}
             ])
    end
  end

  describe "enrich/2" do
    test "delegates to Enricher" do
      ops = [{:drop_table, :enricher_test_rows}]
      enriched = EctoRollbackGuard.enrich(ops, TestRepo)
      assert [{:drop_table, :enricher_test_rows, count}] = enriched
      assert is_integer(count)
    end
  end

  describe "preview/3" do
    test "returns {:ok, impacts}" do
      assert {:ok, impacts} = EctoRollbackGuard.preview(TestRepo, 0, enrich: false)
      assert is_list(impacts)
    end
  end

  describe "log_preview/3" do
    test "prints formatted output to stdout" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          result = EctoRollbackGuard.log_preview(TestRepo, 0, enrich: false)
          assert result == :ok
        end)

      assert output =~ "Rollback Impact Preview"
    end

    test "prints to stdout even when no migrations to revert" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          result = EctoRollbackGuard.log_preview(TestRepo, 99_999_999_999_999, enrich: false)
          assert result == :ok
        end)

      assert output =~ "No migrations"
    end
  end
end
