extends Node

const CardHighlightColor = "#7DF9FF" # Light blue
const NormalCardNamesCN = {
	"grasp": "投技",
	"cross": "游击",
	"assault": "突袭",
	"dive": "飞踢",
	"spike": "刺拳",
	"sweep": "横扫",
	"focus": "专注",
	"block": "格挡",
}

func get_speed_description(card_definition) -> String:
	if not card_definition:
		return ""

	var speed = card_definition.get("speed")
	var card_type = card_definition.get("type", "")
	if speed == null or card_type == "":
		return ""

	var speed_prefix = ""
	match card_type:
		"normal":
			speed_prefix = "普"
		"special":
			speed_prefix = "特"
		"ultra":
			speed_prefix = "必"
		_:
			return ""

	return "（%s%s速）" % [speed_prefix, str(speed)]

func get_display_name_with_speed(card_definition) -> String:
	if not card_definition:
		return "MISSING CARD"

	var display_name = card_definition.get("display_name", "MISSING CARD")
	display_name = NormalCardNamesCN.get(display_name.to_lower(), display_name)
	return "%s%s" % [display_name, get_speed_description(card_definition)]

class EffectSummary:
	var effect
	var min_value = null
	var max_value = null

func get_choice_summary(choice, card_name_source : String):
	var summary_text = ""
	var effect_summaries = []
	for effect in choice:
		var current_summary = null
		for effect_summary in effect_summaries:
			if effect_summary.effect['effect_type'] == effect['effect_type']:
				current_summary = effect_summary
				break
		if not current_summary:
			current_summary = EffectSummary.new()
			current_summary.effect = effect
			effect_summaries.append(current_summary)

		if 'amount' in effect and not 'UI_skip_summary' in effect:
			if current_summary.min_value == null:
				current_summary.min_value = effect['amount']
				current_summary.max_value = effect['amount']
			else:
				if effect['amount'] < current_summary.min_value:
					current_summary.min_value = effect['amount']
				if effect['amount'] > current_summary.max_value:
					current_summary.max_value = effect['amount']


	for i in range(len(effect_summaries)):
		var effect_summary = effect_summaries[i]
		if i > 0:
			summary_text += " 或 "
		if effect_summary.min_value != null and effect_summary.effect['effect_type'] not in [StrikeEffects.SpendLife, StrikeEffects.MoveRandomCards]:
			if effect_summary.effect['effect_type'] in [StrikeEffects.DiscardRandom, StrikeEffects.OpponentDiscardRandom]:
				if effect_summary.min_value == effect_summary.max_value:
					summary_text += "对手随机弃置%s张牌" % str(effect_summary.min_value)
				else:
					summary_text += "对手随机弃置%s-%s张牌" % [str(effect_summary.min_value), str(effect_summary.max_value)]
				continue
			if effect_summary.min_value == effect_summary.max_value:
				if str(effect_summary.min_value) == "strike_x":
					effect_summary.min_value = "X"
				elif str(effect_summary.min_value) == "TOTAL_POWER":
					effect_summary.min_value = "你的总威力"
				summary_text += get_effect_type_heading(effect_summary.effect) + str(effect_summary.min_value)
			else:
				summary_text += get_effect_type_heading(effect_summary.effect) + str(effect_summary.min_value) + "-" + str(effect_summary.max_value)
		else:
			# No amount, so just use the full effect text
			summary_text += get_effect_type_text(effect_summary.effect, card_name_source)
		if "and" in effect_summary.effect:
			summary_text += "; " + get_effect_text(effect_summary.effect["and"], false, false, false, card_name_source)
	return summary_text

func get_force_for_effect_summary(effect, card_name_source : String) -> String:
	var effect_str = ""
	var force_limit = effect['force_max']
	if "per_force_effect" in effect and effect['per_force_effect'] != null:
		var per_effect = effect['per_force_effect']
		if 'combine_multiple_into_one' in per_effect and per_effect['combine_multiple_into_one']:
			effect_str += "花费至多 %s 点能量。%s" % [str(force_limit), get_effect_text(per_effect, false, true, true, card_name_source)]
		else:
			var each_every_str = "每张"
			if 'force_effect_interval' in effect:
				each_every_str = "每 %s 张" % effect['force_effect_interval']
			effect_str += "花费至多 %s 点能量。每 %s，%s" % [str(force_limit), each_every_str, get_effect_text(effect['per_force_effect'], false, true, true, card_name_source)]
	elif 'overall_effect' in effect and effect['overall_effect'] != null:
		effect_str += "你可以花费 %s 点能量来%s" % [str(force_limit), get_effect_text(effect['overall_effect'], false, true, true, card_name_source)]
	return effect_str

func get_gauge_for_effect_summary(effect, card_name_source : String) -> String:
	var required = 'required' in effect and effect['required']
	var maymust_str = "可以"
	if required:
		maymust_str = "必须"
	var effect_str = ""
	var to_hand = 'spent_cards_to_hand' in effect and effect['spent_cards_to_hand']
	var gauge_limit = effect['gauge_max']
	var gauge_card_str = "怒"
	if 'require_specific_card_name' in effect:
		gauge_card_str = "怒中的 %s 的复制" % effect['require_specific_card_name']
	elif 'valid_card_types' in effect:
		gauge_card_str = "怒中的 %s" % '/'.join(effect['valid_card_types'])

	if "per_gauge_effect" in effect and effect['per_gauge_effect'] != null:
		if to_hand:
			effect_str += "将至多 %s 张%s返回手牌。每张，%s" % [str(gauge_limit), gauge_card_str, get_effect_text(effect['per_gauge_effect'], false, true, true, card_name_source)]
		else:
			effect_str += "花费至多 %s 张%s。每张，%s" % [str(gauge_limit), gauge_card_str, get_effect_text(effect['per_gauge_effect'], false, true, true, card_name_source)]
	elif 'overall_effect' in effect and effect['overall_effect'] != null:
		if to_hand:
			effect_str += "你%s将 %s 张%s返回手牌来%s" % [maymust_str, str(gauge_limit), gauge_card_str, get_effect_text(effect['overall_effect'], false, true, true, card_name_source)]
		else:
			effect_str += "你%s花费 %s 张%s来%s" % [maymust_str, str(gauge_limit), gauge_card_str, get_effect_text(effect['overall_effect'], false, true, true, card_name_source)]
	return effect_str

func get_timing_text(timing):
	var text = ""
	match timing:
		"action":
			text += "[b]行动：[/b] "
		"opponent_action":
			text += "[b]对手行动：[/b] "
		"after":
			text += "[b]后置：[/b] "
		"both_players_after":
			text += "[b]双方后置：[/b] "
		"both_players_before":
			text += "[b]双方前置：[/b] "
		"before":
			text += "[b]前置：[/b] "
		"cleanup":
			text += "[b]整理阶段：[/b] "
		"discarded":
			text += ""
		"during_strike":
			text += ""
		"end_of_turn":
			text += "在你的回合结束时："
		"hit":
			text += "[b]击中：[/b] "
		"immediate":
			text += ""
		"now":
			text += "[b]立即：[/b] "
		"on_advance_or_close":
			text += "当你前进或逼近时，"
		"on_cancel":
			text += "当你取消时，"
		"on_any_boost":
			text += "结算完加成后，"
		"on_continuous_boost":
			text += "结算完持续性加成后，"
		"before_boost_effects":
			text += "使用加成时（效果结算前），"
		"on_initiate_strike":
			text += "当你发起一场战斗时，"
		"on_reveal":
			text += ""
		"on_seal":
			text += ""
		"start_of_next_turn":
			text += "在你的下个回合开始时："
		"opponent_start_of_next_turn":
			text += "在对手回合开始时："
		"set_strike":
			text += "当你设置一场战斗时，"
		"opponent_set_strike":
			text += ""
		"opponent_moved_past":
			text += "若对手越过你，"
		"when_hit":
			text += "当被击中时，"
		"on_stop_on_space":
			text += "当加成在战斗中进入场上时，停止移动；"
		"on_spend_life":
			text += "当你花费生命时，"
		"on_stunned":
			text += "当你击晕对手时，"
		"never":
			text += ""
		"on_retreat_cost":
			text += ""
		"on_pay_force_with_gauge":
			text += ""
		_:
			text += "缺失时机"
	return text

