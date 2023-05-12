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

# TODO: DELETEME
#var _bak_entry: BehEditorNodeEntry = null
#var entry: BehEditorNodeEntry:
#	get: return _get_or_construct_entry()


# === Godot Events ===


# Called when the node enters the scene tree for the first time.
func _ready():
	subscribe_panel_btn_signals()
	subscribe_graph_edit_signals()
	subscribe_editor_node_signals()
	_is_ready = true


func _exit_tree():
	clear_editor_nodes()
	_is_ready = false


func clear_editor_nodes():
	print("[BehEditor] Clearing editor nodes (unsubscribing first) and map cache for them.")
	unsubscribe_editor_node_signals()
	if len(_subscribed_editor_nodes) > 0:
		push_warning("[BehEditor] Still had some editor node subscriptions after attempting " +
			"to unsubscribe from them.")
		_subscribed_editor_nodes.clear()
	graph.clear_connections() # Clear connections, prevents errors when freeing GraphNodes
	for key in _editor_node_map.keys():
		var ed_node = _editor_node_map[key]
		_editor_node_map.erase(key)
		graph.remove_child(ed_node)
		ed_node.queue_free()
	_editor_node_map.clear()


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

var _subscribed_active_tree: BehTree = null


func _process(dt):
	var should_process = Engine.is_editor_hint() && _should_update
	if !should_process: return
	_should_update = false
	print("[BehEditor] _process called and had _should_update.")
	
	# Nothing further to update if there is no active tree.
	if active_tree == null:
		return
	
	print("[BehEditor] Updating.")
	
	# Update subscriptions.
	# -------------
	#
	# Ensure we're subscribed to the right active_tree.
	if _subscribed_active_tree != active_tree:
		if _subscribed_active_tree != null:
			_subscribed_active_tree.disconnect("tree_changed", on_tree_changed)
		active_tree.tree_changed.connect(on_tree_changed)
		_subscribed_active_tree = active_tree
			
	# Update editor node subscriptions.
	subscribe_editor_node_signals()
	
	# Save the active_tree.
	# ---------------------
	#
	# This needs to happen prior to updating BehNodeEditors, because the act of saving
	# with the subresource_paths argument creates resource_paths for any newly-added
	# subresources entries in the tree.
	save_active_tree()
	
	# Validate the tree.
	# ------------------
	#
	# And save again if validation changed the tree.
	if active_tree.validate_roots_and_orphans():
		save_active_tree()
	
	# Node Editor view objects
	# ------------------------
	#
	# Ensure that every node in the active_tree has an editor node.
	if active_tree.is_empty(): pass # (Nothing to render in this case)
	else:
		for beh in active_tree.get_all_nodes():
			var id = beh.try_get_stable_id()
			if id == null:
				print("[BehEditor] (BehEditorNode Sync) Skipping missing stab_id for node %s" % [
					beh.get_instance_id()])
			if id != null && !(id is StringName):
				push_error("Expected StringName as NodeBeh stable_id for node %s" % beh.get_instance_id())
			if id != null && id is StringName && !_editor_node_map.has(id):
				print("[BehEditor] (BehEditorNode Sync) Creating new BehEditorNode for node %s" % id)
				create_ed_node_and_update_map(beh, id)
			# Normal sync for each BehEditorNode.
			if id != null && id is StringName && _editor_node_map.has(id):
				var ed_node: BehEditorNode = _editor_node_map[id]
				var valid_beh = ed_node.validate_beh()
