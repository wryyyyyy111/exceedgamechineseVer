extends ExceedGutTest

func who_am_i():
	return "happychaos"

func test_happychaos_exceed_auto_face_attack_returns_to_set_aside_and_reverts():
	position_players(player1, 3, player2, 7)

	var gauge_cards = give_gauge(player1, 3)
	var face_attack = player1.get_set_aside_card("happychaos_deusexmachina")
	assert_ne(face_attack, null)
	var face_attack_id = face_attack.id

	assert_true(game_logic.do_exceed(player1, gauge_cards))

	assert_true(player1.exceeded)
	assert_false(player1.is_card_in_set_aside(face_attack_id))
	assert_false(player1.is_card_in_discards(face_attack_id))
	assert_false(player1.is_card_in_gauge(face_attack_id))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_Strike_Opponent_Response)

	var response_card_id = give_player_specific_card(player2, "standard_normal_cross")
	assert_true(game_logic.do_strike(player2, response_card_id, false, -1))

	assert_false(player1.exceeded)
	assert_eq(player1.face_attack_id, "")
	assert_eq(player1.get_face_attack_card(), null)
	assert_true(player1.is_card_in_set_aside(face_attack_id))
	assert_false(player1.is_card_in_discards(face_attack_id))
	assert_false(player1.is_card_in_gauge(face_attack_id))

func test_happychaos_ua_hit_prompts_without_ultra_in_hand():
	position_players(player1, 3, player2, 4)

	var ultras_in_hand = []
	for card in player1.hand:
		if card.definition["type"] == "ultra":
			ultras_in_hand.append(card.id)
	if ultras_in_hand.size() > 0:
		player1.discard(ultras_in_hand)
	assert_eq(player1.get_cards_in_hand_of_type("ultra").size(), 0)

	# If UA prompt appears, this [] is consumed as "pass" for the optional discard.
	execute_strike(player1, player2,
		"standard_normal_assault", "standard_normal_block",
		false, false,
		[0, []], [[]])

	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
