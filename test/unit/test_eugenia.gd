extends "res://test/exceed_test.gd"

func who_am_i():
	return "eugenia"

func test_queen_of_hearts_powers_up_before_opponent_draws():
	position_players(player1, 4, player2, 5)
	var gauge_ids = give_gauge(player1, 3)
	player2.hand = []
	give_player_specific_card(player2, "standard_normal_assault")
	give_player_specific_card(player2, "standard_normal_cross")
	give_player_specific_card(player2, "standard_normal_dive")

	execute_strike(player1, player2, "eugenia_queen_of_hearts", "standard_normal_grasp", false, false, [gauge_ids, 0], [])

	validate_life(player1, 30, player2, 26)
	assert_eq(player2.hand.size(), 1)

func test_wanderlust_opponent_draws_selected_card_without_shuffling_remaining_deck():
	var wanderlust_id = give_player_specific_card(player1, "eugenia_queen_of_hearts")
	var payment_id = give_player_specific_card(player1, "standard_normal_assault")
	var transform_id = -1
	for card in player1.deck:
		if card.definition['boost']['boost_type'] == "transform":
			transform_id = card.id
			break
	assert_ne(transform_id, -1)

	assert_true(game_logic.do_boost(player1, wanderlust_id, [payment_id]))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostNow)
	assert_true(game_logic.do_boost(player1, transform_id))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseFromTopDeck)
	assert_eq(game_logic.decision_info.player, player2.my_id)

	var chosen_card_id = player2.deck[5].id
	var expected_remaining_ids = player2.deck.map(func(card): return card.id)
	expected_remaining_ids.erase(chosen_card_id)
	game_logic.get_latest_events()

	assert_true(game_logic.do_choose_from_topdeck(player2, chosen_card_id, "add_to_hand"))
	assert_true(chosen_card_id in player2.get_card_ids_in_hand())
	assert_eq(player2.deck.map(func(card): return card.id), expected_remaining_ids)
	var draw_events = game_logic.get_latest_events().filter(func(event):
		return event['event_type'] == Enums.EventType.EventType_Draw \
			and event['event_player'] == player2.my_id
	)
	assert_eq(draw_events.size(), 1)
	assert_eq(draw_events[0]['event_player'], player2.my_id)
	assert_eq(draw_events[0]['number'], chosen_card_id)

func test_wanderlust_opponent_passes_then_shuffles_without_drawing():
	var wanderlust_id = give_player_specific_card(player1, "eugenia_queen_of_hearts")
	var payment_id = give_player_specific_card(player1, "standard_normal_assault")
	var transform_id = -1
	for card in player1.deck:
		if card.definition['boost']['boost_type'] == "transform":
			transform_id = card.id
			break
	assert_ne(transform_id, -1)

	assert_true(game_logic.do_boost(player1, wanderlust_id, [payment_id]))
	assert_true(game_logic.do_boost(player1, transform_id))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseFromTopDeck)
	var original_deck_ids = player2.deck.map(func(card): return card.id)
	original_deck_ids.sort()
	var original_hand_size = player2.hand.size()
	player2.public_topdeck_id = player2.deck[0].id
	game_logic.get_latest_events()

	assert_true(game_logic.do_choose_from_topdeck(player2, -1, StrikeEffects.Pass))
	assert_eq(player2.hand.size(), original_hand_size)
	var shuffled_deck_ids = player2.deck.map(func(card): return card.id)
	shuffled_deck_ids.sort()
	assert_eq(shuffled_deck_ids, original_deck_ids)
	assert_eq(player2.public_topdeck_id, -1)
	var opponent_draw_events = game_logic.get_latest_events().filter(func(event):
		return event['event_type'] == Enums.EventType.EventType_Draw \
			and event['event_player'] == player2.my_id
	)
	assert_eq(opponent_draw_events.size(), 0)

