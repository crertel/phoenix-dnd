import Config

config :daw, DawWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4001],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: String.duplicate("daw-development-secret-key-base-0123456789", 2),
  watchers: [],
  live_reload: [
    patterns: [
      ~r"lib/daw_web/.*(ex|heex)$",
      ~r"assets/.*(js|css)$"
    ]
  ]

config :logger, :console, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
