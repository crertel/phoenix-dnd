defmodule DawWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :daw

  @session_options [
    store: :cookie,
    key: "_daw_key",
    signing_salt: "daw-cookie-signing",
    same_site: "Lax"
  ]

  @colocated_css Path.join(Mix.Project.build_path(), "phoenix-colocated/phoenix_dnd")

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]
  )

  # The studio has no bundler: its JavaScript and CSS are sources that live in
  # priv/static and are served straight from there. Mix copies priv into the
  # build path, so this works in a release and `mix phx.digest` can see it.
  plug(Plug.Static, at: "/assets", from: {:daw, "priv/static"}, gzip: false)

  plug(Plug.Static,
    at: "/phoenix-colocated/phoenix_dnd",
    from: @colocated_css,
    gzip: false,
    only: ~w(colocated.css PhoenixDnd.Editor)
  )

  plug(Plug.Static,
    at: "/vendor/phoenix",
    from: {:phoenix, "priv/static"},
    only: ~w(phoenix.mjs phoenix.mjs.map)
  )

  plug(Plug.Static,
    at: "/vendor/phoenix_live_view",
    from: {:phoenix_live_view, "priv/static"},
    only: ~w(phoenix_live_view.esm.js phoenix_live_view.esm.js.map)
  )

  plug(Plug.Static,
    at: "/phoenix-dnd",
    from: {:phoenix_dnd, "priv/static"},
    only: ~w(phoenix_dnd.js)
  )

  if code_reloading? do
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(DawWeb.Router)
end
