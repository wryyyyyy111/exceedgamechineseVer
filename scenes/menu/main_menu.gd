class_name MainMenu
extends Control

signal start_game(vs_info)
signal start_remote_game(vs_info, data)
signal reference_popout_visibility_changed(is_open)

## Hide community content entries, including when returning to the main hub.
@export var hide_customs_browser : bool = true:
	set(value):
		hide_customs_browser = value
		if is_node_ready():
			_update_customs_browser_visibility()

const RoomMaxLen = 12
const PlayerNameMaxLen = 12
const OffScreen = Vector2(-1000, -1000)

const MatchQueueItemScene = preload("res://scenes/menu/match_queue_item.tscn")
const CardPopoutScene = preload("res://scenes/game/card_popout.tscn")
const CardBaseScene = preload("res://scenes/card/card_base.tscn")
const CharSelectScenePath = "res://scenes/menu/char_select.tscn"
const TierlistImageUrl = "https://cdn.exceedcntyd.com/decks_official/tierlist/chinese2611v11simple.png"

const BackgroundManager = preload("res://globals/game_background_manager.gd")
const MatchAvailableAudioPath = "res://assets/sounds/match_available.mp3"
const MatchStartingAudioPath = "res://assets/sounds/match_notification.mp3"
const SpecialSelectAudioPath = "res://assets/sounds/surface.mp3"
const MainMenuBgmPath = "res://assets/sounds/mainmenu_bgm.mp3"
const QueueNotifyCooldownSeconds := 120
const QueueNotifyUrl := "https://exceedcntyd.com/bot/send_group_msg"
const QueueNotifyToken := "Bearer my_secret_token_mdl123"
const QueueNotifyGroupId := 1064964514

var _dialog_handler : Callable
var _pending_reconnect_match : Dictionary = {}
var _pending_replay_data : Dictionary = {}
var _custom_deck_definition = null
var _custom_buffer = null
const MainMenuUiOpacityExcludedTopLevelNodes := {
	"main_menu": true,
	"Background": true,
	"CharSelectBackdrop": true,
	"CardPopoutParent": true,
	"CardZone": true,
	"TierListDialog": true,
}
const ReplayDirectory := "user://replays/"
var image_loader : CardImageLoader
var reference_image_loader : CardImageLoader
const MobileWebReferenceCardYieldBatchSize : int = 1
const MobileWebMainMenuStartupYieldFrames : int = 2
var mobile_web_audio_unlocked : bool = false
var mobile_web_music_pending : bool = false
var reference_popout_generation : int = 0
var main_menu_resources_suspended_for_char_select : bool = false

#These only get set and used if run on web
var window
var file_load_callback

@onready var player_list : ItemList = $PlayerList
@onready var player_selected_character : String = "solbadguy"
@onready var opponent_selected_character : String = "kykisuke"
@onready var selecting_player : bool = true

@onready var player_name_box : LineEdit = $PlayerNameBox
@onready var background : TextureRect = $Background
@onready var char_select_backdrop : TextureRect = $CharSelectBackdrop

@onready var start_ai_button : Button = $AIBox/VSAIBox/StartButton
@onready var room_select : LineEdit = $MenuList/JoinBox/RoomNameBox
@onready var join_room_button = $MenuList/JoinBox/JoinButton
@onready var join_box = $MenuList/JoinBox
@onready var settings_button = $SettingsButton
@onready var settings_window = $PreferencesWindow
@onready var tier_list_dialog = $TierListDialog
@onready var file_dialog = $FileDialog
@onready var main_navigation : GridContainer = $MainNavigation
@onready var content_backdrop : Panel = $ContentBackdrop
@onready var content_page_title : Label = $ContentPageTitle
@onready var content_back_button : Button = $ContentBackButton
var _active_hub_page := "hub"
var _is_joining_lobby := false

var char_select : CharSelect = null
@onready var change_player_character_button : Button = $PlayerChooser/ChangePlayerCharacterButton
@onready var player_char_label : Label = $PlayerChooser/MarginContainer/VBoxContainer/HBoxContainer/CharName
@onready var player_char_portrait : TextureRect = $PlayerChooser/MarginContainer/VBoxContainer/HBoxContainer/CharPortrait
@onready var player_skin_panel : PanelContainer = $PlayerSkinPanel
@onready var player_skin_buttons : VBoxContainer = $PlayerSkinPanel/SkinButtons

@onready var opponent_char_label : Label = $AIBox/VSAIBox/OpponentChooser/MarginContainer/VBoxContainer/HBoxContainer/CharName
@onready var opponent_char_portrait : TextureRect = $AIBox/VSAIBox/OpponentChooser/MarginContainer/VBoxContainer/HBoxContainer/CharPortrait

@onready var player_chooser_wash : Polygon2D = $PlayerChooser/HoverWash
@onready var player_chooser_sweep : Polygon2D = $PlayerChooser/HoverSweep
@onready var player_chooser_accent : Line2D = $PlayerChooser/CornerAccent
@onready var opponent_chooser_wash : Polygon2D = $AIBox/VSAIBox/OpponentChooser/HoverWash
@onready var opponent_chooser_sweep : Polygon2D = $AIBox/VSAIBox/OpponentChooser/HoverSweep
@onready var opponent_chooser_accent : Line2D = $AIBox/VSAIBox/OpponentChooser/CornerAccent
var _chooser_fx_tweens : Dictionary = {}

@onready var modal_list : ModalList = $ModalList
@onready var modal_dialog : ModalDialog = $ModalDialog

@onready var player_list_button = $PlayerListContainer/PlayerListHBox/PlayersButton
@onready var match_list_button = $RoomListContainer/RoomListHBox/MatchesButton

@onready var cancel_button = $CancelButton
@onready var match_queues : HBoxContainer = $Queues
@onready var hp_rank_mode_label : Label = get_node_or_null("HpRankModeLabel") as Label
@onready var hp_rank_mode_quick_join_button : Button = get_node_or_null("HpRankModeQuickJoinButton") as Button
@onready var hp_rank_mode_status_label : Label = get_node_or_null("HpRankModeStatusLabel") as Label

@onready var card_popout_parent : Node2D = $CardPopoutParent
@onready var card_zone : Node2D = $CardZone
@onready var close_popout_button : Button = $ClosePopoutButton

@onready var label_font_normal = 24
@onready var label_font_small = 16
@onready var label_length_threshold = 15

# Start as true to not play sounds right when you get to the main menu.
@onready var was_match_available : bool = true
@onready var just_clicked_matchmake : bool = false

var player_selected_skin_index : int = 0
var _has_hp_rank_queue : bool = false
var _hp_rank_match_available : bool = false
static var _last_quick_queue_notify_unix_time : int = -999999

const HpRankQueueUnavailableHint := "服务器未开放 hp_rank_mode 队列"
const HpRankQueueAvailableHint := "服务器已开放，可直接进入队列"

func _char_skin_manager() -> Node:
	return get_node("/root/CharSkinManager")

# Called when the node enters the scene tree for the first time.
func _ready():
	image_loader = CardImageLoader.new()
	add_child(image_loader)
	_apply_main_menu_ui_opacity()
	_setup_main_hub_navigation()
	_show_main_hub()

	$VersionContainer/MarginContainer/HBoxContainer/ClientVersion.text = GlobalSettings.get_client_version()
	NetworkManager.connect("connected_to_server", _on_connected)
	NetworkManager.connect("disconnected_from_server", _on_disconnected)
	NetworkManager.connect("game_started", _on_remote_game_started)
	NetworkManager.connect("observe_started", _on_observe_game_started)
	NetworkManager.connect("players_update", _on_players_update)
	NetworkManager.connect("room_join_failed", _on_join_failed)
	NetworkManager.connect("request_failed", _on_network_request_failed)
	NetworkManager.connect("name_update", _on_name_update)
	NetworkManager.connect("session_restore_succeeded", _on_session_restore_succeeded)
	NetworkManager.connect("reconnect_state_changed", _on_reconnect_state_changed)
	_connect_reconnect_choice_dialog_signals()
	cancel_button.visible = false
	$ReconnectToServerButton.visible = false
	_on_players_update(NetworkManager.get_player_list(), NetworkManager.get_match_list(), NetworkManager.get_queue_list(), NetworkManager.any_available_match())
	await _yield_mobile_web_startup_frames("opponent character")
	selecting_player = false
	just_clicked_matchmake = false
	await update_char(opponent_selected_character, false)
	await _yield_mobile_web_startup_frames("menu dialogs")
	modal_dialog.visible = false
	modal_list.visible = false
	file_dialog.visible = false
	update_queues(true)
	_on_reconnect_state_changed(NetworkManager.get_reconnect_state())

	# Initialize settings window
	settings_window.visible = false
	settings_window.bgm_check_toggled.connect(_on_bgm_check_toggled)
	settings_window.main_menu_background_changed.connect(_apply_main_menu_background)
	_setup_chooser_hover_fx()
	if hp_rank_mode_quick_join_button:
		var hp_rank_pressed_callable = Callable(self, "_on_hp_rank_mode_quick_join_button_pressed")
		if not hp_rank_mode_quick_join_button.pressed.is_connected(hp_rank_pressed_callable):
			hp_rank_mode_quick_join_button.pressed.connect(hp_rank_pressed_callable)

	if OS.has_feature("web"):
		#setupFileLoad defined in the HTML5 export header
		#calls window_file_load_handler when file gets user-selected by window.input.click()
		window = JavaScriptBridge.get_interface("window")
		file_load_callback = JavaScriptBridge.create_callback(window_file_load_handler)
		window.setupFileLoad(file_load_callback)

