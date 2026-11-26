extends CharacterBody3D

const SPEED := 8.0
const SPRINT_MULT := 1.5
const ACCEL := 40.0
const JUMP_VELOCITY := 5.5
const MOUSE_SENS := 0.003
const PITCH_MIN := -1.2
const PITCH_MAX := 1.2
const TURN_THRESHOLD := 0.6
const TURN_SPEED := 8.0

const PICKAXE := preload("res://3dModels/pickaxe.glb")
const BULLET := preload("res://scenes/bullet.tscn")
const WEAPON_POS := Vector3(-0.55, 0.18, 0.03)
const WEAPON_SCALE := 2.8

@onready var pivot: Node3D = $CameraPivot
@onready var arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _body: Node3D = $Visual
@onready var _leg_l: Node3D = $Visual/LegL
@onready var _leg_r: Node3D = $Visual/LegR
@onready var _arm_r: Node3D = $Visual/ArmR
@onready var _weapon_pivot: Node3D = get_node_or_null("Visual/ArmR/WeaponPivot")
@onready var _cam: Camera3D = $CameraPivot/SpringArm3D/Camera3D

var cam_yaw := 0.0
var _walk_phase := 0.0
var _walk_amp := 0.0
var _swinging := false


var current_weapon: PackedScene = PICKAXE
var inventory_open := false
var owned: Array = [null, null, null, null, null, null]
var current_slot := 0
var health := 100.0
var shield := 100.0
var ammo := 0
var reloading := false
var _weapon_model: Node3D
var _trigger := false
var _fire_timer := 0.0
var _reload_timer := 0.0
var _ads := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_to_group("player")
	owned[0] = {"scene": PICKAXE, "name": "Pickaxe"}
	_cam.h_offset = 0.8
	_cam.v_offset = 0.15
	arm.spring_length = 3.5
	equip_weapon(current_weapon)


func add_weapon(scene: PackedScene, wname: String) -> bool:
	for e in owned:
		if e != null and e["scene"] == scene:
			return true
	for i in range(1, owned.size()):
		if owned[i] == null:
			owned[i] = {"scene": scene, "name": wname}
			return true
	return false


func is_undroppable(scene: PackedScene) -> bool:
	return scene == PICKAXE


func weapon_entry_at(i: int) -> Variant:
	return owned[i]


func move_slot(a: int, b: int) -> void:
	var tmp = owned[a]
	owned[a] = owned[b]
	owned[b] = tmp


func equip_slot(i: int) -> void:
	var e = owned[i]
	if e != null:
		equip_weapon(e["scene"])


func equip_weapon(scene: PackedScene) -> void:
	current_weapon = scene
	for i in owned.size():
		var e = owned[i]
		if e != null and e["scene"] == scene:
			current_slot = i
	if not _weapon_pivot:
		return
	for c in _weapon_pivot.get_children():
		c.queue_free()
	var model := _instantiate_from_hold(scene)
	if model == null and scene != PICKAXE:
		model = scene.instantiate()
		var hp: Variant = model.get("hold_position")
		model.position = hp if hp is Vector3 else WEAPON_POS
		var hr: Variant = model.get("hold_rotation")
		model.rotation_degrees = hr if hr is Vector3 else Vector3(0, 0, -90)
		var hs: Variant = model.get("hold_scale")
		model.scale = Vector3.ONE * (hs if hs is float else WEAPON_SCALE)
		_weapon_pivot.add_child(model)
		_fix_head(model)
	_weapon_model = model
	ammo = int(_gun_stat("magazine_size", 0))
	reloading = false


func _instantiate_from_hold(scene: PackedScene) -> Node3D:
	var path := "res://scenes/holds/%s_hold.tscn" % scene.resource_path.get_file().get_basename()
	if not ResourceLoader.exists(path):
		return null
	var h: Node = load(path).instantiate()
	var hp := h.get_node_or_null("Player/Visual/ArmR/WeaponPivot")
	var model: Node3D = null
	if hp:
		for c in hp.get_children():
			if c.scene_file_path == scene.resource_path:
				model = c
				break
		if model == null:
			for c in hp.get_children():
				if c.name != "Pickaxe" or scene == PICKAXE:
					model = c
					break
		if model:
			model.reparent(_weapon_pivot, false)
	h.free()
	if model and scene == PICKAXE:
		_fix_head(model)
	return model


func _gun_stat(prop: String, default: Variant) -> Variant:
	if _weapon_model == null:
		return default
	var v: Variant = _weapon_model.get(prop)
	return v if v != null else default


