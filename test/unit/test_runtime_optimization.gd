extends GutTest

var game_logic : LocalGame

const CardBaseScene = preload("res://scenes/card/card_base.tscn")
const CardPopoutScene = preload("res://scenes/game/card_popout.tscn")
const CharacterScene = preload("res://scenes/game/character.tscn")
const GameScene = preload("res://scenes/game/game.tscn")
const MainScript = preload("res://scenes/main.gd")

class TestMobileCardImageLoader extends CardImageLoader:
	func _is_mobile_web() -> bool:
		return true

class TestDesktopCardImageLoader extends CardImageLoader:
	func _is_mobile_web() -> bool:
		return false

class TestMobileCharacter extends Character:
	func _is_mobile_web() -> bool:
		return true

func _instantiate_mobile_character_scene() -> Character:
	var character := CharacterScene.instantiate() as Character
	character.set_script(TestMobileCharacter)
	return character

func test_card_popout_applies_configuration_set_before_ready():
	var popout : CardPopout = CardPopoutScene.instantiate()
	popout.set_title("加载卡牌中...")
	popout.set_amount("已加载 0/17")
	popout.set_instructions(null)
	popout.set_reference_toggle("", false)
	add_child_autofree(popout)
	await get_tree().process_frame

	assert_eq(popout.title_label.text, "加载卡牌中...")
	assert_eq(popout.title_amount.text, "已加载 0/17")
	assert_false(popout.instruction_box.visible)
	assert_false(popout.toggle_container.visible)

func _make_test_shared_atlas(columns: int, rows: int, cell_size: int) -> Image:
	var atlas = Image.create(columns * cell_size, rows * cell_size, false, Image.FORMAT_RGBA8)
	for y in range(rows):
		for x in range(columns):
			var index = y * columns + x
			var color = Color(
				float((index * 37) % 255) / 255.0,
				float((index * 67) % 255) / 255.0,
				float((index * 97) % 255) / 255.0,
				1.0)
			atlas.fill_rect(Rect2i(x * cell_size, y * cell_size, cell_size, cell_size), color)
	return atlas

func _get_texture_center_color(texture) -> Color:
	if texture is AtlasTexture:
		var atlas_image = texture.atlas.get_image()
		var region = texture.region
		var atlas_center = Vector2i(
			int(round(region.position.x + region.size.x * 0.5)),
			int(round(region.position.y + region.size.y * 0.5)))
		return atlas_image.get_pixelv(atlas_center)
	var image = texture.get_image()
	var center = Vector2i(image.get_width() >> 1, image.get_height() >> 1)
	return image.get_pixelv(center)

func _assert_color_close(actual: Color, expected: Color):
	assert_almost_eq(actual.r, expected.r, 0.02)
	assert_almost_eq(actual.g, expected.g, 0.02)
	assert_almost_eq(actual.b, expected.b, 0.02)

func _make_distinct_index_color(index: int) -> Color:
	return Color(
		float((index * 37) % 255) / 255.0,
		float((index * 67) % 255) / 255.0,
		float((index * 97) % 255) / 255.0,
		1.0)

func _assert_scaled_season_atlas_card_size(
		season: int,
		deck_id: String,
		atlas_size: Vector2i,
		expected_card_size: Vector2):
	var loader = TestMobileCardImageLoader.new(false)
	add_child_autofree(loader)
	loader.set_runtime_card_scale(0.5)
	var atlas_url = "https://example.com/season_%s_%s_scaled.png" % [season, deck_id]
	var atlas_image = Image.create(atlas_size.x, atlas_size.y, false, Image.FORMAT_RGBA8)
	atlas_image.fill(Color.WHITE)
	ImageCache.cache_image(atlas_url, atlas_image)
	loader.load_image_page_indexed({
		"url": atlas_url,
		"multiple_cards": true,
		"season": season,
		"deck_id": deck_id,
		"force_cropped_textures": true,
	}, 0)

	await loader._process_request_queue()
	var texture = loader.loaded_images[atlas_url][0] as ImageTexture
	assert_not_null(texture)
	assert_eq(texture.get_size(), expected_card_size)
	loader.teardown()

func _assert_report_scaled_atlas_card_size(
		season: int,
		deck_id: String,
		resource_path: String,
		atlas_size: Vector2i,
		expected_card_size: Vector2):
	var loader = TestMobileCardImageLoader.new(false)
	add_child_autofree(loader)
	var original_url = CardImageLoader.CDN_IMAGE_ROOT + resource_path
	var phone_url = CardImageLoader.CDN_PHONE_IMAGE_ROOT + resource_path
	var atlas_image = Image.create(atlas_size.x, atlas_size.y, false, Image.FORMAT_RGBA8)
	atlas_image.fill(Color.WHITE)
	ImageCache.cache_image(phone_url, atlas_image)
	loader.load_image_page_indexed({
		"url": original_url,
		"multiple_cards": true,
		"season": season,
		"deck_id": deck_id,
	}, 0)

	await loader._process_request_queue()
	var texture = loader.loaded_images[phone_url][0] as ImageTexture
	assert_not_null(texture)
	assert_eq(texture.get_size(), expected_card_size)
	loader.teardown()

func _make_reference_source_card(card_id: int, label: String = "") -> CardBase:
	var card : CardBase = CardBaseScene.instantiate()
	add_child_autofree(card)
	card.initialize_simple(card_id, null, null, "Card %d" % card_id, "Boost %d" % card_id)
	card.flip_card_to_front(true)
	if label != "":
		card.set_label(label)
	else:
		card.set_remaining_count(card_id)
	return card

func before_each():
	game_logic = LocalGame.new(null)
	add_child_autofree(game_logic)

func after_each():
	game_logic.decision_info.free()

func test_combat_log_can_read_only_new_entries():
	game_logic._append_log_full(Enums.LogType.LogType_Default, null, "first")
	game_logic._append_log_full(Enums.LogType.LogType_Action, null, "second")
	game_logic._append_log_full(Enums.LogType.LogType_Effect, null, "third")

	assert_eq(game_logic.get_combat_log_size(), 3)
	assert_eq(
		game_logic.get_combat_log([
			Enums.LogType.LogType_Default,
			Enums.LogType.LogType_Action,
			Enums.LogType.LogType_Effect,
		], 1),
		"*second\nthird")

func test_combat_log_range_keeps_filtering_and_clamps_cursor():
	game_logic._append_log_full(Enums.LogType.LogType_Default, null, "always")
	game_logic._append_log_full(Enums.LogType.LogType_Action, null, "action")
	game_logic._append_log_full(Enums.LogType.LogType_Effect, null, "effect")

	assert_eq(
		game_logic.get_combat_log([Enums.LogType.LogType_Default], -10),
		"**always")
	assert_eq(game_logic.get_combat_log([Enums.LogType.LogType_Default], 99), "")

func test_long_combat_log_can_render_a_bounded_tail():
	for index in range(10000):
		game_logic._append_log_full(Enums.LogType.LogType_Default, null, "entry_%d" % index)

	var bounded_log = game_logic.get_combat_log(
		[Enums.LogType.LogType_Default],
		game_logic.get_combat_log_size() - Game.CombatLogVisibleEntryLimit)
	var lines = bounded_log.split("\n")
	assert_eq(lines.size(), Game.CombatLogVisibleEntryLimit)
	assert_eq(lines[0], "**entry_9500")
	assert_eq(lines[-1], "**entry_9999")

func test_web_runtime_animation_delay_only_shrinks_for_backlog():
	var web_speed := GlobalSettings.get_current_web_animation_speed()
	assert_eq(Game.get_runtime_animation_delay(1.0, 20, false), 1.0)
	assert_eq(Game.get_runtime_animation_delay(1.0, 8, true), 1.0 / web_speed)
	assert_eq(Game.get_runtime_animation_delay(1.0, 9, true, true), 0.25 / web_speed)
	assert_eq(Game.get_runtime_animation_delay(0.2, 20, true, true), 0.1 / web_speed)

func test_web_runtime_animation_delay_keeps_full_visual_delay_when_backlog_judge_disabled():
	var web_speed := GlobalSettings.get_current_web_animation_speed()
	assert_eq(Game.get_runtime_animation_delay(1.0, 9, true, false), 1.0 / web_speed)
	assert_eq(Game.get_runtime_animation_delay(0.2, 20, true, false), 0.2 / web_speed)

