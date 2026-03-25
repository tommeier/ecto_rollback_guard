defmodule EctoRollbackGuard.Preview do
  @moduledoc """
  Orchestrates rollback impact preview: discovers migrations, detects
  operations, and optionally enriches with row counts.
  """

  alias EctoRollbackGuard.{Detector, Enricher, Impact}

  @doc """
  Preview the impact of rolling back to `target_version`.

  Returns `{:ok, [%Impact{}]}` with one entry per migration that would be
  reverted.

  ## Options

  - `:enrich` — query DB for row counts (default: `true`)
  - `:migrations_path` — override migration directory
  """
  @spec preview(Ecto.Repo.t(), non_neg_integer(), keyword()) ::
          {:ok, [Impact.t()]} | {:error, term()}
  def preview(repo, target_version, opts \\ []) do
    enrich? = Keyword.get(opts, :enrich, true)
    migrations_path = Keyword.get(opts, :migrations_path, default_migrations_path(repo))

    migrations_to_revert =
      repo
      |> Ecto.Migrator.migrations(migrations_path)
      |> Enum.filter(fn {status, version, _name} ->
        status == :up and version > target_version
      end)

    impacts =
      Enum.map(migrations_to_revert, fn {_status, version, name} ->
        source_path = find_migration_file(migrations_path, version)

        ops =
          case source_path && File.read(source_path) do
            {:ok, source} ->
              case Detector.detect(source) do
                {:error, _} -> []
                ops -> ops
              end

            _ ->
              []
          end

        ops = if enrich?, do: Enricher.enrich(ops, repo), else: ops
        Impact.from_operations(version, name, ops, source_path: source_path)
      end)

    {:ok, impacts}
  end

  defp default_migrations_path(repo) do
    repo_config = repo.config()

    priv =
      repo_config[:priv] || "priv/#{repo |> Module.split() |> List.last() |> Macro.underscore()}"

    otp_app = repo_config[:otp_app]
    Application.app_dir(otp_app, Path.join(priv, "migrations"))
  rescue
    _ ->
      repo_name = repo |> Module.split() |> List.last() |> Macro.underscore()
      Path.join(["priv", repo_name, "migrations"])
  end

  defp find_migration_file(migrations_path, version) do
    version_str = Integer.to_string(version)

    case Path.wildcard(Path.join(migrations_path, "#{version_str}_*.exs")) do
      [path | _] -> path
      [] -> nil
    end
  end
end
