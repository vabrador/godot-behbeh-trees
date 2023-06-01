class_name BehUtils


# === Contents ===

# - (For Constants, see: BehConst)
# - Value Safety
# - View Style
# - BehEditorNode
# - Script Meta
# - RNG Random Number Generation
# - UUID Unique ID Generation -- See beh_uuid.gd


# === Value Safety ===


static func checkf(f: float, silent_on_non_finite: bool = false) -> float:
	"""Validates a float is neither inf nor nan. If silent_on_non_finite is true, still converts
	a non-finite float to 0, but doesn't push an error message."""
	if is_inf(f) or is_nan(f):
		if !silent_on_non_finite: push_error("[BehUtils] Float was %s; returning 0." % f)
		return 0
	return f

static func checkv(v: Vector2, silent_on_non_finite: bool = false) -> Vector2:
	"""As checkf, for Vector2. Pushes an error if non-finite unless the second arg is set to true."""
	return Vector2(checkf(v.x, silent_on_non_finite), checkf(v.y, silent_on_non_finite))


# === View Style ===


static func get_default_new_node_offset() -> Vector2:
	"""Returns the default relative offset from a node center to create a new node."""
	return Vector2(-300, 0)


# === Script Meta ===


static func get_best_guess_script_class_name(script: Script) -> String:
	"""Literally parses the dang GDScript to try to find the class_name entry.
	Really AWFULLY SILLY that this method has to exist."""
	if script == null:
		return "(Null Script)"
	var script_file_name = script.resource_path.get_file()
	if script.has_source_code():
		var src = script.source_code
		var first_80_chars = src.substr(0, 80)
		var script_name_idx = first_80_chars.find("class_name")
		if script_name_idx >= 0:
			var str_with_name_starting: String = first_80_chars.substr(script_name_idx + len("class_name"))
			str_with_name_starting = str_with_name_starting.lstrip(" ")
			str_with_name_starting = str_with_name_starting.lstrip("\t")
#			print("str_with_name_starting %s" % str_with_name_starting)
			var newline_idx_after_name = str_with_name_starting.find("\n")
			var space_idx_after_name = str_with_name_starting.find(" ")
			var tab_idx_after_name = str_with_name_starting.find("\t")
			if newline_idx_after_name == -1:
				newline_idx_after_name = space_idx_after_name
			if newline_idx_after_name == -1:
				newline_idx_after_name = tab_idx_after_name
			if newline_idx_after_name != -1:
				var parsed_script_class_name = str_with_name_starting.substr(0, newline_idx_after_name)
				return parsed_script_class_name
#	else:
#		print("REMOVE THIS PRINT -- script LACKS source available :(")
	# Fallback is just the script name.
	return script_file_name


# === RNG Random Number Generation ===


static func get_weighted_random_sample(values: Array, weights: Array[float]) -> Variant:
	"""Given an array of values and an array of probability weights, randomly returns one of the values
	according to their probability weights. See get_weighted_random_sample_idx()."""
	var idx = get_weighted_random_sample_idx(weights)
	return values[idx]


static func get_weighted_random_sample_idx(weights: Array[float]) -> int:
	"""Given an array of weights for indices, returns a random index from that array, with
	probability weights corresponding to the weight values.
	
	This function can produce incorrect results if there are weight values that are exceedingly
	small compared to the total sum of weights. This occurs near floating-point precision boundaries
	and is caused by an accumulation operation (see Possible Bug comment)."""
	weights = _inner_sanitize_random_weights(weights) # Duplicates weights array.
	
	# Build list of cutoff weights. For any uniform sample from the 0 to sum(weights), the number
	# of cutoffs that are less than the sample is equal to the index of our weighted choice.
	var cutoff_weights: Array[float] = []
	var acc = 0
	for w in weights:
		cutoff_weights.push_back(acc)
		acc = acc + w # Possible Bug: If w << weight_sum, acc could be the same float as acc + w.
	var weight_sum = acc
	
	# Sample the map uniformly and return the corresponding group index.
	# e.g. 
	# [aaaaaa|bbb|cccccc|dddddddd]   (range 0-23)
	# 0      6   9   ^  15       23  (generate uniform random from 0 to 23)
	#                |
	#                random value 12.5, returns group index 2.
	#
	# In this example, _cutoff_weights contains [0, 6, 9, 15].
	# Here weights are integers, but the logic also works if weights are
	# fractional, as long as they are positive nonzero.
	#
	var sample = randf() * weight_sum
	var idx = -1
	for cutoff in cutoff_weights:
		if sample >= cutoff: idx += 1
	return idx


static func get_weighted_random_sample_expected_averages(weights: Array[float]) -> Array[float]:
	"""Computes expected average probabilities of each option in a weights array.
	That is, returns a new weights array that sums to 1."""
	weights = _inner_sanitize_random_weights(weights) # Duplicates weights array.
	
	# Compute sum.
	var acc = 0
	for w in weights:
		acc = acc + w # Possible Bug: See get_weighted_random_sample_idx comment.
	var weight_sum = acc
	
	# Divide by sum.
	var avgs: Array[float] = []
	for w in weights:
		avgs.push_back(w / weight_sum)
	return avgs


static func _inner_sanitize_random_weights(weights: Array[float]):
	if weights == null: return []
	
	weights = weights.duplicate()
	# Validate weights array. 
	#
	# Clamp negative to zero.
	for w_i in range(len(weights)):
		var w = weights[w_i]
		if w < 0: weights[w_i] = 0
	# All-zero -> All-one.
	var all_zero = true
	for w in weights:
		if w != 0:
			all_zero = false
			break
	if all_zero: for w_i in range(len(weights)): weights[w_i] = 1
	return weights


static func test_get_weighted_random_sample():
	"""Runs and prints a test of get_weighted_random_sample (and get_weighted_random_sample_idx)."""
	print("--- Test: test_get_weighted_random_sample ---")
	var roll_ct = 50000
	var values = ["A", "B", "C", "D"]
	var weights: Array[float] = [1, 2, 3, 4]
	var expected_pcts = [10, 20, 30, 40]
	var buckets = {}
	for _r in range(roll_ct):
		var option = BehUtils.get_weighted_random_sample(values, weights)
		if !buckets.has(option):
			buckets[option] = 0
		buckets[option] += 1
	print("%s rolls:" % roll_ct)
	var get_pct = func(opt_key): return buckets[opt_key] * 100 / float(roll_ct)
	var get_err = func(opt_key, expected): return buckets[opt_key] * 100 / float(roll_ct) - expected
	var all_ok = true
	for v in range(len(values)):
		var val_key = values[v]
		var val_expected = expected_pcts[v]
		var val_err = get_err.call(val_key, val_expected)
		var val_err_ok = val_err < 2 # less than 2 percent; beyond this value a bug is likely
		print("%s: %s occurrences  \t- %s%% \t- error: %s\t- %s" % [val_key, buckets[val_key],
			buckets[val_key] * 100 / float(roll_ct), val_err, "OK" if val_err_ok else "Err: too high!"])
		if !val_err_ok: all_ok = false
	print("-> Test: test_get_weighted_random_sample: %s" % ["OK" if all_ok else "!!! Failed !!!"])
#	var a_ok = abs(get_pct.call("A") - 10) < roll_ct / 10000
#	print("a_ok: %s" % a_ok)


