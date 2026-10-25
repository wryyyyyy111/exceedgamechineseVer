extends ExceedGutTest

var game_ui: Game


func who_am_i():
	return "heiqiyihu"


func before_each():
	game_ui = load("res://scenes/game/game.tscn").instantiate()
	game_ui.set_not_started_directly()
	game_ui.add_child(game_ui.game_wrapper)
	add_child(game_ui)
	game_ui.set_process(false)
	assert_eq(game_ui.ChoiceTagRegex.compile("\\[.*\\]"), OK)
	game_ui.image_loader.test_mode = true
	var deck = CardDataManager.get_deck_from_str_id("heiqiyihu").duplicate(true)
	deck["starting_life"] = 100
	deck["life_cap"] = 100
	game_ui.player_deck = deck
	game_ui.opponent_deck = deck.duplicate(true)
	game_logic = LocalGame.new(game_ui.image_loader)
	game_logic.initialize_game(deck, game_ui.opponent_deck, "p1", "p2", Enums.PlayerId.PlayerId_Player, 24018)
	game_ui.game_wrapper.current_game = game_logic
	player1 = game_logic.player
	player2 = game_logic.opponent
	game_logic.draw_starting_hands_and_begin()
	assert_true(game_logic.do_mulligan(player1, []))
	assert_true(game_logic.do_mulligan(player2, []))
	game_logic.get_latest_events()
	game_ui.setup_bleach_zones()


func after_each():
	game_ui.queue_free()
	await get_tree().process_frame


func _node(id: int, zone: String = "PlayerHand") -> CardBase:
	var card = Game.CardBaseScene.instantiate()
	var definition = game_logic.card_db.get_card(id).definition
	game_ui.get_node("AllCards/" + zone).add_child(card)
	card.initialize_simple(id, null, null, definition["display_name"], definition["boost"]["display_name"], definition)
	return card


func _guardian(owner: Player, definition_id: String) -> int:
	var id = give_player_specific_card(owner, definition_id)
	owner.remove_card_from_hand(id, true, false)
	owner.add_to_bleach(game_logic.card_db.get_card(id))
	return id


func _last_event(kind: Enums.EventType) -> Dictionary:
	var events = game_logic.get_latest_events().filter(func(event): return event["event_type"] == kind)
	assert_gt(events.size(), 0)
	return events.back() if not events.is_empty() else {}


func _button_texts() -> Array:
	var texts = []
	for container in game_ui.action_menu.choice_buttons_grid.get_children():
		if container.visible:
			var text = container.get_child(1).get_child(0).text
			assert_false("缺失" in text, "Actual choice button: " + text)
			texts.append(text)
	return texts


func _show_choice():
	var event = _last_event(Enums.EventType.EventType_Strike_EffectChoice)
	assert_false(event.is_empty())
	if not event.is_empty():
		game_ui._on_effect_choice(event)
		game_ui._update_buttons()
		assert_false("缺失" in game_ui.current_instruction_text, game_ui.current_instruction_text)

func test_ui_both_character_cards_show_complete_ability_and_exceed_text():
	var cards = [
		[game_ui.player_character_card, game_ui.player_deck, game_ui.player_buddy_character_card],
		[game_ui.opponent_character_card, game_ui.opponent_deck, game_ui.opponent_buddy_character_card],
	]
	for entry in cards:
		await game_ui.setup_character_card(entry[0], entry[1], entry[2])
		var labels = entry[0].get_node("MainPanelContainer/MainContainer/VerticalLayout/TextMarginContainer/TextPanelBacking/TextVLayout")
		var normal_text: String = labels.get_node("EffectLabel").text
		var exceed_text: String = labels.get_node("EffectLabelExceed").text
		assert_false("缺失" in normal_text, normal_text)
		assert_false("缺失" in exceed_text, exceed_text)
		for fragment in ["当你觉醒时", "至少抽2张", "本回合不因手牌上限弃牌", "25、15、10", "双方选择攻击牌前"]:
			assert_string_contains(normal_text, fragment)
		for fragment in ["守护卡", "怒气或能量", "1怒气取消"]:
			assert_string_contains(exceed_text, fragment)


