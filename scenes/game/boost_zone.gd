class_name BoostZone
extends Node2D

signal clicked_zone

@onready var boost_effects : RichTextLabel = $OuterMargin/BoostPanel/InnerMargin/BoostVBox/BoostEffects
@onready var show_image : TextureRect = $OuterMargin/ShowHideHBox/MarginContainer/MarginContainer/ShowImage
@onready var hide_image : TextureRect = $OuterMargin/ShowHideHBox/MarginContainer/MarginContainer/HideImage

var effects_visible = true

func _on_focus_pressed():
	clicked_zone.emit()

func set_text(text):
	boost_effects.text = text
	boost_effects.visible = effects_visible

func _on_show_hide_button_pressed():
	effects_visible = not effects_visible
	show_image.visible = not effects_visible
	hide_image.visible = effects_visible
	boost_effects.visible = effects_visible
