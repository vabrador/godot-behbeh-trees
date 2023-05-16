@tool
class_name BehNodeARoot
extends BehNode


@export var child: BehNode = null


# === Overrides ===


func tick(dt: float, bb: Dictionary) -> BehConst.Status:
	if child == null:
		return BehConst.Status.Success
	return child.tick(dt, bb)


func clone(deep: bool) -> BehNode:
	var dup = super.clone(deep)
	if self.child != null && deep:
		var dup_child = child.clone(deep)
		dup.child = dup_child
	return dup


func get_is_root() -> bool: return true


func get_children() -> Array[BehNode]:
	var arr: Array[BehNode] = []
	if child != null: arr.push_back(child)
	return arr


func get_can_add_child() -> bool: return true


func try_add_child(new_child: BehNode) -> bool:
	if child != null: return false # Don't overwrite.
	if new_child == self:
		push_error("[BehNodeARoot] Invalid operation: Add self as child.")
		return false
	print("[BehNodeARoot] try_add_child successfully added a child %s" % new_child)
	child = new_child
	child_added.emit(new_child)
	return true


func remove_child(child_to_remove: BehNode) -> bool:
	if child == null: return false # No child to remove.
	if self.child != child_to_remove: return false # Non-matching child.
	self.child = null
	child_removed.emit(self.child)
	return true


# === Editor Overrides ===


func editor_get_name() -> String: return "Root Entry Point"
func editor_get_color() -> Color: return Color.MEDIUM_SPRING_GREEN


