extends GutTest

const MainMenuScene = preload("res://scenes/menu/main_menu.tscn")
const VersusSplashScene = preload("res://scenes/menu/versus_splash.tscn")
const CharacterScene = preload("res://scenes/game/character.tscn")
const SpecterOriginalPortraitPath := "res://assets/portraits/specter.png"
const SpecterSkinPortraitPath := "res://assets/portraits_skin/specter_1.png"
const CarlswangeeSkinAnimationTexturePath := "res://assets/character_animations_skin/carlswangee_1/carlswangee_1.png"

var main_menu : MainMenu
var captured_vs_info = null
var game_logic : LocalGame
var game_image_loader : CardImageLoader
var versus_splash : VersusSplash
var character_preview : Character
var original_portraits_skin_value = null
var original_animations_skin_value = null
var original_exceed_change_skin_value = null
var original_buddy_skin_value = null

func before_each():
	var skin_config = _get_specter_skin_config()
	original_portraits_skin_value = skin_config.get("portraits_skin")
	original_animations_skin_value = skin_config.get("animations_skin")
	original_exceed_change_skin_value = skin_config.get("exceed_change_skin")
	original_buddy_skin_value = skin_config.get("buddy_skin")
	main_menu = MainMenuScene.instantiate()
	add_child(main_menu)
	main_menu.start_game.connect(_on_start_game)

func after_each():
	var skin_config = _get_specter_skin_config()
	if original_portraits_skin_value == null:
		skin_config.erase("portraits_skin")
	else:
		skin_config["portraits_skin"] = original_portraits_skin_value
	if original_animations_skin_value == null:
		skin_config.erase("animations_skin")
	else:
		skin_config["animations_skin"] = original_animations_skin_value
	if original_exceed_change_skin_value == null:
		skin_config.erase("exceed_change_skin")
	else:
		skin_config["exceed_change_skin"] = original_exceed_change_skin_value
	if original_buddy_skin_value == null:
		skin_config.erase("buddy_skin")
	else:
		skin_config["buddy_skin"] = original_buddy_skin_value

	if game_logic:
		game_logic.teardown()
		game_logic.free()
		game_logic = null
	if game_image_loader:
		game_image_loader.free()
		game_image_loader = null
	if main_menu:
		main_menu.free()
		main_menu = null
	if versus_splash:
		versus_splash.free()
		versus_splash = null
	if character_preview:
		character_preview.free()
		character_preview = null

func test_specter_skin_portrait_enabled_can_start_ai_game_and_take_turn():
	_get_specter_skin_config()["portraits_skin"] = true
	_run_specter_skin_flow(SpecterSkinPortraitPath)

func test_specter_skin_portrait_disabled_uses_original_and_can_take_turn():
	_get_specter_skin_config()["portraits_skin"] = false
	_run_specter_skin_flow(SpecterOriginalPortraitPath)

func test_skin_without_portrait_override_uses_base_character_portrait():
	assert_eq(
		_get_skin_manager().get_portrait_path_for_deck_id("enchantress_1"),
		"res://assets/portraits/enchantress.png",
	)

func test_missing_skin_portrait_override_uses_base_character_portrait():
	var skin_config = _get_specter_skin_config()
	var original_url = skin_config.get("portraits_url", "")
	skin_config["portraits_skin"] = true
	skin_config["portraits_url"] = "res://assets/portraits_skin/does_not_exist.png"

	assert_eq(_get_skin_manager().get_portrait_path_for_deck_id("specter_1"), SpecterOriginalPortraitPath)
	skin_config["portraits_url"] = original_url

func test_missing_character_portrait_uses_global_fallback():
	assert_eq(
		_get_skin_manager().get_portrait_path_for_deck_id("missing_portrait_character"),
		"res://assets/portraits/custom.png",
	)
	assert_not_null(_get_skin_manager().load_portrait_texture_for_deck_id("missing_portrait_character"))

