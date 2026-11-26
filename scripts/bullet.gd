extends Node3D

var direction := Vector3(0, 0, -1)
var speed := 80.0
var damage := 10.0
var max_dist := 100.0
var _traveled := 0.0


func _ready() -> void:
	look_at(global_position + direction)


func _process(delta: float) -> void:
	global_position += direction * speed * delta
	_traveled += speed * delta
	if _traveled >= max_dist:
		queue_free()
