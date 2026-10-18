class_name PracticeGun
extends RangedWeapon

## Arma concreta: pistola de práctica (categoría a distancia).
##
## Es el arma que empuña el enemigo a distancia (EnemyRanged). No sobrescribe
## nada: hereda el comportamiento de RangedWeapon (disparo de proyectiles) y de
## Weapon (daño, cadencia, alcance y combo). Sus valores concretos (daño,
## alcance, velocidad y proyectil) se ajustan en su escena.
##
## Sirve como arma concreta de referencia para la categoría a distancia, igual
## que PracticeSword lo es para melee. Para un arma de rango con efectos propios
## (p. ej. disparos incendiarios), heredar de RangedWeapon y sobrescribir
## get_damage_for_combo() / _on_hit_landed() de Weapon.
