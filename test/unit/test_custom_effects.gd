extends ExceedGutTest


func get_custom_cards():
	return [
		{
			"id": "custom_stealgauge",
			"type": "special",
			"display_name": "this is mine too",
			"force_cost": 0,
			"gauge_cost": 0,
			"range_min": 1,
			"range_max": 1,
			"power": 1,
			"speed": 7,
			"armor": 1,
			"guard": 0,
			"effects": [
				{
					"timing": "during_strike",
					"effect_type": "ignore_armor"
				},
				{
					"timing": "after",
					"condition": "opponent_stunned",
					"effect_type": "add_opponent_strike_to_gauge"
				}
			],
			"boost": {
				"boost_type": "continuous",
				"force_cost": 0,
				"cancel_cost": -1,
				"display_name": "here i come",
				"effects": [
					{
						"timing": "now",
						"effect_type": "strike"
					},
					{
						"timing": "before",
						"effect_type": "close",
						"amount": 4,
						"save_spaces_not_closed_as_strike_x": true,
						"and": {
							"effect_type": "powerup",
							"amount": "strike_x",
							"multiplier": 1
						}
					}
				]
			}
		},
		{
			"id": "custom_notfullpull",
			"type": "special",
			"display_name": "everybody get in here",
			"force_cost": 0,
			"gauge_cost": 0,
			"range_min": 1,
			"range_max": 3,
			"power": 2,
			"speed": 4,
			"armor": 0,
			"guard": 0,
			"effects": [
				{
					"timing": "before",
					"effect_type": "pull",
					"amount": 1,
					"use_semicolon_for_and": true,
					"and": {
						"condition": "not_full_pull",
						"effect_type": "powerup",
						"amount": 5
					}
				}
			],
			"boost": {
				"boost_type": "continuous",
				"force_cost": 0,
				"cancel_cost": -1,
				"display_name": "i promise these stats are real",
				"effects": [
					{
						"timing": "now",
						"effect_type": "strike"
					},
					{
						"timing": "during_strike",
						"effect_type": "powerup",
						"amount": 3,
						"and": {
							"effect_type": "armorup",
							"amount": 3
						}
					},
					{
						"timing": "hit",
						"effect_type": "add_boost_to_gauge_on_strike_cleanup",
						"not_immediate": true
					}
				]
			}
		},
		{
			"id": "custom_reducecostperboost",
			"type": "ultra",
			"display_name": "Cheapskate",
			"force_cost": 0,
			"gauge_cost": 3,
			"gauge_cost_reduction": "per_boost_in_play",
			"range_min": 1,
			"range_max": 8,
			"power": 5,
			"speed": 6,
			"armor": 0,
			"guard": 0,
			"effects": [
				{
					"timing": "before",
					"effect_type": "close",
					"amount": 1
				}
			],
			"boost": {
				"boost_type": "continuous",
				"force_cost": 0,
				"cancel_cost": -1,
				"display_name": "what if i just don't care",
				"effects": [
					{
						"timing": "during_strike",
						"effect_type": "stun_immunity"
					}
				]
			}
		},
		{
			"id": "custom_powerupperarmor",
			"type": "special",
			"display_name": "Offense and Defense in Equal Measures",
			"force_cost": 0,
			"gauge_cost": 0,
			"range_min": 1,
			"range_max": 8,
			"power": 2,
			"speed": 6,
			"armor": 3,
			"guard": 0,
			"effects": [
				{
					"timing": "before",
					"effect_type": "powerup_per_armor",
					"amount": 1
				}
			],
			"boost": {
				"boost_type": "continuous",
				"force_cost": 0,
				"cancel_cost": -1,
				"display_name": "what if i just don't care",
				"effects": [
					{
						"timing": "during_strike",
						"effect_type": "stun_immunity"
					}
				]
			}
		},
		{
			"id": "custom_powerupperspeed",
			"type": "special",
			"display_name": "Where I'm from, Speed Equals Strength",
			"force_cost": 0,
			"gauge_cost": 0,
			"range_min": 1,
			"range_max": 8,
			"power": 2,
			"speed": 8,
			"armor": 0,
			"guard": 0,
			"effects": [
				{
					"timing": "before",
					"effect_type": "powerup_per_speed",
					"amount": 1
				}
			],
			"boost": {
				"boost_type": "continuous",
				"force_cost": 0,
				"cancel_cost": -1,
				"display_name": "what if i just don't care",
				"effects": [
					{
						"timing": "during_strike",
						"effect_type": "stun_immunity"
					}
				]
			}
		},
		{
			"id": "custom_powerupperpower",
			"type": "special",
			"display_name": "double it and give it to the next person",
			"force_cost": 0,
			"gauge_cost": 0,
			"range_min": 1,
			"range_max": 8,
			"power": 5,
			"speed": 6,
			"armor": 0,
			"guard": 0,
			"effects": [
				{
					"timing": "before",
					"effect_type": "powerup_per_power",
					"amount": 1
				}
			],
			"boost": {
				"boost_type": "continuous",
				"force_cost": 0,
				"cancel_cost": -1,
				"display_name": "what if i just don't care",
				"effects": [
					{
						"timing": "during_strike",
						"effect_type": "stun_immunity"
					}
				]
			}
		},
		{
			"id": "custom_opponentprintedspeedgreater",
			"type": "special",
			"display_name": "Patience is a virtue",
			"force_cost": 0,
			"gauge_cost": 0,
			"range_min": 1,
			"range_max": 8,
			"power": 5,
			"speed": 2,
			"armor": 0,
			"guard": 0,
			"effects": [
				{
					"timing": "during_strike",
					"condition": "opponent_printed_speed_greater",
					"effect_type": "powerup",
					"amount": 5
				}
			],
			"boost": {
				"boost_type": "continuous",
				"force_cost": 0,
				"cancel_cost": -1,
				"display_name": "what if i just don't care",
				"effects": [
					{
						"timing": "during_strike",
						"effect_type": "stun_immunity"
					}
				]
			}
		},
		{
			"id": "custom_opponentprintedspeedless",
			"type": "special",
			"display_name": "Patience? What's that",
			"force_cost": 0,
			"gauge_cost": 0,
			"range_min": 1,
			"range_max": 8,
			"power": 5,
			"speed": 8,
			"armor": 0,
			"guard": 0,
			"effects": [
				{
					"timing": "during_strike",
					"condition": "opponent_printed_speed_less",
					"effect_type": "powerup",
					"amount": 5
				}
			],
			"boost": {
				"boost_type": "continuous",
				"force_cost": 0,
				"cancel_cost": -1,
				"display_name": "what if i just don't care",
				"effects": [
					{
						"timing": "during_strike",
						"effect_type": "stun_immunity"
					}
				]
			}
		},
		{
			"id": "custom_opponentprintedspeedgreater",
			"type": "special",
			"display_name": "Patience is a virtue",
			"force_cost": 0,
			"gauge_cost": 0,
			"range_min": 1,
			"range_max": 8,
			"power": 5,
			"speed": 2,
			"armor": 0,
			"guard": 0,
			"effects": [
				{
					"timing": "during_strike",
					"condition": "opponent_printed_speed_greater",
					"effect_type": "powerup",
					"amount": 5
				}
			],
			"boost": {
				"boost_type": "continuous",
				"force_cost": 0,
				"cancel_cost": -1,
				"display_name": "what if i just don't care",
				"effects": [
					{
						"timing": "during_strike",
						"effect_type": "stun_immunity"
					}
				]
			}
		},
		{
			"id": "custom_opponentprintedspeedless",
			"type": "special",
			"display_name": "Patience? What's that",
			"force_cost": 0,
			"gauge_cost": 0,
			"range_min": 1,
			"range_max": 8,
			"power": 5,
			"speed": 8,
			"armor": 0,
			"guard": 0,
			"effects": [
				{
					"timing": "during_strike",
					"condition": "opponent_printed_speed_less",
					"effect_type": "powerup",
					"amount": 5
				}
			],
			"boost": {
				"boost_type": "continuous",
				"force_cost": 0,
				"cancel_cost": -1,
				"display_name": "what if i just don't care",
				"effects": [
					{
						"timing": "during_strike",
						"effect_type": "stun_immunity"
					}
				]
			}
		},
		{
			"id": "custom_opponentatminrange_plus_namespeedopponentdiscardspeedorreveal",
			"type": "special",
			"display_name": "Up Close and Personal",
			"force_cost": 0,
			"gauge_cost": 0,
			"range_min": 1,
			"range_max": 3,
			"power": 3,
			"speed": 8,
			"armor": 0,
			"guard": 0,
			"effects": [
				{
					"timing": "before",
					"effect_type": "close",
					"amount": 3
				},
				{
					"timing": "hit",
					"condition": "opponent_at_min_range",
					"effect_type": "powerup",
					"amount": 2
				}
			],
			"boost": {
				"boost_type": "immediate",
				"force_cost": 0,
				"cancel_cost": -1,
				"display_name": "I know exactly when you'll strike!",
				"effects": [
					{
						"timing": "immediate",
						"effect_type": "name_speed",
						"target_effect": "opponent_discard_speed_or_reveal"
					}
				]
			}
		},
		{
			"id": "custom_opponentpushedorpulled",
			"type": "special",
			"display_name": "Opponent push or pull checker",
			"force_cost": 0,
			"gauge_cost": 0,
			"range_min": 1,
			"range_max": 8,
			"power": 5,
			"speed": 7,
			"armor": 0,
			"guard": 0,
			"effects": [
				{
					"timing": "hit",
					"effect_type": "push",
					"amount": 8,
					"and":
					{
						"condition": "opponent_was_moved_during_strike",
						"condition_amount": 4,
						"effect_type": "draw",
						"amount": 8
					}
				}
			],
			"boost": {
				"boost_type": "continuous",
				"force_cost": 0,
				"cancel_cost": -1,
				"display_name": "whatever",
				"effects": [
					{
						"timing": "during_strike",
						"effect_type": "stun_immunity"
					}
				]
			}
		},
		{
			"id": "custom_playerpushedorpulled",
			"type": "special",
			"display_name": "Player push or pull checker",
			"force_cost": 0,
			"gauge_cost": 0,
			"range_min": 1,
			"range_max": 8,
			"power": 5,
			"speed": 1,
			"armor": 0,
			"guard": 9,
			"effects": [
				{
					"timing": "hit",
					"condition": "was_moved_during_strike",
					"condition_amount": 3,
					"effect_type": "draw",
					"amount": 8
				}
			],
			"boost": {
				"boost_type": "continuous",
				"force_cost": 0,
				"cancel_cost": -1,
				"display_name": "whatever",
				"effects": [
					{
						"timing": "during_strike",
						"effect_type": "stun_immunity"
					}
				]
			}
		},
		{
			"id": "custom_oncepergamedraw",
			"type": "special",
			"display_name": "You Only Money Once",
			"force_cost": 0,
			"gauge_cost": 0,
			"range_min": 1,
			"range_max": 3,
			"power": 4,
			"speed": 5,
			"armor": 0,
			"guard": 0,
			"effects": [
				{
					"timing": "hit",
					"condition": "has_once_per_game_resource",
					"effect_type": "draw",
					"amount": 7,
					"and": {
						"effect_type": "use_once_per_game_resource"
					}
				}
			],
			"boost": {
				"boost_type": "immediate",
				"force_cost": 0,
				"cancel_cost": -1,
				"display_name": "Rewind Time",
				"effects": [
					{
						"timing": "immediate",
						"effect_type": "regain_once_per_game_resource"
					},
					{
						"timing": "immediate",
						"effect_type": "strike"
					},
				]
			}
		},
		{
			"id": "custom_freeifcrit",
			"type": "special",
			"display_name": "1 dollar or 1 cent",
			"force_cost": 1,
			"force_cost_crit": 0,
			"gauge_cost": 0,
			"range_min": 5,
			"range_max": 5,
			"power": 9,
			"speed": 4,
			"armor": 0,
			"guard": 0,
			"effects": [
			],
			"boost": {
				"boost_type": "immediate",
				"force_cost": 0,
				"cancel_cost": -1,
				"display_name": "A Vision",
				"effects": [
					{
						"timing": "immediate",
						"effect_type": "opponent_discard_range_or_reveal",
						"target_range": "range_from_opponent",
						"amount": 1
					},
				]
			}
		},
		{
			"id": "custom_tooverdrive",
			"type": "special",
			"display_name": "Forceverdrive",
			"force_cost": 0,
			"gauge_cost": 0,
			"range_min": 1,
			"range_max": 2,
			"power": 3,
			"speed": 7,
			"armor": 0,
			"guard": 0,
			"effects": [
				{
					"timing": "hit",
					"effect_type": "force_for_effect",
					"per_force_effect": null,
					"overall_effect": {
						"effect_type": "pass",
						"spent_cards_to_overdrive": true
					},
					"force_max": 4
				}
			],
			"boost": {
				"boost_type": "immediate",
				"force_cost": 0,
				"cancel_cost": -1,
				"display_name": "Gaugeverdrive",
				"effects": [
					{
						"timing": "immediate",
						"effect_type": "gauge_for_effect",
						"per_gauge_effect": null,
						"overall_effect": {
							"effect_type": "pass",
							"spent_cards_to_overdrive": true
						},
						"gauge_max": 3
					}
				]
			}
		},
		{
			"id": "custom_kriseffect",
			"type": "special",
			"display_name": "Delayed Explosions",
			"force_cost": 0,
			"gauge_cost": 0,
			"range_min": 1,
			"range_max": 2,
			"power": 3,
			"speed": 7,
			"armor": 0,
			"guard": 0,
			"effects": [
			],
			"boost": {
				"boost_type": "immediate",
				"force_cost": 0,
				"cancel_cost": -1,
				"display_name": "delature",
				"effects": [
					{
						"timing": "immediate",
						"effect_type": "choose_cards_from_top_deck",
						"look_amount": 5,
						"action_choices": [
							"boost_after_current"
						],
						"can_pass": false,
						"destination_unchosen": "topdeck"
					},
					{
						"timing": "immediate",
						"effect_type": "choose_cards_from_top_deck",
						"look_amount": 4,
						"action_choices": [
							"add_to_hand"
						],
						"can_pass": false,
						"destination_unchosen": "topdeck"
					},
					{
						"timing": "immediate",
						"effect_type": "choose_cards_from_top_deck",
						"look_amount": 3,
						"action_choices": [
							"strike_after_current"
						],
						"can_pass": false,
						"destination_unchosen": "topdeck",
						"shuffle_after": true
					}
				]
			}
		}
	]

