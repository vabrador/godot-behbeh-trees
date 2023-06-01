@tool
class_name BehTreeEditor
extends Control


static func dprintd(s: String):
#	print(s) # Enable when debugging.
	pass


# === Contents ===
# - VND Var Node Dependencies
# - VVD Var Volatile Data
# - VMD Var Menu Entry Dictionaries
# - GDE Godot Events
# - PCM Plugin Comms
# - CTX Generic Context Menu Request Handler
# - GCM Graph Context Menu
# - NCM Node Context Menu
# - NOP Node Operations
# - UIS UI Signals
# - NSE Node Selection
# - FEA Formal Editor Action Methods
# - UME Utility Methods
# - VMN View Management


# === VND Var Node Dependencies === 


# Buttons
@onready var graph: BehEditorGraphEdit = $HCtn/GraphEdit
# Action Panel Controls
@onready var btn_reset_view_root: Button = $HCtn/SideCtnMargins/SideCtn/ViewActionsCtn/BtnRecenterViewOnRoot
@onready var btn_open_beh: Button = $HCtn/SideCtnMargins/SideCtn/FileActionsCtn/BtnFileOpen
# Context Menu(s)
## GRAPH ctx menu, for e.g. adding new nodes.
@onready var ctx_menu_graph: PopupPanel = $ContextAddNodePopupPanel
@onready var ctx_menu_graph_ctn: VBoxContainer = $ContextAddNodePopupPanel/MarginCtn/VBoxCtn
## NODE ctx menu, for operations on selected node(s).
@onready var ctx_menu_node: PopupMenu = $ContextPopupMenu
# Side Container
@onready var side_ctn: VBoxContainer = $HCtn/SideCtnMargins/SideCtn
# Debug labels
@onready var dbg_active_node_label: Label = $HCtn/SideCtnMargins/SideCtn/DbgActiveNodeLabel
@onready var dbg_label_root_id: Label = $HCtn/SideCtnMargins/SideCtn/DbgInfoCtn/DbgLabelRootId
@onready var dbg_label_orphan_ct: Label = $HCtn/SideCtnMargins/SideCtn/DbgInfoCtn/DbgLabelOrphanCount
@onready var dbg_label_beh_ct: Label = $HCtn/SideCtnMargins/SideCtn/DbgInfoCtn/DbgLabelBehCt
@onready var dbg_label_generic: Label = $HCtn/SideCtnMargins/SideCtn/DbgInfoCtn/DbgLabelGeneric


# === VVD Var Volatile Data === 


var editor_plugin: EditorPlugin = null
var undo_redo: EditorUndoRedoManager = null # Set by behbeh_plugin on enter_tree.
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
var _editor_node_map: Dictionary = {} # maps BehNode stable_id -> BehEditorNode.
var _subscribed_active_tree: BehTree = null
var _subscribed_editor_nodes: Dictionary = {} # maps beh stable_id -> [func_name, Callable]
var _selected_nodes: Dictionary = {} # maps BehEditorNode name -> bool (true) -- acts like a Set
var _copy_nodes_buffer: Array[BehEditorNode] = []
var _ctx_menu_node_id_pressed_subscribed = false
var _dict_history_storage: Dictionary = {} # Storage to prevent garbage-collection of objects needed for Undo history.
# Undo-buffer-like history that sadly is a small memory leak over many operations without looking
# away from a single Beh editor view.
# Remembers where a node was so that if you undo a deletion, the node reappears back where it was.
# Could possibly change this to be a similar hint stored in the BehNode itself to remove the leak.
var _hint_last_editor_positions: Dictionary = {}
var _del_hint_last_children: Dictionary = {}
var _del_hint_last_parent: Dictionary = {}
var _graph_subscribed := false
var _pending_node_positions = {} # Used to place nodes that don't yet have stable_ids from saving.
var _pending_parent_child_relations = [] # Used to parent nodes that don't yet have stable_ids from saving.
var _pending_set_selected_nodes = null
var _pending_inspect_node = null # Update-consumed BehNode to inspect.
var _pending_scroll_offset = null
var _pending_zoom = null
var _created_ed_node_ct = null
var _delay_pending_scroll_offset = 0


# === VMD Var Menu Entry Dictionaries ===


enum ContextMenuType { GraphCtxMenu, NodeCtxMenu }
var _ctx_menu_node_entries: Array[Dictionary] = [
	{ "id": 0,	"name": "Node Context Menu [...NODE_DEBUG_NAME]",	"action": null, },
	{ "id": 10,	"name": "Copy", 				"action": "on_copy_nodes_request", },
	{ "id": 15,	"name": "Paste",				"action": "on_paste_nodes_request", },
	{ "id": 20,	"name": "Delete",				"action": "on_delete_nodes_request", },
	{ "id": 30,	"name": "Duplicate",			"action": "on_duplicate_nodes_request", },
	{ "id": 50,	"name": "Clear Copy Buffer",	"action": "on_clear_copy_buffer_request", },
]
var _ctx_menu_node_separators: Array[int] = [ ]


# === GDE Godot Events ===


# Called when the node enters the scene tree for the first time.
func _ready():
	subscribe_panel_btn_signals()
	subscribe_graph_edit_signals()
	subscribe_editor_node_signals()
	_is_ready = true
	print("ready called")


func _enter_tree():
#	print("enter tree called")
#	print("[BehEditor] (_enter_tree) Called. Active_tree? %s" % self.active_tree)
	# Try to prevent frame-delay lag by creating editor nodes as soon as we enter the tree.
	if self.active_tree != null:
		update_create_destroy_editor_nodes()


func _exit_tree():
	clear_editor_nodes()
	unsubscribe_graph_edit_signals()
	_is_ready = false


func _draw():
	if !_is_ready: return
	_should_update = true


func _process(dt):
	var should_process = Engine.is_editor_hint() && _should_update
	if !should_process: return
	_should_update = false
	dprintd("[BehEditor] _process called and had _should_update.")
	
	# Nothing further to update if there is no active tree.
	if active_tree == null:
		return
	
	dprintd("[BehEditor] Updating.")
	
	# Update subscriptions.
	# -------------
	#
	# Ensure we're subscribed to the right active_tree.
	if _subscribed_active_tree != active_tree:
		if _subscribed_active_tree != null:
			_subscribed_active_tree.disconnect("tree_changed", on_tree_changed)
		active_tree.tree_changed.connect(on_tree_changed)
		_subscribed_active_tree = active_tree
	
	# Confirm the active_tree is initialized.
	active_tree.confirm_initialized(true)
	
	# Save the active_tree.
	# ---------------------
	#
	# This needs to happen prior to updating BehNodeEditors, because the act of saving
	# with the subresource_paths argument creates resource_paths for any newly-added
	# subresources entries in the tree.
	dprintd("[BehEditor] (Update) Saving active tree.")
	save_active_tree()
	
	# Validate the tree.
	# ------------------
	#
	# And save again if validation changed the tree.
	dprintd("[BehEditor] (Update) Doing validation...")
	if active_tree.validate_roots_and_orphans():
		save_active_tree()
	if active_tree.validate_single_parents():
		save_active_tree()
	dprintd("[BehEditor] (Update) Done validating.")
	
	dprintd("[BehEditor] (Update) Step: Process pending editor positions.")
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
	
	# Create & Destroy Editor Nodes to match the Active Tree
	# ------------------------------------------------------
	#
	# Ensure that every node in the active_tree has an editor node.
	dprintd("[BehEditor] (Update) Step: Create/destroy editor nodes.")
	update_create_destroy_editor_nodes()
	
	
	# Update editor node subscriptions.
	# ---------------------------------
	#
	# This has to occur AFTER we may have added any new GraphNodes, but BEFORE
	# we handle any selection logic that may fire signals.
	dprintd("[BehEditor] (Update) Step: subscribe_editor_node_signals.")
	subscribe_editor_node_signals()
	
	# Update pending scroll offset.
	# -----------------------------
	#
	# We don't set the scroll offset until after any pending node inspection is resolved.
#	dprintd("Pending scroll offset: %s" % _pending_scroll_offset)
#	dprintd("graph.scroll_offset BEFORE: %s" % graph.scroll_offset)
#	print("graph.zoom BEFORE: %s" % graph.zoom)
	dprintd("[BehEditor] (Update) Step: Update pending scroll offset.")
	var has_pending_view_info = _pending_zoom != null || _pending_scroll_offset != null
	var can_set_view_info = true
	# Wait until after editor nodes have stabilized to consume view info.
	if _created_ed_node_ct > 0: can_set_view_info = false
	if len(_pending_node_positions) > 0: can_set_view_info = false
	if _delay_pending_scroll_offset > 0: # Delay used when switch active_tree selection.
		_delay_pending_scroll_offset -= 1
		can_set_view_info = false
	# Consume pending view info.
	if has_pending_view_info && can_set_view_info:
#		print("CONSUMING PENDING VIEW INFO")
#		graph.scroll_offset = _pending_scroll_offset
		if _pending_zoom != null:
			graph.zoom = _pending_zoom
			_pending_zoom = null
		if _pending_scroll_offset != null:
			graph.scroll_offset = _pending_scroll_offset
			_pending_scroll_offset = null
#	dprintd("graph.scroll_offset AFTER: %s" % graph.scroll_offset)
#	dprintd("graph.zoom AFTER: %s" % graph.zoom)
	
	# Update pending selected nodes.
	# ------------------------------
	#
	# If this update created new editor nodes, we have to update again in case
	# there are _pending_set_selected_nodes.
	dprintd("[BehEditor] (Update) Step: Update pending selected nodes.")
	var can_set_pending_selection = true
	if _created_ed_node_ct > 0:
		# Can't set pending selection if we just created editor nodes because we
		# haven't subscribed to callbacks.
		can_set_pending_selection = false
	if _pending_inspect_node != null:
		# Can't set pending selection if we're about to cause a refresh of the
		# window due to selecting a node.
		can_set_pending_selection = false
	# If we want to set the selection but we can't, make sure we are getting another
	# update.
	if _pending_set_selected_nodes != null && !can_set_pending_selection:
		dprintd("[BehEditor] (BehEditorNode Sync) _pending_set_selected_nodes exists and we created GraphNodes this update. Requesting another _process occur after this one.")
		_should_update = true
	# Finally, consume a pending selection if no other action is blocking it.
	if _pending_set_selected_nodes != null && can_set_pending_selection:
		dprintd("[BehEditor] (_pending_set_selected_nodes Sync) Consuming; setting selection to %s nodes from pending buffer." % len(_pending_set_selected_nodes))
		set_selected_nodes(_pending_set_selected_nodes)
		_pending_set_selected_nodes = null
	
	# Update pending inspect node.
	# ----------------------------
	#
	dprintd("[BehEditor] (Update) Step: Update pending inspect node.")
	if _pending_inspect_node != null:
		inspect_node(_pending_inspect_node) # expects BehNode
