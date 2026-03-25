ExUnit.start()

{:ok, _} = EctoRollbackGuard.TestRepo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(EctoRollbackGuard.TestRepo, :manual)
