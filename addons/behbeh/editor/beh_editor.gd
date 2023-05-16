@tool
class_name BehTreeEditor
extends Control


# Buttons
@onready var graph: BehEditorGraphEdit = $HCtn/GraphEdit
# Action Panel Controls
@onready var btn_reset_view_root: Button = $HCtn/SideCtnMargins/SideCtn/ViewActionsCtn/BtnRecenterViewOnRoot
@onready var btn_open_beh: Button = $HCtn/SideCtnMargins/SideCtn/FileActionsCtn/BtnFileOpen
# Context Menu(s)
## GRAPH context menu, for e.g. adding new nodes.
@onready var ctx_menu_graph: PopupPanel = $ContextAddNodePopupPanel
@onready var ctx_menu_graph_ctn: VBoxContainer = $ContextAddNodePopupPanel/MarginCtn/VBoxCtn
## NODE context menu, for operations on selected node(s).
@onready var ctx_menu_node: PopupMenu = $ContextPopupMenu
# Side Container
@onready var side_ctn: VBoxContainer = $HCtn/SideCtnMargins/SideCtn
# Debug labels
@onready var dbg_active_node_label: Label = $HCtn/SideCtnMargins/SideCtn/DbgActiveNodeLabel
@onready var dbg_label_root_id: Label = $HCtn/SideCtnMargins/SideCtn/DbgInfoCtn/DbgLabelRootId
@onready var dbg_label_orphan_ct: Label = $HCtn/SideCtnMargins/SideCtn/DbgInfoCtn/DbgLabelOrphanCount
@onready var dbg_label_beh_ct: Label = $HCtn/SideCtnMargins/SideCtn/DbgInfoCtn/DbgLabelBehCt
@onready var dbg_label_generic: Label = $HCtn/SideCtnMargins/SideCtn/DbgInfoCtn/DbgLabelGeneric


var editor_plugin: EditorPlugin = null
var _is_ready: bool = false
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
var _subscribed_active_tree: BehTree = null
var _subscribed_editor_nodes: Dictionary = {}
var _selected_nodes: Dictionary = {}
var _copy_nodes_buffer: Array[BehEditorNode] = []
var _ctx_menu_node_id_pressed_subscribed = false
var _pending_node_positions = {} # Used to place nodes that don't yet have stable_ids from saving.
var _pending_parent_child_relations = [] # Used to parent nodes that don't yet have stable_ids from saving.


enum ContextMenuType { GraphCtxMenu, NodeCtxMenu }
var _ctx_menu_node_entries: Array[Dictionary] = [
	{ "id": 0,	"name": "Node Context Menu",	"action": null, },
	{ "id": 1,	"name": "Copy", 				"action": "on_copy_nodes_request", },
	{ "id": 2,	"name": "Paste",				"action": "on_paste_nodes_request", },
	{ "id": 3,	"name": "Delete",				"action": "on_delete_nodes_request", },
	{ "id": 4,	"name": "Duplicate",			"action": "on_duplicate_nodes_request", },
	{ "id": 5,	"name": "Clear Copy Buffer",	"action": "on_clear_copy_buffer_request", },
]
var _ctx_menu_node_separators: Array[int] = [ ]


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


func _draw():
	if !_is_ready: return
	_should_update = true


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
	if active_tree.validate_single_parents():
		save_active_tree()
	
	# Process _pending_node_positions in case BehNodes want editor positions but didn't
	# have stable_ids when they were spawned.
	if len(_pending_node_positions) > 0:
		for beh_node in _pending_node_positions.keys():
			var desired_pos = _pending_node_positions[beh_node]
			active_tree.set_editor_offset(beh_node, desired_pos)
		_pending_node_positions.clear()
		_should_update = true # Re-update to invoke a re-save.
	# Process _pending_parent_child_relations. This is used to allow parent-child node
	# pastes to properly allow child nodes to receive stable_ids by first being added as
	# orphans, then receiving their parent-childing later.
	if len(_pending_parent_child_relations) > 0:
		for pair in _pending_parent_child_relations:
			var parent_beh: BehNode = pair[0]
			var child_beh: BehNode = pair[1]
			if !parent_beh.try_add_child(child_beh):
				push_error("[BehEditor] (update _pending_parent_child_relations) Failed to add pended-child; parent %s -> child %s" % [
					parent_beh, child_beh])
			else:
				pass # No issue.
		_pending_parent_child_relations.clear()
		_should_update = true # Re-update to invoke a re-save.
	
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
				# Update orphan status for editor nodes.
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
					if conn_err:
						push_error("[BehEditor] (BehEditorNode Sync Children) Error connecting %s -> %s: %s" % [
							ed_node.name, child_ed_node.name, conn_err])
					print("[BehEditor] (BehEditorNode Sync Children) DONE calling graph.connect_node")
