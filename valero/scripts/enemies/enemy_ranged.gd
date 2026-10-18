class_name EnemyRanged
extends EnemyBase

## Enemigo a distancia (cápsula verde). No persigue: usa un arma a distancia
## sin modelo ni textura (el nodo Weapon, que es quien tiene las propiedades
## de daño, cadencia y alcance) para lanzar proyectiles visibles mientras el
## jugador esté vivo y dentro del rango del arma. Si el jugador sale de ese
## rango, el enemigo deja de atacar y vuelve a su espera.

@onready var _weapon: RangedWeapon = $Weapon


func _ready() -> void:
	super._ready()
	# El arma sabe a quién pertenece (para no dañar a su empuñador y para
	# leerle el estado de combo si alguna vez lo empuña el jugador).
	_weapon.wielder = self


func _physics_process(delta: float) -> void:
	if not is_dead() and _has_live_player() and _in_weapon_range():
		_face_player(delta)
		_aim_weapon()
		# El arma limita su propia cadencia (attack_speed): llamar cada frame
		# solo marca el ritmo; al salir de rango simplemente se deja de llamar.
		_weapon.attack()
	# Gravedad y apoyo en el suelo (comportamiento de EnemyBase).
	super._physics_process(delta)


## true si el jugador vivo está al alcance del arma.
func _in_weapon_range() -> bool:
	return _flat_distance_to_player() <= _weapon.attack_range


## Orienta el arma hacia el jugador en los tres ejes (yaw y pitch), para que
## el proyectil salga en su dirección aunque salte o esté a otra altura.
func _aim_weapon() -> void:
	# look_at falla con direcciones degeneradas (jugador prácticamente encima
	# del cuerpo): en ese caso se mantiene la última orientación.
	var to_player := _player.global_position - _weapon.global_position
	if Vector2(to_player.x, to_player.z).length() <= 0.05:
		return
	_weapon.look_at(_player.global_position)
