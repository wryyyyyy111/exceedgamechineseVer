extends GutTest

const TestCards = [
	{"id": "test_hint_normal", "type": "normal", "speed": 0},
	{"id": "test_hint_special", "type": "special", "speed": 3},
	{"id": "test_hint_ultra", "type": "ultra", "speed": "X"},
	{"id": "test_hint_missing_speed", "type": "normal"},
	{"id": "test_hint_other_type", "type": "other", "speed": 7},
	{"id": "test_hint_special_a", "display_name": "Hint Alpha", "type": "special", "speed": 5.0, "power": 7.0},
	{"id": "test_hint_special_b", "display_name": "Hint Beta", "type": "special", "speed": 5, "power": 4},
	{"id": "test_hint_normal_a", "display_name": "Hint Normal A", "type": "normal", "speed": 5, "power": "N/A"},
	{"id": "test_hint_normal_b", "display_name": "Hint Normal B", "type": "normal", "speed": 5},
	{"id": "test_hint_ultra_a", "display_name": "Hint Ultra A", "type": "ultra", "speed": 5, "power": "X"},
	{"id": "test_hint_ultra_b", "display_name": "Hint Ultra B", "type": "ultra", "speed": 5, "power": 9},
]

func before_each():
	CardDataManager.load_custom_cards(TestCards)

func after_each():
	for card in TestCards:
		CardDataManager.card_data.erase(card["id"])
	CardDataManager.decks.erase("test_hint_deck")
	CardDataManager.decks.erase("test_hint_other_deck")
	CardDataManager._custom_card_name_decks.erase("test_hint_runtime_deck")
	CardDataManager.invalidate_card_name_index()

func test_same_type_speed_in_one_deck_adds_printed_power_for_all_types():
	CardDataManager.decks["test_hint_deck"] = {"cards": [
		{"definition_id": "test_hint_special_a"},
		{"definition_id": "test_hint_special_a"},
		{"definition_id": "test_hint_special_b", "set_aside": true},
		{"definition_id": "test_hint_normal_a"},
		{"definition_id": "test_hint_normal_b"},
		{"definition_id": "test_hint_ultra_a"},
		{"definition_id": "test_hint_ultra_b"},
	]}
	var text = "Hint Alpha；test_hint_special_b；Hint Normal A；Hint Normal B；Hint Ultra A；Hint Ultra B"
	var expected = "Hint Alpha（特5速7攻）；test_hint_special_b（特5速4攻）；Hint Normal A（普5速N/A攻）；Hint Normal B（普5速0攻）；Hint Ultra A（必5速X攻）；Hint Ultra B（必5速9攻）"
	assert_eq(GameStrings.add_card_id_speed_hints(text), expected)
	assert_eq(GameStrings.add_card_id_speed_hints(expected), expected)
	assert_eq(GameStrings.get_display_name_with_speed(TestCards[5]), "Hint Alpha（特5速7攻）")
	var tagged = "[url=Hint Alpha][b]Hint Alpha[/b][/url](特5速7攻)"
	assert_eq(GameStrings.add_card_id_speed_hints(tagged), tagged)
	var legacy_tagged = "[b]Hint Alpha[/b]（特速5攻7）"
	assert_eq(GameStrings.add_card_id_speed_hints(legacy_tagged), legacy_tagged)

func test_copies_other_types_and_other_decks_do_not_add_power():
	CardDataManager.decks["test_hint_deck"] = {"cards": [
		{"definition_id": "test_hint_special_a"},
		{"definition_id": "test_hint_special_a"},
		{"definition_id": "test_hint_normal_a"},
		{"definition_id": "test_hint_ultra_a"},
	]}
	CardDataManager.decks["test_hint_other_deck"] = {"cards": [
		{"definition_id": "test_hint_special_b"},
	]}
	assert_eq(GameStrings.add_card_id_speed_hints("Hint Alpha；Hint Beta；Hint Normal A；Hint Ultra A"),
		"Hint Alpha（特5速）；Hint Beta（特5速）；Hint Normal A（普5速）；Hint Ultra A（必5速）")

