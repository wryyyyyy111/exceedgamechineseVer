extends ExceedGutTest

var ais: Array = []

func who_am_i():
	var deck = CardDataManager.get_deck_from_str_id("heiqiyihu").duplicate(true)
	deck["starting_life"] = 100
	deck["life_cap"] = 100
	return deck

func before_each():
	default_game_setup()
	for owner in [player1, player2]:
		ais.append(AIPlayer.new(game_logic, owner))

func after_each():
	for ai in ais:
		ai.ai_policy.free()
	ais.clear()
	game_logic.teardown()
	game_logic.free()

func _guardian(owner: Player, definition_id: String) -> int:
	var id = give_player_specific_card(owner, definition_id)
	owner.remove_card_from_hand(id, true, false)
	owner.add_to_bleach(game_logic.card_db.get_card(id))
	return id

func _choice(ai: AIPlayer, index: int = -1):
	var actions = ai.determine_effect_choice_actions()
	assert_eq(actions.size(), game_logic.decision_info.choice.size())
	var picked = ai.pick_effect_choice() if index == -1 else actions[index]
	assert_gte(picked.choice, 0)
	assert_lt(picked.choice, actions.size())
	assert_eq(game_logic.decision_info.player, ai.game_player.my_id)
	assert_true(game_logic.do_choice(ai.game_player, picked.choice))

func test_ai_mirror_declaration_guardians_then_fresh_wild_swing():
	for owner in [player1, player2]:
		_guardian(owner, "gg_normal_grasp")
	set_player_topdeck(player1, "gg_normal_dust")
	set_player_topdeck(player1, "gg_normal_cross")
	var original_hand = player1.hand.size()
	var declaration = ais[0].pick_strike()
	assert_eq(declaration.card_id, -1)
	assert_false(declaration.wild_swing)
	assert_true(game_logic.do_strike(player1, declaration.card_id, declaration.wild_swing, declaration.ex_card_id))
	assert_null(game_logic.active_strike.initiator_card)
	_choice(ais[0], 0)
	assert_eq(player1.hand.size(), original_hand + 1)
	assert_null(game_logic.active_strike.initiator_card)
	_choice(ais[1], 0)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)
	var actions = ais[0].get_strike_actions()
	var wild = actions.filter(func(action): return action.wild_swing)[0]
	var top = player1.deck[0].id
	assert_true(game_logic.do_strike(player1, wild.card_id, wild.wild_swing, wild.ex_card_id))
	assert_eq(game_logic.active_strike.initiator_card.id, top)
	var response = give_player_specific_card(player2, "gg_normal_focus")
	assert_true(game_logic.do_strike(player2, response, false, -1))
	# A wild ultra may require a legal cost; finish via the actual AI choice.
	if game_logic.active_strike and game_logic.decision_info.type == Enums.DecisionType.DecisionType_PayStrikeCost_CanWild:
		var payment = ais[0].pay_strike_gauge_cost(game_logic.decision_info.cost, true, 0)
		assert_true(game_logic.do_pay_strike_cost(player1, payment.card_ids, payment.wild_swing, payment.use_free_force))

func test_ai_guardian_pass_is_legal_and_no_preselected_card():
	_guardian(player1, "heiqiyihu_地裂崩击")
	var action = ais[0].pick_strike()
	assert_true(game_logic.do_strike(player1, action.card_id, action.wild_swing, action.ex_card_id))
	_choice(ais[0], game_logic.decision_info.choice.size() - 1)
	assert_eq(player1.bleach_zone.size(), 1)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_WaitForStrike)
	assert_null(game_logic.active_strike.initiator_card)

func test_ai_only_guardian_two_force_move_accepted_front_forbidden():
	player1.hand.clear()
	var money = _guardian(player1, "heiqiyihu_虚化")
	assert_eq(ais[0]._guardian_payment_ids(), [])
	assert_true(ais[0].get_move_actions().is_empty())
	player1.exceeded = true
	var moves = ais[0].get_move_actions().filter(func(action): return action.force_card_ids == [money] and action.location == 5)
	assert_eq(moves.size(), 1)
	if not moves.is_empty():
		assert_true(game_logic.do_move(player1, moves[0].force_card_ids, moves[0].location, false))
		assert_true(player1.is_card_in_discards(money))
		assert_eq(player1.arena_location, 5)

