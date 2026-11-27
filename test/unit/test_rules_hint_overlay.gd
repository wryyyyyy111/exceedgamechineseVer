extends GutTest

const OverlayScene = preload("res://scenes/menu/rules_hint_overlay.tscn")

class LayoutOnlyMenu extends MainMenu:
	func _ready() -> void:
		pass

func _create_overlay() -> Control:
	var overlay : Control = OverlayScene.instantiate()
	add_child_autofree(overlay)
	return overlay

func _click_at(position : Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	get_viewport().push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.pressed = pressed
		get_viewport().push_input(event, true)

func test_open_shows_centered_image_at_original_aspect_ratio() -> void:
	var overlay := _create_overlay()
	assert_false(overlay.visible)
	assert_false(overlay.get_node("OverlayLayer").visible)
	overlay.show_rules()
	await wait_frames(2)

	var image : TextureRect = overlay.get_node("OverlayLayer/ImageView")
	var viewport_size := overlay.get_viewport_rect().size
	assert_true(overlay.get_node("OverlayLayer").visible)
	assert_eq(image.texture.resource_path, "res://assets/ui_art/brief_rules.png")
	assert_almost_eq(image.position + image.size / 2.0, viewport_size / 2.0, Vector2.ONE * 0.01)
	assert_almost_eq(image.size.x / image.size.y, 4505.0 / 2232.0, 0.001)
	assert_true(image.size.x <= viewport_size.x - 48.0)
	assert_true(image.size.y <= viewport_size.y - 48.0)
	assert_gt(overlay.get_node("OverlayLayer").layer, 100)

func test_image_click_stays_open_and_background_click_closes_without_click_through() -> void:
	var underneath := Button.new()
	underneath.position = Vector2.ZERO
	underneath.size = Vector2(100, 100)
	add_child_autofree(underneath)
	watch_signals(underneath)
	var overlay := _create_overlay()
	overlay.show_rules()
	await wait_frames(2)

	var image : TextureRect = overlay.get_node("OverlayLayer/ImageView")
	var background : Button = overlay.get_node("OverlayLayer/BackgroundButton")
	assert_eq(background.size, overlay.get_viewport_rect().size, "Background covers the viewport")
	_click_at(image.position + image.size / 2.0)
	await wait_frames(1)
	assert_true(overlay.visible, "Clicking the image keeps it open")
	_click_at(Vector2(10, 10))
	await wait_frames(1)
	assert_false(overlay.visible, "Clicking outside closes the overlay")
	assert_false(overlay.get_node("OverlayLayer").visible, "Closing hides the CanvasLayer")
	assert_signal_not_emitted(underneath, "pressed")

	_click_at(Vector2(10, 10))
	assert_signal_emitted(underneath, "pressed")

func test_clicking_image_top_right_corner_closes() -> void:
	var overlay := _create_overlay()
	overlay.show_rules()
	await wait_frames(2)
	var image : TextureRect = overlay.get_node("OverlayLayer/ImageView")
	_click_at(image.position + Vector2(image.size.x * 0.96, image.size.y * 0.06))
	await wait_frames(1)
	assert_false(overlay.visible, "Clicking the top-right close area closes the overlay")

func test_hiding_parent_closes_layer_and_does_not_reopen_on_return() -> void:
	var parent := Control.new()
	add_child_autofree(parent)
	var overlay : Control = OverlayScene.instantiate()
	parent.add_child(overlay)
	overlay.show_rules()
	parent.hide()
	assert_false(overlay.get_node("OverlayLayer").visible)
	parent.show()
	assert_false(overlay.visible)
	assert_false(overlay.get_node("OverlayLayer").visible)

func test_image_refits_after_viewport_resize() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child_autofree(viewport)
	var overlay : Control = OverlayScene.instantiate()
	viewport.add_child(overlay)
	overlay.show_rules()
	for viewport_size in [Vector2i(720, 1280), Vector2i(1920, 1080)]:
		viewport.size = viewport_size
		await wait_frames(2)
		var image : TextureRect = overlay.get_node("OverlayLayer/ImageView")
		assert_almost_eq(image.position + image.size / 2.0, Vector2(viewport_size) / 2.0, Vector2.ONE * 0.01)
		assert_almost_eq(image.size.x / image.size.y, 4505.0 / 2232.0, 0.001)
		assert_true(image.size.x <= viewport_size.x - 48.0)
		assert_true(image.size.y <= viewport_size.y - 48.0)

func _check_scene_button(scene_path : String, button_path : String) -> void:
	var scene : Node = load(scene_path).instantiate()
	var button : Button = scene.get_node(button_path)
	var overlay : Control = scene.get_node("RulesHintOverlay")
	assert_eq(button.text, "游戏规则提示卡")
	assert_eq(button.get_theme_color("font_color"), Color(0.6, 0.85, 1, 1))
	assert_true(button.pressed.is_connected(Callable(overlay, "show_rules")))
	button.get_parent().remove_child(button)
	scene.remove_child(overlay)
	if scene is Game:
		scene.game_wrapper.free()
	scene.free()
	add_child_autofree(button)
	add_child_autofree(overlay)
	button.pressed.emit()
	assert_true(overlay.visible)
	assert_true(overlay.get_node("OverlayLayer").visible)

func test_main_menu_button_opens_shared_overlay() -> void:
	_check_scene_button("res://scenes/menu/main_menu.tscn", "RulesHintButton")

func test_game_button_opens_shared_overlay() -> void:
	_check_scene_button("res://scenes/game/game.tscn", "PlayerLife/RulesHintButton")

func test_menu_tools_do_not_overlap_with_community_entry_enabled() -> void:
	var menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	menu.set_script(LayoutOnlyMenu)
	add_child_autofree(menu)
	menu.hide_customs_browser = false
	await wait_frames(2)
	var buttons := [
		menu.get_node("ViewCardsButton"), menu.get_node("CustomsBrowserButton"),
		menu.get_node("RulesHintButton"), menu.get_node("LoadReplayButton"),
		menu.get_node("tierlistbutton")
	]
	for index in range(buttons.size() - 1):
		assert_lte(buttons[index].get_rect().end.y, buttons[index + 1].position.y)
	assert_lte(buttons.back().get_rect().end.y, 652.0)
	menu.hide_customs_browser = true
	assert_eq(menu.get_node("RulesHintButton").position.y, 480.0)
	assert_eq(menu.get_node("LoadReplayButton").position.y, 546.0)
	assert_eq(menu.get_node("tierlistbutton").position.y, 592.0)

func test_tier_list_preserves_full_opacity_without_changing_menu_opacity() -> void:
	var menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	menu.set_script(LayoutOnlyMenu)
	add_child_autofree(menu)
	menu._apply_main_menu_ui_opacity()

	var dialog : Control = menu.get_node("TierListDialog")
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	dialog.show_tier_list(image)
	assert_true(dialog.visible)
	assert_eq(dialog.modulate, Color.WHITE, "Tier list is not faded by menu opacity")
	assert_eq(dialog.get_node("DialogPanel/ImageView").modulate, Color.WHITE)
	assert_eq(dialog.get_node("DialogPanel").modulate, Color.WHITE, "Panel does not fade its children")
	assert_almost_eq(dialog.get_node("DialogPanel").self_modulate.a, GlobalSettings.MainMenuUiOpacity, 0.0001)
	assert_almost_eq(dialog.get_node("Dimmer").self_modulate.a, GlobalSettings.MainMenuUiOpacity, 0.0001)
	assert_almost_eq(menu.get_node("tierlistbutton").modulate.a, GlobalSettings.MainMenuUiOpacity, 0.0001)
	assert_almost_eq(menu.get_node("RulesHintButton").modulate.a, GlobalSettings.MainMenuUiOpacity, 0.0001)
	assert_almost_eq(dialog.get_node("Dimmer").color.a, 0.72, 0.0001, "Background dimming stays unchanged")
	dialog.close_dialog()
	assert_false(dialog.visible)
