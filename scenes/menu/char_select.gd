class_name CharSelect
extends Control

signal select_character(char_id)
signal close_character_select

@onready var hover_label : Label = $HoverBox/HBoxContainer/VBoxContainer/Label
@onready var hover_portrait : TextureRect = $HoverBox/HBoxContainer/VBoxContainer/Portrait

@onready var charselect_s0 = $CenterContainer/S0CharacterSelect
@onready var charselect_s1 = $CenterContainer/S1CharacterSelect
@onready var charselect_s2 = $CenterContainer/SCCharacterSelect
@onready var charselect_s3 = $CenterContainer/SFCharacterSelect
@onready var charselect_s4 = $CenterContainer/SKCharacterSelect
@onready var charselect_s5 = $CenterContainer/BBCharacterSelect
@onready var charselect_s6 = $CenterContainer/UNICharacterSelect
@onready var charselect_s7 = $CenterContainer/GGCharacterSelect
@onready var charselect_s8 = $CenterContainer/STCharacterSelect

@onready var season_button_s0 = $TabSelect/CategoriesHBox/Season0
@onready var season_button_s1 = $TabSelect/CategoriesHBox/Season1
@onready var season_button_s2 = $TabSelect/CategoriesHBox/Season2
@onready var season_button_s3 = $TabSelect/CategoriesHBox/Season3
@onready var season_button_s4 = $TabSelect/CategoriesHBox/Season4
@onready var season_button_s5 = $TabSelect/CategoriesHBox/Season5
@onready var season_button_s6 = $TabSelect/CategoriesHBox/Season6
@onready var season_button_s7 = $TabSelect/CategoriesHBox/Season7
@onready var season_button_s8 = $TabSelect/CategoriesHBox/Season8
@onready var custom_button = $TabSelect/CategoriesHBox2/Custom

var season_columns := {}
var season_column_enabled := {
	"season0": true,
	"season1": true,
	"season2": true,
	"season3": true,
	"season4": true,
	"season5": true,
	"season6": true,
	"season7": true,
	"season8": true,
}

#! Controls the custom deck entry independently of the season0 category.
var custom_button_enabled : bool = false

var current_season_id : String = ""

var default_char_id : String = "random"
var default_skin_index : int = 0
var _current_hover_key : String = ""

@onready var label_font_normal = 42
@onready var label_font_small = 32
@onready var label_length_threshold = 15

func _ready():
	season_columns = {
		"season0": {"node": charselect_s0, "button": season_button_s0},
		"season1": {"node": charselect_s1, "button": season_button_s1},
		"season2": {"node": charselect_s2, "button": season_button_s2},
		"season3": {"node": charselect_s3, "button": season_button_s3},
		"season4": {"node": charselect_s4, "button": season_button_s4},
		"season5": {"node": charselect_s5, "button": season_button_s5},
		"season6": {"node": charselect_s6, "button": season_button_s6},
		"season7": {"node": charselect_s7, "button": season_button_s7},
		"season8": {"node": charselect_s8, "button": season_button_s8},
	}
	_refresh_season_column_visibility()
	_show_first_enabled_season()
	set_custom_button_enabled(custom_button_enabled)

func update_hover(char_id, skin_index: int = 0):
	var hover_key := "%s:%d" % [char_id, skin_index]
	if hover_key == _current_hover_key:
		return
	_current_hover_key = hover_key
	if char_id == "random_s8":
		hover_label.text = "随机（S8）"
		_show_static_preview(load("res://assets/portraits/stlogo.png"))
	elif char_id == "random_s7":
		hover_label.text = "随机（S7）"
		_show_static_preview(load("res://assets/portraits/random.png"))
	elif char_id == "random_s6":
		hover_label.text = "随机（S6）"
		_show_static_preview(load("res://assets/portraits/unilogo.png"))
	elif char_id == "random_s5":
		hover_label.text = "随机（S5）"
		_show_static_preview(load("res://assets/portraits/blazbluelogo2.png"))
	elif char_id == "random_s4":
		hover_label.text = "随机（S4）"
		_show_static_preview(load("res://assets/portraits/sklogo.png"))
	elif char_id == "random_s3":
		hover_label.text = "随机（S3）"
		_show_static_preview(load("res://assets/portraits/sflogo.png"))
	elif char_id == "random_s2":
		hover_label.text = "随机（S2）"
		_show_static_preview(load("res://assets/portraits/sclogo.png"))
	elif char_id == "random_s1":
		hover_label.text = "随机（S1）"
		_show_static_preview(load("res://assets/portraits/redhorizon.png"))
	elif char_id == "random":
		hover_label.text = "随机（全部）"
		_show_static_preview(load("res://assets/portraits/exceedrandom.png"))
	elif char_id.begins_with("custom"):
		hover_label.text = "自订"
		_show_static_preview(load("res://assets/portraits/exceedrandom.png"))
	else:
		var deck = CardDataManager.get_deck_from_str_id(char_id)
		if deck:
			hover_label.text = deck['display_name']
			var preview_deck_id : String = _char_skin_manager().get_skin_deck_id(char_id, skin_index)
			# Keep character selection lightweight: use the cached square portrait
			# instead of loading and playing the full standing animation resource.
			_show_static_preview(_char_skin_manager().load_portrait_texture_for_deck_id(preview_deck_id))
		else:
			hover_label.text = "随机（全部）"
			_show_static_preview(load("res://assets/portraits/exceedrandom.png"))

	if len(hover_label.text) <= label_length_threshold:
		hover_label.set("theme_override_font_sizes/font_size", label_font_normal)
	else:
		hover_label.set("theme_override_font_sizes/font_size", label_font_small)