func test_cats_cradle_powers_down_after_opponent_draws_and_discards():
	position_players(player1, 4, player2, 5)
	var gauge_ids = give_gauge(player1, 3)
	player2.hand = []
	give_player_specific_card(player2, "standard_normal_assault")
	give_player_specific_card(player2, "standard_normal_cross")
	give_player_specific_card(player2, "standard_normal_dive")

	execute_strike(player1, player2, "eugenia_cats_cradle", "standard_normal_spike", false, false, [gauge_ids, 0], [])

	validate_life(player1, 30, player2, 23)
	assert_eq(player2.hand.size(), 2)

func test_werelight_hit_discard_choice_triggers_matching_speed_passive():
	position_players(player1, 3, player2, 5)
	player1.hand = []
	player2.hand = []
	give_player_specific_card(player1, "standard_normal_assault")
	give_player_specific_card(player2, "standard_normal_assault")
	give_player_specific_card(player2, "standard_normal_cross")

	execute_strike(player1, player2, "eugenia_light_of_bygone", "standard_normal_block",
		false, false,
		[1],      # reveal matching speed Assault for Eugenia passive
		[0, []])  # Choose random discard 2, then Block force for armor

	validate_life(player1, 30, player2, 26)
	assert_eq(player2.hand.size(), 0)

func test_werelight_random_discard_two_cards_triggers_ua():
	position_players(player1, 3, player2, 5)
	player1.hand = []
	player2.hand = []
	give_player_specific_card(player1, "standard_normal_assault")
	give_player_specific_card(player2, "standard_normal_assault")
	give_player_specific_card(player2, "standard_normal_cross")

	execute_strike(player1, player2, "eugenia_light_of_bygone", "standard_normal_grasp",
		false, false,
		[1],
		[0])

	validate_life(player1, 30, player2, 24)
	assert_eq(player2.hand.size(), 0)

func test_werelight_random_discard_one_remaining_card_triggers_ua():
	position_players(player1, 3, player2, 5)
	player1.hand = []
	player2.hand = []
	give_player_specific_card(player1, "standard_normal_cross")
	give_player_specific_card(player2, "standard_normal_cross")

	execute_strike(player1, player2, "eugenia_light_of_bygone", "standard_normal_grasp",
		false, false,
		[],
		[], true)

	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player2.my_id)
	game_logic._last_effect_source_player_id = player2.my_id
	assert_true(game_logic.do_choice(player2, 0))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(player2.hand.size(), 0)

func test_werelight_reveal_choose_first_card_triggers_ua():
	position_players(player1, 3, player2, 5)
	player1.hand = []
	player2.hand = []
	give_player_specific_card(player1, "standard_normal_assault")
	var assault_id = give_player_specific_card(player2, "standard_normal_assault")
	give_player_specific_card(player2, "standard_normal_cross")

	execute_strike(player1, player2, "eugenia_light_of_bygone", "standard_normal_grasp",
		false, false,
		[[assault_id], 1],
		[1])

	validate_life(player1, 30, player2, 24)
	assert_eq(player2.hand.size(), 1)

func test_werelight_reveal_choose_nonfirst_card_triggers_ua():
	position_players(player1, 3, player2, 5)
	player1.hand = []
	player2.hand = []
	give_player_specific_card(player1, "standard_normal_cross")
	give_player_specific_card(player2, "standard_normal_assault")
	var cross_id = give_player_specific_card(player2, "standard_normal_cross")

	execute_strike(player1, player2, "eugenia_light_of_bygone", "standard_normal_grasp",
		false, false,
		[],
		[], true)

	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player2.my_id)
	assert_true(game_logic.do_choice(player2, 1))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseToDiscard)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	game_logic._last_effect_source_player_id = player2.my_id
	assert_true(game_logic.do_choose_to_discard(player1, [cross_id]))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(player2.hand.size(), 1)

