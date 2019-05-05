# Phoenix Channels Client for Godot and GDScript

GodotPhoenixChannels is a GDScript and [Godot Engine](https://godotengine.org) implementation for the Channels API of the [Phoenix Framework](http://www.phoenixframework.org/). It enables Godot projects and games to connect to Phoenix Channels to leverage the connected massive real-time capabilities of Elixir and Phoenix backends.

Before diving in, if you want to see some crazy numbers about the scalability of Phoenix, check [The Road to 2 Million Websocket Connections in Phoenix)[https://phoenixframework.org/blog/the-road-to-2-million-websocket-connections] and [How Discord Scaled Elixir to 5,000,000 Concurrent Users](https://blog.discordapp.com/scaling-elixir-f9b8e1e7c29b).

## What is Elixir?
[Elixir](https://elixir-lang.org/) is a dynamic, functional language designed for building scalable and maintainable applications.

Elixir leverages the Erlang VM, known for running low-latency, distributed and fault-tolerant systems, while also being successfully used in web development and the embedded software domain.

## What is Phoenix?
[Phoenix](https://phoenixframework.org/) is a web and real-time framework built with Elixir. Phoenix leverages the Erlang VM ability to handle millions of connections alongside Elixir's beautiful syntax and productive tooling for building fault-tolerant systems.

Its primary purpose is to ease development of real time messaging apps for Android using an Elixir/Phoenix backend. For more about the Elixir language and the massively scalable and reliable systems you can build with Phoenix, see http://elixir-lang.org and http://www.phoenixframework.org.

### What are Phoenix Channels?
[Channels](https://hexdocs.pm/phoenix/channels.html) are an exciting part of Phoenix that enable soft real-time communication with and between millions of connected clients. Some possible use cases include:

- Chat rooms and APIs for messaging apps
- Breaking news, like "a goal was scored" or "an earthquake is coming"
- Tracking trains, trucks, or race participants on a map
- Events in multiplayer games
- Monitoring sensors and controlling lights

## Implementation

This library tries to follow the same design patterns of the official [Phoenix JavaScript client](https://hexdocs.pm/phoenix/js/), but important changes had to be made regarding events, in order to accommodate to GDScript. Godot's [WebSocketClient](https://docs.godotengine.org/en/3.1/classes/class_websocketclient.html) is used as the transport.

Most of the features are already implemented, including Socket reconnection and Channel rejoin timers (similarly to the JS library), but there are some key items still missing. See the [issues](https://github.com/alfredbaudisch/GodotPhoenixChannels/issues).

# Example Usage

## Example Project

**ATTENTION**: Still under heavy development - the examples are still not finished.

For examples see the [Demo](./Demo) folder.

## Example
```gdscript
var phoenix : PhoenixSocket
var channel : PhoenixChannel

phoenix = PhoenixSocket.new("ws://localhost:4000/socket", {
  params = {user_id = 10, token = "some_token"}
})

# Subscribe to Socket events
phoenix.connect("on_open", self, "_on_Phoenix_socket_open")
phoenix.connect("on_close", self, "_on_Phoenix_socket_close")
phoenix.connect("on_error", self, "_on_Phoenix_socket_error")
phoenix.connect("on_connecting", self, "_on_Phoenix_socket_connecting")

# Create a Channel
channel = phoenix.channel("game:abc")

# Subscribe to Channel events
channel.connect("on_event", self, "_on_Channel_event")
channel.connect("on_join_result", self, "_on_Channel_join_result")

get_parent().call_deferred("add_child", phoenix, true)

# Connect!
phoenix.connect_socket()
```

Then you implement the listeners:
```gdscript
func _on_Phoenix_socket_open(payload):
	channel.join()
	print("_on_Phoenix_socket_open: ", " ", payload)

func _on_Phoenix_socket_close(payload):
	print("_on_Phoenix_socket_close: ", " ", payload)

func _on_Phoenix_socket_error(payload):
	print("_on_Phoenix_socket_error: ", " ", payload)

func _on_Channel_event(event, payload, status):
	print("_on_channel_event:  ", event, ", ", status, ", ", payload)

func _on_Channel_join_result(status, result):
	print("_on_channel_join_result:  ", status, result)

func _on_Phoenix_socket_connecting(is_connecting):
	print("_on_Phoenix_socket_connecting: ", " ", is_connecting)
```

Push messages to the server:
```gdscript
channel.push("topic", {some: "param"})
```

Broadcasts and push replies are received in the event `PhoenixChannel.on_event`:
```gdscript
channel.connect("on_event", self, "_on_Channel_event")

func _on_Channel_event(event, payload, status):
	print("_on_channel_event:  ", event, ", ", status, ", ", payload)
```