func test_global_web_runtime_animation_settings_are_valid():
	assert_eq(GlobalSettings.phone_web_speed, 1.5)
	assert_gt(GlobalSettings.phone_animation_final_scaling_adjust, 0.0)
	assert_gt(GlobalSettings.other_web_speed, 0.0)
	assert_true(GlobalSettings.phone_skip_web_judge)
	assert_false(GlobalSettings.other_skip_web_judge)
	assert_eq(
		Game.get_runtime_event_budget_for_health_state(
			Game.RuntimeHealthState.RuntimeHealthState_Backlogged,
			false),
		Game.WebRuntimeEventBudgetUnlimited)

func test_runtime_batch_yield_only_on_web_runtime_thresholds():
	assert_false(Game.should_yield_runtime_batch(4, Game.WebRuntimeLoadYieldBatchSize, false))
	assert_false(Game.should_yield_runtime_batch(3, Game.WebRuntimeLoadYieldBatchSize, true))
	assert_true(Game.should_yield_runtime_batch(4, Game.WebRuntimeLoadYieldBatchSize, true))
	assert_false(Game.should_yield_runtime_batch(5, Game.WebRuntimeLoadYieldBatchSize, true))
	assert_true(Game.should_yield_runtime_batch(6, Game.WebRuntimeEventYieldBatchSize, true))
	assert_eq(Game.get_runtime_load_yield_batch_size(false), Game.WebRuntimeLoadYieldBatchSize)
	assert_eq(Game.get_runtime_load_yield_batch_size(true), Game.MobileWebRuntimeLoadYieldBatchSize)
	assert_eq(Game.MobileWebRuntimeLoadYieldBatchSize, 1)
	assert_eq(Game.WebRuntimeArenaVisualYieldFrames, 1)
	assert_eq(Game.WebRuntimeRotationSettleFrames, 2)
	assert_eq(Game.WebRuntimeMaximumInvalidViewportRetries, 8)
	assert_eq(MainScript.get_runtime_game_reveal_frames(false), MainScript.WebRuntimeGameRevealFrames)
	assert_eq(MainScript.get_runtime_game_reveal_frames(true), MainScript.MobileWebRuntimeGameRevealFrames)
	assert_eq(MainScript.WebRuntimeGameRevealFrames, 2)
	assert_eq(MainScript.MobileWebRuntimeGameRevealFrames, 20)
	assert_eq(MainScript.get_versus_splash_timeout(false), MainScript.VersusSplashTimeout)
	assert_eq(MainScript.get_versus_splash_timeout(true), MainScript.MobileWebVersusSplashTimeout)
	assert_eq(MainScript.VersusSplashTimeout, 3.0)
	assert_eq(MainScript.MobileWebVersusSplashTimeout, 5.0)
	assert_eq(MainMenu.MobileWebMainMenuStartupYieldFrames, 2)
	assert_true(ResourceLoader.exists(MainMenu.MainMenuBgmPath, "AudioStream"))
	assert_true(ResourceLoader.exists(MainMenu.MatchAvailableAudioPath, "AudioStream"))
	var main_menu_scene_file := FileAccess.open("res://scenes/menu/main_menu.tscn", FileAccess.READ)
	assert_not_null(main_menu_scene_file)
	var main_menu_scene_text := main_menu_scene_file.get_as_text()
	assert_false(main_menu_scene_text.contains("res://assets/mainmenu_picture/mp1/1.jpg"))
	assert_false(main_menu_scene_text.contains("res://assets/sounds/mainmenu_bgm.mp3"))
	assert_false(main_menu_scene_text.contains("autoplay = true"))
	assert_true(main_menu_scene_text.contains("[node name=\"CharSelectBackdrop\" type=\"TextureRect\" parent=\".\"]"))
	assert_true(Game.is_rotation_layout_request_current(4, 4))
	assert_false(Game.is_rotation_layout_request_current(4, 5))
	assert_false(Game.is_rotation_viewport_size_valid(Vector2(319, 720)))
	assert_false(Game.is_rotation_viewport_size_valid(Vector2(1280, 239)))
	assert_true(Game.is_rotation_viewport_size_valid(Vector2(320, 240)))
	assert_eq(
		Game.get_rotation_safe_position(Vector2(2000, -900), Vector2(150, 100), Vector2(800, 600)),
		Vector2(800, -100))
	assert_eq(
		Game.get_rotation_safe_position(Vector2(300, 200), Vector2(150, 100), Vector2(800, 600)),
		Vector2(300, 200))

func test_cdn_asset_loader_maps_requested_resource_roots():
	var paths := [
		"res://assets/character_animations/akuma/idle/akumaidle.png",
		"res://assets/character_animations_custom/jinglechunshui/animations.tres",
		"res://assets/character_animations_skin/akuma_1/animations.tres",
		"res://assets/mainmenu_picture/mp1/1.jpg",
		"res://assets/ui/BG2/BG2.jpg",
		"res://assets/phone/character_animations/akuma/idle/akumaidle.png",
		"res://assets/phone/character_animations_custom/jinglechunshui/animations.tres",
		"res://assets/phone/character_animations_skin/akuma_1/animations.tres",
		"res://assets/phone/mainmenu_picture/mp1/1.jpg",
		"res://assets/phone/ui/BG2/BG2.jpg",
	]
	for path in paths:
		assert_true(CdnAssetLoader.is_cdn_mapped_res_path(path), path)
		var expected_url: String = "https://cdn.exceedcntyd.com/assets/phone/" + path.trim_prefix("res://assets/phone/") if path.begins_with("res://assets/phone/") else "https://cdn.exceedcntyd.com/assets/" + path.trim_prefix("res://assets/")
		expected_url += "?v=" + CdnAssetLoader.CDN_ASSET_CACHE_BUSTER + "-" + GlobalSettings.ClientVersionString
		assert_eq(CdnAssetLoader.res_path_to_cdn_url(path), expected_url)
	assert_true(CdnAssetLoader.is_cdn_mapped_res_path("res://assets/portraits/akuma.png"))
	assert_eq(
		Character._get_phone_character_texture_path("res://assets/portraits/vincent.png"),
		"res://assets/phone/portraits/vincent.png")

func test_character_animation_tres_parser_preserves_frames_and_metadata():
	var file := FileAccess.open("res://assets/character_animations/akuma/animations.tres", FileAccess.READ)
	assert_not_null(file)
	var parsed := Character._parse_sprite_frames_tres(file.get_as_text(), "res://assets/character_animations/akuma")
	assert_eq(parsed["texture_paths"].size(), 3)
	assert_eq(parsed["animations"].size(), 3)
	assert_eq(parsed["metadata"].get("flip", false), true)
	assert_eq(parsed["metadata"].get("scaling", 0.0), 1.8)
	var idle_animation = parsed["animations"].filter(func(animation): return animation["name"] == "idle")[0]
	assert_eq(idle_animation["frames"].size(), 10)
	var first_idle_atlas_id = idle_animation["frames"][0]["atlas_id"]
	assert_eq(parsed["atlas_defs"][first_idle_atlas_id]["region"], Rect2(0, 0, 100, 152))

func test_cdn_loader_keeps_local_animation_description_available():
	var tres_text := await CdnAssetLoader.load_text("res://assets/character_animations/akuma/animations.tres")
	assert_true(tres_text.begins_with("[gd_resource type=\"SpriteFrames\""))
	assert_true(tres_text.contains("akumaidle.png"))
	assert_true(FileAccess.file_exists(CdnAssetLoader.ANIMATION_MANIFEST_PATH))
	var manifest_text := CdnAssetLoader._get_animation_manifest_text("res://assets/character_animations/akuma/animations.tres")
	assert_true(manifest_text.begins_with("[gd_resource type=\"SpriteFrames\""))
	assert_true(manifest_text.contains("akumaidle.png"))

func test_character_animation_tres_parser_supports_direct_texture_frames():
	var file := FileAccess.open("res://assets/character_animations/hakumen/animations.tres", FileAccess.READ)
	assert_not_null(file)
	var parsed := Character._parse_sprite_frames_tres(file.get_as_text(), "res://assets/character_animations/hakumen")
	assert_eq(parsed["animations"].size(), 1)
	assert_eq(parsed["animations"][0]["frames"].size(), 1)
	assert_eq(parsed["animations"][0]["frames"][0]["texture_id"], "1_ioics")

func test_character_animation_tres_parser_prefers_cdn_texture_path():
	var tres_text := '[ext_resource type="Texture2D" uid="uid://c6sdqdem06bca" path="res://assets/portraits/custom.png" id="idle"] ; cdn_path="res://assets/character_animations/example/idle.png"'
	var parsed := Character._parse_sprite_frames_tres(tres_text, "res://assets/character_animations/example")
	assert_eq(parsed["texture_paths"].get("idle", ""), "res://assets/character_animations/example/idle.png")

