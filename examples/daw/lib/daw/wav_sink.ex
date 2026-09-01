defmodule Daw.WavSink do
  @moduledoc """
  Writes incoming raw audio to a RIFF/WAVE file.

  RIFF puts two byte counts in a header that sits *before* the audio, so the
  file is opened with a placeholder header and the real sizes are patched in on
  the way out. If the VM dies first the file is still playable by anything that
  reads to EOF, it just misreports its length.
  """

  use Membrane.Sink

  require Membrane.Logger

  alias Membrane.RawAudio

  @header_bytes 44

  def_options(path: [spec: Path.t(), description: "Where to write the WAV file."])

  def_input_pad(:input, accepted_format: %RawAudio{sample_format: :s16le}, flow_control: :auto)

  @impl true
  def handle_init(_ctx, %__MODULE__{path: path}) do
    {[], %{path: path, file: nil, bytes: 0, format: nil}}
  end

  @impl true
  def handle_stream_format(:input, %RawAudio{} = format, _ctx, %{file: nil} = state) do
    File.mkdir_p!(Path.dirname(state.path))
    file = File.open!(state.path, [:write, :binary])
    IO.binwrite(file, header(format, 0))
    Membrane.Logger.info("recording to #{state.path}")
    {[], %{state | file: file, format: format}}
  end

  def handle_stream_format(:input, _format, _ctx, state), do: {[], state}

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    IO.binwrite(state.file, buffer.payload)
    {[], %{state | bytes: state.bytes + byte_size(buffer.payload)}}
  end

  @impl true
  def handle_terminate_request(_ctx, state) do
    {[terminate: :normal], finish(state)}
  end

  defp finish(%{file: nil} = state), do: state

  defp finish(state) do
    File.close(state.file)

    # Patch the two length fields now that the total is known.
    File.open!(state.path, [:read, :write, :binary], fn file ->
      :file.position(file, 0)
      IO.binwrite(file, header(state.format, state.bytes))
    end)

    Membrane.Logger.info("wrote #{state.bytes} bytes to #{state.path}")
    %{state | file: nil}
  end

  defp header(%RawAudio{channels: channels, sample_rate: sample_rate}, data_bytes) do
    bits = 16
    block_align = div(channels * bits, 8)
    byte_rate = sample_rate * block_align

    <<"RIFF", @header_bytes - 8 + data_bytes::little-32, "WAVE", "fmt ", 16::little-32,
      1::little-16, channels::little-16, sample_rate::little-32, byte_rate::little-32,
      block_align::little-16, bits::little-16, "data", data_bytes::little-32>>
  end
end
