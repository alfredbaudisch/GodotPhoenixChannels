extends Node

class_name PhoenixChannel

const DEFAULT_REJOIN_AFTER_SECONDS := [1, 2, 5, 10]

const TOPIC_PHOENIX := "phoenix"
const STATUS = {
	ok = "ok",
	error = "error",
	timeout = "timeout"
}
const PRESENCE_EVENTS := {
	diff = "presence_diff",
	state = "presence_state"
}
const CHANNEL_EVENTS := {
	close = "phx_close",
	error = "phx_error",
	join = "phx_join",
	reply = "phx_reply",
	leave = "phx_leave"
}

enum ChannelStates {CLOSED, ERRORED, JOINED, JOINING, LEAVING}

signal on_join_result(event, payload)
signal on_event(event, payload, status)
signal on_error(error)
signal on_close(params)	

var _state = ChannelStates.CLOSED
var _topic := ""
var _params := {}
var _joined_once := false
var _socket
var _join_ref := ""
var _pending_refs := {}

var _rejoin_timer : Timer
var _should_rejoin_until_connected := false
var _rejoin_pos := -1

func _init(socket, topic, params : Dictionary = {}):
	assert(topic != TOPIC_PHOENIX)
	_socket = socket
	_topic = topic
	_params = params
	
	_rejoin_timer = Timer.new()
	_rejoin_timer.set_autostart(false)
	_rejoin_timer.connect("timeout", self, "_on_Timer_timeout")
	add_child(_rejoin_timer)
	
func _exit_tree():
	leave()
	
	"""
	Leaving the channel with leave() leads to the chain of events that eventually call on_close,
	but then in this specific case of exiting the tree, the event is not called,
	so force call it from here.
	"""	
	emit_signal("on_close", {message = "exit tree"})

#
# Interface
#

func is_closed() -> bool: return _state == ChannelStates.CLOSED
func is_errored() -> bool: return _state == ChannelStates.ERRORED
func is_joined() -> bool: return _state == ChannelStates.JOINED
func is_joining() -> bool: return _state == ChannelStates.JOINING
func is_leaving() -> bool: return _state == ChannelStates.LEAVING

func leave() -> bool:
	if !is_leaving() and !is_closed():
		push(CHANNEL_EVENTS.leave, {})
		_state = ChannelStates.LEAVING
		return true
		
	return false

func join() -> bool:
	if not _joined_once:
		return _rejoin()
	
	return false

func close(params := {}, should_rejoin := false):
	_joined_once = false
	_state = ChannelStates.CLOSED
	emit_signal("on_close", params)
	
	if should_rejoin:
		_start_rejoin()
		
func push(event : String, payload : Dictionary = {}) -> bool:
	if not can_push(event):
		return false

	# todo: start timeout	
	
	var ref = _socket.make_ref()
	_pending_refs[ref] = event
	_socket.push(_socket.compose_message(event, payload, _topic, ref, _join_ref))
	return true

func can_push(event : String) -> bool:
	return _socket.can_push(event) and is_joined()
	
func is_member(topic, join_ref) -> bool:
	if topic != _topic:
		return false
		
	var is_lifecycle_event = (topic == CHANNEL_EVENTS.close or  topic == CHANNEL_EVENTS.error or 
	topic == CHANNEL_EVENTS.join or topic == CHANNEL_EVENTS.reply or topic == CHANNEL_EVENTS.leave)
	
	if(join_ref and is_lifecycle_event and join_ref != _join_ref):
		return false
	
	return true
	
func raw_trigger(event : String, payload := {}):
	trigger(PhoenixMessage.new(_topic, event, PhoenixMessage.NO_REPLY_REF, _join_ref, payload))
			
func trigger(message : PhoenixMessage):
	var status : String = STATUS.ok
	if message.get_payload().has("status"):
		status = message.get_payload().status
	
	# Event related to the channel connection/status
	if message.get_ref() == _join_ref:
		match message.get_event():
			CHANNEL_EVENTS.error:
				var reset_rejoin := is_joined()
				_error(message.get_payload())
				_start_rejoin(reset_rejoin)
		
			CHANNEL_EVENTS.close:
				if _state == ChannelStates.LEAVING:
					close({reason = "leave"})
				else:
					close({reason = "unexpected_close"}, true)
		
			_:
				_state = ChannelStates.JOINED if status == STATUS.ok else ChannelStates.ERRORED
				
				if _state == ChannelStates.JOINED:
					_joined_once = true
					_rejoin_pos = -1
				else:
					_joined_once = false
					_start_rejoin()
					
				emit_signal("on_join_result", status, message.get_response())
	
	# Event related to push replies, presence or broadcasts
	else:
		var event := message.get_event()
		
		# TODO: implement presence
		if event == PRESENCE_EVENTS.diff:
			pass
		else:		
			# Try to get event related to the reply
			if event == CHANNEL_EVENTS.reply:
				var pending_event = _get_pending_ref(message.get_ref())
				if pending_event:
					event = pending_event
					_pending_refs.erase(message.get_ref())

			if event != CHANNEL_EVENTS.leave:
				emit_signal("on_event", event, message.get_response(), status)
			
