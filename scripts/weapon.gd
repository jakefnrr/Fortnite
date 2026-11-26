extends Node3D

@export var weapon_name := "Weapon"
@export var damage := 10.0
@export var fire_rate := 5.0
@export var weapon_range := 100.0
@export var can_shoot := false
@export var is_auto := false
@export var magazine_size := 0
@export var pellets := 1
@export var bullet_speed := 80.0
@export var bullet_scale := 1.0
@export var reload_time := 1.5
@export var hold_position := Vector3.ZERO
@export var hold_rotation := Vector3.ZERO
@export var hold_scale := 1.0
