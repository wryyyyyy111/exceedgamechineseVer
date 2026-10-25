extends ExceedGutTest

const ICE_IDS = [
	"dongshilang_冰刃",
	"dongshilang_冰之虚像",
	"dongshilang_滑翔",
	"dongshilang_绝空",
	"dongshilang_棱形冰壁",
]

func who_am_i():
	return "dongshilang"

func _find_effect_by_type(effects: Array, effect_type: String) -> Dictionary:
	for effect in effects:
		if effect.get("effect_type", "") == effect_type:
			return effect
	return {}

func _assert_has_effect(effects: Array, effect_type: String, message: String = ""):
	assert_true(_find_effect_by_type(effects, effect_type).size() > 0, message if message else "缺少效果 %s" % effect_type)

func _assert_ice_attack_and_common_boost(def_id: String, key_effect_type: String):
	var def = CardDataManager.get_card(def_id)
	assert_eq(def.get("type", ""), "ice_crystal", "%s 应为冰晶类型" % def_id)
	assert_eq(def.get("effects", []).size(), 0, "%s 攻击部分应无效果" % def_id)

	var boost = def.get("boost", {})
	assert_eq(boost.get("boost_type", ""), "continuous", "%s 应为持续加成" % def_id)
	var boost_effects = boost.get("effects", [])
	_assert_has_effect(boost_effects, key_effect_type, "%s 加成应包含核心效果 %s" % [def_id, key_effect_type])

func _zone_contains_card(cards: Array, card_id: int) -> bool:
	return cards.any(func(card): return card.id == card_id)

func test_dongshilang_opening_setup_puts_two_ice_into_bleach_and_three_set_aside():
	assert_eq(player1.bleach_zone.size(), 2, "开局随机将2张冰晶置入冰晶区")
	assert_eq(player1.set_aside_cards.size(), 3, "开局后剩余3张冰晶在游戏外")

func test_dongshilang_character_config_matches_confirmed_requirements():
	var deck = CardDataManager.get_deck_from_str_id("dongshilang")

	assert_true(deck.get("hide_buddy_card_in_match", false), "对局主界面应隐藏冬狮郎固定额外卡展示")
	assert_false(deck.get("hide_ice_boost_until_exceeded", false), "实际打出的冰晶加成应正常展示")
	assert_true(deck.get("show_buddy_cards_in_extra_popout", false), "额外卡牌弹窗仍应展示冰晶")
	assert_eq(deck.get("buddy_cards", []), ICE_IDS, "额外卡牌弹窗应保留全部5张冰晶")

	var on_exceed = deck.get("on_exceed", {})
	assert_eq(on_exceed.get("ice_from_set_aside_to_bleach", -1), 1, "觉醒时应额外置入1张冰晶")
	assert_true(on_exceed.get("grant_exceed_character_action", false), "觉醒时应附带执行一次觉醒主行动")

	var exceed_ability_effects = deck.get("exceed_ability_effects", [])
	assert_gt(exceed_ability_effects.size(), 0)
	var revert_effect = exceed_ability_effects[0]
	assert_eq(revert_effect.get("required_ice_boost_count", -1), 5, "回合结束判定应以5张冰晶为阈值")
	assert_eq(revert_effect.get("count_zone", ""), "my_boost_and_bleach", "应合计我方加成区和冰晶区冰晶")
	assert_eq(revert_effect.get("override_description", ""), "回合结束时，若你的加成区与冰晶区合计冰晶牌数量不为5，退出觉醒。")

	var default_actions = deck.get("character_action_default", [])
	assert_gt(default_actions.size(), 0)
	var default_pass = default_actions[0].get("effect", {})
	assert_eq(default_pass.get("amount", -1), 1)
	assert_false(default_pass.has("can_cancel"), "角色主行动的可取消不应建模为行动前可跳过")
	assert_false(default_pass.has("pass_as_cancel_to_pick_action"), "角色主行动不应通过pass返回来实现取消")

	var exceed_actions = deck.get("character_action_exceeded", [])
	assert_gt(exceed_actions.size(), 0)
	var exceed_pass = exceed_actions[0].get("effect", {})
	assert_eq(exceed_pass.get("amount", -1), 2)
	assert_false(exceed_pass.has("can_cancel"), "觉醒主行动的可取消不应建模为行动前可跳过")
	assert_false(exceed_pass.has("pass_as_cancel_to_pick_action"), "觉醒主行动不应通过pass返回来实现取消")

	for ice_id in ICE_IDS:
		var ice_boost = CardDataManager.get_card(ice_id).get("boost", {})
		assert_eq(ice_boost.get("cancel_cost", 999), -1, "%s 应通过 cancel_cost=-1 建模可取消" % ice_id)

