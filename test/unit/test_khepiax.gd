extends ExceedGutTest

class GaugeChoiceUI extends Game:
	var opened_own_gauge := false
	var opened_opponent_gauge := false

	func _on_player_gauge_gauge_clicked(_auto: bool = true):
		opened_own_gauge = true

	func _on_opponent_gauge_gauge_clicked(_auto: bool = true):
		opened_opponent_gauge = true

	func clear_selected_cards():
		selected_cards.clear()

	func enable_instructions_ui(_text, _enabled, _cancel, _extra: Dictionary = {},
			_can_ex: bool = true, _choices: Array = [], _number: bool = false,
			_extra_text: Array = [], _require_ex: bool = false, _face = null,
			_life_cost: int = 0):
		pass

	func change_ui_state(new_state, new_sub_state = null):
		if new_state != null:
			ui_state = new_state
		if new_sub_state != null:
			ui_sub_state = new_sub_state

func who_am_i():
	return "khepiax"

func _resolve_basic_hit(infused: bool, opponent_has_gauge: bool) -> int:
	position_players(player1, 3, player2, 6)
	if infused:
		var payment = give_gauge(player1, 1)
		assert_true(game_logic.do_character_action(player1, payment, 1))
	var attack = give_player_specific_card(player1, "khepiax_energydrain")
	var hand_before = player1.hand.size()
	var discarded_hand_card = player2.hand[0].id
	var defender_choices = [[]] if opponent_has_gauge else []
	execute_strike(player1, player2, attack, "standard_normal_focus",
			false, false, [], defender_choices, true)
	if infused:
		assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseSimultaneousEffect)
		assert_true(game_logic.do_choice(player1, 0))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseToDiscard)
	assert_true(game_logic.do_choose_to_discard(player2, [discarded_hand_card]))
	assert_true(player2.is_card_in_discards(discarded_hand_card))
	assert_eq(player1.hand.size(), hand_before, "Setting the attack and drawing one must cancel out")
	return attack

func test_infused_energy_drain_opponent_discards_exactly_one_own_gauge():
	var gauge = give_gauge(player2, 2)
	var own_gauge = give_gauge(player1, 1)
	var attack = _resolve_basic_hit(true, true)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseFromDiscard)
	assert_eq(game_logic.decision_info.player, player2.my_id)
	assert_eq(game_logic.decision_info.source, "gauge")
	assert_eq(game_logic.decision_info.destination, "discard")
	assert_false(game_logic.do_choose_from_discard(player2, []))
	assert_false(game_logic.do_choose_from_discard(player2, gauge))
	assert_false(game_logic.do_choose_from_discard(player2, [player2.hand[0].id]))
	assert_true(game_logic.do_choose_from_discard(player2, [gauge[1]]))
	assert_true(player2.is_card_in_discards(gauge[1]))
	assert_true(player2.is_card_in_gauge(gauge[0]))
	assert_true(player1.is_card_in_gauge(own_gauge[0]))
	assert_true(player1.is_card_in_gauge(attack))
	assert_eq(game_logic.active_turn_player, player2.my_id)
	assert_null(game_logic.active_strike)

func test_uninfused_energy_drain_preserves_opponent_gauge():
	var gauge = give_gauge(player2, 2)
	var attack = _resolve_basic_hit(false, true)
	for card_id in gauge:
		assert_true(player2.is_card_in_gauge(card_id))
	assert_true(player1.is_card_in_gauge(attack))
	assert_null(game_logic.active_strike)

func test_infused_energy_drain_skips_empty_opponent_gauge():
	var attack = _resolve_basic_hit(true, false)
	assert_true(player2.gauge.is_empty())
	assert_true(player1.is_card_in_gauge(attack))
	assert_null(game_logic.active_strike)

func test_infused_energy_drain_miss_preserves_opponent_gauge():
	position_players(player1, 2, player2, 7)
	var gauge = give_gauge(player2, 2)
	assert_true(game_logic.do_character_action(player1, give_gauge(player1, 1), 1))
	var attacks = execute_strike(player1, player2, "khepiax_energydrain",
			"standard_normal_focus", false, false, [], [[]])
	for card_id in gauge:
		assert_true(player2.is_card_in_gauge(card_id))
	assert_true(player1.is_card_in_discards(attacks[0]))
	assert_null(game_logic.active_strike)

