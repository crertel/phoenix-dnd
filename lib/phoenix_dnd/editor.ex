defmodule PhoenixDnd.Editor do
  @moduledoc """
  A controlled, server-authoritative node editor.

  The component renders a complete `PhoenixDnd.Scene` snapshot. Browser-side
  interaction state is transient; accepted changes must arrive in a later
  scene revision from the owning LiveView.
  """

  use Phoenix.LiveComponent

  alias PhoenixDnd.{Data, Dom, Intent, Scene, Selection}

  @intent_event "phoenix_dnd:intent"

  @doc "The targeted hook event used for client-to-server intents."
  @spec intent_event() :: String.t()
  def intent_event, do: @intent_event

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, assign(socket, notify: self())}
  end

  @impl Phoenix.LiveComponent
  def update(%{id: id, scene: %Scene{} = raw_scene} = assigns, socket) do
    id = Data.id!(id, "editor id")
    scene = Scene.new!(raw_scene)
    validate_revision!(socket.assigns[:scene], scene)

    min_zoom = validate_zoom!(Map.get(assigns, :min_zoom, 0.1), :min_zoom)
    max_zoom = validate_zoom!(Map.get(assigns, :max_zoom, 4.0), :max_zoom)

    if min_zoom > max_zoom do
      raise ArgumentError,
            "expected :min_zoom to be less than or equal to :max_zoom, " <>
              "got: #{inspect(min_zoom)} and #{inspect(max_zoom)}"
    end

    unless scene.viewport.zoom >= min_zoom and scene.viewport.zoom <= max_zoom do
      raise ArgumentError,
            "expected scene viewport zoom #{inspect(scene.viewport.zoom)} to be between " <>
              ":min_zoom #{inspect(min_zoom)} and :max_zoom #{inspect(max_zoom)}"
    end

    notify = validate_notify!(Map.get(assigns, :notify) || socket.assigns[:notify] || self())

    component_assigns =
      assigns
      |> Map.put(:id, id)
      |> Map.put(:scene, scene)
      |> Map.put(:notify, notify)
      |> Map.put(:min_zoom, min_zoom)
      |> Map.put(:max_zoom, max_zoom)
      |> Map.put_new(:class, nil)
      |> Map.put_new(:aria_label, "Node editor")
      |> Map.put_new(:node, [])

    {:ok, assign(socket, component_assigns)}
  end

  def update(assigns, _socket) do
    raise ArgumentError,
          "#{inspect(__MODULE__)} requires a non-empty string :id and a complete " <>
            "PhoenixDnd.Scene in :scene, got: #{inspect(Map.take(assigns, [:id, :scene]))}"
  end

  @impl Phoenix.LiveComponent
  def handle_event(@intent_event, payload, socket) do
    case Intent.parse(payload) do
      {:ok, intent} ->
        send(
          socket.assigns.notify,
          {:phoenix_dnd, :intent, socket.assigns.id, intent}
        )

        {:reply,
         %{
           status: "received",
           intent_id: intent.intent_id,
           scene_revision: socket.assigns.scene.revision
         }, socket}

      {:error, reason} ->
        {:reply,
         %{
           status: "error",
           code: "invalid_intent",
           message: reason
         }, socket}
    end
  end

  attr(:id, :string, required: true)
  attr(:scene, Scene, required: true)
  attr(:notify, :any, default: nil)
  attr(:class, :any, default: nil)
  attr(:min_zoom, :any, default: 0.1)
  attr(:max_zoom, :any, default: 4.0)
  attr(:aria_label, :string, default: "Node editor")

  slot(:node)

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <style :type={PhoenixDnd.ColocatedCSS} source="../../priv/static/phoenix_dnd.css">
      /* Extract the packaged fallback stylesheet as colocated CSS. */
    </style>
    <div
      id={Dom.editor_id(@id)}
      class={compact_classes(["phoenix-dnd", @class])}
      phx-hook=".Graph"
      phx-target={@myself}
      tabindex="0"
      role="region"
      aria-label={@aria_label}
      data-editor-id={@id}
      data-scene-revision={@scene.revision}
      data-center-x={@scene.viewport.center_x}
      data-center-y={@scene.viewport.center_y}
      data-zoom={@scene.viewport.zoom}
      data-min-zoom={@min_zoom}
      data-max-zoom={@max_zoom}
    >
      <div
        id={Dom.surface_id(@id)}
        class="phoenix-dnd__surface"
        data-dnd-surface
      >
        <div
          id={Dom.world_id(@id)}
          class="phoenix-dnd__world"
          data-dnd-world
        >
          <svg
            id={Dom.edges_id(@id)}
            class="phoenix-dnd__edges"
            data-dnd-edges
            aria-hidden="true"
          >
            <g
              :for={edge <- @scene.edges}
              :key={edge.id}
              id={Dom.edge_id(@id, edge.id)}
            >
              <path
                class="phoenix-dnd__edge-hit"
                d=""
                data-dnd-edge-hit
                data-edge-id={edge.id}
              />
              <path
                class={
                  compact_classes([
                    "phoenix-dnd__edge",
                    edge.class,
                    Selection.edge_selected?(@scene.selection, edge.id) &&
                      "phoenix-dnd__edge--selected"
                  ])
                }
                d=""
                data-dnd-edge
                data-edge-id={edge.id}
                data-source-node={edge.source.node_id}
                data-source-port={edge.source.port_id}
                data-target-node={edge.target.node_id}
                data-target-port={edge.target.port_id}
                data-kind={edge.kind}
                data-selected={selected_string(Selection.edge_selected?(@scene.selection, edge.id))}
              />
            </g>
          </svg>

          <div id={Dom.nodes_id(@id)} class="phoenix-dnd__nodes" data-dnd-nodes>
            <div
              :for={node <- @scene.nodes}
              :key={node.id}
              id={Dom.node_id(@id, node.id)}
              class={
                compact_classes([
                  "phoenix-dnd__node",
                  node.class,
                  Selection.node_selected?(@scene.selection, node.id) &&
                    "phoenix-dnd__node--selected"
                ])
              }
              style={position_style(node.position)}
              data-dnd-node
              data-node-id={node.id}
              data-x={node.position.x}
              data-y={node.position.y}
              data-kind={node.kind}
              data-selected={selected_string(Selection.node_selected?(@scene.selection, node.id))}
            >
              <div class="phoenix-dnd__node-content" data-dnd-drag-handle>
                <%= if @node == [] do %>
                  <span class="phoenix-dnd__node-label">{node.label || node.id}</span>
                <% else %>
                  {render_slot(@node, %{
                    node: node,
                    selected?: Selection.node_selected?(@scene.selection, node.id)
                  })}
                <% end %>
              </div>

              <span
                :for={port <- node.ports}
                :key={port.id}
                id={Dom.port_id(@id, node.id, port.id)}
                class={compact_classes(["phoenix-dnd__port", port.class])}
                aria-hidden="true"
                data-dnd-port
                data-node-id={node.id}
                data-port-id={port.id}
                data-direction={port.direction}
                data-anchor={port.anchor}
              >
                <span class="phoenix-dnd__port-marker" aria-hidden="true"></span>
              </span>
            </div>
          </div>
        </div>

        <svg
          id={Dom.overlay_id(@id)}
          class="phoenix-dnd__overlay"
          data-dnd-overlay
          phx-update="ignore"
          aria-hidden="true"
        >
          <path class="phoenix-dnd__wire-preview" data-dnd-wire-preview />
          <rect class="phoenix-dnd__selection-rect" data-dnd-selection-rect />
        </svg>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Graph">
        import {GraphHook} from "phoenix_dnd/priv/static/phoenix_dnd.js"
        export default GraphHook
      </script>
    </div>
    """
  end

  defp validate_notify!(target) when is_pid(target), do: target

  defp validate_notify!(target) do
    raise ArgumentError, "expected :notify to be a pid, got: #{inspect(target)}"
  end

  defp validate_zoom!(zoom, name) do
    Data.positive_number!(zoom, inspect(name))
  end

  defp validate_revision!(nil, _scene), do: :ok

  defp validate_revision!(
         %Scene{revision: revision} = previous,
         %Scene{revision: revision} = scene
       ) do
    if previous != scene do
      raise ArgumentError,
            "scene content changed without advancing revision #{revision}"
    end

    :ok
  end

  defp validate_revision!(%Scene{revision: previous}, %Scene{revision: revision})
       when revision < previous do
    raise ArgumentError,
          "scene revision regressed from #{previous} to #{revision}; use a new component ID to reset"
  end

  defp validate_revision!(%Scene{}, %Scene{}), do: :ok

  defp selected_string(true), do: "true"
  defp selected_string(false), do: "false"

  defp compact_classes(classes), do: Enum.reject(classes, &(&1 in [nil, false, ""]))

  defp position_style(%{x: x, y: y}), do: "transform: translate(#{x}px, #{y}px);"
end