func who_am_i():
	return "ryu"

func _start_strike_with_before_effects(effects: Array):
	var attack_id = give_player_specific_card(player1, "standard_normal_focus")
	var attack = game_logic.get_card_database().get_card(attack_id)
	attack.definition = attack.definition.duplicate(true)
	attack.definition["effects"] = effects.duplicate(true)
	attack.definition["speed"] = 8
	var response_id = give_player_specific_card(player2, "standard_normal_focus")
	assert_true(game_logic.do_strike(player1, attack_id, false, -1))
	assert_true(game_logic.do_strike(player2, response_id, false, -1))

func _conditional_before(amount: int = 1) -> Dictionary:
	return {
		"timing": "before",
		"condition": "exceeded",
		"effect_type": "powerup",
		"amount": amount,
		"negative_condition_effect": {"effect_type": "draw", "amount": 1}
	}

func test_conditional_before_choice_consumes_parent_once():
	_start_strike_with_before_effects([
		_conditional_before(),
		{"timing": "before", "effect_type": "powerup", "amount": 2},
		{"timing": "before", "effect_type": "powerup", "amount": 3}
	])
	var initial_hand = player1.hand.size()
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player1.hand.size(), initial_hand + 1)
	assert_eq(game_logic.active_strike.remaining_effect_list.size(), 2)
	assert_eq(game_logic.decision_info.choice[0].effect_type, "powerup")
	assert_eq(game_logic.decision_info.choice[0].amount, 2)
	assert_true(game_logic.do_choice(player1, 0))
	assert_null(game_logic.active_strike)
	assert_eq(player1.hand.size(), initial_hand + 1)