#					else:
#						print("[BehEditor] (BehEditorNode Sync Children) Connected")
	
	# Validate selected nodes
	# -----------------------
	for sel_key_name in _selected_nodes.keys():
#		var sel_node = _selected_nodes[sel_key_name]
		var sel_node = graph.get_node_or_null(sel_key_name)
		if sel_node == null:
			push_warning("[BehEditor] (Validate Selected Nodes) Removing a null node from selection (deleted?)")
			_selected_nodes.erase(sel_key_name)
	
	# Update debug info.
	dbg_label_root_id.text = "Root Tree Count: %s" % len(active_tree.roots)
	dbg_label_orphan_ct.text = "Orphan Tree Count: %s" % len(active_tree.orphans)
	dbg_label_beh_ct.text = "Total Beh Count: %s" % len(active_tree.get_all_nodes())
	dbg_label_generic.text = (
		"Selection Count: %s" +
		"\nNode Meta Size: %s"
	) % [
		len(_selected_nodes),
		"(tree null)" if active_tree == null else str(len(active_tree.node_meta.keys()))
	]
	
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


func get_graph_local_pos_from_control_pos(control_local_pos: Vector2) -> Vector2:
	var graph_local_pos_wo_scroll = control_local_pos / graph.zoom
	var graph_local_pos = graph_local_pos_wo_scroll + graph.scroll_offset / graph.zoom
	return graph_local_pos


func on_request_ctx_menu(mouse_graph_control_local_pos: Vector2):
	print("[BehEditor] GOT on_request_ctx_menu")
	
	# Calculate where the click was in the control.
	var mouse_graph_local_pos = get_graph_local_pos_from_control_pos(mouse_graph_control_local_pos)
	print("[BehEditor] (on_request_ctx_menu) mouse_graph_control_local_pos = %s" % mouse_graph_control_local_pos)
	print("[BehEditor] (on_request_ctx_menu) mouse_graph_local_pos = %s" % mouse_graph_local_pos)
	
	# Type of context menu to open.
	var context_menu_type := ContextMenuType.GraphCtxMenu
	
	# Determine whether this is a node_context_menu action or a
	# graph_context_menu action.
	#
	# Right-click any selected node to get the node context menu isntead of the
	# graph context menu.
	var clicked_node = null
	if len(_selected_nodes) > 0:
		for node_name_key in _selected_nodes:
			var node: BehEditorNode = try_get_node_from_name(node_name_key)
			if node == null:
				continue
			var hitbox_control_local = node.get_rect()
			if hitbox_control_local.has_point(mouse_graph_control_local_pos):
				print("[BehEditor] (on_request_ctx_menu) Clicked node: %s @ %s" % [
					node.name, hitbox_control_local])
				clicked_node = node
				break
			else:
				print("[BehEditor] (on_request_ctx_menu) Click missed node: %s @ %s" % [
					node.name, hitbox_control_local])
	if clicked_node != null:
		print("[BehEditor] (on_request_ctx_menu) Context menu on node: %s" % clicked_node.name)
		context_menu_type = ContextMenuType.NodeCtxMenu
	
	match context_menu_type:
		ContextMenuType.GraphCtxMenu:
			open_graph_ctx_menu(mouse_graph_control_local_pos)
		ContextMenuType.NodeCtxMenu:
			open_node_ctx_menu(mouse_graph_control_local_pos)
		_:
			push_error("[BehEditor] (on_request_ctx_menu) Unhandled %s" % context_menu_type)
	pass


