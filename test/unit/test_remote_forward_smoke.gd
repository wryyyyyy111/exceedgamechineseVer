extends ExceedGutTest

func who_am_i():
	return "renea"

class CaptureRemoteGame extends RemoteGame:
	var last_action_message = {}

	func _init():
		super(null)

	func _submit_game_message(action_message):
		last_action_message = action_message

class RestoreCheckRemoteGame extends CaptureRemoteGame:
	var initialize_count := 0

	func teardown():
		_free_lightweight_local_game()

	func _free_lightweight_local_game():
		if not local_game:
			return
		if local_game.decision_info:
			local_game.decision_info.free()
		local_game.free()
		local_game = null

	func _initialize_local_game(_restore_player_info, _restore_opponent_info, _starting_player : Enums.PlayerId, _seed_value : int):
		initialize_count += 1
		_free_lightweight_local_game()
		local_game = LocalGame.new(null)
		_game_message_history = []

	func _process_game_message(action_message):
		_game_message_history.append(action_message)
		if action_message.get('risk_restore_submit', false):
			local_game.event_queue.append({
				'event_type': Enums.EventType.EventType_Strike_EffectDoStrike,
			})

# Smoke check: RemoteGame must forward the methods that game_wrapper.can_player_boost
# (Umina Spiraling Descent) and Tournelouse Ouroboros cancel actions rely on.
# Missing forwards made boost unusable in online (remote) matches.

func test_remote_game_has_forwarded_methods():
	var rg = RemoteGame.new(null)
	assert_true(rg.has_method("get_other_player"), "RemoteGame.get_other_player missing")
	assert_true(rg.has_method("_is_spiraling_match"), "RemoteGame._is_spiraling_match missing")
	assert_true(rg.has_method("do_cancel_tournelouse_ouroboros_hand_choice"), "RemoteGame.do_cancel_tournelouse_ouroboros_hand_choice missing")
	assert_true(rg.has_method("do_cancel_tournelouse_ouroboros_transform_choice"), "RemoteGame.do_cancel_tournelouse_ouroboros_transform_choice missing")
	assert_true(rg.has_method("do_quit"), "RemoteGame.do_quit missing")
	rg.free()

func test_replay_json_numbers_restore_integer_card_ids_recursively():
	var rg = RemoteGame.new(null)
	var normalized = rg._normalize_replay_json_numbers({
		"card_id": 116.0,
		"card_ids": [116.0, 127.0],
		"fractional_value": 1.5,
	})

	assert_typeof(normalized["card_id"], TYPE_INT)
	assert_typeof(normalized["card_ids"][0], TYPE_INT)
	assert_eq(normalized["card_ids"], [116, 127])
	assert_typeof(normalized["fractional_value"], TYPE_FLOAT)
	rg.free()

func test_remote_game_do_quit_sends_action_quit_message():
	var rg = CaptureRemoteGame.new()
	rg._player_info = {
		'id': 17,
	}
	rg._opponent_info = {
		'id': 23,
	}

	assert_true(rg.do_quit(Enums.PlayerId.PlayerId_Player, Enums.GameOverReason.GameOverReason_Quit))
	assert_eq(rg.last_action_message.get('action_type', ''), 'action_quit')
	assert_eq(int(rg.last_action_message.get('player_id', -1)), 17)
	assert_eq(int(rg.last_action_message.get('reason', -1)), Enums.GameOverReason.GameOverReason_Quit)
	rg.free()

func test_remote_game_do_boost_sends_action_without_facedown_override():
	var rg = CaptureRemoteGame.new()
	rg._player_info = {
		'id': 17,
	}
	rg._opponent_info = {
		'id': 23,
	}
	assert_true(rg.do_boost(player1, 42))
	assert_eq(rg.last_action_message.get('action_type', ''), 'action_boost')
	assert_eq(int(rg.last_action_message.get('player_id', -1)), 17)
	assert_eq(int(rg.last_action_message.get('card_id', -1)), 42)
	assert_false(rg.last_action_message.has('facedown_override'))
	rg.free()

func test_remote_game_do_boost_forwards_renea_facedown_override():
	var rg = CaptureRemoteGame.new()
	rg._player_info = {
		'id': 17,
	}
	rg._opponent_info = {
		'id': 23,
	}
	assert_true(rg.do_boost(player1, 42, [], false, 0, [], true))
	assert_eq(rg.last_action_message.get('action_type', ''), 'action_boost')
	assert_eq(int(rg.last_action_message.get('player_id', -1)), 17)
	assert_eq(int(rg.last_action_message.get('card_id', -1)), 42)
	assert_true(rg.last_action_message.get('facedown_override', false))
	rg.free()

