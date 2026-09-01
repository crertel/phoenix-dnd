defmodule Daw.PaletteTest do
  use ExUnit.Case, async: true

  alias Daw.Palette

  describe "the registry" do
    test "every kind declares ports that match its runtime shape" do
      for kind <- Palette.all() do
        ports = Palette.ports(kind.id)
        assert length(ports) == length(kind.inputs) + length(kind.outputs)

        assert Enum.count(ports, &(&1.direction == :input)) == length(kind.inputs),
               "#{kind.label} input ports do not match its declared inputs"
      end
    end

    test "only outputs may have no output port" do
      for kind <- Palette.all(), kind.outputs == [] do
        assert kind.category == :output, "#{kind.label} has no output but is not an output node"
      end
    end

    test "defaults are inside their own declared range" do
      for kind <- Palette.all(), param <- kind.params, param.type == :float do
        assert param.default >= param.min and param.default <= param.max,
               "#{kind.label}/#{param.id} default sits outside its range"
      end
    end

    test "singletons are not offered in the palette" do
      refute Enum.any?(Palette.addable(), & &1.singleton)
    end
  end

  describe "cast_param/3" do
    test "clamps rather than rejects out-of-range numbers" do
      assert {:ok, -1.0} = Palette.cast_param(:pan, "pan", -9.0)
      assert {:ok, 1.0} = Palette.cast_param(:pan, "pan", 9.0)
      assert {:ok, 12.0} = Palette.cast_param(:gain, "gain_db", 400)
    end

    test "parses the strings a range input actually submits" do
      assert {:ok, -6.5} = Palette.cast_param(:gain, "gain_db", "-6.5")
    end

    test "accepts declared enum options and refuses anything else" do
      assert {:ok, "square"} = Palette.cast_param(:tone, "waveform", "square")
      assert {:error, message} = Palette.cast_param(:tone, "waveform", "sawtooth")
      assert message =~ "does not accept"
    end

    test "reads the checkbox encoding for booleans" do
      assert {:ok, true} = Palette.cast_param(:gain, "mute", "true")
      assert {:ok, false} = Palette.cast_param(:gain, "mute", "false")
    end

    test "refuses unknown kinds and parameters" do
      assert {:error, _} = Palette.cast_param(:nonesuch, "gain_db", 0)
      assert {:error, message} = Palette.cast_param(:gain, "cutoff_hz", 0)
      assert message =~ "no parameter"
    end
  end
end
