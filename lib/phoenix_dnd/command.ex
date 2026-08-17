defmodule PhoenixDnd.Command do
  @moduledoc """
  One imperative operation in a server-to-client command batch.
  """

  alias PhoenixDnd.{Data, Viewport}

  @types [
    "interaction.cancel",
    "operation.resolve",
    "viewport.center_node",
    "viewport.fit",
    "viewport.set"
  ]

  @enforce_keys [:id, :type, :payload]
  defstruct [:id, :type, :payload]

  @type t :: %__MODULE__{
          id: String.t(),
          type: String.t(),
          payload: map()
        }

  @spec new!(String.t(), map(), keyword()) :: t()
  def new!(type, payload \\ %{}, opts \\ []) when is_map(payload) do
    validate_options!(opts, [:id], "command")
    type = Data.one_of!(type, @types, "command type")

    %__MODULE__{
      id: opts |> Keyword.get(:id, unique_id("command")) |> Data.id!("command id"),
      type: type,
      payload: validate_payload!(type, payload)
    }
  end

  @spec viewport_set(Viewport.t() | map() | keyword(), keyword()) :: t()
  def viewport_set(viewport, opts \\ []) do
    validate_options!(opts, [:id, :animate_ms], "viewport_set")
    viewport = Viewport.new!(viewport)

    new!(
      "viewport.set",
      %{
        center_x: viewport.center_x,
        center_y: viewport.center_y,
        zoom: viewport.zoom,
        animate_ms: Keyword.get(opts, :animate_ms, 0)
      },
      command_options(opts)
    )
  end

  @spec viewport_fit(keyword()) :: t()
  def viewport_fit(opts \\ []) do
    validate_options!(opts, [:id, :node_ids, :padding, :max_zoom, :animate_ms], "viewport_fit")

    payload = %{
      node_ids: Keyword.get(opts, :node_ids, []),
      padding: Keyword.get(opts, :padding, 48),
      max_zoom: Keyword.get(opts, :max_zoom),
      animate_ms: Keyword.get(opts, :animate_ms, 0)
    }

    new!("viewport.fit", payload, command_options(opts))
  end

  @spec viewport_center_node(String.t(), keyword()) :: t()
  def viewport_center_node(node_id, opts \\ []) do
    validate_options!(opts, [:id, :zoom, :animate_ms], "viewport_center_node")

    new!(
      "viewport.center_node",
      %{
        node_id: Data.id!(node_id, "node id"),
        zoom: Keyword.get(opts, :zoom),
        animate_ms: Keyword.get(opts, :animate_ms, 0)
      },
      command_options(opts)
    )
  end

  @spec interaction_cancel(keyword()) :: t()
  def interaction_cancel(opts \\ []) do
    validate_options!(opts, [:id], "interaction_cancel")
    new!("interaction.cancel", %{}, command_options(opts))
  end

  @spec operation_resolve(String.t(), :accepted | :rejected, keyword()) :: t()
  def operation_resolve(operation_id, status, opts \\ [])

  def operation_resolve(operation_id, status, opts) when status in [:accepted, :rejected] do
    validate_options!(opts, [:id, :reason], "operation_resolve")

    new!(
      "operation.resolve",
      %{
        operation_id: Data.id!(operation_id, "operation id"),
        status: Atom.to_string(status),
        reason: Keyword.get(opts, :reason)
      },
      command_options(opts)
    )
  end

  def operation_resolve(_operation_id, status, _opts) do
    raise ArgumentError,
          "expected operation status to be :accepted or :rejected, got: #{inspect(status)}"
  end

  @spec to_payload(t()) :: map()
  def to_payload(%__MODULE__{} = command) do
    %{id: command.id, type: command.type, payload: command.payload}
  end

  defp unique_id(prefix) do
    suffix = System.unique_integer([:positive, :monotonic])
    "#{prefix}-#{suffix}"
  end

  defp validate_payload!("interaction.cancel", payload) do
    Data.known_keys!(payload, [], "interaction.cancel payload")
    %{}
  end

  defp validate_payload!("operation.resolve", payload) do
    Data.known_keys!(payload, [:operation_id, :status, :reason], "operation.resolve payload")

    reason = Map.get(payload, :reason)
    if not is_nil(reason), do: Data.utf8_string!(reason, "operation resolution reason", 1_024)

    %{
      operation_id:
        payload
        |> Data.fetch!(:operation_id, "operation.resolve payload")
        |> Data.id!("operation id"),
      status:
        payload
        |> Data.fetch!(:status, "operation.resolve payload")
        |> Data.one_of!(["accepted", "rejected"], "operation status"),
      reason: reason
    }
  end

  defp validate_payload!("viewport.set", payload) do
    Data.known_keys!(payload, [:center_x, :center_y, :zoom, :animate_ms], "viewport.set payload")

    viewport =
      Viewport.new!(%{
        center_x: Data.fetch!(payload, :center_x, "viewport.set payload"),
        center_y: Data.fetch!(payload, :center_y, "viewport.set payload"),
        zoom: Data.fetch!(payload, :zoom, "viewport.set payload")
      })

    %{
      center_x: viewport.center_x,
      center_y: viewport.center_y,
      zoom: viewport.zoom,
      animate_ms: animation_ms!(Map.get(payload, :animate_ms, 0))
    }
  end

  defp validate_payload!("viewport.fit", payload) do
    Data.known_keys!(
      payload,
      [:node_ids, :padding, :max_zoom, :animate_ms],
      "viewport.fit payload"
    )

    node_ids = id_list!(Map.get(payload, :node_ids, []), "viewport.fit node_ids")

    padding =
      payload |> Map.get(:padding, 48) |> Data.non_negative_number!("viewport.fit padding")

    max_zoom =
      case Map.get(payload, :max_zoom) do
        nil -> nil
        zoom -> Data.positive_number!(zoom, "viewport.fit max_zoom")
      end

    %{
      node_ids: node_ids,
      padding: padding,
      max_zoom: max_zoom,
      animate_ms: animation_ms!(Map.get(payload, :animate_ms, 0))
    }
  end

  defp validate_payload!("viewport.center_node", payload) do
    Data.known_keys!(
      payload,
      [:node_id, :zoom, :animate_ms],
      "viewport.center_node payload"
    )

    zoom =
      case Map.get(payload, :zoom) do
        nil -> nil
        value -> Data.positive_number!(value, "viewport.center_node zoom")
      end

    %{
      node_id:
        payload
        |> Data.fetch!(:node_id, "viewport.center_node payload")
        |> Data.id!("node id"),
      zoom: zoom,
      animate_ms: animation_ms!(Map.get(payload, :animate_ms, 0))
    }
  end

  defp animation_ms!(value) do
    value = Data.non_negative_integer!(value, "command animate_ms")

    if value <= 60_000 do
      value
    else
      raise ArgumentError, "expected command animate_ms to be at most 60000"
    end
  end

  defp id_list!(ids, context) when is_list(ids) and length(ids) <= 10_000 do
    result = Enum.map(ids, &Data.id!(&1, context))

    if MapSet.size(MapSet.new(result)) != length(result) do
      raise ArgumentError, "expected #{context} to contain unique IDs"
    end

    result
  end

  defp id_list!(_ids, context) do
    raise ArgumentError, "expected #{context} to be a list with at most 10000 entries"
  end

  defp validate_options!(opts, allowed, context) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError, "#{context} options must be a keyword list"
    end

    unknown = Keyword.keys(opts) -- allowed
    if unknown != [], do: raise(ArgumentError, "unknown #{context} options: #{inspect(unknown)}")

    opts
  end

  defp command_options(opts), do: Keyword.take(opts, [:id])
end
