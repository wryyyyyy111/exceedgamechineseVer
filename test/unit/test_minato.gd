extends ExceedGutTest

const RemoteGameScript = preload("res://scenes/core/remote_game.gd")

class CaptureRemoteGame extends RemoteGameScript:
	var last_action_message = {}

	func _init():
		super(null)

	func _submit_game_message(action_message):
		_add_pending_minato_seal_payment(action_message)
		last_action_message = action_message

func who_am_i():
	return "minato"

func spawn_card_to_zone(player : Player, def_id : String, zone : String) -> int:
	var card_id = give_player_specific_card(player, def_id)
	var card = player.hand[player.hand.size() - 1]
	match zone:
		"gauge":
			player.add_to_gauge(card)
			player.hand.remove_at(player.hand.size() - 1)
		"sealed":
			player.add_to_sealed(card)
			player.hand.remove_at(player.hand.size() - 1)
		"discard":
			player.discard([card_id])
		_:
			assert(false, "Unknown zone: %s" % zone)
	return card_id

func count_powerup_events(events : Array, player : Player, amount : int) -> int:
	var count = 0
	for event in events:
		if event.event_type == Enums.EventType.EventType_Strike_PowerUp and event.event_player == player.my_id and event.number == amount:
			count += 1
	return count

func test_change_works_with_only_seal_force_bonus():
	var hand_before = player1.hand.size()
	player1.seal_force_bonus_tmp = 1

	assert_true(game_logic.do_change(player1, [], false))

	assert_eq(player1.seal_force_bonus_tmp, 0)
	assert_eq(player1.hand.size(), hand_before + 2)

func test_change_works_with_mixed_seal_force_and_card_force():
	var hand_before = player1.hand.size()
	var payment_id = give_player_specific_card(player1, "standard_normal_grasp")
	player1.seal_force_bonus_tmp = 1

	assert_true(game_logic.do_change(player1, [payment_id], false))

	assert_eq(player1.seal_force_bonus_tmp, 0)
	assert_true(player1.is_card_in_discards(payment_id))
	assert_eq(player1.hand.size(), hand_before + 3)

func test_move_range_counts_force_available_from_sealing_discards():
	position_players(player1, 3, player2, 7)
	player1.hand.clear()
	player1.gauge.clear()
	player1.free_force = 0
	player1.force_cost_reduction = 0
	for _i in range(3):
		spawn_card_to_zone(player1, "standard_normal_grasp", "discard")
	assert_eq(player1.get_force_to_move_to(6), 3)
	assert_true(player1.can_move_to(6, false))

	player1.seal_top_n_discards(3)
	player1.seal_force_bonus_tmp = 3
	assert_true(game_logic.do_move(player1, [], 6))
	assert_eq(player1.arena_location, 6)
	assert_eq(player1.discards.size(), 0)
	assert_eq(player1.sealed.size(), 3)


func test_remote_pay_strike_cost_processes_minato_sealed_gauge_before_validation():
	game_logic.teardown()
	game_logic.free()
	default_game_setup("taisei")
	position_players(player1, 3, player2, 7)
	for _i in range(11):
		spawn_card_to_zone(player1, "standard_normal_grasp", "discard")
	var ultra_id = give_player_specific_card(player1, "minato_streetcar_disaster")
	var response_id = give_player_specific_card(player2, "standard_normal_block")
	assert_true(game_logic.do_strike(player1, ultra_id, false, -1))
	assert_true(game_logic.do_strike(player2, response_id, false, -1))
	assert_true(game_logic.do_choice(player2, 0))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_PayStrikeCost_Required)

	var remote_game = CaptureRemoteGame.new()
	remote_game.local_game = game_logic
	remote_game._player_info = {'id': 1}
	remote_game._opponent_info = {'id': 2}
	remote_game._process_game_message({
		'action_type': 'action_pay_strike_cost',
		'player_id': 1,
		'card_ids': [],
		'wild_strike': false,
		'discard_ex_first': false,
		'use_free_force': false,
		'spent_life_for_force': 0,
		'pay_alternative_life_cost': false,
		'spent_life_for_gauge': 0,
		'minato_sealed_gauge': 3,
	})

	assert_eq(player1.sealed.size(), 9)
	assert_eq(player1.free_gauge, 0)
	assert_false(game_logic.game_state == Enums.GameState.GameState_PlayerDecision and game_logic.decision_info.player == player1.my_id and game_logic.decision_info.type == Enums.DecisionType.DecisionType_PayStrikeCost_Required)
	remote_game.free()

