defmodule PhoenixDnd.Selection do
  @moduledoc """
  The authoritative node and edge selection for a scene.
  """

  alias PhoenixDnd.Data

  defstruct node_ids: MapSet.new(), edge_ids: MapSet.new()

  @type t :: %__MODULE__{
          node_ids: MapSet.t(String.t()),
          edge_ids: MapSet.t(String.t())
        }

  @spec new!(map() | keyword() | [String.t()] | t()) :: t()
  def new!(%__MODULE__{} = selection) do
    %__MODULE__{
      node_ids: ids!(selection.node_ids, "selection node ID"),
      edge_ids: ids!(selection.edge_ids, "selection edge ID")
    }
  end

  def new!(values) when is_list(values) do
    if Keyword.keyword?(values) do
      values |> Map.new() |> new!()
    else
      new!(%{node_ids: values})
    end
  end

  def new!(attrs) do
    attrs =
      attrs
      |> Data.map!("selection")
      |> Data.known_keys!([:node_ids, :edge_ids], "selection")

    %__MODULE__{
      node_ids: attrs |> Map.get(:node_ids, []) |> ids!("selection node ID"),
      edge_ids: attrs |> Map.get(:edge_ids, []) |> ids!("selection edge ID")
    }
  end

  @spec node_selected?(t(), String.t()) :: boolean()
  def node_selected?(%__MODULE__{node_ids: ids}, id), do: MapSet.member?(ids, id)

  @spec edge_selected?(t(), String.t()) :: boolean()
  def edge_selected?(%__MODULE__{edge_ids: ids}, id), do: MapSet.member?(ids, id)

  defp ids!(ids, context) do
    ids
    |> Enum.map(&Data.id!(&1, context))
    |> MapSet.new()
  end
end
