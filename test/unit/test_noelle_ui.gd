extends GutTest
# 诺艾尔 UI 回归测试：场地加成（地面炸弹）在「加成区」的显示与起战提示
#
# 场景：地面炸弹是「设置在场地一格」的持续性加成，最多同时有 2 张。
# 加成区里可点选它们发起战斗，因此提示必须标出各自所在格，否则两张同名卡无法分辨。

var game_ui : Game
var next_test_card_id = 63000

func next_id() -> int:
	next_test_card_id += 1
	return next_test_card_id - 1

func get_logic():
	return game_ui.game_wrapper.current_game

func _drain_latest_events():
	var saved_fast_forward = game_ui.restore_fast_forwarding
	game_ui.restore_fast_forwarding = true
	while true:
		var events = get_logic().get_latest_events()
		if events.size() == 0 and game_ui.events_to_process.size() == 0:
			break
		if events.size() > 0:
			game_ui._handle_events(events)
		elif game_ui.events_to_process.size() > 0:
			var remaining_events = game_ui.events_to_process
			game_ui.events_to_process = []
			game_ui._handle_events(remaining_events)
	game_ui.restore_fast_forwarding = saved_fast_forward

func give_player_specific_card(player : Player, def_id : String) -> int:
	var card_def = CardDataManager.get_card(def_id)
	var card_id = next_id()
	var card = GameCard.new(card_id, card_def, player.my_id)
	var card_db = get_logic().get_card_database()
	card_db._test_insert_card(card)
	player.hand.append(card)
	return card_id

func add_card_ui_to_hand(card_id : int, is_player : bool) -> void:
	await add_card_ui_to_zone(card_id, is_player, "AllCards/PlayerDeck" if is_player else "AllCards/OpponentDeck")
	game_ui.draw_card(card_id, is_player)

func add_card_ui_to_zone(card_id : int, is_player : bool, zone_path : String) -> void:
	var current_game = get_logic()
	var logic_card = current_game.get_card_database().get_card(card_id)
	var deck_def = game_ui.player_deck if is_player else game_ui.opponent_deck
	var zone = game_ui.get_node(zone_path)
	await game_ui.create_card(
		card_id,
		logic_card.definition,
		logic_card.get_image_url_index_data(),
		deck_def["image_resources"]["cardback"]["url"],
		zone,
		not is_player,
		logic_card.definition["display_name"],
		logic_card.definition["boost"]["display_name"]
	)

func setup_game_ui():
	var game_scene = load("res://scenes/game/game.tscn")
	game_ui = game_scene.instantiate()
	game_ui.set_not_started_directly()
	add_child(game_ui)
	await get_tree().process_frame
	game_ui.image_loader.test_mode = true
	var image_loader = game_ui.image_loader
	var game_logic = LocalGame.new(image_loader)
	var seed_value = randi()
	var deck = CardDataManager.get_deck_from_str_id("noelle")
	game_logic.initialize_game(deck, deck, "p1", "p2", Enums.PlayerId.PlayerId_Player, seed_value)
	game_logic.draw_starting_hands_and_begin()
	game_logic.do_mulligan(game_logic.player, [])
	game_logic.do_mulligan(game_logic.opponent, [])
	game_logic.get_latest_events()
	game_ui.player_deck = deck
	game_ui.opponent_deck = deck
	game_ui.game_wrapper.current_game = game_logic
	game_ui.ai_player = AIPlayer.new(game_logic, game_logic.opponent)
	await game_ui.setup_characters()
	await game_ui.spawn_all_cards()
	game_ui.first_run()
	game_ui.change_ui_state(game_ui.UIState.UIState_PickTurnAction, game_ui.UISubState.UISubState_None)
	game_ui._update_buttons()
	return game_logic

func before_each() -> void:
	await setup_game_ui()

func after_each():
	if game_ui:
		var ai_player = game_ui.ai_player
		game_ui.free()
		if ai_player:
			ai_player.ai_policy.free()
		game_ui = null

func get_choice_index_for_position(pos : int) -> int:
	var lim = get_logic().decision_info.limitation
	for i in range(lim.size()):
		if pos == lim[i]:
			return i
	return -1

func boost_zone_text() -> String:
	return game_ui.get_node("PlayerBoostZone").boost_effects.text

# 把一张地面炸弹「设置」到场地指定格，并让 UI 反映出加成区卡片
func _place_ground_bomb_at(player : Player, location : int) -> int:
	var bomb_id = give_player_specific_card(player, "noelle_setbomb")
	await add_card_ui_to_hand(bomb_id, true)
	_drain_latest_events()
	assert_true(get_logic().do_boost(player, bomb_id), "打出地面炸弹失败")
	var idx = get_choice_index_for_position(location)
	assert_true(idx != -1, "应能选到位置 %d" % location)
	assert_true(get_logic().do_choice(player, idx), "选择位置失败")
	_drain_latest_events()
	return bomb_id

