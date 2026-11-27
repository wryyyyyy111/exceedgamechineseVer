extends GutTest

const ExceedSummaryText = "觉醒：速度+1，威力+1"

var game_ui : Game

func setup_game_ui(player_id : String, opponent_id : String):
	var game_scene = load("res://scenes/game/game.tscn")
	game_ui = game_scene.instantiate()
	game_ui.set_not_started_directly()
	add_child(game_ui)
	var game_logic = load("res://scenes/core/local_game.gd").new(game_ui.image_loader)
	game_logic.initialize_game(
		CardDataManager.get_deck_from_str_id(player_id),
		CardDataManager.get_deck_from_str_id(opponent_id),
		"p1", "p2", Enums.PlayerId.PlayerId_Player, randi())
	game_logic.draw_starting_hands_and_begin()
	assert_true(game_logic.do_mulligan(game_logic.player, []))
	assert_true(game_logic.do_mulligan(game_logic.opponent, []))
	game_logic.get_latest_events()
	game_ui.game_wrapper.current_game = game_logic

func after_each():
	if game_ui:
		game_ui.queue_free()
		game_ui = null
		await get_tree().process_frame

func _setup_extra_cards(player_id : String, opponent_id : String):
	setup_game_ui(player_id, opponent_id)
	game_ui.set_process(false)
	game_ui.player_deck = CardDataManager.get_deck_from_str_id(player_id)
	game_ui.opponent_deck = CardDataManager.get_deck_from_str_id(opponent_id)
	game_ui.image_loader.test_mode = true
	await game_ui.spawn_all_cards()
	game_ui.image_loader.test_mode = false

func _assert_extra_popout(side : String, expected_count : int):
	if side == "Player":
		await game_ui._on_player_buddy_button_pressed()
	else:
		await game_ui._on_opponent_buddy_button_pressed()
	var popout : CardPopout = game_ui.card_popout_parent.get_child(0)
	assert_eq(popout.used_slots, expected_count)
	var player_id = Enums.PlayerId.PlayerId_Player if side == "Player" else Enums.PlayerId.PlayerId_Opponent
	for index in range(expected_count):
		if index >= popout.used_slots:
			break
		var card : CardBase = popout.get_spot(index).get_child(0)
		assert_true(card.is_visible_in_tree())
		assert_true(card.is_front_showing())
		assert_true(card.hover_focus_enabled)
		assert_true(game_ui.game_wrapper.is_card_set_aside(player_id, card.card_id))
		assert_eq(card.clicked_card.get_connections().size(), 1)
	game_ui.close_popout()

func test_beheaded_and_king_extra_cards_are_visible_on_both_sides():
	await _setup_extra_cards("beheaded", "king")
	assert_eq(game_ui.get_node("AllCards/PlayerBuddyCopy").get_child_count(), 3)
	assert_eq(game_ui.get_node("AllCards/OpponentBuddyCopy").get_child_count(), 4)
	await _assert_extra_popout("Player", 3)
	await _assert_extra_popout("Opponent", 4)
	await game_ui._on_player_reference_button_pressed(false)
	for card in game_ui.get_node("AllCards/PlayerAllCopy").get_children():
		if card.card_id < 0:
			continue
		var logic_card = game_ui.game_wrapper.get_card_database().get_card(
			card.card_id - Game.ReferenceScreenIdRangeStart)
		assert_false(logic_card.set_aside, "Extra cards must stay out of the regular deck reference.")

func test_king_extra_card_click_selects_and_boosts_then_hides_used_card():
	await _setup_extra_cards("king", "beheaded")
	var player = game_ui.game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	game_ui.begin_boost_choosing(true, ["extra"], "", false, 1)
	await game_ui._on_player_buddy_button_pressed(true)
	var popout : CardPopout = game_ui.card_popout_parent.get_child(0)
	var legal_cards = player.set_aside_cards.filter(func(item):
		return game_ui.game_wrapper.can_player_boost(player.my_id, item.id, ["extra"], "", true))
	assert_eq(popout.used_slots, legal_cards.size())
	assert_gt(popout.used_slots, 0)
	if popout.used_slots == 0:
		return
	var card : CardBase = popout.get_spot(0).get_child(0)
	assert_true(game_ui.can_select_card(card))
	card.clicked_card.emit(card)
	assert_eq(game_ui.get_selected_card_ids(), [card.card_id])
	var card_id = card.card_id
	var payment = player.hand.slice(0, 3).map(func(item): return item.id)
	assert_true(game_ui.game_wrapper.submit_boost(player.my_id, card_id, payment, false, 0))
	assert_false(player.is_card_in_set_aside(card_id))
	game_ui.clear_selected_cards()
	await _assert_extra_popout("Player", 3)

