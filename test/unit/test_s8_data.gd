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
		assert_eq(deck.get("custom_card_definitions", []).size(), 7, "%s should contain 7 unique definitions" % character_id)

		CardDataManager.load_deck_if_custom(deck)
		for definition in deck["custom_card_definitions"]:
			var definition_id = definition["id"]
			assert_false(definition_ids.has(definition_id), "%s should be unique" % definition_id)
			definition_ids[definition_id] = true
			assert_not_null(CardDataManager.get_card(definition_id))

		assert_true(ResourceLoader.exists("res://assets/portraits/%s.png" % character_id))

	assert_eq(definition_ids.size(), 112)

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
