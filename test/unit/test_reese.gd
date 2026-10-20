extends ExceedGutTest

func who_am_i():
	return "reese"

##
## Reese passive tests
##
## Initial passive: when Reese stuns the opponent, she may pay 1 gauge to gain
## advantage (a GaugeForEffect prompt appears). Applies to both the first
## strike she initiates and to stuns she lands while defending.
## Exceeded passive: stunning the opponent immediately grants advantage; strikes
## she initiates on a turn after one in which a strike occurred get +2 power.
##
## Stun check in this engine: (power - armor) > guard.
## Knight Shockwave (hit: +2 power if fewer cards in hand, no advantage on hit)
## is used for the passive tests so any GainAdvantage event comes only from the
## passive. Cross (guard 0 / armor 0) is used as the stunned target.
##

func test_reese_passive_pay_gauge_on_stun_advantage():
	# Reese initiates with Knight Shockwave (2 + 2 from fewer cards = 4 power)
	# vs Cross (guard 0): stuns. With 1 gauge the prompt appears; paying it
	# grants advantage.
	# Decisions: on_stunned gauge (p1, pay 1), after move choice (p1, advance).
	position_players(player1, 1, player2, 2)
	player1.discard_hand()
	give_gauge(player1, 1)
	execute_strike(player1, player2, "reese_knightshockwave", "standard_normal_cross",
			false, false, [get_cards_from_gauge(player1, 1), 0], [])
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_Strike_GainAdvantage, player1)
	validate_life(player1, 30, player2, 26)

func test_reese_passive_no_gauge_no_prompt():
	# Stunning with no gauge available does not prompt and no advantage is
	# gained.
	position_players(player1, 1, player2, 2)
	player1.discard_hand()
	execute_strike(player1, player2, "reese_knightshockwave", "standard_normal_cross",
			false, false, [0], [])
	var events = game_logic.get_latest_events()
	validate_not_has_event(events, Enums.EventType.EventType_Strike_GainAdvantage, player1)
	validate_life(player1, 30, player2, 26)

func test_reese_passive_stun_as_defender():
	# Opponent initiates with Cross (speed 6, resolves first, 3 damage vs
	# Chivalry's guard 4 = no stun). Reese responds with Chivalry: stuns the
	# opponent (4 > 0) and the passive prompt appears (she pays 1 gauge).
	# Decision: on_stunned gauge (p1, pay 1).
	position_players(player1, 1, player2, 2)
	give_gauge(player1, 1)
	advance_turn(player1)
	var gauge_card = get_cards_from_gauge(player1, 1)
	execute_strike(player2, player1, "standard_normal_cross", "reese_chivalry",
			false, false, [], [gauge_card])
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_Strike_GainAdvantage, player1)
	validate_life(player1, 27, player2, 26)
	# The paid gauge card (Ballista) must have left the gauge.
	assert_false(player1.is_card_in_gauge(gauge_card[0]))

func test_reese_exceeded_passive_auto_advantage():
	# After exceeding, stunning the opponent grants advantage automatically
	# with no gauge payment prompt.
	position_players(player1, 1, player2, 2)
	give_gauge(player1, 3)
	assert_true(game_logic.do_exceed(player1, get_cards_from_gauge(player1, 3)))
	advance_turn(player2)
	player1.discard_hand()
	execute_strike(player1, player2, "reese_knightshockwave", "standard_normal_cross",
			false, false, [0], [])
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_Strike_GainAdvantage, player1)
	validate_life(player1, 30, player2, 26)

