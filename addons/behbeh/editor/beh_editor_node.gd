@tool
class_name BehEditorNode
extends GraphNode


var beh: BehNode = null
var _needs_update := false


# === Godot Events ===


func _draw():
	_needs_update = true


func _process(_dt):
	if !Engine.is_editor_hint(): return
	if !_needs_update: return
	_needs_update = false
	update_view()


# === Render Update ===


func init_node_view():
	# Title
	try_init_node_title_via_behavior_script_name()
	# Port defaults
	self.set_slot(
		0, # port slot
		true, TYPE_BOOL, Color.AQUAMARINE, # left port
		true, TYPE_BOOL, Color.AQUAMARINE,  # right port
		null, null, # icons
		false
#		true # draw_stylebox (?)
	)
	# Ensure slot0 exists.
	var slot0 = null
	if self.get_child_count() == 0:
		slot0 = Control.new()
		self.add_child(slot0)
	else:
		slot0 = self.get_child(0)
	slot0.name = "Foo Bar"
#	self.set_slot
#	self.set_slot_enabled_left(0, true)
#	self.set_slot_enabled_right(0, true)
	# Size
	size.y = 60


func update_view():
	if !validate_beh():
		render_view_invalid()
	else:
		render_view_node()


func validate_beh() -> bool:
	"""Validates that 'node' exists and is otherwise in a valid state. Returns true if OK."""
	return beh != null


func render_view_invalid():
	"""Sets visible properties to indicate this BehEditorNode is missing a BehNode to view/edit."""
	self.title = "(Missing Node)"


func render_view_node():
	"""If called, 'node' property exists and is valid. Update the view representation based on the
	node state."""
	try_init_node_title_via_behavior_script_name()


func try_init_node_title_via_behavior_script_name():
	if self is BehEditorNodeEntry: return
	if beh == null: return
	var beh_script: Script = beh.get_script() as Script
	if beh_script == null:
		title = "(Missing Script)"
		return
	# Best-guess Title
	var classname = get_best_guess_script_class_name(beh_script)
	title = classname


func get_best_guess_script_class_name(script: Script) -> String:
	"""Literally parses the dang GDScript to try to find the class_name entry.
	Really AWFULLY SILLY that this method has to exist."""
	if script == null:
		return "(null Script)"
	var script_file_name = script.resource_path.get_file()
	if script.has_source_code():
		var src = script.source_code
		var first_80_chars = src.substr(0, 80)
		var script_name_idx = first_80_chars.find("class_name")
		if script_name_idx >= 0:
			var str_with_name_starting: String = first_80_chars.substr(script_name_idx + len("class_name"))
			str_with_name_starting = str_with_name_starting.lstrip(" ")
			str_with_name_starting = str_with_name_starting.lstrip("\t")
#			print("str_with_name_starting %s" % str_with_name_starting)
			var newline_idx_after_name = str_with_name_starting.find("\n")
			var space_idx_after_name = str_with_name_starting.find(" ")
			var tab_idx_after_name = str_with_name_starting.find("\t")
			if newline_idx_after_name == -1:
				newline_idx_after_name = space_idx_after_name
			if newline_idx_after_name == -1:
				newline_idx_after_name = tab_idx_after_name
			if newline_idx_after_name != -1:
				var parsed_script_class_name = str_with_name_starting.substr(0, newline_idx_after_name)
				return parsed_script_class_name
	else:
		print("REMOVE THIS PRINT -- script LACKS source available :(")
	# Fallback is just the script name.
	return script_file_name


# === Data ===


func has_attached_beh() -> bool:
	return beh != null


# === View Management ===


func get_center() -> Vector2:
	"""Returns the position_offset + size / 2 of this node."""
	return self.position_offset + self.size / 2


func set_center(pos: Vector2):
	"""Sets the position_offset of this node via a center position (uses size / 2).
	Also updates editor data in the attached BehNode (if it exists)."""
	self.position_offset = pos - self.size / 2


