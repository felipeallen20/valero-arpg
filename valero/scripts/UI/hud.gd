extends CanvasLayer

const HEALTH_COLOR := Color("#c0392b")       # rojo
const STAMINA_COLOR := Color("#d9d9d9")      # blanco/gris
const RECOVERY_COLOR := Color("#e67e22")     # naranja del contragolpe
const BAR_BG_COLOR := Color(0.0, 0.0, 0.0, 0.55)
const BAR_BORDER_COLOR := Color(0.0, 0.0, 0.0, 0.8)
const TWEEN_TIME := 0.12

@onready var _health_bar: ProgressBar = %HealthBar
@onready var _stamina_bar: ProgressBar = %StaminaBar
@onready var _recovery_bar: ProgressBar = %RecoveryBar
@onready var _recovery_timer: Label = %RecoveryTimer

var _stats: PlayerStats
var _health_tween: Tween
var _stamina_tween: Tween


func _ready() -> void:
	_style_bar(_health_bar, HEALTH_COLOR)
	_style_bar(_stamina_bar, STAMINA_COLOR)
	_style_bar(_recovery_bar, RECOVERY_COLOR)

	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		push_warning("HUD: no hay ningún nodo en el grupo 'player'.")
		return

	_stats = player.get_node_or_null("PlayerStats") as PlayerStats
	if _stats == null:
		push_warning("HUD: el Player no tiene un hijo llamado 'PlayerStats'.")
		return

	if not _stats.is_node_ready():
		await _stats.ready

	_stats.health_changed.connect(_on_health_changed)
	_stats.stamina_changed.connect(_on_stamina_changed)
	_stats.recovery_started.connect(_on_recovery_started)
	_stats.recovery_updated.connect(_on_recovery_updated)
	_stats.recovery_ended.connect(_on_recovery_ended)

	_set_bar(_health_bar, _stats.health, _stats.max_health)
	_set_bar(_stamina_bar, _stats.stamina, _stats.max_stamina)
	_recovery_bar.visible = false
	_recovery_timer.visible = false

func _on_health_changed(current: float, maximum: float) -> void:
	_health_tween = _animate_bar(_health_bar, current, maximum, _health_tween)


func _on_stamina_changed(current: float, maximum: float) -> void:
	# La estamina cambia cada frame al regenerar: se asigna directo, sin tween.
	_set_bar(_stamina_bar, current, maximum)


# --- Recuperación por contragolpe ---
# La barra muestra cuánta vida queda por recuperar (value = pool sobre
# max_value = vida máxima) y el label la cuenta atrás de la ventana.
func _on_recovery_started(pool: float, duration: float) -> void:
	_recovery_bar.max_value = _stats.max_health
	_recovery_bar.visible = true
	_recovery_timer.visible = true
	_on_recovery_updated(pool, duration)


func _on_recovery_updated(pool: float, time_left: float) -> void:
	_recovery_bar.value = pool
	_recovery_timer.text = "Recupera %d  ·  %d s" % [ceili(pool), ceili(time_left)]


func _on_recovery_ended() -> void:
	_recovery_bar.visible = false
	_recovery_timer.visible = false


func _set_bar(bar: ProgressBar, current: float, maximum: float) -> void:
	bar.max_value = maximum
	bar.value = current


func _animate_bar(bar: ProgressBar, current: float, maximum: float, old_tween: Tween) -> Tween:
	bar.max_value = maximum
	if old_tween:
		old_tween.kill()
	var tween := create_tween()
	tween.tween_property(bar, "value", current, TWEEN_TIME)
	return tween


func _style_bar(bar: ProgressBar, fill_color: Color) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = BAR_BG_COLOR
	bg.set_corner_radius_all(3)
	bg.set_border_width_all(1)
	bg.border_color = BAR_BORDER_COLOR

	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(3)

	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