func test_energy_drain_rules_ai_discards_own_gauge_and_continues():
	_verify_energy_drain_ai(AIPolicyRules.new(), 3, 1)

func test_energy_drain_omniscient_ai_discards_last_gauge_and_continues():
	_verify_energy_drain_ai(AIPolicyOmniscient.new(), 1, 0)

func test_energy_drain_random_ai_discards_own_gauge_and_continues():
	_verify_energy_drain_ai(AIPolicyRandom.new(), 3, 0)

func _verify_energy_drain_ai(policy, gauge_count: int, own_gauge_count: int):
	var gauge = give_gauge(player2, gauge_count)
	var own_gauge = give_gauge(player1, own_gauge_count)
	var attack = _resolve_basic_hit(true, true)
	var prompts = game_logic.get_latest_events().filter(func(event):
		return event.event_type == Enums.EventType.EventType_ChooseFromDiscard)
	assert_eq(prompts.size(), 1)
	assert_eq(game_logic.decision_info.player, player2.my_id)
	var ui = GaugeChoiceUI.new()
	ui.game_wrapper.current_game = game_logic
	ui.ai_player = AIPlayer.new(game_logic, player2, policy)
	ui._on_choose_from_discard(prompts[0])
	assert_eq(player2.gauge.size(), gauge_count - 1)
	var discarded = gauge.filter(func(card_id): return player2.is_card_in_discards(card_id))
	assert_eq(discarded.size(), 1, "AI must discard exactly one card from its own gauge")
	for card_id in own_gauge:
		assert_true(player1.is_card_in_gauge(card_id))
	assert_true(player1.is_card_in_gauge(attack))
	assert_null(game_logic.active_strike, "AI submission must let the strike finish")
	assert_eq(game_logic.active_turn_player, player2.my_id)
	policy.free()
	ui.ai_player = null
	ui.game_wrapper.current_game = null
	ui.game_wrapper.free()
	ui.free()
	advance_turn(player2)

func test_energy_drain_gauge_prompt_opens_choosers_own_gauge():
	var gauge = give_gauge(player1, 2)
	var other_gauge = give_gauge(player2, 1)
	var attack = give_player_specific_card(player2, "khepiax_energydrain")
	var effect = game_logic.card_db.get_card(attack).definition.effects[1]
	game_logic.handle_strike_effect(attack, effect, player2)
	var events = game_logic.get_latest_events()
	var ui = GaugeChoiceUI.new()
	ui.game_wrapper.current_game = game_logic
	var all_cards = Node.new()
	all_cards.name = "AllCards"
	ui.add_child(all_cards)
	for zone_name in ["PlayerAllCopy", "OpponentAllCopy", "ChoiceZone"]:
		var zone = Node2D.new()
		zone.name = zone_name
		all_cards.add_child(zone)
	ui.choice_zone_parent = all_cards.get_node("ChoiceZone")
	for event in events:
		if event.event_type == Enums.EventType.EventType_ChooseFromDiscard:
			ui._on_choose_from_discard(event)
		elif event.event_type == Enums.EventType.EventType_Boost_DiscardOpponentGauge:
			ui._on_discard_opponent_gauge(event)
	assert_true(ui.opened_own_gauge)
	assert_false(ui.opened_opponent_gauge)
	assert_eq(ui.popout_instruction_info.popout_type, Game.CardPopoutType.CardPopoutType_GaugePlayer)
	assert_eq(ui.select_card_require_min, 1)
	assert_eq(ui.select_card_require_max, 1)
	assert_false(ui.popout_instruction_info.cancel_visible)
	var card = CardBase.new()
	card.card_id = gauge[0]
	assert_true(ui.can_select_card(card))
	card.card_id = other_gauge[0]
	assert_false(ui.can_select_card(card))
	card.card_id = player1.hand[0].id
	assert_false(ui.can_select_card(card))
	card.free()
	assert_true(player1.is_card_in_gauge(gauge[0]))
	ui.game_wrapper.current_game = null
	ui.game_wrapper.free()
	ui.free()
