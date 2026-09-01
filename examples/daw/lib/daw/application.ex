defmodule Daw.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Daw.PubSub},
      DawWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Daw.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    DawWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