func test_identical_else_branches_consume_the_selected_parent():
	_start_strike_with_before_effects([
		_conditional_before(1), _conditional_before(2), _conditional_before(3)
	])
	var initial_hand = player1.hand.size()
	assert_true(game_logic.do_choice(player1, 1))
	assert_eq(game_logic.active_strike.remaining_effect_list.size(), 2)
	assert_eq(game_logic.active_strike.remaining_effect_list[0].amount, 1)
	assert_eq(game_logic.active_strike.remaining_effect_list[1].amount, 3)
	assert_true(game_logic.do_choice(player1, 0))
	assert_null(game_logic.active_strike)
	assert_eq(player1.hand.size(), initial_hand + 3)

func test_only_runnable_else_branch_is_consumed_before_nested_choice():
	var conditional = _conditional_before()
	conditional["negative_condition_effect"]["and"] = {
		"effect_type": "move_to_any_space", "move_min": 0, "move_max": 1
	}
	_start_strike_with_before_effects([
		conditional,
		{"timing": "before", "condition": "exceeded", "effect_type": "powerup", "amount": 5}
	])
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect)
	assert_eq(game_logic.active_strike.remaining_effect_list.size(), 1)
	var hand_after_draw = player1.hand.size()
	assert_true(game_logic.do_choice(player1, select_space(0)))
	assert_null(game_logic.active_strike)
	assert_eq(player1.hand.size(), hand_after_draw)

