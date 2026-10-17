class_name PlayerStats
extends Node

# --- Señales (la UI y otros sistemas se conectan a estas) ---
signal health_changed(current: float, maximum: float)
signal stamina_changed(current: float, maximum: float)
signal damaged(amount: float)
signal healed(amount: float)
signal stamina_depleted
signal died

# --- Vida ---
@export_group("Vida")
@export var max_health: float = 100.0:
	set(value):
		max_health = maxf(value, 1.0)
		if is_node_ready():
			health = health  # re-clampa contra el nuevo máximo
@export var health_regen_rate: float = 0.0   # HP/s (0 = sin regeneración)

# --- Estamina ---
@export_group("Estamina")
@export var max_stamina: float = 100.0:
	set(value):
		max_stamina = maxf(value, 1.0)
		if is_node_ready():
			stamina = stamina
@export var stamina_regen_rate: float = 25.0   # puntos/s una vez termina la espera
@export var stamina_regen_delay: float = 0.8   # segundos sin regenerar tras gastar

# Valores actuales. Los setters clampan y emiten la señal, así que basta con
# asignar para que todo se mantenga coherente.
var health: float:
	set(value):
		var clamped := clampf(value, 0.0, max_health)
		if is_equal_approx(clamped, health):
			return
		health = clamped
		health_changed.emit(health, max_health)

var stamina: float:
	set(value):
		var clamped := clampf(value, 0.0, max_stamina)
		if is_equal_approx(clamped, stamina):
			return
		stamina = clamped
		stamina_changed.emit(stamina, max_stamina)
		if stamina <= 0.0:
			stamina_depleted.emit()

# Mientras sea true, take_damage() no hace nada (i-frames del dash, etc.).
var invulnerable := false

var _regen_delay_left := 0.0


func _ready() -> void:
	health = max_health
	stamina = max_stamina


func _process(delta: float) -> void:
	if is_dead():
		return
	_regen_stamina(delta)
	if health_regen_rate > 0.0:
		health += health_regen_rate * delta


# --- Vida ---
func is_dead() -> bool:
	return health <= 0.0


# Devuelve el daño realmente aplicado (0 si era invulnerable o ya estaba muerto).
func take_damage(amount: float) -> float:
	if amount <= 0.0 or invulnerable or is_dead():
		return 0.0
	var before := health
	health -= amount
	var applied := before - health
	damaged.emit(applied)
	if is_dead():
		died.emit()
	return applied


func heal(amount: float) -> float:
	if amount <= 0.0 or is_dead():
		return 0.0
	var before := health
	health += amount
	var applied := health - before
	if applied > 0.0:
		healed.emit(applied)
	return applied


# --- Estamina ---
func has_stamina(amount: float) -> bool:
	return stamina >= amount


# Gasto puntual (dash, ataque). Si no alcanza, no gasta nada y devuelve false.
func use_stamina(amount: float) -> bool:
	if not has_stamina(amount):
		return false
	stamina -= amount
	_regen_delay_left = stamina_regen_delay
	return true


# Gasto continuo (correr, bloquear): llamar cada frame con "coste por segundo * delta".
# Devuelve false cuando se acabó la estamina.
func drain_stamina(amount: float) -> bool:
	if stamina <= 0.0:
		return false
	stamina -= amount
	_regen_delay_left = stamina_regen_delay
	return stamina > 0.0


func restore_stamina(amount: float) -> void:
	stamina += amount


func _regen_stamina(delta: float) -> void:
	if _regen_delay_left > 0.0:
		_regen_delay_left -= delta
		return
	if stamina < max_stamina:
		stamina += stamina_regen_rate * delta


# --- Utilidades ---
func get_health_ratio() -> float:
	return health / max_health

func get_stamina_ratio() -> float:
	return stamina / max_stamina

func restore_all() -> void:
	health = max_health
	stamina = max_stamina
	_regen_delay_left = 0.0
