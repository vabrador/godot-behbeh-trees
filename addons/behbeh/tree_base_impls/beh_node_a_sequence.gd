@tool
class_name BehNodeASequence
extends BehNodeXMultiChildren


# === Editor Overrides ===


func editor_get_name() -> String: return "Sequence"
func editor_get_color() -> Color: return BehEditorNode.COLOR_TITLE_META


# === Overrides ===


func get_does_child_order_matter() -> bool: return true


func tick(dt: float, bb: Dictionary) -> BehConst.Status:
	"""Ticks children. Fails if any ticked child fails. Returns successful once all children have
	ticked successfully, in sequence."""
	# Initialization.
	if idx == -1:
		idx = 0
	
	# Tick the current behavior.
	if len(children) > 0:
		var beh = children[idx]
		match beh.tick(dt, bb):
			BehConst.Status.Busy:
				pass
			BehConst.Status.Resolved:
				next_idx = idx + 1
			BehConst.Status.Failed:
				next_idx = idx + 1
				push_error("[BehNodeASequence] (tick) Child behavior beh tick Failed. Advancing.")
	if next_idx != -1:
		idx = next_idx
		next_idx = -1
	
	# Continue, or end-of-sequence.
	if idx == len(children):
		idx = -1
		return BehConst.Status.Resolved
	return BehConst.Status.Busy