func test_block_force_for_armor_discard_does_not_trigger_matching_speed_passive():
	position_players(player1, 3, player2, 5)
	player1.hand = []
	player2.hand = []
	var strike_assault = give_player_specific_card(player1, "standard_normal_assault")
	give_player_specific_card(player1, "standard_normal_assault")
	var force_assault = give_player_specific_card(player2, "standard_normal_assault")
	var block = give_player_specific_card(player2, "standard_normal_block")

	execute_strike(player1, player2, strike_assault, block,
		false, false,
		[],
		[[force_assault]])

	validate_life(player1, 30, player2, 30)
	assert_eq(player2.hand.size(), 0)

func test_were_all_mad_here_opponent_discard_triggers_matching_speed_passive():
	player1.hand = []
	player2.hand = []
	var boost_id = give_player_specific_card(player1, "eugenia_wormwood_arrow")
	give_player_specific_card(player1, "standard_normal_assault")
	give_player_specific_card(player1, "standard_normal_assault")
	give_player_specific_card(player2, "standard_normal_assault")

	assert_true(game_logic.do_boost(player1, boost_id))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_choice(player1, 0)) # self draw 0, then random discard 1

	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player2.my_id)
	assert_true(game_logic.do_choice(player2, 0)) # opponent draw 0, then random discard 1

	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_choice(player1, 1)) # reveal matching speed Assault

	validate_life(player1, 30, player2, 28)
	assert_eq(player2.hand.size(), 0)

func test_matching_speed_pass_does_not_consume_passive():
	player1.hand = []
	player2.hand = []
	give_player_specific_card(player1, "standard_normal_assault")
	var first_discard = give_player_specific_card(player2, "standard_normal_assault")
	var second_discard = give_player_specific_card(player2, "standard_normal_assault")

	game_logic._last_effect_source_player_id = player1.my_id
	player2.discard([first_discard])
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	var pass_effect = game_logic.decision_info.choice[0].duplicate()
	game_logic.game_state = Enums.GameState.GameState_Boost_Processing
	game_logic.decision_info.clear()
	game_logic.do_effect_if_condition_met(player1, -1, pass_effect, null)
	assert_false(player1.eugenia_normal_passive_used_this_turn)

	game_logic._last_effect_source_player_id = player1.my_id
	player2.discard([second_discard])
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	var reveal_effect = game_logic.decision_info.choice[1].duplicate()
	game_logic.game_state = Enums.GameState.GameState_Boost_Processing
	game_logic.decision_info.clear()
	game_logic.do_effect_if_condition_met(player1, -1, reveal_effect, null)
	assert_true(player1.eugenia_normal_passive_used_this_turn)
	validate_life(player1, 30, player2, 28)

func test_exceeded_passive_still_triggers_when_discard_happens_mid_decision():
	player1.exceeded = true
	player1.set_aside_cards = []
	player2.hand = []
	var discarded_id = give_player_specific_card(player2, "standard_normal_assault")

	game_logic.game_state = Enums.GameState.GameState_PlayerDecision
	game_logic._last_effect_source_player_id = player1.my_id
	player2.discard([discarded_id])

	assert_true(player1.is_card_in_set_aside(discarded_id))
	assert_false(player2.is_card_in_discards(discarded_id))

func test_color_spray_stun_immunity_when_opponent_has_two_or_fewer_cards():
	position_players(player1, 4, player2, 5)
	player2.hand = []
	give_player_specific_card(player2, "standard_normal_assault")
	give_player_specific_card(player2, "standard_normal_cross")

	execute_strike(player1, player2, "eugenia_colorful_mist", "standard_normal_sweep",
		false, false,
		[1], [0])

	validate_life(player1, 24, player2, 24)
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_Strike_Stun_Immunity, player1)
	validate_not_has_event(events, Enums.EventType.EventType_Strike_Stun, player1)

func test_color_spray_stun_immunity_uses_stun_check_timing_after_opponent_discard_to_two():
	game_logic.teardown()
	game_logic.free()
	default_game_setup("ryu")
	position_players(player1, 4, player2, 5)
	player2.hand = []
	give_player_specific_card(player2, "standard_normal_assault")
	give_player_specific_card(player2, "standard_normal_cross")
	give_player_specific_card(player2, "standard_normal_dive")
	give_player_specific_card(player2, "standard_normal_grasp")

	execute_strike(player1, player2, "eugenia_colorful_mist", "standard_normal_sweep",
		false, false,
		[0, 1], [])

	assert_lte(player2.hand.size(), 2)
	validate_life(player1, 24, player2, 24)
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_Strike_Stun_Immunity, player1)
	validate_not_has_event(events, Enums.EventType.EventType_Strike_Stun, player1)

