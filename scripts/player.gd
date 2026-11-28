extends CharacterBody3D

const SPEED := 8.0
const SPRINT_MULT := 1.5
const ACCEL := 40.0
const JUMP_VELOCITY := 4.6
const GRAVITY_MULT := 1.7
const MOUSE_SENS := 0.003
const PITCH_MIN := -1.2
const PITCH_MAX := 1.2
const TURN_THRESHOLD := 0.6
const TURN_SPEED := 8.0

const PICKAXE := preload("res://3dModels/pickaxe.glb")
const BULLET := preload("res://scenes/bullet.tscn")
const PICKUP_SCENE := preload("res://scenes/weapon_pickup.tscn")
const BLUEPRINT := preload("res://scenes/build/blueprint.tscn")
const GRID := 6.0
const BUILD_PIECES := {
	"wall": {"s": preload("res://scenes/build/wall.tscn"), "h": 5.8, "floor_only": false, "gy": 0.05},
	"stair": {"s": preload("res://scenes/build/stair.tscn"), "h": 2.9, "floor_only": false, "gy": 0.35},
	"cone": {"s": preload("res://scenes/build/cone.tscn"), "h": 1.4, "floor_only": false, "gy": 0.02},
	"floor": {"s": preload("res://scenes/build/floor.tscn"), "h": 0.2, "floor_only": true, "gy": 0.05},
}
const BUILD_ORDER := ["wall", "stair", "cone", "floor"]
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
var _using_item := false
var _use_timer := 0.0
var _use_item_name := ""
var _build_mode := false
var _build_piece := "wall"
var _ghost: Node3D
var _ghost_mat: StandardMaterial3D
var _ghost_bad_mat: StandardMaterial3D
var _ghost_meshes: Array = []
var _ghost_key: Variant = null
var _ghost_ok := false
var _cells := {}
var _prev_weapon: PackedScene


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_to_group("player")
	owned[0] = {"scene": PICKAXE, "name": "Pickaxe"}
	_cam.h_offset = 0.8
	_cam.v_offset = 0.15
	arm.spring_length = 3.5
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.albedo_color = Color(0.2, 0.5, 1, 0.35)
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_bad_mat = StandardMaterial3D.new()
	_ghost_bad_mat.albedo_color = Color(1, 0.15, 0.1, 0.35)
	_ghost_bad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	floor_max_angle = deg_to_rad(55.0)
	collision_mask = 3
	equip_weapon(current_weapon)
	_make_build_grid()


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
	equip_weapon(e["scene"] if e != null else PICKAXE)


func drop_weapon(i: int) -> void:
	var e = owned[i]
	if e == null or is_undroppable(e["scene"]):
		return
	owned[i] = null
	var drop: Node3D = PICKUP_SCENE.instantiate()
	drop.weapon = e["scene"]
	get_tree().current_scene.add_child(drop)
	var fwd := -global_transform.basis.z
	drop.global_position = global_position + fwd * 2.0 + Vector3(0, 0.5, 0)
	if current_weapon == e["scene"]:
		equip_weapon(PICKAXE)


func _set_build_mode(on: bool) -> void:
	if on == _build_mode:
		return
	_build_mode = on
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if on:
		_prev_weapon = current_weapon
		equip_weapon(BLUEPRINT)
	_rebuild_ghost()
	if not on and _prev_weapon:
		equip_weapon(_prev_weapon)
		_prev_weapon = null


func _toggle_build() -> void:
	_set_build_mode(not _build_mode)


func _rebuild_ghost() -> void:
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if not _build_mode:
		return
	_ghost = BUILD_PIECES[_build_piece]["s"].instantiate()
	_ghost_meshes.clear()
	for body in [_ghost] + _ghost.find_children("*", "CollisionObject3D", true, false):
		body.collision_layer = 0
	for mi in _ghost.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = _ghost_mat
		_ghost_meshes.append(mi)
	get_tree().current_scene.add_child(_ghost)


func _set_piece(p: String) -> void:
	if not _build_mode or not BUILD_PIECES.has(p):
		return
	_build_piece = p
	_rebuild_ghost()


