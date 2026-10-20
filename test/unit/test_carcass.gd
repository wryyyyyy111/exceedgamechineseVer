extends ExceedGutTest

## ==========================================================================
## 特遣队员（carcass，S0 DIY 角色）
##
## 角色能力：你的卡牌获得「爆头：威力+1」（觉醒后 +2 且抽 1）
##           击中：手牌数等于距离时触发爆头
## 放宽：EGIS 武器平台 → 相差 1 也算；恶魔子弹 → 无条件（只需击中）
## 守望：不能被移动/击退/拉近/穿越；每次阻止对对手造成 2 点非致命伤害
## ==========================================================================

func who_am_i():
	return "carcass"

func before_each():
	default_game_setup("ryu")

func _headshot_effect():
	return {"condition": "headshot"}

func _pair(effect):
	var lc = LocalStrikeConditions.new()
	return game_logic.is_effect_condition_met(player1, effect, lc)

# ===== 角色与卡组加载 =====

func test_carcass_deck_loads():
	assert_eq(player1.deck_def.get("id"), "carcass", "deck_def 的 id 应为 carcass")
	assert_eq(player1.deck_def.get("season"), 0, "应属于第 0 季")
	assert_eq(player1.deck_def.get("exceed_cost"), 4, "觉醒费用应为 4 怒气")
	assert_eq(player1.deck_def.get("display_name"), "特遣队员")

func test_carcass_deck_composition():
	# 7 张专属卡已迁入全局 card_definitions.json，卡组内不再内嵌自定义卡。
	var custom = player1.deck_def.get("custom_card_definitions", [])
	assert_eq(custom.size(), 0, "卡组内不再内嵌自定义卡")
	var ids = []
	for c in player1.deck_def.get("cards", []):
		ids.append(c["definition_id"])
	for expected in ["carcass_gunfire", "carcass_watch", "carcass_grenade_jump",
			"carcass_living_cannon", "carcass_tube", "carcass_dual_wield", "carcass_sg88"]:
		assert_true(ids.has(expected), "卡组缺少专属卡 %s" % expected)
		assert_true(CardDataManager.get_card(expected).has("id"), "全局卡库缺少 %s" % expected)
	assert_eq(player1.deck_def.get("cards", []).size(), 30, "卡组应为 30 张")

# ===== 爆头条件：手牌数 == 距离 =====

func test_headshot_triggers_when_hand_equals_distance():
	# 先手起手 5 张 → 把双方摆成距离 5
	position_players(player1, 2, player2, 7)
	assert_eq(player1.hand.size(), 5, "前置：起手应为 5 张")
	assert_eq(player1.distance_to_opponent(), 5, "前置：距离应为 5")
	assert_true(_pair(_headshot_effect()), "手牌数等于距离时应触发爆头")

func test_headshot_not_triggered_when_hand_differs():
	position_players(player1, 3, player2, 7)  # 距离 4，手牌 5
	assert_eq(player1.distance_to_opponent(), 4, "前置：距离应为 4")
	assert_false(_pair(_headshot_effect()), "手牌数不等于距离时不应触发爆头")

# ===== 两种放宽 =====

func test_egis_platform_allows_off_by_one():
	position_players(player1, 3, player2, 7)  # 距离 4 vs 手牌 5 → 差 1
	assert_false(_pair(_headshot_effect()), "前置：默认不触发")
	player1.headshot_allow_off_by_one = 1
	assert_true(_pair(_headshot_effect()), "EGIS 武器平台在场时相差 1 也应触发爆头")
	player1.headshot_allow_off_by_one = 0
	assert_false(_pair(_headshot_effect()), "撤销后应恢复不触发")

func test_demon_bullet_makes_headshot_unconditional():
	position_players(player1, 1, player2, 9)  # 距离 8，远超手牌数
	assert_false(_pair(_headshot_effect()), "前置：默认不触发")
	player1.headshot_unconditional = 1
	assert_true(_pair(_headshot_effect()), "恶魔子弹在场时无视任何条件，只需击中")
	player1.headshot_unconditional = 0
	assert_false(_pair(_headshot_effect()), "撤销后应恢复不触发")

# ===== 守望：免疫位移 + 阻止反击 =====

func test_demon_bullet_boost_text_is_complete():
	var texts = []
	for e in CardDataManager.get_card("carcass_tube")["boost"]["effects"]:
		texts.append(GameStrings.get_effect_text(e))
	assert_eq(texts, ["无视护甲，", "爆头不再具有限制条件，只需“击中”即可。", ""],
		"恶魔子弹的加成区文本应完整，且离场清理效果不显示")
	for e in CardDataManager.get_card("carcass_tube")["boost"]["effects"]:
		if e["effect_type"] == "headshot_unconditional":
			assert_true(e.get("show_in_boost_summary", false),
				"该 timing=now 持续说明已显式标记为在加成区显示")

