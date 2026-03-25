defmodule EctoRollbackGuard.ReporterTest do
  use ExUnit.Case, async: true

  alias EctoRollbackGuard.{Impact, Reporter}

  @destructive Impact.from_operations(20260318, "create_email_signups", [
                 {:drop_table, :email_signups, 1847}
               ])

  @safe Impact.from_operations(20260315, "add_email_index", [
          {:drop_index, :users, [:email]}
        ])

  describe "format_terminal/1" do
    test "formats destructive impact with row count" do
      output = Reporter.format_terminal([@destructive])
      assert output =~ "destructive"
      assert output =~ "create_email_signups"
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
  end

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
  end
end
