defmodule PhoenixDnd.CommandBatch do
  @moduledoc """
  An ordered, revision-gated batch of server-to-client commands.

  Command batches are best-effort. Durable state must be represented by the
  next `PhoenixDnd.Scene` snapshot so reconnects can recover without replaying
  old events.
  """

  alias PhoenixDnd.{Command, Data}

  @enforce_keys [:id, :after_revision, :commands]
  defstruct version: 1, id: nil, after_revision: 0, commands: []

  @type t :: %__MODULE__{
          version: 1,
          id: String.t(),
          after_revision: non_neg_integer(),
          commands: [Command.t()]
        }

  @spec new!([Command.t()], keyword()) :: t()
  def new!(commands, opts \\ [])

  def new!(commands, opts) when is_list(commands) and commands != [] do
    validate_options!(opts)

    unless Enum.all?(commands, &match?(%Command{}, &1)) do
      raise ArgumentError, "command batches only accept PhoenixDnd.Command structs"
    end

    %__MODULE__{
      id: opts |> Keyword.get(:id, unique_id()) |> Data.id!("batch id"),
      after_revision:
        opts
        |> Keyword.get(:after_revision, 0)
        |> Data.non_negative_integer!("batch after_revision"),
      commands: commands
    }
  end

  def new!(_commands, _opts) do
    raise ArgumentError, "a command batch requires at least one command"
  end

  @spec to_payload(t(), String.t()) :: map()
  def to_payload(%__MODULE__{} = batch, editor_id) do
    %{
      v: batch.version,
      editor_id: Data.id!(editor_id, "editor id"),
      batch_id: batch.id,
      after_revision: batch.after_revision,
      commands: Enum.map(batch.commands, &Command.to_payload/1)
    }
  end

  defp unique_id do
    suffix = System.unique_integer([:positive, :monotonic])
    "batch-#{suffix}"
  end

  defp validate_options!(opts) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError, "command batch options must be a keyword list"
    end

    unknown = Keyword.keys(opts) -- [:id, :after_revision]

    if unknown != [],
      do: raise(ArgumentError, "unknown command batch options: #{inspect(unknown)}")

    opts
  end
end