func test_character_animation_loads_local_structure_with_remote_texture():
	var character := Character.new()
	autofree(character)
	var texture := await CdnAssetLoader.load_texture(
		"res://assets/character_animations/akuma/idle/akumaidle.png",
		"AnimationTest",
		"visible",
		true)
	assert_not_null(texture)
	var frames := await character._load_cdn_sprite_frames(
		"res://assets/character_animations/akuma/animations.tres", false)
	assert_not_null(frames)
	assert_true(frames.has_animation("idle"))
	assert_gt(frames.get_frame_count("idle"), 0)
	assert_not_null(frames.get_frame_texture("idle", 0))

func test_mobile_remote_animation_uses_phone_scale_for_display_compensation():
	var character := TestMobileCharacter.new()
	autofree(character)
	var frames := await character._load_cdn_sprite_frames(
		"res://assets/character_animations/emogine/animations.tres", false)
	assert_not_null(frames)
	var expected_scale := Character._get_phone_character_texture_scale("res://assets/character_animations/emogine/emogine.png")
	assert_almost_eq(character.mobile_texture_scale_for_display, expected_scale, 0.001)

func test_mobile_remote_ryu_atlas_preserves_authored_regions():
	var character := TestMobileCharacter.new()
	autofree(character)
	var frames := await character._load_cdn_sprite_frames(
		"res://assets/character_animations/ryu/animations.tres", false)
	assert_not_null(frames)
	assert_eq(frames.get_frame_count(&"idle"), 7)
	var first_frame := frames.get_frame_texture(&"idle", 0) as AtlasTexture
	var second_frame := frames.get_frame_texture(&"idle", 1) as AtlasTexture
	assert_not_null(first_frame)
	assert_not_null(second_frame)
	assert_eq(first_frame.region, Rect2(0, 0, 61, 112))
	assert_eq(second_frame.region, Rect2(82, 0, 61, 112))
	assert_same(first_frame.atlas, second_frame.atlas)

func test_mobile_remote_animation_refreshes_display_scale_between_forms():
	var character := TestMobileCharacter.new()
	autofree(character)
	var normal_frames := await character._load_cdn_sprite_frames(
		"res://assets/character_animations/emogine/animations.tres", false)
	assert_not_null(normal_frames)
	var expected_normal_scale := Character._get_phone_character_texture_scale("res://assets/character_animations/emogine/emogine.png")
	assert_almost_eq(character.mobile_texture_scale_for_display, expected_normal_scale, 0.001)

	var exceed_frames := await character._load_cdn_sprite_frames(
		"res://assets/character_animations/emogine_exceed/animations.tres", false)
	assert_not_null(exceed_frames)
	var expected_exceed_scale := Character._get_phone_character_texture_scale("res://assets/character_animations/emogine_exceed/emogine_exceed.png")
	assert_almost_eq(character.mobile_texture_scale_for_display, expected_exceed_scale, 0.001)

func test_mobile_emogine_exceed_preserves_desktop_relative_visual_size():
	var deck := CardDataManager.get_deck_from_str_id("emogine")
	var character := _instantiate_mobile_character_scene()
	add_child_autofree(character)
	var loader := TestMobileCardImageLoader.new(false)
	add_child_autofree(loader)
	await character.load_character(loader, deck, "emogine", false)
	var normal_scale := character.scale
	var normal_texture_scale := Character._get_phone_character_texture_scale(
		"res://assets/character_animations/emogine/emogine.png")
	var exceed_texture_scale := Character._get_phone_character_texture_scale(
		"res://assets/character_animations/emogine_exceed/emogine_exceed.png")
	var desktop_exceed_frames := load(
		"res://assets/character_animations/emogine_exceed/animations.tres") as SpriteFrames
	var desktop_relative_scaling := float(desktop_exceed_frames.get_meta("scaling"))

	await character.set_exceed(true, loader, deck, deck["exceed_animation"])

	var expected_scale := normal_scale * desktop_relative_scaling * normal_texture_scale / exceed_texture_scale
	assert_almost_eq(character.scale.x, expected_scale.x, 0.001)
	assert_almost_eq(character.scale.y, expected_scale.y, 0.001)
	loader.teardown()

func test_mobile_animation_falls_back_to_desktop_texture_when_phone_download_fails():
	var animation_path := "res://assets/character_animations/test_phone_fallback/animations.tres"
	var texture_path := "res://assets/character_animations/test_phone_fallback/idle.png"
	var animation_url := CdnAssetLoader.res_path_to_cdn_url(animation_path)
	var texture_url := CdnAssetLoader.res_path_to_cdn_url(texture_path)
	var source_image := Image.create(8, 6, false, Image.FORMAT_RGBA8)
	source_image.fill(Color.WHITE)
	CdnAssetLoader.loaded_text[animation_url] = '[gd_resource type="SpriteFrames" format=3]\n\n[ext_resource type="Texture2D" path="res://assets/portraits/custom.png" id="idle"] ; cdn_path="%s"\n\n[resource]\nanimations = [{\n"frames": [{\n"duration": 1.0,\n"texture": ExtResource("idle")\n}],\n"loop": true,\n"name": &"idle",\n"speed": 5.0\n}]' % texture_path
	CdnAssetLoader.loaded_textures[texture_url] = ImageTexture.create_from_image(source_image)

	var character := TestMobileCharacter.new()
	autofree(character)
	var frames := await character._load_cdn_sprite_frames(animation_path, false)

	assert_not_null(frames)
	assert_true(frames.has_animation("idle"))
	assert_eq(frames.get_frame_count("idle"), 1)
	assert_eq(frames.get_frame_texture("idle", 0).get_size(), Vector2(8, 6))
	CdnAssetLoader.loaded_text.erase(animation_url)
	CdnAssetLoader.loaded_textures.erase(texture_url)

func test_mobile_emogine_idle_uses_metadata_scaling_without_runtime_compensation():
	var character := _instantiate_mobile_character_scene()
	add_child_autofree(character)
	var loader := TestMobileCardImageLoader.new(false)
	add_child_autofree(loader)
	await character.load_character(loader, {"id": "emogine"}, "emogine", false)
	assert_almost_eq(character.runtime_texture_scale_compensation, 1.0, 0.01)
	var expected_scaling := 0.065 / Character._get_phone_character_texture_scale("res://assets/character_animations/emogine/emogine.png")
	assert_almost_eq(character.animation.sprite_frames.get_meta("scaling"), expected_scaling, 0.01)
	loader.teardown()

func test_mobile_reese_idle_uses_report_scale_when_desktop_reference_incomplete():
	var character := _instantiate_mobile_character_scene()
	add_child_autofree(character)
	var loader := TestMobileCardImageLoader.new(false)
	add_child_autofree(loader)
	await character.load_character(loader, {"id": "reese"}, "reese", false)
	var expected_scale := Character._get_phone_character_texture_scale("res://assets/character_animations/reese/reese.png")
	assert_almost_eq(character.runtime_texture_scale_compensation, 1.0, 0.01)
	assert_almost_eq(character.animation.sprite_frames.get_meta("scaling"), 0.25 / expected_scale, 0.01)
	loader.teardown()

func test_mobile_animation_metadata_scaling_uses_report_ratio():
	var character := TestMobileCharacter.new()
	autofree(character)
	var frames := SpriteFrames.new()
	frames.set_meta("scaling", 0.14)
	character._apply_mobile_animation_scaling_metadata(frames, 0.79)
	assert_almost_eq(frames.get_meta("scaling"), 0.14 / 0.79, 0.001)
	assert_eq(
		Character._scale_mobile_web_rect_for_animation(Rect2(10, 20, 30, 40), 0.14, 0.14 / 0.79),
		Rect2(7.9, 15.8, 23.7, 31.6))
	assert_eq(
		Character._scale_mobile_web_rect_to_atlas(Rect2(240, 280, 240, 280), Vector2(480, 560), Vector2(480, 560)),
		Rect2(240, 280, 240, 280))
	assert_eq(
		Character._scale_mobile_web_rect_to_atlas(Rect2(240, 280, 240, 280), Vector2(960, 1120), Vector2(480, 560)),
		Rect2(120, 140, 120, 140))
	var first_region := Character._scale_mobile_web_rect_to_atlas(
		Rect2(0, 0, 61, 112), Vector2(553, 112), Vector2(388, 79))
	var second_region := Character._scale_mobile_web_rect_to_atlas(
		Rect2(61, 0, 61, 112), Vector2(553, 112), Vector2(388, 79))
	assert_eq(first_region.end.x, second_region.position.x)
	assert_eq(first_region.end.y, second_region.end.y)

