defmodule GodotServerWeb.GameChannel do
  use GodotServerWeb, :channel

  alias GodotServerWeb.{Presence, Socket}

  @impl true
  def join("game:" <> _match_id, _params, socket) do
    conn_id = Ecto.UUID.generate()

    socket =
      socket
      |> assign(:conn_id, conn_id)
      |> assign(:user_id, :rand.uniform(5000))

    send(self(), :after_join)
    {:ok, %{conn_id: conn_id}, socket}
  end

  @impl true
  def handle_info(:after_join, socket) do
    # Track the user being online
    push(socket, "presence_state", Presence.list(socket))
    {:ok, _} = Presence.start_tracking(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_in("ping", %{"error" => true} = params, socket) do
    should_broadcast?(params, socket, "ping")
    {:reply, {:error, %{pong: "error result"}}, socket}
  end

  @impl true
  def handle_in("ping", params, socket) do
    should_broadcast?(params, socket, "ping")
    {:reply, {:ok, %{pong: "success!"}}, socket}
  end

  @doc """
  A quick way to test broadcasting
  """
  defp should_broadcast?(%{"broadcast" => true} = params, socket, event), do:
    broadcast!(socket, event, params)
  defp should_broadcast?(_, _, _), do: :ok
end
