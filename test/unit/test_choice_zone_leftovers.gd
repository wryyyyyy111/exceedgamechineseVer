extends GutTest

# 回归：看牌库顶的决策结束后，未选中的牌必须离开 ChoiceZone。
# 否则下一次「看顶 N 张」的弹窗会把上一次的牌一起显示出来
# （实测场景：尤金妮娅 Queen of Hearts 加成看顶 30 张后，
#   亚拉酷泥 f inverse 加成本应只看顶 5 张，却显示成整个牌库）。

const CARD_SCENE := "res://scenes/card/card_base.tscn"

var game_ui : Game

func setup_game_ui(player_id : String = "eugenia", opponent_id : String = "arakune"):
	var game_scene = load("res://scenes/game/game.tscn")
	game_ui = game_scene.instantiate()
	game_ui.set_not_started_directly()
	game_ui.add_child(game_ui.game_wrapper)
	add_child(game_ui)
	var game_logic = load("res://scenes/core/local_game.gd").new(game_ui.image_loader)
	game_logic.initialize_game(
		CardDataManager.get_deck_from_str_id(player_id),
		CardDataManager.get_deck_from_str_id(opponent_id),
		"p1",
		"p2",
		Enums.PlayerId.PlayerId_Player,
		randi()
	)
	game_logic.draw_starting_hands_and_begin()
	game_logic.do_mulligan(game_logic.player, [])
	game_logic.do_mulligan(game_logic.opponent, [])
	game_logic.get_latest_events()
	game_ui.game_wrapper.current_game = game_logic

func _spawn_choice_card(card_id : int) -> CardBase:
	var card = load(CARD_SCENE).instantiate()
	card.card_id = card_id
	game_ui.get_node("AllCards/ChoiceZone").add_child(card)
	return card

func before_each():
	setup_game_ui()

func after_each():
	if game_ui:
		game_ui.queue_free()
		game_ui = null
		await get_tree().process_frame

func _player_deck_ids(count : int) -> Array:
	var ids = []
	var deck_list = game_ui.game_wrapper.get_player_deck_list(Enums.PlayerId.PlayerId_Player)
	for i in range(min(count, deck_list.size())):
		ids.append(deck_list[i].id)
	return ids

func test_stale_choice_zone_cards_return_to_deck():
	var ids = _player_deck_ids(8)
	assert_eq(ids.size(), 8)
	for id in ids:
		_spawn_choice_card(id)
	var zone = game_ui.get_node("AllCards/ChoiceZone")
	var deck_zone = game_ui.get_node("AllCards/PlayerDeck")
	var deck_before = deck_zone.get_child_count()

	game_ui._park_stale_choice_zone_cards([])

	assert_eq(zone.get_child_count(), 0, "残留牌应全部离开选择区")
	assert_eq(deck_zone.get_child_count(), deck_before + 8, "残留牌应回到牌库")

func test_current_decision_cards_are_kept():
	var ids = _player_deck_ids(5)
	for id in ids:
		_spawn_choice_card(id)
	var zone = game_ui.get_node("AllCards/ChoiceZone")

	game_ui._park_stale_choice_zone_cards([ids[0], ids[1]])

	assert_eq(zone.get_child_count(), 2, "属于本次决策的牌不能被回收")
	assert_eq(zone.get_child(0).card_id, ids[0])
	assert_eq(zone.get_child(1).card_id, ids[1])

func test_only_five_cards_visible_for_topdeck_five_after_big_look():
	# 模拟上一次「看顶 20 张」留下的 20 张
	for id in _player_deck_ids(20):
		_spawn_choice_card(id)
	assert_eq(game_ui.get_node("AllCards/ChoiceZone").get_child_count(), 20)

	# 下一次是「看顶 5 张」：填充前先回收旧牌
	var next_ids = _player_deck_ids(5)
	game_ui._park_stale_choice_zone_cards(next_ids)
	for id in next_ids:
		if game_ui.get_node("AllCards/ChoiceZone").get_child_count() < 5:
			_spawn_choice_card(id)

	var visible_ids = []
	for child in game_ui.get_node("AllCards/ChoiceZone").get_children():
		visible_ids.append(child.card_id)
	assert_eq(visible_ids.size(), 5, "查看顶 5 张时只应有 5 张牌")
	for id in visible_ids:
		assert_true(id in next_ids, "弹窗里不能混入上一次看牌的残留")
