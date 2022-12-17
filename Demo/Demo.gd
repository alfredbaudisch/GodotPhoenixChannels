extends Control

@onready var _username = get_node("MainContainer/ControlRoom/ServerConnect/Username")
@onready var _host = get_node("MainContainer/ControlRoom/ServerConnect/Host")
@onready var _connect = get_node("MainContainer/ControlRoom/ServerConnect/Connect")
@onready var _topic = get_node("MainContainer/ControlRoom/ChannelJoin/Topic")
@onready var _join_topic = get_node("MainContainer/ControlRoom/ChannelJoin/JoinTopic")
@onready var _log = get_node("MainContainer/ControlRoom/Log")
@onready var _users_online = get_node("MainContainer/Presence/UsersOnline")
@onready var _presence_list = get_node("MainContainer/Presence/PresenceList")
@onready var _socket_status = get_node("MainContainer/ControlRoom/Status/SocketStatus")
@onready var _channel_status = get_node("MainContainer/ControlRoom/Status/ChannelSatus")
@onready var _push_event = get_node("MainContainer/ControlRoom/Push/EventDetailsContainer/EventName")
@onready var _push_payload = get_node("MainContainer/ControlRoom/Push/EventDetailsContainer/Payload")
@onready var _push = get_node("MainContainer/ControlRoom/Push/PushActions/Push")
@onready var _push_container = get_node("MainContainer/ControlRoom/Push")
@onready var _broadcast = get_node("MainContainer/ControlRoom/Push/PushActions/Broadcast")

var users := {}

var socket : PhoenixSocket
var channel : PhoenixChannel
var presence : PhoenixPresence

func _enter_tree():
	get_tree().connect("node_removed", _on_node_removed)
	
func _ready():
	_log.set_text("")
	_presence_list.clear()
	_set_socket_status("Not connected")
	_set_channel_status("Not connected")
	_join_topic.set_visible(false)
	_push_container.set_visible(false)
	
func _on_JoinTopic_pressed():
	if not socket:
		_print_log("No socket, can't join a channel")
	
	else:
		if not channel:
			if not presence:
				presence = PhoenixPresence.new()
				
				presence.connect("on_join", _on_Presence_join)
				presence.connect("on_leave", _on_Presence_leave)
			
			channel = socket.channel(_topic.get_text(), {}, presence)
			
			channel.connect("on_event", _on_Channel_event)
			channel.connect("on_join_result", _on_Channel_join_result)
			channel.connect("on_error", _on_Channel_error)
			channel.connect("on_close", _on_Channel_close)
				
		if channel.is_joined():
			channel.leave()
		elif channel.is_closed():
			channel.set_topic(_topic.get_text())
			channel.join()
	
func _on_Connect_pressed():
	if not socket:
		socket = PhoenixSocket.new(_host.get_text(), {
			params = {user_id = _username.get_text()}
		})
		
		socket.connect("on_open", _on_Socket_open)
		socket.connect("on_close", _on_Socket_close)
		socket.connect("on_error", _on_Socket_error)
		socket.connect("on_connecting", _on_Socket_connecting)
		
		call_deferred("add_child", socket, true)
		socket.connect_socket()
	
	elif socket:
		if socket.get_is_connected():
			socket.disconnect_socket()
		else:
			socket.set_endpoint(_host.get_text())
			socket.set_params({user_id = _username.get_text()})
			socket.connect_socket()
			
func _on_Push_pressed():
	var event : String = _push_event.get_text()
	var test_json_conv = JSON.new()
	test_json_conv.parse(_push_payload.get_text())	
	var payload : Dictionary = test_json_conv.get_data()
	
	# This is not a feature from this client library, instead
	# it just adds a parameter to the push payload, which the Demo Elixir server
	# recognizes and then performs a broadcast.
	if(_broadcast["pressed"]):
		payload.broadcast = true
	
	channel.push(event, payload)

	
#
# PhoenixSocket events
#

