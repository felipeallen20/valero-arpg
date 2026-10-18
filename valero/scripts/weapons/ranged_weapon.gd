class_name RangedWeapon
extends Weapon

## Categoría "a distancia": el comportamiento compartido por TODAS las armas
## de rango. No es un arma concreta: cada arma (p. ej. la ballesta de un enemigo)
## hereda de esta y define su propio proyectil y efectos.
##
## No tiene modelo ni textura: es la referencia del arma
## (daño, cadencia y alcance viven aquí, en Weapon). Sus proyectiles sí son
## visibles: cada disparo instancia projectile_scene en el Muzzle, orientado
## hacia donde apunte el arma (su -Z).
##
## El arma no decide cuándo dispara: quien la empuña (p. ej. EnemyRanged)
## llama a attack() mientras el objetivo esté dentro de attack_range.

@export var projectile_scene: PackedScene
@export var projectile_speed := 30.0

@onready var _muzzle: Marker3D = $Muzzle


func _perform_attack() -> void:
	if projectile_scene == null or _muzzle == null:
		return
	var projectile := projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	projectile.global_transform = _muzzle.global_transform
	if projectile.has_method("launch"):
		# El proyectil guarda el arma: al impactar resuelve él el daño y el
		# combo (Weapon.deal_damage), así que el golpe queda "conectado".
		projectile.launch(self, projectile_speed, attack_range)
