defmodule PhoenixDndDemoWeb.EditorLive do
  use Phoenix.LiveView

  alias PhoenixDnd.{Command, CommandBatch, Intent, Scene, Viewport}
  alias PhoenixDndDemo.Graph

  @editor_id "demo-workflow"
  @tick_ms 1_000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        editor_id: @editor_id,
        page_title: "Phoenix DnD demo",
        scene: Graph.initial_scene(),
        pulse: 0,
        last_event: "Waiting for an interaction…",
        last_status: :idle
      )

    if connected?(socket), do: schedule_tick()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="demo-shell">
      <header class="demo-header">
        <p class="demo-kicker">Phoenix LiveView · server authoritative</p>
        <h1>Workflow canvas</h1>
        <p class="demo-intro">
          Build the graph while live server telemetry flows through its nodes.
          Pan, zoom, drag, lasso-select, connect ports, and add or remove steps.
        </p>
      </header>

      <section class="demo-toolbar" aria-label="Canvas controls">
        <button class="demo-button demo-button--primary" phx-click="fit">Fit scene</button>

        <form class="demo-add-form" phx-submit="add_node">
          <label class="demo-sr-only" for="demo-node-kind">Node type</label>
          <select id="demo-node-kind" class="demo-select" name="kind" aria-label="Node type">
            <option value="webhook">Webhook source</option>
            <option value="transform" selected>Transform</option>
            <option value="branch">Decision</option>
            <option value="email">Email action</option>
            <option value="archive">Archive action</option>
          </select>
          <button class="demo-button" type="submit">Add node</button>
        </form>

        <button
          class="demo-button demo-button--danger"
          phx-click="remove_selected"
          disabled={selection_empty?(@scene)}
        >
          Remove selected
        </button>
        <button
          class="demo-button"
          phx-click="center_selected"
          disabled={MapSet.size(@scene.selection.node_ids) == 0}
        >
          Center selected
        </button>
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
            <.node_card node={node} selected?={selected?} pulse={@pulse} />
          </:node>
        </.live_component>
      </section>

      <footer
        class={["demo-event-log", "demo-event-log--#{@last_status}"]}
        role="status"
        aria-live="polite"
        aria-atomic="true"
      >
        <span class="demo-event-log__label">Server</span>
        <span>{@last_event}</span>
      </footer>
    </main>
    """
  end

  defp node_card(assigns) do
    assigns = assign(assigns, :runtime, node_runtime(assigns.node, assigns.pulse))

    ~H"""
    <article
      class={["demo-node", @selected? && "demo-node--selected"]}
      style={"--demo-node-accent: #{node_data(@node, :accent, "#77e6c5")}"}
    >
      <header class="demo-node__header">
        <span class="demo-node__kind">{@node.kind}</span>
        <strong class="demo-node__title">{@node.label}</strong>
        <span class={[
          "demo-node__status",
          @runtime.live? && "demo-node__status--live",
          !@runtime.live? && "demo-node__status--quiet"
        ]}>
          <span class="demo-node__status-dot"></span>
          {@runtime.status}
        </span>
      </header>

      <div class="demo-node__body">
        <p class="demo-node__summary">
          {node_data(@node, :summary, "A configurable workflow step.")}
        </p>

        <div :if={@node.kind == :trigger} class="demo-node__meta">
          <div class="demo-node__meta-row">
            <span class="demo-node__chip">{node_data(@node, :method, "POST")}</span>
            <code>{node_data(@node, :path, "/hooks/events")}</code>
          </div>
        </div>

        <div :if={@node.kind == :transform} class="demo-node__chips">
          <span
            :for={field <- node_data(@node, :chips, ["Normalize", "Enrich"])}
            class="demo-node__chip"
          >
            {field}
          </span>
        </div>

        <div :if={@node.kind == :branch} class="demo-node__split">
          <div class="demo-node__split-item">
            <span class="demo-node__metric-label">{branch_label(@node, :yes, "yes")}</span>
            <strong>{@runtime.left}</strong>
          </div>
          <div class="demo-node__split-item">
            <span class="demo-node__metric-label">{branch_label(@node, :no, "no")}</span>
            <strong>{@runtime.right}</strong>
          </div>
        </div>

        <div :if={@node.kind == :action} class="demo-node__activity">
          <span>{action_detail(@node)}</span>
          <strong>{@runtime.activity}</strong>
        </div>

        <div :if={@node.kind != :branch} class="demo-node__metrics">
          <div class="demo-node__metric">
            <strong class="demo-node__metric-value">{@runtime.primary}</strong>
            <span class="demo-node__metric-label">{@runtime.primary_label}</span>
          </div>
          <div class="demo-node__metric">
            <strong class="demo-node__metric-value">{@runtime.secondary}</strong>
            <span class="demo-node__metric-label">{@runtime.secondary_label}</span>
          </div>
        </div>

        <div :if={@node.kind in [:transform, :action]} class="demo-node__progress" aria-hidden="true">
          <span class="demo-node__progress-bar" style={"--demo-progress: #{@runtime.progress}%"}></span>
        </div>
      </div>
    </article>
    """
  end

  @impl true
  def handle_info(:demo_tick, socket) do
    schedule_tick()
    {:noreply, update(socket, :pulse, &(&1 + 1))}
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

  def handle_event("add_node", %{"kind" => kind}, socket) do
    case Graph.add_node(socket.assigns.scene, kind) do
      {:ok, changes, node_id} ->
        next_scene = Scene.bump(socket.assigns.scene, changes)
        command = Command.viewport_center_node(node_id, zoom: 1.0, animate_ms: 220)

        socket =
          socket
          |> assign(
            scene: next_scene,
            last_event: "added #{node_id} at r#{next_scene.revision}",
            last_status: :accepted
          )
          |> enqueue_command(command, next_scene.revision)

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, reject_action(socket, "add node", reason)}
    end
  end

  def handle_event("add_node", _params, socket) do
    {:noreply, reject_action(socket, "add node", "choose a valid node type")}
  end

  def handle_event("remove_selected", _params, socket) do
    case Graph.remove_selection(socket.assigns.scene) do
      {:ok, changes} ->
        next_scene = Scene.bump(socket.assigns.scene, changes)
        command = Command.viewport_fit(padding: 72, animate_ms: 220)

        socket =
          socket
          |> assign(
            scene: next_scene,
            last_event: "removed selection at r#{next_scene.revision}",
            last_status: :accepted
          )
          |> enqueue_command(command, next_scene.revision)

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, reject_action(socket, "remove selection", reason)}
    end
  end

  def handle_event("center_selected", _params, socket) do
    case socket.assigns.scene.selection.node_ids |> Enum.sort() |> List.first() do
      nil ->
        {:noreply, reject_action(socket, "center selection", "select a node first")}

      node_id ->
        command = Command.viewport_center_node(node_id, zoom: 1.15, animate_ms: 220)
        {:noreply, push_command(socket, command, "center #{node_id}")}
    end
  end

  def handle_event("home", _params, socket) do
    command =
      Command.viewport_set(Viewport.new!(center_x: 520, center_y: 260, zoom: 0.9),
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
    socket
    |> assign(last_event: "server command: #{label}", last_status: :command)
    |> enqueue_command(command, socket.assigns.scene.revision)
  end

  defp enqueue_command(socket, command, revision) do
    batch = CommandBatch.new!([command], after_revision: revision)
    PhoenixDnd.push_commands(socket, @editor_id, batch)
  end

  defp reject_action(socket, label, reason) do
    assign(socket,
      last_event: "could not #{label}: #{reason}",
      last_status: :rejected
    )
  end

  defp selection_empty?(scene) do
    MapSet.size(scene.selection.node_ids) == 0 and MapSet.size(scene.selection.edge_ids) == 0
  end

  defp schedule_tick, do: Process.send_after(self(), :demo_tick, @tick_ms)

  defp node_data(node, key, default) do
    case node.data do
      data when is_map(data) -> Map.get(data, key, Map.get(data, to_string(key), default))
      _ -> default
    end
  end

  defp branch_label(node, branch, default) do
    case node_data(node, :branch_labels, %{}) do
      labels when is_map(labels) ->
        Map.get(labels, branch, Map.get(labels, to_string(branch), default))

      _ ->
        default
    end
  end

  defp action_detail(node) do
    case node_data(node, :template, nil) do
      template when template in [:archive, "archive"] ->
        "Retention #{node_data(node, :retention, "30 days")}"

      _ ->
        node_data(node, :template_name, "Worker queue")
    end
  end

  defp node_runtime(node, pulse) do
    seed = :erlang.phash2(node.id, 19)
    wave = rem(pulse * 7 + seed, 23)

    case node.kind do
      :trigger ->
        %{
          status: "listening",
          live?: true,
          primary: Integer.to_string(1_284 + pulse * 3 + seed),
          primary_label: "events received",
          secondary: "#{42 + wave}/min",
          secondary_label: "current rate",
          progress: 64 + rem(wave, 25),
          left: "",
          right: "",
          activity: ""
        }

      :transform ->
        %{
          status: if(rem(pulse + seed, 7) == 0, do: "warming", else: "running"),
          live?: true,
          primary: Integer.to_string(31 + wave),
          primary_label: "events / sec",
          secondary: "#{96 + rem(wave, 4)}%",
          secondary_label: "clean output",
          progress: 58 + rem(pulse * 5 + seed, 37),
          left: "",
          right: "",
          activity: ""
        }

      :branch ->
        positive = 61 + rem(wave, 12)

        %{
          status: "evaluating",
          live?: true,
          primary: "",
          primary_label: "",
          secondary: "",
          secondary_label: "",
          progress: positive,
          left: "#{positive}%",
          right: "#{100 - positive}%",
          activity: ""
        }

      :action ->
        archive? = node_data(node, :template, nil) in [:archive, "archive"]

        %{
          status:
            if(archive?,
              do: "syncing",
              else: Enum.at(["queued", "sending", "delivered"], rem(pulse + seed, 3))
            ),
          live?: rem(pulse + seed, 5) != 0,
          primary: if(archive?, do: "#{8 + rem(wave, 9)}k", else: Integer.to_string(18 + wave)),
          primary_label: if(archive?, do: "records stored", else: "delivered today"),
          secondary:
            if(archive?, do: "#{34 + rem(wave, 12)}%", else: Integer.to_string(rem(wave, 6))),
          secondary_label: if(archive?, do: "storage used", else: "in queue"),
          progress: 35 + rem(pulse * 4 + seed, 58),
          left: "",
          right: "",
          activity: if(archive?, do: "#{2 + rem(wave, 8)}s ago", else: "template v3")
        }

      _ ->
        %{
          status: "ready",
          live?: false,
          primary: Integer.to_string(wave),
          primary_label: "processed",
          secondary: "0",
          secondary_label: "errors",
          progress: 50,
          left: "",
          right: "",
          activity: "idle"
        }
    end
  end
end
