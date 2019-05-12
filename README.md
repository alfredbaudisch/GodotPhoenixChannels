# Phoenix Channels Client for Godot and GDScript

GodotPhoenixChannels is a GDScript and [Godot Engine](https://godotengine.org) implementation for the Channels API of the [Phoenix Framework](http://www.phoenixframework.org/). It enables Godot projects and games to connect to Phoenix Channels to leverage the connected massive real-time capabilities of Elixir and Phoenix backends.

Before diving in, if you want to see some crazy numbers about the scalability of Phoenix, check [The Road to 2 Million Websocket Connections in Phoenix](https://phoenixframework.org/blog/the-road-to-2-million-websocket-connections) and [How Discord Scaled Elixir to 5,000,000 Concurrent Users](https://blog.discordapp.com/scaling-elixir-f9b8e1e7c29b).

## What is Elixir?
[Elixir](https://elixir-lang.org/) is a dynamic, functional language designed for building scalable and maintainable applications.

Elixir leverages the Erlang VM, known for running low-latency, distributed and fault-tolerant systems, while also being successfully used in web development and the embedded software domain.

## What is Phoenix?
[Phoenix](https://phoenixframework.org/) is a web and real-time framework built with Elixir. Phoenix leverages the Erlang VM ability to handle millions of connections alongside Elixir's beautiful syntax and productive tooling for building fault-tolerant systems.

### What are Phoenix Channels?
[Channels](https://hexdocs.pm/phoenix/channels.html) are an exciting part of Phoenix that enable soft real-time communication with and between millions of connected clients. Some possible use cases include:

- Chat rooms and APIs for messaging apps
- Breaking news, like "a goal was scored" or "an earthquake is coming"
- Tracking trains, trucks, or race participants on a map
- Events in multiplayer games
- Monitoring sensors and controlling lights

## Implementation

This library tries to follow the same design patterns of the official [Phoenix JavaScript client](https://hexdocs.pm/phoenix/js/), but important changes had to be made regarding events, in order to accommodate to GDScript. Godot's [WebSocketClient](https://docs.godotengine.org/en/3.1/classes/class_websocketclient.html) is used as the transport.

### Features
Almost every feature from the JS official client are implemented:

- Main features of Phoenix Socket (connect, heartbeats, reconnect timers, errors)
- Main features of Phoenix Channel (join, leave, push, receive, rejoin timers, errors)
- All features of Presence
- Automatic disconnection and channel leaving on Node freeing

# Examples

## Example Godot Project

For usage examples see the [Demo](./Demo) project.

## Example Elixir Project

A simple Elixir server is available in [Demo/Server](./Demo/server).

To run it, have Elixir installed, then:
```
cd Demo/server
mix deps.get
iex -S mix phx.server
```

After the server is running, you can run the Godot demo and in the Host field put:
`ws://localhost:4000/socket`.

## Example Usage
```gdscript
var socket : PhoenixSocket
var channel : PhoenixChannel
var presence : PhoenixPresence

socket = PhoenixSocket.new("ws://localhost:4000/socket", {
  params = {user_id = 10, token = "some_token"}
})

# Subscribe to Socket events
socket.connect("on_open", self, "_on_Socket_open")
socket.connect("on_close", self, "_on_Socket_close")
socket.connect("on_error", self, "_on_Socket_error")
socket.connect("on_connecting", self, "_on_Socket_connecting")

# If you want to track Presence
presence = PhoenixPresence.new()

# Subscribe to Presence events (sync_diff and sync_state are also implemented)
presence.connect("on_join", self, "_on_Presence_join")
presence.connect("on_leave", self, "_on_Presence_leave")

# Create a Channel
channel = socket.channel("game:abc", {}, presence)

# Subscribe to Channel events
channel.connect("on_event", self, "_on_Channel_event")
channel.connect("on_join_result", self, "_on_Channel_join_result")
channel.connect("on_error", self, "_on_Channel_error")
channel.connect("on_close", self, "_on_Channel_close")

call_deferred("add_child", socket, true)

# Connect!
socket.connect_socket()
```

Then you implement the listeners:
```gdscript
#
# Socket events
#

func _on_Socket_open(payload):
	channel.join()
	print("_on_Socket_open: ", " ", payload)

func _on_Socket_close(payload):
	print("_on_Socket_close: ", " ", payload)

func _on_Socket_error(payload):
	print("_on_Socket_error: ", " ", payload)

func _on_Socket_connecting(is_connecting):
	print("_on_Socket_connecting: ", " ", is_connecting)

#
# Channel events
#

func _on_Channel_event(event, payload, status):
	print("_on_Channel_event:  ", event, ", ", status, ", ", payload)

func _on_Channel_join_result(status, result):
	print("_on_Channel_join_result:  ", status, result)

func _on_Channel_error(error):
	print("_on_Channel_error: " + str(error))

func _on_Channel_close(closed):
	print("_on_Channel_close: " + str(closed))

#
# Presence events
#

func _on_Presence_join(joins):
	print("_on_Presence_join: " + str(joins))

func _on_Presence_leave(leaves):
	print("_on_Presence_leave: " + str(leaves))

```

Push messages to the server:
```gdscript
channel.push("event_name", {some: "param"})
```

Broadcasts and push replies are received in the event `PhoenixChannel.on_event`:
```gdscript
channel.connect("on_event", self, "_on_Channel_event")

func _on_Channel_event(event, payload, status):
	print("_on_channel_event:  ", event, ", ", status, ", ", payload)
```

## TODO
See the [issues](https://github.com/alfredbaudisch/GodotPhoenixChannels/issues), but mostly:
- [ ] Game example
- [ ] Channel push buffer
- [ ] Socket push buffer

## Additional Facts about Elixir

As it was shown above, Elixir leverages the [Erlang VM](https://en.wikipedia.org/wiki/Erlang_(programming_language)), which itself is a programming language used to build massively scalable soft real-time systems with requirements on high availability. Some of its uses are in telecoms, banking, e-commerce, computer telephony and instant messaging. Erlang's runtime system has built-in support for concurrency, distribution and fault tolerance.

Erlang is some 30 years old, built by Ericsson. To give you some context: Ericsson has 45% of the mobile satellite infrastructure in the world. If you are using data in your mobile phone you are certainly in some stage of the day using an equipment that uses Erlang ([Source](https://www.youtube.com/watch?v=Zf51VOjIVCQ)).
