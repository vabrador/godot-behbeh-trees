@tool
class_name BehNodeBPlaceholder
extends BehNode


# Exports here.
@export var wait_ticks := 60
@export var print_msg := "Placeholder."
@export var as_warning := false
@export var start_prefix := "[Placeholder BehNode] "
@export var finish_prefix := "[Placeholder BehNode] Finished: "
@export var print_started := true
@export var print_finished := false


var _waited := -1


# === Editor Overrides ===


func editor_get_name() -> String: return "Placeholder"
func editor_get_color() -> Color: return BehEditorNode.COLOR_TITLE_DEBUG
func editor_get_body_text() -> String: return "Wait %s ticks,\nprint '%s'" % [wait_ticks, print_msg]


# === Overrides ===


func tick(_dt: float, _bb: Dictionary) -> BehConst.Status:
	if _waited == -1:
		if print_msg != null && len(print_msg) > 0:
			if print_started: print_placeholder_msg(start_prefix)
	_waited += 1
	if _waited == wait_ticks:
		if print_msg != null && len(print_msg) > 0:
			if print_finished: print_placeholder_msg(finish_prefix)
		_waited = -1
		return BehConst.Status.Resolved
	return BehConst.Status.Busy


func print_placeholder_msg(prefix):
	var to_print = "%s%s" % [prefix, print_msg]
	if as_warning:
		push_warning(to_print)
	else:
		print(to_print)
