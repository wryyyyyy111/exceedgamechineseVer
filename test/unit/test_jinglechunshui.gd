extends ExceedGutTest

func who_am_i():
	return "jinglechunshui"

func _pass_optional_strike(player: Player):
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player, game_logic.decision_info.choice.size() - 1))

func _exceed_with_four_gauge(player: Player):
	var gauge_ids = give_gauge(player, 4)
	assert_true(game_logic.do_exceed(player, gauge_ids))
	assert_true(player.exceeded)

func process_remaining_decisions(initiator, defender, init_choices, def_choices):
	while game_logic.game_state == Enums.GameState.GameState_PlayerDecision:
		var decision_player = initiator
		var choices = init_choices
		if game_logic.decision_info.player == defender.my_id:
			decision_player = defender
			choices = def_choices
		if choices.is_empty():
			fail_test("Missing decision for %s" % Enums.DecisionType.keys()[game_logic.decision_info.type])
			return
		var choice = choices.pop_front()
		match game_logic.decision_info.type:
			Enums.DecisionType.DecisionType_ChooseSimultaneousEffect:
				assert_true(game_logic.do_choice(decision_player, choice))
			Enums.DecisionType.DecisionType_ReadingNormal:
				assert_true(game_logic.do_boost_name_card_choice_effect(decision_player, choice))
			Enums.DecisionType.DecisionType_ForceForEffect:
				assert_true(game_logic.do_force_for_effect(decision_player, choice, false))
			Enums.DecisionType.DecisionType_ForceForArmor:
				assert_true(game_logic.do_force_for_armor(decision_player, choice if choice is Array else []))
			Enums.DecisionType.DecisionType_ChooseToDiscard:
				assert_true(game_logic.do_choose_to_discard(decision_player, choice))
			_:
				assert_true(game_logic.do_choice(decision_player, choice))

func test_normal_special_boost_can_optionally_strike():
	var boost_id = give_player_specific_card(player1, "jinglechunshui_yingsong")
	assert_true(game_logic.do_boost(player1, boost_id))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player1, 0))
	assert_true(player1.is_card_in_continuous_boosts(boost_id))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)

func test_normal_character_action_boosts_special_from_gauge():
	var boost_id = give_player_specific_card(player1, "jinglechunshui_zhangui")
	player1.move_card_from_hand_to_gauge(boost_id)
	var deck_before = player1.deck.size()
	assert_true(game_logic.do_character_action(player1, []))
	assert_eq(player1.life, 28)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostNow)
	assert_eq(game_logic.decision_info.valid_zones, ["gauge"])
	assert_eq(game_logic.decision_info.limitation, "special")
	validate_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_ForceStartBoost, player1)
	assert_true(game_logic.do_boost(player1, boost_id))
	_pass_optional_strike(player1)
	assert_true(player1.is_card_in_continuous_boosts(boost_id))
	assert_eq(player1.deck.size(), deck_before - 2)
	assert_eq(player1.gauge.size(), 1)

func test_exceed_draws_one_card():
	var gauge_ids = give_gauge(player1, 4)
	var deck_before = player1.deck.size()
	var hand_before = player1.hand.size()
	assert_true(game_logic.do_exceed(player1, gauge_ids))
	assert_true(player1.exceeded)
	assert_eq(player1.deck.size(), deck_before - 2)
	assert_eq(player1.hand.size(), hand_before + 2)
	validate_life(player1, 30, player2, 30)

func test_exceeded_continuous_boost_draws_one_then_can_strike():
	player1.exceed()
	var hand_before = player1.hand.size()
	var boost_id = give_player_specific_card(player1, "jinglechunshui_yingsong")
	assert_true(game_logic.do_boost(player1, boost_id))
	assert_eq(player1.hand.size(), hand_before + 1)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)

