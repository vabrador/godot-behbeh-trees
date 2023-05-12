@tool
class_name BehNode
extends Resource


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
	return BehConst.Status.Success


func get_is_root() -> bool:
	"""If this node is a root, it is ticked by the BehTree that contains it. It is
	also tracked by the BehTree as a root and not an orphan. (Orphans display with
	warnings because they are tracked by the tree but are never ticked.)"""
	return false


func get_children() -> Array[BehNode]:
	"""If this BehNode executes other BehNode that it owns, return those BehNodes here."""
	# TODO: Refactor to get_children overrides
	if self is BehNodeSequence:
		return self.seq as Array[BehNode]
	if self is BehNodeSet:
		return self.set_behs as Array[BehNode]
	var empty_arr: Array[BehNode] = []
	return empty_arr


func try_add_child(new_child: BehNode) -> bool:
	"""Overwrite to add a new child of this node if it accepts children. Return true
	if the child was added, or false if it could not be added for any reason.
	If you add a child, be sure to emit child_added() with the new child."""
	if new_child == self:
		push_error("[BehNode] Invalid operation: Add self as child.")
		return false
	return false


# === Editor Overrides ===


func editor_get_name() -> String:
	if self.script == null: return "Unknown Node"
	return BehUtils.get_best_guess_script_class_name(self.script)


func editor_get_color() -> Color:return Color.ANTIQUE_WHITE


# === Utility Funcs ===


func get_all_children(include_self: bool = true) -> Array[BehNode]:
	"""Walks the node tree and returns a depth-first array. Includes self by default.
	Checks for loops and will push an error and halt iteration if one is detected."""
	var all_children: Array[BehNode] = []
	var to_visit: Array[BehNode] = [self]
	while len(to_visit) > 0:
		var next = to_visit.pop_front()
		all_children.push_back(next)
		var children = next.get_children()
		children.reverse()
		for child in children:
			to_visit.push_front(child)
	return all_children


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
	print("[BehNode] Node inst %s generated stable id %s" % [beh_node.get_instance_id(), stable_id])
	return stable_id



# ======
# GRAVEYARD
# ===



#func get_is_leaf() -> bool:
#	"""Returns whether this BehNode is allowed to have children (e.g. it defers behavior to
#	other nodes). Overwrite this for impls. Non-leaf nodes are allowed to have no children as an
#	edge/initialization case."""
#	return true
#
#
#func get_children() -> Array[BehNode]:
#	"""Returns the direct children of this BehNode. Overwrite this if your BehNode is not a leaf."""
#	var arr: Array[BehNode] = []
#	return arrtions to alter the behavior of a node in the BehBeh Tree Editor.
#
#
#func get_editor_category() -> String:
#	"""Gets the category to organize the NodeBeh into in the 'Add Node' context menu."""
#	return "Hidden" # for now literally just a folder called Hidden


## === Iteration ===
#
#
#func get_all_children(include_self: bool = true) -> Array[BehNode]:
#	"""Walks the node tree and returns a depth-first array. Includes self by default.
#	Checks for loops and will push an error and halt iteration if one is detected."""
#	var all_children: Array[BehNode] = [self]
#	var to_visit: Array[BehNode] = [self]
#	while len(to_visit) > 0:
#		var next = to_visit.pop_front()
#		all_children.push_back(next)
#		for child in next.get_children().reverse():
#			to_visit.push_front(child)
#	return all_children