func test_ragna_same_speed_specials_get_power_in_menu_and_boost_summary():
	var text = "Dead Spike；Gauntlet Hades；Hell's Fang"
	var expected = "Dead Spike（特3速5攻）；Gauntlet Hades（特3速4攻）；Hell's Fang（特4速）"
	var definitions = [CardDataManager.get_card("ragna_deadspike"), CardDataManager.get_card("ragna_gauntlethades"), CardDataManager.get_card("ragna_hellsfang")]
	assert_eq(GameStrings.add_card_id_speed_hints(text, definitions), expected)
	var menu = load("res://scenes/game/action_menu.tscn").instantiate()
	add_child_autofree(menu)
	menu.set_choices(text, [{"text": text}], false, -1, -1, false, false, false, -1, definitions)
	assert_eq(menu.instructions_label.text, "[center]%s[/center]" % expected)
	assert_eq(menu.choice_buttons_grid.get_child(0).get_child(1).get_child(0).text, "[center]%s[/center]" % expected)
	var zone = load("res://scenes/game/boost_zone.tscn").instantiate()
	add_child_autofree(zone)
	zone.set_text(text, definitions)
	assert_eq(zone.boost_effects.text, expected)
	assert_eq(GameStrings.add_card_id_speed_hints("Barnstorming；Cabstand"),
		"Barnstorming（特5速3攻）；Cabstand（特5速3攻）")

func test_adds_printed_speed_for_each_card_type_and_occurrence():
	var text = "选择test_hint_normal、test_hint_special或test_hint_ultra。\n再次test_hint_special"
	var expected = "选择test_hint_normal（普0速）、test_hint_special（特3速）或test_hint_ultra（必X速）。\n再次test_hint_special（特3速）"
	assert_eq(GameStrings.add_card_id_speed_hints(text), expected)
	assert_eq(GameStrings.add_card_id_speed_hints(expected), expected)

func test_preserves_existing_full_width_and_ascii_hints():
	var text = "test_hint_normal（普0速） test_hint_special(特3速) test_hint_ultra（必X速）"
	assert_eq(GameStrings.add_card_id_speed_hints(text), text)

func test_preserves_bbcode_attributes_and_hints_outside_closing_tags():
	var text = "[url=test_hint_special][b]test_hint_special[/b][/url]（特3速）"
	assert_eq(GameStrings.add_card_id_speed_hints(text), text)
	assert_eq(
		GameStrings.add_card_id_speed_hints("[color=cyan]test_hint_special[/color]"),
		"[color=cyan]test_hint_special（特3速）[/color]"
	)

func test_only_matches_complete_known_ids_with_applicable_hints():
	var text = "unknown_id test_hint_special_extra prefix_test_hint_normal test_hint_missing_speed test_hint_other_type"
	assert_eq(GameStrings.add_card_id_speed_hints(text), text)
	assert_eq(GameStrings.add_card_id_speed_hints(""), "")

func test_supports_loaded_standard_card_definitions():
	var definition = CardDataManager.get_card("ryu_hadoken")
	assert_eq(
		GameStrings.add_card_id_speed_hints("ryu_hadoken"),
		"ryu_hadoken" + GameStrings.get_speed_description(definition)
	)

func test_flight_13_transform_choice_shows_speed_in_action_menu():
	var menu = load("res://scenes/game/action_menu.tscn").instantiate()
	add_child_autofree(menu)
	var definition = CardDataManager.get_card("minato_flight_13")
	var choice = {"effect_type": StrikeEffects.TransformAttack, "card_name": definition["display_name"]}
	menu.set_choices("选择一个效果：", [
		{"text": GameStrings.get_effect_text(choice, false, true)},
		{"text": "跳过"},
	], false, -1, -1, false, false, false)
	var label = menu.choice_buttons_grid.get_child(0).get_child(1).get_child(0)
	assert_eq(label.text, "[center]转化Flight 13（特4速）[/center]")

func test_display_names_and_localized_normal_names_get_hints():
	var text = "转化Flight 13；投技；Grasp；[b]Flight 13[/b]（特4速）"
	assert_eq(
		GameStrings.add_card_id_speed_hints(text),
		"转化Flight 13（特4速）；投技（普7速）；Grasp（普7速）；[b]Flight 13[/b]（特4速）"
	)
	assert_eq(
		GameStrings.add_card_id_speed_hints("Flight 130 prefixFlight 13 Flight 13_extra"),
		"Flight 130 prefixFlight 13 Flight 13_extra"
	)

func test_boost_summary_display_names_get_hints():
	var zone = load("res://scenes/game/boost_zone.tscn").instantiate()
	add_child_autofree(zone)
	zone.set_text("Flight 13：投技获得+1威力")
	assert_eq(zone.boost_effects.text, "Flight 13（特4速）：投技（普7速）获得+1威力")
	zone.set_text(zone.boost_effects.text)
	assert_eq(zone.boost_effects.text.count("（特4速）"), 1)

