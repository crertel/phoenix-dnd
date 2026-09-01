defmodule Daw.Dsp.Line do
  @moduledoc """
  A fixed-length delay line.

  Backed by `:queue`, so reading the oldest sample and writing a new one are
  both amortised constant time and no stage ever needs random access into the
  buffer. That matters: reverb runs six of these per channel and the whole
  graph has a 20 ms budget per tick.

  Every kernel that needs a delay line is expressible as "pop the oldest
  sample, compute, push one sample", which is what `step/3` encodes.
  """

  @enforce_keys [:queue, :length]
  defstruct [:queue, :length]

  @type t :: %__MODULE__{queue: :queue.queue(float()), length: pos_integer()}

  @doc "A line of `length` samples, pre-filled with silence."
  @spec new(pos_integer()) :: t()
  def new(length) when is_integer(length) and length > 0 do
    %__MODULE__{queue: :queue.from_list(List.duplicate(0.0, length)), length: length}
  end

  @doc """
  Resizes the line, keeping the most recent samples.

  Changing a delay time mid-stream is audible, exactly as it is on a hardware
  delay. We choose the click over the complexity of crossfading two lines.
  """
  @spec resize(t(), pos_integer()) :: t()
  def resize(%__MODULE__{length: length} = line, length), do: line

  def resize(%__MODULE__{} = line, length) when is_integer(length) and length > 0 do
    samples = :queue.to_list(line.queue)

    samples =
      case length - line.length do
        grow when grow > 0 -> List.duplicate(0.0, grow) ++ samples
        shrink -> Enum.drop(samples, -shrink)
      end

    %__MODULE__{queue: :queue.from_list(samples), length: length}
  end

  @doc """
  Runs one sample through the line.

  `fun` receives the oldest sample and returns `{emitted, written}` - what the
  stage outputs, and what goes back into the line. Splitting those two lets a
  comb filter feed back and an allpass invert without either knowing about the
  queue.
  """
  @spec step(t(), float(), (float(), float() -> {float(), float()})) :: {float(), t()}
  def step(%__MODULE__{queue: queue} = line, input, fun) do
    {{:value, oldest}, rest} = :queue.out(queue)
    {emitted, written} = fun.(input, oldest)
    {emitted, %__MODULE__{line | queue: :queue.in(written, rest)}}
  end

  @doc "Runs a whole channel of samples through the line."
  @spec run(t(), [float()], (float(), float() -> {float(), float()})) :: {[float()], t()}
  def run(%__MODULE__{} = line, samples, fun) do
    {emitted, line} =
      Enum.reduce(samples, {[], line}, fn sample, {acc, line} ->
        {emitted, line} = step(line, sample, fun)
        {[emitted | acc], line}
      end)

    {Enum.reverse(emitted), line}
  end

  @doc """
  Runs a channel through the line while threading an accumulator.

  A comb filter has to carry its damping state from one sample to the next, so
  `fun` receives `{input, oldest, acc}` and returns `{emitted, written, acc}`.
  """
  @spec run(t(), [float()], acc, (float(), float(), acc -> {float(), float(), acc})) ::
          {[float()], t(), acc}
        when acc: term()
  def run(%__MODULE__{} = line, samples, acc, fun) do
    {emitted, line, acc} =
      Enum.reduce(samples, {[], line, acc}, fn sample, {emitted, %__MODULE__{} = line, acc} ->
        {{:value, oldest}, rest} = :queue.out(line.queue)
        {value, written, acc} = fun.(sample, oldest, acc)
        {[value | emitted], %{line | queue: :queue.in(written, rest)}, acc}
      end)

    {Enum.reverse(emitted), line, acc}
  end
end