func _start_with_guardian(accept: bool):
	var source = _guardian(player1, "gg_normal_grasp")
	_node(source, "PlayerBleach")
	var attack = give_player_specific_card(player1, "gg_normal_dust")
	var attack_node = _node(attack)
	game_ui.ui_state = Game.UIState.UIState_PickTurnAction
	game_ui.selected_cards = [attack_node]
	game_ui._on_strike_button_pressed()
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_ui.ui_state, Game.UIState.UIState_WaitForGameServer)
	assert_null(game_logic.active_strike.initiator_card)
	assert_null(game_logic.active_strike.defender_card)
	assert_true(player1.is_card_in_hand(attack), "Declaration cannot lock or spend a chosen attack.")
	assert_eq(game_ui.selected_cards.size(), 0)
	_show_choice()
	var texts = _button_texts()
	assert_eq(texts.size(), 2)
	assert_string_contains(texts[0], "触发守护")
	assert_string_contains(texts[1], "不触发守护")
	assert_false(game_ui.action_menu.choice_buttons_grid.get_child(0).get_child(0).disabled)
	game_ui.action_menu._on_choice_pressed(0 if accept else 1)
	assert_eq(player1.is_card_in_discards(source), accept)
	assert_eq(player1.is_card_in_bleach(source), not accept)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)
	assert_null(game_logic.active_strike.initiator_card)
	var event = _last_event(Enums.EventType.EventType_ForceStartStrike)
	game_ui._on_force_start_strike(event)
	assert_eq(game_ui.ui_sub_state, Game.UISubState.UISubState_SelectCards_StrikeCard)
	assert_true(game_ui.can_select_card(attack_node))
	game_ui.on_card_clicked(attack_node)
	assert_true(game_ui.can_press_ok())
	game_ui._on_instructions_ok_button_pressed(0)
	assert_eq(game_logic.active_strike.initiator_card.id, attack)
	assert_false(player1.is_card_in_hand(attack))
	var response = give_player_specific_card(player2, "gg_normal_focus")
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_null(game_logic.active_strike)


func test_ui_guardian_accept_before_any_attack_is_selected():
	_start_with_guardian(true)


func test_ui_guardian_pass_restores_real_attack_selection():
	_start_with_guardian(false)


func test_ui_both_guardian_zones_public_front_and_no_opponent_selection():
	for owner in [player1, player2]:
		var id = give_player_specific_card(owner, "heiqiyihu_地裂崩击")
		var side = "Player" if owner == player1 else "Opponent"
		var card = _node(id, side + "Hand")
		owner.remove_card_from_hand(id, true, false)
		owner.add_to_bleach(game_logic.card_db.get_card(id))
		var event = _last_event(Enums.EventType.EventType_AddToBleach)
		game_ui._on_add_to_bleach(event)
		assert_eq(card.get_parent(), game_ui.get_node("AllCards/" + side + "Bleach"))
		assert_true(card.is_front_showing())
		assert_true(game_ui.get_node(side + "Zones/" + side + "Bleach").visible)
		assert_false(game_ui._should_hide_bleach_cards_in_match(owner.my_id))
		if owner == player2:
			player1.exceeded = true
			game_ui.ui_state = Game.UIState.UIState_SelectCards
			game_ui.ui_sub_state = Game.UISubState.UISubState_SelectCards_StrikeGauge
			game_ui.select_card_require_max = 2
			assert_false(game_ui.can_select_card(card))


func test_ui_awakened_guardian_selectable_only_in_payment_states():
	var source = _guardian(player1, "heiqiyihu_虚化")
	var card = _node(source, "PlayerBleach")
	var payment_states = [
		Game.UISubState.UISubState_SelectCards_StrikeGauge,
		Game.UISubState.UISubState_SelectCards_BoostCancel,
		Game.UISubState.UISubState_SelectCards_MoveActionGenerateForce,
		Game.UISubState.UISubState_SelectCards_ForceForChange,
		Game.UISubState.UISubState_SelectCards_ForceForArmor,
		Game.UISubState.UISubState_SelectCards_StrikeForce,
		Game.UISubState.UISubState_SelectCards_CharacterAction_Force,
		Game.UISubState.UISubState_SelectCards_CharacterAction_Gauge,
		Game.UISubState.UISubState_SelectCards_ForceForEffect,
		Game.UISubState.UISubState_SelectCards_GaugeForEffect,
		Game.UISubState.UISubState_SelectCards_ForceForBoost,
		Game.UISubState.UISubState_SelectCards_GaugeForBoost
	]
	game_ui.ui_state = Game.UIState.UIState_SelectCards
	game_ui.select_card_require_force = 2
	game_ui.select_card_require_max = 3
	game_ui.select_card_up_to_force = 3
	for exceeded in [false, true]:
		player1.exceeded = exceeded
		for sub_state in payment_states:
			game_ui.ui_sub_state = sub_state
			assert_eq(game_ui.can_select_card(card), exceeded, "Guardian permission for substate%s" % sub_state)
	game_ui.ui_sub_state = Game.UISubState.UISubState_SelectCards_StrikeCard
	assert_false(game_ui.can_select_card(card), "Resource permission never grants attack-from-guardian.")
	game_ui.ui_state = Game.UIState.UIState_PickTurnAction
	assert_false(game_ui.can_select_card(card))


