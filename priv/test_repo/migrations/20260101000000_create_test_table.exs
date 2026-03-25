defmodule EctoRollbackGuard.TestRepo.Migrations.CreateTestTable do
  use Ecto.Migration

  def change do
    create table(:enricher_test_rows) do
      add :data, :string
    end
  end
end
