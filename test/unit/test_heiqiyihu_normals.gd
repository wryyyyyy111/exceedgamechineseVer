extends ExceedGutTest


func who_am_i():
	var deck = CardDataManager.get_deck_from_str_id("heiqiyihu").duplicate(true)
	deck["starting_life"] = 100
	deck["life_cap"] = 100
	return deck


func before_each():
	default_game_setup()


func after_each():
	game_logic.teardown()
	game_logic.free()


func _fresh():
	after_each()
	before_each()


func _guardian(definition_id: String) -> int:
	var id = give_player_specific_card(player1, definition_id)
	var card = game_logic.card_db.get_card(id)
	player1.remove_card_from_hand(id, true, false)
	player1.add_to_bleach(card)
	return id


func _probe(id: int, timing: String):
	var card = game_logic.card_db.get_card(id)
	card.definition = card.definition.duplicate(true)
	card.definition["effects"].append({
		"timing": timing, "effect_type": StrikeEffects.Choice,
		"choice": [{"effect_type": StrikeEffects.Pass, "_choice_text": "GG检查点继续"}]
	})


func _fight(attack: int, response: int):
	if game_logic.active_turn_player == player1.my_id:
		assert_true(game_logic.do_strike(player1, attack, false, -1))
		assert_true(game_logic.do_strike(player2, response, false, -1))
	else:
		assert_true(game_logic.do_strike(player2, response, false, -1))
		assert_true(game_logic.do_strike(player1, attack, false, -1))


func _begin_guardian(source: int):
	assert_true(player1.is_card_in_bleach(source))
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_choice(player1, 0))
	assert_true(player1.is_card_in_discards(source))
	assert_false(player1.is_card_in_continuous_boosts(source))


func _set_after_guardian(attack: int, response: int):
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))


func _resume_hit_power():
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseSimultaneousEffect)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	var index = -1
	for i in range(game_logic.decision_info.choice.size()):
		if game_logic.decision_info.choice[i]["effect_type"] == StrikeEffects.Powerup:
			index = i
	assert_gte(index, 0)
	assert_true(game_logic.do_choice(player1, index))
	assert_eq(game_logic.get_current_strike_timing(), "hit")
	assert_eq(game_logic.decision_info.choice[0]["_choice_text"], "GG检查点继续")


func test_gg_grasp_attack_all_push_pull_options_and_miss():
	for index in range(4):
		_fresh()
		position_players(player1, 3, player2, 4)
		var attack = give_player_specific_card(player1, "gg_normal_grasp")
		var response = give_player_specific_card(player2, "gg_normal_sweep")
		_fight(attack, response)
		assert_eq(game_logic.get_current_strike_timing(), "hit")
		assert_eq(game_logic.decision_info.player, player1.my_id)
		assert_eq(game_logic.decision_info.choice.size(), 4)
		assert_true(game_logic.do_choice(player1, index))
		assert_eq(player2.arena_location, [5, 6, 2, 1][index])
		assert_eq(player2.life, 97)
		assert_null(game_logic.active_strike)
		assert_true(player1.is_card_in_gauge(attack))
	_fresh()
	position_players(player1, 3, player2, 5)
	var attack = give_player_specific_card(player1, "gg_normal_grasp")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	_fight(attack, response)
	assert_null(game_logic.active_strike)
	assert_eq(player2.life, 100)
	assert_true(player1.is_card_in_discards(attack))


func _grasp_boost(virtual_source: bool, stale: bool = false):
	position_players(player1, 3, player2, 5)
	var source = _guardian("gg_normal_grasp") if virtual_source else give_player_specific_card(player1, "gg_normal_grasp")
	var hand_size = player1.hand.size()
	if virtual_source:
		_begin_guardian(source)
		assert_eq(player1.hand.size(), hand_size + 1, "Guardian Now draws exactly1.")
		if stale:
			player1.remove_card_from_discards(source)
			player1.add_to_hand(game_logic.card_db.get_card(source), true)
	else:
		assert_true(game_logic.do_boost(player1, source))
		assert_eq(player1.hand.size(), hand_size + 1, "Spend boost, draw1 Now, plus ordinary end-turn draw1.")
	var attack = give_player_specific_card(player1, "gg_normal_dust")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	_probe(attack, "hit")
	if virtual_source:
		_set_after_guardian(attack, response)
	else:
		_fight(attack, response)
	_resume_hit_power()
	assert_eq(player1.strike_stat_boosts.power, 1)
	assert_eq(player2.life, 100)
	assert_eq(player1.is_card_in_gauge(source), not stale, "Q6: entity moves at Hit, before damage.")
	assert_eq(player1.is_card_in_hand(source), stale)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player2.life, 94, "Dust5 + unscaled normal boost1.")
	assert_null(game_logic.active_strike)