func test_end_of_turn_keeps_exceed_with_five_ice_in_any_zone_split():
	var remaining_ice = player1.set_aside_cards.duplicate()
	for card in remaining_ice:
		player1.remove_card_from_set_aside(card.id)
		player1.add_to_bleach(card)
	player1.exceeded = true
	for boost_count in range(6):
		if boost_count > 0:
			var card = player1.bleach_zone[0]
			player1.remove_card_from_bleach(card.id)
			player1.add_to_continuous_boosts(card)
		assert_eq(player1.continuous_boosts.size(), boost_count)
		assert_eq(player1.bleach_zone.size(), 5 - boost_count)
		player1.exceeded = true
		advance_turn(player1)
		assert_true(player1.exceeded, "%s张加成区冰晶与%s张冰晶区冰晶合计5张，应保持觉醒" % [boost_count, 5 - boost_count])
		advance_turn(player2)

func _set_up_ice_and_other_cards_in_play(ice_to_add: int):
	for index in range(ice_to_add):
		var card = player1.set_aside_cards[0]
		player1.remove_card_from_set_aside(card.id)
		player1.add_to_bleach(card)
	var ice = player1.bleach_zone[0]
	player1.remove_card_from_bleach(ice.id)
	player1.add_to_continuous_boosts(ice)
	var boost_id = give_player_specific_card(player1, "gg_normal_sweep")
	player1.remove_card_from_hand(boost_id, true, false)
	player1.add_to_continuous_boosts(game_logic.card_db.get_card(boost_id))
	var other_id = give_player_specific_card(player1, "gg_normal_grasp")
	player1.remove_card_from_hand(other_id, true, false)
	player1.add_to_bleach(game_logic.card_db.get_card(other_id))

func test_end_of_turn_keeps_exceed_when_five_ice_and_other_cards_are_in_play():
	_set_up_ice_and_other_cards_in_play(3)
	assert_eq(game_logic._dongshilang_count_ice_in_boost_zone(player1), 1)
	assert_eq(player1.bleach_zone.filter(func(card): return card.definition.get("type", "") == "ice_crystal").size(), 4)
	player1.exceeded = true
	advance_turn(player1)
	assert_true(player1.exceeded, "我方两区合计5张冰晶时保持觉醒，其他类型的牌不影响计数")

func test_end_of_turn_reverts_when_four_ice_and_other_cards_are_in_play():
	_set_up_ice_and_other_cards_in_play(2)
	assert_eq(game_logic._dongshilang_count_ice_in_boost_zone(player1), 1)
	assert_eq(player1.bleach_zone.filter(func(card): return card.definition.get("type", "") == "ice_crystal").size(), 3)
	player1.exceeded = true
	advance_turn(player1)
	assert_false(player1.exceeded, "只有4张冰晶时退出觉醒，其他类型的牌不能凑足5张")

func test_third_exceed_reaches_five_ice_and_keeps_exceed():
	for exceed_number in range(1, 4):
		player1.discard_hand()
		var gauge = give_gauge(player1, 3)
		assert_true(game_logic.do_exceed(player1, gauge.slice(0, 2)))
		assert_true(player1.exceeded)
		assert_eq(player1.set_aside_cards.size(), 3 - exceed_number)
		assert_eq(player1.bleach_zone.size() + player1.continuous_boosts.size(), 2 + exceed_number)
		for boost_number in range(mini(2, player1.bleach_zone.size())):
			assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
			assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostNow)
			assert_eq(game_logic.decision_info.player, player1.my_id)
			assert_true(game_logic.do_boost(player1, player1.bleach_zone[0].id, []))
		assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
		assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostCancel)
		assert_eq(game_logic.decision_info.player, player1.my_id)
		assert_true(game_logic.do_boost_cancel(player1, [], false))
		assert_eq(player1.exceeded, exceed_number == 3, "前两次觉醒回合结束退出，第三次达到5冰晶后保持觉醒")
		assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
		assert_eq(game_logic.get_active_player(), player2.my_id)
		if exceed_number < 3:
			advance_turn(player2)

func test_end_of_turn_reverts_with_no_ice_in_either_zone():
	for card in player1.bleach_zone.duplicate():
		player1.remove_card_from_bleach(card.id)
		player1.add_to_set_aside(card)
	player1.exceeded = true
	advance_turn(player1)
	assert_false(player1.exceeded, "两区均无冰晶时应退出觉醒")

