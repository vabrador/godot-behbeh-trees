@tool
class_name BehEditorNode
extends GraphNode


const COLOR_CONNECTION_CONTROL_FLOW := Color.AQUAMARINE
const COLOR_TITLE_ORPHAN := Color.ORANGE


var beh: BehNode = null
var order_label: Label = null
var custom_label: Label = null
var child_index := -1
var call_order_matters := false
var _needs_update := false
var _is_orphan := false
var is_orphan: bool:
	get: return _is_orphan
	set(value):
		if _is_orphan != value: _needs_update = true
		_is_orphan = value
var dbg_label: Label = null
var _mouse_inside := false


# === Signals ===


signal mouse_clicked(this_node: BehEditorNode)


# === Godot Events ===


func _ready():
	self.mouse_entered.connect(on_mouse_entered)


func _draw():
	_needs_update = true


func _process(_dt):
	if !Engine.is_editor_hint(): return
	if !_needs_update: return
	_needs_update = false
	update_view()


func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT && event.pressed:
#			print("[BehEditorNode] Clicked! Emitting mouse_clicked signal.")
			mouse_clicked.emit(self)


# === UI Signals ===


func on_mouse_entered():
	_mouse_inside = true


func on_mouse_exited():
	_mouse_inside = false


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
	
#	# Initialize a label on the interior of the node with debug information.
#	if self.dbg_label == null:
#		self.dbg_label = Label.new()
#		self.add_child(dbg_label)
	if self.order_label == null:
		self.order_label = Label.new()
		self.order_label.add_theme_color_override("font_color", Color.DIM_GRAY)
		self.add_child(order_label)
	if self.custom_label == null:
		self.custom_label = Label.new()
		self.custom_label.add_theme_color_override("font_color", Color.DARK_GRAY)
		self.add_child(custom_label)
		


func update_view():
	if _is_orphan:
		self.add_theme_color_override("title_color", COLOR_TITLE_ORPHAN)
	else:
		self.add_theme_color_override("title_color", beh.editor_get_color())
	
#	# Debug label text.
#	dbg_label.text = "name: ...%s\ninst: ...%s" % [\
#		name.substr(len(String(name)) - 5), str(self.get_instance_id()).substr(len(str(self.get_instance_id())) - 5)]
	
	# Order label text for when the label is in a sequence.
	if self.call_order_matters && self.child_index != -1:
		order_label.text = "(Sequence: %s)" % self.child_index
		order_label.show()
	else:
		order_label.text = ""
		order_label.hide()
	
	if !validate_beh():
		render_view_invalid()
	else:
		var custom_text = beh.editor_get_body_text()
		if custom_text == null: custom_text = ""
		if custom_label != null:
			custom_label.text = custom_text
			if len(custom_label.text) > 0: custom_label.show()
			else: custom_label.hide()
		
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


