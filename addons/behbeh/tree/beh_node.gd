@tool
class_name BehNode
extends Resource


static func dprintd(s: String): BehTreeEditor.dprintd(s)


## The base class for all BehTree behavior nodes. Counter-intuitively, it's a Resource
## instead of a Node.
##
## Due to @tool versus non-@tool script constraints, metadata for authoring BehNodes
## such as "editor position" and "edit-time children" can't be specified in BehNode
## implementations themselves without REQUIRING all implementors to be @tools.
## This isn't desired, so I have to find an alternative solution.


signal child_added(child: BehNode)
signal child_removed(former_child: BehNode)


# === Vars ===


# (none so far)


# === Override Funcs ===
# Override these functions to alter the functionality of a NodeBeh implementation.


func tick(dt: float, bb: Dictionary) -> BehConst.Status:
	"""Main tick function for BehNodes. Overwrite this to implement a new BehNode."""
	return BehConst.Status.Resolved


func clone(also_clone_children: bool) -> BehNode:
	"""Clone implementation for this BehNode. Defaults to duplicate(), but be careful with
	BehNodes that reference other nodes, which may need deep clone calls.
	
	The 'also_clone_children' parameter is passed as false when cloning via the authoring
	editor interface so that only selected children are cloned. Cloning children is handled
	in this case by the editor logic itself. At runtime, also_clone_children is usually passed
	as true so that the tree can be easily duplicated for e.g. duplicate actors.
	
	Call super.clone() in implementations because it has logic related to stable_id generation."""
	dprintd("[BehNode] clone(): OG stable id (res name) was: %s" % self.resource_name)
	var duplicated: BehNode = self.duplicate(false) as BehNode
	duplicated.resource_path = ""
	duplicated.resource_name = ""
	return duplicated


func get_is_root() -> bool:
	"""If this node is a root, it is ticked by the BehTree that contains it. It is
	also tracked by the BehTree as a root and not an orphan. (Orphans display with
	warnings because they are tracked by the tree but are never ticked.)"""
	return false


func get_children() -> Array[BehNode]:
	"""If this BehNode executes other BehNode that it owns, return those BehNodes here.
	It's actually IMPORTANT that this IS the backing array of children for the node! Because
	the return value is sometimes sorted by the BehTreeEditor, so that children are iterated
	according to their visual order (top to bottom, left to right)."""
	# TODO: Refactor to get_children overrides
	if self is BehNodeASequence:
		return self.seq as Array[BehNode]
	if self is BehNodeASet:
		return self.set_behs as Array[BehNode]
	var empty_arr: Array[BehNode] = []
	return empty_arr


func get_can_add_child() -> bool:
	"""Overwrite to allow this node to accept try_add_child calls."""
	return false


func try_add_child(new_child: BehNode) -> bool:
	"""Overwrite to add a new child of this node if it accepts children. Return true
	if the child was added, or false if it could not be added for any reason.
	If you add a child, be sure to emit child_added() with the new child."""
	if new_child == self:
		push_error("[BehNode] Invalid operation: Add self as child.")
		return false
	return false


func remove_child(child_to_remove: BehNode) -> bool:
	"""Removes the specified child from this node. Implementers cannot prevent the removal. The
	return should be true if the child existed and was removed; false if the child already did not
	exist."""
	if child_to_remove == self:
		push_error("[BehNode] Invalid operation: Remove self as child.")
		return false
	# Default BehNode can't have children so return false.
	return false


# === Editor Overrides ===


func editor_get_name() -> String:
	if self.script == null: return "Unknown Node"
	var best_guess = BehUtils.get_best_guess_script_class_name(self.script)
	if best_guess == "BehNode":
		return "BehNode (No-Op)"
	return best_guess


func editor_get_color() -> Color: return Color.ANTIQUE_WHITE


func editor_get_body_text() -> String: return ""


# === Built-in Overrides ===


func _to_string() -> String:
	var stable_id = try_get_stable_id()
	if stable_id == null:
		var inst_id = self.get_instance_id()
		var inst_id_str = str(inst_id)
		return "[BehNode|NoStableId|Inst_..%s]" % inst_id_str.substr(len(inst_id_str) - 5)
	var stable_id_str = str(stable_id)
	return "[BehNode|..%s]" % stable_id_str.substr(len(stable_id_str) - 5)


# === Utility Funcs ===


func has_stable_id() -> bool:
	var stable_id = try_get_stable_id()
	if stable_id == null: return false
	return true


func try_get_stable_id() -> Variant:
	"""Returns null if the operation failed. BehNode must have a resource_path to get a stable ID.
	Otherwise returns a StringName with the stable ID."""
	
	if self.resource_name == null || self.resource_name == "": # Generate stable ID.
		var new_stab_id = try_generate_stable_id(self)
		if new_stab_id == null:
#			push_error("Failed to get stable ID!")
			return null
		self.resource_name = new_stab_id
	return StringName(self.resource_name)


static func try_generate_stable_id(beh_node: BehNode) -> Variant:
	"""Returns null or String. (Null only if failed.)"""
	var og_path = beh_node.resource_path
	if og_path == "":
#		push_error("Can't generate a stable ID for beh_node %s; lacks resource_path" % beh_node.get_instance_id())
		return null
	var og_inst_id = beh_node.get_instance_id()
	var stable_id = "BEHNODE__%s__%s" % [og_path, og_inst_id]
	dprintd("[BehNode] Node inst %s generated stable id %s" % [beh_node.get_instance_id(), stable_id])
	return stable_id


func get_all_children(include_self: bool = true) -> Array[BehNode]:
	"""Walks the node tree and returns a depth-first array. Includes self by default.
	Checks for loops and will push an error and halt iteration if one is detected."""
	var all_children: Array[BehNode] = []
	var to_visit: Array[BehNode] = [self]
	while len(to_visit) > 0:
		var next = to_visit.pop_front()
		all_children.push_back(next)
		var children_copy = next.get_children().duplicate()
		children_copy.reverse() # Be careful NOT to reverse the original child array!
		for child in children_copy:
			to_visit.push_front(child)
	return all_children


func get_all_children_with_parent(include_self: bool = true) -> Array:
	"""As get_all_children but returns [node, parent] pairs. If self is a root, parent is null."""
	var all_pairs = []
	var to_visit = [[self, null]]
	while len(to_visit) > 0:
		var curr_pair = to_visit.pop_front()
		all_pairs.push_back(curr_pair)
		var curr_child = curr_pair[0]
#		var curr_parent = curr_pair[1]
		var child_children_copy = curr_child.get_children().duplicate()
		child_children_copy.reverse() # Be careful NOT to reverse the original child array!
		for child_child in child_children_copy:
			to_visit.push_front([child_child, curr_child])
	return all_pairs


