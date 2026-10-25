extends GutTest

var game_ui: Game

class DelayedUICharacter extends Character:
	signal frames_ready
	var requested_id := ""

	func load_character(_loader: CardImageLoader, _data: Dictionary, char_id: String, _yield_textures := true):
		requested_id = char_id
		await frames_ready
		var frames = SpriteFrames.new()
		frames.add_animation("idle")
		frames.add_frame("idle", load("res://assets/icons/exceedgear.png"))
		frames.set_meta("flip", true)
		animation.sprite_frames = frames
		play_animation("idle")

var delayed_exceed_finished := false

func before_each():
	game_ui = load("res://scenes/game/game.tscn").instantiate()
	game_ui.set_not_started_directly()
	add_child(game_ui)
	game_ui.set_process(false)
	game_ui.image_loader.test_mode = true
	game_ui.player_deck = CardDataManager.get_deck_from_str_id("dongshilang").duplicate(true)
	game_ui.opponent_deck = CardDataManager.get_deck_from_str_id("dongshilang").duplicate(true)
	var game_logic = LocalGame.new(game_ui.image_loader)
	game_logic.initialize_game(
		game_ui.player_deck, game_ui.opponent_deck,
		"p1", "p2", Enums.PlayerId.PlayerId_Player, 1)
	game_ui.game_wrapper.current_game = game_logic
	await game_ui.setup_character_card(
		game_ui.player_character_card, game_ui.player_deck, game_ui.player_buddy_character_card)
	await game_ui.setup_character_card(
		game_ui.opponent_character_card, game_ui.opponent_deck, game_ui.opponent_buddy_character_card)

func after_each():
	game_ui.queue_free()
	await get_tree().process_frame

func test_fixed_buddy_card_is_hidden_for_both_players():
	assert_false(game_ui.get_node("PlayerDeck/PlayerBuddyCharacterCard").is_visible_in_tree(),
		"The fixed card at (350, 375), not a boost or Bleach card, must be hidden.")
	assert_false(game_ui.get_node("OpponentDeck/OpponentBuddyCharacterCard").is_visible_in_tree(),
		"The opponent's fixed buddy card must also be hidden.")
	assert_true(game_ui.get_node("PlayerDeck/ExtraCardsButton").is_visible_in_tree())
	assert_true(game_ui.get_node("OpponentDeck/ExtraCardsButton").is_visible_in_tree())

func test_longxian_conversion_is_shown_in_combat_boost_summary():
	for side in ["Player", "Opponent"]:
		var player_id = Enums.PlayerId.PlayerId_Player if side == "Player" else Enums.PlayerId.PlayerId_Opponent
		var holder = game_ui.get_node("AllCards/%sBoosts" % side)
		var box = game_ui.get_node("%sBoostZone" % side)
		var player = game_ui.game_wrapper._get_player(player_id)
		game_ui.update_boost_summary(player_id, holder, box)
		assert_false("自身所有的前进改为逼近" in box.boost_effects.text)
		var attack = CardDataManager.get_card("dongshilang_龙霰架")
		for effect in attack["effects"]:
			if effect["effect_type"] == "convert_advance_to_close":
				game_ui.game_wrapper.current_game.handle_strike_effect(-1, effect, player)
		game_ui.update_boost_summary(player_id, holder, box)
		assert_true("自身所有的前进改为逼近" in box.boost_effects.text)
		player.strike_stat_boosts.clear()
		game_ui.update_boost_summary(player_id, holder, box)
		assert_false("自身所有的前进改为逼近" in box.boost_effects.text)

func test_text_buttons_open_all_five_ice_reference_cards():
	await game_ui.spawn_all_cards()
	for side in ["Player", "Opponent"]:
		var references = game_ui.get_node("AllCards/%sBuddyCopy" % side)
		assert_eq(references.get_child_count(), 5)
		game_ui.get_node("%sDeck/ExtraCardsButton" % side).pressed.emit()
		for frame in range(20):
			await get_tree().process_frame
		assert_eq(game_ui.card_popout_parent.get_child_count(), 1)
		var popout = game_ui.card_popout_parent.get_child(0)
		assert_eq(popout.used_slots, 5, "Hiding the fixed widget must not remove ice references.")
		for index in range(5):
			var slot = popout.get_spot(index)
			assert_eq(slot.get_child_count(), 1)
			var card = slot.get_child(0)
			assert_true(card.is_visible_in_tree(), "Popout copies must remain visible.")
			assert_eq(card.card_id, references.get_child(index).card_id)
			_assert_hover_enlarges_card(card)
		game_ui.close_popout()
		assert_false(game_ui.get_node("%sDeck/%sBuddyCharacterCard" % [side, side]).is_visible_in_tree())

