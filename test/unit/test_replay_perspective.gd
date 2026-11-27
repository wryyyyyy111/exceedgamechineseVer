extends GutTest

class ReplayMenu extends MainMenu:
	func _ready():
		_connect_reconnect_choice_dialog_signals()
		modal_dialog.hide()

var menu : MainMenu

func before_each():
	menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	menu.set_script(ReplayMenu)
	add_child(menu)
	watch_signals(menu)

func after_each():
	menu.queue_free()
	await get_tree().process_frame

func replay_data() -> Dictionary:
	return {
		"replay_version": GlobalSettings.ReplayVersion,
		"messages": [
			{
				"type": "game_start",
				"player1_id": 7,
				"player2_id": 9,
				"player1_name": "First player",
				"player2_name": "Second player",
				"player1_deck_id": "minato",
				"player2_deck_id": "ryu",
				"player1_custom_deck": null,
				"player2_custom_deck": null,
				"starting_player_id": 7,
				"seed_value": 1234,
				"starting_timer": 60,
				"enforce_timer": false,
				"minimum_time_per_choice": 0,
			},
			{"action_type": "action_prepare", "player_id": 9},
		],
	}

func test_loading_replay_prompts_for_perspective_before_starting():
	menu.load_replay([JSON.stringify(replay_data())])

	assert_true(menu.modal_dialog.visible)
	assert_eq(menu.modal_dialog.message_label.text, "选择载入回放的主视角")
	assert_eq(menu.modal_dialog.accept_button.text,
		"player1(%s)" % CardDataManager.get_deck("minato")["display_name"])
	assert_eq(menu.modal_dialog.secondary_button.text,
		"player2(%s)" % CardDataManager.get_deck("ryu")["display_name"])
	assert_true(menu.modal_dialog.accept_button.visible)
	assert_true(menu.modal_dialog.secondary_button.visible)
	assert_signal_not_emitted(menu, "start_remote_game")

func assert_selected_perspective(player_number : int):
	var data = replay_data()
	menu.load_replay([JSON.stringify(data)])
	if player_number == 1:
		menu.modal_dialog.accept_button.pressed.emit()
	else:
		menu.modal_dialog.secondary_button.pressed.emit()

	assert_signal_emit_count(menu, "start_remote_game", 1)
	var parameters = get_signal_parameters(menu, "start_remote_game")
	var vs_info : Dictionary = parameters[0]
	var start_data : Dictionary = parameters[1]
	assert_eq(start_data["your_player_id"], 7 if player_number == 1 else 9)
	assert_eq(vs_info["player_name"], "First player" if player_number == 1 else "Second player")
	assert_eq(vs_info["opponent_name"], "Second player" if player_number == 1 else "First player")
	assert_eq(vs_info["player_deck"]["id"], "minato" if player_number == 1 else "ryu")
	assert_eq(vs_info["opponent_deck"]["id"], "ryu" if player_number == 1 else "minato")
	assert_eq(start_data["player1_deck_id"], "minato")
	assert_eq(start_data["player2_deck_id"], "ryu")
	assert_eq(start_data["starting_player_id"], 7)
	assert_eq(start_data["seed_value"], 1234)
	assert_true(start_data["observer_mode"])
	assert_true(start_data["replay_mode"])
	assert_eq(start_data["observer_log"], JSON.parse_string(JSON.stringify(data["messages"].slice(1))))
	assert_false(menu.modal_dialog.visible)
	assert_true(menu._pending_replay_data.is_empty())

func test_player1_choice_starts_replay_from_player1():
	assert_selected_perspective(1)

func test_player2_choice_starts_replay_from_player2():
	assert_selected_perspective(2)

