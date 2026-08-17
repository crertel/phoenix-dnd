import test from "node:test"
import assert from "node:assert/strict"

import {
  graphSelection,
  graphSelectionsEqual,
  nodesMovePayload,
  selectionModeFromModifiers,
  selectionPayload,
  selectionsEqual,
  updateGraphSelection,
  updateSelection,
} from "../../priv/static/phoenix_dnd.js"

test("selection modifier mapping is cross-platform", () => {
  assert.equal(selectionModeFromModifiers({}), "replace")
  assert.equal(selectionModeFromModifiers({shiftKey: true}), "add")
  assert.equal(selectionModeFromModifiers({ctrlKey: true}), "toggle")
  assert.equal(selectionModeFromModifiers({metaKey: true, shiftKey: true}), "toggle")
})

test("replace selection discards the previous set", () => {
  assert.deepEqual([...updateSelection(new Set(["a", "b"]), ["c"], "replace")], ["c"])
})

test("add and remove selection do not mutate the input", () => {
  const original = new Set(["a", "b"])
  assert.deepEqual([...updateSelection(original, ["c"], "add")], ["a", "b", "c"])
  assert.deepEqual([...updateSelection(original, ["a"], "remove")], ["b"])
  assert.deepEqual([...original], ["a", "b"])
})

test("toggle applies XOR semantics to every hit", () => {
  assert.deepEqual(
    [...updateSelection(new Set(["a", "b"]), ["b", "c"], "toggle")],
    ["a", "c"],
  )
})

test("selection equality ignores insertion order", () => {
  assert.equal(selectionsEqual(new Set(["a", "b"]), new Set(["b", "a"])), true)
  assert.equal(selectionsEqual(new Set(["a"]), new Set(["b"])), false)
})

test("graph selection updates node and edge sets atomically", () => {
  const original = graphSelection(["node-a"], ["edge-a"])
  const added = updateGraphSelection(original, {nodeIds: ["node-b"]}, "add")

  assert.equal(graphSelectionsEqual(original, graphSelection(["node-a"], ["edge-a"])), true)
  assert.deepEqual(selectionPayload(added), {
    node_ids: ["node-a", "node-b"],
    edge_ids: ["edge-a"],
  })

  assert.deepEqual(
    selectionPayload(updateGraphSelection(added, {edgeIds: ["edge-a"]}, "toggle")),
    {node_ids: ["node-a", "node-b"], edge_ids: []},
  )
  assert.deepEqual(
    selectionPayload(updateGraphSelection(added, {edgeIds: ["edge-b"]}, "replace")),
    {node_ids: [], edge_ids: ["edge-b"]},
  )
})

test("node movement carries the complete selection in one payload", () => {
  const positions = [{id: "node-b", x: 10, y: 20}]

  assert.deepEqual(
    nodesMovePayload(positions, graphSelection(["node-a", "node-b"], ["edge-a"])),
    {
      positions,
      selection: {
        node_ids: ["node-a", "node-b"],
        edge_ids: ["edge-a"],
      },
    },
  )
})
