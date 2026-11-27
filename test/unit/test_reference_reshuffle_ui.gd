extends GutTest

var game_ui : Game

func before_each():
	game_ui = load("res://scenes/game/game.tscn").instantiate()
	game_ui.set_not_started_directly()
	add_child(game_ui)
	game_ui.add_child(game_ui.game_wrapper)
	game_ui.set_process(false)
	game_ui.image_loader.test_mode = true
	var deck = CardDataManager.get_deck_from_str_id("solbadguy")
	game_ui.player_deck = deck
	game_ui.opponent_deck = deck
	var game_logic = LocalGame.new(game_ui.image_loader)
	game_logic.initialize_game(deck, deck, "p1", "p2", Enums.PlayerId.PlayerId_Player, 1)
	game_logic.draw_starting_hands_and_begin()
	assert_true(game_logic.do_mulligan(game_logic.player, []))
	assert_true(game_logic.do_mulligan(game_logic.opponent, []))
	game_logic.get_latest_events()
	game_ui.game_wrapper.current_game = game_logic

func after_each():
	game_ui.queue_free()
	await get_tree().process_frame

func _apply_reshuffle(player_id : Enums.PlayerId) -> Array:
	var logic = game_ui.game_wrapper.current_game
	var player = logic.player if player_id == Enums.PlayerId.PlayerId_Player else logic.opponent
	var discarded_card = player.hand[0]
	player.discard([discarded_card.id])
	logic.get_latest_events()
	player.reshuffle_discard(true)
	var events = logic.get_latest_events().filter(func(event):
		return event["event_type"] == Enums.EventType.EventType_ReshuffleDiscard)
	assert_eq(events.size(), 1)
	game_ui._on_reshuffle_discard(events[0])
	return events[0]["extra_info"]

func _assert_counts(zone : Node, player_id : Enums.PlayerId, snapshot = null):
	for card in zone.get_children():
		if card.card_id < game_ui.ReferenceScreenIdRangeStart:
			continue
		var logic_card = game_ui.game_wrapper.get_card_database().get_card(
			card.card_id - game_ui.ReferenceScreenIdRangeStart)
		var expected = game_ui.game_wrapper.count_cards_in_deck_and_hand(
			player_id, logic_card.definition["id"], snapshot)
		assert_eq(card.get_remaining_count(), expected, logic_card.definition["id"])

func test_player_reference_switches_snapshot_and_reopens_current():
	await game_ui._on_player_reference_button_pressed()
	assert_true(game_ui.card_popout_parent.get_child(0).toggle_button.disabled)
	var snapshot = _apply_reshuffle(Enums.PlayerId.PlayerId_Player)
	await game_ui._on_player_reference_button_pressed()
	var popout = game_ui.card_popout_parent.get_child(0)
	assert_true(popout.toggle_container.visible)
	assert_false(popout.toggle_button.disabled)
	_assert_counts(game_ui.get_node("AllCards/PlayerAllCopy"), Enums.PlayerId.PlayerId_Player)

	popout.toggle_button.pressed.emit()
	await get_tree().process_frame
	assert_eq(game_ui.popout_type_showing, Game.CardPopoutType.CardPopoutType_ReferencePlayer)
	assert_true(game_ui.player_reference_popout_toggle)
	popout = game_ui.card_popout_parent.get_child(0)
	assert_eq(popout.toggle_button.text, "展示当前卡牌")
	_assert_counts(game_ui.get_node("AllCards/PlayerAllCopy"), Enums.PlayerId.PlayerId_Player, snapshot)
	for card in game_ui.get_node("AllCards/PlayerAllCopy").get_children():
		assert_false(card.hand_icons_obj.visible)

	popout.toggle_button.pressed.emit()
	await get_tree().process_frame
	assert_false(game_ui.player_reference_popout_toggle)
	_assert_counts(game_ui.get_node("AllCards/PlayerAllCopy"), Enums.PlayerId.PlayerId_Player)
	await game_ui._on_player_reference_button_pressed(true, true)
	game_ui.close_popout()
	await game_ui._on_player_reference_button_pressed()
	assert_false(game_ui.player_reference_popout_toggle)

func test_players_keep_independent_history_and_opponent_toggle():
	var player_snapshot = _apply_reshuffle(Enums.PlayerId.PlayerId_Player)
	await game_ui._on_opponent_reference_button_pressed()
	assert_true(game_ui.card_popout_parent.get_child(0).toggle_button.disabled)
	var opponent_snapshot = _apply_reshuffle(Enums.PlayerId.PlayerId_Opponent)
	await game_ui._on_opponent_reference_button_pressed()
	game_ui.card_popout_parent.get_child(0).toggle_button.pressed.emit()
	await get_tree().process_frame
	assert_eq(game_ui.popout_type_showing, Game.CardPopoutType.CardPopoutType_ReferenceOpponent)
	assert_true(game_ui.reference_popout_toggle)
	_assert_counts(game_ui.get_node("AllCards/OpponentAllCopy"), Enums.PlayerId.PlayerId_Opponent, opponent_snapshot)
	await game_ui._on_player_reference_button_pressed(true, true)
	_assert_counts(game_ui.get_node("AllCards/PlayerAllCopy"), Enums.PlayerId.PlayerId_Player, player_snapshot)
	assert_eq(game_ui.opponent_cards_before_reshuffle, opponent_snapshot)
	await game_ui._on_opponent_reference_button_pressed(false, true)
	assert_false(game_ui.card_popout_parent.get_child(0).toggle_container.visible)

func test_player_deck_discard_swap_also_enables_history():
	var logic = game_ui.game_wrapper.current_game
	logic.player.swap_deck_and_discard()
	var events = logic.get_latest_events().filter(func(event):
		return event["event_type"] == Enums.EventType.EventType_SwapDeckAndDiscard)
	assert_eq(events.size(), 1)
	game_ui._on_swap_deck_and_discard(events[0])
	await game_ui._on_player_reference_button_pressed(true, true)
	assert_false(game_ui.card_popout_parent.get_child(0).toggle_button.disabled)
	_assert_counts(game_ui.get_node("AllCards/PlayerAllCopy"), Enums.PlayerId.PlayerId_Player, events[0]["extra_info"])

func test_empty_snapshot_does_not_fall_back_to_current_counts():
	game_ui._on_reshuffle_discard({
		"event_player": Enums.PlayerId.PlayerId_Player,
		"extra_info": [],
	})
	await game_ui._on_player_reference_button_pressed(true, true)
	for card in game_ui.get_node("AllCards/PlayerAllCopy").get_children():
		if card.card_id >= game_ui.ReferenceScreenIdRangeStart:
			assert_eq(card.get_remaining_count(), 0)
