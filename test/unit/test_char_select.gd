extends GutTest

const CHAR_SELECT_SCENE = preload("res://scenes/menu/char_select.tscn")

func test_custom_button_can_start_hidden_and_be_restored():
	var char_select = CHAR_SELECT_SCENE.instantiate()
	char_select.custom_button_enabled = false
	add_child_autofree(char_select)

	assert_false(char_select.custom_button.visible)
	assert_true(char_select.season_button_s0.visible)
	assert_true(char_select.show_season("season0"))

	char_select.set_custom_button_enabled(true)
	assert_true(char_select.custom_button.visible)
	assert_eq(char_select.current_season_id, "season0")

	char_select.set_custom_button_enabled(false)
	assert_false(char_select.custom_button.visible)
	assert_true(char_select.charselect_s0.visible)

func test_custom_button_setting_before_ready_is_applied():
	var char_select = CHAR_SELECT_SCENE.instantiate()
	char_select.set_custom_button_enabled(false)
	add_child_autofree(char_select)

	assert_false(char_select.custom_button.visible)
	char_select.set_custom_button_enabled(true)
	watch_signals(char_select)
	char_select.custom_button.on_pressed.emit("custom")
	assert_signal_emitted_with_parameters(char_select, "select_character", ["custom"])

func test_season_switches_do_not_change_custom_or_random_buttons():
	var char_select = CHAR_SELECT_SCENE.instantiate()
	add_child_autofree(char_select)
	var random_button = char_select.get_node("TabSelect/CategoriesHBox/RandomAll")

	char_select.set_all_season_columns_enabled(false)
	assert_true(char_select.custom_button.visible)
	assert_true(random_button.visible)

	char_select.set_custom_button_enabled(false)
	char_select.set_all_season_columns_enabled(true)
	assert_false(char_select.custom_button.visible)
	assert_true(random_button.visible)
	assert_true(char_select.charselect_s1.visible)