func test_display_name_matching_preserves_tags_and_regex_punctuation():
	var definition = {"id": "test_punctuation", "display_name": "Hint (EX)+", "type": "ultra", "speed": 5}
	var text = "[url=Hint (EX)+]Hint (EX)+[/url]；Hint (EX)+（必5速）"
	assert_eq(
		GameStrings.add_card_id_speed_hints(text, [definition]),
		"[url=Hint (EX)+]Hint (EX)+（必5速）[/url]；Hint (EX)+（必5速）"
	)

func test_same_named_cards_use_context_instead_of_another_decks_speed():
	var fast = CardDataManager.get_card("zato_leap")
	var slow = CardDataManager.get_card("zacoal_leap")
	assert_eq(GameStrings.add_card_id_speed_hints("Leap", [fast]), "Leap（特5速）")
	assert_eq(GameStrings.add_card_id_speed_hints("Leap", [slow]), "Leap（特3速7攻）")
	assert_eq(GameStrings.add_card_id_speed_hints("Leap", [fast, slow]), "Leap")
	var menu = load("res://scenes/game/action_menu.tscn").instantiate()
	add_child_autofree(menu)
	menu.set_choices("Leap", [{"text": "Leap"}],
		false, -1, -1, false, false, false, -1, [fast])
	assert_eq(menu.instructions_label.text, "[center]Leap（特5速）[/center]")
	assert_eq(menu.choice_buttons_grid.get_child(0).get_child(1).get_child(0).text,
		"[center]Leap（特5速）[/center]")
	var zone = load("res://scenes/game/boost_zone.tscn").instantiate()
	add_child_autofree(zone)
	zone.set_text("Leap", [slow])
	assert_eq(zone.boost_effects.text, "Leap（特3速7攻）")

func test_longest_name_is_not_partially_annotated_when_its_hint_is_unavailable():
	var definitions = [
		{"display_name": "Hint Strike", "type": "special", "speed": 3},
		{"display_name": "Hint Strike EX", "type": "special"},
	]
	assert_eq(
		GameStrings.add_card_id_speed_hints("Hint Strike EX；Hint Strike", definitions),
		"Hint Strike EX；Hint Strike（特3速）"
	)

func test_effect_choice_with_runtime_card_id_uses_that_cards_printed_speed():
	var game_ui = autofree(Game.new())
	game_ui.add_child(game_ui.game_wrapper)
	assert_eq(game_ui.ChoiceTagRegex.compile("\\[.*\\]"), OK)
	var game_logic = autofree(LocalGame.new(null))
	autofree(game_logic.decision_info)
	var card_db = autofree(CardDatabase.new(null))
	game_logic.card_db = card_db
	game_ui.game_wrapper.current_game = game_logic
	var definition = CardDataManager.get_card("zato_leap")
	var card = autofree(GameCard.new(60000, definition, Enums.PlayerId.PlayerId_Player))
	card_db.add_card(card)
	assert_eq(game_ui.get_effect_text_with_card_name({
		"effect_type": StrikeEffects.TransformAttack,
		"card_id": card.id,
		"card_name": definition["display_name"],
	}, ""), "转化Leap（特5速）")

func test_action_menu_annotates_instructions_and_all_visible_choices():
	var menu = load("res://scenes/game/action_menu.tscn").instantiate()
	add_child_autofree(menu)
	var choices = [
		{"text": "test_hint_normal"},
		{"text": "test_hint_special", "disabled": true},
		{"text": "[b]test_hint_ultra（必X速）[/b]"},
	]
	menu.set_choices("选择test_hint_special", choices, false, -1, -1, false, false, false)
	assert_eq(menu.instructions_label.text, "[center]选择test_hint_special（特3速）[/center]")
	var expected = [
		"[center]test_hint_normal（普0速）[/center]",
		"[center]test_hint_special（特3速）[/center]",
		"[center][b]test_hint_ultra（必X速）[/b][/center]",
	]
	for index in choices.size():
		var container = menu.choice_buttons_grid.get_child(index)
		assert_eq(container.get_child(1).get_child(0).text, expected[index])
	assert_true(menu.choice_buttons_grid.get_child(1).get_child(0).disabled)
	assert_eq(choices[0]["text"], "test_hint_normal")

func test_boost_zones_annotate_multiline_text_without_changing_visibility():
	for side in ["player", "opponent"]:
		var zone = load("res://scenes/game/boost_zone.tscn").instantiate()
		add_child_autofree(zone)
		zone.effects_visible = false
		zone.set_text("[b]test_hint_special[/b]\ntest_hint_ultra（必X速）")
		assert_eq(zone.boost_effects.text, "[b]test_hint_special（特3速）[/b]\ntest_hint_ultra（必X速）", side)
		assert_false(zone.boost_effects.visible, side)
		zone.set_text(zone.boost_effects.text)
		assert_eq(zone.boost_effects.text.count("（特3速）"), 1, side)

