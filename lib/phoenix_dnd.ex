defmodule PhoenixDnd do
  @moduledoc """
  A server-authoritative node editor for Phoenix LiveView.

  The component accepts complete `PhoenixDnd.Scene` snapshots while LiveView's
  keyed rendering sends granular DOM diffs. High-frequency pointer state stays
  in a small browser hook and is reported as semantic `PhoenixDnd.Intent`
  messages.
  """

  alias PhoenixDnd.CommandBatch

  @command_event "phoenix_dnd:commands"

  @doc "The hook event used for server-to-client command batches."
  def command_event, do: @command_event

  @doc """
  Pushes an ordered command batch to one editor instance.

  Events are delivered to every hook listening for the shared event name; the
  editor ID in the envelope scopes the batch to its intended instance.
  """
  @spec push_commands(Phoenix.LiveView.Socket.t(), String.t(), CommandBatch.t()) ::
          Phoenix.LiveView.Socket.t()
  def push_commands(socket, editor_id, %CommandBatch{} = batch) do
    Phoenix.LiveView.push_event(socket, @command_event, CommandBatch.to_payload(batch, editor_id))
  end
end
