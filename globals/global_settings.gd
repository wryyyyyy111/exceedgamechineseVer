extends Node

signal settings_loaded

const BackgroundManager = preload("res://globals/game_background_manager.gd")

const ReleaseLoggingEnabled = false # If true, log even on release builds.
const UseECSServerAlways = true # If true, always defaults to the ECS server (even in debug builds).
const CenterAllSceneText = false #不要开，开了 虽然全部的文本居中 但是主页面的已经居中还是偏上 + 游戏卡卡的。
const ShowMobileResourceBudget = false #todo 显示右侧的移动端资源加载预算。
var MuteEmotes = false
const ClientVersionString : String = "261025.1020" # YYMMDD.HHMM #!最后版本改动时间261020
const ReplayVersion : int = 1

# Web 端动画播放速度倍率：手机端（web_android/web_ios/mobile）默认 1.5x。
var phone_web_speed : float = 1.5
#todo 手机端 animations 资源完成全部处理后的最终展示缩放倍率。
var phone_animation_final_scaling_adjust : float = 1.1
#? Web 端动画播放速度倍率：除手机端外的 Web 平台默认 1.0x。
var other_web_speed : float = 1.0
#? 是否启用“手机 Web 通过运行时健康状态来跳过积压动画”的判定。
var phone_skip_web_judge : bool = true
#? 是否启用“非手机 Web 通过运行时健康状态来跳过积压动画”的判定。
var other_skip_web_judge : bool = false

#todo 角色觉醒背景图（exceedgear.png）的显示大小倍率。
var exceed_char_bg_size : float = 1.6

#todo const CharacterBanlist = ['carmine']
var CharacterBanlist : Array = []
# All times are in seconds
const DefaultStartingTimer : int = 15 * 60
const DefaultEnforceTimer : bool = false
const DefaultMinimumTimePerChoice : int = 20
const DefaultBestOf : int = 1
const DefaultRandomizeFirstVsAi : bool = false
const DefaultAIMode : String = "omniscient"

#主界面ui透明度控制 除了背景
const DefaultMainMenuUiOpacity : float = 0.68
const MainMenuUiOpacityMin : float = 0.35
const MainMenuUiOpacityMax : float = 1.0

const MatchmakingStartingTimer : int = 15 * 60
const MatchmakingEnforceTimer : bool = false
const MatchmakingMinimumTimePerChoice : int = 20
const MatchmakingBestOf : int = 1

# Persistent Settings
var BGMEnabled = false
var DefaultPlayerName = ""
var GameSoundsEnabled = true
var AnimationsEnabled = true
var PlayerCharacter = ""
var CombatLogSettings = {}
var CustomStartingTimer : int = DefaultStartingTimer
var CustomBestOf : int = DefaultBestOf
var CustomEnforceTimer : bool = DefaultEnforceTimer
var CustomHpRankModeEnabled : bool = false
var CustomMinimumTimePerChoice : int = DefaultMinimumTimePerChoice
var RandomizeFirstVsAI : bool = DefaultRandomizeFirstVsAi
var AIMode : String = DefaultAIMode
var ReplayShowOpponentHand : bool = false
var MainMenuBackgroundStyle : String = "BG1"
var MainMenuUiOpacity : float = DefaultMainMenuUiOpacity
var ArenaStyle : String = "classic"
var RandomHistory = []
const RandomHistoryMaxSize = 10
var IgnoreRandomHistory = false
var ActionConfirmationEnabled : bool = false
var _web_fullscreen_initialized := false
var _web_fullscreen_window = null
var _web_fullscreen_support_initialized := false
var _web_fullscreen_supported := false
var _web_landscape_button_support_initialized := false
var _web_landscape_button_supported := false
var _mobile_landscape_last_status := "idle"

const user_settings_file = "user://settings.json"

func can_request_fullscreen() -> bool:
	if OS.has_feature("web"):
		return _is_web_fullscreen_supported()
	return DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS)

func is_fullscreen() -> bool:
	if OS.has_feature("web"):
		return _is_web_fullscreen()
	var window_mode := DisplayServer.window_get_mode()
	return window_mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or window_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

func request_fullscreen() -> void:
	if OS.has_feature("web"):
		_request_web_fullscreen()
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func exit_fullscreen() -> void:
	if OS.has_feature("web"):
		_exit_web_fullscreen()
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func toggle_fullscreen() -> void:
	if is_fullscreen():
		exit_fullscreen()
	else:
		request_fullscreen()

