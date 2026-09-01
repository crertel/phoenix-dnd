defmodule Daw.Pipeline do
  @moduledoc """
  The studio's Membrane pipeline.

  The spine is fixed and outlives every graph edit:

      Engine -> Opus.Encoder -> WebRTC.Sink

  Note what is *not* in that spine. An earlier version linked the microphone
  into it directly, which meant the engine had a static input pad, which meant
  the pipeline could not reach `playing` until a browser had granted microphone
  permission and completed a peer connection. Until then nothing ran: no audio,
  no meters, and every graph edit looked like it had been ignored.

  So the microphone links itself in later. `Membrane.WebRTC.Source` announces
  its tracks with a `:new_tracks` notification, and only then is a decoder
  spawned and attached to a dynamic engine input pad. The studio runs from the
  moment the page loads, with or without a microphone, and picks one up if it
  arrives.

  Recorders work the same way: adding a Recorder node spawns a `Daw.WavSink`
  bound to a fresh `:tap` pad, and removing the node tears that child down.
  """

  use Membrane.Pipeline

  require Membrane.Logger

  alias Daw.{Audio, Engine, WavSink}
  alias Membrane.WebRTC

  @impl true
  def handle_init(_ctx, opts) do
    spec = [
      child(:engine, %Engine{plan: opts[:plan]})
      |> child(:encoder, %Membrane.Opus.Encoder{
        application: :audio,
        input_stream_format: Audio.format()
      })
      |> via_in(:input, options: [kind: :audio])
      |> child(:sink, %WebRTC.Sink{
        signaling: opts[:player_signaling],
        tracks: [:audio],
        video_codec: []
      }),

      # Unlinked on purpose: see the moduledoc. This negotiates in the
      # background and reports its tracks when the browser sends them.
      child(:mic_source, %WebRTC.Source{
        signaling: opts[:capture_signaling],
        allowed_video_codecs: []
      })
    ]

    {[spec: spec],
     %{owner: opts[:owner], recorders: MapSet.new(), recording_dir: opts[:recording_dir]}}
  end

  @doc "Sends a freshly compiled plan to the running engine."
  @spec update_plan(pid(), map()) :: :ok
  def update_plan(pipeline, plan) do
    send(pipeline, {:plan, plan})
    :ok
  end

  @doc "Reconciles recorder children against the plan's tap list."
  @spec sync_recorders(pid(), [String.t()]) :: :ok
  def sync_recorders(pipeline, tap_ids) do
    send(pipeline, {:sync_recorders, tap_ids})
    :ok
  end

  @impl true
  def handle_info({:plan, plan}, _ctx, state) do
    {[notify_child: {:engine, {:plan, plan}}], state}
  end

  def handle_info({:sync_recorders, tap_ids}, _ctx, state) do
    wanted = MapSet.new(tap_ids)
    added = MapSet.difference(wanted, state.recorders)
    removed = MapSet.difference(state.recorders, wanted)

    spec =
      for id <- added do
        get_child(:engine)
        |> via_out(Pad.ref(:tap, id))
        |> child({:recorder, id}, %WavSink{path: recording_path(state.recording_dir, id)})
      end

    actions =
      case Enum.to_list(removed) do
        [] -> []
        ids -> [remove_children: Enum.map(ids, &{:recorder, &1})]
      end

    actions = if spec == [], do: actions, else: [{:spec, spec} | actions]

    {actions, %{state | recorders: wanted}}
  end

  @impl true
  def handle_child_notification({:telemetry, telemetry}, :engine, _ctx, state) do
    send(state.owner, {:daw_telemetry, telemetry})
    {[], state}
  end

  def handle_child_notification({:new_tracks, tracks}, :mic_source, _ctx, state) do
    spec =
      for %{kind: :audio, id: id} <- tracks do
        get_child(:mic_source)
        |> via_out(Pad.ref(:output, id))
        |> child({:mic_decoder, id}, %Membrane.Opus.Decoder{sample_rate: Audio.sample_rate()})
        |> via_in(Pad.ref(:input, id))
        |> get_child(:engine)
      end

    Membrane.Logger.info("microphone tracks arrived: #{inspect(tracks)}")
    send(state.owner, {:daw_mic, :connected})

    {[spec: spec], state}
  end

  def handle_child_notification(notification, child, _ctx, state) do
    Membrane.Logger.debug("#{inspect(child)} said #{inspect(notification)}")
    {[], state}
  end

  defp recording_path(dir, id), do: Path.join(dir, "#{id}.wav")
end
