// Level meters are written to the DOM directly rather than rendered into the
// scene: they arrive ten times a second and are never authoritative, so a
// server round-trip and a DOM diff per node per tick would be pure waste.

import {test} from "node:test"
import assert from "node:assert/strict"

const {meterWidth, formatDb, applyLevels} = await import("../../priv/static/js/meters.js")

test("the meter maps -60..0 dB across its travel", () => {
  assert.equal(meterWidth(1.0), 100)
  assert.equal(Math.round(meterWidth(0.5)), 90)
  assert.equal(meterWidth(0), 0)
  assert.equal(meterWidth(undefined), 0)
})

test("the meter never leaves its bar", () => {
  assert.equal(meterWidth(4.0), 100, "a hot signal must clamp, not overflow")
  assert.equal(meterWidth(0.0000001), 0)
})

test("silence reads as a dash rather than a misleading number", () => {
  assert.equal(formatDb(-60), "—")
  assert.equal(formatDb(-9.1), "-9.1 dB")
  assert.equal(formatDb(undefined), "—")
})

test("levels are written onto the matching nodes", () => {
  const fill = {style: {}}
  const readout = {textContent: ""}

  const root = {
    querySelector: (selector) => {
      if (selector.includes(".daw-node__meter-fill")) return selector.includes("trim") ? fill : null
      if (selector.includes(".daw-node__db")) return selector.includes("trim") ? readout : null
      return null
    },
  }

  globalThis.CSS = {escape: (value) => value}

  const applied = applyLevels(root, {trim: {peak: 1.0, rms_db: -9.1}, absent: {peak: 0.5}})

  assert.equal(applied, 1)
  assert.equal(fill.style.width, "100%")
  assert.equal(readout.textContent, "-9.1 dB")
})

test("a level for a node that is no longer rendered is ignored", () => {
  globalThis.CSS = {escape: (value) => value}
  const root = {querySelector: () => null}

  assert.equal(applyLevels(root, {gone: {peak: 1.0}}), 0)
  assert.equal(applyLevels(root, null), 0)
})
