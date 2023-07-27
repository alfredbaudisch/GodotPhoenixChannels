class_name PhoenixSocket
extends Node

#
# Signals
#

signal on_open(params)
signal on_error(data)
signal on_close()
signal on_connecting(is_connecting)

#
# Socket Members
#

const DEFAULT_TIMEOUT_MS := 10000
const DEFAULT_HEARTBEAT_INTERVAL_MS := 30000
const DEFAULT_BASE_ENDPOINT := "ws://localhost:4000/socket"
const DEFAULT_RECONNECT_AFTER_MS := [1000, 2000, 5000, 10000]
const TRANSPORT := "websocket"

const WRITE_MODE := WebSocketPeer.WRITE_MODE_TEXT

const TOPIC_PHOENIX := "phoenix"
const EVENT_HEARTBEAT := "heartbeat"
const EMPTY_REF := "-1"

const STATUS = {
	ok = "ok",
	error = "error",
	timeout = "timeout"
}

var _socket := WebSocketPeer.new()
var _channels := []
var _settings := {} : get = get_settings
var _is_https := false
var _endpoint_url := ""
var _last_status := -1
var _connected_at := -1
var _last_connected_at := -1
var _requested_disconnect := false
var _last_close_reason := {}

var _last_heartbeat_at := 0
var _pending_heartbeat_ref := EMPTY_REF

var _last_reconnect_try_at := -1
var _should_reconnect := false
var _reconnect_after_pos := 0

# TODO: refactor as SocketStates, just like ChannelStates
@export var is_connected := false : get = get_is_connected
@export var is_connecting := false : get = get_is_connecting

# Events / Messages
var _ref := 0

#
# Godot lifecycle for PhoenixSocket
#

func _init(endpoint,opts = {}):
	_settings = {
		heartbeat_interval = PhoenixUtils.get_key_or_default(opts, "heartbeat_interval", DEFAULT_HEARTBEAT_INTERVAL_MS),
		timeout = PhoenixUtils.get_key_or_default(opts, "timeout", DEFAULT_TIMEOUT_MS),
		reconnect_after = PhoenixUtils.get_key_or_default(opts, "reconnect_after", DEFAULT_RECONNECT_AFTER_MS),
		params = PhoenixUtils.get_key_or_default(opts, "params", {}),
		tls_options = PhoenixUtils.get_key_or_default(opts, "tls_options", null)
	}
	
	set_endpoint(endpoint)	

func _ready():
	set_process(true)
	
func _process(_delta):
	var status = _socket.get_ready_state()

	if status != _last_status:
		if status == WebSocketPeer.STATE_CLOSED:
			var code = _socket.get_close_code()
			var reason = _socket.get_close_reason()
			_last_close_reason = {
				message = "WebSocket closed with code: %d, reason %s. Clean: %s" % [code, reason, code != -1]
			}
			print(_last_close_reason)

			_on_socket_closed()
			is_connected = false
			_last_connected_at = _connected_at
			_connected_at = -1
		
		if status == WebSocketPeer.STATE_CONNECTING:
			emit_signal("on_connecting", true)
			is_connecting = true
		else:
			if is_connecting: emit_signal("on_connecting", false)
			is_connecting = false
			
	if status == WebSocketPeer.STATE_OPEN:
		if _last_status == WebSocketPeer.STATE_CONNECTING:
			_on_socket_connected()
			
		var current_ticks = Time.get_ticks_msec()		
		
		if (current_ticks - _last_heartbeat_at >= _settings.heartbeat_interval) and (current_ticks - _connected_at >= _settings.heartbeat_interval):
			_heartbeat(current_ticks)
			
		while _socket.get_available_packet_count():
			var packet = _socket.get_packet()
			_on_socket_data_received(packet)
			
	_last_status = status
	
	if status == WebSocketPeer.STATE_CLOSED: 
		_retry_reconnect(Time.get_ticks_msec())
		return

	_socket.poll()
	
func _enter_tree():
	var _error = get_tree().connect("node_removed", _on_node_removed)
	
func _exit_tree():
	var payload = {message = "exit tree"}
	_close(true, payload)
	
	"""
	Closing the socket with _socket() leads to the chain of events that eventually call on_close,
	but then in this specific case of exiting the tree, the event is not called, because
	the tree is freed, so force call it from here.
	"""	
	emit_signal("on_close", payload)
	
