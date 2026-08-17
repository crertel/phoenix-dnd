defmodule PhoenixDnd.Viewport do
  @moduledoc """
  A viewport represented by its scene-space center and zoom level.
  """

  alias PhoenixDnd.Data

  defstruct center_x: 0, center_y: 0, zoom: 1.0

  @type t :: %__MODULE__{
          center_x: number(),
          center_y: number(),
          zoom: number()
        }

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = viewport), do: new!(Map.from_struct(viewport))

  def new!(attrs) do
    attrs =
      attrs
      |> Data.map!("viewport")
      |> Data.known_keys!([:center_x, :center_y, :zoom], "viewport")

    zoom = attrs |> Map.get(:zoom, 1.0) |> Data.number!("viewport zoom")

    if zoom <= 0 do
      raise ArgumentError, "expected viewport zoom to be greater than zero, got: #{inspect(zoom)}"
    end

    %__MODULE__{
      center_x: attrs |> Map.get(:center_x, 0) |> Data.number!("viewport center_x"),
      center_y: attrs |> Map.get(:center_y, 0) |> Data.number!("viewport center_y"),
      zoom: zoom
    }
  end
end
