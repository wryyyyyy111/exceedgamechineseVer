extends ExceedGutTest

const PREFIX = "yuanliuzhai_"

func who_am_i():
	return "yuanliuzhai"

func _pressure(owner: Player, definition_id: String) -> int:
	var id = give_player_specific_card(owner, definition_id)
	var card = game_logic.card_db.get_card(id)
	owner.remove_card_from_hand(id, true, false)
	owner.add_to_bleach(card)
	return id

func _burn(owner: Player) -> bool:
	return game_logic.is_effect_condition_met(owner, {"condition": "yuanliuzhai_has_burn"}, null)

func _attack(definition_id: String, opponent_definition: String = "standard_normal_focus",
		payment: Array = [], opposing_guard: int = -1) -> int:
	var attack_id = give_player_specific_card(player1, PREFIX + definition_id)
	var response_id = give_player_specific_card(player2, opponent_definition)
	if opposing_guard >= 0:
		game_logic.card_db.get_card(response_id).definition["guard"] = opposing_guard
	assert_true(game_logic.do_strike(player1, attack_id, false, -1))
	assert_true(game_logic.do_strike(player2, response_id, false, -1))
	_finish_strike(payment)
	return attack_id

func _finish_strike(payment: Array = []):
	for step in range(20):
		if game_logic.game_state != Enums.GameState.GameState_PlayerDecision:
			return
		var info = game_logic.decision_info
		var chooser = game_logic._get_player(info.player)
		match info.type:
			Enums.DecisionType.DecisionType_PayStrikeCost_Required, Enums.DecisionType.DecisionType_PayStrikeCost_CanWild:
				assert_eq(chooser, player1)
				assert_true(game_logic.do_pay_strike_cost(chooser, payment, false))
			Enums.DecisionType.DecisionType_ChooseSimultaneousEffect:
				assert_true(game_logic.do_choice(chooser, 0))
			_:
				fail_test("Unexpected strike decision: %s" % Enums.DecisionType.keys()[info.type])
				return
	fail_test("Strike did not finish within 20 decisions")

func _event_numbers(events: Array, event_type, owner: Player) -> Array:
	var numbers = []
	for event in events:
		if event["event_type"] == event_type and event["event_player"] == owner.my_id:
			numbers.append(event["number"])
	return numbers

func test_runtime_definitions_and_attack_costs():
	var deck = CardDataManager.get_deck_from_str_id(who_am_i())
	assert_eq(deck["cards"].size(), 30)
	assert_eq(deck["custom_card_definitions"].size(), 7)
	assert_eq(deck["exceed_cost"], 3)
	assert_eq(player1.life, 30)
	assert_eq(player1.get_bleach_zone_name(), "威压区")
	assert_false(player1.is_bleach_zone_facedown())
	var expected = {
		"jokaku_enjo": [0, 2, 2, 4, 4, 4],
		"ryujin_jakka": [0, 2, 1, 3, 5, 4],
		"sokotsu": [0, 1, 1, 1, 4, 6],
		"netsu_jigoku": [0, 0, "X", "X", 4, 5],
		"nadegiri": [0, 0, 1, 1, 4, 5],
		"onibi": [0, 0, 1, 1, 5, 4],
		"ikkotsu": [0, 0, 1, 1, 3, 5],
	}
	for suffix in expected:
		var definition = CardDataManager.get_card(PREFIX + suffix)
		var fields = ["force_cost", "gauge_cost", "range_min", "range_max", "power", "speed"]
		for index in range(fields.size()):
			assert_eq(definition[fields[index]], expected[suffix][index], suffix + " " + fields[index])
		assert_eq(definition["armor"], 0)
		assert_eq(definition["guard"], 0)
		for effect in definition["effects"]:
			if effect["effect_type"] == "pull_not_past":
				assert_eq(GameStrings.get_effect_text(effect), "[b]击中：[/b] 缺失效果", "Current pull_not_past text baseline")
			else:
				assert_false(GameStrings.get_effect_text(effect).contains("缺失"), suffix)
	for entry in deck["cards"].slice(14):
		assert_true(entry["definition_id"].begins_with("gg_normal_"))

func test_pressure_type_union():
	var id = give_player_specific_card(player1, PREFIX + "ikkotsu")
	var card = game_logic.card_db.get_card(id)
	assert_false(_burn(player1))
	assert_eq(game_logic.get_total_power(player1, false, card), 3)
	_pressure(player1, "gg_normal_grasp")
	assert_true(_burn(player1))
	assert_eq(game_logic.get_total_power(player1, false, card), 3)
	_pressure(player1, PREFIX + "nadegiri")
	_pressure(player1, PREFIX + "onibi")
	assert_eq(game_logic.get_total_power(player1, false, card), 4)
	_pressure(player1, PREFIX + "sokotsu")
	_pressure(player1, PREFIX + "ryujin_jakka")
	assert_eq(game_logic.get_total_power(player1, false, card), 6)
	assert_false(_burn(player2))
	player1.strike_stat_boosts.power_bonus_multiplier_positive_only = 2
	assert_eq(game_logic.get_total_power(player1, false, card), 9)

func test_normal_cleanup_pressure():
	var discarded = _pressure(player1, PREFIX + "nadegiri")
	var protected_id = _pressure(player1, PREFIX + "jokaku_enjo")
	player1.yuanliuzhai_pressure_protected_ids.append(protected_id)
	game_logic.handle_strike_effect(-1, {"effect_type": "yuanliuzhai_discard_pressure"}, player1)
	assert_true(player1.is_card_in_discards(discarded))
	assert_true(player1.is_card_in_bleach(protected_id))
	assert_ne(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)

func _assert_pressure_cleanup_timing(exceeded: bool, defending: bool):
	if defending:
		advance_turn(player1)
	player1.exceeded = exceeded
	var pressure_id = _pressure(player1, PREFIX + "nadegiri")
	position_players(player1, 3, player2, 5)
	var attack_id = give_player_specific_card(player1, "standard_normal_sweep")
	var attack = game_logic.card_db.get_card(attack_id)
	attack.definition = attack.definition.duplicate(true)
	attack.definition["effects"] = [
		{"timing": "before", "effect_type": "choice", "choice": [{"effect_type": "pass"}]},
		{"timing": "after", "effect_type": "choice", "choice": [{"effect_type": "pass"}]}
	]
	var response_id = give_player_specific_card(player2, "standard_normal_focus")
	game_logic.get_latest_events()
	if defending:
		assert_true(game_logic.do_strike(player2, response_id, false, -1))
		assert_true(game_logic.do_strike(player1, attack_id, false, -1))
	else:
		assert_true(game_logic.do_strike(player1, attack_id, false, -1))
		assert_true(game_logic.do_strike(player2, response_id, false, -1))
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.active_strike.strike_state, game_logic.StrikeState.StrikeState_Card1_Before)
	assert_true(player1.is_card_in_bleach(pressure_id), "Pressure must remain before attack resolution")
	assert_true(_burn(player1))
	assert_eq(game_logic.get_total_power(player1), 7)
	var hand_size = player1.hand.size()
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(game_logic.active_strike.strike_state, game_logic.StrikeState.StrikeState_Card1_After)
	assert_true(player1.is_card_in_bleach(pressure_id), "Pressure must remain through hit and damage")
	assert_eq(player1.hand.size(), hand_size, "Exceed cleanup draw must not happen before cleanup")
	assert_eq(player2.life, 25, "Pressure power applies to damage before it is discarded")
	assert_true(game_logic.do_choice(player1, 0))
	assert_true(player1.is_card_in_discards(pressure_id))
	assert_false(player1.is_card_in_bleach(pressure_id))
	assert_eq(player1.hand.size(), hand_size + (1 if exceeded else 0))
	var events = game_logic.get_latest_events()
	var damage_index = -1
	var discard_index = -1
	for index in range(events.size()):
		var event = events[index]
		if event["event_type"] == Enums.EventType.EventType_Strike_TookDamage and event["event_player"] == player2.my_id:
			damage_index = index
		if event["event_type"] == Enums.EventType.EventType_AddToDiscard and event["number"] == pressure_id:
			discard_index = index
	assert_gte(damage_index, 0)
	assert_gt(discard_index, damage_index, "Pressure discard event must follow attack damage")