func test_iceblade_attack_and_boost_definition():
	_assert_ice_attack_and_common_boost("dongshilang_冰刃", "dongshilang_iceblade_after_stun_bonus_damage")
	var effects = CardDataManager.get_card("dongshilang_冰刃").get("boost", {}).get("effects", [])
	var powerup = _find_effect_by_type(effects, "powerup")
	assert_eq(powerup.get("amount", -1), 1, "冰刃应提供威力+1")

func test_iceclone_attack_and_boost_definition():
	_assert_ice_attack_and_common_boost("dongshilang_冰之虚像", "dongshilang_ice_clone_no_gauge_on_hit")
	var effects = CardDataManager.get_card("dongshilang_冰之虚像").get("boost", {}).get("effects", [])
	_assert_has_effect(effects, "dongshilang_ice_clone_hit_power_if_was_hit", "冰之虚像应包含被击中后击中加威力效果")

func test_glide_attack_and_boost_definition():
	_assert_ice_attack_and_common_boost("dongshilang_滑翔", "advance")
	var effects = CardDataManager.get_card("dongshilang_滑翔").get("boost", {}).get("effects", [])
	var advance = _find_effect_by_type(effects, "advance")
	assert_eq(advance.get("amount", -1), 3, "滑翔应前进3")

func test_zekku_attack_and_boost_definition():
	_assert_ice_attack_and_common_boost("dongshilang_绝空", "dongshilang_zekku_after_range_bonus_damage")

func test_rhombus_attack_and_boost_definition():
	_assert_ice_attack_and_common_boost("dongshilang_棱形冰壁", "armorup")
	var effects = CardDataManager.get_card("dongshilang_棱形冰壁").get("boost", {}).get("effects", [])
	var armorup = _find_effect_by_type(effects, "armorup")
	assert_eq(armorup.get("amount", -1), 2, "棱形冰壁应提供护甲+2")
	_assert_has_effect(effects, "dongshilang_rhombus_hit_powerdown_if_no_armor", "棱形冰壁应包含无护甲时威力-1效果")

func test_hyoten_attack_and_boost_definition():
	var def = CardDataManager.get_card("dongshilang_冰天百花葬")
	assert_eq(def.get("gauge_cost", -1), 1)
	_assert_has_effect(def.get("effects", []), "dongshilang_hyoten_scale_by_ice_boost", "攻击应按冰晶数量提升威力")
	var boost_effects = def.get("boost", {}).get("effects", [])
	_assert_has_effect(boost_effects, "dongshilang_discard_all_other_boosts", "加成应弃置场上其他加成")

func test_longxian_attack_and_boost_definition():
	var def = CardDataManager.get_card("dongshilang_龙霰架")
	assert_eq(def.get("gauge_cost", -1), 3)
	assert_eq(def.get("gauge_cost_reduction", ""), "per_boost_in_play_of_type")
	assert_eq(def.get("gauge_cost_reduction_boost_type", ""), "ice_crystal")
	_assert_has_effect(def.get("effects", []), "pass")
	var movement_effect = _find_effect_by_type(def.get("effects", []), "convert_advance_to_close")
	assert_eq(movement_effect.get("timing", ""), "during_strike")
	_assert_has_effect(def.get("effects", []), "push")
	var boost_effects = def.get("boost", {}).get("effects", [])
	_assert_has_effect(boost_effects, "boost_then_strike", "加成应从冰晶区使用冰晶并战斗")

func test_longxian_converts_ice_glide_advance_to_close_and_clears_after_strike():
	position_players(player1, 3, player2, 5)
	var ice_id = give_player_specific_card(player1, "dongshilang_滑翔")
	var ice = game_logic.card_db.get_card(ice_id)
	player1.remove_card_from_hand(ice_id, true, false)
	player1.add_to_continuous_boosts(ice)
	var payment = give_gauge(player1, 3)
	execute_strike(player1, player2, "dongshilang_龙霰架", "standard_normal_sweep",
		false, false, [payment])
	validate_positions(player1, 4, player2, 6)
	assert_false(player1.strike_stat_boosts.convert_advance_to_close, "战斗结束后应清除移动替换")
	assert_false(player2.strike_stat_boosts.convert_advance_to_close, "不能影响对手")

func test_longxian_converts_advance_when_attacking_from_the_right():
	position_players(player1, 7, player2, 5)
	var ice_id = give_player_specific_card(player1, "dongshilang_滑翔")
	var ice = game_logic.card_db.get_card(ice_id)
	player1.remove_card_from_hand(ice_id, true, false)
	player1.add_to_continuous_boosts(ice)
	var payment = give_gauge(player1, 3)
	execute_strike(player1, player2, "dongshilang_龙霰架", "standard_normal_sweep",
		false, false, [payment])
	validate_positions(player1, 6, player2, 4)