#		print("CALLED inspect_node !!")
		_pending_inspect_node = null
	
	# Validate selected nodes
	# -----------------------
	dprintd("[BehEditor] (Update) Step: Validating selected nodes.")
	for sel_key_name in _selected_nodes.keys():
#		var sel_node = _selected_nodes[sel_key_name]
		var sel_node = graph.get_node_or_null(sel_key_name)
		if sel_node == null:
			push_warning("[BehEditor] (Validate Selected Nodes) Removing a null node from selection (deleted?)")
			_selected_nodes.erase(sel_key_name)
	
	# Sort roots visually for the active_tree.
	# ----------------------------------------
	#
	dprintd("[BehEditor] (Update) Step: Sorting active_tree roots visually.")
	var did_sort_roots = false
	var allow_root_sort = true
	var root_and_positions_arr = []
	for root in active_tree.roots:
		var key = root.try_get_stable_id()
		if key == null:
			push_warning("[BehEditor] (Update - Sort Roots) Root %s lacked stable id, skipping sorting." % root)
			allow_root_sort = false
			break
		if !_editor_node_map.has(key):
			push_warning("[BehEditor] (Update - Sort Roots) Root %s lacked editor_node_map entry for key %s, aborting." % [
				root, key])
			allow_root_sort = false
			break
		if !active_tree.has_editor_offset(root):
			push_warning("[BehEditor] (Update - Sort Roots) Root %s lacked editor offset, aborting." % [
				root])
			allow_root_sort = false
			break
		var root_pos = active_tree.get_editor_offset(root)
		root_and_positions_arr.push_back([root, root_pos])
	if allow_root_sort:
		# Sort the roots based on their positions
		root_and_positions_arr.sort_custom(func(a, b): 
			# Returns true if B should come after A.
			var a_pos = a[1]
			var b_pos = b[1]
			if a_pos.y < b_pos.y: return true # A higher than B: 	A -> B
			if a_pos.y > b_pos.y: return false # A lower than B: 	B -> A
			if a_pos.x < b_pos.x: return true # A left of B: 		A -> B
			return false #											B -> A
		)
		# Use the sorted array to rearrange the tree roots.
		# This assumes active_tree.roots is mutable and not a copy.
		for c in range(len(root_and_positions_arr)):
			var sorted_child = root_and_positions_arr[c][0]
			var og_child = active_tree.roots[c]
			if og_child != sorted_child:
				did_sort_roots = true # A change is being made; will need to re-save and update.
			active_tree.roots[c] = sorted_child # We just write the refs straight to the array.
	if did_sort_roots:
		_should_update = true
		dprintd("[BehEditor] Tree's roots are now:")
		for r in range(len(active_tree.roots)):
			var root = active_tree.roots[r]
			dprintd("[BehEditor] %s - %s" % [r, root])
	# Done sorting active_tree roots.
	
	# Sort children visually for all behaviors.
	# -----------------------------------------
	#
	dprintd("[BehEditor] (Update) Step: Sorting children visually.")
	var children_resorted_ct = 0
	for stab_id in _editor_node_map.keys():
		var ed_node = _editor_node_map[stab_id]
		var beh: BehNode = ed_node.beh
		if beh == null:
			push_warning("[BehEditor] (Sort Children Visually) Missing BehNode in ed_node %s while iterating. Skipping this ed_node." % [
				ed_node])
		var children = beh.get_children() # This array MAY BE MUTATED
		var did_sort = false
		if len(children) > 1:
			var children_and_positions_arr = []
			var skip_sort = false
			for child in children:
				if !child.has_stable_id():
					push_warning("[BehEditor] (Sort Children Visually) Beh %s child %s lacked stable_id; can't sort its children." % [
						beh, child])
					skip_sort = true
					break
				var child_ed_pos = active_tree.get_editor_offset_or(child, Vector2.ZERO)
				children_and_positions_arr.push_back([child, child_ed_pos])
			if skip_sort:
				continue
			# Sort the children based on their positions
			children_and_positions_arr.sort_custom(func(a, b): 
				# Returns true if B should come after A.
				var a_pos = a[1]
				var b_pos = b[1]
				if a_pos.y < b_pos.y: return true # A higher than B: 	A -> B
				if a_pos.y > b_pos.y: return false # A lower than B: 	B -> A
				if a_pos.x < b_pos.x: return true # A left of B: 		A -> B
				return false #											B -> A
			)
			# Finally, use the sorted array to rearrange the node's children.
			# This assumes the get_children() array can be modified and ISN'T
			# a copy!
			for c in range(len(children_and_positions_arr)):
				var sorted_child = children_and_positions_arr[c][0]
				var og_child = children[c]
				if og_child != sorted_child:
					did_sort = true # A change is being made; will need to re-save and update.
				children[c] = sorted_child # We just write the refs straight to the array.
		if did_sort:
			children_resorted_ct += 1
			_should_update = true
			# DBG
			dprintd("[BehEditor] Behavior's children are now:")
			for c in range(len(children)):
				var child = children[c]
				dprintd("[BehEditor] %s - %s" % [c, child])
	if children_resorted_ct > 0:
		dprintd("[BehEditor] (Sort Children Visually) Sorted %s BehNode's children." % children_resorted_ct)
	# End visual children sort for every node.
	
	# Update debug info.
	# ------------------
	#
	dprintd("[BehEditor] (Update) Step: Updating debug info.")
#	dbg_label_root_id.text = "Root Tree Count: %s" % len(active_tree.roots)
#	dbg_label_orphan_ct.text = "Orphan Tree Count: %s" % len(active_tree.orphans)
#	dbg_label_beh_ct.text = "Total Beh Count: %s" % len(active_tree.get_all_nodes())
	dbg_label_generic.text = (
		"Root Tree Count: %s" +
		"\nOrphan Tree Count: %s" +
		"\nTotal Beh Count: %s" +
		"\nSelection Count: %s" +
		"\nNode Meta Size: %s"
	) % [
		len(active_tree.roots),
		len(active_tree.orphans),
		len(active_tree.get_all_nodes()),
		len(_selected_nodes),
		"(tree null)" if active_tree == null else str(len(active_tree.node_meta.keys()))
	]
	
	pass


func update_create_destroy_editor_nodes():
	"""Called on enter_tree if there's already an active_tree, and called on process to ensure
	editor nodes exist for the tree and unnecessary editor nodes do NOT exist.
	Every call clears _created_ed_node_ct, which can be checked to see if the latest update
	created new editor nodes, which may require certain operations to wait until the next
	update."""
	_created_ed_node_ct = 0
	if active_tree.is_empty(): pass # (Nothing to render in this case)
	else:
		for beh in active_tree.get_all_nodes():
			var id = beh.try_get_stable_id()
			if id == null:
				dprintd("[BehEditor] (BehEditorNode Sync) Skipping missing stab_id for node %s" % [
					beh.get_instance_id()])
			if id != null && !(id is StringName):
				push_error("Expected StringName as NodeBeh stable_id for node %s" % beh.get_instance_id())
			if id != null && id is StringName && !_editor_node_map.has(id):
				dprintd("[BehEditor] (BehEditorNode Sync) Creating new BehEditorNode for node %s" % id)
				create_ed_node_and_update_map(beh, id)
				_created_ed_node_ct += 1
			# Normal sync for each BehEditorNode.
			if id != null && id is StringName && _editor_node_map.has(id):
				var ed_node: BehEditorNode = _editor_node_map[id]
				var valid_beh = ed_node.validate_beh()
				if !valid_beh:
					push_warning("[BehEditor] Found INVALID beh in ed_node %s" % ed_node)
					continue
				if ed_node.beh != beh:
					# This can occur if we've changed from one tree to another where nodes
					# have matching stable_ids. For example, a tree has been duplicated, and we
					# move from one selected tree to the other.
					#
					# In this case, we need to wait for the editor nodes to clear and be re-built. (?)
					#
					# So just break.
					dprintd("[BehEditor] Detected stable_id mismatch, most likely from a active_tree moving from one active selection to a duplicate tree selection. Aborting sync update for now.")
					break
#				if !valid_beh:
#					ed_node.set_title_color(BehEditorNode.RED)
				# Update orphan status for editor nodes.
				# Also update other visual state.
				if valid_beh:
					dprintd("[BehEditor] (BehEditorNode Sync) Updating editor node %s info for its beh %s" % [ed_node, ed_node.beh])
					ed_node.beh._editor_ref = self
					ed_node.is_orphan = active_tree.get_is_orphan(ed_node.beh)
					var parent_beh = active_tree.get_parent_node(ed_node.beh)
					var is_root = active_tree.get_is_root(ed_node.beh)
					var child_order_matters = (parent_beh != null && parent_beh.get_does_child_order_matter()) \
						|| is_root
					ed_node.call_order_matters = child_order_matters
					ed_node.is_root = is_root
					ed_node.child_index = active_tree.get_child_index(ed_node.beh, ed_node.is_root)
				# Children connections.
				for child_beh in ed_node.beh.get_children():
					var child_id = child_beh.try_get_stable_id()
					dprintd("[BehEditor] (BehEditorNode Sync Children) Considering parent %s, child %s" % [
						id, child_id])
					if child_id == null:
						push_error("[BehEditor] (BehEditorNode Sync Children) Failed to get child stable ID.")
						continue
					if id == child_id:
						push_error("[BehEditor] (BehEditorNodeSync Children) Unexpected: child_id and parent id match: %s" % [
							id])
						continue
					if !_editor_node_map.has(child_id):
						dprintd("[BehEditor] (BehEditorNode Sync Children) Creating new BehEditorNode for node %s" % child_id)
						create_ed_node_and_update_map(child_beh, child_id)
					var child_ed_node: BehEditorNode = _editor_node_map[child_id]
					dprintd("[BehEditor] (BehEditorNode Sync Children) Calling graph.connect_node")
					var conn_err = graph.connect_node(ed_node.name, 0, child_ed_node.name, 0)
					if conn_err:
						push_error("[BehEditor] (BehEditorNode Sync Children) Error connecting %s -> %s: %s" % [
							ed_node.name, child_ed_node.name, conn_err])
					dprintd("[BehEditor] (BehEditorNode Sync Children) DONE calling graph.connect_node")
#					else:
#						dprintd("[BehEditor] (BehEditorNode Sync Children) Connected")
				# Update the editor node view. TODO: Commented-out; was investigating
				# issue where connection lines connect too far left (due to inner Labeling changing?)
