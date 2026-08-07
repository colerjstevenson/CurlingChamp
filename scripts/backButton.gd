extends TextureButton

const MAIN_SCENE_PATH := "res://scenes/Main.tscn"


func _ready() -> void:
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)

func _on_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)
