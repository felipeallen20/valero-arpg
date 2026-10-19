class_name EnemyBase
extends CharacterBody3D

## Base común de los enemigos: vida, gravedad, daño recibido, números
## de daño flotantes, muerte, localización/orientación hacia el jugador, su
## cono de visión (`vision_range` / `vision_angle`), que decide cuándo empiezan
## a trackearlo, y el merodeo (patrón de espera) con su indicador de mirada.
## La IA concreta va en las clases hijas.

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
## Distancia de "toque" (m): si el jugador está a esta distancia o menos, se
## detecta sin mirar ni ángulo. Evita que un enemigo empuje al jugador sin
## darse cuenta si tropieza con él.
const VISION_TOUCH_DISTANCE := 1.2

# --- Merodeo (comportamiento mientras no persigue a nadie) ---
## STAND = quieto en su sitio mirando alrededor; PING_PONG = va y viene entre
## los puntos; LOOP = los recorre en orden y vuelve al primero.
enum PatrolPattern { STAND, PING_PONG, LOOP }

@export_group("Merodeo")
@export var patrol_pattern := PatrolPattern.STAND
## Puntos del recorrido como desplazamientos respecto a la posición de
## aparición (el eje Y se ignora: se camina en el plano).
@export var patrol_points: PackedVector3Array = []
## Velocidad al merodear (m/s). Suele ser menor que la de persecución.
@export var patrol_speed := 1.5
## Pausa en cada punto: se elige un valor al azar entre ambos (segundos).
@export var patrol_wait_min := 1.0
@export var patrol_wait_max := 3.0
## Margen (± grados) de cada mirada alrededor mientras está quieto.
@export var patrol_look_angle := 70.0
## Segundos entre una mirada alrededor y la siguiente.
@export var patrol_look_interval := 1.6

@export_group("Vida")
@export var max_health := 75.0

@export_group("Postura")
## Puntos de postura (equilibrio) que caben en la barra. Al llenarse, el
## enemigo se aturde. La barra es interna: no se muestra al jugador.
@export var posture_max := 100.0
## Segundos sin recibir golpes antes de que la postura empiece a decaer.
@export var posture_grace_time := 1.2
## Puntos de barra perdidos por segundo tras pasar la gracia.
@export var posture_decay_rate := 20.0
## Segundos que dura el aturdimiento al romperse la postura.
@export var posture_break_duration := 1.5
## Segundos de inmunidad a otra rotura tras recuperarse del aturdimiento.
@export var posture_break_immunity := 1.5

@onready var _health_bar: HealthBar3D = $HealthBar
@onready var _model: MeshInstance3D = get_node_or_null("Model") as MeshInstance3D

var health := 0.0
var _player: Node3D
var _player_stats: PlayerStats
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))

# --- Postura (equilibrio): estado ---
var posture := 0.0
var _posture_grace_left := 0.0
var _posture_immunity_left := 0.0
var _stagger_left := 0.0

# --- Feedback de la rotura de postura ---
const STAGGER_TEXT_COLOR := Color(1.0, 0.72, 0.15)   # ámbar del "Aturdido".
const STAGGER_FLASH_COLOR := Color(1.0, 0.9, 0.4)    # destello del cuerpo.
# Parte de postura que sigue acumulando durante el aturdimiento (anti
# stun-lock: permite encadenar roturas sin que el enemigo no pueda reaccionar).
const POSTURE_DURING_STAGGER := 0.5

# true desde que el jugador fue detectado por primera vez. La detección no se
# olvida: una vez visto, el enemigo lo trackea aunque después salga del cono.
var is_tracking := false

# --- Estado del merodeo (solo lo usa la IA en reposo) ---
# Punto de partida: los patrol_points son desplazamientos respecto a él.
const PATROL_ARRIVE_DISTANCE := 0.5
var _patrol_spawn_origin := Vector3.ZERO
var _patrol_index := 0
var _patrol_step := 1          # +1/-1: sentido del vaivén en PING_PONG.
var _patrol_wait_left := 0.0
var _look_yaw := 0.0           # Rumbo objetivo de la última mirada alrededor.
var _look_timer := 0.0         # Tiempo hasta la siguiente mirada.

# --- Indicador de mirada (ojo de la cara) ---
# Su color comunica el estado: calmado o ya detectado.
const EYE_COLOR_CALM := Color(0.8, 0.95, 1.0)
const EYE_COLOR_ALERT := Color(1.0, 0.3, 0.25)
@onready var _eye: MeshInstance3D = get_node_or_null("FacingIndicator/Eye") as MeshInstance3D