func test_gg_grasp_normal_boost():
	_grasp_boost(false)


func test_gg_grasp_attack_push_at_both_walls_is_clamped():
	for setup in [[8, 9], [2, 1]]:
		_fresh()
		position_players(player1, setup[0], player2, setup[1])
		var attack = give_player_specific_card(player1, "gg_normal_grasp")
		var response = give_player_specific_card(player2, "gg_normal_sweep")
		_fight(attack, response)
		assert_true(game_logic.do_choice(player1, 1))
		assert_eq(player2.arena_location, setup[1])
		assert_eq(player2.life, 97)
		assert_null(game_logic.active_strike)


func test_gg_grasp_guardian_boost():
	_grasp_boost(true)


func test_gg_grasp_guardian_source_left_discards_still_power_but_no_reclaim():
	_grasp_boost(true, true)


func test_gg_cross_attack_retreat_three_both_directions_and_wall():
	for setup in [[5, 6, 2], [5, 4, 8], [3, 4, 1]]:
		_fresh()
		position_players(player1, setup[0], player2, setup[1])
		var attack = give_player_specific_card(player1, "gg_normal_cross")
		var response = give_player_specific_card(player2, "gg_normal_focus")
		_fight(attack, response)
		assert_null(game_logic.active_strike)
		assert_eq(player1.arena_location, setup[2])
		assert_eq(player2.life, 99)
		assert_eq(player1.life, 100, "After retreat occurs before Focus's range check.")
		assert_true(player1.is_card_in_gauge(attack))


func _cross_boost(virtual_source: bool, pull: bool, far: bool = false, stale: bool = false):
	position_players(player1, 3, player2, 6 if far else 4)
	var source = _guardian("gg_normal_cross") if virtual_source else give_player_specific_card(player1, "gg_normal_cross")
	if virtual_source:
		_begin_guardian(source)
	else:
		assert_true(game_logic.do_boost(player1, source))
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.choice.size(), 2)
	if stale:
		player1.remove_card_from_discards(source)
		player1.add_to_hand(game_logic.card_db.get_card(source), true)
	assert_true(game_logic.do_choice(player1, 1 if pull else 0))
	assert_eq(player2.arena_location, (4 if far else 1) if pull else 6)
	var into_gauge = pull and not far and not stale
	assert_eq(player1.is_card_in_gauge(source), into_gauge)
	assert_eq(player1.is_card_in_hand(source), stale)
	assert_eq(player1.is_card_in_discards(source), not into_gauge and not stale)
	if virtual_source:
		var attack = give_player_specific_card(player1, "gg_normal_dust")
		var response = give_player_specific_card(player2, "gg_normal_focus")
		_set_after_guardian(attack, response)
		assert_null(game_logic.active_strike)
	else:
		if game_logic.game_state == Enums.GameState.GameState_PlayerDecision \
		and game_logic.decision_info.type == Enums.DecisionType.DecisionType_BoostCancel:
			assert_true(into_gauge, "Pulling past generated the Gauge that makes the printed cancel affordable.")
			assert_true(game_logic.do_boost_cancel(player1, [], false))
		assert_null(game_logic.active_boost)
		assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)


func test_gg_cross_normal_boost():
	for setup in [[false, false], [true, false], [true, true]]:
		_fresh()
		_cross_boost(false, setup[0], setup[1])


func test_gg_cross_guardian_boost():
	for setup in [[false, false], [true, false], [true, true]]:
		_fresh()
		_cross_boost(true, setup[0], setup[1])


func test_gg_cross_guardian_invalidated_source_is_not_taken_from_hand():
	_cross_boost(true, true, false, true)


