extends ExceedGutTest

## ==========================================================================
## Umina — Shadow Chorus copy regression tests.
##
## Rule: "Shadow Chorus (R1-1 P1 S1). On reveal, it copies a card from your
## Dreamlands. If there is no card in Dreamlands, it uses its own stats."
##
## The copy applies ONLY for the current strike: before being set as an
## attack the card shows itself, and after the strike the card must keep its
## own definition (it must not become a permanent copy of the Dreamlands
## card).
## ==========================================================================

func who_am_i():
	return "umina"

func before_each():
	default_game_setup("ryu")
	gut.p("ran setup", 2)

# Put a card into Umina's Dreamlands (set_aside) directly.
func put_in_dreamlands(player, def_id):
	give_player_specific_card(player, def_id)
	player.set_aside_cards.append(player.hand.pop_back())

func find_card_by_instance_id(_player, card_id, zones):
	for zone in zones:
		for c in zone:
			if c.id == card_id:
				return c
	return null

func has_def_in_zone(_player, def_id, zone):
	for card in zone:
		if card.definition.get("id", "") == def_id:
			return true
	return false

# ===== Baseline: no Dreamlands card -> Shadow Chorus keeps own stats =====

func test_shadow_chorus_without_dreamlands_keeps_own_definition():
	position_players(player1, 4, player2, 5)  # dist1, Shadow R1 hits
	# No card in Dreamlands -> Shadow Chorus uses its own stats (P1 S1).
	# Shadow S1 vs Focus S1 (tie, initiator first): P1 vs Focus G0 -> stun.
	# Shadow hits -> goes to gauge. Focus is stunned and skipped.
	var shadow_id = give_player_specific_card(player1, "umina_shadow_chorus")
	execute_strike(player1, player2, shadow_id, "standard_normal_focus",
		false, false,
		[], [])
	var shadow_card = find_card_by_instance_id(player1, shadow_id, [player1.gauge, player1.discards])
	assert_not_null(shadow_card, "Shadow Chorus should be in gauge or discard after the strike")
	assert_eq(shadow_card.definition.get("id"), "umina_shadow_chorus",
		"Without a Dreamlands card Shadow Chorus must keep its own definition")

# ===== Regression: copy must not permanently pollute the card definition =====

func test_shadow_chorus_copy_restores_own_definition_after_strike():
	position_players(player1, 3, player2, 5)  # dist2
	put_in_dreamlands(player1, "umina_hollow_space")
	var shadow_id = give_player_specific_card(player1, "umina_shadow_chorus")
	# Shadow Chorus R1-1 P1 S1 vs Grasp(R1). Dist2: Grasp misses (no counter).
	# On reveal Shadow Chorus copies Hollow Space (R3-6 P4 S4) from Dreamlands.
	# Dist2 is outside R3-6 -> Shadow misses -> goes to discard. The copied
	# Hollow Space after effect (choice advance 3 / retreat 3) fires: advance (idx0).
	execute_strike(player1, player2, shadow_id, "standard_normal_grasp",
		false, false,
		[0],  # copied Hollow Space after: advance 3
		[])
	var shadow_card = find_card_by_instance_id(player1, shadow_id, [player1.gauge, player1.discards])
	assert_not_null(shadow_card, "Shadow Chorus should be in gauge or discard after the strike")
	assert_eq(shadow_card.definition.get("id"), "umina_shadow_chorus",
		"Shadow Chorus definition must be restored after the strike (copy is temporary)")
	assert_eq(shadow_card.definition.get("type"), "special",
		"Restored Shadow Chorus must be a Special again (not a copied normal) so it never appears in normal-card picks (e.g. Focus Reading)")

