extends GutTest

var game_ui : Game
var next_test_card_id = 61000

func next_id() -> int:
	next_test_card_id += 1
	return next_test_card_id - 1

func _drain_latest_events():
	var saved_fast_forward = game_ui.restore_fast_forwarding
	game_ui.restore_fast_forwarding = true
	while true:
		var events = game_ui.game_wrapper.current_game.get_latest_events()
		if events.size() == 0 and game_ui.events_to_process.size() == 0:
			break
		if events.size() > 0:
			game_ui._handle_events(events)
		elif game_ui.events_to_process.size() > 0:
			var remaining_events = game_ui.events_to_process
			game_ui.events_to_process = []
			game_ui._handle_events(remaining_events)
	game_ui.restore_fast_forwarding = saved_fast_forward

func give_player_specific_card(player : Player, def_id : String) -> int:
	var card_def = CardDataManager.get_card(def_id)
	var card_id = next_id()
	var card = GameCard.new(card_id, card_def, player.my_id)
	var card_db = game_ui.game_wrapper.current_game.get_card_database()
	card_db._test_insert_card(card)
	player.hand.append(card)
	return card_id

func add_card_ui_to_hand(card_id : int, is_player : bool) -> void:
	var current_game = game_ui.game_wrapper.current_game
	var logic_card : GameCard = current_game.get_card_database().get_card(card_id)
	var deck_def = game_ui.player_deck if is_player else game_ui.opponent_deck
	var deck_zone = game_ui.get_node("AllCards/PlayerDeck") if is_player else game_ui.get_node("AllCards/OpponentDeck")
	await game_ui.create_card(
		card_id,
		logic_card.definition,
		logic_card.get_image_url_index_data(),
		deck_def["image_resources"]["cardback"]["url"],
		deck_zone,
		not is_player,
		logic_card.definition["display_name"],
		logic_card.definition["boost"]["display_name"]
	)
	game_ui.draw_card(card_id, is_player)

func add_transform(player : Player, def_id : String):
	var card_id = give_player_specific_card(player, def_id)
	var card = game_ui.game_wrapper.current_game.get_card_database().get_card(card_id)
	await add_card_ui_to_hand(card_id, player.my_id == Enums.PlayerId.PlayerId_Player)
	player.add_to_transforms(card)
	player.hand.remove_at(player.hand.size() - 1)
	_drain_latest_events()

func setup_game_ui():
	var game_scene = load("res://scenes/game/game.tscn")
	game_ui = game_scene.instantiate()
	game_ui.set_not_started_directly()
	add_child(game_ui)
	await get_tree().process_frame
	game_ui.image_loader.test_mode = true
	var image_loader = game_ui.image_loader
	var game_logic = LocalGame.new(image_loader)
	var seed_value = randi()
	var djanette_deck = CardDataManager.get_deck_from_str_id("djanette")
	game_logic.initialize_game(
		djanette_deck,
		djanette_deck,
		"p1",
		"p2",
		Enums.PlayerId.PlayerId_Player,
		seed_value
	)
	game_logic.draw_starting_hands_and_begin()
	assert_true(game_logic.do_mulligan(game_logic.player, []))
	assert_true(game_logic.do_mulligan(game_logic.opponent, []))
	game_logic.get_latest_events()
	game_ui.player_deck = djanette_deck
	game_ui.opponent_deck = djanette_deck
	game_ui.game_wrapper.current_game = game_logic
	game_ui.ai_player = AIPlayer.new(game_logic, game_logic.opponent)
	await game_ui.setup_characters()
	await game_ui.spawn_all_cards()
	game_ui.first_run()
	game_ui.change_ui_state(game_ui.UIState.UIState_PickTurnAction, game_ui.UISubState.UISubState_None)
	game_ui._update_buttons()

func before_each() -> void:
	await setup_game_ui()

