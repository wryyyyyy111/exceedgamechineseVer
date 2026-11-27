extends Node2D
var game : Node2D
var splash : Node2D
var versus_splash_timer : Timer

const CENTER_ALIGNMENT = HORIZONTAL_ALIGNMENT_CENTER

const VersusSplashScene = preload("res://scenes/menu/versus_splash.tscn")
const GameScene = preload("res://scenes/game/game.tscn")

const VersusSplashTimeout = 3.0
const MobileWebVersusSplashTimeout = 5.0
const WebRuntimeGameRevealFrames = 2
const MobileWebRuntimeGameRevealFrames = 20
var versus_splash_timer_ready = false
var versus_splash_load_ready = false
var versus_splash_transitioning = false

@onready var reconnect_overlay : Control = $ReconnectOverlay
@onready var reconnect_blocker : ColorRect = $ReconnectOverlay/CloseBlocker
@onready var reconnect_panel : PanelContainer = $ReconnectOverlay/PanelContainer
@onready var reconnect_message_label : Label = $ReconnectOverlay/PanelContainer/MarginContainer/VBoxContainer/MessageLabel
@onready var reconnect_timer_label : Label = $ReconnectOverlay/PanelContainer/MarginContainer/VBoxContainer/TimerLabel
@onready var reconnect_button : Button = $ReconnectOverlay/PanelContainer/MarginContainer/VBoxContainer/ButtonRow/ReconnectButton
@onready var reconnect_save_replay_button : Button = $ReconnectOverlay/PanelContainer/MarginContainer/VBoxContainer/ButtonRow/SaveReplayButton
@onready var reconnect_cancel_button : Button = $ReconnectOverlay/PanelContainer/MarginContainer/VBoxContainer/ButtonRow/CancelButton
@onready var memory_usage_label : Label = $MemoryUsageLayer/MemoryUsageLabel

var memory_usage_update_elapsed := 0.0
const MemoryUsageUpdateInterval := 1.0

# Called when the node enters the scene tree for the first time.
func _ready():
	GlobalSettings.load_persistent_settings()
	memory_usage_label.visible = GlobalSettings.ShowMobileResourceBudget
	if memory_usage_label.visible:
		_update_memory_usage_label()
	_apply_global_text_alignment(self)
	get_tree().node_added.connect(_on_node_added)
	if get_viewport() and not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	_sync_reconnect_overlay_layout()
	ImageCache.load_image_cache()
	NetworkManager.connect("reconnect_state_changed", _on_reconnect_state_changed)
	NetworkManager.connect("waiting_for_opponent_reconnect_changed", _on_waiting_for_opponent_reconnect_changed)
	NetworkManager.connect("session_restore_failed", _on_session_restore_failed)
	$MainMenu.reference_popout_visibility_changed.connect(_on_reference_popout_visibility_changed)
	await _yield_mobile_web_startup_frames("main menu settings")
	await $MainMenu.settings_loaded()
	await _yield_mobile_web_startup_frames("network connect")
	NetworkManager.connect_to_server()
	_on_reconnect_state_changed(NetworkManager.get_reconnect_state())

	var http_request = HTTPRequest.new()
	add_child(http_request)

func _process(delta: float):
	if not GlobalSettings.ShowMobileResourceBudget:
		return
	memory_usage_update_elapsed += delta
	if memory_usage_update_elapsed >= MemoryUsageUpdateInterval:
		memory_usage_update_elapsed = 0.0
		_update_memory_usage_label()

func _update_memory_usage_label():
	memory_usage_label.text = "资源预算: %.1fMB" % MobileResourceBudget.get_total_budget_mb()

func _is_mobile_web_runtime() -> bool:
	return OS.has_feature("web") and (
		OS.has_feature("mobile")
		or OS.has_feature("web_android")
		or OS.has_feature("web_ios")
	)

func _yield_mobile_web_startup_frames(stage_name : String):
	if not _is_mobile_web_runtime():
		return
	print("[MainStartup] 等待移动端启动帧: ", stage_name)
	await get_tree().process_frame
	await get_tree().process_frame