func test_advance_conversion_preserves_amount_modifiers_and_followup_once():
	position_players(player1, 3, player2, 5)
	game_logic.handle_strike_effect(-1, {"effect_type": "convert_advance_to_close"}, player1)
	player1.strike_stat_boosts.increase_movement_effects_by = 1
	player1.strike_stat_boosts.strike_x = 2
	game_logic.handle_strike_effect(-1, {
		"effect_type": "advance", "amount": "strike_x",
		"and": {"effect_type": "powerup", "amount": 1}
	}, player1)
	validate_positions(player1, 4, player2, 5)
	assert_eq(player1.strike_stat_boosts.power, 1, "后续效果只结算一次")
	player1.strike_stat_boosts.clear()
	game_logic.handle_strike_effect(-1, {"effect_type": "advance", "amount": 3}, player2)
	assert_eq(player2.arena_location, 1, "对手原本的前进仍能穿过角色")

func test_defending_longxian_also_converts_ice_glide():
	position_players(player1, 3, player2, 5)
	var ice_id = give_player_specific_card(player2, "dongshilang_滑翔")
	var ice = game_logic.card_db.get_card(ice_id)
	player2.remove_card_from_hand(ice_id, true, false)
	player2.add_to_continuous_boosts(ice)
	var payment = give_gauge(player2, 3)
	execute_strike(player1, player2, "standard_normal_sweep", "dongshilang_龙霰架",
		false, false, [], [payment])
	validate_positions(player1, 2, player2, 4)
	assert_false(player2.strike_stat_boosts.convert_advance_to_close)

func test_other_special_keeps_ice_glide_as_advance():
	position_players(player1, 3, player2, 5)
	var ice_id = give_player_specific_card(player1, "dongshilang_滑翔")
	var ice = game_logic.card_db.get_card(ice_id)
	player1.remove_card_from_hand(ice_id, true, false)
	player1.add_to_continuous_boosts(ice)
	execute_strike(player1, player2, "dongshilang_真空冰刃", "standard_normal_sweep")
	assert_eq(player1.arena_location, 7, "其他攻击使用滑翔仍应前进并穿过对手")

func test_binghuatu_attack_and_boost_definition():
	var def = CardDataManager.get_card("dongshilang_冰华突")
	_assert_has_effect(def.get("effects", []), "advance")
	_assert_has_effect(def.get("effects", []), "dongshilang_binghuatu_hit_powerup_per_cross")
	var boost_effects = def.get("boost", {}).get("effects", [])
	var speedup = _find_effect_by_type(boost_effects, "speedup")
	assert_eq(speedup.get("amount", 0), 1)
	var powerup = _find_effect_by_type(boost_effects, "powerup")
	assert_eq(powerup.get("amount", 999), -2)
	_assert_has_effect(boost_effects, "add_to_gauge_immediately")

func test_binglong_attack_and_boost_definition():
	var def = CardDataManager.get_card("dongshilang_冰龙旋尾")
	_assert_has_effect(def.get("effects", []), "advance")
	_assert_has_effect(def.get("effects", []), "push")
	var push_effect = _find_effect_by_type(def.get("effects", []), "push")
	var conditional_power = push_effect.get("and", {})
	assert_eq(conditional_power.get("effect_type", ""), "powerup")
	assert_eq(conditional_power.get("condition", ""), "not_full_push", "未完整击退时应威力+2")
	assert_eq(conditional_power.get("amount", -1), 2)
	var boost_effects = def.get("boost", {}).get("effects", [])
	_assert_has_effect(boost_effects, "choice")
	var choice_effect = _find_effect_by_type(boost_effects, "choice")
	assert_eq(choice_effect.get("and", {}).get("effect_type", ""), "add_to_gauge_boost_play_cleanup")