#				ed_node.update_view()
	# Continued-- remove editor nodes if need be.
	# Ensure all editor nodes correspond to actual behaviors in the tree, otherwise remove them.
	var ed_nodes_to_remove: Array[BehEditorNode] = []
	for ed_node in get_editor_nodes():
		var valid_beh = ed_node.validate_beh()
		if !valid_beh || !active_tree.contains(ed_node.beh):
			dprintd("[BehEditor] (BehEditorNode Sync) Deleting editor node data for a non-tree behavior. Ed_node is %s" % ed_node)
			if ed_node.beh != null:
				dprintd("[BehEditor] (BehEditorNode Sync) (non-tree behavior was: %s)" % ed_node.beh)
			ed_nodes_to_remove.push_back(ed_node)
	var removed_ct = 0
	for del_ed_node in ed_nodes_to_remove:
		remove_editor_node(del_ed_node)
		removed_ct += 1
	if removed_ct > 0:
		dprintd("[BehEditor] (BehEditorNode Sync) Removed %s editor nodes for non-tree behaviors." % removed_ct)
	
	# Ensure existing graph connections are for actual parent->child connections.
	# { from_port: 0, from: "GraphNode name 0", to_port: 1, to: "GraphNode name 1" }
	var remove_conns = []
	var removed_conn_ct = 0
	for conn_info in graph.get_connection_list():
		var ed_from = try_get_node_from_name(conn_info["from"])
		var ed_to = try_get_node_from_name(conn_info["to"])
		var beh_par = ed_from.beh
		var beh_child = ed_to.beh
		if !active_tree.has_parent_child_relation(beh_par, beh_child):
			remove_conns.push_back(conn_info)
	for rc in remove_conns:
		graph.disconnect_node(rc["from"], rc["from_port"], rc["to"], rc["to_port"])
		removed_conn_ct += 1
	if removed_conn_ct > 0:
		dprintd("[BehEditor] (BehEditorNode Sync) Removed %s connections for non-existent parent-child relationships." % removed_ct)
	
	# Go ahead and mark a required new update if we added any new editor nodes.
	# Many operations require editor nodes to be stabilized.
	if _created_ed_node_ct > 0:
		_should_update = true
	


func on_tree_changed():
	"""Update visual representation if the BehTree reports that it has changed in some way."""
	dprintd("[BehEditor] Got signal from tree: tree_changed. Will update next frame.")
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
		dprintd("[BehEditor] (BehEditorNode Sync) active_tree HAS offset for %s: %s" % [
			id, known_offset])
		new_ed_node.position_offset = active_tree.get_editor_offset(beh)
	else: # Set a new editor position
		dprintd("[BehEditor] (BehEditorNode Sync) Generating new offset for %s" % id) 
		new_ed_node.position_offset = Vector2(100, 100) # temporary value for now
		active_tree.set_editor_offset(beh, new_ed_node.position_offset)
	graph.add_child(new_ed_node)
	_editor_node_map[id] = new_ed_node
	dprintd("[BehEditor] (create_ed_node_and_update_map) new_ed_node name is %s, pos is %s, and its parent is %s" % [
		new_ed_node.name, new_ed_node.position_offset, new_ed_node.get_parent()])
	_should_update = true


func save_active_tree():
	if !Engine.is_editor_hint():
		# This is important because we look for .tres extensions for saving and at runtime those
		# resources are optimized to .res binary extensions or otherwise messed-with
		dprintd("[BehEditor] (save_active_tree) Skipping save, not in editor.")
	dprintd("[BehEditor] (save_active_tree) Saving...")
	if active_tree != null && active_tree.resource_path != "":
#		dprintd("[BehEditor] Saving active_tree with FLAG_REPLACE_SUBRESOURCE_PATHS...")
		dprintd("[BehEditor] (save_active_tree) active_tree resource_name is %s" % active_tree.resource_name)
		dprintd("[BehEditor] (save_active_tree) active_tree resource_path is %s" % active_tree.resource_path)
		
		# Try to fix subtree saving. Can we save the resource WITHOUT the subresource paths flag?
		#
		# Get the path ending in .tres. This is the path to the base tree resource.
		var attempt_normal_save = true
		var path = active_tree.resource_path
		var idx_of_tres_extension = path.find(".tres")
		var idx_of_scene_extension = path.find(".tscn")
		var base_tree_path = null
		var is_saved_within_scene = false
		if idx_of_tres_extension == -1:
			dprintd("[BehEditor] (save_active_tree) Base tree must be inside a scene node; Failed to find .tres extension in active_tree resource_path: %s -- will attempt normal save." % active_tree.resource_path)
			# Hope everything just works and try to save normally...
			# This case definitely occurs when a tree is not defined on-disk and is attached to a
			# scene instead
			# Could detect this by finding .tscn but what do you do when
			# your resource is a nested tree whose supertree is in a scene?
			# 
			# Might have to parse the resource format MORE to see if it's the FIRST
			# tree resource (.tres OR .tscn::Resource_[\w]+$ == base tree?)
		else:
			base_tree_path = path.substr(0, idx_of_tres_extension + 5)
			if !(base_tree_path.ends_with(".tres")):
				push_error("[BehEditor] (save_active_tree) Failed to get base tree path ending in .tres: %s" % base_tree_path)
				# Will attempt a normal save.
			if base_tree_path == active_tree.resource_path:
				# THIS active_tree is already the base tree on disk.
				# Will just attempt a normal save.
				pass
			else:
				# THIS active_tree is a CHILD tree of the base tree. Attempt a
				# different save.
				attempt_normal_save = false
				# Try to save the base tree instead. Load the base tree.
				var base_tree = ResourceLoader.load(base_tree_path)
				if base_tree == null:
					push_error("[BehEditor] (save_active_tree) Failed to perform special save of child tree by saving base tree. Failed to load base_tree from path: %s" % base_tree_path)
				else:
					# Got base_tree. Save it instead.
					dprintd("[BehEditor] (save_active_tree) Attempting normal save of BASE tree at path %s, detected from child tree path %s." % [base_tree_path, active_tree.resource_path])
					var error = ResourceSaver.save(base_tree, "", ResourceSaver.FLAG_REPLACE_SUBRESOURCE_PATHS)
					if error: push_error("[BehEditor] (save_active_tree) Error saving base tree %s from base_tree_path %s: %s" % [base_tree, base_tree_path, error])
		
		if attempt_normal_save && idx_of_scene_extension != -1:
			# The tree (base or otherwise) is part of a scene.
			# We've modified the way stable_id's work and the user should always manually save
			# any changes to a scene, so experimentally, let's just skip saving.
			dprintd("[BehEditor] (save_active_tree) Skipping auto-save because the tree path %s looks like it's part of a scene." % [
				path])
			is_saved_within_scene = true
			attempt_normal_save = false
			
		# Normal save process. Only known to work for base (non-nested) trees.
		# Nested trees occur when a Subtree node is given a tree via "New BehTree" -- the tree only
		# lives within a (base) BehTree -> BehNode -> BehTree reference chain.
		if attempt_normal_save:
			dprintd("[BehEditor] (save_active_tree) Attempting normal save of active_tree.")
			var error = ResourceSaver.save(active_tree, "",
				ResourceSaver.FLAG_REPLACE_SUBRESOURCE_PATHS
			)
			if error: push_error("[BehEditor] (save_active_tree) Error saving active_tree %s (path %s): %s" % [active_tree, active_tree.resource_path, error])
	#		else: dprintd("[BehEditor] Saved active_tree.")
		
		# Scan nodes to ensure they have resource paths... but not if we're saved in a scene
		if is_saved_within_scene:
			dprintd("[BehEditor] (save_active_tree) Skipping child BehNode scan for resource_paths due to tree being part of a scene.")
		else: # !is_saved_within_scene
			var nodes_ct = 0
			var nodes_lacking_resource_path_ct = 0
	#		var child_save_ct = 0
			for child in active_tree.get_all_nodes():
				if child.resource_path == "":
					push_warning(("[BehEditor] (save_active_tree) Warning: BehNode (%s) lacks resource_path. " + \
					".") % [
						child.get_instance_id()])
					nodes_lacking_resource_path_ct += 1
				nodes_ct += 1
	#			if error: push_error("[BehEditor] (Save) Trying to save child with path: %s" % child.resource_path)
	#			error = ResourceSaver.save(child, child.resource_path, ResourceSaver.FLAG_REPLACE_SUBRESOURCE_PATHS)
	#			if error: push_error("[BehEditor] (Save) Error saving child %s: %s" % [child, error])
	#			else: child_save_ct += 1
			if nodes_lacking_resource_path_ct == 0:
				dprintd("[BehEditor] (save_active_tree) Saved %s nodes." % nodes_ct)
				pass
#		if nodes_ct == child_save_ct:
#			dprintd("[BehEditor] (Save) Success. All %s children were saved." % child_save_ct)
#		else:
#			push_warning("[BehEditor] (Save) Node ct was %s but only saved %s children." % [nodes_ct, child_save_ct])
#	dprintd("[BehEditor] (Save) Finished saving.")
	if active_tree == null:
		push_warning("[BehEditor] (save_active_tree) Skipping, as active_tree is null.")
	if active_tree != null && active_tree.resource_path == null:
		push_warning("[BehEditor] (save_active_tree) Skipping, active_tree exists but lacks a resource_path.")
	pass


# === PCM Plugin Comms ===


func notify_edit_target(target: Variant):
	"""Called by the Plugin Loader when the plugin is asked to edit a new object."""
	dprintd("[BehEditor] (notify_edit_target) Called with target (null if blank): %s" % target)
	var is_new_tree_target = target == null || target is BehTree
	if is_new_tree_target && active_tree != null: # Changing/clearing from an existing target
		dprintd("[BehEditor] (notify_edit_target) Target is changing, had a target already (possibly save pending changes here)")
		# Save the current active_tree before moving to the new tree target.
		dprintd("[BehEditor] (notify_edit_target) active_tree is changing. Saving current tree before changing the target in case the new target is a newly-created inner tree that needs a resource path to be edited.")
		save_active_tree()
		# Clear any _pending state that will be invalid in the new tree view.
		clear_tree_dependent_pending_state()
	var og_active_tree = self.active_tree
	if is_new_tree_target:
		active_tree = target as BehTree
		active_node = null # Clear selected node.
		if active_tree != null:
			dprintd("[BehEditor] (notify_edit_target) Just set edit target to active_tree %s" % active_tree)
		else:
			dprintd("[BehEditor] (notify_edit_target) CLEARING tree target. Removing old edit nodes & graph subscriptions")
			clear_editor_nodes()
			unsubscribe_graph_edit_signals()
	if self.active_tree != null:
		# If we have a valid active tree, make sure we are subscribed to graph edit signals.
		unsubscribe_graph_edit_signals()
		subscribe_graph_edit_signals()
	var is_changed_tree_target = target is BehTree && target != og_active_tree
	if is_changed_tree_target && self.active_tree != null:
		# Reset the view offset to center on the first root if there is one.
		if self.active_tree.has_roots():
			var first_root = self.active_tree.roots[0]
			if self.active_tree.has_editor_offset(first_root):
				var first_root_offset = self.active_tree.get_editor_offset(first_root)
				
				_pending_scroll_offset = first_root_offset \
					+ Vector2.LEFT * graph.size.x * 0.2 \
					+ Vector2.UP * graph.size.y * 0.50
