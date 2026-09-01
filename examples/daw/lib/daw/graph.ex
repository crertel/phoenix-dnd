defmodule Daw.Graph do
  @moduledoc """
  Pure scene transitions for the studio, plus the compiler that turns a scene
  into something `Daw.Engine` can run.

  The reducer never mutates the supplied scene; successful results are changes
  ready for `PhoenixDnd.Scene.bump/2`. Rejections carry a sentence the UI can
  show verbatim, because in this demo a rejected edit is a real statement about
  the audio graph - the patch would have fed back on itself, or double-fed a
  port that can only take one signal.
  """

  alias Daw.Palette
  alias PhoenixDnd.{Edge, Endpoint, Intent, Node, Port, Scene, Selection, Viewport}

  @type changes :: keyword()
  @type plan :: %{
          order: [String.t()],
          nodes: %{String.t() => %{kind: atom(), params: map()}},
          inbound: %{String.t() => [{String.t(), String.t()}]},
          taps: [String.t()],
          master: String.t() | nil
        }

  @spec initial_scene() :: Scene.t()
  def initial_scene do
    nodes = [
      node("mic", :mic, %{x: 40, y: 200}),
      node("tone", :tone, %{x: 40, y: 420}, %{"freq" => 220.0, "level_db" => -18.0}),
      node("trim", :gain, %{x: 330, y: 200}),
      node("verb", :reverb, %{x: 330, y: 420}),
      node("bus", :mixer, %{x: 620, y: 300}),
      node("meter", :meter, %{x: 880, y: 300}),
      node("master", :master, %{x: 1130, y: 300})
    ]

    edges = [
      edge("edge-1", "mic", "out", "trim", "in"),
      edge("edge-2", "tone", "out", "verb", "in"),
      edge("edge-3", "trim", "out", "bus", "in"),
      edge("edge-4", "verb", "out", "bus", "in"),
      edge("edge-5", "bus", "out", "meter", "in"),
      edge("edge-6", "meter", "out", "master", "in")
    ]

    Scene.new!(
      nodes: nodes,
      edges: edges,
      selection: Selection.new!(node_ids: ["trim"]),
      viewport: Viewport.new!(center_x: 620, center_y: 320, zoom: 0.8),
      meta: %{next_edge_id: 7, next_node_id: 1}
    )
  end

  @doc """
  Compiles a scene into an ordered evaluation plan.

  Nodes that cannot reach an output are still evaluated - a delay line or a
  reverb tail has to keep running while it is unpatched, otherwise reconnecting
  it would replay stale audio. Only the ordering matters here.
  """
  @spec compile(Scene.t()) :: plan()
  def compile(%Scene{} = scene) do
    inbound =
      Enum.reduce(scene.nodes, %{}, fn node, acc -> Map.put(acc, node.id, []) end)
      |> then(fn acc ->
        Enum.reduce(scene.edges, acc, fn edge, acc ->
          Map.update!(acc, edge.target.node_id, fn sources ->
            sources ++ [{edge.source.node_id, edge.source.port_id}]
          end)
        end)
      end)

    nodes =
      Map.new(scene.nodes, fn node ->
        {node.id, %{kind: kind_of(node), params: params_of(node)}}
      end)

    %{
      order: topological_order(scene),
      nodes: nodes,
      inbound: inbound,
      taps: for({id, %{kind: :recorder}} <- nodes, do: id),
      master: Enum.find_value(scene.nodes, &if(kind_of(&1) == :master, do: &1.id))
    }
  end

  @doc "Adds a node of the given kind, selecting it and leaving it unpatched."
  @spec add_node(Scene.t(), atom() | String.t()) ::
          {:ok, changes(), String.t()} | {:error, String.t()}
  def add_node(%Scene{} = scene, kind_id) do
    with {:ok, kind} <- fetch_addable(kind_id) do
      {node_id, counter, meta} = take_node_id(scene)
      new_node = node(node_id, kind.id, added_position(counter), %{}, counter)

      {:ok,
       [
         nodes: scene.nodes ++ [new_node],
         selection: Selection.new!(node_ids: [node_id]),
         meta: meta
       ], node_id}
    end
  rescue
    error in ArgumentError -> {:error, Exception.message(error)}
  end

  def add_node(_scene, _kind_id), do: {:error, "expected a scene"}

  @doc "Updates one parameter on one node, validated against the palette."
  @spec set_param(Scene.t(), String.t(), String.t(), term()) ::
          {:ok, changes()} | {:error, String.t()}
  def set_param(%Scene{} = scene, node_id, param_id, value) do
    case Enum.find(scene.nodes, &(&1.id == node_id)) do
      nil ->
        {:error, "unknown node #{inspect(node_id)}"}

      node ->
        with {:ok, cast} <- Palette.cast_param(kind_of(node), param_id, value) do
          params = node.data.params |> Map.put(param_id, cast)
          updated = %{node | data: %{node.data | params: params}}
          {:ok, nodes: replace_node(scene.nodes, updated)}
        end
    end
  end

  @doc "Removes the current selection, refusing to delete fixed nodes."
  @spec remove_selection(Scene.t()) :: {:ok, changes()} | {:error, String.t()}
  def remove_selection(%Scene{} = scene) do
    node_ids = Enum.sort(scene.selection.node_ids)
    edge_ids = Enum.sort(scene.selection.edge_ids)

    with :ok <- non_empty_delete(node_ids, edge_ids),
         :ok <- deletable(scene, node_ids) do
      {:ok, delete_changes(scene, node_ids, edge_ids)}
    end
  end

  @spec apply_intent(Scene.t(), Intent.t()) :: {:ok, changes()} | {:error, String.t()}
  def apply_intent(%Scene{} = scene, %Intent{} = intent) do
    with :ok <- current_revision(scene, intent),
         :ok <- committed(intent) do
      reduce(scene, intent)
    end
  rescue
    error in ArgumentError -> {:error, Exception.message(error)}
  end

  def apply_intent(_scene, _intent), do: {:error, "expected a scene and a parsed intent"}

  @doc "The node kind stored on a scene node."
  @spec kind_of(Node.t()) :: atom()
  def kind_of(%Node{data: %{kind: kind}}), do: kind

  @doc "The parameter map stored on a scene node."
  @spec params_of(Node.t()) :: %{String.t() => term()}
  def params_of(%Node{data: %{params: params}}), do: params

  defp reduce(
         scene,
         %Intent{
           type: "nodes.move",
           payload: %{"positions" => positions, "selection" => selection}
         }
       )
       when is_list(positions) and is_map(selection) do
    position_ids = Enum.map(positions, & &1["id"])
    selected_node_ids = Map.get(selection, "node_ids", [])
    selected_edge_ids = Map.get(selection, "edge_ids", [])

    with :ok <- known_node_ids(scene, position_ids),
         :ok <- known_node_ids(scene, selected_node_ids),
         :ok <- known_edge_ids(scene, selected_edge_ids) do
      by_id = Map.new(positions, &{&1["id"], %{x: &1["x"], y: &1["y"]}})

      nodes =
        Enum.map(scene.nodes, fn node ->
          case Map.fetch(by_id, node.id) do
            {:ok, position} -> %{node | position: position}
            :error -> node
          end
        end)

      {:ok,
       nodes: nodes,
       selection: Selection.new!(node_ids: selected_node_ids, edge_ids: selected_edge_ids)}
    end
  end

  defp reduce(
         scene,
         %Intent{
           type: "selection.change",
           payload: %{"mode" => mode, "node_ids" => node_ids, "edge_ids" => edge_ids}
         }
       ) do
    with :ok <- known_node_ids(scene, node_ids),
         :ok <- known_edge_ids(scene, edge_ids) do
      nodes = update_set(scene.selection.node_ids, MapSet.new(node_ids), mode)
      edges = update_set(scene.selection.edge_ids, MapSet.new(edge_ids), mode)
      {:ok, selection: Selection.new!(node_ids: nodes, edge_ids: edges)}
    end
  end

  defp reduce(_scene, %Intent{
         type: "viewport.change",
         payload: %{"center_x" => x, "center_y" => y, "zoom" => zoom}
       }) do
    {:ok, viewport: Viewport.new!(center_x: x, center_y: y, zoom: zoom)}
  end

  defp reduce(scene, %Intent{
         type: "connection.create",
         payload: %{"source" => source_payload, "target" => target_payload}
       }) do
    with {:ok, source, source_port, _source_node} <- endpoint(scene, source_payload, "source"),
         {:ok, target, target_port, target_node} <- endpoint(scene, target_payload, "target"),
         :ok <- output_port(source_port),
         :ok <- input_port(target_port),
         :ok <- distinct_nodes(source, target),
         :ok <- unique_connection(scene, source, target),
         :ok <- port_has_room(scene, target, target_node),
         :ok <- acyclic(scene, source, target) do
      {edge_id, meta} = take_edge_id(scene)
      {:ok, edges: scene.edges ++ [Edge.new!(edge_id, source, target, kind: :audio)], meta: meta}
    end
  end

  defp reduce(scene, %Intent{
         type: "delete.request",
         payload: %{"node_ids" => node_ids, "edge_ids" => edge_ids}
       }) do
    with :ok <- non_empty_delete(node_ids, edge_ids),
         :ok <- known_node_ids(scene, node_ids),
         :ok <- known_edge_ids(scene, edge_ids),
         :ok <- deletable(scene, node_ids) do
      {:ok, delete_changes(scene, node_ids, edge_ids)}
    end
  end

  defp reduce(_scene, %Intent{type: type}) when is_binary(type) do
    {:error, "unsupported or malformed intent #{inspect(type)}"}
  end

  defp reduce(_scene, _intent), do: {:error, "unsupported or malformed intent"}

  # --- studio-specific connection rules -------------------------------------

  defp port_has_room(scene, target, target_node) do
    kind = Palette.fetch!(kind_of(target_node))

    if kind.fan_in do
      :ok
    else
      used? = Enum.any?(scene.edges, &(&1.target == target))

      if used? do
        {:error,
         "#{kind.label} accepts one signal on #{inspect(target.port_id)}; " <>
           "insert a Mixer to combine sources"}
      else
        :ok
      end
    end
  end

  defp acyclic(scene, source, target) do
    # Walk forward from the prospective target; reaching the source means the
    # new edge would close a loop, and a loop in this engine is an unbounded
    # feedback path rather than a musical one.
    if reaches?(scene, target.node_id, source.node_id) do
      {:error, "that connection would create a feedback loop"}
    else
      :ok
    end
  end

  defp reaches?(_scene, from, from), do: true

  defp reaches?(scene, from, goal) do
    scene.edges
    |> Enum.filter(&(&1.source.node_id == from))
    |> Enum.any?(&reaches?(scene, &1.target.node_id, goal))
  end

  defp deletable(scene, node_ids) do
    fixed =
      scene.nodes
      |> Enum.filter(&(&1.id in node_ids))
      |> Enum.filter(&Palette.fetch!(kind_of(&1)).singleton)

    case fixed do
      [] ->
        :ok

      nodes ->
        labels = nodes |> Enum.map(&Palette.fetch!(kind_of(&1)).label) |> Enum.uniq()
        {:error, "#{Enum.join(labels, " and ")} is part of the studio and cannot be removed"}
    end
  end

  defp topological_order(scene) do
    incoming =
      Enum.reduce(scene.edges, Map.new(scene.nodes, &{&1.id, 0}), fn edge, counts ->
        Map.update(counts, edge.target.node_id, 1, &(&1 + 1))
      end)

    ready = for {id, 0} <- incoming, do: id
    visit(scene, Enum.sort(ready), incoming, [])
  end

  defp visit(_scene, [], _incoming, order), do: Enum.reverse(order)

  defp visit(scene, [id | rest], incoming, order) do
    {ready, incoming} =
      scene.edges
      |> Enum.filter(&(&1.source.node_id == id))
      |> Enum.map(& &1.target.node_id)
      |> Enum.reduce({[], incoming}, fn target, {ready, incoming} ->
        incoming = Map.update!(incoming, target, &(&1 - 1))
        if incoming[target] == 0, do: {[target | ready], incoming}, else: {ready, incoming}
      end)

    visit(scene, rest ++ Enum.sort(ready), incoming, [id | order])
  end

  # --- shared reducer helpers -----------------------------------------------

  defp current_revision(%Scene{revision: revision}, %Intent{base_revision: revision}), do: :ok

  defp current_revision(%Scene{revision: revision}, %Intent{base_revision: base}) do
    {:error, "stale intent based on revision #{inspect(base)}; current revision is #{revision}"}
  end

  defp committed(%Intent{phase: "commit"}), do: :ok

  defp committed(%Intent{phase: phase}),
    do: {:error, "unsupported intent phase #{inspect(phase)}"}

  defp known_node_ids(scene, ids) when is_list(ids), do: known_ids(scene.nodes, ids, "node")
  defp known_node_ids(_scene, _ids), do: {:error, "node IDs must be a list"}

  defp known_edge_ids(scene, ids) when is_list(ids), do: known_ids(scene.edges, ids, "edge")
  defp known_edge_ids(_scene, _ids), do: {:error, "edge IDs must be a list"}

  defp known_ids(items, requested, kind) do
    available = MapSet.new(items, & &1.id)

    case requested |> Enum.reject(&MapSet.member?(available, &1)) |> Enum.sort() do
      [] -> :ok
      ids -> {:error, "unknown #{kind} IDs: #{inspect(ids)}"}
    end
  end

  defp update_set(_current, incoming, "replace"), do: incoming
  defp update_set(current, incoming, "add"), do: MapSet.union(current, incoming)
  defp update_set(current, incoming, "remove"), do: MapSet.difference(current, incoming)

  defp update_set(current, incoming, "toggle") do
    current |> MapSet.union(incoming) |> MapSet.difference(MapSet.intersection(current, incoming))
  end

  defp update_set(_current, _incoming, mode) do
    raise ArgumentError, "unsupported selection mode #{inspect(mode)}"
  end

  defp endpoint(scene, %{"node_id" => node_id, "port_id" => port_id}, side) do
    case Enum.find(scene.nodes, &(&1.id == node_id)) do
      nil ->
        {:error, "unknown #{side} node #{inspect(node_id)}"}

      node ->
        case Enum.find(node.ports, &(&1.id == port_id)) do
          nil -> {:error, "unknown #{side} port #{inspect(port_id)} on #{inspect(node_id)}"}
          port -> {:ok, Endpoint.new!(node_id, port_id), port, node}
        end
    end
  end

  defp endpoint(_scene, _payload, side), do: {:error, "malformed #{side} endpoint"}

  defp output_port(%Port{direction: direction}) when direction in [:output, :bidirectional],
    do: :ok

  defp output_port(%Port{id: id}),
    do: {:error, "port #{inspect(id)} does not send audio"}

  defp input_port(%Port{direction: direction}) when direction in [:input, :bidirectional], do: :ok

  defp input_port(%Port{id: id}),
    do: {:error, "port #{inspect(id)} does not receive audio"}

  defp distinct_nodes(%Endpoint{node_id: id}, %Endpoint{node_id: id}),
    do: {:error, "a node cannot patch into itself"}

  defp distinct_nodes(_source, _target), do: :ok

  defp unique_connection(scene, source, target) do
    if Enum.any?(scene.edges, &(&1.source == source and &1.target == target)) do
      {:error, "those ports are already patched together"}
    else
      :ok
    end
  end

  defp non_empty_delete([], []), do: {:error, "delete requires at least one node or edge"}
  defp non_empty_delete(_node_ids, _edge_ids), do: :ok

  defp delete_changes(scene, node_ids, edge_ids) do
    removed_nodes = MapSet.new(node_ids)
    removed_edges = MapSet.new(edge_ids)

    {dropped, kept} =
      Enum.split_with(scene.edges, fn edge ->
        MapSet.member?(removed_edges, edge.id) or
          MapSet.member?(removed_nodes, edge.source.node_id) or
          MapSet.member?(removed_nodes, edge.target.node_id)
      end)

    dropped_ids = MapSet.new(dropped, & &1.id)

    [
      nodes: Enum.reject(scene.nodes, &MapSet.member?(removed_nodes, &1.id)),
      edges: kept,
      selection:
        Selection.new!(
          node_ids: MapSet.difference(scene.selection.node_ids, removed_nodes),
          edge_ids: MapSet.difference(scene.selection.edge_ids, dropped_ids)
        )
    ]
  end

  defp fetch_addable(kind_id) do
    case Palette.fetch(kind_id) do
      {:ok, %{singleton: true} = kind} ->
        {:error, "#{kind.label} already exists and cannot be added twice"}

      {:ok, kind} ->
        {:ok, kind}

      :error ->
        {:error, "unknown node kind #{inspect(kind_id)}"}
    end
  end

  defp replace_node(nodes, updated) do
    Enum.map(nodes, fn node -> if node.id == updated.id, do: updated, else: node end)
  end

  defp node(id, kind_id, position, overrides \\ %{}, counter \\ nil) do
    kind = Palette.fetch!(kind_id)
    label = if counter, do: "#{kind.label} #{counter}", else: kind.label

    Node.new!(id,
      position: position,
      label: label,
      kind: kind_id,
      class: "daw-node--#{kind.category}",
      data: %{kind: kind.id, params: Map.merge(Palette.defaults(kind.id), overrides)},
      ports: Palette.ports(kind.id)
    )
  end

  defp edge(id, source_node, source_port, target_node, target_port) do
    Edge.new!(
      id,
      Endpoint.new!(source_node, source_port),
      Endpoint.new!(target_node, target_port),
      kind: :audio
    )
  end

  defp added_position(counter) do
    slot = counter - 1
    %{x: 120 + rem(slot, 4) * 280, y: 640 + div(slot, 4) * 240}
  end

  defp take_node_id(scene) do
    used = MapSet.new(scene.nodes, & &1.id)
    counter = scene.meta |> counter_from(:next_node_id) |> free_counter("node", used)
    {"node-#{counter}", counter, put_counter(scene.meta, :next_node_id, counter + 1)}
  end

  defp take_edge_id(scene) do
    used = MapSet.new(scene.edges, & &1.id)
    counter = scene.meta |> counter_from(:next_edge_id) |> free_counter("edge", used)
    {"edge-#{counter}", put_counter(scene.meta, :next_edge_id, counter + 1)}
  end

  defp counter_from(meta, key) when is_map(meta) do
    case Map.get(meta, key) || Map.get(meta, Atom.to_string(key)) do
      counter when is_integer(counter) and counter > 0 -> counter
      _other -> 1
    end
  end

  defp counter_from(_meta, _key), do: 1

  defp free_counter(counter, prefix, used) do
    if MapSet.member?(used, "#{prefix}-#{counter}") do
      free_counter(counter + 1, prefix, used)
    else
      counter
    end
  end

  defp put_counter(meta, key, counter) when is_map(meta), do: Map.put(meta, key, counter)
  defp put_counter(_meta, key, counter), do: %{key => counter}
end
