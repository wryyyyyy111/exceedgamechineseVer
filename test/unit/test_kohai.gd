extends ExceedGutTest

func who_am_i():
	return "kohai"

##
## Tests start here
##

## Kohai - When you boost while Infused, Pull up to 2 (before boost effects).

func test_boost_infuse_before_character_and_card_effects():
	position_players(player1, 3, player2, 7)
	player1.discard_hand()
	var gauge = give_gauge(player1, 1)
	var boost_card = give_player_specific_card(player1, "kohai_earthquakestomp")
	assert_true(game_logic.do_boost(player1, boost_card, []))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_GaugeForEffect)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_false(player1.is_infused())
	assert_eq(player1.hand.size(), 0, "Boost effects must wait for the infuse decision")
	validate_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_GaugeForEffect, player1)

	assert_true(game_logic.do_gauge_for_effect(player1, gauge))
	assert_true(player1.is_infused())
	assert_true(player1.is_card_in_discards(gauge[0]))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(player1.hand.size(), 0, "Character pull must happen before the boost draws")
	assert_true(game_logic.do_choice(player1, 1))
	validate_positions(player1, 3, player2, 5)
	assert_eq(player1.hand.size(), 2, "The boost must draw exactly once")
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)
	assert_true(player1.is_card_in_continuous_boosts(boost_card))

func test_boost_infuse_decline_resolves_uninfused_boost():
	player1.discard_hand()
	var gauge = give_gauge(player1, 1)
	var boost_card = give_player_specific_card(player1, "kohai_earthquakestomp")
	assert_true(game_logic.do_boost(player1, boost_card, []))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_GaugeForEffect)
	assert_true(game_logic.do_gauge_for_effect(player1, []))
	assert_false(player1.is_infused())
	assert_true(player1.is_card_in_gauge(gauge[0]))
	validate_positions(player1, 3, player2, 7)
	assert_eq(player1.hand.size(), 3, "Draw two plus the non-strike end-turn draw")
	assert_eq(game_logic.active_turn_player, player2.my_id)
	assert_true(player1.is_card_in_continuous_boosts(boost_card))
	assert_null(game_logic.active_boost)

func test_boost_infuse_skips_without_gauge():
	player1.discard_hand()
	var boost_card = give_player_specific_card(player1, "kohai_earthquakestomp")
	assert_true(game_logic.do_boost(player1, boost_card, []))
	assert_false(player1.is_infused())
	assert_eq(game_logic.active_turn_player, player2.my_id)
	assert_eq(player1.hand.size(), 3)
	validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_GaugeForEffect, player1)

func test_boost_without_infused_effect_does_not_prompt():
	player1.discard_hand()
	var gauge = give_gauge(player1, 1)
	var boost_card = give_player_specific_card(player1, "standard_normal_grasp")
	assert_true(game_logic.do_boost(player1, boost_card, []))
	assert_false(player1.is_infused())
	assert_true(player1.is_card_in_gauge(gauge[0]))
	assert_eq(game_logic.active_turn_player, player2.my_id)
	validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_GaugeForEffect, player1)

func test_boost_infuse_checks_gauge_after_boost_payment():
	player1.discard_hand()
	var gauge = give_gauge(player1, 1)
	var boost_card = give_player_specific_card(player1, "kohai_gapingmaw")
	assert_true(game_logic.do_boost(player1, boost_card, gauge))
	assert_true(player1.is_card_in_discards(gauge[0]))
	assert_false(player1.is_infused())
	assert_eq(game_logic.active_turn_player, player2.my_id)
	validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_GaugeForEffect, player1)

func test_boost_already_infused_does_not_prompt_again():
	player1.discard_hand()
	var gauge = give_gauge(player1, 2)
	assert_true(game_logic.do_character_action(player1, [gauge[0]]))
	var boost_card = give_player_specific_card(player1, "kohai_earthquakestomp")
	assert_true(game_logic.do_boost(player1, boost_card, []))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player1, 2))
	assert_true(player1.is_card_in_gauge(gauge[1]))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)
	validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_GaugeForEffect, player1)

