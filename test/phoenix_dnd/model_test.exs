defmodule PhoenixDnd.ModelTest do
  use ExUnit.Case, async: true

  alias PhoenixDnd.{Edge, Endpoint, Node, Port, Scene, Selection, Viewport}

  defp scene_attrs do
    input = Port.input("in", anchor: :left)
    output = Port.output("out", anchor: :right)

    source =
      Node.new!("source", position: %{x: 10, y: 20}, ports: [output], data: %{private: true})

    target = Node.new!("target", position: %{x: 310, y: 80}, ports: [input])

    edge = Edge.new!("edge", Endpoint.new!("source", "out"), Endpoint.new!("target", "in"))

    [
      revision: 7,
      nodes: [source, target],
      edges: [edge],
      selection: Selection.new!(node_ids: ["source"], edge_ids: ["edge"]),
      viewport: Viewport.new!(center_x: 100, center_y: 50, zoom: 1.25),
      meta: %{not_serialized: true}
    ]
  end

  test "builds and validates a complete scene snapshot" do
    scene = Scene.new!(scene_attrs())

    assert scene.revision == 7
    assert Enum.map(scene.nodes, & &1.id) == ["source", "target"]
    assert Scene.new!(scene) == scene
    assert Selection.node_selected?(scene.selection, "source")
    assert Selection.edge_selected?(scene.selection, "edge")
    assert scene.viewport == %Viewport{center_x: 100, center_y: 50, zoom: 1.25}
    assert hd(scene.nodes).data == %{private: true}
  end

  test "bumps the revision while replacing authoritative fields" do
    scene = Scene.new!(scene_attrs())
    moved = %{hd(scene.nodes) | position: %{x: 40, y: 60}}

    next = Scene.bump(scene, nodes: [moved | tl(scene.nodes)])

    assert next.revision == 8
    assert hd(next.nodes).position == %{x: 40, y: 60}
    assert next.edges == scene.edges
  end

  test "rejects duplicate IDs" do
    node = Node.new!("duplicate", position: %{x: 0, y: 0})

    assert_raise ArgumentError, ~s(duplicate node IDs: ["duplicate"]), fn ->
      Scene.new!(nodes: [node, node])
    end
  end

  test "rejects dangling node and port references" do
    node = Node.new!("only", position: %{x: 0, y: 0}, ports: [Port.output("out")])

    dangling_node =
      Edge.new!("bad-node", Endpoint.new!("only", "out"), Endpoint.new!("missing", "in"))

    assert_raise ArgumentError, ~r/references unknown node "missing"/, fn ->
      Scene.new!(nodes: [node], edges: [dangling_node])
    end

    dangling_port =
      Edge.new!("bad-port", Endpoint.new!("only", "out"), Endpoint.new!("only", "missing"))

    assert_raise ArgumentError, ~r/references unknown port "missing"/, fn ->
      Scene.new!(nodes: [node], edges: [dangling_port])
    end
  end

  test "rejects selection references outside the scene" do
    assert_raise ArgumentError, ~s(selection references unknown node IDs: ["missing"]), fn ->
      Scene.new!(selection: ["missing"])
    end
  end

  test "rejects invalid viewport and node coordinates" do
    assert_raise ArgumentError, ~r/zoom to be greater than zero/, fn ->
      Viewport.new!(zoom: 0)
    end

    assert_raise ArgumentError, ~r/node x to be a finite number/, fn ->
      Node.new!("node", position: %{x: :infinity, y: 0})
    end

    assert_raise ArgumentError, ~r/finite number between/, fn ->
      Node.new!("node", position: %{x: 1_000_000_000_001, y: 0})
    end
  end

  test "rejects unknown constructor and scene change keys" do
    assert_raise ArgumentError, ~r/unknown node keys: \[:positon\]/, fn ->
      Node.new!(%{id: "node", positon: %{x: 0, y: 0}})
    end

    scene = Scene.new!()

    assert_raise ArgumentError, ~r/unknown scene change keys: \[:node\]/, fn ->
      Scene.bump(scene, node: [])
    end
  end

  test "requires bounded UTF-8 identifiers" do
    assert_raise ArgumentError, ~r/non-empty UTF-8 string/, fn ->
      Node.new!(String.duplicate("x", 513), position: %{x: 0, y: 0})
    end

    assert_raise ArgumentError, ~r/valid UTF-8/, fn ->
      Node.new!(<<255>>, position: %{x: 0, y: 0})
    end
  end
end
