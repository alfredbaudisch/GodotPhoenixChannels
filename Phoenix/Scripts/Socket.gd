extends Node

class_name PhoenixSocket

#
# Socket Members
#

const DEFAULT_TIMEOUT := 10000
const DEFAULT_HEARTBEAT_INTERVAL := 30000
const DEFAULT_BASE_ENDPOINT := "ws://localhost:4000/socket"
const DEFAULT_RECONNECT_AFTER := [1000, 2000, 5000, 10000]
const TRANSPORT := "websocket"

const WRITE_MODE := WebSocketPeer.WRITE_MODE_TEXT

const TOPIC_PHOENIX := "phoenix"
const EVENT_HEARTBEAT := "heartbeat"
const STATUS = {
	ok = "ok",
	error = "error",
	timeout = "timeout"
}

signal on_open(params)
signal on_error(data)
signal on_close()
signal on_connecting(is_connecting)

var _socket := WebSocketClient.new()
var _channels := []
var _settings := {}
var _is_https := false
var _endpoint_url := ""
var _last_status := -1
var _connected_at := -1
var _last_connected_at := -1
var _requested_disconnect := false

var _last_heartbeat_at := 0
var _pending_heartbeat_ref := 0

var _last_reconnect_try_at := -1
var _should_reconnect := false
var _reconnect_after_pos := 0

# TODO: refactor as SocketStates, just like ChannelStates
export var is_connected := false setget ,get_is_connected
export var is_connecting := false setget ,get_is_connecting

# Events
var _ref := 0
var _pending_messages := {}

#
# Channel Members
#

#
# Channel
#

#
# Godot lifecycle for PhoenixSocket
#

func _init(endpoint, opts = {}):
	_settings = {
		heartbeat_interval = PhoenixUtils.get_key_or_default(opts, "heartbeat_interval", DEFAULT_HEARTBEAT_INTERVAL),
		timeout = PhoenixUtils.get_key_or_default(opts, "timeout", DEFAULT_TIMEOUT),
		reconnect_after = PhoenixUtils.get_key_or_default(opts, "reconnect_after", DEFAULT_RECONNECT_AFTER),
		params = PhoenixUtils.get_key_or_default(opts, "params", {}),
		endpoint = PhoenixUtils.add_trailing_slash(endpoint if endpoint else DEFAULT_BASE_ENDPOINT) + TRANSPORT
	}
	
	_is_https = _settings.endpoint.begins_with("wss")
	_endpoint_url = PhoenixUtils.add_url_params(_settings.endpoint, _settings.params)

func _ready():
	_socket.connect("connection_established", self, "_on_socket_connected")
	_socket.connect("connection_error", self, "_on_socket_error")
	_socket.connect("connection_closed", self, "_on_socket_closed")
	_socket.connect("data_received", self, "_on_socket_data_received")
	
	set_process(true)
	
func _process(delta):
	var status = _socket.get_connection_status()

	if status != _last_status:
		_last_status = status
	
		if status == WebSocketClient.CONNECTION_DISCONNECTED:
			is_connected = false
			_last_connected_at = _connected_at
			_connected_at = -1
		
		if status == WebSocketClient.CONNECTION_CONNECTING:
			emit_signal("on_connecting", true)
			is_connecting = true
		else:
			if is_connecting: emit_signal("on_connecting", false)
			is_connecting = false
			
	if status == WebSocketClient.CONNECTION_CONNECTED:
		var current_ticks = OS.get_ticks_msec()		
		
		if (current_ticks - _last_heartbeat_at >= _settings.heartbeat_interval) and (current_ticks - _connected_at >= _settings.heartbeat_interval):
			_heartbeat(current_ticks)
			
	if status == WebSocketClient.CONNECTION_DISCONNECTED: 
		_retry_reconnect(OS.get_ticks_msec())
		return

	_socket.poll()
	
#
# Public
#

func connect_socket():
	if is_connected:
		return
	
	_socket.verify_ssl = false
	_socket.connect_to_url(_endpoint_url)
	
func disconnect_socket():
	if not is_connected:
		return
	
	_requested_disconnect = true
	_socket.disconnect_from_host()	

func get_is_connected() -> bool:
	return is_connected
	
func get_is_connecting() -> bool:
	return is_connecting
	