func test_context_matcher_reuses_copies_but_changes_with_printed_stats():
	CardDataManager.decks["test_hint_deck"] = {"cards": [
		{"definition_id": "test_hint_special_a"}, {"definition_id": "test_hint_special_b"},
	]}
	var definition = TestCards[5].duplicate()
	var index = CardDataManager.get_card_name_index()
	var matcher = index.get_matcher([definition])
	assert_same(index.get_matcher([definition.duplicate(), definition]), matcher)
	assert_eq(matcher.annotate("Hint Alpha"), "Hint Alpha（特5速7攻）")
	definition["power"] = 12
	assert_ne(index.get_matcher([definition]), matcher)
	assert_eq(index.get_matcher([definition]).annotate("Hint Alpha"), "Hint Alpha（特5速12攻）")

func test_loading_custom_deck_and_replacing_card_refreshes_warm_hints():
	assert_eq(GameStrings.add_card_id_speed_hints("Hint Alpha"), "Hint Alpha（特5速）")
	CardDataManager.load_deck_if_custom({
		"id": "test_hint_runtime_deck",
		"cards": [{"definition_id": "test_hint_special_a"}, {"definition_id": "test_hint_special_b"}],
		"custom_card_definitions": [TestCards[5].duplicate(), TestCards[6].duplicate()],
	})
	assert_eq(GameStrings.add_card_id_speed_hints("Hint Alpha"), "Hint Alpha（特5速7攻）")
	var updated = TestCards[5].duplicate()
	updated["power"] = 12
	CardDataManager.load_custom_cards([updated])
	assert_eq(GameStrings.get_speed_description(updated), "（特5速12攻）")
	assert_eq(GameStrings.add_card_id_speed_hints("test_hint_special_a"), "test_hint_special_a（特5速12攻）")
	updated = updated.duplicate()
	updated["speed"] = 6
	CardDataManager.load_custom_cards([updated])
	assert_eq(GameStrings.add_card_id_speed_hints("Hint Alpha"), "Hint Alpha（特6速）")

func test_skin_image_indices_do_not_override_printed_speed_or_power():
	var base_a = {"id": "base_a", "display_name": "Skin Alpha", "type": "special", "speed": 5, "power": 7}
	var base_b = {"id": "base_b", "display_name": "Skin Beta", "type": "special", "speed": 5, "power": 4}
	var skin_a = {"id": "skin_a", "display_name": "Skin Alpha", "type": "special", "speed": 6, "power": 12}
	var skin_b = {"id": "skin_b", "display_name": "Skin Beta", "type": "special", "speed": 6, "power": 9}
	var index = CardDataManager.CardNameIndexScript.new()
	index.rebuild({"base_a": base_a, "base_b": base_b, "skin_a": skin_a, "skin_b": skin_b}, {
		"base": {"cards": [{"definition_id": "base_a", "image_index": 0}, {"definition_id": "base_b", "image_index": 1}]},
		"base_1": {
			"base_id": "base",
			"cards": [{"definition_id": "skin_a", "image_index": 0}, {"definition_id": "skin_b", "image_index": 1}],
			"custom_card_definitions": [skin_a, skin_b],
		},
	})
	assert_eq(index.speed_hints_by_deck["base"]["base_a"], "（特5速7攻）")
	assert_eq(index.speed_hints_by_deck["base_1"]["skin_a"], "（特6速12攻）")
	assert_eq(index.get_matcher([base_a]).annotate("Skin Alpha"), "Skin Alpha（特5速7攻）")
	assert_eq(index.get_matcher([skin_a]).annotate("Skin Alpha"), "Skin Alpha（特6速12攻）")
	assert_eq(index.get_matcher([base_a, skin_a]).annotate("Skin Alpha"), "Skin Alpha")

func test_longer_out_of_context_name_does_not_hide_known_short_name():
	CardDataManager.load_custom_cards([
		{"id": "test_hint_long_name", "display_name": "Hint Alpha EX", "type": "special", "speed": 6},
	])
	assert_eq(GameStrings.add_card_id_speed_hints("Hint Alpha EX", [TestCards[5]]), "Hint Alpha（特5速） EX")
	CardDataManager.card_data.erase("test_hint_long_name")
	CardDataManager.invalidate_card_name_index()