#					+ Vector2.ZERO
				_pending_zoom = 1.
				_delay_pending_scroll_offset = 1
				_should_update = true
	
			
	var is_node_target = target is BehNode
	if is_node_target && !expects_node_target():
		push_error("[BehEditor] (notify_edit_target) Unexpected node target! Target passed to this func should have been null")
	if is_node_target && expects_node_target():
		# Tree stays the same
		# active_node changes instead
		active_node = target as BehNode
		receive_node_target() # Perform actions based on the received node target we expected.
		dprintd("[BehEditor] (notify_edit_target) Received node target (consumed _expects_node_target): %s" % active_node)
	if !is_node_target:
		dprintd("[BehEditor] (notify_edit_target) Got target that was not a node; resetting active_node.")
		active_node = null
	_should_update = true


func clear_tree_dependent_pending_state():
	_pending_node_positions = {}
	_pending_parent_child_relations = []
	_pending_set_selected_nodes = null
	_pending_inspect_node = null
	_pending_scroll_offset = null
	_pending_zoom = null


# === CTX Generic Context Menu Request Handler ===


func on_request_ctx_menu(mouse_graph_control_local_pos: Vector2):
	dprintd("[BehEditor] GOT on_request_ctx_menu")
	
	# Calculate where the click was in the control.
	var mouse_graph_local_pos = get_graph_local_pos_from_control_pos(mouse_graph_control_local_pos)
	dprintd("[BehEditor] (on_request_ctx_menu) mouse_graph_control_local_pos = %s" % mouse_graph_control_local_pos)
	dprintd("[BehEditor] (on_request_ctx_menu) mouse_graph_local_pos = %s" % mouse_graph_local_pos)
	
	# Type of context menu to open.
	var context_menu_type := ContextMenuType.GraphCtxMenu
	
	# Determine whether this is a node_context_menu action or a
	# graph_context_menu action.
	#
	# Right-click any selected node to get the node context menu isntead of the
	# graph ctx menu.
	var clicked_node = null
	if len(_selected_nodes) > 0:
		for node_name_key in _selected_nodes:
			var node: BehEditorNode = try_get_node_from_name(node_name_key)
			if node == null:
				continue
			var hitbox_control_local = node.get_rect()
			if hitbox_control_local.has_point(mouse_graph_control_local_pos):
				dprintd("[BehEditor] (on_request_ctx_menu) Clicked node: %s @ %s" % [
					node.name, hitbox_control_local])
				clicked_node = node
				break
			else:
				dprintd("[BehEditor] (on_request_ctx_menu) Click missed node: %s @ %s" % [
					node.name, hitbox_control_local])
	if clicked_node != null:
		dprintd("[BehEditor] (on_request_ctx_menu) Context menu on node: %s" % clicked_node.name)
		context_menu_type = ContextMenuType.NodeCtxMenu
	
	match context_menu_type:
		ContextMenuType.GraphCtxMenu:
			open_graph_ctx_menu(mouse_graph_control_local_pos)
		ContextMenuType.NodeCtxMenu:
			open_node_ctx_menu(mouse_graph_control_local_pos, clicked_node)
		_:
			push_error("[BehEditor] (on_request_ctx_menu) Unhandled %s" % context_menu_type)
	pass


func get_graph_local_pos_from_control_pos(control_local_pos: Vector2) -> Vector2:
	var graph_local_pos_wo_scroll = control_local_pos / graph.zoom
	var graph_local_pos = graph_local_pos_wo_scroll + graph.scroll_offset / graph.zoom
	return graph_local_pos


# === GCM Graph Context Menu ===


func open_graph_ctx_menu(mouse_graph_control_local_pos: Vector2):
#	if !Engine.is_editor_hint(): return
#	if EngineDebugger.is_active(): return
	
	# Calculate where the click was in the control.
	var mouse_graph_local_pos = get_graph_local_pos_from_control_pos(mouse_graph_control_local_pos)
	dprintd("[BehEditor] (open_graph_ctx_menu) mouse_graph_local_pos = %s (will be used for new nodes)" % mouse_graph_local_pos)
	_new_node_pos = mouse_graph_local_pos
	
	# Spawn the context menu (which needs the global click position instead.)
	ctx_menu_graph.position = graph.get_global_mouse_position()
	ctx_menu_graph.size.x = 300
	ctx_menu_graph.size.y = 60
	# Spawn the node picker inside the context popup panel.
	var beh_node_picker = init_beh_node_picker()
	if beh_node_picker == null:
		return # Silently fail here.
	if beh_node_picker.get_parent() != null: # Make sure parent is correct
		beh_node_picker.get_parent().remove_child(beh_node_picker)
	ctx_menu_graph_ctn.add_child(beh_node_picker)
	ctx_menu_graph.popup()


func init_beh_node_picker() -> EditorResourcePicker:
	"""ContextMenu -> Add Node. Spawns an EditorResourcePicker intended for the Graph context menu."""
	if _add_beh_node_picker != null:
		return _add_beh_node_picker
	_add_beh_node_picker = ClassDB.instantiate(StringName("EditorResourcePicker")) as EditorResourcePicker
	if _add_beh_node_picker == null:
		return null
	_add_beh_node_picker.base_type = "BehNode"
	_add_beh_node_picker.resource_changed.connect(on_resource_picker_changed)
	return _add_beh_node_picker


func on_resource_picker_changed(res: Resource):
	"""Called when the EditorResourcePicker resource changes in the New Node context."""
	if res == null:
		dprintd("[BehEditor] Resource selector cleared")
		return
#	dprintd("BehEditor: EditorResourePicker Got resource changed signal! path is %s" % res.resource_path)
	dprintd("[BehEditor] Adding new Orphan node for res instance id %s at pos %s" % [
		res.get_instance_id(), _new_node_pos])
	var beh = res as BehNode
	if beh == null:
		push_error("[BehEditor] (on_resource_picker_changed) Picked resource was not a BehNode. Aborting.")
		return
	var beh_script: Script = beh.get_script() as Script
	if beh_script == null:
		push_warning("[BehEditor] (on_resource_picker_changed) Expected to have a script; can't add BehNode")
		return
	var is_tool = beh_script.is_tool()
	if !is_tool:
		push_error("[BehEditor] (on_resource_picker_changed) Can't add a script %s because it's not a tool script. Did you add @tool to the top of your custom BehNode?" % beh_script.name)
		return
	
	# Perform (undoable) user action
#	add_new_node(res, _new_node_pos)
	undoable_add_nodes([beh], [_new_node_pos], [])
	
	ctx_menu_graph.hide()
	_add_beh_node_picker.edited_resource = null # Clear resource


# === NCM Node Context Menu ===


func open_node_ctx_menu(mouse_graph_control_local_pos: Vector2, clicked_node: BehEditorNode):
	# Calculate where the click was in the control.
	var mouse_graph_local_pos = get_graph_local_pos_from_control_pos(mouse_graph_control_local_pos)
	dprintd("[BehEditor] (open_node_ctx_menu) mouse_graph_local_pos = %s" % mouse_graph_local_pos)
	
	# Spawn the context menu (which needs the global click position instead.)
	ctx_menu_node.position = graph.get_global_mouse_position()
	# Configure the menu.
	ctx_menu_node.clear()
	var entry_id = 0
	for entry in _ctx_menu_node_entries:
		if entry.name.contains("NODE_DEBUG_NAME"):
			var debug_name = "(missing resource_name)"
			if clicked_node.beh != null:
				debug_name = clicked_node.beh.resource_name
				debug_name = debug_name.substr(len(debug_name) - 5)
			debug_name = entry.name.replace("NODE_DEBUG_NAME", debug_name)
			ctx_menu_node.add_item(debug_name, entry.id)
		else:
			ctx_menu_node.add_item(entry.name, entry.id)
		if entry.action == null:
			ctx_menu_node.set_item_disabled(entry_id, true)
		entry_id += 1
	for sep_idx in _ctx_menu_node_separators:
		ctx_menu_node.add_separator("", sep_idx)
	if !_ctx_menu_node_id_pressed_subscribed:
		ctx_menu_node.id_pressed.connect(on_ctx_menu_node_id_pressed)
		_ctx_menu_node_id_pressed_subscribed = true
	# Open the menu.
	ctx_menu_node.popup()


func on_ctx_menu_node_id_pressed(pressed_id: int):
	dprintd("[BehEditor] (on_ctx_menu_node_id_pressed) For pressed_id: %s" % pressed_id)
	var pressed_entry = null
	for entry in _ctx_menu_node_entries:
		if entry.id == pressed_id:
			pressed_entry = entry
			dprintd("[BehEditor] (on_ctx_menu_node_id_pressed) Matched entry: %s" % pressed_entry.name)
			break
	if pressed_entry == null:
		push_error("[BehEditor] (on_ctx_menu_node_id_pressed) Failed to find entry for pressed id %s" % pressed_id)
		return
	var action_name = pressed_entry["action"]
	if action_name == null:
		push_warning("[BehEditor] (on_ctx_menu_node_id_pressed) Ignoring pressed for actionless entry %s" % pressed_entry.name)
		return
	self.call(action_name)


# === NOP Node Operations ===


func add_new_node(beh_node_inst: BehNode, node_spawn_pos: Vector2):
	"""NOTE: UNDOABLE USER OPERATIONS REQUIRE THE USE OF undoable_() OPERATIONS INSTEAD.
	
	Adds a new parent-less node to the active tree. The orphan will become the root of the tree
	and won't be tracked as an orphan if it is the first node to be added to the tree."""
	if active_tree == null:
		push_error("[BehEditor] Must have an active tree to add a new orphan node.")
		return
	active_tree.add_node(beh_node_inst)
	save_active_tree() # Generates a stable ID for the new node so we can set_editor_offset.
	active_tree.set_editor_offset(beh_node_inst, node_spawn_pos)
	dprintd("[BehEditor] Added node %s at %s" % [beh_node_inst, node_spawn_pos])
	dprintd("[BehEditor] OK, added new orphan node. active_tree orphans count is %s" % len(active_tree.orphans))
	_should_update = true


func try_add_parent_child_relation(desired_parent: BehNode, desired_child: BehNode) -> bool:
	"""NOTE: UNDOABLE USER OPERATIONS REQUIRE THE USE OF undoable_() OPERATIONS INSTEAD.
	
	Attempts to create a parent-child relation between the first and second args. May fail."""
	return desired_parent.try_add_child(desired_child)


