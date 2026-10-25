extends ExceedGutTest

var game_ui : Game

func who_am_i():
	return "vatista"

func before_each():
	super.before_each()
	game_ui = Game.new()
	game_ui.game_wrapper.current_game = game_logic

func after_each():
	game_ui.game_wrapper.free()
	game_ui.free()
	super.after_each()

func setup_lateus_orbis_against_focus(ignore_armor : bool = false):
	advance_turn(player1)
	position_players(player1, 3, player2, 7)
	var gauge = give_gauge(player2, 3)
	player2.hand.clear()
	var focus_id = give_player_specific_card(player1, "uni_normal_focus")
	var lateus_id = give_player_specific_card(player2, "vatista_lateusorbis")
	do_and_validate_strike(player2, lateus_id)
	do_strike_response(player1, focus_id)
	player2.strike_stat_boosts.ignore_armor = ignore_armor
	assert_true(game_logic.do_pay_strike_cost(player2, gauge, false))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ForceForArmor)
	assert_eq(game_logic.decision_info.player, player1.my_id)
	assert_eq(game_logic.get_total_armor(player1), 2)
	var events = game_logic.get_latest_events()
	var armor_events = events.filter(func(event):
		return event['event_type'] == Enums.EventType.EventType_Strike_ForceForArmor)
	assert_eq(armor_events.size(), 1)
	game_ui.force_for_armor_incoming_damage = armor_events[0]['number']
	game_ui.force_for_armor_ignore_armor = armor_events[0]['extra_info']
	game_ui.force_for_armor_amount = game_logic.decision_info.amount
	game_ui.ui_sub_state = Game.UISubState.UISubState_SelectCards_ForceForArmor

func test_focus_base_armor_is_not_generated_armor():
	setup_lateus_orbis_against_focus()
	game_ui.update_force_generation_message()
	assert_string_contains(game_ui.current_instruction_text, "已生成的护甲：0")
	assert_string_contains(game_ui.current_instruction_text, "你将受到 4 点伤害")
	assert_true(game_logic.do_force_for_armor(player1, []))
	validate_life(player1, 26, player2, 30)

func test_generated_armor_only_counts_selected_force():
	setup_lateus_orbis_against_focus()
	var card_id = give_player_specific_card(player1, "uni_normal_grasp")
	game_ui.selected_cards = [{"card_id": card_id}]
	game_ui.update_force_generation_message()
	assert_string_contains(game_ui.current_instruction_text, "已生成的护甲：1")
	assert_string_contains(game_ui.current_instruction_text, "你将受到 3 点伤害")
	assert_true(game_logic.do_force_for_armor(player1, [card_id]))
	validate_life(player1, 27, player2, 30)

func test_ultra_generates_two_armor_without_focus_base_armor():
	setup_lateus_orbis_against_focus()
	var card_id = give_player_specific_card(player1, "vatista_armabellum")
	game_ui.selected_cards = [{"card_id": card_id}]
	game_ui.update_force_generation_message()
	assert_string_contains(game_ui.current_instruction_text, "已生成的护甲：2")
	assert_string_contains(game_ui.current_instruction_text, "你将受到 2 点伤害")
	assert_true(game_logic.do_force_for_armor(player1, [card_id]))
	validate_life(player1, 28, player2, 30)

func test_ignored_armor_is_still_generated_but_does_not_reduce_damage():
	setup_lateus_orbis_against_focus(true)
	var card_id = give_player_specific_card(player1, "uni_normal_grasp")
	game_ui.selected_cards = [{"card_id": card_id}]
	game_ui.update_force_generation_message()
	assert_string_contains(game_ui.current_instruction_text, "已生成的护甲：1")
	assert_string_contains(game_ui.current_instruction_text, "护甲被无视")
	assert_string_contains(game_ui.current_instruction_text, "你将受到 6 点伤害")
	assert_true(game_logic.do_force_for_armor(player1, [card_id]))
	validate_life(player1, 24, player2, 30)

func test_generated_armor_can_exceed_incoming_damage():
	setup_lateus_orbis_against_focus()
	var card_ids = []
	for i in range(3):
		var card_id = give_player_specific_card(player1, "vatista_armabellum")
		card_ids.append(card_id)
		game_ui.selected_cards.append({"card_id": card_id})
	game_ui.update_force_generation_message()
	assert_string_contains(game_ui.current_instruction_text, "已生成的护甲：6")
	assert_string_contains(game_ui.current_instruction_text, "你将受到 0 点伤害")
	assert_true(game_logic.do_force_for_armor(player1, card_ids))
	validate_life(player1, 30, player2, 30)

func test_gauge_for_armor_only_displays_conversion_armor():
	setup_lateus_orbis_against_focus()
	var gauge = give_gauge(player1, 1)
	game_logic.decision_info.limitation = "gauge"
	game_logic.decision_info.amount = 2
	game_ui.force_for_armor_amount = 2
	game_ui.ui_sub_state = Game.UISubState.UISubState_SelectCards_GaugeForArmor
	game_ui.update_gauge_selection_message()
	assert_string_contains(game_ui.current_instruction_text, "已生成的护甲：0")
	game_ui.selected_cards = [{"card_id": gauge[0]}]
	game_ui.update_gauge_selection_message()
	assert_string_contains(game_ui.current_instruction_text, "已生成的护甲：2")
	assert_string_contains(game_ui.current_instruction_text, "你将受到 2 点伤害")
	assert_true(game_logic.do_force_for_armor(player1, gauge))
	validate_life(player1, 28, player2, 30)

func test_other_force_selection_does_not_display_generated_armor():
	game_ui.ui_sub_state = Game.UISubState.UISubState_SelectCards_ForceForChange
	game_ui.update_force_generation_message()
	assert_false("已生成的护甲" in game_ui.current_instruction_text)
