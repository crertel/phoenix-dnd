defmodule PhoenixDnd.Edge do
  @moduledoc """
  A directed relationship between two node ports.
  """

  alias PhoenixDnd.{Data, Endpoint}

  @enforce_keys [:id, :source, :target]
  defstruct [:id, :source, :target, :kind, :data, :class]

  @type t :: %__MODULE__{
          id: String.t(),
          source: Endpoint.t(),
          target: Endpoint.t(),
          kind: String.t() | atom() | nil,
          data: term(),
          class: term()
        }

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = edge), do: new!(Map.from_struct(edge))

  def new!(attrs) do
    attrs =
      attrs
      |> Data.map!("edge")
      |> Data.known_keys!([:id, :source, :target, :kind, :data, :class], "edge")

    kind = Map.get(attrs, :kind)

    if is_binary(kind), do: Data.utf8_string!(kind, "edge kind", 128)

    unless is_nil(kind) or is_atom(kind) or is_binary(kind),
      do: raise(ArgumentError, "expected edge kind to be a valid UTF-8 string, atom, or nil")

    %__MODULE__{
      id: attrs |> Data.fetch!(:id, "edge") |> Data.id!("edge id"),
      source: attrs |> Data.fetch!(:source, "edge") |> Endpoint.new!(),
      target: attrs |> Data.fetch!(:target, "edge") |> Endpoint.new!(),
      kind: kind,
      data: Map.get(attrs, :data),
      class: Map.get(attrs, :class)
    }
  end

  @spec new!(String.t(), Endpoint.t() | map(), Endpoint.t() | map(), map() | keyword()) :: t()
  def new!(id, source, target, attrs \\ []) do
    attrs
    |> Data.map!("edge")
    |> Map.merge(%{id: id, source: source, target: target})
    |> new!()
  end
end
