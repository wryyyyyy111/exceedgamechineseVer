extends GutTest

const ExceedSummaryText = "觉醒：速度+1，威力+1"

var game_ui : Game

func setup_game_ui(player_id : String, opponent_id : String):
	var game_scene = load("res://scenes/game/game.tscn")
	game_ui = game_scene.instantiate()
	game_ui.set_not_started_directly()
	add_child(game_ui)
	var game_logic = load("res://scenes/core/local_game.gd").new(game_ui.image_loader)
	game_logic.initialize_game(
		CardDataManager.get_deck_from_str_id(player_id),
		CardDataManager.get_deck_from_str_id(opponent_id),
		"p1", "p2", Enums.PlayerId.PlayerId_Player, randi())
	game_logic.draw_starting_hands_and_begin()
	assert_true(game_logic.do_mulligan(game_logic.player, []))
	assert_true(game_logic.do_mulligan(game_logic.opponent, []))
	game_logic.get_latest_events()
	game_ui.game_wrapper.current_game = game_logic

func after_each():
	if game_ui:
		game_ui.queue_free()
		game_ui = null

func _summary_text(player_id) -> String:
	var is_player = player_id == Enums.PlayerId.PlayerId_Player
	var box = game_ui.get_node("PlayerBoostZone" if is_player else "OpponentBoostZone")
	var cards = game_ui.get_node("AllCards/PlayerBoosts" if is_player else "AllCards/OpponentBoosts")
	game_ui.update_boost_summary(player_id, cards, box)
	return box.boost_effects.text
func test_beheaded_exceed_adds_and_revert_removes_summary_line():
	setup_game_ui("beheaded", "ryu")
	var player = game_ui.game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	assert_false(ExceedSummaryText in _summary_text(Enums.PlayerId.PlayerId_Player), "未觉醒时不应显示")

	player.exceeded = true
	assert_true(ExceedSummaryText in _summary_text(Enums.PlayerId.PlayerId_Player), "觉醒后应显示")

	player.exceeded = false
	assert_false(ExceedSummaryText in _summary_text(Enums.PlayerId.PlayerId_Player), "退出觉醒后应消失")

func test_other_character_exceed_has_no_beheaded_line():
	setup_game_ui("ryu", "beheaded")
	var player = game_ui.game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	player.exceeded = true
	assert_false(ExceedSummaryText in _summary_text(Enums.PlayerId.PlayerId_Player), "其他角色觉醒不应显示")