func test_exceeded_turn_start_toll_applies_on_both_players_turns():
	player1.exceed()
	advance_turn(player1)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player2.my_id)
	assert_true(game_logic.do_choice(player2, 3))
	assert_ne(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(player2.life, 29)

	advance_turn(player2)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_choice(player1, 3))
	assert_ne(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(player1.life, 29)

func test_all_character_specific_effects_have_display_text():
	var effect_types = [
		StrikeEffects.JingleChunShuiStrikeAfterSpecialBoost,
		StrikeEffects.JingleChunShuiDrawAndStrikeAfterContinuousBoost,
		StrikeEffects.JingleChunShuiTurnStartToll,
		StrikeEffects.JingleChunShuiTurnStartTollPay,
		StrikeEffects.JingleChunShuiGaugeSpecialBoost,
		StrikeEffects.JingleChunShuiOnExceed,
		StrikeEffects.JingleChunShuiPlayBujingdule,
		StrikeEffects.JingleChunShuiChooseTwo,
		StrikeEffects.JingleChunShuiBujingduleReturn,
		StrikeEffects.JingleChunShuiSlowestPlayerDamage,
		StrikeEffects.JingleChunShuiYanguiNameNormal,
		StrikeEffects.JingleChunShuiYanguiNameNormalInternal,
		StrikeEffects.JingleChunShuiAlternatingNormals,
		StrikeEffects.JingleChunShuiAlternatingNormalsInternal,
		StrikeEffects.JingleChunShuiInvalidateIfOpponentDeckOverNine,
		StrikeEffects.JingleChunShuiDiscardTopdeckForPower
	]
	for effect_type in effect_types:
		var text = GameStrings.get_effect_text({ "effect_type": effect_type, "amount": 9 })
		assert_false("缺失" in text, "%s should have display text" % effect_type)
	assert_eq(GameStrings.get_on_exceed_text(player1.deck_def["on_exceed"]), "当你觉醒时：抽1\n")
	assert_eq(CardDataManager.get_card("jinglechunshui_yingsong")["boost"]["display_name"], "Youxi Yinggui")
	assert_eq(CardDataManager.get_card("jinglechunshui_yangui")["boost"]["display_name"], "Youxi Yangui")

func test_character_animation_resources_use_distinct_normal_and_exceed_textures():
	var normal_path = CharSkinManager.get_animation_path_for_deck_id("jinglechunshui")
	var exceed_path = CharSkinManager.get_animation_path_for_deck_id("jinglechunshui_exceed")
	assert_eq(normal_path, "res://assets/character_animations_custom/jinglechunshui/animations.tres")
	assert_eq(exceed_path, "res://assets/character_animations_custom/jinglechunshui_exceed/animations.tres")
	var normal_frames = load(normal_path) as SpriteFrames
	var exceed_frames = load(exceed_path) as SpriteFrames
	assert_not_same(normal_frames, exceed_frames)
	assert_eq(normal_frames.get_frame_texture("idle", 0).resource_path, "res://assets/portraits/custom.png")
	assert_eq(exceed_frames.get_frame_texture("idle", 0).resource_path, "res://assets/portraits/custom.png")
	var normal_text = FileAccess.get_file_as_string(normal_path)
	var exceed_text = FileAccess.get_file_as_string(exceed_path)
	var normal_parsed = Character._parse_sprite_frames_tres(normal_text, normal_path.get_base_dir())
	var exceed_parsed = Character._parse_sprite_frames_tres(exceed_text, exceed_path.get_base_dir())
	assert_eq(normal_parsed["texture_paths"].values()[0],
		"res://assets/character_animations_custom/jinglechunshui/jinglechunshui_default.png")
	assert_eq(exceed_parsed["texture_paths"].values()[0],
		"res://assets/character_animations_custom/jinglechunshui_exceed/jinglechunshui_exceed.png")

func test_zhangui_attack_advances_closes_and_dodges_at_long_range():
	for card in player1.hand.duplicate():
		if card.definition["id"] == "jinglechunshui_bujingdule":
			player1.move_card_from_hand_to_deck(card.id)
	position_players(player1, 3, player2, 7)
	execute_strike(player1, player2, "jinglechunshui_zhangui", "standard_normal_sweep",
		false, false, [0, 1], [])
	validate_positions(player1, 5, player2, 7)
	validate_life(player1, 26, player2, 30)

func test_zhangui_boost_draws_two_and_spends_life_when_hit():
	var boost_id = give_player_specific_card(player1, "jinglechunshui_zhangui")
	assert_true(game_logic.do_boost(player1, boost_id))
	_pass_optional_strike(player1)
	advance_turn(player2)
	var deck_before = player1.deck.size()
	position_players(player1, 4, player2, 5)
	execute_strike(player1, player2, "standard_normal_focus", "standard_normal_assault")
	assert_eq(player1.deck.size(), deck_before - 3)
	assert_eq(player1.life, 27)

func test_zhangui_boost_draws_two_without_life_when_not_hit():
	var boost_id = give_player_specific_card(player1, "jinglechunshui_zhangui")
	assert_true(game_logic.do_boost(player1, boost_id))
	_pass_optional_strike(player1)
	advance_turn(player2)
	var deck_before = player1.deck.size()
	position_players(player1, 4, player2, 5)
	execute_strike(player1, player2, "standard_normal_assault", "standard_normal_block", false, false, [0], [[]])
	assert_eq(player1.deck.size(), deck_before - 2)
	assert_eq(player1.life, 30)

func test_zhangui_boost_unhit_draw_can_only_be_chosen_once_among_hit_effects():
	var boost_id = give_player_specific_card(player1, "jinglechunshui_zhangui")
	var boost_card = game_logic.get_card_database().get_card(boost_id)
	player1.remove_card_from_hand(boost_id, false, false)
	player1.add_to_continuous_boosts(boost_card)
	var deck_before = player1.deck.size()
	position_players(player1, 3, player2, 5)
	var initiator_card_id = give_player_specific_card(player1, "jinglechunshui_yingsong")
	var defender_card_id = give_player_specific_card(player2, "standard_normal_block")
	do_and_validate_strike(player1, initiator_card_id)
	do_strike_response(player2, defender_card_id)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseSimultaneousEffect)
	var zhangui_effect_index = -1
	for effect_index in range(game_logic.decision_info.choice.size()):
		if game_logic.decision_info.choice[effect_index].get("card_id", -1) == boost_id:
			zhangui_effect_index = effect_index
			break
	assert_ne(zhangui_effect_index, -1)
	assert_true(game_logic.do_choice(player1, zhangui_effect_index))
	assert_eq(player1.deck.size(), deck_before - 2)
	assert_false(game_logic.active_strike.remaining_effect_list.any(func(remaining_effect):
		return remaining_effect.get("card_id", -1) == boost_id
	))