func test_boost_from_gauge_cannot_pay_for_its_own_infuse():
	player1.discard_hand()
	var payment_card = give_player_specific_card(player1, "standard_normal_grasp")
	var boost_card = give_player_specific_card(player1, "kohai_gapingmaw")
	player1.move_card_from_hand_to_gauge(boost_card)
	assert_true(game_logic.do_boost(player1, boost_card, [payment_card]))
	assert_false(player1.is_infused())
	assert_true(player1.is_card_in_continuous_boosts(boost_card))
	assert_eq(game_logic.active_turn_player, player2.my_id)
	validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_GaugeForEffect, player1)

func test_preselected_infuse_rejects_shared_payment_without_spending():
	player1.discard_hand()
	var gauge = give_gauge(player1, 1)
	var boost_card = give_player_specific_card(player1, "kohai_ambush")
	assert_false(game_logic.do_boost(player1, boost_card, gauge, false, 0, [], null, gauge))
	assert_true(player1.is_card_in_hand(boost_card))
	assert_true(player1.is_card_in_gauge(gauge[0]))
	assert_false(player1.is_infused())
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)

func test_preselected_infuse_decline_does_not_prompt_twice():
	player1.discard_hand()
	var gauge = give_gauge(player1, 1)
	var boost_card = give_player_specific_card(player1, "kohai_earthquakestomp")
	assert_true(game_logic.do_boost(player1, boost_card, [], false, 0, [], null, []))
	assert_false(player1.is_infused())
	assert_true(player1.is_card_in_gauge(gauge[0]))
	assert_eq(game_logic.active_turn_player, player2.my_id)
	validate_not_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_GaugeForEffect, player1)

func test_preselected_free_gauge_infuse_rejects_missing_discount():
	var boost_card = give_player_specific_card(player1, "kohai_earthquakestomp")
	assert_false(game_logic.do_boost(player1, boost_card, [], false, 0, [], null, {"free_gauge": 1}))
	assert_false(player1.is_infused())
	assert_true(player1.is_card_in_hand(boost_card))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)

func test_kohai_boost_and_pull():
	position_players(player1, 3, player2, 7)
	var gauge_card = give_gauge(player1, 1)
	
	var boost_card = give_player_specific_card(player1, "standard_normal_grasp")
	assert_true(game_logic.do_character_action(player1, gauge_card)) # infuse
	assert_true(game_logic.do_boost(player1, boost_card, []))
	assert_true(game_logic.do_choice(player1, 1)) # pull 2
	
	validate_positions(player1, 3, player2, 5)
	assert_true(player1.is_card_in_continuous_boosts(boost_card))
	
	advance_turn(player2)
	
func test_kohai_terrifying_pull():
	position_players(player1, 3, player2, 5)
	var gauge_card = give_gauge(player1, 1)
	var p2_hand_size = len(player2.hand)
	
	var boost_card = give_player_specific_card(player1, "kohai_harpoon")
	assert_true(game_logic.do_character_action(player1, gauge_card)) # infuse
	assert_true(game_logic.do_boost(player1, boost_card, [player1.hand[0].id]))
	assert_true(game_logic.do_choice(player1, 0)) # pull 1
	
	validate_positions(player1, 3, player2, 4)
	assert_eq(len(player2.hand), p2_hand_size - 2)
	
	execute_strike(player1, player2, "standard_normal_focus", "standard_normal_focus")
	advance_turn(player2)
	
func test_kohai_boost_pull_negate():
	position_players(player1, 3, player2, 7)
	var gauge_card = give_gauge(player1, 1)

	give_player_specific_card(player2, "seijun_yokaibanishing")
	player2.add_to_transforms(player2.hand[-1])
	player2.discard_hand()

	var p1_cross_id = give_player_specific_card(player1, "standard_normal_cross")
	var p2_cross_id = give_player_specific_card(player2, "standard_normal_cross")
	assert_true(game_logic.do_character_action(player1, gauge_card)) # infuse
	assert_true(game_logic.do_boost(player1, p1_cross_id, []))
	assert_true(game_logic.do_choice(player1, 1)) # pull happens first; pull 2
	# p2 has a copy of cross
	assert_true(game_logic.do_choice(player2, 0)) # discard, preventing p2 from using effect

	validate_positions(player1, 3, player2, 5)
	assert_true(player2.is_card_in_discards(p2_cross_id))
	advance_turn(player2)

# There used to be a test around opponent_in_center_3_spaces here, but then the boost
# that used it got changed in a playtesting update