func test_shadow_chorus_copy_hit_restores_own_definition():
	# Same regression, hit path: Shadow Chorus copies Hollow Space (R3-6 P4 S4),
	# hits at dist4, goes to gauge, and must still be restored to itself.
	position_players(player1, 3, player2, 7)  # dist4
	put_in_dreamlands(player1, "umina_hollow_space")
	var shadow_id = give_player_specific_card(player1, "umina_shadow_chorus")
	# Shadow copies Hollow Space on reveal: R3-6 hits at dist4. Grasp(R1) misses.
	# Hollow Space P4 -> p2 takes 4. Copied after effect (choice advance/retreat 3)
	# fires: advance (idx0).
	execute_strike(player1, player2, shadow_id, "standard_normal_grasp",
		false, false,
		[0],  # copied Hollow Space after: advance 3
		[])
	validate_life(player1, 30, player2, 26)
	var shadow_card = find_card_by_instance_id(player1, shadow_id, [player1.gauge, player1.discards])
	assert_not_null(shadow_card, "Shadow Chorus should be in gauge (hit) after the strike")
	assert_eq(shadow_card.definition.get("id"), "umina_shadow_chorus",
		"Shadow Chorus definition must be restored after a hit too")

# ===== Carl Swangee synergy: copied non-special must not trigger +1 armor =====

func test_shadow_copying_normal_does_not_trigger_carl_swangee_armor():
	# Carl Swangee (S2) ability: "While your opponent's attack is a Special, +1
	# Armor" (opponent_is_special_attack -> armorup). Shadow Chorus that copied
	# a NORMAL from Dreamlands is not a Special, so Carl's ability must NOT fire.
	# The copied definition must be what the condition sees during the strike.
	default_game_setup("carlswangee")
	position_players(player1, 3, player2, 5)  # dist2
	put_in_dreamlands(player1, "standard_normal_sweep")
	var shadow_id = give_player_specific_card(player1, "umina_shadow_chorus")
	# Shadow copies Sweep (R1-3 P6 S2, normal) on reveal. Dist2: hits.
	# Grasp(R1) misses at dist2 (no counter). Sweep hit: opponent discards 1
	# random (no decision). Carl's armorup condition sees type "normal" -> false.
	execute_strike(player1, player2, shadow_id, "standard_normal_grasp",
		false, false,
		[], [])
	# P6 vs Grasp armor 0 (no Carl armor bonus) -> p2 takes 6.
	validate_life(player1, 30, player2, 24)

func test_shadow_copying_special_does_trigger_carl_swangee_armor():
	# Control test: Shadow Chorus copying a SPECIAL (Hollow Space) IS a Special,
	# so Carl Swangee's +1 Armor must fire. Guards against over-correcting.
	default_game_setup("carlswangee")
	position_players(player1, 3, player2, 6)  # dist3
	put_in_dreamlands(player1, "umina_hollow_space")
	var shadow_id = give_player_specific_card(player1, "umina_shadow_chorus")
	# Shadow copies Hollow Space (R3-6 P4 S4, special) on reveal. Dist3: hits.
	# Grasp(R1) misses at dist3. Carl's armorup fires (special) -> Grasp armor 1.
	# Hollow Space after: choice advance/retreat 3 -> advance (idx0).
	execute_strike(player1, player2, shadow_id, "standard_normal_grasp",
		false, false,
		[0],  # copied Hollow Space after: advance 3
		[])
	# P4 vs Grasp armor 1 (Carl bonus) -> p2 takes 3.
	validate_life(player1, 30, player2, 27)


# ===== v2.5: Dreamlands stun immunity (Shadow copy + same-name hand card) =====

func test_shadow_copy_gets_dreamlands_stun_immunity():
	# Shadow copies a Dreamlands card with S2/G0 while opponent uses a faster hit.
	# Umina should still activate due to Dreamlands stun immunity.
	position_players(player1, 4, player2, 5)  # dist1
	put_in_dreamlands(player1, "vega_rollingcrystalflash")
	var shadow_id = give_player_specific_card(player1, "umina_shadow_chorus")
	execute_strike(player1, player2, shadow_id, "standard_normal_assault",
		false, false,
		[], [])
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_Strike_Stun_Immunity, player1)
	# Copied card resolves hit push 3, proving it was not skipped by stun.
	validate_positions(player1, 4, player2, 8)

