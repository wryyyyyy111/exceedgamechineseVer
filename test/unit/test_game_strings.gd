extends GutTest

const GameStringsScript = preload("res://globals/game_strings.gd")

func test_normal_card_name_is_localized_in_combat_output():
	var game_strings = GameStringsScript.new()
	var card_names = {
		"grasp": "投技",
		"cross": "游击",
		"assault": "突袭",
		"dive": "飞踢",
		"spike": "刺拳",
		"sweep": "横扫",
		"focus": "专注",
		"block": "格挡",
	}

	for english_name in card_names:
		assert_eq(
			game_strings.get_display_name_with_speed({ "display_name": english_name, "type": "normal", "speed": 7 }),
			"%s（普7速）" % card_names[english_name]
		)

func test_unmapped_card_name_is_preserved_in_combat_output():
	var game_strings = GameStringsScript.new()

	assert_eq(
		game_strings.get_display_name_with_speed({ "display_name": "Custom Strike", "type": "special", "speed": 3 }),
		"Custom Strike（特3速）"
	)

func test_s8_card_names_include_type_and_speed_suffix():
	var game_strings = GameStringsScript.new()
	var s8_cards = [
		[{ "display_name": "Grasp", "type": "normal", "speed": 7 }, "投技（普7速）"],
		[{ "display_name": "Leap", "type": "special", "speed": 3 }, "Leap（特3速）"],
		[{ "display_name": "Titanic Slam", "type": "ultra", "speed": 5 }, "Titanic Slam（必5速）"],
	]

	for test_case in s8_cards:
		assert_eq(game_strings.get_display_name_with_speed(test_case[0]), test_case[1])

func test_effect_per_card_in_zone_includes_range_limitation_text():
	var game_strings = GameStringsScript.new()
	var effect = {
		"effect_type": StrikeEffects.EffectPerCardInZone,
		"limitation": "range_to_opponent",
		"per_card_effect": {
			"effect_type": StrikeEffects.Powerup,
			"amount": 3,
		},
		"zone": "stored_cards",
		"zone_name": "Diabolic Aura",
	}

	assert_eq(
		game_strings.get_effect_text(effect),
		"+3威力，Diabolic Aura中每有1张牌，其距离可命中对手"
	)

func _assert_yuanliuzhai_text(text: String, context: String):
	for placeholder in ["缺失", "未知", "MISSING"]:
		assert_false(text.contains(placeholder), "%s: %s" % [context, text])

func _check_yuanliuzhai_effect(effect: Dictionary, context: String):
	# Characterize the current missing renderer without treating it as complete text.
	if effect["effect_type"] == "pull_not_past":
		assert_eq(GameStrings.get_effect_text(effect), "[b]击中：[/b] 缺失效果", context + " current full text")
		assert_eq(GameStrings.get_effect_type_text(effect), "缺失效果", context + " current body")
	else:
		_assert_yuanliuzhai_text(GameStrings.get_effect_text(effect), context + " full")
		_assert_yuanliuzhai_text(GameStrings.get_effect_type_text(effect), context + " body")
	_assert_yuanliuzhai_text(GameStrings.get_effect_type_heading(effect), context + " heading")
	_assert_yuanliuzhai_text(GameStrings.get_choice_summary([effect], ""), context + " summary")
	if effect["effect_type"] != StrikeEffects.Pass and not effect.get("hide_effect", false):
		assert_false(GameStrings.get_effect_type_text(effect).is_empty(), context + " body must describe the effect")
		assert_false(GameStrings.get_effect_type_heading(effect).is_empty(), context + " heading must describe the effect")
		assert_false(GameStrings.get_effect_text(effect).is_empty(), context + " full text must be visible")
	if effect.has("timing"):
		_assert_yuanliuzhai_text(GameStrings.get_timing_text(effect["timing"]), context + " timing")
	if effect.has("condition"):
		_assert_yuanliuzhai_text(
			GameStrings.get_condition_text(effect, effect.get("condition_amount", 0), 0, ""),
			context + " condition"
		)
	for key in ["and", "negative_condition_effect", "added_effect"]:
		if effect.get(key) is Dictionary:
			_check_yuanliuzhai_effect(effect[key], context + "." + key)
	for index in range(effect.get("choice", []).size()):
		_check_yuanliuzhai_effect(effect["choice"][index], "%s.choice[%d]" % [context, index])

