#extends Node
#
#class_name PhoenixBase
#
#signal on_event(event, payload)
#
#const HEARTBEAT_INTERVAL = 30000
#
#const WRITE_MODE = WebSocketPeer.WRITE_MODE_TEXT
#
#const STATUS = {
#	ok = "ok",
#	timeout = "timeout",
#	error = "error"
#}
#
#const CHANNEL_EVENTS = {
#  close = "phx_close",
#  error = "phx_error",
#  join = "phx_join",
#  reply = "phx_reply",
#  leave = "phx_leave"
#}
#
#const TOPIC_PHOENIX = "phoenix"
#const EVENT_PRESENCE_DIFF = "presence_diff"
#const EVENT_HEARTBEAT = "heartbeat"
#
## Socket members
#var _socket = WebSocketClient.new()
#var _last_status = -1
#var _last_heartbeat_at = 0
#var _tried_connection = false 
#var _connected_at = 0
#export var is_connected = false setget ,get_is_connected
#
## Channel members
#var _topic
#var _ref = 0
#var _join_ref = null
#var _join_ref_pos = 0
#var _pending_refs = {}
#export var is_channel_joined = false setget ,get_is_channel_joined
#
##
## Getters
##
#
#func get_is_connected() -> bool:
#	return is_connected
#
#func get_is_channel_joined() -> bool:
#	return is_channel_joined
#
##
## Public Interface
##
#
#func is_online() -> bool:
#	return get_is_connected() and get_is_channel_joined()
#
#func can_push() -> bool:
#	return is_online()
#
##
## Implementation
##
#
#func _make_ref() -> String:
#	_ref = _ref + 1
#	return str(_ref)
#
#func _make_join_ref():
#	_join_ref_pos = _join_ref_pos + 1
#	_join_ref = str(_join_ref_pos)		
#	return _join_ref
#
#func _get_join_ref():
#	if not _join_ref: _make_join_ref()
#	return _join_ref
#
#func _get_pending_ref(ref):	
#	if _pending_refs.has(ref):
#		return _pending_refs[ref]
#
#	return null
#
#func _can_send_message(event):
#	if is_connected:
#		return is_channel_joined or event == CHANNEL_EVENTS.join
#
#	return false
#
#func _compose_event(event, payload={}, topic=null, join_ref=null):
#	var ref = _make_ref()
#
#	if event == EVENT_HEARTBEAT:
#		join_ref = null
#	elif not join_ref:
#		join_ref = _get_join_ref()
#
#	topic = _topic if not topic else topic
#
#	var composed = {
#		topic = topic,
#		event = event,
#		payload = payload,
#		ref = ref,
#		join_ref = join_ref
#	}
#
#	_pending_refs[ref] = composed
#
#	return composed
#
#func _ready():
#	# Set events
#	_socket.connect("connection_established", self, "started")
#	_socket.connect("connection_error", self, "error", ["error"])
#	_socket.connect("connection_closed", self, "error", ["closed"])
#	_socket.connect("data_received", self, "read")
#
#	if not _tried_connection:
#		start()
#
#	set_process(true)
#
#func _heartbeat(time):
#	write(_compose_event(EVENT_HEARTBEAT, {}, TOPIC_PHOENIX))
#	_last_heartbeat_at = time
#
#func _process(delta):
#	var status = _socket.get_connection_status()
#
#	if status != _last_status:
#		_last_status = status
#		print("STATUS CHANGED!")
#
#		if status == WebSocketClient.CONNECTION_CONNECTED:
#			is_connected = true
#			is_channel_joined = false
#			write(_compose_event(CHANNEL_EVENTS.join, {}, "game:room"))
#		elif status == WebSocketClient.CONNECTION_DISCONNECTED:
#			is_connected = false
#			is_channel_joined = false
#			print("Connection closed")
#
#	if status == WebSocketClient.CONNECTION_CONNECTED:
#		var current_ticks = OS.get_ticks_msec()		
#
#		if (current_ticks - _last_heartbeat_at >= HEARTBEAT_INTERVAL) and (current_ticks - _connected_at >= HEARTBEAT_INTERVAL):
#			_heartbeat(current_ticks)
#
#	if status == WebSocketClient.CONNECTION_DISCONNECTED: 
#		return
#
#	_socket.poll()
#
#func start():
#	# Connect to server
#	print("connecting...")
#	_socket.verify_ssl = false
#	_socket.connect_to_url("ws://localhost:4000/socket/websocket?user_id=1")
#
#func started(protocol):
#	print("success!")
#	print(protocol)
#	_socket.get_peer(1).set_write_mode(WRITE_MODE)
#	_connected_at = OS.get_ticks_msec()
#
#func error(arg):
#    print(": ", arg)
#
#func read(pid=1):
#	var packet = _socket.get_peer(1).get_packet()
#	var json = JSON.parse(packet.get_string_from_utf8())
#	print("Received JSON, %s" % [json.result])
#
#	if json.result.has("event"):
#		var ref = json.result.ref
#
#		match json.result.event:
#			CHANNEL_EVENTS.reply:								
#				var pending_ref = _get_pending_ref(ref)
#				_parse_pending_ref(pending_ref, json.result)
#
#			CHANNEL_EVENTS.error:
#				var pending_ref = _get_pending_ref(ref)
#				if pending_ref and pending_ref.event == CHANNEL_EVENTS.join:
#					print("TODO: phx_leave")
#				else:
#					print("TODO: handle error")
#			_:
#				if ref == null:
#					emit_event(json.result.event, json.result.payload)
#
#func write(message):
#	if _can_send_message(message.event):
#		print("gonna send ", message)
#		_socket.get_peer(1).put_packet(to_json(message).to_utf8())
#
#func _parse_pending_ref(pending_ref, result):
#	if not pending_ref: return
#	var should_emit = true
#	var should_erase_ref = true
#
#	match pending_ref.event:
#		CHANNEL_EVENTS.join:
#			should_emit = false
#			should_erase_ref = false
#
#			is_channel_joined = true
#			_topic = result.topic
#			print("JOINED TOPIC ", _topic)
#
#		EVENT_HEARTBEAT:
#			should_emit = false
#
#			if result.payload.has("status") and result.payload.status != STATUS.ok:
#				print("TODO: heartbeat failed, now what?")
#
#	if should_emit:
#		emit_event(result.event, result.payload)
#
#	if should_erase_ref:
#		_pending_refs.erase(pending_ref.ref)
#
#func emit_event(event, payload):
#	print("Emiting event", event, payload)	
#	emit_signal("on_event", event, payload)	