func after_each():
	if game_ui:
		var ai_player = game_ui.ai_player
		game_ui.free()
		if ai_player:
			ai_player.ai_policy.free()
		game_ui = null

func test_topdeck_then_immediate_draw_does_not_leave_card_visually_in_deck():
	var game_logic = game_ui.game_wrapper.current_game
	var player = game_logic.player
	var card_id = give_player_specific_card(player, "djanette_affliction")
	await add_card_ui_to_hand(card_id, true)
	var card_ui = game_ui.find_card_on_board(card_id)
	card_ui.finish_animation_immediately()

	player.move_card_from_hand_to_deck(card_id)
	player.draw(1)
	_drain_latest_events()
	card_ui.finish_animation_immediately()

	assert_true(player.is_card_in_hand(card_id))
	assert_eq(card_ui.get_parent(), game_ui.get_hand_zone(true))
	assert_eq(card_ui.state, CardBase.CardState.CardState_InHand)

func test_shortcut_character_action_to_spell_circle_completes_ui_flow():
	var game_logic = game_ui.game_wrapper.current_game
	var player = game_ui.game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	var spellcard = give_player_specific_card(player, "djanette_affliction")
	await add_card_ui_to_hand(spellcard, true)

	game_ui.selected_cards = [game_ui.find_card_on_board(spellcard)]
	game_ui._on_shortcut_character_action_pressed(0)

	assert_eq(game_ui.prepared_character_action_data.get("effect_type", ""), "gauge_from_hand")
	assert_eq(game_ui.ui_state, game_ui.UIState.UIState_WaitForGameServer)

	_drain_latest_events()

	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect)
	assert_eq(game_ui.ui_state, game_ui.UIState.UIState_SelectArenaLocation)
	assert_eq(game_ui.prepared_character_action_data.get("effect_type", ""), "gauge_from_hand")

	game_ui._on_arena_location_pressed(6)
	assert_eq(game_ui.ui_state, game_ui.UIState.UIState_WaitForGameServer)

	_drain_latest_events()

	assert_eq(game_logic.active_turn_player, Enums.PlayerId.PlayerId_Opponent)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	assert_eq(game_ui.ui_state, game_ui.UIState.UIState_WaitingOnOpponent)
	assert_eq(game_ui.prepared_character_action_data, {})
	assert_eq(player.set_aside_cards.size(), 1)
	assert_eq(player.set_aside_cards[0].id, spellcard)

func test_shortcut_character_action_to_diabolic_aura_cancel_strike_completes_ui_flow():
	var game_logic = game_ui.game_wrapper.current_game
	var player = game_ui.game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	player.exceed()
	_drain_latest_events()
	add_transform(player, "djanette_blackdeath")
	var aura_card = give_player_specific_card(player, "standard_normal_grasp")
	await add_card_ui_to_hand(aura_card, true)

	game_ui.selected_cards = [game_ui.find_card_on_board(aura_card)]
	game_ui._on_shortcut_character_action_pressed(0)

	assert_eq(game_ui.prepared_character_action_data.get("effect_type", ""), "gauge_from_hand")

	_drain_latest_events()
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ForceForEffect)
	assert_eq(game_ui.ui_state, game_ui.UIState.UIState_SelectCards)
	assert_eq(game_ui.ui_sub_state, game_ui.UISubState.UISubState_SelectCards_ForceForEffect)

	game_ui._on_instructions_cancel_button_pressed()
	assert_eq(game_ui.ui_state, game_ui.UIState.UIState_WaitForGameServer)

	_drain_latest_events()

	assert_eq(game_logic.active_turn_player, Enums.PlayerId.PlayerId_Opponent)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	assert_eq(game_ui.ui_state, game_ui.UIState.UIState_WaitingOnOpponent)
	assert_eq(game_ui.prepared_character_action_data, {})
	assert_eq(player.set_aside_cards.size(), 1)
	assert_eq(player.set_aside_cards[0].id, aura_card)