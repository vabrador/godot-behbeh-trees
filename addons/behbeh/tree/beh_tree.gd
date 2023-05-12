@tool
@icon("res://addons/behbeh/icons/beh_tree.png")
class_name BehTree
extends Resource


const EDITOR_OFFSET_KEY: String = "ed_offset"


# Exports - Not just exposed in the Inspector, but this also determines what's saved!

## BehTrees can have multiple roots, which offer multiple entry points that update
## simultaneously.
@export var roots: Array[BehNode] = []

## Node metadata for in-tree or orphaned BehNodes. This includes "ed_offset", which tracks
## the node's in-editor tree position, if it exists.
@export var node_meta: Dictionary = {}

## Parent-less nodes that are NOT roots that were added to this tree at some point. Usually used
## the authoring process, for newly-created nodes prior to formalizing them with
## a parent connection, or for nodes who were children of a recently-deleted node.
@export var orphans: Array[BehNode] = []


var _subscribed_nodes: Dictionary = {}


signal tree_changed()


func _ready():
	print("[BehTree] _ready called")
	for node in get_all_nodes(): subscribe_node_signals(node)


func subscribe_node_signals(beh: BehNode):
	if _subscribed_nodes.has(beh): return
	print("[BehTree] (subscribe_node_signals) Subscribing to signals for %s" % beh)
	beh.child_added.connect(func(new_child): on_child_added(beh, new_child))
	beh.child_removed.connect(func(old_child): on_child_removed(beh, old_child))
	_subscribed_nodes[beh] = true


func on_child_added(par_beh: BehNode, child_beh: BehNode):
	print("[BehTree] signal child_added: %s -> %s" % [par_beh, child_beh])
	# New child loses orphan status (tree no longer needs to track it).
	var orphan_id = orphans.find(child_beh)
	if orphan_id != -1:
		orphans.remove_at(orphan_id)
		tree_changed.emit()


func on_child_removed(par_beh: BehNode, child_beh: BehNode):
	print("[BehTree] signal child_removed: %s -> %s" % [par_beh, child_beh])
	# New child gains orphan status (tree must track it).
	orphans.push_back(child_beh)
	tree_changed.emit()


func is_empty() -> bool:
	"""Returns whether this tree contains any nodes. Includes orphans that may be in the tree."""
	return len(roots) == 0 && len(orphans) == 0


func has_roots() -> bool:
	"""Returns whether this tree has a root node defined."""
	return len(roots) != 0


func has_orphans() -> bool:
	"""Whether this tree tracks any orphans."""
	return len(orphans) != 0


func add_node(node: BehNode):
	"""Adds a new node. If the node is a root, it's added to the roots list."""
	print("[BehTree] Got add_node: %s" % node)
	if node.get_is_root():
		roots.push_back(node)
	else:
		orphans.push_back(node)
	subscribe_node_signals(node)


func validate_roots_and_orphans() -> bool:
	"""Confirms that orphans are not roots and roots are not orphans. If this validation
	caused the tree to change its state, returns true."""
	var changed_ct = 0
	# Roots -> Orphans
	var new_orphans = []
	var rms = []
	for r in range(len(roots)):
		var root = roots[r]
		if !root.get_is_root():
			new_orphans.push_back(root)
			rms.push_front(r)
			changed_ct += 1
	for rm in rms: # reverse-index order makes this valid
		roots.remove_at(rm)
	for new_orphan in new_orphans:
		orphans.push_back(new_orphan)
	# Orphans -> Roots
	var new_roots = []
	rms.clear()
	for o in range(len(orphans)):
		var orphan = orphans[o]
		if orphan.get_is_root():
			new_roots.push_back(orphan)
			rms.push_front(o)
			changed_ct += 1
	for rm in rms: # reverse-index order
		orphans.remove_at(rm)
	for new_root in new_roots:
		roots.push_back(new_root)
	if changed_ct > 0:
		print("[BehTree] (validate_roots_and_orphans) Counted %s changes between roots & orphans." % changed_ct)
	var any_changed = changed_ct > 0
	return any_changed