func test_zhangui_boost_has_its_summary_text():
	var boost_effect = CardDataManager.get_card("jinglechunshui_zhangui")["boost"]["effects"][0]
	assert_eq(boost_effect["override_description"], "击中：你未被击中,摸2张牌；你已被击中，支付1点生命，摸2张牌，随机弃掉1张牌。")

func test_yingsong_attack_can_pay_two_force_and_gains_advantage_after_passing():
	var force_ids = [
		give_player_specific_card(player1, "standard_normal_block"),
		give_player_specific_card(player1, "standard_normal_block")
	]
	position_players(player1, 3, player2, 5)
	execute_strike(player1, player2, "jinglechunshui_yingsong", "standard_normal_focus",
		false, false, [0, force_ids], [])
	validate_positions(player1, 6, player2, 5)
	assert_eq(player2.life, 27)
	assert_eq(game_logic.active_turn_player, player1.my_id)

func test_yingsong_boost_gives_both_attacks_power_and_ignores_armor():
	var boost_id = give_player_specific_card(player1, "jinglechunshui_yingsong")
	assert_true(game_logic.do_boost(player1, boost_id))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player1, 0))
	position_players(player1, 4, player2, 5)
	execute_strike(player1, player2, "standard_normal_focus", "standard_normal_focus",
		false, false, [0, 0, 0, 0, 0], [0, 0, 0])
	assert_eq(player2.life, 25)
	assert_eq(player1.life, 25)

func test_yingsong_boost_has_one_complete_both_players_hit_effect_and_summary_text():
	var boost_effects = CardDataManager.get_card("jinglechunshui_yingsong")["boost"]["effects"]
	assert_eq(boost_effects.size(), 1)
	assert_eq(boost_effects[0]["timing"], "both_players_hit")
	assert_eq(boost_effects[0]["effect_type"], StrikeEffects.Powerup)
	assert_eq(boost_effects[0]["and"]["effect_type"], StrikeEffects.IgnoreArmor)
	assert_eq(boost_effects[0]["override_description"], "双方玩家具有“威力+1，无视护甲”")

