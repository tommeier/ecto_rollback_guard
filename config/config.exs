import Config

if config_env() == :test do
  config :ecto_rollback_guard, EctoRollbackGuard.TestRepo,
    username: "postgres",
    password: "postgres",
    hostname: "localhost",
    database: "ecto_rollback_guard_test",
    pool: Ecto.Adapters.SQL.Sandbox

  config :ecto_rollback_guard,
    ecto_repos: [EctoRollbackGuard.TestRepo]
end
