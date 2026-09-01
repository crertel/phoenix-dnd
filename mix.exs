defmodule PhoenixDnd.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/crertel/phoenix-dnd"

  def project do
    [
      app: :phoenix_dnd,
      version: @version,
      elixir: "~> 1.15",
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      description: "A server-authoritative node editor component for Phoenix LiveView",
      source_url: @source_url,
      package: package(),
      docs: docs(),
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  def cli do
    [preferred_envs: [check: :test]]
  end

  defp deps do
    [
      # The component declares its hook and its stylesheet as colocated assets,
      # so a host application needs no asset wiring of its own. Both land in the
      # same component, which LiveView dropped the CSS attributes for until
      # v1.2.5, hence the patch-level requirement rather than `~> 1.2`.
      {:phoenix_live_view, "~> 1.2.5"},
      {:phoenix, "~> 1.8"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Chris Ertel"],
      licenses: ["MIT"],
      files: ~w(lib priv .formatter.exs CHANGELOG.md LICENSE mix.exs package.json README.md),
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_url: @source_url,
      source_ref: "v#{@version}"
    ]
  end

  defp aliases do
    [
      check: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test",
        "cmd npm run check",
        "cmd npm test"
      ]
    ]
  end
end