func test_mobile_animation_final_scaling_adjust_preserves_bottom_alignment():
	var display_height := 200.0
	var authored_offset := 20.0
	for final_scaling_adjust in [1.5, 0.5, 1.0, 0.0]:
		var applied_scaling_adjust: float = maxf(0.01, final_scaling_adjust)
		var adjusted_offset := Character._adjust_animation_vertical_offset_for_final_scale(
			authored_offset, display_height, final_scaling_adjust)
		var baseline_bottom := -(display_height / 2.0 + authored_offset) + display_height / 2.0
		var adjusted_bottom := -(display_height / 2.0 + adjusted_offset) + display_height * applied_scaling_adjust / 2.0
		assert_almost_eq(adjusted_bottom, baseline_bottom, 0.001)

func test_mobile_animation_final_scaling_adjust_applies_to_loaded_vertical_offset():
	var character := _instantiate_mobile_character_scene()
	add_child_autofree(character)
	var loader := TestMobileCardImageLoader.new(false)
	add_child_autofree(loader)
	await character.load_character(loader, {"id": "emogine"}, "emogine_exceed", false)
	var authored_offset := -20.0
	var unadjusted_display_height: float = character.get_size().y * character.scale.y
	var expected_offset: float = authored_offset + unadjusted_display_height * (GlobalSettings.phone_animation_final_scaling_adjust - 1.0) / 2.0
	assert_almost_eq(character.vertical_offset, expected_offset, 0.001)
	loader.teardown()

func test_mobile_animation_texture_uses_reported_output_size():
	var source_path := "res://assets/character_animations/example/atlas.png"
	Character.phone_animation_output_size_by_path[source_path] = Vector2i(6, 4)
	var source_image := Image.create(12, 8, false, Image.FORMAT_RGBA8)
	var texture := ImageTexture.create_from_image(source_image)
	var normalized := Character._normalize_mobile_web_texture_to_report_size(texture, source_path)
	assert_eq(normalized.get_size(), Vector2(6, 4))
	Character.phone_animation_output_size_by_path.erase(source_path)

func test_mobile_character_sprite_frames_scale_shared_atlas_and_preserve_animation():
	var character := _instantiate_mobile_character_scene()
	add_child_autofree(character)
	assert_not_null(character.animation)
	assert_not_null(character.exceed_icon)
	var source_image := Image.create(200, 100, false, Image.FORMAT_RGBA8)
	source_image.fill(Color.WHITE)
	var source_atlas := ImageTexture.create_from_image(source_image)
	var first_frame := AtlasTexture.new()
	first_frame.atlas = source_atlas
	first_frame.region = Rect2(0, 0, 100, 100)
	var second_frame := AtlasTexture.new()
	second_frame.atlas = source_atlas
	second_frame.region = Rect2(100, 0, 100, 100)
	var source_frames := SpriteFrames.new()
	source_frames.rename_animation(&"default", &"idle")
	source_frames.set_animation_loop(&"idle", false)
	source_frames.set_animation_speed(&"idle", 7.0)
	source_frames.add_frame(&"idle", first_frame, 1.5)
	source_frames.add_frame(&"idle", second_frame, 0.5)
	source_frames.set_meta("scaling", 0.75)

	var optimized_frames := await character._prepare_sprite_frames_for_runtime(source_frames, false)
	await get_tree().process_frame
	var optimized_first := optimized_frames.get_frame_texture(&"idle", 0) as AtlasTexture
	var optimized_second := optimized_frames.get_frame_texture(&"idle", 1) as AtlasTexture

	assert_eq(optimized_first.atlas.get_size(), Vector2(100, 50))
	assert_same(optimized_first.atlas, optimized_second.atlas)
	assert_eq(optimized_first.region, Rect2(0, 0, 50, 50))
	assert_eq(optimized_second.region, Rect2(50, 0, 50, 50))
	assert_false(optimized_frames.get_animation_loop(&"idle"))
	assert_eq(optimized_frames.get_animation_speed(&"idle"), 7.0)
	assert_eq(optimized_frames.get_frame_duration(&"idle", 0), 1.5)
	assert_eq(optimized_frames.get_meta("scaling"), 1.5)
	assert_eq(Character.get_mobile_web_character_texture_size(Vector2i(1, 3)), Vector2i(1, 2))

func test_mobile_character_phone_texture_path_and_scale_report():
	assert_eq(
		Character._get_phone_character_texture_path("res://assets/character_animations/emogine/emogine.png"),
		"res://assets/phone/character_animations/emogine/emogine.png")
	assert_eq(
		Character._get_phone_character_texture_path("res://assets/character_animations_skin/bison_1/bison_1.png"),
		"res://assets/phone/character_animations_skin/bison_1/bison_1.png")
	assert_eq(
		Character._get_phone_character_texture_path("res://assets/character_animations_custom/jinglechunshui/jinglechunshui_default.png"),
		"res://assets/phone/character_animations_custom/jinglechunshui/jinglechunshui_default.png")
	assert_eq(Character._get_phone_character_texture_scale("res://assets/character_animations/emogine/emogine.png"), 0.4)
	assert_eq(Character._get_phone_character_texture_scale("res://assets/character_animations_skin/bison_1/bison_1.png"), 1.0)
	assert_eq(Character._get_phone_character_texture_scale("res://assets/character_animations_custom/jinglechunshui/jinglechunshui_default.png"), 1.0)
	assert_eq(
		Character._scale_mobile_web_rect(Rect2(10, 20, 30, 40), 0.3),
		Rect2(3, 6, 9, 12))

func test_mobile_atlas_source_size_uses_reported_texture_size():
	var source_path := "res://assets/character_animations/solbadguy/idle/sol_idle_sheet.png"
	var previous_source_size = Character.phone_animation_source_size_by_path.get(source_path, null)
	Character.phone_animation_source_size_by_path[source_path] = Vector2i(432, 576)
	var atlas_defs := {
		"atlas": {
			"texture_id": "texture",
			"region": Rect2(0, 0, 16, 16),
		},
	}
	var texture_paths := {"texture": source_path}
	var atlas_sizes := Character._get_parsed_atlas_source_sizes(atlas_defs, texture_paths)
	assert_eq(atlas_sizes["atlas"], Vector2(432, 576))
	if previous_source_size == null:
		Character.phone_animation_source_size_by_path.erase(source_path)
	else:
		Character.phone_animation_source_size_by_path[source_path] = previous_source_size

func test_mobile_atlas_source_size_fallback_is_shared_by_texture():
	var atlas_defs := {
		"first": {
			"texture_id": "idle",
			"region": Rect2(0, 0, 61, 112),
		},
		"last": {
			"texture_id": "idle",
			"region": Rect2(492, 0, 61, 112),
		},
	}
	var texture_paths := {
		"idle": "res://assets/character_animations/missing_report/idle.png",
	}
	var atlas_sizes := Character._get_parsed_atlas_source_sizes(atlas_defs, texture_paths)
	assert_eq(atlas_sizes["first"], Vector2(553, 112))
	assert_eq(atlas_sizes["last"], Vector2(553, 112))

func test_mobile_character_uses_minimum_phone_scale_for_display_compensation():
	var character := _instantiate_mobile_character_scene()
	add_child_autofree(character)
	assert_not_null(character.animation)
	assert_not_null(character.exceed_icon)
	var base_image_a := Image.create(30, 30, false, Image.FORMAT_RGBA8)
	base_image_a.fill(Color.WHITE)
	var base_image_b := Image.create(30, 30, false, Image.FORMAT_RGBA8)
	base_image_b.fill(Color.WHITE)
	var atlas_a := ImageTexture.create_from_image(base_image_a)
	atlas_a.resource_path = "res://assets/character_animations/emogine/emogine.png"
	var atlas_b := ImageTexture.create_from_image(base_image_b)
	atlas_b.resource_path = "res://assets/character_animations_skin/bison_1/bison_1.png"
	var frame_a := AtlasTexture.new()
	frame_a.atlas = atlas_a
	frame_a.region = Rect2(0, 0, 30, 30)
	var frame_b := AtlasTexture.new()
	frame_b.atlas = atlas_b
	frame_b.region = Rect2(0, 0, 30, 30)
	var source_frames := SpriteFrames.new()
	source_frames.rename_animation(&"default", &"idle")
	source_frames.add_frame(&"idle", frame_a)
	source_frames.add_frame(&"idle", frame_b)

	await character._prepare_sprite_frames_for_runtime(source_frames, false)
	await get_tree().process_frame

	var expected_min_scale := minf(
		Character._get_phone_character_texture_scale("res://assets/character_animations/emogine/emogine.png"),
		Character._get_phone_character_texture_scale("res://assets/character_animations_skin/bison_1/bison_1.png"))
	assert_eq(character.mobile_texture_scale_for_display, expected_min_scale)

