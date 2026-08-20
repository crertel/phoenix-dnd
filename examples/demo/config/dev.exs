import Config

port = String.to_integer(System.get_env("PORT") || "4000")

config :phoenix_dnd_demo, PhoenixDndDemoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: port],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: String.duplicate("phoenix-dnd-demo-secret-", 3),
  watchers: []

config :logger, :default_formatter, format: "[$level] $message\n"
config :phoenix, :plug_init_mode, :runtime
