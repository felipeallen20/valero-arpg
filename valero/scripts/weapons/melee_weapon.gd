class_name MeleeWeapon
extends Weapon

@onready var _anim: AnimationPlayer = $AnimationPlayer
@onready var _hitbox: Area3D = $Pivot/Hitbox

var _already_hit: Array[Node] = []


func _ready() -> void:
	_hitbox.monitoring = false
	_hitbox.body_entered.connect(_on_hitbox_body_entered)


func _perform_attack() -> void:
	_anim.play("attack")


# Los llama la animación (Call Method Track).
func enable_hit() -> void:
	_already_hit.clear()
	_hitbox.set_deferred("monitoring", true)


func disable_hit() -> void:
	_hitbox.set_deferred("monitoring", false)


func _on_hitbox_body_entered(body: Node3D) -> void:
	if body in _already_hit:
		return
	_already_hit.append(body)
	_deal_damage(body)
