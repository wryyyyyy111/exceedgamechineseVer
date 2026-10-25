extends GutTest

const GameScene = preload("res://scenes/game/game.tscn")

class DelayedCharacter extends Character:
	signal finish_loading
	var requested_animation := ""

	func load_character(_image_loader: CardImageLoader, _character_data: Dictionary,
			char_id: String, _yield_between_textures := true):
		requested_animation = char_id
		await finish_loading
		var frames := SpriteFrames.new()
		frames.add_animation("idle")
		var image := Image.create(80, 120, false, Image.FORMAT_RGBA8)
		frames.add_frame("idle", ImageTexture.create_from_image(image))
		animation.sprite_frames = frames
		scale = Vector2(2, 3)
		vertical_offset = 26

class LayoutWrapper extends GameWrapper:
	var poll_count := 0
	var pending_batches: Array = []

	func get_player_location(id):
		return 3 if id == Enums.PlayerId.PlayerId_Player else 7

	func poll_for_events() -> Array:
		poll_count += 1
		if not pending_batches.is_empty():
			return pending_batches.pop_front()
		return []

class LayoutGame extends Game:
	var draw_processed := false
	var reposition_count := 0
	var fast_forward_settled := false

	func _ready():
		pass

	func _exit_tree():
		pass

	func _log_event(_event):
		pass

	func _cache_local_mulligan_selection_if_needed():
		pass

	func _restore_local_mulligan_selection_if_needed():
		pass

	func _update_runtime_frame_health(_delta):
		pass

	func _update_network_reconnect_pause():
		pass

	func spawn_damage_popup(_value: String, _notice_player: Enums.PlayerId):
		pass

	func _refresh_hidden_boost_visuals_for_player(_player_id: Enums.PlayerId) -> void:
		pass

	func _play_awaken_entrance():
		pass

	func _refresh_combat_log_if_visible():
		pass

	func _settle_fast_forward_visual_state():
		fast_forward_settled = true

	func _update_replay_step_buttons():
		pass

	func update_arena_squares():
		pass

	func change_ui_state(new_state, new_sub_state = null):
		ui_state = new_state
		if new_sub_state != null:
			ui_sub_state = new_sub_state

	func _on_draw_event(_event):
		draw_processed = true

	func move_character_to_arena_square(character, arena_location, immediate: bool,
			move_anim: Character.CharacterAnim, buddy_offset: int = 0):
		reposition_count += 1
		super.move_character_to_arena_square(character, arena_location, immediate, move_anim, buddy_offset)

var game_ui: LayoutGame
var original_skin_config: Dictionary

func before_each():
	var instance = GameScene.instantiate()
	instance.game_wrapper.free()
	instance.set_script(LayoutGame)
	game_ui = instance
	game_ui.get_node("PlayerCharacter").set_script(DelayedCharacter)
	game_ui.get_node("OpponentCharacter").set_script(DelayedCharacter)
	game_ui.game_wrapper.free()
	game_ui.game_wrapper = LayoutWrapper.new()
	for node_name in ["PlayerCharacter", "OpponentCharacter"]:
		game_ui.get_node(node_name + "/Animation").sprite_frames = SpriteFrames.new()
	add_child(game_ui)
	game_ui.set_process(false)
	game_ui.player_deck = {
		"id": "layout_test", "exceed_animation": "layout_test_exceed",
		"wide_animation": "layout_test_wide",
	}
	game_ui.opponent_deck = game_ui.player_deck.duplicate()
	game_ui.first_run_done = true
	game_ui.restore_fast_forwarding = true
	original_skin_config = CharSkinManager._get_skin("specter", 1).duplicate(true)

func after_each():
	var skin_config = CharSkinManager._get_skin("specter", 1)
	skin_config.clear()
	skin_config.merge(original_skin_config)
	game_ui.game_wrapper.free()
	game_ui.queue_free()
	await get_tree().process_frame

