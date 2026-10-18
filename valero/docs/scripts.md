# Guía de scripts del proyecto

Referencia rápida de qué hace cada script y cómo están organizados. Solo cubre `scripts/`.

## Organización de carpetas

```
scripts/
├── player/          # Jugador: movimiento, cámara y estadísticas
├── enemies/         # Enemigos (base + variantes)
│   └── UI/          # Elementos visuales 3D de los enemigos
├── weapons/         # Sistema de armas (base, melee, a distancia y proyectiles)
├── UI/              # HUD 2D del jugador
└── world/           # Configuración inicial del mundo
```

## player/

| Archivo | Qué hace |
|---|---|
| `player.gd` | Control del jugador: movimiento en suelo/aire, salto (con coyote time, buffer y altura variable), sprint con estamina, dash con i-frames, ataque con la arma activa, estado del combo (el jugador guarda el contador; el arma define su patrón) y feedback visual de combo (contorno amarillo en el modelo). |
| `player_camera.gd` | Cámara en tercera persona: seguimiento del jugador con SpringArm3D, ratón con captura/pinza, zoom con la rueda y toggle de ratón con Esc. |
| `player_stats.gd` | Estadísticas del jugador (vida, estamina, muerte) como nodo independiente. Gestiona la regeneración de estamina, las invulnerabilidades y el sistema de **recuperación por contragolpe** (recibir daño abre una ventana en la que el daño infligido cura vida). Emite señales que consumen HUD y player. |

## enemies/

| Archivo | Qué hace |
|---|---|
| `enemy_base.gd` | Clase base de todos los enemigos: vida, gravedad, daño recibido, números de daño flotantes, muerte y localización/orientación hacia el jugador (por `NodePath` o grupo "player"). La IA concreta va en las hijas. |
| `enemy.gd` | Enemigo cuerpo a cuerpo (`extends EnemyBase`): máquina de estados CHASE → ATTACK, persigue al jugador, golpea con telegrafiado (windup) y cooldown. |
| `enemy_ranged.gd` | Enemigo a distancia (`extends EnemyBase`): no persigue; apunta su arma al jugador y ataca mientras esté dentro del rango del arma. |
| `UI/health_bar_3d.gd` | Barra de vida 3D con billboard (dos quads: fondo y relleno). Se anima con tween al recibir daño, con destello blanco, y se oculta al estar llena. |
| `UI/damage_number.gd` | Número de daño flotante (`Label3D`): aparece sobre el objetivo con un "pop" de escala, sube y se desvanece. Se crea con el estático `DamageNumber.spawn(...)`. |

## weapons/

| Archivo | Qué hace |
|---|---|
| `weapon.gd` | **Clase base** de armas (`class_name Weapon`): define daño, cadencia, alcance y el **contrato de combo** (patrón y efecto) que comparten todas las armas. No guarda estado de combo (vive en el empuñador). Expone los puntos de extensión `get_damage_for_combo()` (efecto del combo sobre el daño) y `_on_hit_landed()` (efectos al impactar, p. ej. sangrado). |
| `melee_weapon.gd` | **Categoría melee** (`extends Weapon`): comportamiento compartido por todas las armas cuerpo a cuerpo. Reproduce la animación de ataque y activa/desactiva una hitbox según sus frames (Call Method Track), evitando dañar dos veces al mismo objetivo en un swing. No es un arma concreta. |
| `ranged_weapon.gd` | **Categoría a distancia** (`extends Weapon`): comportamiento compartido por todas las armas de rango. Sin modelo propio; cada disparo instancia la escena del proyectil en el Muzzle orientado hacia donde apunte el arma. No es un arma concreta. |
| `practice_sword.gd` | **Arma concreta** (`extends MeleeWeapon`): la espada de práctica. No sobrescribe nada: usa el combo básico de `Weapon` (sube el daño). Sirve de plantilla de cómo se crea un arma concreta. |
| `projectile.gd` | Proyectil visible (`Area3D`): vuela en línea recta desde el Muzzle hasta impactar o agotar el rango. Al impactar delega el daño en el arma (`Weapon.deal_damage`), por lo que un proyectil también cuenta para el combo y dispara los efectos de `_on_hit_landed()`. |

### Jerarquía de armas

```
Weapon (weapon.gd)                 → base: daño, cadencia, alcance y combo
├── MeleeWeapon  (melee_weapon.gd) → categoría: hitbox + animación
│   └── PracticeSword (practice_sword.gd) → arma concreta
└── RangedWeapon (ranged_weapon.gd) → categoría: dispara proyectiles
```

Para crear un arma nueva: heredar de `MeleeWeapon` o `RangedWeapon` (nunca de `Weapon` directamente), sobrescribir `get_damage_for_combo()` y/o `_on_hit_landed()` si tiene efectos propios, y adjuntar ese script a la escena del arma.

## UI/

| Archivo | Qué hace |
|---|---|
| `hud.gd` | HUD 2D (`CanvasLayer`): barras de vida, estamina y recuperación con estilos propios. Se conecta a las señales de `PlayerStats`; la vida se anima con tween, la estamina se asigna directo (cambia cada frame). |

## world/

| Archivo | Qué hace |
|---|---|
| `world.gd` | Inicializa el mundo: al arrancar coloca al jugador en su posición de spawn. |

## Relaciones principales

- `player.gd` → empuña un `Weapon` y delega stats en `PlayerStats`.
- `weapon.gd` / `projectile.gd` → llaman `take_damage()` al objetivo y `register_combo_hit()` / `register_damage_dealt()` al empuñador.
- `enemy_base.gd` y sus hijas → localizan al jugador por el grupo `"player"` y buscan su `PlayerStats`.
- `hud.gd` → solo escucha señales de `PlayerStats` (no busca nodos por frame).
- `damage_number.gd` → usado por `enemy_base.gd` (daño) y `player.gd` (curación).
