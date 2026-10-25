extends ExceedGutTest


const SPECIAL_NAMES = ["呼唤我的名字吧！", "虚化", "地裂崩击", "静血装", "灵魂对接", "全力一击", "瞬步"]
const PRINTED_STATS = [
	["ultra", 0, 2, 1, 2, 5, 5, 0, 5],
	["ultra", 0, 2, -1, -1, 0, 0, 4, 0],
	["special", 0, 0, 2, 4, 3, 5, 0, 0],
	["special", 0, 0, 1, 2, 3, 3, 4, 1],
	["special", 0, 0, 2, 8, 3, 3, 0, 4],
	["special", 0, 0, 1, 1, 4, 4, 0, 4],
	["special", 0, 0, 0, 0, 3, 4, 0, 0]
]
const STAT_KEYS = ["type", "force_cost", "gauge_cost", "range_min", "range_max", "power", "speed", "armor", "guard"]
const NORMAL_INDICES = {"grasp": 3, "cross": 5, "slash": 4, "dive": 6, "dust": 0, "sweep": 2, "focus": 7, "block": 1}
const BOOST_NAMES = ["月牙天冲", "神秘的力量", "无限的潜力", "母亲的守护", "友情的羁绊", "力量的解放", "修行的成果"]


func who_am_i():
	return "heiqiyihu"


func test_guardian_virtual_grasp_normal_hit_moves_before_damage():
	position_players(player1, 3, player2, 4)
	var source_id = give_player_specific_card(player1, "gg_normal_grasp")
	assert_true(game_logic.do_boost(player1, source_id))
	assert_true(player1.is_card_in_continuous_boosts(source_id))
	var attack = give_player_specific_card(player1, "gg_normal_grasp")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseSimultaneousEffect)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_false(player1.is_card_in_gauge(source_id))
	var boost_index = -1
	for i in range(game_logic.decision_info.choice.size()):
		if game_logic.decision_info.choice[i]["effect_type"] == StrikeEffects.Powerup:
			boost_index = i
	assert_gte(boost_index, 0)
	if boost_index < 0:
		return
	assert_true(game_logic.do_choice(player1, boost_index))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(player1.strike_stat_boosts.power, 1)
	assert_true(player1.is_card_in_gauge(source_id), "Q6: immediately after the Hit powerup, not Cleanup.")
	assert_false(player1.is_card_in_continuous_boosts(source_id))
	assert_eq(player2.life, 30, "The attack's Hit movement is still pending; no damage yet.")
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player2.life, 28, "Grasp power3 + boost1 - Focus armor2.")
	assert_null(game_logic.active_strike)


func _definition(index: int) -> Dictionary:
	return CardDataManager.get_card("heiqiyihu_" + SPECIAL_NAMES[index])


func _virtual_grasp_hit_window(source_destination: String = "") -> int:
	position_players(player1, 3, player2, 4)
	var source_id = _give_guardian(player1, "gg_normal_grasp")
	var attack = give_player_specific_card(player1, "gg_normal_grasp")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	var hand_size = player1.hand.size()
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player1.hand.size(), hand_size + 1, "Now draw is consumed only once.")
	assert_true(player1.is_card_in_discards(source_id))
	if source_destination == "hand":
		var source = game_logic.card_db.get_card(source_id)
		player1.remove_card_from_discards(source_id)
		player1.add_to_hand(source, true)
	elif source_destination == "deck":
		player1.reshuffle_discard(false)
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseSimultaneousEffect)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	var boost_index = -1
	for i in range(game_logic.decision_info.choice.size()):
		if game_logic.decision_info.choice[i]["effect_type"] == StrikeEffects.Powerup:
			boost_index = i
	assert_gte(boost_index, 0)
	if boost_index >= 0:
		assert_true(game_logic.do_choice(player1, boost_index))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(player1.strike_stat_boosts.power, 1)
	assert_eq(player2.life, 30, "Hit transfer occurs before damage.")
	assert_eq(game_logic.active_strike.heiqiyihu_guardian_records.size(), 1)
	return source_id


func test_guardian_virtual_grasp_hit_moves_entity_before_damage():
	var source_id = _virtual_grasp_hit_window()
	assert_true(player1.is_card_in_gauge(source_id))
	assert_false(player1.is_card_in_discards(source_id))
	assert_false(player1.is_card_in_continuous_boosts(source_id))
	var strike = game_logic.active_strike
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player2.life, 28)
	assert_null(game_logic.active_strike)
	assert_true(player1.is_card_in_gauge(source_id))
	assert_eq(game_logic.queued_effect_chain["effect"], null)
	# Keeping the old Strike reference must not make it active again.
	assert_eq(strike.heiqiyihu_guardian_records.size(), 1)
	assert_eq(game_logic.get_boost_effects_at_timing("hit", player1).size(), 0)


func test_guardian_virtual_source_in_hand_is_not_retrieved_by_name():
	var other_id = give_player_specific_card(player1, "gg_normal_grasp")
	var other_card = game_logic.card_db.get_card(other_id)
	player1.remove_card_from_hand(other_id, true, false)
	player1.add_to_discards(other_card)
	var source_id = _virtual_grasp_hit_window("hand")
	assert_true(player1.is_card_in_hand(source_id))
	assert_false(player1.is_card_in_gauge(source_id))
	assert_true(player1.is_card_in_discards(other_id), "A same-name entity is not a substitute source.")
	assert_false(player1.is_card_in_gauge(other_id))
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player2.life, 28, "The copied powerup survives the source leaving discards.")
	assert_true(player1.is_card_in_hand(source_id))
	assert_true(player1.is_card_in_discards(other_id))


func test_guardian_virtual_source_shuffled_into_deck_is_not_retrieved():
	var source_id = _virtual_grasp_hit_window("deck")
	assert_false(player1.is_card_in_discards(source_id))
	assert_false(player1.is_card_in_gauge(source_id))
	var found_in_deck = false
	for card in player1.deck:
		found_in_deck = found_in_deck or card.id == source_id
	assert_true(found_in_deck)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player2.life, 28)
	assert_false(player1.is_card_in_gauge(source_id))


func test_guardian_virtual_cross_pull_past_moves_source_after_immediate_chain():
	position_players(player1, 4, player2, 5)
	var source_id = _give_guardian(player1, "gg_normal_cross")
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(player1.is_card_in_discards(source_id))
	assert_true(game_logic.do_choice(player1, 1))
	assert_eq(player2.arena_location, 2)
	assert_true(player1.is_card_in_gauge(source_id))
	assert_false(player1.is_card_in_discards(source_id))
	assert_false(player1.is_card_in_continuous_boosts(source_id))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)
	assert_eq(game_logic.queued_effect_chain["effect"], null)
	validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Boost_CancelDecision, player1)


func test_guardian_virtual_dust_expires_without_next_turn_transfer():
	position_players(player1, 3, player2, 4)
	var source_id = _give_guardian(player1, "gg_normal_dust")
	var attack = give_player_specific_card(player1, "gg_normal_focus")
	var response = give_player_specific_card(player2, "gg_normal_grasp")
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	assert_true(game_logic.do_choice(player1, 0))
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_eq(game_logic.decision_info.player, player2.my_id)
	assert_eq(player1.strike_stat_boosts.guard, 4)
	assert_false(player1.is_card_in_continuous_boosts(source_id))
	assert_true(game_logic.do_choice(player2, 0))
	assert_null(game_logic.active_strike)
	assert_true(player1.is_card_in_discards(source_id))
	assert_false(player1.is_card_in_gauge(source_id))
	assert_eq(game_logic.get_boost_effects_at_timing("during_strike", player1).size(), 0)
	assert_true(game_logic.get_boost_effects_at_timing("start_of_next_turn", player1).is_empty())
	var second_attack = give_player_specific_card(player2, "gg_normal_grasp")
	var second_response = give_player_specific_card(player1, "gg_normal_focus")
	assert_true(game_logic.do_strike(player2, second_attack, false, -1))
	assert_true(game_logic.do_strike(player1, second_response, false, -1))
	assert_eq(player1.strike_stat_boosts.guard, 0, "No virtual bonus survives into the next strike.")
	assert_true(game_logic.do_choice(player2, 0))
	assert_true(player1.is_card_in_discards(source_id))
	assert_false(player1.is_card_in_gauge(source_id))


func test_guardian_virtual_focus_initiator_forces_wild_before_response():
	var source_id = _give_guardian(player1, "gg_normal_focus")
	var attack = give_player_specific_card(player1, "gg_normal_focus")
	var wild_id = set_player_topdeck(player2, "gg_normal_grasp")
	position_players(player1, 3, player2, 4)
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	assert_true(game_logic.do_choice(player1, 0))
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_eq(game_logic.active_strike.defender_card.id, wild_id)
	assert_true(game_logic.active_strike.defender_wild_strike)
	assert_eq(game_logic.decision_info.player, player2.my_id)
	assert_true(player1.is_card_in_discards(source_id))
	assert_true(game_logic.do_choice(player2, 0))
	assert_null(game_logic.active_strike)


func test_guardian_virtual_focus_defender_does_not_force_initiator():
	var source_id = _give_guardian(player2, "gg_normal_focus")
	var attack = give_player_specific_card(player1, "gg_normal_grasp")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	position_players(player1, 3, player2, 4)
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	assert_true(game_logic.do_choice(player2, 0))
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_false(game_logic.active_strike.initiator_wild_strike)
	assert_eq(game_logic.active_strike.initiator_card.id, attack)
	assert_null(game_logic.active_strike.defender_card)
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_false(game_logic.active_strike.defender_wild_strike)
	assert_true(game_logic.do_choice(player1, 0))
	assert_true(player2.is_card_in_discards(source_id))


func test_guardian_virtual_nested_opponent_choice_restores_owner_once():
	var source_id = _give_guardian(player1, "gg_normal_grasp")
	var source = game_logic.card_db.get_card(source_id)
	# A per-entity fixture probes the generic virtual chain, not a new card rule.
	source.definition = source.definition.duplicate(true)
	source.definition["boost"]["effects"] = [{
		"timing": "now", "effect_type": StrikeEffects.Choice,
		"choice": [{"effect_type": StrikeEffects.Draw, "amount": 1}],
		"and": {
			"effect_type": StrikeEffects.Choice, "opponent": true,
			"choice": [{"effect_type": StrikeEffects.Draw, "amount": 1}],
			"and": {
				"effect_type": StrikeEffects.Choice,
				"choice": [{"effect_type": StrikeEffects.Draw, "amount": 2}]
			}
		}
	}]
	var first_hand = player1.hand.size()
	var second_hand = player2.hand.size()
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(game_logic.decision_info.player, player2.my_id)
	assert_eq(player1.hand.size(), first_hand + 1)
	assert_true(game_logic.do_choice(player2, 0))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(player2.hand.size(), second_hand + 1)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player1.hand.size(), first_hand + 3)
	assert_eq(player2.hand.size(), second_hand + 1)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)
	assert_eq(game_logic.queued_effect_chain["effect"], null)
	assert_true(player1.is_card_in_discards(source_id))


func test_guardian_virtual_all_strike_timings_and_cleanup_source_transfer():
	position_players(player1, 3, player2, 5)
	player2.life = 40
	var source_id = _give_guardian(player1, "gg_normal_grasp")
	var source = game_logic.card_db.get_card(source_id)
	source.definition = source.definition.duplicate(true)
	source.definition["boost"]["effects"] = [
		{"timing": "now", "effect_type": StrikeEffects.Draw, "amount": 1},
		{"timing": "during_strike", "effect_type": StrikeEffects.Guardup, "amount": 4},
		{"timing": "before", "effect_type": StrikeEffects.Choice,
			"choice": [{"effect_type": StrikeEffects.Draw, "amount": 1}],
			"and": {"effect_type": StrikeEffects.Draw, "amount": 1}},
		{"timing": "hit", "effect_type": StrikeEffects.Draw, "amount": 1},
		{"timing": "after", "effect_type": StrikeEffects.Draw, "amount": 1},
		{"timing": "cleanup", "effect_type": StrikeEffects.Choice,
			"choice": [{"effect_type": StrikeEffects.Draw, "amount": 1}],
			"and": {"effect_type": StrikeEffects.AddToGaugeImmediately}}
	]
	var attack = give_player_specific_card(player1, "gg_normal_dust")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	var hand_size = player1.hand.size()
	var defender_hand_size = player2.hand.size()
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player1.hand.size(), hand_size + 1)
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.get_current_strike_timing(), "before")
	assert_eq(player1.strike_stat_boosts.guard, 4)
	assert_eq(player1.hand.size(), hand_size, "Only Now and setting the attack have occurred.")
	assert_eq(player2.life, 40)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.get_current_strike_timing(), "cleanup")
	assert_eq(player1.hand.size(), hand_size + 4, "Before drew2, Hit drew1, After drew1.")
	assert_eq(player2.life, 35, "Dust ignores Focus armor.")
	assert_true(player1.strike_stat_boosts.ignore_armor)
	assert_true(player1.strike_stat_boosts.ignore_guard)
	assert_true(game_logic.active_strike.is_player_stunned(player2), "Dust checks Focus guard as zero.")
	assert_eq(player1.life, 30, "Stunned Focus does not activate or deal its printed four power.")
	assert_eq(player2.hand.size(), defender_hand_size - 1, "Stunned Focus also skips its After draw.")
	var combat_events = game_logic.get_latest_events()
	validate_has_event(combat_events, Enums.EventType.EventType_Strike_TookDamage, player2, 5)
	validate_has_event(combat_events, Enums.EventType.EventType_Strike_Stun, player2, response)
	validate_not_has_event(combat_events, Enums.EventType.EventType_Strike_TookDamage, player1)
	assert_true(player1.is_card_in_discards(source_id))
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player1.hand.size(), hand_size + 5)
	assert_true(player1.is_card_in_gauge(source_id))
	assert_false(player1.is_card_in_continuous_boosts(source_id))
	assert_null(game_logic.active_strike)
	assert_true(game_logic.get_boost_effects_at_timing("during_strike", player1).is_empty())
	assert_eq(game_logic.queued_effect_chain["effect"], null)


func test_guardian_virtual_skips_strike_child_but_keeps_legal_async_tail():
	var source_id = _give_guardian(player1, "gg_normal_grasp")
	var source = game_logic.card_db.get_card(source_id)
	source.definition = source.definition.duplicate(true)
	source.definition["boost"]["force_cost"] = 5
	source.definition["boost"]["effects"] = [{
		"timing": "now", "effect_type": StrikeEffects.Strike,
		"and": {
			"effect_type": StrikeEffects.Choice,
			"choice": [{"effect_type": StrikeEffects.Draw, "amount": 2}],
			"and": {"effect_type": StrikeEffects.Draw, "amount": 1}
		}
	}]
	var hand_size = player1.hand.size()
	game_logic.get_latest_events()
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	var declared = game_logic.active_strike
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(player1.hand.size(), hand_size, "No force payment despite the printed cost.")
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player1.hand.size(), hand_size + 3)
	assert_eq(game_logic.active_strike, declared)
	assert_null(declared.initiator_card)
	assert_null(declared.defender_card)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)
	assert_true(player1.is_card_in_discards(source_id))
	var events = game_logic.get_latest_events()
	assert_eq(validate_has_event(events, Enums.EventType.EventType_ForceStartStrike, player1).size(), 1)
	validate_not_has_event(events, Enums.EventType.EventType_Boost_Played, player1)
	validate_not_has_event(events, Enums.EventType.EventType_Boost_CancelDecision, player1)
	validate_not_has_event(events, Enums.EventType.EventType_Boost_Continuous_Added, player1)


func test_guardian_virtual_is_not_a_discard_continuous_boost_target():
	var source_id = _give_guardian(player1, "gg_normal_dust")
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	assert_true(game_logic.do_choice(player1, 0))
	assert_true(player1.get_boosts(true).is_empty())
	assert_true(player2.get_boosts(true).is_empty())
	game_logic.get_latest_events()
	game_logic.handle_strike_effect(-1, {
		"effect_type": StrikeEffects.DiscardContinuousBoost, "required": true, "amount": 1
	}, player2)
	assert_ne(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_true(player1.is_card_in_discards(source_id))
	assert_eq(game_logic.active_strike.heiqiyihu_guardian_records.size(), 1)
	validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Boost_DiscardContinuousChoice, player2)


func _setup_scaled_guardian(special_index: int, huhuan: bool, use_ex: bool = false) -> Dictionary:
	_restart_for_opening(100, 100)
	assert_true(game_logic.do_mulligan(player1, []))
	assert_true(game_logic.do_mulligan(player2, []))
	assert_eq(player1.life, 100)
	assert_eq(player2.life, 100)
	position_players(player1, 3, player2, 4)
	var source_id = _give_guardian(player1, "heiqiyihu_" + SPECIAL_NAMES[special_index])
	var definition_id = "heiqiyihu_呼唤我的名字吧！" if huhuan else "gg_normal_grasp"
	var attack_id = give_player_specific_card(player1, definition_id)
	var attack = game_logic.card_db.get_card(attack_id)
	# Pause one entity at Before to observe actual bonuses before damage.
	attack.definition = attack.definition.duplicate(true)
	attack.definition["effects"].append({
		"timing": "before", "effect_type": StrikeEffects.Choice,
		"choice": [{"effect_type": StrikeEffects.Pass, "_choice_text": "T6继续攻击"}]
	})
	var ex_id = give_player_specific_card(player1, definition_id) if use_ex else -1
	var response_id = give_player_specific_card(player2, "gg_normal_focus")
	var payment = give_gauge(player1, 3) if huhuan else []
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	assert_true(game_logic.do_choice(player1, 0))
	assert_true(game_logic.do_strike(player1, attack_id, false, ex_id))
	if huhuan:
		assert_eq(game_logic.get_gauge_cost(player1, attack), 3)
	assert_true(game_logic.do_strike(player2, response_id, false, -1))
	if huhuan:
		assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_PayStrikeCost_Required)
		assert_eq(game_logic.decision_info.player, player1.my_id)
		assert_eq(game_logic.decision_info.cost, 3)
		assert_eq(game_logic.decision_info.limitation, "gauge")
		assert_false(game_logic.do_pay_strike_cost(player1, payment.slice(0, 2), false))
		assert_eq(player1.gauge.size(), 3, "Rejected payment does not partially discard.")
		assert_true(game_logic.do_pay_strike_cost(player1, payment, false))
		for paid_id in payment:
			assert_true(player1.is_card_in_discards(paid_id))
		assert_eq(player1.gauge.size(), 0)
	return {"source_id": source_id, "attack_id": attack_id}


func _finish_t6_huhuan_cleanup(attack_id: int):
	# C8: no generic Cleanup destination decision for Ichigo. Explicit
	# After/Cleanup abilities have already resolved before this assertion.
	assert_null(game_logic.active_strike)
	assert_true(player1.is_card_in_gauge(attack_id))
	assert_false(player1.is_card_in_bleach(attack_id))
	assert_ne(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)


func _check_guardian_scaling(special_index: int):
	for huhuan in [false, true]:
		var original = _definition(special_index).duplicate(true)
		var ids = _setup_scaled_guardian(special_index, huhuan)
		var extra = 2 if huhuan else 1
		assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
		assert_eq(game_logic.decision_info.player, player1.my_id)
		assert_eq(game_logic.get_current_strike_timing(), "before")
		if special_index == 5:
			assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseSimultaneousEffect)
			var move_index = -1
			for i in range(game_logic.decision_info.choice.size()):
				if game_logic.decision_info.choice[i]["effect_type"] == StrikeEffects.MoveToAnySpace:
					move_index = i
			assert_gte(move_index, 0)
			if move_index < 0:
				return
			assert_true(game_logic.do_choice(player1, move_index))
			assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect)
			assert_eq(game_logic.decision_info.player, player1.my_id)
			assert_true(0 in game_logic.decision_info.limitation, "Move up to retains the zero option.")
			assert_true(5 + extra in game_logic.decision_info.limitation, "Advance skips the occupied space.")
			assert_false(6 + extra in game_logic.decision_info.limitation)
			assert_true(game_logic.do_choice(player1, 0))
			assert_eq(player1.arena_location, 3)
		assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
		assert_eq(game_logic.decision_info.choice[0]["_choice_text"], "T6继续攻击")
		if special_index == 2:
			assert_eq(player1.strike_stat_boosts.power, 2 + extra)
		elif special_index == 3:
			assert_eq(player1.strike_stat_boosts.guard, 2 + extra)
		elif special_index == 6:
			assert_eq(player1.strike_stat_boosts.speed, 1 + extra)
		var hand_before_hit = player1.hand.size()
		assert_true(game_logic.do_choice(player1, 0))
		if special_index == 4 and not huhuan:
			assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseSimultaneousEffect)
			var draw_index = -1
			for i in range(game_logic.decision_info.choice.size()):
				if game_logic.decision_info.choice[i]["effect_type"] == StrikeEffects.Draw:
					draw_index = i
			assert_gte(draw_index, 0)
			if draw_index < 0:
				return
			assert_true(game_logic.do_choice(player1, draw_index))
		if not huhuan:
			assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
			assert_eq(game_logic.decision_info.player, player1.my_id)
			assert_true(game_logic.do_choice(player1, 0))
		else:
			_finish_t6_huhuan_cleanup(ids["attack_id"])
		assert_null(game_logic.active_strike)
		if special_index == 4:
			assert_eq(player1.hand.size(), hand_before_hit + 2 + extra)
		else:
			assert_eq(player1.hand.size(), hand_before_hit)
		var damage = (5 if huhuan else 3) + ((2 + extra) if special_index == 2 else 0) - 2
		assert_eq(player2.life, 100 - damage)
		assert_eq(_definition(special_index), original, "Shared runtime definition must not be scaled.")
		assert_true(player1.is_card_in_discards(ids["source_id"]))