func test_pressure_cleanup_timing_normal_initiator():
	_assert_pressure_cleanup_timing(false, false)

func test_pressure_cleanup_timing_normal_defender():
	_assert_pressure_cleanup_timing(false, true)

func test_pressure_cleanup_timing_exceeded_initiator():
	_assert_pressure_cleanup_timing(true, false)

func test_pressure_cleanup_timing_exceeded_defender():
	_assert_pressure_cleanup_timing(true, true)

func test_jokaku_normal_turn_start_preserves_once():
	var id = _pressure(player1, PREFIX + "jokaku_enjo")
	var other_id = _pressure(player1, PREFIX + "nadegiri")
	player1.yuanliuzhai_pressure_protected_ids.append(id)
	game_logic.handle_strike_effect(-1, {"effect_type": "yuanliuzhai_start_turn"}, player1)
	assert_true(player1.is_card_in_bleach(id))
	assert_false(player1.is_card_in_gauge(id))
	assert_true(player1.is_card_in_gauge(other_id))
	assert_eq(player1.bleach_zone.size(), 1)
	assert_true(player1.yuanliuzhai_pressure_protected_ids.is_empty())
	assert_false(player1.is_card_in_discards(id))
	assert_ne(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)

func test_jokaku_retained_pressure_discards_on_next_cleanup():
	var id = _pressure(player1, PREFIX + "jokaku_enjo")
	player1.yuanliuzhai_pressure_protected_ids.append(id)
	game_logic.handle_strike_effect(-1, {"effect_type": "yuanliuzhai_start_turn"}, player1)
	assert_true(player1.is_card_in_bleach(id))
	assert_true(player1.yuanliuzhai_pressure_protected_ids.is_empty())
	game_logic.handle_strike_effect(-1, {"effect_type": "yuanliuzhai_discard_pressure"}, player1)
	assert_true(player1.is_card_in_discards(id))
	assert_false(player1.is_card_in_bleach(id))
	assert_false(player1.is_card_in_gauge(id))

func test_jokaku_protection_expires_only_after_own_turn_start():
	var id = _pressure(player1, PREFIX + "jokaku_enjo")
	player1.yuanliuzhai_pressure_protected_ids.append(id)
	advance_turn(player1)
	assert_true(player1.is_card_in_bleach(id))
	assert_has(player1.yuanliuzhai_pressure_protected_ids, id)
	advance_turn(player2)
	assert_eq(game_logic.active_turn_player, player1.my_id)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	assert_true(player1.is_card_in_bleach(id))
	assert_false(player1.is_card_in_gauge(id))
	assert_true(player1.yuanliuzhai_pressure_protected_ids.is_empty())
	advance_turn(player1)
	assert_true(player1.is_card_in_bleach(id))
	advance_turn(player2)
	assert_eq(game_logic.active_turn_player, player1.my_id)
	assert_true(player1.is_card_in_gauge(id))
	assert_false(player1.is_card_in_bleach(id))
	assert_false(player1.is_card_in_discards(id))

func test_exceed_cleanup_draw():
	player1.exceeded = true
	var count = player1.hand.size()
	game_logic.handle_strike_effect(-1, {"effect_type": "yuanliuzhai_exceed_discard_pressure"}, player1)
	assert_eq(player1.hand.size(), count)
	var protected_id = _pressure(player1, PREFIX + "jokaku_enjo")
	player1.yuanliuzhai_pressure_protected_ids.append(protected_id)
	game_logic.handle_strike_effect(-1, {"effect_type": "yuanliuzhai_exceed_discard_pressure"}, player1)
	assert_eq(player1.hand.size(), count)
	var discarded = _pressure(player1, PREFIX + "nadegiri")
	game_logic.handle_strike_effect(-1, {"effect_type": "yuanliuzhai_exceed_discard_pressure"}, player1)
	assert_eq(player1.hand.size(), count + 1)
	assert_true(player1.is_card_in_discards(discarded))
	assert_true(player1.is_card_in_bleach(protected_id))

func test_jokaku_protection_across_exceed():
	var id = _pressure(player1, PREFIX + "jokaku_enjo")
	player1.yuanliuzhai_pressure_protected_ids.append(id)
	player1.exceeded = true
	game_logic.handle_strike_effect(-1, {"effect_type": "yuanliuzhai_start_turn"}, player1)
	assert_true(player1.is_card_in_bleach(id))
	assert_true(player1.yuanliuzhai_pressure_protected_ids.is_empty())
	assert_false(player1.is_card_in_gauge(id))
	var count = player1.hand.size()
	game_logic.handle_strike_effect(-1, {"effect_type": "yuanliuzhai_exceed_discard_pressure"}, player1)
	assert_true(player1.is_card_in_discards(id))
	assert_eq(player1.hand.size(), count + 1)

func test_pressure_action():
	_assert_pressure_action_draw()

func test_exceeded_pressure_action():
	player1.exceeded = true
	_assert_pressure_action_draw()

