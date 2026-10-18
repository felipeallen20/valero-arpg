class_name MeleeWeapon
extends Weapon

## Categoría "cuerpo a cuerpo": el comportamiento compartido por TODAS las
## armas melee. No es un arma concreta: cada arma (PracticeSword, y en el
## futuro una katana, un hacha...) hereda de esta y define sus propios
## valores y efectos en su script de arma concreta.
##
## Aporta la hitbox ligada a la animación de ataque: la animación abre y cierra
## la ventana de golpe (enable_hit / disable_hit) y el daño real lo resuelve
## Weapon.deal_damage, que además dispara _on_hit_landed para que las armas
## concretas apliquen sus efectos (sangrado, etc.).

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
	deal_damage(body)
