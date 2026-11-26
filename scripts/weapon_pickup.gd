extends Area3D

const PICKUP_SCENE := preload("res://scenes/weapon_pickup.tscn")
const PICKUP_RANGE := 4.0
const LOOK_DOT := 0.7

@export var weapon: PackedScene

var _model: Node3D
var _player: Node3D
var _prompt: Label3D
var _item_name := "Item"


func _ready() -> void:
	if weapon:
		_model = weapon.instantiate()
		_model.scale = Vector3.ONE * 0.8
		_model.rotation_degrees.y = 30.0
		add_child(_model)
		_fix_head()
		var n: Variant = _model.get("weapon_name")
		if n != null:
			_item_name = str(n)
		elif "pickaxe" in weapon.resource_path:
			_item_name = "Pickaxe"
	_prompt = $Prompt
	_prompt.text = "(E) Pick up " + _item_name
	_prompt.visible = false


func _process(delta: float) -> void:
	if _model:
		_model.rotation.y += delta * 1.5
		_model.position.y = 0.7 + sin(Time.get_ticks_msec() / 400.0) * 0.15
	var can_take := false
	if _player and is_instance_valid(_player) and weapon:
		var dist := global_position.distance_to(_player.global_position + Vector3(0, 1.0, 0))
		if dist < PICKUP_RANGE:
			can_take = true
			if Input.is_action_just_pressed("interact"):
				_take()
	if _prompt:
		_prompt.visible = can_take


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player = body


func _on_body_exited(body: Node3D) -> void:
	if body == _player:
		_player = null


func _take() -> void:
	if not _player.add_weapon(weapon, _item_name):
		return
	var old: PackedScene = _player.current_weapon
	_player.equip_weapon(weapon)
	if old and old != weapon and not _player.is_undroppable(old):
		var drop := PICKUP_SCENE.instantiate()
		drop.weapon = old
		get_tree().current_scene.add_child(drop)
		drop.global_position = global_position + Vector3(0, 0.8, 0)
	queue_free()


func _fix_head() -> void:
	for c in _model.find_children("*", "Node3D", true, false):
		if "2_low" in c.name:
			c.rotation_degrees.y -= 90