# --- Material del cuerpo (para el destello de aturdimiento) ---
var _model_material: StandardMaterial3D
var _model_base_color := Color.WHITE
var _flash_tween: Tween

# --- Barra de postura de depuración (F3) ---
# Alterna el jugador con F3 en builds de debug. Fuera de debug no se puede
# encender: el input ni siquiera llega.
static var posture_debug_visible := false
var _posture_debug_bar: HealthBar3D


func _ready() -> void:
	health = max_health
	_health_bar.set_ratio(1.0, false)
	# Mantiene al enemigo pegado al suelo en pendientes y escalones pequeños.
	floor_snap_length = 0.3
	_patrol_spawn_origin = global_position
	_look_yaw = rotation.y
	_look_timer = randf() * patrol_look_interval
	_setup_eye()
	_setup_model_material()
	_setup_posture_debug_bar()
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
	# Toque directo: da igual el ángulo o si se está de espaldas, se detecta.
	if distance <= VISION_TOUCH_DISTANCE:
		return true
	if distance > vision_range:
		return false
	var forward := -global_basis.z
	return rad_to_deg(forward.angle_to(_direction_to_player())) <= vision_angle * 0.5


## El enemigo pasa a trackear al jugador. La detección es de por vida: no se
## resetea aunque el jugador vuelva a salir del cono de visión.
func detect_player() -> void:
	if is_tracking:
		return
	is_tracking = true
	# El ojo se enciende en rojo: se ve de un vistazo que ya te tiene.
	_set_eye_color(EYE_COLOR_ALERT)


## El frente del cuerpo es -Z (convención de Godot), misma fórmula que el
## Player. Gira el cuerpo hacia una dirección (plana, sin alturas) con la
## suavidad de turn_speed. Es la base de _face_player y del merodeo.
func _face_direction(direction: Vector3, delta: float) -> void:
	if direction == Vector3.ZERO:
		return
	var target_angle := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_angle, 1.0 - exp(-turn_speed * delta))


func _face_player(delta: float) -> void:
	_face_direction(_direction_to_player(), delta)


# --- Merodeo ---
# Lo usan las hijas mientras el jugador no esté detectado. Solo escribe
# velocity X/Z: la gravedad y el desplazamiento los aplica cada hija.

## true si hay un patrón con puntos que recorrer.
func _has_patrol_route() -> bool:
	return patrol_pattern != PatrolPattern.STAND and patrol_points.size() >= 2


## Mueve el cuerpo por el patrón, o lo deja quieto mirando alrededor si no
## hay ruta. Al llegar a un punto hace una pausa aleatoria y echa una mirada.
func _update_patrol(delta: float) -> void:
	if not _has_patrol_route() or _patrol_wait_left > 0.0:
		if _patrol_wait_left > 0.0:
			_patrol_wait_left -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		_idle_look_around(delta)
		return

	var target := _patrol_spawn_origin + patrol_points[_patrol_index]
	var to_target := target - global_position
	to_target.y = 0.0
	if to_target.length() <= PATROL_ARRIVE_DISTANCE:
		_next_patrol_point()
		return
	var direction := to_target.normalized()
	velocity.x = direction.x * patrol_speed
	velocity.z = direction.z * patrol_speed
	_face_direction(direction, delta)


## Elige el punto siguiente según el patrón y prepara la pausa del nuevo punto.
func _next_patrol_point() -> void:
	match patrol_pattern:
		PatrolPattern.PING_PONG:
			if _patrol_index >= patrol_points.size() - 1:
				_patrol_step = -1
			elif _patrol_index <= 0:
				_patrol_step = 1
			_patrol_index = clampi(_patrol_index + _patrol_step, 0, patrol_points.size() - 1)
		PatrolPattern.LOOP:
			_patrol_index = (_patrol_index + 1) % patrol_points.size()
	_patrol_wait_left = randf_range(patrol_wait_min, patrol_wait_max)
	# Fuerza una mirada nueva justo al parar.
	_look_timer = 0.0


## Mirada alrededor: cada cierto tiempo elige un rumbo nuevo (dentro de
## ±patrol_look_angle del actual) y gira hacia él despacio. Es lo que rompe la
## sensación de que el enemigo es un cápsula clavada mirando al vacío.
func _idle_look_around(delta: float) -> void:
	_look_timer -= delta
	if _look_timer <= 0.0:
		_look_timer = patrol_look_interval * randf_range(0.7, 1.4)
		_look_yaw = rotation.y + deg_to_rad(randf_range(-patrol_look_angle, patrol_look_angle))
	rotation.y = lerp_angle(rotation.y, _look_yaw, 1.0 - exp(-turn_speed * 0.4 * delta))