# ---------------- 加成区提示：标出所在格 ----------------

func test_boost_zone_hint_shows_position_of_ground_bomb():
	var game_logic = get_logic()
	var player = game_logic.player
	player.discard_hand()

	var bomb_id = await _place_ground_bomb_at(player, 7)
	assert_eq(player.get_boost_location(bomb_id), 7, "前置：炸弹应设在 7 号格")

	game_ui._update_buttons(true)
	var text = boost_zone_text()
	assert_true(text.find("设为攻击") != -1, "加成区应提示可以把炸弹设为攻击")
	assert_true(text.find("位置7") != -1,
			"加成区提示应标出炸弹所在格（实际：%s）" % text)

func test_boost_zone_hint_distinguishes_two_ground_bombs():
	# 两张地面炸弹分别在 7 和 3 号格：两条提示必须各自带位置，才能分辨该选哪张
	var game_logic = get_logic()
	var player = game_logic.player
	player.discard_hand()

	var bomb_a = await _place_ground_bomb_at(player, 7)

	# 第二张直接置入加成区并占 3 号格（避免受回合限制影响本测试）
	var bomb_b = give_player_specific_card(player, "noelle_setbomb")
	var bomb_b_card = game_logic.get_card_database().get_card(bomb_b)
	player.remove_card_from_hand(bomb_b, false, false)
	player.add_to_continuous_boosts(bomb_b_card)
	player.add_boost_to_location(bomb_b, 3, false)
	await add_card_ui_to_zone(bomb_b, true, "AllCards/PlayerBoosts")

	assert_eq(player.get_boost_location(bomb_a), 7)
	assert_eq(player.get_boost_location(bomb_b), 3)

	game_ui._update_buttons(true)
	var text = boost_zone_text()
	assert_true(text.find("位置7") != -1, "应标出 7 号格的炸弹（实际：%s）" % text)
	assert_true(text.find("位置3") != -1, "应标出 3 号格的炸弹（实际：%s）" % text)

func test_boost_zone_hides_now_timing_effects():
	# timing=now 的效果（如 choice）不在加成区显示，其余时机照常显示
	var game_logic = get_logic()
	var player = game_logic.player
	player.discard_hand()

	var boost_id = give_player_specific_card(player, "zacoal_kradoom")
	var boost_card = game_logic.get_card_database().get_card(boost_id)
	player.remove_card_from_hand(boost_id, false, false)
	player.add_to_continuous_boosts(boost_card)
	await add_card_ui_to_zone(boost_id, true, "AllCards/PlayerBoosts")

	game_ui.update_boost_summary(Enums.PlayerId.PlayerId_Player, game_ui.get_node("AllCards/PlayerBoosts"), game_ui.get_node("PlayerBoostZone"))
	var text = boost_zone_text()
	var expected_text = GameStrings.get_effect_text(boost_card.definition["boost"]["effects"][0])
	assert_true(text.find(expected_text) != -1, "应显示 during_strike 加成（实际：%s）" % text)
	var now_text = GameStrings.get_effect_text(boost_card.definition["boost"]["effects"][1])
	assert_true(now_text != "" and text.find(now_text) == -1, "不应显示 timing=now 的效果（实际：%s）" % text)

func test_boost_zone_shows_explicitly_marked_now_effects():
	var game_logic = get_logic()
	var player = game_logic.player
	player.discard_hand()

	var boost_id = give_player_specific_card(player, "carcass_tube")
	var boost_card = game_logic.get_card_database().get_card(boost_id)
	player.remove_card_from_hand(boost_id, false, false)
	player.add_to_continuous_boosts(boost_card)
	await add_card_ui_to_zone(boost_id, true, "AllCards/PlayerBoosts")

	game_ui.update_boost_summary(Enums.PlayerId.PlayerId_Player, game_ui.get_node("AllCards/PlayerBoosts"), game_ui.get_node("PlayerBoostZone"))
	var text = boost_zone_text()
	var marked_now_effect = boost_card.definition["boost"]["effects"][1]
	assert_true(marked_now_effect.get("show_in_boost_summary", false))
	assert_true(text.find(GameStrings.get_effect_text(marked_now_effect)) != -1,
			"显式标记的 timing=now 效果应显示（实际：%s）" % text)

