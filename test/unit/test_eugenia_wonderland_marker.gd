extends ExceedGutTest

# 回归测试：Eugenia 的 Wonderland 占位标记卡（由 AddToSetAsideImmediately 运行时创建）
#
# 线上两个问题：
#  1) 觉醒后「选择弃掉对手一张手牌」时，界面上出现一张 Wonderland 黑白卡 ——
#     标记卡创建时没带图集（image_atlas 为空），UI 取不到图，显示为空白/黑白占位。
#  2) 联机对战、觉醒状态下 Queen of Hearts 击中效果执行时崩溃 ——
#     标记卡 id 用了全局 randi()（host/client 拿到的 id 不同 → 不同步），
#     且 owner 被写成随机数 → add_to_discards 的「不属于我就交给对手」分支
#     两边都不匹配、互相转交，**无限递归**。

func who_am_i():
	return "eugenia"

func _marker_of(p):
	for c in p.set_aside_cards:
		if c.definition.get("id") == "wonderland":
			return c
	return null


func test_wonderland_marker_owner_is_the_player():
	position_players(player1, 4, player2, 5)
	player1.exceed()
	var marker = _marker_of(player1)
	assert_not_null(marker, "觉醒后 Wonderland 区应有标记卡")
	assert_eq(marker.owner_id, player1.my_id,
		"标记卡 owner 必须是拥有者 —— 随机 owner 会让弃置流程两边互相转交、无限递归")


func test_wonderland_marker_has_image_atlas():
	position_players(player1, 4, player2, 5)
	player1.exceed()
	var marker = _marker_of(player1)
	assert_not_null(marker, "觉醒后 Wonderland 区应有标记卡")
	assert_false(marker.image_atlas.is_empty(),
		"标记卡必须带图集，否则 UI 上是一张没有图的黑白卡")
	var url = str(marker.get_image_url_index_data().get("url", ""))
	assert_true(url.find("wonderland") != -1,
		"应取到卡组里 wonderland 的图（实际：%s）" % url)


func test_wonderland_marker_id_uses_seeded_rng():
	# 联机双方共享同一个 seed，运行时新建卡的 id 必须来自引擎的可种子化 RNG；
	# 用全局 randi() 会让两端算出的 id 不一致（不同步 → 之后按 id 找卡就崩）。
	position_players(player1, 4, player2, 5)
	var state_before = game_logic.random_number_generator.state
	player1.exceed()
	var state_after = game_logic.random_number_generator.state
	var marker = _marker_of(player1)
	assert_not_null(marker, "觉醒后 Wonderland 区应有标记卡")
	assert_true(state_before != state_after,
		"标记卡 id 应消耗引擎的 seeded RNG（用全局 randi() 会让联机两端 id 不一致）")
	assert_true(marker.id >= 1000000 and marker.id < 1100000,
		"运行时卡 id 应落在约定区间（实际 %d）" % marker.id)


func test_wonderland_marker_discard_lands_in_own_discard():
	# 修复前：owner 是随机数 → add_to_discards 里两个玩家都不匹配 → 互相转交 → 无限递归崩溃。
	position_players(player1, 4, player2, 5)
	player1.exceed()
	var marker = _marker_of(player1)
	assert_not_null(marker, "觉醒后 Wonderland 区应有标记卡")

	var p1_before = player1.discards.size()
	var p2_before = player2.discards.size()
	player1.set_aside_cards.erase(marker)
	player1.add_to_discards(marker)  # 修复前这里会无限递归

	assert_eq(player1.discards.size(), p1_before + 1, "标记卡应落到自己的弃牌堆")
	assert_eq(player2.discards.size(), p2_before, "不应被转交给对手")


func test_wonderland_take_does_not_pollute_opponent_discard():
	# 觉醒被动把弃牌收进 Wonderland 时，退役的占位卡不该塞进对手弃牌堆
	# （否则会混进对手牌库/手牌，在 UI 上表现为一张没有图的「黑白卡」）。
	position_players(player1, 4, player2, 5)
	player1.exceed()
	player2.hand = []
	give_player_specific_card(player2, "standard_normal_assault")

	# 直接调 discard_hand 绕过了行动流程，这里补上「有事情正在结算」的标记，
	# 免得收尾的 set_player_action_processing_state 断言报错。
	game_logic.active_character_action = true
	game_logic._last_effect_source_player_id = player1.my_id
	player2.discard_hand()
	game_logic._last_effect_source_player_id = player1.my_id

	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice,
		"对手弃牌后应弹出 Eugenia 觉醒被动选择")
	game_logic.do_choice(player1, 1)  # 0 = 跳过，1 = 第一张牌

	var leak = false
	for c in player2.discards:
		if c.definition.get("id") == "wonderland":
			leak = true
	assert_false(leak, "对手弃牌堆不应混入 wonderland 占位卡")
	assert_eq(player1.set_aside_cards.size(), 1, "Wonderland 应只留收进来的那张牌")
	assert_eq(player1.set_aside_cards[0].definition.get("id"), "standard_normal_assault",
		"Wonderland 里应是刚收进来的那张牌")
