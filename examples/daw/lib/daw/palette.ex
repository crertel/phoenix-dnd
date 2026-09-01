defmodule Daw.Palette do
  @moduledoc """
  The catalogue of node kinds the studio can instantiate.

  One registry drives three things that must never disagree: the ports and
  parameters the editor renders, the connection rules `Daw.Graph` enforces, and
  the kernel `Daw.Dsp` runs. Adding a node kind means adding one entry here.
  """

  alias PhoenixDnd.Port

  @type param :: %{
          required(:id) => String.t(),
          required(:label) => String.t(),
          required(:type) => :float | :enum | :bool,
          required(:default) => term(),
          optional(:min) => number(),
          optional(:max) => number(),
          optional(:step) => number(),
          optional(:unit) => String.t(),
          optional(:options) => [{String.t(), String.t()}]
        }

  @type kind :: %{
          id: atom(),
          label: String.t(),
          category: :source | :effect | :routing | :output,
          summary: String.t(),
          accent: String.t(),
          inputs: [String.t()],
          outputs: [String.t()],
          fan_in: boolean(),
          singleton: boolean(),
          runtime: :dsp | :tap,
          params: [param()]
        }

  # Fan-in is the exception, not the rule: only a mixer accepts more than one
  # edge on a single input port. Everything else is a strict one-in chain, which
  # is what makes the arity check in Daw.Graph meaningful.
  @kinds [
    %{
      id: :mic,
      label: "Mic In",
      category: :source,
      summary: "Your microphone, arriving over WebRTC and decoded from Opus.",
      accent: "#f59e0b",
      inputs: [],
      outputs: ["out"],
      fan_in: false,
      singleton: true,
      runtime: :dsp,
      params: [
        %{
          id: "gain_db",
          label: "Input gain",
          type: :float,
          min: -24.0,
          max: 12.0,
          step: 0.5,
          default: 0.0,
          unit: "dB"
        },
        %{id: "mute", label: "Mute", type: :bool, default: false}
      ]
    },
    %{
      id: :tone,
      label: "Oscillator",
      category: :source,
      summary: "A band-limited-ish test oscillator. Handy when you have no mic.",
      accent: "#fbbf24",
      inputs: [],
      outputs: ["out"],
      fan_in: false,
      singleton: false,
      runtime: :dsp,
      params: [
        %{
          id: "waveform",
          label: "Shape",
          type: :enum,
          default: "sine",
          options: [{"sine", "Sine"}, {"square", "Square"}, {"saw", "Saw"}, {"triangle", "Tri"}]
        },
        %{
          id: "freq",
          label: "Frequency",
          type: :float,
          min: 20.0,
          max: 4000.0,
          step: 1.0,
          default: 220.0,
          unit: "Hz"
        },
        %{
          id: "level_db",
          label: "Level",
          type: :float,
          min: -60.0,
          max: 0.0,
          step: 0.5,
          default: -14.0,
          unit: "dB"
        }
      ]
    },
    %{
      id: :noise,
      label: "Noise",
      category: :source,
      summary: "White or pink noise, useful for hearing what a filter does.",
      accent: "#a3a3a3",
      inputs: [],
      outputs: ["out"],
      fan_in: false,
      singleton: false,
      runtime: :dsp,
      params: [
        %{
          id: "color",
          label: "Colour",
          type: :enum,
          default: "white",
          options: [{"white", "White"}, {"pink", "Pink"}]
        },
        %{
          id: "level_db",
          label: "Level",
          type: :float,
          min: -60.0,
          max: 0.0,
          step: 0.5,
          default: -20.0,
          unit: "dB"
        }
      ]
    },
    %{
      id: :gain,
      label: "Gain",
      category: :effect,
      summary: "Straight level trim in decibels.",
      accent: "#38bdf8",
      inputs: ["in"],
      outputs: ["out"],
      fan_in: false,
      singleton: false,
      runtime: :dsp,
      params: [
        %{
          id: "gain_db",
          label: "Gain",
          type: :float,
          min: -60.0,
          max: 12.0,
          step: 0.5,
          default: 0.0,
          unit: "dB"
        },
        %{id: "mute", label: "Mute", type: :bool, default: false}
      ]
    },
    %{
      id: :pan,
      label: "Pan",
      category: :effect,
      summary: "Balance between the two channels. Centre is unity gain.",
      accent: "#22d3ee",
      inputs: ["in"],
      outputs: ["out"],
      fan_in: false,
      singleton: false,
      runtime: :dsp,
      params: [
        %{
          id: "pan",
          label: "Position",
          type: :float,
          min: -1.0,
          max: 1.0,
          step: 0.05,
          default: 0.0,
          unit: "L/R"
        }
      ]
    },
    %{
      id: :delay,
      label: "Delay",
      category: :effect,
      summary: "Feedback delay line. Long times plus high feedback will howl.",
      accent: "#818cf8",
      inputs: ["in"],
      outputs: ["out"],
      fan_in: false,
      singleton: false,
      runtime: :dsp,
      params: [
        %{
          id: "time_ms",
          label: "Time",
          type: :float,
          min: 10.0,
          max: 1000.0,
          step: 5.0,
          default: 260.0,
          unit: "ms"
        },
        %{
          id: "feedback",
          label: "Feedback",
          type: :float,
          min: 0.0,
          max: 0.95,
          step: 0.01,
          default: 0.35
        },
        %{
          id: "mix",
          label: "Mix",
          type: :float,
          min: 0.0,
          max: 1.0,
          step: 0.01,
          default: 0.35
        }
      ]
    },
    %{
      id: :lowpass,
      label: "Low Pass",
      category: :effect,
      summary: "One-pole low pass. Rolls off the top end.",
      accent: "#34d399",
      inputs: ["in"],
      outputs: ["out"],
      fan_in: false,
      singleton: false,
      runtime: :dsp,
      params: [
        %{
          id: "cutoff_hz",
          label: "Cutoff",
          type: :float,
          min: 50.0,
          max: 18_000.0,
          step: 10.0,
          default: 6000.0,
          unit: "Hz"
        }
      ]
    },
    %{
      id: :highpass,
      label: "High Pass",
      category: :effect,
      summary: "One-pole high pass. Clears out rumble and handling noise.",
      accent: "#2dd4bf",
      inputs: ["in"],
      outputs: ["out"],
      fan_in: false,
      singleton: false,
      runtime: :dsp,
      params: [
        %{
          id: "cutoff_hz",
          label: "Cutoff",
          type: :float,
          min: 20.0,
          max: 8000.0,
          step: 10.0,
          default: 120.0,
          unit: "Hz"
        }
      ]
    },
    %{
      id: :tremolo,
      label: "Tremolo",
      category: :effect,
      summary: "Amplitude modulation by a low-frequency sine.",
      accent: "#c084fc",
      inputs: ["in"],
      outputs: ["out"],
      fan_in: false,
      singleton: false,
      runtime: :dsp,
      params: [
        %{
          id: "rate_hz",
          label: "Rate",
          type: :float,
          min: 0.1,
          max: 20.0,
          step: 0.1,
          default: 4.5,
          unit: "Hz"
        },
        %{
          id: "depth",
          label: "Depth",
          type: :float,
          min: 0.0,
          max: 1.0,
          step: 0.01,
          default: 0.6
        }
      ]
    },
    %{
      id: :drive,
      label: "Overdrive",
      category: :effect,
      summary: "Soft-clipping saturation with a wet/dry blend.",
      accent: "#fb7185",
      inputs: ["in"],
      outputs: ["out"],
      fan_in: false,
      singleton: false,
      runtime: :dsp,
      params: [
        %{
          id: "drive",
          label: "Drive",
          type: :float,
          min: 1.0,
          max: 50.0,
          step: 0.5,
          default: 8.0
        },
        %{
          id: "mix",
          label: "Mix",
          type: :float,
          min: 0.0,
          max: 1.0,
          step: 0.01,
          default: 1.0
        }
      ]
    },
    %{
      id: :crusher,
      label: "Bitcrusher",
      category: :effect,
      summary: "Quantises resolution and holds samples for lo-fi grit.",
      accent: "#f472b6",
      inputs: ["in"],
      outputs: ["out"],
      fan_in: false,
      singleton: false,
      runtime: :dsp,
      params: [
        %{
          id: "bits",
          label: "Bits",
          type: :float,
          min: 2.0,
          max: 16.0,
          step: 1.0,
          default: 8.0
        },
        %{
          id: "hold",
          label: "Hold",
          type: :float,
          min: 1.0,
          max: 32.0,
          step: 1.0,
          default: 4.0,
          unit: "x"
        }
      ]
    },
    %{
      id: :compressor,
      label: "Compressor",
      category: :effect,
      summary: "Peak-following downward compression with makeup gain.",
      accent: "#60a5fa",
      inputs: ["in"],
      outputs: ["out"],
      fan_in: false,
      singleton: false,
      runtime: :dsp,
      params: [
        %{
          id: "threshold_db",
          label: "Threshold",
          type: :float,
          min: -48.0,
          max: 0.0,
          step: 0.5,
          default: -18.0,
          unit: "dB"
        },
        %{
          id: "ratio",
          label: "Ratio",
          type: :float,
          min: 1.0,
          max: 20.0,
          step: 0.5,
          default: 4.0,
          unit: ":1"
        },
        %{
          id: "attack_ms",
          label: "Attack",
          type: :float,
          min: 1.0,
          max: 100.0,
          step: 1.0,
          default: 10.0,
          unit: "ms"
        },
        %{
          id: "release_ms",
          label: "Release",
          type: :float,
          min: 10.0,
          max: 1000.0,
          step: 10.0,
          default: 150.0,
          unit: "ms"
        },
        %{
          id: "makeup_db",
          label: "Makeup",
          type: :float,
          min: 0.0,
          max: 24.0,
          step: 0.5,
          default: 0.0,
          unit: "dB"
        }
      ]
    },
    %{
      id: :reverb,
      label: "Reverb",
      category: :effect,
      summary: "Schroeder comb-and-allpass tail. Cheap, and it sounds it.",
      accent: "#a78bfa",
      inputs: ["in"],
      outputs: ["out"],
      fan_in: false,
      singleton: false,
      runtime: :dsp,
      params: [
        %{
          id: "room",
          label: "Room",
          type: :float,
          min: 0.0,
          max: 1.0,
          step: 0.01,
          default: 0.6
        },
        %{
          id: "damping",
          label: "Damping",
          type: :float,
          min: 0.0,
          max: 1.0,
          step: 0.01,
          default: 0.4
        },
        %{
          id: "mix",
          label: "Mix",
          type: :float,
          min: 0.0,
          max: 1.0,
          step: 0.01,
          default: 0.28
        }
      ]
    },
    %{
      id: :chorus,
      label: "Chorus",
      category: :effect,
      summary: "Modulated short delay, offset per channel for width.",
      accent: "#e879f9",
      inputs: ["in"],
      outputs: ["out"],
      fan_in: false,
      singleton: false,
      runtime: :dsp,
      params: [
        %{
          id: "rate_hz",
          label: "Rate",
          type: :float,
          min: 0.05,
          max: 5.0,
          step: 0.05,
          default: 0.8,
          unit: "Hz"
        },
        %{
          id: "depth_ms",
          label: "Depth",
          type: :float,
          min: 1.0,
          max: 20.0,
          step: 0.5,
          default: 6.0,
          unit: "ms"
        },
        %{
          id: "mix",
          label: "Mix",
          type: :float,
          min: 0.0,
          max: 1.0,
          step: 0.01,
          default: 0.4
        }
      ]
    },
    %{
      id: :mixer,
      label: "Mixer",
      category: :routing,
      summary: "Sums every incoming signal. The only port that accepts fan-in.",
      accent: "#77e6c5",
      inputs: ["in"],
      outputs: ["out"],
      fan_in: true,
      singleton: false,
      runtime: :dsp,
      params: [
        %{
          id: "level_db",
          label: "Level",
          type: :float,
          min: -60.0,
          max: 12.0,
          step: 0.5,
          default: 0.0,
          unit: "dB"
        }
      ]
    },
    %{
      id: :split,
      label: "Splitter",
      category: :routing,
      summary: "Copies one signal to two destinations.",
      accent: "#94a3b8",
      inputs: ["in"],
      outputs: ["a", "b"],
      fan_in: false,
      singleton: false,
      runtime: :dsp,
      params: []
    },
    %{
      id: :meter,
      label: "Meter",
      category: :routing,
      summary: "Passes audio through untouched and reports its level upstream.",
      accent: "#4ade80",
      inputs: ["in"],
      outputs: ["out"],
      fan_in: false,
      singleton: false,
      runtime: :dsp,
      params: []
    },
    %{
      id: :recorder,
      label: "Recorder",
      category: :output,
      summary: "Writes a WAV file. Adding one spawns a real Membrane child.",
      accent: "#ef4444",
      inputs: ["in"],
      outputs: [],
      fan_in: false,
      singleton: false,
      runtime: :tap,
      params: [%{id: "armed", label: "Armed", type: :bool, default: false}]
    },
    %{
      id: :master,
      label: "Master Out",
      category: :output,
      summary: "Encoded to Opus and sent back to your browser over WebRTC.",
      accent: "#f87171",
      inputs: ["in"],
      outputs: [],
      fan_in: true,
      singleton: true,
      runtime: :dsp,
      params: [
        %{
          id: "level_db",
          label: "Level",
          type: :float,
          min: -60.0,
          max: 6.0,
          step: 0.5,
          default: -3.0,
          unit: "dB"
        },
        %{id: "mute", label: "Mute", type: :bool, default: false}
      ]
    }
  ]

  @kinds_by_id Map.new(@kinds, &{&1.id, &1})
  @ids Enum.map(@kinds, & &1.id)

  @spec all() :: [kind()]
  def all, do: @kinds

  @spec ids() :: [atom()]
  def ids, do: @ids

  @doc "Kinds a user can add from the palette, grouped in display order."
  @spec addable() :: [kind()]
  def addable, do: Enum.reject(@kinds, & &1.singleton)

  @spec categories() :: [{atom(), String.t()}]
  def categories do
    [
      {:source, "Sources"},
      {:effect, "Effects"},
      {:routing, "Routing"},
      {:output, "Outputs"}
    ]
  end

  @spec fetch(atom() | String.t()) :: {:ok, kind()} | :error
  def fetch(id) when is_atom(id), do: Map.fetch(@kinds_by_id, id)

  def fetch(id) when is_binary(id) do
    case Enum.find(@ids, &(Atom.to_string(&1) == id)) do
      nil -> :error
      atom -> Map.fetch(@kinds_by_id, atom)
    end
  end

  def fetch(_id), do: :error

  @spec fetch!(atom() | String.t()) :: kind()
  def fetch!(id) do
    case fetch(id) do
      {:ok, kind} -> kind
      :error -> raise ArgumentError, "unknown node kind #{inspect(id)}"
    end
  end

  @doc "The parameter map a freshly added node of this kind starts with."
  @spec defaults(atom() | String.t()) :: %{String.t() => term()}
  def defaults(id) do
    id |> fetch!() |> Map.fetch!(:params) |> Map.new(&{&1.id, &1.default})
  end

  @doc """
  Coerces and range-checks one parameter value.

  Client payloads reach this function, so every branch either returns a value
  inside the declared range or an error; nothing is trusted.
  """
  @spec cast_param(atom() | String.t(), String.t(), term()) ::
          {:ok, term()} | {:error, String.t()}
  def cast_param(kind_id, param_id, value) do
    with {:ok, kind} <- fetch_kind(kind_id),
         {:ok, param} <- fetch_param(kind, param_id) do
      cast_value(param, value)
    end
  end

  @doc "Ports for a node of the given kind, laid out inputs left, outputs right."
  @spec ports(atom() | String.t()) :: [Port.t()]
  def ports(id) do
    kind = fetch!(id)

    Enum.map(kind.inputs, &Port.input(&1, anchor: :left)) ++
      Enum.map(kind.outputs, &Port.output(&1, anchor: :right))
  end

  defp fetch_kind(kind_id) do
    case fetch(kind_id) do
      {:ok, kind} -> {:ok, kind}
      :error -> {:error, "unknown node kind #{inspect(kind_id)}"}
    end
  end

  defp fetch_param(kind, param_id) do
    case Enum.find(kind.params, &(&1.id == param_id)) do
      nil -> {:error, "#{kind.label} has no parameter #{inspect(param_id)}"}
      param -> {:ok, param}
    end
  end

  defp cast_value(%{type: :bool}, value) when is_boolean(value), do: {:ok, value}
  defp cast_value(%{type: :bool}, "true"), do: {:ok, true}
  defp cast_value(%{type: :bool}, "false"), do: {:ok, false}
  defp cast_value(%{type: :bool}, "on"), do: {:ok, true}
  defp cast_value(%{type: :bool}, ""), do: {:ok, false}

  defp cast_value(%{type: :bool, label: label}, value) do
    {:error, "#{label} expects a boolean, got: #{inspect(value)}"}
  end

  defp cast_value(%{type: :enum, options: options} = param, value) when is_binary(value) do
    if Enum.any?(options, fn {option, _label} -> option == value end) do
      {:ok, value}
    else
      {:error, "#{param.label} does not accept #{inspect(value)}"}
    end
  end

  defp cast_value(%{type: :enum, label: label}, value) do
    {:error, "#{label} expects a string option, got: #{inspect(value)}"}
  end

  defp cast_value(%{type: :float} = param, value) when is_number(value) do
    clamp_float(param, value / 1.0)
  end

  defp cast_value(%{type: :float} = param, value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> clamp_float(param, number)
      {number, remainder} -> maybe_trailing(param, number, remainder)
      :error -> {:error, "#{param.label} expects a number, got: #{inspect(value)}"}
    end
  end

  defp cast_value(%{label: label}, value) do
    {:error, "#{label} received an unsupported value: #{inspect(value)}"}
  end

  # Range inputs occasionally submit a trailing unit; anything else is a lie.
  defp maybe_trailing(param, number, remainder) do
    if String.trim(remainder) == "" do
      clamp_float(param, number)
    else
      {:error, "#{param.label} expects a number, got: #{inspect(remainder)}"}
    end
  end

  defp clamp_float(%{min: min, max: max}, number) when is_number(min) and is_number(max) do
    cond do
      number < min -> {:ok, min / 1.0}
      number > max -> {:ok, max / 1.0}
      true -> {:ok, number}
    end
  end

  defp clamp_float(_param, number), do: {:ok, number}
end
