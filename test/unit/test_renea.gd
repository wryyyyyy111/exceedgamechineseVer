extends ExceedGutTest

func who_am_i():
	return "renea"

func before_each():
	default_game_setup("ryu")
	gut.p("ran setup", 2)

func test_mimetism_transform_description():
	var definition = CardDataManager.get_card("renea_paranormal_investigation")
	var effect = definition["boost"]["effects"][0]

	assert_eq(GameStrings.get_effect_text(effect, false, true), "后置：你可以花费2能量来维持一个持续性加成。")

func test_do_boost_with_facedown_override_adds_hidden_continuous_boost():
	var boost_id = give_player_specific_card(player1, "renea_called_shot")

	assert_true(game_logic.do_boost(player1, boost_id, [], false, 0, [], true))
	assert_true(player1.is_card_in_continuous_boosts(boost_id))
	assert_true(game_logic.get_card_database().get_card(boost_id).definition["boost"].get("facedown", false))

	var events = game_logic.get_latest_events()
	var added_events = validate_has_event(events, Enums.EventType.EventType_Boost_Continuous_Added, player1, boost_id)
	assert_true(added_events[-1]["extra_info"])

func test_do_boost_with_faceup_override_keeps_boost_visible():
	var boost_id = give_player_specific_card(player1, "renea_called_shot")

	assert_true(game_logic.do_boost(player1, boost_id, [], false, 0, [], false))
	assert_true(player1.is_card_in_continuous_boosts(boost_id))
	assert_false(game_logic.get_card_database().get_card(boost_id).definition["boost"].get("facedown", false))

	var events = game_logic.get_latest_events()
	var added_events = validate_has_event(events, Enums.EventType.EventType_Boost_Continuous_Added, player1, boost_id)
	assert_eq(added_events[-1]["extra_info"], null)

func test_facedown_boost_order_ignores_grasp_without_now_effect():
	var grasp_id = give_player_specific_card(player1, "standard_normal_grasp")
	var flare_id = give_player_specific_card(player1, "renea_flare")

	assert_false(game_logic._renea_boost_has_now_effect(game_logic.get_card_database().get_card(grasp_id)))
	assert_true(game_logic._renea_boost_has_now_effect(game_logic.get_card_database().get_card(flare_id)))

func test_renea_ua_reveals_all_facedown_boosts_before_resolving_now_effects():
	var sweep_id = give_player_specific_card(player1, "standard_normal_sweep")
	var grasp_id = give_player_specific_card(player1, "standard_normal_grasp")
	var anticipation_id = give_player_specific_card(player1, "renea_anticipation")
	for card_id in [sweep_id, grasp_id, anticipation_id]:
		var card = game_logic.get_card_database().get_card(card_id)
		player1.remove_card_from_hand(card_id, true, false)
		card.definition["boost"]["facedown"] = true
		player1.add_to_continuous_boosts(card)
	game_logic.get_latest_events()

	game_logic._renea_begin_pre_strike_reveal(player1)

	for card_id in [sweep_id, grasp_id, anticipation_id]:
		assert_false(game_logic.get_card_database().get_card(card_id).definition["boost"].get("facedown", false))
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_RevealCard, player1, sweep_id)
	validate_has_event(events, Enums.EventType.EventType_RevealCard, player1, grasp_id)
	validate_has_event(events, Enums.EventType.EventType_RevealCard, player1, anticipation_id)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.decision_info.choice.size(), 2)

func test_renea_offensive_ua_returns_to_strike_selection_silently():
	var grasp_id = give_player_specific_card(player1, "standard_normal_grasp")
	var card = game_logic.get_card_database().get_card(grasp_id)
	player1.remove_card_from_hand(grasp_id, true, false)
	card.definition["boost"]["facedown"] = true
	player1.add_to_continuous_boosts(card)
	game_logic.get_latest_events()

	game_logic._renea_begin_pre_strike_reveal(player1)
	var events = game_logic.get_latest_events()

	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	var force_start_events = validate_has_event(events, Enums.EventType.EventType_ForceStartStrike, player1)
	assert_eq(force_start_events[-1].extra_info3, "silent_pre_strike")