func test_hand_same_named_card_gets_dreamlands_stun_immunity():
	# Directly striking with a hand card that matches Dreamlands should also grant
	# stun immunity, allowing the card's effects to resolve.
	position_players(player1, 4, player2, 5)  # dist1
	put_in_dreamlands(player1, "standard_normal_cross")
	execute_strike(player1, player2, "standard_normal_cross", "standard_normal_grasp",
		false, false,
		[], [0])
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_Strike_Stun_Immunity, player1)
	validate_life(player1, 27, player2, 27)
	validate_positions(player1, 1, player2, 5)


# ===== v2.6: defender seal trigger + cross-season normal matching =====

func test_exceeded_defender_can_seal_dreamlands_for_triggers():
	# Exceeded Umina should be able to seal Dreamlands on set_strike as defender.
	# The sealed Sweep contributes a hit trigger (opponent random discard 1).
	player1.exceeded = true
	position_players(player1, 4, player2, 5)  # dist1
	put_in_dreamlands(player1, "standard_normal_sweep")
	advance_turn(player1)
	execute_strike(player2, player1, "standard_normal_spike", "standard_normal_grasp",
		false, false,
		[], [0], true)
	var events = game_logic.get_latest_events()
	assert_eq(player1.set_aside_cards.size(), 0,
		"Dreamlands card should be sealed when defender chooses seal on set_strike")
	assert_true(has_def_in_zone(player1, "standard_normal_sweep", player1.sealed),
		"Chosen Dreamlands card should be in sealed")
	validate_has_event(events, Enums.EventType.EventType_Seal, player1)

func test_cross_season_normals_match_by_speed_for_stun_immunity():
	# Dreamlands Slash (GG normal, S5) should match UNI Assault (S5) for stun
	# immunity even though definition IDs differ.
	position_players(player1, 4, player2, 5)  # dist1
	put_in_dreamlands(player1, "gg_normal_slash")
	execute_strike(player1, player2, "uni_normal_assault", "standard_normal_grasp",
		false, false,
		[], [0])
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_Strike_Stun_Immunity, player1)

func test_special_does_not_give_stun_immunity_to_normal_same_speed():
	# 幻梦境里是 7 速 special（Terror Whispers），player1 用 7 速 normal（Grasp）防御。
	# normal 与 special 不是同名卡，即使速度相同也不应获得击晕免疫。
	# 对手（initiator）用同速 Grasp 先行动命中 player1，验证 player1 被正常击晕。
	position_players(player1, 4, player2, 5)  # dist1
	put_in_dreamlands(player1, "umina_terror_whispers")
	advance_turn(player1)  # 把回合交给 player2（对手），让其发起战斗
	execute_strike(player2, player1, "standard_normal_grasp", "standard_normal_grasp",
		false, false,
		[0], [])
	var events = game_logic.get_latest_events()
	validate_not_has_event(events, Enums.EventType.EventType_Strike_Stun_Immunity, player1)
	validate_has_event(events, Enums.EventType.EventType_Strike_Stun, player1)

func test_is_spiraling_match_cross_season_rules():
	var slash_id = give_player_specific_card(player1, "gg_normal_slash")
	var assault_id = give_player_specific_card(player1, "uni_normal_assault")
	var dive_id = give_player_specific_card(player1, "uni_normal_dive")
	var shadow_id = give_player_specific_card(player1, "umina_shadow_chorus")
	var card_db = game_logic.get_card_database()
	var slash_card = card_db.get_card(slash_id)
	var assault_card = card_db.get_card(assault_id)
	var dive_card = card_db.get_card(dive_id)
	var shadow_card = card_db.get_card(shadow_id)

	assert_true(game_logic._is_spiraling_match("gg_normal_slash", assault_card),
		"Normal-vs-normal should match by speed across seasons")
	assert_false(game_logic._is_spiraling_match("gg_normal_slash", dive_card),
		"Normal-vs-normal should not match when speed differs")
	assert_false(game_logic._is_spiraling_match("gg_normal_slash", shadow_card),
		"Non-normal cards should not speed-match normals")
	assert_true(game_logic._is_spiraling_match("umina_shadow_chorus", shadow_card),
		"Non-normal matching should use exact definition id")

	# Regression: a normal must NOT match a same-speed special (different card name).
	# e.g. 7-speed Grasp vs 7-speed Terror Whispers.
	var terror_id = give_player_specific_card(player1, "umina_terror_whispers")
	var grasp_id = give_player_specific_card(player1, "standard_normal_grasp")
	var terror_card = card_db.get_card(terror_id)
	var grasp_card = card_db.get_card(grasp_id)
	assert_false(game_logic._is_spiraling_match("umina_terror_whispers", grasp_card),
		"Normal must not speed-match a special, even at the same speed")
	assert_true(game_logic._is_spiraling_match("umina_terror_whispers", terror_card),
		"Special-vs-special should still match by exact id")