func get_condition_text(effect, amount, amount2, detail):
	var condition = effect['condition']
	var text = ""
	match condition:
		"advanced_through":
			text += "若前进越过对手，"
		"not_advanced_through":
			text += "若未前进越过对手，"
		"not_advanced_through_buddy":
			text += "若未前进穿过%s，" % detail
		"any_buddy_in_play":
			text += "若%s在场，" % detail
		"any_buddy_in_opponent_space":
			text += "若对手位于%s上，" % detail
		"any_buddy_adjacent_opponent_space":
			text += "若对手与%s相邻，" % detail
		"any_buddy_in_or_adjacent_opponent_space":
			text += "若对手位于%s上或与之相邻，" % detail
		"not_any_buddy_in_opponent_space":
			text += "若%s不在对手所在格，" % detail
		"at_edge_of_arena":
			text += "若在场地边缘，"
		"in_center_three_spaces":
			text += "若位于场地中央三格，"
		"opponent_in_center_three_spaces":
			text += "若对手位于场地中央三格，"
		"attack_still_in_play":
			text += "若你的攻击仍在场，"
		"attacks_match_printed_speed":
			text += "若你攻击的印刷速度与对手攻击的印刷速度相同，"
		"opponent_printed_speed_greater":
			text += "若对手攻击的印刷速度大于你攻击的印刷速度，"
		"opponent_printed_speed_less":
			text += "若对手攻击的印刷速度小于你攻击的印刷速度，"
		"boost_in_play":
			text += "若有加成在场，"
		"has_continuous_boost":
			text += "若你有持续加成在场，"
		"has_continuous_boost_attack":
			text += "若你有持续加成在场并以特殊技或必杀技发起战斗，"
		"min_continuous_boosts_attack":
			text += "若你有%s个或更多持续加成在场并以特殊技或必杀技发起战斗，"
		"min_continuous_boosts":
			text += "若你有%s个或更多持续加成在场，"
		"pooky_gambling_normals":
			text += "若本战斗揭示了Gambling? I'm In!，"
		"min_gauge":
			text += "若你的怒气区有%s张或更多牌，"
		"canceled_this_turn":
			text += "若本回合已取消过，"
		"copy_of_attack_in_zones":
			var zones = "/".join(effect['condition_zones'])
			text += "若攻击的复制位于%s，" % zones
		"discarded_matches_attack_speed":
			text += "若弃置的牌与攻击速度相同，"
		"initiated_strike":
			text += "若%s发起了战斗，" % detail
		"hit_opponent":
			text += "若击中了对手，"
		"not_hit_opponent":
			text += "若未击中对手，"
		"last_turn_was_strike":
			text += "若上回合是一场战斗，"
		"not_last_turn_was_strike":
			text += "若上回合不是一场战斗，"
		"life_equals":
			text += "若你的生命值恰好为%s，" % amount
		"life_equal_or_below":
			text += "若你的生命值为%s或更低，" % amount
		"life_less_than_opponent":
			text += "若你的生命值低于对手，"
		"not_canceled_this_turn":
			text += "若本回合未取消过，"
		"not_full_push":
			text += "若未完全击退，"
		"not_full_pull":
			text += "若未完全拉近，"
		"pushed_min_spaces":
			text += "若击退了至少%s格，" % amount
		"not_full_close":
			text += "若未完全逼近，"
		"moved_less_than":
			text += "若移动少于%s格，" % amount
		"moved_at_least":
			text += "若至少移动了%s格，" % amount
		"moved_past_this_strike":
			text += "若你在本次战斗中越过对手，"
		"not_initiated_strike":
			text += "若是对手发起了战斗，"
		"not_moved_self_this_strike":
			text += "若你在本次战斗中尚未移动自己，"
		"opponent_not_moved_this_strike":
			text += "若对手在本次战斗中未移动自己，"
		"moved_during_strike":
			text += "若你在本次战斗中至少移动了%s格，" % amount
		"was_moved_during_strike":
			text += "若你在本次战斗中至少被移动了%s格，" % amount
		"opponent_was_moved_during_strike":
			text += "若对手在本次战斗中至少被移动了%s格，"  % amount
		"moved_past":
			text += "若你越过了对手，"
		"min_cards_in_deck":
			text += "若你的牌库中至少有%s张牌，" % amount
		"min_cards_in_discard":
			text += "若你的弃牌堆中至少有%s张牌，" % amount
		"min_cards_in_hand":
			text += "若你的手牌中至少有%s张牌，" % amount
		"max_cards_in_hand":
			var amount_str = "%s张或更少" % amount
			if amount == 0:
				amount_str = "没有"
			text += "若你的手牌中有%s牌，" % amount_str
		"opponent_max_cards_in_hand":
			var amount_str = "<=%s" % amount
			text += "如果对手的手牌 %s, " % amount_str
		"fewer_cards_in_hand":
			text += "若你的手牌比对手少，"
		"player_exceeded":
			text += "若你处于觉醒状态，"
		"opponent_was_stunned_this_turn":
			text += "若你本回合击晕过对手，"
		"max_cards_in_gauge":
			var amount_str = "%s张或更少" % amount
			if amount == 0:
				amount_str = "没有"
			text += "若你的怒中有%s牌，" % amount_str
		"min_cards_in_gauge":
			if effect.get("condition_opponent"):
				text += "若对手的怒中至少有%s张牌，" % amount
			else:
				text += "若你的怒中至少有%s张牌，" % amount
		"min_spaces_behind_opponent":
			text += "若对手身后有%s格或更多，" % amount
		"no_strike_caused":
			text += "若未造成战斗，"
		"stunned":
			text += "若被眩晕，"
		"not_stunned":
			text += "若未被眩晕，"
		"no_active_strike":
			text += ""
		"opponent_stunned":
			text += "若对手被眩晕，"
		"pulled_past":
			text += "若将对手拉近越过你，"
		"used_character_action":
			text += ""
		"used_character_bonus":
			text += ""
		"not_used_character_bonus":
			text += ""
		"boost_caused_start_of_turn_strike":
			text += "若此加成使你进行战斗，"
		"range":
			text += "若对手与攻击源的距离为%s，" % amount
		"range_from_self":
			text += "若对手与你的距离为%s，" % amount
		"range_greater_or_equal":
			text += "若对手与攻击源的距离为%s+，" % amount
		"range_multiple":
			text += "若对手与攻击源的距离为%s-%s，" % [amount, amount2]
		"exceeded":
			text += "若处于觉醒状态："
		"opponent_exceeded":
			text += "若对手处于觉醒状态："
		"is_special_attack":
			text += ""
		"is_special_or_ultra_attack":
			text += "对特殊技/必杀技，"
		"opponent_is_special_attack":
			text += "若对手以特殊技进行战斗，"
		"is_normal_attack":
			text += "若你以普通技进行战斗，"
		"deck_not_empty":
			text += ""
		"top_deck_is_normal_attack":
			text += "若你的牌库顶牌是普通技，"
		"is_buddy_special_or_ultra_attack":
			text += ""
		"buddy_in_opponent_space":
			text += "若%s在对手所在格，" % detail
		"buddy_in_play":
			text += "若%s在场，" % detail
		"buddy_space_unoccupied":
			text += "若%s所在格无人占据，" % detail
		"on_buddy_space":
			text += "若位于%s所在格，" % detail
		"opponent_on_buddy_space":
			text += "若对手位于%s所在格，" % detail
		"buddy_between_attack_source":
			text += "若%s位于你与攻击源之间，" % detail
		"buddy_between_opponent":
			text += "若%s位于你与对手之间，" % detail
		"boost_space_between_opponent":
			text += "若%s位于你与对手之间，" % detail
		"less_cards_than_opponent":
			text += "若对手手牌比你多，"
		"more_cards_than_opponent":
			text += "若你的手牌比对手多，"
		"opponent_at_edge_of_arena":
			text += "若对手在场地边缘，"
		"opponent_at_location":
			text += "若对手位于%s，" % detail
		"opponent_at_max_range":
			text += "若对手处于攻击的最大距离，"
		"opponent_at_min_range":
			text += "若对手处于攻击的最小距离，"
		"opponent_between_buddy":
			if 'include_buddy_space' in effect and effect['include_buddy_space']:
				text += "若对手位于%s上或在你们之间，" % detail
			else:
				text += "若对手位于你与%s之间，" % detail
		"opponent_buddy_in_range":
			text += "若你可以击中%s，" % detail
		"opponent_in_boost_space":
			text += "若对手位于%s，" % detail
		"boost_space_unoccupied":
			text += "若%s所在格无人占据，" % detail
		"boost_is_at_specific_range":
			text += "若%s与你的距离为%s，" % [detail, effect['condition_amount']]
		"boost_space_in_range_towards_opponent":
			text += "若%s在朝向对手的距离内，" % detail
		"opponent_moved_or_was_moved":
			text += "若对手移动过或被移动过，"
		"is_buddy_special_attack":
			text += ""
		"speed_greater_than":
			if amount == "OPPONENT_SPEED":
				text += "若你的速度高于对手，"
			else:
				text += "若你的速度高于%s，" % amount
		"opponent_speed_less_or_equal":
			text += "若对手的速度为%s或更低，" % amount
		"was_wild_swing":
			if effect.get("timing") == "opponent_set_strike":
				text += "若对手进行了疯狂攻击，"
			else:
				text += "若攻击为疯狂，"
		"was_strike_from_gauge":
			text += "若从怒中设置，"
		"was_set_from_boosts":
			text += "若从加成中设置，"
		"was_hit":
			text += "若你被击中，"
		"was_not_hit":
			text += "若你未被击中，"
		"matches_named_card":
			text += "若你的下一次攻击是%s，" % detail
		"is_critical":
			var crit_name = "暴击"
			if 'alt_crit_name' in condition:
				crit_name = condition['alt_crit_name']
			text += "%s：" % crit_name
		"is_infused":
			text += "灌注："
		"is_not_infused":
			text += "若未灌注，"
		"no_sealed_copy_of_attack":
			text += "若没有你攻击的封印复制，"
		"total_powerup_greater_or_equal":
			text += "若你有%s或更多额外威力，" % amount
		"opponent_total_guard_greater_or_equal":
			text += "若对手有%s或更多霸体，" % amount
		"discarded_copy_of_attack":
			text += "若有你攻击的一张弃置复制，"
		"no_discarded_copy_of_attack":
			text += "若弃牌堆中没有本次攻击的同名牌，"
		"copy_of_attack_in_deck":
			text += "若牌库中有本次攻击的同名牌，"
		"not_sustained":
			text += ""
		"boost_in_play_or_parents":
			text += "若有“%s”加成在场，" % detail
		"is_ex_strike":
			text += "若攻击为EX，"
		"same_card_as_boost_in_hand":
			text += ""
		"spent_gauge_this_strike":
			text += "若你在本次战斗中花费了怒，"
		"has_once_per_game_resource":
			text += ""
		"has_any_transform":
			text += "若你有转化牌，"
		"headshot":
			text += "爆头："
		"count_numbers":
			text += "X %s" % amount
		_:
			text += "缺失条件"
	return text

func get_effect_type_heading(effect):
	var effect_str = ""
	var effect_type = effect['effect_type']
	match effect_type:
		StrikeEffects.Advance:
			effect_str += "前进"
		StrikeEffects.Close:
			effect_str += "逼近"
		StrikeEffects.Draw:
			effect_str += "抽"
		StrikeEffects.DiscardRandom:
			effect_str += "对手随机弃置"
		StrikeEffects.SelfDiscardChoose:
			effect_str += "弃置"
		StrikeEffects.Pass:
			effect_str += ""
		StrikeEffects.Pull:
			effect_str += "拉近"
		StrikeEffects.Powerup:
			effect_str += "威力+"
		StrikeEffects.SealTransformForPowerup:
			effect_str += "威力+"
		StrikeEffects.SealTransformForArmorup:
			effect_str += "护甲+"
		StrikeEffects.PullNotPast:
			effect_str += "拉近但不越过"
		StrikeEffects.Push:
			effect_str += "击退"
		StrikeEffects.Retreat:
			effect_str += "后退"
		StrikeEffects.MoveBuddy:
			effect_str += "移动%s" % effect['buddy_name']
		StrikeEffects.OpponentDiscardRandom:
			effect_str += "对手随机弃置"
		StrikeEffects.ReduceOpponentPrepareDraw:
			effect_str += "对手热身行动少摸1牌"
		_:
			effect_str += "缺失效果标题"
	return effect_str

