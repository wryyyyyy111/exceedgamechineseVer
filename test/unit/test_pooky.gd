extends ExceedGutTest

class TestPookyDesktopCardImageLoader extends CardImageLoader:
	func _is_mobile_web() -> bool:
		return false

class TestPookyMobileCardImageLoader extends CardImageLoader:
	func _is_mobile_web() -> bool:
		return true

func who_am_i():
	return "pooky"

func test_pooky_original_shared_atlas_uses_four_by_four_for_both_resource_names():
	var loader = TestPookyMobileCardImageLoader.new(false)
	add_child_autofree(loader)
	for image_name in ["specials", "normals"]:
		assert_eq(
			loader._get_phone_expected_grid({
				"multiple_cards": true,
				"season": 2,
				"deck_id": "pooky",
				"image_name": image_name,
			}, "https://cdn.exceedcntyd.com/phone/decks_official/pooky/normals_specials.jpg"),
			{"grid_w": 4, "grid_h": 4})
	loader.teardown()

func test_pooky_1_skin_registers_separate_four_by_four_card_grids():
	var grid_rules = JSON.parse_string(FileAccess.get_file_as_string("res://data/phone_card_grid_rules.json"))
	var pooky_skin_rules = grid_rules['seasons']['2']['deck_overrides']['pooky_1']['file_rules']
	assert_eq(pooky_skin_rules.size(), 2)
	assert_eq(pooky_skin_rules[0]['image_name'], "specials")
	assert_eq(int(pooky_skin_rules[0]['grid_w']), 4)
	assert_eq(int(pooky_skin_rules[0]['grid_h']), 4)
	assert_eq(pooky_skin_rules[1]['image_name'], "normals")
	assert_eq(int(pooky_skin_rules[1]['grid_w']), 4)
	assert_eq(int(pooky_skin_rules[1]['grid_h']), 4)

	var loader = TestPookyMobileCardImageLoader.new(false)
	add_child_autofree(loader)
	for image_name in ["specials", "normals"]:
		assert_eq(
			loader._get_phone_expected_grid({
				"multiple_cards": true,
				"season": 2,
				"deck_id": "pooky_1",
				"image_name": image_name,
			}, "https://cdn.exceedcntyd.com/phone/decks_official/pooky/normals_specials.jpg"),
			{"grid_w": 4, "grid_h": 4})
	loader.teardown()

func test_pooky_asset_deck_id_takes_priority_over_normalized_deck_id():
	var loader = TestPookyMobileCardImageLoader.new(false)
	add_child_autofree(loader)
	var atlas_data = {
		"multiple_cards": true,
		"season": 2,
		"deck_id": "pooky",
		"asset_deck_id": "pooky_1",
		"image_name": "specials",
	}
	assert_eq(
		loader._get_phone_expected_grid(atlas_data, "https://cdn.exceedcntyd.com/phone/decks_official/pooky/normals_specials.jpg"),
		{"grid_w": 4, "grid_h": 4})
	atlas_data["asset_deck_id"] = "pooky_2"
	assert_eq(
		loader._get_phone_expected_grid(atlas_data, "https://cdn.exceedcntyd.com/phone/character_skin/pooky_2/specials.jpg"),
		{"grid_w": 4, "grid_h": 2})
	loader.teardown()

func test_pooky_2_skin_does_not_inherit_original_shared_atlas_rule():
	var loader = TestPookyMobileCardImageLoader.new(false)
	add_child_autofree(loader)
	for image_name in ["specials", "normals"]:
		assert_eq(
			loader._get_phone_expected_grid({
				"multiple_cards": true,
				"season": 2,
				"deck_id": "pooky_2",
				"image_name": image_name,
			}, "https://cdn.exceedcntyd.com/phone/character_skin/pooky_2/%s.jpg" % image_name),
			{"grid_w": 4, "grid_h": 2})
	loader.teardown()