func test_ui_mixed_guardian_and_gauge_pay_real_ultra_through_ok():
	player1.exceeded = true
	position_players(player1, 3, player2, 4)
	var guardian = _guardian(player1, "gg_normal_grasp")
	var gauge = give_gauge(player1, 1)[0]
	var first = _node(guardian, "PlayerBleach")
	var second = _node(gauge, "PlayerGauge")
	var attack = give_player_specific_card(player1, "heiqiyihu_呼唤我的名字吧！")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	game_ui._on_pay_cost_gauge(_last_event(Enums.EventType.EventType_Strike_PayCost_Gauge))
	assert_string_contains(game_ui.current_instruction_text, "2")
	assert_string_contains(game_ui.current_instruction_text, "怒气")
	assert_false(game_ui.can_press_ok())
	game_ui.on_card_clicked(first)
	assert_false(game_ui.can_press_ok())
	game_ui.on_card_clicked(second)
	assert_eq(game_ui.get_gauge_generated(), 2)
	assert_true(game_ui.can_press_ok())
	game_ui._on_instructions_ok_button_pressed(0)
	assert_null(game_logic.active_strike)
	assert_eq(player2.life, 97)
	assert_true(player1.is_card_in_discards(guardian))
	assert_true(player1.is_card_in_discards(gauge))
	assert_true(player1.is_card_in_gauge(attack))


func test_ui_guardian_ultra_two_force_mixed_hand_payment_submission():
	player1.exceeded = true
	position_players(player1, 3, player2, 6)
	var guardian = _guardian(player1, "heiqiyihu_虚化")
	var hand = give_player_specific_card(player1, "gg_normal_grasp")
	var first = _node(guardian, "PlayerBleach")
	var second = _node(hand)
	var attack = give_player_specific_card(player1, "heiqiyihu_灵魂对接")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	game_ui._on_force_for_effect(_last_event(Enums.EventType.EventType_ForceForEffect))
	assert_string_contains(game_ui.current_instruction_text, "3")
	assert_string_contains(game_ui.current_instruction_text, "威力")
	game_ui.on_card_clicked(first)
	assert_eq(game_ui.get_force_in_selected_cards(), 2)
	game_ui.treat_ultras_as_single_force = true
	assert_eq(game_ui.get_force_in_selected_cards(), 1)
	game_ui.treat_ultras_as_single_force = false
	game_ui.on_card_clicked(second)
	assert_eq(game_ui.get_force_in_selected_cards(), 3)
	assert_true(game_ui.can_press_ok())
	game_ui._on_instructions_ok_button_pressed(0)
	assert_null(game_logic.active_strike)
	assert_true(player1.is_card_in_discards(guardian))
	assert_true(player1.is_card_in_discards(hand))
	assert_eq(player2.life, 96)


func test_ui_dynamic_cancel_one_gauge_guardian_payment_real_button():
	player1.exceeded = true
	var guardian = _guardian(player1, "gg_normal_grasp")
	var money = _node(guardian, "PlayerBleach")
	var boost = give_player_specific_card(player1, "heiqiyihu_地裂崩击")
	assert_eq(game_ui.game_wrapper.get_player_boost_cancel_cost(player1.my_id, boost), 1)
	assert_eq(game_logic.card_db.get_card(boost).definition["boost"]["cancel_cost"], -1)
	assert_true(game_logic.do_boost(player1, boost))
	game_ui._on_boost_cancel_decision(_last_event(Enums.EventType.EventType_Boost_CancelDecision))
	assert_string_contains(game_ui.current_instruction_text, "1")
	assert_string_contains(game_ui.current_instruction_text, "怒气")
	assert_eq(game_ui.select_card_require_min, 1)
	assert_eq(game_ui.select_card_require_max, 1)
	game_ui.on_card_clicked(money)
	assert_true(game_ui.can_press_ok())
	game_ui._on_instructions_ok_button_pressed(0)
	assert_true(player1.is_card_in_discards(guardian))
	assert_eq(game_logic.active_turn_player, player1.my_id)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)


