#@tool
#class_name BehEditorResourcePicker
#extends EditorResourcePicker
#
#
#const START_CUST_ID := 2000
#
#
#var _cust_id: int = START_CUST_ID # Custom ID start index for custom menu entries.
#var _id_to_type_map: Dictionary = {} # Maps "ID" in the picker -> Type name as StringName.
#
#
## === EditorResourcePicker Overrides ===
#
#
#func _enter_tree():
#	print("[BehEditorResourcePicker] (_enter_tree) Got enter_tree.")
#	regenerate_type_map()
#
#
#func _handle_menu_selected(id):
#	print("[BehEditorResourcePicker] (_handle_menu_selected) Called with id %s" % id)
#	if !_id_to_type_map.has(id):
#		push_error("[BehEditorResourcePicker] (_handle_menu_selected) _id_to_type_map missing entry for id %s" % id)
#		return
#	var type_name = _id_to_type_map[id]
#	var new_inst = ClassDB.instantiate(type_name)
#	if new_inst == null:
#		push_error("[BehEditorResourcePicker] (_handle_menu_selected) Tried to instantiate type %s but ClassDB.instantiate returned null." % [
#			type_name])
#		return
#	self.edited_resource = new_inst
#	pass
#
#
#func _set_create_options(menu_node: Object):
#	print("[BehEditorResourcePicker] (_set_create_options) Called with menu_node %s" % menu_node)
#	var popup = menu_node as PopupMenu
#	for type_id in _id_to_type_map.keys():
#		var type_name = _id_to_type_map[type_id]
#		popup.add_item("New %s" % type_name, type_id)
#	pass
#
#
## === Allowed Types ===
#
#
#func regenerate_type_map():
#	print("[BehEditorResourcePicker] (regenerate_type_map) Called.")
#	var filtered_type_names = get_filtered_allowed_types()
#	_id_to_type_map.clear()
#	reset_cust_id()
#	var mapped_ct = 0
#	for type_name in filtered_type_names:
#		var type_id = inc_cust_id() # Totally fine that this is volatile.
#		_id_to_type_map[type_id] = StringName(type_name)
#		mapped_ct += 1
#	print("[BehEditorResourcePicker] (regenerate_type_map) Processed %s types after filtering." % [
#		mapped_ct])
#	pass
#
#
#func get_filtered_allowed_types() -> PackedStringArray:
##	var og_types = super.get_allowed_types()
##	var base_class = StringName("BehNode")
#	var base_class = StringName("Resource")
#	if !ClassDB.class_exists(base_class):
#		push_error("[BehEditorResourcePicker] Base class %s doesn't exist in ClassDB :(" % [
#			base_class])
#	var resource_types = ClassDB.get_inheriters_from_class(base_class)
#	print("[BehEditorResourcePicker] (get_filtered_allowed_types) ClassDB returned %s implementers." % [
#		len(resource_types)])
#
#	var prefix_filter = "BehNode"
#
#	var remove_entries_list = [
#		"BehNode",
#	]
#
#	var types = resource_types.duplicate()
#	var prefix_filtered_types = []
#	# Filter by prefix.
#	for type in types:
#		if type.begins_with(prefix_filter):
#			prefix_filtered_types.push_back(type)
#			print("FOUND PREFIX TYPE %s" % type)
#	types = prefix_filtered_types
#	print("length of types is %s" % len(types))
#	# Filter by removing specific entries.
#	var entry_removed_types = types.duplicate()
#	for remove_entry in remove_entries_list:
#		var remove_idx = entry_removed_types.find(remove_entry)
#		if remove_idx != -1:
#			entry_removed_types.remove_at(remove_idx)
#	types = entry_removed_types
#	# Return types list.
#	return types
#
#
## === Helpers ===
#
#
#func reset_cust_id():
#	_cust_id = START_CUST_ID
#
#
#func inc_cust_id() -> int:
#	_cust_id += 1
#	return _cust_id
#
#
