import test from "node:test"
import assert from "node:assert/strict"

import {
  commandsFromBatches,
  hooks,
  isCommandBatchReady,
  isViewportCommand,
  replyRejectsIntent,
  takeReadyCommandBatches,
} from "../../priv/static/phoenix_dnd.js"

const batch = (id, revision, commands = []) => ({batch_id: id, after_revision: revision, commands})

test("the public hook registry uses the LiveView hook name", () => {
  assert.equal(typeof hooks["PhoenixDnd.Graph"].mounted, "function")
})

test("reply errors reject optimism while receipts await authoritative resolution", () => {
  assert.equal(replyRejectsIntent({status: "error", code: "invalid_intent"}), true)
  assert.equal(replyRejectsIntent({status: "received"}), false)
  assert.equal(replyRejectsIntent(null), false)
})

test("viewport command classification covers every imperative viewport command", () => {
  assert.equal(isViewportCommand("viewport.set"), true)
  assert.equal(isViewportCommand("viewport.fit"), true)
  assert.equal(isViewportCommand("viewport.center_node"), true)
  assert.equal(isViewportCommand("operation.resolve"), false)
})

test("command readiness compares the batch gate with the DOM revision", () => {
  assert.equal(isCommandBatchReady(batch("a", 4), 3), false)
  assert.equal(isCommandBatchReady(batch("a", 4), 4), true)
  assert.equal(isCommandBatchReady(batch("a", 4), 8), true)
})

test("revision gating takes only the ready ordered prefix", () => {
  const queue = [batch("a", 2), batch("b", 5), batch("c", 3)]
  const result = takeReadyCommandBatches(queue, 3)

  assert.deepEqual(result.ready.map((item) => item.batch_id), ["a"])
  assert.deepEqual(result.pending.map((item) => item.batch_id), ["b", "c"])
})

test("ready batches flatten commands without disturbing order", () => {
  const commands = commandsFromBatches([
    batch("a", 1, [{id: "one"}, {id: "two"}]),
    batch("b", 1, [{id: "three"}]),
  ])

  assert.deepEqual(commands.map((command) => command.id), ["one", "two", "three"])
})