func test_guardian_scale_power_three_and_four():
	_check_guardian_scaling(2)


func test_guardian_scale_guard_three_and_four():
	_check_guardian_scaling(3)


func test_guardian_scale_hit_draw_three_and_four():
	_check_guardian_scaling(4)


func test_guardian_scale_before_move_up_to_two_and_three():
	_check_guardian_scaling(5)


func test_guardian_scale_speed_two_and_three():
	_check_guardian_scaling(6)


func test_huhuan_attack_ex_does_not_duplicate_guardian_amplification():
	var ids = _setup_scaled_guardian(2, true, true)
	assert_eq(game_logic.decision_info.choice[0]["_choice_text"], "T6继续攻击")
	assert_eq(player1.strike_stat_boosts.power, 5, "EX +1 plus the guardian's +4, not +5 guardian.")
	assert_true(game_logic.do_choice(player1, 0))
	_finish_t6_huhuan_cleanup(ids["attack_id"])
	assert_null(game_logic.active_strike)
	assert_eq(player2.life, 92, "Printed5 + EX1 + guardian4 - Focus armor2.")


func test_huhuan_attack_without_guardian_costs_two():
	player1.life = 100
	player2.life = 100
	position_players(player1, 3, player2, 4)
	var attack = give_player_specific_card(player1, "heiqiyihu_呼唤我的名字吧！")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	var payment = give_gauge(player1, 2)
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_eq(game_logic.get_gauge_cost(player1, game_logic.card_db.get_card(attack)), 2)
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_PayStrikeCost_Required)
	assert_eq(game_logic.decision_info.cost, 2)
	assert_true(game_logic.do_pay_strike_cost(player1, payment, false))
	_finish_t6_huhuan_cleanup(attack)
	assert_null(game_logic.active_strike)
	assert_eq(player2.life, 97)
	for paid_id in payment:
		assert_true(player1.is_card_in_discards(paid_id))


func test_huhuan_attack_insufficient_cost_wild_replacement_keeps_only_base_scale():
	player1.life = 100
	player2.life = 100
	position_players(player1, 3, player2, 4)
	_give_guardian(player1, "heiqiyihu_地裂崩击")
	var attack = give_player_specific_card(player1, "heiqiyihu_呼唤我的名字吧！")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	var payment = give_gauge(player1, 2)
	var replacement = set_player_topdeck(player1, "gg_normal_grasp")
	assert_eq(player1.deck[0].id, replacement)
	assert_false(replacement in payment)
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	assert_true(game_logic.do_choice(player1, 0))
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.active_strike.initiator_card.id, replacement)
	assert_true(game_logic.active_strike.initiator_wild_strike)
	assert_true(player1.is_card_in_discards(attack))
	assert_eq(player1.strike_stat_boosts.power, 3, "Invalid Huhuan must not leave the second +1.")
	for unpaid_id in payment:
		assert_true(player1.is_card_in_gauge(unpaid_id))
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player2.life, 96)
	assert_null(game_logic.active_strike)


func test_guardian_scale_normal_guardian_is_not_amplified_by_huhuan():
	player1.life = 100
	player2.life = 100
	position_players(player1, 3, player2, 4)
	var source_id = _give_guardian(player1, "gg_normal_grasp")
	var attack = give_player_specific_card(player1, "heiqiyihu_呼唤我的名字吧！")
	var attack_card = game_logic.card_db.get_card(attack)
	attack_card.definition = attack_card.definition.duplicate(true)
	attack_card.definition["effects"].append({
		"timing": "hit", "effect_type": StrikeEffects.Choice,
		"choice": [{"effect_type": StrikeEffects.Pass, "_choice_text": "C8检查Hit后继续伤害"}]
	})
	var response = give_player_specific_card(player2, "gg_normal_focus")
	var payment = give_gauge(player1, 3)
	var hand_size = player1.hand.size()
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player1.hand.size(), hand_size + 1, "Normal guardian Now remains draw1.")
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_eq(game_logic.decision_info.cost, 3)
	assert_true(game_logic.do_pay_strike_cost(player1, payment, false))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseSimultaneousEffect)
	var power_index = -1
	for i in range(game_logic.decision_info.choice.size()):
		if game_logic.decision_info.choice[i]["effect_type"] == StrikeEffects.Powerup:
			power_index = i
	assert_gte(power_index, 0)
	assert_true(game_logic.do_choice(player1, power_index))
	assert_eq(player1.strike_stat_boosts.power, 1, "Normal guardian Hit remains power+1.")
	assert_true(player1.is_card_in_gauge(source_id))
	assert_eq(player2.life, 100, "Checkpoint observes Hit before damage, not cleared stats after Cleanup.")
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player2.life, 96)
	_finish_t6_huhuan_cleanup(attack)


func test_guardian_scale_normal_special_boost_retains_printed_two():
	player1.life = 100
	player2.life = 100
	position_players(player1, 3, player2, 4)
	var source_id = give_player_specific_card(player1, "heiqiyihu_地裂崩击")
	assert_true(game_logic.do_boost(player1, source_id))
	var attack = give_player_specific_card(player1, "gg_normal_grasp")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(player1.strike_stat_boosts.power, 2)
	assert_eq(game_logic.active_strike.heiqiyihu_guardian_records.size(), 0)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player2.life, 97)
	assert_null(game_logic.active_strike)


func test_guardian_scale_ultra_preserves_range_and_power_metadata():
	var source_id = _give_guardian(player1, "heiqiyihu_呼唤我的名字吧！")
	var definition = _definition(0).duplicate(true)
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	assert_true(game_logic.do_choice(player1, 0))
	var record = game_logic.active_strike.heiqiyihu_guardian_records[0]
	assert_eq(record["source_id"], source_id)
	assert_eq(game_logic._get_heiqiyihu_guardian_boost(record), definition["boost"])
	var power_effects = game_logic.get_boost_effects_at_timing("during_strike", player1)
	assert_eq(power_effects.size(), 2)
	assert_eq(power_effects[0]["amount"], 3)
	assert_eq(power_effects[1]["amount"], 0)
	assert_eq(power_effects[1]["amount2"], 1)
	assert_eq(_definition(0), definition)


func test_exceed_guardian_counts_draw_two_two_four_six_immediately_once():
	for count in range(4):
		_restart_for_opening(30, 30)
		assert_true(game_logic.do_mulligan(player1, []))
		assert_true(game_logic.do_mulligan(player2, []))
		for i in range(count):
			_give_guardian(player1, "gg_normal_grasp")
		var hand_size = player1.hand.size()
		var deck_size = player1.deck.size()
		game_logic.get_latest_events()
		player1.exceed()
		var draw_count = max(2, count * 2)
		assert_true(player1.exceeded)
		assert_eq(player1.hand.size(), hand_size + draw_count)
		assert_eq(player1.deck.size(), deck_size - draw_count)
		assert_eq(player1.bleach_zone.size(), count)
		assert_true(player1.heiqiyihu_skip_hand_limit_this_turn)
		assert_false(player1.skip_end_of_turn_draw)
		assert_eq(player1.max_hand_size, 7)
		var events = game_logic.get_latest_events()
		assert_eq(validate_has_event(events, Enums.EventType.EventType_Exceed, player1).size(), 1)
		assert_eq(validate_has_event(events, Enums.EventType.EventType_Draw, player1).size(), draw_count)
		player1.exceed()
		assert_eq(player1.hand.size(), hand_size + draw_count)
		assert_true(game_logic.get_latest_events().is_empty(), "Already exceeded does not emit or draw again.")


func test_exceed_action_keeps_normal_end_turn_draw_and_skips_only_current_hand_limit():
	for i in range(3):
		_give_guardian(player1, "gg_normal_grasp")
	var hand_size = player1.hand.size()
	game_logic.get_latest_events()
	assert_true(game_logic.do_exceed(player1, []))
	assert_true(player1.exceeded)
	assert_eq(player1.hand.size(), hand_size + 6 + 1, "Six awakening cards plus the separate ordinary EOT card.")
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	assert_eq(game_logic.active_turn_player, player2.my_id)
	assert_false(player1.heiqiyihu_skip_hand_limit_this_turn)
	assert_eq(player1.max_hand_size, 7)
	var events = game_logic.get_latest_events()
	assert_eq(validate_has_event(events, Enums.EventType.EventType_Draw, player1).size(), 7)
	validate_not_has_event(events, Enums.EventType.EventType_HandSizeExceeded, player1)
	assert_true(game_logic.do_prepare(player2))
	assert_eq(game_logic.active_turn_player, player2.my_id)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_DiscardDownToMax)
	assert_eq(player2.hand.size(), 8)
	assert_true(game_logic.do_discard_to_max(player2, [player2.hand[0].id]))
	assert_eq(player2.hand.size(), 7)
	assert_eq(game_logic.active_turn_player, player1.my_id)
	game_logic.get_latest_events()
	assert_true(game_logic.do_prepare(player1))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_DiscardDownToMax)
	validate_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_HandSizeExceeded, player1, player1.hand.size() - 7)
	assert_false(player1.heiqiyihu_skip_hand_limit_this_turn)
	var discard_ids = []
	for card in player1.hand.slice(0, player1.hand.size() - 7):
		discard_ids.append(card.id)
	assert_true(game_logic.do_discard_to_max(player1, discard_ids))
	assert_eq(player1.hand.size(), 7)
	assert_eq(game_logic.active_turn_player, player2.my_id)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)


func test_exceed_cleanup_uses_same_draw_without_non_strike_end_turn_card():
	position_players(player1, 3, player2, 7)
	for i in range(2):
		_give_guardian(player1, "gg_normal_grasp")
	var attack_id = give_player_specific_card(player1, "gg_normal_grasp")
	var attack = game_logic.card_db.get_card(attack_id)
	attack.definition = attack.definition.duplicate(true)
	attack.definition["effects"].append({"timing": "cleanup", "effect_type": StrikeEffects.ExceedNow})
	var response = give_player_specific_card(player2, "gg_normal_focus")
	var hand_size = player1.hand.size()
	game_logic.get_latest_events()
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	assert_true(game_logic.do_choice(player1, game_logic.decision_info.choice.size() - 1))
	assert_true(game_logic.do_strike(player1, attack_id, false, -1))
	assert_false(player1.exceeded)
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_null(game_logic.active_strike)
	assert_true(player1.exceeded)
	assert_eq(player1.hand.size(), hand_size - 1 + 4)
	assert_eq(player1.bleach_zone.size(), 2)
	assert_false(player1.heiqiyihu_skip_hand_limit_this_turn)
	var events = game_logic.get_latest_events()
	assert_eq(validate_has_event(events, Enums.EventType.EventType_Draw, player1).size(), 4)
	assert_eq(validate_has_event(events, Enums.EventType.EventType_Exceed, player1).size(), 1)
	validate_not_has_event(events, Enums.EventType.EventType_HandSizeExceeded, player1)


func test_exceed_stops_threshold_and_pre_set_ability_without_resetting_used():
	_give_guardian(player1, "gg_normal_grasp")
	player1.heiqiyihu_thresholds_used.append(25)
	player1.exceed()
	_take_damage(player1, 20)
	assert_eq(player1.life, 10)
	assert_eq(player1.heiqiyihu_thresholds_used, [25])
	assert_true(game_logic.heiqiyihu_pending_thresholds.is_empty())
	assert_true(game_logic.heiqiyihu_threshold_context.is_empty())
	assert_false(game_logic._has_heiqiyihu_guardian_option())
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)


func test_exceed_empty_deck_draw_reshuffles_without_spending_guardians():
	var guardian = _give_guardian(player1, "gg_normal_grasp")
	player1.discards.append_array(player1.deck)
	player1.deck.clear()
	var hand_size = player1.hand.size()
	game_logic.get_latest_events()
	player1.exceed()
	assert_eq(player1.hand.size(), hand_size + 2)
	assert_eq(player1.reshuffle_remaining, 0)
	assert_true(player1.is_card_in_bleach(guardian))
	assert_false(game_logic.game_over)
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_ReshuffleDiscard, player1)
	assert_eq(validate_has_event(events, Enums.EventType.EventType_Draw, player1).size(), 2)


func test_exceed_empty_deck_without_reshuffle_decks_out():
	player1.sealed.append_array(player1.deck)
	player1.deck.clear()
	player1.reshuffle_remaining = 0
	player1.exceed()
	assert_true(game_logic.game_over)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_GameOver)
	assert_eq(game_logic.game_over_winning_player, player2)


func test_exceed_deckout_event_count_matches_preexisting_plain_draw_baseline():
	game_logic.teardown()
	game_logic.free()
	default_game_setup("solbadguy")
	assert_eq(player2.deck_def["id"], "solbadguy")
	assert_false(player2.exceeded)
	player2.sealed.append_array(player2.deck)
	player2.deck.clear()
	player2.reshuffle_remaining = 0
	game_logic.get_latest_events()
	player2.draw(2)
	var baseline_events = game_logic.get_latest_events()
	var baseline_count = validate_has_event(baseline_events, Enums.EventType.EventType_GameOver, player2).size()
	assert_eq(baseline_count, 2, "Baseline evidence only: the existing draw loop emits once for each requested draw.")
	assert_eq(game_logic.game_over_winning_player, player1)
	_restart_for_opening(30, 30)
	assert_true(game_logic.do_mulligan(player1, []))
	assert_true(game_logic.do_mulligan(player2, []))
	player1.sealed.append_array(player1.deck)
	player1.deck.clear()
	player1.reshuffle_remaining = 0
	game_logic.get_latest_events()
	player1.exceed()
	var awakening_events = game_logic.get_latest_events()
	assert_eq(validate_has_event(awakening_events, Enums.EventType.EventType_GameOver, player1).size(), baseline_count)
	validate_not_has_event(awakening_events, Enums.EventType.EventType_Draw, player1)
	assert_eq(game_logic.game_over_winning_player, player2)


func _payment_boost(effect: Dictionary, force_cost: int = 0, gauge_cost: int = -1) -> int:
	var boost_id = give_player_specific_card(player1, "gg_normal_slash")
	var card = game_logic.card_db.get_card(boost_id)
	card.definition = card.definition.duplicate(true)
	card.definition["boost"]["force_cost"] = force_cost
	card.definition["boost"]["cancel_cost"] = -1
	card.definition["boost"]["effects"] = [effect.duplicate(true)]
	card.definition["boost"]["effects"][0]["timing"] = "now"
	if gauge_cost >= 0:
		card.definition["boost"]["gauge_cost"] = gauge_cost
	return boost_id


func test_c8_hit_special_and_ultra_normal_gauge_without_guardian_decision():
	for definition_id in ["heiqiyihu_全力一击", "heiqiyihu_呼唤我的名字吧！"]:
		_restart_for_opening(100, 100)
		assert_true(game_logic.do_mulligan(player1, []))
		assert_true(game_logic.do_mulligan(player2, []))
		position_players(player1, 3, player2, 4)
		var attack = give_player_specific_card(player1, definition_id)
		var response = give_player_specific_card(player2, "gg_normal_focus")
		var cost = 2 if definition_id == "heiqiyihu_呼唤我的名字吧！" else 0
		var payment = give_gauge(player1, cost)
		game_logic.get_latest_events()
		assert_true(game_logic.do_strike(player1, attack, false, -1))
		assert_true(game_logic.do_strike(player2, response, false, -1))
		if cost > 0:
			assert_true(game_logic.do_pay_strike_cost(player1, payment, false))
		assert_null(game_logic.active_strike)
		assert_ne(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
		assert_true(player1.is_card_in_gauge(attack))
		assert_false(player1.is_card_in_bleach(attack))
		assert_eq(player2.life, 97 if cost else 98)
		validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Strike_EffectChoice, player1)


func test_c8_other_character_generic_destination_capability_is_not_disabled():
	# Minato is a real existing character. This isolated fixture opts it into
	# the shared zone capability, not a claim that native Minato has this zone.
	_restart_for_opening(100, 100, Enums.PlayerId.PlayerId_Opponent, "minato")
	assert_true(game_logic.do_mulligan(player1, []))
	assert_true(game_logic.do_mulligan(player2, []))
	player2.deck_def["stored_bleach_info"] = {"name": "通用回归区"}
	assert_true(player2.has_bleach_zone())
	position_players(player1, 3, player2, 4)
	var attack = give_player_specific_card(player2, "heiqiyihu_全力一击")
	var response = give_player_specific_card(player1, "gg_normal_focus")
	assert_true(game_logic.do_strike(player2, attack, false, -1))
	assert_true(game_logic.do_strike(player1, response, false, -1))
	assert_eq(game_logic.decision_info.player, player2.my_id)
	assert_eq(game_logic.get_current_strike_timing(), "cleanup")
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.choice[0]["_choice_text"], "加入通用回归区")
	assert_true(game_logic.do_choice(player2, 0))
	assert_null(game_logic.active_strike)
	assert_true(player2.is_card_in_bleach(attack))
	assert_false(player2.is_card_in_gauge(attack))


func _add_shunbu_checkpoint(card_id: int):
	var card = game_logic.card_db.get_card(card_id)
	card.definition = card.definition.duplicate(true)
	card.definition["effects"].append({
		"timing": "before", "effect_type": StrikeEffects.Choice,
		"choice": [{"effect_type": StrikeEffects.Pass, "_choice_text": "T16前置后检查"}]
	})


func _shunbu_before_window(own: int, other: int, destination: int, blocked: bool = false, extra_armor: bool = false) -> int:
	_restart_for_opening(100, 100)
	assert_true(game_logic.do_mulligan(player1, []))
	assert_true(game_logic.do_mulligan(player2, []))
	position_players(player1, own, player2, other)
	player1.cannot_move = blocked
	var attack = give_player_specific_card(player1, "heiqiyihu_瞬步")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	if extra_armor:
		var card = game_logic.card_db.get_card(response)
		card.definition = card.definition.duplicate(true)
		card.definition["effects"].append({"timing": "during_strike", "effect_type": StrikeEffects.Armorup, "amount": 1})
	_add_shunbu_checkpoint(attack)
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseSimultaneousEffect)
	var move_index = -1
	for i in range(game_logic.decision_info.choice.size()):
		if game_logic.decision_info.choice[i]["effect_type"] == StrikeEffects.MoveToAnySpace:
			move_index = i
	assert_gte(move_index, 0)
	assert_true(game_logic.do_choice(player1, move_index))
	if not blocked:
		assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect)
		assert_eq(game_logic.decision_info.player, player1.my_id)
		assert_eq(game_logic.get_current_strike_timing(), "before")
		assert_true(0 in game_logic.decision_info.limitation)
		# Moving away is not part of "advance up to3".
		var retreat_space = own - 1 if own < other else own + 1
		if retreat_space >= 1 and retreat_space <= 9:
			assert_false(retreat_space in game_logic.decision_info.limitation, "No retreat destination in advance-only choice.")
		var index = game_logic.decision_info.limitation.find(destination)
		assert_gte(index, 0)
		assert_true(game_logic.do_choice(player1, index))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.decision_info.choice[0]["_choice_text"], "T16前置后检查")
	assert_eq(player1.arena_location, own if destination == 0 or blocked else destination)
	assert_eq(player2.life, 100)
	return attack


func test_shunbu_attack_real_cross_left_right_one_two_three_and_edges():
	for setup in [[3, 4, 5], [3, 5, 6], [3, 6, 7], [7, 6, 5],
		[7, 5, 4], [7, 4, 3], [1, 2, 3], [9, 8, 7], [3, 4, 7]]:
		var attack = _shunbu_before_window(setup[0], setup[1], setup[2])
		assert_true(player1.strike_stat_boosts.range_includes_opponent)
		assert_true(player1.strike_stat_boosts.ignore_guard)
		assert_false(player1.strike_stat_boosts.ignore_armor)
		assert_eq(game_logic.get_total_armor(player2), 2)
		game_logic.get_latest_events()
		assert_true(game_logic.do_choice(player1, 0))
		assert_null(game_logic.active_strike, "C8: no generic guardian destination after hitting.")
		assert_eq(player2.life, 99, "Power3 minus armor2: ignores guard, not armor.")
		assert_eq(player1.life, 100)
		assert_true(player1.is_card_in_gauge(attack))
		var events = game_logic.get_latest_events()
		validate_has_event(events, Enums.EventType.EventType_Strike_Stun, player2)
		validate_not_has_event(events, Enums.EventType.EventType_Strike_GainAdvantage, player1)
		assert_eq(game_logic.active_turn_player, player2.my_id)
		assert_false(player1.strike_stat_boosts.range_includes_opponent)
		assert_false(player1.strike_stat_boosts.ignore_guard)