func test_watch_guard_blocks_push_and_pull():
	assert_eq(player1.ignore_push_and_pull, 0, "前置：默认不免疫位移")
	game_logic.handle_strike_effect(-1, {"effect_type": "carcass_watch_guard"}, player1)
	assert_eq(player1.carcass_watch_guard, 1, "守望标记应置位")
	assert_true(player1.strike_stat_boosts.ignore_push_and_pull, "守望期间应不能被移动/击退/拉近")
	assert_false(player1.cannot_move_past_opponent,
		"「不能穿越」不该记在自己身上（opponent_cant_move_past 是记在对手身上的标记）")

	game_logic.handle_strike_effect(-1, {"effect_type": "remove_carcass_watch_guard"}, player1)
	assert_eq(player1.carcass_watch_guard, 0, "守望标记应撤销")

# ===== 觉醒前后能力切换 =====

func test_exceeded_headshot_is_stronger():
	var base = player1.deck_def.get("ability_effects", [])
	var exceed = player1.deck_def.get("exceed_ability_effects", [])
	assert_eq(base.size(), 1, "未觉醒能力应有 1 条")
	assert_eq(exceed.size(), 1, "觉醒能力应有 1 条")

	var base_added = base[0].get("added_effect", {})
	var exceed_added = exceed[0].get("added_effect", {})
	assert_eq(base_added.get("amount"), 1, "未觉醒爆头应为威力+1")
	assert_eq(base_added.get("condition"), "headshot", "应挂在爆头条件上")
	assert_eq(exceed_added.get("amount"), 2, "觉醒爆头应为威力+2")
	assert_eq(exceed_added.get("and", {}).get("effect_type"), "draw", "觉醒爆头应附带抽 1 张")

func test_headshot_effect_has_ua_description_text():
	for ability in [player1.deck_def["ability_effects"][0], player1.deck_def["exceed_ability_effects"][0]]:
		var added = ability["added_effect"]
		var text = GameStrings.get_effect_text(added)
		assert_true(text.begins_with("爆头"), "爆头触发效果应显示UA词条：%s" % text)
		assert_false("缺失" in text, "爆头文本不应缺失：%s" % text)
		var no_override = added.duplicate(true)
		no_override.erase("override_description")
		assert_false("缺失" in GameStrings.get_effect_text(no_override), "爆头条件应有文本")
	assert_eq(GameStrings.get_effect_text(player1.deck_def["ability_effects"][0]["added_effect"]), "爆头：威力+1。")
	assert_eq(GameStrings.get_effect_text(player1.deck_def["exceed_ability_effects"][0]["added_effect"]), "爆头：威力+2，抽1张牌。")

# ===== 枪灵：怒气区的这张卡可以作为 2 能量 / 2 怒气使用 =====
#
# 实现：卡级字段 `gauge_resource_value`，只在卡处于怒气区时生效。
# 判定侧（can_pay_cost_with / get_available_force / get_available_gauge）
# 与实际支付侧都已按该值累加。

func _to_gauge(player, def_id):
	# 把一张指定卡放进怒气区
	var cid = give_player_specific_card(player, def_id)
	var card = game_logic.get_card_database().get_card(cid)
	player.hand.remove_at(player.hand.size() - 1)
	player.add_to_gauge(card)
	return cid


func test_gun_spirit_card_in_gauge_counts_as_two():
	var base_force = player1.get_available_force()
	var base_gauge = player1.get_available_gauge()
	var dw_id = _to_gauge(player1, "carcass_dual_wield")

	assert_eq(player1.get_card_gauge_resource_override(dw_id), 2,
		"左右开弓在怒气区应被记为 2 点资源")
	assert_eq(player1.get_available_force() - base_force, 2,
		"怒气区的枪灵应提供 2 点能量")
	assert_eq(player1.get_available_gauge() - base_gauge, 2,
		"怒气区的枪灵应提供 2 点怒气")


func test_gun_spirit_can_pay_two_with_a_single_gauge_card():
	var dw_id = _to_gauge(player1, "carcass_dual_wield")
	assert_true(player1.can_pay_cost_with([dw_id], 2, 0, false, 0),
		"单张枪灵应足以支付 2 点能量")
	assert_true(player1.can_pay_cost_with([dw_id], 0, 2, false, 0),
		"单张枪灵应足以支付 2 点怒气")


func test_normal_card_in_gauge_still_counts_as_one():
	# 反向对照：普通技在怒气区仍然只值 1（单张付不了 2）。
	var base_force = player1.get_available_force()
	var base_gauge = player1.get_available_gauge()
	var norm_id = _to_gauge(player1, "standard_normal_block")

	assert_eq(player1.get_card_gauge_resource_override(norm_id), 0,
		"普通技没有枪灵覆盖")
	assert_eq(player1.get_available_force() - base_force, 1, "普通技只提供 1 点能量")
	assert_eq(player1.get_available_gauge() - base_gauge, 1, "普通技只提供 1 点怒气")
	assert_false(player1.can_pay_cost_with([norm_id], 2, 0, false, 0),
		"单张普通技不应能支付 2 点能量")


func test_gun_spirit_boost_is_not_playable():
	# 卡面写「不可作为加成打出」：boost_type 为 none。
	var cid = give_player_specific_card(player1, "carcass_dual_wield")
	var card = game_logic.get_card_database().get_card(cid)
	assert_eq(card.definition["boost"]["boost_type"], "none",
		"枪灵的 boost_type 应为 none")
	assert_false(game_logic.do_boost(player1, cid, [], false, 0),
		"枪灵不可作为加成打出")