func get_effect_type_text(effect, card_name_source : String = "", char_effect_panel : bool = false):
	var effect_str = ""
	var effect_type = effect['effect_type']
	match effect_type:
		"yamamoto_cleanup_choice":
			effect_str += "整理时，选择弃置威压中的所有牌；否则在自己下回合开始时将它们置入怒气区"
		"yamamoto_discard_pressure":
			effect_str += "弃置威压中的所有牌"
		"yamamoto_start_turn_gauge":
			effect_str += "将威压中的所有牌置入怒气区"
		"yamamoto_exceed_discard_pressure":
			effect_str += "战斗结束时弃置威压中的所有牌；若成功弃置，摸1张牌"
		"yamamoto_boost_to_pressure_if_empty":
			effect_str += "若威压中没有牌，将此牌置入威压"
		"yamamoto_jokaku_hit":
			effect_str += "若有焚烧，击中时获得优势并将此牌置入威压，直到你的下个行动阶段前保留此牌"
		"yamamoto_ryujin_execute":
			effect_str += "若有焚烧，击中且对手生命低于6时，对其造成99点伤害"
		"yamamoto_counter_cards":
			effect_str += "对手打出加成时，可以发动森罗或威眠"
		"yamamoto_activate_shinra":
			effect_str += "弃置森罗并支付3生命，弃置场上所有加成"
		"yamamoto_activate_imin":
			effect_str += "弃置威眠并支付1生命，阻止该加成造成的自身移动"
		StrikeEffects.SoifonPayShunko:
			effect_str += "设置攻击牌后，支付至多3张『瞬哄』以获得层叠效果"
		StrikeEffects.SoifonApplyShunko:
			effect_str += "结算已支付的『瞬哄』"
		StrikeEffects.SoifonShunkoBeforeMove:
			effect_str += "瞬哄（2张）：前置，移动至多1格"
		StrikeEffects.SoifonShunkoHitMove:
			effect_str += "瞬哄（1张）：击中，击退或拉近至多1格"
		StrikeEffects.SoifonShunkoAfterDamage:
			effect_str += "瞬哄：后置，对手距离2时造成不击晕伤害"
		StrikeEffects.SoifonShunkoCleanup:
			effect_str += "瞬哄（3张）：整理，获得优势"
		StrikeEffects.SoifonNigekiHit:
			effect_str += "结算二击必杀的击中效果"
		StrikeEffects.SoifonTopdeckToShunko:
			effect_str += "将牌堆顶的牌置入『瞬哄』"
		StrikeEffects.SoifonTopdeckToGauge:
			effect_str += "将牌堆顶的牌置入怒气区"
		StrikeEffects.SoifonMoveUpTo:
			effect_str += "移动至多%s格" % effect.get("amount", 1)
		StrikeEffects.SoifonAdvanceUpTo:
			effect_str += "前进至多%s格" % effect.get("amount", 1)
		StrikeEffects.SoifonRetreatUpTo:
			effect_str += "后退至多%s格" % effect.get("amount", 1)
		StrikeEffects.SoifonHankisousai:
			effect_str += "反鬼相杀：比较双方印刷威力"
		StrikeEffects.JingleChunShuiStrikeAfterSpecialBoost:
			effect_str += "若这是特殊技加成，你可以发起战斗"
		StrikeEffects.JingleChunShuiDrawAndStrikeAfterContinuousBoost:
			effect_str += "抽1张牌，然后你可以发起战斗"
		StrikeEffects.JingleChunShuiTurnStartToll:
			effect_str += "当前回合玩家必须花费2点能量或受到1点伤害；每弃置牌库顶2张牌可代替1点能量"
		StrikeEffects.JingleChunShuiTurnStartTollPay:
			effect_str += "支付回合开始费用"
		StrikeEffects.JingleChunShuiGaugeSpecialBoost:
			effect_str += "支付2点生命，从怒气打出一张特殊技加成并支付其费用，然后将牌库顶牌加入怒"
		StrikeEffects.JingleChunShuiOnExceed:
			effect_str += "抽1张牌，然后双方各受到2点非致命伤害"
		StrikeEffects.JingleChunShuiPlayBujingdule:
			effect_str += "你可以从手牌、怒气或弃牌堆免费打出并维持“不精独乐”的加成"
		StrikeEffects.JingleChunShuiChooseTwo:
			effect_str += "选择两项且不可重复：抽1；前进1；后退1；对手选择1张手牌弃掉；威力+1"
		StrikeEffects.JingleChunShuiBujingduleReturn:
			effect_str += "将牌库顶牌加入怒，并将此攻击返回手牌"
		StrikeEffects.JingleChunShuiSlowestPlayerDamage:
			effect_str += "对本次战斗中移动距离唯一较少的玩家造成2点伤害；平手不造成伤害"
		StrikeEffects.JingleChunShuiYanguiNameNormal:
			effect_str += "点名一张普通技；对手弃置同名牌或展示手牌。若弃置，本攻击威力+3且无视霸体"
		StrikeEffects.JingleChunShuiYanguiNameNormalInternal:
			effect_str += "结算点名的普通技"
		StrikeEffects.JingleChunShuiAlternatingNormals:
			effect_str += "从你开始，双方各声明一张普通技；本次战斗中每次声明使同名攻击威力+1，然后发起战斗"
		StrikeEffects.JingleChunShuiAlternatingNormalsInternal:
			effect_str += "声明一张普通技"
		StrikeEffects.JingleChunShuiInvalidateIfOpponentDeckOverNine:
			effect_str += "若对手牌库多于9张，此攻击无效"
		StrikeEffects.JingleChunShuiDiscardTopdeckForPower:
			effect_str += "你可以弃置牌库顶至多%s张牌，每张使威力+1" % effect.get("amount", 9)
		StrikeEffects.ActivateNonExceedOverdrive:
			effect_str += "发动超载效果"
		StrikeEffects.AddAttackEffect:
			if 'description' in effect:
				effect_str += effect['description']
			else:
				if char_effect_panel:
					effect_str += get_effect_text(effect['added_effect'], false, false, false, card_name_source, false)
				else:
					effect_str += "添加效果 - " + get_effect_text(effect['added_effect'], false, false, false, card_name_source, false)
		StrikeEffects.AddAttackTriggers:
			effect_str += "将该牌上的前置/击中/后置效果添加到攻击上"
		StrikeEffects.AddBoostToGaugeOnStrikeCleanup:
			if card_name_source:
				effect_str += "将%s加入怒" % card_name_source
			else:
				effect_str += "将牌加入怒"
		StrikeEffects.AddBoostToOverdriveDuringStrikeImmediately:
			if 'card_name' in effect:
				effect_str += "将%s加入超载区域" % effect['card_name']
			else:
				effect_str += "将牌加入超载区域"
		StrikeEffects.AddHandToGauge:
			effect_str += "将你的手牌加入你的怒"
		StrikeEffects.AddOpponentStrikeToGauge:
			effect_str += "将对手的攻击加入怒"
		StrikeEffects.AddStrikeToGaugeAfterCleanup:
			effect_str += "战斗后将牌加入怒。"
		StrikeEffects.AddStrikeToOverdriveAfterCleanup:
			effect_str += "战斗后将牌加入超载区域。"
		StrikeEffects.AddToSetAsideImmediately:
			effect_str += "将牌加入在角色特殊区域。"
		StrikeEffects.AddToGaugeBoostPlayCleanup:
			effect_str += "将牌加入怒"
		StrikeEffects.AddToGaugeImmediately:
			effect_str += "将牌加入怒"
		StrikeEffects.AddToGaugeImmediatelyMidStrikeUndoEffects:
			effect_str += "将牌加入怒（并取消其效果）。"
		StrikeEffects.AddBonusArmorCounters:
			effect_str += "获得%s个护甲指示物" % str(effect['amount'])
		StrikeEffects.AddBonusGuardCounters:
			effect_str += "获得%s个霸体指示物" % str(effect['amount'])
		StrikeEffects.AddBottomDiscardToGauge:
			var card_str = ""
			if 'card_name' in effect:
				card_str = "([color=%s]%s[/color]) " % [CardHighlightColor, effect['card_name']]
			effect_str += "将弃牌堆底牌%s加入怒" % card_str
		StrikeEffects.AddBottomDiscardToHand:
			var card_str = ""
			if 'card_name' in effect:
				card_str = "([color=%s]%s[/color]) " % [CardHighlightColor, effect['card_name']]
			effect_str += "将弃牌堆底牌%s加入手牌" % card_str
		StrikeEffects.AddTopDeckToGauge:
			var player_str = "将"
			if 'opponent' in effect and effect['opponent']:
				player_str = "对手将"
			var amount_str = "牌库顶牌"
			if 'amount' in effect:
				amount_str = "牌库顶%s张牌" % effect['amount']
				if str(effect['amount']) == 'num_discarded_card_ids':
					amount_str = "等量的牌库顶牌"
				elif str(effect['amount']) == 'force_spent_this_turn':
					amount_str = "本回合每花费1点能量对应的1张牌库顶牌"
			var topdeck_card = ""
			if 'card_name' in effect:
				topdeck_card = "([color=%s]%s[/color]) " % [CardHighlightColor, effect['card_name']]
			effect_str += "%s%s%s加入怒" % [player_str, amount_str, topdeck_card]
		StrikeEffects.AddTopDeckToBottom:
			effect_str = "将牌库顶牌移至牌库底"
		StrikeEffects.AddTopDiscardToGauge:
			if 'amount' in effect:
				effect_str += "将弃牌堆顶%s张牌加入怒" % effect['amount']
			else:
				effect_str += "将弃牌堆顶牌加入怒"
		StrikeEffects.AddTopDiscardToOverdrive:
			if 'card_name' in effect:
				effect_str += "将弃牌堆顶的%s加入超载区域" % effect['card_name']
			else:
				effect_str += "将弃牌堆顶牌加入超载区域"
		StrikeEffects.AddPassive:
			var passive_id = effect['passive']
			match passive_id:
				"discard_2x_topdeck_instead_of_damage":
					effect_str += "无视伤害，改为从牌库顶弃置等量2倍的牌"
				"geoffrey_untainted_passive":
					effect_str += "当你会在回合结束时抽牌时（生命值为5或更低），改为获得1点生命"
				"skip_eot_draw_and_discard":
					effect_str += "跳过回合结束时的抽牌与弃牌"
		StrikeEffects.Advance:
			if 'description' in effect:
				effect_str += effect['description']
			else:
				if 'combine_multiple_into_one' in effect and effect['combine_multiple_into_one']:
					effect_str += "前进等量格。"
				else:
					effect_str += "前进"
					if str(effect['amount']) == "strike_x":
						effect_str += "X"
					else:
						effect_str += str(effect['amount'])
		StrikeEffects.AdvanceInternal:
			effect_str += "前进"
			if str(effect['amount']) == "strike_x":
				effect_str += "X"
			else:
				effect_str += str(effect['amount'])
		StrikeEffects.Armorup:
			effect_str += "+" + str(effect['amount']) + "护甲"
		StrikeEffects.ArmorupDamageDealt:
			effect_str += "每造成1点伤害，+1护甲"
		StrikeEffects.ArmorupBonusArmorCounters:
			effect_str += "此牌上每有1个指示物，+1护甲"
		StrikeEffects.GuardupBonusGuardCounters:
			effect_str += "此牌上每有1个指示物，+1霸体"
		StrikeEffects.ArmorupCurrentPower:
			effect_str += "护甲增加等同于威力的数值"
		StrikeEffects.ArmorupOpponentPerForceSpentThisTurn:
			if effect['amount'] >= 0:
				effect_str += "+"
			effect_str += str(effect['amount']) + " 对手护甲，每花费1点本回合能量。"
		StrikeEffects.AttackDoesNotHit:
			if 'opponent' in effect and effect['opponent']:
				effect_str += "对手的攻击不会击中。"
			else:
				effect_str += "攻击不会击中。"
		StrikeEffects.AttackIncludesRange:
			effect_str += "攻击包含距离%s" % effect['amount']
		StrikeEffects.AttackIsEx:
			effect_str += "下一次战斗为EX"
		StrikeEffects.BecomeWide:
			var description = "宽3格"
			if 'description' in effect:
				description = effect['description']
			effect_str = "变为%s" % description
		StrikeEffects.BlockOpponentMove:
			effect_str += "对手不能移动"
		StrikeEffects.BlockOpponentAdvanceClose:
			effect_str += "对手不能前进或逼近"
		StrikeEffects.RemoveBlockOpponentMove:
			effect_str += ""
		StrikeEffects.RemoveBlockOpponentAdvanceClose:
			effect_str += ""
		StrikeEffects.BonusAction:
			effect_str += "执行额外一动"
		StrikeEffects.BoostAdditional:
			var limitation_str = "加成"
			if 'limitation' in effect and effect['limitation']:
				limitation_str = effect['limitation'] + "加成"
			var ignore_costs_str = ""
			if 'ignore_costs' in effect and effect['ignore_costs']:
				ignore_costs_str = "（无视费用）"
			if 'valid_zones' in effect:
				var zone_string = "/".join(effect['valid_zones'])
				effect_str += "从%s打出1张%s%s。" % [zone_string, limitation_str, ignore_costs_str]
			else:
				effect_str += "从手牌打出1张%s%s。" % [limitation_str, ignore_costs_str]
		StrikeEffects.BoostMultiple:
			var amount_str = "1-%s" % effect['amount']
			if effect['amount'] == 1:
				amount_str = 1
			var limitation_str = "加成"
			if 'limitation' in effect and effect['limitation']:
				limitation_str = effect['limitation'] + "加成"
			var ignore_costs_str = ""
			if 'ignore_costs' in effect and effect['ignore_costs']:
				ignore_costs_str = "（无视费用）"
			if 'valid_zones' in effect:
				var zone_string = "/".join(effect['valid_zones'])
				effect_str += "从%s打出%s张%s%s。" % [zone_string, amount_str, limitation_str, ignore_costs_str]
			else:
				effect_str += "从手牌打出%s张%s%s。" % [amount_str, limitation_str, ignore_costs_str]
		StrikeEffects.BoostOrRevealHand:
			var alternative = "展示手牌"
			if 'strike_instead_of_reveal' in effect and effect['strike_instead_of_reveal']:
				alternative = "战斗"
			effect_str += "打出加成（若不能，则%s）" % alternative
		StrikeEffects.BoostSpecificCard:
			effect_str += "从手牌打出1张“%s”加成" % effect['boost_name']
		StrikeEffects.BoostThenStrike:
			var wild_str = ""
			if 'wild_strike' in effect and effect['wild_strike']:
				wild_str = "疯狂"
			effect_str += "先打出加成，然后若你未被造成战斗，则进行%s战斗" % wild_str
		StrikeEffects.BoostThisThenSustain:
			var sustain_str = "并维持"
			if 'dont_sustain' in effect and effect['dont_sustain']:
				sustain_str = ""
			if card_name_source:
				effect_str += "打出加成%s%s" % [sustain_str, card_name_source]
			else:
				effect_str += "打出加成%s此牌" % sustain_str
		StrikeEffects.BoostThenSustain:
			var sustain_str = "并维持"
			if 'sustain' in effect and not effect['sustain']:
				sustain_str = ""
			var limitation_str = "加成"
			if 'limitation' in effect and effect['limitation']:
				if effect['limitation'] == "transform":
					limitation_str = "转化"
				else:
					limitation_str = effect['limitation'] + "加成"
			var ignore_costs_str = ""
			if 'ignore_costs' in effect and effect['ignore_costs']:
				ignore_costs_str = "（无视费用）"
			if 'valid_zones' in effect:
				var zone_string = "/".join(effect['valid_zones'])
				effect_str += "从%s打出1张%s%s%s。" % [zone_string, limitation_str, sustain_str, ignore_costs_str]
			else:
				effect_str += "从手牌打出1张%s%s%s。" % [limitation_str, sustain_str, ignore_costs_str]
			if 'play_boost_effect' in effect:
				effect_str += "若你如此作，%s" % get_effect_text(effect['play_boost_effect'])
		StrikeEffects.BoostThenSustainTopdeck:
			if 'description' in effect:
				effect_str += effect['description']
			else:
				effect_str += "从你的牌库顶打出并维持%s张牌。" % effect['amount']
		StrikeEffects.BoostThenSustainTopdiscard:
			var limitation_str = "牌"
			if 'limitation' in effect and effect['limitation'] == "continuous":
				limitation_str = "持续性加成"
			effect_str += "从你的弃牌堆顶打出并维持%s张%s" % [effect['amount'], limitation_str]
		StrikeEffects.ChooseBoostsFromTopDeck:
			if 'description' in effect:
				effect_str += effect['description']
			else:
				var choose_limitation_str = "牌"
				if 'limitation' in effect and effect['limitation'] == "continuous":
					choose_limitation_str = "持续性加成"
				effect_str += "查看牌库顶%s张牌，免费打出并维持其中任意数量的%s，其余弃置" % [effect['look_amount'], choose_limitation_str]
		StrikeEffects.BoostAsOverdriveInternal:
			effect_str += "超载效果：从手牌打出1张持续性加成。"
		StrikeEffects.CannotGoBelowLife:
			effect_str += "生命值不能低于%s" % effect['amount']
		StrikeEffects.CannotDrawPassive:
			effect_str += "不能抽牌"
		StrikeEffects.CapAttackDamageTaken:
			effect_str += "本次战斗（计算护甲后）最多承受%s点伤害" % effect['amount']
		StrikeEffects.CanSpendLifeForGauge:
			effect_str += "可以花费%s点生命来获得1点怒" % effect['amount']
		StrikeEffects.CannotStun:
			effect_str += "攻击不会造成眩晕"
		StrikeEffects.Choice:
			var multiple_str = ""
			if 'mulitple_amount' in effect:
				multiple_str = " " + str(effect['mulitple_amount'])
			if 'opponent' in effect and effect['opponent']:
				effect_str += "对手"
			if 'special_choice_name' in effect:
				effect_str += effect['special_choice_name']
			else:
				effect_str += "选择" + multiple_str + "：" + get_choice_summary(effect[StrikeEffects.Choice], card_name_source)
		StrikeEffects.ChoiceAlteredValues:
			if 'opponent' in effect and effect['opponent']:
				effect_str += "对手"
			if 'special_choice_name' in effect:
				effect_str += effect['special_choice_name']
			else:
				effect_str += "选择：" + get_choice_summary(effect[StrikeEffects.Choice], card_name_source)
		StrikeEffects.ChooseCalculateRangeFromBuddy:
			var optional_str = "选择"
			if 'optional' in effect and effect['optional']:
				optional_str = "你可以选择"
			effect_str += optional_str + "1个%s来作为计算距离的起点" % effect['buddy_name']
		StrikeEffects.ChooseDiscard:
			var destination = effect['destination']
			if destination == "lightningrod_any_space":
				effect_str += "从你的弃牌堆中选择1张牌，作为避雷针放置"
			else:
				var destination_str = destination
				var amount_str = str(effect.get("amount", "1"))
				if destination == "deck_noshuffle":
					destination_str = "牌库顶"
				var source = "弃牌堆"
				if 'source' in effect:
					source = effect['source']
				if effect['limitation']:
					effect_str += "从%s中选择%s张%s牌移至%s" % [source, amount_str, effect['limitation'], destination_str]
				else:
					effect_str += "从%s中选择%s张牌移至%s" % [source, amount_str, destination]
				if effect.get("opponent"):
					effect_str = "对手必须：" + effect_str
		StrikeEffects.ChooseOpponentCardToDiscard:
			var opponent = effect['opponent'] if 'opponent' in effect else false
			var use_discarded_card_ids = effect['use_discarded_card_ids'] if 'use_discarded_card_ids' in effect else false
			if opponent:
				if use_discarded_card_ids:
					effect_str += "对手选择其中1张弃置"
				else:
					effect_str += "对手选择你手中的1张牌弃置"
			else:
				if use_discarded_card_ids:
					effect_str += "选择其中1张弃置"
				else:
					effect_str += "选择对手手中的1张牌弃置"
		StrikeEffects.ChooseSustainBoost:
			effect_str += "选择1张要维持的加成。"
		StrikeEffects.Close:
			if 'combine_multiple_into_one' in effect and effect['combine_multiple_into_one']:
				effect_str += "逼近等量格。"
			else:
				effect_str += "逼近" + str(effect['amount'])
		StrikeEffects.CloseDamageTaken:
			effect_str += "本次战斗中每受到1点伤害，逼近%s格" % effect['amount']
		StrikeEffects.CloseInternal:
			effect_str += "逼近" + str(effect['amount'])
		StrikeEffects.CopyOtherHitEffect:
			effect_str += "复制另一个击中效果"
		StrikeEffects.CopyOtherAfterEffect:
			effect_str += "复制另一个后置效果"
		StrikeEffects.Critical:
			var crit_name = "暴击"
			if 'alt_crit_name' in effect:
				crit_name = effect['alt_crit_name']
			effect_str += "%s战斗" % crit_name
		StrikeEffects.DiscardThis:
			effect_str += "弃置此牌"
		StrikeEffects.DiscardSameCardAsBoost:
			effect_str += "弃置1张与该加成同名的牌"
		StrikeEffects.DiscardStrikeAfterCleanup:
			effect_str += "在整理阶段弃置攻击"
		StrikeEffects.DiscardAttack:
			effect_str += "弃置你的攻击"
		StrikeEffects.DiscardContinuousBoost:
			if 'destination' in effect and effect['destination'] == "owner_hand":
				effect_str += "将1张持续性加成返回其拥有者的手牌。"
			else:
				if 'limitation' in effect and effect['limitation'] == 'mine' and 'overall_effect' in effect:
					effect_str += "你可以弃置你的一张持续性加成来%s" % [get_effect_text(effect['overall_effect'])]
				else:
					effect_str += "弃置1张持续性加成"
		StrikeEffects.DiscardOpponentGauge:
			effect_str += "弃置对手怒中的1张牌。"
		StrikeEffects.DiscardOpponentTopdeck:
			effect_str += "弃置对手牌库顶的1张牌"
		StrikeEffects.DiscardTopdeck:
			if 'card_name' in effect:
				effect_str += "从你的牌库顶弃置[color=%s]%s[/color]" % [CardHighlightColor, effect['card_name']]
			else:
				effect_str += "从你的牌库顶弃置1张牌"
		StrikeEffects.DiscardRandom:
			effect_str += "随机弃置%s" % effect['amount']
		StrikeEffects.DiscardRandomAndAddTriggers:
			effect_str += "随机弃置1张牌；将前置/击中/后置触发添加到攻击上"
		StrikeEffects.DodgeAtRange:
			var buddy_string = ""
			if 'from_buddy' in effect and effect['from_buddy']:
				buddy_string = "（以%s为起点）" % effect['buddy_name']
			if 'special_range' in effect and effect['special_range'] == "OVERDRIVE_COUNT":
				effect_str += "对手在距离X的攻击会落空，X为你超载区域中的牌数。"
			elif effect['range_min'] == effect['range_max']:
				effect_str += "对手在距离%s的攻击会落空。%s" % [effect['range_min'], buddy_string]
			else:
				effect_str += "对手在距离%s-%s的攻击会落空。%s" % [effect['range_min'], effect['range_max'], buddy_string]
		StrikeEffects.DodgeAttacks:
			effect_str += "对手攻击落空。"
		StrikeEffects.LowerSpeedMisses:
			var speed = effect.get("dodge_at_speed_lower_or_equal", 0)
			if speed > 0:
				effect_str += "闪避速度%s或更低的攻击" % speed
			else:
				effect_str += "闪避速度更低的攻击"
		StrikeEffects.DodgeFromOppositeBuddy:
			effect_str += "位于%s另一侧的对手攻击落空。" % effect['buddy_name']
		StrikeEffects.DoNotRemoveBuddy:
			effect_str += "不要将%s移出场。" % effect['buddy_name']
		StrikeEffects.RemoveBuddy:
			effect_str += "将%s移出场" % effect['buddy_name']
		StrikeEffects.PlaceBuddyInAnySpace:
			effect_str += "将%s放置到任意格。" % effect['buddy_name']
		StrikeEffects.PlaceBuddyInAttackRange:
			effect_str += "将%s放置到攻击距离内。" % effect['buddy_name']
		StrikeEffects.PlaceNextBuddy:
			var unoccupied_str = ""
			if effect['require_unoccupied']:
				unoccupied_str = "在未被占据的格中"
			var where_str = ""
			match effect['destination']:
				"attack_range":
					where_str = "在攻击距离内"
				"anywhere":
					where_str = "在任意位置"
				"adjacent_self":
					where_str = "在你相邻的位置"
				"self":
					where_str = "在你所在格"
				_:
					where_str = "<缺失目标字符串>"
			effect_str += "将%s放置于%s%s。" % [effect['buddy_name'], where_str, unoccupied_str]
		StrikeEffects.PlaceLightningrod:
			var card_str = ""
			match effect['source']:
				"this_attack_card":
					card_str = "此次攻击"
				"top_discard":
					card_str = "你的弃牌堆顶牌"
			var where_str = ""
			match effect['limitation']:
				"attack_range":
					where_str = "在攻击距离内"
				"any":
					where_str = "在任意位置"
			effect_str += "将%s作为避雷针放置于%s" % [card_str, where_str]
		StrikeEffects.PlaceTopdeckUnderBoost:
			effect_str += "将牌库顶牌放到%s下方；弃置时抽取全部" % effect['card_name']
		StrikeEffects.PlayAttackFromHand:
			effect_str += "从手牌打出1张攻击，并支付其费用。"
		StrikeEffects.CalculateRangeFromBuddy:
			effect_str += "从%s计算距离。" % effect['buddy_name']
		StrikeEffects.CalculateRangeFromBuddyCurrentLocation:
			effect_str += "从%s当前位置计算距离" % effect['buddy_name']
		StrikeEffects.CalculateRangeFromCenter:
			effect_str += "从场地中央计算距离。"
		StrikeEffects.CalculateRangeFromSetFromBoostSpace:
			effect_str += "从其所在格计算距离。"
		StrikeEffects.Draw:
			var amount = effect['amount']
			var amount_str = str(amount)
			var bottom_str = ""
			if amount_str == "strike_x":
				amount_str = "X"
			elif amount_str == "GAUGE_COUNT":
				amount_str = "等同于你的怒数量"
			elif amount_str == "SPACES_BETWEEN":
				amount_str = "你与对手之间每有1格便抽1张"
			if 'from_bottom' in effect:
				bottom_str = "，从牌库底"
			if 'opponent' in effect and effect['opponent']:
				if 'hide_opponent_in_description' in effect and effect['hide_opponent_in_description']:
					effect_str += "抽" + amount_str + bottom_str
				else:
					effect_str += "对手抽" + amount_str + bottom_str
			else:
				effect_str += "抽" + amount_str + bottom_str
		StrikeEffects.DrawForCardInGauge:
			var every_str = "每张牌"
			if 'per_gauge' in effect:
				every_str = "每%s张牌" % effect['per_gauge']
			effect_str += "你的怒中%s抽1张" % every_str
		StrikeEffects.GaugeCardsForceValue:
			effect_str += "使用怒气区的牌支付能量时，每张最多支付%s点能量" % effect['amount']
		StrikeEffects.DrawAnyNumber:
			# amount 作为上限时就是「抽至多 N 张」（可选 0~N）。
			var any_number_cap = effect.get('amount', null)
			if (typeof(any_number_cap) == TYPE_INT or typeof(any_number_cap) == TYPE_FLOAT) and int(any_number_cap) >= 0:
				effect_str += "抽至多%d张牌。" % int(any_number_cap)
			else:
				effect_str += "抽任意数量的牌。"
		StrikeEffects.DrawTo:
			effect_str += "抽牌直到你手中有%s张牌" % str(effect['amount'])
		StrikeEffects.OpponentDrawOrDiscardTo:
			var amount_str = "手中有%s张牌" % str(effect['amount'])
			if str(effect['amount']) == 'other_player_hand_size':
				amount_str = "与你相同数量的手牌"
			effect_str += "对手抽牌或弃牌，直到他们%s" % amount_str
			if 'per_draw_effect' in effect:
				effect_str += "\n若其抽牌：每抽1张，" + get_effect_text(effect['per_draw_effect'], false, false, false)
		StrikeEffects.EffectPerCardInZone:
			var per_effect = get_effect_text(effect["per_card_effect"], false, false, false)
			var limitation_str = ""
			var zone_name = effect['zone']
			if effect.get("zone_name"):
				zone_name = effect['zone_name']
			if effect.get("limitation") == "range_to_opponent":
				limitation_str = "，其距离可命中对手"
			effect_str += "%s，%s中每有1张牌%s" % [per_effect, zone_name, limitation_str]
		StrikeEffects.ExceedNow:
			effect_str += "觉醒"
		StrikeEffects.MayExceedNowWithCost:
			effect_str += "可以觉醒（支付费用）"
		StrikeEffects.ExtraTriggerResolutions:
			effect_str += "前置/击中/后置触发额外结算%s次" % effect['amount']
		StrikeEffects.FlipBuddyMissGetGauge:
			effect_str += effect['description']
		StrikeEffects.ForceCostsReducedPassive:
			effect_str += "能量费用减少%s" % effect['amount']
		StrikeEffects.GaugeCostsReducedPassive:
			effect_str += "怒气花费减少%s" % effect['amount']
		StrikeEffects.ForceForEffect:
			effect_str += get_force_for_effect_summary(effect, card_name_source)
		StrikeEffects.GaugeForEffect:
			effect_str += get_gauge_for_effect_summary(effect, card_name_source)
		StrikeEffects.GainAdvantage:
			effect_str += "获得优势"
		StrikeEffects.GainLife:
			var amount = effect['amount']
			if str(amount) == "LAST_SPENT_LIFE":
				amount = "等量"
			effect_str += "获得" + str(amount) + "点生命"
		StrikeEffects.GainLifeDamageDealt:
			effect_str += "获得等同于所造成伤害的生命"
		StrikeEffects.GaugeFromHand:
			var last_cards_req = ""
			var destination = "怒"
			if effect.get("destination_name"):
				destination = effect['destination_name']
			if effect.get("from_last_cards"):
				last_cards_req = "，从最近抽到的%s张牌中" % effect['from_last_cards']
			effect_str += "从手牌中将1张牌加入%s%s" % [destination, last_cards_req]
		StrikeEffects.GenerateFreeForce:
			if effect.get("zsolt_force_pool"):
				effect_str += "所有消耗(F/G)减少%s" % effect['amount']
			else:
				effect_str += "免费获得%s点能量" % effect['amount']
		StrikeEffects.Guardup:
			if str(effect['amount']) == "strike_x":
				effect_str += "+X霸体"
			else:
				if effect['amount'] > 0:
					effect_str += "+"
				effect_str += str(effect['amount']) + "霸体"
		StrikeEffects.GuardupPerForceSpentThisTurn:
			effect_str += "+" + str(effect['amount']) + "霸体，每花费1点本回合能量。"
		StrikeEffects.GuardupPerTwoCardsInHand:
			effect_str += "手牌每有2张，+1霸体"
		StrikeEffects.GuardupPerGauge:
			effect_str += "怒中每有1张牌，+" + str(effect['amount']) + "霸体。"
		StrikeEffects.IgnoreArmor:
			if 'opponent' in effect and effect['opponent']:
				effect_str += "对手无视护甲"
			else:
				effect_str += "无视护甲"
		StrikeEffects.IgnoreGuard:
			if 'opponent' in effect and effect['opponent']:
				effect_str += "对手无视霸体"
			else:
				effect_str += "无视霸体"
		StrikeEffects.IgnorePushAndPull:
			effect_str += "无视击退和拉近"
		StrikeEffects.IgnorePushAndPullPassiveBonus:
			effect_str += "无视击退和拉近"
		StrikeEffects.IncreaseDrawEffects:
			effect_str += "抽牌效果增加%s" % effect['amount']
		StrikeEffects.IncreaseForceSpentBeforeStrike:
			effect_str += get_effect_text(effect['linked_effect'], false, false, false)
		StrikeEffects.IncreaseMovementEffects:
			effect_str += "前进/后退效果增加%s" % effect['amount']
		StrikeEffects.IncreaseMove_OpponentEffects:
			effect_str += "击退/拉近效果增加%s" % effect['amount']
		StrikeEffects.IncrementBonusArmorCounters:
			effect_str += "在此牌上放置1个指示物"
		StrikeEffects.InvertRange:
			effect_str += "攻击距离反转"
		StrikeEffects.LightningrodStrike:
			effect_str += "将%s返回手牌以造成2点非致命伤害" % effect['card_name']
		StrikeEffects.ResetCharacterPositions:
			effect_str += "将双方移动回起始位置"
		StrikeEffects.RemoveIgnorePushAndPullPassiveBonus:
			effect_str += ""
		StrikeEffects.Infused:
			effect_str += "灌注"
		StrikeEffects.RemoveCannotDrawPassive:
			effect_str += ""
		StrikeEffects.LoseAllArmor:
			effect_str += "失去所有护甲"
		StrikeEffects.NameCardOpponentDiscards:
			effect_str += "声明1张牌名。对手弃置该牌，或展示其不在手中。"
		StrikeEffects.NegateBoost:
			effect_str += "无效并弃置对手的加成"
		StrikeEffects.MayAdvanceBonusSpaces:
			effect_str = "你可以额外前进/逼近%s格" % effect['amount']
		StrikeEffects.MoveAnyBuddy:
			if 'to_opponent' in effect and effect['to_opponent']:
				effect_str += "将%s移动到对手所在格" % effect['buddy_name']
			else:
				var move_min = effect['amount_min']
				var move_max = effect['amount_max']
				effect_str += "移动%s%s-%s格" % [effect['buddy_name'], move_min, move_max]
		StrikeEffects.MoveBuddy:
			var strike_str = ""
			if 'strike_after' in effect and effect['strike_after']:
				strike_str = "并战斗"
			var movement_str = "%s" % effect['amount']
			if effect['amount'] != effect['amount2']:
				movement_str += "-%s" % effect['amount2']
			effect_str += "移动%s%s格%s" % [effect['buddy_name'], movement_str, strike_str]
		StrikeEffects.MoveToBuddy:
			effect_str += "移动到%s" % effect['buddy_name']
		StrikeEffects.MoveToBoostSpace:
			effect_str += "移动到此格"
		StrikeEffects.MoveToAnySpace:
			if 'move_min' in effect:
				var move_min = effect['move_min']
				var move_max = effect['move_max']
				effect_str += "前进或后退%s-%s" % [move_min, move_max]
			else:
				effect_str += "移动到任意格。"
		StrikeEffects.MoveToSpace:
			effect_str += "移动到 %s 格" % effect['amount']
		StrikeEffects.MoveRandomCards:
			var card_count = effect['amount']
			var from_zone = effect['from_zone']
			var to_zone = effect['to_zone']
			var opponent_str = ""
			if effect.get("opponent", false):
				opponent_str = "对手："
			var action_word = "弃置"
			var destination_str = ""
			match to_zone:
				"gauge":
					action_word = "移动"
					destination_str = "到怒"
				# Add other zones here when refactoring other effects.
			var from_str = ""
			match from_zone:
				"gauge":
					from_str = "从怒中"
				# Add other zones here when refactoring other effects.
			effect_str += "%s%s%s张随机牌%s%s" % [opponent_str, action_word, card_count, from_str, destination_str]
		StrikeEffects.MultiplyPowerBonuses:
			if effect['amount'] == 2:
				effect_str += "威力加成翻倍"
			else:
				effect_str += "威力加成变为%s倍" % effect['amount']
		StrikeEffects.MultiplyPositivePowerBonuses:
			if effect['amount'] == 2:
				effect_str += "正向威力加成翻倍"
			else:
				effect_str += "威力加成变为%s倍" % effect['amount']
		StrikeEffects.NonlethalAttack:
			effect_str += "造成非致命伤害"
		StrikeEffects.Nothing:
			if 'description' in effect:
				effect_str += effect['description']
			else:
				effect_str += ""
		StrikeEffects.RegainOncePerGameResource:
			var resource_name = "每局一次机制"
			if 'resource_name' in effect:
				resource_name = effect['resource_name']
			effect_str += "恢复%s的使用次数" % resource_name
		StrikeEffects.OpponentCantMovePast:
			effect_str += "对手不能前进越过你"
		StrikeEffects.RemoveOpponentCantMovePast:
			effect_str += ""
		StrikeEffects.OpponentDiscardChoose:
			var destination_str = "弃置"
			if 'destination' in effect:
				if effect['destination'] == "reveal":
					destination_str = "展示"

			var cards_str = "张牌"
			var amount_str = str(effect['amount'])
			if amount_str == "force_spent_before_strike":
				amount_str = "等量"
			elif amount_str == "CARDS_DISCARDED_THIS_STRIKE":
				amount_str = "本次战斗中每弃置过1张牌便1张牌"
				cards_str = ""

			var allow_fewer = 'allow_fewer' in effect and effect['allow_fewer']
			var up_to_text = ""
			if allow_fewer:
				up_to_text = "至多"
			effect_str += "对手" + destination_str + up_to_text + amount_str + cards_str
			if 'smaller_discard_effect' in effect:
				effect_str += "\n若其弃置较少：" + get_effect_text(effect['smaller_discard_effect'], false, false, false)
		StrikeEffects.OpponentDiscardRandom:
			var dest_str = ""
			if 'destination' in effect:
				dest_str = "到你的" + effect['destination']
			effect_str += "对手随机弃置" + str(effect['amount']) + "张牌" + dest_str + "。"
		StrikeEffects.OpponentDiscardHand:
			effect_str += "对手弃置全部手牌。"
		StrikeEffects.OpponentPowerup:
			effect_str += "对手攻击+" + str(effect['amount']) + "威力"
		StrikeEffects.OpponentTakeDamageOnMove:
			effect_str += "每当对手移动，每移动1格受到" + str(effect['amount']) + "点伤害。"
		StrikeEffects.RetreatCostReduced:
			effect_str += "后退少支付" + str(effect['amount']) + "点能量。"
		"opponent_wild_swings":
			effect_str += "对手进行疯狂攻击。"
		StrikeEffects.Pass:
			effect_str += "跳过"
			if 'description' in effect:
				effect_str += "（%s）" % effect['description']
		StrikeEffects.PlaceBoostInSpace:
			var place_str = "放置"
			if 'boost_already_placed' in effect and effect['boost_already_placed']:
				place_str = "移动"
			var boost_str = "加成"
			if 'boost_name' in effect:
				boost_str = effect['boost_name']

			effect_str += "%s%s。" % [place_str, boost_str]
		StrikeEffects.PlaceBuddyAtRange:
			if effect['range_min'] == effect['range_max']:
				effect_str += "将%s放置在距离%s处" % [effect['buddy_name'], effect['range_min']]
			else:
				effect_str += "将%s放置在距离%s-%s处" % [effect['buddy_name'], effect['range_min'], effect['range_max']]
		StrikeEffects.PlaceBuddyOntoSelf:
			effect_str += "将%s放置到你所在格" % effect['buddy_name']
		StrikeEffects.PowerupPerArmorUsed:
			var amount = str(effect['amount'])
			if effect['amount'] > 0:
				amount = "+%s" % amount
			effect_str += "每消耗1张牌护甲，%s威力。" % amount
		StrikeEffects.Powerup:
			var multiplier_string = ""
			if 'multiplier' in effect and effect['multiplier'] != 1:
				multiplier_string += "（x%s）" % str(effect['multiplier'])

			if str(effect['amount']) == "strike_x":
				effect_str += "+X%s威力" % multiplier_string
			elif str(effect['amount']) == "DISCARDED_COUNT":
				effect_str += "你的弃牌堆中每有1张牌，+1%s威力。" % multiplier_string
			else:
				if effect['amount'] > 0:
					effect_str += "+"
				effect_str += str(effect['amount'])
				effect_str += "%s威力" % multiplier_string
		StrikeEffects.PowerupBothPlayers:
			effect_str += "双方"
			if effect['amount'] > 0:
				effect_str += "+"
			effect_str += str(effect['amount'])
			effect_str += "威力"
		StrikeEffects.PowerupPerBoostInPlay:
			effect_str += "场上每有1张加成，+" + str(effect['amount']) + "威力。"
		StrikeEffects.PowerupPerCardInHand:
			effect_str += "手牌中每有1张牌，+" + str(effect['amount']) + "威力，至多到" + str(effect['amount_max']) + "。"
		StrikeEffects.PowerupPerDamageTaken:
			effect_str += "本次战斗每受到1点伤害，+" + str(effect['amount']) + "威力。"
		StrikeEffects.PowerupPerMoreCardsInHand:
			effect_str += "你的手牌每比对手多1张，+" + str(effect['amount']) + "威力。"
		StrikeEffects.PowerupPerCardInOpponentHand:
			var every_str = "张牌"
			if 'per_card' in effect:
				every_str = "%s张牌" % effect['per_card']
			effect_str += "对手手牌中每有" + every_str + "，+" + str(effect['amount']) + "威力。"
		StrikeEffects.PowerupPerForceSpentThisTurn:
			effect_str += "本回合每花费1点能量，+" + str(effect['amount']) + "威力。"
		StrikeEffects.PowerupPerGuard:
			var max_text = ""
			if 'maximum' in effect:
				max_text = "（上限%s）" % effect['maximum']
			effect_str += "每有1点霸体，+" + str(effect['amount']) + "威力%s。" % max_text
		StrikeEffects.PowerupPerArmor:
			var max_text = ""
			if 'maximum' in effect:
				max_text = "（上限%s）" % effect['maximum']
			effect_str += "每有1点护甲，+" + str(effect['amount']) + "威力%s。" % max_text
		StrikeEffects.PowerupPerSpeed:
			var max_text = ""
			if 'maximum' in effect:
				max_text = "（上限%s）" % effect['maximum']
			effect_str += "每有1点速度，+" + str(effect['amount']) + "威力%s。" % max_text
		StrikeEffects.PowerupPerPower:
			var max_text = ""
			if 'maximum' in effect:
				max_text = "（上限%s）" % effect['maximum']
			effect_str += "每有1点威力，+" + str(effect['amount']) + "威力%s。" % max_text
		StrikeEffects.PowerupPerGauge:
			var opponent_str = ""
			if effect.get("count_opponent"):
				opponent_str = "对手的"
			effect_str += opponent_str + "怒中每有1张牌，+" + str(effect['amount']) + "威力，至多到" + str(effect['amount_max']) + "。"
		StrikeEffects.PowerupPerSpentGaugeMatchingRangeToOpponent:
			effect_str += "每花费1张与对手距离相同的怒，+" + str(effect['amount']) + "威力。"
		StrikeEffects.PowerupPerSealedNormal:
			var max_text = ""
			if 'maximum' in effect:
				max_text = "（上限%s）" % effect['maximum']
			effect_str += "每有1张被封印的普通技，+" + str(effect['amount']) + "威力%s。" % max_text
		StrikeEffects.PowerupDamageTaken:
			effect_str += "本次战斗中每受到1点伤害，+" + str(effect['amount']) + "威力。"
		StrikeEffects.PowerupDiscardedCardPrintedPower:
			effect_str += "+威力，数值等同于被弃牌的印刷威力。"
		StrikeEffects.PowerupOpponent:
			if effect['amount'] > 0:
				effect_str += "+"
			if 'describe_as_self' in effect and effect['describe_as_self']:
				effect_str += str(effect['amount']) + "威力"
			else:
				effect_str += str(effect['amount']) + "对手威力"
		StrikeEffects.Pull:
			if 'combine_multiple_into_one' in effect and effect['combine_multiple_into_one']:
				effect_str += "拉近等量格。"
			elif str(effect['amount']) == "TOTAL_POWER":
				effect_str += "拉近X。X等于该攻击的总威力"
			else:
				effect_str += "拉近" + str(effect['amount'])
		StrikeEffects.PullAnyNumberOfSpacesAndGainPower:
			effect_str += "拉近任意格数，每拉近1格便+1威力。"
		StrikeEffects.PullToRange:
			effect_str += "拉近至距离%s" % str(effect['amount'])
		StrikeEffects.PullToBuddy:
			effect_str += "将%s拉近到%s" % [str(effect['amount']), effect['buddy_name']]
		StrikeEffects.PullToSpaceAndGainPower:
			effect_str += "拉近到格%s，并且每拉近1格便+1威力。" % str(effect['amount'])
		StrikeEffects.Push:
			if 'combine_multiple_into_one' in effect and effect['combine_multiple_into_one']:
				effect_str += "击退等量格。"
			elif str(effect['amount']) == "OPPONENT_SPEED":
				effect_str += "击退X。X等于对手的速度"
			elif str(effect['amount']) == "TOTAL_POWER":
				effect_str += "击退X。X等于该攻击的总威力"
			else:
				var extra_info = ""
				if 'save_buddy_spaces_entered_as_strike_x' in effect and effect['save_buddy_spaces_entered_as_strike_x']:
					extra_info = "\n将X设为对手被击退到%s上的次数" % effect['buddy_name']
				if 'save_unpushed_spaces_as_strike_x' in effect and effect['save_unpushed_spaces_as_strike_x']:
					extra_info = "\n将X设为其无法被继续击退的格数"
				effect_str += "击退" + str(effect['amount']) + extra_info
		StrikeEffects.PushSelf:
			effect_str += "被击退" + str(effect['amount'])
		StrikeEffects.PushFromSource:
			effect_str += "从攻击源击退%s" % str(effect['amount'])
		StrikeEffects.PullFromSource:
			effect_str += "朝攻击源拉近%s" % str(effect['amount'])
			if effect.get("skip_if_on_source"):
				effect_str += "（若已在攻击源上则跳过）"
		StrikeEffects.PushOrPullToAnySpace:
			effect_str += "击退或拉近到任意格。"
		StrikeEffects.PushOrPullToSpace:
			effect_str += "击退或拉近到格%s。" % str(effect['amount'])
		StrikeEffects.PushToAttackMaxRange:
			effect_str += "击退到攻击最大距离"
		StrikeEffects.PushToRange:
			effect_str += "击退到距离%s" % effect['amount']
		StrikeEffects.PushDamageDealt:
			effect_str += "击退等同于造成伤害的格数"
		StrikeEffects.RangeIncludesBoostSpace:
			effect_str += "你的射程包含此加成所在格"
		StrikeEffects.RangeIncludesIfMovedPast:
			effect_str += "若你越过对手，你的距离会包含其所在位置"
		StrikeEffects.Rangeup:
			if effect.get("opponent"):
				effect_str += "对手"
			if effect.get("special_only"):
				effect_str += "特殊技"
			if str(effect['amount']) != str(effect['amount2']):
				# Skip the first one if they're the same.
				if str(effect['amount']) == "strike_x":
					effect_str += "+X - "
				else:
					if effect['amount'] >= 0:
						effect_str += "+"
					effect_str += str(effect['amount']) + " - "
			if str(effect['amount2']) == "strike_x":
				effect_str += "+X"
			else:
				if effect['amount2'] >= 0:
					effect_str += "+"
				effect_str += str(effect['amount2'])
			effect_str += "距离"
		StrikeEffects.RangeupBothPlayers:
			effect_str += "双方"
			if effect['amount'] != effect['amount2']:
				# Skip the first one if they're the same.
				if effect['amount'] >= 0:
					effect_str += "+"
				effect_str += str(effect['amount']) + " - "
			if effect['amount2'] >= 0:
				effect_str += "+"
			effect_str += str(effect['amount2']) + "距离"
		StrikeEffects.RangeupIfExModifier:
			effect_str += "若为EX，+%s-%s距离。" % [str(effect['amount']), str(effect['amount2'])]
		StrikeEffects.RangeupPerBoostInPlay:
			if 'all_boosts' in effect and effect['all_boosts']:
				effect_str += "场上每有任意1张加成，+" + str(effect['amount']) + "-" + str(effect['amount2']) + "距离。"
			else:
				effect_str += "场上每有1张加成，+" + str(effect['amount']) + "-" + str(effect['amount2']) + "距离。"
		StrikeEffects.RangeupPerBoostModifier:
			if 'all_boosts' in effect and effect['all_boosts']:
				effect_str += "场上每有任意1张加成，+" + str(effect['amount']) + "-" + str(effect['amount2']) + "距离。"
			else:
				effect_str += "场上每有1张加成，+" + str(effect['amount']) + "-" + str(effect['amount2']) + "距离。"
		StrikeEffects.RangeupPerCardInHand:
			effect_str += "手牌中每有1张牌，+" + str(effect['amount']) + "-" + str(effect['amount2']) + "距离。"
		StrikeEffects.RangeupPerForceSpentThisTurn:
			effect_str += "本回合每花费1点能量，+" + str(effect['amount']) + "-" + str(effect['amount2']) + "距离。"
		StrikeEffects.RangeupPerSealedNormal:
			effect_str += "每有1张被封印的普通技，+" + str(effect['amount']) + "-" + str(effect['amount2']) + "距离。"
		StrikeEffects.RangeupDiscardedCardPrintedRange:
			effect_str += "+射程，数值等同于被弃牌的印刷射程。"
		StrikeEffects.RemoveBuddyNearOpponent:
			var offset_allowed = effect['offset_allowed']
			var same_space_allowed = effect['same_space_allowed']
			var optional = 'optional' in effect and effect['optional']
			var location_str = ""
			if same_space_allowed:
				location_str = "在"
			if offset_allowed == 1:
				if same_space_allowed:
					location_str += "或"
				location_str += "相邻于"
			var begin_str = ""
			if optional:
				begin_str = "你可以："
			effect_str += "%s将%s从对手%s所在格移出场" % [begin_str, effect['buddy_name'], location_str]
		StrikeEffects.ReduceDiscardAmount:
			effect_str += "弃牌效果减少%s" % effect['amount']
		StrikeEffects.RemoveXBuddies:
			effect_str += "移出场X个%s" % [effect['buddy_name']]
		StrikeEffects.RepeatEffectOptionally:
			effect_str += get_effect_text(effect['linked_effect'], false, false, false)
			var repeats = str(effect['amount'])
			if repeats != '0':
				if repeats == "every_two_sealed_normals":
					repeats = "每2张被封印的普通技可重复1次"
				elif repeats == "GAUGE_COUNT":
					repeats = "怒中每有1张可重复1次"
				else:
					repeats += "次"
				effect_str += "；你可以将此重复%s。" % repeats
		StrikeEffects.ReplaceWildSwing:
			var previous_attack_to = effect.get("previous_attack_to", "discard")
			if previous_attack_to == "gauge":
				effect_str += "加入怒并以接下来1张牌进行疯狂攻击"
			else:
				effect_str += "弃置并以接下来1张牌进行疯狂攻击"
		StrikeEffects.ReshuffleDiscardIntoDeck:
			effect_str += "将弃牌堆洗入牌库"
		StrikeEffects.ResetBonusArmorCounters:
			effect_str += "移除所有指示物"
		StrikeEffects.Retreat:
			if 'combine_multiple_into_one' in effect and effect['combine_multiple_into_one']:
				effect_str += "后退等量格。"
			else:
				effect_str += "后退"
				if str(effect['amount']) == "strike_x":
					effect_str += "X"
				else:
					effect_str += str(effect['amount'])
		StrikeEffects.RetreatInternal:
			effect_str += "后退"
			if str(effect['amount']) == "strike_x":
				effect_str += "X"
			else:
				effect_str += str(effect['amount'])
		StrikeEffects.ReturnAttackToHand:
			if 'card_name' in effect:
				effect_str += "将%s返回手牌" % effect['card_name']
			else:
				effect_str += "将该攻击返回你的手牌"
		StrikeEffects.ReturnAttackToTopOfDeck:
			effect_str += "将该攻击返回你的牌库顶"
		StrikeEffects.ReturnThisBoostToHandStrikeEffect:
			if 'card_name' in effect:
				effect_str += "将%s返回手牌" % effect['card_name']
			else:
				effect_str += "将此牌返回手牌"
		StrikeEffects.ReturnThisToHandImmediateBoost:
			if 'card_name' in effect:
				effect_str += "将%s返回手牌" % effect['card_name']
			else:
				effect_str += "将此牌返回手牌"
		StrikeEffects.ReturnAllCardsGaugeToHand:
			effect_str += "将怒中的所有牌返回手牌。"
		StrikeEffects.ReturnSealedWithSameSpeed:
			effect_str += "将1张与其速度相同的封印牌返回手牌。"
		StrikeEffects.RevealCopyForAdvantage:
			effect_str += "展示此攻击的1张复制以获得优势"
		StrikeEffects.RevealHand:
			if 'opponent' in effect and effect['opponent']:
				effect_str += "展示对手手牌"
			else:
				effect_str += "展示你的手牌"
		StrikeEffects.RevealHandAndTopdeck:
			if 'opponent' in effect and effect['opponent']:
				effect_str += "展示对手手牌和牌库顶牌"
			else:
				effect_str += "展示你的手牌和牌库顶牌"
		StrikeEffects.RevealTopdeck:
			if 'opponent' in effect and effect['opponent']:
				effect_str += "展示对手的牌库顶牌"
			else:
				effect_str += "展示牌库顶牌"
		StrikeEffects.RevealStrike:
			effect_str += "明置发起"
		StrikeEffects.Revert:
			effect_str += "退出觉醒"
		StrikeEffects.SavePower:
			effect_str += "你的印刷威力变为其威力"
		StrikeEffects.SkipEndOfTurnDraw:
			effect_str += "跳过你的回合结束抽牌"
		StrikeEffects.ReduceOpponentPrepareDraw:
			effect_str += "对手热身行动少摸1牌"
		StrikeEffects.UseSavedPowerAsPrintedPower:
			effect_str += "你的印刷威力改为展示牌的威力"
		StrikeEffects.UseTopDiscardAsPrintedPower:
			effect_str += "你的印刷威力改为弃牌堆顶牌的威力"
		StrikeEffects.Say:
			pass
		StrikeEffects.SetDanDrawChoiceInternal:
			if effect['from_bottom']:
				effect_str += "从牌库底抽牌"
			else:
				effect_str += "从牌库顶抽牌"
		StrikeEffects.SetStrikeX:
			if 'description' in effect:
				effect_str += effect['description']
			else:
				effect_str += "将X设为"
				match effect['source']:
					'random_gauge_power':
						effect_str += "随机怒牌的威力"
					'top_discard_power':
						effect_str += "弃牌堆顶牌的威力"
					'top_deck_power':
						effect_str += "牌库顶牌的威力"
					'opponent_speed':
						effect_str += "对手的速度"
					'cards_in_hand':
						effect_str += "手牌数量"
					'force_spent_before_strike':
						effect_str += "已花费的能量"
					'gauge_spent_before_strike':
						effect_str += "已花费的怒"
					'ultras_used_to_pay_gauge_cost':
						effect_str += "用于支付费用的必杀技数量"
					_:
						effect_str += "（未知）"
		StrikeEffects.SetTotalPower:
			effect_str += "你的总威力变为%s" % effect['amount']
		StrikeEffects.SealAttackOnCleanup:
			effect_str += "在整理阶段封印你的攻击"
		StrikeEffects.SealThis:
			if card_name_source:
				effect_str += "封印%s" % card_name_source
			else:
				effect_str += "封印此牌"
		StrikeEffects.SealThisBoost:
			if card_name_source:
				effect_str += "封印%s" % card_name_source
			else:
				effect_str += "封印此牌"
		StrikeEffects.SealTopdeck:
			if 'card_name' in effect:
				effect_str += "从你的牌库顶封印[color=%s]%s[/color]" % [CardHighlightColor, effect['card_name']]
			else:
				effect_str += "封印你的牌库顶牌"
		StrikeEffects.SelfDiscardChoose:
			var destination = effect['destination'] if 'destination' in effect else "discard"
			var limitation_str = ""
			var limitation = effect.get("limitation")
			if limitation:
				match limitation:
					"last_drawn_cards":
						limitation_str = "，从最近抽到的牌中"
					_:
						limitation_str = " " + effect['limitation']
			var bonus = ""
			var optional = 'optional' in effect and effect['optional']
			var optional_text = ""
			if optional:
				optional_text = "你可以："

			var amount_str = str(effect['amount'])
			if amount_str == "force_spent_before_strike":
				amount_str = "等量"
			if 'discard_effect' in effect:
				bonus= "\n以获得：" + get_effect_text(effect['discard_effect'], false, false, false)
				if 'per_discard' in effect['discard_effect'] and effect['discard_effect']['per_discard']:
					bonus += " 每张如此作"
			if destination == "sealed":
				effect_str += optional_text + "封印" + amount_str + limitation_str + "张牌" + bonus
			elif destination == "reveal":
				effect_str += optional_text + "展示" + amount_str + limitation_str + "张牌" + bonus
			elif destination == "opponent_overdrive":
				effect_str += optional_text + "将手中的" + amount_str + limitation_str + "张牌加入对手的超载区域" + bonus
			else:
				effect_str += optional_text + "弃置" + amount_str + limitation_str + "张牌" + bonus
		StrikeEffects.SetEndOfTurnBoostDelay:
			effect_str += "在回合结束时移除此加成"
		StrikeEffects.SetUsedCharacterBonus:
			if 'linked_effect' in effect:
				effect_str += "：" + get_effect_text(effect['linked_effect'], false, false, false)
		StrikeEffects.ShuffleHandToDeck:
			effect_str += "将手牌洗入牌库"
		StrikeEffects.ShuffleSealedToDeck:
			effect_str += "将封印牌洗入牌库"
		StrikeEffects.SidestepDialogue:
			effect_str += "所声明的牌本次战斗不会击中"
		StrikeEffects.SpecificCardDiscardToGauge:
			effect_str += "将弃牌堆中的1张%s复制加入怒" % effect['card_name']
		StrikeEffects.Speedup:
			if str(effect['amount']) == "strike_x":
				effect_str += "+X速度"
			else:
				if effect['amount'] > 0:
					effect_str += "+"
				#else: str() converts it to - already.
					#effect_str += "-"
				effect_str += str(effect['amount']) + "速度"
		StrikeEffects.SpeedupPerBoostInPlay:
			if 'all_boosts' in effect and effect['all_boosts']:
				effect_str += "场上每有任意1张加成，+" + str(effect['amount']) + "速度。"
			else:
				effect_str += "场上每有1张加成，+" + str(effect['amount']) + "速度。"
		StrikeEffects.SpeedupPerBoostModifier:
			if 'all_boosts' in effect and effect['all_boosts']:
				effect_str += "场上每有任意1张加成，+" + str(effect['amount']) + "速度。"
			else:
				effect_str += "场上每有1张加成，+" + str(effect['amount']) + "速度。"
		StrikeEffects.SpeedupPerForceSpentThisTurn:
			effect_str += "本回合每花费1点能量，+" + str(effect['amount']) + "速度。"
		StrikeEffects.SpendAllForceAndSaveAmount:
			effect_str += "将所有手牌/怒作为能量花费"
		StrikeEffects.SpendAllGaugeAndSaveAmount:
			effect_str += "弃置怒中的所有牌"
		StrikeEffects.SpendLife:
			effect_str += "花费" + str(effect['amount']) + "点生命"
		StrikeEffects.SetLife:
			effect_str += "将生命值设为" + str(effect['amount'])
		StrikeEffects.StartOfTurnStrike:
			effect_str += "战斗"
		StrikeEffects.Strike:
			effect_str += "战斗"
		StrikeEffects.StrikeWild:
			effect_str += "疯狂攻击"
			if 'card_name' in effect:
				effect_str += "（牌库顶为[color=%s]%s[/color]）" % [CardHighlightColor, effect['card_name']]
		"strike_with_buddy_card":
			effect_str += "%s（[color=%s]%s[/color]）" % [effect["buddy_name"], CardHighlightColor, effect.get('card_name', "")]
		StrikeEffects.StrikeFaceup:
			effect_str += "明置战斗"
		StrikeEffects.StrikeOpponentSetsFirst:
			effect_str += "战斗（对手先设置）"
		StrikeEffects.StrikeRandomFromGauge:
			effect_str += "以怒中的随机牌进行战斗（对手先设置）"
		StrikeEffects.StrikeResponseReading:
			if 'ex_card_id' in effect:
				effect_str += "EX战斗"
				if 'overload_name' in effect:
					effect_str += "（Overload：%s）" % effect['overload_name']
			else:
				effect_str += "战斗"
		StrikeEffects.StrikeWithEx:
			effect_str += "以EX进行战斗"
		StrikeEffects.StunImmunity:
			effect_str += "眩晕免疫"
		StrikeEffects.SustainAllBoosts:
			effect_str += "维持所有加成"
		StrikeEffects.SustainThis:
			if card_name_source:
				effect_str += "维持%s" % card_name_source
			else:
				effect_str += "维持此牌"
		StrikeEffects.SwapBuddy:
			effect_str += effect['description']
		StrikeEffects.SwapDeckAndDiscard:
			effect_str += "交换你的牌库与弃牌堆"
		StrikeEffects.SwapDeckAndSealed:
			effect_str += "将所有封印牌与牌库交换"
		StrikeEffects.SwapPowerSpeed:
			effect_str += "交换威力与速度"
		StrikeEffects.TakeBonusActions:
			if 'use_simple_description' in effect and effect['use_simple_description']:
				effect_str += "执行额外一动。"
			else:
				var amount = effect['amount']
				effect_str += "执行%s次行动。不能取消，且进行战斗会结束回合。" % str(amount)
		StrikeEffects.TakeDamage:
			var who_str = "受到"
			if 'opponent' in effect and effect['opponent']:
				who_str = "造成"
			var nonlethal_str = ""
			if 'nonlethal' in effect and effect['nonlethal']:
				nonlethal_str = "点非致命"
			effect_str += "%s%s%s伤害" % [who_str, str(effect['amount']), nonlethal_str]
		StrikeEffects.TransformAttack:
			if 'card_name' in effect:
				effect_str += "转化%s" % effect['card_name']
			else:
				effect_str += "转化攻击"
		StrikeEffects.AllowDuplicateNormalTransform:
			effect_str += "本回合可以拥有第二张同名普通技转化"
		StrikeEffects.MaySealTransformForGauge:
			effect_str += "可以封印转化牌来支付怒气费用"
		StrikeEffects.SealTransformForPowerup:
			effect_str += "封印1张转化牌，威力+%s" % effect.get("amount", 2)
		StrikeEffects.SealTransformForArmorup:
			effect_str += "封印1张转化牌，护甲+%s" % effect.get("amount", 2)
		StrikeEffects.TournelouseTransformAnyFromHand:
			effect_str += "可以转化任意数量手牌，然后抽3"
		StrikeEffects.TournelouseOuroboros:
			effect_str += "花费1能量，将1张手牌与1张转化牌交换"
		StrikeEffects.TopdeckFromHand:
			effect_str += "将手中的1张牌放到牌库顶"
		StrikeEffects.WhenHitForceForArmor:
			effect_str += ("当被击中时，每花费1点%s，获得%s点护甲。" % [
					"怒" if effect.get("use_gauge_instead", false) else "能量",
					effect["amount"]])
		StrikeEffects.ZeroVectorDialogue:
			effect_str += "所声明的牌对双方均无效"
		StrikeEffects.ZsoltNormalPassive:
			effect_str += "前进或者后退至多1格"
		StrikeEffects.SquiglyDarkTutelage:
			effect_str += "搜索牌库和弃牌堆，将至多2张同名普通技加入手牌，然后洗切牌库"
		StrikeEffects.SquiglyDarkTutelageTake:
			effect_str += "将所选同名普通技加入手牌，然后洗切牌库"
		StrikeEffects.SquiglyCroise:
			effect_str += "查看牌库顶3张牌，将其中1张加入手牌，然后洗切牌库；牌库不足时先按规则洗牌"
		StrikeEffects.SquiglyCenterStage:
			effect_str += "若中央格未被占据，移动到中央格，然后拉近1格"
		StrikeEffects.SquiglyReturnAttackAndCopies:
			effect_str += "将攻击牌及弃牌堆中所有同名牌返回手牌"
		_:
			effect_str += "缺失效果"
	return effect_str