func _on_viewport_size_changed():
	_sync_reconnect_overlay_layout()

func _sync_reconnect_overlay_layout():
	var viewport_size = get_viewport_rect().size
	reconnect_overlay.position = Vector2.ZERO
	reconnect_overlay.size = viewport_size
	reconnect_blocker.position = Vector2.ZERO
	reconnect_blocker.size = viewport_size
	var panel_size = reconnect_panel.custom_minimum_size
	reconnect_panel.position = (viewport_size - panel_size) / 2.0
	reconnect_panel.size = panel_size

func _on_node_added(node: Node):
	if not GlobalSettings.CenterAllSceneText:
		return
	_apply_global_text_alignment(node)

func _apply_global_text_alignment(node: Node):
	if not GlobalSettings.CenterAllSceneText:
		return
	if node is Control:
		_center_control_text(node)
	for child in node.get_children():
		_apply_global_text_alignment(child)

func _center_control_text(control: Control):
	if _has_property(control, &"horizontal_alignment"):
		control.set(&"horizontal_alignment", CENTER_ALIGNMENT)
	elif _has_property(control, &"alignment"):
		control.set(&"alignment", CENTER_ALIGNMENT)

func _has_property(target: Object, property_name: StringName) -> bool:
	for property_info in target.get_property_list():
		if property_info.name == property_name:
			return true
	return false

func _on_return_from_game():
	_clear_versus_splash()
	game = null
	$MainMenu.visible = true
	$MainMenu.returned_from_game()
	_on_reconnect_state_changed(NetworkManager.get_reconnect_state())

func _clear_versus_splash():
	if splash:
		if splash.get_parent():
			splash.get_parent().remove_child(splash)
		splash.queue_free()
		splash = null
	if versus_splash_timer:
		versus_splash_timer.stop()
		if versus_splash_timer.get_parent():
			versus_splash_timer.get_parent().remove_child(versus_splash_timer)
		versus_splash_timer.queue_free()
		versus_splash_timer = null

func _on_splash_timeout():
	print("Timeout finished!")
	versus_splash_timer_ready = true
	if versus_splash_load_ready:
		_reveal_loaded_game_after_splash()

func _on_loading_complete(loaded_game = null):
	if loaded_game != null and loaded_game != game:
		print("Ignoring stale game loading complete signal")
		return
	print("Images loaded!")
	if OS.has_feature("web"):
		_update_versus_splash_status("准备完成，稳定画面")
		var reveal_frames = get_runtime_game_reveal_frames(_is_mobile_web_runtime())
		print("Game reveal settle frames: ", reveal_frames)
		for _i in range(reveal_frames):
			await get_tree().process_frame
			if loaded_game != null and loaded_game != game:
				print("Stopping stale game reveal settle")
				return
	versus_splash_load_ready = true
	_update_versus_splash_status("准备完成")
	if versus_splash_timer_ready:
		_reveal_loaded_game_after_splash()

func _reveal_loaded_game_after_splash():
	if versus_splash_transitioning:
		return
	versus_splash_transitioning = true
	_clear_versus_splash()
	if game:
		if game.has_method("set_match_entry_processing_held"):
			game.set_match_entry_processing_held(false)
		game.visible = true
		# Match-start entrance animation (Eugenia closeup), played once after the splash.
		if game.has_method("try_play_match_start_entrance"):
			game.try_play_match_start_entrance()
	versus_splash_transitioning = false

func _update_versus_splash_status(status_text : String):
	if game and splash and splash.has_method("set_loading_status"):
		splash.set_loading_status(status_text)

func _on_game_loading_status_changed(status_text : String, source_game):
	if source_game != game:
		print("Ignoring stale game loading status: ", status_text)
		return
	_update_versus_splash_status(status_text)

