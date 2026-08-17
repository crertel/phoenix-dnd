defmodule PhoenixDnd.DomTest do
  use ExUnit.Case, async: true

  alias PhoenixDnd.Dom

  test "builds stable, selector-safe DOM IDs from arbitrary public IDs" do
    editor_id = "workflow / \"東京\""
    node_id = "source.with punctuation?#"
    port_id = "out/one"

    ids = [
      Dom.editor_id(editor_id),
      Dom.surface_id(editor_id),
      Dom.world_id(editor_id),
      Dom.edges_id(editor_id),
      Dom.nodes_id(editor_id),
      Dom.overlay_id(editor_id),
      Dom.edge_id(editor_id, "edge one"),
      Dom.node_id(editor_id, node_id),
      Dom.port_id(editor_id, node_id, port_id)
    ]

    assert Enum.all?(ids, &Regex.match?(~r/\A[A-Za-z0-9_.-]+\z/, &1))
    assert length(Enum.uniq(ids)) == length(ids)

    assert Dom.port_id(editor_id, node_id, port_id) ==
             Dom.port_id(editor_id, node_id, port_id)
  end

  test "uses unambiguous boundaries between encoded ID segments" do
    refute Dom.port_id("editor", "node-a", "port") ==
             Dom.port_id("editor", "node", "a-port")
  end
end
