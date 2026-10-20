class_name PreferencesWindow
extends Control

signal bgm_check_toggled
signal main_menu_background_changed

const BackgroundManager = preload("res://globals/game_background_manager.gd")

const FULLSCREEN_BUTTON_NORMAL_COLOR := Color("#d97a1d")
const FULLSCREEN_BUTTON_HOVER_COLOR := Color("#e38a32")
const FULLSCREEN_BUTTON_PRESSED_COLOR := Color("#bf6713")
const FULLSCREEN_BUTTON_FOCUS_COLOR := Color("#d97a1d")
const MOBILE_ROTATE_BUTTON_NORMAL_COLOR := Color("#2f6e9f")
const MOBILE_ROTATE_BUTTON_HOVER_COLOR := Color("#3d82ba")
const MOBILE_ROTATE_BUTTON_PRESSED_COLOR := Color("#255a82")
const MOBILE_ROTATE_BUTTON_FOCUS_COLOR := Color("#2f6e9f")

const CONFIRM_BUTTON_NORMAL_COLOR := Color("#4e9e3a")
const CONFIRM_BUTTON_HOVER_COLOR := Color("#63b84d")
const CONFIRM_BUTTON_PRESSED_COLOR := Color("#3b7d2b")
const CONFIRM_BUTTON_FOCUS_COLOR := Color("#4e9e3a")

const ARENA_STYLE_POPUP_FONT_SIZE := 24
const ARENA_STYLE_POPUP_MAX_HEIGHT := 360

@onready var timer_selection = %StartingTimersSelection
@onready var best_of_selection = %BestOfSelection
@onready var enforce_timer_checkbutton = %EnforceTimerCheckbutton
@onready var custom_hp_rank_mode_checkbutton = %CustomHpRankModeCheckbutton
@onready var minimum_time_selection = %MinimumTimeSelection
@onready var bgm_checkbutton = %BGMCheckbutton
@onready var game_sound_checkbutton = %GameSoundsCheckbutton
@onready var animations_checkbutton = %AnimationsCheckbutton
@onready var fullscreen_button = %FullscreenButton
@onready var mobile_landscape_button = %MobileLandscapeButton
@onready var mobile_landscape_hint_label = %MobileLandscapeHintLabel
@onready var action_confirmation_button = %ActionConfirmationButton
@onready var ai_first_player_checkbutton = %AIFirstPlayerCheckbutton
@onready var replay_show_opponent_hand_button = %ReplayShowOpponentHandButton
@onready var true_random_checkbutton = %TrueRandomSelectCheckbox
@onready var main_menu_background_selection = %MainMenuBackgroundSelection
@onready var arena_style_selection = %ArenaStyleSelection
@onready var ai_mode_selection = %AIModeSelection

var _last_fullscreen_state := false

# Called when the node enters the scene tree for the first time.
func _ready():
	GlobalSettings.settings_loaded.connect(display_loaded_settings)
	_populate_main_menu_background_selection()
	_populate_arena_style_selection()
	_populate_ai_mode_selection()
	_apply_selection_popup_style(main_menu_background_selection)
	_apply_selection_popup_style(arena_style_selection)
	_apply_selection_popup_style(ai_mode_selection)
	_apply_fullscreen_button_style()
	_apply_mobile_landscape_button_style()
	_apply_action_confirmation_button_style()
	set_process(true)
	_refresh_fullscreen_button_text(true)
	_refresh_mobile_landscape_button_state(true)
	# Populate the possible custom game timer selections
	for mins in [1, 6, 9, 12, 15, 20, 25, 30]:
		timer_selection.add_item("%s:00" % mins, mins*60)
	timer_selection.select(timer_selection.get_item_index(GlobalSettings.CustomStartingTimer))

	# Populate the possible minimum time per choice selections
	for secs in [0, 10, 15, 20, 25, 30, 45, 60]:
		minimum_time_selection.add_item("%02d:%02d" % [secs / 60, secs % 60], secs)