# ===== v2.7: Unknown Khadath swallow/cleanup behavior =====

func test_unknown_khadath_defender_swallows_attack_and_ends_strike():
	# Defender Khadath: initiator acts first on same speed, misses at dist3,
	# then Khadath swallows initiator attack into Dreamlands and moves itself to gauge.
	position_players(player1, 5, player2, 2)  # dist3
	var p1_gauge = give_gauge(player1, 3)
	advance_turn(player1)
	var strike_cards = execute_strike(player2, player1, "uni_normal_cross", "umina_unknown_khadath",
		false, false,
		[], [p1_gauge])
	var init_card_id = strike_cards[0]
	var def_card_id = strike_cards[1]
	assert_not_null(find_card_by_instance_id(player1, init_card_id, [player1.set_aside_cards]),
		"Khadath should move initiator attack into Umina Dreamlands")
	assert_not_null(find_card_by_instance_id(player1, def_card_id, [player1.gauge]),
		"Khadath should move itself to Umina gauge")

func test_unknown_khadath_faster_swallows_attack_and_ends_strike():
	# Initiator Khadath (card1 path) should also swallow attack and end strike immediately.
	position_players(player1, 5, player2, 2)  # dist3
	var p1_gauge = give_gauge(player1, 3)
	var strike_cards = execute_strike(player1, player2, "umina_unknown_khadath", "standard_normal_assault",
		false, false,
		[p1_gauge], [])
	var init_card_id = strike_cards[0]
	var def_card_id = strike_cards[1]
	assert_not_null(find_card_by_instance_id(player1, def_card_id, [player1.set_aside_cards]),
		"Khadath should move defender attack into Umina Dreamlands")
	assert_not_null(find_card_by_instance_id(player1, init_card_id, [player1.gauge]),
		"Khadath should move itself to Umina gauge on card1 path too")

# ===== Whispers in the Dark: 执行幻梦境卡的即时加成时必须在玩家决策处停下 =====
#
# Shadow Chorus 的加成 Whispers in the Dark：抽1张，然后执行幻梦境中一张牌的
# 即时加成效果（忽略其能量费用）。
# 幻梦境里放「专注」时，其加成为 Reading = reading_normal + strike：
# 必须【先】让玩家声明一张普通技，再发起战斗。
# 原实现用同步 for 循环跑完效果列表，reading_normal 刚建好的 ReadingNormal 决策
# 会被紧随其后的 strike 覆盖成 StrikeNow —— 玩家永远选不到牌。

func test_whispers_in_the_dark_stops_for_reading_normal_naming():
	position_players(player1, 3, player2, 5)  # dist2
	put_in_dreamlands(player1, "standard_normal_focus")
	assert_eq(player1.set_aside_cards.size(), 1, "Dreamlands 应有 1 张 专注")

	var shadow_id = give_player_specific_card(player1, "umina_shadow_chorus")
	assert_true(game_logic.do_boost(player1, shadow_id), "打出 Whispers in the Dark 失败")

	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision,
		"Whispers 触发 专注 的加成后应停下等玩家声明普通技（不能被后续 strike 覆盖）")
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ReadingNormal,
		"应为 ReadingNormal 决策（声明一张普通技）")
	assert_eq(game_logic.decision_info.player, player1.my_id,
		"应由 Umina 自己声明")

	# 声明完成后，被排队的 strike 效果应继续执行 → 进入等待发起战斗
	assert_true(game_logic.do_boost_name_card_choice_effect(player1, player1.set_aside_cards[0].id),
		"声明普通技失败")
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike,
		"声明完应继续执行 strike 效果并进入发起战斗")


