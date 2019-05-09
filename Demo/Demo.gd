extends Control

onready var _username = get_node("HBoxContainer/ControlRoom/ServerConnect/Username")
onready var _host = get_node("HBoxContainer/ControlRoom/ServerConnect/Host")
onready var _connect = get_node("HBoxContainer/ControlRoom/ServerConnect/Connect")
onready var _topic = get_node("HBoxContainer/ControlRoom/ChannelJoin/Topic")
onready var _join_topic = get_node("HBoxContainer/ControlRoom/ChannelJoin/JoinTopic")
onready var _log = get_node("HBoxContainer/ControlRoom/Log")
onready var _presence_list = get_node("HBoxContainer/Presence/PresenceList")
onready var _socket_status = get_node("HBoxContainer/ControlRoom/Status/SocketStatus")
onready var _channel_status = get_node("HBoxContainer/ControlRoom/Status/ChannelSatus")

var socket : PhoenixSocket
var channel : PhoenixChannel
var presence : PhoenixPresence

func _ready():
	_log.clear()
	_presence_list.clear()
	_set_socket_status("Not connected")
	_set_channel_status("Not connected")
	
func _on_Connect_pressed():
	if not socket:
		socket = PhoenixSocket.new(_host.get_text(), {
			params = {user_id = _username.get_text()}
		})
		
		socket.connect("on_open", self, "_on_Socket_open")
		socket.connect("on_close", self, "_on_Socket_close")
		socket.connect("on_error", self, "_on_Socket_error")
		socket.connect("on_connecting", self, "_on_Socket_connecting")
		
		get_parent().call_deferred("add_child", socket, true)
		socket.connect_socket()
	
	elif socket:
		if socket.get_is_connected():
			socket.disconnect_socket()
		else:
			socket.set_endpoint(_host.get_text())
			socket.set_params({user_id = _username.get_text()})
			socket.connect_socket()

#
# PhoenixSocket events
#

func _on_Socket_open(payload):	
	_set_socket_status("Connected / Open")
	_log("_on_Socket_open: " + str(payload))
	
	_connect.set_text("Disconnect")
	
func _on_Socket_close(payload):
	_set_socket_status("Closed / Disconnected")
	_log("_on_Socket_close: " + str(payload))
	
	_connect.set_text("Connect")
	
func _on_Socket_error(payload):
	_set_socket_status("Errored")
	_log("_on_Socket_error: " + str(payload))

func _on_Socket_connecting(is_connecting):
	if is_connecting:
		_set_socket_status("Connecting...")
		
	_log("_on_Socket_connecting: " + str(is_connecting))
	
#
# Utils
#

func _log(message):
	print(message)
	_log.add_text(str(message) + "\n")

func _set_socket_status(status):
	_socket_status.set_text("Socket: " + status)
	
func _set_channel_status(status):
	_channel_status.set_text("Channel: " + status)
	