func test_remote_pay_strike_cost_serializes_minato_sealed_gauge():
	var remote_game = CaptureRemoteGame.new()
	remote_game.local_game = game_logic
	remote_game._player_info = {'id': 1}
	remote_game._opponent_info = {'id': 2}

	remote_game.set_pending_minato_seal_payment(0, 3)
	assert_true(remote_game.do_pay_strike_cost(player1, [], false, false, false, 0, false, 0))
	assert_false(remote_game.last_action_message.has('minato_sealed_force'))
	assert_eq(remote_game.last_action_message['minato_sealed_gauge'], 3)
	assert_eq(remote_game.last_action_message['spent_life_for_gauge'], 0)
	remote_game.free()

func test_remote_move_processes_minato_sealed_force_before_validation():
	position_players(player1, 3, player2, 7)
	player1.hand.clear()
	player1.gauge.clear()
	player1.discards.clear()
	player1.sealed.clear()
	player1.free_force = 0
	player1.force_cost_reduction = 0
	for _i in range(3):
		spawn_card_to_zone(player1, "standard_normal_grasp", "discard")

	var remote_game = CaptureRemoteGame.new()
	remote_game.local_game = game_logic
	remote_game._player_info = {'id': 1}
	remote_game._opponent_info = {'id': 2}
	remote_game._process_game_message({
		'action_type': 'action_move',
		'player_id': 1,
		'card_ids': [],
		'new_arena_location': 6,
		'use_free_force': false,
		'spent_life_for_force': 0,
		'minato_sealed_force': 3,
	})

	assert_eq(player1.arena_location, 6)
	assert_eq(player1.sealed.size(), 3)
	assert_eq(player1.discards.size(), 0)
	assert_eq(player1.seal_force_bonus_tmp, 0)
	remote_game.free()

func test_cleared_minato_seal_payment_does_not_leak_to_next_remote_action():
	var remote_game = CaptureRemoteGame.new()
	remote_game.local_game = game_logic
	remote_game._player_info = {'id': 1}
	remote_game._opponent_info = {'id': 2}
	remote_game.set_pending_minato_seal_payment(2, 1)
	remote_game.clear_pending_minato_seal_payment()

	assert_true(remote_game.do_prepare(player1))
	assert_false(remote_game.last_action_message.has('minato_sealed_force'))
	assert_false(remote_game.last_action_message.has('minato_sealed_gauge'))
	remote_game.free()

func test_set_strike_payment_permissions_do_not_emit_character_bonus():
	position_players(player1, 3, player2, 7)

	execute_strike(player1, player2, "standard_normal_cross", "standard_normal_focus")
	var events = game_logic.get_latest_events()

	validate_not_has_event(events, Enums.EventType.EventType_Strike_CharacterEffect, player1)
	assert_eq(player1.strike_stat_boosts.active_character_effects.size(), 0)

func test_exceed_seal_power_bonus_emits_character_effect_text_when_strike_starts():
	position_players(player1, 3, player2, 7)
	player1.exceeded = true
	player1.minato_seal_power_bonus = 3

	assert_true(game_logic.do_strike(player1, give_player_specific_card(player1, "standard_normal_cross"), false, -1))
	assert_true(game_logic.do_strike(player2, give_player_specific_card(player2, "standard_normal_focus"), false, -1))
	var events = game_logic.get_latest_events()

	var found_char_effect = false
	for event in events:
		if event['event_type'] == Enums.EventType.EventType_Strike_CharacterEffect and event['event_player'] == player1.my_id:
			var effect = event.get('extra_info', {})
			if effect.get('override_description', '').find("下一次攻击获得+3威力") != -1:
				found_char_effect = true
				break
	assert_true(found_char_effect)

