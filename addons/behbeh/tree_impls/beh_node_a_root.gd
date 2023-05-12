@tool
class_name BehNodeARoot
extends BehNode


@export var child: BehNode = null


# === Overrides ===


func get_is_root() -> bool: return true


func get_children() -> Array[BehNode]:
	var arr: Array[BehNode] = []
	if child != null: arr.push_back(child)
	return arr


func try_add_child(new_child: BehNode) -> bool:
	if child != null: return false # Don't overwrite.
	if new_child == self:
		push_error("[BehNodeARoot] Invalid operation: Add self as child.")
		return false
	print("[BehNodeARoot] try_add_child successfully added a child %s" % new_child)
	child = new_child
	child_added.emit(new_child)
	return true


# === Editor Overrides ===


func editor_get_name() -> String: return "Root Entry Point"
func editor_get_color() -> Color: return Color.MEDIUM_SPRING_GREEN


