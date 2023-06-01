class_name BehTestTreeUser
extends Node


@export var beh_tree: BehTree = null


var _running := false
var _bb := {}


func _ready():
	_running = true


func _process(dt):
	if beh_tree == null: return
	if !_running: return
	
	# By convention, we expose the "evaluator" Node to the blackboard.
	# As well as other blackboard properties.
	var bb = _bb
	if !bb.has("node"): 			bb["node"] = self
#	if !bb.has("found_player"): 	bb["found_player"] = false
#	if !bb.has("state"): 			bb["state"] = "wander"
	if !bb.has("aggro_target"): 	bb["aggro_target"] = ""
	
	match beh_tree.tick(dt, bb):
		BehConst.Status.Resolved:
#			print("Tree reported RESOLVED.")
			pass
		BehConst.Status.Failed:
#			print("Tree reported FAILED.")
			pass
		BehConst.Status.Busy:
#			print("Tree reported BUSY.")
			pass
	# bb gets mutated over time by the tree to allow it to be stateful.

