extends ExceedGutTest
# 诺艾尔·柯涅尔（noelle）—— 第七季模板 DIY 角色
# 常态：一回合一次，战斗中受到伤害时支付1能量（惩罚）；击中：可以摸1张牌
# 觉醒（费用2）：觉醒时摸2张牌；同惩罚；击中：摸1张牌或获得弃牌堆顶的牌
# 7 张卡的加成全部带「取消」（cancel_cost = 1，取消费用 1 怒气）

const CARD_IDS := [
	"noelle_purewhitearrow", "noelle_setbomb", "noelle_chargedfireball",
	"noelle_whirlwindslash", "noelle_cometdive",
	"noelle_holylightburst", "noelle_orbitalshield",
]

func who_am_i():
	return "noelle"

# ---------------- 卡组与卡定义 ----------------

func test_deck_loads_with_30_cards_and_7_custom_definitions():
	var deck = CardDataManager.get_deck_from_str_id("noelle")
	assert_not_null(deck, "noelle 卡组应能加载")
	assert_eq(deck.get("display_name"), "诺艾尔·柯涅尔")
	assert_eq(deck.get("exceed_cost"), 2, "觉醒费用应为 2")
	assert_eq(deck.get("season"), 0, "应放在春水那一季（season 0）")
	assert_eq(deck["cards"].size(), 30, "应为 30 张牌")
	assert_eq(deck["custom_card_definitions"].size(), 7, "应为 7 张自定义卡")
	for cid in CARD_IDS:
		assert_not_null(CardDataManager.get_card(cid), "%s 应能加载" % cid)

func test_ultras_cost_2_gauge_and_everything_else_is_free():
	var deck = CardDataManager.get_deck_from_str_id("noelle")
	var ultras := []
	for c in deck["custom_card_definitions"]:
		assert_eq(c.get("force_cost"), 0, "%s：第七季没有加成/能量费用" % c["id"])
		if c.get("gauge_cost", 0) > 0:
			ultras.append(c["id"])
	assert_eq(ultras.size(), 2, "只有 2 张必杀技带费用")
	for uid in ["noelle_holylightburst", "noelle_orbitalshield"]:
		assert_true(uid in ultras, "%s 应为 2 怒气必杀技" % uid)
		assert_eq(CardDataManager.get_card(uid)["gauge_cost"], 2)

func test_all_boosts_have_cancel_cost_1():
	for cid in CARD_IDS:
		var c = CardDataManager.get_card(cid)
		assert_eq(c["boost"].get("cancel_cost"), 1,
				"%s 的加成应为「取消 1 怒气」（第七季模板）" % cid)

# ---------------- 常态/觉醒技能 ----------------

func test_ability_and_exceed_ability_are_registered():
	var deck = CardDataManager.get_deck_from_str_id("noelle")
	var base_timings := []
	for e in deck["ability_effects"]:
		base_timings.append(e.get("timing"))
	assert_true("on_strike_damage_taken" in base_timings, "常态应有受伤惩罚时机")
	assert_true("hit" in base_timings, "常态应有击中摸牌")

	var ex_timings := []
	for e in deck["exceed_ability_effects"]:
		ex_timings.append(e.get("timing"))
	assert_true("on_strike_damage_taken" in ex_timings, "觉醒面同样有受伤惩罚")
	assert_true("hit" in ex_timings, "觉醒面有击中摸牌/取弃牌堆顶")
	assert_eq(deck.get("on_exceed", {}).get("effect_type"), "draw", "觉醒时应摸牌")
	assert_eq(deck.get("on_exceed", {}).get("amount"), 2, "觉醒时摸 2 张")

	# 觉醒技能「击中」choice 应有 3 个选项：摸1张牌 / 获得弃牌堆顶 / 都不要
	var ex_hit_choice = null
	for e in deck["exceed_ability_effects"]:
		if e.get("timing") == "hit" and e.get("effect_type") == "choice":
			ex_hit_choice = e
	assert_not_null(ex_hit_choice, "觉醒技能应有击中 choice")
	assert_eq(ex_hit_choice["choice"].size(), 3, "觉醒技能击中应有 3 个选项")
	var ex_has_pass = false
	for opt in ex_hit_choice["choice"]:
		if opt.get("effect_type") == "pass":
			ex_has_pass = true
	assert_true(ex_has_pass, "觉醒技能击中应有「都不要」选项")