func try_remove_parent_child_relation(parent: BehNode, child: BehNode) -> bool:
	"""NOTE: UNDOABLE USER OPERATIONS REQUIRE THE USE OF undoable_() OPERATIONS INSTEAD.
	
	Attempts to remove a parent-child relation between the first and second args. Returns true on success."""
	if !parent.remove_child(child):
		push_error("[BehEditor] (try_remove_parent_child_relation) Failed to remove child %s from parent %s." % [
			child, parent])
		return false
	return true


func delete_node(del_node: BehNode):
	"""NOTE: UNDOABLE USER OPERATIONS REQUIRE THE USE OF undoable_() OPERATIONS INSTEAD."""
	if active_tree == null:
		push_error("[BehEditor] (delete_node) Active tree is null, can't delete from it.")
		return
	if del_node == null:
		push_error("[BehEditor] (delete_node) Can't delete a null node.")
		return
	
	var stab_id = del_node.try_get_stable_id()
	if stab_id == null:
		pass # Can't delete editor node data without a stable id.
		push_warning("[BehEditor] (delete_node) Can't delete an editor_node without a stable ID. Instance was: %s" % del_node)
	else:
		dprintd("[BehEditor] (delete_node) Removing editor node for stable_id %s" % stab_id)
		remove_editor_node_for_stable_id(stab_id)
	
	dprintd("[BehEditor] (delete_node) Removing node %s from the active tree." % del_node)
	var removed_node = active_tree.remove_node(del_node)
	if removed_node == null:
		push_warning("[BehEditor] (delete_node) Failed to remove a node from the active_tree (didn't exist)")
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
		#
		# For now ALL NODES MUST BE WITHIN THE TREE; STORING IN FILE SYSTEM IS NOT OK
	pass


func move_node(beh: BehNode, to_pos: Vector2):
	"""NOTE: UNDOABLE USER OPERATIONS REQUIRE THE USE OF undoable_() OPERATIONS INSTEAD."""
	if beh == null:
		push_error("[BehEditor] (move_node) Can't move null node.")
		return
	if !beh.has_stable_id():
		push_error("[BehEditor] (move_node) Can't move node instance %s, it lacks a stable id (save the tree first)." % [
			beh.get_instance_id()])
		return
	active_tree.set_editor_offset(beh, to_pos)


func try_get_node_from_name(node_name: StringName, silent_on_not_found: bool = false) -> Variant:
	"""Returns BehEditorNode or null if not found."""
	var node = graph.get_node_or_null(NodePath(node_name))
	if node == null && !silent_on_not_found:
		push_error("[BehEditor] (try_get_node_from_name) Failed to find node %s" % node_name)
	var node_as_ed_node = node as BehEditorNode
	if node_as_ed_node == null:
		push_error("[BehEditor] (try_get_node_from_name) Found %s but was not BehEditorNode" % node_name)
	return node_as_ed_node


func set_selected_nodes(behs: Array[BehNode]):
	dprintd("[BehEditor] (set_selected_nodes) Called with %s nodes" % len(behs))
#	var names_to_select = []
	var ed_nodes_to_select = []
	for beh in behs:
		if !beh.has_stable_id():
			push_warning("[BehEditor] (set_selected_nodes) Skipping selection for beh w/o stab id, Inst: %s" % [
				beh.get_instance_id()])
			continue
		var id = beh.try_get_stable_id()
		if !_editor_node_map.has(id):
			push_error("[BehEditor] (set_selected_nodes) Missing editor_node_map entry for id %s" % id)
			continue
		var ed_node: BehEditorNode = _editor_node_map[id]
		ed_nodes_to_select.push_back(ed_node)
	# Clear current selection.
	dprintd("[BehEditor] (set_selected_nodes) Removing selection from %s nodes." % len(_selected_nodes))
	for sel_node_name in _selected_nodes.keys():
		var sel_node: BehEditorNode = graph.get_node(sel_node_name) as BehEditorNode
		sel_node.selected = false
#		sel_node.node_deselected.emit()
#		_selected_nodes.erase(sel_node_name)
	# Set selected nodes.
	dprintd("[BehEditor] (set_selected_nodes) Setting selection to %s nodes." % len(ed_nodes_to_select))
	for ed_node in ed_nodes_to_select:
		ed_node.selected = true
#		ed_node.node_selected.emit()
#		_selected_nodes[ed_node.name] = true
	pass
#		var ed_node_name = ed_node.name
#		names_to_select.push_back(ed_node_name)
##	_selected_nodes.clear()
#	for ed_node_name in names_to_select:
##		_selected_nodes[ed_node_name] = true
#		var ed_node = graph.get_node(ed_node_name)


func inspect_node(beh: BehNode):
	"""Careful, this clears any current node selection."""
	if beh == null:
		push_warning("[BehEditor] (inspect_node) Can't inspect null NodeBeh.")
		return
	if editor_plugin == null:
		push_warning("[BehEditor] (inspect_node) Couldn't inspect; missing editor_interface.")
		return
	var ed_interface = editor_plugin.get_editor_interface()
	if ed_interface == null:
		push_warning("[BehEditor] (inspect_node) Couldn't inspect; missing editor_interface.")
		return
	
	# Store state prior to close-and-reopen.
#	print("INSPECT NODE: Storing view info!")
	_pending_scroll_offset = graph.scroll_offset
	_pending_zoom = graph.zoom
	
	# Tell the editor to inspect the object.
	# Sadly, we can't just set inspector_only, because that closes the plugin without apparent
	# recourse.
	#
	# TODO: See if we can set a flag that SKIPS the make-not-visible call to fix this? Then it
	# might fix the flickering issue. But might cause other issues if we set flags we intend to
	# get consumed by a close-and-reopen (e.g. _expects_node_target!!)
	dprintd("[BehEditor] Inspecting behavior %s" % beh)
	self._expects_node_target = true
	ed_interface.inspect_object(beh, "", false)


# === NSE Node Selection ===


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
	dprintd("OK: receive_node_target() called, consuming")
	_expects_node_target = false
	dbg_active_node_label.text = "Active Node: %s" % active_node.get_class()


# === UIS UI Signals ===


func subscribe_panel_btn_signals():
#	btn_reset_view_root.pressed.connect(center_view_on_root)
#	btn_open_beh.pressed.connect(file_open_dialog())
	pass


func subscribe_graph_edit_signals():
	dprintd("[BehEditor] Subscribing to GraphEdit signals.")
	if _graph_subscribed:
		dprintd("[BehEditor] Skipping GraphEdit subscriptions, already subscribed.")
		return
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
	_graph_subscribed = true


func unsubscribe_graph_edit_signals():
	dprintd("[BehEditor] Unsubscribing from GraphEdit signals.")
	if !_graph_subscribed:
		dprintd("[BehEditor] Skipping unsubscription, not subscribed..")
		return
	# Basics
	graph.popup_request.disconnect(on_request_ctx_menu)
	graph.end_node_move.disconnect(on_graph_end_node_move)
	# Other Interactions
	graph.delete_nodes_request.disconnect(on_delete_nodes_request)
	graph.node_selected.disconnect(on_node_selected)
	graph.node_deselected.disconnect(on_node_deselected)
	graph.copy_nodes_request.disconnect(on_copy_nodes_request)
	graph.paste_nodes_request.disconnect(on_paste_nodes_request)
	graph.connection_request.disconnect(on_connection_request)
	graph.disconnection_request.disconnect(on_disconnection_request)
	_graph_subscribed = false


func subscribe_editor_node_signals():
	"""OK to call multiple times when editor nodes are created; tracks subscriptions and avoids
	resubscribing."""
	for id in _editor_node_map.keys():
		var is_subscribed = _subscribed_editor_nodes.has(id)
		if !is_subscribed:
			var ed_node: BehEditorNode = _editor_node_map[id]
			
			ed_node.position_offset_changed.connect(on_editor_node_pos_changed)
			ed_node.mouse_clicked.connect(on_ed_node_mouse_clicked)
			ed_node.mouse_released_without_drag.connect(on_ed_node_mouse_released_without_drag)
			ed_node.mouse_double_clicked.connect(on_ed_node_double_clicked)
			_subscribed_editor_nodes[id] = [
				["position_offset_changed", on_editor_node_pos_changed],
				["mouse_clicked", on_ed_node_mouse_clicked],
				["mouse_released_without_drag", on_ed_node_mouse_released_without_drag],
				["mouse_double_clicked", on_ed_node_double_clicked],
			]
	pass


func unsubscribe_editor_node_signals():
	"""Cleans up editor node signals. Call this before freeing editor nodes."""
	for id in _editor_node_map.keys():
		var is_subscribed = _subscribed_editor_nodes.has(id)
		if is_subscribed:
			var ed_node: BehEditorNode = _editor_node_map[id]
			var signal_callable_pair_arr = _subscribed_editor_nodes[id]
			for signal_callable_pair in signal_callable_pair_arr:
				var signal_name = signal_callable_pair[0]
				var callable = signal_callable_pair[1]
				ed_node.disconnect(signal_name, callable)
			_subscribed_editor_nodes.erase(id)
	pass


func on_delete_nodes_request(nodes = null):
	if nodes == null || len(nodes) == 0: # Use selection
		nodes = []
		for sel_name in _selected_nodes.keys():
			nodes.push_back(sel_name)
		dprintd("[BehEditor] (on_delete_nodes_request) Got NULL delete request (ctx menu action), set via %s selected nodes" % [
			len(nodes)])
	dprintd("[BehEditor] (on_delete_nodes_request) Got delete nodes request: %s" % [nodes])
	
	var del_nodes: Array[BehNode] = []
	for del_node_name in nodes:
		var del_ed_node = graph.get_node_or_null(NodePath(del_node_name))
		if del_ed_node == null:
			push_warning("Missing ed_node for delete request: Name %s" % del_node_name)
			continue
		var del_beh = del_ed_node.beh
		if del_beh == null:
			push_warning("Missing beh for ed_node named: %s" % del_node_name)
			continue
		del_nodes.push_back(del_beh)
	if len(del_nodes) == 0:
		dprintd("[BehEditor] (on_delete_nodes_request) Skipping empty delete request.")
		return
	undoable_delete_nodes(del_nodes, "Delete Selected Nodes")
	_should_update = true
	
