defmodule PhoenixDnd.EditorTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Phoenix.LiveView.Socket
  alias PhoenixDnd.{Dom, Edge, Editor, Endpoint, Intent, Node, Port, Scene, Selection, Viewport}

  defmodule SlotHost do
    use Phoenix.Component

    alias PhoenixDnd.Editor

    attr(:scene, :any, required: true)

    def editor(assigns) do
      ~H"""
      <.live_component module={Editor} id="slotted" scene={@scene}>
        <:node :let={%{node: node, selected?: selected?}}>
          <strong data-custom-node={node.id}>{node.label}:{selected?}</strong>
        </:node>
      </.live_component>
      """
    end
  end

  defp scene(revision \\ 7) do
    source =
      Node.new!("source / one",
        position: %{x: 10, y: 20},
        label: "Source",
        kind: :source,
        class: "source-node",
        data: %{secret: "must-not-be-rendered"},
        ports: [Port.output("out/main", anchor: :right, class: "output-port")]
      )

    target =
      Node.new!("target",
        position: %{x: 310, y: 80},
        label: "Target",
        ports: [Port.input("in", anchor: :left)]
      )

    edge =
      Edge.new!(
        "edge / one",
        Endpoint.new!("source / one", "out/main"),
        Endpoint.new!("target", "in"),
        class: "main-edge"
      )

    Scene.new!(
      revision: revision,
      nodes: [source, target],
      edges: [edge],
      selection: Selection.new!(node_ids: [source.id], edge_ids: [edge.id]),
      viewport: Viewport.new!(center_x: 25, center_y: -10, zoom: 1.5)
    )
  end

  test "renders the graph hook DOM contract from a complete scene" do
    scene = scene()
    html = render_component(Editor, id: "workflow / unsafe", scene: scene)

    assert html =~ ~s(id="#{Dom.editor_id("workflow / unsafe")}")
    assert html =~ ~s(class="phoenix-dnd")
    assert html =~ ~s(phx-hook="PhoenixDnd.Editor.Graph")
    assert html =~ ~s(data-editor-id="workflow / unsafe")
    assert html =~ ~s(data-scene-revision="7")
    assert html =~ ~s(data-center-x="25")
    assert html =~ ~s(data-center-y="-10")
    assert html =~ ~s(data-zoom="1.5")
    assert html =~ ~s(data-min-zoom="0.1")
    assert html =~ ~s(data-max-zoom="4.0")

    assert html =~ "data-dnd-surface"
    assert html =~ "data-dnd-world"
    assert html =~ "data-dnd-edge"
    assert html =~ "data-dnd-edge-hit"
    assert html =~ ~s(data-source-node="source / one")
    assert html =~ ~s(data-source-port="out/main")
    assert html =~ ~s(data-target-node="target")
    assert html =~ ~s(data-target-port="in")

    assert html =~ ~s(data-dnd-node data-node-id="source / one")
    assert html =~ ~s(data-x="10")
    assert html =~ ~s(data-y="20")
    assert html =~ ~s(data-selected="true")
    assert html =~ ~s(data-dnd-port data-node-id="source / one" data-port-id="out/main")
    assert html =~ ~s(data-direction="output")
    assert html =~ ~s(data-anchor="right")

    assert html =~ ~s(id="#{Dom.overlay_id("workflow / unsafe")}")
    assert html =~ ~s(data-dnd-overlay phx-update="ignore")
    assert html =~ "data-dnd-wire-preview"
    assert html =~ "data-dnd-selection-rect"
    refute html =~ "must-not-be-rendered"
  end

  test "renders custom node content with node and selection slot context" do
    html = render_component(&SlotHost.editor/1, scene: scene())

    assert html =~ ~s(data-custom-node="source / one")
    assert html =~ "Source:true"
    assert html =~ ~s(data-custom-node="target")
    assert html =~ "Target:false"
  end

  test "accepts repeated identical scenes and advances revisions" do
    {:ok, socket} = Editor.mount(%Socket{})
    {:ok, socket} = Editor.update(%{id: "editor", scene: scene()}, socket)
    assert {:ok, socket} = Editor.update(%{id: "editor", scene: scene()}, socket)
    assert {:ok, _socket} = Editor.update(%{id: "editor", scene: scene(8)}, socket)
  end

  test "rejects changed content at the same revision and revision regressions" do
    {:ok, socket} = Editor.mount(%Socket{})
    {:ok, socket} = Editor.update(%{id: "editor", scene: scene()}, socket)

    changed = Scene.bump(scene(), viewport: Viewport.new!(center_x: 99))
    changed = %{changed | revision: 7}

    assert_raise ArgumentError, "scene content changed without advancing revision 7", fn ->
      Editor.update(%{id: "editor", scene: changed}, socket)
    end

    assert_raise ArgumentError, ~r/scene revision regressed from 7 to 6/, fn ->
      Editor.update(%{id: "editor", scene: scene(6)}, socket)
    end
  end

  test "requires finite zoom limits containing the authoritative viewport" do
    {:ok, socket} = Editor.mount(%Socket{})

    assert_raise ArgumentError, ~r/finite number between/, fn ->
      Editor.update(%{id: "editor", scene: scene(), max_zoom: 1.0e20}, socket)
    end

    assert_raise ArgumentError, ~r/scene viewport zoom 1.5 to be between/, fn ->
      Editor.update(%{id: "editor", scene: scene(), max_zoom: 1.25}, socket)
    end
  end

  test "parses and forwards valid intents to the owning parent by default" do
    {:ok, socket} = Editor.mount(%Socket{})
    {:ok, socket} = Editor.update(%{id: "editor", scene: scene()}, socket)

    payload = %{
      "v" => 1,
      "client_id" => "client-1",
      "intent_id" => "intent-2",
      "base_revision" => 7,
      "type" => "selection.change",
      "phase" => "commit",
      "payload" => %{"mode" => "replace", "node_ids" => ["target"], "edge_ids" => []}
    }

    assert {:reply, %{status: "received", intent_id: "intent-2", scene_revision: 7}, ^socket} =
             Editor.handle_event(Editor.intent_event(), payload, socket)

    assert_receive {:phoenix_dnd, :intent, "editor",
                    %Intent{intent_id: "intent-2", type: "selection.change"}}
  end

  test "replies with a safe error and does not forward malformed intents" do
    {:ok, socket} = Editor.mount(%Socket{})
    {:ok, socket} = Editor.update(%{id: "editor", scene: scene(), notify: self()}, socket)

    assert {:reply,
            %{status: "error", code: "invalid_intent", message: "intent must be an object"},
            ^socket} = Editor.handle_event(Editor.intent_event(), "not-an-object", socket)

    refute_received {:phoenix_dnd, :intent, _, _}
  end
end
