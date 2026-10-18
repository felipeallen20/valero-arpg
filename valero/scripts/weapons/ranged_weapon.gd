class_name RangedWeapon
extends Weapon

@export var projectile_scene: PackedScene
@export var projectile_speed := 30.0

@onready var _muzzle: Marker3D = $Muzzle


func _perform_attack() -> void:
	if projectile_scene == null:
		return
	var projectile := projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	projectile.global_transform = _muzzle.global_transform
	if projectile.has_method("launch"):
		projectile.launch(get_current_damage(), projectile_speed, attack_range, wielder)
