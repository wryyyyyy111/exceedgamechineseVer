extends GutTest

const GameScene = preload("res://scenes/game/game.tscn")
const CardScene = preload("res://scenes/card/card_base.tscn")

var game_ui: Game

func before_each():
	game_ui = GameScene.instantiate()
	game_ui.set_not_started_directly()
	add_child(game_ui)
	game_ui.set_process(false)
	game_ui.add_child(game_ui.game_wrapper)
	game_ui.image_loader.test_mode = true
	game_ui.player_deck = CardDataManager.get_deck_from_str_id("yuanliuzhai").duplicate(true)
	game_ui.opponent_deck = game_ui.player_deck.duplicate(true)
	var logic = LocalGame.new(game_ui.image_loader)
	logic.initialize_game(
		game_ui.player_deck, game_ui.opponent_deck,
		"p1", "p2", Enums.PlayerId.PlayerId_Player, 1)
	game_ui.game_wrapper.current_game = logic

func after_each():
	game_ui.queue_free()
	await get_tree().process_frame

func _assert_pressure_count_follows_cleanup_event(exceeded: bool, protected: bool = false):
	var logic = game_ui.game_wrapper.current_game
	for owner in [logic.player, logic.opponent]:
		owner.exceeded = exceeded
		var side = "Player" if owner == logic.player else "Opponent"
		for index in range(2 if protected else 1):
			var pressure_card = owner.deck.pop_front()
			owner.add_to_bleach(pressure_card)
			if index == 1:
				owner.yuanliuzhai_pressure_protected_ids.append(pressure_card.id)
			var card_ui = CardScene.instantiate()
			game_ui.get_node("AllCards/%sBleach" % side).add_child(card_ui)
			card_ui.initialize_card(
				pressure_card.id, null, null, owner == logic.opponent,
				pressure_card.definition["display_name"], "", pressure_card.definition)

	logic.get_latest_events()
	var effect_type = "yuanliuzhai_exceed_discard_pressure" if exceeded else "yuanliuzhai_discard_pressure"
	for owner in [logic.player, logic.opponent]:
		logic.handle_strike_effect(-1, {"effect_type": effect_type}, owner)
	var remaining_count = 1 if protected else 0
	assert_eq(logic.player.bleach_zone.size(), remaining_count)
	assert_eq(logic.opponent.bleach_zone.size(), remaining_count)

	game_ui._update_card_counts_now()
	for side in ["Player", "Opponent"]:
		var amount = game_ui.get_node("%sZones/%sBleach/BackgroundPanel/GaugePanel/GaugeVBox/GaugeAmount" % [side, side])
		assert_eq(amount.text, str(remaining_count + 1), "Pending cleanup events must not empty the displayed pressure zone early")

	for event in logic.get_latest_events():
		if event["event_type"] == Enums.EventType.EventType_AddToDiscard:
			game_ui._on_discard_event(event)
	game_ui._flush_deferred_ui_updates()
	for side in ["Player", "Opponent"]:
		var amount = game_ui.get_node("%sZones/%sBleach/BackgroundPanel/GaugePanel/GaugeVBox/GaugeAmount" % [side, side])
		assert_eq(amount.text, str(remaining_count), "The pressure count must change when its discard event is played")
		assert_eq(game_ui.get_node("AllCards/%sBleach" % side).get_child_count(), remaining_count)
		assert_eq(game_ui.get_node("AllCards/%sDiscards" % side).get_child_count(), 1)

func test_pressure_cleanup_timing_normal_ui():
	_assert_pressure_count_follows_cleanup_event(false)

func test_pressure_cleanup_timing_exceeded_ui():
	_assert_pressure_count_follows_cleanup_event(true)

func test_pressure_cleanup_timing_protected_card_stays_in_ui():
	_assert_pressure_count_follows_cleanup_event(true, true)