# ===== 觉醒后幻梦境不能直接选中战斗 =====
# 正面 Dreamlands 可用其卡直接发起 strike；觉醒后 Dreamlands 翻面变成 face attack，
# 只能 set_strike 封印其 before/hit/after 效果，不能再直接选卡战斗。

func test_exceeded_cannot_strike_directly_from_dreamlands():
	position_players(player1, 4, player2, 5)
	put_in_dreamlands(player1, "standard_normal_assault")
	player1.exceeded = true
	var dream_id = player1.set_aside_cards[0].id
	assert_false(game_logic.do_strike(player1, dream_id, false, -1),
		"觉醒后不应从幻梦境直接攻击")
	assert_eq(player1.set_aside_cards.size(), 1,
		"被拒绝的幻梦境卡不应离开幻梦境")

func test_non_exceeded_can_strike_directly_from_dreamlands():
	position_players(player1, 4, player2, 5)
	put_in_dreamlands(player1, "standard_normal_assault")
	var dream_id = player1.set_aside_cards[0].id
	assert_true(game_logic.do_strike(player1, dream_id, false, -1),
		"未觉醒时应能从幻梦境直接攻击")


# ===== 读心(Reading)：幻梦境里的目标牌可作为响应来源（非觉醒）=====
# 非觉醒 umina 手牌没有目标牌、但幻梦境有目标牌时，读心不直接亮手牌，
# 而是弹选择：从幻梦境设置目标牌，或展示手牌。手牌与幻梦境都有目标牌时也可自由选。

func test_reading_dreamlands_card_offered_as_response():
	# 幻梦境有 sweep、手牌没有 sweep：读心声明 sweep 应弹 2 个选项（幻梦境 sweep + 展示手牌）
	position_players(player1, 3, player2, 6)
	advance_turn(player1)
	player1.discard_hand()
	put_in_dreamlands(player1, "standard_normal_sweep")
	give_player_specific_card(player1, "umina_shadow_chorus")

	var reading_id = give_player_specific_card(player2, "standard_normal_focus")
	var assault_id = give_player_specific_card(player2, "standard_normal_assault")
	assert_true(game_logic.do_boost(player2, reading_id), "打 Reading 失败")
	assert_true(game_logic.do_boost_name_card_choice_effect(player2, player1.set_aside_cards[0].id), "声明 sweep 失败")
	assert_true(game_logic.do_strike(player2, assault_id, false, -1), "player2 发起攻击失败")

	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseSimultaneousEffect)
	assert_eq(game_logic.decision_info.choice.size(), 2, "应有 2 个选项：幻梦境 sweep + 展示手牌")
	assert_true(game_logic.decision_info.choice[0].get("from_set_aside", false),
		"第一个选项应是从幻梦境设置")

	# 选「幻梦境 sweep」→ 从幻梦境设置攻击，幻梦境卡离场
	var dream_id = game_logic.decision_info.choice[0]["card_id"]
	assert_true(game_logic.do_choice(player1, 0), "选择幻梦境 sweep 失败")
	assert_true(game_logic.do_strike(player1, dream_id, false, -1), "从幻梦境设置攻击失败")
	assert_eq(player1.set_aside_cards.size(), 0, "幻梦境 sweep 应离开幻梦境进入战斗")

