defmodule Daw.EngineTest do
  @moduledoc """
  Exercises the engine as a real Membrane element rather than as a function,
  so the pad, timer, and plan-update contracts are covered too.
  """

  use ExUnit.Case, async: false

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Daw.{Audio, Engine, Graph, Palette}
  alias Membrane.Testing
  alias PhoenixDnd.{Intent, Scene}

  @timeout 5_000

  # Order is passed explicitly: a plan's evaluation order is topological, and
  # deriving it from Map.keys/1 here would quietly evaluate a bus before its
  # sources and test nothing at all.
  defp plan(order, nodes, inbound, master, taps \\ []) do
    %{
      order: order,
      nodes: nodes,
      inbound: inbound,
      taps: taps,
      master: master
    }
  end

  defp tone_plan(level_db) do
    plan(
      ["tone", "master"],
      %{
        "tone" => %{
          kind: :tone,
          params: Map.merge(Palette.defaults(:tone), %{"level_db" => level_db, "freq" => 440.0})
        },
        "master" => %{
          kind: :master,
          params: Map.merge(Palette.defaults(:master), %{"level_db" => 0.0})
        }
      },
      %{"tone" => [], "master" => [{"tone", "out"}]},
      "master"
    )
  end

  defp start(plan, mic_payloads \\ []) do
    Testing.Pipeline.start_link_supervised!(
      spec: [
        child(:source, %Testing.Source{
          output: mic_payloads ++ [<<>>],
          stream_format: Audio.format()
        })
        |> child(:engine, %Engine{plan: plan})
        |> child(:sink, Testing.Sink)
      ]
    )
  end

  defp peak_of(payload), do: payload |> Audio.from_binary() |> Audio.peak()

  # Loudest master block seen over a short run, which lets sources with a slow
  # attack (reverb, noise) settle.
  defp master_peak(plan) do
    pipeline = start(plan)

    peak =
      Enum.reduce(1..15, 0.0, fn _tick, peak ->
        assert_sink_buffer(pipeline, :sink, buffer, @timeout)
        max(peak, peak_of(buffer.payload))
      end)

    Testing.Pipeline.terminate(pipeline)
    peak
  end

  test "emits one full block per tick even with no input at all" do
    pipeline = start(tone_plan(-6.0))

    assert_sink_stream_format(pipeline, :sink, %Membrane.RawAudio{
      channels: 2,
      sample_rate: 48_000
    })

    assert_sink_buffer(pipeline, :sink, buffer, @timeout)
    assert byte_size(buffer.payload) == Audio.block_bytes()

    Testing.Pipeline.terminate(pipeline)
  end

  test "renders the graph, so a louder oscillator produces a louder block" do
    quiet = start(tone_plan(-40.0))
    assert_sink_buffer(quiet, :sink, quiet_buffer, @timeout)
    Testing.Pipeline.terminate(quiet)

    loud = start(tone_plan(-6.0))
    assert_sink_buffer(loud, :sink, loud_buffer, @timeout)
    Testing.Pipeline.terminate(loud)

    assert peak_of(loud_buffer.payload) > peak_of(quiet_buffer.payload) * 10
  end

  test "timestamps advance by exactly one block per buffer" do
    pipeline = start(tone_plan(-6.0))

    assert_sink_buffer(pipeline, :sink, first, @timeout)
    assert_sink_buffer(pipeline, :sink, second, @timeout)

    expected = Membrane.Time.seconds(Audio.block_frames()) |> div(Audio.sample_rate())
    assert second.pts - first.pts == expected

    Testing.Pipeline.terminate(pipeline)
  end

  test "a plan with no master bus emits silence rather than failing" do
    pipeline = start(plan([], %{}, %{}, nil))

    assert_sink_buffer(pipeline, :sink, buffer, @timeout)
    assert peak_of(buffer.payload) == 0.0

    Testing.Pipeline.terminate(pipeline)
  end

  test "swapping the plan at runtime changes the audio without restarting" do
    pipeline = start(tone_plan(-40.0))

    assert_sink_buffer(pipeline, :sink, before, @timeout)
    assert peak_of(before.payload) < 0.05

    Testing.Pipeline.execute_actions(pipeline, notify_child: {:engine, {:plan, tone_plan(0.0)}})

    # The change lands on a later tick; find the first block that reflects it.
    assert eventually_loud?(pipeline), "expected the new plan to take effect"

    Testing.Pipeline.terminate(pipeline)
  end

  test "a source patched into the mixer reaches the master bus" do
    # Reproduces the reported scenario exactly: add a Noise node, patch it into
    # the Mixer, and confirm the master bus gets louder. This was inaudible in
    # the browser for an unrelated reason, so it is worth pinning server-side.
    scene = Graph.initial_scene()

    quiet = master_peak(Graph.compile(scene))

    {:ok, changes, noise_id} = Graph.add_node(scene, :noise)
    scene = Scene.bump(scene, changes)

    {:ok, changes} = Graph.set_param(scene, noise_id, "level_db", 0.0)
    scene = Scene.bump(scene, changes)

    {:ok, changes} =
      Graph.apply_intent(
        scene,
        Intent.parse!(%{
          "v" => 1,
          "client_id" => "test-client",
          "intent_id" => "intent-1",
          "type" => "connection.create",
          "phase" => "commit",
          "base_revision" => scene.revision,
          "payload" => %{
            "source" => %{"node_id" => noise_id, "port_id" => "out"},
            "target" => %{"node_id" => "bus", "port_id" => "in"}
          }
        })
      )

    plan = Scene.bump(scene, changes) |> Graph.compile()

    assert Enum.any?(plan.inbound["bus"], fn {id, _port} -> id == noise_id end)

    assert master_peak(plan) > quiet * 2,
           "noise patched into the mixer must raise the master level"
  end

  test "the master bus honours its own fader and mute" do
    scene = Graph.initial_scene()

    {:ok, changes} = Graph.set_param(scene, "master", "level_db", 0.0)
    loud = Scene.bump(scene, changes) |> Graph.compile() |> master_peak()

    {:ok, changes} = Graph.set_param(scene, "master", "level_db", -40.0)
    quiet = Scene.bump(scene, changes) |> Graph.compile() |> master_peak()

    {:ok, changes} = Graph.set_param(scene, "master", "mute", true)
    muted = Scene.bump(scene, changes) |> Graph.compile() |> master_peak()

    assert quiet < loud / 10, "the master fader must attenuate"
    assert muted == 0.0, "master mute must silence the bus"
  end

  test "runs the scene the editor actually starts with" do
    pipeline = start(Graph.compile(Graph.initial_scene()))

    assert_sink_buffer(pipeline, :sink, buffer, @timeout)
    assert byte_size(buffer.payload) == Audio.block_bytes()

    Testing.Pipeline.terminate(pipeline)
  end

  test "reports telemetry for every node in the plan" do
    pipeline = start(tone_plan(-6.0))

    assert_pipeline_notified(pipeline, :engine, {:telemetry, telemetry}, @timeout)
    assert Map.keys(telemetry) |> Enum.sort() == ["master", "tone"]
    assert telemetry["tone"].peak > 0.0

    Testing.Pipeline.terminate(pipeline)
  end

  test "mixes microphone audio into the graph" do
    mic = List.duplicate(Audio.to_binary(List.duplicate({0.5, 0.5}, Audio.block_frames())), 10)

    mic_plan =
      plan(
        ["mic", "master"],
        %{
          "mic" => %{kind: :mic, params: Palette.defaults(:mic)},
          "master" => %{
            kind: :master,
            params: Map.merge(Palette.defaults(:master), %{"level_db" => 0.0})
          }
        },
        %{"mic" => [], "master" => [{"mic", "out"}]},
        "master"
      )

    pipeline = start(mic_plan, mic)

    assert eventually_loud?(pipeline), "expected microphone audio to reach the master bus"

    Testing.Pipeline.terminate(pipeline)
  end

  defp eventually_loud?(pipeline, attempts \\ 25)
  defp eventually_loud?(_pipeline, 0), do: false

  defp eventually_loud?(pipeline, attempts) do
    assert_sink_buffer(pipeline, :sink, buffer, @timeout)

    if peak_of(buffer.payload) > 0.2 do
      true
    else
      eventually_loud?(pipeline, attempts - 1)
    end
  end
end
