defmodule Mix.Tasks.EctoRollbackGuard.Preview do
  @shortdoc "Preview the impact of rolling back Ecto migrations"
  @moduledoc """
  Preview which operations would execute and what data would be lost
  when rolling back to a target migration version.

      $ mix ecto_rollback_guard.preview --to 20230101120000

  ## Options

  - `--to VERSION` — target migration version (required)
  - `--repo MyApp.Repo` — repo module (defaults to app's configured repo)
  - `--no-enrich` — skip database row count queries
  - `--format FORMAT` — output format: `terminal` (default) or `json`
  """

  use Mix.Task

  alias EctoRollbackGuard.Reporter

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [to: :integer, repo: :string, enrich: :boolean, format: :string],
        aliases: [t: :to, r: :repo, f: :format]
      )

    version = opts[:to] || Mix.raise("--to VERSION is required")
    format = opts[:format] || "terminal"
    enrich? = Keyword.get(opts, :enrich, true)
    repo = resolve_repo(opts[:repo])

    Mix.Task.run("app.start")

    case EctoRollbackGuard.preview(repo, version, enrich: enrich?) do
      {:ok, impacts} ->
        output =
          case format do
            "json" -> Reporter.format_json(impacts)
            _ -> Reporter.format_terminal(impacts)
          end

        Mix.shell().info(output)

      {:error, reason} ->
        Mix.raise("Preview failed: #{inspect(reason)}")
    end
  end

  defp resolve_repo(nil) do
    # Look for ecto_repos in the host application's config
    app = Mix.Project.config()[:app]

    case Application.get_env(app, :ecto_repos, []) do
      [repo | _] -> repo
      [] -> Mix.raise("No repo configured. Use --repo MyApp.Repo or configure :ecto_repos")
    end
  end

  defp resolve_repo(repo_string) do
    Module.concat([repo_string])
  end
end
