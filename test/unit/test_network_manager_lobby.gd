extends GutTest

class MockSocket:
	var ready_state := WebSocketPeer.STATE_OPEN
	var sent_messages : Array = []

	func get_ready_state():
		return ready_state

	func poll():
		return OK

	func get_available_packet_count():
		return 0

	func send_text(payload : String):
		sent_messages.append(payload)
		return OK


func before_each():
	_reset_network_manager_state()
	NetworkManager._clear_lobby_cache(false)


func after_each():
	_reset_network_manager_state()
	NetworkManager._clear_lobby_cache(false)


func _reset_network_manager_state():
	NetworkManager.network_state = NetworkManager.NetworkState.NetworkState_NotConnected
	NetworkManager._socket = null
	NetworkManager._is_expected_disconnect = false
	NetworkManager._reconnect_elapsed = 0.0
	NetworkManager._next_auto_reconnect_in = NetworkManager.AUTO_RECONNECT_INTERVAL_SECONDS
	NetworkManager._reset_server_keepalive_tracking()
	NetworkManager._web_page_hidden = false
	NetworkManager.reconnect_state["is_auto_reconnecting"] = false
	NetworkManager.reconnect_state["auto_retry_enabled"] = false
	NetworkManager.reconnect_state["reconnect_seconds"] = 0
	NetworkManager.reconnect_state["last_reconnect_attempt_time"] = -1.0
	NetworkManager.reconnect_state["is_manual_reconnect"] = false
	NetworkManager.reconnect_state["user_cancelled"] = false
	NetworkManager.reconnect_state["disconnect_reason"] = ""
	NetworkManager.reconnect_state["is_waiting_for_opponent_reconnect"] = false
	NetworkManager.reconnect_state["waiting_for_opponent_reconnect_seconds"] = 0
	NetworkManager._waiting_for_opponent_reconnect_elapsed = 0.0
	NetworkManager._pending_disconnect_confirmation_player_id = null
	NetworkManager._waiting_for_disconnect_confirmation = false
	NetworkManager._active_remote_match_finished = false


func test_players_update_replaces_cached_lobby_snapshot():
	NetworkManager._handle_players_update({
		"players": [{
			"player_id": 1,
			"player_version": "dev_test",
			"player_name": "Host",
			"room_name": "room_a",
			"player_deck": "ryu",
		}],
		"rooms": [{
			"room_name": "room_a",
			"room_version": "dev_test",
			"player_count": 1,
			"observer_count": 0,
			"game_started": false,
			"player_names": ["Host", ""],
			"player_decks": ["ryu", ""],
			"player_custom_deck_portraits": [null, null],
		}],
		"queues": [{
			"id": "casual",
			"name": "Casual",
			"match_available": true,
			"waiting_character": "隆德雷奇亚",
			"waiting_deck_id": "londrekia",
		}],
	})

	assert_eq(NetworkManager.get_player_list().size(), 1)
	assert_eq(NetworkManager.get_match_list().size(), 1)
	assert_true(NetworkManager.get_queue_list()[0]["match_available"])
	assert_eq(NetworkManager.get_queue_list()[0]["waiting_character"], "隆德雷奇亚")
	assert_eq(NetworkManager.get_queue_list()[0]["waiting_deck_id"], "londrekia")

	NetworkManager._handle_players_update({
		"players": [],
		"rooms": [],
		"queues": [{
			"id": "casual",
			"name": "Casual",
			"match_available": false,
		}],
	})

	assert_eq(NetworkManager.get_player_list().size(), 0)
	assert_eq(NetworkManager.get_match_list().size(), 0)
	assert_eq(NetworkManager.get_queue_list().size(), 1)
	assert_false(NetworkManager.get_queue_list()[0]["match_available"])