func test_exceeded_sweep_hit_triggers_wonderland_choice():
	position_players(player1, 3, player2, 5)
	player1.exceeded = true
	player2.hand = []
	var discarded_assault = give_player_specific_card(player2, "standard_normal_assault")

	execute_strike(player1, player2, "standard_normal_sweep", "standard_normal_grasp",
		false, false,
		[], [], true)

	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_choice(player1, 1))
	assert_true(player1.is_card_in_set_aside(discarded_assault))

func test_exceeded_wonderland_sweep_hit_triggers_wonderland_choice():
	position_players(player1, 3, player2, 5)
	player1.exceeded = true
	player2.hand = []
	var sweep_id = give_player_specific_card(player1, "standard_normal_sweep")
	var sweep_card = game_logic.card_db.get_card(sweep_id)
	player1.remove_card_from_hand(sweep_id, false, false)
	player1.add_to_set_aside(sweep_card)
	var discarded_assault = give_player_specific_card(player2, "standard_normal_assault")

	execute_strike(player1, player2, sweep_id, "standard_normal_grasp",
		false, false,
		[], [], true)

	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_choice(player1, 1))
	assert_true(player1.is_card_in_set_aside(discarded_assault))

func test_exceeded_response_sweep_hit_triggers_wonderland_choice():
	position_players(player1, 3, player2, 5)
	player1.exceeded = true
	player2.hand = []
	var discarded_assault = give_player_specific_card(player2, "standard_normal_assault")
	advance_turn(player1)

	execute_strike(player2, player1, "standard_normal_block", "standard_normal_sweep",
		false, false,
		[], [], true)

	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_choice(player1, 1))
	assert_true(player1.is_card_in_set_aside(discarded_assault))

func test_off_with_her_head_boost_pushes_choosing_opponent():
	position_players(player1, 6, player2, 5)
	var boost_id = give_player_specific_card(player1, "eugenia_light_of_bygone")

	assert_true(game_logic.do_boost(player1, boost_id))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player2.my_id)
	assert_true(game_logic.do_choice(player2, 1))

	validate_positions(player1, 6, player2, 2)

func test_wonderland_direct_strike_leaves_set_aside_on_hit():
	position_players(player1, 3, player2, 5)
	player1.exceeded = true
	var wonderland_attack_id = give_player_specific_card(player1, "standard_normal_assault")
	var wonderland_attack = game_logic.card_db.get_card(wonderland_attack_id)
	player1.remove_card_from_hand(wonderland_attack_id, false, false)
	player1.add_to_set_aside(wonderland_attack)

	execute_strike(player1, player2, wonderland_attack_id, "standard_normal_grasp")

	assert_false(player1.is_card_in_set_aside(wonderland_attack_id))
	assert_true(player1.is_card_in_gauge(wonderland_attack_id))
	assert_false(player1.is_card_in_discards(wonderland_attack_id))

func test_wonderland_direct_response_leaves_set_aside_on_miss():
	position_players(player1, 3, player2, 5)
	player1.exceeded = true
	var wonderland_attack_id = give_player_specific_card(player1, "standard_normal_dive")
	var wonderland_attack = game_logic.card_db.get_card(wonderland_attack_id)
	player1.remove_card_from_hand(wonderland_attack_id, false, false)
	player1.add_to_set_aside(wonderland_attack)
	advance_turn(player1)

	execute_strike(player2, player1, "standard_normal_assault", wonderland_attack_id)

	assert_false(player1.is_card_in_set_aside(wonderland_attack_id))
	assert_true(player1.is_card_in_discards(wonderland_attack_id))
	assert_false(player1.is_card_in_gauge(wonderland_attack_id))

