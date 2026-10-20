extends ExceedGutTest

# 回归测试：Eugenia 的被动只在「对手弃掉**手牌**」时触发
#
# 线上场景（Sydney & Serena 的 Aluraune's Kiss 击中 → 让对手从**怒气区**弃一张牌）：
#   1) 从怒气区弃牌也触发了 Eugenia 的觉醒被动（把对手怒气区的牌收进了自己的 Wonderland）
#   2) 因为当时正处在 ChooseFromDiscard 决策中，走了 mid-decision fallback → 没给玩家选项
#
# 根因：player.discard() 是通用的「进弃牌堆」入口（会依次从 hand / gauge / 场上 / 牌库找牌），
#      末尾**无条件**回调 _on_player_discard，于是任何来源的弃牌都被当成「弃手牌」。
# 修复：player.discard() 只把「从 hand 分支弃掉的牌」报给 _on_player_discard。

func who_am_i():
	return "eugenia"


func test_passive_not_triggered_by_discard_from_gauge():
	position_players(player1, 4, player2, 5)
	player1.exceed()
	var gauge_ids = give_gauge(player2, 1)

	game_logic._last_effect_source_player_id = player1.my_id
	player2.discard([gauge_ids[0]])
	game_logic._last_effect_source_player_id = player1.my_id

	assert_true(game_logic.game_state != Enums.GameState.GameState_PlayerDecision,
		"对手从怒气区弃牌不该触发 Eugenia 被动（实际 state=%s）" % Enums.GameState.keys()[game_logic.game_state])
	assert_eq(player1.set_aside_cards.size(), 1,
		"Wonderland 里应仍只有那张占位标记卡")
	assert_eq(player1.set_aside_cards[0].definition.get("id"), "wonderland",
		"不该把对手怒气区的牌收进 Wonderland")


func test_passive_not_triggered_by_discard_from_deck():
	# 另一类非手牌来源：牌库里的牌被弃
	position_players(player1, 4, player2, 5)
	player1.exceed()
	var deck_id = player2.deck[0].id

	game_logic._last_effect_source_player_id = player1.my_id
	player2.discard([deck_id])
	game_logic._last_effect_source_player_id = player1.my_id

	assert_true(game_logic.game_state != Enums.GameState.GameState_PlayerDecision,
		"从牌库弃牌不该触发 Eugenia 被动")


func test_passive_still_triggered_by_discard_from_hand():
	position_players(player1, 4, player2, 5)
	player1.exceed()
	player2.hand = []
	give_player_specific_card(player2, "standard_normal_assault")
	var hand_id = player2.hand[0].id

	# 直接调 discard 绕过了行动流程，补上「有事情正在结算」的标记，免收尾断言报错
	game_logic.active_character_action = true
	game_logic._last_effect_source_player_id = player1.my_id
	player2.discard([hand_id])
	game_logic._last_effect_source_player_id = player1.my_id

	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision,
		"对手弃手牌应照常触发觉醒被动")
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice,
		"应弹出「收进 Wonderland」的选择（而不是静默自动选）")
	assert_true(game_logic.do_choice(player1, 1), "应能选第一张牌")

	assert_eq(player1.set_aside_cards.size(), 1, "Wonderland 应只留收进来的那张牌")
	assert_eq(player1.set_aside_cards[0].id, hand_id, "应收进刚弃掉的那张手牌")