func test_ai_mixed_gauge_guardian_ultra_payment_accepted():
	player1.exceeded = true
	var guardian = _guardian(player1, "heiqiyihu_虚化")
	var gauge = give_gauge(player1, 1)[0]
	position_players(player1, 3, player2, 4)
	var attack = give_player_specific_card(player1, "heiqiyihu_呼唤我的名字吧！")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_eq(ais[0].get_available_gauge_payment_value(), 2)
	var options = ais[0].determine_pay_strike_gauge_cost_actions(2, false)
	assert_eq(options.size(), 1)
	if not options.is_empty():
		var payment = ais[0].pay_strike_gauge_cost(2, false, 0)
		assert_true(guardian in payment.card_ids)
		assert_true(gauge in payment.card_ids)
		assert_true(game_logic.do_pay_strike_cost(player1, payment.card_ids, false))
		assert_true(player1.is_card_in_discards(guardian))
		assert_true(player1.is_card_in_discards(gauge))
		assert_null(game_logic.active_strike)

func test_ai_only_guardian_can_pay_normal_boost_and_cancel():
	player1.exceeded = true
	player1.hand.clear()
	var money = _guardian(player1, "heiqiyihu_虚化")
	var boost = give_player_specific_card(player1, "heiqiyihu_虚化")
	var options = ais[0].get_boost_actions(["hand"], "", false, 1)
	assert_eq(options.size(), 1)
	if not options.is_empty():
		assert_eq(options[0].payment_card_ids, [money])
		assert_true(game_logic.do_boost(player1, boost, options[0].payment_card_ids))
		_choice(ais[0], 0)
		assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostCancel)
		var cancel = ais[0].pick_cancel(1)
		assert_not_null(cancel)
		assert_true(game_logic.do_boost_cancel(player1, cancel.card_ids, cancel.cancel))

func test_ai_xuhua_force_choices_never_overpay_then_recover():
	position_players(player1, 3, player2, 4)
	var cost = give_gauge(player1, 2)
	var attack = give_player_specific_card(player1, "heiqiyihu_虚化")
	var response = give_player_specific_card(player2, "gg_normal_focus")
	assert_true(game_logic.do_strike(player1, attack, false, -1))
	assert_true(game_logic.do_strike(player2, response, false, -1))
	assert_true(game_logic.do_pay_strike_cost(player1, cost, false))
	player1.hand.clear()
	var ultra = give_player_specific_card(player1, "heiqiyihu_虚化")
	give_player_specific_card(player1, "gg_normal_grasp")
	var options = ais[0].determine_force_for_effect_actions([0, 1, 2])
	assert_gt(options.size(), 0)
	assert_true(options.any(func(action): return action.card_ids == [ultra]))
	for option in options:
		assert_lte(player1.get_force_with_cards(option.card_ids, "FORCE_FOR_EFFECT", false, option.use_free_force), 2)
	var payment = options.filter(func(action): return action.card_ids == [ultra])[0]
	assert_true(game_logic.do_force_for_effect(player1, payment.card_ids, false))
	_choice(ais[0])
	assert_true(player1.is_card_in_bleach(ultra))
	assert_null(game_logic.active_strike)

func test_ai_threshold_sources_are_exact_legal_choices():
	# Real prepare triggers the pending life-threshold check before the next action.
	player1.life = 24
	assert_true(game_logic.do_prepare(player1))
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	var choices = game_logic.decision_info.choice
	assert_eq(choices[0]["source"], "deck")
	assert_eq(choices.size(), player1.hand.size() + 1)
	_choice(ais[0])
	assert_eq(player1.bleach_zone.size(), 1)
	assert_ne(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)

