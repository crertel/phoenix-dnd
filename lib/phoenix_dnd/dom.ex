defmodule PhoenixDnd.Dom do
  @moduledoc false

  @doc false
  @spec editor_id(String.t()) :: String.t()
  def editor_id(editor_id), do: "phoenix-dnd-editor." <> encode(editor_id)

  @doc false
  @spec surface_id(String.t()) :: String.t()
  def surface_id(editor_id), do: editor_id(editor_id) <> ".surface"

  @doc false
  @spec world_id(String.t()) :: String.t()
  def world_id(editor_id), do: editor_id(editor_id) <> ".world"

  @doc false
  @spec edges_id(String.t()) :: String.t()
  def edges_id(editor_id), do: editor_id(editor_id) <> ".edges"

  @doc false
  @spec nodes_id(String.t()) :: String.t()
  def nodes_id(editor_id), do: editor_id(editor_id) <> ".nodes"

  @doc false
  @spec overlay_id(String.t()) :: String.t()
  def overlay_id(editor_id), do: editor_id(editor_id) <> ".overlay"

  @doc false
  @spec edge_id(String.t(), String.t()) :: String.t()
  def edge_id(editor_id, edge_id), do: editor_id(editor_id) <> ".edge." <> encode(edge_id)

  @doc false
  @spec node_id(String.t(), String.t()) :: String.t()
  def node_id(editor_id, node_id), do: editor_id(editor_id) <> ".node." <> encode(node_id)

  @doc false
  @spec port_id(String.t(), String.t(), String.t()) :: String.t()
  def port_id(editor_id, node_id, port_id) do
    editor_id(editor_id) <> ".port." <> encode(node_id) <> "." <> encode(port_id)
  end

  defp encode(id) when is_binary(id), do: Base.url_encode64(id, padding: false)
end