func test_choose_discard_uses_saved_source_not_global():
	position_players(player1, 4, player2, 5)
	player1.hand = []
	give_player_specific_card(player1, "standard_normal_spike")
	player2.hand.clear()
	var target = give_player_specific_card(player2, "standard_normal_spike")
	execute_strike(player1, player2, "eugenia_frenzied_glimmer", "standard_normal_dive",
		false, false,
		[],
		[], true)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseToDiscard)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	game_logic._last_effect_source_player_id = -1
	assert_true(game_logic.do_choose_to_discard(player1, [target]))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_choice(player1, 1))
	validate_life(player1, 30, player2, 26)

func test_effect_choice_uses_saved_source_not_global():
	position_players(player1, 2, player2, 5)
	player1.hand = []
	give_player_specific_card(player1, "standard_normal_spike")
	player2.hand.clear()
	give_player_specific_card(player2, "standard_normal_spike")
	give_player_specific_card(player2, "standard_normal_spike")
	give_player_specific_card(player2, "standard_normal_spike")
	execute_strike(player1, player2, "eugenia_light_of_bygone", "standard_normal_grasp",
		false, false,
		[],
		[], true)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player2.my_id)
	game_logic._last_effect_source_player_id = -1
	assert_true(game_logic.do_choice(player2, 0))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_choice(player1, 1))
	validate_life(player1, 30, player2, 24)

func test_cats_cradle_end_of_turn_draw_does_not_misread_self_hand():
	position_players(player1, 4, player2, 5)
	player1.hand = []
	player2.hand = []
	var boost_id = give_player_specific_card(player1, "eugenia_cats_cradle")
	var boost_card = game_logic.card_db.get_card(boost_id)
	player1.add_to_continuous_boosts(boost_card)
	if player1.is_card_in_hand(boost_id):
		player1.remove_card_from_hand(boost_id, false, false)
	var discard_target = give_player_specific_card(player2, "standard_normal_assault")
	var p1_before_hand = player1.hand.size()
	var p2_before_hand = player2.hand.size()
	var source_before_discard = player1.my_id
	game_logic._last_effect_source_player_id = source_before_discard

	player2.discard([discard_target])

	assert_eq(game_logic._last_effect_source_player_id, source_before_discard)
	assert_eq(player2.hand.size(), p2_before_hand - 1)
	assert_eq(player1.hand.size(), p1_before_hand)

	game_logic.start_end_turn()
	assert_eq(player1.hand.size(), p1_before_hand + 1)
	assert_eq(player2.hand.size(), p2_before_hand - 1)
	assert_false(player1.hand.is_empty())
	assert_true(player1.is_card_in_continuous_boosts(boost_id))

func test_cats_cradle_boost_end_turn_hand_limit_belongs_to_eugenia():
	position_players(player1, 4, player2, 5)
	player1.hand = []
	player2.hand = []
	var boost_id = give_player_specific_card(player1, "eugenia_cats_cradle")
	for _i in range(7):
		give_player_specific_card(player1, "standard_normal_assault")
	give_player_specific_card(player2, "standard_normal_assault")
	game_logic.get_latest_events()

	assert_true(game_logic.do_boost(player1, boost_id, []))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_choice(player1, 0))

	assert_eq(game_logic.game_state, Enums.GameState.GameState_DiscardDownToMax)
	assert_eq(player1.hand.size(), 8)
	assert_eq(player2.hand.size(), 0)
	var events = game_logic.get_latest_events()
	var hand_size_events = events.filter(func(event):
		return event['event_type'] == Enums.EventType.EventType_HandSizeExceeded
	)
	assert_eq(hand_size_events.size(), 1)
	assert_eq(hand_size_events[0]['event_player'], player1.my_id)
	assert_eq(hand_size_events[0]['number'], 1)

	assert_true(game_logic.do_discard_to_max(player1, [player1.hand[0].id]))
	assert_eq(player1.hand.size(), 7)
	assert_eq(game_logic.active_turn_player, player2.my_id)

