class_name EnemyBase
extends CharacterBody3D

## Base común de los enemigos: vida, gravedad, daño recibido, números
## de daño flotantes, muerte, localización/orientación hacia el jugador y su
## cono de visión (`vision_range` / `vision_angle`), que decide cuándo empiezan
## a trackearlo. La IA concreta va en las clases hijas.

signal died

# --- Referencia al jugador ---
## Si está vacío, se busca automáticamente en el grupo "player" al arrancar.
@export var player_path: NodePath
## Rapidez con la que encara al jugador (giro suave).
@export var turn_speed := 10.0

@export_group("Visión")
## Distancia máxima (plana, en metros) a la que puede detectar al jugador.
@export var vision_range := 12.0
## Ángulo total del cono de visión frontal, en grados (110 = ±55°).
@export var vision_angle := 110.0

@export_group("Vida")
@export var max_health := 75.0

@onready var _health_bar: HealthBar3D = $HealthBar

var health := 0.0
var _player: Node3D
var _player_stats: PlayerStats
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))

# true desde que el jugador fue detectado por primera vez. La detección no se
# olvida: una vez visto, el enemigo lo trackea aunque después salga del cono.
var is_tracking := false


func _ready() -> void:
	health = max_health
	_health_bar.set_ratio(1.0, false)
	# Mantiene al enemigo pegado al suelo en pendientes y escalones pequeños.
	floor_snap_length = 0.3
	_resolve_player()


## Localiza al jugador: por ruta explícita o, si no, por el grupo "player".
func _resolve_player() -> void:
	if player_path != NodePath(""):
		_player = get_node_or_null(player_path) as Node3D
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D

	if _player == null:
		push_warning("Enemy: no se encontró ningún jugador (grupo 'player').")
		set_physics_process(false)
		return

	_player_stats = _player.get_node_or_null("PlayerStats") as PlayerStats


## true si hay un jugador vivo al que perseguir o apuntar.
func _has_live_player() -> bool:
	return _player != null and (_player_stats == null or not _player_stats.is_dead())


## Distancia horizontal (ignora la altura) al jugador.
func _flat_distance_to_player() -> float:
	return Vector2(
		global_position.x - _player.global_position.x,
		global_position.z - _player.global_position.z
	).length()


func _direction_to_player() -> Vector3:
	var dir := _player.global_position - global_position
	dir.y = 0.0
	return dir.normalized() if dir.length_squared() > 0.0001 else Vector3.ZERO


## true si el jugador está dentro del cono de visión (distancia + ángulo con
## el frente del enemigo, que apunta a -Z como el jugador). Es una comprobación
## geométrica: no comprueba línea de vista, así que valdría aunque hubiera una
## pared en medio (la arena actual no tiene obstáculos).
func can_see_player() -> bool:
	if _player == null or not _has_live_player():
		return false
	var distance := _flat_distance_to_player()
	# Pegadísimo: da igual el ángulo, está encima y se ve.
	if distance <= 0.05:
		return true
	if distance > vision_range:
		return false
	var forward := -global_basis.z
	return rad_to_deg(forward.angle_to(_direction_to_player())) <= vision_angle * 0.5


## El enemigo pasa a trackear al jugador. La detección es de por vida: no se
## resetea aunque el jugador vuelva a salir del cono de visión.
func detect_player() -> void:
	is_tracking = true


# El frente del cuerpo es -Z (convención de Godot), misma fórmula que el Player.
func _face_player(delta: float) -> void:
	var direction := _direction_to_player()
	if direction == Vector3.ZERO:
		return
	var target_angle := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_angle, 1.0 - exp(-turn_speed * delta))


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
	# Un golpe revela al jugador aunque esté fuera del cono (lo estás tocando).
	detect_player()
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
