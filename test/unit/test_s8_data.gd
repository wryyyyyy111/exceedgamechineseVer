extends GutTest

const CharSelectScene = preload("res://scenes/menu/char_select.tscn")
const CharacterIds = [
	"miyuki", "doomies", "yami", "akimo",
	"heraal", "gulbjarn", "astryda", "vorhild",
	"shaidrus", "khenui", "shafathi", "khepiax",
	"kohai", "nantaca", "ixatosk", "zacoal",
]

func test_s8_decks_are_complete_and_loadable():
	var definition_ids = {}
	for character_id in CharacterIds:
		var deck = CardDataManager.get_deck(character_id)
		assert_not_null(deck, "%s deck should be registered" % character_id)
		assert_eq(deck.get("season"), 8, "%s should be an S8 deck" % character_id)
		assert_eq(deck.get("cards", []).size(), 30, "%s should contain 30 cards" % character_id)
		CardDataManager.load_deck_if_custom(deck)
		assert_eq(_missing_definition_ids(deck), [], "%s must resolve every runtime definition" % character_id)
		var counts = {}
		for entry in deck["cards"]:
			var id = entry["definition_id"]
			counts[id] = counts.get(id, 0) + 1
			assert_true(deck["image_resources"].has(entry["image_name"]))
			assert_false(str(deck["image_resources"][entry["image_name"]]["url"]).is_empty())
			assert_gte(int(entry["image_index"]), 0)
		assert_eq(counts.size(), 15)
		var exclusive_count = 0
		var types = {"normal": 0, "special": 0, "ultra": 0}
		for definition_id in counts:
			assert_eq(counts[definition_id], 2)
			var definition = CardDataManager.get_card(definition_id)
			assert_not_null(definition)
			assert_true(types.has(definition["type"]))
			types[definition["type"]] += 1
			assert_true(definition.has("force_cost"))
			assert_true(definition.has("gauge_cost"))
			assert_true(definition.has("effects"))
			assert_true(definition.has("boost"))
			for effect in definition["effects"] + definition["boost"].get("effects", []):
				assert_true(effect.has("timing"))
				assert_false(str(effect.get("effect_type", "")).is_empty())
			if definition["type"] == "normal":
				continue
			exclusive_count += 1
			assert_false(definition_ids.has(definition_id), "%s should be unique" % definition_id)
			definition_ids[definition_id] = true
		assert_eq(exclusive_count, 7)
		assert_eq(types, {"normal": 8, "special": 5, "ultra": 2})
		assert_true(ResourceLoader.exists("res://assets/portraits/%s.png" % character_id))

	assert_eq(definition_ids.size(), 112)

func _missing_definition_ids(deck: Dictionary) -> Array:
	var missing = []
	for entry in deck["cards"]:
		var id = entry["definition_id"]
		if not CardDataManager.card_data.has(id) and id not in missing:
			missing.append(id)
	return missing

func test_runtime_integrity_detects_a_missing_definition_without_skipping_it():
	var deck = CardDataManager.get_deck("miyuki").duplicate(true)
	CardDataManager.load_deck_if_custom(deck)
	assert_eq(_missing_definition_ids(deck), [])
	var missing_id = "__s8_integrity_missing_definition__"
	assert_false(CardDataManager.card_data.has(missing_id))
	deck["cards"][0]["definition_id"] = missing_id
	assert_eq(_missing_definition_ids(deck), [missing_id])

func test_s8_character_select_entries_exist():
	var character_select = CharSelectScene.instantiate()
	add_child_autofree(character_select)
	assert_not_null(character_select.get_node_or_null("CenterContainer/STCharacterSelect"))
	assert_not_null(character_select.get_node_or_null("TabSelect/CategoriesHBox/Season8"))
	assert_eq(character_select.season_columns["season8"]["node"].name, "STCharacterSelect")

func test_random_s8_resolves_only_s8_characters():
	for _index in range(32):
		var deck = CardDataManager.get_deck("random_s8")
		assert_not_null(deck)
		assert_eq(deck.get("season"), 8)
		assert_true(deck.get("id") in CharacterIds)