func test_pooky_skin_runtime_asset_id_is_forwarded_to_each_image_resource():
	var deck = CardDataManager.get_deck_from_str_id("pooky_1").duplicate(true)
	deck["asset_deck_id"] = "pooky_1"
	var deck_id = deck.get("asset_deck_id", deck.get("id", ""))
	for image_name in ["specials", "normals"]:
		var image_resource = deck["image_resources"][image_name]
		image_resource["asset_deck_id"] = deck_id
		image_resource["deck_id"] = deck_id
		image_resource["image_name"] = image_name
		assert_eq(image_resource["asset_deck_id"], "pooky_1")
		assert_eq(image_resource["deck_id"], "pooky_1")
		assert_eq(image_resource["image_name"], image_name)

func test_pooky_3_skin_uses_s2_style_split_card_grids():
	var deck = CardDataManager.get_deck_from_str_id("pooky_3")
	assert_eq(deck['image_resources']['normals']['url'], "https://cdn.exceedcntyd.com/decks_official/eugenia/normals.jpg")
	assert_eq(deck['image_resources']['specials']['url'], "https://cdn.exceedcntyd.com/character_skin/pooky_3/specials.jpg")
	assert_eq(int(deck['image_resources']['normals']['grid_w']), 4)
	assert_eq(int(deck['image_resources']['normals']['grid_h']), 2)
	assert_eq(int(deck['image_resources']['specials']['grid_w']), 4)
	assert_eq(int(deck['image_resources']['specials']['grid_h']), 2)

	var grid_rules = JSON.parse_string(FileAccess.get_file_as_string("res://data/phone_card_grid_rules.json"))
	var pooky_skin_grid = grid_rules['seasons']['2']['deck_overrides']['pooky_3']
	assert_eq(int(pooky_skin_grid['grid_w']), 4)
	assert_eq(int(pooky_skin_grid['grid_h']), 2)

	var loader = TestPookyDesktopCardImageLoader.new(false)
	add_child_autofree(loader)
	var image_url = "https://example.com/pooky_3_specials_test.png"
	var atlas_image = Image.create(40, 20, false, Image.FORMAT_RGBA8)
	atlas_image.fill(Color.WHITE)
	ImageCache.cache_image(image_url, atlas_image)
	var atlas_data = {
		"url": image_url,
		"multiple_cards": true,
		"season": 2,
		"deck_id": "pooky_3",
		"image_name": "specials",
		"grid_w": 4,
		"grid_h": 2,
		"force_cropped_textures": true,
	}
	loader.load_image_page_indexed(atlas_data, 7)
	await loader.get_card_image(image_url, 7, atlas_data)
	assert_eq(loader.loaded_images[image_url].size(), 8)
	assert_not_null(loader.loaded_images[image_url][7])
	loader.teardown()
	ImageCache.remove_cached_image(image_url)
	assert_null(ImageCache.load_image(image_url))

func test_pooky_3_skin_mobile_uses_two_by_four_grid():
	var loader = TestPookyMobileCardImageLoader.new(false)
	add_child_autofree(loader)
	var specials_grid = loader._get_phone_expected_grid({
		"multiple_cards": true,
		"season": 2,
		"deck_id": "pooky_3",
		"image_name": "specials",
	}, "https://cdn.exceedcntyd.com/phone/character_skin/pooky_3/specials.jpg")
	var normals_grid = loader._get_phone_expected_grid({
		"multiple_cards": true,
		"season": 2,
		"deck_id": "pooky_3",
		"image_name": "normals",
	}, "https://cdn.exceedcntyd.com/phone/character_skin/pooky_3/normals.jpg")
	assert_eq(specials_grid, { "grid_w": 4, "grid_h": 2 })
	assert_eq(normals_grid, { "grid_w": 4, "grid_h": 2 })
	loader.teardown()

func test_pooky_3_skin_animations_are_registered():
	assert_eq(get_node("/root/CharSkinManager").get_skin_count("pooky"), 3)
	assert_eq(
		get_node("/root/CharSkinManager").get_animation_path_for_deck_id("pooky_3"),
		"res://assets/character_animations_skin/pooky_3/animations.tres",
	)
	assert_eq(
		get_node("/root/CharSkinManager").get_animation_path_for_deck_and_animation_id("pooky_3", "pooky_3_exceed"),
		"res://assets/character_animations_skin/pooky_3_exceed/animations.tres",
	)
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(CdnAssetLoader.ANIMATION_MANIFEST_PATH))
	for animation_path in [
		"res://assets/character_animations_skin/pooky_3/animations.tres",
		"res://assets/character_animations_skin/pooky_3_exceed/animations.tres",
	]:
		assert_true(manifest.has(animation_path))
		var manifest_text = str(manifest.get(animation_path, "")).replace("\r\n", "\n")
		var resource_text = FileAccess.get_file_as_string(animation_path).replace("\r\n", "\n")
		assert_eq(manifest_text, resource_text)

