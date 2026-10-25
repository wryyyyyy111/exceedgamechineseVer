extends GutTest

class CaptureRemote extends RemoteGame:
	var sent: Dictionary = {}
	var fixture_mode := ""

	func _init(loader, mode: String):
		super(loader)
		fixture_mode = mode

	func _submit_game_message(message):
		sent = message.duplicate(true)

	func _initialize_local_game(p_info, o_info, first: Enums.PlayerId, seed_value: int):
		super(p_info, o_info, first, seed_value)
		for remote_id in [17, 23]:
			var owner = _get_player_from_remote_id(remote_id)
			for card in owner.hand.duplicate():
				owner.discard([card.id], false)
		var p = _get_player_from_remote_id(17)
		var o = _get_player_from_remote_id(23)
		if fixture_mode == "guardian":
			_add_card(p, 50000, "gg_normal_grasp", "bleach")
			_add_card(o, 60000, "gg_normal_focus", "bleach")
			_add_card(p, 50001, "gg_normal_dust")
			_add_card(o, 60001, "gg_normal_focus")
		elif fixture_mode == "xuhua":
			o.arena_location = 4
			_add_card(p, 50001, "heiqiyihu_虚化")
			_add_card(o, 60001, "gg_normal_focus")
			_add_card(p, 50002, "gg_normal_cross", "gauge")
			_add_card(p, 50003, "gg_normal_grasp", "gauge")
			_add_card(p, 50004, "gg_normal_cross")
			_add_card(p, 50005, "gg_normal_grasp")
		elif fixture_mode == "mixed":
			p.exceeded = true
			o.arena_location = 4
			_add_card(p, 50000, "heiqiyihu_虚化", "bleach")
			_add_card(p, 50002, "gg_normal_cross", "bleach")
			_add_card(p, 50003, "gg_normal_grasp", "gauge")
			_add_card(p, 50001, "heiqiyihu_呼唤我的名字吧！")
			_add_card(o, 60001, "gg_normal_focus")
		elif fixture_mode == "force":
			p.exceeded = true
			_add_card(p, 50000, "heiqiyihu_虚化", "bleach")
			_add_card(p, 50002, "gg_normal_cross", "bleach")
			_add_card(p, 50001, "heiqiyihu_虚化")
		elif fixture_mode == "random":
			_add_card(p, 50001, "heiqiyihu_地裂崩击")
			_add_card(o, 60001, "gg_normal_focus")
			_add_card(o, 60002, "gg_normal_grasp")
			_add_card(o, 60003, "gg_normal_cross")
		elif fixture_mode == "threshold":
			p.life = 9
			o.life = 24
		local_game.get_latest_events()

	func _add_card(owner: Player, id: int, definition: String, zone: String = "hand"):
		var card = GameCard.new(id, CardDataManager.get_card(definition), owner.my_id)
		local_game.card_db._test_insert_card(card)
		match zone:
			"hand": owner.hand.append(card)
			"gauge": owner.add_to_gauge(card)
			"bleach": owner.add_to_bleach(card)

var remotes: Array = []
var history: Array = []
var mode := ""

func after_each():
	for remote in remotes:
		remote.teardown()
		remote.free()
	remotes.clear()
	history.clear()

func _new_remote(mirrored: bool = false, messages: Array = [], replay: bool = false) -> CaptureRemote:
	var deck = CardDataManager.get_deck_from_str_id("heiqiyihu").duplicate(true)
	deck["starting_life"] = 100
	deck["life_cap"] = 100
	var info = {"id": 17, "name": "p1", "deck": deck}
	var other = {"id": 23, "name": "p2", "deck": deck}
	var remote = CaptureRemote.new(CardImageLoader.new(true), mode)
	remotes.append(remote)
	remote.initialize_game(other if mirrored else info, info if mirrored else other,
		Enums.PlayerId.PlayerId_Opponent if mirrored else Enums.PlayerId.PlayerId_Player,
		24020, false, replay, messages)
	return remote

func _begin(fixture: String):
	mode = fixture
	_new_remote()
	_new_remote(true)
	_send(17, "do_mulligan", [[]])
	_send(23, "do_mulligan", [[]])

func _snapshot(remote: RemoteGame) -> Dictionary:
	var state = {"state": remote.get_game_state(), "players": []}
	for remote_id in [17, 23]:
		var owner = remote._get_player_from_remote_id(remote_id)
		var player_state = {"life": owner.life, "exceeded": owner.exceeded, "location": owner.arena_location}
		for zone in ["hand", "gauge", "bleach_zone", "discards", "deck", "continuous_boosts"]:
			player_state[zone] = AIPlayer.create_card_id_array(owner.get(zone))
		player_state["thresholds"] = owner.heiqiyihu_thresholds_used.duplicate()
		state["players"].append(player_state)
	var info = remote.local_game.decision_info
	state["decision"] = [info.type, remote._get_player_remote_id(remote.local_game._get_player(info.player)) \
		if info.player in [Enums.PlayerId.PlayerId_Player, Enums.PlayerId.PlayerId_Opponent] else -1,
		info.choice.size() if info.choice is Array else info.choice]
	if remote.get_game_state() not in [Enums.GameState.GameState_PlayerDecision, Enums.GameState.GameState_WaitForStrike]:
		state["decision"] = []
	elif info.choice is Array:
		state["options"] = []
		for option in info.choice:
			state["options"].append([
				option.get("effect_type"), option.get("guardian_card_id", -1),
				option.get("paid_id", -1), option.get("source", ""), option.get("_choice_text", "")
			])
	var strike = remote.local_game.active_strike
	state["strike"] = [] if strike == null else [
		strike.initiator_card.id if strike.initiator_card else -1,
		strike.defender_card.id if strike.defender_card else -1,
		remote.local_game.get_current_strike_timing()
	]
	return state

