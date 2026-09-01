import Config

config :daw,
  generators: [timestamp_type: :utc_datetime],
  recording_dir: Path.expand("../priv/recordings", __DIR__)

config :daw, DawWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DawWeb.ErrorHTML, json: DawWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Daw.PubSub,
  live_view: [signing_salt: "daw-live-view"]

config :phoenix, :json_library, Jason

config :logger, :console, format: "$time $metadata[$level] $message\n"

import_config "#{config_env()}.exs"
