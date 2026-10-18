class_name Weapon
extends Node3D

## Arma base. Define QUÉ es el combo de esta arma (su patrón y su efecto),
## pero no guarda el estado del combo: ese pertenece al empuñador (el Player).
## Así cada arma puede llevar su propio combo sin mezclar estados.

signal attacked

@export var weapon_name := "Arma"
@export var damage := 10.0
## Ataques por segundo (1.0 = uno por segundo, 2.0 = dos por segundo).
@export_range(0.1, 10.0, 0.05, "or_greater") var attack_speed := 1.0
## Alcance en metros: largo del golpe (melee) o distancia máxima (rango).
@export var attack_range := 2.0

@export_group("Combo")
## Golpes seguidos del empuñador que activan el combo de ESTE arma.
@export var combo_size := 3
## Efecto del combo activo sobre el daño (0.25 = +25%).
@export var combo_bonus := 0.25
## Segundos de gracia tras el último golpe antes de perder el combo.
@export var combo_window := 5.0

## Quién empuña el arma (el Player). Así el arma no se daña a sí misma
## y puede leer el estado de combo del empuñador.
var wielder: Node3D

var _next_attack_time_ms := 0
# true si el swing en curso ya contó para el combo. Evita que un golpe que
# atraviesa a varios enemigos de un solo swing sume el combo varias veces.
var _combo_counted_this_swing := false


func can_attack() -> bool:
	return Time.get_ticks_msec() >= _next_attack_time_ms


## Intenta atacar. Devuelve true si el ataque se ejecutó.
## El combo NO avanza aquí: solo lo hace si el golpe conecta con un objetivo
## (ver deal_damage). Así fallar el swing no suma combo.
func attack() -> bool:
	if not can_attack():
		return false
	_next_attack_time_ms = Time.get_ticks_msec() + int(1000.0 / maxf(attack_speed, 0.01))
	_combo_counted_this_swing = false
	_perform_attack()
	attacked.emit()
	return true


## Cada tipo de arma sobrescribe esto.
func _perform_attack() -> void:
	pass


# --- Combo: solo definición del arma ---
# El estado (golpes seguidos, ventana de gracia) vive en el empuñador.
# Aquí se define el patrón y el efecto que ese estado produce.

## true si la cantidad de golpes indicada activa el combo de esta arma.
func is_combo_active_for(combo_count: int) -> bool:
	return combo_count >= combo_size


## Efecto del combo sobre el daño de un golpe. Es el punto de extensión:
## cada arma puede sobrescribirlo para aplicar su propio efecto
## (quemadura, empujón, curación, etc.).
func get_damage_for_combo(combo_count: int) -> float:
	if is_combo_active_for(combo_count):
		return damage * (1.0 + combo_bonus)
	return damage


## Daño del próximo golpe, leyendo el estado de combo del empuñador.
func get_current_damage() -> float:
	return get_damage_for_combo(get_wielder_combo_count())


## Aplica el daño del arma a un objetivo, si sabe recibirlo.
## Este es el punto donde el golpe se considera "conectado": solo entonces
## (y una única vez por swing) avanza el combo del empuñador. Lo llaman tanto
## la hitbox melee como el proyectil al impactar.
func deal_damage(target: Node) -> void:
	if target == wielder:
		return
	if target.has_method("take_damage"):
		var damage_dealt := get_current_damage()
		target.take_damage(damage_dealt)
		_register_combo_hit()
		# El empuñador puede usar ese daño para algo más (curación por
		# contragolpe, etc.). Solo lo procesa quien exponga el método.
		if wielder != null and wielder.has_method("register_damage_dealt"):
			wielder.register_damage_dealt(damage_dealt)


## Informa al empuñador de que el swing conectó, para que sume a su combo.
## Como mucho una vez por swing, aunque el golpe toque varios objetivos.
func _register_combo_hit() -> void:
	if _combo_counted_this_swing:
		return
	_combo_counted_this_swing = true
	if wielder != null and wielder.has_method("register_combo_hit"):
		wielder.register_combo_hit()


## Golpes de combo actuales del empuñador. Devuelve 0 si no hay empuñador o
## si no expone el estado (por ejemplo, un arma usada fuera de un personaje).
func get_wielder_combo_count() -> int:
	if wielder != null and wielder.has_method("get_combo_count"):
		return wielder.get_combo_count()
	return 0
