extends ExceedGutTest

## ==========================================================================
## Eugenia 皮肤3（变体）：觉醒费用 5 + 觉醒时让对手随机弃 1 张
##
## 规则：觉醒费用 5（保留 transform_discount，转化后 5/3/1）；
##       觉醒瞬间对手随机弃 1 张 —— 这次弃牌会照常触发 Eugenia 的觉醒被动
##       （对手弃牌时，可选一张收进自己的 Wonderland）。
## 实现：data/decks_skin/eugenia_3.json 的 on_exceed 链尾挂 opponent_discard_random。
## ==========================================================================

func who_am_i():
	return "eugenia_3"

func before_each():
	default_game_setup("ryu")

func has_def_in_zone(_player, def_id, zone):
	for card in zone:
		if card.definition.get("id", "") == def_id:
			return true
	return false

func _names(arr):
	var out = []
	for c in arr:
		out.append(c.definition.get("display_name"))
	return str(out)

# ===== 皮肤注册与费用 =====

func test_skin3_is_registered():
	assert_eq(CharSkinManager.get_skin_count("eugenia"), 3,
		"Eugenia 应有 3 个皮肤（原皮 + 皮肤1/2/3）")
	assert_eq(CharSkinManager.get_skin_deck_id("eugenia", 3), "eugenia_3",
		"皮肤3 的 deck id 应为 eugenia_3")
	assert_eq(CharSkinManager.get_base_character_id("eugenia_3"), "eugenia",
		"皮肤3 必须能被识别回基础角色 eugenia（否则角色能力会全部失效）")

func test_skin3_exceed_cost_is_5():
	assert_eq(player1.deck_def.get("exceed_cost"), 5, "变体的觉醒费用应为 5")
	assert_eq(player1.get_exceed_cost(), 5, "0 张转化时实际觉醒费用为 5")

func test_skin3_exceed_cost_still_discounted_by_transforms():
	# 正常 S2 角色：保留每张转化 -2
	add_transform(player1, "standard_normal_block")
	assert_eq(player1.get_exceed_cost(), 3, "1 张转化应让觉醒费用降到 3")
	add_transform(player1, "standard_normal_grasp")
	assert_eq(player1.get_exceed_cost(), 1, "2 张转化应让觉醒费用降到 1")

# ===== 觉醒时的弃牌 =====

func test_exceed_makes_opponent_discard_and_wonderland_arrives():
	var hand_before = player2.hand.size()
	var discard_before = player2.discards.size()

	# 走真实的「觉醒」行动入口（do_exceed），这样 active_exceed 会被正确置位
	var gauge_ids = give_gauge(player1, 5)
	assert_true(game_logic.do_exceed(player1, gauge_ids), "觉醒行动应成功")

	assert_true(player1.exceeded, "应已觉醒")
	assert_eq(player2.hand.size(), hand_before - 1,
		"觉醒时应让对手随机弃 1 张")
	assert_eq(player2.discards.size(), discard_before + 1,
		"对手弃掉的那张应进入其弃牌堆")
	assert_true(has_def_in_zone(player1, "wonderland", player1.set_aside_cards),
		"觉醒时 Wonderland 应就位（原有的 on_exceed 链必须保留）")

func test_exceed_discard_triggers_exceeded_passive():
	# 关键：这次弃牌的「来源」必须是 Eugenia 自己，觉醒被动才会被唤醒
	# 走真实的「觉醒」行动入口（do_exceed），这样 active_exceed 会被正确置位
	var gauge_ids = give_gauge(player1, 5)
	assert_true(game_logic.do_exceed(player1, gauge_ids), "觉醒行动应成功")

	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision,
		"觉醒时对手弃牌后应停下来等 Eugenia 选择是否收牌")
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice,
		"应为「选一张收进 Wonderland」的选择")
	assert_eq(game_logic.decision_info.player, player1.my_id,
		"决策应归 Eugenia（若来源标记写错，这里会根本收不到决策）")

func test_discarded_card_can_be_moved_into_wonderland():
	# 走真实的「觉醒」行动入口（do_exceed），这样 active_exceed 会被正确置位
	var gauge_ids = give_gauge(player1, 5)
	assert_true(game_logic.do_exceed(player1, gauge_ids), "觉醒行动应成功")
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision,
		"应先弹出觉醒被动的选择")
	var discarded_id = player2.discards[player2.discards.size() - 1].id

	# choices: 0 = 跳过，1 = 第一张弃牌
	process_remaining_decisions(player1, player2, [1], [])

	var moved = false
	for card in player1.set_aside_cards:
		if card.id == discarded_id:
			moved = true
	assert_true(moved, "选中的弃牌应被收进 Wonderland（实际 Wonderland：%s）"
		% _names(player1.set_aside_cards))

# ===== 战斗中觉醒（strike 已开始，此时 exceeded 置真）=====
# 觉醒不一定发生在战斗外，on_exceed 的弃牌在战斗结算中也必须正常执行。

func test_exceed_during_strike_also_discards():
	position_players(player1, 4, player2, 5)  # dist1
	var hand_before = player2.hand.size()
	var discard_before = player2.discards.size()

	# 发起战斗，停在「等待对手应战」——此时战斗已真正开始
	var attack_id = give_player_specific_card(player1, "standard_normal_grasp")
	do_and_validate_strike(player1, attack_id)
	assert_true(game_logic.active_strike != null, "战斗应已开始（active_strike 非空）")

	# 战斗中觉醒
	player1.exceed()

	assert_true(player1.exceeded, "应已觉醒")
	assert_eq(player2.hand.size(), hand_before - 1,
		"战斗内觉醒同样应让对手随机弃 1 张")
	assert_eq(player2.discards.size(), discard_before + 1,
		"战斗中觉醒时那张牌应进入对手弃牌堆")
	assert_true(has_def_in_zone(player1, "wonderland", player1.set_aside_cards),
		"战斗中觉醒 Wonderland 同样应就位")

	# 消化掉觉醒被动的选择，避免测试结束时残留未处理的决策
	if game_logic.game_state == Enums.GameState.GameState_PlayerDecision:
		process_remaining_decisions(player1, player2, [0], [])

func test_original_eugenia_is_not_polluted():
	# 反向对照：改动只应落在皮肤3，原皮 eugenia 的 on_exceed 仍是原来的两段
	var original = CardDataManager.get_deck("eugenia")
	var skip_oe = original.get("on_exceed", {})
	assert_false(skip_oe.get("and", {}).has("and"),
		"原皮 eugenia 的 on_exceed 不应含额外的弃牌段")

	var skin3 = CardDataManager.get_deck("eugenia_3")
	assert_true(skin3.get("on_exceed", {}).get("and", {}).has("and"),
		"皮肤3 的 on_exceed 应挂上弃牌段")
	assert_eq(skin3.get("exceed_cost"), 5, "皮肤3 的觉醒费用应为 5")
	assert_eq(original.get("exceed_cost"), 6, "原皮的觉醒费用应保持 6")
