@tool
class_name BehNodeBSelectRandom
extends BehNodeXMultiChildren


enum RandomMode { Uniform, Weighted }
## If uniform, randomly selects a child to tick. If Weighted, uses the 'weights'
## property to pick a child according to relative probability weights.
## Once a child is ticked, that child continues to be ticked if it returns Busy. A new random
## choice is only selected once a child returns Resolved or Failed (this is referred to as
## 'Sticky' in other Select nodes).
@export var random_mode := RandomMode.Uniform
## Only used if RandomMode is set to Weighted, otherwise these weights are ignored.
## If entries are missing, the resulting values will have a weight equal to 1.
@export var weights: Array[float] = []


var _prev_sticky_child = null


# === Editor Overrides ===


func editor_get_name() -> String: return "Select Random"
func editor_get_color() -> Color: return BehEditorNode.COLOR_TITLE_META
func editor_get_body_text() -> String:
	if random_mode == RandomMode.Uniform:
		return "Uniformly sampled."
	else: # RandomMode.Weighted
		var sanitized_weights = compute_actual_weights()
		var expected_avgs = BehUtils.get_weighted_random_sample_expected_averages(sanitized_weights)
		var body = ""
		var first_line = true
		var opt_idx = -1
		for avg in expected_avgs:
			opt_idx += 1
			if !first_line:
				body += "\n"
			body += "%s: %4.2f%%" % [opt_idx, avg * 100]
			first_line = false
		return body


# === Overrides ===


func get_does_child_order_matter() -> bool: return true # Displays an order hint on children.


func tick(dt: float, bb: Dictionary) -> BehConst.Status:
	"""Ticks a random child. As long as the chosen child is Busy, subsequent ticks
	will continue to tick that child. Differs slightly from Select's ticking behavior in that if
	a randomly-selected child fails, Select-Random resolves (since it already made its ticking
	decision); whereas Select continues looking for a non-failing child as its decision logic."""
	
	if len(children) == 0:
		return BehConst.Status.Resolved
	
	# Roll index. Possibly consume _prev_sticky_child from the previous tick.
	idx = roll_child_idx()
	if _prev_sticky_child != null:
		idx = children.find(_prev_sticky_child)
		_prev_sticky_child = null # Consume it.
	if idx < 0 || idx >= len(children):
		idx = roll_child_idx() # reroll if keep_child resulted in a -1 index.
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
			_prev_sticky_child = beh
			return BehConst.Status.Busy
		BehConst.Status.Failed:
			return BehConst.Status.Resolved # Select consumes failure?
		BehConst.Status.Resolved:
			return BehConst.Status.Resolved
		_:
			push_error("Unhandled %s" % status)
			return BehConst.Status.Failed
	pass


func roll_child_idx() -> int:
	"""Rolls a valid index for selecting a child of this BehNode."""
	match random_mode:
		RandomMode.Uniform:
			return randi_range(0, len(children) - 1)
		RandomMode.Weighted:
			var actual_weights = compute_actual_weights()
			var rand_idx = BehUtils.get_weighted_random_sample_idx(actual_weights)
			return rand_idx
		_:
			push_error("[BehNodeBSelectRandom] Unhandled random_mode %s" % random_mode)
	return -1


func compute_actual_weights() -> Array[float]:
	"""Safely computes a valid weights array even if the user-specified weights is invalid."""
	var actual_weights: Array[float] = []
	for _i in range(len(children)):
		actual_weights.push_back(1) # Default weights.
	for w_i in range(len(self.weights)): # Overwrite with user weights.
		if w_i >= 0 && w_i < len(children): # Valid actual-weight index.
			actual_weights[w_i] = weights[w_i] # Overwrite.
	return actual_weights