func test_reese_exceeded_strike_plus_two_after_battle():
	# Exceeded Reese: strikes she initiates get +2 power when a strike happened
	# on the previous turn (here, the opponent's turn had a strike).
	# Chivalry with +2 (6 power) vs Block (guard 3, armor 2): 6 - 2 = 4 > 3
	# stuns, dealing 4. Without the bonus (4 power) it would deal 2 and not
	# stun.
	position_players(player1, 1, player2, 2)
	give_gauge(player1, 3)
	assert_true(game_logic.do_exceed(player1, get_cards_from_gauge(player1, 3)))
	advance_turn(player2)
	# Reese's turn: a strike that does not stun (Grasp vs Block, 1 damage).
	execute_strike(player1, player2, "standard_normal_grasp", "standard_normal_block",
			false, false, [0], [[]])
	# Opponent's turn: a strike occurs (Grasp vs Block), making
	# last_turn_was_strike true for Reese's next turn.
	position_players(player1, 1, player2, 2)
	execute_strike(player2, player1, "standard_normal_grasp", "standard_normal_block",
			false, false, [0], [[]])
	# Reese's turn: Chivalry with +2 power.
	position_players(player1, 1, player2, 2)
	execute_strike(player1, player2, "reese_chivalry", "standard_normal_block",
			false, false, [], [[]])
	validate_life(player1, 29, player2, 25)

##
## Checkmate: attacks at range 1 cannot hit Reese
##

func test_reese_checkmate_dodge_range_one():
	# Reese defends with Checkmate (gauge cost 3); the opponent's Grasp
	# (range 1) cannot hit her. Checkmate then stuns the opponent.
	position_players(player1, 1, player2, 2)
	give_gauge(player1, 3)
	advance_turn(player1)
	execute_strike(player2, player1, "standard_normal_grasp", "reese_checkmate",
			false, false, [], [get_cards_from_gauge(player1, 3)])
	var events = game_logic.get_latest_events()
	validate_not_has_event(events, Enums.EventType.EventType_Strike_Stun, player1)
	validate_life(player1, 30, player2, 22)

##
## Chivalry: before advance 2
##

func test_reese_chivalry_before_advance_two():
	# Chivalry's before effect advances Reese 2 spaces before the attack
	# (1 -> 3), bringing the distance into range.
	position_players(player1, 1, player2, 5)
	execute_strike(player1, player2, "reese_chivalry", "standard_normal_block",
			false, false, [], [[]])
	validate_positions(player1, 3, player2, 5)
	validate_life(player1, 30, player2, 28)

##
## Chivalry boost "Support": +1 armor / +1 guard at the start of the
## opponent's turn only (counters accumulate; never on Reese's own turn).
##

func test_reese_chivalry_support_boost_opponent_turn_only():
	# Boosting passes the turn to the opponent; their turn start fires the
	# boost once (+1 armor/+1 guard). Reese's own turn start must not add.
	position_players(player1, 3, player2, 7)
	var chivalry = give_player_specific_card(player1, "reese_chivalry")
	assert_true(game_logic.do_boost(player1, chivalry))
	assert_eq(player1.bonus_armor_counters, 1)
	assert_eq(player1.bonus_guard_counters, 1)
	# Reese's own next turn start must not add more counters.
	advance_turn(player2)
	assert_eq(player1.bonus_armor_counters, 1)
	assert_eq(player1.bonus_guard_counters, 1)

func test_reese_chivalry_support_boost_accumulates_and_cleans_up():
	# The Support boost accumulates +1 armor/+1 guard per opponent turn start
	# (2 after the second opponent turn). After a strike, the boost card is
	# discarded and the counters reset.
	position_players(player1, 3, player2, 7)
	var chivalry = give_player_specific_card(player1, "reese_chivalry")
	assert_true(game_logic.do_boost(player1, chivalry))
	# Opponent turn 1 start: +1.
	assert_eq(player1.bonus_armor_counters, 1)
	# Reese's turn: no add.
	advance_turn(player2)
	assert_eq(player1.bonus_armor_counters, 1)
	# Opponent turn 2 start: +1 more (accumulates to 2).
	advance_turn(player1)
	assert_eq(player1.bonus_armor_counters, 2)
	assert_eq(player1.bonus_guard_counters, 2)
	# Reese's turn: strike with Knight Shockwave (stuns Cross, no gauge so no
	# passive prompt). After cleanup the boost is discarded and counters reset.
	advance_turn(player2)
	player1.discard_hand()
	position_players(player1, 1, player2, 2)
	execute_strike(player1, player2, "reese_knightshockwave", "standard_normal_cross",
			false, false, [0], [])
	assert_false(player1.is_card_in_continuous_boosts(chivalry))
	assert_eq(player1.bonus_armor_counters, 0)
	assert_eq(player1.bonus_guard_counters, 0)

