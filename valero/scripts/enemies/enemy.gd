class_name Enemy
extends EnemyBase

## Enemigo cuerpo a cuerpo: persigue al jugador y golpea a corta distancia.
## La vida, el daño recibido y la muerte viven en EnemyBase.

enum State { CHASE, ATTACK, DEAD }

# --- Referencia al jugador ---
## Si está vacío, se busca automáticamente en el grupo "player" al arrancar.
@export var player_path: NodePath

# --- Persecución ---
@export_group("Persecución")
@export var move_speed := 3.0          # Velocidad máxima al perseguir (m/s).
@export var acceleration := 18.0       # Aceleración hacia move_speed (m/s²).
@export var turn_speed := 10.0         # Rapidez con la que encara al jugador.
@export var stop_distance := 1.6       # Distancia a la que deja de acercarse.

# --- Ataque ---
@export_group("Ataque")
@export var attack_range := 2.0        # Alcance del golpe (m).
@export var attack_damage := 10.0      # Daño por golpe.
@export var attack_windup := 0.30      # Segundos de telegrafiado antes de pegar.
@export var attack_cooldown := 1.20    # Segundos entre golpes.

var _state: State = State.CHASE
var _player: Node3D
var _player_stats: PlayerStats
var _windup_left := 0.0
var _cooldown_left := 0.0


func _ready() -> void:
	super._ready()
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


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return

	_apply_gravity(delta)
	_update_timers(delta)

	# Sin jugador vivo no hay a qué perseguir.
	if _player == null or (_player_stats != null and _player_stats.is_dead()):
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	match _state:
		State.CHASE:
			_chase_player(delta)
			_try_start_attack()
		State.ATTACK:
			_update_attack(delta)

	move_and_slide()


# --- Persecución ---
# Se acerca al jugador hasta stop_distance, acelerando y encarando suavemente.
func _chase_player(delta: float) -> void:
	var to_player := _flat_distance_to_player()
	if to_player <= stop_distance:
		# Ya está a rango: frena en seco y mira al jugador.
		_brake(delta)
		_face_player(delta)
		return

	var direction := _direction_to_player()
	velocity.x = move_toward(velocity.x, direction.x * move_speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * move_speed, acceleration * delta)
	_face_player(delta)


func _brake(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)


# --- Ataque ---
# Entra en ATTACK si el jugador está a alcance y el cooldown lo permite.
func _try_start_attack() -> void:
	if _cooldown_left > 0.0:
		return
	if _flat_distance_to_player() > attack_range:
		return
	_state = State.ATTACK
	_windup_left = attack_windup


# Fase de telegrafiado (windup) y, al terminar, aplicación del daño.
func _update_attack(delta: float) -> void:
	# Durante el telegrafiado no se mueve; sigue encarando al jugador.
	_brake(delta)
	_face_player(delta)

	_windup_left -= delta
	if _windup_left <= 0.0:
		_deal_attack()
		_state = State.CHASE
		_cooldown_left = attack_cooldown


# Aplica el daño solo si el jugador sigue vivo y a alcance en el momento exacto
# del golpe (así esquiar/dash deja de funcionar como defensa).
func _deal_attack() -> void:
	if _player == null or _player_stats == null:
		return
	if _flat_distance_to_player() > attack_range:
		return
	_player_stats.take_damage(attack_damage)


# --- Utilidades de distancia y orientación ---
# Distancia horizontal (ignora la altura) al jugador.
func _flat_distance_to_player() -> float:
	return Vector2(
		global_position.x - _player.global_position.x,
		global_position.z - _player.global_position.z
	).length()


func _direction_to_player() -> Vector3:
	var dir := _player.global_position - global_position
	dir.y = 0.0
	return dir.normalized() if dir.length_squared() > 0.0001 else Vector3.ZERO


# El frente del cuerpo es -Z (convención de Godot), misma fórmula que el Player.
func _face_player(delta: float) -> void:
	var direction := _direction_to_player()
	if direction == Vector3.ZERO:
		return
	var target_angle := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_angle, 1.0 - exp(-turn_speed * delta))


func _update_timers(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)


func _die() -> void:
	_state = State.DEAD
	super._die()