func test_pooky_dragon_breath_ale_extends_range_outside_strike():
	position_players(player1, 3, player2, 6)
	var boost_id = give_player_specific_card(player1, "pooky_snackattack")
	var attack_id = give_player_specific_card(player1, "pooky_snackattack")
	var attack_card = game_logic.get_card_database().get_card(attack_id)

	assert_false(player1.does_card_contain_range_to_opponent(attack_id))
	assert_true(game_logic.do_boost(player1, boost_id))
	assert_eq(player1.continuous_boosts.size(), 1)
	assert_eq(player1.build_outside_strike_range_effect_list().size(), 1)
	assert_eq(player1.get_total_max_range_bonus(attack_card), 1)
	assert_true(player1.does_card_contain_range_to_opponent(attack_id))

func test_pooky_gambling_reveal_chains_into_second_gambling():
	position_players(player1, 3, player2, 6)
	var first_gambling_id = give_player_specific_card(player1, "pooky_gamblingimin")
	set_player_topdeck(player1, "standard_normal_spike")
	set_player_topdeck(player1, "pooky_gamblingimin")

	execute_strike(player1, player2, first_gambling_id, "standard_normal_sweep", false, false, [], [])

	validate_life(player1, 30, player2, 23)

func test_pooky_wild_ultra_invalid_then_gambling_reveal_triggers():
	position_players(player1, 3, player2, 6)
	set_player_topdeck(player1, "standard_normal_spike")
	set_player_topdeck(player1, "pooky_gamblingimin")
	set_player_topdeck(player1, "pooky_hattrick")

	# Initiate with wild swing -> Hat Trick (ultra), cannot pay cost, and wild swing again.
	# Second wild swing reveals Gambling? I'm In!, which should still trigger and replace itself.
	execute_strike(player1, player2, -1, "standard_normal_sweep", false, false, [], [])
	var events = game_logic.get_latest_events()

	validate_has_event(events, Enums.EventType.EventType_Boost_Continuous_Added, player1)
	validate_life(player1, 30, player2, 24)

func test_pooky_long_intooth_with_boost_applies_range_bonus_without_crash():
	position_players(player1, 3, player2, 6)
	var boost_id = give_player_specific_card(player1, "pooky_snackattack")
	var boost_card = game_logic.get_card_database().get_card(boost_id)
	player1.add_to_continuous_boosts(boost_card)
	player1.hand.erase(boost_card)

	execute_strike(player1, player2, "pooky_longintooth", "standard_normal_block", false, false, [], [[]])

	validate_life(player1, 30, player2, 27)

func test_pooky_exceeded_stunned_draws_for_stunned_player_only():
	position_players(player1, 3, player2, 4)
	player1.exceed()

	execute_strike(player1, player2, "standard_normal_block", "standard_normal_sweep", false, false, [[], 0], [])
	var events = game_logic.get_latest_events()

	validate_has_event(events, Enums.EventType.EventType_Draw, player1)
	validate_not_has_event(events, Enums.EventType.EventType_Draw, player2)

func test_pooky_exceeded_stunning_opponent_does_not_offer_draw():
	position_players(player1, 3, player2, 4)
	player1.exceed()
	player2.deck_def = player2.deck_def.duplicate(true)
	player2.deck_def["id"] = "test_opponent"

	execute_strike(player1, player2, "standard_normal_sweep", "standard_normal_block", false, false, [], [[]])
	var events = game_logic.get_latest_events()

	validate_not_has_event(events, Enums.EventType.EventType_Draw, player1)
	validate_not_has_event(events, Enums.EventType.EventType_Draw, player2)

