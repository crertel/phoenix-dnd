defmodule Daw.MixProject do
  use Mix.Project

  def project do
    [
      app: :daw,
      version: "0.1.0",
      elixir: "~> 1.15",
      listeners: [Phoenix.CodeReloader],
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      mod: {Daw.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [preferred_envs: [check: :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix_dnd, path: "../.."},
      {:phoenix, "~> 1.8.0"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_live_view, "~> 1.2"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"},

      # Membrane: WebRTC transport, Opus codec, and the raw-audio format the
      # DSP graph operates on.
      {:membrane_core, "~> 1.3"},
      {:membrane_webrtc_plugin, "~> 0.26"},
      {:membrane_opus_plugin, "~> 0.21"},
      {:membrane_raw_audio_format, "~> 0.12"},
      {:lazy_html, "~> 0.1", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      "assets.deploy": ["phx.digest"],
      check: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test",
        "cmd npm test"
      ]
    ]
  end
end
