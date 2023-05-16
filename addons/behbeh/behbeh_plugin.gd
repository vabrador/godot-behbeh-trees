@tool
extends EditorPlugin


var docked_beh_editor: BehTreeEditor = null
var is_first_edit_focus := false
#var _edited_obj: BehTree = null
#var inspector_plugin


func _enter_tree():
	print("[BehBehPlugin] Entering tree.")
	# https://docs.godotengine.org/en/stable/tutorials/plugins/editor/making_plugins.html#a-custom-dock
	docked_beh_editor = preload("res://addons/behbeh/editor/beh_editor.tscn").instantiate()
	docked_beh_editor.editor_plugin = self
	is_first_edit_focus = true
	# INSPECTOR
#	inspector_plugin = preload("res://addons/behbeh/plugin_inspector.gd").instantiate()
#	add_inspector_plugin(inspector_plugin)


func _exit_tree():
	print("[BehBehPlugin] Exiting tree.")
	docked_beh_editor.queue_free()
	# INSPECTOR
#	remove_inspector_plugin(inspector_plugin)
#	inspector_plugin.queue_free()


func _handles(obj: Object) -> bool:
	if obj == null: print("[BehBehPlugin] _handles() called with null arg.")
	# Results in _edit and _make_visible being called
	var is_beh_tree = obj is BehTree
	if is_beh_tree:
		print("[BehBehPlugin] _handles() called with BehTree.")
		return true # Always editable.
	var is_beh_node = obj is BehNode
	if is_beh_node && docked_beh_editor.expects_node_target():
		print("[BehBehPlugin] _handles() called with BehNode and we expected node target.")
#		docked_beh_editor.grab_focus()
		# Because the selection is briefly cleared before we get a Node target,
		# we re-open the bottom panel for the editor here:
		make_bottom_panel_item_visible(docked_beh_editor)
		return true # We're creating or editing a node by focusing it.
	print("[BehBehPlugin] _handles() returning false.")
	return false


func _make_visible(visible: bool):
	print("[BehBehPlugin] make_visible %s called." % visible)
	if visible:
		add_control_to_bottom_panel(docked_beh_editor, "BehBeh Tree Editor")
	else:
		remove_control_from_bottom_panel(docked_beh_editor)


func _edit(obj: Object):
	if obj is BehTree: print("[BehBehPlugin] _edit(): Got object to edit: BehTree")
	if obj is BehNode: print("[BehBehPlugin] _edit(): Got object to edit: BehNode")
	if obj == null: print("[BehBehPlugin] _edit(): Got object to edit: null")
	var to_edit = obj
	if !(_handles(obj)): to_edit = null
	# obj may be null; in which case no object to edit, should clean up editing state.
	docked_beh_editor.notify_edit_target(obj)
	if docked_beh_editor.active_tree != null && !is_first_edit_focus:
		print("[BehBehPlugin] _edit: taking focus b/c active_tree != null")
		make_bottom_panel_item_visible(docked_beh_editor)
	if is_first_edit_focus:
		# We skip the first edit focus because it's called when making a new tree
		# Otherwise the editor takes focus away from the "name the new Resource" save window
		print("[BehBehPlugin] _edit: HACK: Skipping first edit focus...")
		is_first_edit_focus = false
	pass


#func _make_visible(visible):
