defmodule Daw.WavSinkTest do
  use ExUnit.Case, async: false

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Daw.{Audio, WavSink}
  alias Membrane.Testing

  @frames 480

  setup do
    path = Path.join(System.tmp_dir!(), "daw-test-#{System.unique_integer([:positive])}.wav")
    on_exit(fn -> File.rm(path) end)
    {:ok, path: path}
  end

  test "writes a playable WAV with a patched-up header", %{path: path} do
    block = Audio.to_binary(List.duplicate({0.5, -0.5}, @frames))
    blocks = List.duplicate(block, 4)

    pipeline =
      Testing.Pipeline.start_link_supervised!(
        spec: [
          child(:source, %Testing.Source{output: blocks, stream_format: Audio.format()})
          |> child(:sink, %WavSink{path: path})
        ]
      )

    assert_end_of_stream(pipeline, :sink, :input, 5_000)
    Testing.Pipeline.terminate(pipeline)

    written = File.read!(path)
    audio_bytes = 4 * byte_size(block)

    assert <<"RIFF", riff_size::little-32, "WAVE", "fmt ", 16::little-32, 1::little-16,
             2::little-16, 48_000::little-32, _byte_rate::little-32, 4::little-16, 16::little-16,
             "data", data_size::little-32, payload::binary>> = written

    assert data_size == audio_bytes, "the data chunk size must be patched in on close"
    assert riff_size == 36 + audio_bytes
    assert byte_size(payload) == audio_bytes
    assert payload == IO.iodata_to_binary(blocks)
  end
end
