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


# === Base Funcs ===
# Override these functions to alter the functionality of a NodeBeh implementation.


func tick(dt: float, bb: Dictionary) -> BehConst.Status:
	"""Main tick function for BehNodes. Overwrite this to implement a new BehNode."""
	return BehConst.Status.Success


# === Vars ===


# (none so far)


# === Static Funcs ===

static func get_children(beh_node: BehNode) -> Array[BehNode]:
	if beh_node is BehNodeSequence:
		return beh_node.seq
	if beh_node is BehNodeSet:
		return beh_node.set_behs as Array[BehNode]
	var empty_arr: Array[BehNode] = []
	return empty_arr


static func get_all_children(start: BehNode, include_start: bool = true) -> Array[BehNode]:
	"""Walks the node tree and returns a depth-first array. Includes self by default.
	Checks for loops and will push an error and halt iteration if one is detected."""
	var all_children: Array[BehNode] = [start]
	var to_visit: Array[BehNode] = [start]
	while len(to_visit) > 0:
		var next = to_visit.pop_front()
		all_children.push_back(next)
		var children = BehNode.get_children(next)
		children.reverse()
		for child in children:
			to_visit.push_front(child)
	return all_children


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