func test_damage_toll_handler_opens_force_payment_decision():
	position_players(player1, 3, player2, 5)
	player1.discard_hand()
	give_player_specific_card(player1, "gg_normal_grasp")
	assert_false(player1.noelle_damage_toll_used_this_turn)
	game_logic.do_effect_if_condition_met(player1, -1,
			{"effect_type": "noelle_damage_toll"}, null)
	assert_true(player1.noelle_damage_toll_used_this_turn, "应标记本回合已触发")
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision,
			"应弹出支付能量的决策")
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ForceForEffect)
	assert_eq(game_logic.decision_info.player, player1.my_id)

func test_damage_toll_is_once_per_turn():
	position_players(player1, 3, player2, 5)
	player1.discard_hand()
	give_player_specific_card(player1, "gg_normal_grasp")
	give_player_specific_card(player1, "gg_normal_cross")
	player1.noelle_damage_toll_used_this_turn = true
	game_logic.do_effect_if_condition_met(player1, -1,
			{"effect_type": "noelle_damage_toll"}, null)
	assert_ne(game_logic.game_state, Enums.GameState.GameState_PlayerDecision,
			"本回合已触发过时不应再弹决策")

func test_damage_toll_not_triggered_by_zero_damage():
	# 双方都出格挡（威力 0）→ 实际伤害 0 → 不应触发惩罚
	position_players(player1, 3, player2, 5)
	player1.discard_hand()
	player2.discard_hand()
	var blk1 = give_player_specific_card(player1, "gg_normal_block")
	var blk2 = give_player_specific_card(player2, "gg_normal_block")
	advance_turn(player1)  # 把回合交给 p2，让 p2 发起战斗
	execute_strike(player2, player1, blk2, blk1, false, false, [], [])
	assert_false(player1.noelle_damage_toll_used_this_turn,
			"受到 0 点实际伤害不应触发惩罚")
	validate_life(player1, 30, player2, 30)

func test_damage_toll_triggers_on_real_damage_and_pays_force():
	default_game_setup("baiken")  # 对手换非诺艾尔，避免对手也触发同类技能
	position_players(player1, 3, player2, 5)
	player1.discard_hand()
	player2.discard_hand()
	var atk = give_player_specific_card(player2, "gg_normal_slash")    # 4 威力
	var p1_def = give_player_specific_card(player1, "gg_normal_focus")  # 护甲2 → 实受2
	var pay = give_player_specific_card(player1, "gg_normal_grasp")     # 用于支付的手牌
	advance_turn(player1)  # 把回合交给 p2
	# def_choices：[pay] 支付 1 能量（惩罚）→ 0 选「摸1张牌」（击中技能）
	execute_strike(player2, player1, atk, p1_def, false, false, [], [[pay], 0])
	assert_false(player1.is_card_in_hand(pay),
			"受到实际伤害后，用于支付惩罚的手牌应被弃置")
	assert_false(player1.noelle_damage_toll_used_this_turn,
			"回合交接时应重置「一回合一次」标志")
	validate_life(player1, 28, player2, 26)

