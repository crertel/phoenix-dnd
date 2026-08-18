import Config

config :phoenix_dnd_demo, PhoenixDndDemoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: String.duplicate("phoenix-dnd-demo-test-secret-", 3),
  server: false

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
