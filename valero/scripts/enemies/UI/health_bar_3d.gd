class_name HealthBar3D
extends Node3D

@export var bar_size := Vector2(1.2, 0.12)
@export var border := 0.03
@export var fill_color := Color(0.85, 0.1, 0.1)
@export var back_color := Color(0.1, 0.1, 0.1)
@export var flash_color := Color.WHITE
@export var hide_when_full := true

var _fill_mesh: QuadMesh
var _fill_material: StandardMaterial3D
var _tween: Tween
var _flash_tween: Tween

# Proporción mostrada (0..1). Se anima con un Tween; al cambiar, redibuja el relleno.
var _display_ratio := 1.0:
	set(value):
		_display_ratio = clampf(value, 0.0, 1.0)
		_update_fill()


func _ready() -> void:
	# Fondo (un poco más grande que el relleno para dar efecto de borde)
	var back_mesh := QuadMesh.new()
	back_mesh.size = bar_size + Vector2.ONE * border * 2.0
	back_mesh.material = _make_material(back_color)
	_add_quad(back_mesh)

	# Relleno
	_fill_mesh = QuadMesh.new()
	_fill_material = _make_material(fill_color)
	_fill_mesh.material = _fill_material
	_add_quad(_fill_mesh)

	_update_fill()


## Actualiza la barra. ratio = vida actual / vida máxima.
func set_ratio(ratio: float, animate := true) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	if hide_when_full:
		visible = ratio < 1.0

	if not animate:
		_display_ratio = ratio
		return

	var took_damage := ratio < _display_ratio
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "_display_ratio", ratio, 0.2) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	if took_damage:
		_flash()


func _flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_fill_material.albedo_color = flash_color
	_flash_tween = create_tween()
	_flash_tween.tween_property(_fill_material, "albedo_color", fill_color, 0.15)


# El relleno se ancla a la izquierda: se reduce el ancho del quad y se desplaza
# su centro dentro de la propia malla (así el billboard no lo separa del fondo).
func _update_fill() -> void:
	if _fill_mesh == null:
		return
	var w := maxf(bar_size.x * _display_ratio, 0.0001)
	_fill_mesh.size = Vector2(w, bar_size.y)
	_fill_mesh.center_offset = Vector3(-(bar_size.x - w) * 0.5, 0.0, 0.01)


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return material


func _add_quad(mesh: Mesh) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