func _assert_loading_then_position(event_type, player_id, expected_animation: String):
	var character: DelayedCharacter = game_ui.get_node(
		"PlayerCharacter" if player_id == Enums.PlayerId.PlayerId_Player else "OpponentCharacter")
	var original_position := character.position
	var event = {
		"event_type": event_type, "event_player": player_id, "number": 0, "extra_info": "",
	}
	var next_event = {
		"event_type": Enums.EventType.EventType_Draw,
		"event_player": player_id, "number": 0,
	}
	game_ui._handle_events([event, next_event])
	assert_eq(character.requested_animation, expected_animation)
	assert_true(game_ui.runtime_event_batch_in_progress)
	assert_eq(character.position, original_position, "Do not position using the old animation metadata")
	assert_eq(game_ui.reposition_count, 0)
	assert_false(game_ui.draw_processed, "Later events must wait for the animation")
	game_ui._process(0.016)
	assert_eq(game_ui.game_wrapper.poll_count, 0, "Frame processing must not reenter the event batch")

	character.finish_loading.emit()
	assert_false(game_ui.runtime_event_batch_in_progress)
	assert_eq(game_ui.reposition_count, 1)
	if not game_ui.restore_fast_forwarding:
		assert_false(game_ui.draw_processed, "The normal notice delay still pauses subsequent events")
		assert_eq(game_ui.ui_state, Game.UIState.UIState_PlayingAnimation)
		assert_gt(game_ui.remaining_delay, 0.0)
		assert_eq(game_ui.events_to_process.size(), 1)
		var remaining_events = game_ui.events_to_process
		game_ui.events_to_process = []
		game_ui._handle_events(remaining_events)
	assert_true(game_ui.draw_processed)
	var expected_position := game_ui.get_arena_square_center(
		game_ui.game_wrapper.get_player_location(player_id))
	expected_position.y -= 120.0 * 3.0 / 2.0 + game_ui.get_node("ArenaNode/RowButtons").position.y + 26.0
	expected_position = character.get_parent().to_local(expected_position)
	assert_almost_eq(character.position.x, expected_position.x, 0.001)
	assert_almost_eq(character.position.y, expected_position.y, 0.001)
	assert_eq(character.target_position, character.position)

func test_player_exceed_waits_for_animation_before_positioning():
	_assert_loading_then_position(Enums.EventType.EventType_Exceed,
		Enums.PlayerId.PlayerId_Player, "layout_test_exceed")

func test_opponent_exceed_waits_for_animation_before_positioning():
	_assert_loading_then_position(Enums.EventType.EventType_Exceed,
		Enums.PlayerId.PlayerId_Opponent, "layout_test_exceed")

func test_player_revert_waits_for_animation_before_positioning():
	_assert_loading_then_position(Enums.EventType.EventType_ExceedRevert,
		Enums.PlayerId.PlayerId_Player, "layout_test")

func test_opponent_revert_waits_for_animation_before_positioning():
	_assert_loading_then_position(Enums.EventType.EventType_ExceedRevert,
		Enums.PlayerId.PlayerId_Opponent, "layout_test")

func test_player_wide_form_waits_for_animation_before_positioning():
	_assert_loading_then_position(Enums.EventType.EventType_BecomeWide,
		Enums.PlayerId.PlayerId_Player, "layout_test_wide")

func test_opponent_wide_form_waits_for_animation_before_positioning():
	_assert_loading_then_position(Enums.EventType.EventType_BecomeWide,
		Enums.PlayerId.PlayerId_Opponent, "layout_test_wide")

func test_normal_play_waits_for_loading_then_preserves_notice_delay():
	game_ui.restore_fast_forwarding = false
	_assert_loading_then_position(Enums.EventType.EventType_Exceed,
		Enums.PlayerId.PlayerId_Player, "layout_test_exceed")

func test_skin_exceed_without_explicit_exceed_animation_updates_position():
	var skin_config = CharSkinManager._get_skin("specter", 1)
	skin_config["animations_skin"] = true
	skin_config["exceed_change_skin"] = true
	game_ui.player_deck = {"id": "specter_1"}
	_assert_loading_then_position(Enums.EventType.EventType_Exceed,
		Enums.PlayerId.PlayerId_Player, "specter_1_exceed")

func test_skin_revert_without_explicit_exceed_animation_updates_position():
	var skin_config = CharSkinManager._get_skin("specter", 1)
	skin_config["animations_skin"] = true
	skin_config["exceed_change_skin"] = true
	game_ui.opponent_deck = {"id": "specter_1"}
	_assert_loading_then_position(Enums.EventType.EventType_ExceedRevert,
		Enums.PlayerId.PlayerId_Opponent, "specter_1")

func test_restore_fast_forward_waits_for_animation_before_polling_next_batch():
	var character: DelayedCharacter = game_ui.get_node("PlayerCharacter")
	game_ui.restore_fast_forward_pending = true
	game_ui.restore_fast_forwarding = false
	game_ui.game_wrapper.pending_batches = [
		[{
			"event_type": Enums.EventType.EventType_Exceed,
			"event_player": Enums.PlayerId.PlayerId_Player, "number": 0,
		}],
		[{
			"event_type": Enums.EventType.EventType_Draw,
			"event_player": Enums.PlayerId.PlayerId_Player, "number": 0,
		}],
	]
	game_ui._fast_forward_restored_game_if_needed()
	assert_eq(game_ui.game_wrapper.poll_count, 1)
	assert_true(game_ui.runtime_event_batch_in_progress)
	assert_false(game_ui.fast_forward_settled)
	assert_false(game_ui.draw_processed)
	character.finish_loading.emit()
	assert_eq(game_ui.game_wrapper.poll_count, 3)
	assert_true(game_ui.draw_processed)
	assert_true(game_ui.fast_forward_settled)
	assert_false(game_ui.restore_fast_forwarding)
	assert_false(game_ui.runtime_event_batch_in_progress)
	assert_eq(game_ui.reposition_count, 1)
