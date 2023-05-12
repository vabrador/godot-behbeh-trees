class_name BehUtils


# === Contents ===

# - (For Constants, see: BehConst)
# - Value Safety
# - View Style
# - BehEditorNode
# - Script Meta


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

