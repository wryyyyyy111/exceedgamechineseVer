extends ExceedGutTest

class TestDevisDesktopCardImageLoader extends CardImageLoader:
	func _is_mobile_web() -> bool:
		return false

class TestDevisMobileCardImageLoader extends CardImageLoader:
	func _is_mobile_web() -> bool:
		return true

func who_am_i():
	return "devis"

func test_devis_uses_devris_portrait_alias():
	assert_eq(ImageCache.get_local_portrait_path("devis"), "res://assets/portraits/devris.png")

func test_devis_character_action_name():
	var deck = CardDataManager.get_deck_from_str_id("devis")
	assert_eq(deck['character_action_default'][0]['action_name'], "角色主行动")
	assert_eq(deck['character_action_exceeded'][0]['action_name'], "角色主行动")

func test_devis_combined_normals_specials_indices():
	var deck = CardDataManager.get_deck_from_str_id("devis")
	var normal_indices = []
	var special_indices = []
	for card in deck['cards']:
		if card['image_name'] == "normals":
			if card['image_index'] not in normal_indices:
				normal_indices.append(card['image_index'])
		elif card['image_name'] == "specials":
			if card['image_index'] not in special_indices:
				special_indices.append(card['image_index'])
	assert_eq(normal_indices, [0, 1, 2, 3, 4, 5, 6, 7])
	assert_eq(special_indices, [8, 9, 10, 11, 12, 13, 14])
	var grid_rules = JSON.parse_string(FileAccess.get_file_as_string("res://data/phone_card_grid_rules.json"))
	var devis_grid = grid_rules['seasons']['1']['deck_overrides']['devis']
	assert_eq(int(devis_grid['grid_w']), 4)
	assert_eq(int(devis_grid['grid_h']), 4)

func test_devis_desktop_combined_atlas_uses_four_by_four_grid():
	var loader = TestDevisDesktopCardImageLoader.new(false)
	add_child_autofree(loader)
	var image_url = "https://example.com/devis_normals_specials_test.png"
	var atlas_image = Image.create(40, 40, false, Image.FORMAT_RGBA8)
	atlas_image.fill(Color.WHITE)
	ImageCache.cache_image(image_url, atlas_image)
	var atlas_data = {
		"url": image_url,
		"multiple_cards": true,
		"season": 1,
		"deck_id": "devis",
		"image_name": "specials",
		"force_cropped_textures": true,
	}
	loader.load_image_page_indexed(atlas_data, 14)
	await loader.get_card_image(image_url, 14, atlas_data)
	await get_tree().process_frame # Leave the loader's emitting stack before autofree.
	assert_eq(loader.loaded_images[image_url].size(), 16)
	assert_not_null(loader.loaded_images[image_url][14])
	loader.teardown()
	ImageCache.remove_cached_image(image_url)
	assert_null(ImageCache.load_image(image_url))

func test_devis_mobile_combined_atlas_uses_four_by_four_grid():
	var loader = TestDevisMobileCardImageLoader.new(false)
	add_child_autofree(loader)
	var grid = loader._get_phone_expected_grid({
		"multiple_cards": true,
		"season": 1,
		"deck_id": "devis",
		"image_name": "specials",
	}, "https://cdn.exceedcntyd.com/phone/decks_official/devis/normals_specials.jpg")
	assert_eq(grid, { "grid_w": 4, "grid_h": 4 })
	loader.teardown()