func test_web_runtime_backlog_budget_only_engages_for_real_backlog():
	assert_eq(Game.get_runtime_backlog_level(11, true), 0)
	assert_eq(Game.get_runtime_backlog_level(12, true), 1)
	assert_eq(Game.get_runtime_backlog_level(24, true), 2)
	assert_eq(Game.get_runtime_backlog_level(24, false), 0)
	assert_eq(Game.get_runtime_event_budget(11, true), Game.WebRuntimeEventBudgetUnlimited)
	assert_eq(Game.get_runtime_event_budget(12, true), Game.WebRuntimeEventBudgetModerate)
	assert_eq(Game.get_runtime_event_budget(24, true), Game.WebRuntimeEventBudgetSevere)
	assert_eq(Game.get_runtime_event_budget(24, false), Game.WebRuntimeEventBudgetUnlimited)

func test_match_entry_processing_hold_can_be_toggled():
	var game_ui : Game = GameScene.instantiate()
	game_ui.set_not_started_directly()
	game_ui.add_child(game_ui.game_wrapper)
	add_child_autofree(game_ui)
	game_ui.set_process(false)
	await get_tree().process_frame

	assert_false(game_ui.hold_match_entry_processing)
	game_ui.set_match_entry_processing_held(true)
	assert_true(game_ui.hold_match_entry_processing)
	game_ui.set_match_entry_processing_held(false)
	assert_false(game_ui.hold_match_entry_processing)

func test_web_runtime_health_state_warns_degrades_and_recovers():
	assert_eq(Game.get_runtime_health_state(0, 0, 0, Game.WebRuntimeRecoveryStableFrames, false), 0)
	assert_eq(Game.get_runtime_health_state(0, 12, 0, Game.WebRuntimeRecoveryStableFrames, true), 1)
	assert_eq(Game.get_runtime_health_state(0, 24, 0, Game.WebRuntimeRecoveryStableFrames, true), 2)
	assert_eq(Game.get_runtime_frame_pressure_level(0, true), 0)
	assert_eq(Game.get_runtime_frame_pressure_level(Game.WebRuntimeSlowFrameWarningCount, true), 1)
	assert_eq(Game.get_runtime_frame_pressure_level(Game.WebRuntimeSlowFrameSevereCount, true), 2)
	assert_eq(Game.get_runtime_health_state(0, 0, Game.WebRuntimeSlowFrameWarningCount, 0, true), 1)
	assert_eq(Game.get_runtime_health_state(0, 0, Game.WebRuntimeSlowFrameSevereCount, 0, true), 2)
	assert_eq(Game.get_runtime_health_state(1, 0, 0, Game.WebRuntimeRecoveryStableFrames - 1, true), 3)
	assert_eq(Game.get_runtime_health_state(2, 0, 0, Game.WebRuntimeRecoveryStableFrames - 1, true), 3)
	assert_eq(Game.get_runtime_health_state(3, 12, 0, Game.WebRuntimeRecoveryStableFrames, true), 1)
	assert_eq(Game.get_runtime_health_state(3, 0, 0, Game.WebRuntimeRecoveryStableFrames, true), 0)
	assert_eq(Game.get_runtime_event_budget_for_health_state(0), Game.WebRuntimeEventBudgetUnlimited)
	assert_eq(Game.get_runtime_event_budget_for_health_state(1), Game.WebRuntimeEventBudgetModerate)
	assert_eq(Game.get_runtime_event_budget_for_health_state(2), Game.WebRuntimeEventBudgetSevere)
	assert_eq(Game.get_runtime_event_budget_for_health_state(3), Game.WebRuntimeEventBudgetModerate)

func test_card_popout_repeated_show_cards_replaces_old_slots_instead_of_stacking():
	var popout : CardPopout = CardPopoutScene.instantiate()
	add_child_autofree(popout)
	await get_tree().process_frame

	var first_batch = []
	for card_id in range(1, 5):
		first_batch.append(_make_reference_source_card(card_id))
	popout.show_cards(first_batch)

	var second_batch = []
	for card_id in range(1, 9):
		second_batch.append(_make_reference_source_card(card_id))
	popout.show_cards(second_batch)
	await get_tree().process_frame

	assert_eq(popout.used_slots, 8)
	assert_eq(int(popout.total_cols), 4)
	for row in popout.rows.get_children():
		for col in row.get_children():
			assert_true(col.get_child_count() <= 1)

	var first_bottom_slot : CardBase = popout.rows.get_child(1).get_child(0).get_child(0)
	assert_eq(first_bottom_slot.card_id, 5)
	assert_eq(first_bottom_slot.get_remaining_count(), 5)

func test_card_popout_partial_fill_uses_final_slot_layout():
	var popout : CardPopout = CardPopoutScene.instantiate()
	add_child_autofree(popout)
	await get_tree().process_frame

	var partial_batch = []
	for card_id in range(1, 5):
		partial_batch.append(_make_reference_source_card(card_id))
	popout.show_cards(partial_batch, 8)

	assert_eq(popout.used_slots, 8)
	assert_eq(int(popout.total_cols), 4)
	assert_true(popout.rows.get_child(0).get_child(3).visible)
	assert_true(popout.rows.get_child(1).get_child(3).visible)
	assert_eq(popout.rows.get_child(1).get_child(0).get_child_count(), 0)

func test_card_popout_chunked_show_cards_matches_final_layout():
	var popout : CardPopout = CardPopoutScene.instantiate()
	add_child_autofree(popout)
	await get_tree().process_frame

	var batch = []
	for card_id in range(1, 9):
		batch.append(_make_reference_source_card(card_id))
	await popout.show_cards_chunked(batch, -1, 1)

	assert_eq(popout.used_slots, 8)
	assert_eq(int(popout.total_cols), 4)
	for row in popout.rows.get_children():
		for col in row.get_children():
			assert_true(col.get_child_count() <= 1)

	var first_bottom_slot : CardBase = popout.rows.get_child(1).get_child(0).get_child(0)
	assert_eq(first_bottom_slot.card_id, 5)
	assert_eq(first_bottom_slot.get_remaining_count(), 5)

func test_card_popout_chunked_rendered_card_is_fixed_before_next_frame():
	var popout : CardPopout = CardPopoutScene.instantiate()
	add_child_autofree(popout)
	await get_tree().process_frame

	var source_card = _make_reference_source_card(1)
	var render_info = popout._prepare_card_slots([source_card], -1)
	var display_scale = render_info["display_scale"]
	var rendered_card : CardBase = popout._render_card_slot(source_card, 0, display_scale)
	var expected_pos = display_scale * CardBase.ActualCardSize / 2

	assert_eq(rendered_card.state, CardBase.CardState.CardState_InPopout)
	assert_eq(rendered_card.card_features.position, expected_pos)
	assert_eq(rendered_card.resting_position, expected_pos)
	assert_eq(rendered_card.card_features.scale, display_scale)

func test_card_popout_fill_viewport_spacing_fits_wide_mobile_rows():
	var card_width = CardBase.ActualCardSize.x * CardBase.ReferenceCardScale.x * 1.3
	var row_count = 17
	var available_width = 1240.0
	var spacing = CardPopout.get_fill_viewport_row_spacing(row_count, card_width, available_width)
	var final_width = card_width * row_count + float(spacing) * float(row_count - 1)

	assert_lt(spacing, CardPopout.MinSeparation)
	assert_lte(final_width, available_width)

func test_card_popout_fill_viewport_spacing_keeps_default_when_cards_fit():
	var spacing = CardPopout.get_fill_viewport_row_spacing(4, 150.0, 800.0)
	assert_eq(spacing, CardPopout.DefaultSeparation)

func test_card_popout_fill_viewport_width_ignores_overflowed_rows_size():
	var viewport_width = 390.0
	var available_width = CardPopout.get_fill_viewport_available_width(viewport_width, 20.0, 20.0)
	var spacing = CardPopout.get_fill_viewport_row_spacing(5, 150.0, available_width)
	var final_width = 150.0 * 5.0 + float(spacing) * 4.0
	assert_eq(available_width, 350.0)
	assert_lte(final_width, available_width)

func test_card_popout_mobile_scene_keeps_reference_cards_inside_viewport():
	var mobile_viewport := SubViewport.new()
	mobile_viewport.size = Vector2i(390, 720)
	add_child_autofree(mobile_viewport)
	var popout : CardPopout = CardPopoutScene.instantiate()
	mobile_viewport.add_child(popout)
	popout.set_fill_viewport(true)
	popout.set_preview_card_scale(1.3)
	popout.set_title("(点击卡牌记录数量)(点击空地缩小卡牌)(离线不关闭)")
	await get_tree().process_frame

	var cards = []
	for card_id in range(1, 35):
		cards.append(_make_reference_source_card(card_id))
	popout.show_cards(cards)
	await get_tree().process_frame
	await get_tree().process_frame

	for row in popout.rows.get_children():
		var visible_slots = row.get_children().filter(func(slot): return slot.visible)
		if visible_slots.is_empty():
			continue
		var last_slot : Control = visible_slots[-1]
		var right_edge = last_slot.global_position.x + last_slot.size.x
		assert_lte(right_edge, float(mobile_viewport.size.x))