func open_graph_ctx_menu(mouse_graph_control_local_pos: Vector2):
	# Calculate where the click was in the control.
	var mouse_graph_local_pos = get_graph_local_pos_from_control_pos(mouse_graph_control_local_pos)
	print("[BehEditor] (open_graph_ctx_menu) mouse_graph_local_pos = %s (will be used for new nodes)" % mouse_graph_local_pos)
	_new_node_pos = mouse_graph_local_pos
	
	# Spawn the context menu (which needs the global click position instead.)
	ctx_menu_graph.position = graph.get_global_mouse_position()
	ctx_menu_graph.size.x = 300
	ctx_menu_graph.size.y = 60
	# Spawn the node picker inside the context popup panel.
	var beh_node_picker = init_beh_node_picker()
	if beh_node_picker.get_parent() != null: # Make sure parent is correct
		beh_node_picker.get_parent().remove_child(beh_node_picker)
	ctx_menu_graph_ctn.add_child(beh_node_picker)
	ctx_menu_graph.popup()


func open_node_ctx_menu(mouse_graph_control_local_pos: Vector2):
	# Calculate where the click was in the control.
	var mouse_graph_local_pos = get_graph_local_pos_from_control_pos(mouse_graph_control_local_pos)
	print("[BehEditor] (open_node_ctx_menu) mouse_graph_local_pos = %s" % mouse_graph_local_pos)
	
	# Spawn the context menu (which needs the global click position instead.)
	ctx_menu_node.position = graph.get_global_mouse_position()
#	ctx_menu_graph.position = graph.get_global_mouse_position()
#	ctx_menu_graph.size.x = 300
#	ctx_menu_graph.size.y = 60
	
	ctx_menu_node.clear()
	var entry_id = 0
	for entry in _ctx_menu_node_entries:
		ctx_menu_node.add_item(entry.name, entry.id)
		if entry.action == null:
			ctx_menu_node.set_item_disabled(entry_id, true)
		entry_id += 1
	for sep_idx in _ctx_menu_node_separators:
		ctx_menu_node.add_separator("", sep_idx)
	if !_ctx_menu_node_id_pressed_subscribed:
		ctx_menu_node.id_pressed.connect(on_ctx_menu_node_id_pressed)
		_ctx_menu_node_id_pressed_subscribed = true
	ctx_menu_node.popup()


func on_ctx_menu_node_id_pressed(pressed_id: int):
	print("[BehEditor] (on_ctx_menu_node_id_pressed) For pressed_id: %s" % pressed_id)
	var pressed_entry = null
	for entry in _ctx_menu_node_entries:
		if entry.id == pressed_id:
			pressed_entry = entry
			print("[BehEditor] (on_ctx_menu_node_id_pressed) Matched entry: %s" % pressed_entry.name)
			break
	if pressed_entry == null:
		push_error("[BehEditor] (on_ctx_menu_node_id_pressed) Failed to find entry for pressed id %s" % pressed_id)
		return
	var action_name = pressed_entry["action"]
	if action_name == null:
		push_warning("[BehEditor] (on_ctx_menu_node_id_pressed) Ignoring pressed for actionless entry %s" % pressed_entry.name)
		return
	self.call(action_name)


func init_beh_node_picker() -> EditorResourcePicker:
	"""ContextMenu -> Add Node. Spawns an EditorResourcePicker intended for the Graph context menu."""
	if _add_beh_node_picker != null:
		return _add_beh_node_picker
	_add_beh_node_picker = EditorResourcePicker.new()
	_add_beh_node_picker.base_type = "BehNode"
	_add_beh_node_picker.resource_changed.connect(on_erp_res_changed)
	return _add_beh_node_picker


func on_erp_res_changed(res: Resource):
	"""Called when the EditorResourcePicker resource changes in the New Node context."""
	if res == null:
		print("[BehEditor] Resource selector cleared")
		return
