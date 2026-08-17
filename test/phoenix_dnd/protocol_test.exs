defmodule PhoenixDnd.ProtocolTest do
  use ExUnit.Case, async: true

  alias PhoenixDnd.{Command, CommandBatch, Intent, Viewport}

  defp envelope(type, payload, overrides \\ %{}) do
    Map.merge(
      %{
        "v" => 1,
        "client_id" => "client-1",
        "intent_id" => "intent-1",
        "gesture_id" => "gesture-1",
        "base_revision" => 12,
        "type" => type,
        "phase" => "commit",
        "payload" => payload
      },
      overrides
    )
  end

  test "parses a structurally valid node movement intent" do
    payload =
      envelope("nodes.move", %{
        "positions" => [%{"id" => "a", "x" => 10.5, "y" => -3}],
        "selection" => %{"node_ids" => ["a"], "edge_ids" => []}
      })

    assert {:ok, intent} = Intent.parse(payload)
    assert %Intent{type: "nodes.move", phase: "commit", base_revision: 12} = intent
    assert intent.payload == payload["payload"]
  end

  test "validates intent envelopes and type-specific payloads" do
    assert {:error, "unsupported intent protocol version: 2"} =
             Intent.parse(envelope("client.ready", %{}, %{"v" => 2}))

    assert {:error, ~s(missing "positions" in nodes.move payload)} =
             Intent.parse(envelope("nodes.move", %{}))

    assert {:error, "expected viewport zoom to be greater than zero"} =
             Intent.parse(
               envelope("viewport.change", %{"center_x" => 0, "center_y" => 0, "zoom" => 0})
             )

    assert {:error, ~s(missing "target" in connection.create payload)} =
             Intent.parse(
               envelope("connection.create", %{
                 "source" => %{"node_id" => "a", "port_id" => "out"}
               })
             )
  end

  test "builds a deterministic, revision-gated command batch payload" do
    commands = [
      Command.viewport_set(Viewport.new!(center_x: 50, center_y: -20, zoom: 2),
        id: "set-view",
        animate_ms: 180
      ),
      Command.operation_resolve("drag-9", :rejected, id: "resolve", reason: "locked")
    ]

    batch = CommandBatch.new!(commands, id: "batch-1", after_revision: 13)

    assert CommandBatch.to_payload(batch, "editor") == %{
             v: 1,
             editor_id: "editor",
             batch_id: "batch-1",
             after_revision: 13,
             commands: [
               %{
                 id: "set-view",
                 type: "viewport.set",
                 payload: %{center_x: 50, center_y: -20, zoom: 2, animate_ms: 180}
               },
               %{
                 id: "resolve",
                 type: "operation.resolve",
                 payload: %{operation_id: "drag-9", status: "rejected", reason: "locked"}
               }
             ]
           }
  end

  test "requires non-empty batches and known command types" do
    assert_raise ArgumentError, "a command batch requires at least one command", fn ->
      CommandBatch.new!([])
    end

    assert_raise ArgumentError, ~r/command type to be one of/, fn ->
      Command.new!("arbitrary.eval")
    end
  end

  test "fails closed on incomplete, extended, or non-commit intent envelopes" do
    valid =
      envelope("selection.change", %{"mode" => "replace", "node_ids" => [], "edge_ids" => []})

    assert {:error, ~s(missing "v" in intent envelope)} = Intent.parse(Map.delete(valid, "v"))

    assert {:error, ~s(missing "phase" in intent envelope)} =
             Intent.parse(Map.delete(valid, "phase"))

    assert {:error, ~s(missing "payload" in intent envelope)} =
             Intent.parse(Map.delete(valid, "payload"))

    assert {:error, ~s(unknown intent envelope keys: ["extra"])} =
             Intent.parse(Map.put(valid, "extra", true))

    assert {:error, ~s(intent type "selection.change" only accepts the commit phase)} =
             Intent.parse(Map.put(valid, "phase", "update"))

    assert {:error, ~s(unknown selection.change payload keys: ["extra"])} =
             Intent.parse(put_in(valid, ["payload", "extra"], true))
  end

  test "requires atomic, unambiguous node movement payloads" do
    duplicate = %{
      "positions" => [
        %{"id" => "a", "x" => 1, "y" => 2},
        %{"id" => "a", "x" => 3, "y" => 4}
      ],
      "selection" => %{"node_ids" => ["a"], "edge_ids" => []}
    }

    assert {:error, "nodes.move positions must contain unique IDs"} =
             Intent.parse(envelope("nodes.move", duplicate))

    missing_selection = %{
      "positions" => [%{"id" => "a", "x" => 1, "y" => 2}],
      "selection" => %{"node_ids" => ["b"], "edge_ids" => []}
    }

    assert {:error, "nodes.move selection must include every moved node"} =
             Intent.parse(envelope("nodes.move", missing_selection))
  end

  test "keeps revisions inside JavaScript's exact integer range" do
    payload =
      envelope(
        "selection.change",
        %{"mode" => "replace", "node_ids" => [], "edge_ids" => []},
        %{"base_revision" => 9_007_199_254_740_992}
      )

    assert {:error, message} = Intent.parse(payload)
    assert message =~ "JavaScript-safe non-negative integer"

    assert_raise ArgumentError, ~r/JavaScript-safe non-negative integer/, fn ->
      CommandBatch.new!([Command.interaction_cancel()],
        after_revision: 9_007_199_254_740_992
      )
    end
  end

  test "validates command-specific payloads and options before push_event" do
    assert_raise ArgumentError, ~r/viewport zoom to be greater than zero/, fn ->
      Command.viewport_set(%{center_x: 0, center_y: 0, zoom: 0})
    end

    assert_raise ArgumentError, "expected command animate_ms to be at most 60000", fn ->
      Command.viewport_fit(animate_ms: 60_001)
    end

    assert_raise ArgumentError, ~r/operation resolution reason/, fn ->
      Command.operation_resolve("operation", :rejected, reason: {:not, :json})
    end

    assert_raise ArgumentError, ~r/unknown viewport_fit options/, fn ->
      Command.viewport_fit(paddding: 20)
    end

    assert_raise ArgumentError, ~r/unknown viewport.set payload keys/, fn ->
      Command.new!("viewport.set", %{
        center_x: 0,
        center_y: 0,
        zoom: 1,
        animate_ms: 0,
        callback: self()
      })
    end
  end
end
