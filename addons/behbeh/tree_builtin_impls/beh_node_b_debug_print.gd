@tool
class_name BehNodeBDebugPrint
extends BehNode


# === Editor Overrides ===


func editor_get_name() -> String: return "Debug: Print"
func editor_get_color() -> Color: return Color.PLUM


# === Overrides ===


func tick(_dt: float, _bb: Dictionary) -> BehConst.Status:
	print("[BehNodeBDebugPrint] Hello, world! This node is: %s" % self.resource_name)
	return BehConst.Status.Resolved