func _assert_pressure_action_draw():
	assert_true(player1.can_do_character_action(0))
	var action_text = GameStrings.get_effect_text(player1.get_character_action(0)["effect"])
	assert_false(action_text.contains("缺失"))
	var hand_size = player1.hand.size()
	var deck_size = player1.deck.size()
	var action_draws = 0 if player1.exceeded else 1
	var id = player1.hand[0].id if player1.exceeded else player1.deck[0].id
	assert_true(game_logic.do_character_action(player1, []))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_CardFromHandToGauge)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.decision_info.destination, "bleach")
	assert_eq(game_logic.decision_info.effect["min_amount"], 1)
	assert_eq(game_logic.decision_info.effect["max_amount"], 1)
	assert_eq(player1.hand.size(), hand_size + action_draws, "Only the normal-side action draws before choosing")
	assert_eq(player1.deck.size(), deck_size - action_draws)
	assert_true(player1.is_card_in_hand(id), "The selected card must be in hand before entering pressure")
	assert_true(game_logic.do_relocate_card_from_hand(player1, [id]))
	assert_true(player1.is_card_in_bleach(id))
	assert_false(player1.is_card_in_hand(id))
	assert_eq(player1.hand.size(), hand_size + action_draws, "Place one card, then draw one at turn end")
	assert_eq(player1.deck.size(), deck_size - action_draws - 1)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	assert_eq(game_logic.active_turn_player, player2.my_id)
	assert_false(player1.can_do_character_action(0))
	player1.remove_card_from_bleach(id)
	player1.add_to_discards(game_logic.card_db.get_card(id))
	player1.discard(player1.hand.map(func(card): return card.id))
	assert_false(player1.can_do_character_action(0))

func test_jokaku_attack():
	position_players(player1, 3, player2, 6)
	_pressure(player1, "gg_normal_grasp")
	var payment = give_gauge(player1, 3)
	var id = _attack("jokaku_enjo", "standard_normal_dive", payment)
	assert_eq(player2.arena_location, 6, "Opponent's advance must be blocked")
	assert_false(player2.cannot_move, "Movement lock ends with the strike")
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_Strike_GainAdvantage, player1)
	assert_eq(game_logic.active_turn_player, player1.my_id)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	assert_true(player1.is_card_in_bleach(id), "Protection also skips the turn-start gauge transfer after advantage")
	assert_false(player1.is_card_in_gauge(id))
	assert_true(player1.yuanliuzhai_pressure_protected_ids.is_empty())
	assert_false(player1.is_card_in_discards(id))

func test_jokaku_attack_without_burn_does_not_protect():
	position_players(player1, 3, player2, 6)
	var id = _attack("jokaku_enjo", "standard_normal_dive", give_gauge(player1, 3))
	assert_true(player1.is_card_in_gauge(id))
	assert_false(player1.is_card_in_bleach(id))
	assert_true(player1.yuanliuzhai_pressure_protected_ids.is_empty())
	validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Strike_GainAdvantage, player1)

func test_ryujin_attack_executes_below_six():
	position_players(player1, 3, player2, 6)
	_pressure(player1, "gg_normal_grasp")
	player2.life = 10
	_attack("ryujin_jakka", "standard_normal_grasp", give_gauge(player1, 2))
	assert_true(game_logic.game_over)
	assert_lte(player2.life, 0)
	validate_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Strike_TookDamage, player2, 99)

func test_ryujin_attack_six_is_not_below_six():
	position_players(player1, 3, player2, 6)
	_pressure(player1, "gg_normal_grasp")
	player2.life = 11
	_attack("ryujin_jakka", "standard_normal_grasp", give_gauge(player1, 2))
	assert_false(game_logic.game_over)
	assert_eq(player2.life, 6)

func test_ryujin_attack_miss_does_not_execute():
	position_players(player1, 3, player2, 7)
	_pressure(player1, "gg_normal_grasp")
	player2.life = 5
	_attack("ryujin_jakka", "standard_normal_grasp", give_gauge(player1, 2))
	assert_false(game_logic.game_over)
	assert_eq(player2.life, 5)

func test_ryujin_attack_without_burn_does_not_execute():
	position_players(player1, 3, player2, 6)
	player2.life = 10
	_attack("ryujin_jakka", "standard_normal_grasp", give_gauge(player1, 2))
	assert_false(game_logic.game_over)
	assert_eq(player2.life, 5)

func test_sokotsu_attack_ignores_armor_and_closes():
	position_players(player1, 3, player2, 5)
	_pressure(player1, "gg_normal_grasp")
	_attack("sokotsu", "standard_normal_focus", give_gauge(player1, 1))
	assert_eq(player1.arena_location, 4)
	assert_eq(player2.life, 26, "Focus armor must not absorb damage")

func test_sokotsu_attack_without_burn_does_not_close():
	position_players(player1, 6, player2, 4)
	_attack("sokotsu", "standard_normal_focus", give_gauge(player1, 1))
	assert_eq(player1.arena_location, 6)
	assert_eq(player2.life, 30)