func test_shunbu_attack_zero_no_cross_and_blocked_miss_gain_advantage():
	for setup in [[3, 4, 0, false], [3, 7, 5, false], [7, 3, 5, false], [3, 4, 0, true]]:
		var attack = _shunbu_before_window(setup[0], setup[1], setup[2], setup[3])
		assert_false(player1.strike_stat_boosts.range_includes_opponent)
		assert_false(player1.strike_stat_boosts.ignore_guard)
		assert_eq(game_logic.get_total_min_range(player1), 0)
		assert_eq(game_logic.get_total_max_range(player1), 0)
		game_logic.get_latest_events()
		assert_true(game_logic.do_choice(player1, 0))
		assert_null(game_logic.active_strike)
		assert_eq(player2.life, 100)
		assert_true(player1.is_card_in_discards(attack))
		assert_eq(game_logic.active_turn_player, player1.my_id)
		assert_eq(validate_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Strike_GainAdvantage, player1).size(), 1)


func test_shunbu_attack_stunned_before_before_never_moves_or_gets_advantage():
	_restart_for_opening(100, 100, Enums.PlayerId.PlayerId_Opponent)
	assert_true(game_logic.do_mulligan(player1, []))
	assert_true(game_logic.do_mulligan(player2, []))
	position_players(player1, 3, player2, 4)
	var attack = give_player_specific_card(player1, "heiqiyihu_瞬步")
	var response = give_player_specific_card(player2, "gg_normal_grasp")
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_eq(game_logic.decision_info.player, player2.my_id)
	game_logic.get_latest_events()
	assert_true(game_logic.do_choice(player2, 0))
	assert_null(game_logic.active_strike)
	assert_eq(player1.life, 97)
	assert_true(player1.is_card_in_discards(attack))
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_Strike_Stun, player1)
	validate_not_has_event(events, Enums.EventType.EventType_Strike_GainAdvantage, player1)
	validate_not_has_event(events, Enums.EventType.EventType_ChooseArenaLocationForEffect, player1)


func test_shunbu_attack_cross_does_not_dodge_and_next_strike_clears_flags():
	var attack = _shunbu_before_window(3, 4, 5, false, true)
	assert_eq(game_logic.get_total_armor(player2), 3)
	game_logic.get_latest_events()
	assert_true(game_logic.do_choice(player1, 0))
	assert_null(game_logic.active_strike)
	assert_eq(player2.life, 100, "Armor3 absorbs Shunbu's power3.")
	assert_eq(player1.life, 96, "The opponent can still hit after being crossed.")
	assert_true(player1.is_card_in_gauge(attack), "Range hit, not damage, decides attack destination.")
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_Strike_TookDamage, player1, 4)
	validate_not_has_event(events, Enums.EventType.EventType_Strike_GainAdvantage, player1)
	assert_false(player1.strike_stat_boosts.ignore_guard)
	assert_false(player1.strike_stat_boosts.range_includes_opponent)
	position_players(player1, 3, player2, 6)
	var next_attack = give_player_specific_card(player1, "gg_normal_grasp")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_true(game_logic.do_strike(player1, next_attack, false, -1))
	assert_null(game_logic.active_strike)
	assert_true(player1.is_card_in_discards(next_attack), "A later range1 attack at distance3 still misses.")
	assert_eq(player2.life, 100)


func _check_shunbu_boost_speed(mode: int):
	_restart_for_opening(100, 100, Enums.PlayerId.PlayerId_Opponent if mode == 1 else Enums.PlayerId.PlayerId_Player)
	assert_true(game_logic.do_mulligan(player1, []))
	assert_true(game_logic.do_mulligan(player2, []))
	position_players(player1, 3, player2, 5)
	var source = give_player_specific_card(player1, "heiqiyihu_瞬步") if mode == 0 else _give_guardian(player1, "heiqiyihu_瞬步")
	if mode == 0:
		assert_true(game_logic.do_boost(player1, source))
	var attack = give_player_specific_card(player1, "heiqiyihu_呼唤我的名字吧！" if mode == 2 else "gg_normal_focus")
	var response = give_player_specific_card(player2, "gg_normal_grasp" if mode == 2 else "gg_normal_sweep")
	_add_shunbu_checkpoint(attack)
	_add_shunbu_checkpoint(response)
	var payment = give_gauge(player1, 3) if mode == 2 else []
	if mode < 2:
		assert_true(game_logic.do_strike(player2, -1 if mode == 1 else response, false, -1))
		if mode == 1:
			assert_true(game_logic.do_choice(player1, 0))
			assert_true(game_logic.do_strike(player2, response, false, -1))
		assert_true(game_logic.do_strike(player1, attack, false, -1))
	else:
		assert_true(game_logic.do_strike(player1, -1, false, -1))
		assert_true(game_logic.do_choice(player1, 0))
		assert_true(game_logic.do_strike(player1, attack, false, -1))
		assert_true(game_logic.do_strike(player2, response, false, -1))
		assert_true(game_logic.do_pay_strike_cost(player1, payment, false))
	var first = player2 if mode == 0 else player1
	assert_eq(game_logic.decision_info.player, first.my_id)
	assert_eq(game_logic.get_current_strike_timing(), "before")
	assert_eq(game_logic.get_total_speed(player1), 8 if mode == 2 else 2 + mode)
	assert_false(player1.strike_stat_boosts.ignore_guard)
	assert_false(player1.strike_stat_boosts.range_includes_opponent)
	assert_true(game_logic.do_choice(first, 0))
	if mode < 2:
		var second = player1 if mode == 0 else player2
		assert_eq(game_logic.decision_info.player, second.my_id)
		assert_eq(game_logic.get_current_strike_timing(), "before")
		assert_true(game_logic.do_choice(second, 0))
	assert_null(game_logic.active_strike)
	assert_true(player1.is_card_in_discards(source))
	assert_eq(player1.arena_location, 3, "Boost does not acquire the attack's movement.")
	assert_eq(player2.arena_location, 5)
	assert_eq(_definition(6)["boost"]["effects"][0]["amount"], 1)


func test_shunbu_boost_normal_one_speed_tie_opponent_initiates():
	_check_shunbu_boost_speed(0)


func test_shunbu_boost_guardian_two_speed_wins_while_defending():
	_check_shunbu_boost_speed(1)


func test_shunbu_boost_huhuan_three_speed_wins():
	_check_shunbu_boost_speed(2)


func test_quanli_attack_close_two_both_directions_adjacent_edges_and_shortfall():
	for setup in [[3, 6, 5, true], [7, 4, 5, true], [3, 7, 5, false],
		[7, 3, 5, false], [3, 4, 3, true], [1, 2, 1, true], [9, 8, 9, true]]:
		_restart_for_opening(100, 100)
		assert_true(game_logic.do_mulligan(player1, []))
		assert_true(game_logic.do_mulligan(player2, []))
		position_players(player1, setup[0], player2, setup[1])
		var attack = give_player_specific_card(player1, "heiqiyihu_全力一击")
		var response = give_player_specific_card(player2, "gg_normal_focus")
		assert_true(game_logic.do_strike(player1, attack, false, -1))
		assert_true(game_logic.do_strike(player2, response, false, -1))
		assert_eq(player1.arena_location, setup[2], "Close stops at adjacency, never passes the opponent.")
		assert_eq(player2.arena_location, setup[1])
		assert_eq(player2.life, 98 if setup[3] else 100, "Power4 minus armor2 only within range1.")
		if setup[3]:
			_finish_t6_huhuan_cleanup(attack)
		else:
			assert_null(game_logic.active_strike)
			assert_true(player1.is_card_in_discards(attack))


func test_quanli_attack_close_respects_own_movement_restriction():
	_restart_for_opening(100, 100)
	assert_true(game_logic.do_mulligan(player1, []))
	assert_true(game_logic.do_mulligan(player2, []))
	position_players(player1, 3, player2, 6)
	player1.cannot_move = true
	var attack = give_player_specific_card(player1, "heiqiyihu_全力一击")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_eq(player1.arena_location, 3)
	assert_eq(player2.life, 100)
	assert_null(game_logic.active_strike)
	assert_true(player1.is_card_in_discards(attack))


func _quanli_boost_movement_window(mode: int, own_position: int = 3, opponent_position: int = 4) -> Dictionary:
	_restart_for_opening(100, 100)
	assert_true(game_logic.do_mulligan(player1, []))
	assert_true(game_logic.do_mulligan(player2, []))
	position_players(player1, own_position, player2, opponent_position)
	var source = give_player_specific_card(player1, "heiqiyihu_全力一击") if mode == 0 \
		else _give_guardian(player1, "heiqiyihu_全力一击")
	if mode == 0:
		assert_true(game_logic.do_boost(player1, source))
		assert_eq(player1.arena_location, own_position, "No Now movement when normally boosting.")
	var attack = give_player_specific_card(player1, "heiqiyihu_呼唤我的名字吧！" if mode == 2 else "gg_normal_dust")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	var payment = give_gauge(player1, 3) if mode == 2 else []
	if mode == 0:
		assert_true(game_logic.do_strike(player2, response, false, -1))
		assert_eq(player1.arena_location, own_position)
		assert_true(game_logic.do_strike(player1, attack, false, -1))
	else:
		assert_true(game_logic.do_strike(player1, -1, false, -1))
		assert_true(game_logic.do_choice(player1, 0))
		assert_eq(player1.arena_location, own_position, "Guardian setup has no Now movement either.")
		assert_true(game_logic.do_strike(player1, attack, false, -1))
		assert_true(game_logic.do_strike(player2, response, false, -1))
		if mode == 2:
			assert_true(game_logic.do_pay_strike_cost(player1, payment, false))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect)
	assert_eq(game_logic.get_current_strike_timing(), "before")
	assert_eq(player1.arena_location, own_position, "Movement waits for the actual Before location submission.")
	assert_eq(player2.life, 100)
	assert_true(0 in game_logic.decision_info.limitation)
	return {"source": source, "attack": attack}


func _check_quanli_boost_movement(mode: int):
	var destinations = [0, 2, 5]
	if mode >= 1:
		destinations.append(1)
		destinations.append(6)
	if mode == 2:
		destinations.append(7)
	for destination in destinations:
		var ids = _quanli_boost_movement_window(mode)
		assert_false(4 in game_logic.decision_info.limitation, "Occupied space is not a destination.")
		assert_true(5 + mode in game_logic.decision_info.limitation, "Advance skips the occupied space4.")
		assert_false(6 + mode in game_logic.decision_info.limitation, "Maximum distance is1/2/3, not unlimited.")
		assert_false(game_logic.do_choice(player2, 0))
		assert_false(game_logic.do_choice(player1, 9))
		assert_eq(player1.arena_location, 3)
		var destination_index = game_logic.decision_info.limitation.find(destination)
		assert_gte(destination_index, 0)
		assert_true(game_logic.do_choice(player1, destination_index))
		assert_eq(player1.arena_location, 3 if destination == 0 else destination)
		assert_eq(player2.arena_location, 4)
		if mode == 2 and abs(player1.arena_location - 4) <= 2:
			_finish_t6_huhuan_cleanup(ids["attack"])
		else:
			assert_null(game_logic.active_strike)
		assert_true(player1.is_card_in_discards(ids["source"]))
		assert_eq(_definition(5)["boost"]["effects"][0]["move_max"], 1, "Runtime source stays printed1.")


func test_quanli_boost_normal_move_zero_retreat_advance_and_cross_one():
	_check_quanli_boost_movement(0)


func test_quanli_boost_guardian_move_up_to_two():
	_check_quanli_boost_movement(1)


func test_quanli_boost_huhuan_guardian_move_up_to_three():
	_check_quanli_boost_movement(2)


func test_quanli_boost_both_board_edges_no_off_arena_destinations():
	for setup in [[1, 2, 3], [9, 8, 7]]:
		var ids = _quanli_boost_movement_window(0, setup[0], setup[1])
		assert_true(setup[2] in game_logic.decision_info.limitation)
		assert_false(-1 in game_logic.decision_info.limitation)
		assert_false(10 in game_logic.decision_info.limitation)
		var destination_index = game_logic.decision_info.limitation.find(setup[2])
		assert_gte(destination_index, 0)
		assert_true(game_logic.do_choice(player1, destination_index))
		assert_eq(player1.arena_location, setup[2])
		assert_null(game_logic.active_strike)
		assert_true(player1.is_card_in_discards(ids["source"]))


func _linghun_payment_window() -> Dictionary:
	_restart_for_opening(100, 100)
	assert_true(game_logic.do_mulligan(player1, []))
	assert_true(game_logic.do_mulligan(player2, []))
	position_players(player1, 3, player2, 6)
	var attack = give_player_specific_card(player1, "heiqiyihu_灵魂对接")
	var attack_card = game_logic.card_db.get_card(attack)
	attack_card.definition = attack_card.definition.duplicate(true)
	attack_card.definition["effects"].append({
		"timing": "after", "effect_type": StrikeEffects.Choice,
		"choice": [{"effect_type": StrikeEffects.Pass, "_choice_text": "C8检查伤害后继续整理"}]
	})
	var response = give_player_specific_card(player2, "gg_normal_focus")
	var paid = []
	for i in range(3):
		paid.append(give_player_specific_card(player1, "gg_normal_block"))
	var fresh = set_player_topdeck(player1, "gg_normal_block")
	paid.push_front(fresh)
	var hand_size = player1.hand.size()
	game_logic.get_latest_events()
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ForceForEffect)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.get_current_strike_timing(), "hit")
	assert_eq(game_logic.decision_info.effect["force_max"], 3)
	assert_eq(game_logic.decision_info.effect["min_force"], 0)
	assert_eq(player1.hand.size(), hand_size, "Setting the attack spends1, then Hit draws1 before the payment.")
	assert_true(player1.is_card_in_hand(fresh))
	assert_eq(player2.life, 100, "Payment is before damage, not After.")
	assert_eq(game_logic.get_total_armor(player2), 2, "Focus has printed armor2 even when its attack will miss.")
	var events = game_logic.get_latest_events()
	assert_eq(validate_has_event(events, Enums.EventType.EventType_Draw, player1, fresh).size(), 1)
	validate_not_has_event(events, Enums.EventType.EventType_Strike_TookDamage, player2)
	return {"attack": attack, "paid": paid, "fresh": fresh}


func _finish_linghun_payment_attack(attack: int):
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.get_current_strike_timing(), "after")
	assert_eq(game_logic.decision_info.choice[0]["_choice_text"], "C8检查伤害后继续整理")
	assert_true(game_logic.do_choice(player1, 0))
	_finish_t6_huhuan_cleanup(attack)


func test_linghun_attack_draw_before_zero_one_two_three_force_and_damage():
	for force in range(4):
		var ids = _linghun_payment_window()
		var hand_size = player1.hand.size()
		var payment = ids["paid"].slice(0, force)
		assert_false(game_logic.do_force_for_effect(player2, [], false))
		assert_true(game_logic.do_force_for_effect(player1, payment, false))
		assert_eq(player1.hand.size(), hand_size - force)
		assert_eq(player2.life, 99 - force, "Power3 + paid force - Focus armor2.")
		assert_eq(player2.strike_stat_boosts.consumed_armor, 2)
		for paid_id in payment:
			assert_true(player1.is_card_in_discards(paid_id))
		if force > 0:
			assert_true(player1.is_card_in_discards(ids["fresh"]), "The just-drawn card pays the Hit effect.")
		_finish_linghun_payment_attack(ids["attack"])


func test_linghun_attack_over_limit_duplicates_and_invalid_zone_do_not_consume():
	var ids = _linghun_payment_window()
	var hand_size = player1.hand.size()
	var foreign = player2.hand[0].id
	assert_false(game_logic.do_force_for_effect(player1, ids["paid"], false), "Four normal cards exceed3.")
	assert_false(game_logic.do_force_for_effect(player1, [ids["fresh"], ids["fresh"]], false))
	assert_false(game_logic.do_force_for_effect(player1, [foreign], false), "An opponent's card is not available force.")
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ForceForEffect)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(player1.hand.size(), hand_size)
	assert_eq(player2.life, 100)
	for paid_id in ids["paid"]:
		assert_true(player1.is_card_in_hand(paid_id))
	assert_true(game_logic.do_force_for_effect(player1, [], false))
	assert_eq(player2.life, 99, "Unboosted power3 is reduced by Focus armor2.")
	_finish_linghun_payment_attack(ids["attack"])


func test_linghun_attack_ultra_can_pay_one_or_two_and_mix_to_three():
	for force in [1, 2, 3]:
		var ids = _linghun_payment_window()
		var ultra = give_player_specific_card(player1, "heiqiyihu_虚化")
		var payment = [ultra]
		if force == 3:
			payment.append(ids["fresh"])
		assert_true(game_logic.do_force_for_effect(player1, payment, force == 1))
		assert_eq(player2.life, 99 - force, "Ultra payment changes power, not the opponent's armor2.")
		assert_true(player1.is_card_in_discards(ultra))
		if force == 3:
			assert_true(player1.is_card_in_discards(ids["fresh"]))
		_finish_linghun_payment_attack(ids["attack"])


func test_linghun_attack_miss_and_stunned_have_no_draw_or_payment():
	for stunned in [false, true]:
		_restart_for_opening(100, 100, Enums.PlayerId.PlayerId_Opponent if stunned else Enums.PlayerId.PlayerId_Player)
		assert_true(game_logic.do_mulligan(player1, []))
		assert_true(game_logic.do_mulligan(player2, []))
		position_players(player1, 3, player2, 5 if stunned else 4)
		var attack = give_player_specific_card(player1, "heiqiyihu_灵魂对接")
		var response = give_player_specific_card(player2, "gg_normal_dust" if stunned else "gg_normal_focus")
		var hand_size = player1.hand.size()
		game_logic.get_latest_events()
		if stunned:
			assert_true(game_logic.do_strike(player2, response, false, -1))
			assert_true(game_logic.do_strike(player1, attack, false, -1))
		else:
			assert_true(game_logic.do_strike(player1, attack, false, -1))
			assert_true(game_logic.do_strike(player2, response, false, -1))
		assert_null(game_logic.active_strike)
		assert_eq(player1.hand.size(), hand_size - 1)
		assert_eq(player2.life, 100)
		assert_true(player1.is_card_in_discards(attack))
		var events = game_logic.get_latest_events()
		validate_not_has_event(events, Enums.EventType.EventType_Draw, player1)
		validate_not_has_event(events, Enums.EventType.EventType_ForceForEffectConfirmed, player1)
		if stunned:
			assert_eq(player1.life, 95)
			validate_has_event(events, Enums.EventType.EventType_Strike_Stun, player1)


func test_linghun_boost_normal_hit_draw_two_no_attack_payment():
	_restart_for_opening(100, 100)
	assert_true(game_logic.do_mulligan(player1, []))
	assert_true(game_logic.do_mulligan(player2, []))
	position_players(player1, 3, player2, 5)
	var source = give_player_specific_card(player1, "heiqiyihu_灵魂对接")
	assert_true(game_logic.do_boost(player1, source))
	var attack = give_player_specific_card(player1, "gg_normal_dust")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	var hand_size = player1.hand.size()
	game_logic.get_latest_events()
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_null(game_logic.active_strike)
	assert_eq(player1.hand.size(), hand_size - 1 + 2)
	assert_eq(player2.life, 95)
	assert_true(player1.is_card_in_discards(source))
	var events = game_logic.get_latest_events()
	assert_eq(validate_has_event(events, Enums.EventType.EventType_Draw, player1).size(), 2)
	validate_not_has_event(events, Enums.EventType.EventType_ForceForEffectConfirmed, player1)


func test_linghun_boost_guardian_hit_draw_three_and_huhuan_four():
	_check_guardian_scaling(4)


func test_linghun_boost_miss_or_stunned_never_draws():
	for stunned in [false, true]:
		_restart_for_opening(100, 100)
		assert_true(game_logic.do_mulligan(player1, []))
		assert_true(game_logic.do_mulligan(player2, []))
		position_players(player1, 3, player2, 5 if stunned else 7)
		var source = give_player_specific_card(player1, "heiqiyihu_灵魂对接")
		assert_true(game_logic.do_boost(player1, source))
		var attack = give_player_specific_card(player1, "gg_normal_focus" if stunned else "gg_normal_dust")
		var response = give_player_specific_card(player2, "gg_normal_dust" if stunned else "gg_normal_focus")
		var hand_size = player1.hand.size()
		game_logic.get_latest_events()
		assert_true(game_logic.do_strike(player2, response, false, -1))
		assert_true(game_logic.do_strike(player1, attack, false, -1))
		assert_null(game_logic.active_strike)
		assert_eq(player1.hand.size(), hand_size - 1)
		assert_true(player1.is_card_in_discards(source))
		validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Draw, player1)


