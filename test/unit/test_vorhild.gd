extends ExceedGutTest

func who_am_i():
	return "vorhild"

## Character ability -- Action: Retreat 1. If you are Infused, you may play a Boost from your hand.

func test_vorhild_ua_with_boost():
	position_players(player1, 3, player2, 6)
	var fierce_id = give_player_specific_card(player1, "standard_normal_grasp")
	
	var gauge_cards = give_gauge(player1, 1)
	# Infusion action
	assert_true(game_logic.do_character_action(player1, [gauge_cards[0]], 1))

	assert_true(game_logic.do_character_action(player1, []))
	assert_true(game_logic.do_choice(player1, 0)) # accept choice to boost
	assert_true(game_logic.do_boost(player1, fierce_id, []))
	var events = game_logic.get_latest_events()

	assert_true(player1.is_card_in_continuous_boosts(fierce_id))
	validate_positions(player1, 2, player2, 6)
	validate_not_has_event(events, Enums.EventType.EventType_RevealHand, player1, 0)
	assert_eq(game_logic.get_active_player(), player2.my_id)

func test_vorhild_ua_with_no_boost():
	position_players(player1, 3, player2, 6)
	player1.discard_hand()
	
	var gauge_cards = give_gauge(player1, 1)
	# Infusion action
	assert_true(game_logic.do_character_action(player1, [gauge_cards[0]], 1))

	assert_true(game_logic.do_character_action(player1, []))
	assert_true(game_logic.do_choice(player1, 0)) # accept choice to boost, but it gets skipped
	var events = game_logic.get_latest_events()

	validate_positions(player1, 2, player2, 6)
	validate_not_has_event(events, Enums.EventType.EventType_RevealHand, player1, 0)
	assert_eq(game_logic.get_active_player(), player2.my_id)

func _start_ermines_eye_against_carlclover():
	game_logic.teardown()
	game_logic.free()
	default_game_setup("carlclover")
	position_players(player1, 3, player2, 7)
	player2.set_buddy_location("nirvana_active", 8)
	var attack = give_player_specific_card(player1, "vorhild_theermineseye")
	var response = give_player_specific_card(player2, "standard_normal_focus")
	var payment = give_gauge(player1, 2)
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_true(game_logic.do_gauge_for_effect(player1, []))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_true(game_logic.do_pay_strike_cost(player1, payment, false))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseSimultaneousEffect)
	assert_eq(game_logic.decision_info.limitation, [true, false])

func test_ermines_eye_before_is_consumed_without_selecting_failed_nirvana():
	_start_ermines_eye_against_carlclover()
	var initial_hand = player1.hand.size()
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect)
	assert_eq(player1.hand.size(), initial_hand + 1)
	assert_eq(game_logic.active_strike.remaining_effect_list.size(), 1)
	assert_true(game_logic.do_choice(player1, select_space(0)))
	assert_null(game_logic.active_strike)
	assert_eq(player1.hand.size(), initial_hand + 1)
	assert_eq(player2.get_buddy_location("nirvana_active"), 8)

func test_ermines_eye_failed_nirvana_first_still_draws_once():
	_start_ermines_eye_against_carlclover()
	var initial_hand = player1.hand.size()
	assert_true(game_logic.do_choice(player1, 1))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect)
	assert_true(game_logic.do_choice(player1, select_space(0)))
	assert_null(game_logic.active_strike)
	assert_eq(player1.hand.size(), initial_hand + 1)
	assert_eq(player2.get_buddy_location("nirvana_active"), 8)

func test_ermines_eye_movement_can_enable_remaining_nirvana_effect():
	_start_ermines_eye_against_carlclover()
	var initial_hand = player1.hand.size()
	assert_true(game_logic.do_choice(player1, 0))
	assert_true(game_logic.do_choice(player1, select_space(4)))
	assert_eq(player1.arena_location, 4)
	assert_eq(player1.hand.size(), initial_hand + 1)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.choice[0].effect_type, "flip_buddy_miss_get_gauge")
	assert_true(game_logic.do_choice(player1, 0))
	assert_null(game_logic.active_strike)
	assert_eq(player2.get_buddy_location("nirvana_active"), -1)
	assert_eq(player2.get_buddy_location("nirvana_disabled"), 8)