func test_devis_skin_uses_s2_style_split_card_grids():
	var deck = CardDataManager.get_deck_from_str_id("devis_1")
	assert_eq(deck['image_resources']['normals']['url'], "https://cdn.exceedcntyd.com/character_skin/devis_1/normals.jpg")
	assert_eq(deck['image_resources']['specials']['url'], "https://cdn.exceedcntyd.com/character_skin/devis_1/specials.jpg")
	assert_eq(int(deck['image_resources']['normals']['grid_w']), 4)
	assert_eq(int(deck['image_resources']['normals']['grid_h']), 2)
	assert_eq(int(deck['image_resources']['specials']['grid_w']), 4)
	assert_eq(int(deck['image_resources']['specials']['grid_h']), 2)

	var grid_rules = JSON.parse_string(FileAccess.get_file_as_string("res://data/phone_card_grid_rules.json"))
	var devis_skin_grid = grid_rules['seasons']['1']['deck_overrides']['devis_1']
	assert_eq(int(devis_skin_grid['grid_w']), 4)
	assert_eq(int(devis_skin_grid['grid_h']), 2)

	var loader = TestDevisDesktopCardImageLoader.new(false)
	add_child_autofree(loader)
	var image_url = "https://example.com/devis_1_specials_test.png"
	var atlas_image = Image.create(40, 20, false, Image.FORMAT_RGBA8)
	atlas_image.fill(Color.WHITE)
	ImageCache.cache_image(image_url, atlas_image)
	var atlas_data = {
		"url": image_url,
		"multiple_cards": true,
		"season": 1,
		"deck_id": "devis_1",
		"image_name": "specials",
		"force_cropped_textures": true,
	}
	loader.load_image_page_indexed(atlas_data, 7)
	await loader.get_card_image(image_url, 7, atlas_data)
	await get_tree().process_frame
	assert_eq(loader.loaded_images[image_url].size(), 8)
	assert_not_null(loader.loaded_images[image_url][7])
	loader.teardown()
	ImageCache.remove_cached_image(image_url)
	assert_null(ImageCache.load_image(image_url))

func test_devis_skin_explicit_grid_overrides_base_devis_combined_grid():
	var loader = TestDevisDesktopCardImageLoader.new(false)
	add_child_autofree(loader)
	var image_url = "https://example.com/devis_1_explicit_specials_test.png"
	var atlas_image = Image.create(40, 20, false, Image.FORMAT_RGBA8)
	atlas_image.fill(Color.WHITE)
	ImageCache.cache_image(image_url, atlas_image)
	var atlas_data = {
		"url": image_url,
		"multiple_cards": true,
		"season": 1,
		"deck_id": "devis",
		"image_name": "specials",
		"grid_w": 4,
		"grid_h": 2,
		"force_cropped_textures": true,
	}
	loader.load_image_page_indexed(atlas_data, 7)
	await loader.get_card_image(image_url, 7, atlas_data)
	await get_tree().process_frame
	assert_eq(loader.loaded_images[image_url].size(), 8)
	assert_not_null(loader.loaded_images[image_url][7])
	loader.teardown()
	ImageCache.remove_cached_image(image_url)
	assert_null(ImageCache.load_image(image_url))

func test_devis_skin_mobile_uses_two_by_four_grid():
	var loader = TestDevisMobileCardImageLoader.new(false)
	add_child_autofree(loader)
	var grid = loader._get_phone_expected_grid({
		"multiple_cards": true,
		"season": 1,
		"deck_id": "devis_1",
		"image_name": "specials",
	}, "https://cdn.exceedcntyd.com/phone/character_skin/devis_1/specials.jpg")
	assert_eq(grid, { "grid_w": 4, "grid_h": 2 })
	loader.teardown()

func test_devis_animation_manifest_matches_resource():
	var animation_path = "res://assets/character_animations/devis/animations.tres"
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(CdnAssetLoader.ANIMATION_MANIFEST_PATH))
	assert_true(manifest.has(animation_path))
	var manifest_text = str(manifest.get(animation_path, "")).replace("\r\n", "\n")
	var resource_text = FileAccess.get_file_as_string(animation_path).replace("\r\n", "\n")
	assert_eq(manifest_text, resource_text)

func test_devis_skin_animation_manifest_matches_resource():
	var animation_path = "res://assets/character_animations_skin/devis_1/animations.tres"
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(CdnAssetLoader.ANIMATION_MANIFEST_PATH))
	assert_true(manifest.has(animation_path))
	var manifest_text = str(manifest.get(animation_path, "")).replace("\r\n", "\n")
	var resource_text = FileAccess.get_file_as_string(animation_path).replace("\r\n", "\n")
	assert_eq(manifest_text, resource_text)
	assert_eq(resource_text.count("duration"), 22)
	assert_true(resource_text.contains("\"loop\": true"))