func _summary_window(source_name: String, huhuan: bool = false, opponent_source: bool = false) -> Dictionary:
	position_players(player1, 3, player2, 4)
	var owner = player2 if opponent_source else player1
	var source = _guardian(owner, source_name)
	_node(source, "OpponentBleach" if opponent_source else "PlayerBleach")
	var attack = give_player_specific_card(owner, "heiqiyihu_呼唤我的名字吧！" if huhuan else "gg_normal_dust")
	var response = give_player_specific_card(player1 if opponent_source else player2, "gg_normal_focus")
	var card = game_logic.card_db.get_card(attack)
	card.definition = card.definition.duplicate(true)
	card.definition["effects"].append({
		"timing": "before", "effect_type": StrikeEffects.Choice,
		"choice": [{"effect_type": StrikeEffects.Pass, "_choice_text": "UI摘要检查"}]
	})
	var payment = give_gauge(owner, 3) if huhuan else []
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	# Replay the public choice/discard events before the engine continues.
	var offer = _last_event(Enums.EventType.EventType_Strike_EffectChoice)
	assert_eq(offer["reason"], "双方选牌前：守护")
	game_ui.pending_guardian_display_player = offer["event_player"]
	assert_true(game_logic.do_choice(owner, 0))
	var discard = _last_event(Enums.EventType.EventType_AddToDiscard)
	assert_eq(discard["number"], source)
	game_ui._on_discard_event(discard)
	assert_true(game_logic.do_strike(player1, response if opponent_source else attack, false, -1))
	assert_true(game_logic.do_strike(player2, attack if opponent_source else response, false, -1))
	if huhuan:
		assert_true(game_logic.do_pay_strike_cost(owner, payment, false))
		# First activation confirms both attack costs have been paid.
		_node(attack, "Striking")
		_node(response, "Striking")
		game_ui._on_strike_card_activation({"number": attack})
	var side = "Opponent" if opponent_source else "Player"
	game_ui.update_boost_summary(owner.my_id, game_ui.get_node("AllCards/" + side + "Boosts"), game_ui.get_node(side + "BoostZone"))
	return {"owner": owner, "source": source, "attack": attack, "side": side}


func _summary_text(info: Dictionary) -> String:
	var text = game_ui.get_node(info["side"] + "BoostZone").boost_effects.text
	assert_false("缺失" in text, "Actual guardian summary: " + text)
	return text


func test_ui_virtual_power_summary_scaled_three_no_fake_boost_card():
	var info = _summary_window("heiqiyihu_地裂崩击")
	assert_string_contains(_summary_text(info), "守护")
	assert_string_contains(_summary_text(info), "+3")
	assert_false("+2" in _summary_text(info))
	assert_eq(game_ui.get_node("AllCards/PlayerBoosts").get_child_count(), 0)
	assert_eq(player1.continuous_boosts.size(), 0)
	assert_true(player1.is_card_in_discards(info["source"]))
	assert_true(game_logic.do_choice(player1, 0))
	game_ui._on_end_of_strike()
	game_ui.update_boost_summary(player1.my_id, game_ui.get_node("AllCards/PlayerBoosts"), game_ui.get_node("PlayerBoostZone"))
	assert_false("守护" in _summary_text(info), "Virtual summary disappears at Cleanup.")


func test_ui_virtual_guard_summary_three():
	var info = _summary_window("heiqiyihu_静血装")
	assert_string_contains(_summary_text(info), "+3")


func test_ui_virtual_draw_summary_three_and_actual_order_button():
	var info = _summary_window("heiqiyihu_灵魂对接")
	assert_string_contains(_summary_text(info), "3")
	assert_false("抽2" in _summary_text(info))
	assert_true(game_logic.do_choice(player1, 0))
	assert_null(game_logic.active_strike)


func test_ui_virtual_speed_opponent_summary_three_huhuan():
	var info = _summary_window("heiqiyihu_瞬步", true, true)
	assert_string_contains(_summary_text(info), "+3")
	assert_false("+1" in _summary_text(info))
	game_ui.update_boost_summary(player1.my_id, game_ui.get_node("AllCards/PlayerBoosts"), game_ui.get_node("PlayerBoostZone"))
	assert_false("守护" in game_ui.get_node("PlayerBoostZone").boost_effects.text)