func test_qoh_discard_after_shimmer_transform_triggers_matching_speed_passive():
	# Regression: transforming Shimmer adds a 2nd hit effect (Hanging by a Thread
	# +2 Power via AddAttackEffect), so the engine asks ChooseSimultaneousEffect
	# to order the hit effects. That decision path must NOT poison the discard
	# source with -1; the normal passive must still fire on the Queen of Hearts
	# hand discard.
	position_players(player1, 4, player2, 5)
	add_transform(player1, "eugenia_frenzied_glimmer")
	var gauge_ids = give_gauge(player1, 3)
	player2.hand = []
	give_player_specific_card(player2, "standard_normal_assault")
	give_player_specific_card(player2, "standard_normal_cross")
	give_player_specific_card(player2, "standard_normal_dive")

	execute_strike(player1, player2, "eugenia_queen_of_hearts", "standard_normal_grasp",
		false, false,
		[gauge_ids, 0, 0],  # pay gauge; effect order: discard first; passive pass
		[])
	validate_life(player1, 30, player2, 24)  # 30 - (1 base + 3 discarded + 2 Shimmer powerup)

func test_cats_cradle_boost_is_not_an_active_strike_card():
	# Regression: playing Cat's Cradle as a boost (Edge of Sanity) triggers an
	# opponent discard via its "now" effect. The discard event must NOT be
	# mistaken for a Cradle hit closeup trigger, because the card is a boost,
	# not an attack card in the active strike.
	position_players(player1, 4, player2, 5)
	var cradle_id = give_player_specific_card(player1, "eugenia_cats_cradle")

	assert_true(game_logic.do_boost(player1, cradle_id, []))
	# Edge of Sanity's now effect made the opponent discard, which can trigger
	# Eugenia's normal passive choice (reveal matching speed card). Pass it.
	if game_logic.game_state == Enums.GameState.GameState_PlayerDecision \
			and game_logic.decision_info.type == Enums.DecisionType.DecisionType_EffectChoice:
		assert_true(game_logic.do_choice(player1, 0))
	assert_false(game_logic.is_card_active_strike_card(cradle_id),
			"A boosted Cat's Cradle must not count as an active strike attack card")
	# The boost's now effect discarded an opponent card; verify the discard
	# happened but the engine did not register a strike.
	assert_true(player1.is_card_in_continuous_boosts(cradle_id),
			"Edge of Sanity should be a continuous boost")
	assert_false(game_logic.has_active_strike(),
			"No active strike should exist after playing a boost")

func test_cats_cradle_as_attack_is_an_active_strike_card():
	# When Cat's Cradle is actually set as the attack card, it must be
	# recognized as an active strike attack card.
	position_players(player1, 4, player2, 5)
	var cradle_id = give_player_specific_card(player1, "eugenia_cats_cradle")

	assert_true(game_logic.do_strike(player1, cradle_id, false, -1))
	assert_true(game_logic.is_card_active_strike_card(cradle_id),
			"The Cradle attack card should be in the active strike")

func test_cats_cradle_hit_emits_strike_hit_event():
	# When a Cat's Cradle attack actually lands, the engine must emit the
	# Strike_Hit event (the UI plays the hit closeup from this event).
	position_players(player1, 4, player2, 5)
	var gauge_ids = give_gauge(player1, 3)
	player2.hand = []
	give_player_specific_card(player2, "standard_normal_assault")
	give_player_specific_card(player2, "standard_normal_cross")
	give_player_specific_card(player2, "standard_normal_dive")
	game_logic.get_latest_events()

	execute_strike(player1, player2, "eugenia_cats_cradle", "standard_normal_spike", false, false, [gauge_ids, 0], [])

	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_Strike_Hit, player1)
	validate_not_has_event(events, Enums.EventType.EventType_Strike_Miss, player1)

