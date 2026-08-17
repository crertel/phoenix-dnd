defmodule PhoenixDnd.Intent do
  @moduledoc """
  A validated, canonical user intent sent by the editor hook.

  Intents describe user actions, not accepted state changes. The parent
  LiveView remains responsible for authorization, domain validation, and
  producing the next authoritative scene revision.
  """

  alias PhoenixDnd.Data

  @types [
    "connection.create",
    "delete.request",
    "nodes.move",
    "selection.change",
    "viewport.change"
  ]
  @envelope_keys ~w(v client_id intent_id base_revision type phase gesture_id payload)

  @enforce_keys [:client_id, :intent_id, :base_revision, :type, :phase, :payload]
  defstruct version: 1,
            client_id: nil,
            intent_id: nil,
            base_revision: nil,
            type: nil,
            phase: nil,
            gesture_id: nil,
            payload: nil

  @type t :: %__MODULE__{
          version: 1,
          client_id: String.t(),
          intent_id: String.t(),
          base_revision: non_neg_integer(),
          type: String.t(),
          phase: String.t(),
          gesture_id: String.t() | nil,
          payload: map()
        }

  @spec parse(map()) :: {:ok, t()} | {:error, String.t()}
  def parse(payload) when is_map(payload) do
    {:ok, parse!(payload)}
  rescue
    error in ArgumentError -> {:error, Exception.message(error)}
  end

  def parse(_payload), do: {:error, "intent must be an object"}

  @spec parse!(map()) :: t()
  def parse!(payload) when is_map(payload) do
    Data.known_keys!(payload, @envelope_keys, "intent envelope")

    version = fetch!(payload, "v", "intent envelope")

    if version != 1 do
      raise ArgumentError, "unsupported intent protocol version: #{inspect(version)}"
    end

    type =
      payload |> fetch_string!("type", "intent envelope") |> Data.one_of!(@types, "intent type")

    phase = fetch_string!(payload, "phase", "intent envelope")

    if phase != "commit" do
      raise ArgumentError, "intent type #{inspect(type)} only accepts the commit phase"
    end

    body = fetch!(payload, "payload", "intent envelope")
    unless is_map(body), do: raise(ArgumentError, "intent payload must be an object")

    %__MODULE__{
      client_id: bounded_string!(payload, "client_id", "intent envelope", 128),
      intent_id: bounded_string!(payload, "intent_id", "intent envelope", 128),
      base_revision:
        payload
        |> fetch!("base_revision", "intent envelope")
        |> Data.non_negative_integer!("intent base_revision"),
      type: type,
      phase: phase,
      gesture_id: optional_bounded_string!(payload, "gesture_id", "intent envelope", 128),
      payload: validate_body!(type, body)
    }
  end

  defp validate_body!("nodes.move", body) do
    Data.known_keys!(body, ["positions", "selection"], "nodes.move payload")
    positions = fetch!(body, "positions", "nodes.move payload")

    unless is_list(positions) and positions != [] and length(positions) <= 10_000 do
      raise ArgumentError,
            "nodes.move positions must be a non-empty array with at most 10000 entries"
    end

    positions = Enum.map(positions, &position!/1)
    ensure_unique!(Enum.map(positions, & &1["id"]), "nodes.move positions")

    selection =
      body
      |> fetch!("selection", "nodes.move payload")
      |> full_selection!("nodes.move selection")

    moved_ids = MapSet.new(positions, & &1["id"])
    selected_ids = MapSet.new(selection["node_ids"])

    unless MapSet.subset?(moved_ids, selected_ids) do
      raise ArgumentError, "nodes.move selection must include every moved node"
    end

    %{"positions" => positions, "selection" => selection}
  end

  defp validate_body!("selection.change", body) do
    Data.known_keys!(body, ["mode", "node_ids", "edge_ids"], "selection.change payload")

    %{
      "mode" =>
        body
        |> fetch!("mode", "selection.change payload")
        |> Data.one_of!(["replace", "add", "remove", "toggle"], "selection mode"),
      "node_ids" =>
        body
        |> fetch!("node_ids", "selection.change payload")
        |> id_list!("selection node_ids"),
      "edge_ids" =>
        body
        |> fetch!("edge_ids", "selection.change payload")
        |> id_list!("selection edge_ids")
    }
  end

  defp validate_body!("connection.create", body) do
    Data.known_keys!(body, ["source", "target"], "connection.create payload")

    %{
      "source" =>
        body
        |> fetch!("source", "connection.create payload")
        |> endpoint!("connection source"),
      "target" =>
        body
        |> fetch!("target", "connection.create payload")
        |> endpoint!("connection target")
    }
  end

  defp validate_body!("viewport.change", body) do
    Data.known_keys!(body, ["center_x", "center_y", "zoom"], "viewport.change payload")

    %{
      "center_x" =>
        body
        |> fetch!("center_x", "viewport.change payload")
        |> Data.number!("viewport center_x"),
      "center_y" =>
        body
        |> fetch!("center_y", "viewport.change payload")
        |> Data.number!("viewport center_y"),
      "zoom" =>
        body
        |> fetch!("zoom", "viewport.change payload")
        |> Data.positive_number!("viewport zoom")
    }
  end

  defp validate_body!("delete.request", body) do
    Data.known_keys!(body, ["node_ids", "edge_ids"], "delete.request payload")

    result = %{
      "node_ids" =>
        body |> fetch!("node_ids", "delete.request payload") |> id_list!("delete node_ids"),
      "edge_ids" =>
        body |> fetch!("edge_ids", "delete.request payload") |> id_list!("delete edge_ids")
    }

    if result["node_ids"] == [] and result["edge_ids"] == [] do
      raise ArgumentError, "delete.request requires at least one node or edge ID"
    end

    result
  end

  defp position!(position) when is_map(position) do
    Data.known_keys!(position, ["id", "x", "y"], "node position")

    %{
      "id" => fetch_string!(position, "id", "node position"),
      "x" => position |> fetch!("x", "node position") |> Data.number!("node x"),
      "y" => position |> fetch!("y", "node position") |> Data.number!("node y")
    }
  end

  defp position!(_position), do: raise(ArgumentError, "node position must be an object")

  defp endpoint!(endpoint, context) when is_map(endpoint) do
    Data.known_keys!(endpoint, ["node_id", "port_id"], context)

    %{
      "node_id" => fetch_string!(endpoint, "node_id", context),
      "port_id" => fetch_string!(endpoint, "port_id", context)
    }
  end

  defp endpoint!(_endpoint, context), do: raise(ArgumentError, "#{context} must be an object")

  defp full_selection!(selection, context) when is_map(selection) do
    Data.known_keys!(selection, ["node_ids", "edge_ids"], context)

    %{
      "node_ids" => selection |> fetch!("node_ids", context) |> id_list!("#{context} node_ids"),
      "edge_ids" => selection |> fetch!("edge_ids", context) |> id_list!("#{context} edge_ids")
    }
  end

  defp full_selection!(_selection, context),
    do: raise(ArgumentError, "#{context} must be an object")

  defp id_list!(ids, context) when is_list(ids) and length(ids) <= 10_000 do
    result = Enum.map(ids, &Data.id!(&1, context))
    ensure_unique!(result, context)
    result
  end

  defp id_list!(_ids, context) do
    raise ArgumentError, "#{context} must be an array with at most 10000 entries"
  end

  defp ensure_unique!(ids, context) do
    if MapSet.size(MapSet.new(ids)) != length(ids) do
      raise ArgumentError, "#{context} must contain unique IDs"
    end

    ids
  end

  defp fetch!(map, key, context) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "missing #{inspect(key)} in #{context}"
    end
  end

  defp fetch_string!(map, key, context) do
    map |> fetch!(key, context) |> Data.id!(key)
  end

  defp bounded_string!(map, key, context, max_bytes) do
    value = fetch_string!(map, key, context)

    if byte_size(value) > max_bytes do
      raise ArgumentError, "#{key} must be at most #{max_bytes} bytes"
    end

    value
  end

  defp optional_bounded_string!(map, key, context, max_bytes) do
    case Map.fetch(map, key) do
      :error -> nil
      {:ok, nil} -> nil
      {:ok, _value} -> bounded_string!(map, key, context, max_bytes)
    end
  end
end
