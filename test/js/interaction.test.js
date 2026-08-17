import test from "node:test"
import assert from "node:assert/strict"

import {eventTargetBelongsToEditor} from "../../priv/static/phoenix_dnd.js"

test("an outer editor ignores initiating events from a nested editor", () => {
  const outer = {id: "outer"}
  const inner = {id: "inner"}
  const outerTarget = {closest: () => outer}
  const innerTarget = {closest: () => inner}

  assert.equal(eventTargetBelongsToEditor(outer, outerTarget), true)
  assert.equal(eventTargetBelongsToEditor(outer, innerTarget), false)
  assert.equal(eventTargetBelongsToEditor(outer, null), false)
})