func test_ai_awakened_force_and_gauge_effect_combinations_and_front_filter():
	var guardian = _guardian(player1, "heiqiyihu_虚化")
	player1.hand.clear()
	player1.gauge.clear()
	var money = give_gauge(player1, 1)[0]
	for exceeded in [false, true]:
		player1.exceeded = exceeded
		game_logic.decision_info.effect = {"force_max": 3, "gauge_max": 2}
		var forces = ais[0].determine_force_for_effect_actions([0, 1, 2, 3])
		var gauges = ais[0].determine_gauge_for_effect_actions([0, 1, 2], "")
		assert_eq(forces.any(func(action): return guardian in action.card_ids), exceeded)
		assert_eq(gauges.any(func(action): return guardian in action.card_ids), exceeded)
		if exceeded:
			assert_true(forces.any(func(action): return guardian in action.card_ids and money in action.card_ids))
			assert_true(gauges.any(func(action): return guardian in action.card_ids and money in action.card_ids))
			assert_true(ais[0].get_change_cards_actions().any(func(action): return guardian in action.card_ids))
			var attack = give_player_specific_card(player1, "heiqiyihu_呼唤我的名字吧！")
			assert_true(ais[0].get_strike_actions().any(func(action): return action.card_id == attack))

# Full matches deliberately do not use who_am_i's 100-life interaction fixture.
# Both the deck shuffle and policy RNG are fixed; never retry a failing seed.
const FULL_MATCH_STEP_LIMIT = 2000
const FULL_MATCH_SECONDS = 60
var _full_match_completed = false

func _full_match_setup(opponent_id: String, match_seed: int):
	_full_match_completed = false
	after_each()
	seed(match_seed)
	image_loader = CardImageLoader.new(true)
	game_logic = LocalGame.new(image_loader)
	game_logic.initialize_game(
		CardDataManager.get_deck_from_str_id("heiqiyihu"),
		CardDataManager.get_deck_from_str_id(opponent_id),
		"p1", "p2", Enums.PlayerId.PlayerId_Player, match_seed)
	game_logic.draw_starting_hands_and_begin()
	player1 = game_logic.player
	player2 = game_logic.opponent
	assert_eq(player1.deck_def.id, "heiqiyihu")
	assert_eq(player2.deck_def.id, opponent_id)
	for owner in [player1, player2]:
		ais.append(AIPlayer.new(game_logic, owner))
		assert_eq(owner.life, 30, "Full matches must start at printed life")

func _full_match_zones(context: String) -> bool:
	var seen = {}
	var valid = true
	for owner in [player1, player2]:
		for zone in ["hand", "deck", "discards", "gauge", "bleach_zone",
				"continuous_boosts", "sealed", "transforms", "overdrive", "set_aside_cards"]:
			for card in owner.get(zone):
				if seen.has(card.id) or card.owner_id != owner.my_id:
					fail_test("%s: duplicate/wrong-owner card %s in %s; prior=%s" %
						[context, card.id, zone, seen.get(card.id, "")])
					valid = false
				seen[card.id] = zone
	assert_true(valid, context + ": physical zones unique and owned")
	return valid

func _full_match_payment(owner: Player, ids: Array, context: String) -> bool:
	var seen = {}
	for id in ids:
		if seen.has(id) or not (owner.is_card_in_hand(id) or owner.is_card_in_gauge(id)
				or (owner.exceeded and owner.is_card_in_bleach(id))):
			fail_test("%s: illegal payment source %s" % [context, id])
			return false
		seen[id] = true
	return true

func _full_match_strike(ai: AIPlayer, response: bool = false) -> bool:
	var action
	if response:
		action = ai.pick_strike_response()
	elif ai.game_player.next_strike_from_gauge:
		action = ai.pick_strike("gauge")
	elif ai.game_player.next_strike_from_sealed:
		action = ai.pick_strike("sealed")
	elif str(game_logic.decision_info.limitation) == "EX":
		action = ai.pick_strike("", true, false, true)
	else:
		action = ai.pick_strike()
	return game_logic.do_strike(ai.game_player, action.card_id, action.wild_swing, action.ex_card_id)