func test_gg_slash_attack_close_hit_advantage_or_shortfall_miss():
	for far in [false, true]:
		_fresh()
		position_players(player1, 3, player2, 7 if far else 6)
		var attack = give_player_specific_card(player1, "gg_normal_slash")
		var response = give_player_specific_card(player2, "gg_normal_focus")
		game_logic.get_latest_events()
		_fight(attack, response)
		assert_eq(player1.arena_location, 5)
		assert_eq(player2.life, 100 if far else 98)
		assert_null(game_logic.active_strike)
		var events = game_logic.get_latest_events()
		if far:
			validate_not_has_event(events, Enums.EventType.EventType_Strike_GainAdvantage, player1)
		else:
			validate_has_event(events, Enums.EventType.EventType_Strike_GainAdvantage, player1)


func _slash_boost(virtual_source: bool):
	position_players(player1, 3, player2, 5)
	var source = _guardian("gg_normal_slash") if virtual_source else give_player_specific_card(player1, "gg_normal_slash")
	if virtual_source:
		give_gauge(player1, 1)
		_begin_guardian(source)
	else:
		assert_true(game_logic.do_boost(player1, source))
	assert_eq(player1.arena_location, 7, "Advance3 skips the opponent's occupied space; guardian is not4.")
	assert_true(player1.is_card_in_discards(source))
	if virtual_source:
		assert_ne(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostCancel)
		var attack = give_player_specific_card(player1, "gg_normal_focus")
		var response = give_player_specific_card(player2, "gg_normal_focus")
		_set_after_guardian(attack, response)
		assert_null(game_logic.active_strike)
	else:
		assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)


func test_gg_slash_normal_boost():
	_slash_boost(false)


func test_gg_slash_guardian_boost():
	_slash_boost(true)


func test_gg_dive_attack_cross_dodges_but_not_crossed_does_not():
	for setup in [[3, 6, 7, 97, 100], [3, 5, 7, 100, 100], [3, 8, 6, 100, 96]]:
		_fresh()
		position_players(player1, setup[0], player2, setup[1])
		var attack = give_player_specific_card(player1, "gg_normal_dive")
		var response = give_player_specific_card(player2, "gg_normal_focus")
		_fight(attack, response)
		assert_null(game_logic.active_strike)
		assert_eq(player1.arena_location, setup[2])
		assert_eq(player2.life, setup[3])
		assert_eq(player1.life, setup[4])


func _dive_boost(virtual_source: bool, has_target: bool):
	var target = -1
	if has_target:
		target = give_player_specific_card(player2, "gg_normal_grasp")
		player2.remove_card_from_hand(target, true, false)
		player2.add_to_continuous_boosts(game_logic.card_db.get_card(target))
	var source = _guardian("gg_normal_dive") if virtual_source else give_player_specific_card(player1, "gg_normal_dive")
	if virtual_source:
		_begin_guardian(source)
	else:
		assert_true(game_logic.do_boost(player1, source))
	if has_target:
		assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseDiscardContinuousBoost)
		assert_eq(game_logic.decision_info.player, player1.my_id)
		assert_false(game_logic.decision_info.can_pass)
		assert_true(game_logic.do_boost_name_card_choice_effect(player1, target))
		assert_false(player2.is_card_in_continuous_boosts(target))
		assert_true(player2.is_card_in_discards(target))
	assert_true(player1.is_card_in_discards(source))
	if virtual_source:
		position_players(player1, 3, player2, 5)
		var attack = give_player_specific_card(player1, "gg_normal_dust")
		var response = give_player_specific_card(player2, "gg_normal_focus")
		_set_after_guardian(attack, response)
		assert_null(game_logic.active_strike)
	else:
		assert_null(game_logic.active_boost)


func test_gg_dive_normal_boost():
	for has_target in [true, false]:
		_fresh()
		_dive_boost(false, has_target)


func test_gg_dive_guardian_boost():
	for has_target in [true, false]:
		_fresh()
		_dive_boost(true, has_target)


