@tool
class_name BehNodeACondition
extends BehNodeXMultiChildren


## The name of the property in the 'bb' (blackboard) Dictionary to check when ticked.
## If the resulting property value is true (or truthy), the 'true' child pathway is ticked.
## If the resulting property value is false (or falsey), the 'false' child pathway is ticked.
## By default, the 'true' child pathway is the only-child (if one child) or the upper-child
## (if two children). This behavior can be inverted via the 'invert' property.
@export var bb_key: String = ""
@export var equals_expr: String = ""
## If set, the single-child pathway (1 child) or upper-child pathway (2 children) is invoked when
## the condition evaluates to false. Normally, the only-child/upper-child pathway is invoked when
## the condition evaluates to true.
@export var invert := false
enum DebugOverride { Off, ForceTrue, ForceFalse }
@export var debug_override := DebugOverride.Off

# Note: This logic works very similarly to BehNodeASelect's sticky-child logic.
enum ChildBusyHandling { Sticky, Rude }
## In Sticky mode, if a child returns Busy on a tick, then the next time this node
## receives a tick, this node will skip condition logic and tick the formerly-busy child
## again. Only once the busy child resolves or fails will the stickiness be cleared.
## If the child fails, the other children will be ticked.
##
## In Rude mode, the condition logic runs identically every tick, even if a child returned busy.
## This may prevent a child from being ticked again even if has in-progress "work" via the
## busy signal.
@export var child_busy_handling := ChildBusyHandling.Sticky


const COLOR_CONNECTION_TRUTHY := Color.GREEN_YELLOW
const COLOR_CONNECTION_FALSEY := Color.MEDIUM_VIOLET_RED


var _parsed_expr_str = null
var _parsed_expr = null
var _sticky_busy_child = null
var _ignore_failed_sticky_child = null # Sorry for this variable name


# === Editor Overrides ===


func editor_get_name() -> String:
	if !self.invert:
		return "Condition"
	else:
		return "!Condition"
func editor_get_color() -> Color: return BehEditorNode.COLOR_TITLE_UTILITY
func editor_get_body_text() -> String:
	# Validation -- immediate returns.
	match debug_override:
		DebugOverride.Off: pass
		DebugOverride.ForceTrue: return "Overridden: True"
		DebugOverride.ForceFalse: return "Overridden: False"
		_:
			push_error("[BehNodeACondition] Unhandled debug_override %s" % debug_override)
	
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
		label_text += "if bb[\"%s\"] == %s:" % [bb_key, expr_str]
	
	# Child-count / direction info.
	var child_ct = len(self.get_children())
	if child_ct == 0:
		label_text += "\n  (Missing children.)"
	elif child_ct == 1:
		if !invert:
			label_text += "\n  'true' -> child"
		else:
			label_text +=  "\n  'false' -> child"
	else: # child_ct == 2
		if !invert:
			label_text +=  "\n  'true' -> up\n  'false' -> down"
		else:
			label_text +=  "\n  'false' -> up\n  'true' -> down"
	
	return label_text
#func editor_get_connection_color(child_idx: int) -> Color:
#	if child_idx == 0 || (invert && child_idx == 1): return COLOR_CONNECTION_TRUTHY
#	if child_idx == 1 || (invert && child_idx == 0): return COLOR_CONNECTION_FALSEY
#	return BehEditorNode.COLOR_CONNECTION


# === Condition ===


func get_truthy_child() -> Variant:
	"""Returns the child invoked when the condition evaluates to true. Returns null if no
	such child is attached."""
	if invert:
		return get_child_idx_or_null(1)
	return get_child_idx_or_null(0)


func get_falsey_child() -> Variant:
	"""Returns the child invoked when the condition evaluates to true. Returns null if no
	such child is attached."""
	if invert:
		return get_child_idx_or_null(0)
	return get_child_idx_or_null(1)


func try_parse_expr_cached() -> Variant:
	"""Returns null if OK or an error string if the expression could not be parsed."""
	if is_expression_cached():
		return null
	var expr = Expression.new()
	var err = expr.parse(self.equals_expr)
	if err:
		_parsed_expr_str = null
		_parsed_expr = null
		return expr.get_error_text()
	else: # !err
		_parsed_expr_str = self.equals_expr
		_parsed_expr = expr
		return null


