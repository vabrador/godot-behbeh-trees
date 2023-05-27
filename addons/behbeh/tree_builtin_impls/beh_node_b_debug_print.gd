@tool
class_name BehNodeBDebugPrint
extends BehNode


@export var msg: String = "Hello, world!"


# === Editor Overrides ===


func editor_get_name() -> String: return "Debug: Print"
func editor_get_color() -> Color: return BehEditorNode.COLOR_TITLE_DEBUG
func editor_get_body_text() -> String: return "\"%s\"" % msg


# === Overrides ===


func tick(_dt: float, _bb: Dictionary) -> BehConst.Status:
	print(msg)
	return BehConst.Status.Resolved

