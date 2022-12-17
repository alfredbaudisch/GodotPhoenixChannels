defmodule GodotServerWeb.PageController do
  use GodotServerWeb, :controller

  def index(conn, _params) do
    render conn, "index.html"
  end
end
