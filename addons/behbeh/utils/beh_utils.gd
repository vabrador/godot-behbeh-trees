class_name BehUtils


# === Contents ===

# - Constants (See: BehConst)
# - Value Safety
# - View Style
# - BehEditorNode


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


