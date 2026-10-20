extends GutTest

const GameScene = preload("res://scenes/game/game.tscn")

func test_previous_replay_step_rebuild_uses_complete_log_and_skips_emotes():
	var game_ui : Game = GameScene.instantiate()
	add_child_autofree(game_ui)
	await get_tree().process_frame
	game_ui.starting_message = {
		"player1_id": 7,
		"observer_log": [{"action_type": "stale_pending_message"}],
	}
	var processed_messages := [
		{"action_type": "action_prepare"},
		{"action_type": "action_boost"},
		{"action_type": "action_emote"},
	]
	var pending_messages := [{"action_type": "action_strike"}]

	var rebuild_data : Dictionary = game_ui._build_previous_replay_start_data(processed_messages, pending_messages)

	assert_eq(rebuild_data["replay_seek_target"], 1)
	assert_eq(rebuild_data["observer_log"].size(), 4)
	assert_eq(rebuild_data["observer_log"][0]["action_type"], "action_prepare")
	assert_eq(rebuild_data["observer_log"][3]["action_type"], "action_strike")
	assert_eq(rebuild_data["restore_log"], rebuild_data["observer_log"])
	assert_eq(game_ui.starting_message["observer_log"][0]["action_type"], "stale_pending_message")
	assert_true(rebuild_data["replay_step_rebuild"])
	assert_eq(rebuild_data["your_player_id"], 7)