func test_pooky_exceeded_stunned_death_triggers_immediate_game_over():
	position_players(player1, 3, player2, 4)
	player1.exceed()
	player1.life = 3

	var events = execute_strike(player1, player2, "standard_normal_block", "standard_normal_sweep", false, false, [[]], [], false)

	assert_true(game_logic.game_over)
	assert_eq(game_logic.game_state, Enums.GameState.GameState_GameOver)
	assert_eq(game_logic.game_over_winning_player.my_id, player2.my_id)
	validate_has_event(events, Enums.EventType.EventType_GameOver, player1, Enums.GameOverReason.GameOverReason_Life)

## ===== Zol's Secret Recipe（帽子戏法 Hat Trick 的转化）=====
##
## 卡面：每回合你第一次使用即时加成时，你可以花费1能量。
##       若如此做，将其以(无效果)牌面朝下持续性加成放置入场。
##
## 回归背景（玩家反馈「使用即时性加成时效果丢失」）：
## 转化时直接改写了这张**实体卡**的 definition["boost"]，却没有把原件存进
## replaced_boost。卡对象的 definition 是每张实体卡各自的副本，于是这张牌从此
## **永久**变成「无效果面朝下持续加成」——之后再抽到当加成用就完全没有效果了
## （效果丢失），而且每次复用还会白拿一个持续性加成。
## 正解与 Syrus「重打出场」同一惯例：先把原件存进 replaced_boost，离开加成区时
## player.do_discarded_effects_for_boost / remove_from_transforms 会自动还原。

func _pooky_zols_effect_types(card):
	var out = []
	for effect in card.definition['boost']['effects']:
		out.append(effect.get("effect_type"))
	return out

func _pooky_zols_setup():
	# 帽子戏法进转化区 + 一张即时加成的普通技（Block 的 Parry）+ 一张用来付 1 能量的牌
	add_transform(player1, "pooky_hattrick")
	position_players(player1, 3, player2, 6)
	var boost_id = give_player_specific_card(player1, "standard_normal_block")
	var pay_id = give_player_specific_card(player1, "standard_normal_sweep")
	return [boost_id, pay_id]

func _pooky_zols_answer_decisions(pay_card_id, pay_for_zols : bool, max_steps : int = 6):
	# 依次回答：即时加成自身的决策（Parry = 指定一张牌）→ Zol's 的付 1 能量决策
	for _i in range(max_steps):
		if game_logic.game_state != Enums.GameState.GameState_PlayerDecision:
			return
		match game_logic.decision_info.type:
			Enums.DecisionType.DecisionType_NameCard_OpponentDiscards:
				# -1 = 指定一张不存在的牌，对手不用弃牌
				assert_true(game_logic.do_boost_name_card_choice_effect(player1, -1))
			Enums.DecisionType.DecisionType_ForceForEffect:
				var cards = [pay_card_id] if pay_for_zols else []
				assert_true(game_logic.do_force_for_effect(player1, cards, false, not pay_for_zols))
			_:
				return


func test_pooky_zols_recipe_turns_immediate_boost_into_facedown_continuous_boost():
	var setup = _pooky_zols_setup()
	var boost_id = setup[0]
	var card = game_logic.get_card_database().get_card(boost_id)
	assert_eq(card.definition['boost']['boost_type'], "immediate", "前置：Block 的加成应为即时加成")

	game_logic.do_boost(player1, boost_id)
	_pooky_zols_answer_decisions(setup[1], true)

	assert_eq(player1.continuous_boosts.size(), 1, "转化后应入场 1 个持续性加成")
	assert_true(card in player1.continuous_boosts, "被转化的应是这张卡本身")
	assert_eq(card.definition['boost']['boost_type'], "continuous", "转化后应视为持续性加成")
	assert_true(card.definition['boost'].get("facedown", false), "转化后应为面朝下")
	assert_eq(card.definition['boost']['effects'].size(), 0, "转化后应为「无效果」")
	assert_false(card in player1.discards, "转化后不应进弃牌堆")