func test_guided_selection_refreshes_matching_existing_popout():
	var game_ui : Game = GameScene.instantiate()
	game_ui.set_not_started_directly()
	game_ui.add_child(game_ui.game_wrapper)
	add_child_autofree(game_ui)
	game_ui.set_process(false)
	await get_tree().process_frame

	assert_false(game_ui._should_open_or_refresh_popout(false, game_ui.CardPopoutType.CardPopoutType_ReferenceOpponent))

	var existing_popout := Node2D.new()
	game_ui.card_popout_parent.add_child(existing_popout)
	game_ui.popout_type_showing = game_ui.CardPopoutType.CardPopoutType_ReferenceOpponent

	assert_true(game_ui._should_open_or_refresh_popout(false, game_ui.CardPopoutType.CardPopoutType_ReferenceOpponent))
	assert_false(game_ui._should_open_or_refresh_popout(false, game_ui.CardPopoutType.CardPopoutType_GaugeOpponent))

func test_card_popout_does_not_connect_click_for_character_and_buddy_reference_cards():
	var popout : CardPopout = CardPopoutScene.instantiate()
	add_child_autofree(popout)
	await get_tree().process_frame

	var batch = [
		_make_reference_source_card(CardBase.CharacterCardReferenceId),
		_make_reference_source_card(CardBase.BuddyCardReferenceId),
		_make_reference_source_card(50001),
	]
	popout.show_cards(batch)

	for row in popout.rows.get_children():
		for col in row.get_children():
			if col.get_child_count() == 0:
				continue
			var rendered_card : CardBase = col.get_child(0)
			var is_placeholder = rendered_card.card_id in [CardBase.CharacterCardReferenceId, CardBase.BuddyCardReferenceId]
			assert_eq(rendered_card.clicked_card.get_connections().size(), 0 if is_placeholder else 1)

func test_can_select_card_rejects_character_and_buddy_reference_cards():
	var game_ui : Game = GameScene.instantiate()
	game_ui.set_not_started_directly()
	game_ui.add_child(game_ui.game_wrapper)
	add_child_autofree(game_ui)
	game_ui.set_process(false)
	await get_tree().process_frame

	var character_card = _make_reference_source_card(CardBase.CharacterCardReferenceId)
	var buddy_card = _make_reference_source_card(CardBase.BuddyCardReferenceId)

	assert_false(game_ui.can_select_card(character_card))
	assert_false(game_ui.can_select_card(buddy_card))

func test_card_image_loader_tracks_requested_atlas_indices():
	var loader = CardImageLoader.new(false)
	add_child_autofree(loader)
	var atlas = {"url": "http://example.com/cards.png"}

	loader.load_image_page_indexed(atlas, 2)
	loader.load_image_page_indexed(atlas, 5)

	var normalized_url = "https://example.com/cards.png"
	assert_true(loader.image_load_requested_indices[normalized_url].has(2))
	assert_true(loader.image_load_requested_indices[normalized_url].has(5))
	assert_false(loader.image_load_requested_indices[normalized_url].has(-1))
	assert_true(CardImageLoader.should_create_atlas_texture({2: true, 5: true}, 2))
	assert_false(CardImageLoader.should_create_atlas_texture({2: true, 5: true}, 3))
	assert_true(CardImageLoader.should_create_atlas_texture({-1: true}, 3))
	loader.teardown()

func test_mobile_card_image_loader_uses_phone_cdn_path_and_report_scale():
	var loader = TestMobileCardImageLoader.new(false)
	add_child_autofree(loader)
	var original_url = "https://cdn.exceedcntyd.com/decks_official/byakuya/normals.jpg"
	var phone_url = "https://cdn.exceedcntyd.com/phone/decks_official/byakuya/normals.jpg"

	loader.load_image_page_indexed({"url": original_url, "multiple_cards": true}, 0)

	assert_true(loader.image_load_atlas_map.has(phone_url))
	assert_eq(loader.image_load_atlas_map[phone_url]["phone_image_scale"], 1.0)
	loader.teardown()

func test_desktop_card_image_loader_keeps_original_cdn_path():
	var loader = TestDesktopCardImageLoader.new(false)
	add_child_autofree(loader)
	var original_url = "https://cdn.exceedcntyd.com/decks_official/byakuya/normals.jpg"

	loader.load_image_page_indexed({"url": original_url, "multiple_cards": true}, 0)

	assert_true(loader.image_load_atlas_map.has(original_url))
	assert_eq(loader.image_load_atlas_map[original_url]["phone_image_scale"], 1.0)
	loader.teardown()

func test_card_image_loader_merges_later_atlas_metadata_for_same_url():
	var merged = CardImageLoader.merge_image_atlas_details(
		{
			"url": "https://example.com/cards.png",
			"multiple_cards": false,
			"season": 0,
			"deck_id": ""
		},
		{
			"url": "https://example.com/cards.png",
			"multiple_cards": true,
			"season": 7,
			"deck_id": "ino"
		})

	assert_true(merged["multiple_cards"])
	assert_eq(merged["season"], 7)
	assert_eq(merged["deck_id"], "ino")

func test_card_image_loader_invalidates_stale_reference_atlas_before_rebuild():
	var loader = TestMobileCardImageLoader.new(false)
	add_child_autofree(loader)
	loader.lazy_multi_card_textures = true
	loader.set_runtime_card_scale(1.0)
	var atlas_url = "https://example.com/stale_reference_normals.png"
	ImageCache.cache_image(atlas_url, _make_test_shared_atlas(4, 2, 12))
	var wrong_image = Image.create(12, 12, false, Image.FORMAT_RGBA8)
	wrong_image.fill(Color.BLACK)
	loader.loaded_images[atlas_url] = [ImageTexture.create_from_image(wrong_image)]
	var atlas_data = {
		"url": atlas_url,
		"multiple_cards": true,
		"season": 1,
		"image_name": "normals",
		"force_cropped_textures": true,
		"materialize_textures_atomically": true,
	}

	loader.invalidate_loaded_image(atlas_url)
	loader.load_image_page(atlas_data)
	await loader.get_card_image(atlas_url, 0, atlas_data)
	await get_tree().process_frame # GUT must not free a loader still emitting this completion.

	var textures = loader.loaded_images[atlas_url]
	assert_eq(textures.size(), 8)
	for index in range(8):
		assert_not_null(textures[index])
		_assert_color_close(_get_texture_center_color(textures[index]), _make_distinct_index_color(index))
	loader.teardown()

func test_card_image_loader_refreshes_replaced_metadata_after_download_wait():
	var atlas_url = "https://example.com/first_download_s6_normals.png"
	var initial_snapshot = {
		"url": atlas_url,
		"multiple_cards": false,
		"season": 0,
	}
	var latest = CardImageLoader.merge_image_atlas_details(initial_snapshot, {
		"url": atlas_url,
		"multiple_cards": true,
		"season": 6,
		"image_name": "normals",
		"force_cropped_textures": true,
	})
	var atlas_map = {atlas_url: latest}
	var refreshed = CardImageLoader.get_latest_image_atlas_details(
		atlas_map, atlas_url, initial_snapshot)

	assert_false(initial_snapshot["multiple_cards"])
	assert_eq(initial_snapshot["season"], 0)
	assert_true(refreshed["multiple_cards"])
	assert_eq(refreshed["season"], 6)
	assert_eq(refreshed["image_name"], "normals")
	assert_true(refreshed["force_cropped_textures"])

func test_mobile_web_multi_card_atlas_matches_native_materialization_and_yielding():
	assert_false(CardImageLoader.should_materialize_all_multi_card_textures(true, {"multiple_cards": true}))
	assert_false(CardImageLoader.should_materialize_all_multi_card_textures(false, {"multiple_cards": true}))
	assert_false(CardImageLoader.should_materialize_all_multi_card_textures(true, {"multiple_cards": false}))
	assert_false(CardImageLoader.should_yield_after_atlas_texture(true, {}, 0))
	assert_false(CardImageLoader.should_yield_after_atlas_texture(
		true, {"materialize_textures_atomically": true}, 0))
	assert_false(CardImageLoader.should_yield_after_atlas_texture(false, {}, 0))

