@tool
class_name BehNodeBWait
extends BehNode


# Exports here.
@export var ticks := 1

var _waited := -1


# === Editor Overrides ===


func editor_get_name() -> String: return "Wait"
func editor_get_color() -> Color: return BehEditorNode.COLOR_TITLE_UTILITY
func editor_get_body_text() -> String: return "%s ticks" % ticks


# === Overrides ===


func tick(_dt: float, _bb: Dictionary) -> BehConst.Status:
	_waited += 1
	if _waited == ticks:
		_waited = -1
		return BehConst.Status.Resolved
	return BehConst.Status.Busy

