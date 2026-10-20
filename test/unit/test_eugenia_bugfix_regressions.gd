extends ExceedGutTest

# 回归测试：Bug 1（红心皇后被动静默）与 Bug 2（Plot Hook 额外行动取消误结束回合）
# 两个版本通用（Plot Hook id 不同：eugenia_plot_hook / eugenia_illusion_bind，自动查找）
# 运行: Godot_v4.4-stable_win64_console.exe -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_eugenia_bugfix_regressions.gd -gexit

func who_am_i():
	return "eugenia"

# 从 player 的 transforms 里找 Time for Tea（Plot Hook 转化）卡
func _find_plot_hook_transform(player) -> GameCard:
	for card in player.transforms:
		var boost = card.definition.get("boost", {})
		if boost.get("display_name") == "Time for Tea":
			return card
	return null

# 从手牌找 Plot Hook（未转化形态），用于确认 bonus action 存在
func _find_plot_hook_in_deck(player):
	for card in player.deck_list:
		var boost = card.definition.get("boost", {})
		if boost.get("display_name") == "Time for Tea":
			return card
	return null

# 按 display_name 找卡牌定义 id（兼容两版本 id 命名差异）
func _find_def_id_by_display_name(display_name: String) -> String:
	for card_id in CardDataManager.card_data.keys():
		var card_def = CardDataManager.card_data[card_id]
		if card_def.get("display_name") == display_name:
			return card_id
	return ""

## ===== Bug 1: ChooseSimultaneousEffect 缺 source 快照 → 被动静默 =====
# 关键复现场景：对手的 during_strike 效果（如 Potemkin Dust 的 guardup）
# 污染 _last_effect_source_player_id 后，红心皇后+Shimmer 转化双 hit 效果
# 弹 ChooseSimultaneousEffect，提交时 source 退化为对手 ID → 被动不弹。
func test_qoh_shimmer_with_opponent_guardup_discard_triggers_passive():
	position_players(player1, 4, player2, 5)
	var shimmer_id = _find_def_id_by_display_name("Shimmer of Madness")
	assert_ne(shimmer_id, "", "应能找到 Shimmer of Madness 定义")
	if shimmer_id == "":
		return
	add_transform(player1, shimmer_id)  # Hanging by a Thread
	player1.hand = []
	player2.hand = []
	give_player_specific_card(player1, "eugenia_queen_of_hearts")
	give_player_specific_card(player2, "standard_normal_assault")  # 对手手牌(S5)
	give_player_specific_card(player1, "standard_normal_assault")  # Eugenia 匹配牌(S5)

	# 对手打一个带 during_strike guardup 的持续加成（污染 source）
	var dust_id = -1
	for card in player2.hand:
		var boost = card.definition.get("boost", {})
		if boost.get("boost_type") == "continuous" and boost.get("effects", []).any(
				func(e): return e.get("effect_type") == "guardup"):
			dust_id = card.id
			break
	if dust_id != -1:
		assert_true(game_logic.do_boost(player2, dust_id, []), "对手应能打 guardup boost")

	# 红心皇后(G3 必杀)需要怒气支付；直接给怒气
	var gauge_ids = give_gauge(player1, 3)
	execute_strike(player1, player2, "eugenia_queen_of_hearts", "standard_normal_block",
		false, false,
		[gauge_ids, 0, 0],  # 支付怒气；ChooseSimultaneousEffect 排序选0（弃牌先）；被动跳过
		[[]])  # Block ForceForArmor 不付

	var events = game_logic.get_latest_events()
	var has_passive_choice = false
	for ev in events:
		if ev['event_type'] == Enums.EventType.EventType_Strike_EffectChoice:
			has_passive_choice = true
			break
	print("QOH_GUARDUP passive_choice_event=", has_passive_choice)
	assert_true(has_passive_choice, "红心皇后弃牌后应弹出被动 choice（即使对手有 during_strike 效果）")

## ===== Bug 2: Plot Hook 额外行动取消误结束回合 =====
func test_plot_hook_bonus_action_cancel_returns_to_pick_action():
	position_players(player1, 4, player2, 5)
	# 用 deck_list 里的 Plot Hook 定义 id 做转化（兼容两个版本的 id）
	var plot_hook = _find_plot_hook_in_deck(player1)
	assert_not_null(plot_hook, "牌堆应有 Time for Tea 转化卡（Plot Hook）")
	if plot_hook == null:
		return
	add_transform(player1, plot_hook.definition["id"])  # Time for Tea: 付1F 对手弃1

	give_player_specific_card(player1, "standard_normal_assault")  # 付 force 用
	var actions = player1.get_bonus_actions()
	assert_eq(actions.size(), 1, "应有一个 bonus action")

	assert_true(game_logic.do_bonus_turn_action(player1, 0))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ForceForEffect)

	# 取消（不付 force）
	assert_true(game_logic.do_force_for_effect(player1, [], false, true))
	assert_eq(game_logic.get_game_state(), Enums.GameState.GameState_PickAction,
			"取消 bonus action 后应回到 PickAction")
	assert_false(game_logic.active_character_action, "active_character_action 应复位")
	assert_eq(game_logic.active_turn_player, player1.my_id, "回合不应被推进")
