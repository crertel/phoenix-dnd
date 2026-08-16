# phoenix-dnd

A reusable drag-and-drop component for Phoenix LiveView, with as little
client-side JavaScript as the browser interaction permits.

## Development environment

Enter the pinned development shell:

```sh
nix develop
```

Nix ignores untracked files when it treats the working tree as a Git flake.
Before the initial commit, either stage `flake.nix` and `flake.lock` or enter
the shell directly from the working tree:

```sh
nix develop path:.
```

The shell provides Erlang/OTP 28, Elixir 1.19, Hex, Rebar3, Node.js 24 LTS,
Git, and Linux filesystem watching support. Node is included for the small
LiveView hook and its tests; the shell does not assume a JavaScript framework
or a Phoenix application database.

Format the Nix configuration with:

```sh
nix fmt
```