func test_page_lifecycle_pauses_keepalive_only_while_hidden():
	var network_manager_script = preload("res://globals/network_manager.gd")
	assert_true(network_manager_script.should_pause_server_keepalive(true, NetworkManager.NetworkState.NetworkState_Connected))
	assert_true(network_manager_script.should_pause_server_keepalive(false, NetworkManager.NetworkState.NetworkState_NotConnected))
	assert_false(network_manager_script.should_pause_server_keepalive(false, NetworkManager.NetworkState.NetworkState_Connected))

func test_hidden_web_page_pauses_reconnect_timer_progress():
	NetworkManager.reconnect_state["is_auto_reconnecting"] = true
	NetworkManager.reconnect_state["auto_retry_enabled"] = false
	NetworkManager._web_page_hidden = true
	NetworkManager._update_reconnect_timers(5.0)
	assert_eq(NetworkManager._reconnect_elapsed, 0.0)
	assert_eq(NetworkManager.reconnect_state["reconnect_seconds"], 0)


func test_players_update_preserves_all_waiting_queue_fields():
	NetworkManager._handle_players_update({
		"players": [],
		"rooms": [],
		"queues": [{
			"id": "ranked",
			"name": "Ranked",
			"match_available": true,
			"waiting_character": "隆",
			"waiting_deck": "Ryu",
			"waiting_deck_id": "random_s3#ryu",
		}],
	})

	var queue_info = NetworkManager.get_queue_list()[0]
	assert_eq(queue_info["waiting_character"], "隆")
	assert_eq(queue_info["waiting_deck"], "Ryu")
	assert_eq(queue_info["waiting_deck_id"], "random_s3#ryu")


func test_players_update_keeps_hp_rank_waiting_match_room_visible():
	NetworkManager._handle_players_update({
		"players": [{
			"player_id": 1,
			"player_version": "dev_test",
			"player_name": "Host",
			"room_name": "Match_1",
			"player_deck": "ryu",
		}],
		"rooms": [{
			"room_name": "Match_1",
			"room_version": "dev_test",
			"player_count": 1,
			"connected_player_count": 1,
			"observer_count": 0,
			"game_started": false,
			"joinable": true,
			"player_names": ["Host", ""],
			"player_decks": ["ryu", ""],
			"player_custom_deck_portraits": [null, null],
		}],
		"queues": [{
			"id": "hp_rank_mode",
			"name": "血量平衡模式",
			"match_available": true,
			"waiting_deck_id": "ryu",
		}],
	})

	var matches = NetworkManager.get_match_list()
	assert_eq(matches.size(), 1)
	assert_eq(matches[0]["name"], "Match_1")
	assert_eq(matches[0]["host"], "Host")
	assert_true(matches[0]["joinable"])
	assert_false(matches[0]["observable"])
	assert_eq(NetworkManager.get_queue_list()[0]["id"], "hp_rank_mode")
	assert_true(NetworkManager.get_queue_list()[0]["match_available"])


func test_players_update_filters_invalid_rooms_and_ignores_custom_portraits():
	NetworkManager._handle_players_update({
		"players": [],
		"rooms": [{
			"room_name": "empty_room",
			"room_version": "dev_test",
			"player_count": 0,
			"observer_count": 0,
			"game_started": false,
			"player_names": ["", ""],
			"player_decks": ["", ""],
			"player_custom_deck_portraits": [null, null],
		}, {
			"room_name": "no_host_room",
			"room_version": "dev_test",
			"player_count": 1,
			"observer_count": 0,
			"game_started": false,
			"player_names": ["", "Guest"],
			"player_decks": ["", "kykisuke"],
			"player_custom_deck_portraits": [null, null],
		}, {
			"room_name": "half_started_room",
			"room_version": "dev_test",
			"player_count": 1,
			"observer_count": 1,
			"game_started": true,
			"player_names": ["Host", ""],
			"player_decks": ["ryu", ""],
			"player_custom_deck_portraits": [null, null],
		}, {
			"room_name": "valid_started_room",
			"room_version": "dev_test",
			"player_count": 2,
			"observer_count": 1,
			"game_started": true,
			"player_names": ["Host", "Guest"],
			"player_decks": ["", ""],
			"player_custom_deck_portraits": ["ignored_host_portrait", "ignored_guest_portrait"],
		}],
		"queues": [],
	})

	var matches = NetworkManager.get_match_list()
	assert_eq(matches.size(), 1)
	assert_eq(matches[0]["name"], "valid_started_room")
	assert_false(matches[0]["joinable"])
	assert_true(matches[0]["observable"])