func test_linghun_attack_and_boost_both_players_sort_atomic_hit_and_restore_owner():
	_restart_for_opening(100, 100)
	assert_true(game_logic.do_mulligan(player1, []))
	assert_true(game_logic.do_mulligan(player2, []))
	position_players(player1, 3, player2, 5)
	for participant in [player1, player2]:
		var source = give_player_specific_card(participant, "heiqiyihu_灵魂对接")
		assert_true(game_logic.do_boost(participant, source))
	var attack = give_player_specific_card(player1, "heiqiyihu_灵魂对接")
	var response = give_player_specific_card(player2, "heiqiyihu_灵魂对接")
	var first_hand = player1.hand.size()
	var second_hand = player2.hand.size()
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	for participant in [player1, player2]:
		assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseSimultaneousEffect)
		assert_eq(game_logic.decision_info.player, participant.my_id)
		assert_eq(game_logic.get_current_strike_timing(), "hit")
		assert_eq(game_logic.decision_info.choice.size(), 2, "Attack draw/payment is one sortable item, boost draw is the other.")
		var attack_index = -1
		for i in range(game_logic.decision_info.choice.size()):
			if game_logic.decision_info.choice[i].get("amount", 0) == 1:
				attack_index = i
		assert_gte(attack_index, 0)
		if attack_index < 0:
			return
		var own_hand = participant.hand.size()
		assert_true(game_logic.do_choice(participant, attack_index))
		assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ForceForEffect)
		assert_eq(game_logic.decision_info.player, participant.my_id)
		assert_eq(participant.hand.size(), own_hand + 1, "Draw2 has not intruded into atomic Draw1/payment.")
		assert_true(game_logic.do_force_for_effect(participant, [], false))
	assert_eq(player1.hand.size(), first_hand + 2)
	assert_eq(player2.hand.size(), second_hand + 2)
	assert_eq(player1.life, 97)
	assert_eq(player2.life, 97)
	assert_null(game_logic.active_strike)
	assert_ne(game_logic.game_state, Enums.GameState.GameState_PlayerDecision, "Neither player receives the unlisted Cleanup option.")
	assert_true(player1.is_card_in_gauge(attack))
	assert_true(player2.is_card_in_gauge(response))


func _jingxue_grasp_window(movement_probe: bool = false, reset_probe: bool = true) -> int:
	_restart_for_opening(100, 100)
	assert_true(game_logic.do_mulligan(player1, []))
	assert_true(game_logic.do_mulligan(player2, []))
	position_players(player1, 3, player2, 4)
	var attack = give_player_specific_card(player1, "heiqiyihu_静血装")
	var response = give_player_specific_card(player2, "gg_normal_grasp")
	if movement_probe:
		var attack_card = game_logic.card_db.get_card(attack)
		attack_card.definition = attack_card.definition.duplicate(true)
		attack_card.definition["effects"].append({
			"timing": "before", "effect_type": StrikeEffects.Advance, "amount": 1,
			"and": {
				"effect_type": StrikeEffects.Advance, "amount": 1,
				"and": {"effect_type": StrikeEffects.MoveToSpace, "amount": 6, "remove_buddies_encountered": 0}
			}
		})
		var response_card = game_logic.card_db.get_card(response)
		response_card.definition = response_card.definition.duplicate(true)
		response_card.definition["effects"].append({
			"timing": "before", "effect_type": StrikeEffects.Pull, "amount": 1,
			"and": {
				"effect_type": StrikeEffects.MoveToSpace, "amount": 1,
				"remove_buddies_encountered": 0, "for_other_player": true,
				"and": {
					"effect_type": StrikeEffects.Advance, "amount": 1,
					"and": {
						"effect_type": StrikeEffects.Retreat, "amount": 1,
						"and": {"effect_type": StrikeEffects.Draw, "amount": 1}
					}
				}
			}
		})
		response_card.definition["effects"].append({
			"timing": "after", "effect_type": StrikeEffects.Retreat, "amount": 1,
			"and": {"effect_type": StrikeEffects.ResetCharacterPositions} if reset_probe else null
		})
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_eq(game_logic.decision_info.player, player2.my_id)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.get_current_strike_timing(), "hit")
	assert_true(player1.strike_stat_boosts.heiqiyihu_prevent_opponent_moving_me)
	return attack


func _assert_jingxue_after():
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.get_current_strike_timing(), "after")
	assert_eq(game_logic.decision_info.choice.size(), 2)
	assert_eq(game_logic.decision_info.choice[0]["_choice_text"], "将静血装置入守护区")
	assert_eq(game_logic.decision_info.choice[1]["_choice_text"], "不置入守护区")


func test_jingxue_attack_push_pull_blocked_after_accept_or_decline_unique_zone():
	for accept in [true, false]:
		var attack = _jingxue_grasp_window()
		game_logic.get_latest_events()
		# Grasp's first option is a genuine attempted push.
		assert_true(game_logic.do_choice(player2, 0))
		assert_eq(player1.arena_location, 3)
		assert_eq(player1.life, 100)
		_assert_jingxue_after()
		validate_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Strike_IgnoredPushPull, player1)
		assert_false(game_logic.do_choice(player2, 0))
		assert_true(game_logic.do_choice(player1, 0 if accept else 1))
		assert_null(game_logic.active_strike, "No second guardian choice at Cleanup after declining After.")
		assert_eq(player1.is_card_in_bleach(attack), accept)
		assert_eq(player1.is_card_in_gauge(attack), not accept)
		assert_false(player1.is_card_in_discards(attack))
		assert_eq(player1.bleach_zone.filter(func(card): return card.id == attack).size(), 1 if accept else 0)


func test_jingxue_attack_forced_moves_blocked_self_and_opponent_moves_allowed():
	var attack = _jingxue_grasp_window(true)
	# Actual Before forced Pull and opponent-targeted MoveTo already resolved;
	# the untouched Grasp Hit decision still belongs to its original player.
	assert_eq(player1.arena_location, 3)
	assert_eq(player2.arena_location, 4)
	assert_eq(player1.hand.size(), 6, "Blocking forced movement preserves the legal Draw1 tail.")
	var before_events = game_logic.get_latest_events()
	assert_eq(validate_has_event(before_events, Enums.EventType.EventType_Strike_IgnoredPushPull, player1).size(), 4)
	assert_true(game_logic.do_choice(player2, 0))
	_assert_jingxue_after()
	assert_eq(player1.arena_location, 6, "Own Advance/MoveTo executed after the opponent's After reset.")
	assert_eq(player2.arena_location, 7)
	var events = game_logic.get_latest_events()
	assert_eq(validate_has_event(events, Enums.EventType.EventType_Strike_IgnoredPushPull, player1).size(), 2,
		"Both the actual Grasp push and the forced ignore-restrictions reset are blocked.")
	validate_has_event(events, Enums.EventType.EventType_Move, player2, 5)
	validate_has_event(events, Enums.EventType.EventType_Move, player2, 7)
	validate_has_event(events, Enums.EventType.EventType_Move, player1, 4)
	validate_has_event(events, Enums.EventType.EventType_Move, player1, 5)
	validate_has_event(events, Enums.EventType.EventType_Move, player1, 6)
	assert_true(game_logic.do_choice(player1, 1))
	assert_null(game_logic.active_strike)
	assert_true(player1.is_card_in_gauge(attack))
	# Outside a strike, the persistent stat object cannot leak a movement ban.
	game_logic.handle_strike_effect(-1, {"effect_type": StrikeEffects.Push, "amount": 1}, player2)
	assert_eq(player1.arena_location, 5)
	game_logic.handle_strike_effect(-1, {"effect_type": StrikeEffects.Advance, "amount": 1}, player2)
	assert_eq(player2.arena_location, 6)
	var next_attack = give_player_specific_card(player2, "gg_normal_grasp")
	var next_response = give_player_specific_card(player1, "gg_normal_focus")
	assert_true(game_logic.do_strike(player2, next_attack, false, -1))
	assert_false(player1.strike_stat_boosts.heiqiyihu_prevent_opponent_moving_me)
	assert_true(game_logic.do_strike(player1, next_response, false, -1))
	assert_true(game_logic.do_choice(player2, 0))
	assert_null(game_logic.active_strike)


func test_jingxue_attack_own_advance_can_cross_after_opponents_own_retreat():
	var attack = _jingxue_grasp_window(true, false)
	game_logic.get_latest_events()
	assert_true(game_logic.do_choice(player2, 0))
	_assert_jingxue_after()
	assert_eq(player2.arena_location, 5, "Opponent's own Retreat is allowed.")
	assert_eq(player1.arena_location, 6, "Own Advance skips occupied space5 and crosses the opponent.")
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_Move, player1, 4)
	validate_has_event(events, Enums.EventType.EventType_Move, player1, 6)
	assert_true(game_logic.do_choice(player1, 1))
	assert_null(game_logic.active_strike)
	assert_true(player1.is_card_in_gauge(attack))


func test_jingxue_attack_stunned_before_activation_has_no_after_guardian_choice():
	_restart_for_opening(100, 100, Enums.PlayerId.PlayerId_Opponent)
	assert_true(game_logic.do_mulligan(player1, []))
	assert_true(game_logic.do_mulligan(player2, []))
	position_players(player1, 3, player2, 5)
	var attack = give_player_specific_card(player1, "heiqiyihu_静血装")
	var response = give_player_specific_card(player2, "gg_normal_dust")
	game_logic.get_latest_events()
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_null(game_logic.active_strike)
	assert_eq(player1.life, 95)
	assert_true(player1.is_card_in_discards(attack))
	assert_false(player1.is_card_in_bleach(attack))
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_Strike_Stun, player1)
	validate_not_has_event(events, Enums.EventType.EventType_Strike_EffectChoice, player1)


func test_jingxue_boost_guard_two_vs_three_real_stun_boundary():
	for virtual_source in [false, true]:
		_restart_for_opening(100, 100)
		assert_true(game_logic.do_mulligan(player1, []))
		assert_true(game_logic.do_mulligan(player2, []))
		position_players(player1, 3, player2, 4)
		var source = _give_guardian(player1, "heiqiyihu_静血装") if virtual_source \
			else give_player_specific_card(player1, "heiqiyihu_静血装")
		var attack = give_player_specific_card(player1, "gg_normal_dive")
		var response = give_player_specific_card(player2, "gg_normal_grasp")
		if virtual_source:
			assert_true(game_logic.do_strike(player1, -1, false, -1))
			assert_true(game_logic.do_choice(player1, 0))
			assert_true(game_logic.do_strike(player1, attack, false, -1))
			assert_true(game_logic.do_strike(player2, response, false, -1))
		else:
			assert_true(game_logic.do_boost(player1, source))
			assert_true(game_logic.do_strike(player2, response, false, -1))
			assert_true(game_logic.do_strike(player1, attack, false, -1))
		assert_eq(player1.strike_stat_boosts.guard, 3 if virtual_source else 2)
		game_logic.get_latest_events()
		assert_true(game_logic.do_choice(player2, 0))
		assert_null(game_logic.active_strike)
		assert_eq(player1.life, 97)
		assert_true(player1.is_card_in_discards(source))
		if virtual_source:
			assert_eq(player1.arena_location, 6, "Guard3 survives damage3, so Dive's Before executes.")
			validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Strike_Stun, player1)
		else:
			assert_eq(player1.arena_location, 2, "Guard2 is exceeded by damage3, so Dive is skipped.")
			validate_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Strike_Stun, player1)


func test_jingxue_boost_huhuan_guardian_four_real_behavior():
	_check_guardian_scaling(3)


func _dilie_hit_window(first_position: int, second_position: int, response_id: String = "standard_normal_sweep", empty_opponent_hand: bool = false) -> Dictionary:
	_restart_for_opening(100, 100)
	assert_true(game_logic.do_mulligan(player1, []))
	assert_true(game_logic.do_mulligan(player2, []))
	position_players(player1, first_position, player2, second_position)
	if empty_opponent_hand:
		player2.discard_hand()
	var attack = give_player_specific_card(player1, "heiqiyihu_地裂崩击")
	var response = give_player_specific_card(player2, response_id)
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.get_current_strike_timing(), "hit")
	assert_eq(player2.arena_location, second_position)
	assert_eq(player2.life, 100)
	var expected_spaces = []
	for space in [first_position - 1, first_position + 1]:
		if space >= 1 and space <= 9:
			expected_spaces.append(space)
	assert_eq(game_logic.decision_info.limitation, expected_spaces)
	assert_eq(game_logic.decision_info.choice.size(), expected_spaces.size())
	for i in range(expected_spaces.size()):
		var space = expected_spaces[i]
		assert_eq(game_logic.decision_info.choice[i]["effect_type"], StrikeEffects.Pull)
		assert_eq(game_logic.decision_info.choice[i]["_choice_text"], "将对手拉近至你的%s侧（%s号格）" % [
			"左" if space < first_position else "右", space])
	return {"attack": attack, "opponent_hand": player2.hand.size()}


func test_dilie_attack_left_right_crossing_both_board_sides_atomic_order():
	for positions in [[5, 7, 4], [5, 7, 6], [5, 3, 6], [5, 3, 4]]:
		var ids = _dilie_hit_window(positions[0], positions[1])
		var choice_index = game_logic.decision_info.limitation.find(positions[2])
		game_logic.get_latest_events()
		assert_false(game_logic.do_choice(player2, choice_index))
		assert_true(game_logic.do_choice(player1, choice_index))
		assert_eq(player2.arena_location, positions[2])
		assert_eq(player2.hand.size(), ids["opponent_hand"] - 1)
		assert_eq(player2.life, 97)
		var events = game_logic.get_latest_events()
		var move_index = -1
		var discard_index = -1
		var damage_index = -1
		for i in range(events.size()):
			var event = events[i]
			if event["event_player"] != player2.my_id:
				continue
			if event["event_type"] == Enums.EventType.EventType_Move:
				move_index = i
			if event["event_type"] == Enums.EventType.EventType_AddToDiscard:
				assert_eq(discard_index, -1, "Exactly one random discard; no duplicated and continuation.")
				discard_index = i
			if event["event_type"] == Enums.EventType.EventType_Strike_TookDamage:
				damage_index = i
		assert_gte(move_index, 0)
		assert_gt(discard_index, move_index)
		assert_gt(damage_index, discard_index)
		_finish_t6_huhuan_cleanup(ids["attack"])


func test_dilie_attack_corners_offer_only_existing_adjacent_space():
	for positions in [[1, 4, 2], [9, 6, 8]]:
		var ids = _dilie_hit_window(positions[0], positions[1])
		assert_eq(game_logic.decision_info.limitation, [positions[2]])
		assert_true(game_logic.do_choice(player1, 0))
		assert_eq(player2.arena_location, positions[2])
		assert_eq(player2.hand.size(), ids["opponent_hand"] - 1)
		_finish_t6_huhuan_cleanup(ids["attack"])


func test_dilie_attack_focus_immunity_keeps_position_but_still_discards():
	var ids = _dilie_hit_window(3, 5, "standard_normal_focus")
	assert_true(player2.strike_stat_boosts.ignore_push_and_pull)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player2.arena_location, 5)
	assert_eq(player2.hand.size(), ids["opponent_hand"], "Random discard1, then Focus After draw1.")
	assert_eq(player2.life, 99, "Ground power3 minus Focus armor2.")
	_finish_t6_huhuan_cleanup(ids["attack"])


func test_dilie_attack_empty_hand_still_moves_without_discard_decision():
	var ids = _dilie_hit_window(3, 6, "standard_normal_sweep", true)
	assert_eq(ids["opponent_hand"], 0)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player2.arena_location, 2)
	assert_true(player2.hand.is_empty())
	assert_eq(player2.life, 97)
	_finish_t6_huhuan_cleanup(ids["attack"])


func test_dilie_attack_miss_does_not_pull_or_random_discard():
	_restart_for_opening(100, 100)
	assert_true(game_logic.do_mulligan(player1, []))
	assert_true(game_logic.do_mulligan(player2, []))
	position_players(player1, 1, player2, 9)
	var attack = give_player_specific_card(player1, "heiqiyihu_地裂崩击")
	var response = give_player_specific_card(player2, "standard_normal_sweep")
	var hand_size = player2.hand.size() - 1
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_null(game_logic.active_strike)
	assert_eq(player2.arena_location, 9)
	assert_eq(player2.hand.size(), hand_size)
	assert_eq(player2.life, 100)
	assert_true(player1.is_card_in_discards(attack))


func test_dilie_boost_normal_two_and_guardian_three_huhuan_four_real_behavior():
	test_guardian_scale_normal_special_boost_retains_printed_two()
	_check_guardian_scaling(2)


func _xuhua_response_window(response_definition: String = "gg_normal_focus", use_ex: bool = false, distance: int = 1) -> Dictionary:
	_restart_for_opening(100, 100)
	assert_true(game_logic.do_mulligan(player1, []))
	assert_true(game_logic.do_mulligan(player2, []))
	position_players(player1, 3, player2, 3 + distance)
	var cost = give_gauge(player1, 2)
	var materials = []
	for i in range(4):
		materials.append(give_player_specific_card(player1, "gg_normal_cross"))
	var attack = give_player_specific_card(player1, "heiqiyihu_虚化")
	var ex = give_player_specific_card(player1, "heiqiyihu_虚化") if use_ex else -1
	var response = give_player_specific_card(player2, response_definition)
	assert_true(game_logic.do_strike(player1, attack, false, ex))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_PayStrikeCost_Required)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.decision_info.cost, 2)
	assert_true(game_logic.do_pay_strike_cost(player1, cost, false))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ForceForEffect)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.decision_info.choice_card_id, attack)
	assert_eq(game_logic.decision_info.effect["force_max"], 2)
	assert_eq(player1.life, 100, "Hit response is before damage.")
	return {"attack": attack, "cost": cost, "materials": materials}


func _assert_xuhua_recovery_options(ids: Array, destination: String):
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.get_current_strike_timing(), "after")
	assert_eq(game_logic.decision_info.choice.size(), ids.size())
	for option in game_logic.decision_info.choice:
		assert_eq(option["effect_type"], StrikeEffects.HeiqiyihuXuhuaRecoverCard)
		assert_eq(option["destination"], destination)
		assert_true(option["paid_id"] in ids)
		assert_eq(option["_choice_text"], "将「%s」置入%s" % [
			game_logic.card_db.get_card_name(option["paid_id"]), "守护区" if destination == "bleach" else "怒气区"])


func test_xuhua_attack_zero_payment_no_recovery():
	var ids = _xuhua_response_window()
	assert_true(game_logic.do_force_for_effect(player1, [], false))
	assert_null(game_logic.active_strike)
	assert_eq(player1.life, 100)
	assert_true(player1.is_card_in_discards(ids["attack"]))
	assert_true(player1.bleach_zone.is_empty())
	for id in ids["cost"]:
		assert_true(player1.is_card_in_discards(id))


func test_xuhua_attack_one_normal_goes_only_to_guardian():
	var ids = _xuhua_response_window()
	var paid = ids["materials"][0]
	assert_true(game_logic.do_force_for_effect(player1, [paid], false))
	assert_eq(player1.strike_stat_boosts.guard, 1)
	_assert_xuhua_recovery_options([paid], "bleach")
	assert_false(game_logic.do_choice(player2, 0))
	assert_true(game_logic.do_choice(player1, 0))
	assert_null(game_logic.active_strike)
	assert_true(player1.is_card_in_bleach(paid))
	assert_true(player1.gauge.is_empty())


func test_xuhua_attack_two_normals_choose_guardian_then_gauge():
	var ids = _xuhua_response_window()
	var paid = ids["materials"].slice(0, 2)
	assert_true(game_logic.do_force_for_effect(player1, paid, false))
	assert_eq(player1.strike_stat_boosts.guard, 2)
	_assert_xuhua_recovery_options(paid, "bleach")
	assert_true(game_logic.do_choice(player1, 1))
	assert_true(player1.is_card_in_bleach(paid[1]))
	assert_true(player1.is_card_in_discards(paid[0]))
	_assert_xuhua_recovery_options([paid[0]], "gauge")
	assert_true(game_logic.do_choice(player1, 0))
	assert_null(game_logic.active_strike)
	assert_true(player1.is_card_in_gauge(paid[0]))
	for id in ids["cost"]:
		assert_true(player1.is_card_in_discards(id), "Printed attack costs are not response payments.")


func test_xuhua_attack_single_ultra_force_two_or_one_is_one_entity():
	for single_force in [false, true]:
		var ids = _xuhua_response_window()
		var paid = give_player_specific_card(player1, "heiqiyihu_呼唤我的名字吧！")
		assert_true(game_logic.do_force_for_effect(player1, [paid], single_force))
		assert_eq(player1.strike_stat_boosts.guard, 1 if single_force else 2)
		assert_eq(game_logic.active_strike.heiqiyihu_xuhua_spent_ids[ids["attack"]], [paid])
		_assert_xuhua_recovery_options([paid], "bleach")
		assert_true(game_logic.do_choice(player1, 0))
		assert_null(game_logic.active_strike)
		assert_true(player1.is_card_in_bleach(paid))
		assert_true(player1.gauge.is_empty())


func test_xuhua_attack_overpay_duplicate_and_foreign_rejected_without_spending():
	var ids = _xuhua_response_window()
	var paid = ids["materials"]
	var other = give_player_specific_card(player2, "gg_normal_cross")
	assert_false(game_logic.do_force_for_effect(player1, paid.slice(0, 3), false))
	assert_false(game_logic.do_force_for_effect(player1, [paid[0], paid[0]], false))
	assert_false(game_logic.do_force_for_effect(player1, [paid[0], other], false))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ForceForEffect)
	assert_eq(player1.life, 100)
	assert_eq(player1.strike_stat_boosts.guard, 0)
	for id in paid:
		assert_true(player1.is_card_in_hand(id))
	assert_true(game_logic.active_strike.heiqiyihu_xuhua_spent_ids.is_empty())
	assert_true(game_logic.do_force_for_effect(player1, [], false))
	assert_null(game_logic.active_strike)


