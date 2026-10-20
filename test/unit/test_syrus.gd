extends ExceedGutTest

func who_am_i():
	return "syrus"

func before_each():
	default_game_setup("ryu")
	gut.p("ran setup", 2)

func test_starting_life():
	assert_eq(player1.life, 30)
	assert_eq(player2.life, 30)

func test_exceed_cost_default():
	assert_eq(player1.get_exceed_cost(), 6)

func test_exceed_cost_with_one_transform():
	add_transform(player1, "syrus_tidal_whirl")
	assert_eq(player1.get_exceed_cost(), 4)

func test_exceed_cost_with_two_transforms():
	add_transform(player1, "syrus_tidal_whirl")
	add_transform(player1, "syrus_aria_of_the_winds")
	assert_eq(player1.get_exceed_cost(), 2)

func test_tidal_whirl_card_loaded():
	var card = CardDataManager.get_card("syrus_tidal_whirl")
	assert_not_null(card)
	if card:
		assert_eq(card['display_name'], "Tidal Whirl")
		assert_eq(card['power'], 3)
		assert_eq(card['speed'], 6)

func test_symphony_of_the_deep_card_loaded():
	var card = CardDataManager.get_card("syrus_symphony_of_the_deep")
	assert_not_null(card)
	if card:
		assert_eq(card['display_name'], "Symphony of the Deep")
		assert_eq(card['gauge_cost'], 2)

func test_dredge_fury_card_loaded():
	var card = CardDataManager.get_card("syrus_dredge_fury")
	assert_not_null(card)
	if card:
		assert_eq(card['display_name'], "Dredge Fury")
		assert_eq(card['gauge_cost'], 1)

func test_treasure_hunter_hit_discards_opponent_gauge_without_returning_it():
	position_players(player1, 3, player2, 5)
	var discarded_gauge_id = give_gauge(player2, 1)[0]

	execute_strike(player1, player2, "syrus_treasure_hunter", "standard_normal_focus",
		false, false, [], [[discarded_gauge_id]])

	assert_false(player2.is_card_in_gauge(discarded_gauge_id))
	assert_true(player2.is_card_in_discards(discarded_gauge_id))

func test_exceed_moves_continuous_boosts_to_gauge():
	var test_card = player1.deck[0]
	var test_card_id = test_card.id
	player1.add_to_continuous_boosts(test_card)
	player1.deck.remove_at(0)
	assert_eq(player1.continuous_boosts.size(), 1)

	var gauge_ids = give_gauge(player1, 6)
	assert_true(game_logic.do_exceed(player1, gauge_ids), "Syrus should be able to exceed with 6 gauge")
	assert_eq(player1.continuous_boosts.size(), 0, "Continuous boosts should be moved to gauge after exceed")

	var found_in_gauge = false
	for gc in player1.gauge:
		if gc.id == test_card_id:
			found_in_gauge = true
			break
	assert_true(found_in_gauge, "The continuous boost card should be in gauge after exceed")

func test_instant_boost_replays_as_facedown_continuous_boost():
	position_players(player1, 3, player2, 6)
	var boost_id = give_player_specific_card(player1, "syrus_tidal_whirl")

	assert_true(game_logic.do_boost(player1, boost_id, []))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player1, 0))

	var boost_card = game_logic.get_card_database().get_card(boost_id)
	assert_true(player1.is_card_in_continuous_boosts(boost_id))
	assert_false(player1.is_card_in_discards(boost_id))
	assert_true(boost_card.definition.has("replaced_boost"))
	assert_eq(boost_card.definition["replaced_boost"]["boost_type"], "immediate")
	assert_eq(boost_card.definition["boost"]["boost_type"], "continuous")
	assert_true(boost_card.definition["boost"].get("facedown", false))
	assert_eq(boost_card.definition["boost"]["effects"][0]["effect_type"], "add_to_gauge_immediately")
	validate_positions(player1, 4, player2, 6)

func test_exceeded_instant_boost_replacement_moves_and_adds_power():
	position_players(player1, 3, player2, 6)
	player1.exceed()
	var boost_id = give_player_specific_card(player1, "syrus_tidal_whirl")

	assert_true(game_logic.do_boost(player1, boost_id, []))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player1, 0))

	var boost_card = game_logic.get_card_database().get_card(boost_id)
	assert_true(player1.is_card_in_continuous_boosts(boost_id))
	assert_eq(boost_card.definition["boost"]["effects"][0]["effect_type"], "choice")
	assert_eq(boost_card.definition["boost"]["effects"][1]["effect_type"], "powerup")
	validate_positions(player1, 5, player2, 6)

	advance_turn(player2)
	execute_strike(player1, player2, "standard_normal_grasp", "standard_normal_cross",
		false, false, [0], [])
	validate_life(player1, 30, player2, 26)