func _request_web_fullscreen() -> void:
	if not _is_web_fullscreen_supported():
		return
	_ensure_web_fullscreen_window()
	if _web_fullscreen_window == null:
		return
	_web_fullscreen_window.requestGameFullscreen()

func _exit_web_fullscreen() -> void:
	if not _is_web_fullscreen_supported():
		return
	_ensure_web_fullscreen_window()
	if _web_fullscreen_window == null:
		return
	_web_fullscreen_window.exitGameFullscreen()

func _is_web_fullscreen() -> bool:
	if not _is_web_fullscreen_supported():
		return false
	_ensure_web_fullscreen_window()
	if _web_fullscreen_window == null:
		return false
	return _web_fullscreen_window.isGameFullscreen()

func _is_web_fullscreen_supported() -> bool:
	if _web_fullscreen_support_initialized:
		return _web_fullscreen_supported
	_ensure_web_fullscreen_window()
	if _web_fullscreen_window == null:
		_web_fullscreen_support_initialized = true
		_web_fullscreen_supported = false
		return false
	_web_fullscreen_support_initialized = true
	_web_fullscreen_supported = bool(_web_fullscreen_window.isGameFullscreenSupported())
	return _web_fullscreen_supported

func _ensure_web_fullscreen_window() -> void:
	# JavaScriptBridge is a built-in Godot 4 class on Web, not an Engine singleton.
	# Callers already guard with OS.has_feature("web"), so we can use it directly here.
	if not _web_fullscreen_initialized:
		_web_fullscreen_window = JavaScriptBridge.get_interface("window")
		_web_fullscreen_initialized = _web_fullscreen_window != null

func is_phone_web_platform() -> bool:
	return OS.has_feature("web") and (
		OS.has_feature("mobile")
		or OS.has_feature("web_android")
		or OS.has_feature("web_ios")
	)

func get_current_web_animation_speed() -> float:
	if not OS.has_feature("web"):
		return 1.0
	if is_phone_web_platform():
		return maxf(0.01, phone_web_speed)
	return maxf(0.01, other_web_speed)

func should_skip_web_backlog_by_health() -> bool:
	if not OS.has_feature("web"):
		return false
	return phone_skip_web_judge if is_phone_web_platform() else other_skip_web_judge

func set_web_rotation_render_scale(enabled : bool) -> bool:
	if not OS.has_feature("web"):
		return false
	_ensure_web_fullscreen_window()
	if _web_fullscreen_window == null:
		return false
	if not _web_fullscreen_window.hasOwnProperty("setGameRotationRenderScale"):
		return false
	return bool(_web_fullscreen_window.setGameRotationRenderScale(enabled))

func can_request_mobile_landscape_button() -> bool:
	if not OS.has_feature("web"):
		return false
	return true

func request_mobile_landscape_button() -> bool:
	if not can_request_mobile_landscape_button():
		_mobile_landscape_last_status = "unsupported"
		return false
	_ensure_web_fullscreen_window()
	if _web_fullscreen_window == null:
		_mobile_landscape_last_status = "no-window"
		return false
	if _is_web_landscape_button_supported():
		_mobile_landscape_last_status = "pending"
		_web_fullscreen_window.requestGameLandscapeFromButton()
		return true
	if _is_web_fullscreen_supported():
		_mobile_landscape_last_status = "fallback-fullscreen-only"
		_request_web_fullscreen()
		return true
	_mobile_landscape_last_status = "fullscreen-unsupported"
	return true

func get_mobile_landscape_button_status() -> String:
	if not OS.has_feature("web"):
		return "not-web"
	if not _is_web_landscape_button_supported():
		return _mobile_landscape_last_status
	_ensure_web_fullscreen_window()
	if _web_fullscreen_window == null:
		return "no-window"
	return str(_web_fullscreen_window.getGameLandscapeButtonStatus())

func _is_web_landscape_button_supported() -> bool:
	if _web_landscape_button_support_initialized:
		return _web_landscape_button_supported
	_ensure_web_fullscreen_window()
	if _web_fullscreen_window == null:
		_web_landscape_button_support_initialized = true
		_web_landscape_button_supported = false
		return false
	_web_landscape_button_support_initialized = true
	_web_landscape_button_supported = bool(
		_web_fullscreen_window.hasOwnProperty("requestGameLandscapeFromButton")
		and _web_fullscreen_window.hasOwnProperty("getGameLandscapeButtonStatus")
	)
	return _web_landscape_button_supported