func test_cats_cradle_out_of_range_emits_strike_miss_no_hit():
	# Out of range (distance 5 > Cat's Cradle's range 1-3): the attack misses
	# and the engine must emit Strike_Miss for the attacker and NO Strike_Hit,
	# so the UI will not play the hit closeup.
	position_players(player1, 2, player2, 7)
	var gauge_ids = give_gauge(player1, 3)
	player2.hand = []
	give_player_specific_card(player2, "standard_normal_assault")
	give_player_specific_card(player2, "standard_normal_cross")
	give_player_specific_card(player2, "standard_normal_dive")
	game_logic.get_latest_events()

	execute_strike(player1, player2, "eugenia_cats_cradle", "standard_normal_spike", false, false, [gauge_ids], [])

	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_Strike_Miss, player1)
	validate_not_has_event(events, Enums.EventType.EventType_Strike_Hit, player1)

func test_happychaos_fire_gauge_payment_does_not_trigger_eugenia_passive():
	# Regression (2026-08-18): Happy Chaos's Fire (4-speed special) hit effect
	# makes the ATTACKER pay force from gauge. That payment discard must NOT be
	# attributed to Eugenia's passive ("your own effect makes the opponent
	# discard"). Log-exact scenario: seed 5863294181541210112, Eugenia p1,
	# Happy Chaos p2, Fire id 212 paid with 213/229/227.
	image_loader = CardImageLoader.new(true)
	game_logic = LocalGame.new(image_loader)
	game_logic.initialize_game(
		CardDataManager.get_deck_from_str_id("eugenia"),
		CardDataManager.get_deck_from_str_id("happychaos"),
		"p1", "p2", Enums.PlayerId.PlayerId_Player, 5863294181541210112)
	game_logic.draw_starting_hands_and_begin()
	player1 = game_logic.player
	player2 = game_logic.opponent
	assert_true(game_logic.do_mulligan(player1, [106, 119, 122, 105, 107]))
	assert_true(game_logic.do_mulligan(player2, []))
	game_logic.get_latest_events()
	if game_logic.get_active_player() == player1.my_id:
		assert_true(game_logic.do_prepare(player1))
	game_logic.get_latest_events()
	assert_true(game_logic.do_strike(player2, 212, false, -1))
	do_strike_response(player1, 119, -1)
	var saw_eugenia_passive_choice = false
	var guard = 0
	while game_logic.game_state == Enums.GameState.GameState_PlayerDecision and guard < 25:
		guard += 1
		match game_logic.decision_info.type:
			Enums.DecisionType.DecisionType_ChooseSimultaneousEffect:
				assert_true(game_logic.do_choice(player2, 0))
			Enums.DecisionType.DecisionType_ForceForEffect:
				assert_true(game_logic.do_force_for_effect(player2, [213, 229, 227], false))
			Enums.DecisionType.DecisionType_ChooseToDiscard:
				assert_true(game_logic.do_choose_to_discard(player2, []))
			Enums.DecisionType.DecisionType_EffectChoice:
				if game_logic.decision_info.player == player1.my_id:
					saw_eugenia_passive_choice = true
				assert_true(game_logic.do_choice(player2, 0))
			_:
				assert_true(game_logic.do_choice(player2, 0))
	assert_false(saw_eugenia_passive_choice,
		"Fire's gauge payment must NOT trigger Eugenia's passive")
	assert_false(player1.eugenia_normal_passive_used_this_turn,
		"Fire's gauge payment must not consume Eugenia's passive")

func test_opponent_discard_random_triggers_passive():
	# "不能漏": opponent_discard_random is the shared discard path for Cat's
	# Cradle hit / Edge of Sanity (boost now) / Time for Tea (overall_effect).
	# Any of Eugenia's own effects that discard the opponent must arm the
	# matching-speed passive choice.
	position_players(player1, 4, player2, 5)
	player1.hand = []
	give_player_specific_card(player1, "standard_normal_assault")
	player2.hand = []
	give_player_specific_card(player2, "standard_normal_assault")
	game_logic.get_latest_events()
	var effect = {
		"timing": "hit",
		"effect_type": StrikeEffects.OpponentDiscardRandom,
		"amount": 1
	}
	game_logic.handle_strike_effect(-1, effect, player1)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice,
		"Eugenia's own opponent-discard effect must arm the passive choice")
	assert_eq(game_logic.decision_info.player, player1.my_id)

