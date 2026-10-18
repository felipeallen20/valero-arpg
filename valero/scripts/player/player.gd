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

# --- Sprint ---
const SPRINT_SPEED := 12.0                   # Velocidad máxima al correr (m/s).
const SPRINT_STAMINA_COST := 12.0            # Estamina por segundo (con 100 de máx. ≈ 8 s de sprint).
const SPRINT_MIN_STAMINA_TO_START := 15.0    # Mínimo para (re)empezar a correr.

var _is_sprinting := false

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

# --- Feedback de combo ---
const COMBO_OUTLINE_COLOR := Color(1.0, 0.85, 0.1)  # Amarillo del combo.
const COMBO_OUTLINE_THICKNESS := 0.06               # Grosor del contorno (m).
const COMBO_FADE_TIME := 0.15                       # Fundido de entrada/salida.
const COMBO_PULSE_TIME := 0.5                       # Duración de cada pulso.

# --- Combo: estado ---
# El estado del combo vive AQUÍ (en el jugador). La definición de cada combo
# (cuántos golpes, ventana de gracia y efecto) la pone el arma empuñada, así
# que cada arma puede tener el suyo sin mezclar estados.
signal combo_changed(count: int, active: bool)

var combo_count := 0
var _combo_time_left := 0.0

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
@onready var _weapon: Weapon = $PracticeSword
@onready var _model: MeshInstance3D = $Model

# --- Feedback de combo ---
var _combo_outline: MeshInstance3D
var _combo_outline_material: StandardMaterial3D
var _combo_fade_tween: Tween
var _combo_pulse_tween: Tween

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

	_setup_combo_outline()
	# El contorno se alimenta de la señal del propio jugador (ya no del arma).
	combo_changed.connect(_on_combo_changed)


# --- Feedback de combo ---
# Crea un "inverted hull": una copia de la malla del modelo, agrandada por sus
# normales y con las caras traseras visibles. Eso dibuja un contorno alrededor
# del cuerpo sin tocar el material original.
# Nota: en Godot 4.7 grow/grow_amount viven en el material (BaseMaterial3D),
# no en el nodo GeometryInstance3D como en versiones anteriores.
func _setup_combo_outline() -> void:
	_combo_outline_material = StandardMaterial3D.new()
	_combo_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_combo_outline_material.albedo_color = Color(COMBO_OUTLINE_COLOR, 0.0)
	_combo_outline_material.cull_mode = BaseMaterial3D.CULL_FRONT
	_combo_outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_combo_outline_material.no_depth_test = false
	_combo_outline_material.grow = true
	_combo_outline_material.grow_amount = COMBO_OUTLINE_THICKNESS

	_combo_outline = MeshInstance3D.new()
	_combo_outline.mesh = _model.mesh
	_combo_outline.material_override = _combo_outline_material
	_combo_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_combo_outline.visible = false
	# Como hijo del modelo, hereda sus giros y desplazamientos.
	_model.add_child(_combo_outline)


func _on_combo_changed(_count: int, active: bool) -> void:
	_set_combo_outline(active)


func _set_combo_outline(active: bool) -> void:
	# Se mata cualquier tween previo para poder alternar el combo rápido.
	if _combo_fade_tween:
		_combo_fade_tween.kill()
	if _combo_pulse_tween:
		_combo_pulse_tween.kill()

	if active:
		_combo_outline.visible = true

	# Fundido de entrada o de salida.
	_combo_fade_tween = create_tween()
	_combo_fade_tween.tween_property(
		_combo_outline_material, "albedo_color:a", 1.0 if active else 0.0, COMBO_FADE_TIME
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	if active:
		# "Respiración" continua del contorno mientras dura el combo.
		_combo_pulse_tween = create_tween()
		_combo_pulse_tween.tween_property(
			_combo_outline_material, "albedo_color:a", 0.55, COMBO_PULSE_TIME
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_combo_pulse_tween.tween_property(
			_combo_outline_material, "albedo_color:a", 1.0, COMBO_PULSE_TIME
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_combo_pulse_tween.set_loops()
	else:
		_combo_fade_tween.tween_callback(_hide_combo_outline)


func _physics_process(delta: float) -> void:
	_update_dodge_timers(delta)
	_update_jump_assist(delta)
	_update_combo_timer(delta)
	_apply_gravity(delta)
	_try_jump()
	_try_dodge()

	if _is_dodging:
		_apply_dodge_movement()
	else:
		_try_attack()

		var direction := _input_direction()
		_update_sprint(direction, delta)
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
		var max_speed := SPRINT_SPEED if _is_sprinting else SPEED
		horizontal = horizontal.move_toward(direction * max_speed, accel * delta)
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
# Mantener el clic encadena ataques; el cooldown del marca el ritmo.
func _try_attack() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return  # con el mouse liberado (Esc) el clic no debe atacar
	if Input.is_action_pressed("attack"):
		# Solo avanza el combo si el arma aceptó el ataque (cooldown listo).
		if _weapon.attack():
			_advance_combo()
		
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

# --- Sprint ---
# Solo gasta estamina en el suelo. En el aire se conserva el estado que traías
# al saltar, así un salto corriendo mantiene el impulso sin drenar estamina.
func _update_sprint(direction: Vector3, delta: float) -> void:
	if not is_on_floor():
		return

	var wants_sprint := Input.is_action_pressed("sprint") and direction != Vector3.ZERO
	# Para empezar hace falta un mínimo; una vez corriendo, se sigue hasta agotar.
	var has_enough := stats.stamina > 0.0 if _is_sprinting else stats.has_stamina(SPRINT_MIN_STAMINA_TO_START)

	if wants_sprint and has_enough:
		# drain_stamina también pausa la regeneración mientras corres.
		_is_sprinting = stats.drain_stamina(SPRINT_STAMINA_COST * delta)
	else:
		_is_sprinting = false

func _on_died() -> void:
	set_physics_process(false)


# --- Combo: estado ---
# El jugador guarda el estado; el arma empuñada define qué significa ese
# estado (su patrón y su efecto). Así, cambiar de arma cambia el combo sin
# tocar este código.

## Golpes de combo acumulados. Lo consulta el arma (ver Weapon).
func get_combo_count() -> int:
	return combo_count


## true si el arma actual considera activo el combo actual.
func is_combo_active() -> bool:
	return _weapon != null and _weapon.is_combo_active_for(combo_count)


## Registra un golpe del arma actual: suma al combo y reinicia la ventana de
## gracia definida por el arma.
func _advance_combo() -> void:
	combo_count += 1
	_combo_time_left = _weapon.combo_window
	combo_changed.emit(combo_count, is_combo_active())


## Reinicia el combo (ventana agotada, muerte, cambio de arma...).
func _reset_combo() -> void:
	if combo_count == 0:
		return
	combo_count = 0
	_combo_time_left = 0.0
	combo_changed.emit(0, false)


## Cuenta hacia atrás la ventana de gracia del arma.
func _update_combo_timer(delta: float) -> void:
	if _combo_time_left <= 0.0:
		return
	_combo_time_left -= delta
	if _combo_time_left <= 0.0:
		_reset_combo()


## Cambia el arma activa. El combo se reinicia porque la definición del combo
## (patrón, ventana, efecto) depende del arma, y la nueva puede ser distinta.
func set_weapon(new_weapon: Weapon) -> void:
	if new_weapon == _weapon:
		return
	_reset_combo()
	if _weapon != null:
		_weapon.wielder = null
	_weapon = new_weapon
	if _weapon != null:
		_weapon.wielder = self


func _hide_combo_outline() -> void:
	_combo_outline.visible = false
