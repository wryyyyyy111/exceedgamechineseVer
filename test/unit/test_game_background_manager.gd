extends GutTest

const BackgroundManager = preload("res://globals/game_background_manager.gd")

func after_each():
	BackgroundManager._mobile_web_runtime_override = null
	MobileResourceBudget.reset()

func test_background_entries_drive_labels_and_order():
	assert_eq(BackgroundManager.get_background_ids(), ["random", "classic", "BG1", "BG2", "BG3", "BG4", "BG5", "BG6", "BG7", "BG8", "BG9", "BG10", "BG11", "BG22", "BG12", "BG13", "BG14", "BG15", "BG16", "BG17", "BG18", "BG19", "BG20", "BG21"])
	assert_eq(BackgroundManager.get_background_label("random"), "每场随机")
	assert_eq(BackgroundManager.get_background_label("classic"), "BG0 经典")
	assert_eq(BackgroundManager.get_background_label("BG1"), "BG1 森林")
	assert_eq(BackgroundManager.get_background_label("BG2"), "BG2 遗迹")

func test_random_background_resolves_to_non_random_background():
	var resolved_background_id := BackgroundManager.resolve_background_id("random")
	assert_ne(resolved_background_id, "random")
	assert_true(BackgroundManager.get_randomizable_background_ids().has(resolved_background_id))

func test_background_path_uses_url_and_image_ids():
	BackgroundManager._mobile_web_runtime_override = false
	assert_eq(BackgroundManager.get_background_resource_path("BG2"), "res://assets/ui/BG2/BG2.jpg")
	assert_not_null(await BackgroundManager.load_background_texture("BG2"))

func test_mobile_main_menu_background_path_uses_phone_picture_when_available():
	BackgroundManager._mobile_web_runtime_override = true
	assert_eq(BackgroundManager.get_main_menu_background_resource_path("MP1"), "res://assets/phone/mainmenu_picture/mp1/1.jpg")

func test_native_runtime_uses_configured_mobile_resource_flag():
	BackgroundManager._mobile_web_runtime_override = null
	var expected_path := "res://assets/phone/mainmenu_picture/mp1/1.jpg" if MobileRuntimeFlags.is_mobile_resource_runtime() else "res://assets/mainmenu_picture/mp1/1.jpg"
	assert_eq(BackgroundManager.get_main_menu_background_resource_path("MP1"), expected_path)

func test_mobile_background_path_uses_phone_ui_when_available():
	BackgroundManager._mobile_web_runtime_override = true
	assert_eq(BackgroundManager.get_background_resource_path("BG2"), "res://assets/phone/ui/BG2/BG2.jpg")
	assert_eq(BackgroundManager.get_arena_resource_path("BG2", "B", 9), "res://assets/phone/ui/standard_arena/B9.png")
	assert_eq(
		CdnAssetLoader.get_phone_texture_original_size("res://assets/phone/ui/BG2/BG2.jpg"),
		Vector2i(2560, 1440))
	assert_eq(
		CdnAssetLoader.get_phone_texture_display_scale("res://assets/phone/ui/standard_arena/B9.png"),
		0.8)

func test_phone_texture_visual_size_uses_oss_scale_report():
	assert_eq(
		CdnAssetLoader.get_phone_texture_original_size("res://assets/phone/decks_official/anji/character_exceeded_cardback.jpg"),
		Vector2i(4500, 4200))
	assert_eq(
		CdnAssetLoader.get_phone_texture_display_scale("res://assets/phone/character_skin/cviper_1/character_default.jpg"),
		0.79)

func test_standard_arena_uses_shared_track_directory():
	BackgroundManager._mobile_web_runtime_override = false
	var resource_path := BackgroundManager.get_arena_resource_path("BG2", "B", 9)
	assert_eq(
		resource_path,
		"res://assets/ui/standard_arena/B9.png")
	assert_not_null(await BackgroundManager.load_arena_texture("BG2", "B", 9))
	assert_false(BackgroundManager._texture_cache.has(resource_path))

func test_nonstandard_arena_uses_background_track_directory():
	BackgroundManager._mobile_web_runtime_override = false
	assert_eq(
		BackgroundManager.get_arena_resource_path("BG1", "R", 1),
		"res://assets/ui/BG1/arena/R1.png")
	assert_not_null(await BackgroundManager.load_arena_texture("BG1", "R", 1))

func test_wide_character_neighbor_track_paths_exist_for_standard_arena():
	# Tinker tank occupies center +/- 1, so all three mapped arena slots should resolve.
	var center_location = 5
	var mapped_locations = [center_location - 1, center_location, center_location + 1]
	for board_location in mapped_locations:
		var path = BackgroundManager.get_arena_resource_path("BG2", "B", 10 - board_location)
		assert_true(path.ends_with(".png"))
		assert_not_null(await BackgroundManager.load_arena_texture("BG2", "B", 10 - board_location), str(board_location))

func test_unknown_background_id_uses_default():
	assert_eq(BackgroundManager.normalize_background_id("missing"), "classic")

func test_clear_match_texture_cache_preserves_main_menu_textures():
	var match_path := "res://assets/ui/test_match_texture.png"
	var menu_path := "res://assets/mainmenu_picture/test_menu_texture.jpg"
	BackgroundManager._texture_cache[match_path] = null
	BackgroundManager._texture_cache[menu_path] = null

	BackgroundManager.clear_match_texture_cache()

	assert_false(BackgroundManager._texture_cache.has(match_path))
	assert_true(BackgroundManager._texture_cache.has(menu_path))
	BackgroundManager._texture_cache.erase(menu_path)

func test_clear_main_menu_texture_cache_preserves_match_textures():
	var match_path := "res://assets/ui/test_match_texture.png"
	var menu_path := "res://assets/mainmenu_picture/test_menu_texture.jpg"
	var phone_menu_path := "res://assets/phone/mainmenu_picture/test_menu_texture.jpg"
	BackgroundManager._texture_cache[match_path] = null
	BackgroundManager._texture_cache[menu_path] = null
	BackgroundManager._texture_cache[phone_menu_path] = null

	BackgroundManager.clear_main_menu_texture_cache()

	assert_true(BackgroundManager._texture_cache.has(match_path))
	assert_false(BackgroundManager._texture_cache.has(menu_path))
	assert_false(BackgroundManager._texture_cache.has(phone_menu_path))
	BackgroundManager._texture_cache.erase(match_path)
