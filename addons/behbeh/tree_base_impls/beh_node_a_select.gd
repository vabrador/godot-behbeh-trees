@tool
class_name BehNodeASelect
extends BehNodeXMultiChildren


# === Editor Overrides ===


func editor_get_name() -> String: return "Select"
func editor_get_color() -> Color: return BehEditorNode.COLOR_TITLE_META


# === Overrides ===


func get_does_child_order_matter() -> bool: return true


func tick(dt: float, bb: Dictionary) -> BehConst.Status:
	"""Ticks children from the start of the list. If a child fails, the next child is ticked.
	Resolves a Failed if ALL ticked children fail. If any ONE child reports busy, reports busy and
	no other children are ticked that call. Resolves immediately ANY children resolve.
	
	Parent a Select a variety of Conditions to produce state-machine like behavior."""
	idx = 0
	
	# TODO: If a child reports Busy, that child should be ticked again until it doesn't report
	# busy.
	
	# Tick the current behavior.
	while idx < len(children):
		var beh = children[idx]
#		print("Select: Ticking beh %s" % beh)
		match beh.tick(dt, bb):
			BehConst.Status.Busy:
#				print("Select: Beh %s BUSY (halts Select)" % beh)
				return BehConst.Status.Busy
			BehConst.Status.Failed:
#				print("Select: Beh %s Failed (Select continues.)" % beh)
				next_idx = idx + 1
			BehConst.Status.Resolved:
#				print("Select: Beh %s RESOLVED (halts Select)" % beh)
				return BehConst.Status.Resolved
		if next_idx != -1:
			idx = next_idx
			next_idx = -1
	return BehConst.Status.Failed

