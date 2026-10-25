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

func _reading_event() -> Dictionary:
	return {
		"event_type": Enums.EventType.EventType_ReadingNormal,
		"event_player": Enums.PlayerId.PlayerId_Player,
		"number": 0,
	}

func _set_name_decision(decision_type : Enums.DecisionType):
	var game_logic = game_ui.game_wrapper.current_game
	game_logic.game_state = Enums.GameState.GameState_PlayerDecision
	game_logic.decision_info.clear()
	game_logic.decision_info.player = Enums.PlayerId.PlayerId_Player
	game_logic.decision_info.type = decision_type
	game_logic.decision_info.amount = 1

func _assert_deck_is_browsable():
	await game_ui._on_opponent_reference_button_pressed()
	assert_eq(game_ui.card_popout_parent.get_child_count(), 1)
	var popout = game_ui.card_popout_parent.get_child(0)
	assert_false(popout.instruction_box.visible)
	assert_false(game_ui.popout_show_normal_only())
	assert_gt(popout.used_slots, 8)
	var has_special = false
	for slot_index in range(popout.used_slots):
		var card = popout.get_spot(slot_index).get_child(0)
		if card.card_id < game_ui.ReferenceScreenIdRangeStart:
			continue
		var logic_card = game_ui.game_wrapper.get_card_database().get_card(
			card.card_id - game_ui.ReferenceScreenIdRangeStart)
		if logic_card.definition["type"] == "special":
			has_special = true
	assert_true(has_special, "Deck browsing must include specials, not only Reading's normals.")

func test_completed_reading_does_not_leave_naming_ui_after_restore():
	game_ui.restore_fast_forwarding = true
	game_ui._on_name_opponent_card_begin(_reading_event())
	game_ui.restore_fast_forwarding = false
	game_ui._sync_ui_state_after_restore()

	assert_null(game_ui.popout_instruction_info)
	assert_eq(game_ui.ui_state, game_ui.UIState.UIState_PickTurnAction)
	await _assert_deck_is_browsable()
	game_ui.close_popout()
	await _assert_deck_is_browsable()

func test_historical_reading_does_not_replace_a_later_selection():
	var later_instructions = {
		"popout_type": game_ui.CardPopoutType.CardPopoutType_GaugeOpponent,
		"instruction_text": "Choose gauge",
	}
	game_ui.popout_instruction_info = later_instructions
	game_ui.restore_fast_forwarding = true
	game_ui._on_name_opponent_card_begin(_reading_event())
	assert_eq(game_ui.popout_instruction_info, later_instructions)

func test_pending_reading_is_restored_even_from_an_interaction_state():
	_set_name_decision(Enums.DecisionType.DecisionType_ReadingNormal)
	game_ui.ui_state = game_ui.UIState.UIState_PickTurnAction
	game_ui.restore_fast_forwarding = true
	game_ui._on_name_opponent_card_begin(_reading_event())
	assert_null(game_ui.popout_instruction_info)
	game_ui.restore_fast_forwarding = false
	game_ui._sync_ui_state_after_restore()

	assert_eq(game_ui.ui_state, game_ui.UIState.UIState_SelectCards)
	assert_eq(game_ui.ui_sub_state, game_ui.UISubState.UISubState_SelectCards_DiscardFromReference)
	assert_true(game_ui.popout_show_normal_only())
	await game_ui._on_opponent_reference_button_pressed()
	var popout = game_ui.card_popout_parent.get_child(0)
	assert_true(popout.instruction_box.visible)
	assert_false(popout.instruction_button_cancel.visible)
	assert_eq(popout.used_slots, 8)

func test_pending_parry_allows_all_cards_and_fake_name():
	_set_name_decision(Enums.DecisionType.DecisionType_NameCard_OpponentDiscards)
	game_ui._sync_ui_state_after_restore()

	assert_false(game_ui.popout_show_normal_only())
	assert_true(game_ui.popout_instruction_info["cancel_visible"])
	assert_eq(game_ui.ui_sub_state, game_ui.UISubState.UISubState_SelectCards_DiscardFromReference)

func test_pending_sidestep_still_limits_selection_to_normals():
	_set_name_decision(Enums.DecisionType.DecisionType_Sidestep)
	game_ui._sync_ui_state_after_restore()

	assert_true(game_ui.popout_show_normal_only())
	assert_false(game_ui.popout_instruction_info["cancel_visible"])

func test_pending_zero_vector_still_allows_a_nonexistent_card():
	_set_name_decision(Enums.DecisionType.DecisionType_ZeroVector)
	game_ui._sync_ui_state_after_restore()

	assert_false(game_ui.popout_show_normal_only())
	assert_true(game_ui.popout_instruction_info["cancel_visible"])

func test_opponent_pending_reading_does_not_restore_local_selection():
	_set_name_decision(Enums.DecisionType.DecisionType_ReadingNormal)
	game_ui.game_wrapper.current_game.decision_info.player = Enums.PlayerId.PlayerId_Opponent
	game_ui.ui_state = game_ui.UIState.UIState_PickTurnAction
	game_ui.restore_fast_forwarding = true
	game_ui._on_name_opponent_card_begin(_reading_event())
	game_ui.restore_fast_forwarding = false
	game_ui._sync_ui_state_after_restore()

	assert_null(game_ui.popout_instruction_info)
	assert_eq(game_ui.ui_state, game_ui.UIState.UIState_WaitingOnOpponent)
	await _assert_deck_is_browsable()

func test_observer_does_not_restore_a_player_naming_prompt():
	_set_name_decision(Enums.DecisionType.DecisionType_ReadingNormal)
	game_ui.observer_mode = true
	game_ui.ui_state = game_ui.UIState.UIState_PickTurnAction
	game_ui.restore_fast_forwarding = true
	game_ui._on_name_opponent_card_begin(_reading_event())
	game_ui.restore_fast_forwarding = false
	game_ui._sync_ui_state_after_restore()

	assert_null(game_ui.popout_instruction_info)
	assert_eq(game_ui.ui_state, game_ui.UIState.UIState_WaitingOnOpponent)

func test_live_reading_still_enters_normal_only_selection():
	_set_name_decision(Enums.DecisionType.DecisionType_ReadingNormal)
	game_ui._on_name_opponent_card_begin(_reading_event())

	assert_eq(game_ui.ui_state, game_ui.UIState.UIState_SelectCards)
	assert_eq(game_ui.ui_sub_state, game_ui.UISubState.UISubState_SelectCards_DiscardFromReference)
	assert_true(game_ui.popout_show_normal_only())
	assert_false(game_ui.popout_instruction_info["cancel_visible"])
