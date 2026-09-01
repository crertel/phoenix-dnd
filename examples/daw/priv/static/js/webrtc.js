/*
 * The studio's own WebRTC signalling hooks.
 *
 * membrane_webrtc_plugin ships Capture and Player LiveViews with hooks that do
 * this already, and this example used them at first. Three things made owning
 * ~100 lines the better trade:
 *
 * 1. Both shipped hooks assign to an undeclared `message`, which throws under
 *    the strict-mode semantics every ES module gets. Bundlers hide it; serving
 *    the files as native ESM, as this example does, does not.
 * 2. Capture attaches the raw microphone to its own element and plays it. That
 *    is a local monitor which never reaches the server, so nothing in the audio
 *    graph applies to it, and it is an acoustic path straight back into the
 *    mic. There is no option to turn it off.
 * 3. Player renders its element `muted` (browsers only autoplay muted media)
 *    and relies on its own `controls` to unmute, which is awkward to reconcile
 *    with a studio that wants one obvious audio output.
 *
 * These hooks speak exactly the same `json_data` signalling protocol, so the
 * server side is unchanged.
 */

const DEFAULT_ICE_SERVERS = [{urls: "stun:stun.l.google.com:19302"}]

/** Normalises the browser's SDP into the shape the signalling channel wants. */
function describe(description) {
  return {type: description.type, sdp: description.sdp}
}

/**
 * Captures the microphone and offers it to `Membrane.WebRTC.Source`.
 *
 * The browser is the offerer here, which is what the source expects. Note the
 * absence of any local playback: the point of the studio is to hear audio that
 * has been through the graph.
 */
export function createCaptureHook(iceServers = DEFAULT_ICE_SERVERS) {
  return {
    mounted() {
      this.handleEvent("webrtc:capture", (message) => this.receive(message))
      this.start()
    },

    destroyed() {
      this.pc?.close()
    },

    async start() {
      let stream

      try {
        stream = await navigator.mediaDevices.getUserMedia({audio: true, video: false})
      } catch (error) {
        // A denied or absent microphone is not fatal; the studio still runs.
        this.pushEvent("mic_status", {state: "unavailable", reason: error?.name || String(error)})
        return
      }

      this.pc = new RTCPeerConnection({iceServers})

      this.pc.onicecandidate = (event) => {
        if (event.candidate) {
          this.send({type: "ice_candidate", data: event.candidate.toJSON()})
        }
      }

      this.pc.onconnectionstatechange = () => {
        this.pushEvent("mic_status", {state: this.pc.connectionState})
      }

      for (const track of stream.getTracks()) {
        this.pc.addTrack(track, stream)
      }

      const offer = await this.pc.createOffer()
      await this.pc.setLocalDescription(offer)
      this.send({type: "sdp_offer", data: describe(offer)})
    },

    send(message) {
      this.pushEvent("webrtc_signaling", {target: "capture", message})
    },

    async receive({type, data}) {
      if (!this.pc) return

      if (type === "sdp_answer") {
        await this.pc.setRemoteDescription(data)
      } else if (type === "ice_candidate") {
        await this.pc.addIceCandidate(data)
      }
    },
  }
}

/**
 * Plays what `Membrane.WebRTC.Sink` sends back.
 *
 * The browser answers here. The hook attaches the stream the track arrived on
 * rather than mutating a MediaStream that was already assigned to the element -
 * adding tracks after assignment is not reliably picked up across browsers, and
 * silently produces an element that is "playing" nothing.
 */
export function createPlayerHook(iceServers = DEFAULT_ICE_SERVERS) {
  return {
    mounted() {
      this.pc = new RTCPeerConnection({iceServers})

      this.pc.onicecandidate = (event) => {
        if (event.candidate) {
          this.send({type: "ice_candidate", data: event.candidate.toJSON()})
        }
      }

      this.pc.ontrack = (event) => {
        this.el.srcObject = event.streams[0] || new MediaStream([event.track])
        this.play()
      }

      this.handleEvent("webrtc:player", (message) => this.receive(message))
    },

    destroyed() {
      this.pc?.close()
    },

    async play() {
      try {
        await this.el.play()
        this.pushEvent("monitor_status", {state: "playing"})
      } catch (error) {
        // Autoplay policy. The element carries `controls`, so there is always a
        // visible way to start it by hand.
        this.pushEvent("monitor_status", {state: "blocked"})
      }
    },

    send(message) {
      this.pushEvent("webrtc_signaling", {target: "player", message})
    },

    async receive({type, data}) {
      if (type === "sdp_offer") {
        await this.pc.setRemoteDescription(data)
        const answer = await this.pc.createAnswer()
        await this.pc.setLocalDescription(answer)
        this.send({type: "sdp_answer", data: describe(answer)})
      } else if (type === "ice_candidate") {
        await this.pc.addIceCandidate(data)
      }
    },
  }
}
