@tool
@icon("res://addons/behbeh/icons/beh_tree.png")
class_name BehTree
extends Resource


static func dprintd(s: String):
	BehTreeEditor.dprintd(s)


const EDITOR_OFFSET_KEY: String = "ed_offset"


# Exports - Not just exposed in the Inspector, but this also determines what's saved!

## BehTrees can have multiple roots, which offer multiple entry points that update
## simultaneously.
@export var roots: Array[BehNode] = []

## Parent-less nodes that are NOT roots that were added to this tree at some point. Usually used
## the authoring process, for newly-created nodes prior to formalizing them with
## a parent connection, or for nodes who were children of a recently-deleted node.
## Each orphan can have children! Orphan status simply implies they are NEVER called by the
## BehTree. All of an orphan's children are also orphans, but are not tracked in THIS array,
## as they are already referenced via parent -> children.
@export var orphans: Array[BehNode] = []

## Key: BehNode stable_id. Node metadata for in-tree or orphaned BehNodes.
## This includes "ed_offset", which tracks the node's in-editor tree position, if it exists.
@export var node_meta: Dictionary = {}


var _subscribed_nodes: Dictionary = {}
var _ignore_next_orphan_operation: BehNode = null # Set to a BehNode to ignore that node's orphaning once.
var _initialized := false


## Invoked whenever an operation changes the structure of the BehTree.
signal tree_changed()


# === Runtime API ===
#
# Note the tree is NOT EXPECTED to change at runtime. Modifying the tree at runtime will probably
# cause unknown and silent errors.

var completed = null


func tick(dt: float, bb: Dictionary) -> BehConst.Status:
	"""BehTrees tick every Entry Point (aka 'root') that they track. Orphans may be tracked, but as
	they by-definition are not roots/entry points, they do not get ticked.
	
	The tree behaves like a set behavior; each entry point is ticked at the same time. The entire tree
	does not resolve until every entry-point sub-tree resolves."""
	
	# Initialization.
	if completed == null:
		completed = {}
	# Ensure completed tracking entries exist.
	for root in roots:
		if !completed.has(root):
			completed[root] = false
	# Ensure completion tracking doesn't track nonexistent children.
	for tracked_root in completed.keys():
		if !roots.any(func(c): return c == tracked_root):
			completed.erase(tracked_root)
	
	# Tick all behaviors.
	for r in range(len(roots)):
		var beh = roots[r]
		if !completed[beh]:
			if beh.tick(dt, bb) != BehConst.Status.Busy:
				completed[beh] = true
	
	var all_complete = true
	for r in range(len(roots)):
		var beh = roots[r]
		if !completed[beh]: all_complete = false
		if !all_complete: break
	if all_complete:
		# Reset completed.
		for r in completed.keys(): completed[r] = false
		return BehConst.Status.Resolved
	return BehConst.Status.Busy



# === Edit-time API ===


func initialize():
	"""Call this before performing operations on the tree, specifically when loading a new active_tree
	into the BehTreeEditor. This allows the tree to subscribe to existing node callbacks."""
	if _initialized:
		return
	var all_nodes = get_all_nodes()
	dprintd("[BehTree] initialize called; subscribing to %s known nodes." % len(all_nodes))
	for node in all_nodes: subscribe_node_signals(node)
	_initialized = true


func confirm_initialized(silent: bool = false) -> bool:
	if !_initialized:
		if !silent: push_warning("[BehTree] Not initialized! Please call initialize() before calling other operations.")
		initialize()
		return true
	return true


func subscribe_node_signals(beh: BehNode):
	if _subscribed_nodes.has(beh): return
	dprintd("[BehTree] (subscribe_node_signals) Subscribing to signals for %s" % beh)
	beh.child_added.connect(func(new_child): on_child_added(beh, new_child))
	beh.child_removed.connect(func(old_child): on_child_removed(beh, old_child))
	_subscribed_nodes[beh] = true


func on_child_added(par_beh: BehNode, child_beh: BehNode):
	confirm_initialized()
	dprintd("[BehTree] (on_child_added) Signal: child_added: %s -> %s" % [par_beh, child_beh])
	# New child loses root-orphan status (tree no longer needs to track it).
	var found_in_root_orphans = find_node_in_orphans(child_beh, true)
	if found_in_root_orphans[0] != -1:
		var orphan_tree_idx = found_in_root_orphans[0]
		var parent_node = found_in_root_orphans[1]
		var orphan_node = found_in_root_orphans[2]
		if parent_node != null:
			push_error("[BehTree] (on_child_added) Tried to find child_beh as root only but got returned with a non-null parent unexpectedly. Returned parent %s -> child %s" % [
				parent_node, orphan_node])
		else:
			orphans.remove_at(orphan_tree_idx) # Remove root orphan.
		tree_changed.emit()
	else:
		push_error("[BehTree] (on_child_added) Got added child but orphan_id not found in orphan roots. Child: %s" % [
			child_beh])
	pass


