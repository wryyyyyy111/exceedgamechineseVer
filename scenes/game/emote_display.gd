class_name EmoteDisplay
extends Node2D

@export var sent_emote_text_color : Color = Color("#36d854")

@onready var panel : PanelContainer = $Panel
@onready var image : TextureRect = $Panel/Margin/EmoteIcon
@onready var text : Label = $Panel/Margin/EmoteText
@onready var animation_player : AnimationPlayer = $AnimationPlayer

func remove():
	animation_player.stop()

func pause_for_rotation_layout():
	remove()

func play_emote(is_image_emote : bool, emote : String, start_pos: Vector2, height : float):
	animation_player.stop()
	if is_image_emote:
		var texture = load(emote)
		if texture:
			image.texture = texture
		else:
			is_image_emote = false
			emote = "图片载入失败：\n%s" % emote

	if not is_image_emote:
		text.add_theme_color_override("font_color", sent_emote_text_color)
		text.text = emote

	image.visible = is_image_emote
	text.visible = not is_image_emote

	panel.reset_size()
	panel.modulate = Color(1, 1, 1, 0)
	animation_player.play("Rise and Fade")
	var tween = get_tree().create_tween()
	var end_pos = Vector2(0, -height) + start_pos
	var tween_length = animation_player.get_animation("Rise and Fade").length

	tween.tween_property(panel, "position", end_pos, tween_length).from(start_pos)