func _apply_main_menu_ui_opacity() -> void:
	var opacity := GlobalSettings.MainMenuUiOpacity
	tier_list_dialog.set_background_opacity(opacity)
	for child in get_children():
		if child == null:
			continue
		if not child is CanvasItem:
			continue
		if MainMenuUiOpacityExcludedTopLevelNodes.has(child.name):
			continue
		var canvas_item := child as CanvasItem
		var modulate_color := canvas_item.modulate
		modulate_color.a = opacity
		canvas_item.modulate = modulate_color

func _setup_main_hub_navigation() -> void:
	$MainNavigation/LobbyEntry.pressed.connect(_show_lobby_page)
	$MainNavigation/AIEntry.pressed.connect(_show_ai_page)
	$MainNavigation/CommunityEntry.pressed.connect(_on_customs_browser_button_pressed)
	$MainNavigation/ReplayEntry.pressed.connect(_on_load_replay_button_pressed)
	$MainNavigation/TierEntry.pressed.connect(_on_tierlistbutton_pressed)
	$MainNavigation/SettingsEntry.pressed.connect(_show_settings_page)
	content_back_button.pressed.connect(_show_main_hub)
	_set_nodes_visible([
		^"PlayerGroupPanel", ^"BattleGroupPanel", ^"OnlineGroupPanel", ^"PlayerSectionLabel",
		^"BattleSectionLabel", ^"RoomSectionLabel", ^"QuickMatchSectionLabel", ^"OnlineSectionLabel",
		^"ToolsSectionLabel", ^"LoadReplayButton", ^"tierlistbutton", ^"SettingsButton"
	], false)

func _set_nodes_visible(node_paths : Array, visible_state : bool) -> void:
	for node_path in node_paths:
		var node := get_node_or_null(node_path) as CanvasItem
		if node:
			node.visible = visible_state

func _hide_hub_pages() -> void:
	_set_nodes_visible([
		^"PlayerChooser", ^"PlayerNameBox", ^"UpdateNameButton", ^"PlayerSkinPanel", ^"ViewCardsButton",
		^"RulesHintButton", ^"RulesHintOverlay",
		^"MenuList", ^"CancelButton", ^"Queues", ^"HpRankModeLabel", ^"HpRankModeQuickJoinButton", ^"HpRankModeStatusLabel", ^"PlayerListContainer", ^"RoomListContainer",
		^"PlayerListLabel", ^"PlayerList", ^"ReconnectToServerButton", ^"TextEdit2",
		^"CustomsBrowserButton", ^"AIBox", ^"TierListDialog", ^"PreferencesWindow"
	], false)

func _update_customs_browser_visibility() -> void:
	$CustomsBrowserButton.visible = not hide_customs_browser and _active_hub_page == "hub"
	var tool_buttons : Array[Button] = [$CustomsBrowserButton, $RulesHintButton, $LoadReplayButton, $tierlistbutton]
	var default_positions := [500.0, 480.0, 546.0, 592.0]
	for index in range(tool_buttons.size()):
		tool_buttons[index].position.y = default_positions[index] if hide_customs_browser else 480.0 + index * 42.0
		tool_buttons[index].size.y = 40.0 if hide_customs_browser else 36.0
	$MainNavigation/CommunityEntry.visible = not hide_customs_browser

func _show_main_hub() -> void:
	_active_hub_page = "hub"
	_hide_hub_pages()
	_set_nodes_visible([
		^"PlayerGroupPanel", ^"BattleGroupPanel", ^"OnlineGroupPanel",
		^"PlayerSectionLabel", ^"PlayerChooser",
		^"PlayerNameBox", ^"UpdateNameButton", ^"PlayerSkinPanel", ^"ViewCardsButton",
		^"RulesHintButton", ^"LoadReplayButton", ^"tierlistbutton", ^"SettingsButton",
		^"AIBox", ^"MenuList", ^"Queues", ^"HpRankModeLabel", ^"HpRankModeQuickJoinButton", ^"HpRankModeStatusLabel", ^"PlayerListContainer", ^"RoomListContainer",
		^"PlayerListLabel", ^"PlayerList", ^"ReconnectToServerButton", ^"TextEdit2"
	], true)
	_update_customs_browser_visibility()
	$PlayerChooser.position = Vector2(56, 138)
	main_navigation.visible = false
	content_backdrop.visible = false
	content_page_title.visible = false
	content_back_button.visible = false
	update_buttons(_is_joining_lobby)
	_refresh_player_skin_buttons()

func _show_content_page(title : String, node_paths : Array) -> void:
	_hide_hub_pages()
	main_navigation.visible = false
	content_backdrop.visible = true
	content_page_title.text = title
	content_page_title.visible = true
	content_back_button.visible = true
	_set_nodes_visible(node_paths, true)

func _show_lobby_page() -> void:
	_active_hub_page = "lobby"
	_show_content_page("对战大厅  //  ONLINE LOBBY", [
		^"PlayerChooser",
		^"MenuList", ^"CancelButton", ^"Queues", ^"HpRankModeLabel", ^"HpRankModeQuickJoinButton", ^"HpRankModeStatusLabel", ^"PlayerListContainer", ^"RoomListContainer",
		^"PlayerListLabel", ^"PlayerList", ^"ReconnectToServerButton", ^"TextEdit2"
	])
	$PlayerChooser.position = Vector2(824, 138)
	_refresh_player_skin_buttons()
	update_buttons(_is_joining_lobby)

func _show_ai_page() -> void:
	_active_hub_page = "ai"
	_show_content_page("人机对战  //  VS CPU", [^"PlayerChooser", ^"AIBox"])
	$PlayerChooser.position = Vector2(106, 150)
	_refresh_player_skin_buttons()

func _show_settings_page() -> void:
	_active_hub_page = "settings"
	_show_content_page("设置  //  SETTINGS", [^"PreferencesWindow"])

func _setup_chooser_hover_fx() -> void:
	var chooser_configs := [
		{"key":"player", "button":change_player_character_button, "portrait":player_char_portrait,
			"wash":player_chooser_wash, "sweep":player_chooser_sweep, "accent":player_chooser_accent},
		{"key":"opponent", "button":$AIBox/VSAIBox/OpponentChooser/ChangePlayerCharacterButton,
			"portrait":opponent_char_portrait, "wash":opponent_chooser_wash,
			"sweep":opponent_chooser_sweep, "accent":opponent_chooser_accent},
	]
	for config in chooser_configs:
		var portrait_node : TextureRect = config["portrait"]
		portrait_node.pivot_offset = portrait_node.size * 0.5
		config["wash"].modulate.a = 0.0
		config["sweep"].modulate.a = 0.0
		config["accent"].modulate.a = 0.0
		config["button"].mouse_entered.connect(func(): _animate_chooser_hover(config, true))
		config["button"].mouse_exited.connect(func(): _animate_chooser_hover(config, false))
		config["button"].button_down.connect(func(): _play_chooser_impact(config))

func _kill_chooser_tween(key : String) -> void:
	var old_tween : Tween = _chooser_fx_tweens.get(key)
	if old_tween != null and old_tween.is_valid():
		old_tween.kill()

