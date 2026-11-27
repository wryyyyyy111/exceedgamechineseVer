class_name TierListDialog
extends Control

@onready var image_view : TextureRect = $DialogPanel/ImageView

func set_background_opacity(opacity : float) -> void:
	$Dimmer.self_modulate.a = opacity
	$DialogPanel.self_modulate.a = opacity

func _ready() -> void:
	visible = false

func show_tier_list(image : Image) -> void:
	if image == null or image.is_empty():
		return
	image_view.texture = ImageTexture.create_from_image(image)
	visible = true

func close_dialog() -> void:
	visible = false

func _on_close_button_pressed() -> void:
	close_dialog()

func _on_background_button_pressed() -> void:
	close_dialog()