#	print("BehEditor: EditorResourePicker Got resource changed signal! path is %s" % res.resource_path)
	print("[BehEditor] Adding new Orphan node for res instance id %s at pos %s" % [
		res.get_instance_id(), _new_node_pos])
	add_new_node(res, _new_node_pos)
	ctx_menu_graph.hide()
	_add_beh_node_picker.edited_resource = null # Clear resource


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


func try_get_node_from_name(node_name: StringName, silent_on_not_found: bool = false) -> Variant:
	"""Returns BehEditorNode or null if not found."""
	var node = graph.get_node_or_null(NodePath(node_name))
	if node == null && !silent_on_not_found:
		push_error("[BehEditor] (try_get_node_from_name) Failed to find node %s" % node_name)
	var node_as_ed_node = node as BehEditorNode
	if node_as_ed_node == null:
		push_error("[BehEditor] (try_get_node_from_name) Found %s but was not BehEditorNode" % node_name)
	return node_as_ed_node


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
#	btn_reset_view_root.pressed.connect(center_view_on_root)
#	btn_open_beh.pressed.connect(file_open_dialog())
	pass


func subscribe_graph_edit_signals():
	print("[BehEditor] Subscribing to GraphEdit signals.")
	# Basics
	graph.popup_request.connect(on_request_ctx_menu)
	graph.end_node_move.connect(on_graph_end_node_move)
	# Other Interactions
	graph.delete_nodes_request.connect(on_delete_nodes_request)
	graph.node_selected.connect(on_node_selected)
	graph.node_deselected.connect(on_node_deselected)
	graph.copy_nodes_request.connect(on_copy_nodes_request)
	graph.paste_nodes_request.connect(on_paste_nodes_request)
	graph.connection_request.connect(on_connection_request)
	graph.disconnection_request.connect(on_disconnection_request)


func on_delete_nodes_request(nodes = null):
	if nodes == null || len(nodes) == 0: # Use selection
		nodes = []
		for sel_name in _selected_nodes.keys():
			nodes.push_back(sel_name)
		print("[BehEditor] (on_delete_nodes_request) Got NULL delete request (ctx menu action), set via %s selected nodes" % [
			len(nodes)])
	print("[BehEditor] (on_delete_nodes_request) Got delete nodes request: %s" % [nodes])
	for del_node_name in nodes:
		var del_node = graph.get_node_or_null(NodePath(del_node_name))
		if del_node == null:
			push_warning("[BehEditor] (on_delete_nodes_request) node to delete %s was null" % del_node_name)
			continue
		remove_editor_node(del_node)
		# Now remove the node from the active_tree so an editor node doesn't respawn for it.
		if del_node.beh == null:
			push_warning("[BehEditor] (on_delete_nodes_request) Deleted ed_node that had no beh.")
		else:
			var removed_node = active_tree.remove_node(del_node.beh)
			if removed_node == null:
				push_warning("[BehEditor] Failed to remove a node from the active_tree (didn't exist)")
			else:
				pass # Don't free() the node, let it be garbage-collected if no other references exist?
				# Because OTHER trees might have a reference to the node
				# Except that's not really supposed to be true anymore
				# Actually wait it can TOTALLY be true if you add it from the file system
				# That's why you can't store -- shit................................
				# CHILDREN also have to be stored on a PER-TREE BASIS
				# SHIT .....................................................
				# Only OWN NODE data can be stored in a file
				# NODE RELATIONS must be stored IN THE TREE ONLY
				# WEIRD ..............................
				# Ok that's a pending refactor then ....................
	_should_update = true


