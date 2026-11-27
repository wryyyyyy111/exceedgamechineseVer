extends ExceedGutTest

func who_am_i():
	return "doomies"
	
## Legion - [2G] 1-3/1/1/0/6; Infused: +2 Armor. Hit: +1 Power per card in your hand.
# Primarily tested because this hit effect existed but previously expected a maximum value.

func test_doomies_legion_huge_hand():
	position_players(player1, 2, player2, 6)
	var gauge_cards = give_gauge(player1, 2)
	player1.draw(10)
	var hand_size = len(player1.hand)
	
	execute_strike(player1, player2, "doomies_legion", "standard_normal_dive",
		false, false, [[], gauge_cards]) # decline infusion and pay gauge

	validate_life(player1, 25, player2, 29 - hand_size)
	validate_positions(player1, 2, player2, 3)
	
	advance_turn(player2)

func _setup_exceeded_infused_legion_hit() -> int:
	position_players(player1, 3, player2, 6)
	player1.exceeded = true
	player1.infused = true
	player2.infused = true
	var gauge_cards = give_gauge(player1, 2)
	var cards = give_specific_cards(player1, "doomies_legion", player2, "standard_normal_sweep")
	do_and_validate_strike(player1, cards[0])
	do_strike_response(player2, cards[1])
	assert_true(game_logic.do_pay_strike_cost(player1, gauge_cards, false))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseSimultaneousEffect)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.decision_info.choice.size(), 2)
	return player1.hand.size()

func test_doomies_legion_hit_choice_text():
	_setup_exceeded_infused_legion_hit()
	var game_ui = Game.new()
	game_ui.game_wrapper.current_game = game_logic
	game_ui.ChoiceTagRegex.compile("\\[.*\\]")
	var texts = []
	for choice in game_logic.decision_info.choice:
		texts.append(game_ui.get_effect_text_with_card_name(choice, ""))
	assert_eq(texts, ["你每有一张手牌，威力+1。", "抽1"])
	game_ui.game_wrapper.free()
	game_ui.free()

func _resolve_legion_hit_order(draw_first: bool):
	var hand_size = _setup_exceeded_infused_legion_hit()
	var first_effect = StrikeEffects.Draw if draw_first else StrikeEffects.PowerupPerCardInHand
	var choices = game_logic.decision_info.choice
	var choice_index = -1
	for i in range(choices.size()):
		if choices[i]["effect_type"] == first_effect:
			choice_index = i
	assert_ne(choice_index, -1)
	assert_true(game_logic.do_choice(player1, choice_index))
	assert_eq(player1.hand.size(), hand_size + 1)
	var expected_damage = 1 + hand_size + (1 if draw_first else 0)
	validate_life(player1, 26, player2, 30 - expected_damage)
	assert_null(game_logic.active_strike)
	advance_turn(player2)

func test_doomies_legion_hit_power_before_draw():
	_resolve_legion_hit_order(false)

func test_doomies_legion_hit_draw_before_power():
	_resolve_legion_hit_order(true)

## Boom! - [3G] 1/3/3/0/3; Before: Close 5. For each space you couldn't move, +1 Power.
##		After: Push 1 per damage dealt.

func test_doomies_boom_small_push():
	position_players(player1, 1, player2, 5)
	var gauge_cards = give_gauge(player1, 3)
	
	execute_strike(player1, player2, "doomies_boom", "standard_normal_block",
		false, false, [[], gauge_cards], [[]]) # decline infusion and pay gauge, don't spend for block
	
	# P1 closes 3 spaces from 1 to 4, so gains 2 power -> 5 total, so p2 takes 3 and is pushed from 5 to 8

	validate_life(player1, 30, player2, 27)
	validate_positions(player1, 4, player2, 8)
	
	advance_turn(player2)

func test_doomies_boom_huge_push():
	position_players(player1, 1, player2, 2)
	var gauge_cards = give_gauge(player1, 3)
	
	execute_strike(player1, player2, "doomies_boom", "standard_normal_sweep",
		false, false, [[], gauge_cards]) # decline infusion and pay gauge
	
	# P1 doesn't move, so gains 5 power -> 8 total, so p2 takes 3 and is pushed from 2 to 9

	validate_life(player1, 30, player2, 22)
	validate_positions(player1, 1, player2, 9)
	
	advance_turn(player2)
