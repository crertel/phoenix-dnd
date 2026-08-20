defmodule PhoenixDnd.ColocatedAssetsTest do
  use ExUnit.Case, async: true

  @fallback_css Path.expand("../../priv/static/phoenix_dnd.css", __DIR__)

  test "compilation extracts the packaged stylesheet into the colocated manifest" do
    root = Path.join([Mix.Project.build_path(), "phoenix-colocated", "phoenix_dnd"])
    manifest = File.read!(Path.join(root, "colocated.css"))

    relative_path =
      Enum.find(css_imports(manifest), &(Path.dirname(&1) == "PhoenixDnd.Editor")) ||
        flunk("colocated CSS manifest did not include PhoenixDnd.Editor")

    assert Path.extname(relative_path) == ".css"

    extracted_css = File.read!(Path.join(root, relative_path))
    assert extracted_css == File.read!(@fallback_css)
    assert @fallback_css in PhoenixDnd.Editor.__info__(:attributes)[:external_resource]
  end

  defp css_imports(manifest) do
    ~r{@import\s+"\./([^"]+\.css)";}
    |> Regex.scan(manifest, capture: :all_but_first)
    |> List.flatten()
  end
end