func create_versus_splash(vs_info):
	_clear_versus_splash()
	splash = VersusSplashScene.instantiate()
	add_child(splash)
	splash.set_info(vs_info)
	if game:
		splash.set_loading_status("准备观战" if game.observer_mode else "准备对局")

	versus_splash_timer_ready = false
	versus_splash_load_ready = false

	versus_splash_timer = Timer.new()
	versus_splash_timer.wait_time = get_versus_splash_timeout(_is_mobile_web_runtime())
	versus_splash_timer.one_shot = true
	versus_splash_timer.connect("timeout", _on_splash_timeout)
	add_child(versus_splash_timer)
	versus_splash_timer.start()

	var source_game = game
	game.load_characters_complete.connect(_on_loading_complete.bind(source_game), CONNECT_ONE_SHOT)
	game.loading_status_changed.connect(_on_game_loading_status_changed.bind(source_game))

static func get_runtime_game_reveal_frames(mobile_web_runtime : bool) -> int:
	return MobileWebRuntimeGameRevealFrames if mobile_web_runtime else WebRuntimeGameRevealFrames

static func get_versus_splash_timeout(mobile_web_runtime : bool) -> float:
	return MobileWebVersusSplashTimeout if mobile_web_runtime else VersusSplashTimeout


func _on_main_menu_start_game(vs_info):
	$MainMenu.release_reference_card_cache()
	$MainMenu.release_match_start_background()
	await get_tree().process_frame
	$MainMenu.visible = false
	$MainMenu.stop_music()
	game = GameScene.instantiate()
	game.visible = false
	game.connect("returning_from_game", _on_return_from_game)
	game.set_not_started_directly()
	if game.has_method("set_match_entry_processing_held"):
		game.set_match_entry_processing_held(true)
	add_child(game)
	game.begin_local_game(vs_info)
	game.initialization_after_begin_game()
	create_versus_splash(vs_info)

# Listens for a signal from _start_remote_game in main_menu.
func _on_main_menu_start_remote_game(vs_info, data):
	var is_restore_rebuild = data.has("restore_log")
	if game and NetworkManager.get_reconnect_state()["was_in_game"] and not is_restore_rebuild:
		return
	if game and is_restore_rebuild:
		_clear_versus_splash()
		game.queue_free()
		game = null
		await get_tree().process_frame
	$MainMenu.release_reference_card_cache()
	$MainMenu.release_match_start_background()
	await get_tree().process_frame
	$MainMenu.visible = false
	$MainMenu.stop_music()
	game = GameScene.instantiate()
	game.visible = false
	game.connect("returning_from_game", _on_return_from_game)
	game.set_not_started_directly()
	if game.has_method("set_match_entry_processing_held"):
		game.set_match_entry_processing_held(true)
	add_child(game)
	game.begin_remote_game(data)
	game.initialization_after_begin_game()
	if data.get("replay_step_rebuild", false):
		game.load_characters_complete.connect(_on_replay_step_rebuild_loading_complete.bind(game), CONNECT_ONE_SHOT)
	else:
		create_versus_splash(vs_info)

func _on_replay_step_rebuild_loading_complete(source_game):
	if source_game != game:
		print("Ignoring stale replay rebuild loading complete signal")
		return
	if game and game.has_method("set_match_entry_processing_held"):
		game.set_match_entry_processing_held(false)
	if game:
		game.visible = true

func _on_reconnect_state_changed(state : Dictionary):
	_sync_reconnect_overlay_priority()
	if state["is_waiting_for_opponent_reconnect"]:
		_show_waiting_for_opponent_overlay(state["waiting_for_opponent_reconnect_seconds"])
		return
	if state["is_manual_reconnect"]:
		_show_manual_reconnect_overlay()
		return
	if state["is_auto_reconnecting"]:
		_show_auto_reconnect_overlay(state["reconnect_seconds"])
		return
	reconnect_overlay.visible = false

func _on_waiting_for_opponent_reconnect_changed(is_waiting : bool, seconds : int):
	if is_waiting:
		_show_waiting_for_opponent_overlay(seconds)
	else:
		_on_reconnect_state_changed(NetworkManager.get_reconnect_state())

