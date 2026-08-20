defmodule PhoenixDndDemoWeb.EditorLiveTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint PhoenixDndDemoWeb.Endpoint

  test "renders an interactive workflow scene" do
    html = build_conn() |> get("/") |> html_response(200)

    assert html =~ "Workflow canvas"
    assert html =~ ~s(data-editor-id="demo-workflow")
    assert html =~ ~s(phx-hook="PhoenixDnd.Editor.Graph")
    assert html =~ ~s(data-node-id="mixer")
    assert html =~ ~s(data-edge-id="edge-4")
    assert html =~ "events received"
    assert html =~ "current rate"
    assert html =~ "Add node"
    assert html =~ "Remove selected"
    assert html =~ ~s(role="status")
  end

  test "serves the compiled colocated CSS manifest and extracted stylesheet" do
    manifest =
      build_conn()
      |> get("/phoenix-colocated/phoenix_dnd/colocated.css")
      |> response(200)

    relative_path =
      Enum.find(css_imports(manifest), &(Path.dirname(&1) == "PhoenixDnd.Editor")) ||
        flunk("colocated CSS manifest did not include PhoenixDnd.Editor")

    stylesheet =
      build_conn()
      |> get("/phoenix-colocated/phoenix_dnd/#{relative_path}")
      |> response(200)

    assert stylesheet =~ ".phoenix-dnd {"
    assert stylesheet =~ ".phoenix-dnd__surface"
  end

  test "adds and removes a selected node through the LiveView" do
    {:ok, view, _html} = live(build_conn(), "/")

    html =
      view
      |> form(".demo-add-form", %{"kind" => "branch"})
      |> render_submit()

    assert html =~ ~s(data-node-id="node-1")
    assert html =~ "Branch 1"
    assert html =~ ~s(data-scene-revision="1")
    assert html =~ "added node-1 at r1"

    html =
      view
      |> element(~s(button[phx-click="remove_selected"]))
      |> render_click()

    refute html =~ ~s(data-node-id="node-1")
    assert html =~ ~s(data-scene-revision="2")
    assert html =~ "removed selection at r2"
  end

  test "telemetry changes without advancing the scene revision" do
    {:ok, view, initial_html} = live(build_conn(), "/")
    assert initial_html =~ ~s(data-scene-revision="0")

    send(view.pid, :demo_tick)
    updated_html = render(view)

    refute updated_html == initial_html
    assert updated_html =~ ~s(data-scene-revision="0")
  end

  test "rejects malformed add events without crashing the LiveView" do
    {:ok, view, _html} = live(build_conn(), "/")

    html = render_hook(view, "add_node", %{})

    assert html =~ "could not add node: choose a valid node type"
    assert html =~ ~s(data-scene-revision="0")
  end

  defp css_imports(manifest) do
    ~r{@import\s+"\./([^"]+\.css)";}
    |> Regex.scan(manifest, capture: :all_but_first)
    |> List.flatten()
  end
end