func test_card_database_can_defer_registered_card_image_requests():
	var loader = CardImageLoader.new(false)
	add_child_autofree(loader)
	loader.defer_registered_card_images = true
	var card_database = CardDatabase.new(loader)
	add_child_autofree(card_database)
	var game_card = GameCard.new(1, {"id": "test_card"}, 0, {
		"url": "https://example.com/deferred.png",
		"multiple_cards": true,
	}, 2)
	card_database.add_card(game_card)
	assert_true(loader.image_load_queue.is_empty())
	assert_true(loader.image_load_requested_indices.is_empty())
	card_database.teardown()
	loader.teardown()

func test_lazy_multi_card_loader_materializes_requested_indices_incrementally():
	var loader = TestMobileCardImageLoader.new(false)
	add_child_autofree(loader)
	loader.lazy_multi_card_textures = true
	var atlas_url = "https://example.com/lazy_incremental.png"
	ImageCache.cache_image(atlas_url, _make_test_shared_atlas(4, 2, 12))
	var atlas_details = {
		"url": atlas_url,
		"multiple_cards": true,
		"season": 1,
		"force_cropped_textures": true,
	}
	loader.load_image_page_indexed(atlas_details, 2)
	await loader._process_request_queue()
	assert_not_null(loader.loaded_images[atlas_url][2])
	assert_null(loader.loaded_images[atlas_url][5])
	loader.load_image_page_indexed(atlas_details, 5)
	await loader._process_request_queue()
	assert_not_null(loader.loaded_images[atlas_url][2])
	assert_not_null(loader.loaded_images[atlas_url][5])
	assert_null(loader.loaded_images[atlas_url][1])
	loader.teardown()

func test_s1_s6_mobile_cropping_keeps_indices_when_requests_arrive_between_frames():
	for season in [1, 6]:
		var loader = TestMobileCardImageLoader.new(false)
		add_child_autofree(loader)
		loader.lazy_multi_card_textures = true
		loader.set_runtime_card_scale(1.0)
		var atlas_url = "https://example.com/interleaved_s%d_normals.png" % season
		ImageCache.cache_image(atlas_url, _make_test_shared_atlas(4, 2, 12))
		var atlas_data = {
			"url": atlas_url,
			"multiple_cards": true,
			"season": season,
			"image_name": "normals",
			"force_cropped_textures": true,
		}
		loader.load_image_page_indexed(atlas_data, 0)
		loader._process_request_queue()
		for index in range(1, 8):
			loader.load_image_page_indexed(atlas_data, index)
			await get_tree().process_frame
		while loader.processing_queue:
			await get_tree().process_frame

		var textures = loader.loaded_images[atlas_url]
		for index in range(8):
			assert_not_null(textures[index])
			_assert_color_close(_get_texture_center_color(textures[index]), _make_distinct_index_color(index))
		loader.teardown()

func test_mobile_web_uses_pc_atlas_texture_when_within_limit():
	var loader = TestMobileCardImageLoader.new(false)
	add_child_autofree(loader)
	var atlas = _make_test_shared_atlas(6, 4, 12)
	assert_false(loader._should_use_scaled_mobile_atlas_texture({"multiple_cards": true}, atlas))
	loader.teardown()

func test_mobile_web_normals_force_cropped_textures_avoid_atlas_texture():
	var loader = TestMobileCardImageLoader.new(false)
	add_child_autofree(loader)
	var atlas_url = "https://example.com/normals_force_cropped_test.png"
	var atlas_image = _make_test_shared_atlas(4, 2, 12)
	ImageCache.cache_image(atlas_url, atlas_image)

	loader.load_image_page_indexed({
		"url": atlas_url,
		"multiple_cards": true,
		"season": 1,
		"force_cropped_textures": true
	}, 0)

	await loader._process_request_queue()

	var textures = loader.loaded_images[atlas_url]
	assert_eq(textures.size(), 8)
	assert_false(textures[0] is AtlasTexture)
	assert_true(textures[0] is ImageTexture)
	loader.teardown()

func test_problematic_mobile_normal_atlas_scope_is_limited_to_s1_s6_normals():
	assert_true(Game.is_problematic_mobile_normal_atlas(
		{"season": 1, "image_name": "normals"}, true))
	assert_true(Game.is_problematic_mobile_normal_atlas(
		{"season": 6, "image_name": "normals"}, true))
	assert_false(Game.is_problematic_mobile_normal_atlas(
		{"season": 1, "image_name": "specials"}, true))
	assert_false(Game.is_problematic_mobile_normal_atlas(
		{"season": 6, "image_name": "specials"}, true))
	assert_false(Game.is_problematic_mobile_normal_atlas(
		{"season": 7, "image_name": "normals"}, true))
	assert_false(Game.is_problematic_mobile_normal_atlas(
		{"season": 1, "image_name": "normals"}, false))

func test_in_game_deck_image_atlas_normalization_matches_reference_normals():
	var normalized = Game.get_normalized_deck_image_atlas_data(
		{
			"url": "https://example.com/s1_normals.png",
			"multiple_cards": true,
			"season": 1,
		},
		"normals")

	assert_eq(normalized["image_name"], "normals")
	assert_true(normalized["force_cropped_textures"])
	assert_true(Game.is_problematic_mobile_normal_atlas(normalized, true))

func test_problematic_normals_runtime_scale_keeps_pc_card_size():
	assert_eq(Game.MobileWebProblematicNormalsCardScale, 1.0)
	var loader = TestMobileCardImageLoader.new(false)
	add_child_autofree(loader)
	loader.set_runtime_card_scale(0.6)
	assert_eq(loader._get_scaled_card_size(500.0, 682.5), Vector2i(500, 683))
	assert_eq(loader._get_scaled_card_size(
		500.0, 682.5, Game.MobileWebProblematicNormalsCardScale), Vector2i(500, 683))
	loader.teardown()

func test_lazy_mobile_loader_full_page_then_index_wait_prewarms_all_indices():
	for season in [1, 6]:
		var loader = TestMobileCardImageLoader.new(false)
		add_child_autofree(loader)
		loader.lazy_multi_card_textures = true
		var atlas_url = "https://example.com/full_prewarm_s%d_normals.png" % season
		var atlas_size = Vector2i(48, 24) if season == 1 else Vector2i(102, 69)
		var atlas_image = Image.create(atlas_size.x, atlas_size.y, false, Image.FORMAT_RGBA8)
		atlas_image.fill(Color.WHITE)
		ImageCache.cache_image(atlas_url, atlas_image)
		var atlas_data = Game.get_normalized_deck_image_atlas_data(
			{
				"url": atlas_url,
				"multiple_cards": true,
				"season": season,
			},
			"normals")
		atlas_data["runtime_card_scale"] = Game.MobileWebProblematicNormalsCardScale
		loader.load_image_page(atlas_data)
		loader.load_image_page_indexed(atlas_data, 0)
		assert_true(loader.image_load_requested_indices[atlas_url].has(-1))
		assert_true(loader.image_load_requested_indices[atlas_url].has(0))

		await loader._process_request_queue()

		var textures = loader.loaded_images[atlas_url]
		assert_eq(textures.size(), 8)
		var expected_size = Vector2(12, 12) if season == 1 else Vector2(25, 34)
		for texture in textures:
			assert_not_null(texture)
			assert_eq(texture.get_size(), expected_size)
		loader.teardown()

func test_mobile_web_cropped_atlas_uses_pc_cell_dimensions():
	var loader = TestMobileCardImageLoader.new(false)
	add_child_autofree(loader)
	loader.set_runtime_card_scale(0.5)
	var atlas_url = "https://example.com/nonstandard_cell_size.png"
	var atlas_image = Image.create(80, 60, false, Image.FORMAT_RGBA8)
	atlas_image.fill(Color.WHITE)
	ImageCache.cache_image(atlas_url, atlas_image)
	loader.load_image_page_indexed({
		"url": atlas_url,
		"multiple_cards": true,
		"season": 1,
		"force_cropped_textures": true,
	}, 3)

	await loader._process_request_queue()
	var texture = loader.loaded_images[atlas_url][3] as ImageTexture
	assert_not_null(texture)
	assert_eq(texture.get_size(), Vector2(20, 30))
	loader.teardown()

func test_s1_s6_s7_cropped_atlases_use_pc_calculated_cell_dimensions():
	await _assert_scaled_season_atlas_card_size(1, "solbadguy", Vector2i(80, 60), Vector2(20, 30))
	await _assert_scaled_season_atlas_card_size(6, "unknown", Vector2i(100, 70), Vector2(25, 35))
	await _assert_scaled_season_atlas_card_size(7, "ino", Vector2i(120, 80), Vector2(20, 20))
	await _assert_scaled_season_atlas_card_size(7, "happychaos", Vector2i(120, 90), Vector2(20, 30))