func test_damage_toll_does_not_trigger_on_lethal_damage():
	default_game_setup("baiken")
	position_players(player1, 3, player2, 5)
	player1.life = 2
	player1.discard_hand()
	player2.discard_hand()
	var atk = give_player_specific_card(player2, "gg_normal_slash")
	var p1_def = give_player_specific_card(player1, "gg_normal_focus")
	give_player_specific_card(player1, "gg_normal_grasp")
	advance_turn(player1)
	execute_strike(player2, player1, atk, p1_def, false, false, [], [], false)
	assert_true(game_logic.game_over, "致死伤害应直接结束对局")
	assert_eq(game_logic.game_state, Enums.GameState.GameState_GameOver)
	assert_eq(game_logic.game_over_winning_player.my_id, player2.my_id)
	assert_false(player1.noelle_damage_toll_used_this_turn,
			"致死伤害不应触发或消耗受伤付款 UA")

func test_exceeded_damage_toll_does_not_trigger_on_lethal_damage():
	default_game_setup("baiken")
	position_players(player1, 3, player2, 5)
	player1.exceed()
	player1.life = 2
	player1.discard_hand()
	player2.discard_hand()
	var atk = give_player_specific_card(player2, "gg_normal_slash")
	var p1_def = give_player_specific_card(player1, "gg_normal_focus")
	give_player_specific_card(player1, "gg_normal_grasp")
	advance_turn(player1)
	execute_strike(player2, player1, atk, p1_def, false, false, [], [], false)
	assert_true(game_logic.game_over, "觉醒面受到致死伤害应直接结束对局")
	assert_eq(game_logic.game_state, Enums.GameState.GameState_GameOver)
	assert_eq(game_logic.game_over_winning_player.my_id, player2.my_id)
	assert_false(player1.noelle_damage_toll_used_this_turn,
			"觉醒面受到致死伤害不应触发或消耗受伤付款 UA")

# ---------------- 强制支付（照 gordeau 觉醒行动的写法） ----------------
# 「强制」由两个字段共同构成，缺一不可：
#   required: true                   → game.gd can_cancel = false（不能取消）
#   overall_effect 非 null           → game.gd require_max = force_max（必须付满1，不能付0确认）

func test_damage_toll_payment_cannot_be_cancelled():
	position_players(player1, 3, player2, 5)
	player1.discard_hand()
	give_player_specific_card(player1, "gg_normal_grasp")
	game_logic.do_effect_if_condition_met(player1, -1,
			{"effect_type": "noelle_damage_toll"}, null)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	var effect = game_logic.decision_info.effect
	assert_true(effect.get("required", false),
			"惩罚必须 required=true，否则 UI 允许取消")
	# core 层同样拒绝取消 required 的支付
	assert_false(game_logic.do_force_for_effect(player1, [], false, true),
			"required 的支付不应允许取消")
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision,
			"取消被拒后仍应停留在支付决策")

func test_damage_toll_requires_full_payment():
	position_players(player1, 3, player2, 5)
	player1.discard_hand()
	give_player_specific_card(player1, "gg_normal_grasp")
	game_logic.do_effect_if_condition_met(player1, -1,
			{"effect_type": "noelle_damage_toll"}, null)
	var effect = game_logic.decision_info.effect
	assert_eq(effect.get("force_max"), 1, "强制支付 1 能量")
	assert_not_null(effect.get("overall_effect"),
			"overall_effect 必须非 null，否则 UI 的 require_max 为 -1，可以付 0 点确认")
	assert_null(effect.get("per_force_effect"),
			"per_force_effect 为 null（惩罚没有按点收益）")

# ---------------- 卡牌效果 ----------------

func test_pure_white_arrow_speed_bonus_from_boost_zone():
	var c = CardDataManager.get_card("noelle_purewhitearrow")
	assert_true(c.get("may_set_from_boost", false), "应可以从加成区设置攻击")
	var has_speed := false
	for e in c["effects"]:
		if e.get("effect_type") == "speedup" and e.get("condition") == "was_set_from_boosts":
			has_speed = true
	assert_true(has_speed, "应有「从加成区设置则速度+1」")