func test_yuanliuzhai_all_runtime_effect_text_paths_match_current_baseline():
	var deck = CardDataManager.get_deck_from_str_id("yuanliuzhai")
	CardDataManager.load_custom_cards(deck["custom_card_definitions"])
	for key in ["ability_effects", "exceed_ability_effects"]:
		for effect in deck[key]:
			_check_yuanliuzhai_effect(effect, key)
	for key in ["character_action_default", "character_action_exceeded"]:
		for action in deck[key]:
			_check_yuanliuzhai_effect(action["effect"], key)
	var checked_definitions = {}
	for entry in deck["cards"]:
		var definition_id = entry["definition_id"]
		if checked_definitions.has(definition_id):
			continue
		checked_definitions[definition_id] = true
		var definition = CardDataManager.get_card(definition_id)
		for effect in definition["effects"]:
			_check_yuanliuzhai_effect(effect, definition_id + " attack")
		for effect in definition["boost"]["effects"]:
			_check_yuanliuzhai_effect(effect, definition_id + " boost")
	assert_eq(checked_definitions.size(), 15)

func test_yuanliuzhai_range_x_text_matches_runtime_source_fields():
	var expected = "将X设为此时自己到对手的距离"
	for source_key in ["source", "special_amount"]:
		var effect = {"effect_type": StrikeEffects.SetStrikeX, source_key: "RANGE_TO_OPPONENT"}
		assert_eq(GameStrings.get_effect_type_text(effect), expected)
		assert_eq(GameStrings.get_choice_summary([effect], ""), expected)
	assert_eq(GameStrings.get_timing_text("on_strike_reveal"), "揭示攻击牌后：")
	assert_eq(GameStrings.get_timing_text("counter_boost"), "对手打出加成后、效果结算前：")

func test_yuanliuzhai_action_and_reaction_text_describes_actual_effects():
	var deck = CardDataManager.get_deck_from_str_id("yuanliuzhai")
	var action_texts = {
		"character_action_default": ["抽1", "若威压区没有牌，摸1张牌。"],
		"character_action_exceeded": ["从手牌中将1张牌加入威压区", "若威压区没有牌，将1张手牌正面朝上置入威压区。"],
	}
	for key in action_texts:
		var effect = deck[key][0]["effect"]
		assert_eq(GameStrings.get_effect_type_text(effect), action_texts[key][0])
		assert_eq(GameStrings.get_effect_text(effect), action_texts[key][1])
	var descriptions = {
		"yuanliuzhai_discard_pressure": "弃置威压区中所有未受保护的牌",
		"yuanliuzhai_start_turn": "若未觉醒，将威压区所有未受保护的牌置入怒气区；然后解除城郭炎上的保护",
		"yuanliuzhai_exceed_discard_pressure": "弃置威压区中所有未受保护的牌；若以此法弃置了牌，摸1张牌",
		"yuanliuzhai_boost_to_pressure_if_empty": "若威压区没有牌，将此牌置入威压区",
		"yuanliuzhai_jokaku_hit": "获得优势并将此牌置入威压区；此牌在自己的下个回合开始前不会从威压区弃置，且跳过该次回合开始的转怒，随后保护失效",
		"yuanliuzhai_ryujin_execute": "若此攻击击中且对手当前生命低于6，对其造成99点伤害",
		"yuanliuzhai_counter_cards": "对手打出持续性加成后可发动森罗；对手打出包含自身移动的加成后可发动威眠；均在效果结算前响应，也可以不响应",
		"yuanliuzhai_activate_shinra": "从手牌弃置森罗并支付2点生命，弃置双方所有持续性加成并无效当前加成；对手仍可按规则取消",
		"yuanliuzhai_activate_imin": "从手牌弃置威眠并支付2点生命，阻止该张加成离场前的所有自身前进、后退和逼近；其他效果照常结算",
	}
	for effect_type in descriptions:
		var effect = {"effect_type": effect_type}
		assert_eq(GameStrings.get_effect_type_text(effect), descriptions[effect_type])
		assert_eq(GameStrings.get_choice_summary([effect], ""), descriptions[effect_type])
		assert_eq(GameStrings.get_effect_type_heading(effect), descriptions[effect_type])

