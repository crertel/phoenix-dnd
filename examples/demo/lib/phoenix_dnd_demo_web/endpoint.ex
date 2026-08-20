defmodule PhoenixDndDemoWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :phoenix_dnd_demo

  @session_options [
    store: :cookie,
    key: "_phoenix_dnd_demo_key",
    signing_salt: "demo-cookie-signing",
    same_site: "Lax"
  ]

  @demo_assets Path.expand("../../assets", __DIR__)
  @colocated_css Path.join(Mix.Project.build_path(), "phoenix-colocated/phoenix_dnd")

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]
  )

  plug(Plug.Static,
    at: "/assets",
    from: @demo_assets,
    gzip: false
  )

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
  plug(PhoenixDndDemoWeb.Router)
end
