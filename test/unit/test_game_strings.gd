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