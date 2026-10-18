class_name PlayerStats
extends Node

# --- Señales (la UI y otros sistemas se conectan a estas) ---
signal health_changed(current: float, maximum: float)
signal stamina_changed(current: float, maximum: float)
signal damaged(amount: float)
signal healed(amount: float)
signal stamina_depleted
signal died

# --- Recuperación por contragolpe ---
# Recibir una ráfaga de daño abre una ventana en la que el daño que infliges
# cura vida. La barra (pool) es el % de lo recibido que se puede recuperar.
signal recovery_started(pool: float, duration: float)
signal recovery_updated(pool: float, time_left: float)
signal recovery_ended

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

# --- Recuperación por contragolpe ---
# Recibir una ráfaga de daño abre una ventana en la que el daño que infliges
# cura vida (1 punto de daño = 1 punto curado, descontado de la barra).
# Sin botón, sin canal y sin i-frames: la curación es reaccional al combate.
@export_group("Recuperación por contragolpe")
@export var recovery_enabled := true
@export var recovery_burst_damage: float = 30.0   # daño en la ráfaga que la dispara
@export var recovery_burst_window: float = 2.5    # segundos que mira atrás la ráfaga
@export var recovery_duration: float = 7.0        # segundos duros de ventana
@export var recovery_hit_timeout: float = 2.0     # s sin pegar golpe → se cierra
@export var recovery_pool_ratio: float = 0.9      # % del daño recibido que entra a la barra
@export var recovery_cooldown: float = 5.0        # s de espera tras cerrar la ventana

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

# --- Recuperación por contragolpe: estado ---
var _recovery_pool := 0.0
var _recovery_time_left := 0.0
var _recovery_idle_left := 0.0
var _recovery_cooldown_left := 0.0
var _recovery_active := false
# Ráfaga actual: pares (segundo absoluto, daño) para medir el umbral de disparo.
var _burst_events: Array[Vector2] = []

var _regen_delay_left := 0.0


func _ready() -> void:
	health = max_health
	stamina = max_stamina
	died.connect(_end_recovery)


func _process(delta: float) -> void:
	if is_dead():
		return
	_regen_stamina(delta)
	if health_regen_rate > 0.0:
		health += health_regen_rate * delta

	if _recovery_cooldown_left > 0.0:
		_recovery_cooldown_left -= delta

	if _recovery_active:
		_recovery_time_left -= delta
		_recovery_idle_left -= delta
		# Se cierra por tiempo agotado o por no conectar ningún golpe.
		if _recovery_time_left <= 0.0 or _recovery_idle_left <= 0.0:
			_end_recovery()
		else:
			recovery_updated.emit(_recovery_pool, _recovery_time_left)


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
	if applied > 0.0:
		_note_damage_taken(applied)
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


# --- Recuperación por contragolpe ---
## true si la ventana de recuperación está abierta ahora mismo.
func is_recovery_active() -> bool:
	return _recovery_active


## Lo llama el empuñador (vía Player) cuando su golpe conecta con un objetivo.
## Durante la ventana, cada punto de daño infligido cura un punto del pool
## (hasta vaciarlo o llegar a vida máxima). Devuelve lo realmente curado.
func register_damage_dealt(amount: float) -> float:
	if amount <= 0.0 or not _recovery_active or is_dead():
		return 0.0
	# Conectar un golpe mantiene viva la ventana (regla: no pegas, se cierra).
	_recovery_idle_left = recovery_hit_timeout
	var recovered := heal(minf(amount, _recovery_pool))
	_recovery_pool -= recovered
	if _recovery_pool <= 0.001:
		_end_recovery()
	else:
		recovery_updated.emit(_recovery_pool, _recovery_time_left)
	return recovered


## Clasifica el daño recibido: durante la ventana amplía el pool (el daño
## posterior también se recupera, con tope de vida máxima); fuera de ella,
## alimenta la ráfaga que puede abrir la próxima ventana.
func _note_damage_taken(applied: float) -> void:
	if not recovery_enabled:
		return
	if _recovery_active:
		_recovery_pool = minf(_recovery_pool + applied * recovery_pool_ratio, max_health)
		recovery_updated.emit(_recovery_pool, _recovery_time_left)
		return
	if _recovery_cooldown_left > 0.0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	_burst_events.append(Vector2(now, applied))
	while not _burst_events.is_empty() and now - _burst_events[0].x > recovery_burst_window:
		_burst_events.pop_front()
	var burst := 0.0
	for event in _burst_events:
		burst += event.y
	if burst >= recovery_burst_damage:
		_start_recovery(burst * recovery_pool_ratio)


func _start_recovery(pool: float) -> void:
	_burst_events.clear()
	_recovery_pool = minf(pool, max_health)
	_recovery_time_left = recovery_duration
	_recovery_idle_left = recovery_hit_timeout
	_recovery_active = true
	recovery_started.emit(_recovery_pool, _recovery_time_left)


func _end_recovery() -> void:
	if not _recovery_active:
		return
	_recovery_active = false
	_recovery_time_left = 0.0
	_recovery_pool = 0.0
	_burst_events.clear()
	_recovery_cooldown_left = recovery_cooldown
	recovery_ended.emit()


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
	# Vida nueva = ventana de recuperación recién nacida: sin pool ni cooldown.
	_recovery_active = false
	_recovery_time_left = 0.0
	_recovery_pool = 0.0
	_recovery_cooldown_left = 0.0
	_burst_events.clear()
	recovery_ended.emit()
