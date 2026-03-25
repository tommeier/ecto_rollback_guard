defmodule EctoRollbackGuard.DetectorTest do
  use ExUnit.Case, async: true
  alias EctoRollbackGuard.Detector

  # === change/0 — create table ===

  @change_create_table ~S"""
  defmodule M do
    use Ecto.Migration
    def change do
      create table(:users, primary_key: false) do
        add :id, :binary_id, primary_key: true
        add :email, :string, null: false
      end
      create unique_index(:users, [:email])
    end
  end
  """

  @change_create_if_not_exists ~S"""
  defmodule M do
    use Ecto.Migration
    def change do
      create_if_not_exists table(:settings) do
        add :key, :string
      end
    end
  end
  """

  @change_multiple_tables ~S"""
  defmodule M do
    use Ecto.Migration
    def change do
      create table(:entities, primary_key: false) do
        add :id, :binary_id, primary_key: true
      end
      create table(:customers) do
        add :entity_id, references(:entities, type: :binary_id)
      end
    end
  end
  """

  @change_alter_add ~S"""
  defmodule M do
    use Ecto.Migration
    def change do
      alter table(:entities) do
        add :mobile_number, :string
      end
    end
  end
  """

  @change_safe_index ~S"""
  defmodule M do
    use Ecto.Migration
    def change do
      create unique_index(:entities, [:email])
    end
  end
  """

  # === change/0 — execute ===

  @change_execute_two_arg_safe ~S"""
  defmodule M do
    use Ecto.Migration
    def change do
      execute("CREATE EXTENSION IF NOT EXISTS citext", "")
    end
  end
  """

  @change_execute_single_arg ~S"""
  defmodule M do
    use Ecto.Migration
    def change do
      execute "INSERT INTO settings (key, value) VALUES ('v', '2')"
    end
  end
  """

  @change_execute_two_arg_destructive ~S"""
  defmodule M do
    use Ecto.Migration
    def change do
      execute(
        "ALTER TABLE new_users RENAME TO users",
        "DROP TABLE IF EXISTS users"
      )
    end
  end
  """

  @change_execute_heredoc ~S"""
  defmodule M do
    use Ecto.Migration
    def change do
      execute "CREATE EXTENSION citext", "DROP EXTENSION citext"
    end
  end
  """

  # === change/0 — remove ===

  @change_remove_without_type ~S"""
  defmodule M do
    use Ecto.Migration
    def change do
      alter table(:users) do
        remove :legacy_field
      end
    end
  end
  """

  @change_remove_with_type ~S"""
  defmodule M do
    use Ecto.Migration
    def change do
      alter table(:users) do
        remove :legacy_field, :string
      end
    end
  end
  """

  # === change/0 — modify ===

  @change_modify_without_from ~S"""
  defmodule M do
    use Ecto.Migration
    def change do
      alter table(:users) do
        modify :amount, :bigint
      end
    end
  end
  """

  @change_modify_with_from ~S"""
  defmodule M do
    use Ecto.Migration
    def change do
      alter table(:users) do
        modify :amount, :bigint, from: :integer
      end
    end
  end
  """

  # === change/0 — rename ===

  @change_rename ~S"""
  defmodule M do
    use Ecto.Migration
    def change do
      rename table(:old_name), to: table(:new_name)
    end
  end
  """

  # === down/0 ===

  @down_noop ~S"""
  defmodule M do
    use Ecto.Migration
    def up, do: execute("CREATE TABLE foo (id int)")
    def down do
      :ok
    end
  end
  """

  @down_noop_with_comments ~S"""
  defmodule M do
    use Ecto.Migration
    def up, do: execute("DROP TABLE IF EXISTS merchants")
    def down do
      # Intentionally a no-op
      :ok
    end
  end
  """

  @down_inline_noop ~S"""
  defmodule M do
    use Ecto.Migration
    def up, do: execute("CREATE VIEW foo AS SELECT 1")
    def down, do: :ok
  end
  """

  @down_drop_table ~S"""
  defmodule M do
    use Ecto.Migration
    def up do
      create table(:merchants) do
        add :name, :string
      end
    end
    def down do
      drop table(:merchants)
    end
  end
  """

  @down_drop_with_opts ~S"""
  defmodule M do
    use Ecto.Migration
    def up, do: :ok
    def down do
      drop table(:items, prefix: "archive")
    end
  end
  """

  @down_drop_if_exists ~S"""
  defmodule M do
    use Ecto.Migration
    def up, do: :ok
    def down do
      drop_if_exists table(:legacy)
    end
  end
  """

  @down_alter_remove ~S"""
  defmodule M do
    use Ecto.Migration
    def up do
      alter table(:users) do
        add :temp, :string
      end
    end
    def down do
      alter table(:users) do
        remove :temp
      end
    end
  end
  """

  @down_raw_sql_drop ~S"""
  defmodule M do
    use Ecto.Migration
    def up, do: :ok
    def down do
      execute "DROP TABLE IF EXISTS merchant_locations; DROP TABLE IF EXISTS merchants;"
    end
  end
  """

  @down_raw_sql_unknown ~S"""
  defmodule M do
    use Ecto.Migration
    def up, do: :ok
    def down do
      execute "UPDATE settings SET value = 'old' WHERE key = 'version'"
    end
  end
  """

  @down_oban ~S"""
  defmodule M do
    use Ecto.Migration
    def up, do: Oban.Migration.up(version: 1)
    def down, do: Oban.Migration.down(version: 1)
  end
  """

  # === Priority & Edge Cases ===

  @both_down_and_change ~S"""
  defmodule M do
    use Ecto.Migration
    def change do
      create table(:should_not_detect)
    end
    def down do
      drop table(:from_down)
    end
  end
  """

  @module_attr_table ~S"""
  defmodule M do
    use Ecto.Migration
    @table_name :dynamic_users
    def change do
      create table(@table_name) do
        add :name, :string
      end
    end
  end
  """

  @conditional ~S"""
  defmodule M do
    use Ecto.Migration
    def change do
      if System.get_env("CREATE_EXTRA") do
        create table(:extra) do
          add :data, :string
        end
      end
      create table(:always) do
        add :name, :string
      end
    end
  end
  """

  @malformed "defmodule Broken do {"

  # === Tests ===

  describe "change/0 — create table" do
    test "detects create table" do
      assert [{:drop_table, :users}] = Detector.detect(@change_create_table)
    end

    test "detects create_if_not_exists" do
      assert [{:drop_table, :settings}] = Detector.detect(@change_create_if_not_exists)
    end

    test "detects multiple tables" do
      ops = Detector.detect(@change_multiple_tables)
      tables = for {:drop_table, t} <- ops, do: t
      assert :entities in tables
      assert :customers in tables
    end

    test "detects alter add as drop_column" do
      assert [{:drop_column, :entities, :mobile_number}] = Detector.detect(@change_alter_add)
    end

    test "safe index returns empty" do
      assert [] = Detector.detect(@change_safe_index)
    end

    test "empty source returns empty" do
      assert [] = Detector.detect("")
    end
  end

  describe "change/0 — execute" do
    test "two-arg with empty down is safe" do
      assert [] = Detector.detect(@change_execute_two_arg_safe)
    end

    test "single-arg is non_reversible_execute" do
      assert [{:non_reversible_execute}] = Detector.detect(@change_execute_single_arg)
    end

    test "two-arg with DROP TABLE in down SQL" do
      assert [{:drop_table, "users"}] = Detector.detect(@change_execute_two_arg_destructive)
    end

    test "heredoc execute detects correctly" do
      # Two-arg with safe down — no destructive detection
      assert [] = Detector.detect(@change_execute_heredoc)
    end
  end

  describe "change/0 — remove" do
    test "remove without type is non-reversible" do
      assert [{:non_reversible_remove, :users, :legacy_field}] =
               Detector.detect(@change_remove_without_type)
    end

    test "remove with type is safe" do
      assert [] = Detector.detect(@change_remove_with_type)
    end
  end

  describe "change/0 — modify" do
    test "modify without :from is non-reversible" do
      assert [{:non_reversible_modify, :users, :amount}] =
               Detector.detect(@change_modify_without_from)
    end

    test "modify with :from detects type_narrowing_risk" do
      assert [{:type_narrowing_risk, :users, :amount, :bigint, :integer}] =
               Detector.detect(@change_modify_with_from)
    end
  end

  describe "change/0 — rename" do
    test "rename is safe" do
      assert [] = Detector.detect(@change_rename)
    end
  end

  describe "down/0" do
    test "no-op down is irreversible" do
      assert [{:irreversible}] = Detector.detect(@down_noop)
    end

    test "no-op with comments is irreversible" do
      assert [{:irreversible}] = Detector.detect(@down_noop_with_comments)
    end

    test "inline no-op is irreversible" do
      assert [{:irreversible}] = Detector.detect(@down_inline_noop)
    end

    test "drop table" do
      assert [{:drop_table, :merchants}] = Detector.detect(@down_drop_table)
    end

    test "drop table with options" do
      assert [{:drop_table, :items}] = Detector.detect(@down_drop_with_opts)
    end

    test "drop_if_exists" do
      assert [{:drop_table, :legacy}] = Detector.detect(@down_drop_if_exists)
    end

    test "alter remove" do
      assert [{:drop_column, :users, :temp}] = Detector.detect(@down_alter_remove)
    end

    test "raw SQL DROP TABLE" do
      ops = Detector.detect(@down_raw_sql_drop)
      tables = for {:drop_table, t} <- ops, do: t
      assert "merchant_locations" in tables
      assert "merchants" in tables
    end

    test "raw SQL no recognized pattern" do
      assert [{:raw_sql}] = Detector.detect(@down_raw_sql_unknown)
    end

    test "third-party down (Oban) — no false positive" do
      assert [] = Detector.detect(@down_oban)
    end
  end

  describe "priority" do
    test "down takes priority over change" do
      assert [{:drop_table, :from_down}] = Detector.detect(@both_down_and_change)
    end
  end

  describe "edge cases" do
    test "module attribute table name returns unresolved" do
      ops = Detector.detect(@module_attr_table)
      assert [{:drop_table, {:unresolved, _}}] = ops
    end

    test "conditional detects from all branches" do
      ops = Detector.detect(@conditional)
      tables = for {:drop_table, t} <- ops, do: t
      assert :always in tables
      assert :extra in tables
    end

    test "malformed source returns error" do
      assert {:error, _} = Detector.detect(@malformed)
    end
  end
end
