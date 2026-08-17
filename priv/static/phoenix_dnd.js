const VERSION = 1

const SELECTOR = Object.freeze({
  surface: "[data-dnd-surface]",
  world: "[data-dnd-world]",
  node: "[data-dnd-node]",
  port: "[data-dnd-port]",
  edge: "[data-dnd-edge]",
  edgeHit: "[data-dnd-edge-hit]",
  overlay: "[data-dnd-overlay]",
  wirePreview: "[data-dnd-wire-preview]",
  selectionRect: "[data-dnd-selection-rect]",
  dragHandle: "[data-dnd-drag-handle]",
})

const INTERACTIVE_SELECTOR = [
  "input",
  "button",
  "select",
  "textarea",
  "a[href]",
  "[contenteditable]:not([contenteditable='false'])",
  "[data-dnd-no-drag]",
].join(",")

const LINE_HEIGHT = 16
const DRAG_THRESHOLD = 4
const WHEEL_COMMIT_DELAY = 140

function finiteNumber(value, fallback = 0) {
  const number = typeof value === "number" ? value : Number(value)
  return Number.isFinite(number) ? number : fallback
}

function nonNegativeInteger(value, fallback = 0) {
  const number = Number(value)
  return Number.isSafeInteger(number) && number >= 0 ? number : fallback
}

function point(x = 0, y = 0) {
  return {x: finiteNumber(x), y: finiteNumber(y)}
}

function copyViewport(viewport) {
  return {
    centerX: finiteNumber(viewport.centerX),
    centerY: finiteNumber(viewport.centerY),
    zoom: finiteNumber(viewport.zoom, 1),
  }
}

function copySize(size) {
  return {
    width: Math.max(0, finiteNumber(size.width)),
    height: Math.max(0, finiteNumber(size.height)),
  }
}

function rounded(value) {
  const result = Math.round(finiteNumber(value) * 1000) / 1000
  return Object.is(result, -0) ? 0 : result
}

function px(value) {
  return `${rounded(value)}px`
}

export function clamp(value, minimum, maximum) {
  const min = finiteNumber(minimum)
  const max = finiteNumber(maximum, min)
  return Math.min(Math.max(finiteNumber(value, min), min), Math.max(min, max))
}

/** Convert a scene-space point to coordinates local to the editor surface. */
export function sceneToLocal(scenePoint, viewport, size) {
  const safeSize = copySize(size)
  const safeViewport = copyViewport(viewport)

  return {
    x: (finiteNumber(scenePoint.x) - safeViewport.centerX) * safeViewport.zoom + safeSize.width / 2,
    y: (finiteNumber(scenePoint.y) - safeViewport.centerY) * safeViewport.zoom + safeSize.height / 2,
  }
}

/** Convert a point local to the editor surface to scene coordinates. */
export function localToScene(localPoint, viewport, size) {
  const safeSize = copySize(size)
  const safeViewport = copyViewport(viewport)
  const zoom = safeViewport.zoom > 0 ? safeViewport.zoom : 1

  return {
    x: (finiteNumber(localPoint.x) - safeSize.width / 2) / zoom + safeViewport.centerX,
    y: (finiteNumber(localPoint.y) - safeSize.height / 2) / zoom + safeViewport.centerY,
  }
}

/**
 * Move the rendered scene by a local-pixel delta. This is the natural
 * operation for pointer panning: a positive x delta moves content right.
 */
export function panViewport(viewport, delta) {
  const safeViewport = copyViewport(viewport)
  const zoom = safeViewport.zoom > 0 ? safeViewport.zoom : 1

  return {
    centerX: safeViewport.centerX - finiteNumber(delta.x) / zoom,
    centerY: safeViewport.centerY - finiteNumber(delta.y) / zoom,
    zoom,
  }
}

/** Zoom while preserving the scene point beneath a local surface point. */
export function zoomViewportAt(viewport, nextZoom, localPoint, size, limits = {}) {
  const minimum = Math.max(0.000001, finiteNumber(limits.minZoom, 0.1))
  const maximum = Math.max(minimum, finiteNumber(limits.maxZoom, 4))
  const zoom = clamp(nextZoom, minimum, maximum)
  const anchor = localToScene(localPoint, viewport, size)
  const safeSize = copySize(size)

  return {
    centerX: anchor.x - (finiteNumber(localPoint.x) - safeSize.width / 2) / zoom,
    centerY: anchor.y - (finiteNumber(localPoint.y) - safeSize.height / 2) / zoom,
    zoom,
  }
}

/** Return the unambiguous CSS matrix for a center/zoom viewport. */
export function viewportMatrix(viewport, size) {
  const safeViewport = copyViewport(viewport)
  const safeSize = copySize(size)

  return {
    a: safeViewport.zoom,
    b: 0,
    c: 0,
    d: safeViewport.zoom,
    e: safeSize.width / 2 - safeViewport.centerX * safeViewport.zoom,
    f: safeSize.height / 2 - safeViewport.centerY * safeViewport.zoom,
  }
}

export function viewportsEqual(first, second, epsilon = 0.000001) {
  return (
    Math.abs(first.centerX - second.centerX) < epsilon &&
    Math.abs(first.centerY - second.centerY) < epsilon &&
    Math.abs(first.zoom - second.zoom) < epsilon
  )
}

/**
 * Canonical viewport changes supersede local/command projections. The sole
 * exception is a viewport intent awaiting revision-gated resolution.
 */
export function shouldAdoptAuthoritativeViewport(previous, next, hasPendingViewportIntent = false) {
  return !viewportsEqual(previous, next) && !hasPendingViewportIntent
}

/** Fit a scene-space rectangle in the supplied surface size. */
export function fitBounds(bounds, size, options = {}) {
  if (!bounds) return null

  const safeSize = copySize(size)
  const padding = Math.max(0, finiteNumber(options.padding, 0))
  const minZoom = Math.max(0.000001, finiteNumber(options.minZoom, 0.1))
  const maxZoom = Math.max(minZoom, finiteNumber(options.maxZoom, 4))
  const width = Math.max(0, finiteNumber(bounds.width))
  const height = Math.max(0, finiteNumber(bounds.height))
  const availableWidth = Math.max(1, safeSize.width - padding * 2)
  const availableHeight = Math.max(1, safeSize.height - padding * 2)
  const xZoom = width > 0 ? availableWidth / width : Number.POSITIVE_INFINITY
  const yZoom = height > 0 ? availableHeight / height : Number.POSITIVE_INFINITY
  const unconstrained = Math.min(xZoom, yZoom)
  const zoom = clamp(Number.isFinite(unconstrained) ? unconstrained : maxZoom, minZoom, maxZoom)

  return {
    centerX: finiteNumber(bounds.x) + width / 2,
    centerY: finiteNumber(bounds.y) + height / 2,
    zoom,
  }
}

/** Normalize wheel deltas to CSS pixels. */
export function normalizeWheelDelta(event, pageHeight = 800) {
  let multiplier = 1

  if (event.deltaMode === 1) multiplier = LINE_HEIGHT
  if (event.deltaMode === 2) multiplier = Math.max(1, finiteNumber(pageHeight, 800))

  let x = finiteNumber(event.deltaX) * multiplier
  let y = finiteNumber(event.deltaY) * multiplier

  if (event.shiftKey && Math.abs(x) < Math.abs(y)) {
    x = y
    y = 0
  }

  return {x, y}
}

export function rectFromPoints(first, second) {
  const x1 = finiteNumber(first.x)
  const y1 = finiteNumber(first.y)
  const x2 = finiteNumber(second.x)
  const y2 = finiteNumber(second.y)

  return {
    x: Math.min(x1, x2),
    y: Math.min(y1, y2),
    width: Math.abs(x2 - x1),
    height: Math.abs(y2 - y1),
  }
}

export function rectsIntersect(first, second) {
  if (!first || !second) return false

  return (
    first.x <= second.x + second.width &&
    first.x + first.width >= second.x &&
    first.y <= second.y + second.height &&
    first.y + first.height >= second.y
  )
}