func _full_match_turn(ai: AIPlayer) -> bool:
	var owner = ai.game_player
	var action = ai.take_turn()
	if action is AIPlayer.PrepareAction:
		return game_logic.do_prepare(owner)
	if action is AIPlayer.MoveAction:
		return _full_match_payment(owner, action.force_card_ids, "move") and game_logic.do_move(
			owner, action.force_card_ids, action.location, action.use_free_force)
	if action is AIPlayer.ChangeCardsAction:
		return _full_match_payment(owner, action.card_ids, "change") and game_logic.do_change(
			owner, action.card_ids, false, action.use_free_force)
	if action is AIPlayer.ExceedAction:
		return _full_match_payment(owner, action.card_ids, "exceed") and game_logic.do_exceed(owner, action.card_ids)
	if action is AIPlayer.ReshuffleAction:
		return game_logic.do_reshuffle(owner)
	if action is AIPlayer.BoostAction:
		return _full_match_payment(owner, action.payment_card_ids, "boost") and game_logic.do_boost(
			owner, action.card_id, action.payment_card_ids, action.use_free_force)
	if action is AIPlayer.StrikeAction:
		return game_logic.do_strike(owner, action.card_id, action.wild_swing, action.ex_card_id)
	if action is AIPlayer.CharacterActionAction:
		return _full_match_payment(owner, action.card_ids, "character") and game_logic.do_character_action(
			owner, action.card_ids, action.action_idx, action.use_free_force)
	fail_test("Unsupported real AI turn action: %s" % action)
	return false

