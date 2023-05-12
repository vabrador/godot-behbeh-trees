@tool
class_name BehEditorGraphEdit
extends GraphEdit


#signal open_context_menu(relative_pos: Vector2)


#func _gui_input(event):
#	if event is InputEventMouseButton:
#		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
#			open_context_menu.emit(event.position)
#			accept_event()
#