func test_skin_filename_prefix_must_match_json_character_id():
	var valid_skin_data = {"id": "specter"}
	assert_true(CardDataManager._is_valid_skin_deck_file("specter_1.json", valid_skin_data, false))
	assert_false(CardDataManager._is_valid_skin_deck_file("ino_1.json", valid_skin_data, false))
	assert_false(CardDataManager._is_valid_skin_deck_file("specter_0.json", valid_skin_data, false))
	assert_false(CardDataManager._is_valid_skin_deck_file("specter_01.json", valid_skin_data, false))
	assert_false(CardDataManager._is_valid_skin_deck_file("missingcharacter_1.json", {"id": "missingcharacter"}, false))

func test_ino_single_image_skin_animation_loads():
	var sprite_frames = load("res://assets/character_animations_skin/ino_1/animations.tres") as SpriteFrames
	assert_not_null(sprite_frames)
	if not sprite_frames:
		return
	assert_true(sprite_frames.has_animation("idle"))
	assert_eq(sprite_frames.get_frame_count("idle"), 1)
	assert_not_null(sprite_frames.get_frame_texture("idle", 0))

func test_animations_skin_true_uses_skin_folder():
	_get_specter_skin_config()["animations_skin"] = true
	assert_eq(
		_get_skin_manager().get_animation_path_for_deck_id("specter_1"),
		"res://assets/character_animations_skin/specter_1/animations.tres",
	)

func test_animations_skin_false_uses_original_character_folder():
	_get_specter_skin_config()["animations_skin"] = false
	assert_eq(
		_get_skin_manager().get_animation_path_for_deck_id("specter_1"),
		"res://assets/character_animations/specter/animations.tres",
	)

func test_animations_skin_defaults_to_false_when_omitted():
	_get_specter_skin_config().erase("animations_skin")
	assert_eq(
		_get_skin_manager().get_animation_path_for_deck_id("specter_1"),
		"res://assets/character_animations/specter/animations.tres",
	)

func test_exceed_change_skin_defaults_to_false_when_omitted():
	_get_specter_skin_config().erase("exceed_change_skin")
	assert_false(_get_skin_manager().exceed_changes_skin_for_deck_id("specter_1"))

func test_exceed_change_skin_true_uses_matching_exceed_folder():
	var skin_config = _get_specter_skin_config()
	skin_config["animations_skin"] = true
	skin_config["exceed_change_skin"] = true
	assert_true(_get_skin_manager().exceed_changes_skin_for_deck_id("specter_1"))
	assert_eq(
		_get_skin_manager().get_animation_path_for_deck_id("specter_1_exceed"),
		"res://assets/character_animations_skin/specter_1_exceed/animations.tres",
	)
	assert_eq(
		_get_skin_manager().get_animation_path_for_deck_and_animation_id("specter_1", "specter_1_exceed"),
		"res://assets/character_animations_skin/specter_1_exceed/animations.tres",
	)

func test_exceed_change_skin_requires_skin_animation():
	var skin_config = _get_specter_skin_config()
	skin_config["animations_skin"] = false
	skin_config["exceed_change_skin"] = true
	assert_false(_get_skin_manager().exceed_changes_skin_for_deck_id("specter_1"))

func test_skin_without_exceed_change_skin_keeps_skin_resource_for_exceed_state():
	var skin_config = _get_carlswangee_skin_config()
	skin_config["animations_skin"] = true
	skin_config["exceed_change_skin"] = false
	assert_eq(
		_get_skin_manager().get_animation_path_for_deck_and_animation_id("carlswangee_1", "carlswangee_1_exceed"),
		"res://assets/character_animations_skin/carlswangee_1/animations.tres",
	)

func test_buddy_skin_defaults_to_false_when_omitted():
	_get_specter_skin_config().erase("buddy_skin")
	assert_eq(
		_get_skin_manager().get_animation_path_for_deck_and_animation_id("specter_1", "rachel_georgexiii"),
		"res://assets/character_animations/rachel_georgexiii/animations.tres",
	)

