extends ExceedGutTest

func who_am_i():
	return "astryda"

##
## Tests start here
##

## Exceed mode - When you Exceed, name a card and Strike. That card is invalid for both players. Hit: The opponent discards a card. Cleanup: Revert.

func test_astryda_exceed():
	position_players(player1, 3, player2, 5)
	
	var p1_gauge = give_gauge(player1, 2)
	
	# stack decks so wild swings can be tested
	var p1_deckassault = give_player_specific_card(player1, "standard_normal_assault")
	player1.move_card_from_hand_to_deck(p1_deckassault)
	var p2_deckdive = give_player_specific_card(player2, "standard_normal_dive")
	player2.move_card_from_hand_to_deck(p2_deckdive)
	
	var cross = give_player_specific_card(player1, "standard_normal_cross")
	var p1_starting_hand_size = player1.hand.size()
	var p2_starting_hand_size = player2.hand.size()
	
	
	# Exceed and name cross
	assert_true(game_logic.do_exceed(player1, p1_gauge))
	assert_true(game_logic.do_boost_name_card_choice_effect(player1, cross))
	
	# Both strike with cross; should end up with the assault into dive
	var strike_cards = execute_strike(player1, player2, "standard_normal_cross", "standard_normal_cross",
		false, false, [0], [[player2.hand[0].id]]) 
		
	validate_positions(player1, 4, player2, 5)
	validate_life(player1, 30, player2, 26)
	
	assert_true(player1.is_card_in_discards(strike_cards[0]))
	assert_true(player2.is_card_in_discards(strike_cards[1]))
	assert_true(player1.is_card_in_gauge(p1_deckassault))
	assert_true(player2.is_card_in_discards(p2_deckdive))
	assert_eq(player2.hand.size(), p2_starting_hand_size - 1)
	assert_false(player1.exceeded)

	advance_turn(player1)


## Drown - 1/5/3; Infused, Before: Close 2; Hit: The opponent discards all but 1 card from hand, then draws a card.

# normal case

func test_astryda_drown_discard():
	position_players(player1, 4, player2, 5)
	
	player2.draw(5)
	var keep_card = player2.hand[3].id
	var other_cards = []
	for card in player2.hand:
		if card.id != keep_card:
			other_cards.append(card.id)
	
	var strike_cards = execute_strike(player1, player2, "astryda_drown", "standard_normal_spike",
		false, false, [], [other_cards])
	
	validate_positions(player1, 4, player2, 5)
	validate_life(player1, 30, player2, 25)
	
	assert_true(player2.is_card_in_hand(keep_card))
	assert_eq(player2.hand.size(), 2)

	advance_turn(player2)

func test_lust_for_power_ai_discards_own_gauge_with_empty_opponent_gauge():
	_verify_lust_for_power_ai_gauge_discard(1, 0)

func test_lust_for_power_ai_discards_own_gauge_with_both_gauges_populated():
	_verify_lust_for_power_ai_gauge_discard(3, 1)

func _verify_lust_for_power_ai_gauge_discard(ai_gauge_count: int, opponent_gauge_count: int):
	position_players(player1, 3, player2, 7)
	var infuse_gauge = give_gauge(player1, 1)
	var ai_gauge = give_gauge(player2, ai_gauge_count)
	var boost_card = give_player_specific_card(player1, "astryda_bewitchingsong")
	assert_true(game_logic.do_boost(player1, boost_card, [player1.hand[0].id]))
	assert_true(game_logic.do_gauge_for_effect(player1, []))
	advance_turn(player2)
	assert_true(game_logic.do_character_action(player1, infuse_gauge, 1))
	var opponent_gauge = give_gauge(player1, opponent_gauge_count)

	var attack = give_player_specific_card(player1, "standard_normal_dive")
	var response = give_player_specific_card(player2, "standard_normal_sweep")
	do_and_validate_strike(player1, attack)
	do_strike_response(player2, response)
	assert_true(game_logic.do_gauge_for_effect(player2, []))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseDiscardOpponentGauge)
	assert_eq(game_logic.decision_info.player, player2.my_id)

	var action: AIPlayer.DiscardGaugeAction
	for policy_type in [AIPolicyRules, AIPolicyOmniscient, AIPolicyRandom]:
		var ai = AIPlayer.new(game_logic, player2, policy_type.new())
		action = ai.pick_discard_opponent_gauge()
		ai.ai_policy.free()
		assert_not_null(action, "AI must choose from its own gauge even if the opponent's gauge is empty")
		if action == null:
			return
		assert_has(ai_gauge, action.card_id, "AI must discard its own gauge, not the attacker's")
		if action.card_id not in ai_gauge:
			return
	assert_true(game_logic.do_boost_name_card_choice_effect(player2, action.card_id))
	assert_true(player2.is_card_in_discards(action.card_id))
	assert_eq(player2.gauge.size(), ai_gauge_count - 1)
	for card_id in opponent_gauge:
		assert_true(player1.is_card_in_gauge(card_id))
	assert_null(game_logic.active_strike, "The hit decision must resolve and let the strike finish")
	advance_turn(player2)

# empty hand case

func test_astryda_drown_empty_hand():
	position_players(player1, 4, player2, 5)
	
	var p1_handsize = player1.hand.size()
	player2.discard_hand()
	
	var strike_cards = execute_strike(player1, player2, "astryda_drown", "standard_normal_spike",
		false, false, [], [])
	
	validate_positions(player1, 4, player2, 5)
	validate_life(player1, 30, player2, 25)
	
	assert_eq(player1.hand.size(), p1_handsize)
	assert_eq(player2.hand.size(), 1)
	
	advance_turn(player2)

## Lust For Power (boost on Bewitching Song) - +2 Power, +2 Guard.
##     Infused, Hit: The opponent discards a card from their Gauge.

func test_astryda_lust_for_power():
	position_players(player1, 3, player2, 7)
	
	var p1_gauge = give_gauge(player1, 1)
	var p2_gauge = give_gauge(player2, 3)
	
	var boost_card = give_player_specific_card(player1, "astryda_bewitchingsong")
	assert_true(game_logic.do_boost(player1, boost_card, [player1.hand[0].id]))
	assert_true(game_logic.do_gauge_for_effect(player1, []))
	advance_turn(player2)
	
	# infuse
	assert_true(game_logic.do_character_action(player1, p1_gauge, 1))
	var strike_cards = execute_strike(player1, player2, "standard_normal_dive", "standard_normal_sweep",
		false, false, [], [[], p2_gauge[1]]) #p2 does not infuse, then chooses the middle card to discard from gauge
	
	validate_positions(player1, 6, player2, 7)
	validate_life(player1, 30, player2, 23)
	
	assert_true(player2.is_card_in_gauge(p2_gauge[0]))
	assert_true(player2.is_card_in_discards(p2_gauge[1]))
	assert_true(player2.is_card_in_gauge(p2_gauge[2]))
	
	advance_turn(player2)