func test_conditional_before_met_branch_does_not_run_else():
	var conditional = _conditional_before()
	conditional["condition"] = "not_exceeded"
	_start_strike_with_before_effects([
		conditional,
		{"timing": "before", "effect_type": "powerup", "amount": 2},
		{"timing": "before", "effect_type": "powerup", "amount": 3}
	])
	var initial_hand = player1.hand.size()
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(game_logic.active_strike.remaining_effect_list.size(), 2)
	assert_eq(player1.strike_stat_boosts.power, 1)
	assert_true(game_logic.do_choice(player1, 0))
	assert_null(game_logic.active_strike)
	assert_eq(player1.hand.size(), initial_hand)

func test_extra_attack_else_choice_consumes_only_extra_attack_parent():
	_start_strike_with_before_effects([
		_conditional_before(),
		{"timing": "before", "effect_type": "powerup", "amount": 2},
		{"timing": "before", "effect_type": "powerup", "amount": 3}
	])
	var strike = game_logic.active_strike
	var main_effects = strike.remaining_effect_list.duplicate(true)
	strike.extra_attack_in_progress = true
	strike.extra_attack_data.extra_attack_player = player1
	strike.extra_attack_data.extra_attack_card = strike.initiator_card
	strike.extra_attack_data.extra_attack_state = LocalGame.ExtraAttackState.ExtraAttackState_Before
	strike.extra_attack_data.extra_attack_remaining_effects = main_effects.duplicate(true)
	game_logic.game_state = Enums.GameState.GameState_Strike_Processing
	game_logic.do_remaining_effects(player1, LocalGame.ExtraAttackState.ExtraAttackState_DetermineHit)
	var initial_hand = player1.hand.size()
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(player1.hand.size(), initial_hand + 1)
	assert_eq(strike.extra_attack_data.extra_attack_remaining_effects.size(), 2)
	assert_eq(strike.extra_attack_data.extra_attack_remaining_effects[0].amount, 2)
	assert_eq(strike.remaining_effect_list, main_effects)

##
## Tests start here
##

func test_hidden_effects_resolve_without_replacing_visible_effect_order():
	_start_strike_with_before_effects([
		{"timing": "before", "effect_type": "powerup", "amount": 1, "hide_effect": true},
		{"timing": "before", "effect_type": "powerup", "amount": 2, "hide_effect": true},
		{"timing": "before", "effect_type": "powerup", "amount": 3},
		{"timing": "before", "effect_type": "powerup", "amount": 4}
	])
	assert_eq(player1.strike_stat_boosts.power, 3)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseSimultaneousEffect)
	assert_eq(game_logic.decision_info.choice.size(), 2)
	for effect in game_logic.decision_info.choice:
		assert_false(GameStrings.get_effect_text(effect, false, true).is_empty())
	assert_true(game_logic.do_choice(player1, 0))
	assert_null(game_logic.active_strike)

func test_hidden_effects_only_resolve_without_effect_order_decision():
	var initial_hand = player1.hand.size()
	_start_strike_with_before_effects([
		{"timing": "before", "effect_type": "draw", "amount": 1, "hide_effect": true},
		{"timing": "before", "effect_type": "draw", "amount": 1, "hide_effect": true}
	])
	assert_null(game_logic.active_strike)
	assert_eq(player1.hand.size(), initial_hand + 2)

func test_hidden_nested_choice_still_requires_player_input():
	_start_strike_with_before_effects([
		{
			"timing": "before", "effect_type": "choice", "hide_effect": true,
			"choice": [
				{"effect_type": "powerup", "amount": 1},
				{"effect_type": "pass"}
			]
		},
		{"timing": "before", "effect_type": "powerup", "amount": 2},
		{"timing": "before", "effect_type": "powerup", "amount": 3}
	])
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(game_logic.decision_info.choice[1].effect_type, "pass")
	assert_true(game_logic.do_choice(player1, 1))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseSimultaneousEffect)
	assert_eq(game_logic.decision_info.choice.size(), 2)
	assert_true(game_logic.do_choice(player1, 0))
	assert_null(game_logic.active_strike)

func test_hidden_otherwise_branch_resolves_once_before_visible_choices():
	var initial_hand = player1.hand.size()
	var conditional = _conditional_before()
	conditional["hide_effect"] = true
	_start_strike_with_before_effects([
		conditional,
		{"timing": "before", "effect_type": "powerup", "amount": 2},
		{"timing": "before", "effect_type": "powerup", "amount": 3}
	])
	assert_eq(player1.hand.size(), initial_hand + 1)
	assert_eq(game_logic.decision_info.choice.size(), 2)
	assert_true(game_logic.do_choice(player1, 0))
	assert_null(game_logic.active_strike)
	assert_eq(player1.hand.size(), initial_hand + 1)

func test_hidden_unmet_condition_is_rechecked_after_visible_effect():
	var initial_hand = player1.hand.size()
	_start_strike_with_before_effects([
		{
			"timing": "before", "effect_type": "powerup", "amount": 4,
			"condition": "min_cards_in_hand", "condition_amount": initial_hand + 1,
			"hide_effect": true
		},
		{"timing": "before", "effect_type": "draw", "amount": 1},
		{"timing": "before", "effect_type": "speedup", "amount": 1}
	])
	assert_eq(game_logic.decision_info.choice.size(), 2)
	assert_true(game_logic.do_choice(player1, 0))
	assert_null(game_logic.active_strike)
	assert_eq(player1.hand.size(), initial_hand + 1)
	validate_has_event(game_logic.get_latest_events(),
		Enums.EventType.EventType_Strike_PowerUp, player1, 4)

