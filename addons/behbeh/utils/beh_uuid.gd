class_name BehUuid


static func gen_uuid_str() -> StringName:
	"""Generates a uuid v4 and returns it as a StringName.
	
	Warning, the default implementation uses randomize() globally. This will break determinism
	if gen_uuid_str() is ever invoked at runtime."""
	if !Engine.is_editor_hint():
		push_warning("[get_uuid_str] WARNING: Calling this function breaks determinism" +
			"in its current implementation. Recommended only for being called in editor code.")
	return StringName(_v4())



# Original Implementation:
# 
# Source: https://github.com/binogure-studio/godot-uuid/blob/8cc945f72f1d238cd1ddea5739e3ef963e5e6cbc/uuid.gd
# License: MIT
#


# Note: The code might not be as pretty it could be, since it's written
# in a way that maximizes performance. Methods are inlined and loops are avoided.

const BYTE_MASK: int = 0b11111111

static func _uuidbin():
	randomize()
	# 16 random bytes with the bytes on index 6 and 8 modified
	return [
		randi() & BYTE_MASK, randi() & BYTE_MASK, randi() & BYTE_MASK, randi() & BYTE_MASK,
		randi() & BYTE_MASK, randi() & BYTE_MASK, ((randi() & BYTE_MASK) & 0x0f) | 0x40, randi() & BYTE_MASK,
		((randi() & BYTE_MASK) & 0x3f) | 0x80, randi() & BYTE_MASK, randi() & BYTE_MASK, randi() & BYTE_MASK,
		randi() & BYTE_MASK, randi() & BYTE_MASK, randi() & BYTE_MASK, randi() & BYTE_MASK,
	]

static func _uuidbinrng(rng: RandomNumberGenerator):
	rng.randomize()
	return [
		rng.randi() & BYTE_MASK, rng.randi() & BYTE_MASK, rng.randi() & BYTE_MASK, rng.randi() & BYTE_MASK,
		rng.randi() & BYTE_MASK, rng.randi() & BYTE_MASK, ((rng.randi() & BYTE_MASK) & 0x0f) | 0x40, rng.randi() & BYTE_MASK,
		((rng.randi() & BYTE_MASK) & 0x3f) | 0x80, rng.randi() & BYTE_MASK, rng.randi() & BYTE_MASK, rng.randi() & BYTE_MASK,
		rng.randi() & BYTE_MASK, rng.randi() & BYTE_MASK, rng.randi() & BYTE_MASK, rng.randi() & BYTE_MASK,
	]

static func _v4():
	# 16 random bytes with the bytes on index 6 and 8 modified
	var b = _uuidbin()

	return '%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x' % [
		# low
		b[0], b[1], b[2], b[3],

		# mid
		b[4], b[5],

		# hi
		b[6], b[7],

		# clock
		b[8], b[9],

		# clock
		b[10], b[11], b[12], b[13], b[14], b[15]
	]
  
static func _v4_rng(rng: RandomNumberGenerator):
	# 16 random bytes with the bytes on index 6 and 8 modified
	var b = _uuidbinrng(rng)

	return '%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x' % [
		# low
		b[0], b[1], b[2], b[3],

		# mid
		b[4], b[5],

		# hi
		b[6], b[7],

		# clock
		b[8], b[9],

		# clock
		b[10], b[11], b[12], b[13], b[14], b[15]
	]
  
#var _uuid: Array

#func _init(rng := RandomNumberGenerator.new()) -> void:
#  _uuid = uuidbinrng(rng)

#func as_array() -> Array:
#  return _uuid.duplicate()

#func as_dict(big_endian := true) -> Dictionary:
#  if big_endian:
#    return {
#      "low"  : (_uuid[0]  << 24) + (_uuid[1]  << 16) + (_uuid[2]  << 8 ) +  _uuid[3],
#      "mid"  : (_uuid[4]  << 8 ) +  _uuid[5],
#      "hi"   : (_uuid[6]  << 8 ) +  _uuid[7],
#      "clock": (_uuid[8]  << 8 ) +  _uuid[9],
#      "node" : (_uuid[10] << 40) + (_uuid[11] << 32) + (_uuid[12] << 24) + (_uuid[13] << 16) + (_uuid[14] << 8 ) +  _uuid[15]
#    }
#  else:
#    return {
#      "low"  : _uuid[0]          + (_uuid[1]  << 8 ) + (_uuid[2]  << 16) + (_uuid[3]  << 24),
#      "mid"  : _uuid[4]          + (_uuid[5]  << 8 ),
#      "hi"   : _uuid[6]          + (_uuid[7]  << 8 ),
#      "clock": _uuid[8]          + (_uuid[9]  << 8 ),
#      "node" : _uuid[10]         + (_uuid[11] << 8 ) + (_uuid[12] << 16) + (_uuid[13] << 24) + (_uuid[14] << 32) + (_uuid[15] << 40)
#    }
	
#func as_string() -> String:
#  return '%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x' % [
#    # low
#    _uuid[0], _uuid[1], _uuid[2], _uuid[3],
#
#    # mid
#    _uuid[4], _uuid[5],
#
#    # hi
#    _uuid[6], _uuid[7],
#
#    # clock
#    _uuid[8], _uuid[9],
#
#    # node
#    _uuid[10], _uuid[11], _uuid[12], _uuid[13], _uuid[14], _uuid[15]
#  ]
  
#func is_equal(other) -> bool:
#  # Godot Engine compares Array recursively
#  # There's no need for custom comparison here.
#  return _uuid == other._uuid