func _equal_all():
	for remote in remotes.slice(1):
		assert_eq(_snapshot(remote), _snapshot(remotes[0]))

func _send(remote_id: int, method: String, args: Array):
	var sender = remotes[0] if remote_id == 17 else remotes[1]
	assert_true(sender.callv(method, [sender._get_player_from_remote_id(remote_id)] + args))
	var message = sender.sent.duplicate(true)
	assert_eq(message["player_id"], remote_id)
	assert_eq(message["action_type"], method.replace("do_", "action_"))
	history.append(message)
	for remote in remotes:
		remote._process_game_message(message.duplicate(true))
	_equal_all()

func _restore_at_current_decision():
	var restored = _new_remote(false, history.duplicate(true))
	_equal_all()
	assert_eq(restored.get_message_history().size(), history.size())
	assert_eq(restored.get_pending_observer_messages().size(), history.size(), "Retained messages are for UI restore playback.")
	var decoded = JSON.parse_string(JSON.stringify(history))
	var replay = _new_remote(false, decoded, true)
	_equal_all()
	assert_eq(replay.get_message_history().size(), history.size())

func test_remote_mirror_guardian_declaration_restore_and_replay():
	_begin("guardian")
	_send(17, "do_strike", [-1, false, -1])
	assert_null(remotes[0].local_game.active_strike.initiator_card)
	assert_null(remotes[1].local_game.active_strike.defender_card)
	_restore_at_current_decision()
	_send(17, "do_choice", [0])
	assert_null(remotes[0].local_game.active_strike.initiator_card)
	_send(23, "do_choice", [0])
	assert_eq(remotes[0].get_game_state(), Enums.GameState.GameState_WaitForStrike)
	_send(17, "do_strike", [50001, false, -1])
	_send(23, "do_strike", [60001, false, -1])
	assert_null(remotes[0].local_game.active_strike)
	for remote in remotes:
		assert_true(remote._get_player_from_remote_id(17).is_card_in_discards(50000))

func test_remote_xuhua_pay_restore_after_hit_and_recover_exact_entities():
	_begin("xuhua")
	_send(17, "do_strike", [50001, false, -1])
	_send(23, "do_strike", [60001, false, -1])
	_send(17, "do_pay_strike_cost", [[50002, 50003], false, false])
	assert_eq(remotes[0].local_game.decision_info.type, Enums.DecisionType.DecisionType_ForceForEffect)
	_restore_at_current_decision()
	_send(17, "do_force_for_effect", [[50004, 50005], false, false])
	assert_eq(remotes[0].local_game.get_current_strike_timing(), "after")
	_send(17, "do_choice", [1])
	_send(17, "do_choice", [0])
	for remote in remotes:
		var owner = remote._get_player_from_remote_id(17)
		assert_true(owner.is_card_in_bleach(50005))
		assert_true(owner.is_card_in_gauge(50004))
		assert_true(owner.is_card_in_discards(50002))
		assert_null(remote.local_game.active_strike)

func test_remote_mixed_guardian_gauge_attack_payment():
	_begin("mixed")
	_send(17, "do_strike", [50001, false, -1])
	_send(23, "do_strike", [60001, false, -1])
	_send(17, "do_pay_strike_cost", [[50002, 50003], false, false])
	assert_null(remotes[0].local_game.active_strike)
	for remote in remotes:
		var owner = remote._get_player_from_remote_id(17)
		assert_true(owner.is_card_in_discards(50002))
		assert_true(owner.is_card_in_discards(50003))
		assert_true(owner.is_card_in_bleach(50000))

func test_remote_guardian_two_force_boost_then_guardian_cancel():
	_begin("force")
	_send(17, "do_boost", [50001, [50000]])
	_send(17, "do_choice", [0])
	assert_eq(remotes[0].local_game.decision_info.type, Enums.DecisionType.DecisionType_BoostCancel)
	_send(17, "do_boost_cancel", [[50002], true])
	for remote in remotes:
		var owner = remote._get_player_from_remote_id(17)
		assert_true(owner.is_card_in_discards(50000))
		assert_true(owner.is_card_in_discards(50002))
		assert_eq(remote.local_game.active_turn_player, owner.my_id)

func test_remote_random_discard_matches_both_views_and_json_replay():
	_begin("random")
	_send(17, "do_strike", [50001, false, -1])
	_send(23, "do_strike", [60001, false, -1])
	assert_eq(remotes[0].local_game.decision_info.type, Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect)
	_send(17, "do_choice", [0])
	assert_null(remotes[0].local_game.active_strike)
	var discards = AIPlayer.create_card_id_array(remotes[0]._get_player_from_remote_id(23).discards)
	assert_eq(int(60002 in discards) + int(60003 in discards), 1)
	_restore_at_current_decision()
	_equal_all()

func test_remote_initial_threshold_queue_restores_without_repeating_consumption():
	_begin("threshold")
	assert_eq(remotes[0].local_game.decision_info.player, Enums.PlayerId.PlayerId_Player)
	_restore_at_current_decision()
	for i in range(3):
		_send(17, "do_choice", [0])
	_send(23, "do_choice", [0])
	for remote in remotes:
		assert_eq(remote._get_player_from_remote_id(17).heiqiyihu_thresholds_used, [25, 15, 10])
		assert_eq(remote._get_player_from_remote_id(17).bleach_zone.size(), 3)
		assert_eq(remote._get_player_from_remote_id(23).heiqiyihu_thresholds_used, [25])
		assert_eq(remote._get_player_from_remote_id(23).bleach_zone.size(), 1)