#	var del_node_names = nodes.duplicate(false)
#	for del_node_name in del_node_names:
#		var del_node = graph.get_node_or_null(NodePath(del_node_name))
#		# Undoably-delete the node. This will also handle removing the editor node.
#		if del_node.beh == null:
#			push_warning("[BehEditor] (on_delete_nodes_request) Deleted ed_node that had no beh.")
#		else:
#			undoable_delete_nodes([del_node.beh], "Delete Selected Nodes")
##			delete_node(del_node.beh)
#		# Archive: Used to manually remove_editor_node here.
##		if del_node == null:
##			push_warning("[BehEditor] (on_delete_nodes_request) node to delete %s was null" % del_node_name)
##			continue
##		remove_editor_node(del_node)
	
	
#	var del_node_names = nodes.duplicate(false)
#	for del_node_name in del_node_names:
#		var del_node = graph.get_node_or_null(NodePath(del_node_name))
#		# Undoably-delete the node. This will also handle removing the editor node.
#		if del_node.beh == null:
#			push_warning("[BehEditor] (on_delete_nodes_request) Deleted ed_node that had no beh.")
#		else:
#			undoable_delete_nodes([del_node.beh], "Delete Selected Nodes")
##			delete_node(del_node.beh)
#		# Archive: Used to manually remove_editor_node here.
##		if del_node == null:
##			push_warning("[BehEditor] (on_delete_nodes_request) node to delete %s was null" % del_node_name)
##			continue
##		remove_editor_node(del_node)


func on_node_selected(graph_node: Node):
	dprintd("[BehEditor] (on_node_selected) Node: %s" % graph_node.name)
	var node_parent = graph_node.get_parent()
	if node_parent == null: node_parent = "(null)"
	var node_name = graph_node.name
	if node_parent != graph:
		push_error("[BehEditor] (on_node_selected) Got selected node for unknown graph; its parent is %s" % node_parent.name)
		return
	if _selected_nodes.has(graph_node.name):
#		# This is fine; manual selection changes might cause this, which is
#		# why we make selection Set-like.
#		pass
		push_error("[BehEditor] (on_node_selected) _selected_nodes ALREADY contained %s" % graph_node.name)
	_selected_nodes[graph_node.name] = true
	
	_should_update = true


func on_node_deselected(graph_node: Node, allow_not_selected: bool = false):
	dprintd("[BehEditor] (on_node_deselected) Requested deselect node: %s" % graph_node.name)
	var node_parent = graph_node.get_parent()
	if node_parent == null: node_parent = "(null)"
	var node_name = graph_node.name
	if node_parent != graph:
		push_error("[BehEditor] (on_node_deselected) Got selected node for unknown graph; its parent is %s" % node_parent.name)
		return
	if !_selected_nodes.has(graph_node.name) && !allow_not_selected:
		push_error("[BehEditor] (on_node_deselected) _selected_nodes DID NOT contain %s" % graph_node.name)
		return
	if _selected_nodes.has(graph_node.name):
		_selected_nodes.erase(graph_node.name)
	_should_update = true


func on_copy_nodes_request(special_copy_buffer = null):
	dprintd("[BehEditor] (on_copy_nodes_request) Got copy signal.")
	var use_buffer = _copy_nodes_buffer
	if special_copy_buffer != null:
		dprintd("[BehEditor] (on_copy_nodes_request) Copy signal using special arg buffer instead of standard copy buffer.")
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
	dprintd("[BehEditor] (on_paste_nodes_request) Got paste signal.")
	
	# Configure buffer to paste from.
	var use_buffer = _copy_nodes_buffer
	if special_copy_buffer != null:
		dprintd("[BehEditor] (on_copy_nodes_on_paste_nodes_requestrequest) Paste signal using special arg buffer instead of standard copy buffer.")
		use_buffer = special_copy_buffer
	
	var src_to_dup_map = {}
	var dups: Array[BehNode] = []
	var dup_positions = []
	var add_dup_relations = []
	var paste_offset = Vector2(40, 40)
	
	# Create duplicates from the buffer.
	for ed_node_to_copy in use_buffer:
		var src_beh: BehNode = ed_node_to_copy.beh
		var dup_beh = src_beh.clone(false)
		dups.push_back(dup_beh)
		var dup_pos = ed_node_to_copy.position_offset + paste_offset
		dup_positions.push_back(dup_pos)
		if src_beh != null:
			src_to_dup_map[src_beh] = dup_beh
	# For each duplicate, build data to handle relations:
	# - Reparent: dup->src ---> dup->dup
	# - Internalize: dup->(src with no dup) ---> dup->(none)
	for dup in dups:
		for src_child in dup.get_children():
			if src_to_dup_map.has(src_child): # Internal relation: Will reparent dup->dup.
				var dup_child = src_to_dup_map[src_child]
				add_dup_relations.push_back([dup, dup_child])
	# Now we need to process the remove & add parent relations. This can't happen
	# immediately because children need to be tracked by the active_tree as orphans or roots in
	# order to get a stable_id.
	# So the process is:
	# - Remove all child relations within the duplicates FIRST;
	# - UNDOABLY-ADD all duplicates as isolated nodes (roots or orphans) to the active_tree;
	# - SAVE the active_tree to get stable_ids;
	# - UNDOABLY-MOVE the duplicates to their desired positions;
	# - UNDOABLY-PARENT within the paste buffer.
	# The three "undoable" operations will be passed a special override for their action names so that
	# they are undoable & redoable as a single action.
	#
	# Mergeable action name
	var action_name = "Paste %s Nodes" % len(use_buffer)
	#
	# Remove child relations within the duplicates. This doesn't fire any signals; it is an operation
	# entirely invisible to the surrounding tree / editor infrastructure (and this is OK!)
	for dup in dups:
		var children = dup.get_children().duplicate(false)
		for child in children:
			dup.remove_child(child)
	#
	# Undoably-Add all duplicates as isolated nodes to the active tree.
	# We pass FALSE for execute_action so that we execute one single time at the end of defining
	# the actions.
	var fake_positions: Array[Vector2] = []
	for _dup in dups: fake_positions.push_back(Vector2.ZERO)
	dprintd("[BehEditor] (on_paste_nodes_request) Inserting undoable_add_nodes for action name %s ..." % action_name)
	undoable_add_nodes(dups, fake_positions, [], action_name, false)
	# Save the active_tree to get stable_ids (as a step before moving in the forward direction).
	dprintd("[BehEditor] (on_paste_nodes_request) Inserting undoable_insert_save_action for action name %s ..." % action_name)
	undoable_insert_save_action(action_name)
	# Undoably-Move nodes.
	for d in range(len(dups)):
		var dup = dups[d]
		dprintd("[BehEditor] (on_paste_nodes_request) Inserting undoable_move_node for action name %s ..." % action_name)
		undoable_move_node(dup, dup_positions[d], action_name, false)
	# Undoably-Parent nodes within the paste buffer.
	for dup_relation in add_dup_relations:
		var dup_parent = dup_relation[0]
		var dup_child = dup_relation[1]
		dprintd("[BehEditor] (on_paste_nodes_request) Inserting undoable_add_parent_child_relation for action name %s ..." % action_name)
		undoable_add_parent_child_relation(dup_parent, dup_child, action_name, false)
	dprintd("[BehEditor] (on_paste_nodes_request) Inserting undoable on-the-fly action %s ..." % action_name)
	undo_redo.create_action(action_name, UndoRedo.MERGE_ALL, active_tree)
	dprintd("[BehEditor] (on_paste_nodes_request) Committing all added actions now.")
	undo_redo.commit_action(true) # Now all the actions from above are merged and performed.
	
	# Select the newly pasted node(s).
	# We use a _pending buffer because editor nodes don't exist yet for the newly created duplicates
	# until the next process update creates them.
	_pending_set_selected_nodes = dups.duplicate(false)
	
	_should_update = true # Will re-save, make ed_nodes, subscribe to signals, etc.
	
	
	# ORIGINAL PASTE IMPLEMENTATION (didn't support undo/redo)
#	# Track source obj -> duplicate obj so that we can reconstitute children connections
#	# after the duplication process.
#	var src_to_dup_map = {}
#	var nodes_to_be_added: Array[BehNode] = []
#	var add_positions: Array[Vector2] = []
#	for copied_ed_node in use_buffer:
#		if copied_ed_node == null:
#			push_error("[BehEditor] (on_paste_nodes_request) Had null copied node")
#			continue
#		# Duplication method: Create a clone of the BehNode and add it to active_tree.
#		# A new editor node will automatically be created for it.
#		var src_beh: BehNode = copied_ed_node.beh
#		if src_beh == null:
#			push_error("Can't copy null src_beh (ed node: %s)" % copied_ed_node)
#			continue
#		var dup_beh = src_beh.clone(false)
#		var dup_pos = copied_ed_node.position_offset + Vector2(40, 40)
#		dprintd("[BehEditor] (on_paste_nodes_request) ORIG stable_id: %s" % src_beh.try_get_stable_id())
#		dprintd("[BehEditor] (on_paste_nodes_request) DUPE stable_id: %s" % dup_beh.try_get_stable_id())
#		active_tree.add_node(dup_beh)
#		# The newly created node won't have an editor offset until it is saved so that it gets a
#		# stable ID! Instead, queue a position for the node.
#		# This will be processed just saving BehNodes gives them paths in the update step.
#		# e.g. active_tree.set_editor_offset(dup_beh, dup_pos) -> is NOT possible due to lack of stable_id
#		_pending_node_positions[dup_beh] = dup_pos
#		if src_beh != null:
#			src_to_dup_map[src_beh] = dup_beh
#	# Recreate children relationships.
#	# We do this by removing the children of a dup_beh (which refer to src_behs) and
#	# re-adding them IF they are present in our map of duplicated BehNodes.
#	for src_beh in src_to_dup_map.keys():
#		var dup_beh: BehNode = src_to_dup_map[src_beh]
#		var children_to_remove = []
#		var children_to_replace = []
#		for src_child in dup_beh.get_children():
#			if src_to_dup_map.has(src_child):
#				children_to_replace.push_back(src_child)
#			else:
#				children_to_remove.push_back(src_child)
#		for src_child in children_to_remove:
#			# We set ignore_orphan_update to true because pasting will never cause orphaning.
#			dprintd("[BehEditor] (on_paste_nodes_request) (children_to_remove) Removing duped-beh -> src_child relationship with skip-orphaning true.")
#			active_tree.try_remove_parent_child_relationship(dup_beh, src_child, true)
#		for src_child in children_to_replace:
#			# For children we're replacing, we perform the same parenting-removal,
#			# and in the next step we'll add new parent-child relationships.
#			dprintd("[BehEditor] (on_paste_nodes_request) (children_to_replace) Removing duped-beh -> src_child relationship with skip-orphaning true.")
#			active_tree.try_remove_parent_child_relationship(dup_beh, src_child, true)
#		for src_child in children_to_replace:
#			# Instead of immediately adding dup_child as a child relationship,
#			# push it to _pending_parent_child_relations, so that the new children
#			# are tracked directly in the active_tree.orphans array which will get them
#			# a stable_id (via resource_path) when the tree is saved.
#			var dup_child = src_to_dup_map[src_child]
#			_pending_parent_child_relations.push_back([dup_beh, dup_child])
#	_should_update = true # Will save, assign paths, resubscribe to ed_node signals, etc