func test_boost_zone_hint_without_location_has_no_position_tag():
	# 没设置在场地上的可起战加成（无位置）不应显示位置字样，保持原提示
	var game_logic = get_logic()
	var player = game_logic.player
	player.discard_hand()

	var arrow_id = give_player_specific_card(player, "noelle_purewhitearrow")
	var arrow_card = game_logic.get_card_database().get_card(arrow_id)
	player.remove_card_from_hand(arrow_id, false, false)
	player.add_to_continuous_boosts(arrow_card)
	await add_card_ui_to_zone(arrow_id, true, "AllCards/PlayerBoosts")

	assert_eq(player.get_boost_location(arrow_id), -1, "前置：该卡未设置在场地")

	game_ui._update_buttons(true)
	var text = boost_zone_text()
	assert_true(text.find("设为攻击") != -1, "仍应提示可以设为攻击")
	for line in text.split("\n"):
		if line.find("设为攻击") != -1:
			assert_true(line.find("位置") == -1,
					"无位置的加成提示不应出现位置字样（实际：%s）" % line)

# ---------------- 加成区卡片标签：标出所在格 ----------------

func test_boost_zone_card_label_shows_position():
	# 点开加成区时，场地上的炸弹卡要带「位置N」标签
	# （加成弹窗会复制这个标签，所以玩家在弹窗里能一眼分辨该点哪张）
	var game_logic = get_logic()
	var player = game_logic.player
	player.discard_hand()

	var bomb_id = await _place_ground_bomb_at(player, 7)
	game_ui._on_player_boost_zone_clicked_zone(false)

	var card_node = game_ui.find_card_on_board(bomb_id)
	assert_not_null(card_node, "应能取到加成区的炸弹卡节点")
	assert_true(card_node.get_label().find("位置7") != -1,
			"炸弹卡标签应标出所在格（实际：%s）" % card_node.get_label())

func test_boost_zone_card_label_shows_position_and_sustain():
	# 既在场上、又处于维持状态时：标签两者都要有
	var game_logic = get_logic()
	var player = game_logic.player
	player.discard_hand()

	var bomb_id = await _place_ground_bomb_at(player, 3)
	if not bomb_id in player.sustained_boosts:
		player.sustained_boosts.append(bomb_id)

	game_ui._on_player_boost_zone_clicked_zone(false)
	var card_node = game_ui.find_card_on_board(bomb_id)
	var label = card_node.get_label()
	assert_true(label.find("位置3") != -1, "应包含位置（实际：%s）" % label)
	assert_true(label.find("已维持") != -1, "应保留维持标记（实际：%s）" % label)

func test_boost_zone_card_label_cleared_without_position_or_sustain():
	# 既没设置在场地、也没维持的加成：不应残留标签
	var game_logic = get_logic()
	var player = game_logic.player
	player.discard_hand()

	var arrow_id = give_player_specific_card(player, "noelle_purewhitearrow")
	var arrow_card = game_logic.get_card_database().get_card(arrow_id)
	player.remove_card_from_hand(arrow_id, false, false)
	player.add_to_continuous_boosts(arrow_card)
	await add_card_ui_to_zone(arrow_id, true, "AllCards/PlayerBoosts")

	game_ui._on_player_boost_zone_clicked_zone(false)
	var card_node = game_ui.find_card_on_board(arrow_id)
	assert_eq(card_node.get_label(), "", "无位置且未维持时不应显示标签")

func _find_card_with_id(root : Node, card_id : int):
	for child in root.get_children():
		if child is CardBase and child.card_id == card_id:
			return child
		var found = _find_card_with_id(child, card_id)
		if found:
			return found
	return null

func test_boost_popout_card_shows_position_label():
	# 「你的加成」弹窗会复制源卡标签 —— 玩家在弹窗里就能看到炸弹在哪一格
	var game_logic = get_logic()
	var player = game_logic.player
	player.discard_hand()

	var bomb_id = await _place_ground_bomb_at(player, 7)
	game_ui._on_player_boost_zone_clicked_zone(false)
	game_ui.show_popout(
		game_ui.CardPopoutType.CardPopoutType_BoostPlayer,
		"你的加成",
		game_ui.get_node("AllCards/PlayerBoosts"))

	assert_true(game_ui.card_popout_parent.get_child_count() > 0, "弹窗应已打开")
	var popout_root = game_ui.card_popout_parent.get_child(0)
	var pop_card = _find_card_with_id(popout_root, bomb_id)
	assert_not_null(pop_card, "弹窗里应出现炸弹卡")
	assert_true(pop_card.get_label().find("位置7") != -1,
			"弹窗卡上应显示所在格（实际：%s）" % pop_card.get_label())
