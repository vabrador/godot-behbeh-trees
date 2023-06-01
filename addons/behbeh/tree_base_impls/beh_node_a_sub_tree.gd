@tool
class_name BehNodeASubTree
extends BehNode


@export var subtree: BehTree = null
@export var label: String = ""


# === Editor Overrides ===


func editor_get_name() -> String: return "Subtree"
func editor_get_color() -> Color: return BehEditorNode.COLOR_TITLE_META
func editor_get_body_text() -> String:
	if subtree == null: return "(No subtree selected.)"
	if label != null:
		if len(label) > 0:
			return label
	var path = subtree.resource_path
	if path == null || len(path) == 0: return "(Some subtree)"
	if len(path) > 29:
		var begin6 = path.substr(0, 13)
		var end6 = path.substr(len(path) - 13)
		return "%s...%s" % [begin6, end6]
	return path


# === Overrides ===


func tick(dt: float, bb: Dictionary) -> BehConst.Status:
	if subtree == null:
		return BehConst.Status.Failed
	return subtree.tick(dt, bb)