func test_set_bomb_resets_to_space_on_miss():
	# 设置炸弹未命中 → 整理阶段「重新设置」到场地任意格（可挪位置），并被维持
	position_players(player1, 5, player2, 9)  # 距离4，射程 0-1 → 必 miss
	player1.discard_hand()
	var bomb = give_player_specific_card(player1, "noelle_setbomb")
	var blk = give_player_specific_card(player2, "gg_normal_block")
	# init_choices：未命中后的「选择位置」决策 → 放到 7 号格
	execute_strike(player1, player2, bomb, blk, false, false, [7], [])
	assert_eq(player1.get_boost_location(bomb), 7,
			"未命中时应重新设置到所选的场地格")
	var in_play := false
	for b in player1.continuous_boosts:
		if b.id == bomb:
			in_play = true
	assert_true(in_play, "地面炸弹应同时是持续性加成（被维持）")
	var in_discard := false
	for d in player1.discards:
		if d.id == bomb:
			in_discard = true
	assert_false(in_discard, "被维持的卡不应进入弃牌堆")

func test_ground_bomb_set_from_boost_keeps_origin_and_logs_location():
	# 从加成区（地面炸弹）设置攻击：攻击源 = 地面炸弹所在格，场地图标保留，log 标注位置
	position_players(player1, 3, player2, 5)
	player1.discard_hand()
	var bomb = give_player_specific_card(player1, "noelle_setbomb")
	give_player_specific_card(player2, "gg_normal_block")
	assert_true(game_logic.do_boost(player1, bomb))
	assert_true(game_logic.do_choice(player1, get_choice_index_for_position(7)))
	advance_turn(player2)  # 回合回到 player1
	game_logic.get_latest_events()
	assert_true(game_logic.do_strike(player1, bomb, false, -1),
			"应从加成区成功设置攻击")
	assert_eq(game_logic.active_strike.initiator_set_from_boost_space, 7,
			"攻击源应为地面炸弹所在格")
	assert_eq(player1.get_boost_location(bomb), 7,
			"设置攻击后场地图标应保留（作为攻击源）")
	var found := false
	for entry in game_logic.full_combat_log:
		if "设置攻击" in entry.message and "位置7" in entry.message:
			found = true
	assert_true(found, "log 应标注攻击源位置，方便双方查看")

func test_ground_bomb_set_from_boost_miss_resets_to_new_space():
	# 从加成区（位置7）设置攻击 → 未命中 → 重新设置到位置3（攻击源移动，不重复放置）
	position_players(player1, 3, player2, 5)
	player1.discard_hand()
	var bomb = give_player_specific_card(player1, "noelle_setbomb")
	var blk = give_player_specific_card(player2, "gg_normal_block")
	assert_true(game_logic.do_boost(player1, bomb))
	assert_true(game_logic.do_choice(player1, get_choice_index_for_position(7)))
	advance_turn(player2)
	game_logic.get_latest_events()
	# 攻击源位置7，对手位置5，射程0-1 → 距离2未命中 → 重新设置到位置3
	execute_strike(player1, player2, bomb, blk, false, false, [3], [])
	assert_eq(player1.get_boost_location(bomb), 3,
			"未命中重新设置后，攻击源应移到新位置（而非报错/重复放置）")

# ---------------- 场地加成（地面炸弹）的贴图 ----------------
# 场地上的加成靠 buddy 图形渲染：卡定义给 `linked_buddy_id`，卡组给 buddy_* 列表，
# 图形资源在 res://assets/character_animations/<graphics_id>/animations.tres

func test_setbomb_declares_linked_buddy_id():
	var c = CardDataManager.get_card("noelle_setbomb")
	assert_eq(c.get("linked_buddy_id"), "noelle_groundbomb",
			"场地加成必须有 linked_buddy_id，否则放置时 get_buddy_id_for_boost 会断言失败")

func test_ground_bomb_resolves_buddy_id_without_assert():
	position_players(player1, 3, player2, 5)
	player1.discard_hand()
	var bomb = give_player_specific_card(player1, "noelle_setbomb")
	assert_eq(player1.get_buddy_id_for_boost(bomb), "noelle_groundbomb1",
			"应能解析出场地贴图用的 buddy id")

