defmodule PhoenixDndDemoWeb.EditorLive do
  use Phoenix.LiveView

  alias PhoenixDnd.{Command, CommandBatch, Intent, Scene, Viewport}
  alias PhoenixDndDemo.Graph

  @editor_id "demo-workflow"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       editor_id: @editor_id,
       page_title: "Phoenix DnD demo",
       scene: Graph.initial_scene(),
       last_event: "Waiting for an interaction…",
       last_status: :idle
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="demo-shell">
      <header class="demo-header">
        <p class="demo-kicker">Phoenix LiveView · server authoritative</p>
        <h1>Workflow canvas</h1>
        <p class="demo-intro">
          Pan with the wheel, zoom with Ctrl/⌘ + wheel, drag nodes, lasso-select,
          and connect compatible ports. Durable state lives in this LiveView.
        </p>
      </header>

      <section class="demo-toolbar" aria-label="Canvas controls">
        <button class="demo-button demo-button--primary" phx-click="fit">Fit scene</button>
        <button class="demo-button" phx-click="center">Center mixer</button>
        <button class="demo-button" phx-click="home">Home viewport</button>
        <button class="demo-button" phx-click="cancel">Cancel gesture</button>
        <button class="demo-button" type="button" onclick="window.location.reload()">Reset</button>

        <span class="demo-toolbar__spacer"></span>
        <span class="demo-stat">revision <strong>{@scene.revision}</strong></span>
        <span class="demo-stat">nodes <strong>{length(@scene.nodes)}</strong></span>
        <span class="demo-stat">edges <strong>{length(@scene.edges)}</strong></span>
      </section>

      <section class="demo-stage">
        <.live_component
          module={PhoenixDnd.Editor}
          id={@editor_id}
          scene={@scene}
          class="demo-editor"
          min_zoom={0.25}
          max_zoom={3.0}
          aria_label="Demo workflow editor"
        >
          <:node :let={%{node: node, selected?: selected?}}>
            <article
              class={["demo-node", selected? && "demo-node--selected"]}
              style={"--demo-node-accent: #{node.data.accent}"}
            >
              <header class="demo-node__header">
                <span class="demo-node__kind">{node.kind}</span>
                <strong class="demo-node__title">{node.label}</strong>
              </header>
              <p class="demo-node__body">{node.data.summary}</p>
            </article>
          </:node>
        </.live_component>
      </section>

      <footer class={["demo-event-log", "demo-event-log--#{@last_status}"]}>
        <span class="demo-event-log__label">Server</span>
        <span>{@last_event}</span>
      </footer>
    </main>
    """
  end

  @impl true
  def handle_info({:phoenix_dnd, :intent, @editor_id, %Intent{} = intent}, socket) do
    case Graph.apply_intent(socket.assigns.scene, intent) do
      {:ok, changes} ->
        next_scene = Scene.bump(socket.assigns.scene, changes)

        socket =
          socket
          |> assign(
            scene: next_scene,
            last_event: "accepted #{intent.type} at r#{intent.base_revision}",
            last_status: :accepted
          )
          |> resolve_operation(intent, :accepted, next_scene.revision)

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(last_event: "rejected #{intent.type}: #{reason}", last_status: :rejected)
          |> resolve_operation(intent, :rejected, socket.assigns.scene.revision, reason)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("fit", _params, socket) do
    {:noreply,
     push_command(socket, Command.viewport_fit(padding: 72, animate_ms: 220), "fit scene")}
  end

  def handle_event("center", _params, socket) do
    command = Command.viewport_center_node("mixer", zoom: 1.15, animate_ms: 220)
    {:noreply, push_command(socket, command, "center mixer")}
  end

  def handle_event("home", _params, socket) do
    command =
      Command.viewport_set(Viewport.new!(center_x: 320, center_y: 180, zoom: 0.9),
        animate_ms: 220
      )

    {:noreply, push_command(socket, command, "home viewport")}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, push_command(socket, Command.interaction_cancel(), "cancel interaction")}
  end

  defp resolve_operation(socket, intent, status, revision, reason \\ nil) do
    command = Command.operation_resolve(intent.intent_id, status, reason: reason)
    batch = CommandBatch.new!([command], after_revision: revision)
    PhoenixDnd.push_commands(socket, @editor_id, batch)
  end

  defp push_command(socket, command, label) do
    batch = CommandBatch.new!([command], after_revision: socket.assigns.scene.revision)

    socket
    |> assign(last_event: "server command: #{label}", last_status: :command)
    |> PhoenixDnd.push_commands(@editor_id, batch)
  end
end