func test_fractured_memories_attack_is_ex_with_copy_in_sealed():
	position_players(player1, 1, player2, 4)
	add_transform(player1, "minato_bus_stop")
	spawn_card_to_zone(player1, "minato_jump_the_shark", "sealed")

	execute_strike(player1, player2, "minato_jump_the_shark", "standard_normal_focus")
	var events = game_logic.get_latest_events()

	validate_has_event(events, Enums.EventType.EventType_Strike_ExUp, player1)

func test_fractured_memories_does_not_check_gauge_copy():
	position_players(player1, 1, player2, 4)
	add_transform(player1, "minato_bus_stop")
	spawn_card_to_zone(player1, "minato_jump_the_shark", "gauge")

	execute_strike(player1, player2, "minato_jump_the_shark", "standard_normal_focus")
	var events = game_logic.get_latest_events()

	validate_not_has_event(events, Enums.EventType.EventType_Strike_ExUp, player1)

func test_weight_of_regret_returns_missed_attack_to_hand():
	position_players(player1, 1, player2, 5)
	add_transform(player1, "minato_barnstorming")

	var strike_cards = execute_strike(player1, player2, "standard_normal_grasp", "standard_normal_focus", false, false, [0], [])

	assert_true(player1.is_card_in_hand(strike_cards[0]))

func test_weight_of_regret_does_not_return_block_that_goes_to_gauge():
	# block 未命中时，其 after 效果（add_strike_to_gauge_after_cleanup）会把攻击卡
	# 加入怒气，而不是弃掉 → Weight of Regret 不应弹「返回手牌」选择。
	# 距离 2，grasp 射程 1-1 未命中；block 是纯防御（射程 -1）也不会命中对手。
	position_players(player1, 3, player2, 5)
	add_transform(player2, "minato_barnstorming")

	var strike_cards = execute_strike(player1, player2, "standard_normal_grasp", "standard_normal_block", false, false, [], [])

	assert_false(player2.is_card_in_hand(strike_cards[1]),
			"block 会进怒气，不应被 Weight of Regret 返回手牌")
	assert_true(player2.is_card_in_gauge(strike_cards[1]),
			"block 应进入怒气区")

func test_outrun_the_past_seals_discard_and_gauge_then_draws():
	var discard_id = spawn_card_to_zone(player1, "standard_normal_grasp", "discard")
	var gauge_id = spawn_card_to_zone(player1, "standard_normal_cross", "gauge")
	var hand_before = player1.hand.size()
	game_logic.get_latest_events()

	game_logic.handle_strike_effect(-1, {"effect_type": "minato_outrun_the_past"}, player1)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseFromDiscard)
	assert_eq(game_logic.decision_info.source, "outrun_seal")

	assert_true(game_logic.do_choose_from_discard(player1, [discard_id, gauge_id]))
	var events = game_logic.get_latest_events()

	assert_true(player1.is_card_in_sealed(discard_id))
	assert_true(player1.is_card_in_sealed(gauge_id))
	assert_eq(player1.hand.size(), hand_before + 1)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	validate_has_event(events, Enums.EventType.EventType_ForceStartStrike, player1)
	for event in events:
		if event.event_type == Enums.EventType.EventType_ForceStartStrike:
			assert_eq(event.extra_info3, "silent_pre_strike")

func test_outrun_the_past_cancel_still_returns_to_strike_flow():
	spawn_card_to_zone(player1, "standard_normal_grasp", "discard")
	var hand_before = player1.hand.size()
	game_logic.get_latest_events()

	game_logic.handle_strike_effect(-1, {"effect_type": "minato_outrun_the_past"}, player1)
	assert_true(game_logic.do_choose_from_discard(player1, []))
	var events = game_logic.get_latest_events()

	assert_eq(player1.hand.size(), hand_before)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	validate_has_event(events, Enums.EventType.EventType_ForceStartStrike, player1)
	for event in events:
		if event.event_type == Enums.EventType.EventType_ForceStartStrike:
			assert_eq(event.extra_info3, "silent_pre_strike")

