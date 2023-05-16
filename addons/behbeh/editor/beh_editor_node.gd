@tool
class_name BehEditorNode
extends GraphNode


const COLOR_CONNECTION_CONTROL_FLOW := Color.AQUAMARINE
const COLOR_TITLE_ORPHAN := Color.ORANGE


var beh: BehNode = null
var _needs_update := false
var _is_orphan := false
var is_orphan: bool:
	get: return _is_orphan
	set(value):
		if _is_orphan != value: _needs_update = true
		_is_orphan = value
var dbg_label: Label = null


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
	if beh == null:
		self.title = "(Missing Node)"
		return
	self.title = beh.editor_get_name()
	self.add_theme_color_override("title_color", beh.editor_get_color())
	
	# Left slot: Non-root only.
	var has_left_slot = !beh.get_is_root()
	# Right slot: can-add-child only.
	var has_right_slot = beh.get_can_add_child()
	
	# Set up left & right slots.
	self.set_slot(
		0, # slot idx
		has_left_slot, TYPE_BOOL, COLOR_CONNECTION_CONTROL_FLOW,  # left slot
		has_right_slot, TYPE_BOOL, COLOR_CONNECTION_CONTROL_FLOW,  # right slot
		null, null, # icons
		false		# draw_stylebox (?)
	)
	# Ensure slot0 exists. A Control has to exist as a child in order for
	# slots to be drawn.
	var slot0 = null
	if self.get_child_count() == 0:
		slot0 = Control.new()
		self.add_child(slot0)
	else:
		slot0 = self.get_child(0)

	# Standard Sizing
	size.y = 60
	
	# Slot names?
	# Interestingly this doesn't get drawn. I wonder how we draw it...
	# Answer: Probably just labels inside the node?
	slot0.name = "Foo Bar" 
	
	# Initialize a label on the interior of the node with debug information.
	if self.dbg_label == null:
		self.dbg_label = Label.new()
		self.add_child(dbg_label)


func update_view():
	if _is_orphan:
		self.add_theme_color_override("title_color", COLOR_TITLE_ORPHAN)
	else:
		self.add_theme_color_override("title_color", beh.editor_get_color())
	
	# Debug label text.
	dbg_label.text = "name: ...%s\nres_name: ...%s" % [\
		name.substr(len(String(name)) - 6), self.name.substr(len(String(name)) - 6)]
	
	if !validate_beh():
		render_view_invalid()
	else:
		render_view_node()


func validate_beh() -> bool:
	"""Validates that 'node' exists and is otherwise in a valid state. Returns true if OK."""
	return beh != null


func render_view_invalid():
	"""Sets visible properties to indicate this BehEditorNode is missing a BehNode to view/edit."""
	self.title = "(Invalid EditorNode)"


func render_view_node():
	"""If called, 'node' property exists and is valid. Update the view representation based on the
	node state."""
	pass


func try_init_node_title_via_behavior_script_name():
#	if self is BehEditorNodeEntry: return
	if beh == null: return
	var beh_script: Script = beh.get_script() as Script
	if beh_script == null:
		title = "(Missing Script)"
		return
	# Best-guess Title
	var classname = BehUtils.get_best_guess_script_class_name(beh_script)
	title = classname
	pass





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