func test_opponent_discard_choose_internal_triggers_passive():
	# "不能漏": when the opponent's reduce_discard_effects_by forces QOH's hand
	# discard through OpponentDiscardChooseInternal (chooser executes the
	# discard), the passive must still fire: do_choose_to_discard stamps
	# _source_player_id = Eugenia, and the handler / handle_strike_effect entry
	# must honour it.
	position_players(player1, 4, player2, 5)
	player1.hand = []
	give_player_specific_card(player1, "standard_normal_assault")
	player2.hand = []
	var card_id = give_player_specific_card(player2, "standard_normal_assault")
	game_logic.get_latest_events()
	game_logic._last_effect_source_player_id = player1.my_id
	var effect = {
		"effect_type": StrikeEffects.OpponentDiscardChooseInternal,
		"card_ids": [card_id],
		"destination": "discard",
		"_source_player_id": player1.my_id
	}
	game_logic.handle_strike_effect(-1, effect, player2)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice,
		"Reduced QOH discard must still arm Eugenia's passive choice")
	assert_eq(game_logic.decision_info.player, player1.my_id)

func test_opponent_self_discard_does_not_trigger_passive():
	# "不能有多": the OPPONENT discarding their own cards by their own effects
	# must NOT trigger the passive (only Eugenia's own effects count).
	position_players(player1, 4, player2, 5)
	player1.hand = []
	give_player_specific_card(player1, "standard_normal_assault")
	player2.hand = []
	give_player_specific_card(player2, "standard_normal_assault")
	game_logic.get_latest_events()
	game_logic._last_effect_source_player_id = player2.my_id
	player2.discard([player2.hand[0].id])
	assert_ne(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice,
		"Opponent self-discard must not arm Eugenia's passive")
	assert_false(player1.eugenia_normal_passive_used_this_turn)

func test_eugenia_self_discard_does_not_trigger_passive():
	# "不能有多": Eugenia discarding her OWN cards (e.g. paying her own costs)
	# must not trigger the passive — the discarder is Eugenia herself.
	position_players(player1, 4, player2, 5)
	player1.hand = []
	var self_card = give_player_specific_card(player1, "standard_normal_assault")
	game_logic.get_latest_events()
	game_logic._last_effect_source_player_id = player1.my_id
	player1.discard([self_card])
	assert_ne(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice,
		"Eugenia discarding her own card must not arm the passive")
	assert_false(player1.eugenia_normal_passive_used_this_turn)

# ===== 觉醒 +1/+1 只对「用奇境卡牌的面攻」生效（2026-10-05）=====
# next_strike_faceup 是玩家级标记，用过奇境卡后会一直留着；防御方的加成曾读它，
# 于是之后的疯狂攻击也应声吃到 +1/+1。

func test_wild_swing_response_does_not_get_wonderland_bonus():
	player1.exceed()
	position_players(player1, 5, player2, 4)
	advance_turn(player1)  # 把回合交给对手，由它发起战斗
	var atk = give_player_specific_card(player2, "standard_normal_sweep")
	assert_true(game_logic.do_strike(player2, atk, false, -1), "对手发起攻击")
	player1.next_strike_faceup = true  # 模拟本局此前用过奇境卡留下的残留标记
	assert_true(game_logic.do_strike(player1, -1, true, -1), "以疯狂攻击应战")

	assert_eq(player1.strike_stat_boosts.power, 0, "疯狂攻击不该拿到奇境面攻的 +1 威力")
	assert_eq(player1.strike_stat_boosts.speed, 0, "疯狂攻击不该拿到奇境面攻的 +1 速度")
	# 注：那个残留标记本身由「从奇境出牌」的那一支负责清掉（见 local_game 防守方分支），
	# 疯狂攻击不消费它；这里只保证它不会再给该玩家加数值。