func test_xuhua_attack_after_hit_discard_before_damage_can_survive_two_damage():
	var ids = _xuhua_response_window("gg_normal_sweep")
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_AddToDiscard, player1)
	assert_lt(player1.hand.size(), 9, "Sweep Hit has already discarded one actual hand card.")
	var paid = ids["materials"].filter(func(id): return player1.is_card_in_hand(id)).slice(0, 2)
	assert_eq(paid.size(), 2)
	assert_true(game_logic.do_force_for_effect(player1, paid, false))
	assert_eq(player1.life, 98, "Guard is not Armor: Sweep6 - armor4 = 2 actual damage.")
	assert_false(game_logic.active_strike.is_player_stunned(player1))
	_assert_xuhua_recovery_options(paid, "bleach")
	assert_true(game_logic.do_choice(player1, 0))
	assert_true(game_logic.do_choice(player1, 0))
	assert_null(game_logic.active_strike)


func test_xuhua_attack_stunned_skips_after_paid_cards_stay_discarded():
	var ids = _xuhua_response_window("standard_normal_spike", false, 2)
	assert_eq(player1.distance_to_opponent(), 2)
	assert_true(player2.strike_stat_boosts.ignore_armor)
	assert_true(player2.strike_stat_boosts.ignore_guard)
	var paid = ids["materials"].slice(0, 2)
	game_logic.get_latest_events()
	assert_true(game_logic.do_force_for_effect(player1, paid, false))
	assert_null(game_logic.active_strike)
	assert_eq(player1.life, 95, "Spike ignores armor and guard.")
	assert_true(player1.bleach_zone.is_empty())
	for id in paid:
		assert_true(player1.is_card_in_discards(id))
	validate_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Strike_Stun, player1)


func test_xuhua_attack_ex_is_still_na_and_never_hits():
	var ids = _xuhua_response_window("gg_normal_focus", true)
	assert_true(player1.strike_stat_boosts.attack_does_not_hit)
	assert_eq(game_logic.get_total_power(player1), 0)
	assert_false(game_logic.in_range(player1, player2, game_logic.card_db.get_card(ids["attack"])))
	assert_false(game_logic.active_strike.did_player_hit_opponent(player1))
	assert_true(game_logic.do_force_for_effect(player1, [], false))
	assert_null(game_logic.active_strike)
	assert_true(player1.is_card_in_discards(ids["attack"]))
	assert_eq(player2.life, 100)


func test_xuhua_attack_na_even_with_real_getsuga_boost_and_ex():
	_restart_for_opening(100, 100)
	assert_true(game_logic.do_mulligan(player1, []))
	assert_true(game_logic.do_mulligan(player2, []))
	position_players(player1, 3, player2, 4)
	var boost = give_player_specific_card(player1, "heiqiyihu_呼唤我的名字吧！")
	assert_true(game_logic.do_boost(player1, boost))
	var cost = give_gauge(player1, 2)
	var attack = give_player_specific_card(player1, "heiqiyihu_虚化")
	var ex = give_player_specific_card(player1, "heiqiyihu_虚化")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_true(game_logic.do_strike(player1, attack, false, ex))
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_pay_strike_cost(player1, cost, false))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ForceForEffect)
	assert_eq(player1.strike_stat_boosts.power, 4, "EX1 plus actual Getsuga3 exists but cannot make N/A valid.")
	assert_eq(game_logic.get_total_power(player1), 0)
	assert_true(player1.strike_stat_boosts.attack_does_not_hit)
	assert_true(game_logic.do_force_for_effect(player1, [], false))
	assert_null(game_logic.active_strike)
	assert_eq(player2.life, 100)
	assert_true(player1.is_card_in_discards(attack))
	assert_true(player1.is_card_in_bleach(boost))


func test_xuhua_attack_decline_response_and_no_available_force_resume_safely():
	var ids = _xuhua_response_window()
	var material = ids["materials"][0]
	assert_true(game_logic.do_force_for_effect(player1, [], false, true))
	assert_true(player1.is_card_in_hand(material))
	assert_true(player1.bleach_zone.is_empty())
	assert_null(game_logic.active_strike)
	_restart_for_opening(100, 100)
	assert_true(game_logic.do_mulligan(player1, []))
	assert_true(game_logic.do_mulligan(player2, []))
	position_players(player1, 3, player2, 4)
	player1.discard_hand()
	var cost = give_gauge(player1, 2)
	var attack = give_player_specific_card(player1, "heiqiyihu_虚化")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_true(game_logic.do_pay_strike_cost(player1, cost, false))
	assert_null(game_logic.active_strike, "No resources: optional response and empty recovery create no orphan decision.")
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	assert_eq(player1.life, 100)
	assert_true(player1.hand.is_empty())
	assert_true(player1.bleach_zone.is_empty())


func test_xuhua_attack_recovery_filters_source_that_left_discard():
	var ids = _xuhua_response_window()
	var paid = ids["materials"].slice(0, 2)
	assert_true(game_logic.do_force_for_effect(player1, paid, false))
	_assert_xuhua_recovery_options(paid, "bleach")
	player1.seal_from_location(paid[0], "discard")
	assert_false(game_logic.do_choice(player1, 0), "A stale source cannot be fetched from sealed.")
	assert_true(game_logic.do_choice(player1, 1))
	assert_null(game_logic.active_strike, "No legal remaining Gauge source: finish without an empty choice.")
	assert_true(player1.is_card_in_sealed(paid[0]))
	assert_true(player1.is_card_in_bleach(paid[1]))


func test_xuhua_attack_multi_hit_accumulates_four_entities_recovers_only_two():
	_restart_for_opening(100, 100, Enums.PlayerId.PlayerId_Opponent, "zsolt")
	assert_true(game_logic.do_mulligan(player1, []))
	assert_true(game_logic.do_mulligan(player2, []))
	player2.exceeded = true
	position_players(player1, 3, player2, 4)
	var cost = give_gauge(player1, 2)
	var paid = []
	for i in range(4):
		paid.append(give_player_specific_card(player1, "gg_normal_cross"))
	var xuhua = give_player_specific_card(player1, "heiqiyihu_虚化")
	var first_attack = give_player_specific_card(player2, "standard_normal_focus")
	var extra_attack = give_player_specific_card(player2, "standard_normal_assault")
	var zsolt_cost = give_player_specific_card(player2, "standard_normal_cross")
	assert_true(game_logic.do_strike(player2, first_attack, false, -1))
	assert_true(game_logic.do_strike(player1, xuhua, false, -1))
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_pay_strike_cost(player1, cost, false))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ForceForEffect)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_force_for_effect(player1, paid.slice(0, 2), false))
	assert_eq(player1.strike_stat_boosts.guard, 2)
	assert_eq(player1.life, 100, "Focus4 is fully absorbed by Xuhua's printed armor4.")
	assert_eq(player1.strike_stat_boosts.consumed_armor, 4)
	assert_eq(game_logic.get_total_armor(player1), 0, "Armor already consumed by the first hit is not renewed for the extra attack.")
	validate_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Strike_TookDamage, player1, 0)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ForceForEffect)
	assert_eq(game_logic.decision_info.player, player2.my_id, "Real Zsolt UA now controls its own payment.")
	assert_true(game_logic.do_force_for_effect(player2, [zsolt_cost], false))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseToDiscard)
	assert_eq(game_logic.decision_info.player, player2.my_id)
	assert_true(game_logic.do_choose_to_discard(player2, [extra_attack]))
	assert_true(game_logic.active_strike.extra_attack_in_progress)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ForceForEffect)
	assert_eq(game_logic.decision_info.player, player1.my_id, "Extra-attack Hit response returns control to Xuhua.")
	assert_eq(game_logic.decision_info.effect["force_max"], 2)
	assert_eq(player1.strike_stat_boosts.guard, 2, "First response guard persists for this battle.")
	assert_false(game_logic.do_force_for_effect(player1, [paid[2], paid[3], player1.hand[0].id], false))
	assert_true(game_logic.do_force_for_effect(player1, paid.slice(2, 4), false))
	assert_eq(player1.strike_stat_boosts.guard, 4)
	assert_eq(player1.life, 99, "Zsolt's power-capped extra Assault deals 1 against the now-consumed armor.")
	validate_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Strike_TookDamage, player1, 1)
	assert_eq(game_logic.active_strike.heiqiyihu_xuhua_spent_ids[xuhua], paid)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ForceForEffect)
	assert_eq(game_logic.decision_info.player, player2.my_id)
	assert_true(game_logic.do_force_for_effect(player2, [], false), "Decline Zsolt's second extra attack.")
	_assert_xuhua_recovery_options(paid, "bleach")
	assert_true(game_logic.do_choice(player1, 2))
	assert_true(player1.is_card_in_bleach(paid[2]))
	_assert_xuhua_recovery_options([paid[0], paid[1], paid[3]], "gauge")
	assert_false(game_logic.do_choice(player2, 0))
	assert_true(game_logic.do_choice(player1, 1))
	assert_null(game_logic.active_strike)
	assert_eq(player1.life, 99)
	assert_true(player1.is_card_in_gauge(paid[1]))
	for id in [paid[0], paid[3]]:
		assert_true(player1.is_card_in_discards(id), "Only two entities are recovered, not every paid card.")
	assert_true(player2.is_card_in_discards(zsolt_cost))
	for id in cost:
		assert_true(player1.is_card_in_discards(id))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)


func _xuhua_normal_boost_window(exceeded: bool = false) -> Dictionary:
	_restart_cancel_case()
	player1.exceeded = exceeded
	var payment = _give_guardian(player1, "heiqiyihu_虚化") if exceeded else -1
	var boost = give_player_specific_card(player1, "heiqiyihu_虚化")
	var force = [give_player_specific_card(player1, "gg_normal_cross"), give_player_specific_card(player1, "gg_normal_focus")]
	var target = give_player_specific_card(player1, "gg_normal_grasp")
	var top = set_player_topdeck(player1, "gg_normal_dust")
	assert_false(game_logic.do_boost(player1, boost, force.slice(0, 1)))
	assert_true(player1.is_card_in_hand(boost))
	assert_true(game_logic.do_boost(player1, boost, force))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.decision_info.choice[0]["_choice_text"], "将牌堆顶1张牌置入守护区")
	for option in game_logic.decision_info.choice:
		assert_eq(option["effect_type"], StrikeEffects.HeiqiyihuGuardianSource)
		assert_ne(option.get("guardian_card_id", -1), boost)
		for id in force:
			assert_ne(option.get("guardian_card_id", -1), id)
	validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Boost_CancelDecision, player1)
	return {"boost": boost, "target": target, "top": top, "payment": payment, "force": force}


func _finish_xuhua_boost_turn():
	if game_logic.game_state == Enums.GameState.GameState_DiscardDownToMax:
		assert_true(game_logic.do_discard_to_max(player1, [player1.hand[0].id]))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	assert_eq(game_logic.active_turn_player, player2.my_id)
	assert_null(game_logic.active_boost)


func test_xuhua_boost_normal_topdeck_real_source_no_cancel_front():
	var ids = _xuhua_normal_boost_window()
	assert_false(game_logic.do_choice(player2, 0))
	assert_true(game_logic.do_choice(player1, 0))
	assert_true(player1.is_card_in_bleach(ids["top"]))
	assert_true(player1.is_card_in_discards(ids["boost"]))
	for id in ids["force"]:
		assert_true(player1.is_card_in_discards(id))
	_finish_xuhua_boost_turn()


func test_xuhua_boost_normal_hand_exact_source_public_and_no_duplicate():
	var ids = _xuhua_normal_boost_window()
	var index = -1
	for i in range(game_logic.decision_info.choice.size()):
		if game_logic.decision_info.choice[i].get("guardian_card_id", -1) == ids["target"]:
			index = i
	assert_gt(index, 0)
	assert_true(game_logic.do_choice(player1, index))
	assert_true(player1.is_card_in_bleach(ids["target"]))
	assert_false(player1.is_card_in_hand(ids["target"]))
	assert_eq(player1.bleach_zone.filter(func(card): return card.id == ids["target"]).size(), 1)
	assert_false(player1.is_card_in_bleach(ids["top"]))
	_finish_xuhua_boost_turn()


func test_xuhua_boost_seventh_real_integration_cancel_accept_and_decline():
	for accept in [true, false]:
		var ids = _xuhua_normal_boost_window(true)
		assert_true(game_logic.do_choice(player1, 0))
		assert_true(player1.is_card_in_bleach(ids["top"]))
		assert_true(player1.is_card_in_discards(ids["boost"]))
		assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
		assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostCancel)
		assert_eq(game_logic.decision_info.player, player1.my_id)
		assert_eq(game_logic.decision_info.choice, 1)
		validate_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Boost_CancelDecision, player1, 1)
		assert_true(game_logic.do_boost_cancel(player1, [ids["payment"]] if accept else [], accept))
		if accept:
			assert_true(player1.is_card_in_discards(ids["payment"]))
			assert_false(player1.is_card_in_bleach(ids["payment"]))
			assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
			assert_eq(game_logic.active_turn_player, player1.my_id)
			assert_null(game_logic.active_boost)
		else:
			assert_true(player1.is_card_in_bleach(ids["payment"]))
			_finish_xuhua_boost_turn()


func test_xuhua_boost_virtual_free_now_then_attack_setup_no_cancel():
	var source = _give_guardian(player1, "heiqiyihu_虚化")
	var top = set_player_topdeck(player1, "gg_normal_dust")
	var hand_size = player1.hand.size()
	game_logic.get_latest_events()
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_choice(player1, 0))
	assert_true(player1.is_card_in_bleach(top))
	assert_true(player1.is_card_in_discards(source))
	assert_eq(player1.hand.size(), hand_size, "The guardian boost's Force2 printed cost is not paid.")
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)
	assert_null(game_logic.active_boost)
	assert_null(game_logic.active_strike.initiator_card)
	validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Boost_CancelDecision, player1)


func test_xuhua_boost_empty_deck_reshuffles_and_no_reshuffle_deckout():
	for can_reshuffle in [true, false]:
		var ids = _xuhua_normal_boost_window()
		player1.sealed.append_array(player1.deck)
		player1.deck.clear()
		player1.reshuffle_remaining = 1 if can_reshuffle else 0
		assert_true(game_logic.do_choice(player1, 0))
		if can_reshuffle:
			assert_false(game_logic.game_over)
			assert_eq(player1.bleach_zone.size(), 1)
			assert_eq(player1.reshuffle_remaining, 0)
			_finish_xuhua_boost_turn()
		else:
			assert_true(game_logic.game_over)
			assert_eq(game_logic.game_state, Enums.GameState.GameState_GameOver)
			assert_true(player1.bleach_zone.is_empty())
			assert_eq(game_logic.game_over_winning_player, player2)
			validate_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_GameOver, player1)


func _huhuan_cleanup_hit_window(virtual_source: bool, existing_guardians: int = 0, already_exceeded: bool = false) -> Dictionary:
	_restart_cancel_case()
	player1.exceeded = already_exceeded
	position_players(player1, 3, player2, 4)
	var source = _give_guardian(player1, "heiqiyihu_呼唤我的名字吧！") if virtual_source \
		else give_player_specific_card(player1, "heiqiyihu_呼唤我的名字吧！")
	var guardians = []
	for i in range(existing_guardians):
		guardians.append(_give_guardian(player1, "gg_normal_cross"))
	var gauge = give_gauge(player1, 2)
	var attack = give_player_specific_card(player1, "gg_normal_grasp")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	if virtual_source:
		assert_false(already_exceeded)
		assert_true(game_logic.do_strike(player1, -1, false, -1))
		_assert_pre_set_guardian_choice(player1)
		assert_true(game_logic.do_choice(player1, 0))
		assert_true(player1.is_card_in_discards(source))
		assert_true(game_logic.do_strike(player1, attack, false, -1))
		assert_true(game_logic.do_strike(player2, response, false, -1))
	else:
		assert_true(game_logic.do_boost(player1, source))
		if already_exceeded:
			assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostCancel)
			assert_true(game_logic.do_boost_cancel(player1, [], false))
		assert_eq(game_logic.active_turn_player, player2.my_id)
		if game_logic._has_heiqiyihu_guardian_option():
			assert_true(game_logic.do_strike(player2, -1, false, -1))
			_assert_pre_set_guardian_choice(player1)
			assert_true(game_logic.do_choice(player1, game_logic.decision_info.choice.size() - 1))
		assert_true(game_logic.do_strike(player2, response, false, -1))
		assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.get_current_strike_timing(), "hit")
	assert_eq(player1.strike_stat_boosts.power, 3)
	assert_eq(game_logic.get_total_min_range(player1), 1)
	assert_eq(game_logic.get_total_max_range(player1), 2)
	var cleanup = game_logic.get_boost_effects_at_timing("cleanup", player1)
	assert_eq(cleanup.size(), 1, "A single atomic Cleanup item, not separately sortable steps.")
	assert_eq(cleanup[0]["effect_type"], StrikeEffects.HeiqiyihuGetsugaCleanup)
	assert_eq(player1.exceeded, already_exceeded)
	assert_eq(player1.bleach_zone.size(), existing_guardians)
	assert_eq(player1.gauge.size(), 2)
	assert_gt(player1.hand.size(), 0)
	return {"source": source, "attack": attack, "gauge": gauge, "guardians": guardians}


func _finish_huhuan_cleanup_check(ids: Dictionary, expected_guardians: int, already_exceeded: bool = false, source_moved: bool = true):
	var hand_ids = player1.hand.map(func(card): return card.id)
	var deck_size = player1.deck.size()
	game_logic.get_latest_events()
	assert_true(game_logic.do_choice(player1, 0))
	var events = game_logic.get_latest_events()
	assert_null(game_logic.active_strike, "Cleanup does not pause for a spurious ordering choice.")
	assert_eq(player2.life, 26, "Grasp3 + Getsuga3 - Focus armor2.")
	assert_eq(player1.bleach_zone.size(), expected_guardians)
	for guardian in ids["guardians"]:
		assert_true(player1.is_card_in_bleach(guardian), "Existing guardians are not discarded as Gauge.")
	for id in hand_ids + ids["gauge"]:
		assert_true(player1.is_card_in_discards(id))
	assert_eq(player1.gauge.size(), 1, "The hitting attack enters Gauge only after the Cleanup wipe.")
	assert_true(player1.is_card_in_gauge(ids["attack"]))
	assert_true(player1.exceeded)
	var draw_count = 0 if already_exceeded else max(2, expected_guardians * 2)
	assert_eq(player1.hand.size(), draw_count)
	assert_eq(player1.deck.size(), deck_size - draw_count)
	assert_eq(player1.is_card_in_bleach(ids["source"]), source_moved)
	assert_false(player1.is_card_in_continuous_boosts(ids["source"]))
	var last_hand_discard = -1
	var first_gauge_discard = events.size()
	var last_gauge_discard = -1
	var source_index = -1
	var exceed_index = -1
	var draw_indices = []
	for i in range(events.size()):
		var event = events[i]
		if event["event_player"] != player1.my_id:
			continue
		if event["event_type"] == Enums.EventType.EventType_AddToDiscard:
			if event["number"] in hand_ids:
				last_hand_discard = i
			if event["number"] in ids["gauge"]:
				first_gauge_discard = min(first_gauge_discard, i)
				last_gauge_discard = i
		if event["event_type"] == Enums.EventType.EventType_AddToBleach and event["number"] == ids["source"]:
			source_index = i
		if event["event_type"] == Enums.EventType.EventType_Exceed:
			assert_eq(exceed_index, -1, "Only one Exceed event.")
			exceed_index = i
		if event["event_type"] == Enums.EventType.EventType_Draw:
			draw_indices.append(i)
	assert_gte(last_hand_discard, 0)
	assert_gt(first_gauge_discard, last_hand_discard)
	if source_moved:
		assert_gt(source_index, last_gauge_discard)
	else:
		assert_eq(source_index, -1)
	assert_eq(draw_indices.size(), draw_count)
	if already_exceeded:
		assert_eq(exceed_index, -1)
	else:
		assert_gt(exceed_index, max(source_index, last_gauge_discard))
		for draw_index in draw_indices:
			assert_gt(draw_index, exceed_index)
	validate_not_has_event(events, Enums.EventType.EventType_Boost_CancelDecision, player1)


func test_huhuan_boost_normal_zero_guardians_cleanup_order():
	var ids = _huhuan_cleanup_hit_window(false)
	assert_true(player1.is_card_in_continuous_boosts(ids["source"]))
	_finish_huhuan_cleanup_check(ids, 1)


func test_huhuan_boost_normal_multiple_guardians_count_after_source_enters():
	var ids = _huhuan_cleanup_hit_window(false, 2)
	_finish_huhuan_cleanup_check(ids, 3)


