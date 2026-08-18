import {Socket} from "/vendor/phoenix/phoenix.mjs"
import {LiveSocket} from "/vendor/phoenix_live_view/phoenix_live_view.esm.js"
import {hooks as phoenixDndHooks} from "/phoenix-dnd/phoenix_dnd.js"

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  ?.getAttribute("content")

if (!csrfToken) {
  throw new Error("Phoenix DnD demo requires a CSRF meta tag")
}

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: phoenixDndHooks,
  params: {_csrf_token: csrfToken},
})

liveSocket.connect()

// Useful for latency simulation and LiveView debugging from the console.
window.liveSocket = liveSocket