func test_unmet_priority_effect_does_not_discard_runnable_effects():
	var initial_hand = player1.hand.size()
	_start_strike_with_before_effects([
		{
			"timing": "before", "effect_type": "powerup", "amount": 4,
			"condition": "min_cards_in_hand", "condition_amount": 100,
			"resolve_before_simultaneous_effects": true
		},
		{"timing": "before", "effect_type": "draw", "amount": 1},
		{"timing": "before", "effect_type": "speedup", "amount": 1}
	])
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseSimultaneousEffect)
	if not game_logic.active_strike:
		return
	assert_eq(game_logic.decision_info.choice.size(), 2)
	assert_true(game_logic.do_choice(player1, 0))
	assert_null(game_logic.active_strike)
	assert_eq(player1.hand.size(), initial_hand + 1)

func test_internal_cleanup_unblocks_movement_without_blank_choices():
	player2.cannot_move = true
	player2.cannot_advance_or_close = true
	player2.cannot_move_past_opponent = true
	_start_strike_with_before_effects([
		{"timing": "cleanup", "effect_type": "remove_block_opponent_move"},
		{"timing": "cleanup", "effect_type": "remove_block_opponent_advance_close"},
		{"timing": "cleanup", "effect_type": "remove_opponent_cant_move_past"}
	])
	assert_null(game_logic.active_strike)
	assert_false(player2.cannot_move)
	assert_false(player2.cannot_advance_or_close)
	assert_false(player2.cannot_move_past_opponent)

func test_hidden_counter_cleanup_waits_for_visible_payment_choice():
	player1.bonus_armor_counters = 2
	player1.bonus_guard_counters = 2
	_start_strike_with_before_effects([
		{
			"timing": "cleanup", "effect_type": "reset_bonus_armor_counters", "hide_effect": true,
			"and": {"effect_type": "reset_bonus_guard_counters", "hide_effect": true}
		},
		{
			"timing": "cleanup", "effect_type": "choice",
			"choice": [
				{
					"effect_type": "add_bonus_armor_counters", "amount": 1,
					"and": {"effect_type": "add_bonus_guard_counters", "amount": 1}
				},
				{"effect_type": "pass"}
			]
		}
	])
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	assert_eq(player1.bonus_armor_counters, 2)
	assert_eq(player1.bonus_guard_counters, 2)
	assert_true(game_logic.do_choice(player1, 0))
	assert_null(game_logic.active_strike)
	assert_eq(player1.bonus_armor_counters, 0)
	assert_eq(player1.bonus_guard_counters, 0)

func test_hidden_extra_attack_effect_keeps_main_effect_queue():
	_start_strike_with_before_effects([
		{"timing": "before", "effect_type": "powerup", "amount": 1},
		{"timing": "before", "effect_type": "powerup", "amount": 2}
	])
	var strike = game_logic.active_strike
	var main_effects = strike.remaining_effect_list.duplicate(true)
	strike.extra_attack_in_progress = true
	strike.extra_attack_data.extra_attack_player = player1
	strike.extra_attack_data.extra_attack_card = strike.initiator_card
	strike.extra_attack_data.extra_attack_state = LocalGame.ExtraAttackState.ExtraAttackState_Before
	var hidden_effect = main_effects[0].duplicate(true)
	hidden_effect["hide_effect"] = true
	strike.extra_attack_data.extra_attack_remaining_effects = [hidden_effect] + main_effects.duplicate(true)
	game_logic.game_state = Enums.GameState.GameState_Strike_Processing
	game_logic.do_remaining_effects(player1, LocalGame.ExtraAttackState.ExtraAttackState_DetermineHit)
	assert_eq(player1.strike_stat_boosts.power, 1)
	assert_eq(game_logic.decision_info.choice.size(), 2)
	assert_eq(strike.extra_attack_data.extra_attack_remaining_effects.size(), 2)
	assert_eq(strike.remaining_effect_list, main_effects)

# Testing adding opponent's attack to gauge
func test_custom_opponent_strike_to_gauge():
	position_players(player1, 3, player2, 4)
	player1.discard_hand()
	player2.discard_hand()

	var strike_cards = execute_strike(player1, player2, "custom_stealgauge", "standard_normal_cross")

	validate_positions(player1, 3, player2, 4)
	validate_life(player1, 30, player2, 29)
	assert_true(player1.is_card_in_gauge(strike_cards[0]))
	assert_true(player1.is_card_in_gauge(strike_cards[1]))
	advance_turn(player2)

	# should return to original awner's discard
	game_logic.do_change(player1, [strike_cards[0], strike_cards[1]], false)
	assert_true(player1.is_card_in_discards(strike_cards[0]))
	assert_true(player2.is_card_in_discards(strike_cards[1]))
	advance_turn(player2)

# Testing conditioning on not pulling a full amount
func test_custom_not_full_pull_fail():
	position_players(player1, 1, player2, 4)

	execute_strike(player1, player2, "custom_notfullpull", "standard_normal_sweep")

	validate_positions(player1, 1, player2, 3)
	validate_life(player1, 24, player2, 28)
	advance_turn(player2)

func test_custom_not_full_pull_succeed():
	position_players(player1, 1, player2, 2)

	execute_strike(player1, player2, "custom_notfullpull", "standard_normal_sweep")

	validate_positions(player1, 1, player2, 2)
	validate_life(player1, 30, player2, 23)
	advance_turn(player2)

# Testing storage of the number of spaces a close effect doesn't move
func test_custom_bonus_per_not_closed_no_power():
	position_players(player1, 2, player2, 7)

	var boost_id = give_player_specific_card(player1, "custom_stealgauge")
	game_logic.do_boost(player1, boost_id)

	execute_strike(player1, player2, "standard_normal_grasp", "standard_normal_sweep",
		false, false, [0])

	validate_positions(player1, 6, player2, 8)
	validate_life(player1, 24, player2, 27)
	advance_turn(player2)