func test_huhuan_boost_virtual_source_cleanup_and_same_name_isolation():
	var ids = _huhuan_cleanup_hit_window(true, 1)
	var other_copy = give_player_specific_card(player1, "heiqiyihu_呼唤我的名字吧！")
	player1.discard([other_copy])
	_finish_huhuan_cleanup_check(ids, 2)
	assert_true(player1.is_card_in_discards(other_copy))
	assert_false(player1.is_card_in_bleach(other_copy))
	assert_true(game_logic.heiqiyihu_guardian_setup.is_empty())
	assert_true(game_logic.get_boost_effects_at_timing("cleanup", player1).is_empty())


func test_huhuan_boost_virtual_source_left_discard_other_steps_still_resolve():
	var ids = _huhuan_cleanup_hit_window(true)
	player1.seal_from_location(ids["source"], "discard")
	_finish_huhuan_cleanup_check(ids, 0, false, false)
	assert_true(player1.is_card_in_sealed(ids["source"]))


func test_huhuan_boost_already_exceeded_discards_real_gauge_not_guardians_no_redraw():
	var ids = _huhuan_cleanup_hit_window(false, 2, true)
	_finish_huhuan_cleanup_check(ids, 3, true)
	assert_false(player1.heiqiyihu_skip_hand_limit_this_turn)


func test_huhuan_attack_wild_can_decline_two_gauge_payment():
	position_players(player1, 3, player2, 4)
	var payment = give_gauge(player1, 2)
	var attack = set_player_topdeck(player1, "heiqiyihu_呼唤我的名字吧！")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	assert_true(game_logic.do_strike(player1, -1, true, -1))
	var replacement = set_player_topdeck(player1, "gg_normal_grasp")
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_PayStrikeCost_CanWild)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.decision_info.cost, 2)
	assert_true(game_logic.do_pay_strike_cost(player1, [], true))
	assert_true(player1.is_card_in_discards(attack))
	for id in payment:
		assert_true(player1.is_card_in_gauge(id))
	assert_eq(game_logic.active_strike.initiator_card.id, replacement)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player2.life, 29)
	assert_null(game_logic.active_strike)


func _restart_cancel_case():
	_restart_for_opening(30, 30)
	assert_true(game_logic.do_mulligan(player1, []))
	assert_true(game_logic.do_mulligan(player2, []))
	game_logic.get_latest_events()


func test_cancel_six_normal_boosts_accept_after_real_resolution():
	# Xuhua's immediate-body integration is the explicit T11 hard gate.
	for index in [0, 2, 3, 4, 5, 6]:
		_restart_cancel_case()
		player1.exceeded = true
		var payment = _give_guardian(player1, "heiqiyihu_虚化")
		var boost = give_player_specific_card(player1, "heiqiyihu_" + SPECIAL_NAMES[index])
		var card = game_logic.card_db.get_card(boost)
		var printed = card.definition.duplicate(true)
		var wrapper = GameWrapper.new()
		wrapper.current_game = game_logic
		assert_eq(wrapper.get_player_boost_cancel_cost(player1.my_id, boost), 1)
		assert_true(wrapper.can_player_cancel_boost(player1.my_id, boost))
		assert_true(game_logic.do_boost(player1, boost))
		assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
		assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostCancel)
		assert_eq(game_logic.decision_info.player, player1.my_id)
		assert_eq(game_logic.decision_info.choice, 1)
		assert_true(player1.is_card_in_continuous_boosts(boost), "The real boost entered its zone before cancel.")
		assert_true(game_logic.active_boost.checked_counter)
		assert_gt(game_logic.active_boost.effects_resolved, 0)
		validate_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Boost_CancelDecision, player1, 1)
		var hand_size = player1.hand.size()
		assert_true(wrapper.submit_boost_cancel(player1.my_id, [payment], true))
		assert_false(player1.is_card_in_bleach(payment))
		assert_true(player1.is_card_in_discards(payment))
		assert_true(player1.is_card_in_continuous_boosts(boost))
		assert_eq(player1.hand.size(), hand_size, "Cancel grants an action, not an end-turn draw.")
		assert_true(player1.canceled_this_turn)
		assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
		assert_eq(game_logic.active_turn_player, player1.my_id)
		assert_null(game_logic.active_boost)
		assert_eq(card.definition, printed, "Dynamic cancel must not mutate printed data.")
		assert_eq(CardDataManager.get_card(card.definition["id"])["boost"]["cancel_cost"], -1)
		wrapper.free()


func test_cancel_six_normal_boosts_decline_ends_turn_without_spending():
	for index in [0, 2, 3, 4, 5, 6]:
		_restart_cancel_case()
		player1.exceeded = true
		give_gauge(player1, 1)
		var payment = player1.gauge[0].id
		var boost = give_player_specific_card(player1, "heiqiyihu_" + SPECIAL_NAMES[index])
		var hand_size = player1.hand.size()
		assert_true(game_logic.do_boost(player1, boost))
		assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
		assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostCancel)
		assert_eq(game_logic.decision_info.player, player1.my_id)
		assert_true(game_logic.do_boost_cancel(player1, [], false))
		assert_true(player1.is_card_in_gauge(payment))
		assert_true(player1.is_card_in_continuous_boosts(boost))
		assert_false(player1.canceled_this_turn)
		assert_eq(player1.hand.size(), hand_size, "One boost leaves hand, normal end-turn draw replaces it.")
		assert_eq(game_logic.active_turn_player, player2.my_id)
		assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
		assert_null(game_logic.active_boost)


func test_cancel_six_normal_boosts_insufficient_has_no_window():
	for index in [0, 2, 3, 4, 5, 6]:
		_restart_cancel_case()
		player1.exceeded = true
		var boost = give_player_specific_card(player1, "heiqiyihu_" + SPECIAL_NAMES[index])
		assert_eq(player1.get_available_gauge(), 0)
		assert_false(player1.can_cancel(game_logic.card_db.get_card(boost)))
		assert_true(game_logic.do_boost(player1, boost))
		assert_true(player1.is_card_in_continuous_boosts(boost))
		assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
		assert_eq(game_logic.active_turn_player, player2.my_id)
		validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Boost_CancelDecision, player1)


func test_cancel_six_front_boosts_do_not_gain_cancel():
	for index in [0, 2, 3, 4, 5, 6]:
		_restart_cancel_case()
		give_gauge(player1, 1)
		var boost = give_player_specific_card(player1, "heiqiyihu_" + SPECIAL_NAMES[index])
		var card = game_logic.card_db.get_card(boost)
		assert_eq(player1.get_boost_cancel_cost(card), -1)
		assert_false(player1.can_cancel(card))
		assert_true(game_logic.do_boost(player1, boost))
		assert_true(player1.is_card_in_continuous_boosts(boost))
		assert_eq(player1.gauge.size(), 1)
		assert_eq(game_logic.active_turn_player, player2.my_id)
		validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Boost_CancelDecision, player1)


func test_cancel_invalid_submissions_preserve_window_and_all_sources():
	player1.exceeded = true
	var guardian = _give_guardian(player1, "heiqiyihu_虚化")
	var other = give_player_specific_card(player2, "gg_normal_cross")
	var boost = give_player_specific_card(player1, "heiqiyihu_地裂崩击")
	assert_true(game_logic.do_boost(player1, boost))
	assert_false(game_logic.do_boost_cancel(player2, [], true))
	assert_false(game_logic.do_boost_cancel(player1, [], true))
	assert_false(game_logic.do_boost_cancel(player1, [guardian, guardian], true))
	assert_false(game_logic.do_boost_cancel(player1, [guardian, other], true))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostCancel)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(player1.is_card_in_bleach(guardian))
	assert_true(player2.is_card_in_hand(other))
	assert_true(game_logic.do_boost_cancel(player1, [guardian], true))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	assert_eq(game_logic.active_turn_player, player1.my_id)


func test_cancel_preview_revert_and_ordinary_gg_keep_printed_rule():
	player1.exceeded = true
	give_gauge(player1, 1)
	var special = give_player_specific_card(player1, "heiqiyihu_地裂崩击")
	var card = game_logic.card_db.get_card(special)
	assert_eq(player1.get_boost_cancel_cost(card), 1)
	assert_true(player1.can_cancel(card))
	player1.exceeded = false
	assert_eq(player1.get_boost_cancel_cost(card), -1)
	assert_false(player1.can_cancel(card))
	player1.exceeded = true
	var ordinary = give_player_specific_card(player1, "gg_normal_slash")
	assert_eq(player1.get_boost_cancel_cost(game_logic.card_db.get_card(ordinary)), 1)
	assert_true(game_logic.do_boost(player1, ordinary))
	assert_eq(game_logic.decision_info.choice, 1)
	assert_eq(game_logic.card_db.get_card(ordinary).definition["boost"]["boost_type"], "immediate")
	assert_eq(player1.arena_location, 6, "Dash's real Advance 3 resolves before the cancel window.")
	assert_true(player1.is_card_in_discards(ordinary))
	var payment = player1.gauge[0].id
	assert_true(game_logic.do_boost_cancel(player1, [payment], true))
	assert_true(player1.is_card_in_discards(payment))
	assert_true(player1.is_card_in_discards(ordinary))
	assert_false(player1.is_card_in_continuous_boosts(ordinary))
	assert_eq(game_logic.active_turn_player, player1.my_id)


func test_cancel_blocked_or_pending_strike_does_not_grant_dynamic_window():
	for restriction in ["cancel_blocked_this_turn", "strike_on_boost_cleanup", "wild_strike_on_boost_cleanup"]:
		_restart_cancel_case()
		player1.exceeded = true
		give_gauge(player1, 1)
		var boost = give_player_specific_card(player1, "heiqiyihu_地裂崩击")
		var card = game_logic.card_db.get_card(boost)
		player1.set(restriction, true)
		assert_eq(game_logic._get_effective_boost_cancel_cost(player1, card), -1)
		assert_false(player1.can_cancel(card))
		# Check the real normal-boost chain for the non-wild cases.
		# Wild preview uses the same S7 early return; it need not start a
		# random attack to validate this cancellation eligibility.
		if restriction != "wild_strike_on_boost_cleanup":
			assert_true(game_logic.do_boost(player1, boost))
			assert_true(player1.is_card_in_continuous_boosts(boost))
			validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Boost_CancelDecision, player1)
			assert_eq(player1.gauge.size(), 1)
			if restriction == "strike_on_boost_cleanup":
				assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)
			else:
				assert_eq(game_logic.active_turn_player, player2.my_id)


func test_cancel_virtual_guardian_and_active_strike_have_no_window():
	# Triggering guardians is the front-face UA, not the exceeded resource UA.
	position_players(player1, 3, player2, 4)
	var source = _give_guardian(player1, "heiqiyihu_地裂崩击")
	give_gauge(player1, 1)
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	assert_true(game_logic.do_choice(player1, 0))
	assert_true(player1.is_card_in_discards(source))
	assert_false(player1.is_card_in_continuous_boosts(source))
	assert_null(game_logic.active_boost)
	assert_eq(player1.get_boost_cancel_cost(game_logic.card_db.get_card(source)), -1)
	assert_false(player1.can_cancel(game_logic.card_db.get_card(source)))
	validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Boost_CancelDecision, player1)
	var attack = give_player_specific_card(player1, "gg_normal_grasp")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_true(game_logic.do_choice(player1, 0))
	assert_null(game_logic.active_strike)
	assert_eq(player1.gauge.size(), 2)
	validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Boost_CancelDecision, player1)
	_restart_cancel_case()
	player1.exceeded = true
	position_players(player1, 3, player2, 4)
	source = _give_guardian(player1, "heiqiyihu_地裂崩击")
	give_gauge(player1, 1)
	assert_false(game_logic._has_heiqiyihu_guardian_option())
	attack = give_player_specific_card(player1, "gg_normal_grasp")
	response = give_player_specific_card(player2, "gg_normal_focus")
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_not_null(game_logic.active_strike)
	assert_true(player1.is_card_in_bleach(source), "Exceed grants spending, not guardian triggering.")
	assert_eq(player1.get_boost_cancel_cost(game_logic.card_db.get_card(source)), -1)
	assert_false(player1.can_cancel(game_logic.card_db.get_card(source)))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_true(game_logic.do_choice(player1, 0))
	assert_null(game_logic.active_strike)
	assert_true(player1.is_card_in_bleach(source))
	assert_eq(player1.gauge.size(), 2)
	validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Boost_CancelDecision, player1)


func test_guardian_payment_front_rejects_and_exceeded_values_are_usual():
	var normal = _give_guardian(player1, "gg_normal_grasp")
	var ultra = _give_guardian(player1, "heiqiyihu_虚化")
	var ordinary_force = player1.get_available_force()
	var ordinary_gauge = player1.get_available_gauge()
	assert_false(player1.can_pay_cost_with([normal], 1, 0, false, 0))
	assert_false(player1.can_pay_cost_with([ultra], 0, 1, false, 0))
	assert_false(game_logic.do_move(player1, [ultra], 5))
	assert_true(player1.is_card_in_bleach(ultra))
	player1.exceeded = true
	assert_eq(player1.get_available_force(), ordinary_force + 3)
	assert_eq(player1.get_available_gauge(), ordinary_gauge + 2)
	assert_eq(player1.get_force_with_cards([normal, ultra], "MOVE", false, false), 3)
	assert_eq(player1.get_force_with_cards([ultra], "CHANGE_CARDS", true, false), 1)
	assert_eq(player1.get_gauge_payment_value_for_cards([normal, ultra]), 2)
	assert_true(player1.can_pay_cost_with([normal, ultra], 3, 0, false, 0))
	assert_true(player1.can_pay_cost_with([ultra], 0, 1, false, 0))
	assert_false(player1.can_pay_cost_with([ultra], 0, 2, false, 0))


func test_guardian_payment_invalid_sets_do_not_partially_spend_or_move():
	player1.exceeded = true
	var own = _give_guardian(player1, "gg_normal_grasp")
	var other = _give_guardian(player2, "gg_normal_grasp")
	var hand_size = player1.hand.size()
	var discard_size = player1.discards.size()
	for invalid in [[own, own], [own, other], [own, 987654321]]:
		assert_false(player1.can_pay_cost_with(invalid, 1, 0, false, 0))
		assert_false(game_logic.do_move(player1, invalid, 4))
		assert_false(game_logic.do_change(player1, invalid, false))
		assert_true(player1.is_card_in_bleach(own))
		assert_true(player2.is_card_in_bleach(other))
		assert_eq(player1.hand.size(), hand_size)
		assert_eq(player1.discards.size(), discard_size)
		assert_eq(player1.arena_location, 3)
	var stale = player1.remove_card_from_bleach(own)
	player1.add_to_discards(stale)
	assert_false(game_logic.do_move(player1, [own], 4))
	assert_eq(player1.discards.count(stale), 1)


func test_guardian_payment_move_ultra_provides_two_force_from_real_zone():
	player1.exceeded = true
	var ultra = _give_guardian(player1, "heiqiyihu_虚化")
	game_logic.get_latest_events()
	assert_true(game_logic.do_move(player1, [ultra], 5))
	assert_eq(player1.arena_location, 5)
	assert_true(player1.is_card_in_discards(ultra))
	assert_false(player1.is_card_in_bleach(ultra))
	assert_eq(validate_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_AddToDiscard, player1, ultra).size(), 1)


func test_guardian_payment_change_ultra_can_generate_one_or_two():
	for single in [true, false]:
		_restart_for_opening(30, 30)
		assert_true(game_logic.do_mulligan(player1, []))
		assert_true(game_logic.do_mulligan(player2, []))
		player1.exceeded = true
		player1.discard([player1.hand[0].id])
		var ultra = _give_guardian(player1, "heiqiyihu_虚化")
		var hand_size = player1.hand.size()
		game_logic.get_latest_events()
		assert_true(game_logic.do_change(player1, [ultra], single))
		var amount = 1 if single else 2
		assert_eq(player1.hand.size(), hand_size + amount + 1)
		assert_true(player1.is_card_in_discards(ultra))
		assert_false(player1.is_card_in_bleach(ultra))
		assert_eq(validate_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Draw, player1).size(), amount + 1)


func test_guardian_payment_boost_force_and_gauge_accept_mixed_real_sources():
	for gauge_cost in [-1, 2]:
		_restart_for_opening(30, 30)
		assert_true(game_logic.do_mulligan(player1, []))
		assert_true(game_logic.do_mulligan(player2, []))
		player1.exceeded = true
		var guardian = _give_guardian(player1, "gg_normal_grasp")
		var other_id = give_gauge(player1, 1)[0] if gauge_cost == 2 else player1.hand[0].id
		var boost_id = _payment_boost({"effect_type": StrikeEffects.Draw, "amount": 1}, 2 if gauge_cost < 0 else 0, gauge_cost)
		assert_true(game_logic.do_boost(player1, boost_id, [guardian, other_id]))
		assert_true(player1.is_card_in_discards(guardian))
		assert_true(player1.is_card_in_discards(other_id))
		assert_false(player1.is_card_in_bleach(guardian))
		assert_false(player1.is_card_in_gauge(other_id))
		assert_false(player1.is_card_in_hand(other_id))


func test_guardian_payment_attack_gauge_mixes_guardian_with_gauge():
	player1.exceeded = true
	position_players(player1, 3, player2, 4)
	var guardian = _give_guardian(player1, "heiqiyihu_虚化")
	var gauge = give_gauge(player1, 1)[0]
	var attack = give_player_specific_card(player1, "heiqiyihu_呼唤我的名字吧！")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_PayStrikeCost_Required)
	assert_eq(game_logic.decision_info.cost, 2)
	assert_false(game_logic.do_pay_strike_cost(player1, [guardian, guardian], false))
	assert_true(player1.is_card_in_bleach(guardian))
	assert_true(player1.is_card_in_gauge(gauge))
	assert_true(game_logic.do_pay_strike_cost(player1, [guardian, gauge], false))
	assert_true(player1.is_card_in_discards(guardian))
	assert_true(player1.is_card_in_discards(gauge))
	_finish_t6_huhuan_cleanup(attack)


func test_guardian_payment_attack_force_ultra_uses_two():
	player1.exceeded = true
	var guardian = _give_guardian(player1, "heiqiyihu_虚化")
	var attack_id = give_player_specific_card(player1, "gg_normal_focus")
	var attack = game_logic.card_db.get_card(attack_id)
	attack.definition = attack.definition.duplicate(true)
	attack.definition["force_cost"] = 2
	var response = give_player_specific_card(player2, "gg_normal_focus")
	assert_true(game_logic.do_strike(player1, attack_id, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_eq(game_logic.decision_info.limitation, "force")
	assert_eq(game_logic.decision_info.cost, 2)
	assert_true(game_logic.do_pay_strike_cost(player1, [guardian], false))
	assert_true(player1.is_card_in_discards(guardian))
	assert_false(player1.is_card_in_bleach(guardian))
	assert_null(game_logic.active_strike)


func test_guardian_payment_force_for_effect_mixed_and_duplicate_rejection():
	player1.exceeded = true
	var guardian = _give_guardian(player1, "heiqiyihu_虚化")
	var hand_id = player1.hand[0].id
	var boost_id = _payment_boost({
		"effect_type": StrikeEffects.ForceForEffect, "force_max": 3,
		"per_force_effect": {"effect_type": StrikeEffects.Draw, "amount": 1},
		"overall_effect": null
	})
	assert_true(game_logic.do_boost(player1, boost_id))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ForceForEffect)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_false(game_logic.do_force_for_effect(player1, [guardian, guardian], false))
	assert_true(player1.is_card_in_bleach(guardian))
	var hand_size = player1.hand.size()
	assert_true(game_logic.do_force_for_effect(player1, [guardian, hand_id], false))
	assert_true(player1.is_card_in_discards(guardian))
	assert_true(player1.is_card_in_discards(hand_id))
	assert_eq(player1.hand.size(), hand_size - 1 + 3 + 1)


func test_guardian_payment_gauge_for_effect_mixed_and_correct_zone():
	player1.exceeded = true
	var guardian = _give_guardian(player1, "heiqiyihu_虚化")
	var gauge = give_gauge(player1, 1)[0]
	var boost_id = _payment_boost({
		"effect_type": StrikeEffects.GaugeForEffect, "gauge_max": 2, "min_gauge": 2,
		"per_gauge_effect": {"effect_type": StrikeEffects.Draw, "amount": 1},
		"overall_effect": null
	})
	assert_true(game_logic.do_boost(player1, boost_id))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_GaugeForEffect)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_false(game_logic.do_gauge_for_effect(player1, [guardian, guardian]))
	assert_true(player1.is_card_in_bleach(guardian))
	var hand_size = player1.hand.size()
	assert_true(game_logic.do_gauge_for_effect(player1, [guardian, gauge]))
	assert_eq(player1.hand.size(), hand_size + 2 + 1)
	assert_true(player1.is_card_in_discards(guardian))
	assert_true(player1.is_card_in_discards(gauge))


func test_guardian_payment_normal_cancel_spends_ultra_as_one_gauge():
	player1.exceeded = true
	var guardian = _give_guardian(player1, "heiqiyihu_虚化")
	var boost = give_player_specific_card(player1, "gg_normal_slash")
	assert_true(game_logic.do_boost(player1, boost))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostCancel)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_boost_cancel(player1, [guardian], true))
	assert_true(player1.is_card_in_discards(guardian))
	assert_false(player1.is_card_in_bleach(guardian))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	assert_eq(game_logic.active_turn_player, player1.my_id)