func test_gg_dive_guardian_cannot_target_opponents_virtual_continuous_boost():
	var own_source = _guardian("gg_normal_dive")
	var enemy_source = give_player_specific_card(player2, "gg_normal_dust")
	player2.remove_card_from_hand(enemy_source, true, false)
	player2.add_to_bleach(game_logic.card_db.get_card(enemy_source))
	assert_true(game_logic.do_prepare(player1), "Legally pass the turn before the opponent initiates.")
	game_logic.get_latest_events()
	assert_true(game_logic.do_strike(player2, -1, false, -1))
	assert_eq(game_logic.decision_info.player, player2.my_id)
	assert_true(game_logic.do_choice(player2, 0))
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_choice(player1, 0))
	assert_ne(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseDiscardContinuousBoost)
	assert_eq(player1.continuous_boosts.size(), 0)
	assert_eq(player2.continuous_boosts.size(), 0)
	assert_eq(game_logic.active_strike.heiqiyihu_guardian_records.size(), 2)
	validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Boost_DiscardContinuousChoice, player1)
	position_players(player1, 3, player2, 5)
	var attack = give_player_specific_card(player2, "gg_normal_focus")
	var response = give_player_specific_card(player1, "gg_normal_dust")
	assert_true(game_logic.do_strike(player2, attack, false, -1))
	assert_true(game_logic.do_strike(player1, response, false, -1))
	assert_null(game_logic.active_strike)
	assert_true(player1.is_card_in_discards(own_source))
	assert_true(player2.is_card_in_discards(enemy_source))


func test_gg_dust_attack_ignores_armor_and_guard():
	position_players(player1, 3, player2, 5)
	var attack = give_player_specific_card(player1, "gg_normal_dust")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	var hand_size = player2.hand.size()
	game_logic.get_latest_events()
	_fight(attack, response)
	assert_null(game_logic.active_strike)
	assert_eq(player2.life, 95)
	assert_eq(player1.life, 100)
	assert_eq(player2.hand.size(), hand_size - 1, "Stunned Focus never draws its After card.")
	validate_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Strike_Stun, player2)


func _dust_boost(virtual_source: bool):
	position_players(player1, 3, player2, 5)
	var source = _guardian("gg_normal_dust") if virtual_source else give_player_specific_card(player1, "gg_normal_dust")
	if virtual_source:
		_begin_guardian(source)
	else:
		assert_true(game_logic.do_boost(player1, source))
	var attack = give_player_specific_card(player1, "gg_normal_block")
	var response = give_player_specific_card(player2, "gg_normal_sweep")
	if virtual_source:
		_set_after_guardian(attack, response)
	else:
		_fight(attack, response)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ForceForArmor)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.get_total_guard(player1), 7, "Block3 + normal/guardian4, not5.")
	assert_true(game_logic.do_force_for_armor(player1, []))
	assert_null(game_logic.active_strike)
	assert_eq(player1.life, 96, "Sweep6 minus armor2 is below guard7.")
	assert_true(player1.is_card_in_gauge(attack))
	if virtual_source:
		assert_true(player1.is_card_in_discards(source))
		assert_false(player1.is_card_in_gauge(source))
	else:
		assert_true(player1.is_card_in_discards(source), "Unsustained normal boost leaves at battle Cleanup before the next turn.")
	var next_attack = give_player_specific_card(player1, "gg_normal_block")
	var next_response = give_player_specific_card(player2, "gg_normal_sweep")
	_fight(next_attack, next_response)
	assert_eq(game_logic.get_total_guard(player1), 3, "Next strike has no remaining boost.")
	assert_true(game_logic.do_force_for_armor(player1, []))
	assert_null(game_logic.active_strike)
	assert_true(player1.is_card_in_discards(next_attack), "Damage4 exceeds unboosted guard3, skips After.")


func test_gg_dust_normal_boost():
	_dust_boost(false)


func test_gg_dust_normal_boost_survives_non_strike_to_next_own_turn_gauge():
	var source = give_player_specific_card(player1, "gg_normal_dust")
	assert_true(game_logic.do_boost(player1, source))
	assert_true(player1.is_card_in_continuous_boosts(source))
	assert_true(game_logic.do_prepare(player2))
	if game_logic.game_state == Enums.GameState.GameState_DiscardDownToMax:
		var ids = player2.hand.slice(0, player2.hand.size() - 7).map(func(card): return card.id)
		assert_true(game_logic.do_discard_to_max(player2, ids))
	assert_eq(game_logic.active_turn_player, player1.my_id)
	assert_true(player1.is_card_in_gauge(source))
	assert_false(player1.is_card_in_continuous_boosts(source))


func test_gg_dust_guardian_boost():
	_dust_boost(true)


