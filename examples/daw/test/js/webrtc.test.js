// The studio's own WebRTC signalling hooks.
//
// These exist because the hooks shipped by membrane_webrtc_plugin could not be
// used as-is: they throw under the strict-mode semantics every ES module gets,
// they play an un-processed local monitor of the microphone, and their output
// element is muted. Each of those produced a studio that looked completely
// healthy and made no sound, so the replacements are tested directly.

import {test} from "node:test"
import assert from "node:assert/strict"

const {createCaptureHook, createPlayerHook} = await import("../../priv/static/js/webrtc.js")

class FakePeerConnection {
  constructor() {
    this.tracks = []
    this.localDescription = null
    this.remoteDescription = null
    this.connectionState = "new"
  }
  addTrack(track) { this.tracks.push(track) }
  async createOffer() { return {type: "offer", sdp: "offer-sdp"} }
  async createAnswer() { return {type: "answer", sdp: "answer-sdp"} }
  async setLocalDescription(d) { this.localDescription = d }
  async setRemoteDescription(d) { this.remoteDescription = d }
  async addIceCandidate(c) { this.candidate = c }
  close() { this.closed = true }
}

function mount(hook, {el = {}} = {}) {
  const pushed = []
  const handlers = {}
  const context = {
    el,
    pushEvent: (event, payload) => pushed.push({event, payload}),
    handleEvent: (name, callback) => (handlers[name] = callback),
    ...hook,
  }

  globalThis.RTCPeerConnection = FakePeerConnection
  globalThis.MediaStream = class { constructor(tracks = []) { this.tracks = tracks } }

  return {context, pushed, handlers}
}

function stubMicrophone(tracks = [{kind: "audio"}]) {
  Object.defineProperty(globalThis, "navigator", {
    configurable: true,
    value: {mediaDevices: {getUserMedia: async () => ({getTracks: () => tracks})}},
  })
}

function denyMicrophone(name = "NotAllowedError") {
  Object.defineProperty(globalThis, "navigator", {
    configurable: true,
    value: {
      mediaDevices: {
        getUserMedia: async () => {
          const error = new Error("denied")
          error.name = name
          throw error
        },
      },
    },
  })
}

test("capture offers the microphone to the server", async () => {
  stubMicrophone()
  const {context, pushed} = mount(createCaptureHook([]))

  await context.mounted()
  await new Promise((resolve) => setTimeout(resolve, 0))

  const offer = pushed.find((m) => m.payload.message?.type === "sdp_offer")

  assert.ok(offer, "the capture offer must reach the server")
  assert.equal(offer.event, "webrtc_signaling")
  assert.equal(offer.payload.target, "capture")
  assert.equal(offer.payload.message.data.sdp, "offer-sdp")
  assert.equal(context.pc.tracks.length, 1, "the mic track must be added to the peer connection")
})

test("capture never plays a local monitor of the microphone", async () => {
  stubMicrophone()
  const el = {}
  const {context} = mount(createCaptureHook([]), {el})

  await context.mounted()
  await new Promise((resolve) => setTimeout(resolve, 0))

  // The whole point of the studio is hearing audio that went through the graph.
  assert.equal(el.srcObject, undefined, "capture must not attach the mic to any element")
  assert.equal(typeof el.play, "undefined")
})

test("a denied microphone is reported and does not throw", async () => {
  denyMicrophone()
  const {context, pushed} = mount(createCaptureHook([]))

  await context.mounted()
  await new Promise((resolve) => setTimeout(resolve, 0))

  const status = pushed.find((m) => m.event === "mic_status")

  assert.ok(status, "a denied mic must be reported, not swallowed")
  assert.equal(status.payload.state, "unavailable")
  assert.equal(status.payload.reason, "NotAllowedError")
})

test("the player answers an offer and pushes the answer back", async () => {
  const el = {play: async () => {}}
  const {context, pushed, handlers} = mount(createPlayerHook([]), {el})

  context.mounted()
  await handlers["webrtc:player"]({type: "sdp_offer", data: {type: "offer", sdp: "offer-sdp"}})

  const answer = pushed.find((m) => m.payload.message?.type === "sdp_answer")

  assert.ok(answer, "the SDP answer must reach the server")
  assert.equal(answer.payload.target, "player")
  assert.equal(answer.payload.message.data.sdp, "answer-sdp")
})

test("the player attaches the stream the track arrived on", async () => {
  let played = false
  const el = {play: async () => (played = true)}
  const {context} = mount(createPlayerHook([]), {el})

  context.mounted()

  const stream = {id: "inbound"}
  context.pc.ontrack({track: {kind: "audio"}, streams: [stream]})

  // Mutating an already-assigned MediaStream is not reliably picked up by
  // browsers, and yields an element that is "playing" silence.
  assert.equal(el.srcObject, stream)
  assert.ok(played, "the output element must be started")
})

test("the player copes with a track that carries no stream", async () => {
  const el = {play: async () => {}}
  const {context} = mount(createPlayerHook([]), {el})

  context.mounted()
  context.pc.ontrack({track: {kind: "audio"}, streams: []})

  assert.ok(el.srcObject instanceof globalThis.MediaStream)
})

test("blocked autoplay is reported so the UI can say so", async () => {
  const el = {play: async () => { throw new Error("NotAllowedError") }}
  const {context, pushed} = mount(createPlayerHook([]), {el})

  context.mounted()
  context.pc.ontrack({track: {kind: "audio"}, streams: [{}]})
  await new Promise((resolve) => setTimeout(resolve, 0))

  const status = pushed.find((m) => m.event === "monitor_status")

  assert.ok(status)
  assert.equal(status.payload.state, "blocked")
})

test("ice candidates are routed to the channel that produced them", async () => {
  const el = {play: async () => {}}
  const {context, pushed} = mount(createPlayerHook([]), {el})

  context.mounted()
  context.pc.onicecandidate({candidate: {toJSON: () => ({candidate: "candidate:1"})}})

  const candidate = pushed.find((m) => m.payload.message?.type === "ice_candidate")

  assert.ok(candidate)
  assert.equal(candidate.payload.target, "player")
  assert.equal(candidate.payload.message.data.candidate, "candidate:1")
})

test("an end-of-candidates event is not forwarded", async () => {
  const el = {play: async () => {}}
  const {context, pushed} = mount(createPlayerHook([]), {el})

  context.mounted()
  context.pc.onicecandidate({candidate: null})

  assert.equal(pushed.filter((m) => m.event === "webrtc_signaling").length, 0)
})