func on_duplicate_nodes_request():
	"""Invoked via context menu only. Perform a copy & paste using a special duplication buffer.
	Using the special buffer prevents the standard copy buffer from being replaced when calling
	on_copy_nodes_request"""
	var special_buffer = []
	on_copy_nodes_request(special_buffer)
	on_paste_nodes_request(special_buffer)


func on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int):
	if active_tree == null:
		dprintd("[BehEditor] (Connection Request) Ignoring on_connection_request as active_tree is null.")
		return
	# Debugging, figure out what's being called
	dprintd(("[BehEditor] (Connection Request) from_node %s port %s -> to_node %s to_port %s") % [
		from_node, from_port, to_node, to_port])
	
	# Validate this connection is theoretically possible.
	var ed_from = graph.get_node_or_null(NodePath(from_node)) as BehEditorNode
	var ed_to = graph.get_node_or_null(NodePath(to_node)) as BehEditorNode
	dprintd("[BehEditor] (Connection Request) found ed_from? %s" % (ed_from != null))
	dprintd("[BehEditor] (Connection Request) found ed_to?   %s" % (ed_to != null))
	if ed_from == null || ed_to == null: return
	if !ed_from.validate_beh():
		dprintd("[BehEditor] (Connection Request) ed_from had invalidate beh.")
		return
	if !ed_to.validate_beh():
		dprintd("[BehEditor] (Connection Request) ed_to had invalidate beh.")
		return
	
	# Try to add child "from" -> "to"; this might fail.
	undoable_add_parent_child_relation(ed_from.beh, ed_to.beh)
	
#	if try_add_parent_child_relation(ed_from.beh, ed_to.beh):
#		dprintd("[BehEditor] (Connection Request) Successfully added a child relationship: %s -> %s" % [
#			ed_from.beh, ed_to.beh])
#		# graph.connect_node() will be called from the update as a part of the node sync
#		# process.
#		_should_update = true
#	else:
#		dprintd("[BehEditor] (Connection Request) FAILED to add a child relationship (may not be an error!): %s -> %s" % [
#			ed_from.beh, ed_to.beh])
#	_should_update = true
#	pass


