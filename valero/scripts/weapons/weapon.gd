class_name Weapon
extends Node3D

signal attacked

@export var weapon_name := "Arma"
@export var damage := 10.0
## Ataques por segundo (1.0 = uno por segundo, 2.0 = dos por segundo).
@export_range(0.1, 10.0, 0.05, "or_greater") var attack_speed := 1.0
## Alcance en metros: largo del golpe (melee) o distancia máxima (rango).
@export var attack_range := 2.0

## Quién empuña el arma (el Player). Así el arma no se daña a sí misma.
var wielder: Node3D

var _next_attack_time_ms := 0


func can_attack() -> bool:
	return Time.get_ticks_msec() >= _next_attack_time_ms


## Intenta atacar. Devuelve true si el ataque se ejecutó.
func attack() -> bool:
	if not can_attack():
		return false
	_next_attack_time_ms = Time.get_ticks_msec() + int(1000.0 / maxf(attack_speed, 0.01))
	_perform_attack()
	attacked.emit()
	return true


## Cada tipo de arma sobrescribe esto.
func _perform_attack() -> void:
	pass


## Aplica el daño del arma a un objetivo, si sabe recibirlo.
func _deal_damage(target: Node) -> void:
	if target == wielder:
		return
	if target.has_method("take_damage"):
		target.take_damage(damage)
