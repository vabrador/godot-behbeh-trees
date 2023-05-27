@tool
class_name BehNodeBRandomSelect
extends BehNodeXMultiChildren


var _keep_child = null


# === Editor Overrides ===


func editor_get_name() -> String: return "Select Random"
func editor_get_color() -> Color: return BehEditorNode.COLOR_TITLE_META


# === Overrides ===


func get_does_child_order_matter() -> bool: return true


func tick(dt: float, bb: Dictionary) -> BehConst.Status:
	"""Ticks a random child. As long as the chosen child is Busy, subsequent ticks
	will continue to tick that child."""
	
	if len(children) == 0:
		return BehConst.Status.Resolved
	
	# Roll index. Possibly consume _keep_child from the previous tick.
	idx = randi_range(0, len(children) - 1)
	if _keep_child != null:
		idx = children.find(func(c): return c == _keep_child)
		_keep_child = null # Consume it.
	if idx < 0 || idx >= len(children):
		idx = randi_range(0, len(children) - 1) # reroll
	if idx < 0 || idx >= len(children):
		push_error("[BehNodeBRandomSelect] Failed to roll a valid idx. len(children) was %s" % [
			len(children)])
		return BehConst.Status.Failed
	
	var beh = children[idx]
	if beh == null:
		push_error("[BehNodeBRandomSelect] Got null child for index %s" % idx)
		return BehConst.Status.Failed
	var status = beh.tick(dt, bb)
	match status:
		BehConst.Status.Busy:
			_keep_child = beh
			return BehConst.Status.Busy
		BehConst.Status.Failed:
			return BehConst.Status.Resolved
		BehConst.Status.Resolved:
			return BehConst.Status.Resolved
		_:
			push_error("Unhandled %s" % status)
			return BehConst.Status.Failed
	pass