func test_guardian_payment_force_for_armor_uses_ultra_two_force():
	player1.exceeded = true
	position_players(player1, 3, player2, 4)
	var guardian = _give_guardian(player1, "heiqiyihu_虚化")
	var attack = give_player_specific_card(player1, "gg_normal_block")
	var response = give_player_specific_card(player2, "gg_normal_grasp")
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_eq(game_logic.decision_info.player, player2.my_id)
	assert_true(game_logic.do_choice(player2, 0))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ForceForArmor)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_force_for_armor(player1, [guardian]))
	assert_eq(player1.life, 30)
	assert_true(player1.is_card_in_discards(guardian))
	assert_true(player1.is_card_in_gauge(attack))
	assert_null(game_logic.active_strike)


func test_guardian_payment_gauge_effect_returns_guardian_to_hand_or_overdrive():
	for destination in ["hand", "overdrive"]:
		_restart_for_opening(30, 30)
		assert_true(game_logic.do_mulligan(player1, []))
		assert_true(game_logic.do_mulligan(player2, []))
		player1.exceeded = true
		var guardian = _give_guardian(player1, "heiqiyihu_虚化")
		var per_effect = {"effect_type": StrikeEffects.Draw, "amount": 1}
		per_effect["spent_cards_to_" + destination] = true
		var boost = _payment_boost({
			"effect_type": StrikeEffects.GaugeForEffect, "gauge_max": 1, "min_gauge": 1,
			"per_gauge_effect": per_effect, "overall_effect": null
		})
		assert_true(game_logic.do_boost(player1, boost))
		assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_GaugeForEffect)
		assert_true(game_logic.do_gauge_for_effect(player1, [guardian]))
		assert_false(player1.is_card_in_bleach(guardian))
		assert_false(player1.is_card_in_discards(guardian))
		if destination == "hand":
			assert_true(player1.is_card_in_hand(guardian))
			assert_eq(player1.hand.count(game_logic.card_db.get_card(guardian)), 1)
			assert_eq(game_logic.game_state, Enums.GameState.GameState_DiscardDownToMax)
			assert_true(game_logic.do_discard_to_max(player1, [player1.hand[0].id]))
			assert_eq(game_logic.active_turn_player, player2.my_id)
		else:
			assert_eq(player1.overdrive.count(game_logic.card_db.get_card(guardian)), 1)
			assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)


func test_guardian_payment_force_effect_sends_guardian_to_overdrive():
	player1.exceeded = true
	var guardian = _give_guardian(player1, "heiqiyihu_虚化")
	var boost = _payment_boost({
		"effect_type": StrikeEffects.ForceForEffect, "force_max": 2,
		"per_force_effect": {"effect_type": StrikeEffects.Draw, "amount": 1, "spent_cards_to_overdrive": true},
		"overall_effect": null
	})
	assert_true(game_logic.do_boost(player1, boost))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ForceForEffect)
	assert_true(game_logic.do_force_for_effect(player1, [guardian], false))
	assert_false(player1.is_card_in_bleach(guardian))
	assert_false(player1.is_card_in_discards(guardian))
	assert_eq(player1.overdrive.count(game_logic.card_db.get_card(guardian)), 1)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_DiscardDownToMax)
	assert_true(game_logic.do_discard_to_max(player1, [player1.hand[0].id]))
	assert_eq(game_logic.active_turn_player, player2.my_id)


func test_guardian_payment_permission_does_not_alias_guardian_zone_to_gauge():
	player1.exceeded = true
	var guardian = _give_guardian(player1, "heiqiyihu_虚化")
	var gauge = give_gauge(player1, 1)[0]
	assert_eq(player1.get_available_gauge(), 2)
	assert_false(player1.is_card_in_gauge(guardian))
	player1.discard_gauge()
	assert_true(player1.is_card_in_discards(gauge))
	assert_true(player1.is_card_in_bleach(guardian))
	assert_eq(player1.get_available_gauge(), 1)
	assert_eq(player1.get_gauge_payment_value(guardian), 1)
	player1.revert_exceed()
	assert_eq(player1.get_available_gauge(), 0)
	assert_false(player1.can_pay_cost_with([guardian], 1, 0, false, 0))


func test_data_identity_and_public_guardian_zone():
	assert_eq(player1.deck_def["id"], "heiqiyihu")
	assert_eq(player1.deck_def["display_name"], "黑崎一护-死神代理")
	assert_eq(player1.deck_def["season"], 0)
	assert_eq(player1.get_exceed_cost(), 0)
	assert_eq(player1.life, 30, "Do not guess starting HP from the A+ rank.")
	assert_true(player1.has_bleach_zone())
	assert_eq(player1.get_bleach_zone_name(), "守护区")
	assert_false(player1.is_bleach_zone_facedown())
	assert_eq(player1.bleach_zone.size(), 0)
	assert_eq(player1.deck_def["on_exceed"]["effect_type"], "heiqiyihu_exceed_draw")
	assert_eq(player1.deck_def["ability_effects"][0]["effect_type"], "heiqiyihu_guardian_thresholds")
	assert_eq(player1.deck_def["ability_effects"][1]["effect_type"], "heiqiyihu_guardian_before_set")
	assert_eq(player1.deck_def["exceed_ability_effects"][0]["effect_type"], "heiqiyihu_guardian_resources")


func test_data_thirty_cards_fifteen_pairs_and_image_indices():
	var deck = player1.deck_def
	assert_eq(deck["cards"].size(), 30)
	var counts = {}
	for entry in deck["cards"]:
		var definition_id = entry["definition_id"]
		counts[definition_id] = counts.get(definition_id, 0) + 1
		assert_not_null(CardDataManager.get_card(definition_id))
		if definition_id.begins_with("heiqiyihu_"):
			assert_eq(entry["image_name"], "specials")
			assert_eq(entry["image_index"], SPECIAL_NAMES.find(definition_id.trim_prefix("heiqiyihu_")))
		else:
			assert_true(definition_id.begins_with("gg_normal_"))
			var normal_name = definition_id.trim_prefix("gg_normal_")
			assert_true(NORMAL_INDICES.has(normal_name))
			assert_eq(entry["image_name"], "normals")
			assert_eq(entry["image_index"], NORMAL_INDICES[normal_name])
	assert_eq(counts.size(), 15)
	for definition_id in counts:
		assert_eq(counts[definition_id], 2, definition_id)
	assert_eq(deck["custom_card_definitions"].size(), 7)
	for image_name in ["character_default", "character_exceeded", "cardback", "specials", "normals"]:
		var image = deck["image_resources"][image_name]
		var filename = "normals_gg" if image_name == "normals" else image_name
		assert_eq(image["url"], "https://cdn.exceedcntyd.com/decks_custom/heiqiyihu/" + filename + ".jpg")
		assert_eq(image["multiple_cards"], image_name in ["specials", "normals"])


func test_data_seven_runtime_special_definitions_match_printed_stats():
	for i in range(SPECIAL_NAMES.size()):
		var definition = _definition(i)
		assert_eq(definition["id"], "heiqiyihu_" + SPECIAL_NAMES[i])
		assert_eq(definition["display_name"], SPECIAL_NAMES[i])
		for j in range(STAT_KEYS.size()):
			assert_eq(definition[STAT_KEYS[j]], PRINTED_STATS[i][j], SPECIAL_NAMES[i] + ":" + STAT_KEYS[j])


func test_data_printed_boost_costs_types_names_and_text():
	for i in range(SPECIAL_NAMES.size()):
		var definition = _definition(i)
		var boost = definition["boost"]
		assert_eq(boost["display_name"], BOOST_NAMES[i])
		assert_eq(boost["force_cost"], 2 if i == 1 else 0)
		assert_eq(boost["cancel_cost"], -1)
		assert_eq(boost["boost_type"], "immediate" if i == 1 else "continuous")
		for effect in definition["effects"] + boost["effects"]:
			assert_false(str(effect.get("override_description", "")).is_empty())
			assert_false(str(effect["override_description"]).contains("缺失文本"))
			assert_true(effect.has("timing"))
			assert_true(effect.has("effect_type"))


func test_data_effect_timings_and_atomic_chains():
	var huhuan = _definition(0)
	assert_eq(huhuan["effects"][0]["timing"], "set_strike")
	assert_eq(huhuan["effects"][0]["effect_type"], "heiqiyihu_huhuan_guardian")
	assert_eq(huhuan["boost"]["effects"][0]["amount"], 3)
	assert_eq(huhuan["boost"]["effects"][1]["amount"], 0)
	assert_eq(huhuan["boost"]["effects"][1]["amount2"], 1)
	assert_eq(huhuan["boost"]["effects"][2]["timing"], "cleanup")
	assert_eq(huhuan["boost"]["effects"][2]["effect_type"], "heiqiyihu_getsuga_cleanup")
	var xuhua = _definition(1)
	assert_eq(xuhua["effects"][0]["effect_type"], "set_total_power")
	assert_eq(xuhua["effects"][0]["amount"], 0)
	assert_eq(xuhua["effects"][0]["and"]["effect_type"], "attack_does_not_hit")
	assert_eq(xuhua["effects"][1]["timing"], "when_hit")
	assert_eq(xuhua["effects"][1]["effect_type"], "heiqiyihu_xuhua_payment")
	assert_eq(xuhua["effects"][2]["timing"], "after")
	assert_eq(xuhua["effects"][2]["effect_type"], "heiqiyihu_xuhua_recover")
	assert_eq(xuhua["boost"]["effects"][0]["timing"], "now")
	assert_eq(xuhua["boost"]["effects"][0]["effect_type"], "heiqiyihu_add_guardian")
	var dilie = _definition(2)
	assert_eq(dilie["effects"].size(), 1)
	assert_eq(dilie["effects"][0]["timing"], "hit")
	assert_eq(dilie["effects"][0]["effect_type"], "heiqiyihu_pull_adjacent")
	assert_eq(dilie["effects"][0]["and"]["effect_type"], "opponent_discard_random")
	assert_eq(dilie["effects"][0]["and"]["amount"], 1)
	var jingxue = _definition(3)
	assert_eq(jingxue["effects"][0]["timing"], "during_strike")
	assert_eq(jingxue["effects"][0]["effect_type"], "heiqiyihu_prevent_opponent_moving_me")
	assert_eq(jingxue["effects"][1]["timing"], "after")
	assert_eq(jingxue["effects"][1]["choice"][0]["effect_type"], "move_strike_to_bleach")
	assert_eq(jingxue["effects"][1]["choice"][0]["_choice_text"], "将静血装置入守护区")
	assert_eq(jingxue["effects"][1]["choice"][1]["effect_type"], "pass")
	assert_eq(jingxue["effects"][1]["choice"][1]["_choice_text"], "不置入守护区")
	var linghun = _definition(4)["effects"][0]
	assert_eq(_definition(4)["effects"].size(), 1)
	assert_eq(linghun["timing"], "hit")
	assert_eq(linghun["effect_type"], "draw")
	assert_eq(linghun["amount"], 1)
	assert_eq(linghun["and"]["effect_type"], "force_for_effect")
	assert_eq(linghun["and"]["force_max"], 3)
	assert_eq(linghun["and"]["min_force"], 0)
	assert_eq(linghun["and"]["per_force_effect"]["effect_type"], "powerup")
	assert_eq(linghun["and"]["per_force_effect"]["amount"], 1)
	assert_true(linghun["and"]["per_force_effect"]["combine_multiple_into_one"])
	var quanli = _definition(5)
	assert_eq(quanli["effects"][0]["timing"], "before")
	assert_eq(quanli["effects"][0]["effect_type"], "close")
	assert_eq(quanli["effects"][0]["amount"], 2)
	assert_eq(quanli["boost"]["effects"][0]["timing"], "before")
	assert_eq(quanli["boost"]["effects"][0]["effect_type"], "move_to_any_space")
	assert_eq(quanli["boost"]["effects"][0]["move_min"], 0)
	assert_eq(quanli["boost"]["effects"][0]["move_max"], 1)
	var shunbu = _definition(6)
	assert_eq(shunbu["effects"][0]["timing"], "before")
	assert_eq(shunbu["effects"][0]["move_min"], 0)
	assert_eq(shunbu["effects"][0]["move_max"], 3)
	assert_true(shunbu["effects"][0]["advance_only"])
	assert_eq(shunbu["effects"][0]["and"]["condition"], "advanced_through")
	assert_eq(shunbu["effects"][0]["and"]["effect_type"], "heiqiyihu_shunbu_crossed")
	assert_eq(shunbu["effects"][1]["timing"], "after")
	assert_eq(shunbu["effects"][1]["condition"], "not_hit_opponent")
	assert_eq(shunbu["effects"][1]["effect_type"], "gain_advantage")
	for row in [[2, "during_strike", "powerup", 2], [3, "during_strike", "guardup", 2], [4, "hit", "draw", 2], [6, "during_strike", "speedup", 1]]:
		var effect = _definition(row[0])["boost"]["effects"][0]
		assert_eq(effect["timing"], row[1])
		assert_eq(effect["effect_type"], row[2])
		assert_eq(effect["amount"], row[3])


func test_data_gg_definitions_are_reused_unchanged():
	var source = CardDataManager.load_json_file("res://data/card_definitions.json")
	var originals = {}
	for definition in source:
		if definition.get("id", "").begins_with("gg_normal_"):
			originals[definition["id"]] = definition
	for normal_name in NORMAL_INDICES:
		var definition_id = "gg_normal_" + normal_name
		assert_eq(CardDataManager.get_card(definition_id), originals[definition_id])


func test_data_loading_again_does_not_duplicate_definitions():
	var count_before = CardDataManager.card_data.size()
	var expected = []
	for i in range(SPECIAL_NAMES.size()):
		expected.append(_definition(i).duplicate(true))
	CardDataManager.load_deck_if_custom(player1.deck_def)
	assert_eq(CardDataManager.card_data.size(), count_before)
	for i in range(SPECIAL_NAMES.size()):
		assert_eq(_definition(i), expected[i])


func _assert_threshold_choice(target: Player, threshold: int):
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, target.my_id)
	assert_eq(game_logic.decision_info.effect_type, StrikeEffects.HeiqiyihuThresholdSource)
	assert_eq(game_logic.decision_info.effect["threshold"], threshold)
	assert_eq(game_logic.decision_info.choice[0]["_choice_text"], "将牌堆顶1张牌置入守护区")
	assert_eq(game_logic.decision_info.choice.size(), 1 + target.hand.size())
	for choice in game_logic.decision_info.choice:
		assert_ne(choice["effect_type"], StrikeEffects.Pass, "Threshold placement is mandatory.")
		if choice["source"] == "hand":
			assert_true(target.is_card_in_hand(choice["guardian_card_id"]))
			assert_true(choice["_choice_text"].begins_with("将手牌「"))


func _restart_for_opening(first_life: int, second_life: int, first_player = Enums.PlayerId.PlayerId_Player, opponent_id: String = ""):
	game_logic.teardown()
	game_logic.free()
	# LocalGame.teardown owns and frees test-mode loaders.
	image_loader = CardImageLoader.new(true)
	var first_deck = CardDataManager.get_deck_from_str_id("heiqiyihu").duplicate(true)
	var second_deck = first_deck.duplicate(true) if opponent_id.is_empty() else CardDataManager.get_deck_from_str_id(opponent_id).duplicate(true)
	first_deck["starting_life"] = first_life
	second_deck["starting_life"] = second_life
	first_deck["life_cap"] = max(Enums.MaxLife, first_life)
	second_deck["life_cap"] = max(Enums.MaxLife, second_life)
	game_logic = LocalGame.new(image_loader)
	game_logic.initialize_game(first_deck, second_deck, "p1", "p2", first_player, 24010)
	player1 = game_logic.player
	player2 = game_logic.opponent
	game_logic.draw_starting_hands_and_begin()
	game_logic.get_latest_events()


func _take_damage(target: Player, amount: int):
	game_logic.handle_strike_effect(-1, {"effect_type": StrikeEffects.TakeDamage, "amount": amount}, target)


func test_threshold_initial_thirty_has_no_decision():
	assert_eq(player1.life, 30)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	assert_eq(player1.heiqiyihu_thresholds_used.size(), 0)
	assert_eq(game_logic.heiqiyihu_pending_thresholds.size(), 0)
	assert_true(game_logic.heiqiyihu_threshold_context.is_empty())


func test_threshold_opening_twenty_four_after_both_mulligans():
	_restart_for_opening(24, 30)
	assert_true(game_logic.do_mulligan(player1, []))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_Mulligan)
	assert_eq(player1.heiqiyihu_thresholds_used.size(), 0)
	game_logic.get_latest_events()
	assert_true(game_logic.do_mulligan(player2, []))
	_assert_threshold_choice(player1, 25)
	validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_AdvanceTurn, player1)
	var hand_id = player1.hand[0].id
	assert_true(game_logic.do_choice(player1, 1))
	assert_false(player1.is_card_in_hand(hand_id))
	assert_true(player1.is_card_in_bleach(hand_id))
	assert_eq(player1.bleach_zone.size(), 1)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	validate_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_AdvanceTurn, player1)


func test_threshold_opening_nine_resolves_three_times():
	_restart_for_opening(9, 30)
	assert_true(game_logic.do_mulligan(player1, []))
	assert_true(game_logic.do_mulligan(player2, []))
	var hand_size = player1.hand.size()
	for threshold in [25, 15, 10]:
		_assert_threshold_choice(player1, threshold)
		var top_id = player1.deck[0].id
		var size_before = player1.deck.size()
		assert_true(game_logic.do_choice(player1, 0))
		assert_true(player1.is_card_in_bleach(top_id))
		assert_false(player1.is_card_in_hand(top_id))
		assert_eq(player1.deck.size(), size_before - 1)
		assert_eq(player1.hand.size(), hand_size)
	assert_eq(player1.bleach_zone.size(), 3)
	assert_eq(player1.heiqiyihu_thresholds_used, [25, 15, 10])
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)


func test_threshold_opening_mirror_uses_actual_first_player():
	_restart_for_opening(24, 24, Enums.PlayerId.PlayerId_Opponent)
	assert_true(game_logic.do_mulligan(player1, []))
	assert_true(game_logic.do_mulligan(player2, []))
	_assert_threshold_choice(player2, 25)
	assert_true(game_logic.do_choice(player2, 0))
	_assert_threshold_choice(player1, 25)
	assert_eq(player2.bleach_zone.size(), 1)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player1.bleach_zone.size(), 1)
	assert_eq(game_logic.active_turn_player, player2.my_id)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)


func test_threshold_boundaries_and_healing_do_not_reset():
	_take_damage(player1, 6)
	assert_eq(player1.life, 24)
	_assert_threshold_choice(player1, 25)
	assert_true(game_logic.do_choice(player1, 0))
	game_logic.handle_strike_effect(-1, {"effect_type": StrikeEffects.GainLife, "amount": 6}, player1)
	assert_eq(player1.life, 30)
	_take_damage(player1, 6)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	assert_eq(player1.bleach_zone.size(), 1)
	game_logic.handle_strike_effect(-1, {"effect_type": StrikeEffects.SetLife, "amount": 16}, player1)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	_take_damage(player1, 1)
	assert_eq(player1.life, 15)
	_assert_threshold_choice(player1, 15)
	assert_true(game_logic.do_choice(player1, 0))
	game_logic.handle_strike_effect(-1, {"effect_type": StrikeEffects.SetLife, "amount": 11}, player1)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	_take_damage(player1, 1)
	_assert_threshold_choice(player1, 10)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player1.heiqiyihu_thresholds_used, [25, 15, 10])
	assert_eq(player1.bleach_zone.size(), 3)


func test_threshold_one_life_change_crosses_three():
	_take_damage(player1, 21)
	assert_eq(player1.life, 9)
	for threshold in [25, 15, 10]:
		_assert_threshold_choice(player1, threshold)
		assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player1.bleach_zone.size(), 3)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)


func test_threshold_spend_life_and_indirect_damage():
	game_logic.handle_strike_effect(-1, {"effect_type": StrikeEffects.SpendLife, "amount": 5}, player1)
	assert_eq(player1.life, 25)
	assert_eq(player1.last_spent_life, 5)
	_assert_threshold_choice(player1, 25)
	assert_true(game_logic.do_choice(player1, 0))
	_take_damage(player1, 10)
	assert_eq(player1.life, 15)
	_assert_threshold_choice(player1, 15)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player1.bleach_zone.size(), 2)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)


func test_threshold_exceeded_has_no_new_trigger():
	player1.exceeded = true
	_take_damage(player1, 21)
	assert_eq(player1.life, 9)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	assert_eq(player1.heiqiyihu_thresholds_used.size(), 0)
	assert_eq(player1.bleach_zone.size(), 0)
	assert_true(game_logic.heiqiyihu_pending_thresholds.is_empty())


