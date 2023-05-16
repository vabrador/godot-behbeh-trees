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
## Each orphan can have children! Orphan status simply implies they are NEVER called by the
## BehTree. All of an orphan's children are also orphans, but are not tracked in THIS array,
## as they are already referenced via parent -> children.
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
	# All of this child's children are also orphans but are tracked via the child
	# relationship of the top-level orphan.
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


func remove_node(node: BehNode) -> BehNode:
	"""Removes a node from the tree. If the BehNode was found and removed, it is returned;
	otherwise if the BehNode was not found in the tree, this func returns null."""
	var to_return = null
	var found_in_roots = find_node_in_roots(node)
	if found_in_roots[0] != -1:
		# Remove from tree. This will create orphans in if the node has children.
		var root_idx = found_in_roots[0]
		var node_parent = found_in_roots[1]
		var found_node = found_in_roots[2]
		to_return = found_node
		print("[BehTree] (remove_node) Found node to remove. Calling _inner_remove_node with roots list ...")
		_inner_remove_node_from_tree(found_node, node_parent, self.roots, root_idx, self.orphans)
		return to_return
	var found_in_orphans = find_node_in_orphans(node)
	if found_in_orphans[0] != -1:
		var orphan_root_idx = found_in_orphans[0]
		var node_parent = found_in_orphans[1]
		var found_node = found_in_orphans[2]
		to_return = found_node
		print("[BehTree] (remove_node) Found node to remove. Calling _inner_remove_node with orphans list ...")
		_inner_remove_node_from_tree(found_node, node_parent, self.orphans, orphan_root_idx, self.orphans)
		return to_return
	print("[BehTree] (remove_node) Did not find node %s in root trees nor orphan trees." % node)
	return null


static func _inner_remove_node_from_tree(
	found_node: BehNode,
	node_parent: BehNode,
	from_trees: Array,
	tree_idx: int,
	push_orphans_list: Array
):
	"""Helper function for removing a node from a tree and pushing any resulting orphans to the
	push_orphans_list. If the removal node is a tree root, the from_trees list has that entry
	removed."""
	print("[BehTree] (_inner_remove_node_from_tree) Remove tree_idx %s, node_parent %s, found_node %s" % [
		tree_idx, node_parent, found_node])
	
	# The node's children are now orphans.
	var children = found_node.get_children()
	for child in children:
		if !found_node.remove_child(child):
			push_warning("[BehTree] (_inner_remove_node_from_tree) Node %s reported failed to remove child %s (child did not exist)" % [found_node, child])
		# Child is now an orphan.
		push_orphans_list.push_back(child)
	# Also remove the found node as a child from its parent.
	if node_parent != null:
		# The node is NOT itself a root, so just remove it as a child of its parent.
		if !node_parent.remove_child(found_node):
			push_warning("[BehTree] (_inner_remove_node_from_tree) Node %s reported failed to remove child %s (child did not exist)" % [node_parent, found_node])
	else:
		# The node itself IS a root, so remove it from the roots list
		print("[BehTree] (_inner_remove_node_from_tree) Removing tree idx %s" % tree_idx)
		from_trees.remove_at(tree_idx)
	pass


func try_remove_parent_child_relationship(
	parent: BehNode,
	child: BehNode,
	ignore_orphan_update: bool = false
) -> bool:
	"""Tries to confirm the existence of and remove a parent-child relationship in the active_tree,
	whether in a root or orphan tree. If the relationship was invalid in any way and therefore
	could not be removed, returns false, otherwise returns true.
	
	You do NOT need to call this if trying to remove a node from the tree. Just call remove_node
	for that and it will handle removing relationships and handling orphaning itself. Call this
	if you are removing a parent-child relationship but not otherwise modifying the tree structure."""
	print("[BehTree] (try_remove_parent_child_relationship) Wants to remove %s -> child %s" % [
		parent, child])
	var child_to_orphan = null
	var valid_parent = false
	var found_in_roots = find_node_in_roots(parent)
	if found_in_roots[0] != -1:
		if !ignore_orphan_update: child_to_orphan = child # Will orphan the child.
		valid_parent = true # Ignore the orphan update; will just call remove_child.
	var found_in_orphans = find_node_in_orphans(parent)
	if found_in_orphans[0] != -1:
		if !ignore_orphan_update: child_to_orphan = child # Will orphan the child.
		valid_parent = true # Ignore the orphan update; will just call remove_child.
	if !valid_parent:
		push_error("[BehTree] (try_remove_parent_child_relationship) Failed to find parent in the tree.")
		return false
	else:
		var valid_child = false
		for check_child in parent.get_children():
			if check_child == child:
				valid_child = true
				break
		if valid_child == false:
			push_error("[BehTree] (try_remove_parent_child_relationship) Failed to find argument child %s of argument parent %s." % [
				child, parent])
			return false
		else:
			if !parent.remove_child(child):
				push_error("[BehTree] (try_remove_parent_child_relationship) remove_child() failed for parent %s -> child %s" % [
					parent, child])
				return false
			else:
				# Finalize orphaning the child.
				if child_to_orphan != null:
					self.orphans.push_back(child_to_orphan)
				return true
	pass


