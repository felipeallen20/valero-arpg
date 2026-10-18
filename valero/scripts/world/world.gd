extends Node

#Player
@export var player : CharacterBody3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_spawn_player(player)

func _spawn_player(player: CharacterBody3D) -> void:
	player.position = Vector3(0, 1.2, 0)
