defmodule Daw.DspTest do
  use ExUnit.Case, async: true

  alias Daw.{Audio, Dsp}

  @context %{mic: Audio.silence(), tick: 0}

  defp render(kind, params, inputs \\ [], state \\ nil) do
    state = state || Dsp.init(kind, params)
    Dsp.render(kind, params, state, inputs, @context)
  end

  defp tone(level_db \\ -6.0) do
    {block, _state, _telemetry} = render(:tone, %{"freq" => 440.0, "level_db" => level_db})
    block
  end

  test "every kernel returns exactly one block per tick" do
    signal = tone()

    for kind <- Daw.Palette.ids() do
      {block, _state, telemetry} = render(kind, Daw.Palette.defaults(kind), [signal])

      assert length(block) == Audio.block_frames(), "#{kind} produced the wrong block length"
      assert is_map(telemetry)
    end
  end

  test "an unpatched effect renders silence rather than crashing" do
    {block, _state, _telemetry} = render(:reverb, Daw.Palette.defaults(:reverb), [])
    assert Audio.peak(block) == 0.0
  end

  describe "levels" do
    test "gain in decibels is applied as amplitude" do
      signal = tone()
      {block, _state, _telemetry} = render(:gain, %{"gain_db" => -6.0}, [signal])
      assert_in_delta Audio.peak(block) / Audio.peak(signal), 0.501, 0.005
    end

    test "mute wins over gain" do
      {block, _state, _telemetry} = render(:gain, %{"gain_db" => 12.0, "mute" => true}, [tone()])
      assert Audio.peak(block) == 0.0
    end

    test "a mixer sums its inputs" do
      signal = tone(-12.0)
      {one, _, _} = render(:mixer, %{"level_db" => 0.0}, [signal])
      {two, _, _} = render(:mixer, %{"level_db" => 0.0}, [signal, signal])
      assert_in_delta Audio.peak(two) / Audio.peak(one), 2.0, 0.001
    end
  end

  describe "pan" do
    test "centre is unity gain on both channels" do
      signal = tone()
      {block, _state, _telemetry} = render(:pan, %{"pan" => 0.0}, [signal])
      assert block == signal
    end

    test "hard left silences the right channel and never boosts the left" do
      signal = tone()
      {block, _state, _telemetry} = render(:pan, %{"pan" => -1.0}, [signal])

      assert block |> Enum.map(&elem(&1, 1)) |> Enum.all?(&(&1 == 0.0))
      assert Audio.peak(block) <= Audio.peak(signal) + 1.0e-9
    end
  end

  describe "the oscillator" do
    test "advances phase across ticks instead of restarting each block" do
      params = %{"freq" => 440.0, "level_db" => 0.0}
      state = Dsp.init(:tone, params)
      {first, state, _} = Dsp.render(:tone, params, state, [], @context)
      {second, _state, _} = Dsp.render(:tone, params, state, [], @context)

      refute first == second
      # A phase-continuous 440 Hz sine has no step at the block boundary.
      {last, _} = List.last(first)
      {next, _} = List.first(second)
      assert abs(next - last) < 0.1
    end

    test "each waveform stays inside unity" do
      for waveform <- ~w(sine square saw triangle) do
        {block, _state, _} =
          render(:tone, %{"waveform" => waveform, "freq" => 300.0, "level_db" => 0.0})

        assert Audio.peak(block) <= 1.0, "#{waveform} exceeded full scale"
        assert Audio.peak(block) > 0.5, "#{waveform} produced nothing"
      end
    end
  end

  describe "the delay" do
    test "holds the dry signal back by the configured time" do
      params = %{"time_ms" => 20.0, "feedback" => 0.0, "mix" => 1.0}
      signal = tone(0.0)
      {first, state, _} = render(:delay, params, [signal])

      # One tick is exactly 20 ms, so the first block is still the empty line.
      assert Audio.peak(first) == 0.0

      {second, _state, _} = Dsp.render(:delay, params, state, [Audio.silence()], @context)
      assert_in_delta Audio.peak(second), Audio.peak(signal), 1.0e-6
    end

    test "decays to silence once the input stops" do
      params = %{"time_ms" => 20.0, "feedback" => 0.5, "mix" => 1.0}
      {_block, state, _} = render(:delay, params, [tone(0.0)])

      final =
        Enum.reduce(1..60, state, fn _tick, state ->
          {_block, state, _} = Dsp.render(:delay, params, state, [Audio.silence()], @context)
          state
        end)

      {tail, _state, _} = Dsp.render(:delay, params, final, [Audio.silence()], @context)
      assert Audio.peak(tail) < 0.001
    end
  end

  describe "the reverb" do
    test "produces a tail after the input stops, and that tail decays" do
      params = %{"room" => 0.7, "damping" => 0.4, "mix" => 1.0}
      {_block, state, _} = render(:reverb, params, [tone(0.0)])

      {early, state} = advance(:reverb, params, state, 5)
      {late, _state} = advance(:reverb, params, state, 150)

      assert early > 0.001, "expected an audible tail"
      assert late < early, "expected the tail to decay"
    end
  end

  describe "the compressor" do
    test "pulls down a signal above the threshold and reports the reduction" do
      params = %{
        "threshold_db" => -30.0,
        "ratio" => 8.0,
        "attack_ms" => 1.0,
        "release_ms" => 50.0,
        "makeup_db" => 0.0
      }

      loud = tone(0.0)
      state = Dsp.init(:compressor, params)

      {block, _state, telemetry} =
        Enum.reduce(1..10, {nil, state, nil}, fn _tick, {_b, state, _t} ->
          Dsp.render(:compressor, params, state, [loud], @context)
        end)

      assert Audio.peak(block) < Audio.peak(loud)
      assert telemetry.reduction_db < 0.0
    end

    test "leaves a quiet signal alone" do
      params = %{"threshold_db" => -6.0, "ratio" => 8.0, "makeup_db" => 0.0}
      quiet = tone(-40.0)
      {block, _state, _} = render(:compressor, params, [quiet])
      assert_in_delta Audio.peak(block), Audio.peak(quiet), 1.0e-6
    end
  end

  describe "the filters" do
    test "a low pass attenuates high frequencies more than low ones" do
      params = %{"cutoff_hz" => 500.0}
      assert through(:lowpass, params, 4000.0) < through(:lowpass, params, 200.0)
    end

    test "a high pass does the opposite" do
      params = %{"cutoff_hz" => 2000.0}
      assert through(:highpass, params, 200.0) < through(:highpass, params, 6000.0)
    end
  end

  describe "conversion" do
    test "survives a round trip through the wire format" do
      signal = tone(-3.0)
      restored = signal |> Audio.to_binary() |> Audio.from_binary()

      assert length(restored) == length(signal)

      for {{left, _}, {restored_left, _}} <- Enum.zip(signal, restored) do
        assert_in_delta left, restored_left, 1.0e-4
      end
    end

    test "widens a mono source to both channels" do
      mono = <<16_000::little-signed-16, -16_000::little-signed-16>>
      assert [{left, left}, {right, right}] = Audio.from_binary(mono, 1)
      assert left > 0.0 and right < 0.0
    end

    test "clips instead of wrapping" do
      hot = List.duplicate({4.0, -4.0}, 4)

      assert <<32_767::little-signed-16, -32_768::little-signed-16, _rest::binary>> =
               Audio.to_binary(hot)
    end

    test "fit/1 pads a starved block and trims an overfull one" do
      assert length(Audio.fit([])) == Audio.block_frames()
      assert length(Audio.fit(List.duplicate({0.1, 0.1}, 5000))) == Audio.block_frames()
    end
  end

  defp advance(kind, params, state, ticks) do
    {peak, state} =
      Enum.reduce(1..ticks, {0.0, state}, fn _tick, {_peak, state} ->
        {block, state, _telemetry} = Dsp.render(kind, params, state, [Audio.silence()], @context)
        {Audio.peak(block), state}
      end)

    {peak, state}
  end

  # Steady-state output level for a sine at the given frequency.
  defp through(kind, params, frequency) do
    tone_params = %{"freq" => frequency, "level_db" => 0.0}
    tone_state = Dsp.init(:tone, tone_params)
    state = Dsp.init(kind, params)

    {peak, _tone_state, _state} =
      Enum.reduce(1..12, {0.0, tone_state, state}, fn _tick, {_peak, tone_state, state} ->
        {signal, tone_state, _} = Dsp.render(:tone, tone_params, tone_state, [], @context)
        {block, state, _} = Dsp.render(kind, params, state, [signal], @context)
        {Audio.peak(block), tone_state, state}
      end)

    peak
  end
end
