# phoenix-dnd

A server-authoritative node editor for Phoenix LiveView, with focused
client-side JavaScript for direct-manipulation interactions such as pan, zoom,
selection, node dragging, and connection previews.

The package is in early development and has not yet been released to Hex.

## Demo application

A standalone Phoenix application lives in [`examples/demo`](examples/demo).
It uses this repository as a path dependency and includes a five-node workflow,
custom node rendering, the authoritative intent reducer, and server-triggered
viewport controls.

```sh
nix develop
cd examples/demo
mix setup
mix phx.server
```

Visit <http://localhost:4000>. The demo uses native ESM and intentionally has
no separate npm or asset-build step.

## Installation

For local development, add the repository as a path dependency:

```elixir
def deps do
  [
    {:phoenix_dnd, path: "../phoenix-dnd"}
  ]
end
```

Once published, use the Hex package instead:

```elixir
{:phoenix_dnd, "~> 0.1"}
```

Import the component's colocated hook manifest in `assets/js/app.js` and merge
its named `hooks` export into the hooks passed to `LiveSocket`:

```javascript
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as phoenixDndHooks} from "phoenix-colocated/phoenix_dnd"

const appHooks = {}

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: {...phoenixDndHooks, ...appHooks}
})
```

`PhoenixDnd.Editor` declares its namespaced hook with
[`Phoenix.LiveView.ColocatedHook`](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.ColocatedHook.html).
The package keeps the substantial interaction runtime in its prebuilt,
independently tested JavaScript module; the colocated manifest is a small
adapter generated when the dependency compiles. Phoenix 1.8's default esbuild
configuration resolves both `deps` and the Mix build path. If your asset
pipeline is customized, make sure both are resolvable and run `mix compile`
before bundling assets.

Import the library CSS from `assets/css/app.css`. Use the dependency-relative
path because Phoenix's default Tailwind task does not add `deps` as a package
search path:

```css
@import "../../deps/phoenix_dnd/priv/static/phoenix_dnd.css";
```

For a pipeline that cannot consume colocated manifests, import the fallback
hook map directly from
`phoenix_dnd/priv/static/phoenix_dnd.js` (or its relative path under `deps`).
It exposes the same fully qualified hook name.

## Rendering an editor

Build a complete `%PhoenixDnd.Scene{}` on the server and pass it to the
stateful `PhoenixDnd.Editor`. The node slot receives the opaque node and its
authoritative selection state; `node.data` is not serialized unless the slot
renders it.

```elixir
alias PhoenixDnd.{Node, Port, Scene}

scene =
  Scene.new!(
    nodes: [
      Node.new!("source",
        position: %{x: 80, y: 120},
        label: "Source",
        ports: [Port.output("value", anchor: :right)]
      ),
      Node.new!("sink",
        position: %{x: 420, y: 120},
        label: "Sink",
        ports: [Port.input("value", anchor: :left)]
      )
    ]
  )

socket = assign(socket, :scene, scene)
```

```heex
<.live_component
  module={PhoenixDnd.Editor}
  id="workflow"
  scene={@scene}
  min_zoom={0.2}
  max_zoom={4.0}
>
  <:node :let={%{node: node, selected?: selected?}}>
    <article class={["workflow-node", selected? && "is-selected"]}>
      {node.label}
    </article>
  </:node>
</.live_component>
```

`id` and `scene` are required. The ID must be unique across the whole rendered
document, including nested LiveViews. `notify` may be set to a PID; by default
the component sends intents to its owning LiveView process.

## Accepting user intent

The hook sends semantic intent to the component, which validates its protocol
shape and notifies the owner with:

```elixir
{:phoenix_dnd, :intent, editor_id, %PhoenixDnd.Intent{}}
```

The application still owns authorization and domain validation. Apply an
accepted intent to the current scene, then use `Scene.bump/2` so every accepted
authoritative change advances the scene revision. In this example,
`MyApp.Graph.apply_intent/2` is application code returning scene changes such
as `%{nodes: updated_nodes}`:

```elixir
alias PhoenixDnd.{Command, CommandBatch, Intent, Scene}

def handle_info(
      {:phoenix_dnd, :intent, "workflow", %Intent{} = intent},
      socket
    ) do
  scene = socket.assigns.scene

  case MyApp.Graph.apply_intent(scene, intent) do
    {:ok, changes} ->
      next_scene = Scene.bump(scene, changes)

      batch =
        CommandBatch.new!(
          [Command.operation_resolve(intent.intent_id, :accepted)],
          after_revision: next_scene.revision
        )

      socket =
        socket
        |> assign(:scene, next_scene)
        |> PhoenixDnd.push_commands("workflow", batch)

      {:noreply, socket}

    {:error, reason} ->
      batch =
        CommandBatch.new!(
          [Command.operation_resolve(intent.intent_id, :rejected, reason: reason)],
          after_revision: scene.revision
        )

      {:noreply, PhoenixDnd.push_commands(socket, "workflow", batch)}
  end
end
```

Client payloads remain untrusted even after structural parsing. Validate
permissions, IDs, connection rules, coordinates, and the base revision before
changing application state.

Treat `base_revision` as conflict context, not a universal compare-and-swap.
The hook can pipeline committed gestures before a prior scene patch arrives.
Applications will usually revalidate delete/connection IDs against the current
scene, allow latest-wins selection and viewport changes, and reject a node move
only when relevant graph state changed or the nodes are no longer movable.
`MyApp.Graph.apply_intent/2` is where that domain-specific policy belongs.

Send `operation.resolve` for every accepted or rejected optimistic node,
selection, and viewport intent. Its `after_revision` must identify the scene
snapshot that contains the accepted state (or restores the rejected state).
The component's immediate `received` reply acknowledges transport and schema
validation only; it does not mean the application accepted the change.

Each committed gesture is one intent. In particular, `nodes.move` carries
both `positions` and the complete resulting node/edge `selection`, allowing an
application to apply a drag atomically at one base revision. Click/lasso
selection, connection creation, delete requests, and viewport changes use
their own semantic intent types.

Intent payload maps use string keys:

| `intent.type` | `intent.payload` |
| --- | --- |
| `nodes.move` | `%{"positions" => [%{"id" => id, "x" => x, "y" => y}], "selection" => %{"node_ids" => ids, "edge_ids" => ids}}` |
| `selection.change` | `%{"mode" => mode, "node_ids" => ids, "edge_ids" => ids}` |
| `connection.create` | `%{"source" => %{"node_id" => id, "port_id" => id}, "target" => endpoint}` |
| `delete.request` | `%{"node_ids" => ids, "edge_ids" => ids}` |
| `viewport.change` | `%{"center_x" => x, "center_y" => y, "zoom" => zoom}` |

## Server-to-client commands

Use command batches for imperative, best-effort actions such as fitting or
moving the viewport, cancelling an interaction, or resolving an optimistic
operation:

```elixir
batch =
  PhoenixDnd.CommandBatch.new!(
    [PhoenixDnd.Command.viewport_fit(padding: 64, animate_ms: 180)],
    after_revision: socket.assigns.scene.revision
  )

socket = PhoenixDnd.push_commands(socket, "workflow", batch)
```

`after_revision` gates the batch. The hook filters the shared command event by
editor ID, queues the batch until that scene revision is present in the DOM,
then applies its ordered commands together on an animation frame. Commands are
not durable state: anything needed after reconnect must also be represented in
the next scene snapshot.

## Architecture

The API accepts full scene snapshots, while the transport remains incremental:

- The parent owns the canonical graph and supplies a complete `Scene` with a
  monotonic revision.
- The editor renders nodes and edges with stable keys, so HEEx/LiveView sends
  only changed DOM fragments rather than retransmitting a serialized scene.
- The hook owns only transient, high-frequency interaction state: active
  pointer gestures, wire and lasso previews, hover targets, measured geometry,
  and immediate pan/zoom feedback.
- The hook reports semantic intents. The server accepts or rejects them and
  reconciles the browser by rendering the next authoritative snapshot.
- Revision-gated command batches carry ordered, imperative S->C requests that
  do not belong in durable scene state.

This keeps one durable source of truth without putting pointer-rate updates on
the LiveView connection.

## Development environment

Enter the pinned development shell with `nix develop`. Before the initial
commit, use `nix develop path:.` because Nix ignores untracked flake files.

The shell provides Erlang/OTP 28, Elixir 1.19, Hex, Rebar3, Node.js 24 LTS,
Git, and Linux filesystem watching support. Run the complete Elixir and
JavaScript verification suite with `mix check`; format the Nix configuration
with `nix fmt`.