func on_child_removed(par_beh: BehNode, child_beh: BehNode):
	confirm_initialized()
	dprintd("[BehTree] (on_child_removed) Signal: child_removed: %s -> %s" % [par_beh, child_beh])
	var will_ignore_orphaning = false
	if _ignore_next_orphan_operation != null:
		if _ignore_next_orphan_operation == child_beh:
			# Possibly ignore the orphaning, consuming the ignore.
			_ignore_next_orphan_operation = null
			will_ignore_orphaning = true
			dprintd("[BehTree] (on_child_removed) _ignore_next_orphan_operation CONSUMED")
		else:
			# Do NOT consume the next-orphan operation.
#			push_error("[BehTree] (on_child_removed) Invalid use of _ignore_next_orphan_operation, expected to ignore an orphaning for %s but child %s was just reported as removed." % [
#				_ignore_next_orphan_operation, child_beh])
#			_ignore_next_orphan_operation = null
			dprintd("[BehTree] (on_child_removed) NOT consuming _ignore_next_orphan_operation. Removed child was %s, but _ignore_next_orphan_operation target is %s" % [
				child_beh, _ignore_next_orphan_operation])
	if !will_ignore_orphaning:
		# New child gains orphan status (tree must track it).
		# All of this child's children are also orphans but are tracked via the child
		# relationship of the top-level orphan.
		dprintd("[BehTree] (on_child_removed) ORPHANING child: %s" % child_beh)
		_push_orphan(child_beh)
#		if !get_is_orphan(child_beh): # Might already be an orphan b/c it was child-of-orphan
#			dprintd("[BehTree] (on_child_removed) ORPHANING child: %s" % child_beh)
#			_push_orphan(child_beh)
#		else:
#			dprintd("[BehTree] (on_child_removed) NOT orphaning already-orphan-list child: %s" % child_beh)
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
	confirm_initialized()
	dprintd("[BehTree] Got add_node: %s" % node)
	if node.get_is_root():
		_push_root(node)
#		roots.push_back(node) # TODO: delete
	else:
		_push_orphan(node)
#		orphans.push_back(node) # TODO deleteme
	subscribe_node_signals(node)


func _push_root(node: BehNode):
	"""Adds a node to the roots list. Confirms that the node is not ALREADY in a root tree,
	which would be an error."""
	dprintd("[BehTree] Got _push_root: %s" % node)
	var node_in_roots = find_node_in_roots(node)
	if node_in_roots[0] != -1:
		push_error("[BehTree] (_push_root) Node was already tracked by a root tree! Node: %s" % node)
	else:
		dprintd("[BehTree] (_push_orphan) Newly tracked root: %s" % node)
		roots.push_back(node)


func _push_orphan(node: BehNode):
	"""Adds a node to the orphans list. Confirms that the node is not ALREADY in an orphan tree,
	which would be an error."""
	var node_in_orphans = find_node_in_orphans(node)
	if node_in_orphans[0] != -1:
		push_error("[BehTree] (_push_orphan) Node was already tracked by an orphan tree! Node: %s" % node)
	else:
		dprintd("[BehTree] (_push_orphan) Newly tracked orphan: %s" % node)
		orphans.push_back(node)


