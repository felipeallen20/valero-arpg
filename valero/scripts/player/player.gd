extends CharacterBody3D

const SPEED := 6.5              # Velocidad máxima en el suelo (m/s).
const ACCELERATION := 40.0      # Aceleración en el suelo (m/s²).
const DECELERATION := 45.0      # Frenado al soltar las teclas (m/s²).

# Control aéreo. AIR_ACCELERATION debe ser alto para poder corregir la dirección
# en pleno salto (útil para explorar y esquivar); el rozamiento aéreo es suave
# para no cortar el impulso de un salto lanzado.
const AIR_ACCELERATION := 22.0  # Aceleración al dirigir en el aire (m/s²).
const AIR_DECELERATION := 8.0   # Rozamiento aéreo al no pulsar nada (m/s²).

# Salto. La altura se obtiene de JUMP_VELOCITY con la gravedad de subida; la
# caída usa más gravedad para aterrizar rápido y sentirse ágil. Al soltar el
# botón durante la subida se recorta el impulso para permitir saltos de altura
# variable.
const JUMP_VELOCITY := 6.0          # Impulso del salto (m/s). Altura ≈ 1.8 m.
const JUMP_CUT_MULTIPLIER := 0.45   # Recorte de impulso al soltar el salto subiendo.
const GRAVITY_SCALE_RISE := 1.0     # Gravedad mientras se sube (ligera).
const GRAVITY_SCALE_FALL := 1.8     # Gravedad mientras se cae (pesada = aterrizaje rápido).
const MAX_FALL_SPEED := 30.0        # Velocidad de caída máxima (m/s).

# Asistencia al salto para que no se pierda ninguna pulsación:
#   - Coyote time: aún se puede saltar un instante después de dejar el borde.
#   - Jump buffer: pulsar un poco antes de tocar el suelo guarda el salto.
const COYOTE_TIME := 0.12        # Segundos de gracia tras dejar el suelo.
const JUMP_BUFFER_TIME := 0.12   # Segundos que se recuerda una pulsación de salto.

const TURN_SPEED := 18.0         # Rapidez con la que el cuerpo encara hacia la marcha.

# --- Dash ---
const DODGE_SPEED := 24.0        # Velocidad inicial del dash (m/s).
const DODGE_DURATION := 0.25     # ≈ 3.4 m de distancia con la curva de abajo.
const DODGE_COOLDOWN := 0.40
const DODGE_IFRAMES := 0.22

const DODGE_STAMINA_COST := 25.0

@onready var stats: PlayerStats = $PlayerStats

var _is_dodging := false
var _dodge_time_left := 0.0
var _dodge_cooldown_left := 0.0
var _dodge_direction := Vector3.ZERO
var _is_invulnerable := false
var _iframe_time_left := 0.0
var _air_dash_available := true

# --- Referencias ---
@onready var _camera_pivot: Node3D = $ThirdPerson
@onready var _weapon: Weapon = $PracticeSword   # ← ajusta a tu ruta real

# --- Estado ---
# Se toma la gravedad del proyecto en lugar de fijar una propia, para respetar
# la configuración global de física.
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var _coyote_time_left := 0.0
var _jump_buffer_left := 0.0


func _ready() -> void:
	# Mantiene al jugador pegado al suelo en pendientes y escalones pequeños,
	# evitando que "flote" o pierda el contacto al bajar rampas suaves.
	floor_snap_length = 0.3
	_weapon.wielder = self
	stats.died.connect(_on_died)


func _physics_process(delta: float) -> void:
	_update_dodge_timers(delta)
	_update_jump_assist(delta)
	_apply_gravity(delta)
	_try_jump()
	_try_dodge()

	if _is_dodging:
		_apply_dodge_movement()
	else:
		_try_attack()

		var direction := _input_direction()
		_apply_horizontal_movement(direction, delta)
		_turn_body(direction, delta)

	move_and_slide()
	stats.invulnerable = _is_invulnerable


# --- Salto ---
# Actualiza los temporizadores de asistencia (coyote time y buffer de salto) y
# aplica el recorte de altura si se suelta el botón durante la subida.
func _update_jump_assist(delta: float) -> void:
	if is_on_floor():
		_coyote_time_left = COYOTE_TIME
	else:
		_coyote_time_left = maxf(_coyote_time_left - delta, 0.0)

	if Input.is_action_just_pressed("jump"):
		_jump_buffer_left = JUMP_BUFFER_TIME
	else:
		_jump_buffer_left = maxf(_jump_buffer_left - delta, 0.0)

	# Salto de altura variable: soltar pronto corta el impulso ascendente.
	if velocity.y > 0.0 and Input.is_action_just_released("jump"):
		velocity.y *= JUMP_CUT_MULTIPLIER


func _try_jump() -> void:
	if _jump_buffer_left > 0.0 and _coyote_time_left > 0.0:
		velocity.y = JUMP_VELOCITY
		# Se consumen ambos para no permitir un segundo salto en el aire.
		_jump_buffer_left = 0.0
		_coyote_time_left = 0.0


