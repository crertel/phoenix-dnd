defmodule PhoenixDnd.Node do
  @moduledoc """
  A positioned node in a `PhoenixDnd.Scene`.

  The `data` field is deliberately opaque and remains on the server. It is
  passed to the editor's node slot without being serialized into the DOM.
  """

  alias PhoenixDnd.{Data, Port}

  @enforce_keys [:id, :position]
  defstruct [:id, :position, :label, :kind, :data, :class, ports: []]

  @type position :: %{x: number(), y: number()}

  @type t :: %__MODULE__{
          id: String.t(),
          position: position(),
          label: String.t() | nil,
          kind: String.t() | atom() | nil,
          ports: [Port.t()],
          data: term(),
          class: term()
        }

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = node), do: new!(Map.from_struct(node))

  def new!(attrs) do
    attrs =
      attrs
      |> Data.map!("node")
      |> Data.known_keys!([:id, :position, :label, :kind, :ports, :data, :class], "node")

    position = attrs |> Data.fetch!(:position, "node") |> position!()

    ports =
      attrs
      |> Map.get(:ports, [])
      |> Enum.map(&Port.new!/1)
      |> Data.unique_ids!("port")

    label = Map.get(attrs, :label)

    if not is_nil(label), do: Data.utf8_string!(label, "node label")

    kind = kind!(Map.get(attrs, :kind), "node kind")

    %__MODULE__{
      id: attrs |> Data.fetch!(:id, "node") |> Data.id!("node id"),
      position: position,
      label: label,
      kind: kind,
      ports: ports,
      data: Map.get(attrs, :data),
      class: Map.get(attrs, :class)
    }
  end

  @spec new!(String.t(), map() | keyword()) :: t()
  def new!(id, attrs) do
    attrs
    |> Data.map!("node")
    |> Map.put(:id, id)
    |> new!()
  end

  defp position!(value) do
    position =
      value
      |> Data.map!("node position")
      |> Data.known_keys!([:x, :y], "node position")

    %{
      x: position |> Data.fetch!(:x, "node position") |> Data.number!("node x"),
      y: position |> Data.fetch!(:y, "node position") |> Data.number!("node y")
    }
  end

  defp kind!(nil, _context), do: nil
  defp kind!(kind, _context) when is_atom(kind), do: kind
  defp kind!(kind, context) when is_binary(kind), do: Data.utf8_string!(kind, context, 128)

  defp kind!(kind, context) do
    raise ArgumentError, "expected #{context} to be a string, atom, or nil, got: #{inspect(kind)}"
  end
end