func test_players_update_keeps_started_room_with_disconnected_joinable_seat():
	NetworkManager._handle_players_update({
		"players": [],
		"rooms": [{
			"room_name": "reconnect_room",
			"room_version": "dev_test",
			"player_count": 1,
			"connected_player_count": 1,
			"observer_count": 0,
			"game_started": true,
			"joinable": true,
			"reconnect_joinable": true,
			"player_names": ["Host", "Disconnected"],
			"player_decks": ["ryu", "solbadguy"],
			"player_custom_deck_portraits": [null, null],
		}],
		"queues": [],
	})

	var matches = NetworkManager.get_match_list()
	assert_eq(matches.size(), 1)
	assert_eq(matches[0]["name"], "reconnect_room")
	assert_true(matches[0]["joinable"])
	assert_true(matches[0]["reconnect_joinable"])
	assert_true(matches[0]["observable"])


func test_players_update_keeps_game_over_room_observable_only():
	NetworkManager._handle_players_update({
		"players": [],
		"rooms": [{
			"room_name": "finished_room",
			"room_version": "dev_test",
			"player_count": 1,
			"connected_player_count": 1,
			"observer_count": 0,
			"game_started": true,
			"game_over": true,
			"joinable": false,
			"reconnect_joinable": false,
			"player_names": ["Winner", ""],
			"player_decks": ["ryu", "solbadguy"],
			"player_custom_deck_portraits": [null, null],
		}],
		"queues": [],
	})

	var matches = NetworkManager.get_match_list()
	assert_eq(matches.size(), 1)
	assert_eq(matches[0]["name"], "finished_room")
	assert_false(matches[0]["joinable"])
	assert_false(matches[0]["reconnect_joinable"])
	assert_true(matches[0]["observable"])
	assert_true(matches[0]["game_over"])


func test_players_update_keeps_observer_only_room_with_two_empty_reconnect_seats():
	NetworkManager._handle_players_update({
		"players": [],
		"rooms": [{
			"room_name": "observer_kept_room",
			"room_version": "dev_test",
			"player_count": 0,
			"connected_player_count": 0,
			"observer_count": 1,
			"game_started": true,
			"game_over": false,
			"joinable": true,
			"reconnect_joinable": true,
			"reconnectable_seats": [0, 1],
			"player_names": ["", ""],
			"player_decks": ["", ""],
			"seat_decks": ["ryu", "solbadguy"],
			"player_custom_deck_portraits": [null, null],
		}],
		"queues": [],
	})

	var matches = NetworkManager.get_match_list()
	assert_eq(matches.size(), 1)
	assert_eq(matches[0]["host"], "<EMPTY>")
	assert_eq(matches[0]["opponent"], "<EMPTY>")
	assert_eq(matches[0]["reconnectable_seats"], [0, 1])
	assert_eq(matches[0]["seat_decks"], ["ryu", "solbadguy"])
	assert_true(matches[0]["reconnect_joinable"])


func test_server_keepalive_message_updates_keepalive_tracking():
	NetworkManager._handle_server_response(JSON.stringify({
		"type": "server_keepalive",
	}))

	assert_true(NetworkManager._server_keepalive_tracking)
	assert_gt(NetworkManager._last_server_keepalive_time, 0.0)