func test_yingsong_boost_is_one_complete_choice_among_other_hit_effects():
	var boost_id = give_player_specific_card(player1, "jinglechunshui_yingsong")
	var boost_card = game_logic.get_card_database().get_card(boost_id)
	player1.remove_card_from_hand(boost_id, false, false)
	player1.add_to_continuous_boosts(boost_card)
	position_players(player1, 3, player2, 5)
	var attack_id = give_player_specific_card(player1, "standard_normal_sweep")
	var defense_id = give_player_specific_card(player2, "standard_normal_block")
	execute_strike(player1, player2, attack_id, defense_id, false, false, [], [], true)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseSimultaneousEffect)
	assert_eq(game_logic.decision_info.choice.size(), 2)
	var boost_effect_index = -1
	for effect_index in range(game_logic.decision_info.choice.size()):
		if game_logic.decision_info.choice[effect_index].get("card_id", -1) == boost_id:
			boost_effect_index = effect_index
			break
	assert_ne(boost_effect_index, -1)
	assert_true(game_logic.do_choice(player1, boost_effect_index))
	assert_ne(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseSimultaneousEffect)

func test_yinggui_attack_uses_exact_distance_and_ignores_armor():
	position_players(player1, 3, player2, 7)
	execute_strike(player1, player2, "jinglechunshui_yinggui", "standard_normal_focus")
	validate_life(player1, 30, player2, 25)

func test_yinggui_boost_draw_choice_after_opponent_sets():
	var boost_id = give_player_specific_card(player1, "jinglechunshui_yinggui")
	var boost_card = game_logic.get_card_database().get_card(boost_id)
	player1.remove_card_from_hand(boost_id, false, false)
	player1.add_to_continuous_boosts(boost_card)
	assert_true(player1.is_card_in_continuous_boosts(boost_id))
	var set_strike_effects = player1.get_set_strike_effects(null)
	assert_eq(set_strike_effects.size(), 1)
	assert_eq(set_strike_effects[0]["effect_type"], StrikeEffects.StrikeEffectAfterOpponentSets)
	var deck_before = player1.deck.size()
	position_players(player1, 4, player2, 5)
	var initiator_card_id = give_player_specific_card(player1, "standard_normal_assault")
	var defender_card_id = give_player_specific_card(player2, "standard_normal_focus")
	assert_eq(game_logic.active_turn_player, player1.my_id, "京乐必须在自己的回合设置攻击牌。")
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction, "设置攻击前必须处于行动阶段。")
	do_and_validate_strike(player1, initiator_card_id)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_Strike_Opponent_Response, "京乐设置攻击后必须等待对手响应。")
	do_strike_response(player2, defender_card_id)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision, "对手设置攻击后、揭示前必须暂停影鬼选择。")
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player1.deck.size(), deck_before - 1)

func test_yinggui_boost_can_spend_life_to_advance_after_both_set():
	var boost_id = give_player_specific_card(player1, "jinglechunshui_yinggui")
	var boost_card = game_logic.get_card_database().get_card(boost_id)
	player1.remove_card_from_hand(boost_id, false, false)
	player1.add_to_continuous_boosts(boost_card)
	position_players(player1, 3, player2, 6)
	var initiator_card_id = give_player_specific_card(player1, "standard_normal_block")
	var defender_card_id = give_player_specific_card(player2, "standard_normal_block")
	do_and_validate_strike(player1, initiator_card_id)
	do_strike_response(player2, defender_card_id)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_true(game_logic.do_choice(player1, 1))
	assert_eq(player1.life, 29)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player1.life, 29)
	validate_positions(player1, 4, player2, 6)

func test_yinggui_boost_has_its_summary_text():
	var boost_effect = CardDataManager.get_card("jinglechunshui_yinggui")["boost"]["effects"][0]
	assert_eq(boost_effect["override_description"], "在双方玩家都设置好战斗卡后（在揭示战斗卡之前），你可以选择抽1张牌，或者支付1点生命来前进/后退1格。")