func test_s0_s2_s5_mobile_atlases_follow_report_scale_and_season_layout():
	await _assert_report_scaled_atlas_card_size(
		0, "jinglechunshui", "decks_custom/jinglechunshui/normals.jpg",
		Vector2i(1502, 1024), Vector2(375, 512))
	await _assert_report_scaled_atlas_card_size(
		2, "carlswangee", "decks_official/carlswangee/specials.jpg",
		Vector2i(1200, 1640), Vector2(300, 410))
	await _assert_report_scaled_atlas_card_size(
		3, "akuma", "decks_official/akuma/normals.jpg",
		Vector2i(1500, 1024), Vector2(375, 512))
	await _assert_report_scaled_atlas_card_size(
		4, "beheaded", "decks_official/beheaded/normals_specials.jpg",
		Vector2i(900, 1229), Vector2(225, 307))
	await _assert_report_scaled_atlas_card_size(
		5, "arakune", "decks_official/arakune/normals_specials.jpg",
		Vector2i(900, 1537), Vector2(225, 307))

func test_carlswangee_current_combined_atlas_preserves_all_deck_indices():
	var deck = CardDataManager.get_deck("carlswangee")
	var original_url = CardImageLoader.CDN_IMAGE_ROOT + "decks_official/carlswangee/specials.jpg"
	assert_eq(deck["image_resources"]["specials"]["url"], original_url)
	assert_eq(deck["image_resources"]["normals"]["url"], original_url,
		"The current deck uses the combined 4x4 atlas, not the legacy normals-only 4x3 image.")
	var phone_url = CardImageLoader.CDN_PHONE_IMAGE_ROOT + "decks_official/carlswangee/specials.jpg"
	var loader = TestMobileCardImageLoader.new(false)
	add_child_autoqfree(loader)
	var image = Image.create(1200, 1640, false, Image.FORMAT_RGBA8)
	for index in range(16):
		image.fill_rect(Rect2i((index % 4) * 300, (index / 4) * 410, 300, 410),
				_make_distinct_index_color(index))
	ImageCache.cache_image(phone_url, image)
	var atlas = {"url": original_url, "multiple_cards": true, "season": 2, "deck_id": "carlswangee"}
	for card in deck["cards"]:
		loader.load_image_page_indexed(atlas, int(card["image_index"]))
	await loader._process_request_queue()
	assert_eq(loader.loaded_images[phone_url].size(), 16)
	var seen = {}
	for card in deck["cards"]:
		var index = int(card["image_index"])
		var texture = loader.loaded_images[phone_url][index]
		assert_not_null(texture)
		assert_eq(texture.get_size(), Vector2(300, 410))
		_assert_color_close(_get_texture_center_color(texture), _make_distinct_index_color(index))
		seen[index] = true
	assert_eq(seen.size(), 15)
	loader.teardown()
	ImageCache.remove_cached_image(phone_url)

func test_s6_non_divisible_atlas_uses_fixed_floor_slices_and_ignores_remainder():
	var loader = TestDesktopCardImageLoader.new(false)
	add_child_autofree(loader)
	var atlas_url = "https://example.com/s6_non_divisible_boundary_test.png"
	var atlas_width = 102
	var atlas_height = 69
	var atlas_image = Image.create(atlas_width, atlas_height, false, Image.FORMAT_RGBA8)
	var cell_width = int(floor(float(atlas_width) / 4.0))
	var cell_height = int(floor(float(atlas_height) / 2.0))
	# 按固定 floor 尺寸定义 4x2 单元，最右 2px/最下 1px 为应被忽略的余数。
	for y in range(2):
		for x in range(4):
			var idx = y * 4 + x
			atlas_image.fill_rect(
				Rect2i(x * cell_width, y * cell_height, cell_width, cell_height),
				_make_distinct_index_color(idx))
	atlas_image.fill_rect(Rect2i(cell_width * 4, 0, atlas_width - cell_width * 4, atlas_height), Color.MAGENTA)
	atlas_image.fill_rect(Rect2i(0, cell_height * 2, atlas_width, atlas_height - cell_height * 2), Color.MAGENTA)
	ImageCache.cache_image(atlas_url, atlas_image)

	loader.load_image_page({
		"url": atlas_url,
		"multiple_cards": true,
		"season": 6,
		"force_cropped_textures": true,
	})

	await loader._process_request_queue()

	var textures = loader.loaded_images[atlas_url]
	assert_eq(textures.size(), 8)

	for index in range(8):
		var texture = textures[index] as ImageTexture
		assert_not_null(texture)
		_assert_color_close(_get_texture_center_color(texture), _make_distinct_index_color(index))
	loader.teardown()

func test_card_image_loader_trim_edges_for_divisible_grid_accepts_small_remainder():
	var trimmed = CardImageLoader.try_trim_edges_for_divisible_grid(900, 1537, 225.0, 307.2)
	assert_true(trimmed["trimmed"])
	assert_eq(trimmed["region_width"], 900)
	assert_eq(trimmed["region_height"], 1536)
	assert_eq(trimmed["grid_width"], 4.0)
	assert_eq(trimmed["grid_height"], 5.0)
	assert_eq(trimmed["trim_right"], 0)
	assert_eq(trimmed["trim_bottom"], 1)

func test_card_image_loader_trim_edges_for_divisible_grid_rejects_large_mismatch():
	var trimmed = CardImageLoader.try_trim_edges_for_divisible_grid(900, 1537, 375.0, 512.3)
	assert_false(trimmed["trimmed"])

func test_game_card_image_url_index_data_preserves_atlas_metadata():
	var card = GameCard.new(
		1,
		{"id": "test_normal", "display_name": "Test Normal"},
		Enums.PlayerId.PlayerId_Player,
		{
			"url": "https://example.com/normals.png",
			"multiple_cards": true,
			"season": 1,
			"image_name": "normals",
			"force_cropped_textures": true
		},
		3)
	add_child_autofree(card)

	var image_data = card.get_image_url_index_data()
	assert_eq(image_data["url"], "https://example.com/normals.png")
	assert_eq(image_data["index"], 3)
	assert_true(image_data["multiple_cards"])
	assert_eq(image_data["image_name"], "normals")
	assert_true(image_data["force_cropped_textures"])

func test_mobile_web_scaled_atlas_layout_matches_pc_dimensions():
	var loader = TestMobileCardImageLoader.new(false)
	add_child_autofree(loader)
	var layout = loader._get_scaled_mobile_atlas_layout(4, 2, 750.0, 1024.0, 0, 0)
	assert_eq(layout["atlas_size"], Vector2i(3000, 2048))
	assert_eq(layout["card_width"], 750)
	assert_eq(layout["card_height"], 1024)
	loader.teardown()

func test_shared_url_multi_card_atlas_keeps_correct_textures_across_late_requests():
	var loader = TestMobileCardImageLoader.new(false)
	add_child_autofree(loader)
	var atlas_url = "https://example.com/shared_atlas_runtime_test.png"
	var atlas_image = _make_test_shared_atlas(6, 4, 12)
	ImageCache.cache_image(atlas_url, atlas_image)

	loader.load_image_page_indexed({
		"url": atlas_url,
		"multiple_cards": true
	}, 1)
	loader.load_image_page({
		"url": atlas_url,
		"multiple_cards": true,
		"season": 7,
		"deck_id": "ino"
	})

	await loader._process_request_queue()

	var textures = loader.loaded_images[atlas_url]
	assert_eq(textures.size(), 24)
	assert_true(textures.all(func(texture): return texture != null))

	var expected_index_1 = Color(float((1 * 37) % 255) / 255.0, float((1 * 67) % 255) / 255.0, float((1 * 97) % 255) / 255.0, 1.0)
	var expected_index_15 = Color(float((15 * 37) % 255) / 255.0, float((15 * 67) % 255) / 255.0, float((15 * 97) % 255) / 255.0, 1.0)
	_assert_color_close(_get_texture_center_color(textures[1]), expected_index_1)
	_assert_color_close(_get_texture_center_color(textures[15]), expected_index_15)

	var late_texture = await loader.get_card_image(atlas_url, 15)
	await get_tree().process_frame
	assert_not_null(late_texture)
	_assert_color_close(_get_texture_center_color(late_texture), expected_index_15)
	loader.teardown()

func test_mobile_web_reference_loader_scale_keeps_pc_target_card_size():
	var loader = TestMobileCardImageLoader.new(false)
	add_child_autofree(loader)
	loader.set_runtime_card_scale(0.4)
	assert_eq(loader._get_target_card_size(), Vector2i(750, 1024))
	loader.teardown()
