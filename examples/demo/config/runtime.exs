import Config

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "set SECRET_KEY_BASE before starting the demo in production"

  port = String.to_integer(System.get_env("PORT") || "4000")

  config :phoenix_dnd_demo, PhoenixDndDemoWeb.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    server: true
end
