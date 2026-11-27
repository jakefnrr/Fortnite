extends CanvasLayer

const INV_SLOT := preload("res://scripts/inv_slot.gd")

var _player: Node
var _hotbar_icons: Array = []
var _inv_icons: Array = []
var _icon_cache := {}
var _icon_sig := ""
var _open := false
var _shield_bar: ProgressBar
var _health_bar: ProgressBar
var _reload_label: Label


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_shield_bar = $Bars/ShieldBar
	_health_bar = $Bars/HealthBar
	_reload_label = $ReloadLabel

	for i in 6:
		var slot := $Hotbar.get_node("Slot%d" % i)
		var tr := _make_icon_rect()
		slot.add_child(tr)
		_hotbar_icons.append(tr)
		slot.gui_input.connect(_on_slot_input.bind(i))

	var grid := $InventoryUI/InventoryPanel/Margin/Grid
	for i in 5:
		var s = INV_SLOT.new()
		s.slot_index = i + 1
		s.player = _player
		s.custom_minimum_size = Vector2(72, 72)
		grid.add_child(s)
		var tr := _make_icon_rect()
		s.add_child(tr)
		_inv_icons.append(tr)
	$InventoryUI/Dim.gui_input.connect(_on_dim_input)


func _make_icon_rect() -> TextureRect:
	var tr := TextureRect.new()
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return tr


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("inventory"):
		_set_open(not _open)
	if _player == null:
		return
	_shield_bar.value = _player.shield
	_health_bar.value = _player.health
	_reload_label.text = _player.reload_hint()
	_reload_label.visible = _reload_label.text != ""

	var sig := ""
	for i in 6:
		var e = _player.weapon_entry_at(i)
		var slot := $Hotbar.get_node("Slot%d" % i)
		slot.self_modulate = Color(1, 1, 0.4) if i == _player.current_slot else Color.WHITE
		sig += str(e["name"]) if e != null else "-"
		if e == null:
			if i < _hotbar_icons.size():
				_hotbar_icons[i].texture = null
	for j in 5:
		var e = _player.weapon_entry_at(j + 1)
		if e == null and j < _inv_icons.size():
			_inv_icons[j].texture = null
	if sig != _icon_sig:
		_icon_sig = sig
		_assign_icons()


func _assign_icons() -> void:
	for i in 6:
		var e = _player.weapon_entry_at(i)
		var tex: Texture2D = null
		if e != null:
			tex = _icon_viewport(e["scene"]).get_texture()
		if i < _hotbar_icons.size():
			_hotbar_icons[i].texture = tex
	for j in 5:
		var e = _player.weapon_entry_at(j + 1)
		var tex: Texture2D = null
		if e != null:
			tex = _icon_viewport(e["scene"]).get_texture()
		if j < _inv_icons.size():
			_inv_icons[j].texture = tex


func _icon_viewport(scene: PackedScene) -> SubViewport:
	if _icon_cache.has(scene):
		return _icon_cache[scene]
	var vp := SubViewport.new()
	vp.size = Vector2i(96, 96)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var model: Node3D = scene.instantiate()
	vp.add_child(model)
	var cam := Camera3D.new()
	cam.position = Vector3(0.9, 0.7, 1.4)
	cam.rotation_degrees = Vector3(-25, 30, 0)
	cam.fov = 45.0
	vp.add_child(cam)
	var l := OmniLight3D.new()
	l.position = Vector3(1.5, 2.5, 2.0)
	l.light_energy = 2.5
	l.omni_range = 6.0
	vp.add_child(l)
	add_child(vp)

	var aabb := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var wb: AABB = mi.global_transform * mi.get_aabb()
		aabb = wb if first else aabb.merge(wb)
		first = false
	if not first and aabb.size.length() > 0.01:
		var f := 1.3 / maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
		model.scale = Vector3.ONE * f
		model.position = -aabb.get_center() * f
	_icon_cache[scene] = vp
	return vp


func _on_slot_input(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		_player.equip_slot(slot_index)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_open(false)


func _set_open(open: bool) -> void:
	_open = open
	$InventoryUI.visible = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