# ===== 左右开弓：可以和任何一张卡组成强力攻击 =====

func test_dual_wield_pairs_with_a_differently_named_card():
	var dw_id = give_player_specific_card(player1, "carcass_dual_wield")
	var partner_id = give_player_specific_card(player1, "standard_normal_spike")

	assert_true(player1.can_ex_strike_with_something(),
		"手牌有左右开弓 + 任意其他牌时应视为可组强力攻击")
	assert_true(game_logic.do_strike(player1, dw_id, false, partner_id),
		"左右开弓应能与不同名牌组成强力攻击")

	var ex_card = game_logic.active_strike.initiator_ex_card
	assert_not_null(ex_card, "应设置强力攻击的第二张卡")
	assert_eq(ex_card.definition["id"], "standard_normal_spike",
		"第二张卡应为搭档本身")
	assert_false(player1.is_card_in_hand(partner_id),
		"展示后搭档应从手牌移出（弃掉另一张）")
	assert_false(player1.is_card_in_hand(dw_id), "左右开弓本身也应离手")


func test_dual_wield_is_the_attack_even_when_chosen_as_the_partner():
	var dw_id = give_player_specific_card(player1, "carcass_dual_wield")
	var partner_id = give_player_specific_card(player1, "standard_normal_spike")

	assert_true(game_logic.do_strike(player1, partner_id, false, dw_id),
		"左右开弓作为搭档牌时也应能组成强力攻击")

	assert_eq(game_logic.active_strike.initiator_card.definition["id"], "carcass_dual_wield",
		"主攻击牌应永远是左右开弓")
	assert_eq(game_logic.active_strike.initiator_ex_card.definition["id"], "standard_normal_spike",
		"另一张不同名牌应作为被弃掉的搭档牌")


func test_normal_ex_strike_keeps_chosen_card_order():
	var a_id = give_player_specific_card(player1, "standard_normal_spike")
	var b_id = give_player_specific_card(player1, "standard_normal_spike")
	assert_true(game_logic.do_strike(player1, b_id, false, a_id))
	assert_eq(game_logic.active_strike.initiator_card.id, b_id, "普通强力攻击不应交换牌序")
	assert_eq(game_logic.active_strike.initiator_ex_card.id, a_id)


func test_normal_card_cannot_pair_with_a_differently_named_card():
	# 反向对照：普通技仍只能同名配对，不能借此机制乱配。
	var n_id = give_player_specific_card(player1, "standard_normal_grasp")
	var partner_id = give_player_specific_card(player1, "standard_normal_spike")
	assert_false(game_logic.do_strike(player1, n_id, false, partner_id),
		"普通技不应能与不同名牌组成强力攻击")


func test_dual_wield_has_pairing_flag():
	var card = CardDataManager.get_card("carcass_dual_wield")
	assert_true(card.get("may_ex_with_any_card", false),
		"左右开弓应带 may_ex_with_any_card 标记")
	assert_eq(card.get("gauge_resource_value"), 2, "应带枪灵的资源覆盖值")
	assert_eq(card["effects"].size(), 0,
		"配对由卡级标记驱动，效果数组应为空（避免未注册的 effect_type）")

# ===== 枪灵在「支付护甲」路径上也算 2 点 =====
#
# 引擎里换护甲有两条路（都在 local_game.do_force_for_armor）：
#   ① limitation == "force"：弃手牌/怒气当能量（走 get_force_with_cards）——本来就已按点数算
#   ② limitation == "gauge"：用怒气卡顶能量（Snow Slash 的持续加成 "Block And..."
#      的 when_hit_force_for_armor + use_gauge_instead 产生）——原本是 len(card_ids) 按张数
# 这里把 ② 改成逐张取支付点数（player.get_gauge_payment_value_for_cards），
# 与 ① 以及「怒气当作能量/怒气支付」的其他路径保持一致。
#
# 数值：每点能量换 2 护甲（decision_info.amount = 2）；
#       飞踢(P5) 打 尖刺(A0) → 基础 5 伤。
#       枪灵 = 2 点 → 4 护甲 → 受 1 伤；普通技 = 1 点 → 2 护甲 → 受 3 伤。

func _carcass_strike_and_pay_armor(limitation : String, pay_card_id):
	# 站位 distance 4：飞踢 advance 3 不会穿过对手（避免触发闪避），保证命中
	position_players(player1, 2, player2, 6)
	advance_turn(player1)
	var atk = give_player_specific_card(player2, "standard_normal_dive")
	var dfn = give_player_specific_card(player1, "standard_normal_spike")
	do_and_validate_strike(player2, atk)
	# 注入「被打时可用怒气/能量换护甲」标记，等价于 Snow Slash 的 Block And... 已生效
	player1.strike_stat_boosts.when_hit_force_for_armor = limitation
	var life_before = player1.life
	do_strike_response(player1, dfn)
	process_remaining_decisions(player2, player1, [], [[pay_card_id]])
	return life_before - player1.life


