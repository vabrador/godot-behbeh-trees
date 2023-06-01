@tool
class_name BehNodeASelect
extends BehNodeXMultiChildren


enum ChildBusyHandling { Sticky, Rude }
## In Sticky mode, if a child returns Busy on a tick, then the next time this node
## receives a tick, this node will skip selection logic and tick the formerly-busy child
## again. Only once the busy child resolves or fails will the stickiness be cleared.
## If the child fails, the other children will be ticked.
##
## In Rude mode, the selection logic runs identically every tick, even if a child returned busy.
## This may prevent a child from being ticked again even if has in-progress "work" via the
## busy signal.
@export var child_busy_handling := ChildBusyHandling.Sticky


var _sticky_busy_child = null
var _ignore_failed_sticky_child = null # Sorry for this variable name


# === Editor Overrides ===


func editor_get_name() -> String: return "Select"
func editor_get_color() -> Color: return BehEditorNode.COLOR_TITLE_META


# === Overrides ===


func get_does_child_order_matter() -> bool: return true


func tick(dt: float, bb: Dictionary) -> BehConst.Status:
	"""Ticks children from the start of the list. If a child fails, the next child is ticked.
	Resolves a Failed if ALL ticked children fail. If any ONE child reports busy, reports busy and
	no other children are ticked that call. Resolves immediately if ANY child resolves.
	
	Parent a Select a variety of Conditions to produce state-machine like behavior."""
	idx = 0
	
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
	
	# Tick the current behavior.
	while idx < len(children):
		var beh = children[idx]
		if beh == _ignore_failed_sticky_child: # Consume failed sticky child instead of ticking
			# AKA, Saturn Devouring His Son. I'm sorry
			_ignore_failed_sticky_child = null
			continue
#		print("Select: Ticking beh %s" % beh)
		match beh.tick(dt, bb):
			BehConst.Status.Busy:
#				print("Select: Beh %s BUSY (halts Select)" % beh)
				if child_busy_handling == ChildBusyHandling.Sticky:
					_sticky_busy_child = beh
				return BehConst.Status.Busy
			BehConst.Status.Failed:
#				print("Select: Beh %s Failed (Select continues.)" % beh)
				next_idx = idx + 1
			BehConst.Status.Resolved:
#				print("Select: Beh %s RESOLVED (halts Select)" % beh)
				return BehConst.Status.Resolved
		if next_idx != -1:
			idx = next_idx
			next_idx = -1
	return BehConst.Status.Failed

