class_name PracticeSword
extends MeleeWeapon

## Arma concreta: espada de práctica (categoría melee).
##
## Su combo es el básico: al encadenar golpes que conectan, sube el daño
## mientras el combo siga activo. Ese comportamiento ya lo aporta Weapon
## (combo_size / combo_bonus / combo_window, ajustables desde la escena), así
## que esta clase no necesita sobrescribir nada.
##
## Para añadir un arma con comportamiento propio (p. ej. una katana cuyo combo
## aplique sangrado), heredar de MeleeWeapon (o RangedWeapon) y sobrescribir
## los puntos de extensión de Weapon:
##   - get_damage_for_combo(): cambia cómo afecta el combo al daño.
##   - _on_hit_landed(): aplica estados al impactar (sangrado, quemadura...).
## La escena del arma se adjunta al script de su clase concreta.
