# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog], and this project follows
[Semantic Versioning].

## [Unreleased]

### Added

- A stateful, server-authoritative `PhoenixDnd.Editor` LiveComponent that
  renders complete, revisioned scene snapshots while keeping active gestures
  transient in the browser.
- Validated scene models for nodes, ports, edges, selection, and viewport
  state, including opaque server-side node data and customizable node slots.
- Direct-manipulation panning, cursor-centered zoom, click and lasso selection,
  multi-node dragging, connection previews and creation, edge selection, and
  keyboard cancellation and deletion.
- A versioned semantic intent protocol with optimistic interaction receipts,
  authoritative accept/reject resolution, and stale-revision context.
- Ordered, revision-gated server command batches for viewport changes,
  interaction cancellation, and optimistic-operation resolution.
- Namespaced colocated hook and CSS manifests, with prebuilt JavaScript and CSS
  fallbacks for asset pipelines that cannot consume colocated assets.
- A standalone Phoenix demo with rich node rendering, live transient telemetry,
  runtime node creation and removal, graph validation, and server-triggered
  viewport controls.
- A second example application wiring the editor to Membrane: a WebRTC audio
  studio whose node graph is a live DSP pipeline, with server-side accept and
  reject decisions that reflect what the audio graph can actually perform.
- Hex package metadata, an MIT license, a Nix development flake, and automated
  Elixir and JavaScript test suites.

[Unreleased]: https://github.com/crertel/phoenix-dnd/commits/master
[Keep a Changelog]: https://keepachangelog.com/en/1.1.0/
[Semantic Versioning]: https://semver.org/spec/v2.0.0.html
