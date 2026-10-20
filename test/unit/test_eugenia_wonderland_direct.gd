extends GutTest

const LocalGameScript = preload("res://scenes/core/local_game.gd")
const CardImageLoaderScript = preload("res://scenes/core/card_image_loader.gd")

var game_logic
var image_loader
var next_test_card_id = 50000
var player1
var player2

func next_id():
	next_test_card_id += 1
	return next_test_card_id - 1

func before_each():
	var default_deck = CardDataManager.get_deck_from_str_id("eugenia")
	image_loader = CardImageLoaderScript.new(true)
	game_logic = LocalGameScript.new(image_loader)
	game_logic.initialize_game(default_deck, default_deck, "p1", "p2", Enums.PlayerId.PlayerId_Player, 1)
	game_logic.draw_starting_hands_and_begin()
	game_logic.do_mulligan(game_logic.player, [])
	game_logic.do_mulligan(game_logic.opponent, [])
	player1 = game_logic.player
	player2 = game_logic.opponent
	game_logic.get_latest_events()

func test_skin_deck_keeps_base_character_id_metadata():
	var skin_deck = CardDataManager.get_deck_from_str_id("eugenia_1")
	assert_not_null(skin_deck)
	if not skin_deck:
		return
	assert_eq(skin_deck.get("id", ""), "eugenia_1")
	assert_eq(skin_deck.get("base_id", ""), "eugenia")

func test_skin_deck_uses_base_character_id_in_local_game_logic():
	var skin_deck = CardDataManager.get_deck_from_str_id("eugenia_1")
	assert_not_null(skin_deck)
	if not skin_deck:
		return

	var skin_loader = CardImageLoaderScript.new(true)
	var skin_game = LocalGameScript.new(skin_loader)
	skin_game.initialize_game(skin_deck, skin_deck, "p1", "p2", Enums.PlayerId.PlayerId_Player, 1)

	assert_eq(skin_game.player.deck_def.get("id", ""), "eugenia")
	assert_eq(skin_game.opponent.deck_def.get("id", ""), "eugenia")

	skin_game.teardown()
	skin_game.free()

func after_each():
	game_logic.teardown()
	game_logic.free()

func give_player_specific_card(player, def_id):
	var card_def = CardDataManager.get_card(def_id)
	var card_id = next_id()
	var card = GameCard.new(card_id, card_def, player.my_id)
	var card_db = game_logic.get_card_database()
	card_db._test_insert_card(card)
	player.hand.append(card)
	return card_id

func position_players(p1, loc1, p2, loc2):
	p1.arena_location = loc1
	p2.arena_location = loc2

func advance_turn(player):
	assert_true(game_logic.do_prepare(player))

func do_and_validate_strike(player, card_id):
	assert_true(game_logic.can_do_strike(player))
	assert_true(game_logic.do_strike(player, card_id, false, -1))
	assert_true(game_logic.game_state == Enums.GameState.GameState_Strike_Opponent_Response or game_logic.game_state == Enums.GameState.GameState_PlayerDecision)

func do_strike_response(player, card_id):
	assert_true(game_logic.do_strike(player, card_id, false, -1))

func process_remaining_decisions_until_done():
	while game_logic.game_state == Enums.GameState.GameState_PlayerDecision:
		var player = player1
		if game_logic.decision_info.player == player2.my_id:
			player = player2
		match game_logic.decision_info.type:
			Enums.DecisionType.DecisionType_ChooseToDiscard:
				assert_true(game_logic.do_choose_to_discard(player, [] if game_logic.decision_info.can_pass else [player.hand[0].id]))
			Enums.DecisionType.DecisionType_EffectChoice:
				assert_true(game_logic.do_choice(player, 0))
			Enums.DecisionType.DecisionType_ForceForArmor:
				assert_true(game_logic.do_force_for_armor(player, []))
			Enums.DecisionType.DecisionType_PayStrikeCost_Required, Enums.DecisionType.DecisionType_PayStrikeCost_CanWild:
				assert_true(game_logic.do_pay_strike_cost(player, [], false))
			_:
				fail_test("Unhandled decision type %s" % Enums.DecisionType.keys()[game_logic.decision_info.type])
				return

func execute_strike(init_player, def_player, init_card_id, def_card_id):
	do_and_validate_strike(init_player, init_card_id)
	do_strike_response(def_player, def_card_id)
	process_remaining_decisions_until_done()

func test_wonderland_direct_strike_leaves_set_aside_on_hit():
	position_players(player1, 3, player2, 5)
	player1.exceeded = true
	var wonderland_attack_id = give_player_specific_card(player1, "standard_normal_assault")
	var wonderland_attack = game_logic.card_db.get_card(wonderland_attack_id)
	player1.remove_card_from_hand(wonderland_attack_id, false, false)
	player1.add_to_set_aside(wonderland_attack)
	var defend_card_id = give_player_specific_card(player2, "standard_normal_grasp")

	execute_strike(player1, player2, wonderland_attack_id, defend_card_id)

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
	var init_card_id = give_player_specific_card(player2, "standard_normal_assault")

	execute_strike(player2, player1, init_card_id, wonderland_attack_id)

	assert_false(player1.is_card_in_set_aside(wonderland_attack_id))
	assert_true(player1.is_card_in_discards(wonderland_attack_id))
	assert_false(player1.is_card_in_gauge(wonderland_attack_id))