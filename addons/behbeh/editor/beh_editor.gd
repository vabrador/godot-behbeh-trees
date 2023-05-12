@tool
class_name BehTreeEditor
extends Control


# Buttons
@onready var graph: BehEditorGraphEdit = $HCtn/GraphEdit
# Action Panel Controls
@onready var btn_reset_view_root: Button = $HCtn/SideCtnMargins/SideCtn/ViewActionsCtn/BtnRecenterViewOnRoot
@onready var btn_open_beh: Button = $HCtn/SideCtnMargins/SideCtn/FileActionsCtn/BtnFileOpen
# Context Menu(s)
@onready var ctx_menu: PopupMenu = $ContextPopupMenu
@onready var ctx_add_node_panel: PopupPanel = $ContextAddNodePopupPanel
@onready var ctx_add_node_panel_ctn: VBoxContainer = $ContextAddNodePopupPanel/MarginCtn/VBoxCtn
# Side Container
@onready var side_ctn: VBoxContainer = $HCtn/SideCtnMargins/SideCtn
# Debug labels
@onready var dbg_active_node_label: Label = $HCtn/SideCtnMargins/SideCtn/DbgActiveNodeLabel
@onready var dbg_label_root_id: Label = $HCtn/SideCtnMargins/SideCtn/DbgInfoCtn/DbgLabelRootId
@onready var dbg_label_orphan_ct: Label = $HCtn/SideCtnMargins/SideCtn/DbgInfoCtn/DbgLabelOrphanCount


var editor_plugin: EditorPlugin = null
var _is_ready: bool = false;
var _centered_on_first_draw = false
var _bak_entry: BehEditorNodeEntry = null
var entry: BehEditorNodeEntry:
	get: return _get_or_construct_entry()
## Currently-focused BehTree. Null if none is selected or available.
var active_tree: BehTree = null
## Currently-focused BehNode. Null if none is selected or available.
var active_node: BehNode = null
var _should_update := false
#var _ctx_open := false
var _mouse_inside := false
var _add_beh_node_picker: EditorResourcePicker = null
var _new_node_pos = null
var _editor_node_map: Dictionary = {}
var _subscribed_editor_nodes: Dictionary = {}


# === Godot Events ===


# Called when the node enters the scene tree for the first time.
func _ready():
	subscribe_panel_btn_signals()
	subscribe_graph_edit_signals()
	subscribe_editor_node_signals()
	_is_ready = true


func _exit_tree():
	for key in _editor_node_map.keys():
		var ed_node = _editor_node_map[key]
		graph.remove_child(ed_node)
		_editor_node_map.erase(key)
		ed_node.queue_free()
	_editor_node_map.clear()
	_subscribed_editor_nodes.clear()
	_is_ready = false


func _draw():
	if !_centered_on_first_draw:
		_centered_on_first_draw = true
		center_view_on_root.call()
	if !_is_ready: return
	_should_update = true


#func _notification(what):
#	match what:
#		NOTIFICATION_MOUSE_ENTER:
#			print("MOUSE INSIDE")
#			_mouse_inside = true
#		NOTIFICATION_FOCUS_EXIT:
#			print("FOCUS OUTSIDE")
#			_mouse_inside = false
#		NOTIFICATION_DRAW:
#			print("DRAW")
#		NOTIFICATION_RESIZED:
#			print("RESIZED")
#		NOTIFICATION_EXIT_CANVAS:
#			print("NOTIFICATION_EXIT_CANVAS")
#		NOTIFICATION_DISABLED:
#			print("NOTIFICATION_DISABLED")
#		NOTIFICATION_VP_MOUSE_ENTER:
#			print("NOTIFICATION_VP_MOUSE_ENTER")
#		NOTIFICATION_VP_MOUSE_EXIT:
#			print("NOTIFICATION_VP_MOUSE_EXIT")
#		NOTIFICATION_FOCUS_EXIT:
#			print("MOUSE OUTSIDE")
#			_mouse_inside = false


#func _input(event: InputEvent):
#	if event is InputEventMouseButton:
#		if event.button_index == MOUSE_BUTTON_RIGHT && _mouse_inside:
#			print("mouse was inside")
#			if event.is_pressed():
#				print("opening context menu")
#				open_context_menu(event.position)
#				print("ctx menu is at %s" % ctx_menu.position)
#		else:
#			if _ctx_open:
#				print("closing context menu")
#				_ctx_open = false


func _process(dt):
	var should_process = Engine.is_editor_hint() && _should_update
	if !should_process: return
	_should_update = false
	
	# Nothing further to update if there is no active tree.
	if active_tree == null:
		return
	
	# Ensure that every node in the active_tree has an editor node.
	if active_tree.is_empty(): pass
	else:
		for beh in active_tree.get_all_nodes():