func test_server_keepalive_timeout_starts_reconnect_flow():
	NetworkManager.network_state = NetworkManager.NetworkState.NetworkState_Connected
	NetworkManager._server_keepalive_tracking = true
	NetworkManager._last_server_keepalive_time = Time.get_ticks_msec() / 1000.0 - NetworkManager.SERVER_KEEPALIVE_TIMEOUT_SECONDS - 1.0

	NetworkManager._update_server_keepalive_timeout()

	var state = NetworkManager.get_reconnect_state()
	assert_true(state["is_auto_reconnecting"])
	assert_true(state["auto_retry_enabled"])
	assert_eq(state["reconnect_seconds"], 1)
	assert_false(NetworkManager._server_keepalive_tracking)


func test_player_reconnect_does_not_clear_waiting_before_disconnect_confirmation_finishes():
	NetworkManager._waiting_for_disconnect_confirmation = true
	NetworkManager._pending_disconnect_confirmation_player_id = 42
	NetworkManager.begin_waiting_for_opponent_reconnect()

	NetworkManager._handle_player_reconnect({
		"type": "player_reconnect",
		"player_id": 42,
		"player_name": "Reconnecter",
	})

	assert_true(NetworkManager.get_reconnect_state()["is_waiting_for_opponent_reconnect"])


func test_disconnect_confirmation_required_tracks_pending_player():
	NetworkManager._handle_disconnect_confirmation_required({
		"type": "disconnect_confirmation_required",
		"player_id": 77,
	})

	assert_eq(NetworkManager._pending_disconnect_confirmation_player_id, 77)
	assert_true(NetworkManager._waiting_for_disconnect_confirmation)


func test_request_players_update_sends_explicit_refresh_message():
	var socket = MockSocket.new()
	NetworkManager._socket = socket

	assert_true(NetworkManager.request_players_update())
	assert_eq(socket.sent_messages.size(), 1)
	var parser = JSON.new()
	assert_eq(parser.parse(socket.sent_messages[0]), OK)
	assert_eq(parser.data.get("type", ""), "request_players_update")


func test_room_waiting_for_opponent_preserves_matchmaking_context_and_refreshes_lobby():
	var socket = MockSocket.new()
	NetworkManager._socket = socket
	NetworkManager.set_restore_context(NetworkManager.RestoreContextType.RestoreContextType_Matchmaking, {
		"player_name": "Host",
		"lobby_state": "Matchmaking",
		"deck_id": "ryu",
		"queue_id": "hp_rank_mode",
	})

	NetworkManager._handle_room_waiting_for_opponent({
		"type": "room_waiting_for_opponent",
	})

	var context = NetworkManager.get_restore_context()
	assert_eq(context.get("state_type"), NetworkManager.RestoreContextType.RestoreContextType_Matchmaking)
	assert_eq(context.get("queue_id", ""), "hp_rank_mode")
	assert_eq(socket.sent_messages.size(), 1)
	var parser = JSON.new()
	assert_eq(parser.parse(socket.sent_messages[0]), OK)
	assert_eq(parser.data.get("type", ""), "request_players_update")


func test_request_matchlog_upload_sends_explicit_marker_message():
	var socket = MockSocket.new()
	NetworkManager._socket = socket

	assert_true(NetworkManager.request_matchlog_upload())
	assert_eq(socket.sent_messages.size(), 1)
	var parser = JSON.new()
	assert_eq(parser.parse(socket.sent_messages[0]), OK)
	assert_eq(parser.data.get("type", ""), "request_matchlog_upload")


func test_matchlog_upload_result_emits_server_outcome():
	var outcomes := []
	var capture_outcome = func(success, uploaded, error_message):
		outcomes.append([success, uploaded, error_message])
	NetworkManager.matchlog_upload_finished.connect(capture_outcome)

	NetworkManager._handle_server_response(JSON.stringify({
		"type": "matchlog_upload_result",
		"success": false,
		"uploaded": false,
		"error": "OSS unavailable",
	}))

	assert_eq(outcomes, [[false, false, "OSS unavailable"]])
	NetworkManager.matchlog_upload_finished.disconnect(capture_outcome)


