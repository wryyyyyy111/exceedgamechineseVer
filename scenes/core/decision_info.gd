class_name DecisionInfo
extends Node

var player : Enums.PlayerId
var type : Enums.DecisionType
var effect_type
var effect
var choice
var choice_card_id : int
var limitation
var destination
var amount : int
var amount_min : int
var cost : int
var valid_zones : Array
var strike_after : bool
var action
var can_pass : bool
var bonus_effect
var source
var ignore_costs : bool
var extra_info
var multiple_choice_amount : int
# Heidi 开关扇: boost_multiple + return_to_hand — the boosted card resolves its
# effects and then returns to hand instead of being discarded.
var return_boost_to_hand : bool
# When true, a ChooseFromTopDeck decision accepts a whole set of cards
# (0..amount) instead of exactly one. Used by Heidi's 匕首风暴·三倍插入.
var select_multiple : bool
var source_player_id : int = -1

func clear():
	player = Enums.PlayerId.PlayerId_Unassigned
	type = Enums.DecisionType.DecisionType_None
	effect_type = null
	effect = null
	choice = null
	choice_card_id = -1
	limitation = null
	destination = null
	amount = -1
	amount_min = 999
	cost = -1
	valid_zones = []
	strike_after = false
	action = null
	can_pass = false
	bonus_effect = null
	source = null
	ignore_costs = false
	extra_info = null
	multiple_choice_amount = 0
	return_boost_to_hand = false
	select_multiple = false
	source_player_id = -1
