defmodule EctoRollbackGuard.ImpactTest do
  use ExUnit.Case, async: true

  alias EctoRollbackGuard.Impact

  test "new impact struct has defaults" do
    impact = %Impact{version: 20_260_318, name: "create_users"}
    assert impact.version == 20_260_318
    assert impact.name == "create_users"
    assert impact.operations == []
    assert impact.destructive? == false
    assert impact.source_path == nil
  end

  test "from_operations classifies destructive ops" do
    for op <- [
          {:drop_table, :users},
          {:drop_column, :users, :email},
          {:irreversible},
          {:raw_sql},
          {:non_reversible_execute},
          {:non_reversible_remove, :users, :email},
          {:non_reversible_modify, :users, :amount}
        ] do
      impact = Impact.from_operations(1, "test", [op])
      assert impact.destructive?, "Expected #{inspect(op)} to be destructive"
    end
  end

  test "from_operations classifies safe ops" do
    for op <- [
          {:drop_index, :users, [:email]},
          {:rename, :old_table, :new_table},
          {:type_narrowing_risk, :users, :amount, :bigint, :integer}
        ] do
      impact = Impact.from_operations(1, "test", [op])
      refute impact.destructive?, "Expected #{inspect(op)} to be safe"
    end
  end

  test "from_operations sets source_path from opts" do
    impact = Impact.from_operations(1, "test", [], source_path: "/path/to/migration.exs")
    assert impact.source_path == "/path/to/migration.exs"
  end
end