func display_loaded_settings():
	best_of_selection.select(best_of_selection.get_item_index((GlobalSettings.CustomBestOf)))
	enforce_timer_checkbutton.set_pressed_no_signal(GlobalSettings.CustomEnforceTimer)
	custom_hp_rank_mode_checkbutton.set_pressed_no_signal(GlobalSettings.CustomHpRankModeEnabled)
	bgm_checkbutton.set_pressed_no_signal(GlobalSettings.BGMEnabled)
	ai_first_player_checkbutton.set_pressed_no_signal(GlobalSettings.RandomizeFirstVsAI)
	game_sound_checkbutton.set_pressed_no_signal(GlobalSettings.GameSoundsEnabled)
	animations_checkbutton.set_pressed_no_signal(GlobalSettings.AnimationsEnabled)
	timer_selection.select(timer_selection.get_item_index(GlobalSettings.CustomStartingTimer))
	minimum_time_selection.select(minimum_time_selection.get_item_index((GlobalSettings.CustomMinimumTimePerChoice)))
	replay_show_opponent_hand_button.set_pressed_no_signal(GlobalSettings.ReplayShowOpponentHand)
	true_random_checkbutton.set_pressed_no_signal(GlobalSettings.IgnoreRandomHistory)
	_select_ai_mode(GlobalSettings.AIMode)
	_select_main_menu_background_style(GlobalSettings.MainMenuBackgroundStyle)
	_select_arena_style(GlobalSettings.ArenaStyle)
	_refresh_action_confirmation_button_text()
	_refresh_fullscreen_button_text(true)
	_refresh_mobile_landscape_button_state(true)

func _populate_main_menu_background_selection() -> void:
	main_menu_background_selection.clear()
	for background_id in BackgroundManager.get_main_menu_background_ids():
		var item_index : int = main_menu_background_selection.item_count
		main_menu_background_selection.add_item(BackgroundManager.get_main_menu_background_label(background_id))
		main_menu_background_selection.set_item_metadata(item_index, background_id)

func _select_main_menu_background_style(background_id: String) -> void:
	var normalized_id := BackgroundManager.normalize_main_menu_background_id(background_id)
	for item_index in range(main_menu_background_selection.item_count):
		if main_menu_background_selection.get_item_metadata(item_index) == normalized_id:
			main_menu_background_selection.select(item_index)
			return

func _populate_arena_style_selection() -> void:
	arena_style_selection.clear()
	for background_id in BackgroundManager.get_background_ids():
		var item_index : int = arena_style_selection.item_count
		arena_style_selection.add_item(BackgroundManager.get_background_label(background_id))
		arena_style_selection.set_item_metadata(item_index, background_id)

func _populate_ai_mode_selection() -> void:
	ai_mode_selection.clear()
	ai_mode_selection.add_item("入门难度")
	ai_mode_selection.set_item_metadata(0, "rules")
	ai_mode_selection.add_item("超级难度")
	ai_mode_selection.set_item_metadata(1, "omniscient")

func _select_ai_mode(ai_mode: String) -> void:
	for item_index in range(ai_mode_selection.item_count):
		if ai_mode_selection.get_item_metadata(item_index) == ai_mode:
			ai_mode_selection.select(item_index)
			return
	ai_mode_selection.select(1)

func _apply_selection_popup_style(selection: OptionButton) -> void:
	var popup_menu : PopupMenu = selection.get_popup()
	popup_menu.add_theme_font_size_override("font_size", ARENA_STYLE_POPUP_FONT_SIZE)
	popup_menu.max_size = Vector2i(10000, ARENA_STYLE_POPUP_MAX_HEIGHT)

func _select_arena_style(background_id: String) -> void:
	var normalized_id := BackgroundManager.normalize_background_id(background_id)
	for item_index in range(arena_style_selection.item_count):
		if arena_style_selection.get_item_metadata(item_index) == normalized_id:
			arena_style_selection.select(item_index)
			return

func _process(_delta: float) -> void:
	if visible:
		_refresh_fullscreen_button_text()
		_refresh_mobile_landscape_button_state()

func _notification(what):
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		_refresh_fullscreen_button_text(true)
		_refresh_mobile_landscape_button_state(true)

