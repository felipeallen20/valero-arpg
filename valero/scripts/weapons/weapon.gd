class_name Weapon
extends Node3D

## Arma base. Define QUÉ es el combo de esta arma (su patrón y su efecto),
## pero no guarda el estado del combo: ese pertenece al empuñador (el Player).
## Así cada arma puede llevar su propio combo sin mezclar estados.
##
## Jerarquía: Weapon (base) → MeleeWeapon / RangedWeapon (categorías de
## comportamiento) → arma concreta (p. ej. PracticeSword). Las armas concretas
## sobrescriben get_damage_for_combo() o _on_hit_landed() para definir sus
## efectos específicos (sangrado, quemadura, etc.).

signal attacked

@export var weapon_name := "Arma"
@export var damage := 10.0
## Ataques por segundo (1.0 = uno por segundo, 2.0 = dos por segundo).
@export_range(0.1, 10.0, 0.05, "or_greater") var attack_speed := 1.0
## Alcance en metros: largo del golpe (melee) o distancia máxima (rango).
@export var attack_range := 2.0

@export_group("Ataque pesado")
## Golpes por segundo del ataque pesado. Es más lento que el normal por
## diseño: compensa con heavy_damage_multiplier. Debe casar con la duración
## de la animación pesada del arma.
@export_range(0.1, 10.0, 0.05, "or_greater") var heavy_attack_speed := 0.8
## Multiplicador de daño del ataque pesado sobre el daño normal (2.0 = doble).
@export var heavy_damage_multiplier := 2.0

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
# true si el swing en curso es el pesado (afecta al daño: ver get_current_damage).
var _is_heavy_swing := false
# true si el swing en curso ya contó para el combo. Evita que un golpe que
# atraviesa a varios enemigos de un solo swing sume el combo varias veces.
var _combo_counted_this_swing := false


func can_attack() -> bool:
	return Time.get_ticks_msec() >= _next_attack_time_ms


## Intenta atacar. Devuelve true si el ataque se ejecutó.
## El combo NO avanza aquí: solo lo hace si el golpe conecta con un objetivo
## (ver deal_damage). Así fallar el swing no suma combo.
func attack() -> bool:
	return _start_swing(false)


## Intenta atacar pesado (clic derecho). Igual que attack(), pero con su propia
## cadencia (más lenta) y su propio multiplicador de daño.
func heavy_attack() -> bool:
	return _start_swing(true)


## Arranca un swing, normal o pesado: fija el cooldown según la cadencia de ese
## swing, marca si es pesado y lo delega en la subclase. El combo NO avanza
## aquí: solo si el golpe conecta (ver deal_damage).
func _start_swing(heavy: bool) -> bool:
	if not can_attack():
		return false
	_is_heavy_swing = heavy
	var speed := heavy_attack_speed if heavy else attack_speed
	_next_attack_time_ms = Time.get_ticks_msec() + int(1000.0 / maxf(speed, 0.01))
	_combo_counted_this_swing = false
	if heavy:
		_perform_heavy_attack()
	else:
		_perform_attack()
	attacked.emit()
	return true


## Cada tipo de arma sobrescribe esto.
func _perform_attack() -> void:
	pass


## Ataque pesado. Por defecto reutiliza el ataque normal: un arma sin variante
## pesada propia sigue siendo usable con clic derecho.
func _perform_heavy_attack() -> void:
	_perform_attack()


# --- Combo: solo definición del arma ---
# El estado (golpes seguidos, ventana de gracia) vive en el empuñador.
# Aquí se define el patrón y el efecto que ese estado produce.

## true si la cantidad de golpes indicada activa el combo de esta arma.
func is_combo_active_for(combo_count: int) -> bool:
	return combo_count >= combo_size


## Efecto del combo sobre el daño de un golpe. Es el punto de extensión:
## el arma concreta puede sobrescribirlo para aplicar su propio efecto
## (quemadura, empujón, curación, etc.).
func get_damage_for_combo(combo_count: int) -> float:
	if is_combo_active_for(combo_count):
		return damage * (1.0 + combo_bonus)
	return damage


## Daño del próximo golpe, leyendo el estado de combo del empuñador.
## Un swing pesado multiplica ese daño por heavy_damage_multiplier.
func get_current_damage() -> float:
	var result := get_damage_for_combo(get_wielder_combo_count())
	if _is_heavy_swing:
		result *= heavy_damage_multiplier
	return result


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
		_on_hit_landed(target, damage_dealt)
		_register_combo_hit()
		# El empuñador puede usar ese daño para algo más (curación por
		# contragolpe, etc.). Solo lo procesa quien exponga el método.
		if wielder != null and wielder.has_method("register_damage_dealt"):
			wielder.register_damage_dealt(damage_dealt)


## Punto de extensión para efectos al impactar (sangrado, quemadura, etc.).
## Se llama UNA vez por golpe conectado, justo después de aplicar el daño.
## Las armas concretas lo sobrescriben; aquí no hace nada.
func _on_hit_landed(_target: Node, _damage_dealt: float) -> void:
	pass


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
