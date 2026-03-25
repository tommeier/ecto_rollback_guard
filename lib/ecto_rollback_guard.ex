defmodule EctoRollbackGuard do
  @moduledoc """
  Detect destructive operations before rolling back Ecto migrations.

  Analyzes migration source files via AST to identify operations that would
  cause data loss when reverted — table drops, column removals, irreversible
  migrations — and optionally enriches results with live row counts from
  PostgreSQL.

  ## Usage

  ### In a Release module

      defmodule MyApp.Release do
        def rollback(repo, version) do
          EctoRollbackGuard.log_preview(repo, version)
          {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
        end
      end

  ### Programmatic

      EctoRollbackGuard.detect(source)
      #=> [{:drop_table, :users}, {:drop_column, :entities, :mobile_number}]

      EctoRollbackGuard.preview(MyApp.Repo, 20230101120000)
      #=> {:ok, [%EctoRollbackGuard.Impact{...}]}

  ### Mix task

      mix ecto_rollback_guard.preview --to 20230101120000
  """

  alias EctoRollbackGuard.{Detector, Enricher, Impact, Preview, Reporter}

  @doc """
  Detect rollback operations from migration source text.

  Returns a list of operation tuples, or `{:error, reason}` if the source
  cannot be parsed.
  """
  @spec detect(String.t()) :: [Impact.operation()] | {:error, term()}
  defdelegate detect(source), to: Detector

  @doc """
  Returns `true` if any operation in the list is destructive.
  """
  @spec destructive?([Impact.operation()]) :: boolean()
  def destructive?(operations) do
    Impact.from_operations(0, "", operations).destructive?
  end

  @doc """
  Enrich operations with approximate row counts from PostgreSQL.
  """
  @spec enrich([Impact.operation()], Ecto.Repo.t()) :: [Impact.operation()]
  defdelegate enrich(operations, repo), to: Enricher

  @doc """
  Preview the impact of rolling back to `target_version`.

  Returns `{:ok, [%Impact{}]}`.

  ## Options

  - `:enrich` — query DB for row counts (default: `true`)
  - `:migrations_path` — override migration directory
  """
  @spec preview(Ecto.Repo.t(), non_neg_integer(), keyword()) ::
          {:ok, [Impact.t()]} | {:error, term()}
  def preview(repo, target_version, opts \\ []) do
    Preview.preview(repo, target_version, opts)
  end

  @doc """
  Log a formatted rollback impact preview to stdout.

  Designed for use in Release modules before executing a rollback.
  """
  @spec log_preview(Ecto.Repo.t(), non_neg_integer(), keyword()) :: :ok
  def log_preview(repo, target_version, opts \\ []) do
    {:ok, impacts} = preview(repo, target_version, opts)
    IO.puts(Reporter.format_terminal(impacts))
    :ok
  end
end
