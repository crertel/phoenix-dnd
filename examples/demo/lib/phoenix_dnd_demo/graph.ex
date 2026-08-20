defmodule PhoenixDndDemo.Graph do
  @moduledoc """
  Pure graph state transitions used by the demo LiveView.

  The reducer never mutates the supplied scene. Successful results are scene
  changes that can be passed directly to `PhoenixDnd.Scene.bump/2`.
  """

  alias PhoenixDnd.{Edge, Endpoint, Intent, Node, Port, Scene, Selection, Viewport}

  @type changes :: keyword()
  @type node_template ::
          :webhook | :transform | :branch | :email | :archive | :trigger | :action | String.t()

  @spec initial_scene() :: Scene.t()
  def initial_scene do
    webhook =
      Node.new!("webhook",
        position: %{x: 40, y: 160},
        label: "Webhook",
        kind: :trigger,
        class: "demo-node--trigger",
        data: %{
          accent: "#facc15",
          summary: "Receive and validate a new lead event.",
          template: :webhook,
          variant: :trigger,
          method: "POST",
          path: "/hooks/leads"
        },
        ports: [Port.output("event", anchor: :right)]
      )

    mixer =
      Node.new!("mixer",
        position: %{x: 340, y: 160},
        label: "Mix payload",
        kind: :transform,
        class: "demo-node--transform",
        data: %{
          accent: "#77e6c5",
          summary: "Normalize fields and enrich the event.",
          template: :transform,
          variant: :transform,
          chips: ["Normalize", "Enrich"]
        },
        ports: [
          Port.input("input", anchor: :left),
          Port.output("clean", anchor: :right),
          Port.output("error", anchor: :bottom)
        ]
      )

    route =
      Node.new!("route",
        position: %{x: 650, y: 160},
        label: "Qualified?",
        kind: :branch,
        class: "demo-node--branch",
        data: %{
          accent: "#c084fc",
          summary: "Route qualified leads to the right action.",
          template: :branch,
          variant: :branch,
          branch_labels: %{yes: "Qualified", no: "Fallback"}
        },
        ports: [
          Port.input("input", anchor: :left),
          Port.output("yes", anchor: :right),
          Port.output("no", anchor: :bottom)
        ]
      )

    email =
      Node.new!("email",
        position: %{x: 970, y: 60},
        label: "Send email",
        kind: :action,
        class: "demo-node--action",
        data: %{
          accent: "#60a5fa",
          summary: "Send a personalized welcome message.",
          template: :email,
          variant: :action,
          template_name: "Qualified lead welcome"
        },
        ports: [Port.input("input", anchor: :left)]
      )

    archive =
      Node.new!("archive",
        position: %{x: 970, y: 330},
        label: "Archive event",
        kind: :action,
        class: "demo-node--action",
        data: %{
          accent: "#94a3b8",
          summary: "Persist the event for later review.",
          template: :archive,
          variant: :action,
          retention: "30 days"
        },
        ports: [Port.input("input", anchor: :left)]
      )

    nodes = [webhook, mixer, route, email, archive]

    edges = [
      edge("edge-1", "webhook", "event", "mixer", "input"),
      edge("edge-2", "mixer", "clean", "route", "input"),
      edge("edge-3", "route", "yes", "email", "input"),
      edge("edge-4", "route", "no", "archive", "input")
    ]

    Scene.new!(
      nodes: nodes,
      edges: edges,
      selection: Selection.new!(node_ids: ["mixer"]),
      viewport: Viewport.new!(center_x: 520, center_y: 260, zoom: 0.9),
      meta: %{next_edge_id: 5, next_node_id: 1}
    )
  end

  @doc """
  Builds one demo node template as a scene change without advancing revision.

  The returned node ID is deterministic within the scene and the new node
  replaces the current selection. Pass the changes to `PhoenixDnd.Scene.bump/2`.
  """
  @spec add_node(Scene.t(), node_template()) ::
          {:ok, changes(), String.t()} | {:error, String.t()}
  def add_node(%Scene{} = scene, template_type) do
    with {:ok, template} <- normalize_node_template(template_type) do
      {node_id, counter, meta} = take_node_id(scene)
      node = template_node(template, node_id, counter, added_node_position(counter))

      {:ok,
       [
         nodes: scene.nodes ++ [node],
         selection: Selection.new!(node_ids: [node_id]),
         meta: meta
       ], node_id}
    end
  rescue
    error in ArgumentError -> {:error, Exception.message(error)}
  end

  def add_node(_scene, _template_type), do: {:error, "expected a scene"}

  @doc """
  Removes the scene's selected nodes and edges without advancing revision.

  Edges incident to a selected node are removed along with that node. Pass the
  returned changes to `PhoenixDnd.Scene.bump/2`.
  """
  @spec remove_selection(Scene.t()) :: {:ok, changes()} | {:error, String.t()}
  def remove_selection(%Scene{} = scene) do
    node_ids = scene.selection.node_ids |> Enum.sort()
    edge_ids = scene.selection.edge_ids |> Enum.sort()

    with :ok <- non_empty_delete(node_ids, edge_ids) do
      {:ok, delete_changes(scene, node_ids, edge_ids)}
    end
  end

  def remove_selection(_scene), do: {:error, "expected a scene"}

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
         :ok <- known_edge_ids(scene, selected_edge_ids),
         :ok <- moved_nodes_are_selected(position_ids, selected_node_ids) do
      positions_by_id =
        Map.new(positions, fn position ->
          {position["id"], %{x: position["x"], y: position["y"]}}
        end)

      nodes =
        Enum.map(scene.nodes, fn node ->
          case Map.fetch(positions_by_id, node.id) do
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
           payload: %{
             "mode" => mode,
             "node_ids" => node_ids,
             "edge_ids" => edge_ids
           }
         }
       ) do
    with :ok <- known_node_ids(scene, node_ids),
         :ok <- known_edge_ids(scene, edge_ids) do
      selected_nodes = update_set(scene.selection.node_ids, MapSet.new(node_ids), mode)
      selected_edges = update_set(scene.selection.edge_ids, MapSet.new(edge_ids), mode)

      {:ok, selection: Selection.new!(node_ids: selected_nodes, edge_ids: selected_edges)}
    end
  end

  defp reduce(
         _scene,
         %Intent{
           type: "viewport.change",
           payload: %{"center_x" => center_x, "center_y" => center_y, "zoom" => zoom}
         }
       ) do
    {:ok, viewport: Viewport.new!(center_x: center_x, center_y: center_y, zoom: zoom)}
  end

  defp reduce(
         scene,
         %Intent{
           type: "connection.create",
           payload: %{"source" => source_payload, "target" => target_payload}
         }
       ) do
    with {:ok, source, source_port} <- endpoint(scene, source_payload, "source"),
         {:ok, target, target_port} <- endpoint(scene, target_payload, "target"),
         :ok <- output_port(source_port),
         :ok <- input_port(target_port),
         :ok <- distinct_endpoints(source, target),
         :ok <- new_connection(scene, source, target) do
      {edge_id, meta} = take_edge_id(scene)
      new_edge = Edge.new!(edge_id, source, target, kind: :flow)
      {:ok, edges: scene.edges ++ [new_edge], meta: meta}
    end
  end

  defp reduce(
         scene,
         %Intent{
           type: "delete.request",
           payload: %{"node_ids" => node_ids, "edge_ids" => edge_ids}
         }
       ) do
    with :ok <- non_empty_delete(node_ids, edge_ids),
         :ok <- known_node_ids(scene, node_ids),
         :ok <- known_edge_ids(scene, edge_ids) do
      {:ok, delete_changes(scene, node_ids, edge_ids)}
    end
  end

  defp reduce(_scene, %Intent{type: type}) when is_binary(type) do
    {:error, "unsupported or malformed intent #{inspect(type)}"}
  end

  defp reduce(_scene, _intent), do: {:error, "unsupported or malformed intent"}

  defp current_revision(%Scene{revision: revision}, %Intent{base_revision: revision}), do: :ok

  defp current_revision(%Scene{revision: revision}, %Intent{base_revision: base_revision}) do
    {:error,
     "stale intent based on revision #{inspect(base_revision)}; current revision is #{revision}"}
  end

  defp committed(%Intent{phase: "commit"}), do: :ok

  defp committed(%Intent{phase: phase}),
    do: {:error, "unsupported intent phase #{inspect(phase)}"}

  defp known_node_ids(scene, ids) when is_list(ids) do
    known_ids(scene.nodes, ids, "node")
  end

  defp known_node_ids(_scene, _ids), do: {:error, "node IDs must be a list"}

  defp known_edge_ids(scene, ids) when is_list(ids) do
    known_ids(scene.edges, ids, "edge")
  end

  defp known_edge_ids(_scene, _ids), do: {:error, "edge IDs must be a list"}

  defp known_ids(items, requested_ids, kind) do
    available_ids = MapSet.new(items, & &1.id)
    unknown_ids = requested_ids |> Enum.reject(&MapSet.member?(available_ids, &1)) |> Enum.sort()

    case unknown_ids do
      [] -> :ok
      ids -> {:error, "unknown #{kind} IDs: #{inspect(ids)}"}
    end
  end

  defp moved_nodes_are_selected(moved_ids, selected_ids) do
    if MapSet.subset?(MapSet.new(moved_ids), MapSet.new(selected_ids)) do
      :ok
    else
      {:error, "the movement selection must include every moved node"}
    end
  end

  defp update_set(_current, incoming, "replace"), do: incoming
  defp update_set(current, incoming, "add"), do: MapSet.union(current, incoming)
  defp update_set(current, incoming, "remove"), do: MapSet.difference(current, incoming)

  defp update_set(current, incoming, "toggle") do
    current
    |> MapSet.union(incoming)
    |> MapSet.difference(MapSet.intersection(current, incoming))
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
          nil -> {:error, "unknown #{side} port #{inspect(port_id)} on node #{inspect(node_id)}"}
          port -> {:ok, Endpoint.new!(node_id, port_id), port}
        end
    end
  end

  defp endpoint(_scene, _payload, side), do: {:error, "malformed #{side} endpoint"}

  defp output_port(%Port{direction: direction}) when direction in [:output, :bidirectional],
    do: :ok

  defp output_port(%Port{id: id}) do
    {:error, "source port #{inspect(id)} does not allow outgoing connections"}
  end

  defp input_port(%Port{direction: direction}) when direction in [:input, :bidirectional], do: :ok

  defp input_port(%Port{id: id}) do
    {:error, "target port #{inspect(id)} does not allow incoming connections"}
  end

  defp distinct_endpoints(endpoint, endpoint), do: {:error, "cannot connect a port to itself"}
  defp distinct_endpoints(_source, _target), do: :ok

  defp new_connection(scene, source, target) do
    if Enum.any?(scene.edges, &(&1.source == source and &1.target == target)) do
      {:error, "that connection already exists"}
    else
      :ok
    end
  end

  defp non_empty_delete([], []), do: {:error, "delete requires at least one node or edge"}
  defp non_empty_delete(_node_ids, _edge_ids), do: :ok

  defp delete_changes(scene, node_ids, edge_ids) do
    removed_nodes = MapSet.new(node_ids)
    explicitly_removed_edges = MapSet.new(edge_ids)

    {removed_edges, kept_edges} =
      Enum.split_with(scene.edges, fn edge ->
        MapSet.member?(explicitly_removed_edges, edge.id) or
          MapSet.member?(removed_nodes, edge.source.node_id) or
          MapSet.member?(removed_nodes, edge.target.node_id)
      end)

    removed_edge_ids = MapSet.new(removed_edges, & &1.id)

    selection =
      Selection.new!(
        node_ids: MapSet.difference(scene.selection.node_ids, removed_nodes),
        edge_ids: MapSet.difference(scene.selection.edge_ids, removed_edge_ids)
      )

    [
      nodes: Enum.reject(scene.nodes, &MapSet.member?(removed_nodes, &1.id)),
      edges: kept_edges,
      selection: selection
    ]
  end

  defp normalize_node_template(template)
       when template in [:webhook, :transform, :branch, :email, :archive],
       do: {:ok, template}

  defp normalize_node_template(template) when template in [:trigger, "trigger"],
    do: {:ok, :webhook}

  defp normalize_node_template(template) when template in [:action, "action"],
    do: {:ok, :email}

  defp normalize_node_template(template) when is_binary(template) do
    case template do
      "webhook" -> {:ok, :webhook}
      "transform" -> {:ok, :transform}
      "branch" -> {:ok, :branch}
      "email" -> {:ok, :email}
      "archive" -> {:ok, :archive}
      _ -> unknown_node_template(template)
    end
  end

  defp normalize_node_template(template), do: unknown_node_template(template)

  defp unknown_node_template(template) do
    {:error,
     "unknown node template #{inspect(template)}; expected webhook, transform, branch, email, or archive"}
  end

  defp template_node(:webhook, id, counter, position) do
    Node.new!(id,
      position: position,
      label: "Webhook #{counter}",
      kind: :trigger,
      class: "demo-node--trigger",
      data: %{
        accent: "#facc15",
        summary: "Receive a signed event from an external service.",
        template: :webhook,
        variant: :trigger,
        method: "POST",
        path: "/hooks/#{id}"
      },
      ports: [Port.output("event", anchor: :right)]
    )
  end

  defp template_node(:transform, id, counter, position) do
    Node.new!(id,
      position: position,
      label: "Transform #{counter}",
      kind: :transform,
      class: "demo-node--transform",
      data: %{
        accent: "#77e6c5",
        summary: "Normalize fields and enrich the incoming event.",
        template: :transform,
        variant: :transform,
        chips: ["Normalize", "Enrich"]
      },
      ports: [
        Port.input("input", anchor: :left),
        Port.output("clean", anchor: :right),
        Port.output("error", anchor: :bottom)
      ]
    )
  end

  defp template_node(:branch, id, counter, position) do
    Node.new!(id,
      position: position,
      label: "Branch #{counter}",
      kind: :branch,
      class: "demo-node--branch",
      data: %{
        accent: "#c084fc",
        summary: "Split the workflow using a server-owned condition.",
        template: :branch,
        variant: :branch,
        branch_labels: %{yes: "Qualified", no: "Fallback"}
      },
      ports: [
        Port.input("input", anchor: :left),
        Port.output("yes", anchor: :right),
        Port.output("no", anchor: :bottom)
      ]
    )
  end

  defp template_node(:email, id, counter, position) do
    Node.new!(id,
      position: position,
      label: "Send email #{counter}",
      kind: :action,
      class: "demo-node--action",
      data: %{
        accent: "#60a5fa",
        summary: "Send a personalized message to the current lead.",
        template: :email,
        variant: :action,
        template_name: "Qualified lead welcome"
      },
      ports: [Port.input("input", anchor: :left)]
    )
  end

  defp template_node(:archive, id, counter, position) do
    Node.new!(id,
      position: position,
      label: "Archive #{counter}",
      kind: :action,
      class: "demo-node--action",
      data: %{
        accent: "#94a3b8",
        summary: "Persist the event for later inspection and replay.",
        template: :archive,
        variant: :action,
        retention: "30 days"
      },
      ports: [Port.input("input", anchor: :left)]
    )
  end

  defp added_node_position(counter) do
    slot = counter - 1
    %{x: 80 + rem(slot, 4) * 300, y: 520 + div(slot, 4) * 280}
  end

  defp take_node_id(scene) do
    used_ids = MapSet.new(scene.nodes, & &1.id)
    counter = max(node_meta_counter(scene.meta), inferred_node_counter(scene.nodes))
    counter = next_unused_node_counter(counter, used_ids)

    {"node-#{counter}", counter, put_next_node_id(scene.meta, counter + 1)}
  end

  defp node_meta_counter(%{next_node_id: counter}) when is_integer(counter) and counter > 0,
    do: counter

  defp node_meta_counter(%{"next_node_id" => counter}) when is_integer(counter) and counter > 0,
    do: counter

  defp node_meta_counter(_meta), do: 1

  defp inferred_node_counter(nodes) do
    Enum.reduce(nodes, 1, fn node, next_counter ->
      case Regex.run(~r/\Anode-(\d+)\z/, node.id, capture: :all_but_first) do
        [number] -> max(String.to_integer(number) + 1, next_counter)
        _ -> next_counter
      end
    end)
  end

  defp next_unused_node_counter(counter, used_ids) do
    if MapSet.member?(used_ids, "node-#{counter}") do
      next_unused_node_counter(counter + 1, used_ids)
    else
      counter
    end
  end

  defp put_next_node_id(meta, counter) when is_map(meta),
    do: Map.put(meta, :next_node_id, counter)

  defp put_next_node_id(_meta, counter), do: %{next_node_id: counter}

  defp take_edge_id(scene) do
    used_ids = MapSet.new(scene.edges, & &1.id)
    counter = max(meta_counter(scene.meta), inferred_counter(scene.edges))
    counter = next_unused_counter(counter, used_ids)

    {"edge-#{counter}", put_next_edge_id(scene.meta, counter + 1)}
  end

  defp meta_counter(%{next_edge_id: counter}) when is_integer(counter) and counter > 0,
    do: counter

  defp meta_counter(%{"next_edge_id" => counter}) when is_integer(counter) and counter > 0,
    do: counter

  defp meta_counter(_meta), do: 1

  defp inferred_counter(edges) do
    Enum.reduce(edges, 1, fn edge, next_counter ->
      case Regex.run(~r/\Aedge-(\d+)\z/, edge.id, capture: :all_but_first) do
        [number] -> max(String.to_integer(number) + 1, next_counter)
        _ -> next_counter
      end
    end)
  end

  defp next_unused_counter(counter, used_ids) do
    if MapSet.member?(used_ids, "edge-#{counter}") do
      next_unused_counter(counter + 1, used_ids)
    else
      counter
    end
  end

  defp put_next_edge_id(meta, counter) when is_map(meta),
    do: Map.put(meta, :next_edge_id, counter)

  defp put_next_edge_id(_meta, counter), do: %{next_edge_id: counter}

  defp edge(id, source_node, source_port, target_node, target_port) do
    Edge.new!(
      id,
      Endpoint.new!(source_node, source_port),
      Endpoint.new!(target_node, target_port),
      kind: :flow
    )
  end
end