func test_restore_message_queue_rolls_back_trailing_risky_submit_event():
	var rg = RestoreCheckRemoteGame.new()
	var restore_messages = [
		{'action_type': 'action_prepare', 'player_id': 17},
		{'action_type': 'action_strike', 'player_id': 17, 'risk_restore_submit': true},
	]
	rg._initialize_local_game({}, {}, Enums.PlayerId.PlayerId_Player, 1)
	rg._process_restore_message_queue_with_safety_check({}, {}, Enums.PlayerId.PlayerId_Player, 1, restore_messages)

	assert_eq(rg.initialize_count, 2)
	assert_eq(rg.get_message_history().size(), 1)
	assert_eq(rg.get_message_history()[0].get('action_type', ''), 'action_prepare')
	assert_eq(rg.get_pending_observer_messages().size(), 1)
	assert_false(rg._has_risky_restore_fast_forward_event())
	rg.teardown()
	rg.free()

func test_restore_message_queue_keeps_earlier_risky_event_when_tail_is_safe():
	var rg = RestoreCheckRemoteGame.new()
	var restore_messages = [
		{'action_type': 'action_prepare', 'player_id': 17},
		{'action_type': 'action_strike', 'player_id': 17, 'risk_restore_submit': true},
		{'action_type': 'action_choice', 'player_id': 17},
	]
	rg._initialize_local_game({}, {}, Enums.PlayerId.PlayerId_Player, 1)
	rg._process_restore_message_queue_with_safety_check({}, {}, Enums.PlayerId.PlayerId_Player, 1, restore_messages)

	assert_eq(rg.initialize_count, 1)
	assert_eq(rg.get_message_history().size(), 3)
	assert_eq(rg.get_message_history()[2].get('action_type', ''), 'action_choice')
	assert_eq(rg.get_pending_observer_messages().size(), 3)
	assert_true(rg._has_risky_restore_fast_forward_event())
	rg.teardown()
	rg.free()

func test_remote_game_starts_renea_pre_strike_reveal():
	var rg = CaptureRemoteGame.new()
	rg._player_info = {
		'id': 17,
	}
	rg._opponent_info = {
		'id': 23,
	}

	assert_true(rg.do_renea_pre_strike_reveal(player1))
	assert_eq(rg.last_action_message.get('action_type', ''), 'action_renea_pre_strike_reveal')
	assert_eq(int(rg.last_action_message.get('player_id', -1)), 17)
	assert_false(rg.last_action_message.get('strike_response', false))
	rg.free()

func test_remote_game_starts_renea_response_reveal():
	var rg = CaptureRemoteGame.new()
	rg._player_info = {
		'id': 17,
	}
	rg._opponent_info = {
		'id': 23,
	}

	assert_true(rg.do_renea_pre_strike_reveal(player1, true))
	assert_eq(rg.last_action_message.get('action_type', ''), 'action_renea_pre_strike_reveal')
	assert_eq(int(rg.last_action_message.get('player_id', -1)), 17)
	assert_true(rg.last_action_message.get('strike_response', false))
	rg.free()

# Minato Outrun the Past (attacker side): the strike button must forward over the
# network through RemoteGame do_/process_ pairs, mirroring the Renea pre-strike
# reveal fix. Directly calling handle_strike_effect on current_game (RemoteGame)
# silently failed in online matches, freezing the game before the attack card
# could be selected.

func test_remote_game_has_minato_outrun_forwarded_methods():
	var rg = RemoteGame.new(null)
	assert_true(rg.has_method("do_minato_outrun_before_strike"), "RemoteGame.do_minato_outrun_before_strike missing")
	assert_true(rg.has_method("process_minato_outrun_before_strike"), "RemoteGame.process_minato_outrun_before_strike missing")
	rg.free()

func test_remote_game_forwards_minato_outrun_before_strike():
	var rg = CaptureRemoteGame.new()
	rg._player_info = {
		'id': 17,
	}
	rg._opponent_info = {
		'id': 23,
	}

	assert_true(rg.do_minato_outrun_before_strike(player1))
	assert_eq(rg.last_action_message.get('action_type', ''), 'action_minato_outrun_before_strike')
	assert_eq(int(rg.last_action_message.get('player_id', -1)), 17)
	rg.free()

func test_remote_game_process_minato_outrun_sets_flag_and_starts_decision():
	var rg = CaptureRemoteGame.new()
	rg._player_info = {
		'id': 17,
	}
	rg._opponent_info = {
		'id': 23,
	}
	rg.local_game = game_logic
	# player1 (remote id 17) is the attacker; give it cards to seal.
	var discard_id = give_player_specific_card(player1, "standard_normal_grasp")
	player1.discard([discard_id])

	rg._process_game_message({
		'action_type': 'action_minato_outrun_before_strike',
		'player_id': 17,
	})

	assert_true(player1.minato_outrun_triggered_before_strike)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseFromDiscard)
	assert_eq(game_logic.decision_info.source, "outrun_seal")
	rg.free()

func test_game_wrapper_local_branch_triggers_outrun():
	var wrapper = GameWrapper.new()
	wrapper.current_game = game_logic
	var discard_id = give_player_specific_card(player1, "standard_normal_grasp")
	player1.discard([discard_id])

	assert_true(wrapper.submit_minato_outrun_before_strike(Enums.PlayerId.PlayerId_Player))
	assert_true(player1.minato_outrun_triggered_before_strike)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.source, "outrun_seal")
	wrapper.free()