func _assert_hover_enlarges_card(card: CardBase):
	assert_true(card.hover_focus_enabled)
	card._on_focus_mouse_entered()
	assert_eq(card.state, CardBase.CardState.CardState_Focusing)
	assert_eq(card.target_scale, CardBase.FocusScale)
	assert_gt(card.target_scale.x, card.resting_scale.x)
	card._on_focus_mouse_exited()
	assert_eq(card.state, CardBase.CardState.CardState_Unfocusing)

func test_ice_zone_and_choice_popouts_allow_hover_enlargement():
	await game_ui.spawn_all_cards()
	for side in ["Player", "Opponent"]:
		var player_id = Enums.PlayerId.PlayerId_Player if side == "Player" else Enums.PlayerId.PlayerId_Opponent
		var player = game_ui.game_wrapper._get_player(player_id)
		var ice = player.set_aside_cards[0]
		await game_ui._on_add_to_bleach({"event_player": player_id, "number": ice.id})
		if side == "Player":
			game_ui._on_player_bleach_clicked()
		else:
			game_ui._on_opponent_bleach_clicked()
		for frame in range(20):
			await get_tree().process_frame
		var popout = game_ui.card_popout_parent.get_child(0)
		_assert_hover_enlarges_card(popout.get_spot(0).get_child(0))
		game_ui.close_popout()
	var choice_card = game_ui.get_node("AllCards/PlayerBleach").get_child(0)
	game_ui.reparent_to_zone(choice_card, game_ui.choice_zone_parent)
	await game_ui.show_popout(
		game_ui.CardPopoutType.CardPopoutType_ChoiceZone, "Ice selection", game_ui.choice_zone_parent)
	var choice_popout = game_ui.card_popout_parent.get_child(0)
	_assert_hover_enlarges_card(choice_popout.get_spot(0).get_child(0))

func test_fixed_widget_stays_hidden_across_exceed_and_revert():
	# setup_character_card only initializes card UI, not the arena Character.
	# Production awaits setup_characters before events; supply explicit local frames
	# here rather than invoking CDN loading or changing Character's null contract.
	_initialize_arena_animation_fixture()
	game_ui.player_deck.erase("exceed_animation")
	game_ui.opponent_deck.erase("exceed_animation")
	game_ui.player_deck["buddy_exceeds"] = true
	game_ui.opponent_deck["buddy_exceeds"] = true
	for player_id in [Enums.PlayerId.PlayerId_Player, Enums.PlayerId.PlayerId_Opponent]:
		var player = game_ui.game_wrapper._get_player(player_id)
		var event = {"event_player": player_id}
		var widget = game_ui.player_buddy_character_card
		if player_id == Enums.PlayerId.PlayerId_Opponent:
			widget = game_ui.opponent_buddy_character_card
		player.exceeded = true
		await game_ui._on_exceed_event(event)
		assert_false(widget.is_visible_in_tree())
		player.exceeded = false
		await game_ui._on_exceed_revert_event(event)
		assert_false(widget.is_visible_in_tree())

func _initialize_arena_animation_fixture():
	var texture = load("res://assets/icons/exceedgear.png") as Texture2D
	assert_not_null(texture)
	for side in ["Player", "Opponent"]:
		var character = game_ui.get_node(side + "Character")
		assert_null(character.animation.sprite_frames, "Card-only setup must not masquerade as arena loading.")
		var frames = SpriteFrames.new()
		frames.add_animation("idle")
		frames.add_frame("idle", texture)
		character.animation.sprite_frames = frames
		character.play_animation("idle")
		assert_eq(character.get_size(), texture.get_size())

func test_arena_frames_retained_on_no_animation_change_both_sides():
	_initialize_arena_animation_fixture()
	for side in ["Player", "Opponent"]:
		var character = game_ui.get_node(side + "Character")
		var frames = character.animation.sprite_frames
		await character.set_exceed(true)
		assert_same(character.animation.sprite_frames, frames)
		character.set_facing(true)
		assert_true(character.animation.flip_h, "Absent flip metadata must not invert facing.")
		frames.set_meta("flip", true)
		character.set_facing(true)
		assert_false(character.animation.flip_h)
		await character.set_exceed(false)
		assert_same(character.animation.sprite_frames, frames)
		assert_false(character.exceed_icon.visible)

