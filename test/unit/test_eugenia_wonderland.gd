extends "res://test/exceed_test.gd"

func who_am_i():
	return "eugenia"

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