@tool
class_name BehNodeXMultiChildren
extends BehNode


## A base class for BehNodeASequence and BehNodeASet that handles having multiple children and
## sorting those children by their editor positions.
##
## Supports an arbitrary number of children.


@export var children: Array[BehNode] = []


var idx := -1
var next_idx := -1


static func dprint(s: String): BehTreeEditor.dprint(s)


# === Editor Overrides ===


func editor_get_name() -> String: return "(Please use Sequence or Set)"


# === Overrides ===


func tick(dt: float, bb: Dictionary) -> BehConst.Status:
	push_warning("[BehNodeXMultiChildren] Warning: Default tick impl. Override this.")
	return BehConst.Status.Resolved


func clone(deep: bool) -> BehNode:
	var dup = super.clone(deep) as BehNodeXMultiChildren
	var dup_children: Array[BehNode] = []
	if !deep:
		for src_child in self.children:
			dup_children.push_back(src_child)
	else: # deep clone
		for src_child in self.children:
			var dup_child = src_child.clone(deep)
			dup_children.push_back(dup_child)
	dup.children = dup_children
	return dup


func get_is_root() -> bool: return false


func get_children() -> Array[BehNode]:
	return children


func get_can_add_child() -> bool: return true


func try_add_child(new_child: BehNode) -> bool:
	children.push_back(new_child)
	dprint("[%s] try_add_child successfully added a child %s" % [self, new_child])
	child_added.emit(new_child)
	return true


func remove_child(child_to_remove: BehNode) -> bool:
	var found_idx = children.find(child_to_remove)
	if found_idx == -1:
		dprint("[%s] remove_child returning false. Not found: %s" % [self, child_to_remove])
		return false
	children.remove_at(found_idx)
	child_removed.emit(child_to_remove)
	dprint("[%s] remove_child successfully removed child %s" % [self, child_to_remove])
	return true


