extends Node

class_name Phoenix

signal on_event(event_name, payload)

const HEARTBEAT_INTERVAL = 30000

const WRITE_MODE = WebSocketPeer.WRITE_MODE_TEXT

const TOPIC_PHOENIX = "phoenix"
const EVENT_JOIN = "phx_join"
const EVENT_REPLY = "phx_reply"
const EVENT_PRESENCE_DIFF = "presence_diff"
const EVENT_HEARTBEAT = "heartbeat"

var socket = WebSocketClient.new()
var last_status = -1
var last_heartbeat_at = 0
var tried_connection = false
var connected_at = 0

onready var start_time = OS.get_ticks_msec()

var _topic
var _ref = 0
var _join_ref = null
var _join_ref_pos = 0
var _pending_refs = {}

func _make_ref() -> String:
	_ref = _ref + 1
	return str(_ref)

func _make_join_ref():
	_join_ref_pos = _join_ref_pos + 1
	_join_ref = str(_join_ref_pos)		
	return _join_ref

func _get_join_ref():
	if not _join_ref: _make_join_ref()
	return _join_ref

func _get_pending_ref(ref):	
	if _pending_refs.has(ref):
		return _pending_refs[ref]
			
	return null

func _compose_event(event_name, payload={}, topic=null, join_ref=null):
	var ref = _make_ref()
	
	if event_name == EVENT_HEARTBEAT:
		join_ref = null
	elif not join_ref:
		join_ref = _get_join_ref()
	
	topic = _topic if not topic else topic
	
	var composed = {
		topic = topic,
		event = event_name,
		payload = payload,
		ref = ref,
		join_ref = join_ref
	}
	
	_pending_refs[ref] = composed
		
	return composed

func _ready():
	# Set events
	socket.connect("connection_established", self, "started")
	socket.connect("connection_error", self, "error", ["error"])
	socket.connect("connection_closed", self, "error", ["closed"])
	socket.connect("data_received", self, "read")
	
	if not tried_connection:
		start()
		
	set_process(true)

func _heartbeat(time):
	write(to_json(_compose_event(EVENT_HEARTBEAT, {}, TOPIC_PHOENIX)))
	last_heartbeat_at = time
	
func _process(delta):
	var status = socket.get_connection_status()

	if status != last_status:
		last_status = status
		print("Status: ", status)
		
		if(status == 2):
			write(to_json(_compose_event(EVENT_JOIN, {}, "game:room")))
			
	if status == WebSocketClient.CONNECTION_CONNECTED:
		var current_ticks = OS.get_ticks_msec()		
		
		if (current_ticks - last_heartbeat_at >= HEARTBEAT_INTERVAL) and (current_ticks - connected_at >= HEARTBEAT_INTERVAL):
			_heartbeat(current_ticks)
			
	if status == WebSocketClient.CONNECTION_DISCONNECTED: 
		return

	socket.poll()

func start():
	# Connect to server
	print("connecting...")
	socket.verify_ssl = false
	socket.connect_to_url("ws://localhost:4000/socket/websocket?user_id=1")

func started(protocol):
	print("success!")
	print(protocol)
	socket.get_peer(1).set_write_mode(WRITE_MODE)
	connected_at = OS.get_ticks_msec()

func error(arg):
    print(": ", arg)

func read(pid=1):
	var packet = socket.get_peer(1).get_packet()
	var json = JSON.parse(packet.get_string_from_utf8())
	print("Received JSON, %s" % [json.result])
		
	if json.result.has("event"):
		match json.result["event"]:
			EVENT_REPLY:
				var ref = json.result["ref"]
				
				var pending_ref = _get_pending_ref(ref)
				_parse_pending_ref(pending_ref, json.result)

func write(data):
	print("gonna send ", data, data.to_utf8())
    # Send message
	socket.get_peer(1).put_packet(data.to_utf8())

func _parse_pending_ref(pending_ref, result):
	if not pending_ref: return
	var should_emit = true
	
	match pending_ref.event:
		EVENT_JOIN:
			should_emit = false
			_topic = result["topic"]
			print("JOINED TOPIC ", _topic)
		
		EVENT_HEARTBEAT:
			should_emit = false
						
			if result.payload.has("status"):
				if result.payload.status == "ok":
					print("connection OK")
				else:
					print("heartbeat failed, now what?")
					
	if should_emit:	
		emit_signal("on_event", result["event"], result["payload"])
		print("Emiting event", result)	
	
	_pending_refs.erase(pending_ref.ref)