func test_renea_offensive_ua_with_now_effect_returns_to_strike_selection_silently():
	var anticipation_id = give_player_specific_card(player1, "renea_anticipation")
	var card = game_logic.get_card_database().get_card(anticipation_id)
	player1.remove_card_from_hand(anticipation_id, true, false)
	card.definition["boost"]["facedown"] = true
	player1.add_to_continuous_boosts(card)
	game_logic.get_latest_events()

	game_logic._renea_begin_pre_strike_reveal(player1)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player1, 0))
	var events = game_logic.get_latest_events()

	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	var force_start_events = validate_has_event(events, Enums.EventType.EventType_ForceStartStrike, player1)
	assert_eq(force_start_events[-1].extra_info3, "silent_pre_strike")

func test_renea_defensive_ua_waits_for_sagat_set_strike_effects():
	game_logic.teardown()
	game_logic.free()
	default_game_setup("sagat")
	var facedown_boost_id = give_player_specific_card(player1, "renea_anticipation")
	assert_true(game_logic.do_boost(player1, facedown_boost_id, [], false, 0, [], true))
	game_logic.active_turn_player = player2.my_id
	game_logic.game_state = Enums.GameState.GameState_PickAction

	var sagat_attack_id = give_player_specific_card(player2, "sagat_lowstepkick")
	assert_true(game_logic.do_strike(player2, sagat_attack_id, false, -1))
	assert_eq(game_logic.decision_info.player, player2.my_id)
	assert_eq(game_logic.decision_info.choice[0].get("effect_type", ""), "reveal_strike")
	assert_true(game_logic.do_choice(player2, 0))

	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.active_strike.initiator_card.definition["id"] == "sagat_lowstepkick")
	assert_eq(game_logic.decision_info.choice[0].get("effect_type", ""), "advance")
	assert_eq(player1.renea_pre_strike_effects.size(), 1)
	assert_eq(player1.renea_pre_strike_index, 1)
	assert_false(player1.renea_pre_strike_needs_fss)
	assert_true(player1.renea_pre_strike_response)

	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_Strike_Opponent_Response)
	assert_eq(game_logic.decision_info.player, player1.my_id)

func test_neutralizer_hit_discards_exceeded_opponent_gauge_not_renea_hand():
	position_players(player1, 3, player2, 4)
	var p1_cost = give_gauge(player1, 2)
	var p2_gauge = give_gauge(player2, 3)
	var p1_hand_id = give_player_specific_card(player1, "standard_normal_grasp")
	player2.exceed()

	execute_strike(player1, player2, "renea_neutralizer", "standard_normal_focus",
		false, false, [p1_cost, p2_gauge[0], p2_gauge[1]], [[]])

	assert_true(player1.is_card_in_hand(p1_hand_id))
	assert_false(player2.is_card_in_gauge(p2_gauge[0]))
	assert_false(player2.is_card_in_gauge(p2_gauge[1]))
	assert_true(player2.is_card_in_discards(p2_gauge[0]))
	assert_true(player2.is_card_in_discards(p2_gauge[1]))
	assert_true(player2.is_card_in_gauge(p2_gauge[2]))

func test_neutralizer_hit_skips_gauge_discard_when_opponent_not_exceeded():
	position_players(player1, 3, player2, 4)
	var p1_cost = give_gauge(player1, 2)
	var p2_gauge = give_gauge(player2, 2)
	var p1_hand_id = give_player_specific_card(player1, "standard_normal_grasp")

	execute_strike(player1, player2, "renea_neutralizer", "standard_normal_focus",
		false, false, [p1_cost], [[]])

	assert_true(player1.is_card_in_hand(p1_hand_id))
	assert_true(player2.is_card_in_gauge(p2_gauge[0]))
	assert_true(player2.is_card_in_gauge(p2_gauge[1]))
func test_faceup_flare_boost_triggers_pakout_immediately():
	# Regression: Flare's Pakout boost has a now effect (return to hand + draw
	# 1). Face-up placement must trigger it immediately, even though the boost
	# isn't in continuous_boosts yet at now-resolution time.
	var flare_id = give_player_specific_card(player1, "renea_flare")
	var hand_count_before = player1.hand.size()
	assert_true(game_logic.do_boost(player1, flare_id, [], false, 0, [], false))
	assert_true(player1.is_card_in_hand(flare_id),
			"Flare should return to hand via Pakout")
	assert_false(player1.is_card_in_continuous_boosts(flare_id),
			"Flare must not remain as a continuous boost")
	# Deck shrinks by one from Pakout draw; hand grows (flare back + draw).
	# Hand-size top-ups from check_hand_size can add cards too, so only assert
	# the guaranteed net gain.
	assert_true(player1.hand.size() >= hand_count_before + 1,
			"Pakout draws one card (net +1 hand)")