func get_client_version() -> String:
	var prepend = ""
	if OS.is_debug_build():
		prepend = "dev_"
	return prepend + ClientVersionString

func is_logging_enabled() -> bool:
	if ReleaseLoggingEnabled:
		return true
	return OS.is_debug_build()

func get_server_url() -> String:
	const ecs_url = "wss://exceedcntyd.com"
	const local_url = "ws://localhost:8080"
	if UseECSServerAlways or not OS.is_debug_build():
		return ecs_url
	else:
		return local_url

func load_persistent_settings() -> bool:  # returns success code
	if not FileAccess.file_exists(user_settings_file):
		print("Unable to load settings file.")
		settings_loaded.emit()
		return false # Error! We don't have a save to load.

	var file = FileAccess.open(user_settings_file, FileAccess.READ)
	var text = file.get_as_text()
	var json = JSON.parse_string(text)
	print("Settings json: %s" % text)
	if OS.has_feature("web"):
		# Web 端每次访问都默认关闭背景音乐，不读取历史 BGM 开关设置。
		BGMEnabled = false
	elif 'BGMEnabled' in json and json['BGMEnabled'] is bool:
		BGMEnabled = json['BGMEnabled']
	if 'DefaultPlayerName' in json and json['DefaultPlayerName'] is String:
		DefaultPlayerName = json['DefaultPlayerName']
	if 'GameSoundsEnabled' in json and json['GameSoundsEnabled'] is bool:
		GameSoundsEnabled = json['GameSoundsEnabled']
	if 'AnimationsEnabled' in json and json['AnimationsEnabled'] is bool:
		AnimationsEnabled = json['AnimationsEnabled']
	if 'CombatLogSettings' in json and json['CombatLogSettings'] is Dictionary:
		CombatLogSettings = json['CombatLogSettings']
	if 'CustomStartingTimer' in json: #raise concern
		CustomStartingTimer = json['CustomStartingTimer']
	if 'CustomEnforceTimer' in json and json['CustomEnforceTimer'] is bool:
		CustomEnforceTimer = json['CustomEnforceTimer']
	if 'CustomHpRankModeEnabled' in json and json['CustomHpRankModeEnabled'] is bool:
		CustomHpRankModeEnabled = json['CustomHpRankModeEnabled']
	if 'CustomBestOf' in json:
		CustomBestOf = json['CustomBestOf']
	if 'CustomMinimumTimePerChoice' in json:
		CustomMinimumTimePerChoice = json['CustomMinimumTimePerChoice']
	if 'RandomizeFirstVsAI' in json and json['RandomizeFirstVsAI'] is bool:
		RandomizeFirstVsAI = json['RandomizeFirstVsAI']
	if 'AIMode' in json and json['AIMode'] is String and json['AIMode'] in ["rules", "omniscient"]:
		AIMode = json['AIMode']
	if 'ReplayShowOpponentHand' in json and json['ReplayShowOpponentHand'] is bool:
		ReplayShowOpponentHand = json['ReplayShowOpponentHand']
	if 'MainMenuBackgroundStyle' in json and json['MainMenuBackgroundStyle'] is String:
		MainMenuBackgroundStyle = _normalize_main_menu_background_style(json['MainMenuBackgroundStyle'])
	if 'MainMenuUiOpacity' in json and typeof(json['MainMenuUiOpacity']) in [TYPE_FLOAT, TYPE_INT]:
		MainMenuUiOpacity = _normalize_main_menu_ui_opacity(float(json['MainMenuUiOpacity']))
	if 'ArenaStyle' in json and json['ArenaStyle'] is String:
		ArenaStyle = _normalize_arena_style(json['ArenaStyle'])
	if 'PlayerCharacter' in json and json['PlayerCharacter'] is String and not json['PlayerCharacter'].is_empty():
		PlayerCharacter = json['PlayerCharacter']
	if 'RandomHistory' in json and json['RandomHistory'] is Array:
		RandomHistory = json['RandomHistory']
	if 'IgnoreRandomHistory' in json and json['IgnoreRandomHistory'] is bool:
		IgnoreRandomHistory = json['IgnoreRandomHistory']
	if 'ActionConfirmationEnabled' in json and json['ActionConfirmationEnabled'] is bool:
		ActionConfirmationEnabled = json['ActionConfirmationEnabled']
	else:
		PlayerCharacter = 'solbadguy'
	settings_loaded.emit()
	return true