func test_gg_sweep_attack_discards_one_random_before_opponents_after_draw():
	position_players(player1, 3, player2, 5)
	var attack = give_player_specific_card(player1, "gg_normal_sweep")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	_probe(response, "before")
	var hand_size = player2.hand.size()
	var legal_ids = player2.hand.filter(func(card): return card.id != response).map(func(card): return card.id)
	_fight(attack, response)
	assert_eq(game_logic.decision_info.player, player2.my_id)
	assert_eq(game_logic.get_current_strike_timing(), "before")
	assert_eq(player2.hand.size(), hand_size - 2)
	assert_eq(player2.discards.size(), 1)
	assert_true(player2.discards[0].id in legal_ids)
	assert_eq(player2.life, 96)
	assert_true(game_logic.do_choice(player2, 0))
	assert_eq(player2.hand.size(), hand_size - 1, "Focus After then draws1.")
	assert_null(game_logic.active_strike)


func _sweep_boost(virtual_source: bool, already_ex: bool):
	position_players(player1, 3, player2, 5)
	var source = _guardian("gg_normal_sweep") if virtual_source else give_player_specific_card(player1, "gg_normal_sweep")
	if virtual_source:
		_begin_guardian(source)
	else:
		assert_true(game_logic.do_boost(player1, source))
	var attack = give_player_specific_card(player1, "gg_normal_dust")
	var ex_id = give_player_specific_card(player1, "gg_normal_dust") if already_ex else -1
	var response = give_player_specific_card(player2, "gg_normal_focus")
	_probe(attack, "before")
	if virtual_source:
		assert_true(game_logic.do_strike(player1, attack, false, ex_id))
		assert_true(game_logic.do_strike(player2, response, false, -1))
	else:
		assert_true(game_logic.do_strike(player2, response, false, -1))
		assert_true(game_logic.do_strike(player1, attack, false, ex_id))
	assert_true(player1.strike_stat_boosts.is_ex)
	assert_eq(game_logic.get_total_power(player1), 6)
	assert_eq(game_logic.get_total_speed(player1), 4)
	assert_eq(game_logic.get_total_armor(player1), 1)
	assert_eq(game_logic.get_total_guard(player1), 5)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player2.life, 94)
	assert_null(game_logic.active_strike)
	assert_true(player1.is_card_in_discards(source))
	if already_ex:
		assert_true(player1.is_card_in_discards(ex_id))


func test_gg_sweep_normal_boost():
	for already_ex in [false, true]:
		_fresh()
		_sweep_boost(false, already_ex)


func test_gg_sweep_guardian_boost():
	for already_ex in [false, true]:
		_fresh()
		_sweep_boost(true, already_ex)


func test_gg_focus_attack_push_immune_and_after_draw_one():
	for index in [0, 3]:
		_fresh()
		position_players(player1, 3, player2, 4)
		var attack = give_player_specific_card(player1, "gg_normal_focus")
		var response = give_player_specific_card(player2, "gg_normal_grasp")
		var hand_size = player1.hand.size()
		_fight(attack, response)
		assert_eq(game_logic.decision_info.player, player2.my_id)
		assert_true(game_logic.do_choice(player2, index))
		assert_null(game_logic.active_strike)
		assert_eq(player1.arena_location, 3)
		assert_eq(player1.life, 99)
		assert_eq(player1.hand.size(), hand_size)
		assert_true(player1.is_card_in_gauge(attack))


func _focus_boost(virtual_source: bool):
	position_players(player1, 3, player2, 5)
	var source = _guardian("gg_normal_focus") if virtual_source else give_player_specific_card(player1, "gg_normal_focus")
	if virtual_source:
		_begin_guardian(source)
	else:
		assert_true(game_logic.do_boost(player1, source))
		assert_null(game_logic.active_strike, "Q1: normal Scramble does not initiate on its own.")
		assert_true(game_logic.do_prepare(player2))
		if game_logic.game_state == Enums.GameState.GameState_DiscardDownToMax:
			var ids = player2.hand.slice(0, player2.hand.size() - 7).map(func(card): return card.id)
			assert_true(game_logic.do_discard_to_max(player2, ids))
	var wild = set_player_topdeck(player2, "gg_normal_focus")
	var attack = give_player_specific_card(player1, "gg_normal_dust")
	_probe(attack, "before")
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_eq(game_logic.active_strike.defender_card.id, wild)
	assert_true(game_logic.active_strike.defender_wild_strike)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_choice(player1, 0))
	assert_null(game_logic.active_strike)
	assert_eq(player2.life, 95)
	assert_true(player1.is_card_in_discards(source))


