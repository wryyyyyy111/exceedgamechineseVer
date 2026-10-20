extends GutTest

const LocalGameScript = preload("res://scenes/core/local_game.gd")
const CardImageLoaderScript = preload("res://scenes/core/card_image_loader.gd")
const GameCardScript = preload("res://scenes/core/game_card.gd")

var game_logic
var image_loader
var default_deck = CardDataManager.get_deck_from_str_id("djanette")

var player1
var player2
var next_test_card_id := 50000

func next_id():
	var card_id = next_test_card_id
	next_test_card_id += 1
	return card_id

func default_game_setup():
	image_loader = CardImageLoaderScript.new(true)
	game_logic = LocalGameScript.new(image_loader)
	var seed_value = randi()
	game_logic.initialize_game(default_deck, default_deck, "p1", "p2", Enums.PlayerId.PlayerId_Player, seed_value)
	game_logic.draw_starting_hands_and_begin()
	game_logic.do_mulligan(game_logic.player, [])
	game_logic.do_mulligan(game_logic.opponent, [])
	player1 = game_logic.player
	player2 = game_logic.opponent
	game_logic.get_latest_events()

func before_each():
	default_game_setup()

func after_each():
	game_logic.teardown()
	game_logic.free()

func give_player_specific_card(player, def_id):
	var card_def = CardDataManager.get_card(def_id)
	var card_id = next_id()
	var card = GameCardScript.new(card_id, card_def, player.my_id)
	var card_db = game_logic.get_card_database()
	card_db._test_insert_card(card)
	player.hand.append(card)
	return card_id

func position_players(p1, loc1, p2, loc2):
	p1.arena_location = loc1
	p2.arena_location = loc2

func get_choice_index_for_position(pos):
	for i in range(game_logic.decision_info.limitation.size()):
		if game_logic.decision_info.limitation[i] == pos:
			return i
	assert(false, "Unable to find choice index")
	return 0

func advance_turn(player):
	assert_true(game_logic.do_prepare(player),
			"Player %s tried to prepare but could not (%s)." % [player.my_id + 1, game_or_decision_state_string()])
	if player.hand.size() > player.max_hand_size:
		var cards = []
		var to_discard = player.hand.size() - player.max_hand_size
		for i in range(to_discard):
			cards.append(player.hand[i].id)
		assert_true(game_logic.do_discard_to_max(player, cards))

func game_or_decision_state_string():
	if game_logic.game_state == Enums.GameState.GameState_PlayerDecision:
		return Enums.DecisionType.keys()[game_logic.decision_info.type]
	return Enums.GameState.keys()[game_logic.game_state]

func validate_positions(p1, l1, p2, l2):
	assert_eq(p1.arena_location, l1)
	assert_eq(p2.arena_location, l2)

func validate_life(p1, l1, p2, l2):
	assert_eq(p1.life, l1)
	assert_eq(p2.life, l2)

func test_start_of_turn_spellcircle_strike_with_circlecard_keeps_turn():
	position_players(player1, 1, player2, 7)
	var spellcard = give_player_specific_card(player1, "djanette_affliction")
	assert_eq(player1.hand.size(), 6)
	assert_true(game_logic.do_character_action(player1, []))
	assert_true(game_logic.do_relocate_card_from_hand(player1, [spellcard]))
	assert_true(game_logic.do_choice(player1, get_choice_index_for_position(6)))
	assert_eq(player1.hand.size(), 7)
	assert_eq(player1.set_aside_cards.size(), 1)

	advance_turn(player2)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)
	assert_true(game_logic.do_strike(player1, -1, true, 0))
	var opponent_attack = give_player_specific_card(player2, "standard_normal_assault")
	assert_true(game_logic.do_strike(player2, opponent_attack, false, -1))
	assert_true(game_logic.do_choice(player1, 1))
	assert_true(game_logic.do_choice(player1, 1))

	validate_positions(player1, 1, player2, 7)
	validate_life(player1, 30, player2, 27)
	assert_eq(player1.gauge.size(), 1)
	assert_eq(game_logic.active_turn_player, player1.my_id)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)

	advance_turn(player1)

func test_start_of_turn_spellcircle_strike_with_normal_skips_eot_draw():
	position_players(player1, 1, player2, 7)
	var spellcard = give_player_specific_card(player1, "djanette_affliction")
	assert_eq(player1.hand.size(), 6)
	assert_true(game_logic.do_character_action(player1, []))
	assert_true(game_logic.do_relocate_card_from_hand(player1, [spellcard]))
	assert_true(game_logic.do_choice(player1, get_choice_index_for_position(6)))
	assert_eq(player1.hand.size(), 7)
	assert_eq(player1.set_aside_cards.size(), 1)

	advance_turn(player2)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)
	var player_attack = give_player_specific_card(player1, "standard_normal_assault")
	assert_true(game_logic.do_strike(player1, player_attack, false, -1))
	var opponent_attack = give_player_specific_card(player2, "standard_normal_assault")
	assert_true(game_logic.do_strike(player2, opponent_attack, false, -1))

	validate_positions(player1, 3, player2, 5)
	validate_life(player1, 30, player2, 30)
	assert_eq(player1.gauge.size(), 0)
	assert_eq(player1.discards.size(), 2)
	assert_eq(player1.discards[0].id, spellcard)

	advance_turn(player2)