func test_bujingdule_attack_chooses_two_and_returns_to_hand_after_paying_force():
	var attack_cost_id = give_player_specific_card(player1, "standard_normal_block")
	var return_cost_id = give_player_specific_card(player1, "standard_normal_block")
	var deck_before = player1.deck.size()
	position_players(player1, 3, player2, 6)
	var strike_cards = execute_strike(player1, player2, "jinglechunshui_bujingdule", "standard_normal_block",
		false, false, [[attack_cost_id], 0, 3, [return_cost_id]], [[]])
	assert_eq(player2.life, 29)
	assert_true(player1.is_card_in_hand(strike_cards[0]))
	assert_true(player1.is_card_in_discards(attack_cost_id))
	assert_eq(player1.gauge.size(), 1)
	assert_eq(player1.deck.size(), deck_before - 2)

func test_bujingdule_boost_damages_player_who_moved_less():
	var boost_id = give_player_specific_card(player1, "jinglechunshui_bujingdule")
	assert_true(game_logic.do_boost(player1, boost_id))
	_pass_optional_strike(player1)
	advance_turn(player2)
	position_players(player1, 4, player2, 5)
	execute_strike(player1, player2, "standard_normal_cross", "standard_normal_assault")
	assert_eq(player2.life, 25)

func test_zhangui_after_effects_are_a_single_ordered_trigger():
	var effects = CardDataManager.get_card("jinglechunshui_zhangui")["effects"]
	var after_effects = effects.filter(func(effect): return effect.get("timing") == "after")
	assert_eq(after_effects.size(), 1)
	assert_eq(after_effects[0]["effect_type"], StrikeEffects.Close)
	assert_eq(after_effects[0]["and"]["effect_type"], StrikeEffects.Armorup)

func test_zhangui_cleanup_boosts_bujingdule_without_ua_and_resolves_cleanup():
	var bujingdule_id = give_player_specific_card(player1, "jinglechunshui_bujingdule")
	position_players(player1, 3, player2, 7)
	execute_strike(player1, player2, "jinglechunshui_zhangui", "standard_normal_focus",
		false, false, [], [], true)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostNow)
	assert_true(game_logic.do_boost(player1, bujingdule_id))
	assert_true(player1.is_card_in_continuous_boosts(bujingdule_id))
	assert_ne(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)
	assert_eq(player2.life, 30)
	var damage_events = game_logic.get_latest_events().filter(func(event):
		return event['event_type'] == Enums.EventType.EventType_Strike_TookDamage \
			and event['event_player'] == player2.my_id)
	assert_eq(damage_events.size(), 1)

func test_yangui_attack_discards_named_normal_for_power_and_ignore_guard():
	var named_id = give_player_specific_card(player2, "standard_normal_assault")
	var named_cards_in_hand = player2.hand.filter(
		func(card): return card.definition['id'] == "standard_normal_assault").size()
	position_players(player1, 4, player2, 5)
	execute_strike(player1, player2, "jinglechunshui_yangui", "standard_normal_focus",
		false, false, [named_id], [])
	assert_eq(player2.life, 29)
	assert_eq(player2.hand.filter(
		func(card): return card.definition['id'] == "standard_normal_assault").size(), named_cards_in_hand - 1)
	assert_true(player2.discards.any(
		func(card): return card.definition['id'] == "standard_normal_assault"))

func test_yangui_boost_alternates_normal_names_then_forces_strike():
	var p1_named_id = give_player_specific_card(player1, "standard_normal_assault")
	var p2_named_id = give_player_specific_card(player2, "standard_normal_cross")
	var boost_id = give_player_specific_card(player1, "jinglechunshui_yangui")
	assert_true(game_logic.do_boost(player1, boost_id))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ReadingNormal)
	assert_true(game_logic.do_boost_name_card_choice_effect(player1, p1_named_id))
	assert_eq(player1.jinglechunshui_named_normal_powerups, ["standard_normal_assault"])
	assert_eq(game_logic.decision_info.player, player2.my_id)
	assert_true(game_logic.do_boost_name_card_choice_effect(player2, p2_named_id))
	assert_eq(player1.jinglechunshui_named_normal_powerups, ["standard_normal_assault", "standard_normal_cross"])
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)
	position_players(player1, 4, player2, 5)
	execute_strike(player1, player2, "standard_normal_assault", "standard_normal_focus")
	assert_eq(player2.life, 27)