#		for beh in active_tree.root.get_all_children():
			var id = beh.get_instance_id()
			if !_editor_node_map.has(id):
				print("[BehEditor] _process() adding new BehEditorNode.")
				# Create a new EditorNode for this node.
				var new_ed_node = BehEditorNode.new()
				new_ed_node.beh = beh
				new_ed_node.init_node_view()
				if active_tree.has_editor_offset(beh):
					new_ed_node.position_offset = active_tree.get_editor_offset(beh)
				else: # Set a new editor position
					new_ed_node.position_offset = Vector2(100, 100) # temporary value for now
					active_tree.set_editor_offset(beh, new_ed_node.position_offset)
				graph.add_child(new_ed_node)
				_editor_node_map[id] = new_ed_node
				print("[BehEditor] _process(): new_ed_node name is %s, pos is %s, and its parent is %s" % [
					new_ed_node.name, new_ed_node.position_offset, new_ed_node.get_parent()])
			else:
#				print("[BehEditor] _editor_node_map already tracks id %s." % id)
				pass
		# Update editor node subscriptions.
		subscribe_editor_node_signals()
	
	# WIP: Editor-positions & auto-layout if none exist.
	if active_tree.root == null:
		print("Tree is empty, not updating editor positions")
	else:
		pass # TODO: Handle missing tree editor positions
	
	# Update entry -> tree root.
#	if active_tree.has_root():
#		entry.port
	
	# Update debug info.
	if active_tree.has_root():
		dbg_label_root_id.text = "Root Id: %s" % active_tree.root.get_instance_id()
	else:
		dbg_label_root_id.text = "Root Id: (none)"
	dbg_label_orphan_ct.text = "Tracked Orphan Count: %s" % len(active_tree.orphans)
	
	pass


# === Plugin Comms ===


func notify_edit_target(target: Variant):
	"""Called by the Plugin Loader when the plugin is asked to edit a new object."""
	var is_new_tree_target = target == null || target is BehTree
	if is_new_tree_target && active_tree != null: # Changing/clearing from an existing target
		print("BehTree: Target is changing, had a target already (possibly save pending changes here)")
	if is_new_tree_target:
		active_tree = target as BehTree
		active_node = null # Clear selected node.
		if active_tree != null:
			print("Just set edit target")
		else:
			print("Just CLEARED tree target")
	var is_node_target = target is BehNode
	if is_node_target && !expects_node_target():
		push_error("Unexpected node target! Target passed to this func should have been null")
	if is_node_target && expects_node_target():
		# Tree stays the same
		# active_node changes instead
		active_node = target as BehNode
		receive_node_target() # Perform actions based on the received node target we expected.
	_should_update = true


# === Context Menu & Add-Node Picker ===


func open_context_menu(graph_control_local_mouse_pos: Vector2):
	print("GOT open_context_menu")
	
	# Calculate where to spawn the new node based on the click.
	var graph_local_pos_ignore_scroll = graph_control_local_mouse_pos / graph.zoom
	var graph_local_pos = graph_local_pos_ignore_scroll + graph.scroll_offset / graph.zoom
	_new_node_pos = graph_local_pos
	# Spawn the context menu (which needs the global click position instead.)
	ctx_add_node_panel.position = graph.get_global_mouse_position()
	ctx_add_node_panel.size.x = 300
	ctx_add_node_panel.size.y = 60
	# Spawn the node picker inside the context popup panel.
	var beh_node_picker = init_beh_node_picker()
	if beh_node_picker.get_parent() != null: # Make sure parent is correct
		beh_node_picker.get_parent().remove_child(beh_node_picker)
	ctx_add_node_panel_ctn.add_child(beh_node_picker)
	ctx_add_node_panel.popup()


func init_beh_node_picker() -> EditorResourcePicker:
	if _add_beh_node_picker != null:
		return _add_beh_node_picker
	_add_beh_node_picker = EditorResourcePicker.new()
	_add_beh_node_picker.base_type = "BehNode"
#	_add_beh_node_picker.resource_selected.connect(on_erp_res_selected)
	_add_beh_node_picker.resource_changed.connect(on_erp_res_changed)
#	side_ctn.add_child(_add_beh_node_picker)
	return _add_beh_node_picker


func on_erp_res_changed(res: Resource):
	if res == null:
		print("[BehEditor] Resource selector cleared")
		return
#	print("BehEditor: EditorResourePicker Got resource changed signal! path is %s" % res.resource_path)
	print("[BehEditor] Adding new Orphan node for res instance id %s at pos %s" % [
		res.get_instance_id(), _new_node_pos])
	add_new_orphan_node(res, _new_node_pos)
	ctx_add_node_panel.hide()
	_add_beh_node_picker.edited_resource = null # Clear resource


#func on_erp_res_selected(res: Resource, inspect: bool):
##	editor_plugin.get_editor_interface().select_file(res.resource_path)
#	_expects_node_target = true # Prepare to receive node target...
#	editor_plugin.get_editor_interface().inspect_object(res)
#	print("Got 'selected', path of resource is %s" % res.resource_path)

