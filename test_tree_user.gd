class_name TestTreeUser
extends Node


@export var beh_tree: BehTree = null


var _running := false


func _ready():
	_running = true


func _process(dt):
	if beh_tree == null: return
	if !_running: return
	var bb = { "node" = self } # By convention, we expose the "evaluator" Node to the blackboard.
	match beh_tree.tick(dt, bb):
		BehConst.Status.Resolved:
			print("Tree reported RESOLVED.")
			_running = false
		BehConst.Status.Failed:
			print("Tree reported FAILED.")
			_running = false
		BehConst.Status.Busy:
			pass

