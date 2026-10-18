class_name Weapon
extends Node3D

signal attacked
## Se emite al cambiar el estado del combo (para la UI, sonidos, etc.).
signal combo_changed(count: int, active: bool)

@export var weapon_name := "Arma"
@export var damage := 10.0
## Ataques por segundo (1.0 = uno por segundo, 2.0 = dos por segundo).
@export_range(0.1, 10.0, 0.05, "or_greater") var attack_speed := 1.0
## Alcance en metros: largo del golpe (melee) o distancia máxima (rango).
@export var attack_range := 2.0

@export_group("Combo")
## Golpes seguidos necesarios para activar el combo.
@export var combo_size := 3
## Daño extra multiplicativo mientras el combo está activo (0.25 = +25%).
@export var combo_bonus := 0.25
## Segundos de gracia que se toleran tras el último golpe antes de perder el
## combo. Si el jugador para de atacar, el combo sigue vivo este tiempo.
@export var combo_window := 5.0

## Quién empuña el arma (el Player). Así el arma no se daña a sí misma.
var wielder: Node3D

var _next_attack_time_ms := 0
var _combo_count := 0
var _combo_time_left := 0.0


func _process(delta: float) -> void:
	if _combo_time_left <= 0.0:
		return
	_combo_time_left -= delta
	if _combo_time_left <= 0.0:
		_reset_combo()


func can_attack() -> bool:
	return Time.get_ticks_msec() >= _next_attack_time_ms


## Intenta atacar. Devuelve true si el ataque se ejecutó.
func attack() -> bool:
	if not can_attack():
		return false
	_next_attack_time_ms = Time.get_ticks_msec() + int(1000.0 / maxf(attack_speed, 0.01))
	_advance_combo()
	_perform_attack()
	attacked.emit()
	return true


## Cada tipo de arma sobrescribe esto.
func _perform_attack() -> void:
	pass


## Daño del próximo golpe, aplicando el bonus de combo si está activo.
func get_current_damage() -> float:
	if is_combo_active():
		return damage * (1.0 + combo_bonus)
	return damage


## Aplica el daño del arma a un objetivo, si sabe recibirlo.
func _deal_damage(target: Node) -> void:
	if target == wielder:
		return
	if target.has_method("take_damage"):
		target.take_damage(get_current_damage())


# --- Combo ---
## true si ya se encadenaron combo_size golpes dentro de la ventana.
func is_combo_active() -> bool:
	return _combo_count >= combo_size


## Cuenta un golpe nuevo y reinicia la ventana. Se cuenta el intento (swing),
## no el acierto: fallar no castiga, pero pararse sí rompe el combo.
func _advance_combo() -> void:
	_combo_count += 1
	_combo_time_left = combo_window
	combo_changed.emit(_combo_count, is_combo_active())


func _reset_combo() -> void:
	if _combo_count == 0:
		return
	_combo_count = 0
	_combo_time_left = 0.0
	combo_changed.emit(0, false)