func test_dredge_fury_spent_gauge_choice_returns_one_card_to_hand():
	position_players(player1, 3, player2, 7)
	var gauge_ids = give_gauge(player1, 4)
	var cost_id = gauge_ids[0]
	var spent_ids = [gauge_ids[1], gauge_ids[2], gauge_ids[3]]
	var kept_id = spent_ids[1]
	var kept_def_id = game_logic.get_card_database().get_card(kept_id).definition["id"]

	execute_strike(player1, player2, "syrus_dredge_fury", "standard_normal_focus",
		false, false, [[cost_id], spent_ids, 1], [])

	assert_true(player1.is_card_in_hand(kept_id))
	assert_true(kept_def_id in player1.get_public_hand_info()["known"])
	assert_false(player1.is_card_in_discards(kept_id))
	assert_true(player1.is_card_in_discards(spent_ids[0]))
	assert_true(player1.is_card_in_discards(spent_ids[2]))
	validate_life(player1, 30, player2, 24)

func test_dredge_fury_zero_gauge_confirms_without_keep_choice():
	# gauge_for_effect supports min_gauge=0, so choosing 0 should confirm
	# and skip both keep-choice and per-gauge powerup.
	position_players(player1, 3, player2, 7)
	var gauge_ids = give_gauge(player1, 4)
	var cost_id = gauge_ids[0]

	execute_strike(player1, player2, "syrus_dredge_fury", "standard_normal_focus",
		false, false, [[cost_id], []], [])

	assert_false(player1.is_card_in_hand(cost_id))
	assert_true(player1.is_card_in_discards(cost_id))
	# Focus has armor 2, so Dredge Fury base power 2 deals 0 with no spent gauge.
	validate_life(player1, 30, player2, 30)

func test_silver_shadow_uses_move_to_space_with_range_3_limit():
	position_players(player1, 3, player2, 5)
	var boost_id = give_player_specific_card(player1, "syrus_symphony_of_the_deep")

	assert_true(game_logic.do_boost(player1, boost_id, []))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect)
	assert_eq(game_logic.decision_info.effect_type, StrikeEffects.MoveToSpace)
	assert_eq(game_logic.decision_info.limitation, [2, 8])
	assert_true(game_logic.do_choice(player1, get_choice_index_for_position(8)))
	validate_positions(player1, 8, player2, 5)

func test_talon_only_boosts_immediate_from_gauge_and_seals_before_syrus_replay():
	position_players(player1, 3, player2, 6)
	add_transform(player1, "syrus_albatross_talon")

	var continuous_boost_id = give_player_specific_card(player1, "standard_normal_grasp")
	player1.move_card_from_hand_to_gauge(continuous_boost_id)
	assert_false(player1.can_boost_something(["gauge"], ""))

	var immediate_boost_id = give_player_specific_card(player1, "syrus_tidal_whirl")
	player1.move_card_from_hand_to_gauge(immediate_boost_id)
	assert_true(player1.can_boost_something(["gauge"], ""))
	assert_true(game_logic.do_boost(player1, immediate_boost_id, []))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player1, 0))

	var boosted_card = game_logic.get_card_database().get_card(immediate_boost_id)
	assert_true(player1.is_card_in_sealed(immediate_boost_id))
	assert_false(player1.is_card_in_continuous_boosts(immediate_boost_id))
	assert_false(player1.is_card_in_discards(immediate_boost_id))
	assert_false(boosted_card.definition.has("replaced_boost"))

func test_talon_gauge_boost_shows_seal_choice_when_exceeded():
	# Exceeded Syrus playing an instant boost from gauge (Memories from the
	# Deep) should be offered the seal choice instead of sealing outright.
	position_players(player1, 3, player2, 6)
	player1.exceed()
	add_transform(player1, "syrus_albatross_talon")
	var immediate_boost_id = give_player_specific_card(player1, "syrus_tidal_whirl")
	player1.move_card_from_hand_to_gauge(immediate_boost_id)

	assert_true(game_logic.do_boost(player1, immediate_boost_id, []))
	# First choice is Tidal Whirl's own immediate effect (advance/retreat + draw).
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player1, 0))
	# Then the seal choice should appear with both options.
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.choice.size(), 2,
			"Exceeded Syrus should be offered seal-direct and exceed-face-then-seal")

func test_talon_gauge_boost_seal_direct_when_exceeded():
	# Choosing "seal directly" keeps the old behavior: card goes straight to
	# sealed, no Syrus passive replay, no exceed-face now effect.
	position_players(player1, 3, player2, 6)
	player1.exceed()
	add_transform(player1, "syrus_albatross_talon")
	var immediate_boost_id = give_player_specific_card(player1, "syrus_tidal_whirl")
	player1.move_card_from_hand_to_gauge(immediate_boost_id)

	assert_true(game_logic.do_boost(player1, immediate_boost_id, []))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player1, 0))  # Tidal Whirl: advance + draw
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player1, 0))  # seal choice: seal directly

	var boosted_card = game_logic.get_card_database().get_card(immediate_boost_id)
	assert_true(player1.is_card_in_sealed(immediate_boost_id))
	assert_false(player1.is_card_in_continuous_boosts(immediate_boost_id))
	assert_false(boosted_card.definition.has("replaced_boost"))

