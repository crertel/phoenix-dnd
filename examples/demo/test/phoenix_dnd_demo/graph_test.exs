defmodule PhoenixDndDemo.GraphTest do
  use ExUnit.Case, async: true

  alias PhoenixDnd.{Intent, Scene, Selection, Viewport}
  alias PhoenixDndDemo.Graph

  defp intent(scene, type, payload) do
    Intent.parse!(%{
      "v" => 1,
      "client_id" => "graph-test",
      "intent_id" => "#{type}-#{scene.revision}",
      "base_revision" => scene.revision,
      "type" => type,
      "phase" => "commit",
      "payload" => payload
    })
  end

  defp apply!(scene, type, payload) do
    assert {:ok, changes} = Graph.apply_intent(scene, intent(scene, type, payload))
    Scene.bump(scene, changes)
  end

  test "initial scene is a useful, internally valid workflow" do
    scene = Graph.initial_scene()

    assert %Scene{revision: 0} = scene

    assert Enum.map(scene.nodes, & &1.id) == [
             "webhook",
             "mixer",
             "route",
             "email",
             "archive"
           ]

    assert Enum.map(scene.edges, & &1.id) == ["edge-1", "edge-2", "edge-3", "edge-4"]
    assert Enum.all?(scene.nodes, &(&1.ports != []))
    assert scene.selection == Selection.new!(node_ids: ["mixer"])

    assert Enum.all?(
             scene.nodes,
             &match?(%{accent: _, summary: _, template: _, variant: _}, &1.data)
           )

    assert Enum.find(scene.nodes, &(&1.id == "webhook")).data.method == "POST"
    assert Enum.find(scene.nodes, &(&1.id == "mixer")).data.chips == ["Normalize", "Enrich"]

    assert Enum.find(scene.nodes, &(&1.id == "route")).data.branch_labels == %{
             yes: "Qualified",
             no: "Fallback"
           }

    assert Enum.find(scene.nodes, &(&1.id == "email")).data.template_name ==
             "Qualified lead welcome"

    assert Enum.find(scene.nodes, &(&1.id == "archive")).data.retention == "30 days"
    assert scene.viewport == %Viewport{center_x: 520, center_y: 260, zoom: 0.9}
    assert scene.meta == %{next_edge_id: 5, next_node_id: 1}
    assert Scene.new!(scene) == scene
  end

  test "adds every node template with deterministic IDs and selects the new node" do
    templates = [:webhook, "transform", :branch, "email", :archive]

    {scene, ids} =
      Enum.reduce(templates, {Graph.initial_scene(), []}, fn template, {scene, ids} ->
        assert {:ok, changes, node_id} = Graph.add_node(scene, template)
        next_scene = Scene.bump(scene, changes)

        assert next_scene.selection == Selection.new!(node_ids: [node_id])
        assert Scene.new!(next_scene) == next_scene

        {next_scene, ids ++ [node_id]}
      end)

    assert ids == ["node-1", "node-2", "node-3", "node-4", "node-5"]
    assert scene.meta == %{next_edge_id: 5, next_node_id: 6}

    added_nodes = Enum.filter(scene.nodes, &(&1.id in ids))

    assert Enum.map(added_nodes, & &1.data.template) ==
             templates |> Enum.map(&to_string/1) |> Enum.map(&String.to_existing_atom/1)

    assert Enum.uniq(Enum.map(added_nodes, & &1.position)) |> length() == 5

    assert Enum.map(Enum.find(added_nodes, &(&1.id == "node-1")).ports, & &1.id) == ["event"]

    assert Enum.map(Enum.find(added_nodes, &(&1.id == "node-2")).ports, & &1.id) == [
             "input",
             "clean",
             "error"
           ]

    assert Enum.find(added_nodes, &(&1.id == "node-3")).data.branch_labels.no == "Fallback"
    assert Enum.find(added_nodes, &(&1.id == "node-4")).data.template_name
    assert Enum.find(added_nodes, &(&1.id == "node-5")).data.retention == "30 days"
  end

  test "node IDs remain unique when metadata is missing or stale" do
    scene = %{Graph.initial_scene() | meta: nil}

    assert {:ok, first_changes, "node-1"} = Graph.add_node(scene, :email)
    first = Scene.bump(scene, first_changes)

    stale_meta = %{first | meta: %{next_edge_id: 5, next_node_id: 1}}
    assert {:ok, second_changes, "node-2"} = Graph.add_node(stale_meta, "archive")
    second = Scene.bump(stale_meta, second_changes)

    assert Enum.count(second.nodes, &String.starts_with?(&1.id, "node-")) == 2
    assert second.meta == %{next_edge_id: 5, next_node_id: 3}
  end

  test "added node positions keep expanding without wrapping onto earlier nodes" do
    {_scene, positions} =
      Enum.reduce(1..17, {Graph.initial_scene(), []}, fn _, {scene, positions} ->
        assert {:ok, changes, node_id} = Graph.add_node(scene, :transform)
        next_scene = Scene.bump(scene, changes)
        node = Enum.find(next_scene.nodes, &(&1.id == node_id))

        {next_scene, positions ++ [node.position]}
      end)

    assert length(Enum.uniq(positions)) == 17
    assert Enum.at(positions, 0) == %{x: 80, y: 520}
    assert Enum.at(positions, 4) == %{x: 80, y: 800}
    assert List.last(positions) == %{x: 80, y: 1_640}
  end

  test "rejects unknown node templates without changing the scene" do
    scene = Graph.initial_scene()

    assert {:error, reason} = Graph.add_node(scene, "database")
    assert reason =~ ~s(unknown node template "database")
    assert scene == Graph.initial_scene()
  end

  test "removes the current selection and cascades incident edges" do
    scene =
      Graph.initial_scene()
      |> Scene.bump(selection: Selection.new!(node_ids: ["route"], edge_ids: ["edge-1"]))

    assert {:ok, changes} = Graph.remove_selection(scene)
    removed = Scene.bump(scene, changes)

    assert Enum.map(removed.nodes, & &1.id) == ["webhook", "mixer", "email", "archive"]
    assert removed.edges == []
    assert removed.selection == Selection.new!(node_ids: [], edge_ids: [])
    assert removed.meta == %{next_edge_id: 5, next_node_id: 1}
    assert Scene.new!(removed) == removed
  end

  test "does not remove anything when the selection is empty" do
    scene =
      Graph.initial_scene()
      |> Scene.bump(selection: Selection.new!(node_ids: [], edge_ids: []))

    assert {:error, "delete requires at least one node or edge"} = Graph.remove_selection(scene)
  end

  test "moves nodes and replaces selection as one scene change" do
    scene = Graph.initial_scene()

    moved =
      apply!(scene, "nodes.move", %{
        "positions" => [
          %{"id" => "webhook", "x" => 100, "y" => 220},
          %{"id" => "mixer", "x" => 400, "y" => 220}
        ],
        "selection" => %{
          "node_ids" => ["webhook", "mixer"],
          "edge_ids" => ["edge-1"]
        }
      })

    assert Enum.find(moved.nodes, &(&1.id == "webhook")).position == %{x: 100, y: 220}
    assert Enum.find(moved.nodes, &(&1.id == "mixer")).position == %{x: 400, y: 220}
    assert Enum.find(moved.nodes, &(&1.id == "route")).position == %{x: 650, y: 160}
    assert moved.selection.node_ids == MapSet.new(["webhook", "mixer"])
    assert moved.selection.edge_ids == MapSet.new(["edge-1"])
  end

  test "rejects an unknown movement atomically" do
    scene = Graph.initial_scene()

    movement =
      intent(scene, "nodes.move", %{
        "positions" => [%{"id" => "missing", "x" => 0, "y" => 0}],
        "selection" => %{"node_ids" => ["missing"], "edge_ids" => []}
      })

    assert {:error, reason} = Graph.apply_intent(scene, movement)
    assert reason == ~s(unknown node IDs: ["missing"])
    assert String.valid?(reason)
    assert scene == Graph.initial_scene()
  end

  test "applies every selection mode to nodes and edges" do
    scene = Graph.initial_scene()

    added =
      apply!(scene, "selection.change", %{
        "mode" => "add",
        "node_ids" => ["webhook"],
        "edge_ids" => ["edge-1"]
      })

    assert added.selection.node_ids == MapSet.new(["mixer", "webhook"])
    assert added.selection.edge_ids == MapSet.new(["edge-1"])

    removed =
      apply!(added, "selection.change", %{
        "mode" => "remove",
        "node_ids" => ["mixer"],
        "edge_ids" => ["edge-1"]
      })

    assert removed.selection.node_ids == MapSet.new(["webhook"])
    assert removed.selection.edge_ids == MapSet.new()

    toggled =
      apply!(removed, "selection.change", %{
        "mode" => "toggle",
        "node_ids" => ["webhook", "route"],
        "edge_ids" => ["edge-2"]
      })

    assert toggled.selection.node_ids == MapSet.new(["route"])
    assert toggled.selection.edge_ids == MapSet.new(["edge-2"])

    replaced =
      apply!(toggled, "selection.change", %{
        "mode" => "replace",
        "node_ids" => ["email"],
        "edge_ids" => ["edge-3"]
      })

    assert replaced.selection.node_ids == MapSet.new(["email"])
    assert replaced.selection.edge_ids == MapSet.new(["edge-3"])
  end

  test "updates the authoritative viewport" do
    scene = Graph.initial_scene()

    changed =
      apply!(scene, "viewport.change", %{
        "center_x" => -25.5,
        "center_y" => 400,
        "zoom" => 1.75
      })

    assert changed.viewport == %Viewport{center_x: -25.5, center_y: 400, zoom: 1.75}
  end

  test "creates valid connections with deterministic edge IDs" do
    scene = Graph.initial_scene()

    connected =
      apply!(scene, "connection.create", %{
        "source" => %{"node_id" => "webhook", "port_id" => "event"},
        "target" => %{"node_id" => "email", "port_id" => "input"}
      })

    assert List.last(connected.edges).id == "edge-5"
    assert connected.meta == %{next_edge_id: 6, next_node_id: 1}

    connected_again =
      apply!(connected, "connection.create", %{
        "source" => %{"node_id" => "mixer", "port_id" => "error"},
        "target" => %{"node_id" => "archive", "port_id" => "input"}
      })

    assert List.last(connected_again.edges).id == "edge-6"
    assert connected_again.meta == %{next_edge_id: 7, next_node_id: 1}

    duplicate =
      intent(connected_again, "connection.create", %{
        "source" => %{"node_id" => "webhook", "port_id" => "event"},
        "target" => %{"node_id" => "email", "port_id" => "input"}
      })

    assert {:error, "that connection already exists"} =
             Graph.apply_intent(connected_again, duplicate)
  end

  test "infers the next deterministic edge ID if metadata is unavailable" do
    scene = %{Graph.initial_scene() | meta: nil}

    connected =
      apply!(scene, "connection.create", %{
        "source" => %{"node_id" => "webhook", "port_id" => "event"},
        "target" => %{"node_id" => "email", "port_id" => "input"}
      })

    assert List.last(connected.edges).id == "edge-5"
    assert connected.meta == %{next_edge_id: 6}
  end

  test "rejects unknown endpoints and incompatible port directions" do
    scene = Graph.initial_scene()

    unknown =
      intent(scene, "connection.create", %{
        "source" => %{"node_id" => "missing", "port_id" => "out"},
        "target" => %{"node_id" => "email", "port_id" => "input"}
      })

    assert {:error, ~s(unknown source node "missing")} = Graph.apply_intent(scene, unknown)

    reversed =
      intent(scene, "connection.create", %{
        "source" => %{"node_id" => "mixer", "port_id" => "input"},
        "target" => %{"node_id" => "email", "port_id" => "input"}
      })

    assert {:error, ~s(source port "input" does not allow outgoing connections)} =
             Graph.apply_intent(scene, reversed)
  end

  test "deleting nodes cascades incident edges and cleans selection" do
    scene =
      Graph.initial_scene()
      |> Scene.bump(
        selection:
          Selection.new!(
            node_ids: ["mixer", "route"],
            edge_ids: ["edge-1", "edge-2", "edge-4"]
          )
      )

    deleted =
      apply!(scene, "delete.request", %{
        "node_ids" => ["mixer"],
        "edge_ids" => ["edge-4"]
      })

    assert Enum.map(deleted.nodes, & &1.id) == ["webhook", "route", "email", "archive"]
    assert Enum.map(deleted.edges, & &1.id) == ["edge-3"]
    assert deleted.selection.node_ids == MapSet.new(["route"])
    assert deleted.selection.edge_ids == MapSet.new()
    assert Scene.new!(deleted) == deleted
  end

  test "rejects unknown deletion IDs and stale intents" do
    scene = Graph.initial_scene()

    deletion =
      intent(scene, "delete.request", %{
        "node_ids" => ["missing"],
        "edge_ids" => []
      })

    assert {:error, ~s(unknown node IDs: ["missing"])} = Graph.apply_intent(scene, deletion)

    stale = %{deletion | base_revision: scene.revision + 1}

    assert {:error, reason} = Graph.apply_intent(scene, stale)
    assert reason =~ "stale intent"
    assert String.valid?(reason)
  end
end
