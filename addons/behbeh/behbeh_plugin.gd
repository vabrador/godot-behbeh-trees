@tool
extends EditorPlugin


var docked_beh_editor: BehTreeEditor = null
var is_first_edit_focus := false
var undo_redo: EditorUndoRedoManager = get_undo_redo()


static func dprintd(s: String):
	BehTreeEditor.dprintd(s) # See BehTreeEditor implementation for debug switch.


func _enter_tree():
	dprintd("[BehBehPlugin] Entering tree.")
	# https://docs.godotengine.org/en/stable/tutorials/plugins/editor/making_plugins.html#a-custom-dock
	docked_beh_editor = preload("res://addons/behbeh/editor/beh_editor.tscn").instantiate()
	docked_beh_editor.editor_plugin = self
	docked_beh_editor.undo_redo = self.undo_redo
	is_first_edit_focus = true
	# INSPECTOR
#	inspector_plugin = preload("res://addons/behbeh/plugin_inspector.gd").instantiate()
#	add_inspector_plugin(inspector_plugin)


func _exit_tree():
	dprintd("[BehBehPlugin] Exiting tree.")
	docked_beh_editor.queue_free()
	# INSPECTOR
#	remove_inspector_plugin(inspector_plugin)
#	inspector_plugin.queue_free()


func _handles(obj: Object) -> bool:
	if obj == null:
		dprintd("[BehBehPlugin] _handles() called with null arg.")
		if docked_beh_editor.active_tree != null: # Have an open tree, keep open
			dprintd("[BehBehPlugin] (_handles) Returning true (open active tree)")
			return true
		dprintd("[BehBehPlugin] (_handles) Returning false")
		return false
	# Results in _edit and _make_visible being called
	var is_beh_tree = obj is BehTree
	if is_beh_tree:
		dprintd("[BehBehPlugin] _handles() called with BehTree; returning true")
		return true # Always editable.
	var is_beh_node = obj is BehNode
	if is_beh_node && docked_beh_editor.expects_node_target():
		dprintd("[BehBehPlugin] _handles() called with BehNode and we expected node target.")
#		docked_beh_editor.receive_node_target()
#		docked_beh_editor.grab_focus()
		# Because the selection is briefly cleared before we get a Node target,
		# we re-open the bottom panel for the editor here:
		make_bottom_panel_item_visible(docked_beh_editor)
		dprintd("[BehBehPlugin] (_handles) Returning true")
		return true # We're creating or editing a node by focusing it.
	dprintd("[BehBehPlugin] (_handles) Returning false")
	return false


func _make_visible(visible: bool):
	dprintd("[BehBehPlugin] make_visible %s called." % visible)
	if visible:
		add_control_to_bottom_panel(docked_beh_editor, "BehBeh Tree Editor")
	else:
		remove_control_from_bottom_panel(docked_beh_editor)


func _edit(obj: Object):
	if obj == null:
		dprintd("[BehBehPlugin] _edit(): Got object to edit: null")
		return
	if obj is BehTree: dprintd("[BehBehPlugin] _edit(): Got object to edit: BehTree")
	if obj is BehNode: dprintd("[BehBehPlugin] _edit(): Got object to edit: BehNode, %s" % obj)
	var to_edit = obj
	if !(_handles(obj)): to_edit = null
	docked_beh_editor.notify_edit_target(obj)
	if docked_beh_editor.active_tree != null:# && !is_first_edit_focus:
		dprintd("[BehBehPlugin] _edit: taking focus b/c active_tree != null")
		make_bottom_panel_item_visible(docked_beh_editor)
#	if is_first_edit_focus:
#		# We skip the first edit focus because it's called when making a new tree
#		# Otherwise the editor takes focus away from the "name the new Resource" save window
#		dprintd("[BehBehPlugin] _edit: HACK: Skipping first edit focus...")
#		is_first_edit_focus = false
	pass


#func _make_visible(visible):