func get_is_orphan(node: BehNode):
	var is_orphan = orphans.find(node) != -1
#	print("[BehTree] is_orphan for node %s ? %s" % [node, is_orphan])
	return orphans.find(node) != -1


func get_all_nodes() -> Array[BehNode]:
	"""Returns an array with all BehNodes tracked by this tree, INCLUDING its orphans."""
	var arr: Array[BehNode] = []
	if has_roots():
		for root in roots:
			for node in root.get_all_children():
				arr.push_back(node)
	for orphan in orphans:
		arr.push_back(orphan)
	return arr


func has_editor_offset(beh_node: BehNode) -> bool:
	var id = beh_node.try_get_stable_id()
	if id == null:
		push_warning("[BehTree] Can't has_editor_offset: BehNode lacks stable ID")
		return false
	else:
		print("[BehTree] OK: has_editor_offset on BehNode with stable ID %s" % id)
	if node_meta == null: node_meta = {}
	if !node_meta.has(id): return false
	if !node_meta[id].has(EDITOR_OFFSET_KEY): return false
	if node_meta[id][EDITOR_OFFSET_KEY] == BehConst.UNSET_VEC: return false
	return true


func get_editor_offset(beh_node: BehNode) -> Vector2:
	var id = beh_node.try_get_stable_id()
	if id == null:
		push_warning("[BehTree] Can't get_editor_offset: BehNode lacks stable ID")
		return BehConst.UNSET_VEC
	else:
		print("[BehTree] OK: get_editor_offset on BehNode with stable ID %s" % id)
	if node_meta == null: node_meta = {}
	if !node_meta.has(id): node_meta[id] = {}
	if !node_meta[id].has(EDITOR_OFFSET_KEY): node_meta[id][EDITOR_OFFSET_KEY] = BehConst.UNSET_VEC
	if node_meta[id][EDITOR_OFFSET_KEY] == BehConst.UNSET_VEC:
		return Vector2.ZERO
	return node_meta[id][EDITOR_OFFSET_KEY]


func set_editor_offset(beh_node: BehNode, pos: Vector2):
	var id = beh_node.try_get_stable_id()
	if id == null:
		push_warning("[BehTree] Can't set_editor_offset: BehNode lacks stable ID")
		return
#	print("[BehTree] == set_editor_offset volatility test ==")
#	print("[BehTree] beh_node stable_id = %s" % id)
#	print("[BehTree] beh_node resource_path = %s" % beh_node.resource_path)
#	print("[BehTree] beh_node resource_name = %s" % beh_node.resource_name)
#	print("set_editor_offset: Setting beh_node id %s pos to %s" % [id, pos])
	if node_meta == null: node_meta = {}
	if !node_meta.has(id): node_meta[id] = {}
	node_meta[id][EDITOR_OFFSET_KEY] = pos
	print("[BehTree] OK: set_editor_offset on BehNode with stable ID %s; arg was pos %s and get_editor_offset now returns pos %s for this node" % [
		id, pos, get_editor_offset(beh_node)])


# TODO: Remove once editor position refactor has stabilized -2023-05-11
#func has_editor_position() -> bool:
#	"""Whether this BehNode has an _ed_offset specified from being opened in the BehTreeEditor."""
#	return _ed_offset != BehConst.UNSET_VEC
#
#func get_editor_position() -> Vector2:
#	"""Whether this BehNode has an _ed_offset specified from being opened in the BehTreeEditor."""
#	if !has_editor_position(): return Vector2.ZERO
#	return _ed_offset
#
#func has_editor_positions_recursive() -> bool:
#	"""Whether this BehNode and all its children have valid _ed_offset variables.
#	Checks against BehUtils.UNSET_VEC."""
#	for child in get_all_children():
#		if !child.has_editor_position(): return false
#	return true
