defmodule PhoenixDnd.Data do
  @moduledoc false

  @max_id_bytes 512
  @max_safe_integer 9_007_199_254_740_991
  @max_geometry_magnitude 1_000_000_000_000

  def map!(value, _context) when is_map(value), do: value
  def map!(value, _context) when is_list(value), do: Map.new(value)

  def map!(value, context) do
    raise ArgumentError, "expected #{context} to be a map or keyword list, got: #{inspect(value)}"
  end

  def fetch!(attrs, key, context) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "missing #{inspect(key)} in #{context}"
    end
  end

  def id!(value, _context)
      when is_binary(value) and byte_size(value) > 0 and byte_size(value) <= @max_id_bytes do
    if String.valid?(value),
      do: value,
      else: raise(ArgumentError, "identifiers must be valid UTF-8")
  end

  def id!(value, context) do
    raise ArgumentError,
          "expected #{context} to be a non-empty UTF-8 string of at most " <>
            "#{@max_id_bytes} bytes, got: #{inspect(value)}"
  end

  def number!(value, _context)
      when is_integer(value) and value >= -@max_geometry_magnitude and
             value <= @max_geometry_magnitude,
      do: value

  def number!(value, _context)
      when is_float(value) and value == value and value >= -@max_geometry_magnitude and
             value <= @max_geometry_magnitude,
      do: value

  def number!(value, context) do
    raise ArgumentError,
          "expected #{context} to be a finite number between " <>
            "#{-@max_geometry_magnitude} and #{@max_geometry_magnitude}, got: #{inspect(value)}"
  end

  def non_negative_integer!(value, _context)
      when is_integer(value) and value >= 0 and value <= @max_safe_integer,
      do: value

  def non_negative_integer!(value, context) do
    raise ArgumentError,
          "expected #{context} to be a JavaScript-safe non-negative integer, got: " <>
            inspect(value)
  end

  def positive_number!(value, context) do
    value = number!(value, context)

    if value > 0,
      do: value,
      else: raise(ArgumentError, "expected #{context} to be greater than zero")
  end

  def non_negative_number!(value, context) do
    value = number!(value, context)
    if value >= 0, do: value, else: raise(ArgumentError, "expected #{context} to be non-negative")
  end

  def utf8_string!(value, context, max_bytes \\ nil)

  def utf8_string!(value, _context, nil) when is_binary(value) do
    if String.valid?(value), do: value, else: raise(ArgumentError, "strings must be valid UTF-8")
  end

  def utf8_string!(value, _context, max_bytes)
      when is_binary(value) and is_integer(max_bytes) and byte_size(value) <= max_bytes do
    if String.valid?(value), do: value, else: raise(ArgumentError, "strings must be valid UTF-8")
  end

  def utf8_string!(value, context, nil) do
    raise ArgumentError, "expected #{context} to be a valid UTF-8 string, got: #{inspect(value)}"
  end

  def utf8_string!(value, context, max_bytes) do
    raise ArgumentError,
          "expected #{context} to be a valid UTF-8 string of at most #{max_bytes} bytes, got: " <>
            inspect(value)
  end

  def known_keys!(attrs, allowed, context) when is_map(attrs) do
    unknown = Map.keys(attrs) -- allowed

    if unknown != [] do
      raise ArgumentError, "unknown #{context} keys: #{inspect(Enum.sort(unknown))}"
    end

    attrs
  end

  def one_of!(value, allowed, context) do
    if value in allowed do
      value
    else
      raise ArgumentError,
            "expected #{context} to be one of #{inspect(allowed)}, got: #{inspect(value)}"
    end
  end

  def unique_ids!(items, context) do
    duplicate_ids =
      items
      |> Enum.frequencies_by(& &1.id)
      |> Enum.filter(fn {_id, count} -> count > 1 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    if duplicate_ids != [] do
      raise ArgumentError, "duplicate #{context} IDs: #{inspect(duplicate_ids)}"
    end

    items
  end
end
