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
registers the library's static hook map. For CSS, the endpoint exposes the
compiled `phoenix-colocated` tree and `assets/css/app.css` imports the library's
generated manifest. Serving build output directly keeps this development demo
small; production applications should bundle the colocated hook and CSS
manifests as described in the root README.

The relevant application integration is split between:

- `lib/phoenix_dnd_demo_web/live/editor_live.ex`, which owns the scene and
  accepts or rejects client intent while injecting transient telemetry into
  the node slot without advancing scene revisions;
- `lib/phoenix_dnd_demo/graph.ex`, a pure reducer for authoritative graph
  transitions;
- `lib/phoenix_dnd_demo_web/endpoint.ex`, which exposes the compiled colocated
  CSS tree for the demo's no-build asset setup;
- `assets/js/app.js`, the minimal LiveSocket and hook setup; and
- `assets/css/app.css`, which imports the generated library defaults and adds
  the demo presentation layer.

Run the demo's checks with:

```sh
mix check
```
