extends GutTest

const BackgroundManager = preload("res://globals/game_background_manager.gd")

func before_each():
	CdnAssetLoader.clear_all_textures()
	CdnAssetLoader.cache_soft_limit_override_bytes = 100
	CdnAssetLoader.cache_hard_limit_override_bytes = 200

func after_each():
	CdnAssetLoader.clear_all_textures()
	CdnAssetLoader.cache_soft_limit_override_bytes = -1
	CdnAssetLoader.cache_hard_limit_override_bytes = -1

func _make_texture(width: int = 4, height: int = 4) -> Texture2D:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)

func test_unowned_textures_are_evicted_by_lru_at_soft_limit():
	CdnAssetLoader._cache_texture("old", _make_texture(), "", "preview")
	CdnAssetLoader._cache_texture("recent", _make_texture(), "", "preview")

	assert_false(CdnAssetLoader.loaded_textures.has("old"))
	assert_true(CdnAssetLoader.loaded_textures.has("recent"))
	assert_eq(CdnAssetLoader.get_texture_cache_estimated_bytes(), 64)

func test_cache_hit_refreshes_lru_order():
	CdnAssetLoader.cache_soft_limit_override_bytes = 130
	CdnAssetLoader._cache_texture("first", _make_texture(), "", "preview")
	CdnAssetLoader._cache_texture("second", _make_texture(), "", "preview")
	CdnAssetLoader._touch_texture_cache_entry("first", "", "preview")
	CdnAssetLoader._cache_texture("third", _make_texture(), "", "preview")

	assert_true(CdnAssetLoader.loaded_textures.has("first"))
	assert_false(CdnAssetLoader.loaded_textures.has("second"))
	assert_true(CdnAssetLoader.loaded_textures.has("third"))

func test_soft_limit_preserves_owned_textures_until_hard_limit():
	CdnAssetLoader._cache_texture("owned", _make_texture(), "character", "visible")
	CdnAssetLoader._cache_texture("unowned", _make_texture(), "", "preview")
	CdnAssetLoader.trim_texture_cache()

	assert_true(CdnAssetLoader.loaded_textures.has("owned"))
	assert_false(CdnAssetLoader.loaded_textures.has("unowned"))

func test_hard_limit_can_drop_cache_reference_for_owned_texture():
	CdnAssetLoader.cache_soft_limit_override_bytes = 64
	CdnAssetLoader.cache_hard_limit_override_bytes = 100
	var first_texture := _make_texture()
	CdnAssetLoader._cache_texture("first", first_texture, "character-one", "visible")
	CdnAssetLoader._cache_texture("second", _make_texture(), "character-two", "visible")

	assert_false(CdnAssetLoader.loaded_textures.has("first"))
	assert_true(CdnAssetLoader.loaded_textures.has("second"))
	assert_not_null(first_texture)

func test_owner_release_only_evicts_after_last_owner():
	var texture := _make_texture()
	CdnAssetLoader._cache_texture("shared", texture, "one", "visible")
	CdnAssetLoader._touch_texture_cache_entry("shared", "two", "visible")

	CdnAssetLoader.release_owner("one")
	assert_true(CdnAssetLoader.loaded_textures.has("shared"))

	CdnAssetLoader.release_owner("two")
	assert_false(CdnAssetLoader.loaded_textures.has("shared"))

func test_debug_info_reports_limits_and_estimated_size():
	CdnAssetLoader._cache_texture("texture", _make_texture(), "", "preview")
	var info := CdnAssetLoader.get_texture_cache_debug_info()

	assert_eq(info["entries"], 1)
	assert_eq(info["estimated_bytes"], 64)
	assert_eq(info["soft_limit_bytes"], 100)
	assert_eq(info["hard_limit_bytes"], 200)

func test_match_background_owner_release_does_not_clear_main_menu_texture():
	CdnAssetLoader._cache_texture(
		"match",
		_make_texture(),
		BackgroundManager.MATCH_TEXTURE_OWNER,
		"visible")
	CdnAssetLoader._cache_texture(
		"menu",
		_make_texture(),
		BackgroundManager.MAIN_MENU_TEXTURE_OWNER,
		"visible")

	CdnAssetLoader.release_owner(BackgroundManager.MATCH_TEXTURE_OWNER)

	assert_false(CdnAssetLoader.loaded_textures.has("match"))
	assert_true(CdnAssetLoader.loaded_textures.has("menu"))
