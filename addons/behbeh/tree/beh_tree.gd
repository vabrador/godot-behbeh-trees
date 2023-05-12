@tool
@icon("res://addons/behbeh/icons/beh_tree.png")
class_name BehTree
extends Resource


const EDITOR_OFFSET_KEY: String = "ed_offset"


var root: BehNode = null


## Node metadata for in-tree or orphaned BehNodes. This includes "ed_offset", which tracks
## the node's in-editor tree position, if it exists.
var node_meta: Dictionary = {}


## Parent-less nodes that were added to this tree at some point. Usually used
## the authoring process, for newly-created nodes prior to formalizing them with
## a parent connection, or for nodes who were children of a recently-deleted node.
var orphans: Array[BehNode] = []


func is_empty() -> bool:
	"""Returns whether this tree contains any nodes. Includes orphans that may be in the tree."""
	return root == null && len(orphans) == 0
func has_root() -> bool:
	"""Returns whether this tree has a root node defined."""
	return root != null


func get_all_nodes() -> Array[BehNode]:
	"""Returns an array with all BehNodes tracked by this tree, INCLUDING its orphans."""
	var arr: Array[BehNode] = []
	if root != null:
		for tree_node in BehNode.get_all_children(root):
			arr.push_back(tree_node)
	for orphan in orphans:
		arr.push_back(orphan)
	return arr


func has_editor_offset(beh_node: BehNode) -> bool:
	var id = beh_node.get_instance_id()
	if node_meta == null: node_meta = {}
	if !node_meta.has(id): return false
	if !node_meta[id].has(EDITOR_OFFSET_KEY): return false
	if node_meta[id][EDITOR_OFFSET_KEY] == BehConst.UNSET_VEC: return false
	return true


func get_editor_offset(beh_node: BehNode) -> Vector2:
	var id = beh_node.get_instance_id()
	if node_meta == null: node_meta = {}
	if !node_meta.has(id): node_meta[id] = {}
	if !node_meta[id].has(EDITOR_OFFSET_KEY): node_meta[id][EDITOR_OFFSET_KEY] = BehConst.UNSET_VEC
	if node_meta[id][EDITOR_OFFSET_KEY] == BehConst.UNSET_VEC:
		return Vector2.ZERO
	return node_meta[id][EDITOR_OFFSET_KEY]


func set_editor_offset(beh_node: BehNode, pos: Vector2):
	var id = beh_node.get_instance_id()
	if node_meta == null: node_meta = {}
	if !node_meta.has(id): node_meta[id] = {}
	node_meta[id][EDITOR_OFFSET_KEY] = pos


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