func _full_match_decision(ai: AIPlayer) -> bool:
	var owner = ai.game_player
	var info = game_logic.decision_info
	assert_eq(info.player, owner.my_id, "Decision must be submitted by its actual player")
	match info.type:
		Enums.DecisionType.DecisionType_EffectChoice, Enums.DecisionType.DecisionType_ChooseSimultaneousEffect:
			var action = ai.pick_effect_choice()
			assert_gte(action.choice, 0)
			assert_lt(action.choice, info.choice.size())
			return game_logic.do_choice(owner, action.choice)
		Enums.DecisionType.DecisionType_BoostCancel:
			var action = ai.pick_cancel(info.cost)
			return _full_match_payment(owner, action.card_ids, "cancel") and game_logic.do_boost_cancel(
				owner, action.card_ids, action.cancel)
		Enums.DecisionType.DecisionType_PayStrikeCost_Required, Enums.DecisionType.DecisionType_PayStrikeCost_CanWild:
			var can_wild = info.type == Enums.DecisionType.DecisionType_PayStrikeCost_CanWild
			var action = ai.pay_strike_gauge_cost(info.cost, can_wild, 0) if info.limitation == "gauge" \
				else ai.pay_strike_force_cost(info.cost, can_wild, 0)
			return _full_match_payment(owner, action.card_ids, "strike cost") and game_logic.do_pay_strike_cost(
				owner, action.card_ids, action.wild_swing, true, action.use_free_force)
		Enums.DecisionType.DecisionType_ForceForArmor:
			var action = ai.pick_force_for_armor(info.limitation == "gauge")
			return _full_match_payment(owner, action.card_ids, "armor") and game_logic.do_force_for_armor(
				owner, action.card_ids, action.use_free_force)
		Enums.DecisionType.DecisionType_ForceForEffect:
			var options = []
			if info.effect.get("per_force_effect") != null:
				for amount in range(info.effect.get("min_force", 0), info.effect.force_max + 1):
					options.append(amount)
			else:
				if not info.effect.get("required", false):
					options.append(0)
				options.append(info.effect.force_max)
			var action = ai.pick_force_for_effect(options)
			return _full_match_payment(owner, action.card_ids, "force effect") and game_logic.do_force_for_effect(
				owner, action.card_ids, false, false, action.use_free_force)
		Enums.DecisionType.DecisionType_GaugeForEffect:
			var options = []
			if info.effect.get("per_gauge_effect") != null:
				for amount in range(info.effect.get("min_gauge", 0), info.effect.gauge_max + 1):
					options.append(amount)
			else:
				if not info.effect.get("required", false):
					options.append(0)
				options.append(info.effect.gauge_max)
			var action = ai.pick_gauge_for_effect(options, info.effect.get("require_specific_card_id", ""),
				info.effect.get("valid_card_types", []))
			return _full_match_payment(owner, action.card_ids, "gauge effect") and game_logic.do_gauge_for_effect(owner, action.card_ids)
		Enums.DecisionType.DecisionType_CardFromHandToGauge:
			var action = ai.pick_card_hand_to_gauge(info.effect.min_amount, info.effect.max_amount,
				info.effect.get("restricted_to_card_ids", []))
			return game_logic.do_relocate_card_from_hand(owner, action.card_ids)
		Enums.DecisionType.DecisionType_ChooseFromBoosts:
			var action = ai.pick_choose_from_boosts(info.amount)
			return game_logic.do_choose_from_boosts(owner, action.card_ids)
		Enums.DecisionType.DecisionType_ChooseFromDiscard:
			var action = ai.pick_choose_from_discard(info.amount)
			return game_logic.do_choose_from_discard(owner, action.card_ids)
		Enums.DecisionType.DecisionType_ChooseToDiscard:
			var action
			if info.effect.effect_type == "choose_opponent_card_to_discard":
				action = ai.pick_choose_opponent_card_to_discard(info.choice)
			else:
				action = ai.pick_choose_to_discard(info.effect.amount, info.limitation,
					info.can_pass, info.effect.get("allow_fewer", false))
			return game_logic.do_choose_to_discard(owner, action.card_ids)
		Enums.DecisionType.DecisionType_BoostNow:
			var action = ai.take_boost(info.valid_zones, info.limitation, info.ignore_costs, info.amount)
			return _full_match_payment(owner, action.payment_card_ids, "boost now") and game_logic.do_boost(
				owner, action.card_id, action.payment_card_ids, action.use_free_force, 0, action.additional_boost_ids)
		Enums.DecisionType.DecisionType_NameCard_OpponentDiscards, Enums.DecisionType.DecisionType_ReadingNormal, Enums.DecisionType.DecisionType_Sidestep:
			var action = ai.pick_name_opponent_card(info.type != Enums.DecisionType.DecisionType_NameCard_OpponentDiscards)
			return game_logic.do_boost_name_card_choice_effect(owner, action.card_id)
		Enums.DecisionType.DecisionType_ChooseDiscardContinuousBoost:
			var action = ai.pick_discard_continuous(info.limitation, info.can_pass, info.extra_info)
			return game_logic.do_boost_name_card_choice_effect(owner, action.card_id)
		Enums.DecisionType.DecisionType_ChooseDiscardOpponentGauge:
			var action = ai.pick_discard_opponent_gauge()
			return game_logic.do_boost_name_card_choice_effect(owner, action.card_id)
		Enums.DecisionType.DecisionType_ChooseFromTopDeck:
			var action = ai.pick_choose_from_topdeck(info.action, info.amount, info.can_pass)
			return game_logic.do_choose_from_topdeck(owner, action.card_id, action.action)
		Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect:
			var action = ai.pick_choose_arena_location_for_effect(info.limitation)
			return game_logic.do_choice(owner, info.limitation.find(action.location))
		Enums.DecisionType.DecisionType_PickNumberFromRange:
			var action = ai.pick_number_from_range_for_effect(info.limitation, info.choice)
			return game_logic.do_choice(owner, info.limitation.find(action.number))
		_:
			fail_test("Unsupported decision (no fallback): %s" % Enums.DecisionType.keys()[info.type])
			return false