func _show_static_preview(texture : Texture2D) -> void:
	hover_portrait.texture = texture

func show_char_select(char_id : String, skin_index: int = 0):
	default_char_id = char_id
	default_skin_index = skin_index
	var selected_season_id := _get_character_season_id(char_id)
	if not selected_season_id.is_empty() and season_column_enabled.get(selected_season_id, false):
		show_season(selected_season_id)
	else:
		_show_first_enabled_season()
	update_hover(char_id, skin_index)

func _get_character_season_id(char_id : String) -> String:
	if char_id.begins_with("custom"):
		return "season0"
	if char_id.begins_with("random_s"):
		var season_text := char_id.trim_prefix("random_s").split("#", false, 1)[0]
		if season_text.is_valid_int():
			return "season%s" % season_text

	var deck = CardDataManager.get_deck(char_id)
	if deck and deck.has("season"):
		return "season%d" % int(deck["season"])
	return ""

func _char_skin_manager() -> Node:
	return get_node("/root/CharSkinManager")

func _on_background_button_pressed():
	close_character_select.emit()

func set_custom_button_enabled(enabled : bool) -> void:
	custom_button_enabled = enabled
	if not is_node_ready():
		return
	custom_button.visible = enabled

func set_season_column_enabled(season_id : String, enabled : bool) -> void:
	if not season_column_enabled.has(season_id):
		return
	season_column_enabled[season_id] = enabled
	if season_columns.is_empty():
		return
	if current_season_id == season_id and not enabled:
		current_season_id = ""
	_refresh_season_column_visibility()
	if current_season_id == "":
		_show_first_enabled_season()

func set_all_season_columns_enabled(enabled : bool) -> void:
	for season_id in season_column_enabled.keys():
		season_column_enabled[season_id] = enabled
	if season_columns.is_empty():
		return
	if current_season_id != "" and not season_column_enabled.get(current_season_id, false):
		current_season_id = ""
	_refresh_season_column_visibility()
	if current_season_id == "":
		_show_first_enabled_season()

func _show_first_enabled_season() -> void:
	if season_column_enabled.get("season1", false):
		show_season("season1")
		return
	for season_id in season_column_enabled.keys():
		if season_column_enabled[season_id]:
			show_season(season_id)
			return
	current_season_id = ""
	_refresh_season_column_visibility()

func _refresh_season_column_visibility() -> void:
	for season_id in season_columns.keys():
		var season_column = season_columns[season_id]
		var is_enabled : bool = season_column_enabled.get(season_id, true)
		season_column["node"].visible = is_enabled and season_id == current_season_id
		season_column["button"].visible = is_enabled
		season_column["button"].set_selected(is_enabled and season_id == current_season_id)

func show_season(season_id : String) -> bool:
	if not season_column_enabled.get(season_id, false):
		return false
	current_season_id = season_id
	_refresh_season_column_visibility()
	return true

func _on_char_button_on_pressed(character_id : String):
	if character_id.begins_with("season"):
		show_season(character_id)
	else:
		select_character.emit(character_id)

func _on_char_hover(char_id : String, enter : bool):
	if char_id.begins_with("season"):
		return

	if enter:
		update_hover(char_id)
	else:
		update_hover(default_char_id, default_skin_index)