#				if !valid_beh:
#					ed_node.set_title_color(BehEditorNode.RED)
				if valid_beh:
					ed_node.is_orphan = active_tree.get_is_orphan(ed_node.beh)
				# Children connections.
				for child_beh in ed_node.beh.get_children():
					var child_id = child_beh.try_get_stable_id()
					print("[BehEditor] (BehEditorNode Sync Children) Considering parent %s, child %s" % [
						id, child_id])
					if child_id == null:
						push_error("[BehEditor] (BehEditorNode Sync Children) Failed to get child stable ID.")
						continue
					if id == child_id:
						push_error("[BehEditor] (BehEditorNodeSync Children) Unexpected: child_id and parent id match: %s" % [
							id])
						continue
					if !_editor_node_map.has(child_id):
						print("[BehEditor] (BehEditorNode Sync Children) Creating new BehEditorNode for node %s" % child_id)
						create_ed_node_and_update_map(child_beh, child_id)
					var child_ed_node: BehEditorNode = _editor_node_map[child_id]
					print("[BehEditor] (BehEditorNode Sync Children) Calling graph.connect_node")
					var conn_err = graph.connect_node(ed_node.name, 0, child_ed_node.name, 0)
					print("[BehEditor] (BehEditorNode Sync Children) DONE calling graph.connect_node")
					if conn_err:
						print("[BehEditor] (BehEditorNode Sync Children) Error connecting %s -> %s: %s" % [
							ed_node.name, child_ed_node.name, conn_err])
#					else:
#						print("[BehEditor] (BehEditorNode Sync Children) Connected")
	
	# Update debug info.
	dbg_label_root_id.text = "Root Count: %s" % len(active_tree.roots)
	dbg_label_orphan_ct.text = "Orphan Count: %s" % len(active_tree.orphans)
	
	pass


func on_tree_changed():
	"""Update visual representation if the BehTree reports that it has changed in some way."""
	print("[BehEditor] Got signal from tree: tree_changed")
	_should_update = true


func create_ed_node_and_update_map(beh: BehNode, id: StringName):
	"""Side-effect: Updates _editor_node_map"""
	if _editor_node_map.has(id):
		push_error("[BehEditor] (create_ed_node_and_update_map) _editor_node_map already contained id %s" % id)
		return
	# Create a new EditorNode for this node.
	var new_ed_node = BehEditorNode.new()
	new_ed_node.name = "EditorNode_%s" % id
	new_ed_node.beh = beh
	new_ed_node.init_node_view()
	if active_tree.has_editor_offset(beh):
		var known_offset = active_tree.get_editor_offset(beh)
		print("[BehEditor] (BehEditorNode Sync) active_tree HAS offset for %s: %s" % [
			id, known_offset])
		new_ed_node.position_offset = active_tree.get_editor_offset(beh)
	else: # Set a new editor position
		print("[BehEditor] (BehEditorNode Sync) Generating new offset for %s" % id) 
		new_ed_node.position_offset = Vector2(100, 100) # temporary value for now
		active_tree.set_editor_offset(beh, new_ed_node.position_offset)
	graph.add_child(new_ed_node)
	_editor_node_map[id] = new_ed_node
	print("[BehEditor] (create_ed_node_and_update_map) new_ed_node name is %s, pos is %s, and its parent is %s" % [
		new_ed_node.name, new_ed_node.position_offset, new_ed_node.get_parent()])


func save_active_tree():
	print("[BehEditor] (Save) Saving...")
	if active_tree != null && active_tree.resource_path != "":
#		print("[BehEditor] Saving active_tree with FLAG_REPLACE_SUBRESOURCE_PATHS...")
		var error = ResourceSaver.save(active_tree, "", ResourceSaver.FLAG_REPLACE_SUBRESOURCE_PATHS)
		if error: push_error("[BehEditor] (Save) Error saving active_tree %s: %s" % [active_tree, error])
#		else: print("[BehEditor] Saved active_tree.")
		var nodes_ct = 0
		var nodes_lacking_resource_path_ct = 0
#		var child_save_ct = 0
		for child in active_tree.get_all_nodes():
			if child.resource_path == "":
				push_warning(("[BehEditor] (Save) Warning: BehNode (%s) lacks resource_path. " + \
				".") % [
					child.get_instance_id()])
				nodes_lacking_resource_path_ct += 1
			nodes_ct += 1