func test_ui_virtual_move_summary_and_real_sort_button_use_two_not_one():
	var info = _summary_window("heiqiyihu_全力一击")
	assert_string_contains(_summary_text(info), "2")
	_show_choice()
	var texts = _button_texts()
	var move_index = -1
	for i in range(game_ui.current_effect_choices.size()):
		if game_ui.current_effect_choices[i]["effect_type"] == StrikeEffects.MoveToAnySpace:
			move_index = i
	assert_gte(move_index, 0)
	if move_index >= 0:
		assert_string_contains(texts[move_index], "2")
		assert_string_contains(texts[move_index], "前进或后退")
		game_ui.action_menu._on_choice_pressed(move_index)
		assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect)
		assert_true(6 in game_logic.decision_info.limitation)


func test_ui_xuhua_payment_and_recovery_actual_buttons():
	position_players(player1, 3, player2, 4)
	var cost = give_gauge(player1, 2)
	var paid = [
		give_player_specific_card(player1, "gg_normal_cross"),
		give_player_specific_card(player1, "gg_normal_grasp")
	]
	var first = _node(paid[0])
	var second = _node(paid[1])
	var attack = give_player_specific_card(player1, "heiqiyihu_虚化")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_true(game_logic.do_pay_strike_cost(player1, cost, false))
	game_ui._on_force_for_effect(_last_event(Enums.EventType.EventType_ForceForEffect))
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_ui.select_card_up_to_force, 2)
	assert_string_contains(game_ui.current_instruction_text, "2")
	assert_string_contains(game_ui.current_instruction_text, "霸体")
	assert_true(game_ui.can_press_ok(), "Zero Force is allowed.")
	game_ui.on_card_clicked(first)
	game_ui.on_card_clicked(second)
	assert_true(game_ui.can_press_ok())
	game_ui._on_instructions_ok_button_pressed(0)
	_show_choice()
	var texts = _button_texts()
	assert_eq(texts.size(), 2)
	for text in texts:
		assert_string_contains(text, "守护区")
	assert_eq(game_logic.get_current_strike_timing(), "after")
	game_ui.action_menu._on_choice_pressed(1)
	assert_true(player1.is_card_in_bleach(paid[1]))
	_show_choice()
	assert_eq(_button_texts().size(), 1)
	assert_string_contains(_button_texts()[0], "怒气区")
	game_ui.action_menu._on_choice_pressed(0)
	assert_true(player1.is_card_in_gauge(paid[0]))
	assert_null(game_logic.active_strike)


func test_ui_guardian_source_choice_topdeck_and_specific_hand():
	var boost = give_player_specific_card(player1, "heiqiyihu_虚化")
	var hand = give_player_specific_card(player1, "gg_normal_grasp")
	var payment = [
		give_player_specific_card(player1, "gg_normal_cross"),
		give_player_specific_card(player1, "gg_normal_focus")
	]
	assert_true(game_logic.do_boost(player1, boost, payment))
	_show_choice()
	var texts = _button_texts()
	assert_eq(texts[0], "[center]将牌堆顶1张牌置入守护区[/center]")
	var index = -1
	for i in range(game_logic.decision_info.choice.size()):
		if game_logic.decision_info.choice[i].get("guardian_card_id", -1) == hand:
			index = i
	assert_gte(index, 0)
	if index >= 0:
		assert_eq(texts[index], "[center]将手牌「%s」置入守护区[/center]" % game_logic.card_db.get_card(hand).definition["display_name"])
		game_ui.action_menu._on_choice_pressed(index)
		assert_true(player1.is_card_in_bleach(hand))
		assert_false(player1.is_card_in_hand(hand))


