extends ExceedGutTest

class StrikeUI extends Game:
	var chosen_source := ""
	var response_requested := false
	var emotes_seen := 0
	var attacks_seen := 0

	func spawn_damage_popup(_value: String, _player: Enums.PlayerId):
		pass

	func change_ui_state(new_state, new_sub_state = null):
		if new_state != null:
			ui_state = new_state
		if new_sub_state != null:
			ui_sub_state = new_sub_state

	func begin_gauge_strike_choosing(_response: bool, _cancel: bool, source: String):
		chosen_source = source

	func begin_strike_choosing(_response: bool, _cancel: bool,
			_opponent_first: bool = false, _disable_wild: bool = false,
			_disable_ex: bool = false, _require_ex = false):
		response_requested = true
		change_ui_state(UIState.UIState_SelectCards, UISubState.UISubState_SelectCards_StrikeResponseCard)

	func _on_strike_started(_event, _is_ex: bool, _is_wild: bool = false):
		attacks_seen += 1

	func _on_emote(_event):
		emotes_seen += 1

var game_ui: StrikeUI
var remote: RemoteGame

func who_am_i():
	return "doomies"

func before_each():
	default_game_setup("hyde")
	remote = RemoteGame.new(image_loader)
	remote.local_game = game_logic
	remote._player_info = {"id": 17}
	remote._opponent_info = {"id": 23}
	game_ui = StrikeUI.new()
	game_ui.game_wrapper.current_game = remote
	game_logic.active_turn_player = player2.my_id
	player2.exceeded = true

func after_each():
	game_ui.game_wrapper.free()
	game_ui.free()
	remote.local_game = null
	remote.free()
	super.after_each()

func _start_gauge_action() -> Array:
	var payment = give_gauge(player2, 1)
	var attack_id = give_player_specific_card(player2, "uni_normal_cross")
	player2.add_to_gauge(game_logic.card_db.get_card(attack_id))
	player2.remove_card_from_hand(attack_id, false, false)
	remote.process_character_action({
		"player_id": 23, "card_ids": payment, "action_idx": 0,
		"use_free_force": false, "spent_life_for_force": 0,
	})
	assert_eq(game_logic.decision_info.source, "gauge")
	var events = game_logic.get_latest_events()
	var prompts = events.filter(func(event):
		return event["event_type"] == Enums.EventType.EventType_Strike_FromGauge)
	assert_eq(prompts.size(), 1)
	return [prompts[0], attack_id]

func test_delayed_hyde_gauge_prompt_does_not_drop_attack_and_response():
	var setup = _start_gauge_action()
	# Both network actions arrive before the receiver finishes its animations.
	remote.process_strike({
		"player_id": 23, "card_id": setup[1], "wild_strike": false,
		"ex_card_id": -1, "opponent_sets_first": false, "use_face_attack": false,
	})
	assert_eq(game_logic.game_state, Enums.GameState.GameState_Strike_Opponent_Response)
	assert_null(game_logic.decision_info.source)
	var strike_events = game_logic.get_latest_events().filter(func(event):
		return event["event_type"] in [
			Enums.EventType.EventType_Strike_Started,
			Enums.EventType.EventType_Strike_DoResponseNow,
		])
	assert_eq(strike_events.size(), 2)
	await game_ui._handle_events([setup[0]] + strike_events)
	var pending = game_ui.events_to_process
	game_ui.events_to_process = []
	await game_ui._handle_events(pending)
	assert_false(game_ui.runtime_event_batch_in_progress)
	assert_eq(game_ui.attacks_seen, 1)
	assert_true(game_ui.response_requested)
	assert_eq(game_ui.ui_sub_state, Game.UISubState.UISubState_SelectCards_StrikeResponseCard)

	remote.process_emote({"player_id": 23, "is_image_emote": false, "emote": "hello"})
	await game_ui._handle_events(game_logic.get_latest_events())
	assert_eq(game_ui.emotes_seen, 1)
	assert_true(game_ui.response_requested)

func test_gauge_prompt_carries_source_before_decision_is_cleared():
	var setup = _start_gauge_action()
	assert_eq(setup[0]["extra_info"], "gauge")
	assert_eq(game_ui._on_strike_from_gauge(setup[0]), Game.SmallNoticeDelay)

func test_local_gauge_prompt_uses_event_source_not_later_decision():
	var setup = _start_gauge_action()
	setup[0]["event_player"] = Enums.PlayerId.PlayerId_Player
	game_logic.decision_info.source = "sealed"
	game_ui._on_strike_from_gauge(setup[0])
	assert_eq(game_ui.chosen_source, "gauge")

func test_sealed_strike_prompt_carries_its_own_source():
	var sealed_id = give_player_specific_card(player2, "uni_normal_cross")
	player2.seal_from_location(sealed_id, "hand")
	game_logic.handle_strike_effect(-1, {"effect_type": "strike_from_sealed"}, player2)
	var prompts = game_logic.get_latest_events().filter(func(event):
		return event["event_type"] == Enums.EventType.EventType_Strike_FromGauge)
	assert_eq(prompts.size(), 1)
	assert_eq(prompts[0]["extra_info"], "sealed")