func save_persistent_settings():
	var settings = {
		"HasExplicitBGMPreference": true,
		"BGMEnabled": BGMEnabled,
		"DefaultPlayerName": DefaultPlayerName,
		"GameSoundsEnabled": GameSoundsEnabled,
		"AnimationsEnabled": AnimationsEnabled,
		"PlayerCharacter": PlayerCharacter,
		"CombatLogSettings": CombatLogSettings,
		"CustomStartingTimer": CustomStartingTimer,
		"CustomEnforceTimer": CustomEnforceTimer,
		"CustomHpRankModeEnabled": CustomHpRankModeEnabled,
		"CustomBestOf": CustomBestOf,
		"CustomMinimumTimePerChoice": CustomMinimumTimePerChoice,
		"RandomizeFirstVsAI": RandomizeFirstVsAI,
		"AIMode": AIMode,
		"ReplayShowOpponentHand": ReplayShowOpponentHand,
		"MainMenuBackgroundStyle": MainMenuBackgroundStyle,
		"MainMenuUiOpacity": MainMenuUiOpacity,
		"ArenaStyle": ArenaStyle,
		"RandomHistory": RandomHistory,
		"IgnoreRandomHistory": IgnoreRandomHistory,
		"ActionConfirmationEnabled": ActionConfirmationEnabled,
	}

	var file = FileAccess.open(user_settings_file, FileAccess.WRITE)
	file.store_line(JSON.stringify(settings))

func set_bgm(value : bool):
	BGMEnabled = value
	save_persistent_settings()

func set_game_sounds_enabled(value : bool):
	GameSoundsEnabled = value
	save_persistent_settings()

func set_animations_enabled(value : bool):
	AnimationsEnabled = value
	save_persistent_settings()

func set_player_name(value : String):
	DefaultPlayerName = value
	save_persistent_settings()

func set_player_character(value: String):
	if not value.begins_with("custom_"):
		PlayerCharacter = value
		save_persistent_settings()

func set_combat_log_setting(setting : String, value):
	CombatLogSettings[setting] = value
	save_persistent_settings()

func set_randomize_first_player_vs_ai(value : bool):
	RandomizeFirstVsAI = value
	save_persistent_settings()

func set_ai_mode(value : String):
	if value in ["rules", "omniscient"]:
		AIMode = value
		save_persistent_settings()

func set_replay_show_opponent_hand(value : bool):
	ReplayShowOpponentHand = value
	save_persistent_settings()

func set_main_menu_background_style(value : String):
	MainMenuBackgroundStyle = _normalize_main_menu_background_style(value)
	save_persistent_settings()

func set_main_menu_ui_opacity(value : float):
	MainMenuUiOpacity = _normalize_main_menu_ui_opacity(value)
	save_persistent_settings()

func set_arena_style(value : String):
	ArenaStyle = _normalize_arena_style(value)
	save_persistent_settings()

func set_starting_timers(value : int):
	CustomStartingTimer = value
	save_persistent_settings()

func set_enforce_timers(value : bool):
	CustomEnforceTimer = value
	save_persistent_settings()

func set_custom_hp_rank_mode_enabled(value : bool):
	CustomHpRankModeEnabled = value
	save_persistent_settings()

func set_minimum_time_per_choice(value : int):
	CustomMinimumTimePerChoice = value
	save_persistent_settings()

func append_random_history(value : String):
	if RandomHistory.size() >= RandomHistoryMaxSize:
		RandomHistory.pop_front()
	RandomHistory.append(value)
	save_persistent_settings()

func set_ignore_random_history(value : bool):
	IgnoreRandomHistory = value
	save_persistent_settings()

func set_action_confirmation_enabled(value : bool):
	ActionConfirmationEnabled = value
	save_persistent_settings()

func _normalize_arena_style(value : String) -> String:
	return BackgroundManager.normalize_background_id(value)

func _normalize_main_menu_background_style(value : String) -> String:
	return BackgroundManager.normalize_main_menu_background_id(value)

func _normalize_main_menu_ui_opacity(value : float) -> float:
	return clampf(value, MainMenuUiOpacityMin, MainMenuUiOpacityMax)
