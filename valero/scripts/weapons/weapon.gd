class_name Weapon
extends Node3D

@export var damage: float = 10.0
@export var attack_speed = 0.5

func attack() -> void:
	print("Ataque con daño: ", damage)