func test_custom_bonus_per_not_closed_some_power():
	position_players(player1, 4, player2, 7)

	var boost_id = give_player_specific_card(player1, "custom_stealgauge")
	game_logic.do_boost(player1, boost_id)

	execute_strike(player1, player2, "standard_normal_grasp", "standard_normal_sweep",
		false, false, [0])

	validate_positions(player1, 6, player2, 8)
	validate_life(player1, 24, player2, 25)
	advance_turn(player2)

func test_custom_bonus_per_not_closed_big_power():
	position_players(player1, 6, player2, 7)

	var boost_id = give_player_specific_card(player1, "custom_stealgauge")
	game_logic.do_boost(player1, boost_id)

	execute_strike(player1, player2, "standard_normal_grasp", "standard_normal_sweep",
		false, false, [0])

	validate_positions(player1, 6, player2, 8)
	validate_life(player1, 30, player2, 23)
	advance_turn(player2)

# Testing boosts not adding themselves to gauge immediately
func test_custom_boost_add_to_gauge_at_strike_end():
	position_players(player1, 3, player2, 6)

	var boost_id = give_player_specific_card(player1, "custom_notfullpull")
	game_logic.do_boost(player1, boost_id)

	execute_strike(player1, player2, "standard_normal_assault", "standard_normal_focus",
		false, false, [0])

	validate_positions(player1, 5, player2, 6)
	validate_life(player1, 29, player2, 25)
	assert_true(player1.is_card_in_gauge(boost_id))
	advance_turn(player1)

# Testing gauge cost reduction per boosts in play
func test_custom_gauge_reduction_per_boost_in_play():
	position_players(player1, 3, player2, 6)

	# Give 3 gauge to Player 1.
	var gauge_ids = give_gauge(player1, 2)
	# Player 1 boosts Fierce
	var boost_id = give_player_specific_card (player1, "standard_normal_grasp")
	game_logic.do_boost(player1, boost_id)

	# Player 1 strikes with an ultra that reducces cost by boost in play - should only need to pay 2 gauge here despite 3 gauge cost.
	execute_strike (player2, player1, "standard_normal_assault", "custom_reducecostperboost", false, false, [], [[], gauge_ids])

	advance_turn(player1)

# Testing powerup per armor
func test_custom_powerup_per_armor():
	position_players(player1, 3, player2, 6)

	# Player 1 strikes with an special with 2 power, 3 armor, and before: powerup_per_armor, amount: 1.
	execute_strike (player1, player2, "custom_powerupperarmor", "standard_normal_dive", false, false, [], [])

	# Validate that player 1 is still at max life, and player 2 is at 25.
	validate_life(player1, 30, player2, 25)

# Testing powerup per speed
func test_custom_powerup_per_speed():
	position_players(player1, 3, player2, 6)

	# Player 1 strikes with an special with 2 power, 8 speed, and before: powerup_per_speed, amount: 1.
	execute_strike (player1, player2, "custom_powerupperspeed", "standard_normal_dive", false, false, [], [])

	# Validate that player 1 is still at max life, and player 2 is at 20.
	validate_life(player1, 30, player2, 20)

# Testing powerup per power
func test_custom_powerup_per_power():
	position_players(player1, 3, player2, 6)

	# Player 1 strikes with an special with 5 power and before: powerup_per_power, amount: 1.
	execute_strike (player1, player2, "custom_powerupperpower", "standard_normal_dive", false, false, [], [])

	# Validate that player 1 is still at max life, and player 2 is at 20.
	validate_life(player1, 30, player2, 20)

# Testing opponent printed speed greater
func test_custom_opponent_printed_speed_greater():
	position_players(player1, 3, player2, 6)

	# Player 1 strikes with an special with 5 power, 2 speed, and +5 power if opponent's attack has greater printed speed.
	# Player 2 responds with a printed Speed 7 Grasp.
	execute_strike (player1, player2, "custom_opponentprintedspeedgreater", "standard_normal_grasp", false, false, [], [])

	# Validate that player 1 is still at max life, and player 2 is at 20.
	validate_life(player1, 30, player2, 20)

# Testing opponent printed speed less
func test_custom_opponent_printed_speed_less():
	position_players(player1, 3, player2, 6)

	# Player 1 strikes with an special with 5 power, 8 speed, and +5 power if opponent's attack has less printed speed.
	# Player 2 responds with a printed Speed 7 Grasp.
	execute_strike (player1, player2, "custom_opponentprintedspeedless", "standard_normal_grasp", false, false, [], [])

	# Validate that player 1 is still at max life, and player 2 is at 20.
	validate_life(player1, 30, player2, 20)

# Testing opponent at min range
func test_custom_opponent_at_min_range():
	position_players(player1, 3, player2, 6)

	# Player 1 strikes with an special with 1-3 range, 3 power, before: close 3, and +2 power if opponent is at minimum range.
	# Player 2 responds with a printed Speed 7 Grasp.
	execute_strike (player1, player2, "custom_opponentatminrange_plus_namespeedopponentdiscardspeedorreveal", "standard_normal_grasp", false, false, [], [])

	# Validate that player 1 is still at max life, and player 2 is at 25.
	validate_life(player1, 30, player2, 25)

# Testing condition that checks if opponent / player was pushed or pulled by the other player.
func test_custom_condition_opponent_was_moved():
	position_players(player1, 1, player2, 4)

	# P1 strikes with an attack that pushes 8.  If P2 was pushed, P1 draws 8.
	# P2 responds with an attack that draws 8 if they were pushed.
	execute_strike(player1, player2, "custom_opponentpushedorpulled", "custom_playerpushedorpulled")

	validate_positions(player1, 1, player2, 9)
	assert_eq(player1.hand.size(), 13)
	assert_eq(player2.hand.size(), 14)
	validate_life(player1, 25, player2, 25)

