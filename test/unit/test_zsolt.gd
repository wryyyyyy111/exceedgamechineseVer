extends ExceedGutTest

func who_am_i():
	return "zsolt"

func _find_character_effect_event(events, player, effect_type):
	for event in events:
		if event['event_type'] != Enums.EventType.EventType_Strike_CharacterEffect:
			continue
		if event['event_player'] != player.my_id:
			continue
		var extra_info = event.get('extra_info', {})
		if extra_info.get('effect_type') == effect_type:
			return event
	return null

func _has_active_character_effect(player, effect_type):
	for effect in player.strike_stat_boosts.active_character_effects:
		if typeof(effect) == TYPE_DICTIONARY and effect.get('effect_type') == effect_type:
			return true
	return false

func _start_strike_with_transform(transform_def_id, strike_def_id):
	add_transform(player1, transform_def_id)
	position_players(player1, 4, player2, 5)
	var strike_card_id = give_player_specific_card(player1, strike_def_id)
	assert_true(game_logic.do_strike(player1, strike_card_id, false, -1), "failed to start strike")
	return game_logic.get_latest_events()

func test_mad_dog_force_for_effect_shows_powerup_only_after_paying_force():
	var events = _start_strike_with_transform("zsolt_blazingflame", "standard_normal_assault")

	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ForceForEffect)
	var preview_event = _find_character_effect_event(events, player1, StrikeEffects.Powerup)
	assert_eq(preview_event, null)
	assert_false(_has_active_character_effect(player1, StrikeEffects.Powerup))
	assert_eq(player1.strike_stat_boosts.power, 0)

	var force_card = give_player_specific_card(player1, "standard_normal_grasp")
	assert_true(game_logic.do_force_for_effect(player1, [force_card], false), "failed do_force_for_effect")
	var paid_events = game_logic.get_latest_events()
	var paid_preview_event = _find_character_effect_event(paid_events, player1, StrikeEffects.Powerup)
	assert_not_null(paid_preview_event)
	if paid_preview_event == null:
		return
	var paid_preview_info = paid_preview_event.get('extra_info', {})
	assert_true(paid_preview_info.get('character_effect', false))
	assert_eq(paid_preview_info.get('amount', -1), 1)
	assert_true(_has_active_character_effect(player1, StrikeEffects.Powerup))

func test_press_the_attack_shows_speedup_only_after_paying_force():
	var events = _start_strike_with_transform("zsolt_explosivesmash", "standard_normal_assault")

	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ForceForEffect)
	var preview_event = _find_character_effect_event(events, player1, StrikeEffects.Speedup)
	assert_eq(preview_event, null)
	assert_false(_has_active_character_effect(player1, StrikeEffects.Speedup))
	assert_eq(player1.strike_stat_boosts.speed, 0)

	var force_card = give_player_specific_card(player1, "standard_normal_grasp")
	assert_true(game_logic.do_force_for_effect(player1, [force_card], false), "failed do_force_for_effect")
	var paid_events = game_logic.get_latest_events()
	var paid_preview_event = _find_character_effect_event(paid_events, player1, StrikeEffects.Speedup)
	assert_not_null(paid_preview_event)
	if paid_preview_event == null:
		return
	var paid_preview_info = paid_preview_event.get('extra_info', {})
	assert_true(paid_preview_info.get('character_effect', false))
	assert_eq(paid_preview_info.get('amount', -1), 1)
	assert_true(_has_active_character_effect(player1, StrikeEffects.Speedup))

func test_zsolt_awaken_force_for_effect_does_not_emit_character_effect_preview():
	game_logic.initialize_new_strike(player1, false)
	game_logic.active_strike.initiator = player1
	game_logic.active_strike.defender = player2
	game_logic.active_strike.initiator_first = true
	game_logic.active_strike.player1_hit = true
	game_logic.get_latest_events()

	var awaken_effect = {
		"effect_type": StrikeEffects.ForceForEffect,
		"is_zsolt_awaken": true,
		"overall_effect": null,
		"force_max": 1,
		"per_force_effect": {
			"effect_type": StrikeEffects.Powerup,
			"amount": 1,
		},
	}

	game_logic.handle_strike_effect(-1, awaken_effect, player1)
	var events = game_logic.get_latest_events()

	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ForceForEffect)
	assert_eq(_find_character_effect_event(events, player1, StrikeEffects.Powerup), null)
	assert_false(_has_active_character_effect(player1, StrikeEffects.Powerup))