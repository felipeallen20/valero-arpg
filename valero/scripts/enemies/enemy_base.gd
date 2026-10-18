class_name EnemyBase
extends CharacterBody3D

## Base común de todos los enemigos: vida, gravedad, daño recibido,
## números de daño flotantes y muerte.
## La IA (perseguir, ataque a distancia, etc.) va en las clases hijas.

signal died

@export_group("Vida")
@export var max_health := 75.0

@onready var _health_bar: HealthBar3D = $HealthBar

var health := 0.0
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


func _ready() -> void:
	health = max_health
	_health_bar.set_ratio(1.0, false)
	# Mantiene al enemigo pegado al suelo en pendientes y escalones pequeños.
	floor_snap_length = 0.3


## Sin IA propia el cuerpo solo aplica gravedad y se queda quieto; las
## hijas con comportamiento (perseguir, ataque a distancia...) lo sobrescriben.
func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	move_and_slide()


func is_dead() -> bool:
	return health <= 0.0


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	velocity.y -= _gravity * delta


# --- Daño recibido ---
func take_damage(amount: float) -> void:
	if is_dead():
		return
	health = maxf(health - amount, 0.0)
	_health_bar.set_ratio(health / max_health)
	# Número de daño flotante. Se añade a la escena actual (no al enemigo)
	# para que el golpe letal siga mostrándose aunque el enemigo muera.
	DamageNumber.spawn(get_tree().current_scene, global_position, amount)
	if is_dead():
		_die()


## Las hijas pueden sobrescribir para añadir lo suyo y llamar a super._die().
func _die() -> void:
	died.emit()
	queue_free()