#
# Implementation
#

func _error(error):
	_state = ChannelStates.ERRORED
	emit_signal("on_error", error)
	
func _start_rejoin(reset := false):
	if reset:
		_rejoin_pos = -1
		_joined_once = false		
		
	if _rejoin_pos < DEFAULT_REJOIN_AFTER_SECONDS.size() - 1:
		_rejoin_pos += 1
		
	_rejoin_timer.set_wait_time(DEFAULT_REJOIN_AFTER_SECONDS[_rejoin_pos])
	
	if _rejoin_timer.is_stopped():
		_rejoin_timer.start()

	_should_rejoin_until_connected = true
	
func _rejoin() -> bool:
	if _state == ChannelStates.JOINING or _state == ChannelStates.JOINED:
		return false
		
	else:
		if _socket.can_push(CHANNEL_EVENTS.join):
			if _should_rejoin_until_connected and !_rejoin_timer.is_stopped():
				_rejoin_timer.stop()
				_should_rejoin_until_connected = false
				
			_state = ChannelStates.JOINING
			
			var ref = _socket.make_ref()
			_join_ref = ref
			_socket.push(_socket.compose_message(CHANNEL_EVENTS.join, _params, _topic, ref, _join_ref))
			return true
			
		else:
			_should_rejoin_until_connected = true
			return false
			
func _get_pending_ref(ref):	
	if _pending_refs.has(ref):
		return _pending_refs[ref]
			
	return null
	
#
# Listeners
#

func _on_Timer_timeout():
	if _should_rejoin_until_connected:
		if not _joined_once:
			_rejoin()
		
#
# Presence Inner Class
#

class Presence:
	var _state := {}
	
	func sync_state(new_state : Dictionary):		
		var joins := {}
		var leaves := {}
		
		var keys := _state.keys()
		for key in keys:
			if not new_state.has(key):
				leaves[key] = _state[key]
		
		var new_state_keys := new_state.keys()		
		for key in new_state_keys:			
			var new_presence = new_state[key]
			
			if _state.has(key):
				var current_presence = _state[key]
				var new_refs := PhoenixUtils.map(funcref(self, "_get_phx_ref"), new_presence)
				var curr_refs := PhoenixUtils.map(funcref(self, "_get_phx_ref"), current_presence)
				
				var joined_metas := _find_metas_from_refs(new_presence.metas, curr_refs)
				var left_metas := _find_metas_from_refs(current_presence.metas, new_refs)
						
				if joined_metas.size() > 0:
					joins[key] = new_presence
					joins[key].metas = joined_metas
					
				if left_metas.size() > 0:
					leaves[key] = current_presence.duplicate(true)
					leaves[key].metas = left_metas					
			
			else:
				joins[key] = new_presence
		
		return sync_diff({
			joins = joins,
			leaves = leaves
		})
		
	func sync_diff(diff):
		var joins = diff.joins
		var leaves = diff.leaves
		
		var keys = joins.keys()
		for key in keys:
			var new_presence = joins[key]			
			var current_presence = _state[key] if _state.has(key) else null
			_state[key] = new_presence
			
			if current_presence:
				for meta in current_presence.metas:
					_state[key].metas.push_front(meta)
			
			#on_join(key, current_presence, new_presence)
			
		keys = leaves.keys()
		for key in keys:
			var left_presence = leaves[key]
			
			if _state.has(key):
				var current_presence = _state[key]				
				var refs_to_remove = PhoenixUtils.map(funcref(self, "_get_phx_ref"), left_presence.metas)				
				current_presence.metas = _find_metas_from_refs(current_presence.metas, refs_to_remove)
				
				#on_leave(key, current_presence, left_presence)
				
				if current_presence.metas.size() == 0:
					_state.erase(key)
		
		return _state
		
	func list(chooser : FuncRef = null):
		if chooser:
			var sorted := []		
			for key in _state.keys():
				sorted.append(chooser.call_func(key, _state[key]))
							
			return sorted
		
		else:
			return _state.values()

	func _get_phx_ref(presence : Dictionary) -> String:
		return presence.phx_ref			
	
	func _find_metas_from_refs(metas : Array, refs : Array) -> Array:	
		var final_metas := []
			
		for meta in metas:
			var pos := refs.find(meta.phx_ref)
			if pos == -1:
				final_metas.append(meta)
		
		return final_metas