export function boundsOfRects(rectangles) {
  const usable = rectangles.filter(Boolean)
  if (usable.length === 0) return null

  let left = Number.POSITIVE_INFINITY
  let top = Number.POSITIVE_INFINITY
  let right = Number.NEGATIVE_INFINITY
  let bottom = Number.NEGATIVE_INFINITY

  for (const rectangle of usable) {
    left = Math.min(left, finiteNumber(rectangle.x))
    top = Math.min(top, finiteNumber(rectangle.y))
    right = Math.max(right, finiteNumber(rectangle.x) + Math.max(0, finiteNumber(rectangle.width)))
    bottom = Math.max(bottom, finiteNumber(rectangle.y) + Math.max(0, finiteNumber(rectangle.height)))
  }

  return {x: left, y: top, width: right - left, height: bottom - top}
}

export function selectionModeFromModifiers(modifiers = {}) {
  if (modifiers.ctrlKey || modifiers.metaKey) return "toggle"
  if (modifiers.shiftKey) return "add"
  return "replace"
}

/** Apply replace/add/remove/toggle selection algebra without mutating input. */
export function updateSelection(selection, ids, mode = "replace") {
  const next = mode === "replace" ? new Set() : new Set(selection)

  for (const id of ids) {
    if (mode === "remove") {
      next.delete(id)
    } else if (mode === "toggle") {
      if (next.has(id)) next.delete(id)
      else next.add(id)
    } else {
      next.add(id)
    }
  }

  return next
}

export function selectionsEqual(first, second) {
  if (first.size !== second.size) return false
  for (const id of first) if (!second.has(id)) return false
  return true
}

export function graphSelection(nodeIds = [], edgeIds = []) {
  return {nodeIds: new Set(nodeIds), edgeIds: new Set(edgeIds)}
}

export function copyGraphSelection(selection) {
  return graphSelection(selection?.nodeIds || [], selection?.edgeIds || [])
}

/** Apply the same selection mode atomically across node and edge identities. */
export function updateGraphSelection(selection, targets, mode = "replace") {
  const current = copyGraphSelection(selection)
  const next = mode === "replace" ? graphSelection() : current
  const setMode = mode === "replace" ? "add" : mode

  next.nodeIds = updateSelection(next.nodeIds, targets?.nodeIds || [], setMode)
  next.edgeIds = updateSelection(next.edgeIds, targets?.edgeIds || [], setMode)
  return next
}

export function graphSelectionsEqual(first, second) {
  return selectionsEqual(first.nodeIds, second.nodeIds) && selectionsEqual(first.edgeIds, second.edgeIds)
}

export function selectionPayload(selection) {
  return {
    node_ids: [...selection.nodeIds],
    edge_ids: [...selection.edgeIds],
  }
}

export function nodesMovePayload(positions, selection) {
  return {positions, selection: selectionPayload(selection)}
}

function anchorVector(anchor) {
  switch (anchor) {
    case "left": return {x: -1, y: 0}
    case "top": return {x: 0, y: -1}
    case "bottom": return {x: 0, y: 1}
    default: return {x: 1, y: 0}
  }
}

/** Build a cubic path between two points with outward-facing port tangents. */
export function connectionPath(source, target, sourceAnchor = "right", targetAnchor = "left") {
  const start = point(source.x, source.y)
  const finish = point(target.x, target.y)
  const distance = Math.hypot(finish.x - start.x, finish.y - start.y)
  const handle = clamp(distance * 0.5, 36, 240)
  const sourceVector = anchorVector(sourceAnchor)
  const targetVector = anchorVector(targetAnchor)
  const control1 = {
    x: start.x + sourceVector.x * handle,
    y: start.y + sourceVector.y * handle,
  }
  const control2 = {
    x: finish.x + targetVector.x * handle,
    y: finish.y + targetVector.y * handle,
  }

  return [
    "M", rounded(start.x), rounded(start.y),
    "C", rounded(control1.x), rounded(control1.y),
    rounded(control2.x), rounded(control2.y),
    rounded(finish.x), rounded(finish.y),
  ].join(" ")
}

export function isCommandBatchReady(batch, revision) {
  return nonNegativeInteger(batch?.after_revision, Number.MAX_SAFE_INTEGER) <= nonNegativeInteger(revision)
}

/**
 * Take the ready prefix of an ordered command queue. A future-revision batch
 * blocks later batches, preserving server delivery order.
 */
export function takeReadyCommandBatches(batches, revision) {
  let count = 0
  while (count < batches.length && isCommandBatchReady(batches[count], revision)) count += 1

  return {
    ready: batches.slice(0, count),
    pending: batches.slice(count),
  }
}

export function commandsFromBatches(batches) {
  return batches.flatMap((batch) => Array.isArray(batch.commands) ? batch.commands : [])
}

export function isViewportCommand(type) {
  return ["viewport.set", "viewport.fit", "viewport.center_node"].includes(type)
}

export function replyRejectsIntent(reply) {
  return Boolean(reply && reply.status === "error")
}

function interpolateViewport(from, to, progress) {
  const amount = clamp(progress, 0, 1)
  return {
    centerX: from.centerX + (to.centerX - from.centerX) * amount,
    centerY: from.centerY + (to.centerY - from.centerY) * amount,
    zoom: from.zoom + (to.zoom - from.zoom) * amount,
  }
}

function easeOutCubic(progress) {
  return 1 - Math.pow(1 - clamp(progress, 0, 1), 3)
}