# --- Gravedad ---
func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var gravity_scale := GRAVITY_SCALE_RISE if velocity.y > 0.0 else GRAVITY_SCALE_FALL
	velocity.y -= _gravity * gravity_scale * delta
	velocity.y = maxf(velocity.y, -MAX_FALL_SPEED)


# --- Movimiento horizontal ---
# Dirección de avance en coordenadas de mundo, tomando como referencia el giro
# de la cámara: "adelante" siempre es hacia donde mira la cámara.
func _input_direction() -> Vector3:
	var input_vec := Input.get_vector("left", "right", "forward", "backward")
	if input_vec == Vector2.ZERO:
		return Vector3.ZERO
	var yaw := _camera_pivot.global_rotation.y
	return (Basis(Vector3.UP, yaw) * Vector3(input_vec.x, 0.0, input_vec.y)).normalized()


func _apply_horizontal_movement(direction: Vector3, delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if direction == Vector3.ZERO:
		var decel := DECELERATION if is_on_floor() else AIR_DECELERATION
		horizontal = horizontal.move_toward(Vector3.ZERO, decel * delta)
	else:
		var accel := ACCELERATION if is_on_floor() else AIR_ACCELERATION
		horizontal = horizontal.move_toward(direction * SPEED, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


# --- Orientación del cuerpo ---
# El frente del cuerpo es -Z (convención de Godot). Se interpola el giro para
# que el personaje mire hacia donde avanza sin dar giros bruscos. Cuando no hay
# desplazamiento, encara hacia donde mira la cámara para acompañar su giro.
#
# Se rota el Player completo (y no solo $Model) porque la espada cuelga del
# Player: así modelo y arma giran juntos y el giro se ve en pantalla.
func _turn_body(direction: Vector3, delta: float) -> void:
	var facing := direction
	if facing == Vector3.ZERO:
		# "Adelante" es hacia donde mira la cámara (misma convención que _input_direction).
		facing = Basis(Vector3.UP, _camera_pivot.global_rotation.y) * Vector3.FORWARD
	var target_angle := atan2(-facing.x, -facing.z)
	rotation.y = lerp_angle(rotation.y, target_angle, 1.0 - exp(-TURN_SPEED * delta))

# --- Ataque ---
# Mantener el clic encadena ataques; el cooldown del arma marca el ritmo.
func _try_attack() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return  # con el mouse liberado (Esc) el clic no debe atacar
	if Input.is_action_pressed("attack"):
		_weapon.attack()
		
# --- Dash ---
func _try_dodge() -> void:
	if not Input.is_action_just_pressed("dodge"):
		return
	if _is_dodging or _dodge_cooldown_left > 0.0:
		return
	if not stats.use_stamina(DODGE_STAMINA_COST):
		return
		_start_dodge()
	# Un solo dash en el aire por salto; se recarga al tocar el suelo.
	if not is_on_floor() and not _air_dash_available:
		return
	_start_dodge()


func _start_dodge() -> void:
	_is_dodging = true
	_dodge_time_left = DODGE_DURATION
	_dodge_cooldown_left = DODGE_COOLDOWN

	if not is_on_floor():
		_air_dash_available = false

	# Si hay input, se dashea hacia donde pulsas; si no, hacia donde mira el cuerpo.
	var dir := _input_direction()
	if dir == Vector3.ZERO:
		dir = -global_basis.z
	dir.y = 0.0
	_dodge_direction = dir.normalized()

	# El cuerpo encara el dash al instante (el giro normal está pausado durante el dash).
	rotation.y = atan2(-_dodge_direction.x, -_dodge_direction.z)

	_is_invulnerable = true
	_iframe_time_left = DODGE_IFRAMES


func _apply_dodge_movement() -> void:
	# Arranca a DODGE_SPEED y baja hasta SPEED: sale con tirón y termina
	# fluido, enlazando con la carrera sin frenazo.
	var t := 1.0 - (_dodge_time_left / DODGE_DURATION)
	var speed := lerpf(DODGE_SPEED, SPEED, t * t)
	velocity.x = _dodge_direction.x * speed
	velocity.z = _dodge_direction.z * speed

	# En el aire el dash es horizontal: sin gravedad mientras dura.
	if not is_on_floor():
		velocity.y = 0.0


func _update_dodge_timers(delta: float) -> void:
	_dodge_cooldown_left = maxf(_dodge_cooldown_left - delta, 0.0)

	if is_on_floor():
		_air_dash_available = true

	if _is_dodging:
		_dodge_time_left -= delta
		if _dodge_time_left <= 0.0:
			_is_dodging = false

	if _is_invulnerable:
		_iframe_time_left -= delta
		if _iframe_time_left <= 0.0:
			_is_invulnerable = false

func _on_died() -> void:
	set_physics_process(false)
	print("Jugador muerto")