func _on_Socket_open(payload):	
	_set_socket_status("Connected / Open")	
	_set_channel_status("Not joined")
	_print_log("_on_Socket_open: " + str(payload))
	
	_connect.set_text("Disconnect")
	_join_topic.set_visible(true)
	
func _on_Socket_close(payload):
	_set_socket_status("Closed / Disconnected")
	_print_log("_on_Socket_close: " + str(payload))
	
	_connect.set_text("Connect")
	_join_topic.set_visible(false)
	_set_users_online_title()
	
func _on_Socket_error(payload):
	_set_socket_status("Errored")
	_print_log("_on_Socket_error: " + str(payload))
	
	_join_topic.set_visible(false)
	_push_container.set_visible(false)
	_set_users_online_title()

func _on_Socket_connecting(is_connecting):
	if is_connecting:
		_set_socket_status("Connecting...")
		_join_topic.set_visible(false)
		
	_print_log("_on_Socket_connecting: " + str(is_connecting))	
	
#
# PhoenixChannel events
#

func _on_Channel_event(event, payload, status):
	_print_log("_on_Channel_event:  " + event + ", status: " + status + ", payload: " + str(payload))
	
	if event == PhoenixChannel.PRESENCE_EVENTS.diff:
		presence.sync_diff(payload)		
	elif event == PhoenixChannel.PRESENCE_EVENTS.state:
		presence.sync_state(payload)
	
func _on_Channel_join_result(status, result):
	if status == PhoenixChannel.STATUS.ok:
		_set_channel_status("Joined - " + channel.get_topic())
		_join_topic.set_text("Leave Channel")
		_push_container.set_visible(true)
	else:
		_set_channel_status("Not joined")
		_join_topic.set_text("Join Channel")
		_push_container.set_visible(false)

	_set_users_online_title()
	_print_log("_on_Channel_join_result: " + status + ", " + str(result))
	
func _on_Channel_error(error):
	_print_log("_on_Channel_error: " + str(error))
	_set_channel_status("Errored")
	_join_topic.set_text("Join Channel")
	_push_container.set_visible(false)
	
func _on_Channel_close(closed):
	_print_log("_on_Channel_close: " + str(closed))
	_set_channel_status("Not joined")
	_join_topic.set_text("Join Channel")
	_push_container.set_visible(false)
	_set_users_online_title()
	
func _on_Presence_join(joins):
	for join in joins:
		if not users.has(join.key):
			users[join.key] = join.key
	_list_users()
	_print_log("_on_Presence_join: " + str(joins))
	
func _on_Presence_leave(leaves):
	for leave in leaves:
		if users.has(leave.key):
			users.erase(leave.key)
	_list_users()
	_print_log("_on_Presence_leave: " + str(leaves))

#
# Utils
#

func _list_users():
	var list := ""	
	for user in users:
		list += "- " + user + "\n"	
	_presence_list.set_text(list)

func _print_log(message):
	print(message)
	var time = Time.get_time_dict_from_system()
	_log.set_text(str(time.hour) + ":" + str(time.minute) + ":" + str(time.second) + ": " + str(message) + "\n" + _log.get_text())

func _set_socket_status(status):
	_socket_status.set_text("Socket: " + status)
	
func _set_channel_status(status):
	_channel_status.set_text("Channel: " + status)
	
func _set_users_online_title():
	var title := "Users Online"
	if channel and channel.is_joined():
		title += "\n" + channel.get_topic() + "\n==================="
	else:
		_presence_list.clear()
	_users_online.set_text(title)
	
func _on_RemoveSocket_pressed():
	if socket: socket.queue_free()

func _on_RemoveChannel_pressed():
	if channel: channel.queue_free()
	
func _on_node_removed(node):
	var cast = node as PhoenixChannel
	var clear_channel := false
	
	if cast:
		clear_channel = true
	else:
		cast = node as PhoenixSocket
		if cast:
			socket = null
			clear_channel = true
			
	if clear_channel:
		channel = null
		presence = null
		
func _on_ClearLog_pressed():
	_log.set_text("")