func test_gun_spirit_counts_two_when_paying_gauge_for_armor():
	var gun = _to_gauge(player1, "carcass_dual_wield")
	var damage = _carcass_strike_and_pay_armor("gauge", gun)

	assert_eq(damage, 1, "枪灵在怒气区应按 2 点算 → 4 护甲 → 只受 1 伤（按张数算会受 3 伤）")
	assert_false(player1.is_card_in_gauge(gun), "该怒气卡应已被花费")


func test_normal_card_counts_one_when_paying_gauge_for_armor():
	# 反向对照：普通技在怒气区仍然只值 1 点
	var norm = _to_gauge(player1, "standard_normal_spike")
	var damage = _carcass_strike_and_pay_armor("gauge", norm)

	assert_eq(damage, 3, "普通技只提供 1 点 → 2 护甲 → 受 3 伤")
	assert_false(player1.is_card_in_gauge(norm), "该怒气卡应已被花费")


func test_gun_spirit_counts_two_when_paying_force_for_armor():
	# 另一条路（limitation == "force"，Block 一类）：从怒气区选枪灵同样算 2 点
	var gun = _to_gauge(player1, "carcass_dual_wield")
	var damage = _carcass_strike_and_pay_armor("force", gun)

	assert_eq(damage, 1, "枪灵按 2 点算 → 4 护甲 → 受 1 伤")

# ===== 枪灵在「怒气被用于支付」的其他路径上也按点数算 =====
#
# 卡面：怒气区的这张卡可以视为 2 能量或 2 张怒气使用。
# 除了护甲（见上）之外，引擎里还有几处原本按张数 len(...) 结算，都已改成按点数
# （player.get_gauge_payment_value_for_cards）：觉醒费用 / 加成的怒气费用 /
# 取消费用 / 付 N 怒换效果，以及 UI 的 get_gauge_generated() 与 AI 的组合生成。

func _carcass_begin_gauge_for_effect_decision(gauge_max : int, min_gauge : int):
	# 直接构造「付 N 怒换效果」的决策，隔离结算本身
	game_logic.active_character_action = true  # 让收尾状态机有「正在进行的事」，避免无关 assert
	game_logic.change_game_state(Enums.GameState.GameState_PlayerDecision)
	game_logic.decision_info.clear()
	game_logic.decision_info.player = player1.my_id
	game_logic.decision_info.type = Enums.DecisionType.DecisionType_GaugeForEffect
	game_logic.decision_info.choice_card_id = -1
	game_logic.decision_info.effect = {
		"effect_type": "gauge_for_effect",
		"per_gauge_effect": null,
		"overall_effect": {"effect_type": StrikeEffects.Nothing},
		"gauge_max": gauge_max,
		"min_gauge": min_gauge,
		"can_pass": false,
	}


func test_gun_spirit_counts_two_for_exceed_cost():
	# 觉醒费用：carcass 要 4 点，两张枪灵（各 2 点）应刚好够
	var gun1 = _to_gauge(player1, "carcass_dual_wield")
	var gun2 = _to_gauge(player1, "carcass_dual_wield")
	assert_eq(player1.get_exceed_cost(), 4, "前置：carcass 觉醒费用应为 4 点")
	assert_eq(player1.get_gauge_payment_value_for_cards([gun1, gun2]), 4, "两张枪灵应值 4 点")

	assert_true(game_logic.do_exceed(player1, [gun1, gun2]),
		"两张枪灵应足以支付 4 点觉醒费用")
	assert_true(player1.exceeded, "应已觉醒")


func test_exceed_draws_two_cards():
	# 直接觉醒，避开行动结束时的回合末摸牌
	var hand_before = player1.hand.size()
	player1.exceed()
	assert_true(player1.exceeded)
	assert_eq(player1.hand.size(), hand_before + 2, "觉醒时应摸 2 张牌")
	assert_eq(GameStrings.get_on_exceed_text(player1.deck_def["on_exceed"]), "当你觉醒时：抽2\n")


func test_two_normal_cards_cannot_pay_exceed_cost():
	# 反向对照：两张普通技只有 2 点，付不了 4 点觉醒费
	var norm1 = _to_gauge(player1, "standard_normal_spike")
	var norm2 = _to_gauge(player1, "standard_normal_cross")
	assert_eq(player1.get_gauge_payment_value_for_cards([norm1, norm2]), 2, "两张普通技只值 2 点")

	assert_false(game_logic.do_exceed(player1, [norm1, norm2]),
		"两张普通技不足以支付 4 点觉醒费用")
	assert_false(player1.exceeded, "不应觉醒")


func test_gun_spirit_counts_two_when_paying_gauge_for_effect():
	# 付 N 怒换效果：单张枪灵（2 点）应满足需要 2 点的效果
	var gun = _to_gauge(player1, "carcass_dual_wield")
	_carcass_begin_gauge_for_effect_decision(2, 2)
	assert_true(game_logic.do_gauge_for_effect(player1, [gun]),
		"单张枪灵 = 2 点，应满足 min_gauge=2 / gauge_max=2")


