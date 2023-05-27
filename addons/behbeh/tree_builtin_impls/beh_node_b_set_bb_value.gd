@tool
class_name BehNodeBSetBBValue
extends BehNode


## The name of the property in the 'bb' (blackboard) Dictionary to check when ticked.
## If the resulting property value is true (or truthy), the 'true' child pathway is ticked.
## If the resulting property value is false (or falsey), the 'false' child pathway is ticked.
## By default, the 'true' child pathway is the only-child (if one child) or the upper-child
## (if two children). This behavior can be inverted via the 'invert' property.
@export var bb_key: String = ""
@export var to_val_expr: String = ""


var _parsed_expr_str = null
var _parsed_expr = null


# === Editor Overrides ===


func editor_get_name() -> String: return "Set BB Value"
func editor_get_color() -> Color: return BehEditorNode.COLOR_TITLE_UTILITY
func editor_get_body_text() -> String:
	# Validation -- immediate returns.
	if bb_key == null || len(bb_key) == 0:
		return "No bb_key set."
	
	var expr_err_str = try_parse_expr_cached()
	if expr_err_str != null:
		return "Invalid expression: %s" % expr_err_str
	
	# Build-up label text info.
	var label_text = ""
	
	# Expr info.
	if expr_err_str == null:
		var expr_str = self._parsed_expr_str
		label_text += "bb[\"%s\"] = %s" % [bb_key, expr_str]
	return label_text


# === Set BB Value ===


func try_parse_expr_cached() -> Variant:
	"""Returns null if OK or an error string if the expression could not be parsed."""
	if is_expression_cached():
		return null
	var expr = Expression.new()
	var err = expr.parse(self.to_val_expr)
	if err:
		_parsed_expr_str = null
		_parsed_expr = null
		return expr.get_error_text()
	else: # !err
		_parsed_expr_str = self.to_val_expr
		_parsed_expr = expr
		return null


func is_expression_cached() -> bool:
	"""Return true if the current expression string has already been successfully parsed and is cached."""
	return _parsed_expr_str == self.to_val_expr && _parsed_expr != null


# === Overrides - BehNode ===


func tick(dt: float, bb: Dictionary) -> BehConst.Status:
	var expr_err_str = try_parse_expr_cached()
	if expr_err_str != null:
		push_error("[BehNodeBSetBBValue] (tick) Unable to evaluate expression; couldn't parse expr. %s" % [
			expr_err_str])
		return BehConst.Status.Failed
	else: # has expr
		var expr: Expression = _parsed_expr
		var expr_val = expr.execute()
		if expr.has_execute_failed():
			push_error("[BehNodeBSetBBValue] (tick) Failed to execute expr. (Did you remember to quote any strings in the expr?) %s" % [
				expr.get_error_text()])
			return BehConst.Status.Failed
#		if !bb.has(self.bb_key):
#			push_error("[BehNodeBSetBBValue] (tick) Can't set bb entry value @ [%s]; key not in bb." % [
#				expr_val, self.bb_key])
#			return BehConst.Status.Failed
		bb[self.bb_key] = expr_val
		return BehConst.Status.Resolved
	pass