#			if error: push_error("[BehEditor] (Save) Trying to save child with path: %s" % child.resource_path)
#			error = ResourceSaver.save(child, child.resource_path, ResourceSaver.FLAG_REPLACE_SUBRESOURCE_PATHS)
#			if error: push_error("[BehEditor] (Save) Error saving child %s: %s" % [child, error])
#			else: child_save_ct += 1
		if nodes_lacking_resource_path_ct == 0:
			print("[BehEditor] (Save) Success. All %s nodes had resource_path." % nodes_ct)
			pass
#		if nodes_ct == child_save_ct:
#			print("[BehEditor] (Save) Success. All %s children were saved." % child_save_ct)
#		else:
#			push_warning("[BehEditor] (Save) Node ct was %s but only saved %s children." % [nodes_ct, child_save_ct])
	print("[BehEditor] (Save) Finished saving.")


# === Plugin Comms ===


func notify_edit_target(target: Variant):
	"""Called by the Plugin Loader when the plugin is asked to edit a new object."""
	print("[BehEditor] notify_edit_target with target (null if blank): %s" % target)
	var is_new_tree_target = target == null || target is BehTree
	if is_new_tree_target && active_tree != null: # Changing/clearing from an existing target
		print("[BehEditor] Target is changing, had a target already (possibly save pending changes here)")
	if is_new_tree_target:
		active_tree = target as BehTree
		active_node = null # Clear selected node.
		if active_tree != null:
			print("[BehEditor] Just set edit target")
		else:
			print("[BehEditor] CLEARING tree target. Removing old edit nodes")
			clear_editor_nodes()
			
	var is_node_target = target is BehNode
	if is_node_target && !expects_node_target():
		push_error("[BehEditor] Unexpected node target! Target passed to this func should have been null")
	if is_node_target && expects_node_target():
		# Tree stays the same
		# active_node changes instead
		active_node = target as BehNode
		receive_node_target() # Perform actions based on the received node target we expected.
	_should_update = true


# === Context Menu & Add-Node Picker ===


func open_context_menu(graph_control_local_mouse_pos: Vector2):
	print("[BehEditor] GOT open_context_menu")
	
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
	add_new_node(res, _new_node_pos)
	ctx_add_node_panel.hide()
	_add_beh_node_picker.edited_resource = null # Clear resource


#func on_erp_res_selected(res: Resource, inspect: bool):
##	editor_plugin.get_editor_interface().select_file(res.resource_path)
#	_expects_node_target = true # Prepare to receive node target...
#	editor_plugin.get_editor_interface().inspect_object(res)
#	print("Got 'selected', path of resource is %s" % res.resource_path)

# === Node Operations ===


func add_new_node(beh_node_inst: BehNode, node_spawn_pos: Vector2):
	"""Adds a new parent-less node to the active tree. The orphan will become the root of the tree
	and won't be tracked as an orphan if it is the first node to be added to the tree."""
	if active_tree == null:
		push_error("[BehEditor] Must have an active tree to add a new orphan node.")
		return
	active_tree.add_node(beh_node_inst)
	save_active_tree() # Generates a stable ID for the new node so we can set_editor_offset.
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
	print("[BehEDitor] SUBSCRIBING TO GRAPH EDIT SIGNALS")
	graph.popup_request.connect(open_context_menu)
#	graph.open_context_menu.connect(open_context_menu)
	graph.end_node_move.connect(on_graph_end_node_move)
	graph.connection_request.connect(on_graph_connection_request)


func subscribe_editor_node_signals():
	"""OK to call multiple times when editor nodes are created; tracks subscriptions and avoids
	resubscribing."""
	for id in _editor_node_map.keys():
		var is_subscribed = _subscribed_editor_nodes.has(id)
		if !is_subscribed:
			var ed_node: BehEditorNode = _editor_node_map[id]
			var callable = func(): on_editor_node_pos_changed(id)
			ed_node.position_offset_changed.connect(callable)
			_subscribed_editor_nodes[id] = ["position_offset_changed", callable]