func test_normal_card_needs_two_for_two_point_gauge_for_effect():
	# 反向对照：单张普通技只算 1 点，要两张才够
	var norm1 = _to_gauge(player1, "standard_normal_spike")
	var norm2 = _to_gauge(player1, "standard_normal_cross")
	_carcass_begin_gauge_for_effect_decision(2, 2)
	assert_false(game_logic.do_gauge_for_effect(player1, [norm1]),
		"单张普通技 = 1 点，不满足 min_gauge=2")

	_carcass_begin_gauge_for_effect_decision(2, 2)
	assert_true(game_logic.do_gauge_for_effect(player1, [norm1, norm2]),
		"两张普通技 = 2 点，应满足 min_gauge=2")


func test_gun_spirit_adapts_to_one_point_when_effect_only_wants_one():
	# 弹性支付：枪灵面值 2，但「只要 1 怒气」的效果里会自动作为 1 点使用，不该被当超付拒掉。
	var gun = _to_gauge(player1, "carcass_dual_wield")
	_carcass_begin_gauge_for_effect_decision(1, 1)
	assert_true(game_logic.do_gauge_for_effect(player1, [gun]),
		"枪灵应自动适配成 1 点，满足 gauge_max=1")


func test_gun_spirit_payment_value_range_is_one_to_two():
	# 每张怒气卡最少贡献 1 点、最多其面值（枪灵 2 点）。
	var gun = _to_gauge(player1, "carcass_dual_wield")
	var norm = _to_gauge(player1, "standard_normal_spike")
	assert_eq(player1.get_gauge_payment_value_range([gun]), [1, 2],
		"单张枪灵：最少 1 点、最多 2 点")
	assert_eq(player1.get_gauge_payment_value_range([gun, norm]), [2, 3],
		"枪灵 + 普通技：最少 2 点（各 1）、最多 3 点")
	assert_eq(player1.get_gauge_payment_value_range([norm, norm]), [2, 2],
		"两张普通技：恰好 2 点（没有弹性）")


func test_gun_spirit_adapts_to_the_gauge_max_of_the_effect():
	# 同一张卡按效果上限自动适配：上限 1 → 作为 1 点；上限 2 → 作为 2 点。
	var gun1 = _to_gauge(player1, "carcass_dual_wield")
	_carcass_begin_gauge_for_effect_decision(1, 1)
	assert_true(game_logic.do_gauge_for_effect(player1, [gun1]), "上限 1：枪灵作为 1 点")

	var gun2 = _to_gauge(player1, "carcass_dual_wield")
	_carcass_begin_gauge_for_effect_decision(2, 2)
	assert_true(game_logic.do_gauge_for_effect(player1, [gun2]), "上限 2：枪灵作为 2 点")


func test_two_gun_spirits_can_pay_three_points():
	# 弹性支付：两张枪灵可以付 3 点（一张当 2、一张当 1）。
	var gun1 = _to_gauge(player1, "carcass_dual_wield")
	var gun2 = _to_gauge(player1, "carcass_dual_wield")
	assert_eq(player1.get_gauge_payment_value_range([gun1, gun2]), [2, 4], "两张枪灵：2..4 点")
	_carcass_begin_gauge_for_effect_decision(3, 3)
	assert_true(game_logic.do_gauge_for_effect(player1, [gun1, gun2]), "两张枪灵应付得出 3 点")


func test_three_gun_spirits_cannot_pay_only_two_points():
	# 每张至少 1 点：三张卡最少付 3 点，不能只付 2 点。
	var g1 = _to_gauge(player1, "carcass_dual_wield")
	var g2 = _to_gauge(player1, "carcass_dual_wield")
	var g3 = _to_gauge(player1, "carcass_dual_wield")
	assert_eq(player1.get_gauge_payment_value_range([g1, g2, g3]), [3, 6], "三张枪灵：3..6 点")
	_carcass_begin_gauge_for_effect_decision(2, 2)
	assert_false(game_logic.do_gauge_for_effect(player1, [g1, g2, g3]),
		"三张卡最少付 3 点，不应能只付 2 点")


func test_ai_gauge_payment_combinations_use_card_values():
	# AI 必须按「弹性点数」组合怒气卡，否则会漏掉枪灵能付的低费效果
	var ai = AIPlayer.new(game_logic, player1, AIPolicyRules.new())
	var gun = _to_gauge(player1, "carcass_dual_wield")
	var norm = _to_gauge(player1, "standard_normal_spike")

	# 付 2 点：单张枪灵就够
	var combos_for_two = ai.generate_gauge_payment_combinations([gun, norm], 2)
	var single_gun_combo = false
	for combo in combos_for_two:
		if combo.size() == 1 and combo[0] == gun:
			single_gun_combo = true
	assert_true(single_gun_combo, "付 2 点时应能用 1 张枪灵凑出")

	# 付 1 点：枪灵可自适应成 1 点，所以「单张枪灵」也是合法组合
	var combos_for_one = ai.generate_gauge_payment_combinations([gun, norm], 1)
	var single_gun_for_one = false
	for combo in combos_for_one:
		if combo.size() == 1 and combo[0] == gun:
			single_gun_for_one = true
	assert_true(single_gun_for_one, "付 1 点时枪灵自适应为 1 点，单张枪灵应可用")
	var uses_two_cards = false
	for combo in combos_for_one:
		if combo.size() >= 2:
			uses_two_cards = true
	assert_false(uses_two_cards, "付 1 点时每张至少 1 点，两张卡会超付，不应出现")

	# 普通技之间仍是老行为（2 张凑 2 点）
	var combos_two_normals = ai.generate_gauge_payment_combinations([norm, norm], 2)
	assert_eq(combos_two_normals.size(), 1, "两张普通技凑 2 点")

	ai.ai_policy.free()