# --- Indicador de mirada ---
## Cada enemigo necesita su propio material de ojo: los recursos de las escenas
## se comparten, así que sin duplicarlo cambiar el color de uno cambiaría a todos.
func _setup_eye() -> void:
	if _eye == null:
		return
	var mat := _eye.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return
	_eye.set_surface_override_material(0, mat.duplicate() as StandardMaterial3D)
	_set_eye_color(EYE_COLOR_CALM)


func _set_eye_color(color: Color) -> void:
	if _eye == null:
		return
	var mat := _eye.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return
	mat.albedo_color = color
	if mat.emission_enabled:
		mat.emission = color


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


# --- Postura (equilibrio) ---
## true mientras dure el aturdimiento por postura rota. Las hijas lo consultan
## para suspender su IA (perseguir/apuntar) mientras tanto.
func is_staggered() -> bool:
	return _stagger_left > 0.0


## Empuja la barra de postura con este golpe. Lo llama el arma con el resultado
## de su fórmula (Weapon._apply_posture): el empujón se define en el arma,
## pero la barra y sus reglas viven aquí, en el enemigo.
func add_posture(amount: float) -> void:
	if is_dead() or _posture_immunity_left > 0.0:
		return
	# Durante el aturdimiento la barra avanza a medias (anti stun-lock).
	if is_staggered():
		amount *= POSTURE_DURING_STAGGER
	posture = minf(posture + amount, posture_max)
	_posture_grace_left = posture_grace_time
	if posture >= posture_max and not is_staggered():
		break_posture()


## Rota la postura: barra a cero, aturdimiento y feedback (texto "Aturdido"
## y destello del cuerpo). El texto usa el mismo patrón que los números de
## daño flotantes.
func break_posture() -> void:
	posture = 0.0
	_stagger_left = posture_break_duration
	DamageNumber.spawn(
		get_tree().current_scene, global_position, 0.0, STAGGER_TEXT_COLOR, "Aturdido"
	)
	_flash_stagger()


## Descuenta el aturdimiento (al llegar a cero aplica la inmunidad posterior)
## y, cuando toca, hace decaer la postura tras la gracia. Lo llaman las hijas
## cada frame; también actualiza la barra de depuración.
func _update_posture(delta: float) -> void:
	if is_staggered():
		_stagger_left = maxf(_stagger_left - delta, 0.0)
		if _stagger_left <= 0.0:
			_posture_immunity_left = posture_break_immunity
	elif _posture_immunity_left > 0.0:
		_posture_immunity_left -= delta
	elif _posture_grace_left > 0.0:
		_posture_grace_left -= delta
	else:
		posture = maxf(posture - posture_decay_rate * delta, 0.0)
	_update_posture_debug_bar()


# --- Feedback de la rotura ---

## Cada enemigo necesita su propio material de cuerpo: duplica el de la escena
## para poder destellar sin cambiar el material original (mismo criterio que
## el ojo del indicador de mirada).
func _setup_model_material() -> void:
	if _model == null:
		return
	var mat := _model.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return
	_model_material = mat.duplicate() as StandardMaterial3D
	_model.set_surface_override_material(0, _model_material)
	_model_base_color = _model_material.albedo_color


func _flash_stagger() -> void:
	if _model_material == null:
		return
	if _flash_tween != null:
		_flash_tween.kill()
	_model_material.albedo_color = STAGGER_FLASH_COLOR
	_flash_tween = create_tween()
	_flash_tween.tween_property(_model_material, "albedo_color", _model_base_color, 0.25)


# --- Barra de postura de depuración (F3) ---

func _setup_posture_debug_bar() -> void:
	_posture_debug_bar = HealthBar3D.new()
	_posture_debug_bar.bar_size = Vector2(1.0, 0.08)
	_posture_debug_bar.fill_color = Color(0.95, 0.78, 0.2)
	_posture_debug_bar.hide_when_full = false
	_posture_debug_bar.visible = false
	add_child(_posture_debug_bar)
	# Encima de la barra de vida (y = 1.45 en las escenas de enemigo).
	_posture_debug_bar.position = Vector3(0.0, 1.65, 0.0)


func _update_posture_debug_bar() -> void:
	if _posture_debug_bar == null:
		return
	if _posture_debug_bar.visible != posture_debug_visible:
		_posture_debug_bar.visible = posture_debug_visible
	if posture_debug_visible:
		_posture_debug_bar.set_ratio(posture / maxf(posture_max, 0.01), false)