func test_outrun_the_past_and_following_strike_share_one_strike_start():
	position_players(player1, 3, player2, 5)
	add_transform(player1, "minato_flight_13")
	var discard_id = spawn_card_to_zone(player1, "standard_normal_grasp", "discard")
	var attack_id = give_player_specific_card(player1, "standard_normal_assault")
	var response_id = give_player_specific_card(player2, "standard_normal_block")

	game_logic.handle_strike_effect(-1, {"effect_type": "minato_outrun_the_past"}, player1)
	assert_true(game_logic.do_choose_from_discard(player1, [discard_id]))
	game_logic.get_latest_events()

	assert_true(game_logic.do_strike(player1, attack_id, false, -1))
	assert_true(game_logic.do_strike(player2, response_id, false, -1))
	var events = game_logic.get_latest_events()
	var strike_started_count = 0
	var force_start_count = 0
	for event in events:
		if event.event_type == Enums.EventType.EventType_Strike_Started:
			strike_started_count += 1
		elif event.event_type == Enums.EventType.EventType_ForceStartStrike:
			force_start_count += 1

	assert_eq(strike_started_count, 1)
	assert_eq(force_start_count, 0)

func test_outrun_the_past_defender_triggers_before_setting_response():
	position_players(player1, 3, player2, 5)
	add_transform(player2, "minato_flight_13")
	spawn_card_to_zone(player2, "standard_normal_cross", "discard")
	var attack_id = give_player_specific_card(player1, "standard_normal_assault")
	var response_id = give_player_specific_card(player2, "standard_normal_block")

	assert_true(game_logic.do_strike(player1, attack_id, false, -1))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.player, player2.my_id)
	assert_eq(game_logic.decision_info.source, "outrun_seal")

	assert_true(game_logic.do_choose_from_discard(player2, []))
	assert_true(game_logic.do_strike(player2, response_id, false, -1))

func test_outrun_the_past_defender_does_not_repeat_carlswangee_exceed_ua():
	game_logic.teardown()
	game_logic.free()
	default_game_setup("carlswangee")
	position_players(player1, 3, player2, 5)
	player2.exceeded = true
	game_logic.active_turn_player = player2.my_id
	add_transform(player1, "minato_flight_13")
	spawn_card_to_zone(player1, "standard_normal_cross", "discard")
	var carl_sweep_id = give_player_specific_card(player2, "standard_normal_sweep")
	var minato_response_id = give_player_specific_card(player1, "standard_normal_block")

	assert_true(game_logic.do_strike(player2, carl_sweep_id, false, -1))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.decision_info.source, "outrun_seal")
	assert_true(game_logic.do_choose_from_discard(player1, []))
	assert_true(game_logic.do_strike(player1, minato_response_id, false, -1))
	var events = game_logic.get_latest_events()

	assert_eq(count_powerup_events(events, player2, 2), 1)

func test_outrun_the_past_initiator_does_not_repeat_carlswangee_response_exceed_ua():
	game_logic.teardown()
	game_logic.free()
	default_game_setup("carlswangee")
	position_players(player1, 3, player2, 5)
	player2.exceeded = true
	add_transform(player1, "minato_flight_13")
	var discard_id = spawn_card_to_zone(player1, "standard_normal_cross", "discard")
	var minato_attack_id = give_player_specific_card(player1, "standard_normal_assault")
	var carl_sweep_id = give_player_specific_card(player2, "standard_normal_sweep")

	game_logic.handle_strike_effect(-1, {"effect_type": "minato_outrun_the_past"}, player1)
	assert_true(game_logic.do_choose_from_discard(player1, [discard_id]))
	game_logic.get_latest_events()

	assert_true(game_logic.do_strike(player1, minato_attack_id, false, -1))
	assert_true(game_logic.do_strike(player2, carl_sweep_id, false, -1))
	var events = game_logic.get_latest_events()

	assert_eq(count_powerup_events(events, player2, 2), 1)