function uniqueId(prefix) {
  const cryptoObject = globalThis.crypto
  if (cryptoObject && typeof cryptoObject.randomUUID === "function") {
    return `${prefix}-${cryptoObject.randomUUID()}`
  }

  return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`
}

function portKey(nodeId, portId) {
  return `${nodeId.length}:${nodeId}${portId}`
}

function closestInEditor(root, target, selector) {
  if (!target || typeof target.closest !== "function") return null
  const match = target.closest(selector)
  if (!match || !root.contains(match)) return null
  const editor = match.closest(".phoenix-dnd[data-editor-id]")
  return editor === root ? match : null
}

export function eventTargetBelongsToEditor(editor, target) {
  return Boolean(
    target &&
    typeof target.closest === "function" &&
    target.closest(".phoenix-dnd[data-editor-id]") === editor
  )
}

function belongsToEditor(root, element) {
  return element.closest(".phoenix-dnd[data-editor-id]") === root
}

function isAuthoritativelySelected(element) {
  return element.getAttribute("aria-selected") === "true" || element.getAttribute("data-selected") === "true"
}

function pointerDistance(interaction, local) {
  return Math.hypot(local.x - interaction.startLocal.x, local.y - interaction.startLocal.y)
}

function normalizedAnchor(anchor, fallback) {
  return ["left", "right", "top", "bottom"].includes(anchor) ? anchor : fallback
}

function oppositeAnchor(anchor) {
  switch (anchor) {
    case "left": return "right"
    case "right": return "left"
    case "top": return "bottom"
    case "bottom": return "top"
    default: return "left"
  }
}

function normalizeDirection(direction) {
  if (direction === "input" || direction === "output") return direction
  return "bidirectional"
}

class GraphRuntime {
  constructor(hook) {
    this.hook = hook
    this.el = hook.el
    this.win = this.el.ownerDocument.defaultView || globalThis.window
    this.doc = this.el.ownerDocument
    this.editorId = this.el.dataset.editorId
    this.clientId = uniqueId("client")
    this.intentSequence = 0
    this.revision = 0
    this.minZoom = 0.1
    this.maxZoom = 4
    this.viewport = {centerX: 0, centerY: 0, zoom: 1}
    this.authoritativeViewport = copyViewport(this.viewport)
    this.viewportProjection = null
    this.appliedViewport = copyViewport(this.viewport)
    this.surfaceSize = {width: 1, height: 1}
    this.appliedSurfaceSize = copySize(this.surfaceSize)
    this.surfaceRect = null
    this.nodes = new Map()
    this.ports = new Map()
    this.edges = []
    this.edgesById = new Map()
    this.appliedNodePositions = new Map()
    this.authoritativeSelection = graphSelection()
    this.displaySelection = graphSelection()
    this.nodeOverrides = new Map()
    this.pendingOperations = new Map()
    this.earlyRejectedIntents = new Set()
    this.commandBatches = []
    this.seenBatchIds = new Set()
    this.interaction = null
    this.viewportAnimation = null
    this.localViewportBase = null
    this.spacePressed = false
    this.highlightedPort = null
    this.frameId = null
    this.inFrame = false
    this.destroyed = false
    this.wheelCommitTimer = null
    this.dirty = {
      measure: false,
      viewport: false,
      nodes: false,
      selection: false,
      edges: false,
      overlay: false,
    }
  }

  mount() {
    this.readRootConfiguration(true)
    this.refreshDom()
    this.installListeners()
    this.installObservers()
    this.restoreProjection()
    this.mark("measure", "edges", "overlay")
    this.commandEventRef = this.hook.handleEvent("phoenix_dnd:commands", (batch) => this.receiveCommands(batch))
  }

  beforeUpdate() {
    // Interaction state intentionally lives outside the DOM. LiveView's
    // beforeUpdate callback must remain synchronous and mutation-free.
  }

  updated() {
    const previousRevision = this.revision
    this.readRootConfiguration(false)

    if (this.revision < previousRevision) this.resetOptimisticState()

    this.refreshDom()
    this.reconcileInteraction()
    this.rebindObservers()
    this.restoreProjection()
    this.mark("measure", "edges", "overlay")
  }

  disconnected() {
    this.cancelInteraction({restore: true})
    this.viewportAnimation = null
  }

  reconnected() {
    this.resetOptimisticState()
    this.readRootConfiguration(true)
    this.refreshDom()
    this.rebindObservers()
    this.restoreProjection()
    this.mark("measure", "edges", "overlay")
  }

  destroy() {
    this.destroyed = true
    this.cancelInteraction({restore: false})
    this.removeListeners()
    if (this.resizeObserver) this.resizeObserver.disconnect()
    if (this.commandEventRef) this.hook.removeHandleEvent(this.commandEventRef)
    if (this.frameId !== null) this.win.cancelAnimationFrame(this.frameId)
    if (this.wheelCommitTimer !== null) this.win.clearTimeout(this.wheelCommitTimer)
    this.frameId = null
  }

  readRootConfiguration(includeViewport) {
    this.editorId = this.el.dataset.editorId || this.editorId
    this.revision = nonNegativeInteger(this.el.dataset.sceneRevision, this.revision)
    this.minZoom = Math.max(0.000001, finiteNumber(this.el.dataset.minZoom, this.minZoom))
    this.maxZoom = Math.max(this.minZoom, finiteNumber(this.el.dataset.maxZoom, this.maxZoom))

    const canonicalViewport = {
      centerX: finiteNumber(this.el.dataset.centerX, this.authoritativeViewport.centerX),
      centerY: finiteNumber(this.el.dataset.centerY, this.authoritativeViewport.centerY),
      zoom: clamp(
        finiteNumber(this.el.dataset.zoom, this.authoritativeViewport.zoom),
        this.minZoom,
        this.maxZoom,
      ),
    }

    if (includeViewport) {
      this.authoritativeViewport = canonicalViewport
      this.viewport = copyViewport(canonicalViewport)
      this.viewportProjection = null
    } else {
      const adoptCanonical = shouldAdoptAuthoritativeViewport(
        this.authoritativeViewport,
        canonicalViewport,
        this.preserveViewportAcrossCanonicalUpdate(),
      )
      this.authoritativeViewport = canonicalViewport

      if (adoptCanonical) {
        if (this.interaction?.kind === "pan") this.cancelInteraction({restore: false})
        if (this.wheelCommitTimer !== null) {
          this.win.clearTimeout(this.wheelCommitTimer)
          this.wheelCommitTimer = null
        }
        this.viewportAnimation = null
        this.viewportProjection = null
        this.localViewportBase = null
        this.viewport = copyViewport(canonicalViewport)
      }

      this.viewport.zoom = clamp(this.viewport.zoom, this.minZoom, this.maxZoom)
    }
  }

  preserveViewportAcrossCanonicalUpdate() {
    return (
      this.viewportProjection?.kind === "pending" &&
      this.pendingOperations.has(this.viewportProjection.operationId)
    )
  }

  refreshDom() {
    this.surface = this.el.querySelector(SELECTOR.surface)
    this.world = this.el.querySelector(SELECTOR.world)
    this.overlay = this.el.querySelector(SELECTOR.overlay)
    this.wirePreview = this.el.querySelector(SELECTOR.wirePreview)
    this.selectionRect = this.el.querySelector(SELECTOR.selectionRect)

    if (!this.surface || !this.world) {
      throw new Error("PhoenixDnd.Graph requires data-dnd-surface and data-dnd-world descendants")
    }

    this.ignoreAttributes(this.el, ["data-dnd-interaction"])
    this.ignoreAttributes(this.world, ["style"])

    const previousNodes = this.nodes
    const previousPorts = this.ports
    const authoritativeSelection = graphSelection()
    const nodes = new Map()

    for (const element of this.el.querySelectorAll(SELECTOR.node)) {
      if (!belongsToEditor(this.el, element)) continue
      const id = element.dataset.nodeId
      if (!id || nodes.has(id)) continue
      const previous = previousNodes.get(id)

      nodes.set(id, {
        id,
        element,
        x: finiteNumber(element.dataset.x),
        y: finiteNumber(element.dataset.y),
        width: previous?.width || 0,
        height: previous?.height || 0,
      })

      if (isAuthoritativelySelected(element)) authoritativeSelection.nodeIds.add(id)
      this.ignoreAttributes(element, ["data-dnd-selected"])
    }

    const ports = new Map()
    for (const element of this.el.querySelectorAll(SELECTOR.port)) {
      if (!belongsToEditor(this.el, element)) continue
      const nodeId = element.dataset.nodeId
      const portId = element.dataset.portId
      if (!nodeId || !portId || !nodes.has(nodeId)) continue
      const key = portKey(nodeId, portId)
      const previous = previousPorts.get(key)
      const direction = normalizeDirection(element.dataset.direction)
      const fallbackAnchor = direction === "input" ? "left" : "right"

      ports.set(key, {
        key,
        nodeId,
        portId,
        element,
        direction,
        anchor: normalizedAnchor(element.dataset.anchor || element.dataset.portAnchor, fallbackAnchor),
        offset: previous?.offset || null,
      })

      this.ignoreAttributes(element, ["data-dnd-wire-target"])
    }

    this.distributePorts(ports)

    const edges = []
    const edgesById = new Map()
    for (const element of this.el.querySelectorAll(SELECTOR.edge)) {
      if (!belongsToEditor(this.el, element)) continue
      const sourceNode = element.dataset.sourceNode
      const sourcePort = element.dataset.sourcePort
      const targetNode = element.dataset.targetNode
      const targetPort = element.dataset.targetPort
      if (!sourceNode || !sourcePort || !targetNode || !targetPort) continue

      const id = element.dataset.edgeId || null
      const edge = {
        id,
        element,
        hitElement: element.parentElement?.querySelector(SELECTOR.edgeHit) || null,
        sourceKey: portKey(sourceNode, sourcePort),
        targetKey: portKey(targetNode, targetPort),
      }
      edges.push(edge)
      if (id && !edgesById.has(id)) {
        edgesById.set(id, edge)
        if (isAuthoritativelySelected(element)) authoritativeSelection.edgeIds.add(id)
      }
      this.ignoreAttributes(element, ["d", "data-dnd-selected"])
      this.ignoreAttributes(edge.hitElement, ["d"])
    }

    this.nodes = nodes
    this.ports = ports
    this.edges = edges
    this.edgesById = edgesById
    this.authoritativeSelection = authoritativeSelection

    for (const nodeId of this.nodeOverrides.keys()) {
      if (!nodes.has(nodeId)) this.nodeOverrides.delete(nodeId)
    }

    const pendingSelection = this.latestPendingSelection()
    if (!this.isSelectionGestureActive()) {
      this.displaySelection = pendingSelection ? copyGraphSelection(pendingSelection.selection) : copyGraphSelection(authoritativeSelection)
    }
    this.displaySelection = graphSelection(
      [...this.displaySelection.nodeIds].filter((id) => nodes.has(id)),
      [...this.displaySelection.edgeIds].filter((id) => edgesById.has(id)),
    )
  }

  distributePorts(ports) {
    const groups = new Map()

    for (const port of ports.values()) {
      const key = `${port.nodeId.length}:${port.nodeId}:${port.anchor}`
      const group = groups.get(key) || []
      group.push(port)
      groups.set(key, group)
    }

    for (const group of groups.values()) {
      group.forEach((port, index) => {
        const percentage = ((index + 1) / (group.length + 1)) * 100
        port.element.style.setProperty("--phoenix-dnd-port-offset", `${rounded(percentage)}%`)
      })
    }
  }

  ignoreAttributes(element, attributes) {
    if (!element || typeof this.hook.js !== "function") return
    try {
      const commands = this.hook.js()
      if (commands && typeof commands.ignoreAttributes === "function") {
        commands.ignoreAttributes(element, attributes)
      }
    } catch (_error) {
      // LiveView versions without hook-side ignoreAttributes still reconcile in
      // updated(); ignoring merely avoids needless attribute churn.
    }
  }

  installListeners() {
    this.onPointerDown = (event) => this.pointerDown(event)
    this.onPointerMove = (event) => this.pointerMove(event)
    this.onPointerUp = (event) => this.pointerUp(event)
    this.onPointerCancel = (event) => this.pointerCancel(event)
    this.onWheel = (event) => this.wheel(event)
    this.onKeyDown = (event) => this.keyDown(event)
    this.onKeyUp = (event) => this.keyUp(event)
    this.onWindowBlur = () => this.windowBlur()

    this.el.addEventListener("pointerdown", this.onPointerDown)
    this.el.addEventListener("pointermove", this.onPointerMove)
    this.el.addEventListener("pointerup", this.onPointerUp)
    this.el.addEventListener("pointercancel", this.onPointerCancel)
    this.surface.addEventListener("wheel", this.onWheel, {passive: false})
    this.el.addEventListener("keydown", this.onKeyDown)
    this.win.addEventListener("keyup", this.onKeyUp)
    this.win.addEventListener("blur", this.onWindowBlur)
  }

  removeListeners() {
    this.el.removeEventListener("pointerdown", this.onPointerDown)
    this.el.removeEventListener("pointermove", this.onPointerMove)
    this.el.removeEventListener("pointerup", this.onPointerUp)
    this.el.removeEventListener("pointercancel", this.onPointerCancel)
    if (this.surface) this.surface.removeEventListener("wheel", this.onWheel)
    this.el.removeEventListener("keydown", this.onKeyDown)
    this.win.removeEventListener("keyup", this.onKeyUp)
    this.win.removeEventListener("blur", this.onWindowBlur)
  }

  installObservers() {
    if (typeof this.win.ResizeObserver === "function") {
      this.resizeObserver = new this.win.ResizeObserver(() => this.mark("measure", "edges", "overlay"))
      this.rebindObservers()
    }

    const fonts = this.doc.fonts
    if (fonts?.ready && typeof fonts.ready.then === "function") {
      fonts.ready.then(() => {
        if (!this.destroyed) this.mark("measure", "edges", "overlay")
      })
    }
  }

  rebindObservers() {
    if (!this.resizeObserver) return
    this.resizeObserver.disconnect()
    this.resizeObserver.observe(this.surface)
    for (const node of this.nodes.values()) this.resizeObserver.observe(node.element)
  }

  resetOptimisticState() {
    this.cancelInteraction({restore: false})
    this.nodeOverrides.clear()
    this.pendingOperations.clear()
    this.earlyRejectedIntents.clear()
    this.commandBatches = []
    this.seenBatchIds.clear()
    this.viewportAnimation = null
    this.viewportProjection = null
    this.localViewportBase = null
    this.viewport = copyViewport(this.authoritativeViewport)
    if (this.wheelCommitTimer !== null) {
      this.win.clearTimeout(this.wheelCommitTimer)
      this.wheelCommitTimer = null
    }
  }

  restoreProjection() {
    const rectangle = this.surface.getBoundingClientRect()
    this.surfaceRect = rectangle
    this.surfaceSize = {width: Math.max(1, rectangle.width), height: Math.max(1, rectangle.height)}
    this.renderWorld()
    this.renderNodes()
    this.renderSelection()
    this.renderOverlay()
    this.renderInteractionAttribute()
  }

  mark(...flags) {
    for (const flag of flags) this.dirty[flag] = true
    if (!this.inFrame && this.frameId === null && !this.destroyed) {
      this.frameId = this.win.requestAnimationFrame((timestamp) => this.frame(timestamp))
    }
  }

  frame(timestamp) {
    this.frameId = null
    if (this.destroyed) return
    this.inFrame = true

    if (this.dirty.measure) this.measureGeometry()

    const gated = takeReadyCommandBatches(this.commandBatches, this.revision)
    this.commandBatches = gated.pending
    for (const command of commandsFromBatches(gated.ready)) this.applyCommand(command, timestamp)

    if (this.viewportAnimation) this.stepViewportAnimation(timestamp)
    if (this.dirty.viewport) this.renderWorld()
    if (this.dirty.nodes) this.renderNodes()
    if (this.dirty.selection) this.renderSelection()
    if (this.dirty.edges) this.renderEdges()
    if (this.dirty.overlay) this.renderOverlay()

    this.inFrame = false
    if (this.viewportAnimation || Object.values(this.dirty).some(Boolean)) this.mark()
  }

  measureGeometry() {
    this.dirty.measure = false
    const surfaceRectangle = this.surface.getBoundingClientRect()
    const conversionSize = copySize(this.appliedSurfaceSize)
    const conversionViewport = copyViewport(this.appliedViewport)
    const zoom = conversionViewport.zoom > 0 ? conversionViewport.zoom : 1
    this.surfaceRect = surfaceRectangle

    for (const node of this.nodes.values()) {
      const rectangle = node.element.getBoundingClientRect()
      node.width = rectangle.width / zoom
      node.height = rectangle.height / zoom
    }

    for (const port of this.ports.values()) {
      const rectangle = port.element.getBoundingClientRect()
      const local = {
        x: rectangle.left + rectangle.width / 2 - surfaceRectangle.left,
        y: rectangle.top + rectangle.height / 2 - surfaceRectangle.top,
      }
      const scene = localToScene(local, conversionViewport, conversionSize)
      const appliedNode = this.appliedNodePositions.get(port.nodeId) || this.displayNodePosition(port.nodeId)
      if (appliedNode) port.offset = {x: scene.x - appliedNode.x, y: scene.y - appliedNode.y}
    }

    this.surfaceSize = {
      width: Math.max(1, surfaceRectangle.width),
      height: Math.max(1, surfaceRectangle.height),
    }
    this.dirty.viewport = true
    this.dirty.edges = true
    this.dirty.overlay = true
  }

  renderWorld() {
    this.dirty.viewport = false
    const matrix = viewportMatrix(this.viewport, this.surfaceSize)
    this.world.style.transformOrigin = "0 0"
    this.world.style.transform = `matrix(${rounded(matrix.a)}, ${rounded(matrix.b)}, ${rounded(matrix.c)}, ${rounded(matrix.d)}, ${rounded(matrix.e)}, ${rounded(matrix.f)})`
    const gridSize = Math.max(4, 24 * this.viewport.zoom)
    this.surface.style.setProperty("--phoenix-dnd-grid-size", px(gridSize))
    this.surface.style.setProperty("--phoenix-dnd-grid-x", px(matrix.e % gridSize))
    this.surface.style.setProperty("--phoenix-dnd-grid-y", px(matrix.f % gridSize))
    this.appliedViewport = copyViewport(this.viewport)
    this.appliedSurfaceSize = copySize(this.surfaceSize)
    this.dirty.overlay = true
  }

  displayNodePosition(nodeId) {
    if (this.interaction?.kind === "node-drag" && this.interaction.positions.has(nodeId)) {
      return this.interaction.positions.get(nodeId)
    }

    const override = this.nodeOverrides.get(nodeId)
    if (override) return override.position
    const node = this.nodes.get(nodeId)
    return node ? {x: node.x, y: node.y} : null
  }

  renderNodes() {
    this.dirty.nodes = false
    this.appliedNodePositions.clear()

    for (const node of this.nodes.values()) {
      const position = this.displayNodePosition(node.id)
      if (!position) continue
      node.element.style.transform = `translate3d(${px(position.x)}, ${px(position.y)}, 0)`
      this.appliedNodePositions.set(node.id, {...position})
    }

    this.dirty.edges = true
    this.dirty.overlay = true
  }

  renderSelection() {
    this.dirty.selection = false
    for (const node of this.nodes.values()) {
      node.element.setAttribute("data-dnd-selected", this.displaySelection.nodeIds.has(node.id) ? "true" : "false")
    }
    for (const edge of this.edges) {
      if (edge.id) {
        edge.element.setAttribute("data-dnd-selected", this.displaySelection.edgeIds.has(edge.id) ? "true" : "false")
      }
    }
  }

  portPosition(port) {
    const position = this.displayNodePosition(port.nodeId)
    if (!position || !port.offset) return null
    return {x: position.x + port.offset.x, y: position.y + port.offset.y}
  }

  renderEdges() {
    this.dirty.edges = false
    for (const edge of this.edges) {
      const source = this.ports.get(edge.sourceKey)
      const target = this.ports.get(edge.targetKey)
      const sourcePosition = source ? this.portPosition(source) : null
      const targetPosition = target ? this.portPosition(target) : null

      if (!sourcePosition || !targetPosition) {
        edge.element.setAttribute("d", "")
        if (edge.hitElement) edge.hitElement.setAttribute("d", "")
        edge.element.setAttribute("data-dnd-unresolved", "true")
        continue
      }

      const path = connectionPath(sourcePosition, targetPosition, source.anchor, target.anchor)
      edge.element.setAttribute("d", path)
      if (edge.hitElement) edge.hitElement.setAttribute("d", path)
      edge.element.removeAttribute("data-dnd-unresolved")
    }
  }

  renderOverlay() {
    this.dirty.overlay = false
    const interaction = this.interaction

    if (this.wirePreview) {
      if (interaction?.kind === "wire") {
        const source = this.ports.get(interaction.sourceKey)
        const candidate = interaction.candidateKey ? this.ports.get(interaction.candidateKey) : null
        const startScene = source ? this.portPosition(source) : null
        const finishScene = candidate ? this.portPosition(candidate) : interaction.currentScene

        if (source && startScene && finishScene) {
          const start = sceneToLocal(startScene, this.viewport, this.surfaceSize)
          const finish = sceneToLocal(finishScene, this.viewport, this.surfaceSize)
          const targetAnchor = candidate ? candidate.anchor : oppositeAnchor(source.anchor)
          this.wirePreview.setAttribute("d", connectionPath(start, finish, source.anchor, targetAnchor))
          this.wirePreview.removeAttribute("hidden")
        } else {
          this.wirePreview.setAttribute("hidden", "")
        }
      } else {
        this.wirePreview.setAttribute("hidden", "")
      }
    }

    if (this.selectionRect) {
      if (interaction?.kind === "box") {
        const start = sceneToLocal(interaction.startScene, this.viewport, this.surfaceSize)
        const finish = sceneToLocal(interaction.currentScene, this.viewport, this.surfaceSize)
        const rectangle = rectFromPoints(start, finish)
        this.selectionRect.setAttribute("x", rounded(rectangle.x))
        this.selectionRect.setAttribute("y", rounded(rectangle.y))
        this.selectionRect.setAttribute("width", rounded(rectangle.width))
        this.selectionRect.setAttribute("height", rounded(rectangle.height))
        this.selectionRect.removeAttribute("hidden")
      } else {
        this.selectionRect.setAttribute("hidden", "")
      }
    }

    this.renderWireCandidate(interaction?.kind === "wire" ? interaction.candidateKey : null)
    this.renderInteractionAttribute()
  }

  renderWireCandidate(candidateKey) {
    const next = candidateKey ? this.ports.get(candidateKey)?.element : null
    if (this.highlightedPort && this.highlightedPort !== next) {
      this.highlightedPort.removeAttribute("data-dnd-wire-target")
    }
    if (next) next.setAttribute("data-dnd-wire-target", "true")
    this.highlightedPort = next || null
  }

  renderInteractionAttribute() {
    const kind = this.interaction?.kind
    if (kind) this.el.setAttribute("data-dnd-interaction", kind)
    else this.el.removeAttribute("data-dnd-interaction")
  }

  receiveCommands(batch) {
    if (!batch || batch.v !== VERSION || batch.editor_id !== this.editorId) return
    if (!Array.isArray(batch.commands) || typeof batch.batch_id !== "string") return
    if (this.seenBatchIds.has(batch.batch_id)) return

    this.seenBatchIds.add(batch.batch_id)
    if (this.seenBatchIds.size > 256) {
      const oldest = this.seenBatchIds.values().next().value
      this.seenBatchIds.delete(oldest)
    }

    this.commandBatches.push({
      ...batch,
      after_revision: nonNegativeInteger(batch.after_revision),
    })
    this.mark()
  }

  applyCommand(command, timestamp) {
    if (!command || typeof command.type !== "string") return
    const payload = command.payload && typeof command.payload === "object" ? command.payload : {}
    if (isViewportCommand(command.type)) this.supersedeUncommittedViewportInput()

    switch (command.type) {
      case "interaction.cancel":
        this.cancelInteraction({restore: true})
        this.supersedeUncommittedViewportInput()
        break

      case "operation.resolve":
        this.resolveOperation(payload.operation_id, payload.status)
        break

      case "viewport.set": {
        const target = {
          centerX: finiteNumber(payload.center_x, this.viewport.centerX),
          centerY: finiteNumber(payload.center_y, this.viewport.centerY),
          zoom: clamp(finiteNumber(payload.zoom, this.viewport.zoom), this.minZoom, this.maxZoom),
        }
        this.setViewportFromCommand(target, payload.animate_ms, timestamp)
        break
      }

      case "viewport.fit": {
        const ids = Array.isArray(payload.node_ids) && payload.node_ids.length > 0 ? payload.node_ids : [...this.nodes.keys()]
        const bounds = this.boundsForNodes(ids)
        const target = fitBounds(bounds, this.surfaceSize, {
          padding: payload.padding,
          minZoom: this.minZoom,
          maxZoom: payload.max_zoom == null ? this.maxZoom : Math.min(this.maxZoom, finiteNumber(payload.max_zoom, this.maxZoom)),
        })
        if (target) this.setViewportFromCommand(target, payload.animate_ms, timestamp)
        break
      }

      case "viewport.center_node": {
        const node = this.nodes.get(payload.node_id)
        const position = node ? this.displayNodePosition(node.id) : null
        if (node && position) {
          const target = {
            centerX: position.x + node.width / 2,
            centerY: position.y + node.height / 2,
            zoom: payload.zoom == null ? this.viewport.zoom : clamp(payload.zoom, this.minZoom, this.maxZoom),
          }
          this.setViewportFromCommand(target, payload.animate_ms, timestamp)
        }
        break
      }
    }
  }

  supersedeUncommittedViewportInput() {
    if (this.interaction?.kind === "pan") this.cancelInteraction({restore: true})

    if (this.wheelCommitTimer !== null) {
      this.win.clearTimeout(this.wheelCommitTimer)
      this.wheelCommitTimer = null
    }

    if (this.viewportProjection?.kind === "local") {
      if (this.localViewportBase) {
        this.viewport = copyViewport(this.localViewportBase.viewport)
        this.viewportProjection = this.localViewportBase.projection
      } else {
        const pending = this.latestPendingViewport()
        this.viewport = copyViewport(pending?.viewport || this.authoritativeViewport)
        this.viewportProjection = pending ? {kind: "pending", operationId: pending.operationId} : null
      }
      this.mark("viewport", "overlay")
    }

    this.localViewportBase = null
  }

  setViewportFromCommand(target, animateMs, timestamp) {
    const duration = Math.max(0, finiteNumber(animateMs))
    const reduceMotion = this.win.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches
    this.viewportProjection = {kind: "command"}

    if (duration === 0 || reduceMotion) {
      this.viewportAnimation = null
      this.viewport = copyViewport(target)
      this.mark("viewport", "overlay")
      return
    }

    this.viewportAnimation = {
      from: copyViewport(this.viewport),
      to: copyViewport(target),
      startedAt: finiteNumber(timestamp, this.win.performance.now()),
      duration,
    }
    this.mark("viewport", "overlay")
  }

  stepViewportAnimation(timestamp) {
    const animation = this.viewportAnimation
    if (!animation) return
    const progress = (timestamp - animation.startedAt) / animation.duration
    this.viewport = interpolateViewport(animation.from, animation.to, easeOutCubic(progress))
    this.dirty.viewport = true
    this.dirty.overlay = true

    if (progress >= 1) {
      this.viewport = copyViewport(animation.to)
      this.viewportAnimation = null
    }
  }

  boundsForNodes(ids) {
    return boundsOfRects(ids.map((id) => {
      const node = this.nodes.get(id)
      const position = node ? this.displayNodePosition(id) : null
      if (!node || !position) return null
      return {x: position.x, y: position.y, width: node.width, height: node.height}
    }))
  }

  registerPendingOperation(operationId, operation) {
    this.pendingOperations.set(operationId, operation)
    if (this.earlyRejectedIntents.delete(operationId)) this.resolveOperation(operationId, "rejected")
  }

  handleIntentReply(intentId, type, reply) {
    if (!replyRejectsIntent(reply)) return
    if (this.pendingOperations.has(intentId)) {
      this.resolveOperation(intentId, "rejected", {preserveCommandViewport: true})
    } else if (["nodes.move", "selection.change", "viewport.change"].includes(type)) {
      this.earlyRejectedIntents.add(intentId)
    }
  }

  resolveOperation(operationId, _status, options = {}) {
    if (typeof operationId !== "string") return
    const operation = this.pendingOperations.get(operationId)
    if (!operation) return
    this.pendingOperations.delete(operationId)

    if (operation.kind === "nodes") {
      for (const nodeId of operation.nodeIds) {
        if (this.nodeOverrides.get(nodeId)?.operationId === operationId) this.nodeOverrides.delete(nodeId)
      }
      this.mark("nodes", "edges", "overlay")
    }

    if (operation.selection) {
      for (const pending of this.pendingOperations.values()) {
        if (pending.selection && pending.sequence <= operation.sequence) pending.selectionSuperseded = true
      }
      const latest = this.latestPendingSelection()
      this.displaySelection = latest ? copyGraphSelection(latest.selection) : copyGraphSelection(this.authoritativeSelection)
      this.mark("selection")
    }

    if (operation.kind === "viewport") {
      for (const pending of this.pendingOperations.values()) {
        if (pending.kind === "viewport" && pending.sequence <= operation.sequence) pending.viewportSuperseded = true
      }
      const latest = this.latestPendingViewport()
      if (latest) {
        this.viewport = copyViewport(latest.viewport)
        this.viewportProjection = {kind: "pending", operationId: latest.operationId}
      } else if (options.preserveCommandViewport && this.viewportProjection?.kind === "command") {
        // A later server command already superseded this rejected client input.
      } else {
        this.viewportAnimation = null
        this.viewport = copyViewport(this.authoritativeViewport)
        this.viewportProjection = null
      }
      this.mark("viewport", "overlay")
    }
  }

  latestPendingSelection() {
    let latest = null
    for (const operation of this.pendingOperations.values()) {
      if (operation.selection && !operation.selectionSuperseded && (!latest || operation.sequence > latest.sequence)) {
        latest = operation
      }
    }
    return latest
  }

  latestPendingViewport() {
    let latest = null
    for (const operation of this.pendingOperations.values()) {
      if (operation.kind === "viewport" && !operation.viewportSuperseded && (!latest || operation.sequence > latest.sequence)) {
        latest = operation
      }
    }
    return latest
  }

  isSelectionGestureActive() {
    return ["node-press", "node-drag", "edge-press", "box-press", "box"].includes(this.interaction?.kind)
  }

  pointerDown(event) {
    if (!this.ownsEventTarget(event.target)) return
    if (this.interaction) return

    const isMiddle = event.button === 1
    const isPrimary = event.button === 0
    if (!isMiddle && !isPrimary) return

    const local = this.localFromEvent(event, true)
    if (isMiddle || (isPrimary && this.spacePressed)) {
      this.startPan(event, local)
      return
    }
    if (!isPrimary) return

    const portElement = closestInEditor(this.el, event.target, SELECTOR.port)
    if (portElement) {
      this.startWire(event, local, portElement)
      return
    }

    const nodeElement = closestInEditor(this.el, event.target, SELECTOR.node)
    if (nodeElement) {
      const interactive = closestInEditor(this.el, event.target, INTERACTIVE_SELECTOR)
      if (interactive) return

      const handle = closestInEditor(this.el, event.target, SELECTOR.dragHandle)
      const hasHandle = Boolean(nodeElement.querySelector(SELECTOR.dragHandle))
      this.startNodePress(event, local, nodeElement, Boolean(handle) || !hasHandle)
      return
    }

    const edgeElement = closestInEditor(this.el, event.target, `${SELECTOR.edge}, ${SELECTOR.edgeHit}`)
    if (edgeElement?.dataset.edgeId) {
      this.startEdgePress(event, local, edgeElement)
      return
    }

    if (event.pointerType === "touch") this.startPan(event, local)
    else this.startBoxPress(event, local)
  }

  pointerMove(event) {
    const interaction = this.interaction
    if (!interaction || event.pointerId !== interaction.pointerId) return
    const local = this.localFromEvent(event)

    switch (interaction.kind) {
      case "pan":
        this.viewport = panViewport(interaction.startViewport, {
          x: local.x - interaction.startLocal.x,
          y: local.y - interaction.startLocal.y,
        })
        interaction.moved = interaction.moved || pointerDistance(interaction, local) >= DRAG_THRESHOLD
        this.mark("viewport", "overlay")
        break

      case "node-press":
        if (interaction.canDrag && pointerDistance(interaction, local) >= DRAG_THRESHOLD) {
          this.beginNodeDrag(interaction, local)
        } else if (!interaction.canDrag && pointerDistance(interaction, local) >= DRAG_THRESHOLD) {
          interaction.moved = true
        }
        break

      case "node-drag":
        this.updateNodeDrag(interaction, local)
        break

      case "edge-press":
        break

      case "box-press":
        if (pointerDistance(interaction, local) >= DRAG_THRESHOLD) this.beginBox(interaction, local)
        break

      case "box":
        this.updateBox(interaction, local)
        break

      case "wire":
        this.updateWire(interaction, event, local)
        break
    }
  }

  pointerUp(event) {
    const interaction = this.interaction
    if (!interaction || event.pointerId !== interaction.pointerId) return
    const local = this.localFromEvent(event)

    switch (interaction.kind) {
      case "pan":
        this.viewport = panViewport(interaction.startViewport, {
          x: local.x - interaction.startLocal.x,
          y: local.y - interaction.startLocal.y,
        })
        this.finishPointer(event)
        if (!this.viewportsEqual(interaction.startViewport, this.viewport)) {
          this.sendViewportIntent(interaction.gestureId, interaction.baseRevision)
        } else {
          this.viewportProjection = interaction.startViewportProjection || null
        }
        break

      case "node-press":
        this.finishNodePress(interaction)
        this.finishPointer(event)
        break

      case "node-drag":
        this.updateNodeDrag(interaction, local)
        this.finishNodeDrag(interaction)
        this.finishPointer(event)
        break

      case "edge-press":
        this.finishEdgePress(interaction)
        this.finishPointer(event)
        break

      case "box-press":
        this.finishBoxPress(interaction)
        this.finishPointer(event)
        break

      case "box":
        this.updateBox(interaction, local)
        this.finishBox(interaction)
        this.finishPointer(event)
        break

      case "wire":
        this.updateWire(interaction, event, local)
        this.finishWire(interaction)
        this.finishPointer(event)
        break
    }
  }

  pointerCancel(event) {
    if (!this.interaction || event.pointerId !== this.interaction.pointerId) return
    this.cancelInteraction({restore: true})
    this.releasePointer(event.pointerId)
  }

  startPan(event, local) {
    const startViewportProjection = this.viewportProjection
    this.cancelViewportAnimation()
    this.viewportProjection = {kind: "local"}
    this.focusEditor()
    this.interaction = {
      kind: "pan",
      pointerId: event.pointerId,
      startLocal: local,
      startViewport: copyViewport(this.viewport),
      startViewportProjection,
      baseRevision: this.revision,
      gestureId: uniqueId("gesture"),
      moved: false,
    }
    this.capturePointer(event.pointerId)
    event.preventDefault()
    this.mark("overlay")
  }

  startNodePress(event, local, element, canDrag) {
    this.cancelViewportAnimation()
    this.focusEditor()
    const nodeId = element.dataset.nodeId
    const baseSelection = copyGraphSelection(this.displaySelection)
    const mode = selectionModeFromModifiers(event)

    if (!baseSelection.nodeIds.has(nodeId)) {
      this.displaySelection = updateGraphSelection(baseSelection, {nodeIds: [nodeId]}, mode)
    }

    this.interaction = {
      kind: "node-press",
      pointerId: event.pointerId,
      nodeId,
      startLocal: local,
      startScene: localToScene(local, this.viewport, this.surfaceSize),
      baseSelection,
      mode,
      canDrag,
      moved: false,
      baseRevision: this.revision,
      gestureId: uniqueId("gesture"),
    }
    this.capturePointer(event.pointerId)
    event.preventDefault()
    this.mark("selection", "overlay")
  }

  beginNodeDrag(press, local) {
    const pointerScene = localToScene(local, this.viewport, this.surfaceSize)
    const startPointerScene = press.startScene
    const positions = new Map()
    const offsets = new Map()

    for (const nodeId of this.displaySelection.nodeIds) {
      const position = this.displayNodePosition(nodeId)
      if (!position) continue
      positions.set(nodeId, {...position})
      offsets.set(nodeId, {x: position.x - startPointerScene.x, y: position.y - startPointerScene.y})
    }

    this.interaction = {
      ...press,
      kind: "node-drag",
      offsets,
      positions,
      currentScene: pointerScene,
    }
    this.updateNodeDrag(this.interaction, local)
    this.mark("nodes", "edges", "overlay")
  }

  updateNodeDrag(interaction, local) {
    const pointerScene = localToScene(local, this.viewport, this.surfaceSize)
    interaction.currentScene = pointerScene
    for (const [nodeId, offset] of interaction.offsets) {
      interaction.positions.set(nodeId, {x: pointerScene.x + offset.x, y: pointerScene.y + offset.y})
    }
    this.mark("nodes", "edges", "overlay")
  }

  finishNodePress(interaction) {
    if (interaction.moved) {
      this.displaySelection = copyGraphSelection(interaction.baseSelection)
    } else {
      this.displaySelection = updateGraphSelection(
        interaction.baseSelection,
        {nodeIds: [interaction.nodeId]},
        interaction.mode,
      )
    }
    this.commitSelectionIfChanged(interaction.baseSelection, interaction.gestureId, interaction.baseRevision)
    this.mark("selection", "overlay")
  }

  finishNodeDrag(interaction) {
    const positions = [...interaction.positions].map(([id, position]) => ({id, x: position.x, y: position.y}))
    const selection = copyGraphSelection(this.displaySelection)
    const operationId = this.sendIntent("nodes.move", nodesMovePayload(positions, selection), {
      gestureId: interaction.gestureId,
      baseRevision: interaction.baseRevision,
    })

    for (const position of positions) {
      this.nodeOverrides.set(position.id, {
        operationId,
        position: {x: position.x, y: position.y},
      })
    }
    this.registerPendingOperation(operationId, {
      kind: "nodes",
      operationId,
      nodeIds: positions.map((position) => position.id),
      selection,
      sequence: this.intentSequence,
    })
    this.mark("nodes", "selection", "edges", "overlay")
  }

  startEdgePress(event, local, element) {
    this.cancelViewportAnimation()
    this.focusEditor()
    const edgeId = element.dataset.edgeId
    const baseSelection = copyGraphSelection(this.displaySelection)
    const mode = selectionModeFromModifiers(event)

    if (!baseSelection.edgeIds.has(edgeId)) {
      this.displaySelection = updateGraphSelection(baseSelection, {edgeIds: [edgeId]}, mode)
    }

    this.interaction = {
      kind: "edge-press",
      pointerId: event.pointerId,
      edgeId,
      startLocal: local,
      baseSelection,
      mode,
      baseRevision: this.revision,
      gestureId: uniqueId("gesture"),
    }
    this.capturePointer(event.pointerId)
    event.preventDefault()
    this.mark("selection", "overlay")
  }

  finishEdgePress(interaction) {
    this.displaySelection = updateGraphSelection(
      interaction.baseSelection,
      {edgeIds: [interaction.edgeId]},
      interaction.mode,
    )
    this.commitSelectionIfChanged(interaction.baseSelection, interaction.gestureId, interaction.baseRevision)
    this.mark("selection", "overlay")
  }

  startBoxPress(event, local) {
    this.cancelViewportAnimation()
    this.focusEditor()
    const baseSelection = copyGraphSelection(this.displaySelection)
    const mode = selectionModeFromModifiers(event)
    if (mode === "replace") this.displaySelection = graphSelection()

    this.interaction = {
      kind: "box-press",
      pointerId: event.pointerId,
      startLocal: local,
      startScene: localToScene(local, this.viewport, this.surfaceSize),
      baseSelection,
      mode,
      baseRevision: this.revision,
      gestureId: uniqueId("gesture"),
    }
    this.capturePointer(event.pointerId)
    event.preventDefault()
    this.mark("selection", "overlay")
  }

  beginBox(press, local) {
    this.interaction = {
      ...press,
      kind: "box",
      currentScene: localToScene(local, this.viewport, this.surfaceSize),
    }
    this.updateBox(this.interaction, local)
  }

  updateBox(interaction, local) {
    interaction.currentScene = localToScene(local, this.viewport, this.surfaceSize)
    const selectionRectangle = rectFromPoints(interaction.startScene, interaction.currentScene)
    const hits = []

    for (const node of this.nodes.values()) {
      const position = this.displayNodePosition(node.id)
      if (position && rectsIntersect(selectionRectangle, {
        x: position.x,
        y: position.y,
        width: node.width,
        height: node.height,
      })) hits.push(node.id)
    }

    this.displaySelection = updateGraphSelection(interaction.baseSelection, {nodeIds: hits}, interaction.mode)
    this.mark("selection", "overlay")
  }

  finishBoxPress(interaction) {
    if (interaction.mode !== "replace") this.displaySelection = copyGraphSelection(interaction.baseSelection)
    this.commitSelectionIfChanged(interaction.baseSelection, interaction.gestureId, interaction.baseRevision)
    this.mark("selection", "overlay")
  }

  finishBox(interaction) {
    this.commitSelectionIfChanged(interaction.baseSelection, interaction.gestureId, interaction.baseRevision)
    this.mark("selection", "overlay")
  }

  startWire(event, local, element) {
    this.cancelViewportAnimation()
    this.focusEditor()
    const key = portKey(element.dataset.nodeId, element.dataset.portId)
    const source = this.ports.get(key)
    if (!source) return

    this.interaction = {
      kind: "wire",
      pointerId: event.pointerId,
      sourceKey: key,
      candidateKey: null,
      currentScene: localToScene(local, this.viewport, this.surfaceSize),
      startLocal: local,
      baseRevision: this.revision,
      gestureId: uniqueId("gesture"),
    }
    this.capturePointer(event.pointerId)
    event.preventDefault()
    this.mark("overlay")
  }

  updateWire(interaction, event, local) {
    interaction.currentScene = localToScene(local, this.viewport, this.surfaceSize)
    const targetElement = this.doc.elementFromPoint(event.clientX, event.clientY)
    const portElement = closestInEditor(this.el, targetElement, SELECTOR.port)
    const candidateKey = portElement ? portKey(portElement.dataset.nodeId, portElement.dataset.portId) : null
    const source = this.ports.get(interaction.sourceKey)
    const candidate = candidateKey ? this.ports.get(candidateKey) : null
    interaction.candidateKey = source && candidate && this.portsCompatible(source, candidate) ? candidateKey : null
    this.mark("overlay")
  }

  portsCompatible(first, second) {
    if (first.key === second.key) return false
    if (first.direction === "output" && second.direction === "output") return false
    if (first.direction === "input" && second.direction === "input") return false
    return true
  }

  finishWire(interaction) {
    const first = this.ports.get(interaction.sourceKey)
    const second = interaction.candidateKey ? this.ports.get(interaction.candidateKey) : null
    if (!first || !second || !this.portsCompatible(first, second)) return

    let source = first
    let target = second
    if (first.direction === "input" || second.direction === "output") {
      source = second
      target = first
    }

    this.sendIntent("connection.create", {
      source: {node_id: source.nodeId, port_id: source.portId},
      target: {node_id: target.nodeId, port_id: target.portId},
    }, {
      gestureId: interaction.gestureId,
      baseRevision: interaction.baseRevision,
    })
    this.mark("overlay")
  }

  commitSelectionIfChanged(baseSelection, gestureId, baseRevision) {
    if (graphSelectionsEqual(baseSelection, this.displaySelection)) return null
    const selection = copyGraphSelection(this.displaySelection)
    const operationId = this.sendIntent("selection.change", {
      mode: "replace",
      ...selectionPayload(selection),
    }, {gestureId, baseRevision})

    this.registerPendingOperation(operationId, {
      kind: "selection",
      operationId,
      selection,
      sequence: this.intentSequence,
    })
    return operationId
  }

  wheel(event) {
    if (!this.ownsEventTarget(event.target)) return
    if (closestInEditor(this.el, event.target, "[data-dnd-native-wheel]")) return
    if (closestInEditor(this.el, event.target, "input, select, textarea")) return

    if (this.viewportProjection?.kind !== "local") {
      this.localViewportBase = {
        viewport: copyViewport(this.viewport),
        projection: this.viewportProjection,
      }
    }
    this.cancelViewportAnimation()
    this.viewportProjection = {kind: "local"}
    const rectangle = this.surface.getBoundingClientRect()
    this.surfaceRect = rectangle
    this.surfaceSize = {width: Math.max(1, rectangle.width), height: Math.max(1, rectangle.height)}
    const local = {x: event.clientX - rectangle.left, y: event.clientY - rectangle.top}
    const delta = normalizeWheelDelta(event, rectangle.height)

    if (event.ctrlKey) {
      const nextZoom = this.viewport.zoom * Math.exp(-delta.y * 0.002)
      this.viewport = zoomViewportAt(this.viewport, nextZoom, local, this.surfaceSize, {
        minZoom: this.minZoom,
        maxZoom: this.maxZoom,
      })
    } else {
      this.viewport = panViewport(this.viewport, {x: -delta.x, y: -delta.y})
    }

    event.preventDefault()
    this.mark("viewport", "overlay")
    this.scheduleWheelCommit()
  }

  scheduleWheelCommit() {
    if (this.wheelCommitTimer !== null) this.win.clearTimeout(this.wheelCommitTimer)
    this.wheelCommitTimer = this.win.setTimeout(() => {
      this.wheelCommitTimer = null
      this.sendViewportIntent(null, this.revision)
    }, WHEEL_COMMIT_DELAY)
  }

  keyDown(event) {
    if (!this.ownsEventTarget(event.target)) return
    if (event.key === "Escape" && this.interaction) {
      event.preventDefault()
      this.cancelInteraction({restore: true})
      return
    }

    if (
      (event.key === "Delete" || event.key === "Backspace") &&
      !this.isEditableTarget(event.target) &&
      (this.displaySelection.nodeIds.size > 0 || this.displaySelection.edgeIds.size > 0)
    ) {
      event.preventDefault()
      if (!event.repeat) this.sendIntent("delete.request", selectionPayload(this.displaySelection))
      return
    }

    if (event.code === "Space" && !this.isEditableTarget(event.target)) {
      this.spacePressed = true
      event.preventDefault()
    }
  }

  keyUp(event) {
    if (event.code === "Space") this.spacePressed = false
  }

  windowBlur() {
    this.spacePressed = false
    if (this.interaction) this.cancelInteraction({restore: true})
  }

  isEditableTarget(target) {
    return Boolean(target && typeof target.closest === "function" && target.closest(INTERACTIVE_SELECTOR))
  }

  ownsEventTarget(target) {
    return eventTargetBelongsToEditor(this.el, target)
  }

  cancelInteraction({restore}) {
    const interaction = this.interaction
    if (!interaction) return

    if (restore && interaction.baseSelection) this.displaySelection = copyGraphSelection(interaction.baseSelection)
    if (restore && interaction.kind === "pan" && interaction.startViewport) {
      this.viewport = copyViewport(interaction.startViewport)
      this.viewportProjection = interaction.startViewportProjection || null
    }

    this.releasePointer(interaction.pointerId)
    this.interaction = null
    this.renderWireCandidate(null)
    this.mark("viewport", "nodes", "selection", "edges", "overlay")
  }

  reconcileInteraction() {
    const interaction = this.interaction
    if (!interaction) return

    if (interaction.nodeId && !this.nodes.has(interaction.nodeId)) {
      this.cancelInteraction({restore: false})
      return
    }
    if (interaction.edgeId && !this.edgesById.has(interaction.edgeId)) {
      this.cancelInteraction({restore: false})
      return
    }
    if (interaction.kind === "wire" && !this.ports.has(interaction.sourceKey)) {
      this.cancelInteraction({restore: false})
      return
    }
    if (interaction.kind === "node-drag") {
      for (const nodeId of interaction.positions.keys()) {
        if (!this.nodes.has(nodeId)) {
          interaction.positions.delete(nodeId)
          interaction.offsets.delete(nodeId)
        }
      }
    }
  }

  finishPointer(event) {
    this.releasePointer(event.pointerId)
    this.interaction = null
    this.renderWireCandidate(null)
    this.mark("viewport", "nodes", "selection", "edges", "overlay")
  }

  capturePointer(pointerId) {
    try { this.el.setPointerCapture(pointerId) } catch (_error) { /* ignored */ }
  }

  releasePointer(pointerId) {
    try {
      if (this.el.hasPointerCapture(pointerId)) this.el.releasePointerCapture(pointerId)
    } catch (_error) { /* ignored */ }
  }

  localFromEvent(event, refreshRectangle = false) {
    if (refreshRectangle || !this.surfaceRect) this.surfaceRect = this.surface.getBoundingClientRect()
    return {
      x: event.clientX - this.surfaceRect.left,
      y: event.clientY - this.surfaceRect.top,
    }
  }

  focusEditor() {
    try { this.el.focus({preventScroll: true}) } catch (_error) { this.el.focus() }
  }

  cancelViewportAnimation() {
    this.viewportAnimation = null
  }

  viewportsEqual(first, second) {
    return viewportsEqual(first, second)
  }

  sendViewportIntent(gestureId, baseRevision) {
    const viewport = copyViewport(this.viewport)
    const operationId = this.sendIntent("viewport.change", {
      center_x: viewport.centerX,
      center_y: viewport.centerY,
      zoom: viewport.zoom,
    }, {gestureId, baseRevision})
    this.viewportProjection = {kind: "pending", operationId}
    this.localViewportBase = null
    this.registerPendingOperation(operationId, {
      kind: "viewport",
      operationId,
      viewport,
      sequence: this.intentSequence,
    })
    return operationId
  }

  sendIntent(type, payload, options = {}) {
    this.intentSequence += 1
    const intentId = `${this.clientId}-${this.intentSequence}`
    const envelope = {
      v: VERSION,
      client_id: this.clientId,
      intent_id: intentId,
      base_revision: nonNegativeInteger(options.baseRevision, this.revision),
      type,
      phase: options.phase || "commit",
      payload,
    }
    if (options.gestureId) envelope.gesture_id = options.gestureId
    this.hook.pushEventTo(this.el, "phoenix_dnd:intent", envelope, (reply) => {
      this.handleIntentReply(intentId, type, reply)
    })
    return intentId
  }
}

const GraphHook = {
  mounted() {
    this.__phoenixDndRuntime = new GraphRuntime(this)
    this.__phoenixDndRuntime.mount()
  },

  beforeUpdate() {
    this.__phoenixDndRuntime?.beforeUpdate()
  },

  updated() {
    this.__phoenixDndRuntime?.updated()
  },

  disconnected() {
    this.__phoenixDndRuntime?.disconnected()
  },

  reconnected() {
    this.__phoenixDndRuntime?.reconnected()
  },

  destroyed() {
    this.__phoenixDndRuntime?.destroy()
    this.__phoenixDndRuntime = null
  },
}

export const hooks = Object.freeze({
  "PhoenixDnd.Graph": GraphHook,
})

export default hooks
