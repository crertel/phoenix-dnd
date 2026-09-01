defmodule DawWeb.Router do
  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:put_root_layout, html: {DawWeb.Layouts, :root})
    plug(:protect_from_forgery)
  end

  scope "/", DawWeb do
    pipe_through(:browser)

    live("/", StudioLive, :index)
  end
end
