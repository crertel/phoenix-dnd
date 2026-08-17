defmodule PhoenixDnd.Scene do
  @moduledoc """
  The complete, server-authoritative snapshot rendered by an editor.

  Scene revisions are monotonic within one editor component instance. Durable
  graph state belongs here; active pointer gestures and measured geometry do
  not.
  """

  alias PhoenixDnd.{Data, Edge, Node, Selection, Viewport}

  defstruct revision: 0,
            nodes: [],
            edges: [],
            selection: %Selection{},
            viewport: %Viewport{},
            meta: nil

  @type t :: %__MODULE__{
          revision: non_neg_integer(),
          nodes: [Node.t()],
          edges: [Edge.t()],
          selection: Selection.t(),
          viewport: Viewport.t(),
          meta: term()
        }

  @spec new!(map() | keyword() | t()) :: t()
  def new!(attrs \\ %{})

  def new!(%__MODULE__{} = scene), do: scene |> Map.from_struct() |> new!()

  def new!(attrs) do
    attrs =
      attrs
      |> Data.map!("scene")
      |> Data.known_keys!([:revision, :nodes, :edges, :selection, :viewport, :meta], "scene")

    scene = %__MODULE__{
      revision: attrs |> Map.get(:revision, 0) |> Data.non_negative_integer!("scene revision"),
      nodes: attrs |> Map.get(:nodes, []) |> Enum.map(&Node.new!/1) |> Data.unique_ids!("node"),
      edges: attrs |> Map.get(:edges, []) |> Enum.map(&Edge.new!/1) |> Data.unique_ids!("edge"),
      selection: attrs |> Map.get(:selection, %{}) |> Selection.new!(),
      viewport: attrs |> Map.get(:viewport, %{}) |> Viewport.new!(),
      meta: Map.get(attrs, :meta)
    }

    validate_references!(scene)
  end

  @spec bump(t(), map() | keyword()) :: t()
  def bump(%__MODULE__{} = scene, changes \\ %{}) do
    changes =
      changes
      |> Data.map!("scene changes")
      |> Data.known_keys!([:nodes, :edges, :selection, :viewport, :meta], "scene change")

    scene
    |> Map.from_struct()
    |> Map.merge(changes)
    |> Map.put(:revision, scene.revision + 1)
    |> new!()
  end

  defp validate_references!(scene) do
    nodes_by_id = Map.new(scene.nodes, &{&1.id, &1})
    edge_ids = MapSet.new(scene.edges, & &1.id)

    Enum.each(scene.edges, fn edge ->
      validate_endpoint!(edge.id, :source, edge.source, nodes_by_id)
      validate_endpoint!(edge.id, :target, edge.target, nodes_by_id)
    end)

    unknown_nodes = MapSet.difference(scene.selection.node_ids, MapSet.new(Map.keys(nodes_by_id)))
    unknown_edges = MapSet.difference(scene.selection.edge_ids, edge_ids)

    if MapSet.size(unknown_nodes) > 0 do
      raise ArgumentError,
            "selection references unknown node IDs: #{inspect(Enum.sort(unknown_nodes))}"
    end

    if MapSet.size(unknown_edges) > 0 do
      raise ArgumentError,
            "selection references unknown edge IDs: #{inspect(Enum.sort(unknown_edges))}"
    end

    scene
  end

  defp validate_endpoint!(edge_id, side, endpoint, nodes_by_id) do
    case Map.fetch(nodes_by_id, endpoint.node_id) do
      :error ->
        raise ArgumentError,
              "edge #{inspect(edge_id)} #{side} references unknown node #{inspect(endpoint.node_id)}"

      {:ok, node} ->
        unless Enum.any?(node.ports, &(&1.id == endpoint.port_id)) do
          raise ArgumentError,
                "edge #{inspect(edge_id)} #{side} references unknown port " <>
                  "#{inspect(endpoint.port_id)} on node #{inspect(endpoint.node_id)}"
        end
    end
  end
end