func _assert_honglianlong_moves_then_enters_gauge(start: int, opponent_start: int,
		choice_index: int, expected_position: int):
	position_players(player1, start, player2, opponent_start)
	var id = give_player_specific_card(player1, "dongshilang_冰龙旋尾")
	game_logic.get_latest_events()
	assert_true(game_logic.do_boost(player1, id))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.choice.size(), 2)
	assert_false(player1.is_card_in_gauge(id), "Choose movement before sending the boost to gauge")
	assert_true(game_logic.do_choice(player1, choice_index))
	validate_positions(player1, expected_position, player2, opponent_start)
	assert_true(player1.is_card_in_gauge(id), "The boost must enter gauge after its one-space move")
	assert_false(player1.is_card_in_continuous_boosts(id))
	assert_false(player1.is_card_in_discards(id))
	assert_false(player1.is_card_in_bleach(id))
	var move_index = -1
	var gauge_index = -1
	var events = game_logic.get_latest_events()
	for index in range(events.size()):
		var event = events[index]
		if event["event_type"] == Enums.EventType.EventType_Move and event["event_player"] == player1.my_id:
			move_index = index
		if event["event_type"] == Enums.EventType.EventType_AddToGauge and event["number"] == id:
			gauge_index = index
	assert_gte(move_index, 0)
	assert_gt(gauge_index, move_index, "Gauge transfer must follow movement, even if the new distance is two")
	if game_logic.game_state == Enums.GameState.GameState_PlayerDecision:
		assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostCancel)
		assert_true(game_logic.do_boost_cancel(player1, [], false))
	assert_eq(game_logic.active_turn_player, player2.my_id)

func test_honglianlong_adjacent_advance_crosses_right_then_enters_gauge():
	_assert_honglianlong_moves_then_enters_gauge(3, 4, 0, 5)

func test_honglianlong_adjacent_advance_crosses_left_then_enters_gauge():
	_assert_honglianlong_moves_then_enters_gauge(6, 5, 0, 4)

func test_honglianlong_adjacent_retreat_left_then_enters_gauge():
	_assert_honglianlong_moves_then_enters_gauge(3, 4, 1, 2)

func test_honglianlong_adjacent_retreat_right_then_enters_gauge():
	_assert_honglianlong_moves_then_enters_gauge(6, 5, 1, 7)

func test_honglianlong_outside_range_one_stays_as_continuous_boost():
	position_players(player1, 3, player2, 5)
	var id = give_player_specific_card(player1, "dongshilang_冰龙旋尾")
	assert_true(game_logic.do_boost(player1, id))
	validate_positions(player1, 3, player2, 5)
	assert_true(player1.is_card_in_continuous_boosts(id))
	assert_false(player1.is_card_in_gauge(id))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	assert_eq(game_logic.active_turn_player, player2.my_id)

func test_honglianlong_can_cancel_using_the_card_just_added_to_gauge():
	position_players(player1, 3, player2, 4)
	var id = give_player_specific_card(player1, "dongshilang_冰龙旋尾")
	assert_true(game_logic.do_boost(player1, id))
	assert_true(game_logic.do_choice(player1, 1))
	assert_true(player1.is_card_in_gauge(id))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostCancel)
	assert_true(game_logic.do_boost_cancel(player1, [id], true))
	assert_true(player1.is_card_in_discards(id))
	assert_false(player1.is_card_in_continuous_boosts(id))
	assert_eq(game_logic.active_turn_player, player1.my_id)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)

func test_binglong_push_blocked_by_right_corner_adds_two_power():
	position_players(player1, 7, player2, 9)
	execute_strike(player1, player2, "dongshilang_冰龙旋尾", "standard_normal_sweep")
	validate_positions(player1, 8, player2, 9)
	assert_eq(player2.life, 24, "A zero-space push at the right corner must deal 4+2 damage")

func test_binglong_push_blocked_by_left_corner_adds_two_power():
	position_players(player1, 3, player2, 1)
	execute_strike(player1, player2, "dongshilang_冰龙旋尾", "standard_normal_sweep")
	validate_positions(player1, 2, player2, 1)
	assert_eq(player2.life, 24, "A zero-space push at the left corner must deal 4+2 damage")

func test_binglong_full_push_does_not_add_power():
	position_players(player1, 3, player2, 5)
	execute_strike(player1, player2, "dongshilang_冰龙旋尾", "standard_normal_sweep")
	validate_positions(player1, 4, player2, 6)
	assert_eq(player2.life, 26, "A full one-space push must only deal the printed 4 damage")

func test_binglong_push_blocked_by_focus_adds_two_power():
	position_players(player1, 3, player2, 5)
	execute_strike(player1, player2, "dongshilang_冰龙旋尾", "standard_normal_focus")
	validate_positions(player1, 4, player2, 5)
	assert_eq(player2.life, 26, "Push immunity must grant +2 power before Focus absorbs 2 damage")

func test_duanzuo_attack_and_boost_definition():
	var def = CardDataManager.get_card("dongshilang_端坐于霜天")
	_assert_has_effect(def.get("effects", []), "ignore_push_and_pull")
	_assert_has_effect(def.get("effects", []), "dongshilang_limit_self_move_to_one_this_strike")
	var boost_effects = def.get("boost", {}).get("effects", [])
	var advance = _find_effect_by_type(boost_effects, "advance")
	assert_eq(advance.get("amount", -1), 4, "冰轮丸应前进4")

