extends Control

## Emitted when the player taps the stone to lock in their spin value.
## spin_value is in degrees, ranging from -270 to 270.
## Negative = counter-clockwise, positive = clockwise.
signal spin_selected(spin_value: float)

const SPIN_SPEED := 180.0   # degrees per second
const MAX_SPIN := 135.0
const STOP_DURATION := 0.5  # seconds to pause before closing

var _spin_dir := 1.0
var _current_spin := 0.0
var _spinning := true
var _tap_handled := false

@onready var _stone: AnimatedSprite2D = $StoneSprite



## Call this after adding the scene to set the stone color.
## color should be "blue", "red", or "yellow".
func setup(color: String) -> void:
	_stone.play(color)


func _process(delta: float) -> void:
	if not _spinning:
		return

	_current_spin += SPIN_SPEED * _spin_dir * delta

	if _current_spin >= MAX_SPIN:
		_current_spin = MAX_SPIN
		_spin_dir = -1.0
	elif _current_spin <= -MAX_SPIN:
		_current_spin = -MAX_SPIN
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
	await get_tree().create_timer(STOP_DURATION).timeout
	spin_selected.emit(_current_spin)
	queue_free()