func test_reading_dreamlands_card_can_choose_reveal_hand():
	# 幻梦境有 sweep、手牌没有 sweep：读心可自由选择「展示手牌」而非设置幻梦境卡
	position_players(player1, 3, player2, 6)
	advance_turn(player1)
	player1.discard_hand()
	put_in_dreamlands(player1, "standard_normal_sweep")
	var shadow_id = give_player_specific_card(player1, "umina_shadow_chorus")

	var reading_id = give_player_specific_card(player2, "standard_normal_focus")
	var assault_id = give_player_specific_card(player2, "standard_normal_assault")
	assert_true(game_logic.do_boost(player2, reading_id), "打 Reading 失败")
	assert_true(game_logic.do_boost_name_card_choice_effect(player2, player1.set_aside_cards[0].id), "声明 sweep 失败")
	assert_true(game_logic.do_strike(player2, assault_id, false, -1), "player2 发起攻击失败")

	assert_eq(game_logic.decision_info.choice.size(), 2)
	assert_true(game_logic.do_choice(player1, 1), "选择展示手牌失败")
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_RevealHand, player1)
	assert_eq(player1.set_aside_cards.size(), 1, "选展示手牌时幻梦境 sweep 应保留")

func test_reading_hand_and_dreamlands_both_offer_choice():
	# 手牌 + 幻梦境都有 sweep：读心应给出 3 个选项（手牌 sweep、EX sweep、幻梦境 sweep）
	position_players(player1, 3, player2, 6)
	advance_turn(player1)
	player1.discard_hand()
	put_in_dreamlands(player1, "standard_normal_sweep")
	give_player_specific_card(player1, "standard_normal_sweep")

	var reading_id = give_player_specific_card(player2, "standard_normal_focus")
	var assault_id = give_player_specific_card(player2, "standard_normal_assault")
	assert_true(game_logic.do_boost(player2, reading_id), "打 Reading 失败")
	assert_true(game_logic.do_boost_name_card_choice_effect(player2, player1.set_aside_cards[0].id), "声明 sweep 失败")
	assert_true(game_logic.do_strike(player2, assault_id, false, -1), "player2 发起攻击失败")

	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseSimultaneousEffect)
	assert_eq(game_logic.decision_info.choice.size(), 3, "应有 3 个选项：手牌 sweep + EX sweep + 幻梦境 sweep")
	assert_true(game_logic.decision_info.choice[2].get("from_set_aside", false),
		"第三个选项应是从幻梦境设置")

# ===== Shadow Chorus 复制到「转化卡」时不能转化 =====
# 影分身只是临时套用了幻梦境那张牌的定义，本身不是转化卡。
# 若允许转化，没转化的 Shadow Chorus 会被放进转化区。

func test_shadow_copy_of_transform_card_cannot_transform():
	position_players(player1, 4, player2, 5)  # dist1
	put_in_dreamlands(player1, "galdred_witheringtoxin")  # 转化卡 sp3 pw3 rng1-2
	var shadow_id = give_player_specific_card(player1, "umina_shadow_chorus")
	# 不提供任何选择：修复后不应再弹「是否转化 X」的决策
	execute_strike(player1, player2, shadow_id, "standard_normal_focus",
		false, false,
		[], [])
	assert_null(find_card_by_instance_id(player1, shadow_id, [player1.transforms]),
		"影分身不能被转化（否则没转化的 Shadow Chorus 会进入转化区）")
	var shadow_card = find_card_by_instance_id(player1, shadow_id, [player1.gauge, player1.discards])
	assert_not_null(shadow_card, "影分身应正常进入怒气/弃牌堆")
	assert_eq(shadow_card.definition.get("id"), "umina_shadow_chorus",
		"影分身离场时应已还原为 Shadow Chorus 本身")

func test_real_transform_card_can_still_transform():
	# 反向对照：真正的转化卡自己攻击时，转化选项必须仍然可用
	position_players(player1, 4, player2, 5)  # dist1
	var toxin_id = give_player_specific_card(player1, "galdred_witheringtoxin")
	execute_strike(player1, player2, toxin_id, "standard_normal_focus",
		false, false,
		[0], [])  # index0 = 转化
	assert_not_null(find_card_by_instance_id(player1, toxin_id, [player1.transforms]),
		"真正的转化卡应仍可选择转化并进入转化区")


# ===== Slipping Away（Out of Mind 的转化）触发时机 =====
#
# 规则：「当你将一张牌置入幻梦境时，你可以花费 1 能量移动 1 格。」
# 实现走 add_queued_effect，本意是「当前动作结算完后」触发（避免嵌套决策）。
# 但 Unknown Khadath（3 怒大招）吞掉对手攻击后战斗直接跳 Cleanup → start_end_turn，
# 这条出口原本不调 do_queued_effects → Move 1 残留到下一次才结算（触发时机错乱）。
# 修复：start_end_turn() 进入回合结束效果之前先结算一次队列。