func test_one_more_ride_returns_sealed_instead_of_end_draw():
	var sealed_id = spawn_card_to_zone(player1, "standard_normal_sweep", "sealed")
	var boost_id = give_player_specific_card(player1, "minato_cabstand")
	var hand_before = player1.hand.size()

	assert_true(game_logic.do_boost(player1, boost_id, []))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseFromDiscard)
	assert_eq(game_logic.decision_info.source, "sealed")

	assert_true(game_logic.do_choose_from_discard(player1, [sealed_id]))

	assert_true(player1.is_card_in_hand(sealed_id))
	assert_eq(player1.hand.size(), hand_before)

func test_one_more_ride_triggers_again_next_turn_while_boost_remains():
	var sealed_id_1 = spawn_card_to_zone(player1, "standard_normal_sweep", "sealed")
	var sealed_id_2 = spawn_card_to_zone(player1, "standard_normal_grasp", "sealed")
	var boost_id = give_player_specific_card(player1, "minato_cabstand")

	assert_true(game_logic.do_boost(player1, boost_id, []))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseFromDiscard)
	assert_eq(game_logic.decision_info.source, "sealed")
	assert_true(game_logic.do_choose_from_discard(player1, [sealed_id_1]))
	assert_true(player1.is_card_in_hand(sealed_id_1))
	assert_eq(player1.continuous_boosts.size(), 1)

	advance_turn(player2)
	advance_turn(player1)

	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseFromDiscard)
	assert_eq(game_logic.decision_info.source, "sealed")
	assert_true(game_logic.do_choose_from_discard(player1, [sealed_id_2]))
	assert_true(player1.is_card_in_hand(sealed_id_2))

func test_one_more_ride_does_not_stack_with_two_boosts():
	spawn_card_to_zone(player1, "standard_normal_sweep", "sealed")
	var boost_id_1 = give_player_specific_card(player1, "minato_cabstand")

	assert_true(game_logic.do_boost(player1, boost_id_1, []))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_true(game_logic.do_choice(player1, 1))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)

	advance_turn(player2)
	var boost_id_2 = give_player_specific_card(player1, "minato_cabstand")

	assert_true(game_logic.do_boost(player1, boost_id_2, []))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(player1.continuous_boosts.size(), 2)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.choice.size(), 2)
	assert_true(game_logic.do_choice(player1, 1))

func test_daredevil_multiple_boosts_stack_per_card_instance():
	position_players(player1, 2, player2, 5)
	var boost_id_1 = give_player_specific_card(player1, "minato_streetcar_disaster")
	var boost_id_2 = give_player_specific_card(player1, "minato_streetcar_disaster")

	assert_true(game_logic.do_boost(player1, boost_id_1, []))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_true(game_logic.do_choice(player1, 1))
	assert_eq(player1.continuous_boosts.size(), 1)
	assert_eq(int(player1.continuous_boosts[0].get_meta("minato_dd_count")), 2)

	game_logic.game_state = Enums.GameState.GameState_PickAction
	game_logic.active_turn_player = player1.my_id

	assert_true(game_logic.do_boost(player1, boost_id_2, []))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_true(game_logic.do_choice(player1, 3))
	assert_eq(player1.continuous_boosts.size(), 2)
	assert_eq(int(player1.continuous_boosts[1].get_meta("minato_dd_count")), 4)
	assert_eq(player1.sealed.size(), 6)

	var attack_id = give_player_specific_card(player1, "standard_normal_sweep")
	assert_true(game_logic.do_strike(player1, attack_id, false, -1))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_Strike_Opponent_Response)

	assert_eq(game_logic.get_total_speed(player1), 8)

func test_exceed_begin_turn_seals_discards_and_next_attack_gets_power():
	position_players(player1, 4, player2, 5)
	spawn_card_to_zone(player1, "standard_normal_grasp", "discard")
	spawn_card_to_zone(player1, "standard_normal_cross", "discard")
	player1.exceed()
	game_logic.get_latest_events()

	game_logic.start_begin_turn()

	assert_eq(player1.discards.size(), 0)
	assert_eq(player1.minato_seal_power_bonus, 2)
	assert_eq(player1.sealed.size(), 2)

	execute_strike(player1, player2, "standard_normal_assault", "standard_normal_focus")

	assert_eq(player1.minato_seal_power_bonus, 0)
	validate_life(player1, 26, player2, 26)