func _animate_chooser_hover(config : Dictionary, active : bool) -> void:
	var key : String = config["key"]
	_kill_chooser_tween(key)
	var tween := create_tween().set_parallel(true)
	_chooser_fx_tweens[key] = tween
	tween.tween_property(config["portrait"], "scale", Vector2(1.055, 1.055) if active else Vector2.ONE, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(config["wash"], "modulate:a", 0.11 if active else 0.0, 0.1)
	tween.tween_property(config["accent"], "modulate:a", 1.0 if active else 0.0, 0.1)
	if active:
		_play_chooser_sweep(config)

func _play_chooser_sweep(config : Dictionary) -> void:
	var sweep_node : Polygon2D = config["sweep"]
	sweep_node.position.x = -90.0
	sweep_node.modulate.a = 0.0
	var move_tween := create_tween().set_parallel(true)
	move_tween.tween_property(sweep_node, "position:x", 300.0, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var fade_tween := create_tween()
	fade_tween.tween_property(sweep_node, "modulate:a", 0.78, 0.055)
	fade_tween.tween_property(sweep_node, "modulate:a", 0.0, 0.18)

func _play_chooser_impact(config : Dictionary) -> void:
	var portrait_node : TextureRect = config["portrait"]
	var impact := create_tween()
	impact.tween_property(portrait_node, "scale", Vector2(0.96, 0.96), 0.045)
	impact.tween_property(portrait_node, "scale", Vector2(1.09, 1.09), 0.075).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	impact.tween_property(portrait_node, "scale", Vector2(1.055, 1.055), 0.08)
	config["wash"].modulate.a = 0.3
	create_tween().tween_property(config["wash"], "modulate:a", 0.11, 0.16)
	_play_chooser_sweep(config)

func _connect_reconnect_choice_dialog_signals():
	var accept_callable = Callable(self, "_on_modal_dialog_accept_button_pressed")
	var secondary_callable = Callable(self, "_on_modal_dialog_secondary_button_pressed")
	var close_callable = Callable(self, "_on_modal_dialog_close_button_pressed")
	if not modal_dialog.accept_button_pressed.is_connected(accept_callable):
		modal_dialog.accept_button_pressed.connect(accept_callable)
	if not modal_dialog.secondary_button_pressed.is_connected(secondary_callable):
		modal_dialog.secondary_button_pressed.connect(secondary_callable)
	if not modal_dialog.close_button_pressed.is_connected(close_callable):
		modal_dialog.close_button_pressed.connect(close_callable)

func _is_saved_character_available(char_id : String) -> bool:
	if char_id == "random" or char_id.begins_with("random_s"):
		return true
	return CardDataManager.decks.has(char_id)

func settings_loaded():
	player_selected_character = GlobalSettings.PlayerCharacter if GlobalSettings.PlayerCharacter else "solbadguy"
	# Different project versions share the same user:// settings directory. A
	# newer build may have saved a character that this build does not contain.
	if not _is_saved_character_available(player_selected_character):
		push_warning("Saved character '%s' is unavailable; falling back to solbadguy." % player_selected_character)
		player_selected_character = "solbadguy"
		GlobalSettings.set_player_character(player_selected_character)
	await _yield_mobile_web_startup_frames("main menu background")
	await _apply_main_menu_background()
	await _yield_mobile_web_startup_frames("player character")
	await update_char(player_selected_character, true)
	await _yield_mobile_web_startup_frames("main menu music")
	start_music()

func _yield_mobile_web_startup_frames(stage_name : String):
	if not _is_mobile_web_runtime():
		return
	print("[MainMenuStartup] 等待移动端启动帧: ", stage_name)
	for _frame in range(MobileWebMainMenuStartupYieldFrames):
		await get_tree().process_frame

func _apply_main_menu_background():
	var texture := await BackgroundManager.load_main_menu_background_texture(GlobalSettings.MainMenuBackgroundStyle)
	if texture != null:
		background.texture = texture

func _suspend_main_menu_resources_for_char_select():
	if main_menu_resources_suspended_for_char_select:
		return
	main_menu_resources_suspended_for_char_select = true
	if background.texture == null:
		await _apply_main_menu_background()
	char_select_backdrop.texture = background.texture
	char_select_backdrop.visible = char_select_backdrop.texture != null
	background.texture = null
	player_char_portrait.texture = null
	opponent_char_portrait.texture = null
	if not $BGM.playing:
		$BGM.stream = null
	BackgroundManager.clear_main_menu_texture_cache()

func _restore_main_menu_resources_after_char_select():
	if not main_menu_resources_suspended_for_char_select:
		return
	await _apply_main_menu_background()
	await _yield_mobile_web_startup_frames("restore main menu character portraits")
	await update_char(player_selected_character, true)
	await update_char(opponent_selected_character, false)
	await get_tree().process_frame
	char_select_backdrop.visible = false
	char_select_backdrop.texture = null
	main_menu_resources_suspended_for_char_select = false

func _on_bgm_check_toggled():
	if GlobalSettings.BGMEnabled:
		start_music()
	else:
		stop_music()

func stop_music():
	mobile_web_music_pending = false
	$BGM.stop()

func _requires_web_audio_unlock() -> bool:
	return OS.has_feature("web")

func _input(event):
	if not _requires_web_audio_unlock() or mobile_web_audio_unlocked:
		return
	if event is InputEventScreenTouch and event.pressed:
		_unlock_mobile_web_audio()
	elif event is InputEventMouseButton and event.pressed:
		_unlock_mobile_web_audio()
	elif event is InputEventKey and event.pressed:
		_unlock_mobile_web_audio()

func _unlock_mobile_web_audio():
	mobile_web_audio_unlocked = true
	if mobile_web_music_pending or GlobalSettings.BGMEnabled:
		start_music()

func _play_menu_sound(audio_player : AudioStreamPlayer):
	if not GlobalSettings.GameSoundsEnabled:
		return
	if _requires_web_audio_unlock() and not mobile_web_audio_unlocked:
		return
	_ensure_menu_audio_stream(audio_player)
	audio_player.play()

func _ensure_menu_audio_stream(audio_player : AudioStreamPlayer):
	if audio_player.stream != null:
		return
	match audio_player.name:
		"MatchAvailableAudio":
			audio_player.stream = load(MatchAvailableAudioPath)
		"MatchStartingAudio":
			audio_player.stream = load(MatchStartingAudioPath)
		"SpecialSelectAudio":
			audio_player.stream = load(SpecialSelectAudioPath)
		"BGM":
			audio_player.stream = load(MainMenuBgmPath)

func start_music():
	if _requires_web_audio_unlock() and not mobile_web_audio_unlocked:
		mobile_web_music_pending = true
		$BGM.stop()
		return
	if GlobalSettings.BGMEnabled:
		mobile_web_music_pending = false
		_ensure_menu_audio_stream($BGM)
		$BGM.play()
	else:
		mobile_web_music_pending = false
		$BGM.stop()

func returned_from_game():
	_on_players_update(NetworkManager.get_player_list(), NetworkManager.get_match_list(), NetworkManager.get_queue_list(), NetworkManager.any_available_match())
	update_buttons(false)
	just_clicked_matchmake = false
	NetworkManager.set_lobby_state("Lobby")
	start_music()
	if OS.has_feature("web"):
		window.setupFileLoad(file_load_callback)
	# 进战斗前释放过主菜单背景，回到主菜单时补回来（背景是 CDN 纹理，不释放会一直占显存）。
	if background != null and background.texture == null:
		_apply_main_menu_background()

func release_reference_card_cache():
	_on_popout_close_window()

func release_match_start_background():
	# 进战斗前释放主菜单背景图，避免战斗全程白占显存；返回时由 returned_from_game 重新加载。
	if background != null and background.texture != null:
		background.texture = null
	BackgroundManager.clear_main_menu_texture_cache()

func _on_start_button_pressed():
	# For local play, random selection is still random at this point.
	var player_random_tag = ""
	if player_selected_character.begins_with("random"):
		player_random_tag = player_selected_character
	var opponent_random_tag = ""
	if opponent_selected_character.begins_with("random"):
		opponent_random_tag = opponent_selected_character

	var player_deck = _get_deck(player_selected_character, GlobalSettings.RandomHistory, true)
	GlobalSettings.append_random_history(player_deck['id'])
	var opponent_deck = _get_deck(opponent_selected_character)
	var player_name = get_player_name()
	var opponent_name = "CPU"
	NetworkManager.set_lobby_state("AI")
	start_game.emit(get_vs_info(player_name,
		player_deck,
		player_random_tag,
		opponent_name,
		opponent_deck,
		opponent_random_tag,
		GlobalSettings.RandomizeFirstVsAI))

func _on_connected(player_name):
	join_room_button.disabled = false
	player_list_button.disabled = false
	match_list_button.disabled = false
	player_name_box.editable = true
	$ReconnectToServerButton.visible = false
	if NetworkManager.is_reconnect_active():
		$ServerStatusLabel.text = "正在恢复连接"
		return
	player_name_box.text = player_name
	$ServerStatusLabel.text = "已连接服务器"
	if GlobalSettings.DefaultPlayerName:
		player_name_box.text = GlobalSettings.DefaultPlayerName
		NetworkManager.set_player_name(player_name_box.text)
	else:
		NetworkManager.set_player_name("")

func _on_disconnected():
	update_buttons(false)
	join_room_button.disabled = true
	update_queues(false)
	player_list_button.disabled = true
	match_list_button.disabled = true
	var reconnect_state = NetworkManager.get_reconnect_state()
	$ReconnectToServerButton.visible = reconnect_state["is_manual_reconnect"]
	$ReconnectToServerButton.disabled = false
	if reconnect_state["is_manual_reconnect"]:
		$ServerStatusLabel.text = "自动重新连接失败，请主动重新连接"
	elif reconnect_state["is_auto_reconnecting"]:
		$ServerStatusLabel.text = "正在尝试重新连接"
	else:
		$ServerStatusLabel.text = "已断开服务器连接"
	just_clicked_matchmake = false
	_on_players_update([], [], [], false)

func _on_reconnect_state_changed(state : Dictionary):
	if state["is_manual_reconnect"]:
		$ServerStatusLabel.text = "自动重新连接失败，请主动重新连接"
		$ReconnectToServerButton.visible = true
		$ReconnectToServerButton.disabled = NetworkManager.network_state == NetworkManager.NetworkState.NetworkState_Connecting
		return
	if state["is_auto_reconnecting"]:
		$ServerStatusLabel.text = "正在尝试重新连接"
		$ReconnectToServerButton.visible = false
		$ReconnectToServerButton.disabled = NetworkManager.network_state == NetworkManager.NetworkState.NetworkState_Connecting
		return
	if NetworkManager.is_server_connected():
		$ServerStatusLabel.text = "已连接服务器"
		$ReconnectToServerButton.visible = false
	else:
		$ReconnectToServerButton.visible = true
		$ReconnectToServerButton.disabled = false

func get_vs_info(player_name, player_deck, player_random_tag, opponent_name,
		opponent_deck, opponent_random_tag, randomize_first_vs_ai = false):
	return {
		'player_name': player_name,
		'player_deck': player_deck,
		'player_random_tag': player_random_tag,
		'opponent_name': opponent_name,
		'opponent_deck': opponent_deck,
		'opponent_random_tag': opponent_random_tag,
		'randomize_first_vs_ai': randomize_first_vs_ai
	}

func get_random_tag(deck_id):
	if deck_id.begins_with("random"):
		return deck_id.split("#")[0]
	return ""

func get_deck_id_without_random_tag(deck_id):
	if deck_id.begins_with("random"):
		return deck_id.split("#")[1]
	return deck_id

func _on_observe_game_started(data, is_replay = false, replay_player_number : int = 0):
	just_clicked_matchmake = false

	# Observe games pass in the full message log up to this point.
	# The first message is the game_start message.
	var message_log = data.get('messages')
	if not message_log:
		var json = JSON.new()
		var error = json.parse(data.get('MatchLog'))
		if error == OK:
			message_log = json.data
		else:
			assert(false, "Unexpected data")
			return
	var start_data = message_log[0].duplicate(true)

	var primary_player = "player2" if is_replay and replay_player_number == 2 else "player1"
	var other_player = "player1" if primary_player == "player2" else "player2"
	var player_deck = start_data[primary_player + '_deck_id']
	var player_name = start_data[primary_player + '_name']
	var opponent_deck = start_data[other_player + '_deck_id']
	var opponent_name = start_data[other_player + '_name']
	var player_deck_object = _get_deck_object(player_deck, start_data.get(primary_player + '_custom_deck'))
	var opponent_deck_object = _get_deck_object(opponent_deck, start_data.get(other_player + '_custom_deck'))
	if is_replay and replay_player_number == 0:
		_pending_reconnect_match = {}
		_pending_replay_data = {'messages': message_log.duplicate(true)}
		modal_dialog.set_choice_fields(
			"选择载入回放的主视角",
			"player1(%s)" % player_deck_object['display_name'],
			"player2(%s)" % opponent_deck_object['display_name'],
			"取消"
		)
		return

	# For remote play, random was decided locally first
	# and the deck id is random#deck_id.
	var player_random_tag = get_random_tag(player_deck)
	var opponent_random_tag = get_random_tag(opponent_deck)

	start_data['player1_deck_id'] = get_deck_id_without_random_tag(start_data['player1_deck_id'])
	start_data['player2_deck_id'] = get_deck_id_without_random_tag(start_data['player2_deck_id'])

	start_data['observer_mode'] = true
	start_data['replay_mode'] = is_replay
	start_data['observer_log'] = message_log.slice(1)
	start_data['your_player_id'] = start_data[primary_player + '_id']

	start_remote_game.emit(get_vs_info(player_name, player_deck_object,
		player_random_tag, opponent_name, opponent_deck_object, opponent_random_tag), start_data)

func _on_session_restore_succeeded(data):
	if not data.get("in_game", false):
		_restore_menu_state_after_session_restore(data)
		return
	var message_log = data.get("messages", [])
	if message_log.size() == 0:
		return
	var start_data = message_log[0].duplicate(true)
	if start_data.get("type", "") != "game_start":
		return
	start_data["your_player_id"] = data.get("player_id", data.get("restored_player_id", data.get("old_player_id", start_data.get("player1_id", 0))))
	start_data["restore_log"] = message_log.slice(1)
	_on_remote_game_started(start_data)

func _restore_menu_state_after_session_restore(data : Dictionary):
	var restore_context = data.get("context", NetworkManager.get_restore_context())
	var state_type = restore_context.get("state_type", NetworkManager.RestoreContextType.RestoreContextType_Lobby)
	var joining = state_type in [
		NetworkManager.RestoreContextType.RestoreContextType_Room,
		NetworkManager.RestoreContextType.RestoreContextType_Matchmaking,
		NetworkManager.RestoreContextType.RestoreContextType_Observe,
	]
	just_clicked_matchmake = false
	_on_players_update(NetworkManager.get_player_list(), NetworkManager.get_match_list(), NetworkManager.get_queue_list(), false)
	update_buttons(joining)

func _get_deck_object(deck, custom_deck):
	var deck_no_random = get_deck_id_without_random_tag(deck)
	if deck_no_random.begins_with("custom_"):
		return custom_deck
	else:
		return CardDataManager.get_deck_from_str_id(deck_no_random)

# Handles a signal from _handle_game_start in network manager
func _on_remote_game_started(data):
	just_clicked_matchmake = false
	_play_menu_sound($MatchStartingAudio)
	var player1_is_me = true
	var player_deck = data['player1_deck_id']
	var player_name = data['player1_name']
	var player_custom_deck = data.get('player1_custom_deck')
	var opponent_deck = data['player2_deck_id']
	var opponent_name = data['player2_name']
	var opponent_custom_deck = data.get('player2_custom_deck')
	if data['your_player_id'] != data['player1_id']:
		player1_is_me = false
		player_deck = data['player2_deck_id']
		player_name = data['player2_name']
		player_custom_deck = data.get('player2_custom_deck')
		opponent_deck = data['player1_deck_id']
		opponent_name = data['player1_name']
		opponent_custom_deck = data.get('player1_custom_deck')

	# For remote play, random was decided locally first
	# and the deck id is random#deck_id.
	var player_random_tag = get_random_tag(player_deck)
	var player_deck_no_random = get_deck_id_without_random_tag(player_deck)
	var opponent_random_tag = get_random_tag(opponent_deck)
	var opponent_deck_no_random = get_deck_id_without_random_tag(opponent_deck)

	if player_random_tag:
		GlobalSettings.append_random_history(player_deck_no_random)

	if player1_is_me:
		data['player1_deck_id'] = player_deck_no_random
		data['player2_deck_id'] = opponent_deck_no_random
	else:
		data['player1_deck_id'] = opponent_deck_no_random
		data['player2_deck_id'] = player_deck_no_random

	var player_deck_object = _get_deck_object(player_deck_no_random, player_custom_deck)
	var opponent_deck_object = _get_deck_object(opponent_deck_no_random, opponent_custom_deck)
	start_remote_game.emit(get_vs_info(player_name, player_deck_object,
		player_random_tag, opponent_name, opponent_deck_object, opponent_random_tag), data)

func _on_name_update(new_name):
	player_name_box.text = new_name
	if not NetworkManager.is_reconnect_active():
		GlobalSettings.set_player_name(new_name)

func _update_hp_rank_mode_entry_state() -> void:
	if hp_rank_mode_quick_join_button:
		hp_rank_mode_quick_join_button.text = "立即开始" if _hp_rank_match_available else "进入\n队列"
		hp_rank_mode_quick_join_button.add_theme_color_override("font_color", Color(1, 0.72, 0.72, 1) if _hp_rank_match_available else Color.YELLOW)
		hp_rank_mode_quick_join_button.disabled = _is_joining_lobby or not _has_hp_rank_queue
		hp_rank_mode_quick_join_button.tooltip_text = HpRankQueueUnavailableHint if not _has_hp_rank_queue else ""
	if hp_rank_mode_status_label:
		hp_rank_mode_status_label.text = HpRankQueueAvailableHint if _has_hp_rank_queue else HpRankQueueUnavailableHint

func _on_players_update(players, matches, queues : Array, newly_available_match : bool):
	player_list.clear()
	for player in players:
		player_list.add_item(player['player_name'] + " - " + player['room_name'])

	var player_count = players.size()
	var match_count = matches.size()
	$PlayerListContainer/PlayerListHBox/PlayerCount.text = str(player_count)
	$RoomListContainer/RoomListHBox/MatchCount.text = str(match_count)

	var visible_queues : Array = []
	for queue_info in queues:
		if str(queue_info.get("id", "")) == "hp_rank_mode":
			continue
		visible_queues.append(queue_info)

	var queue_items = match_queues.get_children()
	if queue_items.size() != visible_queues.size():
		while match_queues.get_child_count() > 0:
			var queue_item = match_queues.get_child(0)
			match_queues.remove_child(queue_item)
			queue_item.queue_free()
		for queue_info in visible_queues:
			var new_queue = MatchQueueItemScene.instantiate()
			match_queues.add_child(new_queue)
			new_queue.initialize_queue(
				queue_info["id"],
				queue_info["name"],
				queue_info["match_available"],
				MatchQueueItem.get_waiting_character_display(queue_info)
			)
			new_queue.on_join_queue.connect(_on_queue_join_clicked)

	for i in range(visible_queues.size()):
		var queue_info = visible_queues[i]
		var queue : MatchQueueItem = match_queues.get_child(i)
		queue.initialize_queue(
			queue_info["id"],
			queue_info["name"],
			queue_info["match_available"],
			MatchQueueItem.get_waiting_character_display(queue_info)
		)
		queue.set_match_available(queue_info["match_available"])

	_has_hp_rank_queue = false
	_hp_rank_match_available = false
	for queue_info in queues:
		if str(queue_info.get("id", "")) == "hp_rank_mode":
			_has_hp_rank_queue = true
			_hp_rank_match_available = bool(queue_info.get("match_available", false))
			break
	_update_hp_rank_mode_entry_state()
	if visible and newly_available_match and not just_clicked_matchmake:
		_play_menu_sound($MatchAvailableAudio)

func _on_join_failed(error_message : String, invalid_deck : bool):
	if invalid_deck and _check_banned():
		return

	modal_dialog.set_text_fields(error_message, "OK", "")
	update_buttons(false)

func _on_network_request_failed(error_message : String):
	$ServerStatusLabel.text = error_message
	if not NetworkManager.is_reconnect_active():
		modal_dialog.set_text_fields(error_message, "OK", "")
	update_buttons(false)
	just_clicked_matchmake = false

func get_player_name() -> String:
	return player_name_box.text

func _on_join_button_pressed():
	_join_named_room(room_select.text)

func _join_named_room(room_name : String):
	var player_name = get_player_name()
	var chosen_deck = _get_deck(player_selected_character, GlobalSettings.RandomHistory, true)
	var chosen_deck_id = chosen_deck['id']
	if player_selected_character.begins_with("random"):
		chosen_deck_id = player_selected_character + "#" + chosen_deck_id
	if NetworkManager.join_room(player_name,
		room_name,
		chosen_deck_id,
		GlobalSettings.CustomStartingTimer,
		GlobalSettings.CustomEnforceTimer,
		GlobalSettings.CustomMinimumTimePerChoice,
		_custom_deck_definition
	):
		update_buttons(true)

func _join_reconnect_room(match_info : Dictionary, reconnect_seat : int = -1):
	var player_name = get_player_name()
	var room_name = match_info["name"]
	var chosen_deck = _get_deck(player_selected_character, GlobalSettings.RandomHistory, true)
	var chosen_deck_id = chosen_deck['id']
	if player_selected_character.begins_with("random"):
		chosen_deck_id = player_selected_character + "#" + chosen_deck_id
	if NetworkManager.join_reconnect_room(player_name,
		room_name,
		chosen_deck_id,
		GlobalSettings.CustomStartingTimer,
		GlobalSettings.CustomEnforceTimer,
		GlobalSettings.CustomMinimumTimePerChoice,
		_custom_deck_definition,
		reconnect_seat
	):
		update_buttons(true)

func update_buttons(joining : bool):
	_is_joining_lobby = joining
	start_ai_button.disabled = joining
	change_player_character_button.disabled = joining
	room_select.editable = not joining
	join_box.visible = not joining
	cancel_button.visible = joining and _active_hub_page in ["lobby", "hub"]
	player_list_button.disabled = joining
	match_list_button.disabled = joining
	_update_player_skin_buttons_disabled(joining)
	_update_hp_rank_mode_entry_state()
	update_queues(not joining)

func _on_hp_rank_mode_quick_join_button_pressed() -> void:
	_on_queue_join_clicked("hp_rank_mode", _hp_rank_match_available, "血量平衡模式")

func _can_send_quick_queue_notification() -> bool:
	var now_unix = int(Time.get_unix_time_from_system())
	if now_unix - _last_quick_queue_notify_unix_time < QueueNotifyCooldownSeconds:
		return false
	_last_quick_queue_notify_unix_time = now_unix
	return true

func _send_quick_queue_notification(queue_display_name : String) -> void:
	if not _can_send_quick_queue_notification():
		return
	var t = Time.get_time_dict_from_system()
	var time_str = "%02d:%02d" % [t["hour"], t["minute"]]
	var msg = "-----------有人正在队列%s等待 %s-----------\n-----------有人正在队列%s等待 %s-----------\n-----------有人正在队列%s等待 %s-----------" % [queue_display_name, time_str, queue_display_name, time_str, queue_display_name, time_str]
	var body = JSON.stringify({"group_id": QueueNotifyGroupId, "message": msg})
	var headers := PackedStringArray()
	headers.append("Content-Type: application/json")
	headers.append("Authorization: %s" % QueueNotifyToken)
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_result, response_code, _headers, body_bytes):
		if response_code != 200:
			push_warning("QQ通知发送失败，HTTP状态码: %d，返回: %s" % [response_code, body_bytes.get_string_from_utf8()])
		http.queue_free()
	)
	var err = http.request(QueueNotifyUrl, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		push_error("发送QQ通知请求失败，错误码: %d" % err)
		http.queue_free()

func update_queues(enabled : bool):
	for child in match_queues.get_children():
		var queue_item : MatchQueueItem = child
		queue_item.set_enabled(enabled)

func _on_queue_join_clicked(queue_id, match_available : bool = false, queue_display_name : String = ""):
	if not match_available:
		_send_quick_queue_notification(queue_display_name if queue_display_name != "" else str(queue_id))
	just_clicked_matchmake = true
	var player_name = get_player_name()

	var chosen_deck = _get_deck(player_selected_character, GlobalSettings.RandomHistory, true)
	var chosen_deck_id = chosen_deck['id']
	if player_selected_character.begins_with("random"):
		chosen_deck_id = player_selected_character + "#" + chosen_deck_id
	if NetworkManager.join_matchmaking(
		player_name,
		chosen_deck_id,
		queue_id,
		_custom_deck_definition
	):
		update_buttons(true)
	else:
		just_clicked_matchmake = false

func _on_cancel_button_pressed():
	NetworkManager.leave_room()
	update_buttons(false)
	just_clicked_matchmake = false

func _on_update_name_button_pressed():
	var player_name = get_player_name()
	NetworkManager.set_player_name(player_name)
	GlobalSettings.set_player_name(player_name)

func _on_reconnect_to_server_button_pressed():
	$ServerStatusLabel.text = "Reconnecting to server..."
	NetworkManager.attempt_manual_reconnect()
	$ReconnectToServerButton.disabled = true

func _on_char_select_close_character_select():
	if char_select:
		char_select.visible = false
	await _restore_main_menu_resources_after_char_select()
	match _active_hub_page:
		"lobby":
			_show_lobby_page()
		"ai":
			_show_ai_page()
		_:
			_show_main_hub()

func _ensure_char_select() -> CharSelect:
	if char_select:
		return char_select

	var char_select_scene = load(CharSelectScenePath)
	char_select = char_select_scene.instantiate()
	char_select.visible = false
	char_select.z_index = 120
	add_child(char_select)
	char_select.close_character_select.connect(_on_char_select_close_character_select)
	char_select.select_character.connect(_on_char_select_select_character)
	return char_select

func update_char(char_id: String, is_player: bool) -> void:
	var label = player_char_label if is_player else opponent_char_label
	var portrait = player_char_portrait if is_player else opponent_char_portrait
	var display_name = "Random"
	if is_player:
		if player_selected_character != char_id:
			player_selected_skin_index = 0
		player_selected_character = char_id
		GlobalSettings.set_player_character(char_id)
	else:
		opponent_selected_character = char_id
	var portrait_id: String
	if char_id == "random_s8":
		portrait_id = "stlogo"
	elif char_id == "random_s7":
		portrait_id = "random"
	elif char_id == "random_s6":
		portrait_id = "unilogo"
	elif char_id == "random_s5":
		portrait_id = "blazbluelogo2"
	elif char_id == "random_s4":
		portrait_id = "sklogo"
	elif char_id == "random_s3":
		portrait_id = "sflogo"
	elif char_id == "random_s2":
		portrait_id = "sclogo"
	elif char_id == "random_s1":
		portrait_id = "redhorizon"
	elif char_id == "random":
		portrait_id = "exceedrandom"
	else:
		var deck
		if char_id.begins_with("custom_"):
			deck = _custom_deck_definition
		else:
			deck = CardDataManager.get_deck_from_str_id(char_id)
		if deck:
			display_name = deck['display_name']
			portrait_id = char_id
		else:
			portrait_id = "exceedrandom"
			if is_player:
				player_selected_character = "random"
				GlobalSettings.set_player_character("random")
			else:
				opponent_selected_character = "random"
	label.text = display_name
	if char_id.begins_with("custom_"):
		if char_id in ImageCache.loaded_portraits:
			portrait.texture = ImageCache.loaded_portraits[char_id]
		else:
			var set_texture = false;
			if 'portrait_image_url' in _custom_deck_definition:
				var portrait_texture = await image_loader.get_animation_images(_custom_deck_definition['portrait_image_url'],
					0, 0, -1, -1, 1, 1)
				if portrait_texture:
					set_texture = true
					ImageCache.loaded_portraits[char_id] = portrait_texture[0]
					portrait.texture = portrait_texture[0]
			if !set_texture:
				portrait.texture = load("res://assets/portraits/custom.png")
	else:
		portrait.texture = _char_skin_manager().load_portrait_texture_for_deck_id(portrait_id)

	if len(display_name) <= label_length_threshold:
		label.set("theme_override_font_sizes/font_size", label_font_normal)
	else:
		label.set("theme_override_font_sizes/font_size", label_font_small)

	if is_player:
		_refresh_player_skin_buttons()
		_update_player_skin_portrait()

func _refresh_player_skin_buttons() -> void:
	var show_skin_buttons = not player_selected_character.begins_with("random") and not player_selected_character.begins_with("custom_")
	player_skin_panel.visible = show_skin_buttons and _active_hub_page == "hub"
	for child in player_skin_buttons.get_children():
		child.queue_free()

	if not show_skin_buttons:
		return

	var skin_manager = _char_skin_manager()
	var skin_count = skin_manager.get_skin_count(player_selected_character)
	if player_selected_skin_index > skin_count:
		player_selected_skin_index = 0

	for skin_index in range(skin_manager.get_total_button_count(player_selected_character)):
		var button := Button.new()
		button.custom_minimum_size = Vector2(160, 28)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.focus_mode = Control.FOCUS_NONE
		button.disabled = _is_joining_lobby
		button.text = skin_manager.get_button_label(player_selected_character, skin_index)
		_apply_skin_button_style(button, skin_index == player_selected_skin_index)
		button.pressed.connect(_on_player_skin_button_pressed.bind(skin_index))
		player_skin_buttons.add_child(button)

func _on_player_skin_button_pressed(skin_index: int) -> void:
	player_selected_skin_index = skin_index
	_sync_player_skin_button_pressed_states()
	_update_player_skin_portrait()

func _sync_player_skin_button_pressed_states() -> void:
	for index in range(player_skin_buttons.get_child_count()):
		var child = player_skin_buttons.get_child(index)
		if child is Button:
			_apply_skin_button_style(child as Button, index == player_selected_skin_index)

func _update_player_skin_buttons_disabled(disabled : bool) -> void:
	for child in player_skin_buttons.get_children():
		if child is Button:
			(child as Button).disabled = disabled

func _update_player_skin_portrait() -> void:
	if player_selected_character == "random_s8":
		player_char_portrait.texture = load("res://assets/portraits/stlogo.png")
	elif player_selected_character == "random_s7":
		player_char_portrait.texture = load("res://assets/portraits/random.png")
	elif player_selected_character == "random_s6":
		player_char_portrait.texture = load("res://assets/portraits/unilogo.png")
	elif player_selected_character == "random_s5":
		player_char_portrait.texture = load("res://assets/portraits/blazbluelogo2.png")
	elif player_selected_character == "random_s4":
		player_char_portrait.texture = load("res://assets/portraits/sklogo.png")
	elif player_selected_character == "random_s3":
		player_char_portrait.texture = load("res://assets/portraits/sflogo.png")
	elif player_selected_character == "random_s2":
		player_char_portrait.texture = load("res://assets/portraits/sclogo.png")
	elif player_selected_character == "random_s1":
		player_char_portrait.texture = load("res://assets/portraits/redhorizon.png")
	elif player_selected_character == "random":
		player_char_portrait.texture = load("res://assets/portraits/exceedrandom.png")
	else:
		var skin_deck_id = _char_skin_manager().get_skin_deck_id(player_selected_character, player_selected_skin_index)
		player_char_portrait.texture = _char_skin_manager().load_portrait_texture_for_deck_id(skin_deck_id)

func _apply_skin_button_style(button: Button, selected: bool = false) -> void:
	var normal_color := Color("#f38181") if selected else Color("fff44f")
	var hover_color := Color("#f79696") if selected else Color("fff875")
	button.add_theme_color_override("font_color", Color("1b1b00"))
	button.add_theme_color_override("font_hover_color", Color("1b1b00"))
	button.add_theme_color_override("font_pressed_color", Color("1b1b00"))
	button.add_theme_stylebox_override("normal", _make_skin_button_style(normal_color))
	button.add_theme_stylebox_override("hover", _make_skin_button_style(hover_color))
	button.add_theme_stylebox_override("pressed", _make_skin_button_style(Color("#f38181")))

func _make_skin_button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style

func _get_effective_player_character_id(char_id: String) -> String:
	return _char_skin_manager().get_skin_deck_id(char_id, player_selected_skin_index)

func _on_char_select_select_character(char_id):
	if char_id == "custom":
		# Show UI to select a file from disk.
		_show_file_dialog(load_custom, true, "")
	else:
		update_char(char_id, selecting_player)
	_on_char_select_close_character_select()

func _on_change_player_character_button_pressed(is_player : bool):
	var char_id = player_selected_character
	if not is_player:
		char_id = opponent_selected_character
	await _suspend_main_menu_resources_for_char_select()
	var selector = _ensure_char_select()
	selector.show_char_select(char_id, player_selected_skin_index if is_player else 0)
	# The selector is translucent by design. Hide the underlying chooser page
	# while it is open so the old "选择斗士" frame cannot show through it.
	_hide_hub_pages()
	content_backdrop.visible = false
	content_page_title.visible = false
	content_back_button.visible = false
	selector.visible = true
	selecting_player = is_player

func cropLineToMaxLength_room_line_edit(new_text : String, max_length: int) -> void:
	if new_text.length() > max_length:
		var col = room_select.caret_column
		if col != 0:
			new_text = new_text.substr(0, col-1) + new_text.substr(col)
		else:
			new_text = new_text.substr(1)
		new_text = new_text.substr(0, max_length)
		room_select.text = new_text
		room_select.caret_column = col - 1

func cropLineToMaxLength_name_line_edit(new_text : String, max_length: int) -> void:
	if new_text.length() > max_length:
		var col = player_name_box.caret_column
		if col != 0:
			new_text = new_text.substr(0, col-1) + new_text.substr(col)
		else:
			new_text = new_text.substr(1)
		new_text = new_text.substr(0, max_length)
		player_name_box.text = new_text
		player_name_box.caret_column = col - 1

func _on_room_name_box_text_changed(new_text):
	cropLineToMaxLength_room_line_edit(new_text, RoomMaxLen)

func _on_player_name_box_focus_entered():
	player_name_box.select_all()

func _on_player_name_box_text_changed(new_text : String):
	cropLineToMaxLength_name_line_edit(new_text, PlayerNameMaxLen)

func _on_players_button_pressed():
	modal_list.show_player_list()

func _on_matches_button_pressed():
	modal_list.show_match_list()

func _check_banned():
	var chosen_deck = _get_deck(player_selected_character, [], true)
	var chosen_deck_id = chosen_deck['id']
	if chosen_deck_id in GlobalSettings.CharacterBanlist:
		if not $SpecialSelectAudio.playing:
			_play_menu_sound($SpecialSelectAudio)
		modal_dialog.set_text_fields(
			"\"Weaklings should stay away...\"\n(This character is banned\nfrom standard matchmaking.)",
			"OK", "")
		update_buttons(false)

		return true
	return false

func _on_modal_list_join_match_pressed(row_index):
	_pending_replay_data = {}
	var matches = NetworkManager.get_match_list()
	var selected_match = matches[row_index]
	room_select.text = selected_match['name']
	if selected_match.get("reconnect_joinable", false):
		var reconnectable_seats = selected_match.get("reconnectable_seats", [])
		if reconnectable_seats.size() > 1:
			_pending_reconnect_match = selected_match
			modal_dialog.set_choice_fields(
				"选择要接管的玩家席位",
				_get_reconnect_seat_button_text(selected_match, 0),
				_get_reconnect_seat_button_text(selected_match, 1),
				"取消"
			)
		elif reconnectable_seats.size() == 1:
			_join_reconnect_room(selected_match, reconnectable_seats[0])
		else:
			_join_reconnect_room(selected_match)
	else:
		_join_named_room(selected_match['name'])

func _on_modal_dialog_accept_button_pressed():
	if not _pending_replay_data.is_empty():
		_start_pending_replay(1)
	else:
		_join_pending_reconnect_seat(0)

func _on_modal_dialog_secondary_button_pressed():
	if not _pending_replay_data.is_empty():
		_start_pending_replay(2)
	else:
		_join_pending_reconnect_seat(1)

func _on_modal_dialog_close_button_pressed():
	_pending_reconnect_match = {}
	_pending_replay_data = {}

func _start_pending_replay(player_number : int):
	var replay_data = _pending_replay_data
	_pending_replay_data = {}
	_on_observe_game_started(replay_data, true, player_number)

func _get_reconnect_seat_button_text(match_info : Dictionary, seat_index : int) -> String:
	var character_name = "未知角色"
	var seat_decks = match_info.get("seat_decks", [])
	if seat_index < seat_decks.size():
		var deck_id = str(seat_decks[seat_index])
		var split_index = deck_id.find("#")
		if split_index != -1:
			deck_id = deck_id.substr(split_index + 1)
		if CardDataManager.decks.has(deck_id):
			character_name = CardDataManager.get_deck(deck_id).get("display_name", deck_id)
		elif not deck_id.is_empty():
			character_name = deck_id
	return "玩家%d(%s)" % [seat_index + 1, character_name]

func _join_pending_reconnect_seat(reconnect_seat : int):
	if _pending_reconnect_match.is_empty():
		return
	var selected_match = _pending_reconnect_match
	_pending_reconnect_match = {}
	_join_reconnect_room(selected_match, reconnect_seat)

func _on_modal_list_observe_match_pressed(row_index):
	var matches = NetworkManager.get_match_list()
	var selected_match = matches[row_index]
	var room_name = selected_match['name']
	var player_name = get_player_name()
	NetworkManager.observe_room(player_name, room_name)
	update_buttons(true)

func _on_load_replay_button_pressed():
	if _is_android_runtime():
		_show_android_replay_file_dialog()
	else:
		_show_file_dialog(load_replay, true)

func _show_android_replay_file_dialog():
	if not DirAccess.dir_exists_absolute(ReplayDirectory):
		modal_dialog.set_text_fields("没有可载入的回放文件。", "OK", "")
		return
	_dialog_handler = load_replay
	file_dialog.file_mode = FileDialog.FileMode.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_USERDATA
	file_dialog.root_subfolder = "replays"
	file_dialog.filters = PackedStringArray(["*.txt ; Replay Files"])
	file_dialog.visible = true

func _is_android_runtime() -> bool:
	return OS.has_feature("android") or OS.get_name() == "Android"

func _show_file_dialog(dialog_hander : Callable, loading_file : bool, file_name : String = ""):
	_dialog_handler = dialog_hander
	if OS.has_feature("web"):
		window.input.click()
	else:
		# Default dialog access for desktop-like file operations.
		file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		file_dialog.root_subfolder = ""
		file_dialog.filters = PackedStringArray()
		if loading_file:
			file_dialog.file_mode = FileDialog.FileMode.FILE_MODE_OPEN_FILE
		else:
			file_dialog.file_mode = FileDialog.FileMode.FILE_MODE_SAVE_FILE
		if file_name:
			file_dialog.current_file = file_name
		file_dialog.visible = true

func _on_settings_button_pressed():
	settings_window.visible = true

func window_file_load_handler(data):
	_dialog_handler.call(data)

func load_replay(data):
	_pending_replay_data = {}
	_pending_reconnect_match = {}
	var json = JSON.new()
	if json.parse(data[0]) == OK:
		var replay_data = json.data
		var replay_version = 1
		if 'replay_version' in replay_data:
			replay_version = replay_data['replay_version']

		if replay_version == GlobalSettings.ReplayVersion:
			_on_observe_game_started(replay_data, true)
		else:
			var error_message = "Client replay version does not match replay version"
			modal_dialog.set_text_fields(error_message, "OK", "")
			update_buttons(false)
	else:
		var error_message = "JSON Parse Error: " + json.get_error_message()
		modal_dialog.set_text_fields(error_message, "OK", "")
		update_buttons(false)

func _on_file_dialog_file_selected(path):
	if file_dialog.file_mode == FileDialog.FileMode.FILE_MODE_SAVE_FILE:
		_dialog_handler.call(path)
	else:
		_dialog_handler.call([FileAccess.get_file_as_string(path)])

func load_custom(data):
	var json = JSON.new()
	if json.parse(data[0]) == OK:
		_custom_deck_definition = CardDataManager.convert_floats_to_ints(json.data)
		var deck_id = "custom_" + _custom_deck_definition["id"]
		_custom_deck_definition["id"] = deck_id
		update_char(deck_id, selecting_player)
	else:
		var error_message = "JSON Parse Error: " + json.get_error_message()
		modal_dialog.set_text_fields(error_message, "OK", "")
		update_buttons(false)

func _get_deck(char_id, exclude_ids = [], use_player_skin: bool = false):
	if char_id.begins_with("custom_"):
		return _custom_deck_definition
	else:
		var resolved_char_id = char_id
		if use_player_skin:
			resolved_char_id = _get_effective_player_character_id(char_id)
		var deck = CardDataManager.get_deck_from_str_id(resolved_char_id, exclude_ids).duplicate(true)
		if use_player_skin:
			deck["asset_deck_id"] = resolved_char_id
		return deck


func _on_view_cards_button_pressed() -> void:
	if player_selected_character.begins_with("random"):
		var error_message = "Cannot view Random"
		modal_dialog.set_text_fields(error_message, "OK", "")
	else:
		var deck = _get_deck(player_selected_character, [], true)
		_show_popout_for_deck(deck, true, 1.3) #!展示卡牌时 卡牌放大XX倍的开关

func _show_popout_for_deck(deck, only_close_with_popout_button: bool = false, preview_card_scale_multiplier: float = 1.0):
	reference_popout_generation += 1
	var popout_generation = reference_popout_generation
	# only_close_with_popout_button=true 时：仅允许弹窗内部“关闭视窗”按钮关闭
	# 其它入口保持原行为（允许点击主界面遮罩关闭）
	close_popout_button.visible = not only_close_with_popout_button
	CardDataManager.load_deck_if_custom(deck)
	_release_reference_image_loader()
	_clear_reference_card_zone()
	reference_image_loader = CardImageLoader.new()
	reference_image_loader.set_meta("resource_budget_priority", "preview")
	add_child(reference_image_loader)
	var card_popout = CardPopoutScene.instantiate()
	card_popout.set_fill_viewport(true) #可配置指定弹窗的全屏尺寸
	card_popout.set_preview_card_scale(preview_card_scale_multiplier)
	card_popout.set_preview_label_color(Color("#0bcd12"))  #!展示卡牌时 弹窗里的 Label颜色
	card_popout.set_close_on_outside_click(not only_close_with_popout_button)
	card_popout.set_enable_card_label_count_click_update(true)
	card_popout.set_amount("已加载 0")
	card_popout.set_title("加载卡牌中...")
	card_popout.set_instructions(null)
	card_popout.set_reference_toggle("", false)
	card_popout_parent.add_child(card_popout)
	reference_popout_visibility_changed.emit(true)
	card_popout.close_window.connect(_on_popout_close_window)
	var cards = await spawn_deck(deck, popout_generation, card_popout)
	if _is_reference_popout_generation_current(popout_generation) and is_instance_valid(card_popout) and card_popout.get_parent() != null:
		card_popout.set_title("(点击卡牌记录数量)(点击空地缩小卡牌)(离线不关闭)")
		if _is_mobile_web_runtime() and card_popout.has_method("show_cards_chunked"):
			await card_popout.show_cards_chunked(cards, -1, MobileWebReferenceCardYieldBatchSize)
		else:
			card_popout.show_cards(cards)

func _is_mobile_web_runtime() -> bool:
	return OS.has_feature("web") and (
		OS.has_feature("mobile")
		or OS.has_feature("web_android")
		or OS.has_feature("web_ios")
	)

func _is_reference_popout_generation_current(popout_generation : int) -> bool:
	return popout_generation == -1 or popout_generation == reference_popout_generation

func _yield_mobile_reference_card_batch(processed_count : int):
	if _is_mobile_web_runtime() and processed_count > 0 and processed_count % MobileWebReferenceCardYieldBatchSize == 0:
		await get_tree().process_frame

func _show_texture_popout(title: String, texture: Texture2D, only_close_with_popout_button: bool = false):
	if is_reference_popout_open():
		_on_popout_close_window()
	close_popout_button.visible = not only_close_with_popout_button
	var card_popout = CardPopoutScene.instantiate()
	card_popout.set_fill_viewport(true)
	card_popout.set_close_on_outside_click(not only_close_with_popout_button)
	card_popout_parent.add_child(card_popout)
	reference_popout_visibility_changed.emit(true)
	card_popout.close_window.connect(_on_popout_close_window)
	card_popout.set_amount("")
	card_popout.set_title(title)
	card_popout.set_instructions(null)
	card_popout.set_reference_toggle("", false)
	card_popout.show_texture(texture)

func _show_image_popout(title: String, image: Image, only_close_with_popout_button: bool = false):
	if is_reference_popout_open():
		_on_popout_close_window()
	close_popout_button.visible = not only_close_with_popout_button
	var card_popout = CardPopoutScene.instantiate()
	card_popout.set_fill_viewport(true)
	card_popout.set_close_on_outside_click(not only_close_with_popout_button)
	card_popout_parent.add_child(card_popout)
	reference_popout_visibility_changed.emit(true)
	card_popout.close_window.connect(_on_popout_close_window)
	card_popout.set_amount("")
	card_popout.set_title(title)
	card_popout.set_instructions(null)
	card_popout.set_reference_toggle("", false)
	card_popout.show_image(image)

func is_reference_popout_open() -> bool:
	return card_popout_parent.get_child_count() > 0

func spawn_deck(
	deck_def,
	popout_generation : int = -1,
	loading_progress_popout = null
):
	var preview_loader := reference_image_loader if reference_image_loader else image_loader
	var image_resources = deck_def['image_resources']
	var deck_season = deck_def.get('season', 0)
	var deck_id_str = deck_def.get('asset_deck_id', deck_def.get('id', ''))
	for _res_key in image_resources:
		if not 'season' in image_resources[_res_key]:
			image_resources[_res_key]['season'] = deck_season
		if deck_def.get('asset_deck_id', '') != '':
			image_resources[_res_key]['asset_deck_id'] = deck_id_str
			image_resources[_res_key]['deck_id'] = deck_id_str
		elif not 'deck_id' in image_resources[_res_key]:
			image_resources[_res_key]['deck_id'] = deck_id_str
	var cards = []
	var deck_list = []
	var fully_registered_atlas_urls := {}
	var reference_atlases := []
	for deck_card_def in deck_def['cards']:
		if deck_card_def.get('hide_from_reference', false):
			continue
		var card_def = CardDataManager.get_card(deck_card_def['definition_id'])
		var image_atlas = image_resources[deck_card_def['image_name']].duplicate(true)
		image_atlas['image_name'] = deck_card_def['image_name']
		if deck_card_def['image_name'] == 'normals':
			image_atlas['force_cropped_textures'] = true
		var image_index = deck_card_def['image_index']
		var card = GameCard.new(-1, card_def, -1, image_atlas, image_index)
		if image_atlas.get('multiple_cards', false) and not fully_registered_atlas_urls.has(image_atlas['url']):
			# Register the complete atlas before any per-card await. On mobile Web,
			# later index registrations can arrive after the HTTP response is processed.
			preview_loader.load_image_page(image_atlas)
			fully_registered_atlas_urls[image_atlas['url']] = true
			reference_atlases.append(image_atlas)
		preview_loader.load_image_page_indexed(card.image_atlas, card.image_index)
		deck_list.append(card)

	if _is_mobile_web_runtime():
		for image_atlas in reference_atlases:
			if not await preview_loader.ensure_image_page(image_atlas):
				return cards

	var buddy_graphics = _get_reference_buddy_graphics(deck_def)
	var loading_total = 2 + _count_unique_reference_buddy_graphics(buddy_graphics) + _count_reference_deck_cards(deck_list)
	_update_reference_loading_progress(loading_progress_popout, cards.size(), loading_total, popout_generation)

	var normal_character_card = await create_character_reference_card(false, card_zone, image_resources, deck_def)
	if normal_character_card == null or not _is_reference_popout_generation_current(popout_generation):
		return cards
	cards.append(normal_character_card)
	_update_reference_loading_progress(loading_progress_popout, cards.size(), loading_total, popout_generation)
	await _yield_mobile_reference_card_batch(cards.size())
	var exceed_character_card = await create_character_reference_card(true, card_zone, image_resources, deck_def)
	if exceed_character_card == null or not _is_reference_popout_generation_current(popout_generation):
		return cards
	cards.append(exceed_character_card)
	_update_reference_loading_progress(loading_progress_popout, cards.size(), loading_total, popout_generation)
	await _yield_mobile_reference_card_batch(cards.size())

	# Setup buddy if they have one.
	var created_buddy_cards = []
	for buddy_id in buddy_graphics:
		if buddy_id in created_buddy_cards:
			# Skip any that share graphics.
			continue
		created_buddy_cards.append(buddy_id)
		var buddy_card_id = CardBase.BuddyCardReferenceId
		var new_card = await create_buddy_reference_card(buddy_id, false, card_zone, buddy_card_id, image_resources)
		if new_card == null or not _is_reference_popout_generation_current(popout_generation):
			return cards
		cards.append(new_card)
		_update_reference_loading_progress(loading_progress_popout, cards.size(), loading_total, popout_generation)
		await _yield_mobile_reference_card_batch(cards.size())

	# 统计每种卡牌定义在牌组中的数量，用于剩余计数
	var def_counts = {}
	for _deck_card in deck_list:
		var _def_id = _deck_card.definition['id']
		def_counts[_def_id] = def_counts.get(_def_id, 0) + 1

	var previous_def_id = ""
	var card_num = 1
	for card in deck_list:
		if previous_def_id != card.definition['id']:
			print("[ReferencePopout] 卡牌映射: %s -> image_name=%s, image_index=%s, url=%s" % [
				str(card.definition['id']),
				str(card.image_atlas.get('image_name', '')),
				str(card.image_index),
				str(card.image_atlas.get('url', '')),
			])
			var copy_card = await create_card(
				card_num,
				card.get_image_url_index_data(),
				card_zone,
				card.definition['display_name'],
				card.definition['boost']['display_name'],
				card.definition
			)
			if copy_card == null or not _is_reference_popout_generation_current(popout_generation):
				return cards
			card_num += 1
			copy_card.set_card_and_focus(OffScreen, 0, CardBase.ReferenceCardScale)
			copy_card.resting_scale = CardBase.ReferenceCardScale
			copy_card.change_state(CardBase.CardState.CardState_Offscreen)
			copy_card.flip_card_to_front(true)
			previous_def_id = card.definition['id']
			# 仅对多卡图集来源的卡牌设置初始剩余数量（card_popout 展示时会复制并处理点击逻辑）
			if card.image_atlas.get('multiple_cards', false):
				var initial_count : int = def_counts[card.definition['id']]
				copy_card.set_remaining_count(initial_count)
			cards.append(copy_card)
			_update_reference_loading_progress(loading_progress_popout, cards.size(), loading_total, popout_generation)
			await _yield_mobile_reference_card_batch(cards.size())
	return cards

func _get_reference_buddy_graphics(deck_def) -> Array:
	var buddy_graphics = []
	if deck_def.get('hide_buddy_reference'):
		return buddy_graphics
	if 'buddy_card' in deck_def:
		buddy_graphics.append(deck_def['buddy_card'])
		# 主页面参考卡中，单 buddy 角色即使有 buddy_exceeds 也只展示 1 张 buddy。
		# 这样不会影响对局逻辑，只调整主菜单弹窗展示数量。
	elif 'buddy_card_graphic_override' in deck_def:
		for buddy_card in deck_def['buddy_card_graphic_override']:
			buddy_graphics.append(buddy_card)
	elif 'buddy_cards' in deck_def:
		for buddy_card in deck_def['buddy_cards']:
			buddy_graphics.append(buddy_card)
			if 'buddy_exceeds' in deck_def and deck_def['buddy_exceeds']:
				buddy_graphics.append(buddy_card + "_exceeded")
	return buddy_graphics


func _count_unique_reference_buddy_graphics(buddy_graphics : Array) -> int:
	var created_buddy_cards = []
	for buddy_id in buddy_graphics:
		if buddy_id in created_buddy_cards:
			continue
		created_buddy_cards.append(buddy_id)
	return created_buddy_cards.size()

func _count_reference_deck_cards(deck_list : Array) -> int:
	var previous_def_id = ""
	var count = 0
	for card in deck_list:
		if previous_def_id != card.definition['id']:
			count += 1
			previous_def_id = card.definition['id']
	return count

func _update_reference_loading_progress(card_popout, loaded_count : int, total_count : int, popout_generation : int):
	if card_popout == null:
		return
	if not _is_reference_popout_generation_current(popout_generation):
		return
	if not is_instance_valid(card_popout) or card_popout.get_parent() == null:
		return
	card_popout.set_amount("已加载 %d/%d" % [loaded_count, total_count])

func get_card_node_name(id):
	return "Card_" + str(id)

func create_card(id, image_url_index, parent, card_name, boost_name, card_def: Dictionary = {}) -> CardBase:
	var new_card : CardBase = CardBaseScene.instantiate()
	parent.add_child(new_card)

	var url_loaded_image = null
	if image_url_index:
		var preview_loader := reference_image_loader if reference_image_loader else image_loader
		url_loaded_image = await preview_loader.get_card_image(image_url_index["url"], image_url_index["index"], image_url_index)
		if not is_instance_valid(new_card) or new_card.is_queued_for_deletion() or new_card.get_parent() != parent:
			return null

	new_card.initialize_card(
		id,
		url_loaded_image,
		null,
		false,
		card_name,
		boost_name,
		card_def
	)

	new_card.name = get_card_node_name(id)
	return new_card


func create_character_reference_card(exceeded : bool, zone, image_resources, deck_def = {}):
	var image_url = image_resources['character_default']['url']
	if exceeded:
		image_url = image_resources['character_exceeded']['url']
	var definition := _character_fallback_definition(deck_def, exceeded)
	var card_name := str(deck_def.get("display_name", "角色"))
	if exceeded:
		card_name += "（觉醒）"
	return await _create_reference_card(image_url, card_name, zone, CardBase.CharacterCardReferenceId, definition)

func create_buddy_reference_card(buddy_id, exceeded : bool, zone, click_buddy_id, image_resources):
	var image_url = image_resources[buddy_id]['url']
	if exceeded:
		image_url = image_resources[buddy_id + '_exceeded']['url']
	return await _create_reference_card(image_url, "Extra Card", zone, click_buddy_id)

func _create_reference_card(
	image_url : String,
	card_name : String,
	zone,
	card_id : int,
	definition = {}
):
	var new_card : CardBase = CardBaseScene.instantiate()
	zone.add_child(new_card)

	var preview_loader := reference_image_loader if reference_image_loader else image_loader
	var url_loaded_image = await preview_loader.get_card_image(image_url, 0)
	if not is_instance_valid(new_card) or new_card.is_queued_for_deletion() or new_card.get_parent() != zone:
		return null

	new_card.initialize_card(
		card_id,
		url_loaded_image,
		"",
		false,
		card_name,
		"",
		definition
	)
	new_card.name = card_name

	new_card.set_card_and_focus(OffScreen, 0, CardBase.ReferenceCardScale)
	new_card.resting_scale = CardBase.ReferenceCardScale
	new_card.change_state(CardBase.CardState.CardState_Offscreen)
	new_card.flip_card_to_front(true)
	return new_card

func _character_fallback_definition(deck_def: Dictionary, exceeded: bool) -> Dictionary:
	var definition := {
		"reference_label": "觉醒角色" if exceeded else "角色",
		"exceed_cost": deck_def.get("exceed_cost", 0),
		"effects": [],
	}
	if exceeded:
		if deck_def.has("on_exceed"):
			definition["effects"].append(deck_def["on_exceed"])
		definition["effects"].append_array(deck_def.get("exceed_ability_effects", []))
	else:
		definition["effects"].append_array(deck_def.get("ability_effects", []))
	return definition

func _on_popout_close_window() -> void:
	reference_popout_generation += 1
	while card_popout_parent.get_child_count() > 0:
		var child = card_popout_parent.get_child(0)
		card_popout_parent.remove_child(child)
		child.queue_free()
	close_popout_button.visible = false
	_release_reference_image_loader()
	_clear_reference_card_zone()
	reference_popout_visibility_changed.emit(false)

func _release_reference_image_loader():
	if reference_image_loader == null:
		return
	reference_image_loader.teardown()
	remove_child(reference_image_loader)
	reference_image_loader.queue_free()
	reference_image_loader = null

func _clear_reference_card_zone():
	while card_zone.get_child_count() > 0:
		var card = card_zone.get_child(0)
		card_zone.remove_child(card)
		card.queue_free()

func _on_close_popout_button_pressed() -> void:
	_on_popout_close_window()

func _on_customs_browser_button_pressed() -> void:
	modal_list.show_customs_list()

func _on_modal_list_view_custom_pressed(row_index: int) -> void:
	var customs = NetworkManager.get_customs_dict()
	var keys = customs.keys()
	var custom_chosen = customs[keys[row_index]]
	_show_popout_for_deck(custom_chosen)

func save_custom(path):
	var file_access = FileAccess.open(path, FileAccess.WRITE)
	file_access.store_buffer(_custom_buffer)
	file_access.close()

func _on_modal_list_download_custom_pressed(row_index: int) -> void:
	var customs = NetworkManager.get_customs_dict()
	var keys = customs.keys()
	var custom_chosen = customs[keys[row_index]]

	var filename = custom_chosen["id"] + ".json"
	var custom_as_str = JSON.stringify(custom_chosen, "\t", false)
	_custom_buffer = custom_as_str.to_utf8_buffer()
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(_custom_buffer, filename, "text/plain")
	else:
		_show_file_dialog(save_custom, false, filename)


func _on_tierlistbutton_pressed():
	var loaded_texture = await image_loader.get_card_image(TierlistImageUrl, 0)
	var tierlist_image = ImageCache.load_image(TierlistImageUrl)
	if tierlist_image == null or tierlist_image.is_empty():
		if loaded_texture != null:
			tierlist_image = loaded_texture.get_image()
	if tierlist_image == null or tierlist_image.is_empty():
		modal_dialog.set_text_fields("Tier List 图片加载失败。", "OK", "")
		return
	tier_list_dialog.show_tier_list(tierlist_image)
