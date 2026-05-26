extends Camera2D

@export var target_path: NodePath = ^"../Stone"
@export var lock_x_to_center := true
@export var center_x := 360.0

var target: Node2D

func _ready() -> void:
	target = get_node_or_null(target_path) as Node2D
	position_smoothing_enabled = true
	position_smoothing_speed = 8.0
	make_current()

func _physics_process(_delta: float) -> void:
	if target == null:
		return

	var next_pos := global_position
	next_pos.y = target.global_position.y
	if lock_x_to_center:
		next_pos.x = center_x
	else:
		next_pos.x = target.global_position.x

	global_position = next_pos
