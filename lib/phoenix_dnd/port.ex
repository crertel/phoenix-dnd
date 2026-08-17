defmodule PhoenixDnd.Port do
  @moduledoc """
  A connectable port rendered on a node.
  """

  alias PhoenixDnd.Data

  @directions [:input, :output, :bidirectional]
  @anchors [:left, :right, :top, :bottom]

  @enforce_keys [:id, :direction, :anchor]
  defstruct [:id, :direction, :anchor, :data, :class]

  @type direction :: :input | :output | :bidirectional
  @type anchor :: :left | :right | :top | :bottom

  @type t :: %__MODULE__{
          id: String.t(),
          direction: direction(),
          anchor: anchor(),
          data: term(),
          class: term()
        }

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = port), do: validate!(port)

  def new!(attrs) do
    attrs =
      attrs
      |> Data.map!("port")
      |> Data.known_keys!([:id, :direction, :anchor, :data, :class], "port")

    %__MODULE__{
      id: attrs |> Data.fetch!(:id, "port") |> Data.id!("port id"),
      direction:
        attrs
        |> Map.get(:direction, :bidirectional)
        |> Data.one_of!(@directions, "port direction"),
      anchor: attrs |> Map.get(:anchor, :right) |> Data.one_of!(@anchors, "port anchor"),
      data: Map.get(attrs, :data),
      class: Map.get(attrs, :class)
    }
  end

  @spec new!(String.t(), map() | keyword()) :: t()
  def new!(id, attrs) do
    attrs
    |> Data.map!("port")
    |> Map.put(:id, id)
    |> new!()
  end

  @spec input(String.t(), map() | keyword()) :: t()
  def input(id, attrs \\ []), do: new!(id, Map.put(Data.map!(attrs, "port"), :direction, :input))

  @spec output(String.t(), map() | keyword()) :: t()
  def output(id, attrs \\ []),
    do: new!(id, Map.put(Data.map!(attrs, "port"), :direction, :output))

  defp validate!(port), do: new!(Map.from_struct(port))
end