func test_briefcase_hit_takes_bottom_most_boost_card():
	# Exceed passive hit takes the BOTTOM-most boost card from the opponent's
	# discard pile (bottom = earliest discarded = discards[0]), not the
	# top-most one.
	var boost_bottom_id = give_player_specific_card(player2, "renea_called_shot")
	var no_boost_id = give_player_specific_card(player2, "standard_normal_grasp")
	var boost_top_id = give_player_specific_card(player2, "renea_flare")
	player2.discard([boost_bottom_id])
	player2.discard([no_boost_id])
	player2.discard([boost_top_id])
	assert_eq(player2.discards[0].id, boost_bottom_id)
	assert_eq(player2.discards[player2.discards.size() - 1].id, boost_top_id)
	game_logic.do_effect_if_condition_met(player1, -1, {"effect_type": "renea_briefcase_hit"}, null)
	var briefcase_ids = player1.set_aside_cards.map(func(c): return c.id)
	assert_true(boost_bottom_id in briefcase_ids,
			"Bottom-most boost card should enter the briefcase")
	assert_false(boost_top_id in briefcase_ids,
			"Top-most boost card must NOT be taken")

func test_on_exceed_briefcase_takes_top_three_boost_cards():
	# On-exceed briefcase fill takes the TOP 3 boost cards from the opponent's
	# discard (top = end of array = most recently discarded).
	# Discard pile bottom->top: A(boost), B(boost), C(boost), D(boost).
	# With 4 boost cards, top-3 fill must leave the bottom-most A behind.
	var a_id = give_player_specific_card(player2, "renea_called_shot")
	var b_id = give_player_specific_card(player2, "renea_neutralizer")
	var c_id = give_player_specific_card(player2, "renea_anticipation")
	var d_id = give_player_specific_card(player2, "renea_flare")
	player2.discard([a_id, b_id, c_id, d_id])
	assert_eq(player2.discards[0].id, a_id)
	assert_eq(player2.discards[player2.discards.size() - 1].id, d_id)
	game_logic.do_effect_if_condition_met(player1, -1, {"effect_type": "renea_on_exceed"}, null)
	var briefcase_ids = player1.set_aside_cards.map(func(c): return c.id)
	assert_true(d_id in briefcase_ids, "Top boost card D should enter the briefcase")
	assert_true(c_id in briefcase_ids, "Boost card C should enter the briefcase")
	assert_true(b_id in briefcase_ids, "Boost card B should enter the briefcase")
	assert_false(a_id in briefcase_ids, "Bottom-most boost card A must NOT be taken (top 3 only)")

func test_exceeded_briefcase_boost_then_prepare_advances_turn():
	game_logic.teardown()
	game_logic.free()
	default_game_setup("taisei")
	player1.exceeded = true
	var boost_id = give_player_specific_card(player2, "taisei_bloodthirst")
	var boost_card = game_logic.get_card_database().get_card(boost_id)
	player2.remove_card_from_hand(boost_id, true, false)
	player1.add_to_set_aside(boost_card)

	assert_true(game_logic.do_boost(player1, boost_id))
	assert_eq(game_logic.active_turn_player, player1.my_id)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	assert_eq(player1.bonus_actions, 0)

	assert_true(game_logic.do_prepare(player1))
	assert_eq(game_logic.active_turn_player, player2.my_id)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)

func test_exceeded_briefcase_false_life_prepare_waits_for_discard_then_advances():
	game_logic.teardown()
	game_logic.free()
	default_game_setup("taisei")
	player1.exceeded = true
	var boost_id = give_player_specific_card(player2, "taisei_nightmaretares")
	var boost_card = game_logic.get_card_database().get_card(boost_id)
	player2.remove_card_from_hand(boost_id, true, false)
	player1.add_to_set_aside(boost_card)

	assert_true(game_logic.do_boost(player1, boost_id))
	assert_eq(player1.hand.size(), 7)
	assert_eq(player1.bonus_actions, 0)
	assert_true(game_logic.do_prepare(player1))

	assert_eq(game_logic.active_turn_player, player1.my_id)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_DiscardDownToMax)
	assert_eq(player1.hand.size(), 9)
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_HandSizeExceeded, player1, 2)

	assert_true(game_logic.do_discard_to_max(player1, [player1.hand[0].id, player1.hand[1].id]))
	assert_eq(game_logic.active_turn_player, player2.my_id)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
