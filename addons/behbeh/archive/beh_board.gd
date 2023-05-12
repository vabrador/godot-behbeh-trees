#class_name BehBoard
#
#var _dict: Dictionary = {}
#
#
#func get(key: String) -> Variant:
#	"""Returns the variant value at the specified key in the backing dictionary."""
#	return _dict.get(key, null)
#
#
#func has(key: String) -> bool:
#	return _dict.has(key)
#
#
#func clear(key):
#	_dict.clear()
#
#
#func remove(key: String) -> bool:
#	if !_dict.has(key): return false
#	_dict.erase(key)
#	return true
#
#
#func set(key: String, val: Variant) -> Variant:
#	"""Returns the old value at the key if it existed, or null if there was no value.
#	Pushes a warning if set is called with null as a value (use remove() to remove entries)."""
#	var old_val = null
#	if _dict.has(key):
#		old_val = get(key)
#	_dict[key] = val
#	return old_val
#
