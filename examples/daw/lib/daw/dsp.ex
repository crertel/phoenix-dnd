defmodule Daw.Dsp do
  @moduledoc """
  The per-node audio kernels.

  Every kernel is a pure function of `{params, state, inputs}`, which is the
  whole point: the studio's audio behaviour can be tested without starting a
  pipeline, a WebRTC connection, or a browser. `Daw.Engine` is the only thing
  that knows about wall-clock time.

  Blocks are `Daw.Audio` blocks - lists of `{left, right}` float pairs. Kernels
  are free to exceed `-1.0..1.0`; clipping happens once, in `Daw.Audio.to_binary/1`.
  """

  alias Daw.Audio
  alias Daw.Dsp.Line

  @type params :: %{String.t() => term()}
  @type state :: map()
  @type context :: %{mic: Audio.block(), tick: non_neg_integer()}
  @type telemetry :: %{atom() => term()}

  @two_pi 2.0 * :math.pi()

  # Freeverb's tunings, resampled from 44.1 kHz to 48 kHz. The right channel is
  # offset so the tail decorrelates into something vaguely stereo.
  @comb_lengths [1214, 1293, 1390, 1476]
  @allpass_lengths [605, 480]
  @stereo_spread 25

  @doc "The mutable state a node of this kind starts with."
  @spec init(atom(), params()) :: state()
  def init(:tone, _params), do: %{phase: 0.0}
  def init(:noise, _params), do: %{pink: {0.0, 0.0, 0.0}}
  def init(:delay, params), do: %{lines: stereo_lines(delay_samples(params))}
  def init(:lowpass, _params), do: %{last: {0.0, 0.0}}
  def init(:highpass, _params), do: %{last: {0.0, 0.0}, previous: {0.0, 0.0}}
  def init(:tremolo, _params), do: %{phase: 0.0}
  def init(:crusher, _params), do: %{held: {0.0, 0.0}, counter: 0}
  def init(:compressor, _params), do: %{envelope: 0.0, reduction_db: 0.0}
  def init(:reverb, _params), do: %{combs: reverb_combs(), allpasses: reverb_allpasses()}
  def init(:chorus, _params), do: %{history: {[], []}, phase: 0.0}
  def init(_kind, _params), do: %{}

  @doc """
  Renders one tick for one node.

  `inputs` holds the blocks arriving on the node's input port; only a mixer or
  the master bus ever sees more than one. Returns the block every output port
  emits, the next state, and any telemetry the UI should show.
  """
  @spec render(atom(), params(), state(), [Audio.block()], context()) ::
          {Audio.block(), state(), telemetry()}
  def render(kind, params, state, inputs, context)

  def render(:mic, params, state, _inputs, context) do
    block =
      if boolean(params, "mute", false) do
        Audio.silence()
      else
        scale(context.mic, Audio.db_to_amp(number(params, "gain_db", 0.0)))
      end

    {block, state, level(block)}
  end

  def render(:tone, params, state, _inputs, _context) do
    amplitude = Audio.db_to_amp(number(params, "level_db", -14.0))
    waveform = string(params, "waveform", "sine")
    increment = @two_pi * number(params, "freq", 220.0) / Audio.sample_rate()

    {samples, phase} =
      Enum.map_reduce(1..Audio.block_frames(), state.phase, fn _index, phase ->
        {oscillator(waveform, phase) * amplitude, wrap(phase + increment)}
      end)

    block = mono(samples)
    {block, %{state | phase: phase}, level(block)}
  end

  def render(:noise, params, state, _inputs, _context) do
    amplitude = Audio.db_to_amp(number(params, "level_db", -20.0))
    color = string(params, "color", "white")

    {samples, pink} =
      Enum.map_reduce(1..Audio.block_frames(), state.pink, fn _index, pink ->
        white = :rand.uniform() * 2.0 - 1.0

        case color do
          "pink" ->
            {value, pink} = pink_step(white, pink)
            {value * amplitude, pink}

          _white ->
            {white * amplitude, pink}
        end
      end)

    block = mono(samples)
    {block, %{state | pink: pink}, level(block)}
  end

  def render(:gain, params, state, inputs, _context) do
    block =
      if boolean(params, "mute", false) do
        Audio.silence()
      else
        inputs |> sum() |> scale(Audio.db_to_amp(number(params, "gain_db", 0.0)))
      end

    {block, state, level(block)}
  end

  def render(:pan, params, state, inputs, _context) do
    # A balance law, not a pan law: centre is unity and moving the control only
    # ever attenuates the far side. Inserting this node at centre is a no-op,
    # which is a great deal less surprising than a 3 dB dip.
    position = number(params, "pan", 0.0) |> clamp(-1.0, 1.0)
    left_gain = min(1.0, 1.0 - position)
    right_gain = min(1.0, 1.0 + position)

    block =
      inputs
      |> sum()
      |> Enum.map(fn {left, right} -> {left * left_gain, right * right_gain} end)

    {block, state, level(block)}
  end

  def render(:delay, params, state, inputs, _context) do
    block = sum(inputs)
    feedback = number(params, "feedback", 0.35) |> clamp(0.0, 0.95)
    mix = number(params, "mix", 0.35) |> clamp(0.0, 1.0)
    {left_line, right_line} = state.lines
    wanted = delay_samples(params)

    left_line = Line.resize(left_line, wanted)
    right_line = Line.resize(right_line, wanted)
    {left, right} = channels(block)

    echo = fn input, oldest -> {oldest, input + oldest * feedback} end

    {left_wet, left_line} = Line.run(left_line, left, echo)
    {right_wet, right_line} = Line.run(right_line, right, echo)

    block = blend(block, zip(left_wet, right_wet), mix)
    {block, %{state | lines: {left_line, right_line}}, level(block)}
  end

  def render(:lowpass, params, state, inputs, _context) do
    coefficient = one_pole(number(params, "cutoff_hz", 6000.0))
    {block, last} = one_pole_scan(sum(inputs), state.last, coefficient)
    {block, %{state | last: last}, level(block)}
  end

  def render(:highpass, params, state, inputs, _context) do
    block = sum(inputs)
    coefficient = one_pole(number(params, "cutoff_hz", 120.0))
    {lowpassed, last} = one_pole_scan(block, state.last, coefficient)

    block =
      Enum.zip_with(block, lowpassed, fn {left, right}, {low_left, low_right} ->
        {left - low_left, right - low_right}
      end)

    {block, %{state | last: last}, level(block)}
  end

  def render(:tremolo, params, state, inputs, _context) do
    depth = number(params, "depth", 0.6) |> clamp(0.0, 1.0)
    increment = @two_pi * number(params, "rate_hz", 4.5) / Audio.sample_rate()

    {block, phase} =
      Enum.map_reduce(sum(inputs), state.phase, fn {left, right}, phase ->
        factor = 1.0 - depth * (0.5 - 0.5 * :math.cos(phase))
        {{left * factor, right * factor}, wrap(phase + increment)}
      end)

    {block, %{state | phase: phase}, level(block)}
  end

  def render(:drive, params, state, inputs, _context) do
    block = sum(inputs)
    drive = number(params, "drive", 8.0) |> clamp(1.0, 50.0)
    mix = number(params, "mix", 1.0) |> clamp(0.0, 1.0)
    normalise = :math.tanh(drive)

    wet =
      Enum.map(block, fn {left, right} ->
        {:math.tanh(left * drive) / normalise, :math.tanh(right * drive) / normalise}
      end)

    block = blend(block, wet, mix)
    {block, state, level(block)}
  end

  def render(:crusher, params, state, inputs, _context) do
    steps = :math.pow(2.0, round(number(params, "bits", 8.0) |> clamp(2.0, 16.0)) - 1)
    hold = round(number(params, "hold", 4.0) |> clamp(1.0, 32.0))

    {block, {held, counter}} =
      Enum.map_reduce(sum(inputs), {state.held, state.counter}, fn frame, {held, counter} ->
        if rem(counter, hold) == 0 do
          {left, right} = frame
          quantised = {quantise(left, steps), quantise(right, steps)}
          {quantised, {quantised, counter + 1}}
        else
          {held, {held, counter + 1}}
        end
      end)

    {block, %{state | held: held, counter: counter}, level(block)}
  end

  def render(:compressor, params, state, inputs, _context) do
    block = sum(inputs)
    threshold = number(params, "threshold_db", -18.0)
    ratio = number(params, "ratio", 4.0) |> clamp(1.0, 20.0)
    makeup = Audio.db_to_amp(number(params, "makeup_db", 0.0))
    attack = time_coefficient(number(params, "attack_ms", 10.0))
    release = time_coefficient(number(params, "release_ms", 150.0))

    {block, {envelope, reduction_db}} =
      Enum.map_reduce(block, {state.envelope, 0.0}, fn {left, right}, {envelope, worst} ->
        peak = max(abs(left), abs(right))
        coefficient = if peak > envelope, do: attack, else: release
        envelope = envelope + coefficient * (peak - envelope)

        over = Audio.amp_to_db(envelope) - threshold

        gain_db = if over > 0.0, do: -over * (1.0 - 1.0 / ratio), else: 0.0
        factor = Audio.db_to_amp(gain_db) * makeup

        {{left * factor, right * factor}, {envelope, min(worst, gain_db)}}
      end)

    telemetry = block |> level() |> Map.put(:reduction_db, Float.round(reduction_db, 1))
    {block, %{state | envelope: envelope, reduction_db: reduction_db}, telemetry}
  end

  def render(:reverb, params, state, inputs, _context) do
    block = sum(inputs)
    room = number(params, "room", 0.6) |> clamp(0.0, 1.0)
    damping = number(params, "damping", 0.4) |> clamp(0.0, 1.0)
    mix = number(params, "mix", 0.28) |> clamp(0.0, 1.0)

    feedback = room * 0.28 + 0.7
    damp = damping * 0.4

    {left, right} = channels(block)
    {left_wet, combs_left, allpasses_left} = reverb_channel(left, state, :left, feedback, damp)

    {right_wet, combs_right, allpasses_right} =
      reverb_channel(right, state, :right, feedback, damp)

    state = %{
      state
      | combs: %{left: combs_left, right: combs_right},
        allpasses: %{left: allpasses_left, right: allpasses_right}
    }

    block = blend(block, zip(left_wet, right_wet), mix)
    {block, state, level(block)}
  end

  def render(:chorus, params, state, inputs, _context) do
    block = sum(inputs)
    depth = number(params, "depth_ms", 6.0) |> clamp(1.0, 20.0)
    mix = number(params, "mix", 0.4) |> clamp(0.0, 1.0)
    increment = @two_pi * number(params, "rate_hz", 0.8) / Audio.sample_rate()

    {left, right} = channels(block)
    {left_history, right_history} = state.history

    # A tuple gives O(1) fractional taps; the history list is only rebuilt once
    # per block, which keeps the modulated read cheap.
    {left_wet, phase} = chorus_channel(left, left_history, state.phase, increment, depth, 0.0)

    {right_wet, _phase} =
      chorus_channel(right, right_history, state.phase, increment, depth, :math.pi() / 2.0)

    history = {push_history(left_history, left), push_history(right_history, right)}
    block = blend(block, zip(left_wet, right_wet), mix)
    {block, %{state | history: history, phase: phase}, level(block)}
  end

  def render(:mixer, params, state, inputs, _context) do
    block = inputs |> sum() |> scale(Audio.db_to_amp(number(params, "level_db", 0.0)))
    telemetry = block |> level() |> Map.put(:sources, length(inputs))
    {block, state, telemetry}
  end

  def render(:split, _params, state, inputs, _context) do
    block = sum(inputs)
    {block, state, level(block)}
  end

  def render(:meter, _params, state, inputs, _context) do
    block = sum(inputs)
    {block, state, level(block)}
  end

  # A recorder consumes audio and emits nothing; the block it returns is what
  # Daw.Engine forwards to the recorder's Membrane child.
  def render(:recorder, _params, state, inputs, _context) do
    block = sum(inputs)
    {block, state, level(block)}
  end

  def render(:master, params, state, inputs, _context) do
    block =
      if boolean(params, "mute", false) do
        Audio.silence()
      else
        inputs |> sum() |> scale(Audio.db_to_amp(number(params, "level_db", -3.0)))
      end

    {block, state, level(block)}
  end

  def render(kind, _params, _state, _inputs, _context) do
    raise ArgumentError, "no audio kernel for node kind #{inspect(kind)}"
  end

  @doc "Sums any number of blocks, returning silence when there are none."
  @spec sum([Audio.block()]) :: Audio.block()
  def sum([]), do: Audio.silence()
  def sum([block]), do: block

  def sum([first | rest]) do
    Enum.reduce(rest, first, fn block, acc ->
      Enum.zip_with(acc, block, fn {left, right}, {other_left, other_right} ->
        {left + other_left, right + other_right}
      end)
    end)
  end

  @doc "Peak and RMS of a block, rounded for display."
  @spec level(Audio.block()) :: telemetry()
  def level(block) do
    %{
      peak: Float.round(Audio.peak(block), 4),
      rms_db: Float.round(Audio.rms(block) |> Audio.amp_to_db(), 1)
    }
  end

  defp scale(block, 1.0), do: block

  defp scale(block, factor) do
    Enum.map(block, fn {left, right} -> {left * factor, right * factor} end)
  end

  defp blend(dry, _wet, +0.0), do: dry

  defp blend(dry, wet, mix) do
    Enum.zip_with(dry, wet, fn {left, right}, {wet_left, wet_right} ->
      {left * (1.0 - mix) + wet_left * mix, right * (1.0 - mix) + wet_right * mix}
    end)
  end

  defp mono(samples), do: Enum.map(samples, &{&1, &1})

  defp channels(block), do: {Enum.map(block, &elem(&1, 0)), Enum.map(block, &elem(&1, 1))}

  defp zip(left, right), do: Enum.zip_with(left, right, &{&1, &2})

  defp oscillator("sine", phase), do: :math.sin(phase)
  defp oscillator("square", phase), do: if(phase < :math.pi(), do: 1.0, else: -1.0)
  defp oscillator("saw", phase), do: phase / :math.pi() - 1.0

  defp oscillator("triangle", phase) do
    normalised = phase / :math.pi()
    if normalised < 1.0, do: 2.0 * normalised - 1.0, else: 3.0 - 2.0 * normalised
  end

  defp oscillator(_unknown, phase), do: :math.sin(phase)

  defp wrap(phase) when phase >= @two_pi, do: phase - @two_pi
  defp wrap(phase), do: phase

  # Paul Kellet's economy pink filter: three one-poles summed with the raw
  # white noise, which tracks -3 dB/octave closely enough to hear.
  defp pink_step(white, {b0, b1, b2}) do
    b0 = 0.99765 * b0 + white * 0.0990460
    b1 = 0.96300 * b1 + white * 0.2965164
    b2 = 0.57000 * b2 + white * 1.0526913
    {(b0 + b1 + b2 + white * 0.1848) * 0.11, {b0, b1, b2}}
  end

  defp one_pole(cutoff_hz) do
    cutoff = clamp(cutoff_hz, 10.0, Audio.sample_rate() / 2.2)
    1.0 - :math.exp(-@two_pi * cutoff / Audio.sample_rate())
  end

  defp one_pole_scan(block, last, coefficient) do
    Enum.map_reduce(block, last, fn {left, right}, {last_left, last_right} ->
      next_left = last_left + coefficient * (left - last_left)
      next_right = last_right + coefficient * (right - last_right)
      {{next_left, next_right}, {next_left, next_right}}
    end)
  end

  defp quantise(sample, steps), do: Float.round(sample * steps) / steps

  defp time_coefficient(milliseconds) do
    seconds = max(milliseconds, 0.1) / 1000.0
    1.0 - :math.exp(-1.0 / (seconds * Audio.sample_rate()))
  end

  defp delay_samples(params) do
    milliseconds = number(params, "time_ms", 260.0) |> clamp(10.0, 1000.0)
    max(round(milliseconds * Audio.sample_rate() / 1000.0), 1)
  end

  defp stereo_lines(length), do: {Line.new(length), Line.new(length)}

  defp reverb_combs do
    %{
      left: Enum.map(@comb_lengths, &Line.new/1),
      right: Enum.map(@comb_lengths, &Line.new(&1 + @stereo_spread))
    }
  end

  defp reverb_allpasses do
    %{
      left: Enum.map(@allpass_lengths, &Line.new/1),
      right: Enum.map(@allpass_lengths, &Line.new(&1 + @stereo_spread))
    }
  end

  defp reverb_channel(samples, state, side, feedback, damp) do
    combs = Map.fetch!(state.combs, side)
    allpasses = Map.fetch!(state.allpasses, side)

    # Combs run in parallel and are summed; allpasses run in series to smear
    # the result into something that does not ring.
    {summed, combs} =
      Enum.map_reduce(combs, [], fn line, acc ->
        {wet, line, _damped} =
          Line.run(line, samples, 0.0, fn input, oldest, damped ->
            damped = oldest * (1.0 - damp) + damped * damp
            {oldest, input + damped * feedback, damped}
          end)

        {wet, [line | acc]}
      end)
      |> then(fn {wets, combs} -> {sum_channels(wets), Enum.reverse(combs)} end)

    {wet, allpasses} =
      Enum.reduce(allpasses, {summed, []}, fn line, {signal, acc} ->
        {out, line} =
          Line.run(line, signal, fn input, oldest ->
            {oldest - input, input + oldest * 0.5}
          end)

        {out, [line | acc]}
      end)

    {Enum.map(wet, &(&1 * 0.25)), combs, Enum.reverse(allpasses)}
  end

  defp sum_channels([first | rest]) do
    Enum.reduce(rest, first, fn channel, acc -> Enum.zip_with(acc, channel, &(&1 + &2)) end)
  end

  @chorus_history_samples 2048

  defp chorus_channel(samples, history, phase, increment, depth_ms, phase_offset) do
    taps = List.to_tuple(history)
    size = tuple_size(taps)
    base = 0.006 * Audio.sample_rate()
    swing = depth_ms / 1000.0 * Audio.sample_rate() / 2.0

    Enum.map_reduce(samples, phase, fn _sample, phase ->
      offset = base + swing * (1.0 + :math.sin(phase + phase_offset))
      {tap(taps, size, offset), wrap(phase + increment)}
    end)
  end

  # `history` is newest-first, so index 0 is the previous sample.
  defp tap(_taps, 0, _offset), do: 0.0

  defp tap(taps, size, offset) do
    index = trunc(offset)
    fraction = offset - index

    cond do
      index + 1 >= size -> 0.0
      true -> elem(taps, index) * (1.0 - fraction) + elem(taps, index + 1) * fraction
    end
  end

  defp push_history(history, samples) do
    samples
    |> Enum.reverse()
    |> Kernel.++(history)
    |> Enum.take(@chorus_history_samples)
  end

  defp number(params, key, default) do
    case Map.get(params, key, default) do
      value when is_number(value) -> value / 1.0
      _other -> default / 1.0
    end
  end

  defp boolean(params, key, default) do
    case Map.get(params, key, default) do
      value when is_boolean(value) -> value
      _other -> default
    end
  end

  defp string(params, key, default) do
    case Map.get(params, key, default) do
      value when is_binary(value) -> value
      _other -> default
    end
  end

  defp clamp(value, low, high), do: value |> max(low) |> min(high)
end