func _finish_delayed_exceed(character: Character):
	await character.set_exceed(true, game_ui.image_loader, {}, "fixture_exceed")
	character.set_facing(true)
	delayed_exceed_finished = true

func test_arena_async_exceed_waits_for_frames_before_facing():
	var character = load("res://scenes/game/character.tscn").instantiate()
	character.set_script(DelayedUICharacter)
	add_child(character)
	delayed_exceed_finished = false
	assert_null(character.animation.sprite_frames)
	_finish_delayed_exceed(character)
	assert_eq(character.requested_id, "fixture_exceed")
	assert_false(delayed_exceed_finished)
	await get_tree().process_frame
	assert_false(delayed_exceed_finished, "Pending loader must not resume layout with null frames.")
	character.frames_ready.emit()
	assert_true(delayed_exceed_finished)
	assert_not_null(character.animation.sprite_frames)
	assert_eq(character.animation.sprite_frames.get_frame_count("idle"), 1)
	assert_false(character.animation.flip_h, "Loaded flip metadata applies after the await.")
	character.queue_free()
	await get_tree().process_frame

func test_other_character_keeps_fixed_buddy_card():
	var deck = CardDataManager.get_deck_from_str_id("kokonoe")
	for side in ["Player", "Opponent"]:
		await game_ui.setup_character_card(
			game_ui.get_node("%sDeck/%sCharacterCard" % [side, side]),
			deck, game_ui.get_node("%sDeck/%sBuddyCharacterCard" % [side, side]))
		assert_true(game_ui.get_node("%sDeck/%sBuddyCharacterCard" % [side, side]).is_visible_in_tree())
		assert_false(game_ui.get_node("%sDeck/ExtraCardsButton" % side).is_visible_in_tree())

func test_actual_ice_boosts_are_not_hidden():
	for player_id in [Enums.PlayerId.PlayerId_Player, Enums.PlayerId.PlayerId_Opponent]:
		var player = game_ui.game_wrapper._get_player(player_id)
		var ice_count = 0
		for card in game_ui.game_wrapper.get_player_deck_list(player_id):
			if card.definition.get("type", "") != "ice_crystal":
				continue
			ice_count += 1
			for exceeded in [false, true]:
				player.exceeded = exceeded
				assert_false(game_ui._should_hide_boost_visual_until_exceeded(player_id, card.id),
					"An actual ice boost is not the fixed reference widget.")
		assert_eq(ice_count, 5)

func test_deck_reference_excludes_ice_for_both_players():
	await game_ui.spawn_all_cards()
	var ice_reference_ids = []
	for player_id in [Enums.PlayerId.PlayerId_Player, Enums.PlayerId.PlayerId_Opponent]:
		for card in game_ui.game_wrapper.get_player_deck_list(player_id):
			if card.definition.get("type", "") == "ice_crystal":
				ice_reference_ids.append(card.id + game_ui.ReferenceScreenIdRangeStart)
	assert_eq(ice_reference_ids.size(), 10)
	for side in ["Player", "Opponent"]:
		if side == "Player":
			await game_ui._on_player_reference_button_pressed()
		else:
			await game_ui._on_opponent_reference_button_pressed()
		for frame in range(20):
			await get_tree().process_frame
		var references = game_ui.get_node("AllCards/%sAllCopy" % side)
		assert_eq(references.get_child_count(), 17, "Only two character faces and 15 attack types belong here.")
		for card in references.get_children():
			assert_false(ice_reference_ids.has(card.card_id))
		var popout = game_ui.card_popout_parent.get_child(0)
		assert_eq(popout.used_slots, 17)
		for index in range(popout.used_slots):
			var card = popout.get_spot(index).get_child(0)
			assert_false(ice_reference_ids.has(card.card_id),
				"The actual deck-reference popup must not render ice cards.")
		assert_eq(game_ui.get_node("AllCards/%sBuddyCopy" % side).get_child_count(), 5,
			"The separate extra-card reference must retain all five ice cards.")
		game_ui.close_popout()