func test_join_reconnect_room_sends_selected_seat():
	var socket = MockSocket.new()
	NetworkManager._socket = socket

	assert_true(NetworkManager.join_reconnect_room(
		"Rejoiner", "observer_kept_room", "ryu", 900, false, 30, null, 1
	))
	assert_eq(socket.sent_messages.size(), 1)
	var parser = JSON.new()
	assert_eq(parser.parse(socket.sent_messages[0]), OK)
	assert_true(parser.data.get("reconnect_join", false))
	assert_eq(int(parser.data.get("reconnect_seat", -1)), 1)


func test_join_custom_room_sends_hp_rank_mode_setting_for_creator():
	var socket = MockSocket.new()
	NetworkManager._socket = socket
	var saved_enabled = GlobalSettings.CustomHpRankModeEnabled
	GlobalSettings.CustomHpRankModeEnabled = true

	assert_true(NetworkManager.join_room("Host", "hp_rank_room", "ryu", 900, false, 20, null))

	GlobalSettings.CustomHpRankModeEnabled = saved_enabled
	assert_eq(socket.sent_messages.size(), 1)
	var parser = JSON.new()
	assert_eq(parser.parse(socket.sent_messages[0]), OK)
	assert_eq(parser.data.get("type", ""), "join_room")
	assert_true(parser.data.get("hp_rank_mode_enabled", false))


func test_main_menu_reconnect_choice_dialog_signals_are_connected():
	var main_menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	add_child_autofree(main_menu)
	await get_tree().process_frame
	var dialog : ModalDialog = main_menu.get_node("ModalDialog")

	assert_true(dialog.accept_button_pressed.is_connected(
		Callable(main_menu, "_on_modal_dialog_accept_button_pressed")
	))
	assert_true(dialog.secondary_button_pressed.is_connected(
		Callable(main_menu, "_on_modal_dialog_secondary_button_pressed")
	))
	assert_true(dialog.close_button_pressed.is_connected(
		Callable(main_menu, "_on_modal_dialog_close_button_pressed")
	))

func test_main_menu_hub_hides_navigation_before_async_initialization():
	var main_menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	add_child_autofree(main_menu)

	assert_false((main_menu.get_node("MainNavigation") as CanvasItem).visible)
	assert_true((main_menu.get_node("AIBox") as CanvasItem).visible)

func test_main_menu_customs_browser_is_hidden_by_default():
	var main_menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	add_child_autofree(main_menu)

	assert_true(main_menu.hide_customs_browser)
	assert_false(main_menu.get_node("CustomsBrowserButton").visible)
	assert_false(main_menu.get_node("MainNavigation/CommunityEntry").visible)
	main_menu._show_lobby_page()
	main_menu._show_main_hub()
	assert_false(main_menu.get_node("CustomsBrowserButton").visible)

func test_main_menu_customs_browser_can_be_shown_and_hidden():
	var main_menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	main_menu.hide_customs_browser = false
	add_child_autofree(main_menu)

	assert_true(main_menu.get_node("CustomsBrowserButton").visible)
	assert_true(main_menu.get_node("MainNavigation/CommunityEntry").visible)
	main_menu._show_lobby_page()
	assert_false(main_menu.get_node("CustomsBrowserButton").visible)
	main_menu.hide_customs_browser = true
	main_menu.hide_customs_browser = false
	assert_false(main_menu.get_node("CustomsBrowserButton").visible)
	main_menu._show_main_hub()
	assert_true(main_menu.get_node("CustomsBrowserButton").visible)
	main_menu.hide_customs_browser = true
	assert_false(main_menu.get_node("CustomsBrowserButton").visible)
	assert_false(main_menu.get_node("MainNavigation/CommunityEntry").visible)