func test_netsu_jigoku_attack_reveal_and_before_range():
	position_players(player1, 3, player2, 5)
	_pressure(player1, "gg_normal_grasp")
	var id = give_player_specific_card(player1, PREFIX + "netsu_jigoku")
	game_logic.card_db.get_card(id).definition["guard"] = 99
	var response = give_player_specific_card(player2, "standard_normal_cross")
	assert_true(game_logic.do_strike(player1, id, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	_finish_strike()
	assert_eq(_event_numbers(game_logic.get_latest_events(), Enums.EventType.EventType_Strike_SetX, player1), [2, 5])
	assert_eq(player2.life, 26)
	assert_eq(player2.arena_location, 5, "Pull 3 brings opponent back without crossing")

func test_netsu_jigoku_attack_without_burn_does_not_refresh_x():
	position_players(player1, 3, player2, 5)
	var id = give_player_specific_card(player1, PREFIX + "netsu_jigoku")
	game_logic.card_db.get_card(id).definition["guard"] = 99
	var response = give_player_specific_card(player2, "standard_normal_cross")
	assert_true(game_logic.do_strike(player1, id, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	_finish_strike()
	assert_eq(_event_numbers(game_logic.get_latest_events(), Enums.EventType.EventType_Strike_SetX, player1), [2])
	assert_eq(player2.life, 30)
	assert_eq(player2.arena_location, 8)

func _assert_netsu_jigoku_pull(attacker_space: int, defender_space: int, expected_space: int):
	position_players(player1, attacker_space, player2, defender_space)
	_attack("netsu_jigoku", "standard_normal_sweep")
	assert_eq(player1.arena_location, attacker_space)
	assert_eq(player2.arena_location, expected_space)
	assert_eq(player2.life, 26, "The attack still hits before pulling the opponent")

func test_netsu_jigoku_pull_stops_adjacent_on_right():
	_assert_netsu_jigoku_pull(3, 5, 4)

func test_netsu_jigoku_pull_stops_adjacent_on_left():
	_assert_netsu_jigoku_pull(7, 5, 6)

func test_netsu_jigoku_pull_does_not_move_adjacent_opponent():
	_assert_netsu_jigoku_pull(3, 4, 4)

func test_netsu_jigoku_pull_moves_full_three_spaces_at_long_range():
	_assert_netsu_jigoku_pull(1, 9, 6)

func test_ordinary_pull_can_still_cross():
	position_players(player1, 4, player2, 6)
	game_logic.handle_strike_effect(-1, {"effect_type": "pull", "amount": 3}, player1)
	assert_eq(player2.arena_location, 2)

func test_nadegiri_attack_burn_speed():
	position_players(player1, 3, player2, 4)
	_pressure(player1, "gg_normal_grasp")
	_attack("nadegiri", "standard_normal_grasp")
	assert_eq(player2.life, 26)
	assert_eq(player1.life, 30, "Speed 7 wins the initiator tie and stuns Grasp")

func test_nadegiri_attack_without_burn_is_slower():
	position_players(player1, 3, player2, 4)
	_attack("nadegiri", "standard_normal_cross")
	assert_eq(player1.life, 27)
	assert_eq(player2.life, 30)

func test_onibi_attack_is_free_and_ignores_guard():
	position_players(player1, 3, player2, 4)
	_pressure(player1, "gg_normal_grasp")
	var payment = give_player_specific_card(player1, "gg_normal_grasp")
	_attack("onibi", "standard_normal_focus")
	assert_true(player1.is_card_in_hand(payment), "The free attack does not discard a force payment")
	assert_eq(player2.life, 27)
	assert_eq(player1.life, 30, "Damage below Focus guard still stuns")

func test_onibi_attack_without_burn_keeps_guard():
	position_players(player1, 3, player2, 4)
	var payment = give_player_specific_card(player1, "gg_normal_grasp")
	_attack("onibi", "standard_normal_focus", [payment])
	assert_eq(player1.life, 26)
	assert_eq(player2.life, 27)

func test_ikkotsu_attack_advance_and_burn_push():
	position_players(player1, 3, player2, 5)
	_pressure(player1, "gg_normal_grasp")
	_attack("ikkotsu", "standard_normal_grasp")
	assert_eq(player1.arena_location, 4)
	assert_eq(player2.arena_location, 8)
	assert_eq(player2.life, 27)

func test_ikkotsu_attack_without_burn_does_not_push():
	position_players(player1, 6, player2, 4)
	_attack("ikkotsu", "standard_normal_grasp")
	assert_eq(player1.arena_location, 5)
	assert_eq(player2.arena_location, 4)
	assert_eq(player2.life, 27)

func _clear_hand(owner: Player):
	owner.discard(owner.hand.map(func(card): return card.id))

func _counter_hand(suffix: String = "") -> int:
	_clear_hand(player2)
	var definition_id = PREFIX + ("netsu_jigoku" if suffix.is_empty() else suffix)
	for zone in [player2.deck, player2.discards]:
		for card in zone:
			if card.definition["id"] == definition_id:
				zone.erase(card)
				if suffix.is_empty():
					# A missing-hand test still needs one unaccounted-for copy to bluff.
					player2.deck.append(card)
				else:
					player2.hand.append(card)
				return -1 if suffix.is_empty() else card.id
	fail_test("Counter fixture could not find a real copy: " + definition_id)
	return -1

func _choose_counter(effect_type: String):
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player2.my_id)
	for index in range(game_logic.decision_info.choice.size()):
		if game_logic.decision_info.choice[index]["effect_type"] == effect_type:
			assert_true(game_logic.do_choice(player2, index))
			return
	fail_test("Counter option missing: " + effect_type)

func _fixture_boost(owner: Player, effects: Array, continuous: bool = true) -> int:
	var id = give_player_specific_card(owner, "standard_normal_cross")
	game_logic.card_db.get_card(id).definition["boost"] = {
		"display_name": "Movement fixture", "boost_type": "continuous" if continuous else "immediate",
		"force_cost": 0, "cancel_cost": 1, "effects": effects
	}
	return id

func _existing_boost(owner: Player) -> int:
	var id = _fixture_boost(owner, [{"timing": "during_strike", "effect_type": "powerup", "amount": 1}])
	var card = game_logic.card_db.get_card(id)
	owner.remove_card_from_hand(id, true, false)
	owner.add_to_continuous_boosts(card)
	return id

func test_runtime_boost_definitions_and_text():
	var expected = {
		"jokaku_enjo": ["松明", "immediate", 1],
		"ryujin_jakka": ["一刀火葬", "continuous", 1],
		"sokotsu": ["瞬步", "immediate", 1],
		"netsu_jigoku": ["森罗", "immediate", -1],
		"nadegiri": ["燎原", "continuous", 1],
		"onibi": ["威眠", "immediate", -1],
		"ikkotsu": ["千年", "continuous", 1],
	}
	for suffix in expected:
		var boost = CardDataManager.get_card(PREFIX + suffix)["boost"]
		assert_eq(boost["display_name"], expected[suffix][0])
		assert_eq(boost["boost_type"], expected[suffix][1])
		assert_eq(boost["force_cost"], 0)
		assert_eq(boost["cancel_cost"], expected[suffix][2])
		assert_eq(boost.get("reaction_only", false), suffix in ["netsu_jigoku", "onibi"])
		for effect in boost["effects"]:
			assert_false(GameStrings.get_effect_text(effect).contains("缺失"), suffix)

func test_taimatsu_boost_draw_then_empty_pressure():
	_clear_hand(player1)
	var id = give_player_specific_card(player1, PREFIX + "jokaku_enjo")
	var deck_size = player1.deck.size()
	assert_true(game_logic.do_boost(player1, id))
	assert_eq(player1.hand.size(), 2, "Boost draw plus normal end-of-turn draw")
	assert_eq(player1.deck.size(), deck_size - 2)
	assert_true(player1.is_card_in_bleach(id))
	assert_false(player1.is_card_in_discards(id))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	var events = game_logic.get_latest_events()
	var draw_index = -1
	var pressure_index = -1
	for index in range(events.size()):
		if events[index]["event_type"] == Enums.EventType.EventType_Draw and draw_index < 0:
			draw_index = index
		if events[index]["event_type"] == Enums.EventType.EventType_AddToBleach:
			pressure_index = index
	assert_gt(pressure_index, draw_index)
	advance_turn(player2)
	assert_true(player1.is_card_in_gauge(id), "Own turn-start UA moves pressure to gauge")

func test_taimatsu_boost_nonempty_pressure_discards_itself():
	_pressure(player1, "gg_normal_grasp")
	var id = give_player_specific_card(player1, PREFIX + "jokaku_enjo")
	assert_true(game_logic.do_boost(player1, id))
	assert_true(player1.is_card_in_discards(id))
	assert_false(player1.is_card_in_bleach(id))
	assert_eq(player1.bleach_zone.size(), 1)

func test_itto_kaso_boost_life_power_and_cleanup():
	_counter_hand()
	var id = give_player_specific_card(player1, PREFIX + "ryujin_jakka")
	assert_true(game_logic.do_boost(player1, id))
	assert_eq(player1.life, 30, "Counter window precedes Now payment")
	_choose_counter("pass")
	assert_eq(player1.life, 26)
	assert_true(player1.is_card_in_continuous_boosts(id))
	advance_turn(player2)
	position_players(player1, 3, player2, 4)
	_attack("nadegiri")
	assert_eq(player2.life, 24)
	assert_eq(player1.life, 26, "Now payment is not repeated in a strike")
	assert_true(player1.is_card_in_discards(id))

func test_shunpo_boost_closes_without_crossing():
	_counter_hand("onibi")
	position_players(player1, 7, player2, 3)
	var id = give_player_specific_card(player1, PREFIX + "sokotsu")
	assert_true(game_logic.do_boost(player1, id))
	assert_eq(player1.arena_location, 7, "Response must precede movement")
	_choose_counter("pass")
	assert_eq(player1.arena_location, 4)
	assert_true(player1.is_card_in_discards(id))

func test_ryogen_boost_life_speed_and_cleanup():
	_counter_hand()
	var id = give_player_specific_card(player1, PREFIX + "nadegiri")
	assert_true(game_logic.do_boost(player1, id))
	_choose_counter("pass")
	assert_eq(player1.life, 27)
	advance_turn(player2)
	position_players(player1, 3, player2, 4)
	_attack("nadegiri", "standard_normal_grasp")
	assert_eq(player1.life, 27, "Speed 7 wins initiator tie")
	assert_eq(player2.life, 26)
	assert_true(player1.is_card_in_discards(id))

func test_sennen_boost_life_power_and_cleanup():
	_counter_hand()
	var id = give_player_specific_card(player1, PREFIX + "ikkotsu")
	assert_true(game_logic.do_boost(player1, id))
	_choose_counter("pass")
	assert_eq(player1.life, 28)
	advance_turn(player2)
	position_players(player1, 3, player2, 4)
	_attack("nadegiri")
	assert_eq(player2.life, 26, "4+2 power minus 2 armor")
	assert_eq(player1.life, 24, "Focus can respond because damage 4 does not exceed guard 5")
	assert_true(player1.is_card_in_discards(id))

func test_shinra_boost_discards_both_sides_and_negates_pending_now():
	var response = _counter_hand("netsu_jigoku")
	var own_boost = _existing_boost(player1)
	var other_boost = _existing_boost(player2)
	var id = give_player_specific_card(player1, PREFIX + "ryujin_jakka")
	assert_true(game_logic.do_boost(player1, id))
	assert_eq(game_logic.active_boost.effects_resolved, 0)
	assert_eq(player1.life, 30)
	assert_eq(game_logic.decision_info.choice[0]["_choice_text"], "弃置森罗并支付2点生命：弃置双方所有持续性加成并无效当前加成")
	_choose_counter("yuanliuzhai_activate_shinra")
	assert_eq(player1.life, 30, "Negated boost must not spend its printed Now life cost")
	assert_eq(player2.life, 28)
	assert_true(player2.is_card_in_discards(response))
	assert_true(player1.is_card_in_discards(own_boost))
	assert_true(player2.is_card_in_discards(other_boost))
	assert_true(player1.is_card_in_discards(id))
	assert_true(player1.continuous_boosts.is_empty())
	assert_true(player2.continuous_boosts.is_empty())
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	assert_eq(game_logic.active_turn_player, player2.my_id)

func test_shinra_boost_pass_preserves_pending_effect():
	var response = _counter_hand("netsu_jigoku")
	var id = give_player_specific_card(player1, PREFIX + "ryujin_jakka")
	assert_true(game_logic.do_boost(player1, id))
	_choose_counter("pass")
	assert_eq(player1.life, 26)
	assert_eq(player2.life, 30)
	assert_true(player2.is_card_in_hand(response))
	assert_true(player1.is_card_in_continuous_boosts(id))

func test_shinra_counter_precedes_boost_choice_after_synchronous_counter():
	_counter_hand("netsu_jigoku")
	player2.deck_def = player2.deck_def.duplicate(true)
	player2.deck_def["ability_effects"].push_front({
		"timing": "counter_boost", "effect_type": "pass"
	})
	var id = _fixture_boost(player1, [{
		"timing": "now", "effect_type": "choice", "choice": [
			{"effect_type": "draw", "amount": 1},
			{"effect_type": "pass"}
		]
	}])
	var hand_size = player1.hand.size()
	assert_true(game_logic.do_boost(player1, id))
	assert_eq(game_logic.decision_info.player, player2.my_id, "Counter must precede the boost owner's choice")
	if game_logic.decision_info.player != player2.my_id:
		return
	assert_eq(game_logic.active_boost.effects_resolved, 0)
	_choose_counter("pass")
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.active_boost.checked_counter)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player1.hand.size(), hand_size + 1, "Remove boost, draw once, then draw at turn end")
	assert_true(player1.is_card_in_continuous_boosts(id))
	assert_null(game_logic.active_boost, "The boost must not ask for the same choice twice")
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)