func test_qunniao_attack_and_boost_definition():
	var def = CardDataManager.get_card("dongshilang_群鸟冰柱")
	assert_eq(def.get("force_cost", -1), 1)
	_assert_has_effect(def.get("effects", []), "dongshilang_convert_advance_to_retreat")
	var boost_effects = def.get("boost", {}).get("effects", [])
	_assert_has_effect(boost_effects, "block_opponent_move")

func _play_ice_prison() -> int:
	var id = give_player_specific_card(player1, "dongshilang_群鸟冰柱")
	assert_true(game_logic.do_boost(player1, id))
	assert_true(player1.is_card_in_continuous_boosts(id))
	assert_false(player2.cannot_move, "Ice Prison only blocks movement during a strike")
	return id

func test_ice_prison_blocks_during_strike_and_clears_after_cleanup():
	position_players(player1, 3, player2, 6)
	var id = _play_ice_prison()
	execute_strike(player2, player1, "standard_normal_cross", "standard_normal_sweep")
	validate_positions(player1, 3, player2, 6)
	assert_true(player1.is_card_in_discards(id))
	assert_false(player2.cannot_move, "The discarded boost must not leave a permanent movement lock")
	assert_false(id in player2.block_opponent_move_source_ids)
	assert_true(player2.can_move_to(7, true))
	execute_strike(player1, player2, "standard_normal_sweep", "standard_normal_cross")
	validate_positions(player1, 3, player2, 9)

func test_ice_prison_sustained_boost_does_not_block_outside_strike():
	position_players(player1, 3, player2, 6)
	var id = _play_ice_prison()
	player1.sustained_boosts.append(id)
	execute_strike(player2, player1, "standard_normal_cross", "standard_normal_sweep")
	validate_positions(player1, 3, player2, 6)
	assert_true(player1.is_card_in_continuous_boosts(id))
	assert_false(player2.cannot_move, "Sustaining the boost must not extend its lock outside the strike")
	assert_true(player2.can_move_to(7, true))
	execute_strike(player1, player2, "standard_normal_sweep", "standard_normal_cross")
	validate_positions(player1, 3, player2, 6)
	assert_false(player2.cannot_move)
	assert_true(player1.is_card_in_discards(id))

func test_ice_prison_leaving_early_removes_only_its_own_lock():
	var id = _play_ice_prison()
	var other_id = give_player_specific_card(player1, "jin_dualicestrike")
	game_logic.handle_strike_effect(id, {"effect_type": "block_opponent_move"}, player1)
	game_logic.handle_strike_effect(other_id, {"effect_type": "block_opponent_move"}, player1)
	assert_true(player2.cannot_move)
	player1.remove_from_continuous_boosts(game_logic.card_db.get_card(id), "gauge")
	assert_true(player1.is_card_in_gauge(id))
	assert_false(id in player2.block_opponent_move_source_ids)
	assert_true(other_id in player2.block_opponent_move_source_ids)
	assert_true(player2.cannot_move, "Removing Ice Prison must preserve an independent movement lock")
	game_logic.handle_strike_effect(other_id, {"effect_type": "remove_block_opponent_move"}, player1)
	assert_false(player2.cannot_move)

func test_ice_prison_leaving_before_strike_does_not_create_a_lock():
	var id = _play_ice_prison()
	player1.remove_from_continuous_boosts(game_logic.card_db.get_card(id), "hand")
	assert_true(player1.is_card_in_hand(id))
	assert_false(player2.cannot_move)
	assert_true(player2.block_opponent_move_source_ids.is_empty())

func test_zhenkong_attack_and_boost_definition():
	var def = CardDataManager.get_card("dongshilang_真空冰刃")
	_assert_has_effect(def.get("effects", []), "ignore_armor")
	var boost = def.get("boost", {})
	assert_eq(boost.get("boost_type", ""), "immediate")
	var boost_effects = boost.get("effects", [])
	var retreat = _find_effect_by_type(boost_effects, "retreat")
	assert_eq(retreat.get("amount", -1), 1)
	_assert_has_effect(boost_effects, "discard_continuous_boost")

func test_ice_boost_leaves_to_hand_but_returns_to_bleach():
	var ice_id = give_player_specific_card(player1, "dongshilang_冰刃")
	var ice_card = game_logic.card_db.get_card(ice_id)
	player1.remove_card_from_hand(ice_id, true, false)
	player1.add_to_continuous_boosts(ice_card)

	assert_true(player1.is_card_in_continuous_boosts(ice_id), "前置：冰晶应已在加成区")
	player1.remove_from_continuous_boosts(ice_card, "hand")

	assert_false(player1.is_card_in_continuous_boosts(ice_id), "离开后不应留在加成区")
	assert_false(_zone_contains_card(player1.hand, ice_id), "离开目标即使是手牌，也不应回手")
	assert_true(_zone_contains_card(player1.bleach_zone, ice_id), "离开加成区后应回到冰晶区")

