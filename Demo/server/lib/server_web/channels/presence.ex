defmodule GodotServerWeb.Presence do
  @moduledoc """
  Provides presence tracking to channels and processes.

  See the [`Phoenix.Presence`](https://hexdocs.pm/phoenix/Phoenix.Presence.html)
  docs for more details.
  """
  use Phoenix.Presence, otp_app: :server,
                        pubsub_server: GodotServer.PubSub

  def start_tracking(socket) do
    track(socket, socket.assigns.user_id |> to_string(), %{
      online_at: System.system_time(:second)
    })
  end
end
