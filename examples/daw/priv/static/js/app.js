import {Socket} from "/vendor/phoenix/phoenix.mjs"
import {LiveSocket} from "/vendor/phoenix_live_view/phoenix_live_view.esm.js"
import {hooks as phoenixDndHooks} from "/phoenix-dnd/phoenix_dnd.js"
import {createCaptureHook, createPlayerHook} from "/assets/js/webrtc.js"
import {createMetersHook} from "/assets/js/meters.js"

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  ?.getAttribute("content")

if (!csrfToken) {
  throw new Error("The Membrane studio requires a CSRF meta tag")
}

const iceServers = [{urls: "stun:stun.l.google.com:19302"}]

const hooks = {
  ...phoenixDndHooks,
  StudioCapture: createCaptureHook(iceServers),
  StudioPlayer: createPlayerHook(iceServers),
  StudioMeters: createMetersHook(),
}

const liveSocket = new LiveSocket("/live", Socket, {
  hooks,
  params: {_csrf_token: csrfToken},
})

liveSocket.connect()

// LiveView's console logging is opt-in and sticky: it lives in sessionStorage,
// so `liveSocket.enableDebug()` stays on across reloads until it is turned off
// with `liveSocket.disableDebug()`.
window.liveSocket = liveSocket
