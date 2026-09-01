defmodule Daw.GraphTest do
  use ExUnit.Case, async: true

  alias Daw.{Graph, Palette}
  alias PhoenixDnd.{Intent, Scene}

  defp scene, do: Graph.initial_scene()

  defp connect(scene, source_node, source_port, target_node, target_port) do
    Graph.apply_intent(
      scene,
      intent(scene, "connection.create", %{
        "source" => %{"node_id" => source_node, "port_id" => source_port},
        "target" => %{"node_id" => target_node, "port_id" => target_port}
      })
    )
  end

  defp intent(scene, type, payload) do
    Intent.parse!(%{
      "v" => 1,
      "client_id" => "test-client",
      "intent_id" => "intent-#{System.unique_integer([:positive])}",
      "type" => type,
      "phase" => "commit",
      "base_revision" => scene.revision,
      "payload" => payload
    })
  end

  describe "the starting scene" do
    test "is a complete signal path into the master bus" do
      scene = scene()
      plan = Graph.compile(scene)

      assert plan.master == "master"
      assert "mic" in plan.order
      # Every node is ordered after everything feeding it.
      for {target, sources} <- plan.inbound, {source, _port} <- sources do
        assert index(plan.order, source) < index(plan.order, target),
               "#{source} must be evaluated before #{target}"
      end
    end

    test "compiles every node to a kind the DSP layer knows" do
      plan = Graph.compile(scene())

      for {_id, %{kind: kind}} <- plan.nodes do
        assert kind in Palette.ids()
      end
    end
  end

  describe "connection rules" do
    test "refuses a second signal into a port that takes one" do
      scene = scene()
      assert {:error, message} = connect(scene, "tone", "out", "trim", "in")
      assert message =~ "one signal"
      assert message =~ "Mixer"
    end

    test "allows fan-in on a mixer" do
      scene = scene()
      {:ok, changes} = connect(scene, "mic", "out", "bus", "in")
      next = Scene.bump(scene, changes)
      assert length(next.edges) == length(scene.edges) + 1
    end

    test "refuses a connection that would close a loop" do
      # Free the Gain's input first, so the arity rule cannot mask the cycle
      # rule. Audio already flows trim -> bus, so bus -> trim closes the loop.
      scene = scene()

      {:ok, changes} =
        Graph.apply_intent(
          scene,
          intent(scene, "delete.request", %{"node_ids" => [], "edge_ids" => ["edge-1"]})
        )

      scene = Scene.bump(scene, changes)

      assert {:error, message} = connect(scene, "bus", "out", "trim", "in")
      assert message =~ "feedback loop"
    end

    test "refuses patching a node into itself" do
      scene = scene()
      assert {:error, message} = connect(scene, "bus", "out", "bus", "in")
      assert message =~ "into itself"
    end

    test "refuses an output patched to an output" do
      scene = scene()
      assert {:error, message} = connect(scene, "tone", "out", "trim", "out")
      assert message =~ "does not receive audio"
    end

    test "refuses a duplicate cable" do
      scene = scene()
      assert {:error, message} = connect(scene, "trim", "out", "bus", "in")
      assert message =~ "already patched"
    end

    test "refuses an intent based on a stale revision" do
      scene = scene()

      stale =
        intent(scene, "selection.change", %{
          "mode" => "replace",
          "node_ids" => [],
          "edge_ids" => []
        })

      moved = Scene.bump(scene, [])

      assert {:error, message} = Graph.apply_intent(moved, stale)
      assert message =~ "stale intent"
    end
  end

  describe "deletion" do
    test "refuses to remove a fixed part of the studio" do
      scene = scene()

      assert {:error, message} =
               Graph.apply_intent(
                 scene,
                 intent(scene, "delete.request", %{"node_ids" => ["master"], "edge_ids" => []})
               )

      assert message =~ "cannot be removed"
    end

    test "removes a node together with every cable touching it" do
      scene = scene()

      {:ok, changes} =
        Graph.apply_intent(
          scene,
          intent(scene, "delete.request", %{"node_ids" => ["trim"], "edge_ids" => []})
        )

      next = Scene.bump(scene, changes)

      refute Enum.any?(next.nodes, &(&1.id == "trim"))
      refute Enum.any?(next.edges, &(&1.source.node_id == "trim" or &1.target.node_id == "trim"))
    end

    test "a graph with a node removed still compiles and still reaches master" do
      scene = scene()

      {:ok, changes} =
        Graph.apply_intent(
          scene,
          intent(scene, "delete.request", %{"node_ids" => ["bus"], "edge_ids" => []})
        )

      plan = scene |> Scene.bump(changes) |> Graph.compile()

      assert plan.master == "master"
      assert length(plan.order) == map_size(plan.nodes)
    end
  end

  describe "adding nodes" do
    test "adds an unpatched node of every offered kind" do
      for kind <- Palette.addable() do
        assert {:ok, changes, node_id} = Graph.add_node(scene(), kind.id)
        next = Scene.bump(scene(), changes)
        added = Enum.find(next.nodes, &(&1.id == node_id))

        assert Graph.kind_of(added) == kind.id
        assert Map.keys(Graph.params_of(added)) == Enum.map(kind.params, & &1.id) |> Enum.sort()
        refute Enum.any?(next.edges, &(&1.target.node_id == node_id))
      end
    end

    test "refuses to add a second singleton" do
      assert {:error, message} = Graph.add_node(scene(), :master)
      assert message =~ "cannot be added twice"
    end

    test "refuses an unknown kind" do
      assert {:error, message} = Graph.add_node(scene(), "theremin")
      assert message =~ "unknown node kind"
    end
  end

  describe "parameters" do
    test "are validated against the palette before they reach the scene" do
      scene = scene()
      assert {:ok, changes} = Graph.set_param(scene, "trim", "gain_db", "-12.0")
      next = Scene.bump(scene, changes)
      assert Graph.params_of(Enum.find(next.nodes, &(&1.id == "trim")))["gain_db"] == -12.0
    end

    test "are clamped rather than trusted" do
      {:ok, changes} = Graph.set_param(scene(), "trim", "gain_db", 9_999)
      next = Scene.bump(scene(), changes)
      assert Graph.params_of(Enum.find(next.nodes, &(&1.id == "trim")))["gain_db"] == 12.0
    end

    test "reject a parameter the node does not have" do
      assert {:error, _} = Graph.set_param(scene(), "trim", "cutoff_hz", 100)
    end

    test "changing one does not change the topology" do
      scene = scene()
      {:ok, changes} = Graph.set_param(scene, "trim", "gain_db", -3.0)
      next = Scene.bump(scene, changes)

      assert Graph.compile(next).order == Graph.compile(scene).order
    end
  end

  describe "recorders" do
    test "appear in the plan's tap list so the pipeline can spawn a child" do
      assert Graph.compile(scene()).taps == []

      {:ok, changes, node_id} = Graph.add_node(scene(), :recorder)
      plan = scene() |> Scene.bump(changes) |> Graph.compile()

      assert plan.taps == [node_id]
    end
  end

  defp index(list, value), do: Enum.find_index(list, &(&1 == value))
end