func test_main_menu_reference_popout_initializes_before_card_loading():
	var main_menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	add_child_autofree(main_menu)
	await get_tree().process_frame

	main_menu._show_popout_for_deck(CardDataManager.get_deck_from_str_id("ryu"), true, 1.3)
	await get_tree().process_frame

	var popout : CardPopout = main_menu.card_popout_parent.get_child(0)
	assert_eq(popout.title_label.text, "加载卡牌中...")
	assert_true(popout.title_amount.text.begins_with("已加载 0"))
	assert_false(popout.instruction_box.visible)


func test_reconnect_choice_buttons_send_selected_seat():
	var socket = MockSocket.new()
	NetworkManager._socket = socket
	var main_menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	add_child_autofree(main_menu)
	await get_tree().process_frame
	var dialog : ModalDialog = main_menu.get_node("ModalDialog")
	var match_info = {
		"name": "observer_kept_room",
		"reconnectable_seats": [0, 1],
		"seat_decks": ["ryu", "solbadguy"],
	}

	main_menu._pending_reconnect_match = match_info
	dialog.accept_button.pressed.emit()
	assert_eq(socket.sent_messages.size(), 1)
	var parser = JSON.new()
	assert_eq(parser.parse(socket.sent_messages[0]), OK)
	assert_eq(int(parser.data.get("reconnect_seat", -1)), 0)

	main_menu._pending_reconnect_match = match_info
	dialog.secondary_button.pressed.emit()
	assert_eq(socket.sent_messages.size(), 2)
	assert_eq(parser.parse(socket.sent_messages[1]), OK)
	assert_eq(int(parser.data.get("reconnect_seat", -1)), 1)


func test_reconnect_choice_button_includes_seat_character_name():
	var main_menu = MainMenu.new()
	var ryu_name = CardDataManager.get_deck("ryu").get("display_name", "ryu")
	var sol_name = CardDataManager.get_deck("solbadguy").get("display_name", "solbadguy")
	var match_info = {"seat_decks": ["ryu", "solbadguy"]}

	assert_eq(main_menu._get_reconnect_seat_button_text(match_info, 0), "玩家1(%s)" % ryu_name)
	assert_eq(main_menu._get_reconnect_seat_button_text(match_info, 1), "玩家2(%s)" % sol_name)
	main_menu.free()


func test_saved_random_character_ids_are_considered_available():
	var main_menu = MainMenu.new()

	assert_true(main_menu._is_saved_character_available("random"))
	assert_true(main_menu._is_saved_character_available("random_s7"))
	assert_true(main_menu._is_saved_character_available("solbadguy"))
	assert_false(main_menu._is_saved_character_available("missing_character_id"))

	main_menu.free()


func test_leave_room_sends_normal_game_over_when_match_finished():
	var socket = MockSocket.new()
	NetworkManager._socket = socket
	NetworkManager.set_active_remote_match_finished(true)

	NetworkManager.leave_room()

	assert_eq(socket.sent_messages.size(), 1)
	var parser = JSON.new()
	assert_eq(parser.parse(socket.sent_messages[0]), OK)
	assert_eq(parser.data.get("type", ""), "leave_room")
	assert_true(parser.data.get("normal_game_over", false))
	assert_false(NetworkManager._active_remote_match_finished)


func test_player_disconnect_does_not_start_reconnect_after_normal_game_over():
	NetworkManager.set_active_remote_match_finished(true)

	NetworkManager._handle_player_disconnect({
		"type": "player_disconnect",
		"player_id": 42,
		"player_name": "Opponent",
	})

	assert_false(NetworkManager.get_reconnect_state()["is_waiting_for_opponent_reconnect"])


func test_player_quit_does_not_start_reconnect_after_normal_game_over():
	NetworkManager.set_active_remote_match_finished(true)

	NetworkManager._handle_player_quit({
		"type": "player_quit",
		"player_id": 42,
		"player_name": "Opponent",
		"is_disconnect": true,
	})

	assert_false(NetworkManager.get_reconnect_state()["is_waiting_for_opponent_reconnect"])