func _on_reference_popout_visibility_changed(_is_open : bool):
	_on_reconnect_state_changed(NetworkManager.get_reconnect_state())

func _on_session_restore_failed(reason : String):
	print("Session restore failed, returning to menu: ", reason)
	if game and game.has_method("abandon_match_after_disconnect"):
		game.abandon_match_after_disconnect()
		reconnect_overlay.visible = false

func _show_auto_reconnect_overlay(seconds : int):
	_show_reconnect_overlay()
	reconnect_message_label.text = "正在尝试重新连接"
	reconnect_timer_label.text = str(max(seconds, 1))
	reconnect_button.visible = false
	reconnect_save_replay_button.visible = false
	reconnect_cancel_button.visible = true
	reconnect_cancel_button.text = "取消"

func _show_manual_reconnect_overlay():
	_show_reconnect_overlay()
	reconnect_message_label.text = "自动重新连接失败，请主动重新连接"
	reconnect_timer_label.text = ""
	reconnect_button.visible = true
	reconnect_save_replay_button.visible = false
	reconnect_button.text = "重新连接"
	reconnect_button.disabled = NetworkManager.network_state == NetworkManager.NetworkState.NetworkState_Connecting
	reconnect_cancel_button.visible = false

func _show_waiting_for_opponent_overlay(seconds : int):
	if splash and game:
		_clear_versus_splash()
	_show_reconnect_overlay()
	reconnect_message_label.text = "对方断开连接，请等待对方重连"
	reconnect_timer_label.text = str(max(seconds, 1))
	reconnect_button.visible = false
	reconnect_save_replay_button.visible = game != null and game.has_method("save_current_replay")
	reconnect_cancel_button.visible = true
	reconnect_cancel_button.text = "取消"

func _show_reconnect_overlay():
	_sync_reconnect_overlay_layout()
	reconnect_overlay.visible = true
	_sync_reconnect_overlay_priority()
	if not _is_main_menu_reference_popout_open():
		reconnect_overlay.move_to_front()

func _is_main_menu_reference_popout_open() -> bool:
	return $MainMenu.visible and $MainMenu.has_method("is_reference_popout_open") and $MainMenu.is_reference_popout_open()

func _sync_reconnect_overlay_priority():
	var reference_popout_open = _is_main_menu_reference_popout_open()
	if reference_popout_open:
		reconnect_overlay.z_index = -10
		reconnect_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		reconnect_blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		reconnect_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		reconnect_overlay.z_index = 0
		reconnect_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		reconnect_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
		reconnect_panel.mouse_filter = Control.MOUSE_FILTER_STOP

func _on_reconnect_button_pressed():
	NetworkManager.attempt_manual_reconnect()
	_on_reconnect_state_changed(NetworkManager.get_reconnect_state())

func _on_reconnect_save_replay_button_pressed():
	if not NetworkManager.is_waiting_for_opponent_reconnect():
		return
	if game and game.has_method("save_current_replay"):
		if not OS.has_feature("web"):
			reconnect_overlay.visible = false
			if game.has_signal("replay_save_finished"):
				game.replay_save_finished.connect(_on_waiting_replay_save_finished, CONNECT_ONE_SHOT)
		game.save_current_replay()

func _on_waiting_replay_save_finished():
	if NetworkManager.is_waiting_for_opponent_reconnect():
		_show_waiting_for_opponent_overlay(NetworkManager.get_reconnect_state()["waiting_for_opponent_reconnect_seconds"])

func _on_reconnect_cancel_button_pressed():
	var reconnect_state = NetworkManager.get_reconnect_state()
	if reconnect_state["is_waiting_for_opponent_reconnect"]:
		NetworkManager.quit_waiting_for_opponent()
		if game and game.has_method("abandon_match_after_disconnect"):
			game.abandon_match_after_disconnect()
		return
	NetworkManager.cancel_reconnect()
	_on_reconnect_state_changed(NetworkManager.get_reconnect_state())
