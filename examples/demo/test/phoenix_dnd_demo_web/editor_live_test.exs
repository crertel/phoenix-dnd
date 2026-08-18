defmodule PhoenixDndDemoWeb.EditorLiveTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  @endpoint PhoenixDndDemoWeb.Endpoint

  test "renders an interactive workflow scene" do
    html = build_conn() |> get("/") |> html_response(200)

    assert html =~ "Workflow canvas"
    assert html =~ ~s(data-editor-id="demo-workflow")
    assert html =~ ~s(phx-hook="PhoenixDnd.Editor.Graph")
    assert html =~ ~s(data-node-id="mixer")
    assert html =~ ~s(data-edge-id="edge-4")
  end
end