func test_pooky_zols_conversion_restores_original_boost_when_leaving_boost_zone():
	# 核心回归：离开加成区后必须还原成原本的即时加成，否则这张实体卡永久失去效果。
	var setup = _pooky_zols_setup()
	var boost_id = setup[0]
	var card = game_logic.get_card_database().get_card(boost_id)

	game_logic.do_boost(player1, boost_id)
	_pooky_zols_answer_decisions(setup[1], true)
	assert_true(card.definition.has("replaced_boost"),
		"转化时必须把原始的即时加成存进 replaced_boost")

	player1.remove_from_continuous_boosts(card)

	assert_eq(card.definition['boost']['boost_type'], "immediate",
		"离开加成区后应还原为即时加成（否则以后再用就没有效果了）")
	assert_eq(_pooky_zols_effect_types(card), ["name_card_opponent_discards"],
		"应还原 Block 原本的 Parry 效果")
	assert_false(card.definition.has("replaced_boost"), "还原后应清掉 replaced_boost 标记")


func test_pooky_zols_converted_card_can_resolve_its_immediate_effect_again():
	# 用户可见症状：这张牌以后再当加成用，原本的即时效果仍应生效（效果不丢）。
	var setup = _pooky_zols_setup()
	var boost_id = setup[0]
	var card = game_logic.get_card_database().get_card(boost_id)

	game_logic.do_boost(player1, boost_id)
	_pooky_zols_answer_decisions(setup[1], true)
	player1.remove_from_continuous_boosts(card)

	var now_immediate = game_logic.get_card_database().get_card_boost_effects_now_immediate(card)
	assert_eq(now_immediate.size(), 1, "还原后应重新具备即时加成效果（效果不丢）")
	assert_eq(now_immediate[0].get("effect_type"), "name_card_opponent_discards",
		"应是 Parry 的指定牌效果")
	assert_false(card.definition['boost'].get("facedown", false), "不应该再是面朝下加成")


func test_pooky_zols_recipe_does_not_convert_when_payment_declined():
	# 反向对照：不付 1 能量 → 不做任何改写，卡按普通即时加成进弃牌堆。
	var setup = _pooky_zols_setup()
	var boost_id = setup[0]
	var card = game_logic.get_card_database().get_card(boost_id)

	game_logic.do_boost(player1, boost_id)
	_pooky_zols_answer_decisions(setup[1], false)

	assert_eq(player1.continuous_boosts.size(), 0, "拒绝付费时不应产生持续性加成")
	assert_eq(card.definition['boost']['boost_type'], "immediate", "拒绝付费时不应改写定义")
	assert_false(card.definition.has("replaced_boost"), "拒绝付费时不应留下 replaced_boost")
	assert_true(card in player1.discards, "拒绝付费时这张卡应正常进弃牌堆")


func test_pooky_zols_recipe_is_only_offered_once_per_turn():
	# 卡面写「每回合**首次**」：本次结算中途再触发一次不应再提供机会。
	# （之前只靠 pooky_zols_target_id 判断，而成功转化会把它清回 -1，
	#   于是同一回合再打一张即时加成会被再转化一次。）
	var setup = _pooky_zols_setup()
	game_logic.do_boost(player1, setup[0])

	# 回答 Parry 的指定牌决策，停在 Zol's 的付 1 能量决策
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_NameCard_OpponentDiscards,
		"前置：应先等 Parry 的指定牌决策")
	assert_true(game_logic.do_boost_name_card_choice_effect(player1, -1))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ForceForEffect,
		"前置：Zol's 应提供付 1 能量的决策")
	assert_true(player1.pooky_zols_used_this_turn, "本回合的机会应已被用掉")

	# 同一次结算中再触发：应被拦下，不产生新决策、不改动待转化目标
	game_logic.handle_strike_effect(-1, {"effect_type": "pooky_zols_on_boost"}, player1)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ForceForEffect,
		"不应再弹一次付能量决策")
	assert_eq(player1.pooky_zols_target_id, -2, "应仍停在 in-progress 状态，没有被重设")

	# 收尾：正常付 1 能量完成转化
	assert_true(game_logic.do_force_for_effect(player1, [setup[1]], false))
	assert_eq(player1.continuous_boosts.size(), 1, "第一次仍应正常转化")
