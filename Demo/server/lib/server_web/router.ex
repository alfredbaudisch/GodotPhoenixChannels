defmodule GodotServerWeb.Router do
  use GodotServerWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", GodotServerWeb do
    pipe_through :api
  end
end