func test_player2_choice_initializes_game_and_remote_player_mapping():
	menu.load_replay([JSON.stringify(replay_data())])
	menu.modal_dialog.secondary_button.pressed.emit()
	var parameters = get_signal_parameters(menu, "start_remote_game")
	var game_ui : Game = load("res://scenes/game/game.tscn").instantiate()
	game_ui.set_not_started_directly()
	game_ui.add_child(game_ui.game_wrapper)
	add_child(game_ui)
	game_ui.image_loader.defer_registered_card_images = true
	game_ui.begin_remote_game(parameters[1])

	var remote_game = game_ui.game_wrapper.current_game
	assert_eq(game_ui.player_deck["id"], "ryu")
	assert_eq(game_ui.opponent_deck["id"], "minato")
	assert_eq(remote_game._get_player_from_remote_id(9).my_id, Enums.PlayerId.PlayerId_Player)
	assert_eq(remote_game._get_player_from_remote_id(7).my_id, Enums.PlayerId.PlayerId_Opponent)
	assert_eq(remote_game.local_game.active_turn_player, Enums.PlayerId.PlayerId_Opponent)
	assert_true(game_ui.replay_mode)
	assert_true(game_ui.observer_mode)
	game_ui.free()

func test_cancelling_clears_pending_replay_without_starting():
	menu.load_replay([JSON.stringify(replay_data())])
	menu.modal_dialog.cancel_button.pressed.emit()

	assert_signal_not_emitted(menu, "start_remote_game")
	assert_false(menu.modal_dialog.visible)
	assert_true(menu._pending_replay_data.is_empty())
	menu.modal_dialog.accept_button.pressed.emit()
	assert_signal_not_emitted(menu, "start_remote_game")

func test_choice_labels_and_player2_support_random_and_custom_decks():
	var data = replay_data()
	var start_data : Dictionary = data["messages"][0]
	start_data["player1_deck_id"] = "random_s2#minato"
	start_data["player2_deck_id"] = "custom_replay_test"
	start_data["player2_custom_deck"] = {
		"id": "custom_replay_test",
		"display_name": "Replay custom character",
	}
	menu.load_replay([JSON.stringify(data)])

	assert_eq(menu.modal_dialog.accept_button.text,
		"player1(%s)" % CardDataManager.get_deck("minato")["display_name"])
	assert_eq(menu.modal_dialog.secondary_button.text, "player2(Replay custom character)")
	menu.modal_dialog.secondary_button.pressed.emit()
	var parameters = get_signal_parameters(menu, "start_remote_game")
	var vs_info : Dictionary = parameters[0]
	var loaded_start : Dictionary = parameters[1]
	assert_eq(vs_info["player_deck"]["id"], "custom_replay_test")
	assert_eq(vs_info["opponent_deck"]["id"], "minato")
	assert_eq(vs_info["opponent_random_tag"], "random_s2")
	assert_eq(loaded_start["player1_deck_id"], "minato")
	assert_eq(loaded_start["your_player_id"], 9)

func test_legacy_match_log_also_prompts_for_perspective():
	var data = replay_data()
	var legacy_data = {
		"replay_version": GlobalSettings.ReplayVersion,
		"MatchLog": JSON.stringify(data["messages"]),
	}
	menu.load_replay([JSON.stringify(legacy_data)])

	assert_true(menu.modal_dialog.visible)
	assert_signal_not_emitted(menu, "start_remote_game")
	menu.modal_dialog.secondary_button.pressed.emit()
	var parameters = get_signal_parameters(menu, "start_remote_game")
	assert_eq(parameters[1]["your_player_id"], 9)
	assert_eq(parameters[1]["observer_log"], JSON.parse_string(JSON.stringify(data["messages"].slice(1))))

func test_live_observation_keeps_player1_without_prompt_or_input_mutation():
	var data = replay_data()
	var original = data.duplicate(true)
	menu._on_observe_game_started(data)

	assert_signal_emit_count(menu, "start_remote_game", 1)
	var parameters = get_signal_parameters(menu, "start_remote_game")
	assert_eq(parameters[1]["your_player_id"], 7)
	assert_false(parameters[1]["replay_mode"])
	assert_false(menu.modal_dialog.visible)
	assert_eq(data, original)

func test_replay_step_back_preserves_selected_player2_perspective():
	var game_ui = Game.new()
	game_ui.starting_message = {
		"player1_id": 7,
		"player2_id": 9,
		"your_player_id": 9,
	}
	var rebuilt = game_ui._build_previous_replay_start_data(
		[{"action_type": "action_prepare", "player_id": 9}], [])

	assert_eq(rebuilt["your_player_id"], 9)
	game_ui.game_wrapper.free()
	game_ui.free()
