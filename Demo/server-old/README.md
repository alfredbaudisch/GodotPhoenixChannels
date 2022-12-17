# GodotServer

To start your Phoenix server:

  * Install dependencies with `mix deps.get`
  * Create and migrate your database with `mix ecto.create && mix ecto.migrate`
  * Install Node.js dependencies with `cd assets && npm install`
  * Start Phoenix endpoint with `mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

# Demo Implementation

Example socket, channel and events in:

* [GodotServerWeb.GameChannel](lib/godot_server_web/channels/game_channel.ex)
* [GodotServerWeb.UserSocket](lib/godot_server_web/channels/user_socket.ex)
