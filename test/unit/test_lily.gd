extends ExceedGutTest

func who_am_i():
	return "lily"

##
## Lily passive tests
##

func test_lily_retreat_costs_less_force():
	# Lily retreats 2 spaces (5 -> 3) with only 1 force available.
	# Normal cost is 2 force; her passive reduces retreat cost by 1.
	position_players(player1, 5, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	var card1 = give_player_specific_card(player1, "standard_normal_grasp")
	assert_true(game_logic.do_move(player1, [card1], 3))
	validate_positions(player1, 3, player2, 7)

func test_lily_retreat_one_space_is_free():
	# Lily retreats 1 space (5 -> 4); discount brings cost from 1 to 0.
	position_players(player1, 5, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	assert_true(game_logic.do_move(player1, [], 4))
	validate_positions(player1, 4, player2, 7)

func test_lily_retreat_on_right_side_costs_less_force():
	# Lily is on the opponent's right side; retreating means moving right
	# (away from the opponent). The discount must apply on this side too.
	position_players(player1, 7, player2, 3)
	player1.discard_hand()
	player2.discard_hand()
	# Retreat 2 spaces right (7 -> 9): normal cost 2, discounted to 1.
	var card1 = give_player_specific_card(player1, "standard_normal_grasp")
	assert_true(game_logic.do_move(player1, [card1], 9))
	validate_positions(player1, 9, player2, 3)

func test_lily_retreat_on_right_side_one_space_is_free():
	# Retreating 1 space right (7 -> 8) is free thanks to the discount.
	position_players(player1, 7, player2, 3)
	player1.discard_hand()
	player2.discard_hand()
	assert_true(game_logic.do_move(player1, [], 8))
	validate_positions(player1, 8, player2, 3)

func test_lily_advance_on_right_side_does_not_get_discount():
	# On the opponent's right side, advancing means moving left (toward them).
	# Advancing must NOT get the retreat discount: 2 spaces still needs 2 force.
	position_players(player1, 7, player2, 3)
	player1.discard_hand()
	player2.discard_hand()
	var card1 = give_player_specific_card(player1, "standard_normal_grasp")
	assert_false(game_logic.do_move(player1, [card1], 5))
	validate_positions(player1, 7, player2, 3)

func test_lily_advance_does_not_get_discount():
	# Advancing 2 spaces (3 -> 5) still costs 2 force; 1 card is not enough.
	position_players(player1, 3, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	var card1 = give_player_specific_card(player1, "standard_normal_grasp")
	assert_false(game_logic.do_move(player1, [card1], 5))
	validate_positions(player1, 3, player2, 7)

func test_lily_exceed_retreat_costs_less_force():
	# After exceeding, the retreat discount still applies.
	# Exceeding (like boosting) passes the turn, so p2 prepares first.
	position_players(player1, 5, player2, 7)
	give_gauge(player1, 3)
	assert_true(game_logic.do_exceed(player1, get_cards_from_gauge(player1, 3)))
	advance_turn(player2)
	player1.discard_hand()
	player2.discard_hand()
	var card1 = give_player_specific_card(player1, "standard_normal_grasp")
	assert_true(game_logic.do_move(player1, [card1], 3))
	validate_positions(player1, 3, player2, 7)

##
## Wild Gang boost (fire suppression) tests
##

func test_lily_wildgang_boost_opponent_move_action_damage():
	# Opponent's move action (outside a strike) triggers 1 non-lethal damage per space.
	# After Lily boosts, turn passes to the opponent, so p2 acts directly.
	position_players(player1, 3, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	var wildgang = give_player_specific_card(player1, "lily_wildgang")
	assert_true(game_logic.do_boost(player1, wildgang))
	# p2 advances 2 spaces (7 -> 5): takes 2 damage from fire suppression.
	var p2c1 = give_player_specific_card(player2, "standard_normal_grasp")
	var p2c2 = give_player_specific_card(player2, "standard_normal_grasp")
	assert_true(game_logic.do_move(player2, [p2c1, p2c2], 5))
	validate_positions(player1, 3, player2, 5)
	validate_life(player1, 30, player2, 28)

func test_lily_wildgang_boost_opponent_retreat_action_damage():
	# Retreating in a move action also triggers the damage.
	position_players(player1, 3, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	var wildgang = give_player_specific_card(player1, "lily_wildgang")
	assert_true(game_logic.do_boost(player1, wildgang))
	# p2 retreats 2 spaces (7 -> 9): takes 2 damage.
	var p2c1 = give_player_specific_card(player2, "standard_normal_grasp")
	var p2c2 = give_player_specific_card(player2, "standard_normal_grasp")
	assert_true(game_logic.do_move(player2, [p2c1, p2c2], 9))
	validate_positions(player1, 3, player2, 9)
	validate_life(player1, 30, player2, 28)

func test_lily_wildgang_boost_opponent_pushed_no_damage():
	# Passive forced movement (push) does NOT trigger the fire suppression
	# damage; only the opponent's own active movement does.
	position_players(player1, 3, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	var wildgang = give_player_specific_card(player1, "lily_wildgang")
	assert_true(game_logic.do_boost(player1, wildgang))
	# Lily pushes the opponent 2 spaces away (7 -> 9): no damage.
	player1.push(2)
	validate_positions(player1, 3, player2, 9)
	validate_life(player1, 30, player2, 30)

func test_lily_wildgang_boost_opponent_pulled_no_damage():
	# Passive forced movement (pull) does NOT trigger the fire suppression
	# damage either; only the opponent's own active movement does.
	position_players(player1, 3, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	var wildgang = give_player_specific_card(player1, "lily_wildgang")
	assert_true(game_logic.do_boost(player1, wildgang))
	# Lily pulls the opponent 2 spaces closer (7 -> 5): no damage.
	player1.pull(2)
	validate_positions(player1, 3, player2, 5)
	validate_life(player1, 30, player2, 30)

func test_lily_wildgang_boost_lethal_can_kill():
	# The fire suppression damage is lethal: it can reduce the opponent to 0
	# life and end the game (it never stuns and is not blocked by armor).
	position_players(player1, 3, player2, 7)
	player2.life = 2
	player1.discard_hand()
	player2.discard_hand()
	var wildgang = give_player_specific_card(player1, "lily_wildgang")
	assert_true(game_logic.do_boost(player1, wildgang))
	player2.retreat(10)
	assert_eq(player2.life, 0)
	assert_true(game_logic.game_over)
	validate_positions(player1, 3, player2, 9)

func test_lily_wildgang_boost_no_damage_without_boost():
	# Without the boost, moving deals no damage.
	position_players(player1, 3, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	advance_turn(player1)
	var p2c1 = give_player_specific_card(player2, "standard_normal_grasp")
	var p2c2 = give_player_specific_card(player2, "standard_normal_grasp")
	assert_true(game_logic.do_move(player2, [p2c1, p2c2], 5))
	validate_positions(player1, 3, player2, 5)
	validate_life(player1, 30, player2, 30)

func test_lily_magicbullet_wild_swing_rangeup():
	# Wild-swinging Magic Bullet from top of deck with gauge to pay:
	# its before effect (range becomes 2-6) should apply.
	position_players(player1, 5, player2, 8)  # distance 3
	player1.discard_hand()
	player2.discard_hand()
	var gauge_ids = give_gauge(player1, 2)
	set_player_topdeck(player1, "lily_magicbullet")
	execute_strike(player1, player2, -1, "standard_normal_grasp",
			false, false, [gauge_ids], [])
	# Magic Bullet power 7 hits p2 from range 3 (2-6); p2's grasp (range 1) misses.
	validate_life(player1, 30, player2, 23)

func test_lily_discard_range_ignores_boost_range_for_both_cards():
	# Both range-based discard effects must carry the character-only marker.
	# This prevents a range boost such as Fire Suppression from making an
	# otherwise out-of-range normal card eligible for the discard choice.
	var card_db = CardDataManager
	for card_id in ["lily_densefire", "lily_wildgang"]:
		var card_def = card_db.get_card(card_id)
		var discard_effect = card_def["effects"][0]
		assert_true(discard_effect.get("range_only_character_effects", false))

func test_lily_densefire_discard_range_counts_only_passive():
	# At distance 4, a normal grasp is only range 1-2 after Lily's passive.
	# Fire Suppression's +0-3 attack range must not make it discardable.
	position_players(player1, 5, player2, 9)
	player1.discard_hand()
	player2.discard_hand()
	var wildgang = give_player_specific_card(player1, "lily_wildgang")
	assert_true(game_logic.do_boost(player1, wildgang))
	advance_turn(player2)
	give_player_specific_card(player1, "standard_normal_grasp")
	give_player_specific_card(player1, "standard_normal_grasp")
	execute_strike(player1, player2, "lily_densefire", "standard_normal_block",
			false, false, [[]], [[]])
	validate_life(player1, 30, player2, 29)

func test_lily_display_no_missing_timing():
	# The fire suppression boost and the retreat discount passive must render
	# without a "MISSING TIMING" prefix in their effect text.
	var wildgang_effect = null
	var card_def = CardDataManager.get_card("lily_wildgang")
	for e in card_def['boost']['effects']:
		if e['effect_type'] == "opponent_take_damage_on_move":
			wildgang_effect = e
	assert_true(wildgang_effect != null)
	var boost_text = GameStrings.get_effect_text(wildgang_effect)
	print("FIRE_SUPPRESSION_TEXT=[", boost_text, "]")
	assert_false(boost_text.contains("MISSING TIMING"))
	assert_true(boost_text.length() > 0)

	var deck = CardDataManager.get_deck_from_str_id("lily")
	var ability_text = GameStrings.get_effects_text(deck['ability_effects'])
	print("ABILITY_TEXT=[", ability_text, "]")
	assert_false(ability_text.contains("MISSING TIMING"))

