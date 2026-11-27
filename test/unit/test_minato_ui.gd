extends GutTest

var game_ui : Game
var next_test_card_id = 60000
const S8CharacterIds = preload("res://test/unit/test_s8_data.gd").CharacterIds

class SelectedCard extends RefCounted:
	var card_id : int
	var selected : bool = true
	func _init(id : int):
		card_id = id
	func set_selected(value : bool):
		selected = value

func next_id() -> int:
	next_test_card_id += 1
	return next_test_card_id - 1

func give_player_specific_card(player : Player, def_id : String) -> int:
	var card_def = CardDataManager.get_card(def_id)
	var card_id = next_id()
	var card = GameCard.new(card_id, card_def, player.my_id)
	var card_db = game_ui.game_wrapper.current_game.get_card_database()
	card_db._test_insert_card(card)
	player.hand.append(card)
	return card_id

func add_transform(player : Player, def_id : String):
	give_player_specific_card(player, def_id)
	player.add_to_transforms(player.hand[-1])
	player.hand.remove_at(player.hand.size() - 1)

func setup_game_ui(player_id : String = "minato", opponent_id : String = "minato"):
	var game_scene = load("res://scenes/game/game.tscn")
	game_ui = game_scene.instantiate()
	game_ui.set_not_started_directly()
	game_ui.add_child(game_ui.game_wrapper)
	add_child(game_ui)
	var image_loader = game_ui.image_loader
	image_loader.defer_registered_card_images = true
	var game_logic = load("res://scenes/core/local_game.gd").new(image_loader)
	var seed_value = randi()
	game_logic.initialize_game(
		CardDataManager.get_deck_from_str_id(player_id),
		CardDataManager.get_deck_from_str_id(opponent_id),
		"p1",
		"p2",
		Enums.PlayerId.PlayerId_Player,
		seed_value
	)
	game_logic.draw_starting_hands_and_begin()
	assert_true(game_logic.do_mulligan(game_logic.player, []))
	assert_true(game_logic.do_mulligan(game_logic.opponent, []))
	game_logic.get_latest_events()
	game_ui.game_wrapper.current_game = game_logic

func before_each():
	setup_game_ui()

func after_each():
	if game_ui:
		game_ui.queue_free()
		game_ui = null
		await get_tree().process_frame

func test_force_for_change_ok_counts_sealed_force():
	var player = game_ui.game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	player.discard([player.hand[0].id])

	game_ui.ui_state = game_ui.UIState.UIState_SelectCards
	game_ui.ui_sub_state = game_ui.UISubState.UISubState_SelectCards_ForceForChange
	game_ui.selected_cards = []
	game_ui.can_seal_for_force = true
	game_ui.action_menu.number_panel_current_number = 1
	game_ui.use_free_force = false

	assert_true(game_ui.can_press_ok())

func test_s8_exceeded_boost_nested_infuse_opens_existing_confirmation():
	game_ui.free()
	game_ui = null
	setup_game_ui("heraal")
	var game_logic = game_ui.game_wrapper.current_game
	var player = game_logic.player
	player.exceeded = true
	player.discard_hand()
	var gauge_card = player.deck.pop_front()
	player.add_to_gauge(gauge_card)
	var boost_id = give_player_specific_card(player, "heraal_gore")
	assert_true(game_logic.do_boost(player, boost_id, []))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_GaugeForEffect)
	var infuse_events = game_logic.get_latest_events().filter(func(event):
		return event["event_type"] == Enums.EventType.EventType_GaugeForEffect)
	assert_eq(infuse_events.size(), 1)
	game_ui._on_gauge_for_effect(infuse_events[0])
	game_ui._update_buttons(true)
	assert_eq(game_ui.ui_sub_state, game_ui.UISubState.UISubState_SelectCards_GaugeForEffect)
	assert_eq(game_ui.select_card_require_min, 0)
	assert_eq(game_ui.select_card_require_max, 1)
	assert_string_contains(game_ui.action_menu.instructions_label.text, "灌注")
	game_ui.selected_cards = [{"card_id": gauge_card.id}]
	assert_true(game_ui.can_press_ok())

	assert_true(game_logic.do_gauge_for_effect(player, [gauge_card.id]))
	assert_true(player.is_infused())
	assert_true(player.is_card_in_discards(gauge_card.id))
	assert_eq(player.hand.size(), 1)
	assert_eq(game_logic.active_turn_player, player.my_id, "Nested Infused bonus action must resolve")

