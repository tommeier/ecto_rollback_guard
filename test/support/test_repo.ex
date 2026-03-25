defmodule EctoRollbackGuard.TestRepo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :ecto_rollback_guard,
    adapter: Ecto.Adapters.Postgres
end