func test_buddy_skin_true_uses_matching_skin_folder():
	var skin_config = _get_specter_skin_config()
	skin_config["animations_skin"] = true
	skin_config["buddy_skin"] = true
	assert_eq(
		_get_skin_manager().get_animation_path_for_deck_and_animation_id("specter_1", "rachel_georgexiii"),
		"res://assets/character_animations_skin/rachel_georgexiii_1/animations.tres",
	)
	assert_eq(
		_get_skin_manager().get_animation_path_for_deck_and_animation_id("specter_1", "rachel_ivyblossom"),
		"res://assets/character_animations_skin/rachel_ivyblossom_1/animations.tres",
	)
	assert_eq(
		_get_skin_manager().get_animation_path_for_deck_and_animation_id("specter_1", "rachel_impishgypsophila"),
		"res://assets/character_animations_skin/rachel_impishgypsophila_1/animations.tres",
	)
	assert_eq(
		_get_skin_manager().get_animation_path_for_deck_and_animation_id("specter_1", "rachel_lightningrod"),
		"res://assets/character_animations_skin/rachel_lightningrod_1/animations.tres",
	)
	assert_eq(
		_get_skin_manager().get_animation_path_for_deck_and_animation_id("specter_1", "rachel_georgexiii_1"),
		"res://assets/character_animations_skin/rachel_georgexiii_1/animations.tres",
	)

func test_animations_skin_false_disables_buddy_skin_even_when_graphics_id_has_skin_suffix():
	var skin_config = _get_specter_skin_config()
	skin_config["animations_skin"] = false
	skin_config["buddy_skin"] = true
	assert_eq(
		_get_skin_manager().get_animation_path_for_deck_and_animation_id("specter_1", "rachel_georgexiii_1"),
		"res://assets/character_animations/rachel_georgexiii/animations.tres",
	)

func test_rachel_skin_deck_uses_suffixed_buddy_graphics_ids_directly():
	assert_eq(
		_get_skin_manager().get_animation_path_for_deck_and_animation_id("rachel_1", "rachel_ivyblossom_1"),
		"res://assets/character_animations_skin/rachel_ivyblossom_1/animations.tres",
	)
	assert_eq(
		_get_skin_manager().get_animation_path_for_deck_and_animation_id("rachel_1", "rachel_georgexiii_1"),
		"res://assets/character_animations_skin/rachel_georgexiii_1/animations.tres",
	)
	assert_eq(
		_get_skin_manager().get_animation_path_for_deck_and_animation_id("rachel_1", "rachel_impishgypsophila_1"),
		"res://assets/character_animations_skin/rachel_impishgypsophila_1/animations.tres",
	)
	assert_eq(
		_get_skin_manager().get_animation_path_for_deck_and_animation_id("rachel_1", "rachel_lightningrod_1"),
		"res://assets/character_animations_skin/rachel_lightningrod_1/animations.tres",
	)

func test_rachel_buddy_skin_resources_load_valid_textures():
	var animation_paths = [
		"res://assets/character_animations_skin/rachel_ivyblossom_1/animations.tres",
		"res://assets/character_animations_skin/rachel_georgexiii_1/animations.tres",
		"res://assets/character_animations_skin/rachel_impishgypsophila_1/animations.tres",
		"res://assets/character_animations_skin/rachel_lightningrod_1/animations.tres",
	]
	for animation_path in animation_paths:
		var sprite_frames = load(animation_path) as SpriteFrames
		assert_not_null(sprite_frames)
		if not sprite_frames:
			continue
		assert_true(sprite_frames.has_animation("idle"))
		assert_true(sprite_frames.get_frame_count("idle") > 0)
		assert_not_null(sprite_frames.get_frame_texture("idle", 0))

func test_buddy_skin_false_uses_original_buddy_folder():
	var skin_config = _get_specter_skin_config()
	skin_config["animations_skin"] = true
	skin_config["buddy_skin"] = false
	assert_eq(
		_get_skin_manager().get_animation_path_for_deck_and_animation_id("specter_1", "rachel_georgexiii"),
		"res://assets/character_animations/rachel_georgexiii/animations.tres",
	)