func _update_ghost() -> void:
	if _ghost == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_transform.basis.z * 8.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var info: Dictionary = BUILD_PIECES[_build_piece]
	if hit.is_empty():
		_ghost.visible = false
		return
	var n: Vector3 = hit["normal"]
	if info["floor_only"] and n.y < 0.5:
		_ghost.visible = false
		return
	var hp: Vector3 = hit["position"]
	var yaw := snappedf(cam_yaw, PI / 2.0)
	var pos: Vector3
	var key: Variant
	if _build_piece == "wall":
		# walls snap onto grid lines and must stay in front of the player
		var along_x := absf(cos(yaw)) >= absf(sin(yaw))
		if along_x:
			var li := _line_ahead(roundi(hp.z / GRID), global_position.z, -cos(yaw))
			pos = Vector3(floori(hp.x / GRID) * GRID + GRID * 0.5, 0.0, li * GRID)
			key = Vector3i(0, li, floori(hp.x / GRID))
		else:
			var li := _line_ahead(roundi(hp.x / GRID), global_position.x, -sin(yaw))
			pos = Vector3(li * GRID, 0.0, floori(hp.z / GRID) * GRID + GRID * 0.5)
			key = Vector3i(1, li, floori(hp.z / GRID))
	elif _build_piece == "stair":
		# stairs target the cell you are walking into: the current cell until
		# you pass the first third of it, then the next cell ahead
		var cell := _stair_cell()
		pos = Vector3(cell.x * GRID + GRID * 0.5, 0.0, cell.y * GRID + GRID * 0.5)
		key = cell
	else:
		var cell := Vector2i(floori(hp.x / GRID), floori(hp.z / GRID))
		pos = Vector3(cell.x * GRID + GRID * 0.5, 0.0, cell.y * GRID + GRID * 0.5)
		key = cell
	# every build rests its bottom on whatever is below it
	var support := _support_height(pos, hp.y)
	if is_nan(support):
		_ghost.visible = false
		return
	pos.y = support + float(info["gy"])
	# never allow building behind the player
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var to := pos - global_position
	to.y = 0.0
	_ghost.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	_ghost_key = key
	_ghost_ok = (to.dot(fwd) > 0.0 or _build_piece == "stair") and not _cells.has(key)
	var mat := _ghost_mat if _ghost_ok else _ghost_bad_mat
	for mi in _ghost_meshes:
		mi.material_override = mat
	_ghost.visible = true


# bumps a grid-line index forward until the line sits ahead of the player
func _line_ahead(li: int, player_axis: float, fwd_sign: float) -> int:
	var guard := 0
	while (li * GRID - player_axis) * fwd_sign <= 0.05 and guard < 20:
		li += 1 if fwd_sign > 0.0 else -1
		guard += 1
	return li


func _stair_cell() -> Vector2i:
	var f := Vector2(-sin(cam_yaw), -cos(cam_yaw))
	var cell := Vector2i(floori(global_position.x / GRID), floori(global_position.z / GRID))
	if absf(f.x) >= absf(f.y):
		var g := global_position.x / GRID
		var frac := g - floorf(g)
		var prog := frac if f.x > 0.0 else 1.0 - frac
		if prog > 1.0 / 3.0:
			cell.x += 1 if f.x > 0.0 else -1
	else:
		var g := global_position.z / GRID
		var frac := g - floorf(g)
		var prog := frac if f.y > 0.0 else 1.0 - frac
		if prog > 1.0 / 3.0:
			cell.y += 1 if f.y > 0.0 else -1
	return cell


func _support_height(pos: Vector3, ref_y: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(pos.x, ref_y + 8.0, pos.z),
		Vector3(pos.x, ref_y - 25.0, pos.z))
	q.collision_mask = 3
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return NAN
	return hit["position"].y


func _make_build_grid() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var ext := 96.0
	var i := -ext
	while i <= ext:
		mesh.surface_add_vertex(Vector3(i, 0.03, -ext))
		mesh.surface_add_vertex(Vector3(i, 0.03, ext))
		mesh.surface_add_vertex(Vector3(-ext, 0.03, i))
		mesh.surface_add_vertex(Vector3(ext, 0.03, i))
		i += GRID
	mesh.surface_end()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 1, 1, 0.22)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mi := MeshInstance3D.new()
	mi.name = "BuildGrid"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = mat
	mi.mesh = mesh
	var ps := get_tree().current_scene
	if ps:
		ps.add_child.call_deferred(mi)