func test_shinra_missing_card_prompts_before_boost_effects_and_resumes_once():
	_counter_hand()
	_clear_hand(player1)
	var id = _fixture_boost(player1, [
		{"timing": "now", "effect_type": "draw", "amount": 2},
		{"timing": "now", "effect_type": "choice", "choice": [
			{"effect_type": "draw", "amount": 1},
			{"effect_type": "pass"}
		]}
	])
	assert_true(game_logic.do_boost(player1, id))
	assert_eq(player1.hand.size(), 0, "Even without Shinra in hand, ask before resolving the boost")
	_choose_counter("pass")
	assert_eq(player1.hand.size(), 2)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.active_boost.checked_counter)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player1.hand.size(), 4, "Draw 2, selected draw 1, and turn-end draw 1 each resolve once")
	assert_true(player1.is_card_in_continuous_boosts(id))
	assert_null(game_logic.active_boost)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)

func test_shinra_negate_prevents_draw_before_boost_choice():
	_counter_hand("netsu_jigoku")
	player2.deck_def = player2.deck_def.duplicate(true)
	player2.deck_def["ability_effects"].push_front({
		"timing": "counter_boost", "effect_type": "pass"
	})
	var id = _fixture_boost(player1, [
		{"timing": "now", "effect_type": "draw", "amount": 2},
		{"timing": "now", "effect_type": "choice", "choice": [
			{"effect_type": "draw", "amount": 1},
			{"effect_type": "pass"}
		]}
	])
	var deck_size = player1.deck.size()
	assert_true(game_logic.do_boost(player1, id))
	assert_eq(player1.deck.size(), deck_size, "No boost effect may run before the counter")
	_choose_counter("yuanliuzhai_activate_shinra")
	assert_eq(player1.deck.size(), deck_size - 1, "Only the normal turn-end draw may run")
	assert_true(player1.is_card_in_discards(id))
	assert_null(game_logic.active_boost)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)

func test_shinra_decline_finishes_remaining_counters_before_boost_choice():
	_counter_hand("netsu_jigoku")
	player2.deck_def = player2.deck_def.duplicate(true)
	player2.deck_def["ability_effects"].append({
		"timing": "counter_boost", "effect_type": "pass"
	})
	var id = _fixture_boost(player1, [{
		"timing": "now", "effect_type": "choice", "choice": [
			{"effect_type": "draw", "amount": 1},
			{"effect_type": "pass"}
		]
	}])
	var hand_size = player1.hand.size()
	assert_true(game_logic.do_boost(player1, id))
	_choose_counter("pass")
	assert_true(game_logic.active_boost.checked_counter, "Boost choices must not resume as counter choices")
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_choice(player1, 0))
	assert_null(game_logic.active_boost, "The boost choice must resolve exactly once")
	assert_eq(player1.hand.size(), hand_size + 1)
	assert_true(player1.is_card_in_continuous_boosts(id))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)