## Testing of name_speed + opponent_discard_speed_or_reveal boost:
## The below 6 tests are modified from the Zangief tests for his Intimidate boost.
##   Name a speed; the opponent must discard a card with that that speed or reveal a hand that
##   doesn't contain such a card.
## (Reminder: both players are Ryu here.

func test_name_speed_opponent_discard_speed_boost_reveal():
	position_players(player1, 4, player2, 7)
	var card_id = give_player_specific_card(player1, "custom_opponentatminrange_plus_namespeedopponentdiscardspeedorreveal")
	assert_true(game_logic.do_boost(player1, card_id))

	# Name the speed 0-9 are real speeds, 10 is a valid choice but doesn't exist, 11 is X
	assert_true(game_logic.do_choice(player1, 11)) # Ryu has no X cards.
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_RevealHand, player2)
	advance_turn(player2)

func test_name_speed_opponent_discard_speed_boost_reveal2():
	position_players(player1, 4, player2, 7)
	var card_id = give_player_specific_card(player1, "custom_opponentatminrange_plus_namespeedopponentdiscardspeedorreveal")
	assert_true(game_logic.do_boost(player1, card_id))

	# Name the speed 0-9 are real speeds, 10 is a valid choice but doesn't exist, 11 is X
	assert_true(game_logic.do_choice(player1, 8)) # Ryu has no 8
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_RevealHand, player2)
	advance_turn(player2)

func test_name_speed_opponent_discard_speed_boost_discard_X():
	position_players(player1, 4, player2, 7)
	var boost_id = give_player_specific_card(player1, "custom_opponentatminrange_plus_namespeedopponentdiscardspeedorreveal")
	assert_true(game_logic.do_boost(player1, boost_id))
	player2.discard_hand()
	var inksplash_id = give_player_specific_card(player2, "seijun_inksplash")
	# Speed X; Ryu calls "X" as the speed
	assert_true(game_logic.do_choice(player1, 11))
	assert_true(game_logic.do_choose_to_discard(player2, [inksplash_id]))
	advance_turn(player2)

func test_name_speed_opponent_discard_speed_boost_discard_1_with_X_eval():
	position_players(player1, 4, player2, 7)
	var boost_id = give_player_specific_card(player1, "custom_opponentatminrange_plus_namespeedopponentdiscardspeedorreveal")
	assert_true(game_logic.do_boost(player1, boost_id))

	player2.discard_hand()
	var inksplash_id = give_player_specific_card(player2, "seijun_inksplash")
	# Speed where X is the amount of cards the player has in hand; Ryu calls "1"
	assert_true(game_logic.do_choice(player1, 1))
	assert_true(game_logic.do_choose_to_discard(player2, [inksplash_id]))
	advance_turn(player2)

func test_name_speed_opponent_discard_speed_boost_discard_2_with_X_eval_fails():
	position_players(player1, 4, player2, 7)
	var boost_id = give_player_specific_card(player1, "custom_opponentatminrange_plus_namespeedopponentdiscardspeedorreveal")
	assert_true(game_logic.do_boost(player1, boost_id))
	player2.discard_hand()
	give_player_specific_card(player2, "seijun_inksplash")
	# Speed where X is the amount of cards the player has in hand
	# Ryu calls "2", which whiffs because the other player only has 1 card in hand
	assert_true(game_logic.do_choice(player1, 2))
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_RevealHand, player2)
	advance_turn(player2)

func test_name_speed_opponent_discard_speed_boost_discard_3():
	position_players(player1, 4, player2, 7)
	var boost_id = give_player_specific_card(player1, "custom_opponentatminrange_plus_namespeedopponentdiscardspeedorreveal")
	assert_true(game_logic.do_boost(player1, boost_id))

	player2.discard_hand()
	var spike_id = give_player_specific_card(player2, "standard_normal_spike")
	# Name the speed 0-9 are real speeds, 10 is a valid choice but doesn't exist, 11 is X
	assert_true(game_logic.do_choice(player1, 3))
	assert_true(game_logic.do_choose_to_discard(player2, [spike_id]))
	advance_turn(player2)

# Testing once-per-game effects
func test_custom_once_per_game_effect():
	position_players(player1, 4, player2, 7)
	var initial_cards = len(player1.hand)

	# first time used - draw 7
	execute_strike(player1, player2, "custom_oncepergamedraw", "standard_normal_assault")

	validate_life(player1, 30, player2, 26)
	assert_eq(len(player1.hand), initial_cards + 7)
	advance_turn(player2)
	
	# second time used - do not draw
	execute_strike(player1, player2, "custom_oncepergamedraw", "standard_normal_assault",
		false, false, [[]])

	validate_life(player1, 30, player2, 22)
	assert_eq(len(player1.hand), initial_cards + 7)
	advance_turn(player2)
	
func test_custom_once_per_game_effect_refresh():
	position_players(player1, 4, player2, 7)
	var initial_cards = len(player1.hand)

	# first time used - draw 7
	execute_strike(player1, player2, "custom_oncepergamedraw", "standard_normal_assault")

	validate_life(player1, 30, player2, 26)
	assert_eq(len(player1.hand), initial_cards + 7)
	advance_turn(player2)
	
	# second time used - do not draw
	var boost_id = give_player_specific_card(player1, "custom_oncepergamedraw")
	assert_true(game_logic.do_boost(player1, boost_id))
	execute_strike(player1, player2, "custom_oncepergamedraw", "standard_normal_assault",
		false, false, [[]])

	validate_life(player1, 30, player2, 22)
	assert_eq(len(player1.hand), initial_cards + 14)
	advance_turn(player2)