func test_char_select_portrait_is_a_real_image_not_placeholder():
	var tex_path = "res://assets/portraits/noelle.png"
	assert_true(ResourceLoader.exists(tex_path, "Texture2D"))
	var tex = load(tex_path)
	assert_eq(tex.get_size(), Vector2(150, 150), "选人头像应为 150x150，与其它角色一致")

func test_orbital_shield_gains_power_from_armor():
	# 环轨护盾：击中时失去所有护甲并增加等量威力（护甲4 → +4威力）
	var c = CardDataManager.get_card("noelle_orbitalshield")
	assert_eq(c.get("armor"), 4)
	assert_eq(c.get("power"), 0)
	var found := false
	for e in c["effects"]:
		if e.get("effect_type") == "powerup_per_armor":
			found = true
	assert_true(found, "应有「失去护甲转威力」")
	var dodge_found := false
	for e in c["effects"]:
		if e.get("effect_type") == "dodge_at_range":
			assert_eq(e.get("range_min"), 4, "距离4起闪避")
			dodge_found = true
	assert_true(dodge_found, "应有「距离4+的攻击无法击中你」")

func test_comet_dive_can_play_boost_from_hand_on_hit():
	var c = CardDataManager.get_card("noelle_cometdive")
	var ok := false
	for e in c["effects"]:
		if e.get("timing") == "hit" and e.get("effect_type") == "choice":
			for opt in e["choice"]:
				if opt.get("effect_type") == "boost_then_sustain":
					assert_eq(opt.get("sustain"), false, "打出的加成不维持")
					assert_eq(opt.get("ignore_costs"), true, "忽略费用")
					ok = true
	assert_true(ok, "击中时应可选择从手牌打出一张加成")

func test_whirlwind_slash_advances_through_and_moves():
	var c = CardDataManager.get_card("noelle_whirlwindslash")
	var ok := false
	for e in c["effects"]:
		if e.get("timing") == "before" and e.get("effect_type") == "advance":
			assert_eq(e.get("amount"), 3)
			var and_e = e.get("and", {})
			assert_eq(and_e.get("effect_type"), "dodge_attacks")
			assert_eq(and_e.get("condition"), "advanced_through")
			ok = true
	assert_true(ok, "前置应为「前进3，穿过则对手无法击中你」")

func test_charged_fireball_hit_draws_and_moves():
	var c = CardDataManager.get_card("noelle_chargedfireball")
	var ok := false
	for e in c["effects"]:
		if e.get("timing") == "hit" and e.get("effect_type") == "draw":
			assert_eq(e.get("amount"), 1)
			assert_eq(e.get("and", {}).get("effect_type"), "choice")
			ok = true
	assert_true(ok, "击中应为「摸1张牌，移动至多1」")

func test_magic_shotgun_gives_normals_an_opponent_choice():
	var c = CardDataManager.get_card("noelle_purewhitearrow")
	var boost = c["boost"]
	assert_eq(boost.get("boost_type"), "continuous")
	assert_eq(boost.get("display_name"), "魔法霰弹")
	var ok := false
	for e in boost["effects"]:
		if e.get("effect_type") == "noelle_magic_shotgun":
			assert_eq(e.get("condition"), "is_normal_attack", "只对普通技生效")
			ok = true
	assert_true(ok, "加成应给普通技加一条击中效果")

func test_holylight_burst_has_stun_immunity_and_push_3():
	var c = CardDataManager.get_card("noelle_holylightburst")
	var stun := false
	var push3 := false
	for e in c["effects"]:
		if e.get("effect_type") == "stun_immunity":
			stun = true
		if e.get("timing") == "hit" and e.get("effect_type") == "push" and e.get("amount") == 3:
			push3 = true
	assert_true(stun, "应击晕免疫")
	assert_true(push3, "击中应击退3")