func test_slipping_away_triggers_when_khadath_ends_strike():
	position_players(player1, 5, player2, 2)  # dist3
	add_transform(player1, "umina_out_of_mind")
	var p1_gauge = give_gauge(player1, 3)
	var pay_card = give_player_specific_card(player1, "standard_normal_block")

	var pos_before = player1.arena_location
	# choices: Khadath 的 3 怒 → Slipping Away 的 1 能量（弃牌）→ 前进(0)/后退(1)
	execute_strike(player1, player2, "umina_unknown_khadath", "standard_normal_assault",
		false, false, [p1_gauge, [pay_card], 0], [])

	assert_true(has_def_in_zone(player1, "standard_normal_assault", player1.set_aside_cards),
		"Khadath 应把对手的攻击吞进幻梦境（触发 Slipping Away 的前提）")
	assert_eq(player1.arena_location, pos_before - 1,
		"Slipping Away 应在回合结束前触发并前进 1 格（不能残留到下一回合）")
	assert_eq(game_logic.queued_effect_chain["effect"], null,
		"排队效果必须结算干净，不能残留")


func test_slipping_away_not_triggered_without_transform():
	# 反向对照：没有转化 Out of Mind 时，Khadath 吞掉攻击不应产生任何移动。
	position_players(player1, 5, player2, 2)  # dist3
	var p1_gauge = give_gauge(player1, 3)

	var pos_before = player1.arena_location
	execute_strike(player1, player2, "umina_unknown_khadath", "standard_normal_assault",
		false, false, [p1_gauge], [])

	assert_true(has_def_in_zone(player1, "standard_normal_assault", player1.set_aside_cards),
		"Khadath 仍应吞掉对手攻击")
	assert_eq(player1.arena_location, pos_before,
		"未转化 Slipping Away 时不应移动")


func test_slipping_away_triggers_at_begin_turn_put():
	# 觉醒后回合开始把牌库顶放入幻梦境 → Slipping Away 应在转入行动阶段之前结算。
	# （continue_begin_turn 出口原本不结算队列，Move 1 会被推迟到下一次 do_queued_effects。）
	player1.exceeded = true
	position_players(player1, 5, player2, 2)
	add_transform(player1, "umina_out_of_mind")
	var top_id = set_player_topdeck(player1, "standard_normal_spike")

	game_logic.handle_strike_effect(-1, {
		"effect_type": "umina_begin_turn_dreamlands_put",
		"card_id": top_id
	}, player1)
	assert_true(game_logic.queued_effect_chain["effect"] != null,
		"置入幻梦境后应把 Slipping Away 的 Move 1 排队")

	game_logic.continue_begin_turn()
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision,
		"回合开始转入行动阶段之前应停下来结算排队的 Slipping Away")
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ForceForEffect,
		"应为「付 1 能量换移动」的决策")
	assert_eq(game_logic.decision_info.player, player1.my_id,
		"应由 Umina 自己决定")


func test_queued_effect_runs_for_its_owner_not_the_caller():
	# 排队的移动效果必须按队列项记录的归属玩家执行。
	# 场景来源：Umina 在对手回合置入幻梦境（Khadath / Dark Thoughts 应战），
	# 若按「当前操作者」结算就会错误地让对手移动。
	position_players(player1, 5, player2, 2)
	game_logic.add_queued_effect({
		"effect_type": "umina_slipping_away_move",
		"override_description": "Move 1"
	}, null, player1.my_id)

	# 故意用 player2 当「当前操作者」来结算队列
	game_logic.do_queued_effects(player2)

	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision,
		"应停下来等选择前进/后退")
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.player, player1.my_id,
		"决策必须归 Umina，不能落到调用方 player2 身上")
	assert_eq(game_logic.queued_effect_chain["effect"], null,
		"队列项应已取出")