func test_ice_boost_cleanup_to_gauge_still_returns_to_bleach():
	var ice_id = give_player_specific_card(player1, "dongshilang_冰刃")
	var ice_card = game_logic.card_db.get_card(ice_id)
	player1.remove_card_from_hand(ice_id, true, false)
	player1.add_to_continuous_boosts(ice_card)
	player1.cleanup_boost_to_gauge_cards.append(ice_id)

	player1.cleanup_continuous_boosts()

	assert_false(player1.is_card_in_continuous_boosts(ice_id), "cleanup后不应留在加成区")
	assert_false(_zone_contains_card(player1.gauge, ice_id), "即使被标记为加入怒，也应优先回到冰晶区")
	assert_true(_zone_contains_card(player1.bleach_zone, ice_id), "cleanup离开加成区后应回到冰晶区")

func test_dongshilang_special_hit_goes_to_gauge_without_bleach_choice():
	position_players(player1, 3, player2, 4)
	var strike_result = execute_strike(player1, player2, "dongshilang_真空冰刃", "standard_normal_sweep")
	var attack_card_id = strike_result[0]

	assert_true(_zone_contains_card(player1.gauge, attack_card_id), "东狮郎特技击中后应按常规进入怒气区")
	assert_false(_zone_contains_card(player1.bleach_zone, attack_card_id), "东狮郎不应出现攻击入冰晶区选项或结果")
	assert_ne(game_logic.game_state, Enums.GameState.GameState_PlayerDecision, "不应因入区二选一停在决策态")

func test_exceed_granted_ice_action_also_enters_boost_cancel_and_can_gain_extra_action():
	position_players(player1, 3, player2, 7)
	assert_eq(game_logic.get_active_player(), player1.my_id, "前置：应是我方行动回合")

	var gauge_ids = give_gauge(player1, 3)
	var gauge_id = gauge_ids[2]
	assert_true(game_logic.do_exceed(player1, gauge_ids.slice(0, 2)), "支付2怒气执行觉醒")
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostNow, "觉醒附带主行动应进入加成选择")
	assert_eq(game_logic.decision_info.amount, 2, "觉醒附带主行动应要求打出2张冰晶")

	assert_true(player1.bleach_zone.size() >= 2, "前置：觉醒后冰晶区应至少有2张冰晶")
	var first_ice_id = player1.bleach_zone[0].id
	var second_ice_id = player1.bleach_zone[1].id

	assert_true(game_logic.do_boost(player1, first_ice_id, []), "应可先打出第1张冰晶")
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostNow, "第1张冰晶后应继续要求完成角色主行动，不应立刻询问取消")
	assert_eq(game_logic.decision_info.amount, 1, "第1张冰晶后应还剩1张待打出")

	assert_true(game_logic.do_boost(player1, second_ice_id, []), "应可再打出第2张冰晶")
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostCancel, "整段角色主行动完成后才应进入一次取消决策")
	assert_eq(game_logic.decision_info.choice, 1, "取消费用应为1怒气")

	assert_true(game_logic.do_boost_cancel(player1, [gauge_id], true), "支付1怒气后应成功取消")
	validate_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Boost_ActionAfterBoost, player1)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction, "取消后应返回行动选择")
	assert_eq(game_logic.get_active_player(), player1.my_id, "取消后仍应是自己行动")

func test_ice_character_action_triggers_boost_cancel_decision_and_grants_extra_action_when_paid():
	position_players(player1, 3, player2, 7)
	assert_eq(game_logic.get_active_player(), player1.my_id, "前置：应是我方行动回合")

	var ice_id = give_player_specific_card(player1, "dongshilang_冰刃")
	var ice_card = game_logic.card_db.get_card(ice_id)
	player1.remove_card_from_hand(ice_id, true, false)
	player1.add_to_bleach(ice_card)

	var gauge_id = give_gauge(player1, 1)[0]

	assert_true(game_logic.do_character_action(player1, []), "应可执行冰晶主行动")
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostNow, "角色主行动后应进入加成选择")

	assert_true(game_logic.do_boost(player1, ice_id, []), "应可从冰晶区打出冰晶加成")
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostCancel, "打出后应进入取消决策")
	assert_eq(game_logic.decision_info.choice, 1, "取消费用应为1怒气")

	assert_true(game_logic.do_boost_cancel(player1, [gauge_id], true), "支付1怒气后应成功取消")
	validate_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_Boost_ActionAfterBoost, player1)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction, "取消后应返回行动选择")
	assert_eq(game_logic.get_active_player(), player1.my_id, "取消后仍应是自己行动")