func test_random_character_selection_excludes_skin_decks():
	assert_true(CardDataManager._is_random_selectable_deck(CardDataManager.get_deck_from_str_id("specter")))
	assert_false(CardDataManager._is_random_selectable_deck(CardDataManager.get_deck_from_str_id("specter_1")))
	assert_true(CardDataManager._is_random_selectable_deck(CardDataManager.get_deck_from_str_id("carlswangee")))
	assert_false(CardDataManager._is_random_selectable_deck(CardDataManager.get_deck_from_str_id("carlswangee_1")))

func test_skin_animation_stays_on_skin_resource_after_exceed():
	character_preview = CharacterScene.instantiate()
	add_child(character_preview)

	var skin_deck = CardDataManager.get_deck_from_str_id("carlswangee_1")
	assert_not_null(skin_deck)
	if not skin_deck:
		return

	await character_preview.load_character(null, skin_deck, skin_deck["id"])
	var scale_before_exceed = character_preview.scale
	assert_eq(
		character_preview.animation.sprite_frames.get_frame_texture("idle", 0).resource_path,
		CarlswangeeSkinAnimationTexturePath,
	)

	await character_preview.set_exceed(true, null, skin_deck, skin_deck["exceed_animation"])
	assert_true(character_preview.exceed_icon.visible)
	assert_eq(character_preview.scale, scale_before_exceed)
	assert_eq(
		character_preview.animation.sprite_frames.get_frame_texture("idle", 0).resource_path,
		CarlswangeeSkinAnimationTexturePath,
	)

func _run_specter_skin_flow(expected_portrait_path: String) -> void:
	assert_true(FileAccess.file_exists("res://data/decks_skin/specter_1.json"))
	assert_true(ResourceLoader.exists("res://assets/character_animations_skin/specter_1/animations.tres", "SpriteFrames"))
	assert_not_null(load("res://assets/character_animations_skin/specter_1/animations.tres"))
	assert_true(ResourceLoader.exists(expected_portrait_path, "Texture2D"))

	var skin_deck = CardDataManager.get_deck_from_str_id("specter_1")
	assert_not_null(skin_deck)
	if not skin_deck:
		return
	assert_eq(skin_deck["id"], "specter_1")

	main_menu.update_char("specter", true)
	var skin_buttons = main_menu.get_node("PlayerSkinPanel/SkinButtons")
	assert_eq(skin_buttons.get_child_count(), 2)
	skin_buttons.get_child(1).pressed.emit()
	assert_eq(main_menu.player_char_portrait.texture.resource_path, expected_portrait_path)

	captured_vs_info = null
	main_menu._on_start_button_pressed()
	assert_not_null(captured_vs_info)
	if not captured_vs_info:
		return
	assert_eq(captured_vs_info["player_deck"]["id"], "specter_1")
	versus_splash = VersusSplashScene.instantiate()
	add_child(versus_splash)
	versus_splash.set_info(captured_vs_info)
	assert_eq(versus_splash.me_portrait.texture.resource_path, expected_portrait_path)

	game_image_loader = CardImageLoader.new(true)
	game_logic = LocalGame.new(game_image_loader)
	game_logic.initialize_game(
		captured_vs_info["player_deck"],
		captured_vs_info["opponent_deck"],
		"p1",
		"CPU",
		Enums.PlayerId.PlayerId_Player,
		1,
	)
	game_logic.draw_starting_hands_and_begin()
	game_logic.do_mulligan(game_logic.player, [])
	game_logic.do_mulligan(game_logic.opponent, [])
	assert_true(game_logic.do_prepare(game_logic.player))

func _on_start_game(vs_info):
	captured_vs_info = vs_info

func _get_skin_manager() -> Node:
	return get_node("/root/CharSkinManager")

func _get_specter_skin_config() -> Dictionary:
	return _get_skin_manager().CHARACTER_SKINS["specter"]["skins"][1]

func _get_carlswangee_skin_config() -> Dictionary:
	return _get_skin_manager().CHARACTER_SKINS["carlswangee"]["skins"][1]