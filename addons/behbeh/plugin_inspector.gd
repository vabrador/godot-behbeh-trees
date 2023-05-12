# no class_name
extends EditorInspectorPlugin


func _can_handle(obj: Object) -> bool:
	return obj is BehTree