func _run_full_match(opponent_id: String, match_seed: int):
	_full_match_setup(opponent_id, match_seed)
	var events = game_logic.get_latest_events()
	var steps = 0
	var actions = 0
	var decisions = 0
	var start = Time.get_ticks_msec()
	while not game_logic.game_over and steps < FULL_MATCH_STEP_LIMIT:
		var context = "seed=%s opponent=%s step=%s state=%s decision=%s player=%s" % [
			match_seed, opponent_id, steps, Enums.GameState.keys()[game_logic.game_state],
			Enums.DecisionType.keys()[game_logic.decision_info.type], game_logic.decision_info.player]
		if Time.get_ticks_msec() - start >= FULL_MATCH_SECONDS * 1000:
			fail_test(context + ": wall-clock limit reached, NOT a successful match")
			return
		var owner_id = game_logic.get_priority_player()
		var ai = ais[0] if owner_id == player1.my_id else ais[1]
		var accepted = false
		match game_logic.game_state:
			Enums.GameState.GameState_Mulligan:
				ai = ais[0] if not player1.mulligan_complete else ais[1]
				var action = ai.pick_mulligan()
				accepted = game_logic.do_mulligan(ai.game_player, action.card_ids)
				decisions += 1
			Enums.GameState.GameState_PickAction:
				accepted = _full_match_turn(ai)
				actions += 1
			Enums.GameState.GameState_PlayerDecision:
				accepted = _full_match_decision(ai)
				decisions += 1
			Enums.GameState.GameState_DiscardDownToMax:
				var action = ai.pick_discard_to_max(ai.game_player.hand.size() - ai.game_player.max_hand_size)
				accepted = game_logic.do_discard_to_max(ai.game_player, action.card_ids)
				decisions += 1
			Enums.GameState.GameState_WaitForStrike:
				accepted = _full_match_strike(ai)
				decisions += 1
			Enums.GameState.GameState_Strike_Opponent_Response:
				accepted = _full_match_strike(ai, true)
				decisions += 1
			_:
				fail_test(context + ": unsupported state, NOT bypassed")
				return
		steps += 1
		assert_true(accepted, context + ": real AI submission accepted")
		if not accepted:
			print("FULL_MATCH_FAILED ", context)
			return
		events.append_array(game_logic.get_latest_events())
		if not _full_match_zones(context):
			return
	assert_true(game_logic.game_over, "seed=%s opponent=%s steps=%s: must reach real GameOver before cap" %
		[match_seed, opponent_id, steps])
	if not game_logic.game_over:
		return
	assert_eq(game_logic.game_state, Enums.GameState.GameState_GameOver)
	var endings = events.filter(func(event): return event.event_type == Enums.EventType.EventType_GameOver)
	assert_eq(endings.size(), 1, "Exactly one authoritative ending")
	if endings.size() != 1:
		return
	var ending = endings[0]
	assert_true(ending.event_player in [player1.my_id, player2.my_id])
	assert_true(ending.number in [Enums.GameOverReason.GameOverReason_Life, Enums.GameOverReason.GameOverReason_Decked])
	var loser = game_logic._get_player(ending.event_player)
	assert_ne(game_logic.game_over_winning_player.my_id, loser.my_id)
	if ending.number == Enums.GameOverReason.GameOverReason_Life:
		assert_lte(loser.life, 0, "Life ending must actually be lethal")
	else:
		assert_eq(loser.deck.size(), 0)
		assert_eq(loser.reshuffle_remaining, 0)
	var strikes = events.filter(func(event): return event.event_type == Enums.EventType.EventType_Strike_Started).size()
	assert_gt(actions, 0)
	assert_gt(decisions, 2)
	assert_gt(strikes, 0)
	print("FULL_MATCH seed=%s opponent=%s steps=%s actions=%s decisions=%s battles_started=%s winner=%s reason=%s life=%s/%s state=%s" %
		[match_seed, opponent_id, steps, actions, decisions, strikes, game_logic.game_over_winning_player.my_id,
		Enums.GameOverReason.keys()[ending.number], player1.life, player2.life, Enums.GameState.keys()[game_logic.game_state]])
	_full_match_completed = true

func test_ai_full_match_mirror_seed_20261025():
	_run_full_match("heiqiyihu", 20261025)
	assert_true(_full_match_completed, "Mirror seed 20261025 must finish, including after script errors")

func test_ai_full_match_mirror_seed_20261026():
	_run_full_match("heiqiyihu", 20261026)
	assert_true(_full_match_completed, "Mirror seed 20261026 must finish, including after script errors")

func test_ai_full_match_solbadguy_seed_20261025():
	_run_full_match("solbadguy", 20261025)
	assert_true(_full_match_completed, "Sol seed 20261025 must finish, including after script errors")

func test_ai_full_match_solbadguy_seed_20261026():
	_run_full_match("solbadguy", 20261026)
	assert_true(_full_match_completed, "Sol seed 20261026 must finish, including after script errors")
