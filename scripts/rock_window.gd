extends Control

const Stone = preload("res://scripts/stone_data.gd")
const RED_SIDE_TEXTURE := preload("res://assets/curling/stones/stone_red_side.png")
const BLUE_SIDE_TEXTURE := preload("res://assets/curling/stones/stone_blue_side.png")
const YELLOW_SIDE_TEXTURE := preload("res://assets/curling/stones/stone_yellow_side.png")

@onready var name_label: RichTextLabel = $Panel/Name
@onready var age_label: RichTextLabel = $Panel/age
@onready var wins_label: RichTextLabel = $Panel/wins
@onready var rock_sprite: Sprite2D = $Panel/Rock
@onready var power_bar: ProgressBar = $Panel/VBoxContainer/Power/PowerBar
@onready var spin_bar: ProgressBar = $Panel/VBoxContainer/Spin/SpinBar
@onready var precision_bar: ProgressBar = $Panel/VBoxContainer/Precision/PrecisionBar
@onready var condition_bar: ProgressBar = $Panel/VBoxContainer/Spin2/SpinBar
@onready var close_button: TextureButton = $Panel/Close
@onready var auction_button: TextureButton = $Panel/auctionButton


func _ready() -> void:
	if is_instance_valid(close_button):
		close_button.visible = false
	if is_instance_valid(auction_button):
		auction_button.visible = false


func setup_from_stone(stone: Stone) -> void:
	if stone == null:
		return

	if is_instance_valid(name_label):
		name_label.text = stone.name
	if is_instance_valid(age_label):
		age_label.text = "Age: %d" % stone.age
	if is_instance_valid(wins_label):
		wins_label.text = "Wins: %d" % stone.wins
	_set_rock_sprite_color(stone.color)

	_set_bar_value(power_bar, stone.power)
	_set_bar_value(spin_bar, stone.spin)
	_set_bar_value(precision_bar, stone.precision)
	_set_bar_value(condition_bar, stone.condition)


func _set_bar_value(bar: ProgressBar, value: int) -> void:
	if not is_instance_valid(bar):
		return
	bar.min_value = 0
	bar.max_value = 100
	bar.value = clampf(float(value), 0.0, 100.0)


func _set_rock_sprite_color(stone_color: String) -> void:
	if not is_instance_valid(rock_sprite):
		return

	match stone_color:
		"blue":
			rock_sprite.texture = BLUE_SIDE_TEXTURE
		"yellow":
			rock_sprite.texture = YELLOW_SIDE_TEXTURE
		_:
			rock_sprite.texture = RED_SIDE_TEXTURE


func _close_window() -> void:
	queue_free()


func _launch_auction() -> void:
	# Placeholder for scenes that use this control as an auction popup.
	pass
