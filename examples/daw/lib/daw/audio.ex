defmodule Daw.Audio do
  @moduledoc """
  The single audio format the studio operates on, and conversions to and from
  the interleaved binaries Membrane carries.

  Everything between the Opus decoder and the Opus encoder is 48 kHz stereo.
  Inside the DSP graph a *block* is one tick worth of audio represented as a
  list of `{left, right}` float pairs nominally in `-1.0..1.0`. Floats keep the
  per-node kernels in `Daw.Dsp` readable and let intermediate stages clip only
  where a real console would.
  """

  @sample_rate 48_000
  @channels 2
  @tick_ms 20
  @block_frames div(@sample_rate * @tick_ms, 1000)
  @sample_max 32_767
  @sample_min -32_768

  @type sample :: float()
  @type frame :: {sample(), sample()}
  @type block :: [frame()]

  @spec sample_rate() :: pos_integer()
  def sample_rate, do: @sample_rate

  @spec channels() :: pos_integer()
  def channels, do: @channels

  @spec tick_ms() :: pos_integer()
  def tick_ms, do: @tick_ms

  @doc "Frames rendered per engine tick."
  @spec block_frames() :: pos_integer()
  def block_frames, do: @block_frames

  @doc "Bytes in one interleaved s16le block at the given channel count."
  @spec block_bytes(pos_integer()) :: pos_integer()
  def block_bytes(channels \\ @channels), do: @block_frames * channels * 2

  @spec format() :: Membrane.RawAudio.t()
  def format do
    %Membrane.RawAudio{
      sample_rate: @sample_rate,
      channels: @channels,
      sample_format: :s16le
    }
  end

  @doc "A block of digital silence."
  @spec silence() :: block()
  def silence, do: List.duplicate({0.0, 0.0}, @block_frames)

  @doc """
  Decodes an interleaved s16le binary into a block.

  A mono source - which is what a browser microphone almost always is after
  Opus decoding - is widened by copying the sample to both channels, so the
  rest of the graph only ever deals with one layout.
  """
  @spec from_binary(binary(), pos_integer()) :: block()
  def from_binary(binary, channels \\ @channels)

  def from_binary(binary, 1) when is_binary(binary) do
    for <<sample::little-signed-16 <- binary>> do
      value = sample / @sample_max
      {value, value}
    end
  end

  def from_binary(binary, _channels) when is_binary(binary) do
    for <<left::little-signed-16, right::little-signed-16 <- binary>> do
      {left / @sample_max, right / @sample_max}
    end
  end

  @doc """
  Encodes a block back to interleaved s16le, clipping to the representable
  range. This is the only place samples are hard-limited.
  """
  @spec to_binary(block()) :: binary()
  def to_binary(block) when is_list(block) do
    for {left, right} <- block, into: <<>> do
      <<clamp(left)::little-signed-16, clamp(right)::little-signed-16>>
    end
  end

  @doc """
  Returns exactly `block_frames/0` frames, padding the tail with silence when
  the queue has starved. Under-runs are normal right after a graph edit.
  """
  @spec fit(block()) :: block()
  def fit(block) when is_list(block) do
    case length(block) do
      @block_frames -> block
      size when size > @block_frames -> Enum.take(block, @block_frames)
      size -> block ++ List.duplicate({0.0, 0.0}, @block_frames - size)
    end
  end

  @doc "Peak absolute sample in a block, used for the level meters."
  @spec peak(block()) :: float()
  def peak([]), do: 0.0

  def peak(block) do
    Enum.reduce(block, 0.0, fn {left, right}, peak ->
      peak |> max(abs(left)) |> max(abs(right))
    end)
  end

  @doc "Root-mean-square level of a block, used for the level meters."
  @spec rms(block()) :: float()
  def rms([]), do: 0.0

  def rms(block) do
    sum =
      Enum.reduce(block, 0.0, fn {left, right}, sum ->
        sum + left * left + right * right
      end)

    :math.sqrt(sum / (length(block) * 2))
  end

  @doc "Converts decibels to a linear amplitude factor."
  @spec db_to_amp(number()) :: float()
  def db_to_amp(db) when db <= -60, do: 0.0
  def db_to_amp(db), do: :math.pow(10.0, db / 20.0)

  @doc "Converts a linear amplitude factor to decibels, floored at -60 dB."
  @spec amp_to_db(number()) :: float()
  def amp_to_db(amp) when amp <= 0.001, do: -60.0
  def amp_to_db(amp), do: 20.0 * :math.log10(amp)

  defp clamp(sample) do
    sample
    |> Kernel.*(@sample_max)
    |> round()
    |> min(@sample_max)
    |> max(@sample_min)
  end
end