##
## Valiant Guardian boost "Timing": +2 speed / +2 power only when Reese
## initiates; when the opponent initiates the boost is discarded.
##

func test_reese_valiantguardian_timing_boost_self_initiate():
	# Reese boosts Timing, then initiates: +2 power applies (Chivalry 4 + 2 = 6
	# vs Block: 6 - 2 = 4 > 3 guard -> stuns, dealing 4). Without the bonus it
	# would deal only 2 and not stun.
	position_players(player1, 3, player2, 7)
	var valiant = give_player_specific_card(player1, "reese_valiantguardian")
	assert_true(game_logic.do_boost(player1, valiant))
	advance_turn(player2)
	position_players(player1, 1, player2, 2)
	execute_strike(player1, player2, "reese_chivalry", "standard_normal_block",
			false, false, [], [[]])
	assert_false(player1.is_card_in_continuous_boosts(valiant))
	validate_life(player1, 30, player2, 26)

func test_reese_valiantguardian_timing_boost_discard_on_opponent_strike():
	# Opponent initiates: Timing is discarded before Reese sets a response.
	position_players(player1, 3, player2, 7)
	var valiant = give_player_specific_card(player1, "reese_valiantguardian")
	assert_true(game_logic.do_boost(player1, valiant))
	position_players(player1, 1, player2, 2)
	var opponent_attack = give_player_specific_card(player2, "standard_normal_grasp")
	assert_true(game_logic.do_strike(player2, opponent_attack, false, -1))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_Strike_Opponent_Response)
	assert_false(player1.is_card_in_continuous_boosts(valiant))
	assert_true(player1.is_card_in_discards(valiant))

##
## Supreme Glory: it is an Ultra, worth 2 force when paid as energy.
##

func test_reese_supremeglory_is_ultra_worth_two_force():
	# Supreme Glory is an Ultra card, so it counts as 2 energy when paid.
	var card_id = give_player_specific_card(player1, "reese_supremeglory")
	var force_value = game_logic.get_card_database().get_card_force_value(card_id)
	assert_eq(force_value, 2)

func test_reese_support_summary_tracks_guard_counters():
	var game_scene = load("res://scenes/game/game.tscn")
	var game_ui = game_scene.instantiate()
	game_ui.set_not_started_directly()
	add_child(game_ui)
	var ui_game_logic = game_ui.game_wrapper.current_game
	if ui_game_logic:
		ui_game_logic.teardown()
	var ui_image_loader = game_ui.image_loader
	ui_game_logic = load("res://scenes/core/local_game.gd").new(ui_image_loader)
	var seed_value = randi()
	ui_game_logic.initialize_game(
		CardDataManager.get_deck_from_str_id("reese"),
		CardDataManager.get_deck_from_str_id("reese"),
		"p1",
		"p2",
		Enums.PlayerId.PlayerId_Player,
		seed_value
	)
	ui_game_logic.draw_starting_hands_and_begin()
	assert_true(ui_game_logic.do_mulligan(ui_game_logic.player, []))
	assert_true(ui_game_logic.do_mulligan(ui_game_logic.opponent, []))
	ui_game_logic.get_latest_events()
	game_ui.game_wrapper.current_game = ui_game_logic

	var support_id = next_id()
	var support_def = CardDataManager.get_card("reese_chivalry")
	var support_card = GameCard.new(support_id, support_def, ui_game_logic.player.my_id)
	ui_game_logic.get_card_database()._test_insert_card(support_card)
	ui_game_logic.player.continuous_boosts.append(support_card)
	ui_game_logic.player.bonus_armor_counters = 2
	ui_game_logic.player.bonus_guard_counters = 2

	game_ui._update_buttons(true)
	var boost_text = game_ui.get_node("PlayerBoostZone").boost_effects.text
	assert_true(boost_text.find("累积: 护甲 +2, 霸体 +2") != -1)

	ui_game_logic.teardown()
	game_ui.queue_free()