func test_yuyingzhong_attack_costs_one_gauge_while_exceeded_and_gains_power_after_passing():
	player1.exceed()
	var gauge_ids = give_gauge(player1, 1)
	position_players(player1, 3, player2, 5)
	execute_strike(player1, player2, "jinglechunshui_yuyingzhong", "standard_normal_block",
		false, false, [gauge_ids, 0], [[], 0])
	validate_positions(player1, 7, player2, 5)
	assert_eq(player2.life, 25)
	assert_false(player1.gauge.any(func(card): return card.id == gauge_ids[0]))

func test_yuyingzhong_before_effects_are_a_single_ordered_trigger():
	var effects = CardDataManager.get_card("jinglechunshui_yuyingzhong")["effects"]
	var before_effects = effects.filter(func(effect): return effect.get("timing") == "before")
	assert_eq(before_effects.size(), 1)
	assert_eq(before_effects[0]["effect_type"], StrikeEffects.Advance)
	assert_eq(before_effects[0]["amount"], 3)
	assert_eq(before_effects[0]["and"]["condition"], "moved_past_this_strike")
	assert_eq(before_effects[0]["and"]["effect_type"], StrikeEffects.Powerup)
	assert_eq(before_effects[0]["and"]["amount"], 4)

func test_yuyingzhong_boost_spends_five_draws_three_and_heals_after_strike():
	var hand_before = player1.hand.size()
	var boost_id = give_player_specific_card(player1, "jinglechunshui_yuyingzhong")
	assert_true(game_logic.do_boost(player1, boost_id))
	assert_eq(player1.life, 25)
	assert_eq(player1.hand.size(), hand_before + 3)
	position_players(player1, 4, player2, 5)
	execute_strike(player1, player2, "standard_normal_focus", "standard_normal_block",
		false, false, [0], [[]])
	assert_eq(player1.life, 27)

func test_zhongyanzhimu_attack_costs_one_gauge_while_exceeded_and_discards_nine_for_power():
	player1.exceed()
	var gauge_ids = give_gauge(player1, 1)
	player2.deck.resize(9)
	var deck_before = player1.deck.size()
	position_players(player1, 3, player2, 5)
	execute_strike(player1, player2, "jinglechunshui_zhongyanzhimu", "standard_normal_block",
		false, false, [gauge_ids, 9], [[], 0])
	assert_eq(player2.life, 23)
	assert_eq(player1.deck.size(), deck_before - 9)
	assert_false(player1.gauge.any(func(card): return card.id == gauge_ids[0]))

func test_zhongyanzhimu_boost_adds_power_and_opponent_can_discard_top_four():
	var boost_id = give_player_specific_card(player1, "jinglechunshui_zhongyanzhimu")
	assert_true(game_logic.do_boost(player1, boost_id))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player1, 1))
	advance_turn(player2)
	var opponent_deck_before = player2.deck.size()
	position_players(player1, 4, player2, 5)
	execute_strike(player1, player2, "standard_normal_focus", "standard_normal_block",
		false, false, [], [1, []])
	assert_eq(player2.life, 27)
	assert_eq(player2.deck.size(), opponent_deck_before - 4)

func test_zhongyanzhimu_boost_summary_hides_now_effect_and_describes_persistent_effects():
	var boost_effects = CardDataManager.get_card("jinglechunshui_zhongyanzhimu")["boost"]["effects"]
	assert_true(boost_effects[1]["hide_in_boost_summary"])
	assert_eq(boost_effects[0]["override_description"], "+1 威力")
	assert_eq(boost_effects[2]["override_description"], "击中：对手选择：“随机弃掉1张手牌并且弃掉1点怒气（若有）”，或者“弃掉牌堆顶的4张牌”。")
	assert_eq(boost_effects[2]["choice"][1]["_choice_text"], "从你的牌堆顶弃掉4张牌")

func test_zhongyanzhimu_boost_opponent_discards_remaining_topdeck_when_fewer_than_four():
	var boost_id = give_player_specific_card(player1, "jinglechunshui_zhongyanzhimu")
	assert_true(game_logic.do_boost(player1, boost_id))
	assert_true(game_logic.do_choice(player1, 1))
	advance_turn(player2)
	player2.deck.resize(2)
	position_players(player1, 4, player2, 5)
	execute_strike(player1, player2, "standard_normal_focus", "standard_normal_block",
		false, false, [], [1, []])
	assert_eq(player2.deck.size(), 0)