func test_gg_focus_normal_boost():
	_focus_boost(false)


func test_gg_focus_guardian_boost():
	_focus_boost(true)


func test_gg_focus_guardian_defending_does_not_force_initiator_wild():
	var source = give_player_specific_card(player2, "gg_normal_focus")
	player2.remove_card_from_hand(source, true, false)
	player2.add_to_bleach(game_logic.card_db.get_card(source))
	position_players(player1, 3, player2, 5)
	var attack = give_player_specific_card(player1, "gg_normal_dust")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	_probe(attack, "before")
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	assert_true(game_logic.do_choice(player2, 0))
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_false(game_logic.active_strike.initiator_wild_strike)
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_false(game_logic.active_strike.defender_wild_strike)
	assert_true(game_logic.do_choice(player1, 0))
	assert_null(game_logic.active_strike)


func test_gg_block_attack_zero_power_optional_armor_and_after_gauge():
	for paid_force in [0, 1]:
		_fresh()
		position_players(player1, 3, player2, 5)
		var attack = give_player_specific_card(player1, "gg_normal_block")
		var response = give_player_specific_card(player2, "gg_normal_focus")
		var payment = [give_player_specific_card(player1, "gg_normal_grasp")] if paid_force else []
		_fight(attack, response)
		assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ForceForArmor)
		assert_eq(game_logic.decision_info.player, player1.my_id)
		assert_eq(game_logic.get_total_power(player1), 0)
		assert_true(game_logic.do_force_for_armor(player1, payment))
		assert_null(game_logic.active_strike)
		assert_eq(player2.life, 100)
		assert_eq(player1.life, 100 if paid_force else 98)
		assert_true(player1.is_card_in_gauge(attack), "After sends Block to Gauge despite no hit.")


func test_gg_block_attack_stunned_skips_after_gauge():
	position_players(player1, 3, player2, 5)
	var attack = give_player_specific_card(player1, "gg_normal_block")
	var response = give_player_specific_card(player2, "gg_normal_dust")
	_fight(attack, response)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_force_for_armor(player1, []))
	assert_null(game_logic.active_strike)
	assert_eq(player1.life, 95)
	assert_true(player1.is_card_in_discards(attack))
	assert_false(player1.is_card_in_gauge(attack))


func _block_boost(virtual_source: bool, present: bool):
	player2.sealed.append_array(player2.hand)
	player2.hand.clear()
	var named = give_player_specific_card(player2, "gg_normal_grasp")
	var missing = give_player_specific_card(player1, "gg_normal_focus")
	var source = _guardian("gg_normal_block") if virtual_source else give_player_specific_card(player1, "gg_normal_block")
	if virtual_source:
		_begin_guardian(source)
	else:
		assert_true(game_logic.do_boost(player1, source))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_NameCard_OpponentDiscards)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.decision_info.amount, 1)
	game_logic.get_latest_events()
	assert_true(game_logic.do_boost_name_card_choice_effect(player1, named if present else missing))
	assert_eq(player2.is_card_in_discards(named), present)
	assert_eq(player2.is_card_in_hand(named), not present)
	var events = game_logic.get_latest_events()
	if not present:
		validate_has_event(events, Enums.EventType.EventType_RevealHand, player2)
	assert_true(player1.is_card_in_discards(source))
	if virtual_source:
		position_players(player1, 3, player2, 5)
		var attack = give_player_specific_card(player1, "gg_normal_dust")
		var response = give_player_specific_card(player2, "gg_normal_focus")
		_probe(attack, "before")
		_set_after_guardian(attack, response)
		assert_eq(player1.strike_stat_boosts.when_hit_force_for_armor, "")
		assert_true(game_logic.do_choice(player1, 0))
		assert_null(game_logic.active_strike)
	else:
		assert_null(game_logic.active_boost)


func test_gg_block_normal_boost():
	for present in [true, false]:
		_fresh()
		_block_boost(false, present)


func test_gg_block_guardian_boost():
	for present in [true, false]:
		_fresh()
		_block_boost(true, present)
