defmodule PhoenixDndDemo.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: PhoenixDndDemo.PubSub},
      PhoenixDndDemoWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: PhoenixDndDemo.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    PhoenixDndDemoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