func remove_node(node: BehNode) -> BehNode:
	"""Removes a node from the tree. If the BehNode was found and removed, it is returned;
	otherwise if the BehNode was not found in the tree, this func returns null."""
	confirm_initialized()
	var del_node = null
	
	dprintd("[BehTree] Got remove_node: %s" % node)
	var found_in_roots = find_node_in_roots(node)
	if found_in_roots[0] != -1:
		# Remove from tree. This will create orphans if the node has children.
		var root_idx = found_in_roots[0]
		var node_parent = found_in_roots[1]
		var found_node = found_in_roots[2]
		del_node = found_node
		dprintd("[BehTree] (remove_node) Found node to remove. Calling _inner_remove_node with roots list ...")
		if node_parent != null:
			# Ignore orphaning of found_node from its parent, as we're going to delete it
			_ignore_next_orphan_operation = found_node
			dprintd("[BehTree] (remove_node) Had parent, so _ignore_next_orphan_operation SET TO: %s" % _ignore_next_orphan_operation)
		_inner_remove_node_from_tree(found_node, node_parent, self.roots, root_idx, self.orphans)
	var found_in_orphans = find_node_in_orphans(node)
	if found_in_orphans[0] != -1:
		var orphan_root_idx = found_in_orphans[0]
		var node_parent = found_in_orphans[1]
		var found_node = found_in_orphans[2]
		del_node = found_node
		dprintd("[BehTree] (remove_node) Found node to remove. Calling _inner_remove_node with orphans list ...")
		if node_parent != null:
			# Ignore orphaning of found_node from its parent, as we're going to delete it
			_ignore_next_orphan_operation = found_node
			dprintd("[BehTree] (remove_node) Had parent, so _ignore_next_orphan_operation SET TO: %s" % _ignore_next_orphan_operation)
		_inner_remove_node_from_tree(found_node, node_parent, self.orphans, orphan_root_idx, self.orphans)
	
	if del_node == null:
		dprintd("[BehTree] (remove_node) Did not find node %s in root trees nor orphan trees." % node)
		return null
	# Before returning, Also remove node_meta information associated with this node.
	var del_node_id = del_node.try_get_stable_id()
	if del_node_id == null:
		push_error("[BehTree] (_inner_remove_node_from_tree) Missing stable_id for node-being-deleted %s" %
			del_node)
	else:
		node_meta.erase(del_node_id)
	return del_node


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
	dprintd("[BehTree] (_inner_remove_node_from_tree) Remove tree_idx %s, node_parent %s, found_node %s" % [
		tree_idx, node_parent, found_node])

	# Prior to children -- if necessary remove the found node as a child from its OWN parent.
	if node_parent != null:
		dprintd("[BehTree] (_inner_remove_node_from_tree) Removing NON-TREE-root del-node from own parent ...")
		# The node is NOT itself a tree root, so just remove it as a child of its parent.
		if !node_parent.remove_child(found_node):
			push_warning("[BehTree] (_inner_remove_node_from_tree) Node %s reported failed to remove child %s (child did not exist)" % [node_parent, found_node])
	else:
		# The node itself IS a tree root, so remove it from the trees list
		dprintd("[BehTree] (_inner_remove_node_from_tree) Removing tree idx %s" % tree_idx)
		from_trees.remove_at(tree_idx)
	
	# The node's children are now root orphans.
	dprintd("[BehTree] (_inner_remove_node_from_tree) Removing children of del-node if any ...")
	var children_copy = found_node.get_children().duplicate(false)
	# Subtle: We COPY the children list so we don't modify-while-iterating.
	dprintd("[BehTree] (_inner_remove_node_from_tree) Node had %s children ..." % len(children_copy))
	for child in children_copy:
		dprintd("[BehTree] (_inner_remove_node_from_tree) Removing child %s ..." % child)
		if !found_node.remove_child(child):
			push_warning("[BehTree] (_inner_remove_node_from_tree) Node %s reported failed to remove child %s (child did not exist)" % [found_node, child])
		# Child is now an orphan. No need to orphan here; signal for removing children will take care of this!
