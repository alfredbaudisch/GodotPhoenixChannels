extends Node

class_name PhoenixChannel

const TOPIC_PHOENIX := "phoenix"
const EVENT_HEARTBEAT := "heartbeat"
const STATUS = {
	ok = "ok",
	error = "error",
	timeout = "timeout"
}

const CHANNEL_EVENTS := {
	close = "phx_close",
	error = "phx_error",
	join = "phx_join",
	reply = "phx_reply",
	leave = "phx_leave"
}
enum ChannelStates {CLOSED, ERRORED, JOINED, JOINING, LEAVING}

const PRESENCE_EVENTS := {
	diff = "presence_diff"
}

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
	assert(topic != TOPIC_PHOENIX)
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
	
func is_member(topic, join_ref) -> bool:
	if topic != _topic:
		return false
		
	var is_lifecycle_event = (topic == CHANNEL_EVENTS.close or  topic == CHANNEL_EVENTS.error or 
	topic == CHANNEL_EVENTS.join or topic == CHANNEL_EVENTS.reply or topic == CHANNEL_EVENTS.leave)
	
	if(join_ref and is_lifecycle_event and join_ref != _join_ref):
		return false
	
	return true
			
func trigger(message):
	var status : String = STATUS.ok
	if message.get_payload().has("status"):
		status = message.get_payload().status			
	
	if message.get_ref() == _join_ref:			
		_state = ChannelStates.JOINED if status == STATUS.ok else ChannelStates.ERRORED
		
		if _state == ChannelStates.JOINED:
			_joined_once = true
		else:
			_joined_once = false
			_socket.rejoin_channel()
			
		emit_signal("on_join_result", status, message.get_response())
		
	else:
		# TODO: implement presence
		if message.get_event() == PRESENCE_EVENTS.diff:
			pass
		else:
			emit_signal("on_event", message.get_event(), message.get_payload())
	
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
