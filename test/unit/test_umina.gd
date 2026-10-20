extends ExceedGutTest

func who_am_i():
	return "umina"

func _prepare_terror_whispers_transform() -> void:
	var tf1 = give_player_specific_card(player1, "umina_terror_whispers")
	var tf2 = give_player_specific_card(player1, "umina_terror_whispers")
	assert_true(game_logic.do_ex_transform(player1, tf1, tf2))
	# Transform action ends the current turn. Advance opponent turn to get back to p1.
	advance_turn(player2)

func _find_twh_action_index() -> int:
	var actions = player1.get_bonus_actions()
	for i in range(actions.size()):
		if actions[i].get("effect_type", "") == "umina_terror_whispers_action":
			return i
	return -1

func test_terror_whispers_action_requires_2_gauge():
	_prepare_terror_whispers_transform()
	var action_idx = _find_twh_action_index()
	assert_ne(action_idx, -1)
	assert_eq(player1.get_available_gauge(), 0)
	assert_false(game_logic.do_bonus_turn_action(player1, action_idx))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)

func test_terror_whispers_action_pay_then_force_opponent_wild_swing():
	_prepare_terror_whispers_transform()
	var action_idx = _find_twh_action_index()
	assert_ne(action_idx, -1)

	var gauge_ids = give_gauge(player1, 2)
	assert_true(game_logic.do_bonus_turn_action(player1, action_idx))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_GaugeForEffect)
	assert_eq(game_logic.decision_info.effect.get("gauge_max", -1), 2)
	assert_true(game_logic.do_gauge_for_effect(player1, gauge_ids))

	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_StrikeNow)

	# Stabilize opponent wild swing to a known normal card to avoid cost-side branches.
	set_player_topdeck(player2, "standard_normal_assault")
	var strike_id = give_player_specific_card(player1, "standard_normal_assault")
	assert_true(game_logic.do_strike(player1, strike_id, false, -1))
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_Strike_ForceWildSwing, player1)
	assert_false(player1.opponent_next_strike_forced_wild_swing)

func test_terror_whispers_action_cancel_gauge_payment_returns_without_strike():
	_prepare_terror_whispers_transform()
	var action_idx = _find_twh_action_index()
	assert_ne(action_idx, -1)

	give_gauge(player1, 2)
	assert_eq(game_logic.active_turn_player, player1.my_id)
	assert_true(game_logic.do_bonus_turn_action(player1, action_idx))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_GaugeForEffect)

	# Cancel/Pass from the gauge payment step.
	assert_true(game_logic.do_gauge_for_effect(player1, []))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_None)
	assert_eq(game_logic.active_turn_player, player1.my_id)


# ===== Dark Thoughts hit: optional Dreamlands placement (2026-08-06) =====

func has_def_in_zone(_player, def_id, zone):
	for card in zone:
		if card.definition.get("id", "") == def_id:
			return true
	return false

func test_dark_thoughts_choose_to_place():
	position_players(player1, 3, player2, 5)  # distance 2, Dark Thoughts R2-5 hits
	player2.hand.clear()
	give_player_specific_card(player2, "standard_normal_spike")
	# Dark Thoughts R2-5 P6 S2 vs Grasp(R1) at dist2 -> Grasp misses.
	# hit: opponent discards the only card (Spike) -> choice:
	#   idx0 = put into Dreamlands, idx1 = don't put.
	# Dark Thoughts is a transform (Spiraling Descent) so a transform offer
	# follows the hit choice: pass (idx1).
	execute_strike(player1, player2, "umina_dark_thoughts", "standard_normal_grasp",
		false, false,
		[0, 1],  # hit choice: put into Dreamlands; transform offer: pass
		[])
	assert_true(has_def_in_zone(player1, "standard_normal_spike", player1.set_aside_cards),
		"Chosen card should be in Dreamlands")
	assert_false(has_def_in_zone(player2, "standard_normal_spike", player2.discards),
		"Chosen card should be removed from opponent discard")