func on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int):
	"""Called by the disconnection_request signal from the graph."""
	dprintd("[BehEditor] (on_disconnection_request) Got disconnect request for conn from %s -> to %s" % [
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
		dprintd("[BehEditor] (on_disconnection_request) Calling try_remove_parent_child_relationship because the nodes were disconnected.")
		
		undoable_remove_parent_child_relation(beh_parent, beh_child)
#		if !active_tree.try_remove_parent_child_relationship(beh_parent, beh_child):
#			push_warning("[BehEditor] (on_disconnection_request) Failed to remove parent->child relationship. Parent beh: %s -> Child beh: %s" % [
#				beh_parent, beh_child])
#	# Refresh.
#	_should_update = true


func on_editor_node_pos_changed():
	# Argumentless implementation: Update all editor nodes
	for ed_node in get_editor_nodes():
		var ed_node_pos = ed_node.position_offset
		if ed_node.beh != null:
			active_tree.set_editor_offset(ed_node.beh, ed_node_pos)
	pass


func on_ed_node_mouse_clicked(ed_node: BehEditorNode):
	"""Attached to BehEditorNode mouse_clicked event, FORMERLY used to Inspect a node."""
	# Note: Moved Inspection trigger to when an editor node is released without dragging the node.
	# That handler is just below.
	pass


func on_ed_node_mouse_released_without_drag(ed_node: BehEditorNode):
	"""Also formerly used to Inspect a node."""
	# Note: Moved to double-click handler
	pass

func on_ed_node_double_clicked(ed_node: BehEditorNode):
	"""Attached to BehEditorNode mouse_released_without_drag event, used to Inspect a node."""
	if ed_node == null:
		push_error("[BehEditor] (on_ed_node_double_clicked) Got null ed_node.")
		return
	# If a SINGLE node is currently selected and we just got this event,
	# open the node in the Inspector.
	var first_sel_ed_node_name = null
	for sel_ed_node_name in _selected_nodes.keys():
		first_sel_ed_node_name = sel_ed_node_name
		break
	var did_click_on_single_selected_ed_node = first_sel_ed_node_name == ed_node.name
	if len(_selected_nodes) == 1 && did_click_on_single_selected_ed_node && !_expects_node_target:
		var beh = ed_node.beh
		if beh == null:
			push_error("[BehEditor] (on_ed_node_double_clicked) Can't inspect null beh in ed_node %s" % ed_node)
			return
		dprintd("[BehEditor] (on_ed_node_double_clicked) Inspecting double-clicked beh %s" % beh)
		_pending_inspect_node = beh
		var set_sel: Array[BehNode] = [beh]
		_pending_set_selected_nodes = set_sel
		_should_update = true
	pass


func remove_editor_node(ed_node: BehEditorNode):
	""""""
	dprintd("[BehEditor] (remove_editor_node) Remove (delete) ed_node %s" % ed_node)
	if ed_node == null:
		push_error("[BehEditor] (remove_editor_node) Wanted to remove a null BehEditorNode")
		
	# Remove from selection if selected.
	var ed_node_name = ed_node.name
	if _selected_nodes.has(ed_node_name):
		_selected_nodes.erase(ed_node_name)
	
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
				if _subscribed_editor_nodes.has(id):
					# We'll free the ed_node, so just remove the key.
					# We don't have to unsubscribe since it's handled from the node
					# that's being freed anyway.
					_subscribed_editor_nodes.erase(id)
					
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
		dprintd("[BehEditor] (remove_editor_node) Removing %s -> %s" % [conn.from, conn.to])
		graph.disconnect_node(conn.from, conn.from_port, conn.to, conn.to_port)
	for conn in conns_to:
		dprintd("[BehEditor] (remove_editor_node) Removing %s -> %s" % [conn.from, conn.to])
		graph.disconnect_node(conn.from, conn.from_port, conn.to, conn.to_port)
	
	# Remove the BehEditorNode from the graph and free it.
	graph.remove_child(ed_node)
	ed_node.queue_free()
	_should_update = true


func remove_editor_node_for_stable_id(stab_id: String):
	if stab_id == null:
		push_error("[BehEditor] (remove_editor_node_for_stable_id) Got null stab_id.")
		return
	if !_editor_node_map.has(stab_id):
		push_error("[BehEditor] (remove_editor_node_for_stable_id) _editor_node_map missing entry for stable ID %s" % stab_id)
		return
	var ed_node = _editor_node_map[stab_id]
	remove_editor_node(ed_node)


func clear_editor_nodes():
	dprintd("[BehEditor] Clearing editor nodes (unsubscribing first) and map cache for them.")
	unsubscribe_editor_node_signals()
	if len(_subscribed_editor_nodes) > 0:
		push_warning(("[BehEditor] Still had %s editor node subscriptions after attempting " +
			"to unsubscribe from them.") % len(_subscribed_editor_nodes))
		_subscribed_editor_nodes.clear()
	graph.clear_connections() # Clear connections, prevents errors when freeing GraphNodes
	for key in _editor_node_map.keys():
		var ed_node = _editor_node_map[key]
		remove_editor_node(ed_node)
	_editor_node_map.clear()


# === FEA Formal Editor Action Methods ===
#
# Invoke these methods to perform operations on the tree. Each call constructs Actions in the
# undo/redo history so that Godot can automatically handle undo & redo calls.


func undoable_add_nodes(
	nodes_to_be_added: Array[BehNode],
	add_positions: Array[Vector2],
	parent_child_relations: Array[Array],
	action_name_override: String = "",
	execute_action: bool = true
):
	"""Undoably adds nodes to the active tree."""
	# Validation.
	if nodes_to_be_added == null:
		push_error("[BehEditor] (undoable_add_nodes) Called with null nodes_to_be_added.")
		return
	if add_positions == null:
		push_error("[BehEditor] (undoable_add_nodes) Called with null add_positions.")
		return
	if len(nodes_to_be_added) != len(add_positions):
		push_error("[BehEditor] (undoable_add_nodes) nodes_to_be_added length != add_positions length.")
		return
	if parent_child_relations == null:
		push_error("[BehEditor] (undoable_add_nodes) Called with null parent_child_relations.")
		return
	for relation in parent_child_relations:
		var parent = relation[0]
		var child = relation[1]
		if !nodes_to_be_added.any(func(node): return node == parent):
			push_error("[BehEditor] (undoable_add_nodes) Relation parent %s not present in argument added nodes list.")
			return
		if !nodes_to_be_added.any(func(node): return node == child):
			push_error("[BehEditor] (undoable_add_nodes) Relation child %s not present in argument added nodes list.")
			return
	dprintd("[BehEditor] (undoable_add_nodes) Called to add %s nodes with %s inner relations." % [
		len(nodes_to_be_added), len(parent_child_relations)])
	if active_tree == null:
		push_error("[BehEditor] (undoable_add_nodes) Must have active tree to perform this operation.")
		return
	
	# Init the undoable action.
	if len(action_name_override) > 0:
		# Use override and allow undo ops to merge by name.
		dprintd("[BehEditor] (undoable_add_nodes) Overridden mergeable with action_name %s" % action_name_override)
		undo_redo.create_action(action_name_override, UndoRedo.MERGE_ALL, active_tree)
	else:
		# Create standard action.
		var action_name = "Add %s Nodes" % len(nodes_to_be_added)
		undo_redo.create_action(action_name, UndoRedo.MERGE_DISABLE, active_tree)
		dprintd("[BehEditor] (undoable_add_nodes) Created undoable add with standard name %s" % action_name)
	
	# Shallow-copy arrays to be passed to forward ("do") callable.
	nodes_to_be_added = nodes_to_be_added.duplicate(false)
	parent_child_relations = parent_child_relations.duplicate(false)
	# Add forward action.
	undo_redo.add_do_method(self, "_midaction_add_nodes", nodes_to_be_added, add_positions, parent_child_relations)
	# Shallow-copy arrays to be passed to reverse ("undo") callable.
	nodes_to_be_added = nodes_to_be_added.duplicate(false)
	parent_child_relations = parent_child_relations.duplicate(false)
	# Add reverse action.
	undo_redo.add_undo_method(self, "_midaction_delete_nodes", nodes_to_be_added)
	
	# Commit the action. execute passed as true, so the do methods are invoked.
	dprintd("[BehEditor] (undoable_add_nodes) Committing action.")
	undo_redo.commit_action(execute_action)


func undoable_delete_nodes(nodes_to_be_deleted: Array[BehNode], override_action_name: String = "", execute_action: bool = true):
	# Validation.
	if nodes_to_be_deleted == null:
		push_error("[BehEditor] (undoable_delete_nodes) Called with null nodes_to_be_deleted.")
		return
	for del_node in nodes_to_be_deleted:
		if del_node == null:
			push_error("[BehEditor] (undoable_delete_nodes) Null entry in nodes_to_be_deleted.")
			return
		var has_pos = active_tree.has_editor_offset(del_node)
		if !has_pos:
			push_error("[BehEditor] (undoable_delete_nodes) del_node %s lacks pos (needed for undo). Aborting." % del_node)
			return
	if active_tree == null:
		push_error("[BehEditor] (undoable_delete_nodes) Must have active tree to perform this operation.")
		return
	
	# Init action.
	var use_action_name = "Delete %s Nodes" % len(nodes_to_be_deleted)
	if len(override_action_name) > 0:
		use_action_name = override_action_name
		undo_redo.create_action(use_action_name, UndoRedo.MERGE_ENDS, active_tree)
	else:
		undo_redo.create_action(use_action_name, UndoRedo.MERGE_DISABLE, active_tree)
	
	# Action operations.
	nodes_to_be_deleted = nodes_to_be_deleted.duplicate(false)
	undo_redo.add_do_method(self, "_midaction_delete_nodes", nodes_to_be_deleted)
	nodes_to_be_deleted = nodes_to_be_deleted.duplicate(false)
	undo_redo.add_undo_method(self, "_midaction_add_nodes", nodes_to_be_deleted, null, null)
	for del_node in nodes_to_be_deleted: # Add undo references so we don't lose the nodes to GC
		undo_redo.add_undo_reference(del_node)
	
	# Commit action.
	undo_redo.commit_action(execute_action)


func undoable_add_parent_child_relation(parent: BehNode, child: BehNode, override_action_name: String = "", execute_action: bool = true):
	# Validation.
	if parent == null:
		push_error("[BehEditor] (undoable_add_parent_child_relation) Called with null parent.")
		return
	if child == null:
		push_error("[BehEditor] (undoable_add_parent_child_relation) Called with null child.")
		return
	if active_tree == null:
		push_error("[BehEditor] (undoable_add_parent_child_relation) Must have active tree to perform this operation.")
		return
	if active_tree.get_node_parent(child) != null:
		push_error("[BehEditor] (undoable_add_parent_child_relation) Cannot add parent to child that already has one.")
		return
	
	# Init action.
	var use_action_name = "Set Parent-Child Node Relationship"
	if len(override_action_name) > 0:
		use_action_name = override_action_name
	undo_redo.create_action(use_action_name, UndoRedo.MERGE_ALL, active_tree)
	# Action operations.
	undo_redo.add_do_method(self, "_midaction_add_parent_child_relation", parent, child)
	undo_redo.add_undo_method(self, "_midaction_remove_parent_child_relation", parent, child)
	# Commit action.
	dprintd("[BehEditor] (undoable_add_parent_child_relation) Committing action.")
	undo_redo.commit_action(execute_action)


func undoable_remove_parent_child_relation(parent: BehNode, child: BehNode, execute_action: bool = true):
	# Validation.
	if parent == null:
		push_error("[BehEditor] (undoable_remove_parent_child_relation) Called with null parent.")
		return
	if child == null:
		push_error("[BehEditor] (undoable_remove_parent_child_relation) Called with null child.")
		return
	if active_tree == null:
		push_error("[BehEditor] (undoable_remove_parent_child_relation) Must have active tree to perform this operation.")
		return
	
	# TODO: Finish implementing undoable_remove_parent_child_relation here;
	
	# Init action.
	undo_redo.create_action("Remove Parent-Child Node Relationship", UndoRedo.MERGE_ALL, active_tree)
	# Action operations.
	undo_redo.add_do_method(self, "_midaction_remove_parent_child_relation", parent, child)
	undo_redo.add_undo_method(self, "_midaction_add_parent_child_relation", parent, child)
	# Commit action.
	undo_redo.commit_action(execute_action)


func undoable_move_node(node_to_be_moved: BehNode, destination_pos_offset: Vector2, override_action_name: String = "", execute_action: bool = true):
	# Validation.
	if node_to_be_moved == null:
		push_error("[BehEditor] (undoable_move_node) Called with null node_to_be_moved.")
		return
	# Subtle validation -- This action may a QUEUED action;
	# node may have stable_id by the time action is committed.
	if !node_to_be_moved.has_stable_id() && execute_action:
		push_error("[BehEditor] (undoable_move_node) node_to_be_moved %s lacks stable_id." % node_to_be_moved)
		return
	if active_tree == null:
		push_error("[BehEditor] (undoable_move_node) Must have active tree to perform this operation.")
		return
	
	# Init action.
	var use_action_name = "Move Node"
	if len(override_action_name) > 0:
		use_action_name = override_action_name
	undo_redo.create_action(use_action_name, UndoRedo.MERGE_ALL, active_tree)
	# Action operations.
	undo_redo.add_do_method(self, "_midaction_move_node", node_to_be_moved, destination_pos_offset)
	var original_pos_offset = active_tree.get_editor_offset_or(node_to_be_moved, Vector2.ZERO)
	undo_redo.add_undo_method(self, "_midaction_move_node", node_to_be_moved, original_pos_offset)
	# Commit action.
	dprintd("[BehEditor] (undoable_move_node) Committing action.")
	undo_redo.commit_action(execute_action)


func undoable_insert_save_action(action_name: String):
	"""Inserts a save action with the specified action name and MERGE_ALL merge rule. Call this
	when you are chaining a series of merge-intended undo actions that require stable_id generation
	(e.g. between adding a new node and moving it)."""
	undo_redo.create_action(action_name, UndoRedo.MERGE_ALL, active_tree)
	undo_redo.add_do_method(self, "save_active_tree")
	dprintd("[BehEditor] (undoable_insert_save_action) Committing action.")
	undo_redo.commit_action(false)


# --- Mid-Action Implementation Functions for Formal Editor Action Methods ---


func _midaction_add_nodes(
	nodes_to_be_added: Array[BehNode],
	add_positions, # Array[Vector2],
	parent_child_relations # Array[Array]
):
	dprintd("[BehEditor] (_midaction_add_nodes) Called for %s nodes." % len(nodes_to_be_added))
	var added_nodes = nodes_to_be_added
	# Add the nodes.
	for n in range(len(added_nodes)):
		var add_node = added_nodes[n]
		if add_node == null: continue
		var add_pos = Vector2.ZERO
		if add_positions == null:
			if _hint_last_editor_positions.has(add_node):
				add_pos = _hint_last_editor_positions[add_node]
				_hint_last_editor_positions.erase(add_node)
				dprintd("[BehEditor] (_midaction_add_nodes) Consumed _hint_last_editor_positions entry for add_node %s." % [
					add_node])
		else:
			add_pos = add_positions[n]
		_midaction_add_node(add_node, add_pos)
	# Create relationships between the nodes.
	if parent_child_relations == null: # Check _del_hint_last_children in case we're undoing a delete.
		for add_node in added_nodes:
			if _del_hint_last_children.has(add_node):
				var add_children_relations = _del_hint_last_children[add_node]
				for add_node_child in add_children_relations:
					if parent_child_relations == null:
						parent_child_relations = []
					parent_child_relations.push_back([add_node, add_node_child])
				dprintd("[BehEditor] (_midaction_add_nodes) Consumed _del_hint_last_children entry for add_node %s." % [
					add_node])
				_del_hint_last_children.erase(add_node)
			# Also check if the node has a parent relation to restore.
			if _del_hint_last_parent.has(add_node):
				var add_parent = _del_hint_last_parent[add_node]
				if parent_child_relations == null:
					parent_child_relations = []
				parent_child_relations.push_back([add_parent, add_node])
	if parent_child_relations != null:
		# Prevent double-assignment since we add relations bidirectionally above.
		var handled_parent_child_additions = {} 
		for parent_child_relation in parent_child_relations:
			var parent = parent_child_relation[0]
			var child = parent_child_relation[1]
			if handled_parent_child_additions.has(child):
				var handled_parent = handled_parent_child_additions[child]
				if handled_parent != parent:
					push_error("[BehEditor] (_midaction_add_nodes) Handling parent_child_relations but incompatibly tried to add a second parent to a child. First parent %s -> to child %s; second parent was %s." % [
						handled_parent, child, parent])
				continue # Either way, skip this parent->child duplicate entry.
			_midaction_add_parent_child_relation(parent, child)
			handled_parent_child_additions[child] = parent
	
	# NEXT STEPS: See sublime, notes re: reproducing a bug relating to undoing the deletion
	# of two or more chain steps of a chain


func _midaction_add_node(beh: BehNode, pos: Vector2):
	dprintd("[BehEditor] (_midaction_add_node) Called for %s @ %s" % [beh, pos])
	add_new_node(beh, pos)
	_should_update = true


func _midaction_add_parent_child_relation(parent: BehNode, child: BehNode):
	dprintd("[BehEditor] (_midaction_add_parent_child_relation) Called for %s -> %s" % [parent, child])
	var success = try_add_parent_child_relation(parent, child)
	if !success:
		push_error("[BehEditor] (_midaction_add_parent_child_relation) Failed to create a parent->child relation for %s -> %s." % [
			parent, child])
		return
	_should_update = true


func _midaction_remove_parent_child_relation(parent: BehNode, child: BehNode):
	dprintd("[BehEditor] (_midaction_remove_parent_child_relation) Called.")
	var success = try_remove_parent_child_relation(parent, child)
	if !success:
		push_error("[BehEditor] (_midaction_remove_parent_child_relation) Failed to remove a parent->child relation for %s -> %s." % [
			parent, child])
		return
	_should_update = true


func _midaction_delete_nodes(nodes_to_be_deleted: Array[BehNode]):
	dprintd("[BehEditor] (_midaction_delete_nodes) Called.")
	var del_nodes = nodes_to_be_deleted
	# Store position hints and parent-child relation hints.
	for d in range(len(del_nodes)):
		var del_node = del_nodes[d]
		var del_pos = active_tree.get_editor_offset(del_node)
		_hint_last_editor_positions[del_node] = del_pos
		var del_children = del_node.get_children().duplicate(false)
		_del_hint_last_children[del_node] = del_children
		var del_parent = active_tree.get_node_parent(del_node)
		if del_parent != null:
			_del_hint_last_parent[del_node] = del_parent
	for del_node in del_nodes:
		_midaction_delete_node(del_node)


func _midaction_delete_node(beh: BehNode):
	dprintd("[BehEditor] (_midaction_delete_node) Called.")
	delete_node(beh)
	_should_update = true


func _midaction_move_node(beh: BehNode, to_pos: Vector2):
	dprintd("[BehEditor] (_midaction_move_node) Called.")
	move_node(beh, to_pos)
	_should_update = true


# === UME Utility Methods ===


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


# === VMN View Management ===


func get_view_center_offset() -> Vector2:
	return graph.size / 2