func _place_piece() -> void:
	if _ghost == null or not _ghost.visible or not _ghost_ok:
		return
	var p: Node3D = BUILD_PIECES[_build_piece]["s"].instantiate()
	p.transform = _ghost.transform
	for c in [p] + p.find_children("*", "CollisionObject3D", true, false):
		c.collision_layer = 2
	p.set_meta("build_key", _ghost_key)
	p.set_meta("build_hp", 2)
	get_tree().current_scene.add_child(p)
	_cells[_ghost_key] = true


func _pickaxe_hit() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_transform.basis.z * 8.0)
	q.collision_mask = 2
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var piece: Object = hit["collider"]
	if not piece.has_meta("build_key"):
		return
	var hp_left := int(piece.get_meta("build_hp", 2)) - 1
	if hp_left <= 0:
		_cells.erase(piece.get_meta("build_key"))
		piece.queue_free()
	else:
		piece.set_meta("build_hp", hp_left)


func _on_key(k: int) -> void:
	match k:
		KEY_B:
			_toggle_build()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			_set_build_mode(false)
			equip_slot(k - KEY_1 + 1)
		KEY_6:
			_set_build_mode(false)
			equip_slot(0)
		KEY_C:
			_set_piece("wall")
		KEY_V:
			_set_piece("stair")
		KEY_Z:
			_set_piece("cone")
		KEY_X:
			_set_piece("floor")


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
			model.owner = null
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


func _can_use_item() -> bool:
	if _weapon_model == null or _using_item or reloading:
		return false
	var t: Variant = _weapon_model.get("use_time")
	return t != null and float(t) > 0.0


func _start_use() -> void:
	var t := float(_weapon_model.get("use_time"))
	if _weapon_model.get("time_scales_with_missing") == true:
		var missing := 100.0 - health
		t = 2.0 if missing <= 25.0 else (5.0 if missing <= 50.0 else 8.0)
	_using_item = true
	_use_timer = t
	_use_item_name = str(_weapon_model.get("weapon_name") or "Item")


func _finish_use() -> void:
	_using_item = false
	if _weapon_model == null:
		return
	if _weapon_model.get("heal_health") == true:
		health = 100.0
	var amt := float(_weapon_model.get("heal_shield") or 0.0)
	if amt > 0.0:
		shield = minf(shield + amt, float(_weapon_model.get("shield_cap") or 100.0))


func reload_hint() -> String:
	if _using_item:
		return "Using %s... %.1fs" % [_use_item_name, _use_timer]
	if _build_mode:
		var names := {"wall": "Wall [C]", "stair": "Stair [V]", "cone": "Cone [Z]", "floor": "Floor [X]"}
		return "BUILD MODE - %s  (B to exit)" % names[_build_piece]
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
	if _build_mode:
		_update_ghost()
	if _using_item:
		_use_timer -= delta
		if _use_timer <= 0.0:
			_finish_use()
	if _trigger and _can_shoot() and ammo > 0 and not reloading:
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			_fire_burst()
			_fire_timer = 1.0 / maxf(float(_gun_stat("fire_rate", 1.0)), 0.1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_on_key(event.keycode)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw -= event.relative.x * MOUSE_SENS
		arm.rotation.x = clampf(arm.rotation.x - event.relative.y * MOUSE_SENS, PITCH_MIN, PITCH_MAX)
	elif event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				if _build_mode:
					_place_piece()
				elif _using_item:
					_using_item = false
				elif _can_use_item():
					_start_use()
				elif _can_shoot():
					_trigger = true
					_fire_timer = 0.0
				else:
					if current_weapon == PICKAXE:
						_pickaxe_hit()
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
		velocity.y += get_gravity().y * GRAVITY_MULT * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY

	var diff := wrapf(cam_yaw - rotation.y, -PI, PI)
	if absf(diff) > TURN_THRESHOLD:
		rotation.y += clampf(diff, -TURN_SPEED * delta, TURN_SPEED * delta)

	var input_dir := Vector2.ZERO if _using_item else Input.get_vector("left", "right", "foward", "backward")
	var direction := (Basis(Vector3.UP, cam_yaw) * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var speed := SPEED * (SPRINT_MULT if Input.is_action_pressed("sprint") else 1.0)
	var target := direction * speed
	velocity.x = move_toward(velocity.x, target.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCEL * delta)

	move_and_slide()
