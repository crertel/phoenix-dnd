defmodule PhoenixDnd.MixProject do
  use Mix.Project

  @version "0.1.0-dev"

  def project do
    [
      app: :phoenix_dnd,
      version: @version,
      elixir: "~> 1.15",
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      description: "A server-authoritative node editor component for Phoenix LiveView",
      package: package(),
      docs: [main: "readme", extras: ["README.md"]],
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
      {:phoenix, "~> 1.8.0"},
      {:phoenix_live_view, "~> 1.2"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      files: ~w(lib priv .formatter.exs LICENSE mix.exs package.json README.md),
      licenses: ["MIT"],
      links: %{"Documentation" => "https://hexdocs.pm/phoenix_dnd"}
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
