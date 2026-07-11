extends Control

## Emitted when the player taps the stone to lock in their spin value.
## spin_value is in degrees, ranging from -150 to 150.
## Negative = counter-clockwise, positive = clockwise.
signal spin_selected(spin_value: float)

var _spin_speed_base := 180.0
var _max_spin := 150.0
var _stop_duration := 0.5

var _spin_dir := 1.0
var _current_spin := 0.0
var _spinning := true
var _tap_handled := false
var _base_stone_scale := Vector2.ONE
var _spin_speed_scale := 1.0

@onready var _stone: AnimatedSprite2D = get_node_or_null("StoneSprite") as AnimatedSprite2D


func _ready() -> void:
	if not is_instance_valid(_stone):
		push_warning("SpinSetter: missing StoneSprite child node")
		return
	_base_stone_scale = _stone.scale
	_adjust_layout_to_viewport()



## Call this after adding the scene to set the stone color.
## color should be "blue", "red", or "yellow".
func setup(color: String, spin_speed_scale: float = 1.0, max_spin_degrees: float = 150.0, stop_duration: float = 0.5) -> void:
	if not is_instance_valid(_stone):
		return
	set_spin_speed_scale(spin_speed_scale)
	set_spin_bounds(max_spin_degrees)
	set_stop_duration(stop_duration)
	_stone.play(color)
	_adjust_layout_to_viewport()


func set_spin_speed_scale(spin_speed_scale: float) -> void:
	_spin_speed_scale = maxf(spin_speed_scale, 0.1)


func set_spin_bounds(max_spin_degrees: float) -> void:
	_max_spin = maxf(max_spin_degrees, 1.0)


func set_stop_duration(stop_duration: float) -> void:
	_stop_duration = maxf(stop_duration, 0.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_adjust_layout_to_viewport()


func _adjust_layout_to_viewport() -> void:
	if not is_instance_valid(_stone):
		return

	var viewport_size: Vector2 = get_viewport_rect().size
	if viewport_size == Vector2.ZERO:
		return

	_stone.position = viewport_size * 0.5

	var fit_scale := minf(viewport_size.x / 720.0, viewport_size.y / 1280.0)
	fit_scale = clampf(fit_scale, 0.65, 1.0)
	_stone.scale = _base_stone_scale * fit_scale


func _process(delta: float) -> void:
	if not is_instance_valid(_stone):
		return

	if not _spinning:
		return

	_current_spin += _spin_speed_base * _spin_speed_scale * _spin_dir * delta

	if _current_spin >= _max_spin:
		_current_spin = _max_spin
		_spin_dir = -1.0
	elif _current_spin <= -_max_spin:
		_current_spin = -_max_spin
		_spin_dir = 1.0

	_stone.rotation_degrees = _current_spin
	


func _input(event: InputEvent) -> void:
	if _tap_handled:
		return

	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed:
			_on_stone_tapped()


func _on_stone_tapped() -> void:
	_tap_handled = true
	_spinning = false
	await get_tree().create_timer(_stop_duration).timeout
	spin_selected.emit(_current_spin)
	queue_free()