func _apply_fullscreen_button_style() -> void:
	if not is_instance_valid(fullscreen_button):
		return
	var style_colors = {
		"normal": FULLSCREEN_BUTTON_NORMAL_COLOR,
		"hover": FULLSCREEN_BUTTON_HOVER_COLOR,
		"pressed": FULLSCREEN_BUTTON_PRESSED_COLOR,
		"focus": FULLSCREEN_BUTTON_FOCUS_COLOR,
	}
	for style_name in style_colors:
		var base_style = fullscreen_button.get_theme_stylebox(style_name)
		var style = base_style.duplicate() if base_style else StyleBoxFlat.new()
		if not style is StyleBoxFlat:
			style = StyleBoxFlat.new()
		style.bg_color = style_colors[style_name]
		fullscreen_button.add_theme_stylebox_override(style_name, style)

func _apply_mobile_landscape_button_style() -> void:
	if not is_instance_valid(mobile_landscape_button):
		return
	var style_colors = {
		"normal": MOBILE_ROTATE_BUTTON_NORMAL_COLOR,
		"hover": MOBILE_ROTATE_BUTTON_HOVER_COLOR,
		"pressed": MOBILE_ROTATE_BUTTON_PRESSED_COLOR,
		"focus": MOBILE_ROTATE_BUTTON_FOCUS_COLOR,
	}
	for style_name in style_colors:
		var base_style = mobile_landscape_button.get_theme_stylebox(style_name)
		var style = base_style.duplicate() if base_style else StyleBoxFlat.new()
		if not style is StyleBoxFlat:
			style = StyleBoxFlat.new()
		style.bg_color = style_colors[style_name]
		mobile_landscape_button.add_theme_stylebox_override(style_name, style)

func _apply_action_confirmation_button_style() -> void:
	if not is_instance_valid(action_confirmation_button):
		return
	var style_colors = {
		"normal": CONFIRM_BUTTON_NORMAL_COLOR,
		"hover": CONFIRM_BUTTON_HOVER_COLOR,
		"pressed": CONFIRM_BUTTON_PRESSED_COLOR,
		"focus": CONFIRM_BUTTON_FOCUS_COLOR,
	}
	for style_name in style_colors:
		var base_style = action_confirmation_button.get_theme_stylebox(style_name)
		var style = base_style.duplicate() if base_style else StyleBoxFlat.new()
		if not style is StyleBoxFlat:
			style = StyleBoxFlat.new()
		style.bg_color = style_colors[style_name]
		action_confirmation_button.add_theme_stylebox_override(style_name, style)

func _refresh_action_confirmation_button_text() -> void:
	if not is_instance_valid(action_confirmation_button):
		return
	action_confirmation_button.text = "关闭操作前确认" if GlobalSettings.ActionConfirmationEnabled else "打开操作前确认"

func _refresh_fullscreen_button_text(force: bool = false) -> void:
	if not is_instance_valid(fullscreen_button):
		return
	var fullscreen_supported := GlobalSettings.can_request_fullscreen()
	fullscreen_button.disabled = not fullscreen_supported
	if not fullscreen_supported:
		_last_fullscreen_state = false
		fullscreen_button.text = "不支持全屏"
		return
	var fullscreen_now := GlobalSettings.is_fullscreen()
	if not force and fullscreen_now == _last_fullscreen_state:
		return
	_last_fullscreen_state = fullscreen_now
	fullscreen_button.text = "退出全屏" if fullscreen_now else "进入全屏"

func _refresh_mobile_landscape_button_state(force: bool = false) -> void:
	if not is_instance_valid(mobile_landscape_button) or not is_instance_valid(mobile_landscape_hint_label):
		return
	var supported := GlobalSettings.can_request_mobile_landscape_button()
	mobile_landscape_button.disabled = not supported
	if supported:
		mobile_landscape_button.text = "手机端转屏（测试）"
		if force or mobile_landscape_hint_label.text.is_empty() or mobile_landscape_hint_label.text == "当前平台不支持该按钮":
			mobile_landscape_hint_label.text = "点击后会尝试：进入全屏 -> 锁定横屏。"
	else:
		mobile_landscape_button.text = "手机端转屏（不可用）"
		mobile_landscape_hint_label.text = "当前平台不支持该按钮"