func test_beheaded_exceed_extra_card_click_selects_and_plays_trait():
	await _setup_extra_cards("beheaded", "king")
	var game_logic = game_ui.game_wrapper.current_game
	var player = game_logic.player
	var gauge_ids = []
	for index in range(2):
		var gauge_card = player.deck[0]
		player.remove_top_card_from_deck()
		player.add_to_gauge(gauge_card)
		gauge_ids.append(gauge_card.id)
	assert_true(game_logic.do_exceed(player, gauge_ids))
	game_ui.begin_boost_choosing(false, ["extra"], "", true, 1)
	await game_ui._on_player_buddy_button_pressed(true)
	var popout : CardPopout = game_ui.card_popout_parent.get_child(0)
	assert_eq(popout.used_slots, 3)
	if popout.used_slots == 0:
		return
	var card : CardBase = popout.get_spot(0).get_child(0)
	assert_true(game_ui.can_select_card(card))
	card.clicked_card.emit(card)
	assert_eq(game_ui.get_selected_card_ids(), [card.card_id])
	assert_true(game_ui.game_wrapper.submit_boost(player.my_id, card.card_id, [], false, 0))
	assert_true(player.is_card_in_continuous_boosts(card.card_id))
	game_ui.clear_selected_cards()
	await _assert_extra_popout("Player", 2)

func test_explicitly_hidden_buddy_references_remain_hidden():
	await _setup_extra_cards("byakuya", "beheaded")
	assert_eq(game_ui.get_node("AllCards/PlayerBuddyCopy").get_child_count(), 0)
	await _assert_extra_popout("Opponent", 3)

func test_storage_linked_extra_popouts_preserve_cards_and_facedown_rules():
	await _setup_extra_cards("renea", "eugenia_1")
	for side in ["Player", "Opponent"]:
		var player_id = Enums.PlayerId.PlayerId_Player if side == "Player" else Enums.PlayerId.PlayerId_Opponent
		var player = game_ui.game_wrapper._get_player(player_id)
		var stored_card = player.hand[0]
		var facedown = side == "Player"
		player.move_card_from_hand_to_stored_cards(stored_card.id, facedown)
		game_ui.find_card_on_board(stored_card.id).flip_card_to_front(not facedown)
		game_ui._on_add_to_stored({
			"event_player": player_id, "number": stored_card.id, "extra_info": facedown
		})
		if side == "Player":
			await game_ui._on_player_buddy_button_pressed()
		else:
			await game_ui._on_opponent_buddy_button_pressed()
		var popout : CardPopout = game_ui.card_popout_parent.get_child(0)
		assert_eq(popout.used_slots, 1)
		var card : CardBase = popout.get_spot(0).get_child(0)
		assert_eq(card.card_id, stored_card.id)
		assert_true(card.is_visible_in_tree())
		assert_eq(card.is_front_showing(), not facedown)
		game_ui.close_popout()

func _summary_text(player_id) -> String:
	var is_player = player_id == Enums.PlayerId.PlayerId_Player
	var box = game_ui.get_node("PlayerBoostZone" if is_player else "OpponentBoostZone")
	var cards = game_ui.get_node("AllCards/PlayerBoosts" if is_player else "AllCards/OpponentBoosts")
	game_ui.update_boost_summary(player_id, cards, box)
	return box.boost_effects.text
func test_beheaded_exceed_adds_and_revert_removes_summary_line():
	setup_game_ui("beheaded", "ryu")
	var player = game_ui.game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	assert_false(ExceedSummaryText in _summary_text(Enums.PlayerId.PlayerId_Player), "未觉醒时不应显示")

	player.exceeded = true
	assert_true(ExceedSummaryText in _summary_text(Enums.PlayerId.PlayerId_Player), "觉醒后应显示")

	player.exceeded = false
	assert_false(ExceedSummaryText in _summary_text(Enums.PlayerId.PlayerId_Player), "退出觉醒后应消失")

func test_other_character_exceed_has_no_beheaded_line():
	setup_game_ui("ryu", "beheaded")
	var player = game_ui.game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	player.exceeded = true
	assert_false(ExceedSummaryText in _summary_text(Enums.PlayerId.PlayerId_Player), "其他角色觉醒不应显示")