# Testing force special discount on crit
func test_custom_force_special_crit_discount():
	position_players(player1, 3, player2, 8)
	var gauge_ids = give_gauge(player1, 1)

	execute_strike(player1, player2, "custom_freeifcrit", "standard_normal_sweep",
		false, false, [gauge_ids])

	validate_life(player1, 30, player2, 21)
	advance_turn(player2)

func test_custom_force_special_crit_discount_invalidate():
	position_players(player1, 3, player2, 8)
	var gauge_ids = give_gauge(player1, 1)
	
	var strike_card = give_player_specific_card(player1, "standard_normal_sweep")
	player1.move_card_from_hand_to_deck(strike_card)
	var invalidatable_card = give_player_specific_card(player1, "custom_freeifcrit")
	player1.move_card_from_hand_to_deck(invalidatable_card)
	
	var response_card = give_player_specific_card(player2, "standard_normal_assault")

	game_logic.do_strike(player1, -1, true, -1) # wild swing
	game_logic.do_gauge_for_effect(player1, gauge_ids) # spend for crit
	game_logic.do_strike(player2, response_card, false, -1) # respond with assault
	game_logic.do_pay_strike_cost(player1, [], true) # wild swing into special; should be able to invalidate

	validate_life(player1, 30, player2, 24)
	validate_positions(player1, 3, player2, 6)
	assert_true(player1.is_card_in_discards(invalidatable_card))
	advance_turn(player2)

# Testing current-range parry
func test_custom_current_range_parry_success():
	position_players(player1, 3, player2, 5)
	
	player2.discard_hand()
	var target_id = give_player_specific_card(player2, "standard_normal_sweep")
	
	var boost_id = give_player_specific_card(player1, "custom_freeifcrit")
	assert_true(game_logic.do_boost(player1, boost_id))
	assert_true(game_logic.do_choose_to_discard(player2, [target_id]))

	assert_true(player2.is_card_in_discards(target_id))
	advance_turn(player2)

func test_custom_current_range_parry_fail():
	position_players(player1, 3, player2, 7)
	
	player2.discard_hand()
	var target_id = give_player_specific_card(player2, "standard_normal_sweep")
	
	var boost_id = give_player_specific_card(player1, "custom_freeifcrit")
	assert_true(game_logic.do_boost(player1, boost_id))

	assert_true(player2.is_card_in_hand(target_id))
	assert_true("standard_normal_sweep" in player2.get_public_hand_info()["known"])
	advance_turn(player2)
	
# Testing force/gauge for overdrive
func test_custom_force_to_overdrive():
	position_players(player1, 3, player2, 5)
	
	var force_ids = get_cards_from_hand(player1, 4)
	
	execute_strike(player1, player2, "custom_tooverdrive", "standard_normal_assault",
		false, false, [force_ids])
	
	for card_id in force_ids:
		assert_true(player1.is_card_in_overdrive(card_id))
		
	validate_life(player1, 30, player2, 27)
	validate_positions(player1, 3, player2, 5)
	advance_turn(player2)
	
func test_custom_gauge_to_overdrive():
	position_players(player1, 3, player2, 5)
	
	var gauge_ids = give_gauge(player1, 3)
	var boost_id = give_player_specific_card(player1, "custom_tooverdrive")
	
	assert_true(game_logic.do_boost(player1, boost_id))
	assert_true(game_logic.do_gauge_for_effect(player1, gauge_ids))
	
	for card_id in gauge_ids:
		assert_true(player1.is_card_in_overdrive(card_id))
		
	advance_turn(player2)

func test_card_data_manager_ignores_note_only_custom_entries():
	CardDataManager.load_custom_cards([
		{"NOTE": "BROKEN ENTRY"},
		{
			"id": "custom_valid_after_note",
			"type": "special",
			"display_name": "Valid After Note",
			"force_cost": 0,
			"gauge_cost": 0,
			"range_min": 1,
			"range_max": 1,
			"power": 1,
			"speed": 1,
			"armor": 0,
			"guard": 0,
			"effects": [],
			"boost": {}
		}
	])

	assert_eq(CardDataManager.get_card("custom_valid_after_note")["display_name"], "Valid After Note")

# Testing delayed boosting and striking from topdeck
func test_custom_topdeck_after_current():
	position_players(player1, 1, player2, 7)
	
	var response_id = give_player_specific_card(player2, "standard_normal_grasp")
	
	var boost_id = give_player_specific_card(player1, "custom_kriseffect")
	var topdeck_ids = []
	for topdeck_card in [
			"standard_normal_grasp",
			"standard_normal_cross",
			"standard_normal_assault",
			"standard_normal_sweep",
			"standard_normal_block"]:
		topdeck_ids.append(give_player_specific_card(player1, topdeck_card))
		player1.move_card_from_hand_to_deck(topdeck_ids[-1])
	
	assert_true(game_logic.do_boost(player1, boost_id))
	# Queue cross to boost
	assert_true(game_logic.do_choose_from_topdeck(player1, topdeck_ids[1], "boost_after_current"))
	# Add assault to hand
	assert_true(game_logic.do_choose_from_topdeck(player1, topdeck_ids[2], "add_to_hand"))
	# Queue sweep to strike
	assert_true(game_logic.do_choose_from_topdeck(player1, topdeck_ids[3], "strike_after_current"))
	# Use cross boost to advance 3
	assert_true(game_logic.do_choice(player1, 2))
	
	# Strike initiated with sweep, player 2 responds
	assert_true(game_logic.do_strike(player2, response_id, false, -1))
		
	validate_life(player1, 30, player2, 24)
	validate_positions(player1, 4, player2, 7)
	assert_true(player1.is_card_in_deck(topdeck_ids[0]))
	assert_true(player1.is_card_in_discards(topdeck_ids[1]))
	assert_true(player1.is_card_in_hand(topdeck_ids[2]))
	assert_true(player1.is_card_in_gauge(topdeck_ids[3]))
	assert_true(player1.is_card_in_deck(topdeck_ids[4]))
	advance_turn(player2)
