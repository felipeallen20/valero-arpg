class_name DamageNumber
extends Label3D

## Número de daño flotante: aparece sobre el objetivo, hace un "pop" de escala,
## salta hacia arriba y se desvanece. Se crea con DamageNumber.spawn().

const START_HEIGHT := 1.3      # Altura sobre el origen del objetivo donde aparece.
const RISE_DISTANCE := 1.0     # Metros que sube durante su vida.
const RISE_TIME := 0.55        # Segundos de la subida.
const POP_SCALE := 1.6         # Escala inicial (efecto de impacto).
const POP_TIME := 0.12
const FADE_TIME := 0.25        # Duración del desvanecido final.
const POSITION_JITTER := 0.2   # Desplazamiento aleatorio para que no se solapen.


func _init() -> void:
	# Siempre de cara a la cámara, legible sobre cualquier fondo.
	# Nota: en Label3D de Godot 4.7 la propiedad se llama "billboard" (no
	# billboard_mode) y el color del texto va con "modulate" (no font_color).
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	font_size = 80
	pixel_size = 0.005          # 80 * 0.005 ≈ 0.4 m de alto.
	modulate = Color(0.92, 0.16, 0.14)   # rojo del daño.
	outline_size = 16
	outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	# El texto no debe recibir luces (falso = unshaded, que es el valor por defecto).
	shaded = false


## Crea y anima un número de daño en la posición de mundo indicada.
## El nodo se añade a parent (mejor la escena actual, para que el número
## sobreviva si el enemigo muere justo después del golpe).
static func spawn(parent: Node, world_position: Vector3, amount: float) -> void:
	if parent == null:
		return
	var number := DamageNumber.new()
	number.text = str(int(round(amount)))
	parent.add_child(number)
	number.global_position = world_position + Vector3(
		randf_range(-POSITION_JITTER, POSITION_JITTER),
		START_HEIGHT,
		randf_range(-POSITION_JITTER, POSITION_JITTER)
	)
	number._play()


func _play() -> void:
	scale = Vector3.ONE * POP_SCALE
	var rise_target := global_position + Vector3(
		randf_range(-0.1, 0.1),
		RISE_DISTANCE,
		randf_range(-0.08, 0.08)
	)

	# Escala, subida y fundido en paralelo; la liberación espera a todos.
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector3.ONE, POP_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", rise_target, RISE_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, FADE_TIME) \
		.set_delay(RISE_TIME - FADE_TIME)
	tween.chain().tween_callback(queue_free)