func test_threshold_lethal_does_not_prompt():
	_take_damage(player1, 30)
	assert_eq(player1.life, 0)
	assert_true(game_logic.game_over)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_GameOver)
	assert_true(game_logic.heiqiyihu_pending_thresholds.is_empty())
	assert_true(game_logic.heiqiyihu_threshold_context.is_empty())
	assert_eq(player1.bleach_zone.size(), 0)


func test_threshold_topdeck_reshuffles_without_entering_hand():
	player1.discards.append_array(player1.deck)
	player1.deck.clear()
	var hand_size = player1.hand.size()
	_take_damage(player1, 6)
	_assert_threshold_choice(player1, 25)
	game_logic.get_latest_events()
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player1.reshuffle_remaining, 0)
	assert_eq(player1.bleach_zone.size(), 1)
	assert_eq(player1.hand.size(), hand_size)
	var guardian_id = player1.bleach_zone[0].id
	assert_false(player1.is_card_in_hand(guardian_id))
	assert_false(player1.is_card_in_discards(guardian_id))
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_ReshuffleDiscard, player1)
	validate_has_event(events, Enums.EventType.EventType_AddToBleach, player1, guardian_id)
	validate_not_has_event(events, Enums.EventType.EventType_Draw, player1)


func test_threshold_empty_hand_has_only_topdeck():
	player1.discards.append_array(player1.hand)
	player1.hand.clear()
	_take_damage(player1, 6)
	_assert_threshold_choice(player1, 25)
	assert_eq(game_logic.decision_info.choice.size(), 1)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player1.bleach_zone.size(), 1)
	assert_eq(player1.hand.size(), 0)


func test_threshold_empty_deck_without_reshuffle_loses():
	player1.sealed.append_array(player1.deck)
	player1.deck.clear()
	player1.reshuffle_remaining = 0
	_take_damage(player1, 6)
	_assert_threshold_choice(player1, 25)
	assert_true(game_logic.do_choice(player1, 0))
	assert_true(game_logic.game_over)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_GameOver)
	assert_eq(game_logic.game_over_winning_player, player2)
	assert_eq(player1.bleach_zone.size(), 0)
	assert_true(game_logic.heiqiyihu_threshold_context.is_empty())


func test_threshold_wrong_player_invalid_index_and_stale_hand_are_rejected():
	_take_damage(player1, 6)
	_assert_threshold_choice(player1, 25)
	var threshold_count = player1.heiqiyihu_thresholds_used.size()
	assert_false(game_logic.do_choice(player2, 0))
	assert_false(game_logic.do_choice(player1, -1))
	assert_false(game_logic.do_choice(player1, game_logic.decision_info.choice.size()))
	assert_eq(player1.bleach_zone.size(), 0)
	assert_eq(player1.heiqiyihu_thresholds_used.size(), threshold_count)
	var unavailable = player1.hand.pop_front()
	player1.add_to_discards(unavailable)
	assert_false(game_logic.do_choice(player1, 1))
	assert_false(player1.is_card_in_bleach(unavailable.id))
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player1.bleach_zone.size(), 1)


func test_threshold_atomic_and_chain_resumes_once():
	var hand_size = player1.hand.size()
	game_logic.handle_strike_effect(-1, {
		"effect_type": StrikeEffects.TakeDamage,
		"amount": 6,
		"and": {"effect_type": StrikeEffects.Draw, "amount": 2}
	}, player1)
	_assert_threshold_choice(player1, 25)
	assert_eq(player1.hand.size(), hand_size, "The and-chain waits for threshold placement.")
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player1.hand.size(), hand_size + 2)
	assert_eq(player1.bleach_zone.size(), 1)
	assert_eq(game_logic.queued_effect_chain["effect"], null)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)


func test_threshold_strike_damage_stunned_defender_still_chooses():
	player1.life = 26
	position_players(player1, 3, player2, 4)
	var cross_id = give_player_specific_card(player1, "gg_normal_cross")
	var grasp_id = give_player_specific_card(player2, "gg_normal_grasp")
	assert_true(game_logic.do_strike(player1, cross_id, false, -1))
	assert_true(game_logic.do_strike(player2, grasp_id, false, -1))
	assert_eq(game_logic.decision_info.player, player2.my_id)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player2, 0))
	_assert_threshold_choice(player1, 25)
	assert_eq(player1.life, 23)
	assert_true(game_logic.active_strike.is_player_stunned(player1))
	assert_eq(player1.arena_location, 2)
	assert_true(game_logic.do_choice(player1, 0))
	assert_null(game_logic.active_strike)
	assert_eq(player1.arena_location, 2, "The stunned Cross did not execute its After retreat.")
	assert_true(player1.is_card_in_discards(cross_id))
	assert_eq(player1.bleach_zone.size(), 1)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)


func _give_guardian(target: Player, definition_id: String) -> int:
	var guardian_id = give_player_specific_card(target, definition_id)
	var guardian = game_logic.card_db.get_card(guardian_id)
	target.remove_card_from_hand(guardian_id, true, false)
	target.add_to_bleach(guardian)
	return guardian_id


func _assert_pre_set_guardian_choice(target: Player):
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, target.my_id)
	assert_eq(game_logic.decision_info.effect_type, "heiqiyihu_guardian_before_set")
	assert_not_null(game_logic.active_strike)
	assert_true(game_logic.active_strike.heiqiyihu_declared_before_set)
	assert_null(game_logic.active_strike.initiator_card)
	assert_null(game_logic.active_strike.defender_card)
	assert_null(game_logic.active_strike.initiator_ex_card)
	assert_null(game_logic.active_strike.defender_ex_card)
	assert_eq(game_logic.decision_info.choice.size(), target.bleach_zone.size() + 1)
	assert_eq(game_logic.decision_info.choice[-1]["_choice_text"], "不触发守护")
	for choice in game_logic.decision_info.choice:
		if choice["effect_type"] != StrikeEffects.Pass:
			assert_true(target.is_card_in_bleach(choice["guardian_card_id"]))
			assert_true(choice["_choice_text"].begins_with("触发守护「"))


func test_guardian_pre_set_drawn_card_can_be_selected_as_initiator():
	var guardian_id = _give_guardian(player1, "gg_normal_grasp")
	var new_attack = set_player_topdeck(player1, "gg_normal_cross")
	var hand_size = player1.hand.size()
	game_logic.get_latest_events()
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	_assert_pre_set_guardian_choice(player1)
	validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Strike_Started, player1)
	assert_false(player1.is_card_in_hand(new_attack))
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player1.hand.size(), hand_size + 1)
	assert_true(player1.is_card_in_hand(new_attack))
	assert_false(player1.is_card_in_bleach(guardian_id))
	assert_true(player1.is_card_in_discards(guardian_id))
	assert_false(player1.is_card_in_continuous_boosts(guardian_id))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)
	var declared_strike = game_logic.active_strike
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_Draw, player1, new_attack)
	validate_not_has_event(events, Enums.EventType.EventType_Strike_Started, player1)
	assert_true(game_logic.do_strike(player1, new_attack, false, -1))
	assert_eq(game_logic.active_strike, declared_strike)
	assert_eq(game_logic.active_strike.initiator_card.id, new_attack)
	assert_eq(game_logic.active_strike.heiqiyihu_guardian_records.size(), 1)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_Strike_Opponent_Response)


func test_guardian_pre_set_wild_swing_uses_top_after_guardian_draw():
	_give_guardian(player1, "gg_normal_grasp")
	var actual_wild = set_player_topdeck(player1, "gg_normal_focus")
	var drawn = set_player_topdeck(player1, "gg_normal_cross")
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	_assert_pre_set_guardian_choice(player1)
	assert_eq(player1.deck[0].id, drawn)
	assert_true(game_logic.do_choice(player1, 0))
	assert_true(player1.is_card_in_hand(drawn))
	assert_eq(player1.deck[0].id, actual_wild)
	assert_true(game_logic.do_strike(player1, -1, true, -1))
	assert_true(game_logic.active_strike.initiator_wild_strike)
	assert_eq(game_logic.active_strike.initiator_card.id, actual_wild)
	assert_ne(game_logic.active_strike.initiator_card.id, drawn)


func test_guardian_pre_set_defender_draws_before_either_attack_is_set():
	_give_guardian(player2, "gg_normal_grasp")
	var defender_attack = set_player_topdeck(player2, "gg_normal_cross")
	var initiator_attack = give_player_specific_card(player1, "gg_normal_sweep")
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	_assert_pre_set_guardian_choice(player2)
	assert_true(player1.is_card_in_hand(initiator_attack))
	assert_false(player2.is_card_in_hand(defender_attack))
	assert_true(game_logic.do_choice(player2, 0))
	assert_true(player2.is_card_in_hand(defender_attack))
	assert_true(game_logic.do_strike(player1, initiator_attack, false, -1))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_Strike_Opponent_Response)
	game_logic.get_latest_events()
	assert_true(game_logic.do_strike(player2, defender_attack, false, -1))
	validate_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Strike_Response, player2, defender_attack)
	assert_true(game_logic.heiqiyihu_guardian_setup.is_empty())


func test_guardian_pre_set_mirror_resolves_initiator_then_defender():
	_give_guardian(player1, "gg_normal_grasp")
	var untouched = _give_guardian(player1, "gg_normal_focus")
	_give_guardian(player2, "gg_normal_grasp")
	var first_hand = player1.hand.size()
	var second_hand = player2.hand.size()
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	_assert_pre_set_guardian_choice(player1)
	assert_true(game_logic.do_choice(player1, 0))
	_assert_pre_set_guardian_choice(player2)
	assert_eq(player1.hand.size(), first_hand + 1)
	assert_eq(player2.hand.size(), second_hand)
	assert_true(player1.is_card_in_bleach(untouched))
	assert_true(game_logic.do_choice(player2, 0))
	assert_eq(player2.hand.size(), second_hand + 1)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)
	assert_eq(game_logic.active_strike.heiqiyihu_guardian_records.size(), 2)
	assert_true(player1.is_card_in_bleach(untouched), "Each side only gets one guardian this strike.")


func test_guardian_pre_set_pass_does_not_move_guardian():
	var guardian_id = _give_guardian(player1, "gg_normal_grasp")
	var hand_size = player1.hand.size()
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	_assert_pre_set_guardian_choice(player1)
	assert_true(game_logic.do_choice(player1, game_logic.decision_info.choice.size() - 1))
	assert_true(player1.is_card_in_bleach(guardian_id))
	assert_false(player1.is_card_in_discards(guardian_id))
	assert_eq(player1.hand.size(), hand_size)
	assert_eq(game_logic.active_strike.heiqiyihu_guardian_records.size(), 0)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)


func test_guardian_pre_set_empty_and_exceeded_do_not_offer():
	var attack_id = give_player_specific_card(player1, "gg_normal_cross")
	assert_true(game_logic.do_strike(player1, attack_id, false, -1))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_Strike_Opponent_Response)
	assert_false(game_logic.active_strike.heiqiyihu_declared_before_set)
	_restart_for_opening(30, 30)
	assert_true(game_logic.do_mulligan(player1, []))
	assert_true(game_logic.do_mulligan(player2, []))
	var guardian_id = _give_guardian(player1, "gg_normal_grasp")
	player1.exceeded = true
	attack_id = give_player_specific_card(player1, "gg_normal_cross")
	assert_true(game_logic.do_strike(player1, attack_id, false, -1))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_Strike_Opponent_Response)
	assert_true(player1.is_card_in_bleach(guardian_id))
	assert_false(game_logic.active_strike.heiqiyihu_declared_before_set)


func test_guardian_pre_set_legacy_attack_ids_are_not_cached():
	_give_guardian(player1, "gg_normal_grasp")
	var discarded_selection = give_player_specific_card(player1, "gg_normal_cross")
	var discarded_ex_selection = give_player_specific_card(player1, "gg_normal_cross")
	var actual_selection = give_player_specific_card(player1, "gg_normal_sweep")
	assert_true(game_logic.do_strike(player1, discarded_selection, false, discarded_ex_selection))
	_assert_pre_set_guardian_choice(player1)
	assert_true(player1.is_card_in_hand(discarded_selection))
	assert_true(player1.is_card_in_hand(discarded_ex_selection))
	assert_true(game_logic.do_choice(player1, 0))
	assert_true(game_logic.do_strike(player1, actual_selection, false, -1))
	assert_eq(game_logic.active_strike.initiator_card.id, actual_selection)
	assert_null(game_logic.active_strike.initiator_ex_card)
	assert_true(player1.is_card_in_hand(discarded_selection))
	assert_true(player1.is_card_in_hand(discarded_ex_selection))


func test_guardian_pre_set_invalid_submissions_do_not_consume():
	var guardian_id = _give_guardian(player1, "gg_normal_grasp")
	var attack_id = give_player_specific_card(player1, "gg_normal_cross")
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	_assert_pre_set_guardian_choice(player1)
	assert_false(game_logic.do_choice(player2, 0))
	assert_false(game_logic.do_choice(player1, -1))
	assert_false(game_logic.do_choice(player1, game_logic.decision_info.choice.size()))
	assert_false(game_logic.do_strike(player1, attack_id, false, -1))
	assert_true(player1.is_card_in_bleach(guardian_id))
	assert_true(player1.is_card_in_hand(attack_id))
	var guardian = player1.remove_card_from_bleach(guardian_id)
	player1.add_to_discards(guardian)
	assert_false(game_logic.do_choice(player1, 0))
	assert_eq(game_logic.active_strike.heiqiyihu_guardian_records.size(), 0)
	assert_true(game_logic.do_choice(player1, game_logic.decision_info.choice.size() - 1))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)


func test_guardian_pre_set_immediate_choice_resumes_once():
	var guardian_id = _give_guardian(player1, "gg_normal_cross")
	position_players(player1, 3, player2, 6)
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	_assert_pre_set_guardian_choice(player1)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.decision_info.choice_card_id, guardian_id)
	assert_null(game_logic.active_strike.initiator_card)
	assert_null(game_logic.active_strike.defender_card)
	assert_true(player1.is_card_in_discards(guardian_id))
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player2.arena_location, 8, "Push 2 happened once, not twice.")
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)
	assert_eq(game_logic.active_strike.heiqiyihu_guardian_records.size(), 1)
	assert_true(game_logic.heiqiyihu_guardian_setup.is_empty())
	assert_eq(game_logic.queued_effect_chain["effect"], null)


func test_guardian_pre_set_forced_strike_requests_guardians_before_attack_event():
	_give_guardian(player1, "gg_normal_grasp")
	game_logic.get_latest_events()
	game_logic.handle_strike_effect(-1, {"effect_type": StrikeEffects.Strike}, player1)
	_assert_pre_set_guardian_choice(player1)
	validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_ForceStartStrike, player1)
	assert_true(game_logic.do_choice(player1, 0))
	var events = game_logic.get_latest_events()
	assert_eq(validate_has_event(events, Enums.EventType.EventType_ForceStartStrike, player1).size(), 1)
	validate_not_has_event(events, Enums.EventType.EventType_Strike_Started, player1)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)


func test_guardian_pre_set_forced_wild_swing_waits_for_guardian_draw():
	_give_guardian(player1, "gg_normal_grasp")
	var actual_wild = set_player_topdeck(player1, "gg_normal_cross")
	var drawn = set_player_topdeck(player1, "gg_normal_sweep")
	game_logic.handle_strike_effect(-1, {"effect_type": StrikeEffects.StrikeWild}, player1)
	_assert_pre_set_guardian_choice(player1)
	assert_eq(player1.deck[0].id, drawn)
	assert_true(game_logic.do_choice(player1, 0))
	assert_true(player1.is_card_in_hand(drawn))
	assert_eq(game_logic.active_strike.initiator_card.id, actual_wild)
	assert_true(game_logic.active_strike.initiator_wild_strike)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_Strike_Opponent_Response)


func test_guardian_pre_set_opponent_sets_first_after_both_guardians():
	_give_guardian(player1, "gg_normal_grasp")
	var initiator_card = give_player_specific_card(player1, "gg_normal_focus")
	var defender_card = give_player_specific_card(player2, "gg_normal_cross")
	game_logic.handle_strike_effect(-1, {"effect_type": StrikeEffects.StrikeOpponentSetsFirst}, player1)
	_assert_pre_set_guardian_choice(player1)
	var declared_strike = game_logic.active_strike
	assert_true(game_logic.active_strike.opponent_sets_first)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_Strike_Opponent_Response)
	assert_null(game_logic.active_strike.initiator_card)
	assert_null(game_logic.active_strike.defender_card)
	assert_true(game_logic.do_strike(player2, defender_card, false, -1, true))
	assert_eq(game_logic.active_strike, declared_strike)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)
	assert_null(game_logic.active_strike.initiator_card)
	assert_eq(game_logic.active_strike.defender_card.id, defender_card)
	assert_eq(game_logic.active_strike.heiqiyihu_guardian_records.size(), 1)
	game_logic.get_latest_events()
	assert_true(game_logic.do_strike(player1, initiator_card, false, -1, true))
	validate_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Strike_Started, player1, initiator_card)
	assert_true(game_logic.heiqiyihu_guardian_setup.is_empty())


func test_guardian_pre_set_ex_requirement_survives_guardian_choice():
	_give_guardian(player1, "gg_normal_grasp")
	var attack_id = give_player_specific_card(player1, "gg_normal_cross")
	var ex_id = give_player_specific_card(player1, "gg_normal_cross")
	game_logic.handle_strike_effect(-1, {"effect_type": StrikeEffects.StrikeWithEx}, player1)
	_assert_pre_set_guardian_choice(player1)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)
	assert_eq(game_logic.decision_info.limitation, "EX")
	assert_false(game_logic.do_strike(player1, attack_id, false, -1))
	assert_true(player1.is_card_in_hand(attack_id))
	assert_true(game_logic.do_strike(player1, attack_id, false, ex_id))
	assert_eq(game_logic.active_strike.initiator_card.id, attack_id)
	assert_eq(game_logic.active_strike.initiator_ex_card.id, ex_id)
	assert_false(player1.is_card_in_hand(ex_id))


func test_guardian_pre_set_rule_required_face_attack_stays_outside_hand_until_after_guardian():
	game_logic.teardown()
	game_logic.free()
	default_game_setup("happychaos")
	game_logic.active_turn_player = player2.my_id
	game_logic.next_turn_player = player1.my_id
	_give_guardian(player1, "gg_normal_grasp")
	var face_id = -1
	for card in player2.set_aside_cards:
		if card.definition["id"] == "happychaos_deusexmachina":
			face_id = card.id
	assert_ne(face_id, -1)
	var payment = give_gauge(player2, player2.get_exceed_cost())
	assert_true(game_logic.do_exceed(player2, payment))
	_assert_pre_set_guardian_choice(player1)
	assert_eq(game_logic.active_strike.initiator, player2)
	assert_true(player2.is_card_in_set_aside(face_id))
	assert_false(player2.is_card_in_hand(face_id))
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(game_logic.active_strike.initiator_card.id, face_id)
	assert_false(player2.is_card_in_set_aside(face_id))
	assert_false(player2.is_card_in_hand(face_id))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_Strike_Opponent_Response)


func test_guardian_pre_set_required_source_zone_survives_guardian_choice():
	for source in ["gauge", "sealed"]:
		_restart_for_opening(30, 30)
		assert_true(game_logic.do_mulligan(player1, []))
		assert_true(game_logic.do_mulligan(player2, []))
		_give_guardian(player1, "gg_normal_grasp")
		var attack_id = give_player_specific_card(player1, "gg_normal_cross")
		var attack = game_logic.card_db.get_card(attack_id)
		player1.remove_card_from_hand(attack_id, true, false)
		if source == "gauge":
			player1.add_to_gauge(attack)
		else:
			player1.add_to_sealed(attack)
		var effect_type = StrikeEffects.StrikeFromGauge if source == "gauge" else StrikeEffects.StrikeFromSealed
		game_logic.handle_strike_effect(-1, {"effect_type": effect_type}, player1)
		_assert_pre_set_guardian_choice(player1)
		assert_false(player1.is_card_in_hand(attack_id))
		assert_true(player1.is_card_in_gauge(attack_id) if source == "gauge" else player1.is_card_in_sealed(attack_id))
		assert_true(game_logic.do_choice(player1, 0))
		assert_eq(game_logic.decision_info.source, source)
		assert_true(game_logic.do_strike(player1, attack_id, false, -1))
		assert_eq(game_logic.active_strike.initiator_card.id, attack_id)
		assert_false(player1.is_card_in_gauge(attack_id))
		assert_false(player1.is_card_in_sealed(attack_id))


func test_guardian_pre_set_empty_required_gauge_falls_back_to_wild_after_guardian():
	_give_guardian(player1, "gg_normal_grasp")
	var wild_id = set_player_topdeck(player1, "gg_normal_cross")
	var drawn_id = set_player_topdeck(player1, "gg_normal_focus")
	assert_eq(player1.gauge.size(), 0)
	game_logic.handle_strike_effect(-1, {"effect_type": StrikeEffects.StrikeFromGauge}, player1)
	_assert_pre_set_guardian_choice(player1)
	assert_true(game_logic.do_choice(player1, 0))
	assert_true(player1.is_card_in_hand(drawn_id))
	assert_eq(game_logic.active_strike.initiator_card.id, wild_id)
	assert_true(game_logic.active_strike.initiator_wild_strike)