func test_shinra_boost_missing_card_still_prompts_pass():
	_counter_hand()
	var id = give_player_specific_card(player1, PREFIX + "ryujin_jakka")
	assert_true(game_logic.do_boost(player1, id))
	assert_eq(game_logic.decision_info.choice.size(), 1)
	assert_eq(game_logic.decision_info.choice[0]["_choice_text"], "不响应")
	_choose_counter("pass")
	assert_eq(player1.life, 26)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)

func _put_counter_copies_in_public_zones(suffix: String, pressure_count: int) -> Array[GameCard]:
	var copies: Array[GameCard] = []
	for zone in [player2.hand, player2.deck, player2.discards]:
		for card in zone.duplicate():
			if card.definition["id"] == PREFIX + suffix:
				zone.erase(card)
				copies.append(card)
	assert_eq(copies.size(), 2, "Use the two real deck copies, not additional fixture cards")
	for index in range(copies.size()):
		if index < pressure_count:
			player2.add_to_bleach(copies[index])
		else:
			player2.add_to_discards(copies[index])
	return copies

func _assert_unavailable_shinra_skips_counter(pressure_count: int, exceeded: bool = false):
	_counter_hand()
	_clear_hand(player1)
	player2.exceeded = exceeded
	_put_counter_copies_in_public_zones("netsu_jigoku", pressure_count)
	var id = _fixture_boost(player1, [
		{"timing": "now", "effect_type": "draw", "amount": 2},
		{"timing": "now", "effect_type": "choice", "choice": [
			{"effect_type": "draw", "amount": 1},
			{"effect_type": "pass"}
		]}
	])
	assert_true(game_logic.do_boost(player1, id))
	assert_eq(player1.hand.size(), 2, "Resolve the boost without an unavailable Shinra prompt")
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.active_boost.checked_counter)
	validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Strike_EffectChoice, player2)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player1.hand.size(), 4, "Draw 2, selected draw 1, and turn-end draw 1 each resolve once")
	assert_true(player1.is_card_in_continuous_boosts(id))
	assert_null(game_logic.active_boost)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)

func test_shinra_skips_when_both_copies_are_in_discards():
	_assert_unavailable_shinra_skips_counter(0)

func test_shinra_skips_when_both_copies_are_in_pressure():
	_assert_unavailable_shinra_skips_counter(2)

func test_shinra_skips_when_copies_are_split_between_discards_and_pressure():
	_assert_unavailable_shinra_skips_counter(1)

func test_shinra_skips_when_exceeded_and_both_copies_are_in_discards():
	_assert_unavailable_shinra_skips_counter(0, true)

func test_shinra_skips_when_exceeded_and_both_copies_are_in_pressure():
	_assert_unavailable_shinra_skips_counter(2, true)

func test_shinra_skips_when_exceeded_and_copies_are_split_between_public_zones():
	_assert_unavailable_shinra_skips_counter(1, true)

func test_shinra_unavailable_still_offers_imin_against_continuous_movement():
	var response = _counter_hand("onibi")
	_clear_hand(player1)
	_put_counter_copies_in_public_zones("netsu_jigoku", 1)
	position_players(player1, 3, player2, 7)
	var id = _fixture_boost(player1, [{
		"timing": "now", "effect_type": "advance", "amount": 2,
		"and": {"effect_type": "draw", "amount": 2}
	}])
	assert_true(game_logic.do_boost(player1, id))
	assert_eq(game_logic.decision_info.choice.size(), 2)
	assert_eq(game_logic.decision_info.choice[0]["effect_type"], "yuanliuzhai_activate_imin")
	assert_eq(game_logic.decision_info.choice[1]["effect_type"], "pass")
	_choose_counter("yuanliuzhai_activate_imin")
	assert_eq(player1.arena_location, 3)
	assert_eq(player1.hand.size(), 3, "Imin blocks movement but not the draw chain or turn-end draw")
	assert_eq(player2.life, 28)
	assert_true(player2.is_card_in_discards(response))
	assert_true(player1.is_card_in_continuous_boosts(id))
	assert_null(game_logic.active_boost)

func test_shinra_one_public_copy_still_prompts_without_revealing_hidden_copy():
	_counter_hand()
	_clear_hand(player1)
	var copies = _put_counter_copies_in_public_zones("netsu_jigoku", 0)
	player2.discards.erase(copies[1])
	player2.deck.append(copies[1])
	assert_true(player2.hand.is_empty())
	var id = _fixture_boost(player1, [{"timing": "now", "effect_type": "draw", "amount": 2}])
	var hand_size = player1.hand.size()
	assert_true(game_logic.do_boost(player1, id))
	assert_eq(player1.hand.size(), hand_size - 1, "Retain the bluff window while one copy is unaccounted for")
	assert_eq(game_logic.decision_info.choice.size(), 1)
	_choose_counter("pass")
	assert_eq(player1.hand.size(), hand_size + 2)
	assert_null(game_logic.active_boost)

func _assert_shinra_returned_to_hand_can_respond(pressure_count: int):
	_counter_hand()
	var copies = _put_counter_copies_in_public_zones("netsu_jigoku", pressure_count)
	var response = copies[0]
	if pressure_count > 0:
		player2.remove_card_from_bleach(response.id)
	else:
		player2.discards.erase(response)
	player2.hand.append(response)
	var id = _fixture_boost(player1, [{"timing": "now", "effect_type": "draw", "amount": 2}])
	var deck_size = player1.deck.size()
	assert_true(game_logic.do_boost(player1, id))
	_choose_counter("yuanliuzhai_activate_shinra")
	assert_true(player2.is_card_in_discards(response.id))
	assert_true(player1.is_card_in_discards(id))
	assert_eq(player2.life, 28)
	assert_eq(player1.deck.size(), deck_size - 1, "Only the turn-end draw resolves after negation")
	assert_null(game_logic.active_boost)

func test_shinra_returned_from_discards_to_hand_can_respond():
	_assert_shinra_returned_to_hand_can_respond(0)

func test_shinra_returned_from_pressure_to_hand_can_respond():
	_assert_shinra_returned_to_hand_can_respond(2)

func test_shinra_boost_allows_cancel_after_negate():
	_counter_hand("netsu_jigoku")
	var payment = give_gauge(player1, 1)
	var id = give_player_specific_card(player1, PREFIX + "ryujin_jakka")
	assert_true(game_logic.do_boost(player1, id))
	_choose_counter("yuanliuzhai_activate_shinra")
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostCancel)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.active_boost.boost_negated)
	assert_true(game_logic.active_boost.allow_cancel_after_negate)
	assert_true(game_logic.do_boost_cancel(player1, payment, true))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	assert_eq(game_logic.active_turn_player, player1.my_id)
	assert_true(player1.is_card_in_discards(payment[0]))

