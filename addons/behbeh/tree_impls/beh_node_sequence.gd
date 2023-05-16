@tool
class_name BehNodeSequence
extends BehNode


# Remember to EXPORT any references that are intended for serialization!
@export var seq: Array[BehNode] = []


# === Overrides ===


func tick(dt: float, bb: Dictionary) -> BehConst.Status:
	"""Ticks children. Fails if any ticked child fails. Returns successful once all children have
	ticked successfully, in sequence."""
	print("[BehNodeSequence] (tick) TODO: Transfer tick logic from older Sequence behavior to this. Returning success immediately.")
	return BehConst.Status.Success


func clone(deep: bool) -> BehNode:
	var dup = super.clone(deep) as BehNodeSequence
	var dup_seq: Array[BehNode] = []
	if !deep:
		for src_child in self.seq:
			dup_seq.push_back(src_child)
	else: # deep clone
		for src_child in self.seq:
			var dup_child = src_child.clone(deep)
			dup_seq.push_back(dup_child)
	dup.seq = dup_seq
	return dup


func get_is_root() -> bool: return false


func get_children() -> Array[BehNode]:
	return seq


func get_can_add_child() -> bool: return true


func try_add_child(new_child: BehNode) -> bool:
	seq.push_back(new_child)
	print("[BehNodeSequence] try_add_child successfully added a child %s" % new_child)
	child_added.emit(new_child)
	return true


func remove_child(child_to_remove: BehNode) -> bool:
	var found_idx = seq.find(child_to_remove)
	if found_idx == -1:
		print("[BehNodeSequence] remove_child returning false. Not found: %s" % child_to_remove)
		return false
	seq.remove_at(found_idx)
	child_removed.emit(child_to_remove)
	print("[BehNodeSequence] remove_child successfully removed child %s" % child_to_remove)
	return true