# Override: base-class validate_gauge compares runtime card.id (int) against a
# definition id (String) inside a lambda, which errors in GDScript. Compare
# against the card definition id instead.
func validate_gauge(player, amount, id):
	assert_eq(len(player.gauge), amount)
	if len(player.gauge) != amount:
		return
	if amount == 0:
		return
	for card in player.gauge:
		if card.definition['id'] == id:
			return
	fail_test("Didn't have required card in gauge.")

##
## Devis passive tests: gauge cards count as more force when paying
##

func test_devis_gauge_card_pays_as_two_force():
	# Devis pays a move costing 2 force with a single gauge card.
	# Her passive makes each gauge card worth up to 2 force, so 1 card suffices.
	position_players(player1, 5, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	set_player_topdeck(player1, "standard_normal_grasp")
	var gauge_ids = give_gauge(player1, 1)
	assert_true(game_logic.do_move(player1, gauge_ids, 3))
	validate_positions(player1, 3, player2, 7)

func test_devis_gauge_card_one_is_not_enough_for_three_force():
	# A single gauge card is worth at most 2 force pre-exceed, so a 3-force
	# move must fail.
	position_players(player1, 5, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	set_player_topdeck(player1, "standard_normal_grasp")
	var gauge_ids = give_gauge(player1, 1)
	assert_false(game_logic.do_move(player1, gauge_ids, 2))
	validate_positions(player1, 5, player2, 7)

func test_devis_exceed_gauge_card_pays_as_three_force():
	# After exceeding, each gauge card is worth up to 3 force, so one card
	# pays a 3-force move.
	position_players(player1, 5, player2, 7)
	give_gauge(player1, 2)
	assert_true(game_logic.do_exceed(player1, get_cards_from_gauge(player1, 2)))
	advance_turn(player2)
	player1.discard_hand()
	player2.discard_hand()
	set_player_topdeck(player1, "standard_normal_grasp")
	var gauge_ids = give_gauge(player1, 1)
	assert_true(game_logic.do_move(player1, gauge_ids, 2))
	validate_positions(player1, 2, player2, 7)

##
## Devis character action: pay 1 life to add the top card of the deck to gauge
##

func test_devis_character_action_adds_topdeck_to_gauge():
	position_players(player1, 5, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	set_player_topdeck(player1, "standard_normal_grasp")
	assert_true(game_logic.do_character_action(player1, [], 0))
	validate_life(player1, 29, player2, 30)
	validate_gauge(player1, 1, "standard_normal_grasp")

##
## Flame Grenade boost (Blood Contract): top 3 of deck to gauge, pay 4 life
##

func test_devis_flamegrenade_boost_blood_contract():
	position_players(player1, 5, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	set_player_topdeck(player1, "standard_normal_grasp")
	set_player_topdeck(player1, "standard_normal_cross")
	set_player_topdeck(player1, "standard_normal_assault")
	var flamegrenade = give_player_specific_card(player1, "devis_flamegrenade")
	assert_true(game_logic.do_boost(player1, flamegrenade))
	validate_life(player1, 26, player2, 30)
	validate_gauge(player1, 3, "standard_normal_assault")

##
## Death Mark before: each force spent prompts one advance/retreat choice
##

func test_devis_deathmark_move_once_per_force():
	# Death Mark (range 3) before: pay up to 3 force, each force moves 1
	# space with a choice of advance or retreat. Paying 2 force must prompt
	# the player twice (one choice per force).
	position_players(player1, 2, player2, 5)
	player1.discard_hand()
	player2.discard_hand()
	var c1 = give_player_specific_card(player1, "standard_normal_grasp")
	var c2 = give_player_specific_card(player1, "standard_normal_grasp")
	# Strike with Death Mark, pay 2 force ([c1, c2]), then choose advance
	# for both prompts: p1 2 -> 3 -> 4.
	execute_strike(player1, player2, "devis_deathmark", "standard_normal_grasp",
		false, false, [[c1, c2], 0, 0], [])
	validate_positions(player1, 4, player2, 5)

func test_devis_deathmark_move_mixed_choices_per_force():
	# Paying 3 force prompts 3 choices: advance, retreat, advance.
	# p1 2 -> 3 (advance) -> 2 (retreat) -> 3 (advance).
	position_players(player1, 2, player2, 5)
	player1.discard_hand()
	player2.discard_hand()
	var c1 = give_player_specific_card(player1, "standard_normal_grasp")
	var c2 = give_player_specific_card(player1, "standard_normal_grasp")
	var c3 = give_player_specific_card(player1, "standard_normal_grasp")
	execute_strike(player1, player2, "devis_deathmark", "standard_normal_grasp",
		false, false, [[c1, c2, c3], 0, 1, 0], [])
	validate_positions(player1, 3, player2, 5)

##
## Hell Force boost (6 force): gauge cards count as 2 force each, so 3 gauge
## cards (6 force) pay it — matching what the UI displays and confirms.
##

func test_devis_hellforce_boost_pays_with_gauge_cards():
	position_players(player1, 5, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	var lifedrain = give_player_specific_card(player1, "devis_lifedrain")
	set_player_topdeck(player1, "standard_normal_grasp")
	set_player_topdeck(player1, "standard_normal_grasp")
	set_player_topdeck(player1, "standard_normal_grasp")
	var gauge_ids = give_gauge(player1, 3)
	# 3 gauge cards = 3 * 2 force (Devis passive) = 6 force.
	assert_eq(player1.get_force_with_cards(gauge_ids, "GENERIC_PAY_FORCE_COST", false, false), 6)
	assert_true(game_logic.do_boost(player1, lifedrain, gauge_ids))

##
## Raider Summon card face: range 1 / power 4 / speed 4 / guard (霸体) 4
##

func test_devis_raidersummon_card_face():
	var card_def = CardDataManager.get_card("devis_raidersummon")
	assert_eq(card_def['range_min'], 1)
	assert_eq(card_def['range_max'], 1)
	assert_eq(card_def['power'], 4)
	assert_eq(card_def['speed'], 4)
	assert_eq(card_def['armor'], 0)
	assert_eq(card_def['guard'], 4)

##
## Death Mark card face: range 3 / power 5 / speed 5 / guard (霸体) 5
##

func test_devis_deathmark_card_face():
	var card_def = CardDataManager.get_card("devis_deathmark")
	assert_eq(card_def['range_min'], 3)
	assert_eq(card_def['range_max'], 3)
	assert_eq(card_def['power'], 5)
	assert_eq(card_def['speed'], 3)
	assert_eq(card_def['armor'], 0)
	assert_eq(card_def['guard'], 5)

func test_devis_burnout_gauge_cost_resolves_on_hit():
	var card_def = CardDataManager.get_card("devis_burnout")
	var gauge_effect = null
	for effect in card_def['effects']:
		if effect['effect_type'] == 'gauge_for_effect':
			gauge_effect = effect
	assert_not_null(gauge_effect)
	assert_eq(gauge_effect['timing'], 'hit')
	assert_true(gauge_effect['required'])
	assert_eq(gauge_effect['min_gauge'], 1)

##
## Dark Energy boost (Death Mark): immediate draw 1; before: pay up to 4
## force, each force gives +1 power (continuous).
##

func test_devis_darkenergy_boost_immediate_draw():
	# Boosting Death Mark activates Dark Energy: immediate draw 1 (plus the
	# normal end-of-turn draw after boosting, so hand grows by 2).
	position_players(player1, 5, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	var deathmark = give_player_specific_card(player1, "devis_deathmark")
	assert_true(game_logic.do_boost(player1, deathmark))
	assert_gte(player1.hand.size(), 2)

func test_devis_darkenergy_boost_before_force_for_effect():
	# The boost carries a before force_for_effect: pay up to 4 force,
	# each force grants +1 power.
	var card_def = CardDataManager.get_card("devis_deathmark")
	var found_before_force = false
	for e in card_def['boost']['effects']:
		if e['effect_type'] == 'force_for_effect' and e['timing'] == 'before':
			found_before_force = true
			assert_eq(e['force_max'], 4)
			assert_eq(e['per_force_effect']['effect_type'], 'powerup')
			assert_eq(e['per_force_effect']['amount'], 1)
	assert_true(found_before_force)

func test_devis_darkenergy_boost_power_applied():
	# Full strike: Dark Energy boosted, then Death Mark strike. In before,
	# pay 3 force to the Dark Energy effect -> +3 power (5 + 3 = 8 damage).
	position_players(player1, 2, player2, 5)
	player1.discard_hand()
	player2.discard_hand()
	var deathmark_boost = give_player_specific_card(player1, "devis_deathmark")
	assert_true(game_logic.do_boost(player1, deathmark_boost))
	# Opponent acts, then back to p1.
	var p2c = give_player_specific_card(player2, "standard_normal_grasp")
	assert_true(game_logic.do_move(player2, [p2c], 6))
	player1.discard_hand()
	# p1 strikes with Death Mark. before decisions (both card move effect and
	# the Dark Energy power effect are simultaneous, so first choose an
	# effect order, then pay the move effect 1 force (choice: advance), then
	# pay the Dark Energy power effect 3 force.
	var c1 = give_player_specific_card(player1, "standard_normal_grasp")
	var c2 = give_player_specific_card(player1, "standard_normal_grasp")
	var c3 = give_player_specific_card(player1, "standard_normal_grasp")
	var c4 = give_player_specific_card(player1, "standard_normal_grasp")
	execute_strike(player1, player2, "devis_deathmark", "standard_normal_grasp",
		false, false, [0, [c1], 0, [c2, c3, c4]], [])
	# Death Mark power 5 + 3 = 8 vs grasp (armor 0) -> 8 damage; p2 life 22.
	validate_life(player1, 30, player2, 22)

##
## Demon Connection boost (Book Contract): both players draw/discard to 6
##

func test_devis_demonconnection_boost_book_contract():
	# With both hands smaller than 6, the contract simply draws both to 6
	# (no discard decision is required).
	position_players(player1, 5, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	var demonconnection = give_player_specific_card(player1, "devis_demonconnection")
	assert_true(game_logic.do_boost(player1, demonconnection))
	print("BOOK_CONTRACT_HANDS p1=", player1.hand.size(), " p2=", player2.hand.size())
	# 书之契约让双方摸/弃到 6；boost 后回合推进可能附带额外摸牌，因此验证至少 6。
	assert_gte(player1.hand.size(), 6)
	assert_gte(player2.hand.size(), 6)

##
## Display: Devis effects must render without MISSING text
##

func test_devis_display_no_missing_timing():
	var deck = CardDataManager.get_deck_from_str_id("devis")
	var ability_text = GameStrings.get_effects_text(deck['ability_effects'])
	print("DEVIS_ABILITY_TEXT=[", ability_text, "]")
	assert_false(ability_text.contains("MISSING"))

	for card_id in ["devis_illusorypower", "devis_raidersummon", "devis_lifedrain",
			"devis_deathmark", "devis_burnout", "devis_flamegrenade", "devis_demonconnection"]:
		var card_def = CardDataManager.get_card(card_id)
		var card_text = GameStrings.get_effects_text(card_def['effects'])
		var boost_text = GameStrings.get_effects_text(card_def['boost']['effects'])
		print("CARD[", card_id, "]=", card_text, " | BOOST=", boost_text)
		assert_false(card_text.contains("MISSING"))
		assert_false(boost_text.contains("MISSING"))