func test_shinra_boost_can_pay_life_to_zero_and_lose():
	var response = _counter_hand("netsu_jigoku")
	player2.life = 2
	var id = give_player_specific_card(player1, PREFIX + "ryujin_jakka")
	assert_true(game_logic.do_boost(player1, id))
	_choose_counter("yuanliuzhai_activate_shinra")
	assert_eq(player2.life, 0)
	assert_true(game_logic.game_over)
	assert_true(player2.is_card_in_discards(response))
	assert_eq(player1.life, 30)

func test_shinra_boost_insufficient_life_only_pass():
	_counter_hand("netsu_jigoku")
	player2.life = 1
	var id = give_player_specific_card(player1, PREFIX + "ryujin_jakka")
	assert_true(game_logic.do_boost(player1, id))
	assert_eq(game_logic.decision_info.choice.size(), 1)
	_choose_counter("pass")
	assert_eq(player2.life, 1)

func _assert_unavailable_imin_skips_counter(pressure_count: int, exceeded: bool = false, continuous: bool = false):
	_counter_hand()
	_clear_hand(player1)
	player2.exceeded = exceeded
	_put_counter_copies_in_public_zones("onibi", pressure_count)
	if continuous:
		_put_counter_copies_in_public_zones("netsu_jigoku", 0)
	position_players(player1, 3, player2, 7)
	var id = _fixture_boost(player1, [{
		"timing": "now", "effect_type": "advance", "amount": 2,
		"and": {"effect_type": "draw", "amount": 2}
	}], continuous)
	assert_true(game_logic.do_boost(player1, id))
	assert_eq(player1.arena_location, 5, "An unavailable Imin cannot block movement")
	assert_eq(player1.hand.size(), 3, "Chained draw 2 and turn-end draw 1 resolve once")
	assert_eq(player2.life, 30)
	assert_null(game_logic.active_boost)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Strike_EffectChoice, player2)
	if continuous:
		assert_true(player1.is_card_in_continuous_boosts(id))
	else:
		assert_true(player1.is_card_in_discards(id))

func test_imin_skips_when_both_copies_are_in_discards():
	_assert_unavailable_imin_skips_counter(0)

func test_imin_skips_when_both_copies_are_in_pressure():
	_assert_unavailable_imin_skips_counter(2)

func test_imin_skips_when_copies_are_split_between_discards_and_pressure():
	_assert_unavailable_imin_skips_counter(1)

func test_imin_skips_when_exceeded_and_both_copies_are_in_discards():
	_assert_unavailable_imin_skips_counter(0, true)

func test_imin_skips_when_exceeded_and_both_copies_are_in_pressure():
	_assert_unavailable_imin_skips_counter(2, true)

func test_imin_skips_when_exceeded_and_copies_are_split_between_public_zones():
	_assert_unavailable_imin_skips_counter(1, true)

func test_imin_and_shinra_unavailable_skip_continuous_movement_response():
	_assert_unavailable_imin_skips_counter(1, false, true)

func test_imin_unavailable_still_offers_shinra_against_continuous_movement():
	_counter_hand("netsu_jigoku")
	_clear_hand(player1)
	_put_counter_copies_in_public_zones("onibi", 1)
	position_players(player1, 3, player2, 7)
	var id = _fixture_boost(player1, [{
		"timing": "now", "effect_type": "advance", "amount": 2,
		"and": {"effect_type": "draw", "amount": 2}
	}])
	assert_true(game_logic.do_boost(player1, id))
	assert_eq(game_logic.decision_info.choice.size(), 2)
	assert_eq(game_logic.decision_info.choice[0]["effect_type"], "yuanliuzhai_activate_shinra")
	assert_eq(game_logic.decision_info.choice[1]["effect_type"], "pass")
	assert_eq(player1.arena_location, 3)
	assert_eq(player1.hand.size(), 0)
	_choose_counter("yuanliuzhai_activate_shinra")
	assert_eq(player1.arena_location, 3)
	assert_eq(player1.hand.size(), 1, "Only the turn-end draw resolves after Shinra negates")
	assert_true(player1.is_card_in_discards(id))
	assert_null(game_logic.active_boost)

func _assert_imin_returned_to_hand_can_respond(pressure_count: int):
	_counter_hand()
	_clear_hand(player1)
	var copies = _put_counter_copies_in_public_zones("onibi", pressure_count)
	var response = copies[0]
	if pressure_count > 0:
		player2.remove_card_from_bleach(response.id)
	else:
		player2.discards.erase(response)
	player2.hand.append(response)
	position_players(player1, 3, player2, 7)
	var id = _fixture_boost(player1, [{
		"timing": "now", "effect_type": "advance", "amount": 2,
		"and": {"effect_type": "draw", "amount": 2}
	}], false)
	assert_true(game_logic.do_boost(player1, id))
	assert_eq(game_logic.decision_info.choice.size(), 2)
	_choose_counter("yuanliuzhai_activate_imin")
	assert_eq(player1.arena_location, 3)
	assert_eq(player1.hand.size(), 3)
	assert_eq(player2.life, 28)
	assert_true(player2.is_card_in_discards(response.id))
	assert_true(player1.is_card_in_discards(id))
	assert_null(game_logic.active_boost)

func test_imin_returned_from_discards_to_hand_can_respond():
	_assert_imin_returned_to_hand_can_respond(0)

func test_imin_returned_from_pressure_to_hand_can_respond():
	_assert_imin_returned_to_hand_can_respond(2)

func test_imin_boost_immediate_movement_block_preserves_draw_chain():
	var response = _counter_hand("onibi")
	_clear_hand(player1)
	position_players(player1, 3, player2, 7)
	var id = _fixture_boost(player1, [{
		"timing": "immediate", "effect_type": "advance", "amount": 2,
		"and": {"effect_type": "draw", "amount": 1}
	}], false)
	assert_true(game_logic.do_boost(player1, id))
	assert_eq(player1.arena_location, 3)
	assert_eq(game_logic.decision_info.choice[0]["_choice_text"], "弃置威眠并支付2点生命：阻止该张加成离场前的所有自身移动")
	_choose_counter("yuanliuzhai_activate_imin")
	assert_eq(player1.arena_location, 3)
	assert_eq(player1.hand.size(), 2, "Chained draw plus turn-end draw both resolve")
	assert_eq(player2.life, 28)
	assert_true(player2.is_card_in_discards(response))
	assert_true(player1.yuanliuzhai_blocked_boost_ids.is_empty())
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)