func test_exceed_bonus_persists_during_strike_and_clears_after_cleanup():
	position_players(player1, 4, player2, 5)
	player1.exceeded = true
	player1.minato_seal_power_bonus = 2

	assert_true(game_logic.do_strike(player1, give_player_specific_card(player1, "standard_normal_assault"), false, -1))
	assert_eq(player1.minato_seal_power_bonus, 2)
	assert_true(game_logic.do_strike(player2, give_player_specific_card(player2, "standard_normal_focus"), false, -1))
	assert_eq(player1.minato_seal_power_bonus, 0)

func test_exceed_clears_free_gauge_after_payment():
	position_players(player1, 4, player2, 5)
	var gauge_ids = give_gauge(player1, 3)
	player1.free_gauge = 2

	assert_true(game_logic.do_exceed(player1, gauge_ids))
	assert_eq(player1.free_gauge, 0)

func test_ultra_cost_counts_gauge_available_from_sealing_discards():
	position_players(player1, 3, player2, 7)
	var gauge_ids = give_gauge(player1, 1)
	for _i in range(6):
		spawn_card_to_zone(player1, "standard_normal_grasp", "discard")
	var ultra_id = give_player_specific_card(player1, "minato_streetcar_disaster")
	var response_id = give_player_specific_card(player2, "standard_normal_focus")

	assert_true(game_logic.do_strike(player1, ultra_id, false, -1))
	assert_true(game_logic.do_strike(player2, response_id, false, -1))

	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_PayStrikeCost_Required)
	assert_eq(game_logic.decision_info.limitation, "gauge")
	assert_eq(game_logic.decision_info.cost, 3)

	player1.seal_top_n_discards(6)
	player1.free_gauge += 2
	assert_true(game_logic.do_pay_strike_cost(player1, gauge_ids, false))
	assert_eq(player1.discards.size(), 2)
	assert_eq(player1.gauge.size(), 0)
	assert_eq(player1.sealed.size(), 6)

func test_can_pay_cost_counts_seal_gauge_potential():
	position_players(player1, 4, player2, 5)
	give_gauge(player1, 3)
	for i in range(9):
		spawn_card_to_zone(player1, "standard_normal_grasp", "discard")
	assert_true(player1.can_pay_cost(0, 6))

func test_can_do_exceed_counts_seal_gauge_potential():
	position_players(player1, 4, player2, 5)
	game_logic.game_state = Enums.GameState.GameState_PickAction
	game_logic.active_turn_player = player1.my_id
	player1.gauge.clear()
	player1.free_gauge = 0
	player1.exceed_cost = 2
	for i in range(6):
		spawn_card_to_zone(player1, "standard_normal_grasp", "discard")

	assert_true(game_logic.can_do_exceed(player1))

func test_can_pay_cost_rejects_when_seal_gauge_insufficient():
	position_players(player1, 4, player2, 5)
	give_gauge(player1, 3)
	for i in range(3):
		spawn_card_to_zone(player1, "standard_normal_grasp", "discard")
	assert_false(player1.can_pay_cost(0, 6))

func test_can_pay_cost_counts_seal_force_potential():
	position_players(player1, 4, player2, 5)
	player1.hand = []
	for i in range(3):
		spawn_card_to_zone(player1, "standard_normal_grasp", "discard")
	assert_true(player1.can_pay_cost(3, 0))

func test_can_move_to_counts_seal_force_potential():
	position_players(player1, 4, player2, 5)
	player1.hand = []
	spawn_card_to_zone(player1, "standard_normal_grasp", "discard")
	spawn_card_to_zone(player1, "standard_normal_cross", "discard")
	assert_true(player1.can_move_to(3, false))

func test_can_move_to_rejects_without_seal_force():
	position_players(player1, 4, player2, 5)
	player1.hand = []
	assert_false(player1.can_move_to(3, false))