func can_push(event) -> bool:
	# TODO: do better validation? I.e. do not allow sending message to a topic if a channel is not joined in that topic
	return is_connected
	
func channel(topic : String, params : Dictionary = {}) -> PhoenixChannel:
	var channel := PhoenixChannel.new(self, topic, params)
	_channels.push_back(channel)
	add_child(channel)
	return channel
	
func compose_message(event : String, payload := {}, topic := TOPIC_PHOENIX, ref := "", join_ref := PhoenixMessage.GLOBAL_JOIN_REF) -> PhoenixMessage:	
	if event == EVENT_HEARTBEAT:
		join_ref = PhoenixMessage.GLOBAL_JOIN_REF

	ref = ref if ref != "" else make_ref()
	topic = topic if topic else TOPIC_PHOENIX
	
	return PhoenixMessage.new(topic, event, ref, join_ref, payload)
	
func push(message : PhoenixMessage):
	var dict = message.to_dictionary()
	
	if can_push(dict.event):	
		_socket.get_peer(1).put_packet(to_json(dict).to_utf8())		
		
func make_ref() -> String:
	_ref = _ref + 1
	return str(_ref)

#
# Implementation 
#

func _reset_reconnection():
	_last_reconnect_try_at = -1
	_should_reconnect = false
	_reconnect_after_pos = 0

func _retry_reconnect(current_time):
	if _should_reconnect:
		# Just started the reconnection timer, set time as now, so the
		# first _reconnect_after_pos amount will be subtracted from now
		if _last_reconnect_try_at == -1:
			_last_reconnect_try_at = current_time
		else:
			var reconnect_after = _settings.reconnect_after[_reconnect_after_pos]
							
			if current_time - _last_reconnect_try_at >= reconnect_after:
				_last_reconnect_try_at = current_time
				
				# Move to the next reconnect time (or keep the last one)
				if _reconnect_after_pos < reconnect_after - 1 and _reconnect_after_pos < _settings.reconnect_after.size() - 1: 
					_reconnect_after_pos += 1
					
				connect_socket()
	
func _heartbeat(time):
	push(compose_message(EVENT_HEARTBEAT, {}, TOPIC_PHOENIX))
	_last_heartbeat_at = time
	
func _get_pending_ref(ref):	
	if _pending_messages.has(ref):
		return _pending_messages[ref]
			
	return null
	
func _parse_pending_ref(pending_ref, result):
	if not pending_ref: return
	var should_erase_ref = true
	
	var message = pending_ref.to_dictionary()
	
	match message.event:		
		EVENT_HEARTBEAT:
			if result.payload.has("status") and result.payload.status != STATUS.ok:
				print("TODO: heartbeat failed, now what?")
	
	if should_erase_ref:
		_pending_messages.erase(message.ref)

#
# Listeners
#

func _on_socket_connected(protocol):
	_socket.get_peer(1).set_write_mode(WRITE_MODE)
	
	_connected_at = OS.get_ticks_msec()	
	_last_heartbeat_at = 0
	_requested_disconnect = false
	_reset_reconnection()
	
	is_connected = true	
	emit_signal("on_open", {})
	
func _on_socket_error(reason = null):
	if not is_connected or (_connected_at == -1 and _last_connected_at != -1):
		_should_reconnect = true

	print("_on_socket_closed: ", reason)
	emit_signal("on_error", reason)
		
func _on_socket_closed(clean):
	if not _requested_disconnect:
		_should_reconnect = true	
	
	var payload = {
		was_requested = _requested_disconnect,
		will_reconnect = not _requested_disconnect
	}	

	for channel in _channels:
		channel.close(payload, _should_reconnect)
		
	print("_on_socket_closed: ", payload)
	emit_signal("on_close", payload)	
	
func _on_socket_data_received(pid := 1):
	var packet = _socket.get_peer(1).get_packet()
	var json = JSON.parse(packet.get_string_from_utf8())
	print("_on_socket_data_received, %s" % [json.result])
	
	if json.result.has("event"):
		var result = json.result
		var message = PhoenixUtils.get_message_from_dictionary(json.result)
		var ref = message.get_ref()
		
		if message.get_topic() == TOPIC_PHOENIX:
			pass
		else:
			for channel in _channels:
				if channel.is_member(message.get_topic(), message.get_join_ref()):
					channel.trigger(message)