func unsubscribe_editor_node_signals():
	"""Cleans up editor node signals. Call this before freeing editor nodes."""
	for id in _editor_node_map.keys():
		var is_subscribed = _subscribed_editor_nodes.has(id)
		if is_subscribed:
			var ed_node: BehEditorNode = _editor_node_map[id]
			var signal_callable_pair = _subscribed_editor_nodes[id]
			var signal_name = signal_callable_pair[0]
			var callable = signal_callable_pair[1]
			ed_node.disconnect(signal_name, callable)
			_subscribed_editor_nodes.erase(id)
		


func on_editor_node_pos_changed(node_id: StringName):
	if !_editor_node_map.has(node_id):
		push_warning("[BehEditor] Got on_editor_node_dragged for unknown editor_node id %s" % node_id)
		return
	var ed_node: BehEditorNode = _editor_node_map[node_id]
	if ed_node.beh == null:
		push_error("[BehEditor] Node ID %s is missing a backing NodeBeh" % node_id)
		return
	# Update the position!
	active_tree.set_editor_offset(ed_node.beh, ed_node.position_offset)
#	print("[BehEditor] Successfully set a tree's NodeBeh editor offset via ed_node.position_offset! Value: %s" % [
#		active_tree.get_editor_offset(ed_node.beh)])
	pass


func on_graph_end_node_move():
	_should_update = true # Resave so that we capture new node positions.


func on_graph_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int):
	if active_tree == null:
		print("[BehEditor] (Connection Request) Ignoring on_graph_connection_request as active_tree is null.")
		return
	# Debugging, figure out what's being called
	print(("[BehEditor] (Connection Request) from_node %s port %s -> to_node %s to_port %s") % [
		from_node, from_port, to_node, to_port])
	
	# Validate this connection is theoretically possible.
	var ed_from = graph.get_node_or_null(NodePath(from_node)) as BehEditorNode
	var ed_to = graph.get_node_or_null(NodePath(to_node)) as BehEditorNode
	print("[BehEditor] (Connection Request) found ed_from? %s" % (ed_from != null))
	print("[BehEditor] (Connection Request) found ed_to?   %s" % (ed_to != null))
	if ed_from == null || ed_to == null: return
	if !ed_from.validate_beh():
		print("[BehEditor] (Connection Request) ed_from had invalidate beh.")
		return
	if !ed_to.validate_beh():
		print("[BehEditor] (Connection Request) ed_to had invalidate beh.")
		return
	
	# Try to add child "from" -> "to"; this might fail.
	if ed_from.beh.try_add_child(ed_to.beh):
		print("[BehEditor] (Connection Request) Successfully added a child relationship: %s -> %s" % [
			ed_from.beh, ed_to.beh])
		# graph.connect_node() will be called from the update as a part of the node sync
		# process.
		_should_update = true


	_should_update = true
	pass


# === View Management ===


func get_view_center_offset() -> Vector2:
	return graph.size / 2


func center_view_on_root():
	print("[BehEditor] (center_view_on_root) Disabled for now.")
#	if active_tree == null || !active_tree.has_roots(): return
#	if active_tree.has_roots
#	if entry == null:
#		return
#	var entry_pos_ofs = entry.get_center()
#	graph.scroll_offset = entry_pos_ofs - get_view_center_offset()
	pass


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


# TODO: DELETE
### Impl for get "self.entry" virtual node.
#func _get_or_construct_entry() -> BehEditorNode:
#	# Ensures the root node exists and is accessible via _root.
#	if _bak_entry == null:
#		# Check by name.
#		var existing_root = graph.get_node_or_null("Entry")
#		if existing_root != null && not (existing_root is BehEditorNodeEntry):
#			print("[BehEditor] Existing Entry root is of the wrong type; recreating it.")
#			existing_root.queue_free()
##			push_error("[BehEditor] Child 'Entry' is not of type BehEditorNode. Invalid setup, returning null.")
##			return null
#		_bak_entry = existing_root as BehEditorNodeEntry
#		if _bak_entry == null:
#			# Make.
#			var new_entry = BehEditorNodeEntry.new()
#			new_entry.init_node_view()
#			graph.add_child(new_entry)
#			_bak_entry = new_entry
#	if _bak_entry == null:
#		push_error("[BehEditor] Failed to get or create root node!")
#	return _bak_entry
#