static func find_node_in_tree_list(node: BehNode, tree_roots: Array[BehNode]) -> Array:
	"""Static helper for finding a node in a list of trees. If found, returns [tree_idx, parent, node].
	Returns [-1, null, null] if not found."""
	var root_idx = -1
	var parent = null
	var r = 0
	for root in tree_roots:
		for pair in root.get_all_children_with_parent():
			var child = pair[0]
			var child_parent = pair[1]
			if node == child:
				root_idx = r
				parent = child_parent
				break
		if root_idx != -1: break
		r += 1
	if root_idx == -1:
		print("[BehTree] (find_node_in_tree_list) NOT FOUND")
	else:
		print("[BehTree] (find_node_in_tree_list) Returning found in given tree_roots: %s" % [[root_idx, parent, node]])
	if root_idx == -1: # Not found.
		return [-1, null, null]
	return [root_idx, parent, node]
	


func find_node_in_roots(node: BehNode) -> Array:
	"""Searches for the node in the 'roots' trees. Returns [root_idx, parent_node, node] if found.
	If the node is itself a root, parent_node will be null. Returns [-1, null, null] if not found."""
	print("[BehTree] (find_node_in_roots) arg node: %s; calling find_node_in_tree_list with self.roots" % node)
	return find_node_in_tree_list(node, self.roots)


func find_node_in_orphans(node: BehNode) -> Array:
	"""Searches for the node in the 'orphans' trees. Returns [orphan_idx, parent_node, node] if found.
	If the node is itself a root orphan, parent_node will be null. Returns [-1, null, null] if not found."""
	print("[BehTree] (find_node_in_roots) arg node: %s; calling find_node_in_tree_list with self.roots" % node)
	return find_node_in_tree_list(node, self.orphans)


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


func validate_single_parents() -> bool:
	"""Confirms that every child has a single parent. If more than one parent is detected for a child,
	a warning is pushed and the relationship is fixed (only the first detected parent retains
	parenthood for a given child, and returns true. Returns false if no change was necessary."""
	var changes = []
#	var parent = {}
#	var addl_parents = []
#	var child = {}
	
	var child_parents = {}
	for child_parent_pair in self.get_all_nodes_with_parents():
		var child = child_parent_pair[0]
		var parent = child_parent_pair[1]
		if parent != null:
			if !child_parents.has(child):
				child_parents[child] = []
			child_parents[child].push_back(parent)
	for child in child_parents.keys():
		var parents = child_parents[child]
		if len(parents) > 1:
			var addl_parents = []
			for p in range(1, len(parents)):
				var addl_parent = parents[p]
				addl_parents.push_back(addl_parent)
				changes.push_back({
					"msg": "Remove addl-parent %s -> child %s relationship" % [addl_parent, child],
					"parent": addl_parent,
					"child": child,
				})
	# Process any changes.
	for change in changes:
		if !try_remove_parent_child_relationship(change.parent, change.child, true):
			push_error("[BehTree] (validate_single_parents)  Failed to remove parent-child relationship: parent %s -> child %s" % [
				change.parent, change.child])
	
	var any_changed = len(changes) == 0
	if !any_changed:
		for change in changes:
			push_warning("[BehTree] (validate_single_parents) Effected a change to preserve single-parenthood: %s" % [
				change.msg])
	return !any_changed


func get_is_orphan(node: BehNode):
	var is_orphan = orphans.find(node) != -1
#	print("[BehTree] is_orphan for node %s ? %s" % [node, is_orphan])
	return orphans.find(node) != -1


func get_all_nodes_with_parents() -> Array:
	"""Returns an array with all BehNodes tracked by this tree, including its orphan trees.
	Returned array contains pairs: [node, parent]. If the node has no parent, the parent entry
	will be null."""
	var arr = []
	if has_roots():
		for root in roots:
			for node_parent_pair in root.get_all_children_with_parent():
				arr.push_back(node_parent_pair)
	if has_orphans():
		for orphan in orphans:
			for node_parent_pair in orphan.get_all_children_with_parent():
				arr.push_back(node_parent_pair)
	return arr


func get_all_nodes() -> Array[BehNode]:
	"""Returns an array with all BehNodes tracked by this tree, including its orphan trees."""
	var arr: Array[BehNode] = []
	if has_roots():
		for root in roots:
			for node in root.get_all_children():
				arr.push_back(node)
	if has_orphans():
		for orphan in orphans:
			for node in orphan.get_all_children():
				arr.push_back(node)
	return arr


func has_editor_offset(beh_node: BehNode) -> bool:
	var id = beh_node.try_get_stable_id()
	if id == null:
		push_warning("[BehTree] Can't has_editor_offset: BehNode lacks stable ID")
		return false
	else:
#		print("[BehTree] OK: has_editor_offset on BehNode with stable ID %s" % id)
		pass
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
#		print("[BehTree] OK: get_editor_offset on BehNode with stable ID %s" % id)
		pass
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
#	print("[BehTree] OK: set_editor_offset on BehNode with stable ID %s; arg was pos %s and get_editor_offset now returns pos %s for this node" % [
#		id, pos, get_editor_offset(beh_node)])


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
