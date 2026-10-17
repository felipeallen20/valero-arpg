extends Node3D

@export_group("Look")
@export var mouse_sensitivity := 0.003
@export_range(-89.0, 0.0) var pitch_min_deg := -60.0
@export_range(0.0, 89.0) var pitch_max_deg := 30.0
@export_range(-89.0, 89.0) var start_pitch_deg := -15.0

@export_group("Follow")
@export var pivot_height := 1.5
@export var follow_speed_xz := 14.0  # más alto = cámara más pegada
@export var follow_speed_y := 6.0    # más bajo en Y evita tirones al saltar/subir escalones

@export_group("Distance")
@export var default_distance := 4.0
@export var min_distance := 2.0
@export var max_distance := 7.0
@export var zoom_step := 0.5
@export var zoom_speed := 8.0
@export var shoulder_offset := 0.5   # 0 = centrada; positivo = sobre el hombro derecho

@onready var _spring_arm: SpringArm3D = $SpringArm3D
@onready var _target: Node3D = get_parent()

var _yaw := 0.0
var _pitch := 0.0
var _distance := 4.0


func _ready() -> void:
	# Independiente de la rotación del Player
	top_level = true

	_distance = default_distance
	_yaw = _target.global_rotation.y  # empieza detrás del personaje
	_pitch = deg_to_rad(start_pitch_deg)

	global_position = _target.global_position + Vector3.UP * pivot_height
	rotation = Vector3(_pitch, _yaw, 0.0)

	_spring_arm.spring_length = _distance
	_spring_arm.position = Vector3(shoulder_offset, 0.0, 0.0)
	if _target is CollisionObject3D:
		_spring_arm.add_excluded_object(_target.get_rid())

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative)
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(-zoom_step)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(zoom_step)
			MOUSE_BUTTON_LEFT:
				if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		_toggle_mouse_capture()


func _process(delta: float) -> void:
	_follow_target(delta)
	_spring_arm.spring_length = lerpf(
		_spring_arm.spring_length,
		_distance,
		1.0 - exp(-zoom_speed * delta)
	)


func _look(relative: Vector2) -> void:
	# Yaw libre: sin clamp, solo lo mantenemos en rango
	_yaw = wrapf(_yaw - relative.x * mouse_sensitivity, -PI, PI)
	_pitch = clampf(
		_pitch - relative.y * mouse_sensitivity,
		deg_to_rad(pitch_min_deg),
		deg_to_rad(pitch_max_deg)
	)
	# Sin suavizado: el mouse se aplica directo
	rotation = Vector3(_pitch, _yaw, 0.0)


func _follow_target(delta: float) -> void:
	var goal := _target.global_position + Vector3.UP * pivot_height
	var pos := global_position
	var k_xz := 1.0 - exp(-follow_speed_xz * delta)  # independiente del framerate
	var k_y := 1.0 - exp(-follow_speed_y * delta)
	pos.x = lerpf(pos.x, goal.x, k_xz)
	pos.z = lerpf(pos.z, goal.z, k_xz)
	pos.y = lerpf(pos.y, goal.y, k_y)
	global_position = pos


func _zoom(amount: float) -> void:
	_distance = clampf(_distance + amount, min_distance, max_distance)


func _toggle_mouse_capture() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
