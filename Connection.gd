extends Node

var phoenix : Phoenix

func _ready():
	phoenix = Phoenix.new()
	phoenix.connect("on_event", self, "_on_channel_event")
	
	get_parent().call_deferred("add_child", phoenix)

func _on_channel_event(event, payload):
	print("received phoenix event: ", event, ", ", payload)