func test_yuanliuzhai_jokaku_protection_text_matches_turn_start_order():
	var deck = CardDataManager.get_deck_from_str_id("yuanliuzhai")
	CardDataManager.load_custom_cards(deck["custom_card_definitions"])
	var turn_effect = deck["ability_effects"][2]
	assert_eq(turn_effect["effect_type"], "yuanliuzhai_start_turn")
	assert_eq(GameStrings.get_effect_text(turn_effect), "自己的回合开始时：将威压区中所有未受保护的牌置入怒气区，然后解除城郭炎上的保护。")
	var card = CardDataManager.get_card("yuanliuzhai_jokaku_enjo")
	var hit_effect = card["effects"][2]
	assert_eq(hit_effect["effect_type"], "yuanliuzhai_jokaku_hit")
	assert_eq(GameStrings.get_effect_text(hit_effect), "焚烧·击中：获得优势，将此牌置入威压区；此牌受保护，不会在自己的下个回合开始前从威压区弃置，该次回合开始时也保留在威压区，随后保护失效。")

func _assert_heiqiyihu_text(text: String, context: String):
	for placeholder in ["缺失", "MISSING", "未知效果"]:
		assert_false(text.contains(placeholder), "%s: %s" % [context, text])

func _check_heiqiyihu_effect_text(effect: Dictionary, context: String):
	var full_text = GameStrings.get_effect_text(effect)
	var body = GameStrings.get_effect_type_text(effect)
	_assert_heiqiyihu_text(full_text, context + " full")
	_assert_heiqiyihu_text(body, context + " body")
	_assert_heiqiyihu_text(GameStrings.get_choice_summary([effect], ""), context + " summary")
	if effect.get("effect_type") != StrikeEffects.Pass and not effect.get("hide_effect", false):
		assert_false(full_text.is_empty(), context + " full text must be visible")
		assert_false(body.is_empty(), context + " body must describe the effect")
	if effect.has("amount"):
		_assert_heiqiyihu_text(GameStrings.get_effect_type_heading(effect), context + " heading")
	if effect.has("timing"):
		_assert_heiqiyihu_text(GameStrings.get_timing_text(effect["timing"]), context + " timing")
	if effect.has("condition"):
		_assert_heiqiyihu_text(
			GameStrings.get_condition_text(effect, effect.get("condition_amount", 0), 0, ""),
			context + " condition")
	for key in ["and", "negative_condition_effect", "per_force_effect", "overall_effect", "added_effect"]:
		if effect.get(key) is Dictionary:
			_check_heiqiyihu_effect_text(effect[key], context + "." + key)
	for index in range(effect.get("choice", []).size()):
		var option = effect["choice"][index]
		if option.has("_choice_text"):
			assert_false(str(option["_choice_text"]).is_empty(), context + " choice must be visible")
			_assert_heiqiyihu_text(option["_choice_text"], context + " button")
		_check_heiqiyihu_effect_text(option, "%s.choice[%d]" % [context, index])

func test_heiqiyihu_all_fifteen_runtime_cards_and_character_effects_have_text():
	var deck = CardDataManager.get_deck_from_str_id("heiqiyihu")
	CardDataManager.load_deck_if_custom(deck)
	for key in ["ability_effects", "exceed_ability_effects"]:
		for effect in deck[key]:
			_check_heiqiyihu_effect_text(effect, key)
	_check_heiqiyihu_effect_text(deck["on_exceed"], "on_exceed")
	var definitions = {}
	for entry in deck["cards"]:
		var definition_id = entry["definition_id"]
		if definitions.has(definition_id):
			continue
		definitions[definition_id] = true
		var definition = CardDataManager.get_card(definition_id)
		for effect in definition["effects"]:
			_check_heiqiyihu_effect_text(effect, definition_id + " attack")
		for effect in definition["boost"]["effects"]:
			_check_heiqiyihu_effect_text(effect, definition_id + " boost")
	assert_eq(definitions.size(), 15)