# ===== 取消（cancel）：carcass 的卡牌不带这个机制 =====
#
# 「取消」是第七季的特殊机制：加成标了 `boost.cancel_cost: 1` 时，打出来后可以付 1 怒气取消
# （`player.can_cancel()` → `DecisionType_BoostCancel` → `do_boost_cancel`），并保留行动权。
# 全库只有 S7 的卡和 `gg_normal_*` 用 1，其它季度 / 角色一律 -1。
# 特遣队员是第 0 季 DIY 角色，卡面与设计文档都没有取消，所以所有加成都不该出现取消窗口。

func test_carcass_boosts_have_no_cancel_cost():
	var checked = 0
	for card_entry in player1.deck_def.get("cards", []):
		var c = CardDataManager.get_card(card_entry["definition_id"])
		if not c["id"].begins_with("carcass_"):
			continue
		checked += 1
		assert_eq(c["boost"].get("cancel_cost"), -1,
			"%s 的加成不应带取消费用（应为 -1）" % c["id"])
	assert_eq(checked, 14, "应检查卡组内 7 种专属卡的全部 14 张")


func test_carcass_boost_does_not_offer_cancel():
	# 枪炮齐鸣的 S.T.G. 不需要付能量：即使怒气充足，也不该进入取消决策。
	position_players(player1, 4, player2, 6)
	give_gauge(player1, 3)
	var boost_id = give_player_specific_card(player1, "carcass_gunfire")
	var card = game_logic.get_card_database().get_card(boost_id)

	assert_false(player1.can_cancel(card), "carcass 的加成不应可取消")
	assert_true(game_logic.do_boost(player1, boost_id, []), "加成本身应能正常打出")
	validate_not_has_event(game_logic.get_latest_events(),
		Enums.EventType.EventType_Boost_CancelDecision, player1)


func test_season7_reference_boost_still_offers_cancel():
	# 反向对照：第七季的卡仍然照常弹取消，说明只改了 carcass 的数据，机制没有被关掉。
	position_players(player1, 4, player2, 6)
	give_gauge(player1, 3)
	var boost_id = give_player_specific_card(player1, "goldlewis_rise")
	var card = game_logic.get_card_database().get_card(boost_id)

	assert_eq(card.definition["boost"]["cancel_cost"], 1, "前置：goldlewis_rise 是 S7 的取消卡")
	assert_true(player1.can_cancel(card), "S7 的卡应仍然可取消")
	assert_true(game_logic.do_boost(player1, boost_id, []))
	validate_has_event(game_logic.get_latest_events(),
		Enums.EventType.EventType_Boost_CancelDecision, player1)

# ===== 加成效果字段约定（漏字段会让效果静默失效）=====
#
# 引擎里有几处是**直接取键**（`effect['xxx']`）而非 `get`，卡定义漏写就报错中断：
#   gauge_for_effect → 必须带 per_gauge_effect（全库 54 处都有）
#   discard_continuous_boost → 必须带 required（全库 12 处都有）
# 之前 S.T.G. / 恶魔子弹 漏了 per_gauge_effect，付 6 怒后报
# "Invalid access to property or key 'per_gauge_effect'"，+66 威力整段没生效。

func _custom_card(def_id : String) -> Dictionary:
	return CardDataManager.get_card(def_id)


func test_gauge_for_effect_effects_declare_per_gauge_effect():
	for def_id in ["carcass_gunfire", "carcass_tube"]:
		var card = _custom_card(def_id)
		var found = false
		for e in card["boost"]["effects"] + card["effects"]:
			if e.get("effect_type") == "gauge_for_effect":
				found = true
				assert_true(e.has("per_gauge_effect"),
					"%s 的 gauge_for_effect 必须显式写 per_gauge_effect（引擎直接取键）" % def_id)
		assert_true(found, "%s 应有一处 gauge_for_effect" % def_id)


func test_discard_continuous_boost_declares_required_and_overall_effect():
	var card = _custom_card("carcass_living_cannon")
	for e in card["effects"]:
		if e.get("effect_type") == "discard_continuous_boost":
			assert_true(e.has("required"), "discard_continuous_boost 必须显式写 required")
			assert_false(e["required"], "守望/大炮是可选弃置（玩家可以略过）")
			assert_eq(e.get("limitation"), "mine", "只能弃自己的持续性加成")
			assert_eq(e.get("overall_effect", {}).get("effect_type"), "powerup",
				"加成威力要写在 overall_effect 里（powerup_amount 不是有效字段）")
			assert_eq(e["overall_effect"].get("amount"), 6, "应威力+6")