func test_imin_boost_delayed_movement_block_is_source_scoped_until_leaving():
	_counter_hand("onibi")
	_clear_hand(player1)
	var id = _fixture_boost(player1, [{
		"timing": "before", "effect_type": "choice", "choice": [
			{"effect_type": "advance", "amount": 2, "and": {"effect_type": "draw", "amount": 1}},
			{"effect_type": "retreat", "amount": 2}
		]
	}])
	assert_true(game_logic.do_boost(player1, id))
	_choose_counter("yuanliuzhai_activate_imin")
	assert_has(player1.yuanliuzhai_blocked_boost_ids, id)
	assert_true(player1.is_card_in_continuous_boosts(id))
	advance_turn(player2)
	position_players(player1, 3, player2, 7)
	var attack_id = give_player_specific_card(player1, PREFIX + "ikkotsu")
	var defense_id = give_player_specific_card(player2, "standard_normal_focus")
	assert_true(game_logic.do_strike(player1, attack_id, false, -1))
	assert_true(game_logic.do_strike(player2, defense_id, false, -1))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseSimultaneousEffect)
	for step in range(4):
		if game_logic.decision_info.type != Enums.DecisionType.DecisionType_ChooseSimultaneousEffect:
			break
		assert_true(game_logic.do_choice(player1, 0))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_choice(player1, 0))
	_finish_strike()
	assert_eq(player1.arena_location, 4, "Own attack advance 1 is not blocked; boost advance 2 is")
	assert_true(player1.is_card_in_discards(id))
	assert_false(id in player1.yuanliuzhai_blocked_boost_ids)
	game_logic.handle_strike_effect(id, {"effect_type": "advance", "amount": 1}, player1)
	assert_eq(player1.arena_location, 5, "Leaving play removes the movement restriction")

func test_imin_boost_blocks_retreat_and_close_but_not_push():
	_counter_hand("onibi")
	position_players(player1, 3, player2, 7)
	var id = _fixture_boost(player1, [
		{"timing": "immediate", "effect_type": "retreat", "amount": 1},
		{"timing": "immediate", "effect_type": "close", "amount": 2},
		{"timing": "immediate", "effect_type": "push", "amount": 1}
	], false)
	assert_true(game_logic.do_boost(player1, id))
	_choose_counter("yuanliuzhai_activate_imin")
	assert_eq(player1.arena_location, 3)
	assert_eq(player2.arena_location, 8)

func test_imin_boost_missing_card_resolves_movement_without_response():
	_counter_hand()
	position_players(player1, 3, player2, 7)
	var id = give_player_specific_card(player1, PREFIX + "sokotsu")
	assert_true(game_logic.do_boost(player1, id))
	assert_eq(player1.arena_location, 6)
	assert_eq(player2.life, 30)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Strike_EffectChoice, player2)

func test_shinra_ignores_immediate_boost_without_movement():
	var response = _counter_hand("netsu_jigoku")
	_clear_hand(player1)
	var id = _fixture_boost(player1, [{"timing": "immediate", "effect_type": "draw", "amount": 1}], false)
	assert_true(game_logic.do_boost(player1, id))
	assert_eq(player1.hand.size(), 2, "Boost and turn-end draws resolve without a response")
	assert_true(player2.is_card_in_hand(response))
	assert_eq(player2.life, 30)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Strike_EffectChoice, player2)

func test_shinra_ignores_immediate_movement_boost_without_imin():
	var response = _counter_hand("netsu_jigoku")
	position_players(player1, 3, player2, 7)
	var id = give_player_specific_card(player1, PREFIX + "sokotsu")
	assert_true(game_logic.do_boost(player1, id))
	assert_eq(player1.arena_location, 6)
	assert_true(player2.is_card_in_hand(response))
	assert_eq(player2.life, 30)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Strike_EffectChoice, player2)

func test_shinra_immediate_movement_response_only_offers_imin():
	var shinra_id = _counter_hand("netsu_jigoku")
	var imin_id = give_player_specific_card(player2, PREFIX + "onibi")
	position_players(player1, 3, player2, 7)
	var id = give_player_specific_card(player1, PREFIX + "sokotsu")
	assert_true(game_logic.do_boost(player1, id))
	assert_eq(game_logic.decision_info.choice.size(), 2)
	assert_eq(game_logic.decision_info.choice[0]["effect_type"], "yuanliuzhai_activate_imin")
	assert_eq(game_logic.decision_info.choice[1]["effect_type"], "pass")
	_choose_counter("pass")
	assert_eq(player1.arena_location, 6)
	assert_true(player2.is_card_in_hand(shinra_id))
	assert_true(player2.is_card_in_hand(imin_id))
	assert_eq(player2.life, 30)

func test_shinra_immediate_boost_cannot_be_negated():
	var response = _counter_hand("netsu_jigoku")
	var id = _fixture_boost(player1, [{
		"timing": "immediate", "effect_type": "choice", "choice": [
			{"effect_type": "pass"}, {"effect_type": "draw", "amount": 1}
		]
	}], false)
	assert_true(game_logic.do_boost(player1, id))
	assert_eq(game_logic.decision_info.player, player1.my_id)
	game_logic.handle_strike_effect(-1, {
		"effect_type": "yuanliuzhai_activate_shinra", "card_id": response
	}, player2)
	assert_false(game_logic.active_boost.boost_negated)
	assert_true(player2.is_card_in_hand(response))
	assert_eq(player2.life, 30)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_choice(player1, 0))
	assert_true(player1.is_card_in_discards(id))

func test_imin_boost_can_pay_life_to_zero_and_lose():
	var response = _counter_hand("onibi")
	player2.life = 2
	var id = give_player_specific_card(player1, PREFIX + "sokotsu")
	assert_true(game_logic.do_boost(player1, id))
	_choose_counter("yuanliuzhai_activate_imin")
	assert_eq(player2.life, 0)
	assert_true(game_logic.game_over)
	assert_true(player2.is_card_in_discards(response))
	assert_eq(player1.arena_location, 3)

func test_reaction_only_cards_are_not_boost_options_for_player_ui_or_ai():
	_clear_hand(player1)
	var wrapper = GameWrapper.new()
	wrapper.current_game = game_logic
	var ai = AIPlayer.new(game_logic, player1)
	for suffix in ["netsu_jigoku", "onibi"]:
		var id = give_player_specific_card(player1, PREFIX + suffix)
		assert_false(wrapper.can_player_boost(player1.my_id, id, ["hand"], "", true))
		assert_false(game_logic.do_boost(player1, id))
		assert_true(player1.is_card_in_hand(id))
	assert_false(player1.can_boost_something(["hand"], "", true))
	assert_eq(ai.get_boost_actions(["hand"], "", true, 1).size(), 0)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	ai.ai_policy.free()
	ai = null
	wrapper.current_game = null
	wrapper.free()

func test_imin_boost_sustain_preserves_restriction_and_transfer_clears_it():
	_counter_hand("onibi")
	var id = _fixture_boost(player1, [{"timing": "before", "effect_type": "close", "amount": 1}])
	assert_true(game_logic.do_boost(player1, id))
	_choose_counter("yuanliuzhai_activate_imin")
	player1.sustained_boosts.append(id)
	player1.cleanup_continuous_boosts()
	assert_true(player1.is_card_in_continuous_boosts(id))
	assert_has(player1.yuanliuzhai_blocked_boost_ids, id)
	player1.remove_from_continuous_boosts(game_logic.card_db.get_card(id), "hand")
	assert_true(player1.is_card_in_hand(id))
	assert_false(id in player1.yuanliuzhai_blocked_boost_ids)
