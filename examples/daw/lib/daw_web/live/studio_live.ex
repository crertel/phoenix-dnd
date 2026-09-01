defmodule DawWeb.StudioLive do
  @moduledoc """
  The studio: a `PhoenixDnd.Editor` whose scene is a live Membrane audio graph.

  Three kinds of state share this LiveView, and it is worth being precise about
  which owns what.

  Topology - nodes, edges, positions, selection - is `PhoenixDnd` scene state,
  edited through the intent protocol and answered with accept or reject.

  Parameters are ordinary LiveView form events, because turning a knob is not a
  direct-manipulation gesture and does not belong in the intent protocol. Both
  of those end the same way: bump the scene, recompile the plan, hand it to the
  running engine.

  Level meters are neither. They are transient, arrive ten times a second, and
  are never authoritative, so they are pushed to the browser as events and
  written to the DOM by a hook. Rendering them into the scene would mean a
  server round-trip and a DOM diff per node per tick for information that is
  stale before it lands.
  """

  use Phoenix.LiveView, layout: false

  require Logger

  alias Daw.{Graph, Palette, Pipeline}
  alias Membrane.WebRTC.Signaling
  alias PhoenixDnd.{Command, CommandBatch, Scene}

  @editor_id "studio"

  @impl true
  def mount(_params, _session, socket) do
    scene = Graph.initial_scene()
    plan = Graph.compile(scene)

    socket =
      assign(socket,
        editor_id: @editor_id,
        scene: scene,
        plan: plan,
        notice: nil,
        pipeline: nil,
        capture_signaling: nil,
        player_signaling: nil,
        live?: false,
        running?: false,
        mic: "no mic",
        monitor: "starting"
      )

    {:ok, if(connected?(socket), do: start_studio(socket, plan), else: socket)}
  end

  defp start_studio(socket, plan) do
    capture_signaling = Signaling.new()
    player_signaling = Signaling.new()

    # This LiveView is the browser's peer on both channels. membrane_webrtc_plugin
    # ships Capture and Player LiveViews that would do this, but their browser
    # hooks have problems this example cannot fix from the outside - see
    # priv/static/js/webrtc.js - so the studio speaks the same `json_data`
    # signalling protocol itself.
    Signaling.register_peer(capture_signaling, message_format: :json_data)
    Signaling.register_peer(player_signaling, message_format: :json_data)

    case Membrane.Pipeline.start_link(Pipeline,
           capture_signaling: capture_signaling,
           player_signaling: player_signaling,
           plan: plan,
           owner: self(),
           recording_dir: Application.fetch_env!(:daw, :recording_dir)
         ) do
      {:ok, _supervisor, pipeline} ->
        assign(socket,
          pipeline: pipeline,
          capture_signaling: capture_signaling,
          player_signaling: player_signaling,
          live?: true
        )

      {:error, reason} ->
        Logger.error("could not start the studio pipeline: #{inspect(reason)}")
        assign(socket, notice: "The audio pipeline failed to start: #{inspect(reason)}")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="daw">
      <header class="daw__bar">
        <div class="daw__title">
          <h1>Membrane studio</h1>
          <p>
            A <code>PhoenixDnd.Editor</code>
            scene compiled into a live Membrane pipeline. Patch it while it plays.
          </p>
        </div>

        <div class="daw__transport">
          <span class={["daw__status", @running? && "is-live"]} title={status_hint(@running?)}>
            {if @running?, do: "engine running", else: "waiting for playback peer"}
          </span>
          <span class={["daw__status", @mic == "connected" && "is-live"]}>
            {@mic}
          </span>

          <%!-- The studio's audio output. Visible and with controls on purpose:
                browsers refuse unmuted autoplay until the page has been
                interacted with, and this is the one obvious way to start it. --%>
          <audio id="studio-monitor" phx-hook="StudioPlayer" class="daw__audio" controls autoplay></audio>

          <button type="button" phx-click="fit">Fit view</button>
          <button type="button" phx-click="delete">Delete selection</button>
        </div>
      </header>

      <p :if={@notice} class="daw__notice" role="status">{@notice}</p>

      <div class="daw__body">
        <aside class="daw__palette">
          <p class="daw__hint">
            Wear headphones — monitoring your own mic through speakers feeds back.
          </p>

          <section :for={{category, label} <- Palette.categories()}>
            <h2>{label}</h2>
            <ul>
              <li :for={kind <- addable_in(category)}>
                <button
                  type="button"
                  phx-click="add"
                  phx-value-kind={kind.id}
                  style={"--daw-accent: #{kind.accent}"}
                  title={kind.summary}
                >
                  {kind.label}
                </button>
              </li>
            </ul>
          </section>
        </aside>

        <main id="studio-meters" class="daw__canvas" phx-hook="StudioMeters">
          <.live_component
            module={PhoenixDnd.Editor}
            id={@editor_id}
            scene={@scene}
            min_zoom={0.25}
            max_zoom={2.0}
          >
            <:node :let={%{node: node, selected?: selected?}}>
              <.node_body
                node={node}
                selected?={selected?}
                kind={Palette.fetch!(Graph.kind_of(node))}
              />
            </:node>
          </.live_component>
        </main>
      </div>

      <div :if={@live?} id="studio-capture" phx-hook="StudioCapture" hidden></div>
    </div>
    """
  end

  attr(:node, :map, required: true)
  attr(:kind, :map, required: true)
  attr(:selected?, :boolean, required: true)

  defp node_body(assigns) do
    ~H"""
    <article
      class={["daw-node", "daw-node--#{@kind.category}", @selected? && "is-selected"]}
      style={"--daw-accent: #{@kind.accent}"}
      data-meter={@node.id}
    >
      <header class="daw-node__head">
        <span class="daw-node__kind">{@kind.label}</span>
        <%!-- Filled in by the StudioMeters hook; never rendered by the server. --%>
        <span class="daw-node__db"></span>
      </header>

      <p class="daw-node__summary">{@kind.summary}</p>

      <div class="daw-node__meter" aria-hidden="true">
        <span class="daw-node__meter-fill"></span>
      </div>

      <div :if={@kind.params != []} class="daw-node__params" data-dnd-no-drag>
        <.param
          :for={param <- @kind.params}
          param={param}
          node_id={@node.id}
          value={Map.get(Graph.params_of(@node), param.id, param.default)}
        />
      </div>
    </article>
    """
  end

  attr(:param, :map, required: true)
  attr(:node_id, :string, required: true)
  attr(:value, :any, required: true)

  defp param(%{param: %{type: :float}} = assigns) do
    ~H"""
    <form class="daw-param" id={"param-#{@node_id}-#{@param.id}"} phx-change="param">
      <input type="hidden" name="node" value={@node_id} />
      <input type="hidden" name="param" value={@param.id} />
      <label>
        <span class="daw-param__label">{@param.label}</span>
        <span class="daw-param__value">{format_value(@value)}{unit(@param)}</span>
      </label>
      <input
        type="range"
        name="value"
        min={@param.min}
        max={@param.max}
        step={@param.step}
        value={@value}
        phx-throttle="60"
      />
    </form>
    """
  end

  defp param(%{param: %{type: :enum}} = assigns) do
    ~H"""
    <form class="daw-param" id={"param-#{@node_id}-#{@param.id}"} phx-change="param">
      <input type="hidden" name="node" value={@node_id} />
      <input type="hidden" name="param" value={@param.id} />
      <label><span class="daw-param__label">{@param.label}</span></label>
      <select name="value">
        <option :for={{option, label} <- @param.options} value={option} selected={option == @value}>
          {label}
        </option>
      </select>
    </form>
    """
  end

  defp param(%{param: %{type: :bool}} = assigns) do
    ~H"""
    <form
      class="daw-param daw-param--toggle"
      id={"param-#{@node_id}-#{@param.id}"}
      phx-change="param"
    >
      <input type="hidden" name="node" value={@node_id} />
      <input type="hidden" name="param" value={@param.id} />
      <input type="hidden" name="value" value="false" />
      <label>
        <input type="checkbox" name="value" value="true" checked={@value == true} />
        <span class="daw-param__label">{@param.label}</span>
      </label>
    </form>
    """
  end

  @impl true
  def handle_event("add", %{"kind" => kind}, socket) do
    case Graph.add_node(socket.assigns.scene, kind) do
      {:ok, changes, _node_id} -> {:noreply, commit(socket, changes)}
      {:error, reason} -> {:noreply, assign(socket, notice: reason)}
    end
  end

  def handle_event("delete", _params, socket) do
    case Graph.remove_selection(socket.assigns.scene) do
      {:ok, changes} -> {:noreply, commit(socket, changes)}
      {:error, reason} -> {:noreply, assign(socket, notice: reason)}
    end
  end

  def handle_event("param", %{"node" => node, "param" => param, "value" => value}, socket) do
    case Graph.set_param(socket.assigns.scene, node, param, normalize(value)) do
      {:ok, changes} -> {:noreply, commit(socket, changes)}
      {:error, reason} -> {:noreply, assign(socket, notice: reason)}
    end
  end

  def handle_event("fit", _params, socket) do
    batch =
      CommandBatch.new!([Command.viewport_fit(padding: 72, animate_ms: 200)],
        after_revision: socket.assigns.scene.revision
      )

    {:noreply, PhoenixDnd.push_commands(socket, @editor_id, batch)}
  end

  # Browser -> Membrane. The payload is opaque signalling; the studio only
  # routes it to the channel the sending hook named.
  def handle_event("webrtc_signaling", %{"target" => target, "message" => message}, socket) do
    case signaling(socket, target) do
      nil -> {:noreply, socket}
      channel -> {:noreply, tap_signal(socket, channel, message)}
    end
  end

  def handle_event("mic_status", %{"state" => state}, socket) do
    {:noreply, assign(socket, mic: mic_label(state))}
  end

  def handle_event("monitor_status", %{"state" => state}, socket) do
    {:noreply, assign(socket, monitor: state)}
  end

  @impl true
  def handle_info({:phoenix_dnd, :intent, @editor_id, intent}, socket) do
    case Graph.apply_intent(socket.assigns.scene, intent) do
      {:ok, changes} ->
        socket = commit(socket, changes)
        {:noreply, resolve(socket, intent, :accepted, [])}

      {:error, reason} ->
        socket = assign(socket, notice: reason)
        {:noreply, resolve(socket, intent, :rejected, reason: reason)}
    end
  end

  # Membrane -> browser.
  def handle_info({:membrane_webrtc_signaling, pid, message, _metadata}, socket) do
    case signaling_name(socket, pid) do
      nil -> {:noreply, socket}
      name -> {:noreply, push_event(socket, "webrtc:#{name}", message)}
    end
  end

  def handle_info({:daw_telemetry, levels}, socket) do
    # Telemetry only arrives once the engine is actually ticking, which makes it
    # the honest signal for "the studio is running" - more honest than "we
    # started a pipeline", since the WebRTC sink gates playback until the
    # browser has answered its offer.
    {:noreply, socket |> assign(running?: true) |> push_event("levels", %{levels: levels})}
  end

  def handle_info({:daw_mic, :connected}, socket) do
    {:noreply, assign(socket, mic: "mic live")}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # Bumps the scene and, when the audio graph actually changed, hands the engine
  # a new plan. Selection and viewport edits compile to an identical plan, so
  # they never disturb the pipeline.
  defp commit(socket, changes) do
    scene = Scene.bump(socket.assigns.scene, changes)
    plan = Graph.compile(scene)

    if socket.assigns.pipeline && plan != socket.assigns.plan do
      Pipeline.update_plan(socket.assigns.pipeline, plan)

      if plan.taps != socket.assigns.plan.taps do
        Pipeline.sync_recorders(socket.assigns.pipeline, plan.taps)
      end
    end

    assign(socket, scene: scene, plan: plan, notice: nil)
  end

  defp resolve(socket, intent, status, opts) do
    batch =
      CommandBatch.new!(
        [Command.operation_resolve(intent.intent_id, status, opts)],
        after_revision: socket.assigns.scene.revision
      )

    PhoenixDnd.push_commands(socket, @editor_id, batch)
  end

  defp signaling(socket, "capture"), do: socket.assigns.capture_signaling
  defp signaling(socket, "player"), do: socket.assigns.player_signaling
  defp signaling(_socket, _target), do: nil

  defp signaling_name(%{assigns: %{capture_signaling: %{pid: pid}}}, pid), do: "capture"
  defp signaling_name(%{assigns: %{player_signaling: %{pid: pid}}}, pid), do: "player"
  defp signaling_name(_socket, _pid), do: nil

  defp tap_signal(socket, channel, message) do
    Signaling.signal(channel, message)
    socket
  end

  defp mic_label("connected"), do: "mic live"
  defp mic_label("unavailable"), do: "no mic"
  defp mic_label("failed"), do: "mic failed"
  defp mic_label(_state), do: "mic connecting"

  defp status_hint(true), do: "The DSP graph is being evaluated every 20 ms."

  defp status_hint(false),
    do: "The engine starts once the browser has accepted the studio's audio stream."

  defp addable_in(category), do: Enum.filter(Palette.addable(), &(&1.category == category))

  # A checkbox posts both its hidden false and its checked true.
  defp normalize(value) when is_list(value), do: List.last(value)
  defp normalize(value), do: value

  defp format_value(value) when is_float(value), do: Float.round(value, 2)
  defp format_value(value), do: value

  defp unit(%{unit: unit}), do: " " <> unit
  defp unit(_param), do: ""
end
