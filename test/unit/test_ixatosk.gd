extends ExceedGutTest

func who_am_i():
	return "ixatosk"

func test_skytear_predator_opponent_gauge_choice_instruction():
	var skytear_predator_id = give_player_specific_card(player1, "ixatosk_skytearpredator")
	give_gauge(player2, 1)
	game_logic.get_latest_events()
	var hit_effect = game_logic.card_db.get_card(skytear_predator_id).definition.effects[1]

	game_logic.handle_strike_effect(skytear_predator_id, hit_effect, player1)

	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseDiscardOpponentGauge)
	assert_eq(game_logic.decision_info.player, player2.my_id)
	var events = game_logic.get_latest_events()
	assert_eq(events.size(), 1)
	assert_eq(events[0].event_type, Enums.EventType.EventType_Boost_DiscardOpponentGauge)
	assert_eq(events[0].event_player, player2.my_id)
	assert_eq(events[0].reason, "选择一张自己的怒气牌来弃置")