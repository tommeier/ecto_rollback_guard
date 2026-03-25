defmodule Mix.Tasks.EctoRollbackGuard.PreviewTest do
  use ExUnit.Case

  alias Ecto.Adapters.SQL.Sandbox
  alias EctoRollbackGuard.TestRepo
  alias Mix.Tasks.EctoRollbackGuard.Preview, as: PreviewTask

  setup do
    :ok = Sandbox.checkout(TestRepo)
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  describe "run/1" do
    test "raises when --to is missing" do
      assert_raise Mix.Error, ~r/--to VERSION is required/, fn ->
        PreviewTask.run([])
      end
    end

    test "outputs terminal format by default" do
      PreviewTask.run([
        "--to",
        "0",
        "--repo",
        "EctoRollbackGuard.TestRepo",
        "--no-enrich"
      ])

      assert_received {:mix_shell, :info, [output]}
      assert output =~ "Rollback Impact Preview" or output =~ "No migrations"
    end

    test "outputs JSON format with --format json" do
      PreviewTask.run([
        "--to",
        "0",
        "--repo",
        "EctoRollbackGuard.TestRepo",
        "--no-enrich",
        "--format",
        "json"
      ])

      assert_received {:mix_shell, :info, [output]}
      assert {:ok, decoded} = Jason.decode(output)
      assert is_list(decoded["migrations"])
      assert is_map(decoded["summary"])
    end

    test "--no-enrich skips row count queries" do
      PreviewTask.run([
        "--to",
        "0",
        "--repo",
        "EctoRollbackGuard.TestRepo",
        "--no-enrich",
        "--format",
        "json"
      ])

      assert_received {:mix_shell, :info, [output]}
      {:ok, decoded} = Jason.decode(output)

      for migration <- decoded["migrations"], op <- migration["operations"] do
        refute Map.has_key?(op, "rows"),
               "Expected no row counts with --no-enrich, got: #{inspect(op)}"
      end
    end

    test "resolves repo from --repo string" do
      PreviewTask.run([
        "--to",
        "99999999999999",
        "--repo",
        "EctoRollbackGuard.TestRepo",
        "--no-enrich"
      ])

      assert_received {:mix_shell, :info, [output]}
      assert output =~ "No migrations"
    end

    test "supports -t alias for --to" do
      PreviewTask.run([
        "-t",
        "99999999999999",
        "-r",
        "EctoRollbackGuard.TestRepo",
        "--no-enrich"
      ])

      assert_received {:mix_shell, :info, [output]}
      assert output =~ "No migrations"
    end
  end
end