func remove_editor_node(ed_node: BehEditorNode):
	print("[BehEditor] (remove_editor_node) Remove (delete) ed_node %s" % ed_node)
	if ed_node == null:
		push_error("[BehEditor] (remove_editor_node) Wanted to remove a null BehEditorNode")
	
	# Remove the entry from _editor_node_map for this ed_node.
	var ed_beh = ed_node.beh
	if ed_beh == null:
		push_warning("BehEditorNode won't have entry in _editor_node_map due to null ed_node.beh")
	else:
		var id = ed_beh.try_get_stable_id()
		if id == null:
			push_warning("[BehEditor] (remove_editor_node) Couldn't get stable_id of ed_node %s to remove it from the _editor_node_map before deleting" % [
				ed_node.name])
		else:
			if !_editor_node_map.has(id):
				push_warning("[BehEditor] (remove_editor_node) _editor_node_map lacked key stable_id %s entry for ed_node %s" % [
					id, ed_node.name])
			else:
				_editor_node_map.erase(id)
	on_node_deselected(ed_node, true) # Try deselect before deleting (avoids a warning)
		
	# Also remove CONNECTIONS to or from the node prior to removing it.
	var conn_list = graph.get_connection_list()
	var conns_from = []
	var conns_to = []
	for conn in conn_list:
		if conn.from == ed_node.name:
			conns_from.push_back(conn)
		if conn.to == ed_node.name:
			conns_to.push_back(conn)
	for conn in conns_from:
		print("[BehEditor] (remove_editor_node) Removing %s -> %s" % [conn.from, conn.to])
		graph.disconnect_node(conn.from, conn.from_port, conn.to, conn.to_port)
	for conn in conns_to:
		print("[BehEditor] (remove_editor_node) Removing %s -> %s" % [conn.from, conn.to])
		graph.disconnect_node(conn.from, conn.from_port, conn.to, conn.to_port)
	
	# Remove the BehEditorNode from the graph and free it.
	graph.remove_child(ed_node)
	ed_node.queue_free()
	_should_update = true


func clear_editor_nodes():
	print("[BehEditor] Clearing editor nodes (unsubscribing first) and map cache for them.")
	unsubscribe_editor_node_signals()
	if len(_subscribed_editor_nodes) > 0:
		push_warning("[BehEditor] Still had %s editor node subscriptions after attempting " +
			"to unsubscribe from them.", len(_subscribed_editor_nodes))
		_subscribed_editor_nodes.clear()
	graph.clear_connections() # Clear connections, prevents errors when freeing GraphNodes
	for key in _editor_node_map.keys():
		var ed_node = _editor_node_map[key]
		remove_editor_node(ed_node)
	_editor_node_map.clear()


func on_node_selected(node: Node):
	print("[BehEditor] (on_node_selected) Node: %s" % node.name)
	var node_parent = node.get_parent()
	if node_parent == null: node_parent = "(null)"
	var node_name = node.name
	if node_parent != graph:
		push_error("[BehEditor] (on_node_selected) Got selected node for unknown graph; its parent is %s" % node_parent.name)
		return
	if _selected_nodes.has(node.name):
		push_error("[BehEditor] (on_node_selected) _selected_nodes ALREADY contained %s" % node.name)
		return
	_selected_nodes[node.name] = true
	_should_update = true


func on_node_deselected(node: Node, allow_not_selected: bool = false):
	print("[BehEditor] (on_node_deselected) Requested deselect node: %s" % node.name)
	var node_parent = node.get_parent()
	if node_parent == null: node_parent = "(null)"
	var node_name = node.name
	if node_parent != graph:
		push_error("[BehEditor] (on_node_deselected) Got selected node for unknown graph; its parent is %s" % node_parent.name)
		return
	if !_selected_nodes.has(node.name) && !allow_not_selected:
		push_error("[BehEditor] (on_node_deselected) _selected_nodes DID NOT contain %s" % node.name)
		return
	_selected_nodes.erase(node.name)
	_should_update = true


func on_copy_nodes_request(special_copy_buffer = null):
	print("[BehEditor] (on_copy_nodes_request) Got copy signal.")
	var use_buffer = _copy_nodes_buffer
	if special_copy_buffer != null:
		print("[BehEditor] (on_copy_nodes_request) Copy signal using special arg buffer instead of standard copy buffer.")
		use_buffer = special_copy_buffer
	use_buffer.clear()
	for sel_key_name in _selected_nodes.keys():
		var sel_node = graph.get_node_or_null(sel_key_name)
		if sel_node == null:
			push_error("[BehEditor] (on_copy_nodes_request) Did not find node %s to copy" % sel_key_name)
			continue
		var sel_node_as_ed_node = sel_node as BehEditorNode
		if sel_node_as_ed_node == null:
			push_error("[BehEditor] (on_copy_nodes_request) Node %s was not BehEditorNode" % sel_key_name)
			continue
		use_buffer.push_back(sel_node_as_ed_node)
	pass