func test_shortcut_change_enables_seal_force_for_minato():
	var player = game_ui.game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	player.discard([player.hand[0].id])

	game_ui._on_shortcut_change_pressed()

	assert_true(game_ui.can_seal_for_force)
	assert_eq(game_ui.ui_sub_state, game_ui.UISubState.UISubState_SelectCards_ForceForChange)

func test_s8_shortcut_boost_prompts_before_any_effect_or_payment():
	game_ui.free()
	setup_game_ui("akimo")
	var logic = game_ui.game_wrapper.current_game
	var player = logic.player
	player.discard_hand()
	var gauge_card = player.deck.pop_front()
	player.add_to_gauge(gauge_card)
	var boost_id = give_player_specific_card(player, "akimo_bloodthirst")
	game_ui.selected_cards = [SelectedCard.new(boost_id)]
	game_ui._on_shortcut_boost_pressed()
	assert_string_contains(game_ui.action_menu.instructions_label.text, "是否要灌注")
	game_ui._update_buttons(true)
	assert_string_contains(game_ui.action_menu.instructions_label.text, "是否要灌注")
	assert_true(player.is_card_in_hand(boost_id))
	assert_true(player.is_card_in_gauge(gauge_card.id))
	assert_false(player.is_infused())
	assert_eq(logic.game_state, Enums.GameState.GameState_PickAction)
	game_ui.current_action_menu_choices[-1]["action"].call()
	assert_eq(logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_false(player.is_infused())
	assert_true(game_ui.pending_boost_infuse.is_empty())

func test_s8_normal_boost_confirms_infuse_before_force_cost():
	game_ui.free()
	setup_game_ui("kohai")
	var logic = game_ui.game_wrapper.current_game
	var player = logic.player
	player.discard_hand()
	var gauge_card = player.deck.pop_front()
	player.add_to_gauge(gauge_card)
	var boost_id = give_player_specific_card(player, "kohai_ambush")
	var force_id = give_player_specific_card(player, "standard_normal_grasp")
	game_ui._on_boost_button_pressed()
	game_ui.selected_cards = [SelectedCard.new(boost_id)]
	game_ui._on_instructions_ok_button_pressed(0)
	assert_string_contains(game_ui.action_menu.instructions_label.text, "是否要灌注")
	assert_true(player.is_card_in_hand(force_id))
	assert_true(player.is_card_in_hand(boost_id))
	game_ui.current_action_menu_choices[0]["action"].call()
	assert_eq(game_ui.ui_sub_state, game_ui.UISubState.UISubState_SelectCards_CharacterAction_Gauge)
	game_ui.selected_cards = [SelectedCard.new(gauge_card.id)]
	game_ui._on_instructions_ok_button_pressed(0)
	assert_eq(game_ui.ui_sub_state, game_ui.UISubState.UISubState_SelectCards_ForceForBoost)
	assert_false(player.is_infused(), "Selecting costs must not mutate authoritative state")
	game_ui.selected_cards = [SelectedCard.new(gauge_card.id)]
	assert_false(game_ui.can_press_ok(), "Infuse payment cannot also pay the boost")
	game_ui.selected_cards = [SelectedCard.new(force_id)]
	assert_true(game_ui.can_press_ok())
	game_ui._on_instructions_ok_button_pressed(0)
	assert_true(player.is_infused())
	assert_true(player.is_card_in_discards(force_id))
	assert_true(player.is_card_in_discards(gauge_card.id))
	assert_eq(logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(logic.do_choice(player, 2))
	assert_eq(logic.active_turn_player, player.my_id)
	assert_true(player.is_card_in_continuous_boosts(boost_id))
	assert_true(game_ui.pending_boost_infuse.is_empty())

func test_s8_unconditional_boost_skips_preconfirmation():
	game_ui.free()
	setup_game_ui("akimo")
	var player = game_ui.game_wrapper.current_game.player
	var gauge_card = player.deck.pop_front()
	player.add_to_gauge(gauge_card)
	var boost_id = give_player_specific_card(player, "standard_normal_grasp")
	game_ui.selected_cards = [SelectedCard.new(boost_id)]
	game_ui._on_shortcut_boost_pressed()
	assert_true(game_ui.pending_boost_infuse.is_empty())
	assert_true(player.is_card_in_continuous_boosts(boost_id))

func test_akimo_boost_can_infuse_with_life_without_gauge():
	game_ui.free()
	setup_game_ui("akimo")
	var logic = game_ui.game_wrapper.current_game
	var player = logic.player
	player.discard_hand()
	var boost_id = give_player_specific_card(player, "akimo_bloodthirst")
	game_ui.selected_cards = [SelectedCard.new(boost_id)]
	game_ui._on_shortcut_boost_pressed()
	assert_string_contains(game_ui.action_menu.instructions_label.text, "是否要灌注")
	assert_string_contains(game_ui.current_action_menu_choices[0]["text"], "支付2生命")
	assert_eq(player.life, 30)
	game_ui.current_action_menu_choices[0]["action"].call()
	assert_true(player.is_infused())
	assert_eq(player.life, 28)
	assert_eq(logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(game_ui.pending_boost_infuse.is_empty())

func test_cancel_preboost_infuse_does_not_spend_or_set_boost():
	game_ui.free()
	setup_game_ui("kohai")
	var logic = game_ui.game_wrapper.current_game
	var player = logic.player
	var gauge_card = player.deck.pop_front()
	player.add_to_gauge(gauge_card)
	var boost_id = give_player_specific_card(player, "kohai_ambush")
	game_ui._on_boost_button_pressed()
	game_ui.selected_cards = [SelectedCard.new(boost_id)]
	game_ui._on_instructions_ok_button_pressed(0)
	game_ui.current_action_menu_choices[0]["action"].call()
	game_ui._on_instructions_cancel_button_pressed()
	assert_true(player.is_card_in_hand(boost_id))
	assert_true(player.is_card_in_gauge(gauge_card.id))
	assert_false(player.is_infused())
	assert_true(game_ui.pending_boost_infuse.is_empty())
	assert_eq(game_ui.ui_sub_state, game_ui.UISubState.UISubState_SelectCards_PlayBoost)
	assert_eq(logic.game_state, Enums.GameState.GameState_PickAction)

func test_all_s8_boost_infuse_payability_on_both_sides():
	var checked_boosts = 0
	for character_id in S8CharacterIds:
		for exceeded in [false, true]:
			game_ui.free()
			setup_game_ui(character_id)
			var logic = game_ui.game_wrapper.current_game
			var player = logic.player
			player.exceeded = exceeded
			var gauge_card = player.deck.pop_front()
			var seen = {}
			var eligible_ids = []
			for entry in player.deck_def["cards"]:
				var definition_id = entry["definition_id"]
				if seen.has(definition_id):
					continue
				seen[definition_id] = true
				var definition = CardDataManager.get_card(definition_id)
				var boost = definition["boost"]
				var eligible = boost.get("boost_type") in ["continuous", "immediate"] \
						and not boost.get("passively_infuse", false) \
						and JSON.stringify(boost.get("effects", [])).contains('"condition":"is_infused"')
				var card_id = give_player_specific_card(player, definition_id)
				var context = "%s %s %s" % [character_id, "exceeded" if exceeded else "normal", definition_id]
				player.gauge.clear()
				player.gauge.append(gauge_card)
				player.life = 30
				player.free_gauge = 0
				player.infused = false
				assert_eq(player.get_boost_infuse_effect([card_id]) != null, eligible, context)
				assert_eq(not player.get_boost_infuse_payment_options([card_id]).is_empty(), eligible, context)
				if eligible:
					eligible_ids.append(card_id)
					game_ui._begin_boost_payment([card_id], null, false)
					assert_true(game_ui.pending_boost_infuse.get("awaiting_confirmation", false), context)
					assert_string_contains(game_ui.action_menu.instructions_label.text, "是否要灌注")
					game_ui.pending_boost_infuse = {}
					checked_boosts += 1
				player.gauge.clear()
				player.life = 2
				assert_eq(player.get_boost_infuse_payment_options([card_id]), [], "Cannot pay: " + context)
				player.free_gauge = 1
				assert_eq(not player.get_boost_infuse_payment_options([card_id]).is_empty(), eligible, "Free gauge: " + context)
				player.infused = true
				assert_eq(player.get_boost_infuse_payment_options([card_id]), [], "Already infused: " + context)
			player.infused = false
			player.free_gauge = 0
			player.life = 2
			player.gauge.clear()
			var no_payment_boost_id = eligible_ids[0] if not eligible_ids.is_empty() \
					else give_player_specific_card(player, "standard_normal_grasp")
			game_ui._begin_boost_payment([no_payment_boost_id], null, false)
			assert_false(game_ui.pending_boost_infuse.get("awaiting_confirmation", false), "%s cannot pay infuse" % character_id)
			assert_false(game_ui.action_menu.instructions_label.text.contains("是否要灌注"), "%s cannot pay infuse" % character_id)
	gut.p("Checked %s Infused boosts across all 16 S8 characters and both sides." % checked_boosts)

func test_akimo_infuse_options_require_remaining_life_above_cost():
	game_ui.free()
	setup_game_ui("akimo")
	var player = game_ui.game_wrapper.current_game.player
	var boost_id = give_player_specific_card(player, "akimo_bloodthirst")
	player.life = 2
	assert_eq(player.get_boost_infuse_payment_options([boost_id]), [])
	player.life = 3
	assert_eq(player.get_boost_infuse_payment_options([boost_id]).size(), 1)
	assert_eq(player.get_boost_infuse_payment_options([boost_id], [], 1), [])
	var gauge_card = player.deck.pop_front()
	player.add_to_gauge(gauge_card)
	player.life = 2
	var options = player.get_boost_infuse_payment_options([boost_id])
	assert_eq(options.size(), 1)
	assert_eq(options[0]["effect_type"], StrikeEffects.GaugeForEffect)
	assert_eq(player.get_boost_infuse_payment_options([boost_id], [gauge_card.id]), [])

func test_s8_free_gauge_infuse_does_not_require_or_consume_a_card():
	game_ui.free()
	setup_game_ui("kohai")
	var logic = game_ui.game_wrapper.current_game
	var player = logic.player
	player.discard_hand()
	player.free_gauge = 1
	var boost_id = give_player_specific_card(player, "kohai_earthquakestomp")
	game_ui.selected_cards = [SelectedCard.new(boost_id)]
	game_ui._on_shortcut_boost_pressed()
	assert_true(game_ui.pending_boost_infuse.get("awaiting_confirmation", false))
	game_ui.current_action_menu_choices[0]["action"].call()
	assert_true(player.is_infused())
	assert_eq(player.free_gauge, 1, "Passive gauge discount must stay active")
	assert_eq(player.gauge.size(), 0)
	assert_eq(logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_true(logic.do_choice(player, 2))
	assert_eq(logic.game_state, Enums.GameState.GameState_WaitForStrike)

func test_treasure_exceed_change_shows_optional_one_free_force_after_strike():
	game_ui.free()
	game_ui = null
	setup_game_ui("treasure", "treasure")
	var game_logic = game_ui.game_wrapper.current_game
	var player = game_logic.player
	var opponent = game_logic.opponent
	var gauge_ids = []
	for _i in range(3):
		var card = player.deck.pop_front()
		player.add_to_gauge(card)
		gauge_ids.append(card.id)
	assert_true(game_logic.do_exceed(player, gauge_ids))
	assert_true(game_logic.do_choice(player, 3))
	opponent.hand.clear()
	assert_true(game_logic.do_prepare(opponent))
	var attack_id = give_player_specific_card(player, "standard_normal_grasp")
	var response_id = give_player_specific_card(opponent, "standard_normal_grasp")
	assert_true(game_logic.do_strike(player, attack_id, false, -1))
	assert_true(game_logic.do_strike(opponent, response_id, false, -1))
	assert_true(game_logic.do_prepare(opponent))

	player.hand.clear()
	game_ui._on_shortcut_change_pressed()
	game_ui._update_buttons(true)
	var toggle = game_ui.action_menu.get_node("OuterMargin/MainVBox/CheckHBox3/FreeForceOptionCheck")
	assert_true(toggle.visible)
	assert_true(toggle.button_pressed)
	assert_eq(game_ui.get_force_in_selected_cards(), 1)
	assert_true(game_ui.can_press_ok())

	toggle.button_pressed = false
	assert_eq(game_ui.get_force_in_selected_cards(), 0)
	assert_false(game_ui.can_press_ok())
	toggle.button_pressed = true
	var hand_size = player.hand.size()
	game_ui._on_instructions_ok_button_pressed(0)
	assert_eq(player.hand.size(), hand_size + 2)

func test_treasure_normal_change_does_not_offer_free_force():
	game_ui.free()
	game_ui = null
	setup_game_ui("treasure")
	game_ui._on_shortcut_change_pressed()
	game_ui._update_buttons(true)
	var toggle = game_ui.action_menu.get_node("OuterMargin/MainVBox/CheckHBox3/FreeForceOptionCheck")
	assert_false(toggle.visible)
	assert_false(game_ui.use_free_force)

func test_strike_button_triggers_outrun_before_attack_selection():
	var player = game_ui.game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	add_transform(player, "minato_flight_13")
	player.discard([player.hand[0].id])

	game_ui._on_strike_button_pressed()
	var game_logic = game_ui.game_wrapper.current_game

	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseFromDiscard)
	assert_eq(game_logic.decision_info.source, "outrun_seal")
	assert_true(player.minato_outrun_triggered_before_strike)


func test_restore_sync_reopens_player_decision_ui_from_wait_state():
	var player = game_ui.game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	add_transform(player, "minato_flight_13")
	player.discard([player.hand[0].id])
	game_ui._on_strike_button_pressed()
	var game_logic = game_ui.game_wrapper.current_game

	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseFromDiscard)

	game_ui.change_ui_state(game_ui.UIState.UIState_WaitForGameServer, game_ui.UISubState.UISubState_None)
	game_ui._sync_ui_state_after_restore()

	assert_eq(game_ui.ui_state, game_ui.UIState.UIState_SelectCards)
	assert_eq(game_ui.ui_sub_state, game_ui.UISubState.UISubState_SelectCards_ChooseDiscardToDestination)

func test_seal_for_gauge_uses_floor_division_and_step_three():
	var player = game_ui.game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	for _i in range(7):
		var card_id = give_player_specific_card(player, "standard_normal_grasp")
		player.discard([card_id])

	game_ui.ui_state = game_ui.UIState.UIState_SelectCards
	game_ui.ui_sub_state = game_ui.UISubState.UISubState_SelectCards_StrikeGauge
	game_ui.select_card_require_min = 3
	game_ui.select_card_require_max = 3
	game_ui.selected_cards = []
	game_ui.can_seal_for_gauge = true
	game_ui.action_menu.number_panel_current_number = 7

	assert_eq(game_ui.get_gauge_generated(), 2)
	game_ui._update_buttons(true)
	assert_eq(game_ui.action_menu.number_picker_step, 3)
	assert_eq(game_ui.instructions_number_picker_max, 7)

func test_dredge_fury_allows_partial_gauge_selection_for_optional_effect():
	var game_logic = game_ui.game_wrapper.current_game
	game_logic.decision_info.clear()
	game_logic.decision_info.player = Enums.PlayerId.PlayerId_Player
	game_logic.decision_info.type = Enums.DecisionType.DecisionType_GaugeForEffect
	game_logic.decision_info.effect = {
		"gauge_max": 3,
		"min_gauge": 0,
		"per_gauge_effect": {"effect_type": "powerup", "amount": 2},
		"overall_effect": {"effect_type": "syrus_dredge_fury_keep_choice"},
		"allow_partial_gauge_selection": true
	}

	game_ui._on_gauge_for_effect({"event_player": Enums.PlayerId.PlayerId_Player})
	var player = game_ui.game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	var gauge_card = player.hand.pop_back()
	player.add_to_gauge(gauge_card)
	game_ui.selected_cards = [{"card_id": gauge_card.id}]

	assert_eq(game_ui.get_gauge_generated(), 1)
	assert_true(game_ui.can_press_ok())

func test_taisei_death_exceed_allows_zero_gauge_confirmation():
	game_ui.free()
	game_ui = null
	setup_game_ui("taisei")
	var game_logic = game_ui.game_wrapper.current_game
	game_logic.decision_info.clear()
	game_logic.decision_info.player = Enums.PlayerId.PlayerId_Player
	game_logic.decision_info.type = Enums.DecisionType.DecisionType_GaugeForEffect
	game_logic.decision_info.effect = {
		"gauge_max": 0,
		"min_gauge": 0,
		"can_pass": true,
		"decline_on_death_game_over": true,
		"per_gauge_effect": null,
		"overall_effect": {"effect_type": StrikeEffects.ExceedNow},
	}

	game_ui._on_gauge_for_effect({"event_player": Enums.PlayerId.PlayerId_Player})

	assert_true(game_ui.can_press_ok())

func test_sealed_gauge_payment_is_one_shot():
	var player = game_ui.game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	var game_logic = game_ui.game_wrapper.current_game
	for _i in range(3):
		var discard_id = give_player_specific_card(player, "standard_normal_grasp")
		player.discard([discard_id])
	game_logic.game_state = Enums.GameState.GameState_PlayerDecision
	game_logic.active_exceed = true
	game_logic.decision_info.clear()
	game_logic.decision_info.player = player.my_id
	game_logic.decision_info.type = Enums.DecisionType.DecisionType_GaugeForEffect
	game_logic.decision_info.effect = {
		"gauge_max": 1,
		"min_gauge": 1,
		"per_gauge_effect": {"effect_type": "pass"},
		"overall_effect": null
	}

	game_ui.ui_state = game_ui.UIState.UIState_SelectCards
	game_ui.ui_sub_state = game_ui.UISubState.UISubState_SelectCards_GaugeForEffect
	game_ui.select_card_require_min = 1
	game_ui.select_card_require_max = 1
	game_ui.selected_cards = []
	game_ui.can_seal_for_gauge = true
	game_ui.action_menu.number_panel_current_number = 3

	assert_true(game_ui.can_press_ok())
	game_ui._on_instructions_ok_button_pressed(0)

	assert_eq(player.free_gauge, 0)
	assert_eq(player.gauge.size(), 0)
	assert_eq(player.sealed.size(), 3)
	assert_false(player.can_pay_cost(0, 1))

func test_streetcar_disaster_pays_three_gauge_by_sealing_nine_discards_against_taisei_block():
	game_ui.free()
	game_ui = null
	setup_game_ui("minato", "taisei")
	var player = game_ui.game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	var opponent = game_ui.game_wrapper._get_player(Enums.PlayerId.PlayerId_Opponent)
	var game_logic = game_ui.game_wrapper.current_game
	player.arena_location = 3
	opponent.arena_location = 7
	for _i in range(11):
		var discard_id = give_player_specific_card(player, "standard_normal_grasp")
		player.discard([discard_id])
	var ultra_id = give_player_specific_card(player, "minato_streetcar_disaster")
	var response_id = give_player_specific_card(opponent, "standard_normal_block")

	assert_true(game_logic.do_strike(player, ultra_id, false, -1))
	assert_true(game_logic.do_strike(opponent, response_id, false, -1))
	assert_true(game_logic.do_choice(opponent, 0))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_PayStrikeCost_Required)
	assert_eq(game_logic.decision_info.cost, 3)

	game_ui.ui_state = game_ui.UIState.UIState_SelectCards
	game_ui.ui_sub_state = game_ui.UISubState.UISubState_SelectCards_StrikeGauge
	game_ui.select_card_require_min = 3
	game_ui.select_card_require_max = 3
	game_ui.selected_cards = []
	game_ui.can_seal_for_gauge = true
	game_ui.action_menu.number_panel_current_number = 9
	assert_true(game_ui.can_press_ok())
	game_ui._on_instructions_ok_button_pressed(0)

	assert_eq(player.sealed.size(), 9)

func test_exceed_ok_enabled_when_sealed_discards_generate_enough_gauge():
	var player = game_ui.game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	for _i in range(6):
		var discard_id = give_player_specific_card(player, "standard_normal_grasp")
		player.discard([discard_id])

	game_ui.ui_state = game_ui.UIState.UIState_SelectCards
	game_ui.ui_sub_state = game_ui.UISubState.UISubState_SelectCards_Exceed
	game_ui.select_card_require_min = 2
	game_ui.select_card_require_max = 2
	game_ui.selected_cards = []
	game_ui.can_seal_for_gauge = true
	game_ui.action_menu.number_panel_current_number = 6

	assert_eq(game_ui.get_gauge_generated(), 2)
	assert_true(game_ui.can_press_ok())

func test_exceed_pending_power_bonus_text_shows_in_boost_box():
	var player = game_ui.game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	player.exceeded = true
	player.minato_seal_power_bonus = 4

	game_ui._update_buttons(true)
	var boost_text = game_ui.get_node("PlayerBoostZone").boost_effects.text
	assert_true(boost_text.find("下一次攻击获得+4威力") != -1)
