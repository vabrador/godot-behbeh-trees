@tool
class_name BehNodeASet
extends BehNodeXMultiChildren


var completed = null


# === Editor Overrides ===


func editor_get_name() -> String: return "Set"
func editor_get_color() -> Color: return Color.DEEP_SKY_BLUE


# === Overrides ===


func tick(dt: float, bb: Dictionary) -> BehConst.Status:
	"""Ticks children. Each child gets a tick until it resolves or errors. The set resolves once
	all children have reported a non-Busy status. After resolving, all children will be ticked
	once more."""

	# Initialization.
	if completed == null:
		completed = {}
	# Ensure completed tracking entries exist.
	for child in children:
		if !completed.has(child):
			completed[child] = false
	# Ensure completion tracking doesn't track nonexistent children.
	for tracked_child in completed.keys():
		if !children.any(func(c): return c == tracked_child):
			completed.erase(tracked_child)
	
	# Tick all behaviors.
	for c in range(len(children)):
		var beh = children[c]
		if !completed[beh]:
			if beh.tick(dt, bb) != BehConst.Status.Busy:
				completed[beh] = true
	
	var all_complete = true
	for c in range(len(children)):
		var beh = children[c]
		if !completed[beh]: all_complete = false
		if !all_complete: break
	if all_complete:
		# Reset completed.
		for c in completed.keys(): completed[c] = false
		return BehConst.Status.Resolved
	return BehConst.Status.Busy