func on_paste_nodes_request(special_copy_buffer = null):
	print("[BehEditor] (on_paste_nodes_request) Got paste signal.")
	var use_buffer = _copy_nodes_buffer
	if special_copy_buffer != null:
		print("[BehEditor] (on_copy_nodes_on_paste_nodes_requestrequest) Paste signal using special arg buffer instead of standard copy buffer.")
		use_buffer = special_copy_buffer
	# Track source obj -> duplicate obj so that we can reconstitute children connections
	# after the duplication process.
	var src_to_dup_map = {}
	for copied_ed_node in use_buffer:
		if copied_ed_node == null:
			push_error("[BehEditor] (on_paste_nodes_request) Had null copied node")
			continue
		# Duplication method: Create a clone of the BehNode and add it to active_tree.
		# A new editor node will automatically be created for it.
		var src_beh: BehNode = copied_ed_node.beh
		if src_beh == null:
			push_error("Can't copy null src_beh (ed node: %s)" % copied_ed_node)
			continue
		var dup_beh = src_beh.clone(false)
		var dup_pos = copied_ed_node.position_offset + Vector2(40, 40)
		print("[BehEditor] (on_paste_nodes_request) ORIG stable_id: %s" % src_beh.try_get_stable_id())
		print("[BehEditor] (on_paste_nodes_request) DUPE stable_id: %s" % dup_beh.try_get_stable_id())
		active_tree.add_node(dup_beh)
		# The newly created node won't have an editor offset until it is saved so that it gets a
		# stable ID! Instead, queue a position for the node.
		# This will be processed just saving BehNodes gives them paths in the update step.
		# e.g. active_tree.set_editor_offset(dup_beh, dup_pos) -> is NOT possible due to lack of stable_id
		_pending_node_positions[dup_beh] = dup_pos
		if src_beh != null:
			src_to_dup_map[src_beh] = dup_beh
	# Recreate children relationships.
	# We do this by removing the children of a dup_beh (which refer to src_behs) and
	# re-adding them IF they are present in our map of duplicated BehNodes.
	for src_beh in src_to_dup_map.keys():
		var dup_beh: BehNode = src_to_dup_map[src_beh]
		var children_to_remove = []
		var children_to_replace = []
		for src_child in dup_beh.get_children():
			if src_to_dup_map.has(src_child):
				children_to_replace.push_back(src_child)
			else:
				children_to_remove.push_back(src_child)
		for src_child in children_to_remove:
			# # # We set ignore_orphan_update to true because pasting will never cause orphaning.
			# Actually, setting to FALSE to NOT ignore the update to see if adding things as orphans
			# allows them to be TRACKED, which allows them to SAVE and get stable_ids; then when they
			# are added later we should be able to remove them as orphans when they are added,
			# properly.
			# Wait, no, we DON'T want them to become orphans
			active_tree.try_remove_parent_child_relationship(dup_beh, src_child, true)
		for src_child in children_to_replace:
			active_tree.try_remove_parent_child_relationship(dup_beh, src_child, true)
		for src_child in children_to_replace:
			# Instead of immediately adding dup_child as a child relationship,
			# push it to _pending_parent_child_relations, so that the new children
			# are tracked directly in the active_tree.orphans array which will get them
			# a stable_id (via resource_path) when the tree is saved.
			var dup_child = src_to_dup_map[src_child]
			_pending_parent_child_relations.push_back([dup_beh, dup_child])
#			if !dup_beh.try_add_child(dup_child):
#				push_error("[BehEditor] (on_paste_nodes_request) Failed to add duplicated child %s to parent %s" % [
#					dup_child, dup_beh])
#			else:
#				pass # No issue.
	_should_update = true # Will save, assign paths, resubscribe to ed_node signals, etc