func test_ice_action_cancel_override_cannot_bypass_shared_restrictions():
	var payment = give_gauge(player1, 1)[0]
	var ice_id = player1.bleach_zone[0].id
	assert_true(game_logic.do_character_action(player1, []))
	assert_true(game_logic.do_boost(player1, ice_id))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostCancel)
	assert_eq(game_logic.decision_info.choice, 1)
	var ice_card = game_logic.card_db.get_card(ice_id)
	assert_eq(ice_card.definition["boost"]["cancel_cost"], -1)
	for restriction in ["cancel_blocked_this_turn", "strike_on_boost_cleanup", "wild_strike_on_boost_cleanup"]:
		player1.set(restriction, true)
		assert_eq(game_logic._get_effective_boost_cancel_cost(player1, ice_card), -1, restriction)
		assert_false(game_logic.do_boost_cancel(player1, [payment], true), restriction)
		assert_true(player1.is_card_in_gauge(payment))
		assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
		assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostCancel)
		player1.set(restriction, false)
	assert_eq(game_logic._get_effective_boost_cancel_cost(player1, ice_card), 1)
	assert_true(game_logic.do_boost_cancel(player1, [payment], true))
	assert_true(player1.is_card_in_discards(payment))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PickAction)
	assert_eq(game_logic.get_active_player(), player1.my_id)

func _assert_tenso_jurin_boost_has_no_cancel():
	var ice_id = give_player_specific_card(player1, "dongshilang_冰刃")
	var ice_card = game_logic.card_db.get_card(ice_id)
	player1.remove_card_from_hand(ice_id, true, false)
	player1.add_to_bleach(ice_card)
	var boost_id = give_player_specific_card(player1, "dongshilang_龙霰架")
	var gauge_size = player1.gauge.size()
	game_logic.get_latest_events()

	assert_true(game_logic.do_boost(player1, boost_id))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostNow)
	assert_eq(game_logic.decision_info.valid_zones, ["bleach"])
	assert_eq(game_logic.decision_info.limitation, "ice_crystal")
	assert_true(game_logic.do_boost(player1, ice_id))
	var events = game_logic.get_latest_events()
	validate_not_has_event(events, Enums.EventType.EventType_Boost_CancelDecision, player1)
	validate_not_has_event(events, Enums.EventType.EventType_Boost_ActionAfterBoost, player1)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_StrikeNow)
	assert_true(player1.is_card_in_continuous_boosts(ice_id))
	assert_true(player1.is_card_in_discards(boost_id))
	assert_eq(player1.gauge.size(), gauge_size)
	assert_null(game_logic.active_boost)
	validate_has_event(events, Enums.EventType.EventType_ForceStartStrike, player1)

func test_tenso_jurin_boost_plays_ice_then_strikes_without_cancel():
	give_gauge(player1, 1)
	_assert_tenso_jurin_boost_has_no_cancel()

func test_tenso_jurin_boost_after_character_action_cancel_has_no_second_cancel():
	var payment = give_gauge(player1, 2)
	var ice_id = player1.bleach_zone[0].id
	assert_true(game_logic.do_character_action(player1, []))
	assert_true(game_logic.do_boost(player1, ice_id))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostCancel)
	assert_true(game_logic.do_boost_cancel(player1, [payment[0]], true))
	_assert_tenso_jurin_boost_has_no_cancel()

func test_tenso_jurin_boost_without_ice_still_strikes_without_cancel():
	for ice_card in player1.bleach_zone.duplicate():
		player1.remove_card_from_bleach(ice_card.id)
		player1.add_to_set_aside(ice_card)
	give_gauge(player1, 1)
	var boost_id = give_player_specific_card(player1, "dongshilang_龙霰架")
	game_logic.get_latest_events()
	assert_true(game_logic.do_boost(player1, boost_id))
	var events = game_logic.get_latest_events()
	validate_not_has_event(events, Enums.EventType.EventType_Boost_CancelDecision, player1)
	validate_not_has_event(events, Enums.EventType.EventType_ForceStartBoost, player1)
	validate_has_event(events, Enums.EventType.EventType_ForceStartStrike, player1)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)
	assert_true(player1.is_card_in_discards(boost_id))
	assert_null(game_logic.active_boost)
