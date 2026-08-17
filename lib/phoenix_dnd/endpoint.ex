defmodule PhoenixDnd.Endpoint do
  @moduledoc """
  Identifies one port on one node.
  """

  alias PhoenixDnd.Data

  @enforce_keys [:node_id, :port_id]
  defstruct [:node_id, :port_id]

  @type t :: %__MODULE__{
          node_id: String.t(),
          port_id: String.t()
        }

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = endpoint) do
    %__MODULE__{
      node_id: Data.id!(endpoint.node_id, "endpoint node_id"),
      port_id: Data.id!(endpoint.port_id, "endpoint port_id")
    }
  end

  def new!(attrs) do
    attrs = attrs |> Data.map!("endpoint") |> Data.known_keys!([:node_id, :port_id], "endpoint")

    %__MODULE__{
      node_id: attrs |> Data.fetch!(:node_id, "endpoint") |> Data.id!("endpoint node_id"),
      port_id: attrs |> Data.fetch!(:port_id, "endpoint") |> Data.id!("endpoint port_id")
    }
  end

  @spec new!(String.t(), String.t()) :: t()
  def new!(node_id, port_id), do: new!(%{node_id: node_id, port_id: port_id})
end