func test_sg88_discard_boost_pays_off_with_powerup_six():
	# 活体大炮「前置」：弃掉自己场上 1 张持续性加成 → 威力+6（参考 Trinity 的 5 速特殊技）
	position_players(player1, 3, player2, 6)
	var boost_id = give_player_specific_card(player1, "carcass_sg88")
	var boost_card = game_logic.get_card_database().get_card(boost_id)
	player1.add_to_continuous_boosts(boost_card)
	player1.hand.erase(boost_card)

	var effect = null
	for e in _custom_card("carcass_living_cannon")["effects"]:
		if e.get("effect_type") == "discard_continuous_boost":
			effect = e
	assert_true(effect != null, "前置：应找到 discard_continuous_boost 效果")

	game_logic.handle_strike_effect(-1, effect, player1)
	assert_eq(game_logic.decision_info.type,
		Enums.DecisionType.DecisionType_ChooseDiscardContinuousBoost, "应弹出选择弃哪张加成")
	assert_true(game_logic.decision_info.can_pass, "required=false 时应可以略过")
	assert_eq(game_logic.decision_info.limitation, "mine")

	assert_true(game_logic.do_boost_name_card_choice_effect(player1, boost_id), "选自己的加成弃置")
	assert_eq(player1.strike_stat_boosts.power, 6, "弃置加成应使威力+6")
	assert_eq(player1.get_boosts(true).size(), 0, "被弃的持续性加成应离开场上")


# ===== 弹药哥布林：摸至多 2 张（可选 0~2）=====

func test_grenade_boost_caps_draw_to_two():
	position_players(player1, 4, player2, 6)
	var cid = give_player_specific_card(player1, "carcass_grenade_jump")

	assert_true(game_logic.do_boost(player1, cid, []), "弹药哥布林应能作为加成打出")
	assert_eq(game_logic.decision_info.type,
		Enums.DecisionType.DecisionType_PickNumberFromRange, "应弹数字选择器（0~2）")
	assert_eq(game_logic.decision_info.amount_min, 0, "可以选 0 张")
	assert_eq(game_logic.decision_info.amount, 2, "上限应为 2 张（不是固定摸 2）")


func test_grenade_boost_draws_exactly_the_chosen_number():
	position_players(player1, 4, player2, 6)
	var cid = give_player_specific_card(player1, "carcass_grenade_jump")
	assert_true(game_logic.do_boost(player1, cid, []))
	var hand_before = player1.hand.size()

	assert_true(game_logic.do_choice(player1, 1), "选择抽 1 张（区间下限 0 之后的第一档）")
	assert_eq(player1.hand.size(), hand_before + 1, "应只抽 1 张，而不是固定的 2 张")


# ===== S.T.G.：爆头付 6 怒气换威力+66 =====

func test_stg_headshot_pays_six_gauge_for_sixty_six_power():
	position_players(player1, 4, player2, 6)
	var gauge_ids = give_gauge(player1, 6)
	var effect = null
	for e in _custom_card("carcass_gunfire")["boost"]["effects"]:
		if e.get("effect_type") == "gauge_for_effect":
			effect = e
	assert_true(effect != null, "前置：应找到 S.T.G. 的 gauge_for_effect")
	assert_eq(effect.get("gauge_max"), 6, "需要支付 6 怒气")

	game_logic.change_game_state(Enums.GameState.GameState_PlayerDecision)
	game_logic.decision_info.clear()
	game_logic.decision_info.player = player1.my_id
	game_logic.decision_info.type = Enums.DecisionType.DecisionType_GaugeForEffect
	game_logic.decision_info.choice_card_id = -1
	game_logic.decision_info.effect = effect

	assert_true(game_logic.do_gauge_for_effect(player1, gauge_ids), "付 6 怒气应成功结算")
	assert_eq(player1.strike_stat_boosts.power, 66, "爆头应使威力+66")
	assert_eq(player1.gauge.size(), 0, "6 张怒气应被支付掉")


# ===== 守望：对手不能穿越我（参考杰弗里 3G 神圣裁决）=====

func test_watch_card_uses_engine_opponent_cant_move_past():
	var card = _custom_card("carcass_watch")
	var types = []
	for e in card["effects"]:
		types.append(e.get("effect_type"))
	assert_true(types.has("opponent_cant_move_past"),
		"守望应用引擎原语 opponent_cant_move_past（把标记记在对手身上）")
	assert_true(types.has("remove_opponent_cant_move_past"),
		"清理阶段要撤销对手的「不能穿越」")


func test_watch_stops_opponent_from_passing_and_punishes():
	position_players(player1, 4, player2, 6)
	game_logic.handle_strike_effect(-1, {"effect_type": "carcass_watch_guard"}, player1)
	game_logic.handle_strike_effect(-1, {"effect_type": "opponent_cant_move_past"}, player1)

	assert_true(player2.cannot_move_past_opponent, "守望持有者的对手应不能穿越")
	assert_false(player1.cannot_move_past_opponent, "守望持有者自己不该被自己的标记拦住")

	var life_before = player2.life
	player2.move_in_direction_by_amount(true, 3, false, -1, StrikeEffects.Advance)
	assert_eq(player2.arena_location, 5, "对手应被卡在守望者前一格，穿不过去")
	assert_eq(player2.life, life_before - 2, "阻止穿越应对对手造成 2 点非致命伤害")