func is_expression_cached() -> bool:
	"""Return true if the current expression string has already been successfully parsed and is cached."""
	return _parsed_expr_str == self.equals_expr && _parsed_expr != null


# === Overrides - BehNodeXMultiChildren ===
#
# Careful here. We only override adding children, to cap the number of children of Conditions to 2.
# This gives conditions a True path (child 0, upper) and a False path (child 1, lower).


func get_can_add_child() -> bool:
	# Subtle (TODO rename for clarity) -- ALWAYS must return true!
	# This allows the right-side port to always exist!
	# try_add_child still returns false sometimes, to cap the number of children.
	return true


func try_add_child(new_child: BehNode) -> bool:
	"""One of the only overrides that is allowed to fail. Return false to not accept
	the new child."""
	if len(children) == 2: return false # Cap: Maximum 2 children.
	return super.try_add_child(new_child)


# === Overrides - BehNode ===


func tick(dt: float, bb: Dictionary) -> BehConst.Status:
	var override_tick_child = null
	match debug_override:
		DebugOverride.Off: pass
		DebugOverride.ForceTrue: override_tick_child = get_truthy_child()
		DebugOverride.ForceFalse: override_tick_child = get_falsey_child()
		_:
			push_error("[BehNodeACondition] Unhandled debug_override %s" % debug_override)
	if override_tick_child != null:
		return override_tick_child.tick(dt, bb)
	
	# TODO: Conditions should have a default "sticky" mode. If the condition runs a child
	# and gets a "Busy" result from that child, the condition should tick the child again
	# on its own next tick() WITHOUT running the condition again.
	# "Mode: Sticky (skips check if child was busy)"
	# "Mode: Rude (re-checks even if child was busy)"
	
	# (In Sticky mode) If a child reports Busy, that child should be ticked again
	# until it doesn't report busy, circumventing the usual selection logic.
	var tick_normally = true
	if _sticky_busy_child != null:
		# Tick the sticky child.
		var res = _sticky_busy_child.tick(dt, bb)
		if res == BehConst.Status.Failed:
			# We need to tick the other children instead. Will tick "normally," but don't
			# double-tick this first-attempt sticky child.
			_ignore_failed_sticky_child = _sticky_busy_child
			_sticky_busy_child = null
		if res == BehConst.Status.Resolved:
			_sticky_busy_child = null # Resolved child is no longer sticky.
		else: # Child resolved or was busy; either way, return that status
			tick_normally = false
			return res
	
	var expr_err_str = try_parse_expr_cached()
	if expr_err_str != null:
		push_error("[BehNodeACondition] (tick) Unable to evaluate expression; couldn't parse expr. %s" % [
			expr_err_str])
		return BehConst.Status.Failed
	else: # has expr
		var expr: Expression = _parsed_expr
		var expr_val = expr.execute()
		if expr.has_execute_failed():
			push_error("[BehNodeACondition] (tick) Failed to execute expr. (Did you remember to quote any strings in the expr?) %s" % [
				expr.get_error_text()])
			return BehConst.Status.Failed
		if !bb.has(self.bb_key):
			push_error("[BehNodeACondition] (tick) Can't test expr value %s against bb entry [%s]; key not in bb." % [
				expr_val, self.bb_key])
			return BehConst.Status.Failed
		var bb_val = bb[self.bb_key]
		
		var tick_child = null
		if bb_val == expr_val: 	tick_child = get_truthy_child()
		else:					tick_child = get_falsey_child()
		if tick_child != null:
			match tick_child.tick(dt, bb):
				BehConst.Status.Busy:
					if child_busy_handling == ChildBusyHandling.Sticky:
						_sticky_busy_child = tick_child # Child was busy, will tick it again next.
					return BehConst.Status.Busy
			return BehConst.Status.Resolved
		else:
			return BehConst.Status.Failed # Couldn't tick any child.
	pass