func on_duplicate_nodes_request():
	"""Invoked via context menu only. Perform a copy & paste using a special duplication buffer.
	Using the special buffer prevents the standard copy buffer from being replaced when calling
	on_copy_nodes_request"""
	var special_buffer = []
	on_copy_nodes_request(special_buffer)
	on_paste_nodes_request(special_buffer)


func on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int):
	if active_tree == null:
		print("[BehEditor] (Connection Request) Ignoring on_connection_request as active_tree is null.")
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
	else:
		print("[BehEditor] (Connection Request) FAILED to add a child relationship (may not be an error!): %s -> %s" % [
			ed_from.beh, ed_to.beh])
	_should_update = true
	pass


func on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int):
	"""Called by the disconnection_request signal from the graph."""
	print("[BehEditor] (on_disconnection_request) Got disconnect request for conn from %s -> to %s" % [
		from_node, to_node])
	graph.disconnect_node(from_node, from_port, to_node, to_port)
	# Remember to also remove the parent-child relationship, otherwise the connection will be
	# auto-added back in the next update.
	var node_parent = try_get_node_from_name(from_node)
	var node_child = try_get_node_from_name(to_node)
	if node_parent == null || node_child == null:
		push_warning("[BehEditor] (on_disconnection_request) Skipping; parent or child was null. Parent: %s -> Child: %s" % [
			node_parent, node_child])
	else:
		var beh_parent = node_parent.beh
		var beh_child = node_child.beh
		if beh_parent == null || beh_child == null:
			push_warning("[BehEditor] (on_disconnection_request) Skipping; parent or child beh was null. Parent beh: %s -> Child beh: %s" % [
				beh_parent, beh_child])
		# Remove the parent->child relationship.
		if !active_tree.try_remove_parent_child_relationship(beh_parent, beh_child):
			push_warning("[BehEditor] (on_disconnection_request) Failed to remove parent->child relationship. Parent beh: %s -> Child beh: %s" % [
				beh_parent, beh_child])
	# Refresh.
	_should_update = true


func subscribe_editor_node_signals():
	"""OK to call multiple times when editor nodes are created; tracks subscriptions and avoids
	resubscribing."""
	for id in _editor_node_map.keys():
		var is_subscribed = _subscribed_editor_nodes.has(id)
		if !is_subscribed:
			var ed_node: BehEditorNode = _editor_node_map[id]
			### TEST FIX: Getting weird "missing function '' in BehEditor" error when moving ed_nodes
#			var callable = func(): on_editor_node_pos_changed(id)
			var callable = on_editor_node_pos_changed
			
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


#func on_editor_node_pos_changed(node_id: StringName):
#	if !_editor_node_map.has(node_id):
#		push_warning("[BehEditor] Got on_editor_node_dragged for unknown editor_node id %s" % node_id)
#		return
#	var ed_node: BehEditorNode = _editor_node_map[node_id]
#	if ed_node.beh == null:
#		push_error("[BehEditor] Node ID %s is missing a backing NodeBeh" % node_id)
#		return
#	# Update the position!
#	active_tree.set_editor_offset(ed_node.beh, ed_node.position_offset)
##	print("[BehEditor] Successfully set a tree's NodeBeh editor offset via ed_node.position_offset! Value: %s" % [
##		active_tree.get_editor_offset(ed_node.beh)])
func on_editor_node_pos_changed():
	# Argumentless implementation: Update all editor nodes
	for ed_node in get_editor_nodes():
		var ed_node_pos = ed_node.position_offset
		if ed_node.beh != null:
			active_tree.set_editor_offset(ed_node.beh, ed_node_pos)
	pass


func get_editor_nodes() -> Array[BehEditorNode]:
	var arr: Array[BehEditorNode] = []
	for child in graph.get_children():
		var child_ed_node = child as BehEditorNode
		if child_ed_node == null:
			continue
		arr.push_back(child_ed_node)
	return arr


func on_graph_end_node_move():
	_should_update = true # Resave so that we capture new node positions.


# === View Management ===


func get_view_center_offset() -> Vector2:
	return graph.size / 2