func test_zhongyanzhimu_boost_spend_life_strikes_before_exceeded_ua():
	player1.exceed()
	var boost_id = give_player_specific_card(player1, "jinglechunshui_zhongyanzhimu")
	assert_true(game_logic.do_boost(player1, boost_id))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player1.life, 28)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)

func test_zhongyanzhimu_boost_pass_uses_exceeded_ua_choice():
	player1.exceed()
	var boost_id = give_player_specific_card(player1, "jinglechunshui_zhongyanzhimu")
	assert_true(game_logic.do_boost(player1, boost_id))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player1, 1))
	assert_eq(player1.life, 30)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)

func test_zhongyanzhimu_invalid_over_nine_cards_replaces_it_with_wild_swing():
	var wild_id = give_player_specific_card(player1, "standard_normal_assault")
	player1.move_card_from_hand_to_deck(wild_id)
	position_players(player1, 4, player2, 5)
	var strike_cards = execute_strike(player1, player2, "jinglechunshui_zhongyanzhimu", "standard_normal_focus")
	assert_true(player1.is_card_in_discards(strike_cards[0]))
	assert_true(player1.is_card_in_gauge(wild_id))
	validate_life(player1, 26, player2, 28)

func test_normal_special_boost_pass_choice_resolves_once():
	var boost_id = give_player_specific_card(player1, "jinglechunshui_yingsong")
	assert_true(game_logic.do_boost(player1, boost_id))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player1, 1))
	assert_ne(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(player1.is_card_in_continuous_boosts(boost_id))

func test_exceeded_continuous_boost_pass_choice_resolves_once():
	player1.exceed()
	var boost_id = give_player_specific_card(player1, "jinglechunshui_yingsong")
	assert_true(game_logic.do_boost(player1, boost_id))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player1, 1))
	assert_false(game_logic.decision_info.type == Enums.DecisionType.DecisionType_EffectChoice and game_logic.decision_info.player == player1.my_id)
	assert_true(player1.is_card_in_continuous_boosts(boost_id))

func test_bujingdule_choose_two_removes_the_first_selected_option():
	var attack_id = give_player_specific_card(player1, "jinglechunshui_bujingdule")
	var attack_cost_id = give_player_specific_card(player1, "standard_normal_block")
	var defense_id = give_player_specific_card(player2, "standard_normal_block")
	position_players(player1, 3, player2, 6)
	execute_strike(player1, player2, attack_id, defense_id,
		false, false, [[attack_cost_id], 0], [], true)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.choice.size(), 5)
	var selected_effect_type = game_logic.decision_info.choice[0]["effect_type"]
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.choice.size(), 4)
	assert_false(game_logic.decision_info.choice.any(
		func(choice): return choice["effect_type"] == selected_effect_type))

func test_bujingdule_hit_opponent_chooses_exactly_one_card_to_discard():
	var attack_id = give_player_specific_card(player1, "jinglechunshui_bujingdule")
	var attack_cost_id = give_player_specific_card(player1, "standard_normal_block")
	var defense_id = give_player_specific_card(player2, "standard_normal_block")
	var discarded_id = give_player_specific_card(player2, "standard_normal_focus")
	var retained_id = give_player_specific_card(player2, "standard_normal_assault")
	position_players(player1, 3, player2, 6)
	execute_strike(player1, player2, attack_id, defense_id,
		false, false, [[attack_cost_id], 3], [], true)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player1, 3))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseToDiscard)
	assert_eq(game_logic.decision_info.player, player2.my_id)
	assert_true(game_logic.do_choose_to_discard(player2, [discarded_id]))
	assert_true(player2.is_card_in_discards(discarded_id))
	assert_true(player2.is_card_in_hand(retained_id))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.decision_info.choice.size(), 4)
	assert_false(game_logic.decision_info.choice.any(
		func(choice): return choice["effect_type"] == StrikeEffects.OpponentDiscardChoose))
	var remaining_choice_texts = game_logic.decision_info.choice.map(func(choice): return choice.get("_choice_text", ""))
	assert_true(game_logic.do_choice(player1, 0))
	if game_logic.decision_info.type == Enums.DecisionType.DecisionType_EffectChoice:
		var next_choice_texts = game_logic.decision_info.choice.map(func(choice): return choice.get("_choice_text", ""))
		assert_ne(next_choice_texts, remaining_choice_texts)