#
# Public
#

func connect_socket():
	if is_connected:
		return
	
	_endpoint_url = PhoenixUtils.add_url_params(_settings.endpoint, _settings.params)
	
	if _settings.tls_options:
		_socket.connect_to_url(_endpoint_url, _settings.tls_options)
	else:
		_socket.connect_to_url(_endpoint_url)
	
func disconnect_socket():	
	_close(true, {message = "disconnect requested"})

func get_is_connected() -> bool:
	return is_connected
	
func get_is_connecting() -> bool:
	return is_connecting
	
func get_settings():
	return _settings
	
func set_endpoint(endpoint : String):
	_settings.endpoint = PhoenixUtils.add_trailing_slash(endpoint if endpoint else DEFAULT_BASE_ENDPOINT) + TRANSPORT
	_is_https = _settings.endpoint.begins_with("wss")
	
func set_params(params : Dictionary = {}):
	_settings.params = params
	
func can_push(_event : String) -> bool:
	return is_connected
	
func channel(topic : String, params : Dictionary = {}, presence = null) -> PhoenixChannel:
	var channel : PhoenixChannel = PhoenixChannel.new(self, topic, params, presence)
	
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
		var _error = _socket.send_text(JSON.new().stringify(dict))		
		
func make_ref() -> String:
	_ref = _ref + 1
	return str(_ref)

#
# Implementation 
#

func _trigger_channel_error(channel : PhoenixChannel, payload := {}):
	channel.raw_trigger(PhoenixChannel.CHANNEL_EVENTS.error, payload)

func _close(requested := false, reason := {}):
	if not is_connected:
		return
		
	_last_close_reason = reason
	_requested_disconnect = requested
	_socket.close()	

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
	if get_is_connected():
		# There is still a pending heartbeat, which means it timed out
		if _pending_heartbeat_ref != EMPTY_REF:
			_close(false, {message = "heartbeat timeout"})
		else:
			_pending_heartbeat_ref = make_ref()
			push(compose_message(EVENT_HEARTBEAT, {}, TOPIC_PHOENIX, _pending_heartbeat_ref))
			_last_heartbeat_at = time
	
func _find_and_remove_channel(channel : PhoenixChannel):	
	var pos = _channels.find(channel)
	if pos != -1:
		_channels.remove_at(pos)
		
#
# Listeners
#

func _on_socket_connected():	
	_connected_at = Time.get_ticks_msec()
	_last_close_reason = {}
	_pending_heartbeat_ref = EMPTY_REF
	_last_heartbeat_at = 0
	_requested_disconnect = false
	_reset_reconnection()
	
	is_connected = true	
	emit_signal("on_open", {})
	
func _on_socket_error(reason = null):
	if not is_connected or (_connected_at == -1 and _last_connected_at != -1):
		_should_reconnect = true

	_last_close_reason = reason if reason else {message = "connection error"}
	
	emit_signal("on_error", _last_close_reason)
		
func _on_socket_closed():
	if not _requested_disconnect:
		_should_reconnect = true	
	
	_last_close_reason = {message = "connection lost"} if _last_close_reason.is_empty() else _last_close_reason
	
	var payload = {
		was_requested = _requested_disconnect,
		will_reconnect = not _requested_disconnect,
		reason = _last_close_reason
	}	
	
	for channel in _channels:
		channel.close(payload, _should_reconnect)

	emit_signal("on_close", payload)	
	
func _on_socket_data_received(packet):
	var test_json_conv = JSON.new()
	test_json_conv.parse(packet.get_string_from_utf8())
	var json = test_json_conv.get_data()
	
	if json.has("event"):
		var message = PhoenixUtils.get_message_from_dictionary(json)
		var ref = message.get_ref()
		
		if message.get_topic() == TOPIC_PHOENIX:
			if ref == _pending_heartbeat_ref:
				_pending_heartbeat_ref = EMPTY_REF
		else:
			for channel in _channels:
				if channel.is_member(message.get_topic(), message.get_join_ref()):
					channel.trigger(message)

func _on_node_removed(node : Node):
	var channel = node as PhoenixChannel
	if channel:
		_find_and_remove_channel(channel)
