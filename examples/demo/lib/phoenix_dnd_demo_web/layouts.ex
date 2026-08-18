defmodule PhoenixDndDemoWeb.Layouts do
  @moduledoc false

  use Phoenix.Component

  def root(assigns) do
    assigns =
      assigns
      |> assign_new(:page_title, fn -> "Phoenix DnD demo" end)
      |> assign(:csrf_token, Plug.CSRFProtection.get_csrf_token())

    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={@csrf_token} />
        <title>{@page_title}</title>
        <link rel="icon" href="data:," />
        <link rel="stylesheet" href="/assets/css/app.css" />
        <script type="module" src="/assets/js/app.js">
        </script>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end
end