func test_ui_played_summary_survives_engine_cleanup_until_end_event():
	position_players(player1, 3, player2, 4)
	var source = _guardian(player1, "heiqiyihu_地裂崩击")
	_node(source, "PlayerBleach")
	var attack = give_player_specific_card(player1, "gg_normal_dust")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	assert_true(game_logic.do_strike(player1, -1, false, -1))
	_show_choice()
	assert_true(game_logic.do_choice(player1, 0))
	var discard = _last_event(Enums.EventType.EventType_AddToDiscard)
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_null(game_logic.active_strike, "Engine can finish before playback reaches discard.")
	game_ui.update_boost_summary(player1.my_id, game_ui.get_node("AllCards/PlayerBoosts"), game_ui.get_node("PlayerBoostZone"))
	assert_false("守护" in game_ui.get_node("PlayerBoostZone").boost_effects.text)
	game_ui._on_discard_event(discard)
	game_ui.update_boost_summary(player1.my_id, game_ui.get_node("AllCards/PlayerBoosts"), game_ui.get_node("PlayerBoostZone"))
	assert_string_contains(game_ui.get_node("PlayerBoostZone").boost_effects.text, "+3")
	assert_eq(game_ui.get_node("AllCards/PlayerBoosts").get_child_count(), 0)
	game_ui._on_end_of_strike()
	assert_true(game_ui.played_guardian_records.is_empty())


func test_resources_manifest_and_copied_images_match_authorized_sources():
	var resource = "res://assets/character_animations_custom/heiqiyihu/animations.tres"
	assert_eq(CharSkinManager.get_animation_path_for_deck_id("heiqiyihu"), resource)
	assert_eq(CdnAssetLoader._get_animation_manifest_text(resource).replace("\r\n", "\n"),
		FileAccess.get_file_as_string(resource).replace("\r\n", "\n"))
	assert_eq(FileAccess.get_sha256("res://assets/character_animations_custom/heiqiyihu/heiqiyihu.png"),
		"d0b4b3151e611b442937d95c63cc3cbd37e0837b03c55eafc5c7077063eb32ad")
	assert_eq(FileAccess.get_sha256("res://assets/portraits/heiqiyihu.png"),
		"340185b8f7627d396ceec3e8486ea9e2c45ce33a53ef99187bd08026c730281a")
	var frames = load(resource) as SpriteFrames
	assert_not_null(frames)
	assert_eq(frames.get_frame_count("idle"), 1)
	assert_false(frames.get_meta("flip"))
	assert_eq(frames.get_meta("scaling"), 0.3)


func test_resources_real_game_loads_both_sides_at_242px_and_exceed_reuses_art():
	await game_ui.setup_characters()
	await get_tree().process_frame
	assert_true(game_ui.setup_characters_complete)
	for side in ["Player", "Opponent"]:
		var character = game_ui.get_node(side + "Character")
		var frames = character.animation.sprite_frames
		assert_not_null(frames)
		assert_eq(frames.get_frame_count("idle"), 1)
		var texture = frames.get_frame_texture("idle", 0)
		assert_eq(texture.get_size(), Vector2(854, 1612), "Must load cdn_path art, not the placeholder.")
		var source_image = Image.new()
		assert_eq(source_image.load_png_from_buffer(FileAccess.get_file_as_bytes(
			"res://assets/character_animations_custom/heiqiyihu/heiqiyihu.png")), OK)
		var runtime_image = texture.get_image()
		source_image.convert(Image.FORMAT_RGBA8)
		runtime_image.convert(Image.FORMAT_RGBA8)
		assert_eq(hash(runtime_image.get_data()), hash(source_image.get_data()), "Displayed pixels must match authorized art.")
		assert_eq(character.scale, Vector2(0.15, 0.15))
		var display_size = texture.get_size() * character.scale
		assert_almost_eq(display_size.y, 241.8, 0.01)
		assert_almost_eq(display_size.x / display_size.y, 854.0 / 1612.0, 0.0001)
		var owner = player1 if side == "Player" else player2
		game_ui.move_character_to_arena_square(character, owner.arena_location, true, Character.CharacterAnim.CharacterAnim_None)
		var center = game_ui.get_arena_square_center(owner.arena_location)
		assert_almost_eq(character.global_position.x, center.x, 0.01)
		assert_gt(character.global_position.y - display_size.y / 2, 0.0)
		assert_lt(character.global_position.y + display_size.y / 2, 720.0)
		assert_true(character.animation.is_playing())
		owner.exceeded = true
		await game_ui._on_exceed_event({"event_player": owner.my_id})
		assert_same(character.animation.sprite_frames, frames, "No invented exceed resource.")
		owner.exceeded = false
		await game_ui._on_exceed_revert_event({"event_player": owner.my_id})
		assert_same(character.animation.sprite_frames, frames)
	var left = game_ui.get_node("PlayerCharacter")
	var right = game_ui.get_node("OpponentCharacter")
	assert_true(left.animation.flip_h)
	assert_false(right.animation.flip_h)
	left.position.x = right.position.x + 100
	game_ui.update_character_facing()
	assert_false(left.animation.flip_h)
	assert_true(right.animation.flip_h)