func test_watch_removal_clears_opponent_flag():
	position_players(player1, 4, player2, 6)
	game_logic.handle_strike_effect(-1, {"effect_type": "opponent_cant_move_past"}, player1)
	assert_true(player2.cannot_move_past_opponent, "前置：对手已被阻止穿越")

	game_logic.handle_strike_effect(-1, {"effect_type": "remove_opponent_cant_move_past"}, player1)
	assert_false(player2.cannot_move_past_opponent, "整理阶段应撤销，恢复可穿越")

# ===== 觉醒行动选项：也要按「支付点数」判定（枪灵算 2 点）=====
#
# `local_game.can_do_exceed` 原先用 `len(gauge) + free_gauge` 按**张数**算，
# 于是怒气区只有两张枪灵（=4 点，够付 4 点觉醒费）时，觉醒行动选项会被禁用。

func test_exceed_option_available_with_two_gun_spirits():
	_to_gauge(player1, "carcass_dual_wield")
	_to_gauge(player1, "carcass_dual_wield")

	assert_eq(player1.gauge.size(), 2, "前置：怒气区只有 2 张牌")
	assert_eq(player1.get_available_gauge(), 4, "前置：两张枪灵 = 4 点")
	assert_eq(player1.get_exceed_cost(), 4, "前置：觉醒费 4 点")
	assert_true(game_logic.can_do_exceed(player1),
		"两张枪灵够付 4 点觉醒费，觉醒选项应可选（按张数算会被禁掉）")


func test_exceed_option_hidden_when_points_are_insufficient():
	_to_gauge(player1, "carcass_dual_wield")
	assert_eq(player1.get_available_gauge(), 2, "前置：一张枪灵 = 2 点")
	assert_false(game_logic.can_do_exceed(player1), "2 点付不了 4 点觉醒费")

	# 反向对照：普通技仍按 1 点算，3 点还是不够
	_to_gauge(player1, "standard_normal_spike")
	assert_eq(player1.get_available_gauge(), 3, "枪灵 + 普通技 = 3 点")
	assert_false(game_logic.can_do_exceed(player1), "3 点仍不够觉醒")


func test_exceed_option_available_with_four_normals():
	for i in range(4):
		_to_gauge(player1, "standard_normal_spike")
	assert_eq(player1.get_available_gauge(), 4, "4 张普通技 = 4 点")
	assert_true(game_logic.can_do_exceed(player1), "4 点应可以觉醒")


# ===== 2026-10-05 设计修订：管状物/恶魔子弹 0 费；枪炮齐鸣 S.T.G. 速度+1 =====

func test_demon_bullet_boost_is_free_and_keeps_armor_pierce_and_unconditional():
	var def = CardDataManager.get_card("carcass_tube")
	assert_eq(def["boost"]["display_name"], "恶魔子弹")
	assert_eq(def["boost"]["boost_type"], "continuous")
	assert_eq(def["boost"]["force_cost"], 0, "恶魔子弹改为 0 费")
	var types = []
	for e in def["boost"]["effects"]:
		types.append(e.get("effect_type"))
	assert_true(types.has("ignore_armor"), "恶魔子弹仍应无视护甲")
	assert_true(types.has("headshot_unconditional"), "恶魔子弹仍应让爆头只需击中")
	assert_true(types.has("remove_headshot_unconditional"), "离场时应撤销爆头放宽")

func test_gunfire_stg_boost_grants_plus_one_speed():
	var def = CardDataManager.get_card("carcass_gunfire")
	assert_eq(def["boost"]["display_name"], "S.T.G.")
	var speedups = []
	for e in def["boost"]["effects"]:
		if e.get("effect_type") == "speedup":
			speedups.append(e)
	assert_eq(speedups.size(), 1, "S.T.G. 应有一条「速度+1」")
	assert_eq(speedups[0].get("timing"), "during_strike", "速度+1 在战斗中生效")
	assert_eq(speedups[0].get("amount"), 1)

func test_gunfire_stg_headshot_pays_six_gauge_for_66_power():
	var def = CardDataManager.get_card("carcass_gunfire")
	var hit_effect = null
	for e in def["boost"]["effects"]:
		if e.get("timing") == "hit":
			hit_effect = e
	assert_true(hit_effect != null, "S.T.G. 应有击中效果")
	assert_eq(hit_effect.get("condition"), "headshot", "该效果由爆头触发")
	assert_eq(hit_effect.get("effect_type"), "gauge_for_effect")
	assert_eq(hit_effect.get("min_gauge"), 6, "至少支付 6 怒气")
	assert_eq(hit_effect.get("gauge_max"), 6, "至多支付 6 怒气")
	assert_true(hit_effect.get("can_pass"), "怒气不足时可以放弃")
	assert_eq(hit_effect.get("overall_effect", {}).get("effect_type"), "powerup")
	assert_eq(hit_effect.get("overall_effect", {}).get("amount"), 66, "支付 6 怒气获得威力+66")