func _get_mobile_landscape_status_message(status: String) -> String:
	match status:
		"success":
			return "已请求全屏并锁定横屏。若没有变化，请手动点击浏览器全屏后重试。"
		"fullscreen-unsupported":
			return "浏览器不支持网页全屏，无法继续锁定横屏。"
		"fullscreen-failed":
			return "进入全屏失败。请确保由手动点击按钮触发并允许全屏。"
		"fullscreen-unsupported":
			return "当前浏览器不支持网页全屏，因此无法继续自动转到横屏。"
		"orientation-unsupported":
			return "浏览器不支持锁定屏幕方向。请关闭系统竖屏锁后手动横持手机。"
		"orientation-failed":
			return "锁定横屏失败。请先关闭系统竖屏锁，再点一次。"
		"fallback-fullscreen-only":
			return "当前浏览器不支持网页锁定横屏，已尝试进入全屏。请关闭系统竖屏锁并手动横持手机。"
		"pending":
			return "正在请求全屏和横屏锁定..."
		"unsupported":
			return "当前平台不支持该按钮"
		_:
			return "转屏请求未完成，请稍后重试。"

func _on_bgm_check_box_toggled(button_pressed):
	GlobalSettings.set_bgm(button_pressed)
	bgm_check_toggled.emit()

func _on_game_sounds_check_box_toggled(button_pressed):
	GlobalSettings.set_game_sounds_enabled(button_pressed)

func _on_animations_check_box_toggled(button_pressed):
	GlobalSettings.set_animations_enabled(button_pressed)

func _on_starting_timers_selection_item_selected(_index):
	GlobalSettings.set_starting_timers(timer_selection.get_selected_id())

func _on_enforce_timer_check_box_toggled(toggled_on):
	GlobalSettings.set_enforce_timers(toggled_on)

func _on_custom_hp_rank_mode_checkbutton_toggled(toggled_on):
	GlobalSettings.set_custom_hp_rank_mode_enabled(toggled_on)

func _on_minimum_time_selection_item_selected(_index):
	GlobalSettings.set_minimum_time_per_choice(minimum_time_selection.get_selected_id())

func _on_close_button_pressed() -> void:
	hide()

func _on_ai_first_player_checkbutton_toggled(button_pressed):
	GlobalSettings.set_randomize_first_player_vs_ai(button_pressed)

func _on_ai_mode_selection_item_selected(index: int) -> void:
	GlobalSettings.set_ai_mode(ai_mode_selection.get_item_metadata(index))

func _on_replay_show_opponent_hand_button_toggled(button_pressed):
	GlobalSettings.set_replay_show_opponent_hand(button_pressed)

func _on_true_random_select_checkbox_toggled(button_pressed: bool) -> void:
	GlobalSettings.set_ignore_random_history(button_pressed)

func _on_main_menu_background_selection_item_selected(index: int) -> void:
	GlobalSettings.set_main_menu_background_style(main_menu_background_selection.get_item_metadata(index))
	main_menu_background_changed.emit()

func _on_arena_style_selection_item_selected(index: int) -> void:
	GlobalSettings.set_arena_style(arena_style_selection.get_item_metadata(index))

func _on_fullscreen_button_pressed() -> void:
	if not GlobalSettings.can_request_fullscreen():
		_refresh_fullscreen_button_text(true)
		return
	GlobalSettings.toggle_fullscreen()
	_refresh_fullscreen_button_text(true)

func _on_mobile_landscape_button_pressed() -> void:
	if not is_instance_valid(mobile_landscape_hint_label):
		return
	if not GlobalSettings.can_request_mobile_landscape_button():
		mobile_landscape_hint_label.text = "当前平台不支持该按钮"
		return
	if not GlobalSettings.request_mobile_landscape_button():
		mobile_landscape_hint_label.text = "转屏请求发起失败，请刷新页面后重试。"
		return
	mobile_landscape_hint_label.text = _get_mobile_landscape_status_message("pending")
	await get_tree().create_timer(0.9).timeout
	var status := GlobalSettings.get_mobile_landscape_button_status()
	mobile_landscape_hint_label.text = _get_mobile_landscape_status_message(status)

func _on_action_confirmation_button_pressed() -> void:
	GlobalSettings.set_action_confirmation_enabled(not GlobalSettings.ActionConfirmationEnabled)
	_refresh_action_confirmation_button_text()

