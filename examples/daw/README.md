# Membrane WebRTC studio

A second `phoenix-dnd` example, in which the node graph is not a picture of a
pipeline — it *is* the pipeline. Nodes are audio stages, edges are signal
paths, and every accepted edit reconfigures a running
[Membrane](https://membrane.stream) graph that is processing live WebRTC audio
from your microphone and streaming the result back to your browser.

```sh
nix develop
cd examples/daw
mix setup
mix phx.server
```

Visit <http://localhost:4001>. **Wear headphones** — monitoring your own
microphone through speakers will feed back.

## Why this example exists

The library's thesis is that the server owns the graph. That is easy to assert
and hard to feel when the graph is a diagram. Here the server owns something
with real consequences, so the authority is not decorative:

- A rejected connection is rejected because the audio graph could not perform
  it — patching a second cable into a port that mixes nothing, or closing a
  feedback loop.
- The rejection travels the ordinary route: `Command.operation_resolve/3` with
  a reason, which the hook applies by rolling the optimistic edge back.
- Accepted edits are recompiled into a plan and handed to a running element, so
  you hear the change without the stream stopping.

## Architecture

```
       ┌── linked when the browser's mic track actually arrives ───┐
       │   WebRTC.Source ── Opus.Decoder ──┐                       │
       └───────────────────────────────────┼───────────────────────┘
                                           │  dynamic :input pads
                                           ▼
                                     Daw.Engine  ◄── {:plan, plan}
                            (20 ms tick; runs the DSP graph)
                                           │
                    ┌──────────────────────┼── dynamic :tap pads ──┐
                    ▼                      ▼                       ▼
             Opus.Encoder            Daw.WavSink            Daw.WavSink
                    │              (one per Recorder node)
                    ▼
              WebRTC.Sink ──► your browser
```

`Daw.Engine` is the studio's only clock. Each tick it pulls whatever
microphone audio has queued, evaluates the compiled plan in topological order,
and pushes one 20 ms block of 48 kHz stereo downstream.

### Why the graph runs inside one element

The obvious design — one Membrane child per node, one link per edge — was
rejected on purpose. Membrane tears down links by removing children, so every
re-patch would mean rebuilding part of the pipeline while audio flowed through
it. Evaluating the graph inside a single element makes a re-patch a message
rather than a teardown: no renegotiation, no dropout, and the DSP becomes a
pure function that `test/daw/dsp_test.exs` can exercise without a pipeline, a
peer connection, or a browser.

Nodes that genuinely need their own process still get one. A Recorder is a real
`Daw.WavSink` child, spawned and torn down at runtime against a dynamic `:tap`
pad, which is where the dynamic-reconfiguration path is exercised for real.

### Why the microphone is not in the spine

Membrane moves every child to `playing` together, so one child with incomplete
setup holds up the whole pipeline. `Membrane.WebRTC.Source` does not complete
setup until a peer has connected — which for a microphone means waiting on a
permission prompt the user may ignore or deny.

An earlier version linked the microphone straight into a static engine input
pad. The result was a studio that did nothing at all until mic permission was
granted: no audio, no meters, and every graph edit apparently ignored, because
the engine's timer had never started.

So the microphone links itself in afterwards. The source is created unlinked,
announces its tracks with a `:new_tracks` notification, and only then is a
decoder spawned and attached to a dynamic engine input pad. The studio runs
from page load, with or without a microphone, and picks one up if it appears.

`Membrane.WebRTC.Sink` gates startup the same way, and that one is left in
place: it needs no permission prompt and negotiates as soon as the page loads,
and until it has, there is nobody to hear anything anyway. The status chip in
the header reports which of those two things has happened.

## Who owns what

Two kinds of edit share the LiveView, and they deliberately travel different
routes:

| Edit | Route | Reaches the engine? |
| --- | --- | --- |
| Move a node, select, pan/zoom | `PhoenixDnd` intent | No — position is not audio |
| Patch or unpatch a cable | `PhoenixDnd` intent | Yes |
| Add or delete a node | LiveView event | Yes |
| Turn a knob | LiveView event | Yes |

Moving a node compiles to a byte-identical plan, so a drag never disturbs the
audio. Turning a knob is a form event rather than an intent, because it is not
a direct-manipulation gesture and does not belong in the intent protocol.
`test/daw_web/studio_live_test.exs` asserts both halves of that table.

## The node palette

Everything in the palette does real work; none of it is a pass-through stub.

| Category | Nodes |
| --- | --- |
| Sources | Mic In, Oscillator (sine/square/saw/triangle), Noise (white/pink) |
| Effects | Gain, Pan, Delay, Low Pass, High Pass, Tremolo, Overdrive, Bitcrusher, Compressor, Reverb, Chorus |
| Routing | Mixer, Splitter, Meter |
| Outputs | Recorder, Master Out |

The DSP is honest but cheap, and the code says so where it matters: the reverb
is a Schroeder comb-and-allpass network, the filters are one-pole, and changing
a delay time clicks rather than crossfading. The whole palette evaluated at once
costs roughly 7 ms of the 20 ms tick budget.

Mixer is the only node that accepts fan-in; everything else takes one signal per
input port, which is what makes the arity rejection meaningful. Mic In and
Master Out are fixed parts of the studio and cannot be deleted.

Recorder nodes write to `priv/recordings/<node-id>.wav`.

## Why the studio owns its WebRTC hooks

`membrane_webrtc_plugin` ships `Capture` and `Player` LiveViews with browser
hooks that do exactly this job, and this example used them first. Three things
made owning about a hundred lines of JavaScript the better trade — and each of
them produced a studio that looked completely healthy and made no sound.

**They throw under strict mode.** Both shipped hooks assign to an undeclared
`message`:

```javascript
message = { type: `sdp_answer`, data: answer };
this.pushEventTo(this.el, `webrtc_signaling`, message);
```

ES modules are always strict, so that is a `ReferenceError`. Bundled builds
never hit it, because bundlers commonly emit sloppy-mode wrappers where the same
line quietly creates a global — invisible to everyone running esbuild, fatal to
anyone serving the files as native ESM, as this example does. It fails quietly:
the browser still applies the offer, builds an answer, and gathers ICE, so the
server sees STUN traffic and looks half-connected, but the throw lands on the
line *before* the answer is pushed. The answer never arrives, the peer
connection never completes, the sink never finishes setup, the pipeline never
reaches `playing`, and the engine's clock never starts.

**Capture plays a local monitor.** It attaches the raw microphone to its own
element and calls `play()`. That audio never reaches the server, so nothing in
the graph applies to it — not the master fader, not mute — and it is an
acoustic path straight back into the microphone. There is no option to turn it
off. Combined with the next point, the studio plays your unprocessed voice and
nothing else, so patching a Noise source into the Mixer appears to do nothing.

**Player renders its element muted**, because browsers only autoplay muted
media, and relies on its own `controls` to unmute.

`priv/static/js/webrtc.js` replaces both. It speaks the same `json_data`
signalling protocol, so the server side is unchanged; `DawWeb.StudioLive`
registers itself as the browser's peer on both channels. The capture hook has
no local playback at all, and the player attaches the stream the track arrived
on rather than mutating an already-assigned `MediaStream`, which browsers do not
reliably pick up. The output is a plain `<audio controls autoplay>` in the
header: visible on purpose, because unmuted autoplay needs a prior interaction
with the page and those native controls are the one dependable way to start it
by hand.

## Meters do not go through the scene

The engine reports levels ten times a second. Rendering those into the scene
would mean a DOM diff per node per tick for information that is stale before it
lands — and it fills the browser console with diff traffic if LiveView
debugging is on.

So the server pushes one `levels` event and `priv/static/js/meters.js` writes to
the DOM directly. Nothing there is authoritative: a dropped meter frame is
invisible and the next arrives 100 ms later. This is the same division the
editor itself draws — durable state on the server, transient high-frequency
state in the browser.

(LiveView's console logging is opt-in and sticky: it lives in `sessionStorage`,
so once `liveSocket.enableDebug()` has been run it survives reloads until
`liveSocket.disableDebug()`.)

## Assets

The studio has no bundler. Its JavaScript and CSS are sources that live in
`priv/static` and are served straight from there, which means Mix copies them
into the build path like any other `priv` content, `Plug.Static` reads them
through the `{:app, "priv/static"}` form in every environment including a
release, and `mix phx.digest` can see them. `phoenix`, `phoenix_live_view`, and
`phoenix_dnd` ship their own ESM the same way and are served from their
packages.

## Native dependencies

The repository's `flake.nix` provides them: `ex_dtls` needs `pkg-config` and
OpenSSL, `ex_libsrtp` needs libsrtp2, and `membrane_opus_plugin` builds against
libopus.

## Tests

```sh
mix check
```

`test/daw/dsp_test.exs` covers the audio kernels as pure functions,
`test/daw/engine_test.exs` runs the engine as a real Membrane element including
a live plan swap, `test/daw/graph_test.exs` covers the connection rules, and
`test/daw_web/studio_live_test.exs` covers the editor-to-engine seam.
Several are there because this example broke in ways nothing else would have
caught. `test/daw/webrtc_playback_test.exs` drives a real
`ExWebRTC.PeerConnection` through the same signalling channel the browser uses
and asserts the engine starts ticking and RTP arrives — the only test that
would notice the pipeline failing to reach `playing`.
`test/js/webrtc.test.js` runs the studio's hooks as native ES modules, which is
the only place a strict-mode failure is visible, and pins the two behaviours
that made the studio silent: capture must never play a local monitor, and the
player must attach the stream the track arrived on.
`test/js/meters.test.js` covers the meter mapping.