#		push_orphans_list.push_back(child)
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
	confirm_initialized()
	dprintd("[BehTree] (try_remove_parent_child_relationship) Wants to remove %s -> child %s" % [
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
	if found_in_roots[0] != -1 && found_in_orphans[0] != -1:
		push_error("[BehTree] (try_remove_parent_child_relationship) Node %s was found in both roots and orphans. Node: %s" % parent)
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
			dprintd("[BehTree] (try_remove_parent_child_relationship) Calling parent.remove_child on parent %s ..." % parent)
			if ignore_orphan_update:
				# Will get a signal from the remove_child op. To ignore orphaning, we set a flag
				# for the signal callback to consume instead of orphaning.
				_ignore_next_orphan_operation = child
				dprintd("[BehTree] (try_remove_parent_child_relationship) _ignore_next_orphan_operation SET TO: %s" % _ignore_next_orphan_operation)
			if !parent.remove_child(child):
				push_error("[BehTree] (try_remove_parent_child_relationship) remove_child() failed for parent %s -> child %s" % [
					parent, child])
				return false
			else:
				dprintd("[BehTree] (try_remove_parent_child_relationship) Removed child %s" % child)
				# Note: NO NEED to orphan here; GraphNode subscription of remove_child
				# handles the orphaning operation! So this would be a duplicate.
#				# Finalize orphaning the child.
#				if child_to_orphan != null:
#					self.orphans.push_back(child_to_orphan)
#					dprintd("[BehTree] (try_remove_parent_child_relationship) Finished. Pushed child to orphans list. Child: %s" % child)
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
		dprintd("[BehTree] (find_node_in_tree_list) NOT FOUND")
	else:
		dprintd("[BehTree] (find_node_in_tree_list) Returning found in given tree list: %s" % [[root_idx, parent, node]])
	if root_idx == -1: # Not found.
		return [-1, null, null]
	return [root_idx, parent, node]
	


func find_node_in_roots(node: BehNode) -> Array:
	"""Searches for the node in the 'roots' trees. Returns [root_idx, parent_node, node] if found.
	If the node is itself a root, parent_node will be null. Returns [-1, null, null] if not found."""
	dprintd("[BehTree] (find_node_in_roots) arg node: %s; calling find_node_in_tree_list with self.roots" % node)
	return find_node_in_tree_list(node, self.roots)


func find_node_in_orphans(node: BehNode, search_roots_only: bool = false) -> Array:
	"""Searches for the node in the 'orphans' trees. Returns [orphan_idx, parent_node, node] if found.
	If the node is itself a root orphan, parent_node will be null. Returns [-1, null, null] if not found."""
	if search_roots_only:
		dprintd("[BehTree] (find_node_in_orphans) arg node: %s; searching self.orphans roots ONLY" % node)
		var found_orphan_idx = -1
		var o = 0
		var node_to_return = null
		for orphan_root in self.orphans:
			if orphan_root == node:
				node_to_return = orphan_root
				found_orphan_idx = o
				break
			o += 1
		return [found_orphan_idx, null, node_to_return]
	else:
		dprintd("[BehTree] (find_node_in_orphans) arg node: %s; calling find_node_in_tree_list with self.orphans" % node)
		return find_node_in_tree_list(node, self.orphans)


func validate_roots_and_orphans() -> bool:
	"""Confirms that orphans are not roots and roots are not orphans. If this validation
	caused the tree to change its state, returns true."""
	dprintd("[BehTree] validate_roots_and_orphans() called.")
	confirm_initialized()
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
		_push_orphan(new_orphan)
#		orphans.push_back(new_orphan)
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
#		roots.push_back(new_root)
		_push_root(new_root)
	if changed_ct > 0:
		dprintd("[BehTree] (validate_roots_and_orphans) Counted %s changes between roots & orphans." % changed_ct)
	var any_changed = changed_ct > 0
	return any_changed


func validate_single_parents() -> bool:
	"""Confirms that every child has a single parent. If more than one parent is detected for a child,
	a warning is pushed and the relationship is fixed (only the first detected parent retains
	parenthood for a given child, and returns true. Returns false if no change was necessary."""
	dprintd("[BehTree] validate_single_parents() called.")
	confirm_initialized()
	var changes = []
#	var parent = {}
#	var addl_parents = []
#	var child = {}
	
	var child_parents = {}
	for child_parent_pair in get_all_nodes_with_parents():
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
	dprintd("[BehTree] (validate_single_parents) Processing remove_parent_child for %s desired changes" % len(changes))
	for change in changes:
		dprintd("[BehTree] (validate_single_parents) Processing change: %s" % change.msg)
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
	dprintd("[BehTree] Got get_is_orphan: %s" % node)
	var is_in_roots = find_node_in_roots(node)[0] != -1
	var is_in_orphans = find_node_in_orphans(node)[0] != -1
	if !is_in_roots && !is_in_orphans:
		push_error("[BehTree] (get_is_orphan) Node is neither in roots nor orphans: %s" % node)
		# This error is occurring at unknown times and contexts, so print a stack trace so we can
		# dig on it when it happens again.
		print("[BehTree] (get_is_orphan) For error, printing stack trace ...")
		print_stack() # TODO: Determine how and when this function is called
		return false
	if is_in_roots && is_in_orphans:
		push_error("[BehTree] (get_is_orphan) Invalid state: Node is in both roots and orphans: %s" % node)
		return true
	if is_in_roots:
		return false
	if is_in_orphans:
		return true
#	dprintd("[BehTree] is_orphan for node %s ? %s" % [node, is_orphan])
	return false


func get_is_root(node: BehNode) -> bool:
	var node_in_roots = find_node_in_roots(node)
	if node_in_roots[0] != -1 && node_in_roots[1] == null: # In root tree & no parent
		return true
	return false


func get_child_index(node: BehNode, allow_root_tree_idx: bool = false):
	"""Returns the index of the argument BehNode in its parent's children. Returns -1 if the node
	is not tracked by this tree or if it has no parent. Optionally, can return the root index
	of a root if the passed node is a root, if allow_root_tree_idx is passed as true."""
#	print("[BehTree] (get_child_index) Called for node %s." % node)
	var parent = get_node_parent(node)
	if parent != null:
#		print("[BehTree] (get_child_index) Node's parent is %s." % parent)
		var p_children = parent.get_children()
		for c in range(len(p_children)):
			var child = p_children[c]
#			print("[BehTree] (get_child_index) Considering child @ %s: %s..." % [child, c])
			if child == node:
#				print("[BehTree] (get_child_index) Match, will return %s" % c)
				return c
	if parent == null && allow_root_tree_idx:
		var found_in_roots = find_node_in_roots(node) # [root_idx, parent_node, node]
		if found_in_roots[0] != -1:
			return found_in_roots[0] # Return root index if allow_root_tree_idx is passed.
	return -1


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


func contains(beh: BehNode) -> bool:
	"""Returns whether this tree tracks the argument node."""
	if beh == null: return false
	var all_nodes = get_all_nodes()
	for node in all_nodes:
		if beh == node: return true
	return false


func get_node_parent(beh: BehNode) -> Variant:
	"""Returns the BehNode parent of the argument BehNode or null if the node has
	no parent (is a root or a root orphan). Also returns null if the argument node is not
	tracked by this tree."""
	dprintd("[BehTree] (get_node_parent) Called for beh %s." % beh)
	var root_found = find_node_in_roots(beh)
	if root_found[0] != -1:
		return root_found[1]
	var orphan_found = find_node_in_orphans(beh)
	if orphan_found[0] != -1:
		return orphan_found[1]
	return null


func get_parent_node(beh: BehNode) -> Variant:
	"""Same as get_node_parent."""
	return get_node_parent(beh)


func has_parent_child_relation(parent: BehNode, child: BehNode) -> bool:
	"""Returns whether the argument parent is the parent of the argument child in this tree."""
	var child_parent = get_node_parent(child)
	if child_parent == null: return false
	if child_parent == parent: return true
	return false


func has_editor_offset(beh_node: BehNode) -> bool:
	var id = beh_node.try_get_stable_id()
	if id == null:
		push_warning("[BehTree] Can't has_editor_offset: BehNode lacks stable ID")
		return false
	else:
#		dprintd("[BehTree] OK: has_editor_offset on BehNode with stable ID %s" % id)
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
#		dprintd("[BehTree] OK: get_editor_offset on BehNode with stable ID %s" % id)
		pass
	if node_meta == null: node_meta = {}
	if !node_meta.has(id): node_meta[id] = {}
	if !node_meta[id].has(EDITOR_OFFSET_KEY): node_meta[id][EDITOR_OFFSET_KEY] = BehConst.UNSET_VEC
	if node_meta[id][EDITOR_OFFSET_KEY] == BehConst.UNSET_VEC:
		return Vector2.ZERO
	return node_meta[id][EDITOR_OFFSET_KEY]


func get_editor_offset_or(beh_node: BehNode, or_pos: Vector2) -> Vector2:
	var id = beh_node.try_get_stable_id()
	if id == null:
		return or_pos
	if !has_editor_offset(beh_node):
		return or_pos
	return get_editor_offset(beh_node)


func set_editor_offset(beh_node: BehNode, pos: Vector2):
	var id = beh_node.try_get_stable_id()
	if id == null:
		push_warning("[BehTree] Can't set_editor_offset: BehNode lacks stable ID")
		return
#	dprintd("[BehTree] == set_editor_offset volatility test ==")
#	dprintd("[BehTree] beh_node stable_id = %s" % id)
#	dprintd("[BehTree] beh_node resource_path = %s" % beh_node.resource_path)
#	dprintd("[BehTree] beh_node resource_name = %s" % beh_node.resource_name)
#	dprintd("set_editor_offset: Setting beh_node id %s pos to %s" % [id, pos])
	if node_meta == null: node_meta = {}
	if !node_meta.has(id): node_meta[id] = {}
	node_meta[id][EDITOR_OFFSET_KEY] = pos
#	dprintd("[BehTree] OK: set_editor_offset on BehNode with stable ID %s; arg was pos %s and get_editor_offset now returns pos %s for this node" % [
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
