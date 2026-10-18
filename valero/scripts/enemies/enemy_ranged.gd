class_name EnemyRanged
extends EnemyBase

## Enemigo a distancia (cápsula verde). No persigue: merodea su zona siguiendo
## su patrón de patrulla hasta detectar al jugador en su cono de visión y, a
## partir de ahí, se queda quieto y encarado a él, usando un arma a distancia
## sin modelo ni textura (el nodo Weapon, que es quien tiene las propiedades de
## daño, cadencia y alcance) para lanzar proyectiles visibles mientras el
## jugador esté vivo y dentro del rango del arma. Si el jugador sale de ese
## rango, el enemigo deja de atacar pero sigue trackeándolo.

@onready var _weapon: RangedWeapon = $Weapon


func _ready() -> void:
	super._ready()
	# El arma sabe a quién pertenece (para no dañar a su empuñador y para
	# leerle el estado de combo si alguna vez lo empuña el jugador).
	_weapon.wielder = self


func _physics_process(delta: float) -> void:
	var live := not is_dead() and _has_live_player()
	if live and not is_tracking and can_see_player():
		detect_player()

	if live and is_tracking:
		# Ya no merodea: quieto y encarado al jugador; apunta y dispara solo
		# mientras esté además dentro del rango del arma.
		velocity.x = 0.0
		velocity.z = 0.0
		_face_player(delta)
		if _in_weapon_range():
			_aim_weapon()
			# El arma limita su propia cadencia (attack_speed): llamar cada
			# frame solo marca el ritmo al salir de rango.
			_weapon.attack()
	elif live:
		# Sin detectar: vigila su cono de visión y merodea su zona.
		_update_patrol(delta)
	else:
		# Sin jugador vivo: quieto en el sitio donde estaba.
		velocity.x = 0.0
		velocity.z = 0.0

	# Gravedad y apoyo en el suelo (comportamiento de EnemyBase). Siempre,
	# también antes de detectar, para que no se despegue del suelo.
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
