# Phoenix DnD demo

This is a small, standalone Phoenix application that exercises the library as
a path dependency. It demonstrates a server-authoritative workflow canvas with
rich custom node rendering, injected live telemetry, runtime node creation and
removal, node movement, pan and zoom, selection, connection creation, deletion,
and revision-gated server commands.

From the repository root:

```sh
nix develop
cd examples/demo
mix setup
mix phx.server
```

Then visit <http://localhost:4000>.

The demo deliberately has no npm or asset-build step. Its endpoint serves the
Phoenix, LiveView, and Phoenix DnD ESM files directly, while `assets/js/app.js`
registers the library's static hook map. Normal Phoenix 1.8 applications should
prefer the library's generated colocated-hook manifest, as described in the
root README.

The relevant application integration is split between:

- `lib/phoenix_dnd_demo_web/live/editor_live.ex`, which owns the scene and
  accepts or rejects client intent while injecting transient telemetry into
  the node slot without advancing scene revisions;
- `lib/phoenix_dnd_demo/graph.ex`, a pure reducer for authoritative graph
  transitions;
- `assets/js/app.js`, the minimal LiveSocket and hook setup; and
- `assets/css/app.css`, the demo presentation layer over the library defaults.

Run the demo's checks with:

```sh
mix check
```