func test_can_do_move_counts_seal_force_potential():
	position_players(player1, 4, player2, 5)
	player1.hand = []
	spawn_card_to_zone(player1, "standard_normal_grasp", "discard")
	spawn_card_to_zone(player1, "standard_normal_cross", "discard")
	assert_true(game_logic.can_do_move(player1))

func seal_all_other_cards(player, keep_id = -1):
	for card in player.hand.duplicate():
		if card.id != keep_id:
			player.add_to_sealed(card)
			player.hand.erase(card)
	for card in player.deck.duplicate():
		if card.id != keep_id:
			player.add_to_sealed(card)
			player.deck.erase(card)
	for card in player.discards.duplicate():
		if card.id != keep_id:
			player.add_to_sealed(card)
			player.discards.erase(card)

func test_hellward_bound_free_when_all_other_cards_sealed():
	position_players(player1, 2, player2, 5)
	var hb_id = give_player_specific_card(player1, "minato_hellward_bound")
	seal_all_other_cards(player1, hb_id)
	do_and_validate_strike(player1, hb_id)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_Strike_Opponent_Response)
	var hb_card = game_logic.active_strike.get_player_card(player1)
	assert_eq(game_logic.get_gauge_cost(player1, hb_card), 0)

func test_hellward_bound_not_free_when_discard_has_cards():
	position_players(player1, 2, player2, 5)
	give_gauge(player1, 6)
	var hb_id = give_player_specific_card(player1, "minato_hellward_bound")
	seal_all_other_cards(player1, hb_id)
	spawn_card_to_zone(player1, "standard_normal_grasp", "discard")
	var gauge_cards = []
	for c in player1.gauge:
		gauge_cards.append(c.id)
	execute_strike(player1, player2, hb_id, "standard_normal_dive", false, false,
		[gauge_cards],
		[[]],
		true)
	assert_eq(player1.gauge.size(), 0)

# ---------------- 回合结束：跳过抽牌 ≠ 跳过手牌上限 ----------------
# 默认：跳过「回合结束抽牌」会连带跳过「弃牌到上限」（superskullman Zap 等依赖此行为）。
# 但带 still_check_hand_limit 的效果（minato One More Ride / eugenia Time for Tea 觉醒）
# 只是「不抽牌」，手牌超过上限（7）时仍须弃牌。

func test_still_check_hand_limit_forces_discard_down():
	position_players(player1, 3, player2, 5)
	player1.discard_hand()
	for _i in range(8):
		give_player_specific_card(player1, "gg_normal_grasp")
	assert_eq(player1.hand.size(), 8, "前置：应有 8 张手牌（上限 7）")
	player1.skip_end_of_turn_draw = true
	player1.eot_skip_draw_still_check_hand_limit = true
	game_logic.finish_end_turn_draw(player1)
	assert_false(game_logic.end_of_turn_skip_eot_discard,
			"标记了 still_check_hand_limit 时仍要检查手牌上限")
	assert_eq(game_logic.game_state, Enums.GameState.GameState_DiscardDownToMax,
			"手牌超上限时应进入弃牌流程")

func test_plain_skip_draw_still_skips_discard():
	position_players(player1, 3, player2, 5)
	player1.discard_hand()
	for _i in range(8):
		give_player_specific_card(player1, "gg_normal_grasp")
	player1.skip_end_of_turn_draw = true
	game_logic.finish_end_turn_draw(player1)
	assert_true(game_logic.end_of_turn_skip_eot_discard,
			"普通跳过抽牌（无标记）应保持原行为：连带跳过弃牌")

func test_iaquis_passive_still_skips_draw_and_discard():
	position_players(player1, 3, player2, 5)
	player1.discard_hand()
	for _i in range(8):
		give_player_specific_card(player1, "gg_normal_grasp")
	player1.passive_effects["skip_eot_draw_and_discard"] = 1
	game_logic.finish_end_turn_draw(player1)
	assert_true(game_logic.end_of_turn_skip_eot_discard,
			"Dragon's Roar 的被动应继续同时跳过抽牌与弃牌")