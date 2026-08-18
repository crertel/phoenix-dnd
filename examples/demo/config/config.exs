import Config

config :phoenix_dnd_demo, PhoenixDndDemoWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PhoenixDndDemoWeb.ErrorHTML, json: PhoenixDndDemoWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: PhoenixDndDemo.PubSub,
  live_view: [signing_salt: "phoenix-dnd-demo-live"]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
