defmodule PhoenixDndDemo.MixProject do
  use Mix.Project

  def project do
    [
      app: :phoenix_dnd_demo,
      version: "0.1.0",
      elixir: "~> 1.15",
      listeners: [Phoenix.CodeReloader],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      mod: {PhoenixDndDemo.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [preferred_envs: [check: :test]]
  end

  defp deps do
    [
      {:phoenix_dnd, path: "../.."},
      {:phoenix, "~> 1.8"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_live_view, "~> 1.2"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"},
      {:lazy_html, "~> 0.1", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      check: ["format --check-formatted", "compile --warnings-as-errors", "test"]
    ]
  end
end
