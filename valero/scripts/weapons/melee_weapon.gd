class_name MeleeWeapon
extends Weapon

@onready var _hitbox: Area3D = $Hitbox


func _perform_attack() -> void:
	for body in _hitbox.get_overlapping_bodies():
		_deal_damage(body)
