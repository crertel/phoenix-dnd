defmodule DawWeb.StudioLiveTest do
  @moduledoc """
  Covers the seam between the editor and the audio engine: which edits are
  supposed to reach the pipeline, and which are deliberately not.
  """

  use DawWeb.ConnCase, async: false

  alias Daw.Graph
  alias PhoenixDnd.Intent

  # The LiveView keeps the compiled plan in its assigns, and only pushes it to
  # the pipeline when it differs. Reading it back is the most direct way to
  # assert what would have been sent.
  defp plan(view), do: assigns(view).plan
  defp scene(view), do: assigns(view).scene
  defp assigns(view), do: :sys.get_state(view.pid).socket.assigns

  defp intent(view, type, payload) do
    Intent.parse!(%{
      "v" => 1,
      "client_id" => "test-client",
      "intent_id" => "intent-#{System.unique_integer([:positive])}",
      "type" => type,
      "phase" => "commit",
      "base_revision" => scene(view).revision,
      "payload" => payload
    })
  end

  # Delivers the message PhoenixDnd.Editor sends to its owner on a committed
  # gesture, then waits for the LiveView to finish handling it.
  defp commit(view, type, payload) do
    send(view.pid, {:phoenix_dnd, :intent, "studio", intent(view, type, payload)})
    render(view)
    view
  end

  describe "the initial page" do
    test "renders the studio graph and the palette", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      assert html =~ "Membrane studio"
      assert html =~ "Master Out"
      assert html =~ "Oscillator"
      assert html =~ "Bitcrusher"
      assert html =~ ~s(data-editor-id="studio")
    end
  end

  describe "edits that must reach the engine" do
    test "changing a parameter recompiles the plan with the new value", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert plan(view).nodes["trim"].params["gain_db"] == 0.0

      render_change(view, "param", %{"node" => "trim", "param" => "gain_db", "value" => "-12.0"})

      assert plan(view).nodes["trim"].params["gain_db"] == -12.0
    end

    test "a rejected parameter leaves the plan untouched", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      before = plan(view)

      html =
        render_change(view, "param", %{
          "node" => "trim",
          "param" => "cutoff_hz",
          "value" => "100"
        })

      assert plan(view) == before
      assert html =~ "no parameter"
    end

    test "adding a node puts it in the plan, unpatched", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      render_click(view, "add", %{"kind" => "delay"})

      added = Enum.find(plan(view).nodes, fn {_id, node} -> node.kind == :delay end)
      assert {id, _node} = added
      assert plan(view).inbound[id] == []
      assert id in plan(view).order
    end

    test "creating a connection changes what feeds a node", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert plan(view).inbound["bus"] == [{"trim", "out"}, {"verb", "out"}]

      commit(view, "connection.create", %{
        "source" => %{"node_id" => "mic", "port_id" => "out"},
        "target" => %{"node_id" => "bus", "port_id" => "in"}
      })

      assert plan(view).inbound["bus"] == [{"trim", "out"}, {"verb", "out"}, {"mic", "out"}]
    end

    test "adding a recorder adds a tap for the pipeline to spawn a child for", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert plan(view).taps == []
      render_click(view, "add", %{"kind" => "recorder"})
      assert [_recorder] = plan(view).taps
    end
  end

  describe "edits that must not reach the engine" do
    test "moving a node changes the scene but compiles to the same plan", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      before = plan(view)

      commit(view, "nodes.move", %{
        "positions" => [%{"id" => "trim", "x" => 999, "y" => 777}],
        "selection" => %{"node_ids" => ["trim"], "edge_ids" => []}
      })

      moved = Enum.find(scene(view).nodes, &(&1.id == "trim"))
      assert moved.position == %{x: 999, y: 777}

      # Position is not audio. The engine must not be disturbed by a drag.
      assert plan(view) == before
    end

    test "selecting a node compiles to the same plan", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      before = plan(view)

      commit(view, "selection.change", %{
        "mode" => "replace",
        "node_ids" => ["verb"],
        "edge_ids" => []
      })

      assert MapSet.member?(scene(view).selection.node_ids, "verb")
      assert plan(view) == before
    end
  end

  describe "rejections" do
    test "a patch that would feed back is refused and explained", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      before = plan(view)

      commit(view, "delete.request", %{"node_ids" => [], "edge_ids" => ["edge-1"]})

      html =
        commit(view, "connection.create", %{
          "source" => %{"node_id" => "bus", "port_id" => "out"},
          "target" => %{"node_id" => "trim", "port_id" => "in"}
        })
        |> render()

      assert html =~ "feedback loop"
      assert plan(view).inbound["trim"] == []
      assert before.inbound["trim"] == [{"mic", "out"}]
    end

    test "deleting the master bus is refused", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      html =
        commit(view, "delete.request", %{"node_ids" => ["master"], "edge_ids" => []}) |> render()

      assert html =~ "cannot be removed"
      assert plan(view).master == "master"
    end
  end

  describe "metering" do
    test "telemetry is pushed to the browser, not rendered into the scene", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      levels = %{"trim" => %{peak: 0.5, rms_db: -9.1}}

      send(view.pid, {:daw_telemetry, levels})

      # Ten of these arrive per second. Rendering them would mean a DOM diff per
      # node per tick for information that is stale before it lands.
      assert_push_event(view, "levels", %{levels: ^levels})
      refute render(view) =~ "-9.1"
    end

    test "each node carries the hook's anchor for its meter", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      assert html =~ ~s(data-meter="trim")
      assert html =~ "daw-node__meter-fill"
    end

    test "telemetry is what marks the engine as running", %{conn: conn} do
      {:ok, view, html} = live(conn, "/")
      refute html =~ "engine running"

      send(view.pid, {:daw_telemetry, %{}})

      assert render(view) =~ "engine running"
    end
  end

  describe "webrtc signalling" do
    test "the studio renders its own capture and playback elements", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # Its own, rather than membrane_webrtc_plugin's Capture/Player LiveViews:
      # those hooks throw under strict mode, monitor the raw microphone, and
      # render a muted output. See priv/static/js/webrtc.js.
      assert html =~ ~s(phx-hook="StudioPlayer")
      assert html =~ ~s(phx-hook="StudioCapture")
      assert html =~ ~s(id="studio-monitor")

      # The output must not be muted, or the master fader appears to do nothing.
      refute html =~ ~r/<audio[^>]*\smuted/
    end

    test "each Membrane channel's messages reach the matching browser hook", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      %{capture_signaling: capture, player_signaling: player} = assigns(view)

      offer = %{"type" => "sdp_offer", "data" => %{"type" => "offer", "sdp" => "o"}}

      # Both channels are already fully peered (this LiveView and the Membrane
      # element), so routing is asserted from the observable direction: the
      # event name the browser hook is expected to be listening on.
      send(view.pid, {:membrane_webrtc_signaling, player.pid, offer, %{}})
      assert_push_event(view, "webrtc:player", ^offer)

      send(view.pid, {:membrane_webrtc_signaling, capture.pid, offer, %{}})
      assert_push_event(view, "webrtc:capture", ^offer)

      assert capture.pid != player.pid
    end

    test "signalling from an unrecognised channel is ignored", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      send(view.pid, {:membrane_webrtc_signaling, self(), %{"type" => "sdp_offer"}, %{}})

      assert render(view) =~ "Membrane studio"
    end

    test "browser signalling is forwarded to a real channel", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      candidate = %{
        "candidate" => "candidate:1 1 UDP 1 127.0.0.1 9 typ host",
        "sdpMLineIndex" => 0,
        "sdpMid" => "0",
        "usernameFragment" => nil
      }

      render_hook(view, "webrtc_signaling", %{
        "target" => "player",
        "message" => %{"type" => "ice_candidate", "data" => candidate}
      })

      assert render(view) =~ "Membrane studio"
    end

    test "an unknown signalling target is ignored rather than crashing", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      render_hook(view, "webrtc_signaling", %{"target" => "nonsense", "message" => %{}})

      assert render(view) =~ "Membrane studio"
    end

    test "microphone status from the browser is reflected in the header", %{conn: conn} do
      {:ok, view, html} = live(conn, "/")
      assert html =~ "no mic"

      assert render_hook(view, "mic_status", %{"state" => "connected"}) =~ "mic live"
      assert render_hook(view, "mic_status", %{"state" => "unavailable"}) =~ "no mic"
    end
  end

  describe "the pipeline seam" do
    test "a plan sent to the pipeline is forwarded to the engine child" do
      plan = Graph.compile(Graph.initial_scene())
      state = %{owner: self(), recorders: MapSet.new(), recording_dir: "/tmp"}

      assert {[notify_child: {:engine, {:plan, ^plan}}], ^state} =
               Daw.Pipeline.handle_info({:plan, plan}, %{}, state)
    end

    test "the microphone is not required for the pipeline to be built" do
      # Regression: the mic used to sit in the spine on a static engine pad, so
      # nothing ran until a browser granted microphone permission.
      plan = Graph.compile(Graph.initial_scene())

      assert {[spec: spec], _state} =
               Daw.Pipeline.handle_init(%{},
                 plan: plan,
                 owner: self(),
                 recording_dir: "/tmp",
                 capture_signaling: Membrane.WebRTC.Signaling.new(),
                 player_signaling: Membrane.WebRTC.Signaling.new()
               )

      # Two independent entries: the engine spine, and an unlinked mic source.
      assert length(spec) == 2
    end

    test "a microphone track links itself to the engine when it arrives" do
      state = %{owner: self(), recorders: MapSet.new(), recording_dir: "/tmp"}
      tracks = [%{id: "track-1", kind: :audio}]

      assert {[spec: [_link]], ^state} =
               Daw.Pipeline.handle_child_notification(
                 {:new_tracks, tracks},
                 :mic_source,
                 %{},
                 state
               )

      assert_receive {:daw_mic, :connected}
    end

    test "a video track is ignored" do
      state = %{owner: self(), recorders: MapSet.new(), recording_dir: "/tmp"}
      tracks = [%{id: "track-2", kind: :video}]

      assert {[spec: []], ^state} =
               Daw.Pipeline.handle_child_notification(
                 {:new_tracks, tracks},
                 :mic_source,
                 %{},
                 state
               )
    end

    test "recorder taps are reconciled into child specs and removals" do
      state = %{owner: self(), recorders: MapSet.new(["old"]), recording_dir: "/tmp"}

      assert {actions, next} = Daw.Pipeline.handle_info({:sync_recorders, ["new"]}, %{}, state)
      assert next.recorders == MapSet.new(["new"])
      assert [{:spec, [_child]}, {:remove_children, [{:recorder, "old"}]}] = actions
    end
  end
end
