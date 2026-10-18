class_name Enemy
extends EnemyBase

## Enemigo cuerpo a cuerpo: merodea su zona (patrulla) hasta ver al jugador
## dentro de su cono de visión, lo persigue y golpea a corta distancia. La
## detección solo ocurre una vez: a partir de ahí lo trackea aunque pierda el
## contacto visual. La vida, el daño recibido y la localización/orientación
## del jugador viven en EnemyBase.

enum State { IDLE, CHASE, ATTACK, DEAD }

# --- Persecución ---
@export_group("Persecución")
@export var move_speed := 3.0          # Velocidad máxima al perseguir (m/s).
@export var acceleration := 18.0       # Aceleración hacia move_speed (m/s²).
@export var stop_distance := 1.6       # Distancia a la que deja de acercarse.

# --- Ataque ---
@export_group("Ataque")
@export var attack_range := 2.0        # Alcance del golpe (m).
@export var attack_damage := 10.0      # Daño por golpe.
@export var attack_windup := 0.30      # Segundos de telegrafiado antes de pegar.
@export var attack_cooldown := 1.20    # Segundos entre golpes.

# Arranca en IDLE: no persigue hasta que el jugador entre en su cono.
var _state: State = State.IDLE
var _windup_left := 0.0
var _cooldown_left := 0.0


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return

	_apply_gravity(delta)
	_update_timers(delta)

	# Sin jugador vivo no hay a qué perseguir.
	if not _has_live_player():
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	match _state:
		State.IDLE:
			# Merodea su zona (o mira alrededor si no tiene patrón) sin encarar
			# al jugador: si lo encarase, su cono de visión apuntaría siempre a
			# él y detectar sería solo distancia.
			_try_detect_player()
			if _state == State.IDLE:
				_update_patrol(delta)
		State.CHASE:
			_chase_player(delta)
			_try_start_attack()
		State.ATTACK:
			_update_attack(delta)

	move_and_slide()


## IDLE → CHASE: entra el jugador en el cono (o ya estaba trackeado, p. ej.
## porque le has pegado) y a partir de ahí persigue sin límite de distancia.
func _try_detect_player() -> void:
	if not is_tracking and not can_see_player():
		return
	detect_player()
	_state = State.CHASE


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


# Las utilidades de distancia y orientación (_flat_distance_to_player,
# _direction_to_player y _face_player) viven en EnemyBase, compartidas con
# el enemigo a distancia.

func _update_timers(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)


func _die() -> void:
	_state = State.DEAD
	super._die()