func test_select_real_s0_button_hover_and_press_resolve_exact_deck():
	var menu = load("res://scenes/menu/char_select.tscn").instantiate()
	add_child(menu)
	menu.show_char_select("heiqiyihu")
	await get_tree().process_frame
	assert_eq(menu.current_season_id, "season0")
	var row = menu.get_node("CenterContainer/S0CharacterSelect/Rows/Row1")
	var matches = row.get_children().filter(func(button): return button.char_id == "heiqiyihu")
	assert_eq(matches.size(), 1)
	var button = matches[0]
	assert_true(button.is_visible_in_tree())
	assert_true(button.is_connected("on_hover", Callable(menu, "_on_char_hover")))
	assert_true(button.is_connected("on_pressed", Callable(menu, "_on_char_button_on_pressed")))
	assert_same(button.portrait.texture, load("res://assets/portraits/heiqiyihu.png"))
	button.get_node("Button").mouse_entered.emit()
	assert_eq(menu.hover_label.text, "黑崎一护-死神代理")
	assert_same(menu.hover_portrait.texture, button.portrait.texture)
	var picked = []
	menu.select_character.connect(func(id): picked.append(id))
	button.get_node("Button").pressed.emit()
	assert_eq(picked, ["heiqiyihu"])
	assert_eq(CardDataManager.get_deck_from_str_id(picked[0])["id"], "heiqiyihu")
	assert_gt(button.size.x, 0.0)
	assert_gt(button.size.y, 0.0)
	assert_lte(row.size.x, 1280.0, "Adding the button must not push the S0 row off screen.")
	menu.queue_free()
	await get_tree().process_frame


func test_select_hp_rank_a_plus_both_sides_without_custom_hp_guess():
	var manager = HpRankModeManager.new()
	var match_info = manager.build_match_starting_hp("hp_rank_mode", "heiqiyihu", "heiqiyihu")
	assert_true(match_info["valid"])
	assert_eq(match_info["player1_tier"], "A+")
	assert_eq(match_info["player2_tier"], "A+")
	var config = JSON.parse_string(FileAccess.get_file_as_string("res://data/hp_rank_mode_manager.json"))
	assert_eq(config["tier"].filter(func(entry): return entry["character"] == "heiqiyihu").size(), 1)
	assert_false("heiqiyihu" in config["banned_character"])


func test_select_real_card_atlases_render_all_fifteen_unique_cards():
	var loader = CardImageLoader.new(false)
	add_child(loader)
	var deck = CardDataManager.get_deck_from_str_id("heiqiyihu")
	var seen = []
	var expected_normals = {
		"grasp": 3, "cross": 5, "slash": 4, "dive": 6,
		"dust": 0, "sweep": 2, "focus": 7, "block": 1
	}
	for entry in deck["cards"]:
		var definition_id = entry["definition_id"]
		if definition_id in seen:
			continue
		seen.append(definition_id)
		var atlas = deck["image_resources"][entry["image_name"]].duplicate(true)
		atlas["season"] = 0
		atlas["image_name"] = entry["image_name"]
		atlas["deck_id"] = "heiqiyihu"
		var texture = await loader.get_card_image(atlas["url"], entry["image_index"], atlas)
		assert_not_null(texture, "Actual CDN card art for %s" % definition_id)
		if texture == null:
			continue
		assert_true(texture is AtlasTexture)
		assert_eq(texture.get_size(), Vector2(750, 1024))
		assert_eq(texture.region.position, Vector2(
			(entry["image_index"] % 4) * 750, int(entry["image_index"] / 4) * 1024))
		if entry["image_name"] == "normals":
			assert_eq(entry["image_index"], expected_normals[definition_id.trim_prefix("gg_normal_")])
		var definition = CardDataManager.get_card(definition_id)
		var card = Game.CardBaseScene.instantiate()
		game_ui.get_node("AllCards/PlayerHand").add_child(card)
		card.initialize_simple(70000 + seen.size(), texture, null,
			definition["display_name"], definition["boost"]["display_name"], definition)
		card.flip_card_to_front(true)
		assert_same(card.fancy_card.texture, texture)
		assert_true(card.fancy_card.visible)
		assert_true(card.is_front_showing())
	assert_eq(seen.size(), 15)
	loader.queue_free()
	await get_tree().process_frame
