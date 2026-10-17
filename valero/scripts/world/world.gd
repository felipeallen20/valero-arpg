extends Node

#Player
@export var player : CharacterBody3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_spawn_player(player)
	print(player.position)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _spawn_player(player) -> void:
	player.position = Vector3(0, 1.2, 0)
