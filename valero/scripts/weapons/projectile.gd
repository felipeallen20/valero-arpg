class_name Projectile
extends Area3D

## Proyectil visible de un arma a distancia (cualquier forma: aquí, una esfera).
## Vuela en línea recta desde el Muzzle hasta impactar con algo o recorrer el
## rango del arma. Al impactar no calcula el daño por su cuenta: se lo delega
## al arma (Weapon.deal_damage), que aplica el daño y registra el combo.
##
## A quién puede dar lo define la máscara de colisión de la escena: esta
## variante (máscara 1) da al jugador y al mundo; para un arma en manos del
## jugador haría falta una variante con máscara 4 (enemigos).

var _weapon: Weapon
var _speed := 30.0
var _distance_left := 10.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


## Prepara el vuelo. speed (m/s): rapidez; weapon_range (m): distancia máxima
## que recorre antes de desaparecer (el rango del arma).
func launch(weapon: Weapon, speed: float, weapon_range: float) -> void:
	_weapon = weapon
	_speed = maxf(speed, 0.01)
	_distance_left = maxf(weapon_range, 0.01)


func _physics_process(delta: float) -> void:
	var step := _speed * delta
	_distance_left -= step
	if _distance_left <= 0.0:
		queue_free()
		return
	# Avanza por su -Z (el frente de Godot): es la orientación que le dio el
	# Muzzle al disparar.
	global_position -= global_transform.basis.z * step


func _on_body_entered(body: Node3D) -> void:
	# Ignora al empuñador por si el proyectil nace solapado con él.
	if _weapon != null and body == _weapon.wielder:
		return
	if _weapon != null:
		_weapon.deal_damage(body)
	# Un impacto consume el proyectil (aunque el objetivo no reciba daño,
	# por ejemplo la plataforma).
	queue_free()
