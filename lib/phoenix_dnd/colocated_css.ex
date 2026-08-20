defmodule PhoenixDnd.ColocatedCSS do
  @moduledoc """
  Extracts global CSS for Phoenix DnD components at compile time.

  A `source` attribute may point to a stylesheet relative to the template that
  declares the colocated style. The source is registered as an external
  resource so changing it recompiles the owning component.
  """

  use Phoenix.LiveView.ColocatedCSS

  @impl true
  def transform(
        "style",
        %{"source" => source} = attrs,
        _inline_css,
        %{file: file, module: module}
      )
      when is_binary(source) and map_size(attrs) == 1 do
    path = Path.expand(source, Path.dirname(file))
    Module.put_attribute(module, :external_resource, path)

    {:ok, File.read!(path), []}
  end

  def transform("style", attrs, css, _meta) when map_size(attrs) == 0 do
    {:ok, css, []}
  end

  def transform("style", attrs, _css, _meta) do
    {:error, "unsupported colocated CSS attributes: #{inspect(attrs)}"}
  end
end