func test_talon_gauge_boost_exceed_face_then_seal_when_exceeded():
	# Choosing "resolve exceed face effect first" replays the boost as the
	# exceeded replacement (facedown continuous boost), lets the now "Move up
	# to 1" choice resolve, then seals it.
	position_players(player1, 3, player2, 6)
	player1.exceed()
	add_transform(player1, "syrus_albatross_talon")
	var immediate_boost_id = give_player_specific_card(player1, "syrus_tidal_whirl")
	player1.move_card_from_hand_to_gauge(immediate_boost_id)

	assert_true(game_logic.do_boost(player1, immediate_boost_id, []))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player1, 0))  # Tidal Whirl: advance + draw
	# Seal choice: choose "先执行觉醒面效果（移动至多1格）再封印" (index 1).
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_logic.do_choice(player1, 1))
	# The exceed-face now effect is a Move up to 1 choice (advance/retreat/pass).
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice,
			"The exceed-face now effect should prompt the Move up to 1 choice")
	# advance 1 (index 0)
	assert_true(game_logic.do_choice(player1, 0))
	# Tidal Whirl advanced 1 (3 -> 4), then the exceed-face now effect
	# advanced 1 more (4 -> 5).
	validate_positions(player1, 5, player2, 6)

	# After the now effect resolved, the boost should be sealed. Note that
	# sealing removes it from continuous boosts, which restores the original
	# boost definition (replaced_boost is erased by disable_boost_effects).
	assert_true(player1.is_card_in_sealed(immediate_boost_id))
	assert_false(player1.is_card_in_continuous_boosts(immediate_boost_id))
	assert_false(player1.is_card_in_discards(immediate_boost_id))
	var boosted_card = game_logic.get_card_database().get_card(immediate_boost_id)
	assert_false(boosted_card.definition.has("replaced_boost"),
			"Sealing restores the original boost definition")

# ===== Symphony of the Deep（2G 击中）：随机取牌必须用共享种子的 RNG（2026-10-05）=====
# 之前用 Array.shuffle()（全局随机），联机两端牌序不同 → 双方状态分叉。

func _syrus_state_after_symphony(seed_value : int) -> Array:
	var deck = CardDataManager.get_deck_from_str_id("syrus")
	var loader = CardImageLoader.new(true)
	var g = LocalGame.new(loader)
	g.initialize_game(deck, deck, "p1", "p2", Enums.PlayerId.PlayerId_Player, seed_value)
	g.draw_starting_hands_and_begin()
	g.do_mulligan(g.player, [])
	g.do_mulligan(g.opponent, [])
	# 两边完全相同地准备弃牌堆（5 张普通技）+ 手牌 2 张
	var p = g.player
	var ids = [11001, 11002, 11003, 11004, 11005]
	p.discards = []
	var db = g.get_card_database()
	for i in range(5):
		var card_def = CardDataManager.get_card("standard_normal_spike")
		var card = GameCard.new(ids[i], card_def, p.my_id)
		db._test_insert_card(card)
		p.discards.append(card)
	p.hand = p.hand.slice(0, 2)
	g.handle_strike_effect(-1, {"effect_type": "syrus_return_to_hand_until_7"}, p)
	var returned = []
	for card in p.hand:
		returned.append(card.id)
	returned.sort()
	loader.free()
	return returned


func test_symphony_returns_cards_up_to_seven():
	position_players(player1, 4, player2, 6)
	var ids = []
	for i in range(5):
		ids.append(give_player_specific_card(player1, "standard_normal_spike"))
	var db = game_logic.get_card_database()
	for cid in ids:
		var card = db.get_card(cid)
		player1.hand.erase(card)
		player1.add_to_discards(card)
	player1.hand = player1.hand.slice(0, 2)

	game_logic.handle_strike_effect(-1, {"effect_type": "syrus_return_to_hand_until_7"}, player1)
	assert_eq(player1.hand.size(), 7, "应把弃牌堆的牌返回手牌直到 7 张")
	assert_eq(player1.discards.size(), 0, "5 张应全部被取回")


func test_symphony_picks_are_identical_for_the_same_seed():
	# 联机不同步的回归：同一 seed 的两局必须取到完全相同的牌
	var a = _syrus_state_after_symphony(24680)
	var b = _syrus_state_after_symphony(24680)
	assert_eq(a, b, "同一 seed 下取牌结果必须一致（否则联机双方会分叉）")