func _can_shoot() -> bool:
	return _weapon_model != null and _weapon_model.get("can_shoot") == true


func _start_reload() -> void:
	if reloading or not _can_shoot():
		return
	var mag := int(_gun_stat("magazine_size", 0))
	if mag <= 0 or ammo >= mag:
		return
	reloading = true
	_reload_timer = float(_gun_stat("reload_time", 1.5))


func reload_hint() -> String:
	if reloading:
		return "Reloading..."
	if _can_shoot() and ammo <= 0:
		return "[R] Reload"
	return ""


func _fire_burst() -> void:
	var cam := get_viewport().get_camera_3d()
	var fwd := -cam.global_transform.basis.z
	var origin := cam.global_position + fwd * 0.5
	for i in int(_gun_stat("pellets", 1)):
		var b := BULLET.instantiate()
		var spread := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.03
		b.direction = (fwd + spread).normalized()
		b.position = origin
		b.speed = float(_gun_stat("bullet_speed", 80.0))
		b.damage = float(_gun_stat("damage", 10.0))
		b.max_dist = float(_gun_stat("weapon_range", 100.0))
		b.scale = Vector3.ONE * float(_gun_stat("bullet_scale", 1.0))
		get_tree().current_scene.add_child(b)
	ammo -= 1
	if not bool(_gun_stat("is_auto", false)):
		_trigger = false


func _fix_head(n: Node) -> void:
	for c in n.find_children("*", "Node3D", true, false):
		if "2_low" in c.name:
			c.rotation_degrees.y -= 90


func _process(delta: float) -> void:
	pivot.rotation.y = wrapf(cam_yaw - rotation.y, -PI, PI)

	var hspeed := Vector2(velocity.x, velocity.z).length()
	var moving := hspeed > 0.5
	if moving:
		_walk_phase += delta * 9.0
	_walk_amp = move_toward(_walk_amp, 1.0 if moving else 0.0, delta * 6.0)
	var swing := sin(_walk_phase) * 0.55 * _walk_amp
	var local_vel := global_transform.basis.inverse() * velocity
	var strafe := absf(local_vel.x) > absf(local_vel.z) * 1.2
	if strafe and _walk_amp > 0.01:
		var dir := signf(local_vel.x)
		_leg_l.rotation.x = 0.0
		_leg_l.rotation.z = -swing * dir * 0.5
		_leg_r.rotation.x = 0.0
		_leg_r.rotation.z = swing * dir * 0.5
	else:
		_leg_l.rotation.x = swing
		_leg_l.rotation.z = 0.0
		_leg_r.rotation.x = -swing
		_leg_r.rotation.z = 0.0
	_body.position.y = absf(sin(_walk_phase)) * 0.04 * _walk_amp

	arm.spring_length = move_toward(arm.spring_length, 2.0 if _ads else 3.5, delta * 10.0)
	_cam.fov = move_toward(_cam.fov, 55.0 if _ads else 75.0, delta * 60.0)
	if reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			ammo = int(_gun_stat("magazine_size", 0))
			reloading = false
	if _trigger and _can_shoot() and ammo > 0 and not reloading:
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			_fire_burst()
			_fire_timer = 1.0 / maxf(float(_gun_stat("fire_rate", 1.0)), 0.1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw -= event.relative.x * MOUSE_SENS
		arm.rotation.x = clampf(arm.rotation.x - event.relative.y * MOUSE_SENS, PITCH_MIN, PITCH_MAX)
	elif event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				if _can_shoot():
					_trigger = true
					_fire_timer = 0.0
				else:
					_swing()
			elif event.button_index == MOUSE_BUTTON_RIGHT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				_ads = not _ads
			elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not inventory_open:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_trigger = false
	elif event.is_action_pressed("reload"):
		_start_reload()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _swing() -> void:
	if _swinging:
		return
	_swinging = true
	var tw := create_tween()
	tw.tween_property(_arm_r, "rotation:x", 1.1, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_arm_r, "rotation:x", 0.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _swinging = false)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += get_gravity().y * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY

	var diff := wrapf(cam_yaw - rotation.y, -PI, PI)
	if absf(diff) > TURN_THRESHOLD:
		rotation.y += clampf(diff, -TURN_SPEED * delta, TURN_SPEED * delta)

	var input_dir := Input.get_vector("left", "right", "foward", "backward")
	var direction := (Basis(Vector3.UP, cam_yaw) * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var speed := SPEED * (SPRINT_MULT if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	var target := direction * speed
	velocity.x = move_toward(velocity.x, target.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCEL * delta)

	move_and_slide()
