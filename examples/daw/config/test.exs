import Config

config :daw, DawWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: String.duplicate("daw-test-secret-key-base-0123456789", 2),
  server: false

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
