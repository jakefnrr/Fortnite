extends PanelContainer

var slot_index := -1
var player: Node
var _was_dragged := false


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)
	sb.border_color = Color(1, 1, 1, 0.4)
	sb.set_border_width_all(2)
	add_theme_stylebox_override("panel", sb)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_was_dragged = false
		elif not _was_dragged:
			player.equip_slot(slot_index)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if slot_index == 0:
		return null
	var e = player.weapon_entry_at(slot_index)
	if e == null:
		return null
	_was_dragged = true
	var preview := Label.new()
	preview.text = e["name"]
	set_drag_preview(preview)
	return {"from": slot_index}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return slot_index != 0 and data is Dictionary and data.get("from") != slot_index


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	player.move_slot(data["from"], slot_index)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and not get_viewport().gui_is_drag_successful():
		if not get_global_rect().has_point(get_global_mouse_position()):
			player.drop_weapon(slot_index)
