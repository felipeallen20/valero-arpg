class_name Enemy
extends CharacterBody3D

signal died

@export var max_health := 50.0
@onready var _health_bar: HealthBar3D = $HealthBar

var health := 0.0


func _ready() -> void:
	health = max_health
	_health_bar.set_ratio(1.0, false)


func take_damage(amount: float) -> void:
	if health <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	_health_bar.set_ratio(health / max_health)
	print("%s recibió %s de daño. Vida: %s/%s" % [name, amount, health, max_health])
	if health <= 0.0:
		_die()


func _die() -> void:
	print("%s murió" % name)
	died.emit()
	queue_free()