# === Node Operations ===


func add_new_orphan_node(beh_node_inst: BehNode, node_spawn_pos: Vector2):
	"""Adds a new parent-less node to the active tree. The orphan will become the root of the tree
	and won't be tracked as an orphan if it is the first node to be added to the tree."""
	if active_tree == null:
		push_error("[BehEditor] Must have an active tree to add a new orphan node.")
		return
	if active_tree.is_empty():
		active_tree.root = beh_node_inst
	else: # Add to the orphans list.
		active_tree.orphans.push_back(beh_node_inst)
	active_tree.set_editor_offset(beh_node_inst, node_spawn_pos)
	print("[BehEditor] Adding node at %s" % node_spawn_pos)
	print("[BehEditor] OK, added new orphan node. active_tree orphans count is %s" % len(active_tree.orphans))
	_should_update = true

# === Node Selection ===


var _expects_node_target = false
func expects_node_target() -> bool:
	return _expects_node_target


func receive_node_target():
	"""Called by 'notify_edit_target' coming from a plugin callback. Used to do logic when
	a node in this tree is selected instead of the tree itself."""
	if !expects_node_target():
		push_error("Must expect node target to call this")
		return
	if active_node == null:
		push_error("Must have active node to call this")
		return
	print("OK: receive_node_target() called, consuming")
	_expects_node_target = false
	dbg_active_node_label.text = "Active Node: %s" % active_node.get_class()


# === UI Signals ===


func subscribe_panel_btn_signals():
	btn_reset_view_root.pressed.connect(center_view_on_root)
#	btn_open_beh.pressed.connect(file_open_dialog())


func subscribe_graph_edit_signals():
	print("SUBSCRIBING TO GRAPH EDIT SIGNALS")
	graph.popup_request.connect(open_context_menu)
#	graph.open_context_menu.connect(open_context_menu)
#	graph.end_node_move.connect()


func subscribe_editor_node_signals():
	"""OK to call multiple times when editor nodes are created; tracks subscriptions and avoids
	resubscribing."""
	for id in _editor_node_map.keys():
		var is_subscribed = _subscribed_editor_nodes.has(id)
		if !is_subscribed:
			var node_id_copy: int = id
			var ed_node: BehEditorNode = _editor_node_map[id]
			ed_node.position_offset_changed.connect(func(): on_editor_node_pos_changed(node_id_copy))
			_subscribed_editor_nodes[id] = true


func on_editor_node_pos_changed(node_id: int):
	if !_editor_node_map.has(node_id):
		push_warning("Got on_editor_node_dragged for unknown editor_node id %s" % node_id)
		return
	var ed_node: BehEditorNode = _editor_node_map[node_id]
	if ed_node.beh == null:
		if ed_node is BehEditorNodeEntry:
			# This is fine -- entry nodes are virtual nodes with no backing behavior.
			return
		else:
			push_error("Node ID %s is missing a backing NodeBeh" % node_id)
			return
	# Update the position!
	active_tree.set_editor_offset(ed_node.beh, ed_node.position_offset)
#	print("[BehEditor] Successfully set a tree's NodeBeh editor offset via ed_node.position_offset! Value: %s" % [
#		active_tree.get_editor_offset(ed_node.beh)])
	pass

# === View Management ===


func get_view_center_offset() -> Vector2:
	return graph.size / 2


func center_view_on_root():
	if entry == null:
		return
	var entry_pos_ofs = entry.get_center()
	graph.scroll_offset = entry_pos_ofs - get_view_center_offset()


#func auto_layout_tree(tree: BehTree):
#	"""Sets editor node positions of the tree"""


# === IO ===

#var open_dialog: EditorFileDialog = null
#
#
#func file_open_dialog():
#	print("FILE OPEN")
#	open_dialog = EditorFileDialog.new()
#	open_dialog.add_filter("*.tres", )


# === Helpers ===


## Impl for get "self.entry" virtual node.
func _get_or_construct_entry() -> BehEditorNode:
	# Ensures the root node exists and is accessible via _root.
	if _bak_entry == null:
		# Check by name.
		var existing_root = graph.get_node_or_null("Entry")
		if existing_root != null && not (existing_root is BehEditorNodeEntry):
			print("[BehTreeEditor] Existing Entry root is of the wrong type; recreating it.")
			existing_root.queue_free()
#			push_error("[BehTreeEditor] Child 'Entry' is not of type BehEditorNode. Invalid setup, returning null.")
#			return null
		_bak_entry = existing_root as BehEditorNodeEntry
		if _bak_entry == null:
			# Make.
			var new_entry = BehEditorNodeEntry.new()
			new_entry.init_node_view()
			graph.add_child(new_entry)
			_bak_entry = new_entry
	if _bak_entry == null:
		push_error("[BehTreeEditor] Failed to get or create root node!")
	return _bak_entry