func test_heiqiyihu_custom_effect_bodies_headings_and_summaries_describe_rules():
	var descriptions = {
		"heiqiyihu_guardian_thresholds": "未觉醒时，生命值降至25、15、10或以下，每个阈值每局一次，将牌堆顶或1张手牌置入守护区。",
		"heiqiyihu_guardian_before_set": "任意一方宣战后、双方选择攻击牌前，你可以弃置1张守护卡免费触发其加成。特殊技守护加成的效果数值+1；发起战斗的子效果无效。",
		"heiqiyihu_guardian_resources": "每张守护卡可作为1怒气，或按通常能量值支付。你正常打出的特殊技和必杀技加成可支付1怒气取消，仍受通常取消规则限制。",
		"heiqiyihu_threshold_source": "将牌堆顶1张牌置入守护区",
		"heiqiyihu_exceed_draw": "立刻抽守护卡数量×2张牌，至少抽2张；本回合不因手牌上限弃牌。",
		"heiqiyihu_getsuga_cleanup": "依次弃置所有手牌、所有怒气区的牌，将此牌置入守护区，然后觉醒。已经觉醒时不再觉醒。",
		"heiqiyihu_add_guardian": "将牌堆顶的牌或1张手牌置入守护区。",
		"heiqiyihu_guardian_source": "将牌堆顶1张牌置入守护区",
		"heiqiyihu_xuhua_payment": "对手所有击中效果结算后、伤害与击晕判定前，可以支付至多2能量，每点霸体+1。",
		"heiqiyihu_xuhua_recover": "从本次虚化实际消耗且仍在弃牌堆的牌中选1张置入守护区；若还有另一张，将它置入怒气区。",
		"heiqiyihu_xuhua_recover_card": "将选中的牌置入守护区",
		"heiqiyihu_pull_adjacent": "选择将对手拉近至你左侧或右侧的合法相邻格。",
		"heiqiyihu_shunbu_crossed": "对手视为在你的攻击距离内，并且无视霸体。",
		"heiqiyihu_huhuan_guardian": "本次战斗触发过守护时，此牌怒气费用替换为3。此牌为有效攻击时，特殊技守护加成效果数值再+1。",
		"heiqiyihu_prevent_opponent_moving_me": "对手不能移动你；不影响你自己的移动或对手自身移动。",
		"move_strike_to_bleach": "将此攻击牌置入守护区",
	}
	for effect_type in descriptions:
		var effect = {"effect_type": effect_type}
		assert_eq(GameStrings.get_effect_type_text(effect), descriptions[effect_type], effect_type + " body")
		assert_eq(GameStrings.get_effect_type_heading(effect), descriptions[effect_type], effect_type + " heading")
		assert_eq(GameStrings.get_choice_summary([effect], ""), descriptions[effect_type], effect_type + " summary")
	for effect_type in [StrikeEffects.HeiqiyihuThresholdSource, StrikeEffects.HeiqiyihuGuardianSource]:
		assert_eq(GameStrings.get_effect_type_text({"effect_type": effect_type, "source": "hand"}),
			"将选中的1张手牌置入守护区")
	assert_eq(GameStrings.get_effect_type_text({
		"effect_type": StrikeEffects.HeiqiyihuXuhuaRecoverCard, "destination": "gauge"
	}), "将选中的牌置入怒气区")

func test_heiqiyihu_on_exceed_text_describes_draw_and_hand_limit():
	var effect = CardDataManager.get_deck_from_str_id("heiqiyihu")["on_exceed"]
	var expected = "当你觉醒时：立刻抽守护卡数量×2张牌，至少抽2张；本回合不因手牌上限弃牌。\n"
	assert_eq(GameStrings.get_on_exceed_text(effect), expected)
	var without_override = effect.duplicate(true)
	without_override.erase("override_description")
	assert_eq(GameStrings.get_on_exceed_text(without_override), expected)
	assert_eq(GameStrings.get_timing_text("passive"), "")

func test_heiqiyihu_range_summary_preserves_both_range_values():
	var effect = {"effect_type": StrikeEffects.Rangeup, "amount": 0, "amount2": 1}
	assert_eq(GameStrings.get_choice_summary([effect], ""), "+0 - +1距离")
	effect["amount"] = 1
	effect["amount2"] = 2
	assert_eq(GameStrings.get_choice_summary([effect], ""), "+1 - +2距离")

func test_heiqiyihu_dynamic_choice_text_preserves_card_names_and_pass():
	var choices = [
		{"effect_type": "heiqiyihu_guardian_before_set", "_choice_text": "触发守护「地裂崩击」"},
		{"effect_type": "heiqiyihu_guardian_before_set", "_choice_text": "不触发守护"},
		{"effect_type": StrikeEffects.HeiqiyihuThresholdSource, "source": "hand", "_choice_text": "将手牌「瞬步」置入守护区"},
		{"effect_type": StrikeEffects.HeiqiyihuXuhuaRecoverCard, "destination": "gauge", "_choice_text": "将「虚化」置入怒气区"},
	]
	for choice in choices:
		assert_eq(GameStrings.get_effect_text(choice), choice["_choice_text"])
		assert_eq(GameStrings.get_choice_summary([choice], ""), choice["_choice_text"])