defmodule Daw.Engine do
  @moduledoc """
  The Membrane element that runs the user's DSP graph.

  It is the only clock in the studio. Every 20 ms it takes whatever input audio
  has arrived, evaluates the compiled plan from `Daw.Graph.compile/1` in
  topological order, and pushes one block downstream to the Opus encoder.

  Running the graph *inside* one element rather than as a Membrane subgraph is
  deliberate. Re-patching a cable then costs a message, not a pipeline teardown,
  so edits do not interrupt the WebRTC stream or renegotiate anything. Nodes
  that need a real child process - recorders - get one, linked to a dynamic
  `:tap` pad.

  Input pads are dynamic for the same reason the clock is internal: the studio
  has to run before, and without, a microphone. A browser that never grants mic
  permission still hears its oscillators.
  """

  # The input pads are fed by a real-time WebRTC source while the outputs are
  # driven by this element's own 20 ms timer, so mixing :auto and :push is the
  # intent rather than an oversight.
  use Membrane.Filter, flow_control_hints?: false

  require Membrane.Logger

  alias Daw.{Audio, Dsp}
  alias Membrane.{Buffer, RawAudio}

  # The graph is evaluated on a timer, so an input queue only ever needs to
  # cover jitter. Beyond this we drop the oldest audio rather than grow without
  # bound.
  @max_queued_blocks 8
  @telemetry_every_ticks 5

  def_options(
    plan: [
      spec: map(),
      description: "The initial compiled plan from `Daw.Graph.compile/1`."
    ]
  )

  def_input_pad(:input,
    accepted_format: %RawAudio{sample_format: :s16le},
    flow_control: :auto,
    availability: :on_request
  )

  def_output_pad(:output,
    accepted_format: RawAudio,
    flow_control: :push
  )

  def_output_pad(:tap,
    accepted_format: RawAudio,
    flow_control: :push,
    availability: :on_request
  )

  @impl true
  def handle_init(_ctx, %__MODULE__{plan: plan}) do
    {[],
     %{
       plan: plan,
       node_states: init_states(plan, %{}),
       inputs: %{},
       frames: 0,
       tick: 0,
       telemetry: %{}
     }}
  end

  @impl true
  def handle_playing(_ctx, state) do
    interval = Membrane.Time.milliseconds(Audio.tick_ms())

    {[stream_format: {:output, Audio.format()}, start_timer: {:tick, interval}], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:tap, _id) = pad, _ctx, state) do
    {[stream_format: {pad, Audio.format()}], state}
  end

  def handle_pad_added(Pad.ref(:input, _id) = pad, _ctx, state) do
    {[], put_in(state.inputs[pad], %{queue: <<>>, channels: 1})}
  end

  @impl true
  def handle_pad_removed(Pad.ref(:input, _id) = pad, _ctx, state) do
    {[], %{state | inputs: Map.delete(state.inputs, pad)}}
  end

  def handle_pad_removed(_pad, _ctx, state), do: {[], state}

  @impl true
  def handle_stream_format(Pad.ref(:input, _id) = pad, %RawAudio{channels: channels}, _ctx, state) do
    # A track decides its own layout; drop anything queued in the old one rather
    # than reinterpret it and emit a burst of noise.
    {[], put_in(state.inputs[pad], %{queue: <<>>, channels: channels})}
  end

  @impl true
  def handle_buffer(Pad.ref(:input, _id) = pad, buffer, _ctx, state) do
    case Map.fetch(state.inputs, pad) do
      {:ok, input} ->
        limit = @max_queued_blocks * Audio.block_bytes(input.channels)
        queue = trim(input.queue <> buffer.payload, limit)
        {[], put_in(state.inputs[pad], %{input | queue: queue})}

      :error ->
        {[], state}
    end
  end

  @impl true
  def handle_end_of_stream(Pad.ref(:input, _id), _ctx, state) do
    # A Filter forwards end-of-stream downstream by default. Here that would be
    # wrong and fatal: the output is driven by this element's timer, not by the
    # microphone, so a mic track ending - a revoked permission, a dropped peer -
    # must not end the studio's output. Oscillators and reverb tails play on.
    #
    # Whatever is already queued still gets rendered; the track ending means no
    # more audio is coming, not that the last 160 ms should be thrown away.
    {[], state}
  end

  @impl true
  def handle_parent_notification({:plan, plan}, _ctx, state) do
    # Keeping per-node DSP state across a re-plan is what lets a reverb tail
    # survive having a cable moved somewhere else in the graph.
    {[], %{state | plan: plan, node_states: init_states(plan, state.node_states)}}
  end

  def handle_parent_notification(_notification, _ctx, state), do: {[], state}

  @impl true
  def handle_tick(:tick, ctx, state) do
    {mic, inputs} = take_inputs(state.inputs)
    context = %{mic: mic, tick: state.tick}

    {outputs, node_states, telemetry} = run(state.plan, state.node_states, context)

    master = Map.get(outputs, state.plan.master, Audio.silence())
    buffer = %Buffer{payload: Audio.to_binary(master), pts: pts(state.frames)}

    taps =
      for id <- state.plan.taps, Map.has_key?(ctx.pads, Pad.ref(:tap, id)) do
        payload = outputs |> Map.get(id, Audio.silence()) |> Audio.to_binary()
        {:buffer, {Pad.ref(:tap, id), %Buffer{payload: payload, pts: pts(state.frames)}}}
      end

    state = %{
      state
      | inputs: inputs,
        node_states: node_states,
        frames: state.frames + Audio.block_frames(),
        tick: state.tick + 1,
        telemetry: telemetry
    }

    {[{:buffer, {:output, buffer}} | taps] ++ report(state), state}
  end

  defp run(plan, node_states, context) do
    Enum.reduce(evaluation_order(plan), {%{}, node_states, %{}}, fn id,
                                                                    {outputs, states, telemetry} ->
      %{kind: kind, params: params} = Map.fetch!(plan.nodes, id)

      inputs =
        plan.inbound
        |> Map.get(id, [])
        |> Enum.map(fn {source_id, _port} -> Map.get(outputs, source_id) end)
        |> Enum.reject(&is_nil/1)

      node_state = Map.get_lazy(states, id, fn -> Dsp.init(kind, params) end)
      {block, node_state, node_telemetry} = Dsp.render(kind, params, node_state, inputs, context)

      {Map.put(outputs, id, block), Map.put(states, id, node_state),
       Map.put(telemetry, id, node_telemetry)}
    end)
  end

  # A plan should always be a DAG - Daw.Graph refuses to create cycles - but an
  # engine that silently dropped nodes would be a miserable thing to debug.
  defp evaluation_order(plan) do
    plan.order ++ (plan.nodes |> Map.keys() |> Enum.sort() |> Kernel.--(plan.order))
  end

  defp init_states(plan, previous) do
    Map.new(plan.nodes, fn {id, %{kind: kind, params: params}} ->
      case Map.get(previous, id) do
        nil -> {id, Dsp.init(kind, params)}
        existing -> {id, existing}
      end
    end)
  end

  # Every linked input contributes one block, summed. In practice there is one
  # microphone track, but nothing here has to assume that.
  defp take_inputs(inputs) when map_size(inputs) == 0, do: {Audio.silence(), inputs}

  defp take_inputs(inputs) do
    {blocks, inputs} =
      Enum.map_reduce(inputs, inputs, fn {pad, input}, acc ->
        size = Audio.block_bytes(input.channels)

        case input.queue do
          <<block::binary-size(size), rest::binary>> ->
            {Audio.from_binary(block, input.channels), put_in(acc[pad], %{input | queue: rest})}

          _starved ->
            {Audio.silence(), acc}
        end
      end)

    {Dsp.sum(blocks), inputs}
  end

  defp trim(queue, limit) when byte_size(queue) > limit do
    binary_part(queue, byte_size(queue) - limit, limit)
  end

  defp trim(queue, _limit), do: queue

  defp pts(frames), do: Membrane.Time.seconds(frames) |> div(Audio.sample_rate())

  # Metering at tick rate would push 50 messages a second at the LiveView for no
  # visible benefit; 10 Hz is already faster than anyone can read a meter.
  defp report(%{tick: tick, telemetry: telemetry}) when rem(tick, @telemetry_every_ticks) == 0 do
    [notify_parent: {:telemetry, telemetry}]
  end

  defp report(_state), do: []
end
