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

const GLOBAL_JOIN_REF := ""
const TOPIC_PHOENIX := "phoenix"
const EVENT_HEARTBEAT := "heartbeat"

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
var _pending_refs := {}

#
# Channel Members
#

const CHANNEL_EVENTS := {
	close = "phx_close",
	error = "phx_error",
	join = "phx_join",
	reply = "phx_reply",
	leave = "phx_leave"
}
enum ChannelStates {CLOSED, ERRORED, JOINED, JOINING, LEAVING}

#
# Channel
#

class PhoenixMessage:
	var _message : Dictionary = {} setget ,to_dictionary
	
	func _init(topic : String, event : String, ref : String, join_ref : String = GLOBAL_JOIN_REF, payload : Dictionary = {}):
		var final_join_ref = join_ref if join_ref != GLOBAL_JOIN_REF else null
		
		_message = {
			topic = topic,
			event = event,
			payload = payload,
			ref = ref,
			join_ref = final_join_ref
		}
		
	static func from_dictionary(from : Dictionary = {}) -> PhoenixMessage:
		return PhoenixMessage.new(from.topic, from.event, from.ref, from.join_ref, from.payload)
		
	func to_dictionary() -> Dictionary:
		return _message

class PhoenixChannel:
	signal on_join_result(event, payload)
	signal on_event(event, payload)
	signal on_error(error)
	signal on_close(params)	
	
	var _state = ChannelStates.CLOSED
	var _topic := ""
	var _params := {}
	var _joined_once := false
	var _socket
	var _join_ref := ""
	
	func _init(socket, topic, params : Dictionary = {}):
		_socket = socket
		_topic = topic
		_params = params
	
	#
	# Interface
	#
	
	func is_closed() -> bool: return _state == ChannelStates.CLOSED
	func is_errored() -> bool: return _state == ChannelStates.ERRORED
	func is_joined() -> bool: return _state == ChannelStates.JOINED
	func is_joining() -> bool: return _state == ChannelStates.JOINING
	func is_leaving() -> bool: return _state == ChannelStates.LEAVING
	
	func join():
		if not _joined_once:
			_rejoin()
	
	func close(params):
		_state = ChannelStates.CLOSED
		emit_signal("on_close", params)
		
	func can_push() -> bool:
		return _socket.can_push() and is_joined()
		
	#
	# Implementation
	#
	
	func _event(event, payload):
		emit_signal("on_event", payload)		
	
	func _error(error):
		_state = ChannelStates.ERRORED
		emit_signal("on_error", error)
		
	func _joined(event : String, payload : Dictionary = {}):
		_state = ChannelStates.JOINED
		emit_signal("on_join_result", event, payload)
		
	func _rejoin():		
		if _state == ChannelStates.JOINING or _state == ChannelStates.JOINED:
			return
		else:
			_state = ChannelStates.JOINING
			
			var ref = _socket.make_ref()
			_join_ref = ref
			_socket.push(_socket.compose_message(CHANNEL_EVENTS.join, _params, _topic, ref, _join_ref))
				
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
	
func channel(topic, params : Dictionary = {}) -> PhoenixChannel:
	var channel := PhoenixChannel.new(self, topic, params)
	_channels.push_back(channel)
	return channel
	
func compose_message(event : String, payload := {}, topic := TOPIC_PHOENIX, ref := "", join_ref := GLOBAL_JOIN_REF) -> PhoenixMessage:	
	if event == EVENT_HEARTBEAT:
		join_ref = GLOBAL_JOIN_REF

	ref = ref if ref != "" else make_ref()
	topic = topic if topic else TOPIC_PHOENIX
	
	var composed = PhoenixMessage.new(topic, event, ref, join_ref, payload)
	
	_pending_refs[ref] = composed
		
	return composed
	
func push(message : PhoenixMessage):
	var dict = message.to_dictionary()
	print(to_json(dict))
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

func can_push(event) -> bool:
	# TODO: do better validation? I.e. do not allow sending message to a topic if a channel is not joined in that topic
	return is_connected
	
func _heartbeat(time):
	push(compose_message(EVENT_HEARTBEAT, {}, TOPIC_PHOENIX))
	_last_heartbeat_at = time

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
	print("_on_socket_closed: ", payload)
	emit_signal("on_close", payload)
	
func _on_socket_data_received(pid := 1):
    print("_on_socket_data_received")