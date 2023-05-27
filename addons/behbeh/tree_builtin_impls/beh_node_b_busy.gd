@tool
class_name BehNodeBBusy
extends BehNode


## This leaf node always returns busy. Use as a Condition pathway to block 
## Sequence evaluation until a Condition is met.


# === Editor Overrides ===


func editor_get_name() -> String: return "Busy"
func editor_get_color() -> Color: return BehEditorNode.COLOR_TITLE_META
func editor_get_body_text() -> String:
	if self._editor_ref != null:
		var editor: BehTreeEditor = self._editor_ref
		var tree = editor.active_tree
		if tree != null:
			var parent = tree.get_node_parent(self)
			if parent != null:
				if parent is BehNodeASequence:
					return "Warning: Permanently blocks parent Sequence."
				if parent is BehNodeASet:
					return "Warning: Permanently blocks parent Set."
	return ""


# === Overrides ===


func tick(_dt: float, _bb: Dictionary) -> BehConst.Status:
	return BehConst.Status.Busy