func get_effect_text(effect, short = false, skip_timing = false, skip_condition = false, card_name_source : String = "", char_effect_panel : bool = false):
	if not card_name_source:
		if 'card_name' in effect:
			card_name_source = effect['card_name']
	var effect_str = ""
	if 'hide_effect' in effect and effect['hide_effect']:
		return effect_str
	if 'override_description' in effect:
		return effect['override_description']

	if 'timing' in effect and not skip_timing:
		effect_str += get_timing_text(effect['timing'])
	var effect_separator = ", "
	if char_effect_panel:
		effect_separator = "\n"

	var silent_effect = false
	if 'silent_effect' in effect and effect['silent_effect']:
		silent_effect = true
	if not silent_effect:
		if 'condition' in effect and not skip_condition:
			var amount = 0
			var amount2 = 0
			var detail = ""
			if 'condition_amount' in effect:
				amount = effect['condition_amount']
			if 'condition_amount_min' in effect:
				amount = effect['condition_amount_min']
			if 'condition_amount_max' in effect:
				amount2 = effect['condition_amount_max']
			if 'condition_amount2' in effect:
				amount2 = effect['condition_amount2']
			if 'condition_detail' in effect:
				detail = effect['condition_detail']
			effect_str += get_condition_text(effect, amount, amount2, detail)

		effect_str += get_effect_type_text(effect, card_name_source, char_effect_panel)

	var suppress_and_description = 'suppress_and_description' in effect and effect['suppress_and_description']
	if 'and' in effect and effect['and'] and not suppress_and_description:
		if effect_str != "":
			if "use_semicolon_for_and" in effect and effect['use_semicolon_for_and']:
				effect_str += "; "
			else:
				effect_str += effect_separator
		effect_str += get_effect_text(effect['and'], short, false, false, card_name_source, char_effect_panel)
	if 'negative_condition_effect' in effect:
		if not 'suppress_negative_description' in effect or not effect['suppress_negative_description']:
			effect_str += "; 否则" + get_effect_text(effect['negative_condition_effect'], short, skip_timing, false, card_name_source)

	# Remove unnecessary starting colons, e.g. from character_bonus effects
	if len(effect_str) >= 2 and effect_str.substr(0, 2) == ": ":
		effect_str = effect_str.substr(2)
	return effect_str

func get_effects_text(effects):
	var effects_str = ""
	for effect in effects:
		var effect_text = get_effect_text(effect)
		if effect_text:
			effects_str += effect_text + "\n"
	return effects_str

func get_on_exceed_text(on_exceed_ability):
	if not on_exceed_ability:
		return ""
	var effect_type = on_exceed_ability['effect_type']
	match effect_type:
		StrikeEffects.JingleChunShuiOnExceed:
			return "当你觉醒时：抽1张牌，然后双方各受到2点非致命伤害\n"
		StrikeEffects.Strike:
			return "当你觉醒时：战斗\n"
		StrikeEffects.Draw:
			return "当你觉醒时：抽%s" % on_exceed_ability['amount'] + "\n"
		_:
			return "缺失觉醒效果\n"

func get_boost_text(effects):
	return get_effects_text(effects)