func test_dark_thoughts_choose_not_to_place():
	position_players(player1, 3, player2, 5)
	player2.hand.clear()
	give_player_specific_card(player2, "standard_normal_spike")
	execute_strike(player1, player2, "umina_dark_thoughts", "standard_normal_grasp",
		false, false,
		[1, 1],  # hit choice: don't put (Pass); transform offer: pass
		[])
	assert_eq(player1.set_aside_cards.size(), 0,
		"Not chosen: Dreamlands must stay empty")
	assert_true(has_def_in_zone(player2, "standard_normal_spike", player2.discards),
		"Not chosen: card should remain in opponent discard")

func test_dark_thoughts_cannot_place_shadow_chorus():
	# Opponent is Umina too; the discarded card is a Shadow Chorus, which can
	# never enter Dreamlands. The choice must only offer "don't put" (idx0).
	default_game_setup("umina")
	position_players(player1, 3, player2, 5)
	player2.hand.clear()
	give_player_specific_card(player2, "umina_shadow_chorus")
	execute_strike(player1, player2, "umina_dark_thoughts", "standard_normal_grasp",
		false, false,
		[0, 1],  # hit choice: only Pass available; transform offer: pass
		[])
	assert_eq(player1.set_aside_cards.size(), 0,
		"Shadow Chorus must not be placed into Dreamlands")
	assert_true(has_def_in_zone(player2, "umina_shadow_chorus", player2.discards),
		"Shadow Chorus should remain in opponent discard")

func test_reading_dreamlands_card_offered_and_can_reveal_hand():
	# 非觉醒 umina：手牌没有 sweep、幻梦境有 sweep 时，读心不再直接亮手牌，
	# 而是弹选择（从幻梦境设置 sweep 或展示手牌）。
	position_players(player1, 3, player2, 6)
	advance_turn(player1)

	player1.discard_hand()
	var dreamlands_sweep_id = give_player_specific_card(player1, "standard_normal_sweep")
	var dreamlands_sweep_card = game_logic.get_card_database().get_card(dreamlands_sweep_id)
	var shadow_chorus_id = give_player_specific_card(player1, "umina_shadow_chorus")
	player1.remove_card_from_hand(dreamlands_sweep_id, false, false)
	player1.add_to_set_aside(dreamlands_sweep_card)

	assert_true(player1.is_card_in_set_aside(dreamlands_sweep_id))
	assert_false(has_def_in_zone(player1, "standard_normal_sweep", player1.hand))
	assert_true(has_def_in_zone(player1, "umina_shadow_chorus", player1.hand))

	var reading_id = give_player_specific_card(player2, "standard_normal_focus")
	var assault_id = give_player_specific_card(player2, "standard_normal_assault")
	assert_true(game_logic.do_boost(player2, reading_id))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ReadingNormal)
	assert_true(game_logic.do_boost_name_card_choice_effect(player2, dreamlands_sweep_id))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)

	assert_true(game_logic.do_strike(player2, assault_id, false, -1))
	# 弹选择（2 选项），而非直接亮手牌
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseSimultaneousEffect)
	assert_eq(game_logic.decision_info.choice.size(), 2, "应有 2 个选项：幻梦境 sweep + 展示手牌")
	# 选「展示手牌」→ 亮手牌，幻梦境 sweep 保留
	assert_true(game_logic.do_choice(player1, 1), "选择展示手牌失败")
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_RevealHand, player1)
	assert_true(player1.is_card_in_set_aside(dreamlands_sweep_id), "选展示手牌时幻梦境 sweep 应保留")

# Spiraling Descent 的描述必须说明「攻击视为无效」，而不是「不能发起战斗」。
# 实现侧对手可以照常设置该攻击，只是该攻击走标准 invalid 流程（卡进弃牌堆 + 改为疯狂攻击）。
func test_spiraling_descent_description_says_attack_is_invalid():
	var card_def = CardDataManager.get_card("umina_dark_thoughts")
	assert_not_null(card_def, "应能读到 Dark Thoughts 定义")
	var boost_effects = card_def.get("boost", {}).get("effects", [])
	assert_gt(boost_effects.size(), 0, "Spiraling Descent 应有效果")

	var text = GameStrings.get_effect_text(boost_effects[0])
	assert_true(text.find("视为无效攻击") != -1,
		"描述应说明用同名牌发起的攻击视为无效攻击（实际：%s）" % text)
	assert_true(text.find("发起战斗") == -1,
		"描述不应再说「不能发起战斗」—— 对手可以发起，只是该攻击无效（实际：%s）" % text)


