extends Node
## Entry point. Hands control to the App autoload.

func _ready() -> void:
	App.boot()
	queue_free()
