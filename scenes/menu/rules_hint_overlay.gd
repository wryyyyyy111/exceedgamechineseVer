extends Control

const ImageMargin := 24.0

@onready var overlay_layer : CanvasLayer = $OverlayLayer
@onready var image_view : TextureRect = $OverlayLayer/ImageView

func _ready() -> void:
	visibility_changed.connect(_sync_layer_visibility)
	get_viewport().size_changed.connect(_update_image_layout)
	_update_image_layout()
	_sync_layer_visibility()

func show_rules() -> void:
	_update_image_layout()
	show()
	$OverlayLayer/BackgroundButton.grab_focus()

func _sync_layer_visibility() -> void:
	overlay_layer.visible = is_visible_in_tree()
	# CanvasLayer does not inherit the menu/game's CanvasItem visibility.
	if not is_visible_in_tree() and visible:
		hide()

func _update_image_layout() -> void:
	var viewport_size := get_viewport_rect().size
	var texture_size := image_view.texture.get_size()
	var available_size := (viewport_size - Vector2.ONE * ImageMargin * 2.0).max(Vector2.ONE)
	var image_scale := minf(available_size.x / texture_size.x, available_size.y / texture_size.y)
	image_view.size = texture_size * image_scale
	image_view.position = (viewport_size - image_view.size) / 2.0