func _umina_empty_deck_with_hand_cards() -> Array:
	position_players(player1, 3, player2, 6)
	advance_turn(player1)
	player1.discard_hand()
	player1.deck.clear()
	player1.reset_public_hand_knowledge()
	var ids = []
	ids.append(give_player_specific_card(player1, "standard_normal_sweep"))
	ids.append(give_player_specific_card(player1, "standard_normal_assault"))
	ids.append(give_player_specific_card(player1, "standard_normal_focus"))
	return ids

func _umina_place_hand_card_into_dreamlands(card_id : int) -> void:
	game_logic.do_effect_if_condition_met(player1, -1, {
		"effect_type": "umina_place_hand_to_dreamlands_do",
		"card_id_to_add": card_id
	}, null)

func test_empty_deck_does_not_reveal_hand_with_facedown_hand_card_in_dreamlands():
	var ids = _umina_empty_deck_with_hand_cards()
	player1.umina_dreamlands_facedown = true
	_umina_place_hand_card_into_dreamlands(ids[0])
	assert_true(player1.is_card_in_set_aside(ids[0]))
	assert_true(player1.has_umina_facedown_hand_card_in_dreamlands())
	player1.update_public_hand_if_deck_empty()
	assert_eq(player1.get_public_hand_info()["known"].size(), 0, "幻梦境有面朝下手牌时不应展示手牌")

func test_empty_deck_reveals_hand_without_facedown_hand_card_in_dreamlands():
	var ids = _umina_empty_deck_with_hand_cards()
	player1.update_public_hand_if_deck_empty()
	assert_eq(player1.get_public_hand_info()["known"].size(), 3, "幻梦境无面朝下手牌时应照常展示手牌")

func test_empty_deck_reveals_hand_when_dreamlands_hand_card_was_faceup():
	var ids = _umina_empty_deck_with_hand_cards()
	_umina_place_hand_card_into_dreamlands(ids[0])
	assert_false(player1.has_umina_facedown_hand_card_in_dreamlands())
	player1.update_public_hand_if_deck_empty()
	assert_eq(player1.get_public_hand_info()["known"].size(), 2, "面朝上放入时应照常展示手牌")

func test_empty_deck_reveals_hand_after_facedown_hand_card_was_revealed():
	var ids = _umina_empty_deck_with_hand_cards()
	player1.umina_dreamlands_facedown = true
	_umina_place_hand_card_into_dreamlands(ids[0])
	player1.umina_revealed_dreamlands_ids.append(ids[0])
	assert_false(player1.has_umina_facedown_hand_card_in_dreamlands())
	player1.update_public_hand_if_deck_empty()
	assert_eq(player1.get_public_hand_info()["known"].size(), 2)

func test_empty_deck_reveals_hand_after_facedown_hand_card_left_dreamlands():
	var ids = _umina_empty_deck_with_hand_cards()
	player1.umina_dreamlands_facedown = true
	_umina_place_hand_card_into_dreamlands(ids[0])
	player1.remove_card_from_set_aside(ids[0])
	assert_false(player1.has_umina_facedown_hand_card_in_dreamlands())
	player1.update_public_hand_if_deck_empty()
	assert_eq(player1.get_public_hand_info()["known"].size(), 2)

func test_empty_deck_reveals_hand_for_other_character_regardless_of_umina_flag():
	_umina_empty_deck_with_hand_cards()
	player2.deck.clear()
	player2.reset_public_hand_knowledge()
	player2.hand.clear()
	give_player_specific_card(player2, "standard_normal_sweep")
	player2.update_public_hand_if_deck_empty()
	assert_eq(player2.get_public_hand_info()["known"].size(), 1)
