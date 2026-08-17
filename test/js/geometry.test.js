import test from "node:test"
import assert from "node:assert/strict"

import {
  boundsOfRects,
  connectionPath,
  fitBounds,
  localToScene,
  normalizeWheelDelta,
  panViewport,
  rectFromPoints,
  rectsIntersect,
  sceneToLocal,
  shouldAdoptAuthoritativeViewport,
  viewportMatrix,
  viewportsEqual,
  zoomViewportAt,
} from "../../priv/static/phoenix_dnd.js"

const approximately = (actual, expected, epsilon = 1e-9) => {
  assert.ok(Math.abs(actual - expected) <= epsilon, `${actual} is not within ${epsilon} of ${expected}`)
}

test("scene/local coordinates round-trip through a center/zoom viewport", () => {
  const viewport = {centerX: 200, centerY: -40, zoom: 2.5}
  const size = {width: 1000, height: 600}
  const scene = {x: 312.5, y: 75.25}
  const local = sceneToLocal(scene, viewport, size)
  const result = localToScene(local, viewport, size)

  approximately(result.x, scene.x)
  approximately(result.y, scene.y)
})

test("viewport matrix has center/zoom translation semantics", () => {
  assert.deepEqual(
    viewportMatrix({centerX: 100, centerY: 50, zoom: 2}, {width: 800, height: 600}),
    {a: 2, b: 0, c: 0, d: 2, e: 200, f: 200},
  )
})

test("authoritative viewport reconciliation distinguishes unrelated patches from changes", () => {
  const canonical = {centerX: 10, centerY: 20, zoom: 1}
  const changed = {centerX: 50, centerY: 20, zoom: 2}

  assert.equal(viewportsEqual(canonical, {...canonical}), true)
  assert.equal(shouldAdoptAuthoritativeViewport(canonical, canonical, false), false)
  assert.equal(shouldAdoptAuthoritativeViewport(canonical, changed, false), true)
  assert.equal(shouldAdoptAuthoritativeViewport(canonical, changed, true), false)
})

test("pointer panning moves content with the pointer", () => {
  assert.deepEqual(
    panViewport({centerX: 10, centerY: 20, zoom: 2}, {x: 40, y: -10}),
    {centerX: -10, centerY: 25, zoom: 2},
  )
})

test("zoom preserves the scene point beneath the cursor", () => {
  const viewport = {centerX: 10, centerY: 20, zoom: 1}
  const size = {width: 800, height: 600}
  const cursor = {x: 700, y: 100}
  const before = localToScene(cursor, viewport, size)
  const next = zoomViewportAt(viewport, 3, cursor, size, {minZoom: 0.25, maxZoom: 4})
  const after = localToScene(cursor, next, size)

  approximately(after.x, before.x)
  approximately(after.y, before.y)
})

test("fitBounds respects padding and zoom bounds", () => {
  assert.deepEqual(
    fitBounds(
      {x: 100, y: 200, width: 400, height: 200},
      {width: 1000, height: 600},
      {padding: 100, minZoom: 0.1, maxZoom: 4},
    ),
    {centerX: 300, centerY: 300, zoom: 2},
  )

  assert.equal(
    fitBounds(
      {x: 0, y: 0, width: 1, height: 1},
      {width: 1000, height: 600},
      {maxZoom: 1.5},
    ).zoom,
    1.5,
  )
})

test("wheel normalization handles line, page, and shifted scrolling", () => {
  assert.deepEqual(normalizeWheelDelta({deltaX: 1, deltaY: 2, deltaMode: 1}), {x: 16, y: 32})
  assert.deepEqual(normalizeWheelDelta({deltaX: 0, deltaY: 1, deltaMode: 2}, 720), {x: 0, y: 720})
  assert.deepEqual(normalizeWheelDelta({deltaX: 0, deltaY: 12, deltaMode: 0, shiftKey: true}), {x: 12, y: 0})
})

test("rectangle helpers normalize points and include touching bounds", () => {
  const first = rectFromPoints({x: 20, y: 30}, {x: 5, y: 10})
  assert.deepEqual(first, {x: 5, y: 10, width: 15, height: 20})
  assert.equal(rectsIntersect(first, {x: 20, y: 30, width: 5, height: 5}), true)
  assert.equal(rectsIntersect(first, {x: 20.1, y: 30.1, width: 5, height: 5}), false)
})

test("boundsOfRects ignores null entries and spans all rectangles", () => {
  assert.deepEqual(
    boundsOfRects([
      {x: 10, y: 20, width: 30, height: 40},
      null,
      {x: -5, y: 50, width: 10, height: 5},
    ]),
    {x: -5, y: 20, width: 45, height: 40},
  )
  assert.equal(boundsOfRects([]), null)
})

test("connectionPath uses port-facing cubic tangents", () => {
  assert.equal(
    connectionPath({x: 0, y: 0}, {x: 100, y: 0}, "right", "left"),
    "M 0 0 C 50 0 50 0 100 0",
  )
})
