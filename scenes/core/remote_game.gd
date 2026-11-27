#### !!! WARNING !!!
# This file handles the communication of actions between clients. When a local
# game calls `do_X`, it transmits a dictionary-like message to the game server,
# with key `'action_type': "action_Y"`. The game server sends this to both clients,
# and the clients on both sides then handle the message with
# `process_Z()`. Because this mapping is done through string manipulation, it is
# important that X == Y == Z.

class_name RemoteGame
extends Node

var local_game : LocalGame

var _player_info
var _opponent_info
var _observer_mode : bool
var _replay_mode : bool
var _game_message_queue : Array
var _game_message_history : Array
var _pending_minato_sealed_force : int
var _pending_minato_sealed_gauge : int

const RestoreFastForwardRiskyEventTypes = [
	Enums.EventType.EventType_EffectDoBoost,
	Enums.EventType.EventType_Strike_EffectDoStrike,
	Enums.EventType.EventType_Strike_OpponentSetsFirst,
]

var image_loader : CardImageLoader
func _init(card_image_loader):
	image_loader = card_image_loader

func teardown():
	if NetworkManager.is_connected("game_message_received", _on_remote_game_message):
		NetworkManager.disconnect("game_message_received", _on_remote_game_message)
	if NetworkManager.is_connected("other_player_quit", _on_remote_player_quit):
		NetworkManager.disconnect("other_player_quit", _on_remote_player_quit)
	if NetworkManager.is_connected("disconnected_from_server", _on_disconnected):
		NetworkManager.disconnect("disconnected_from_server", _on_disconnected)
	if local_game:
		local_game.teardown()
		local_game.free()
		local_game = null

func get_latest_events() -> Array:
	return local_game.get_latest_events()

func get_combat_log(log_filters, start_index : int = 0) -> String:
	return local_game.get_combat_log(log_filters, start_index)

func get_combat_log_size() -> int:
	return local_game.get_combat_log_size()

func get_message_history() -> Array:
	return _game_message_history

func get_pending_observer_messages() -> Array:
	return _game_message_queue.duplicate(true)

func get_next_observer_message() -> Dictionary:
	if _game_message_queue.is_empty():
		return {}
	return _game_message_queue[0]

func _get_player(id):
	return local_game._get_player(id)

func _get_player_remote_id(player : Player) -> int:
	if player.my_id == Enums.PlayerId.PlayerId_Player:
		return _player_info['id']
	else:
		return _opponent_info['id']

func _get_player_from_remote_id(remote_id : int):
	if remote_id == _player_info['id']:
		return _get_player(Enums.PlayerId.PlayerId_Player)
	else:
		return _get_player(Enums.PlayerId.PlayerId_Opponent)

func get_striking_card_ids_for_player(player : Player) -> Array:
	return local_game.get_striking_card_ids_for_player(player)

func initialize_game(player_info,
		opponent_info,
		starting_player : Enums.PlayerId,
		seed_value : int,
		observer_mode : bool,
		replay_mode : bool,
		starting_message_queue : Array):
	_game_message_queue = starting_message_queue.duplicate(true)
	if replay_mode:
		_game_message_queue = _normalize_replay_json_numbers(_game_message_queue)
	_game_message_history = []

	_player_info = player_info
	_opponent_info = opponent_info
	_observer_mode = observer_mode
	_replay_mode = replay_mode
	_initialize_local_game(player_info, opponent_info, starting_player, seed_value)
	if not observer_mode and starting_message_queue.size() > 0:
		_process_restore_message_queue_with_safety_check(player_info, opponent_info, starting_player, seed_value, starting_message_queue)

	NetworkManager.connect("game_message_received", _on_remote_game_message)
	NetworkManager.connect("other_player_quit", _on_remote_player_quit)
	NetworkManager.connect("disconnected_from_server", _on_disconnected)

func _normalize_replay_json_numbers(value):
	if value is Array:
		var normalized_array := []
		for item in value:
			normalized_array.append(_normalize_replay_json_numbers(item))
		return normalized_array
	if value is Dictionary:
		var normalized_dictionary := {}
		for key in value:
			normalized_dictionary[key] = _normalize_replay_json_numbers(value[key])
		return normalized_dictionary
	if value is float and is_finite(value) and value == floor(value):
		return int(value)
	return value

func _initialize_local_game(player_info, opponent_info, starting_player : Enums.PlayerId, seed_value : int):
	if local_game:
		local_game.teardown()
		local_game.free()
	local_game = LocalGame.new(image_loader)
	local_game.initialize_game(player_info['deck'], opponent_info['deck'],
		player_info['name'], opponent_info['name'], starting_player, seed_value)
	local_game.draw_starting_hands_and_begin()
	_game_message_history = []

func _process_restore_message_queue_with_safety_check(player_info, opponent_info, starting_player : Enums.PlayerId, seed_value : int, starting_message_queue : Array):
	var safe_message_queue = starting_message_queue.duplicate(true)
	while true:
		var trailing_message_has_risky_event = false
		for message_index in range(safe_message_queue.size()):
			var message = safe_message_queue[message_index]
			var event_start_index = local_game.event_queue.size()
			_process_game_message(message)
			if message_index == safe_message_queue.size() - 1:
				trailing_message_has_risky_event = _has_risky_restore_fast_forward_event(event_start_index)
		if not trailing_message_has_risky_event or safe_message_queue.is_empty():
			_game_message_queue = safe_message_queue
			return

		var dropped_message = safe_message_queue[safe_message_queue.size() - 1]
		if GlobalSettings.is_logging_enabled():
			print("Restore fast-forward rolled back one risky message: %s" % str(dropped_message.get('action_type', 'missing')))
		safe_message_queue = safe_message_queue.slice(0, safe_message_queue.size() - 1)
		_initialize_local_game(player_info, opponent_info, starting_player, seed_value)

func _has_risky_restore_fast_forward_event(start_index : int = 0) -> bool:
	for event in local_game.event_queue.slice(start_index):
		if event.get('event_type') in RestoreFastForwardRiskyEventTypes:
			return true
	return false

func _on_remote_game_message(game_message):
	if GlobalSettings.is_logging_enabled():
		print("REMOTE_GAME_MESSAGE action=%s observer=%s queue=%d history=%d" % [
			str(game_message.get('action_type', 'missing')),
			str(_observer_mode),
			_game_message_queue.size(),
			_game_message_history.size(),
		])
	if _observer_mode:
		_game_message_queue.append(game_message)
	else:
		_process_game_message(game_message)

func observer_process_next_message_from_queue():
	if _game_message_queue.size() > 0:
		var message = _game_message_queue[0]
		_game_message_queue.remove_at(0)
		if message['action_type'] == "match_result":
			return false
		_process_game_message(message)
		return true
	else:
		return false

func _process_game_message(game_message):
	_save_game_message(game_message)
	var sealed_force = int(game_message.get('minato_sealed_force', 0))
	var sealed_gauge = int(game_message.get('minato_sealed_gauge', 0))
	var seal_player = null
	if sealed_force > 0 or sealed_gauge > 0:
		seal_player = _get_player_from_remote_id(game_message['player_id'])
		var sealed_card_count = sealed_force + sealed_gauge * 3
		if seal_player.deck_def.get("id") != "minato" or seal_player.exceeded or sealed_card_count > seal_player.discards.size():
			local_game.printlog("ERROR: Invalid Minato sealed-discard payment in remote action.")
			return
		seal_player.seal_top_n_discards(sealed_card_count)
		seal_player.seal_force_bonus_tmp = sealed_force
		seal_player.free_gauge += sealed_gauge
	var action_type = game_message['action_type']
	var action_function_name = action_type.replace("action_", "process_")
	var action_function = Callable(self, action_function_name)
	action_function.call(game_message)
	if seal_player:
		seal_player.seal_force_bonus_tmp = 0
		seal_player.free_gauge = max(seal_player.free_gauge - sealed_gauge, 0)

func _save_game_message(game_message):
	var updated_game_message = game_message.duplicate()
	updated_game_message['your_player_id'] = _player_info['id']
	_game_message_history.append(updated_game_message)

func _on_disconnected():
	return

func _on_remote_player_quit(_is_disconnect : bool):
	if get_game_state() == Enums.GameState.GameState_GameOver:
		return
	NetworkManager.begin_waiting_for_opponent_reconnect()

func get_game_state() -> Enums.GameState:
	return local_game.get_game_state()

func has_active_strike() -> bool:
	return local_game.has_active_strike()

func get_active_player() -> Enums.PlayerId:
	return local_game.get_active_player()

func get_priority_player() -> Enums.PlayerId:
	return local_game.get_priority_player()

func get_decision_info() -> DecisionInfo:
	return local_game.get_decision_info()

func get_card_database() -> CardDatabase:
	return local_game.get_card_database()

func get_other_player(test_player : Enums.PlayerId) -> Enums.PlayerId:
	return local_game.get_other_player(test_player)

func _is_spiraling_match(target_def_id : String, check_card : GameCard) -> bool:
	return local_game._is_spiraling_match(target_def_id, check_card)

func can_do_prepare(player : Player) -> bool:
	return local_game.can_do_prepare(player)

func can_do_move(player : Player) -> bool:
	return local_game.can_do_move(player)

func can_do_change(player : Player) -> bool:
	return local_game.can_do_change(player)

func can_do_exceed(player : Player) -> bool:
	return local_game.can_do_exceed(player)

func can_do_reshuffle(player : Player) -> bool:
	return local_game.can_do_reshuffle(player)

func can_do_boost(player : Player) -> bool:
	return local_game.can_do_boost(player)

func can_do_ex_transform(player : Player) -> bool:
	return local_game.can_do_ex_transform(player)

func can_do_strike(player : Player) -> bool:
	return local_game.can_do_strike(player)

func can_move_to(player : Player, location : int) -> bool:
	var ignore_force_req = false
	return player.can_move_to(location, ignore_force_req)

### Action Functions ###

func _submit_game_message(action_message):
	_add_pending_minato_seal_payment(action_message)
	NetworkManager.submit_game_message(action_message)

func _add_pending_minato_seal_payment(action_message : Dictionary) -> void:
	if _pending_minato_sealed_force > 0:
		action_message['minato_sealed_force'] = _pending_minato_sealed_force
	if _pending_minato_sealed_gauge > 0:
		action_message['minato_sealed_gauge'] = _pending_minato_sealed_gauge
	clear_pending_minato_seal_payment()

func set_pending_minato_seal_payment(force_amount : int, gauge_amount : int) -> void:
	_pending_minato_sealed_force += force_amount
	_pending_minato_sealed_gauge += gauge_amount

func clear_pending_minato_seal_payment() -> void:
	_pending_minato_sealed_force = 0
	_pending_minato_sealed_gauge = 0

func do_prepare(player : Player) -> bool:
	var action_message = {
		'action_type': 'action_prepare',
		'player_id': _get_player_remote_id(player),
	}
	_submit_game_message(action_message)
	return true

func process_prepare(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	local_game.do_prepare(game_player)

func do_reshuffle(player : Player) -> bool:
	var action_message = {
		'action_type': 'action_reshuffle',
		'player_id': _get_player_remote_id(player),
	}
	_submit_game_message(action_message)
	return true

func process_reshuffle(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	local_game.do_reshuffle(game_player)

func do_choice(player : Player, choice_index : int) -> bool:
	var action_message = {
		'action_type': 'action_choice',
		'player_id': _get_player_remote_id(player),
		'choice_index': choice_index,
	}
	_submit_game_message(action_message)
	return true

func process_choice(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	var choice_index = action_message['choice_index']
	local_game.do_choice(game_player, choice_index)

# Minato Outrun the Past (attacker side): the strike button triggers this BEFORE
# the attack card is selected. It must travel over the network so both local
# engines set up the same seal decision; otherwise the opponent's engine never
# learns about it and the online game freezes (same root cause as Renea's
# pre-strike facedown reveal).
func do_minato_outrun_before_strike(player : Player) -> bool:
	var action_message = {
		'action_type': 'action_minato_outrun_before_strike',
		'player_id': _get_player_remote_id(player),
	}
	_submit_game_message(action_message)
	return true

func process_minato_outrun_before_strike(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	game_player.minato_outrun_triggered_before_strike = true
	local_game.handle_strike_effect(-1, {
		"effect_type": "minato_outrun_the_past",
		"minato_otp_sealed": 0
	}, game_player)

func do_renea_pre_strike_reveal(player : Player, strike_response : bool = false) -> bool:
	var action_message = {
		'action_type': 'action_renea_pre_strike_reveal',
		'player_id': _get_player_remote_id(player),
		'strike_response': strike_response,
	}
	_submit_game_message(action_message)
	return true

func process_renea_pre_strike_reveal(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	local_game._renea_begin_pre_strike_reveal(game_player, not action_message.get('strike_response', false), action_message.get('strike_response', false))

func do_boost_cancel(player : Player, gauge_card_ids : Array, doing_cancel : bool) -> bool:
	var action_message = {
		'action_type': 'action_boost_cancel',
		'player_id': _get_player_remote_id(player),
		'gauge_card_ids': gauge_card_ids,
		'doing_cancel': doing_cancel,
	}
	_submit_game_message(action_message)
	return true

func process_boost_cancel(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	var gauge_card_ids = action_message['gauge_card_ids']
	var doing_cancel = action_message['doing_cancel']
	local_game.do_boost_cancel(game_player, gauge_card_ids, doing_cancel)

func do_boost_name_card_choice_effect(player : Player, card_id : int) -> bool:
	var action_message = {
		'action_type': 'action_boost_name_card_choice_effect',
		'player_id': _get_player_remote_id(player),
		'card_id': card_id,
	}
	_submit_game_message(action_message)
	return true

func process_boost_name_card_choice_effect(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	var card_id = action_message['card_id']
	local_game.do_boost_name_card_choice_effect(game_player, card_id)

func do_discard_to_max(player : Player, card_ids : Array) -> bool:
	var action_message = {
		'action_type': 'action_discard_to_max',
		'player_id': _get_player_remote_id(player),
		'card_ids': card_ids,
	}
	_submit_game_message(action_message)
	return true

func process_discard_to_max(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	var card_ids = action_message['card_ids']
	local_game.do_discard_to_max(game_player, card_ids)

func do_relocate_card_from_hand(player : Player, card_ids : Array) -> bool:
	var action_message = {
		'action_type': 'action_relocate_card_from_hand',
		'player_id': _get_player_remote_id(player),
		'card_ids': card_ids,
	}
	_submit_game_message(action_message)
	return true

func process_relocate_card_from_hand(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	var card_ids = action_message['card_ids']
	local_game.do_relocate_card_from_hand(game_player, card_ids)

func do_pay_strike_cost(
	player : Player,
	card_ids : Array,
	wild_strike : bool,
	discard_ex_first : bool,
	use_free_force : bool = false,
	spent_life_for_force : int = 0,
	pay_alternative_life_cost : bool = false,
	spent_life_for_gauge : int = 0
	) -> bool:
	var action_message = {
		'action_type': 'action_pay_strike_cost',
		'player_id': _get_player_remote_id(player),
		'card_ids': card_ids,
		'wild_strike': wild_strike,
		'discard_ex_first': discard_ex_first,
		'use_free_force': use_free_force,
		'spent_life_for_force': spent_life_for_force,
		'pay_alternative_life_cost': pay_alternative_life_cost,
		'spent_life_for_gauge': spent_life_for_gauge,
	}
	_submit_game_message(action_message)
	return true

func process_pay_strike_cost(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	var card_ids = action_message['card_ids']
	var wild_strike = action_message['wild_strike']
	var discard_ex_first = action_message['discard_ex_first']
	var use_free_force = action_message['use_free_force']
	var spent_life_for_force = action_message['spent_life_for_force']
	var pay_alternative_life_cost = action_message['pay_alternative_life_cost']
	var spent_life_for_gauge = action_message.get('spent_life_for_gauge', 0)
	local_game.do_pay_strike_cost(game_player, card_ids, wild_strike, discard_ex_first, use_free_force, spent_life_for_force, pay_alternative_life_cost, spent_life_for_gauge)

func do_exceed(player : Player, card_ids : Array, spent_life_for_gauge : int = 0) -> bool:
	var action_message = {
		'action_type': 'action_exceed',
		'player_id': _get_player_remote_id(player),
		'card_ids': card_ids,
		'spent_life_for_gauge': spent_life_for_gauge,
	}
	_submit_game_message(action_message)
	return true

func process_exceed(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	var card_ids = action_message['card_ids']
	var spent_life_for_gauge = action_message.get('spent_life_for_gauge', 0)
	local_game.do_exceed(game_player, card_ids, spent_life_for_gauge)

func do_move(player : Player, card_ids : Array, new_arena_location : int, use_free_force : bool = false, spent_life_for_force : int = 0) -> bool:
	var action_message = {
		'action_type': 'action_move',
		'player_id': _get_player_remote_id(player),
		'card_ids': card_ids,
		'new_arena_location': new_arena_location,
		'use_free_force': use_free_force,
		'spent_life_for_force': spent_life_for_force,
	}
	_submit_game_message(action_message)
	return true

func process_move(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	var card_ids = action_message['card_ids']
	var new_arena_location = action_message['new_arena_location']
	var use_free_force = action_message['use_free_force']
	var spent_life_for_force = action_message['spent_life_for_force']
	local_game.do_move(game_player, card_ids, new_arena_location, use_free_force, spent_life_for_force)

func do_change(player : Player, card_ids : Array, treat_ultras_as_single_force : bool,
		use_free_force : bool = false, spent_life_for_force : int = 0) -> bool:
	var action_message = {
		'action_type': 'action_change',
		'player_id': _get_player_remote_id(player),
		'card_ids': card_ids,
		'treat_ultras_as_single_force': treat_ultras_as_single_force,
		'use_free_force': use_free_force,
		'spent_life_for_force': spent_life_for_force,
	}
	_submit_game_message(action_message)
	return true

func process_change(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	var card_ids = action_message['card_ids']
	var treat_ultras_as_single_force = action_message['treat_ultras_as_single_force']
	var use_free_force = action_message['use_free_force']
	var spent_life_for_force = action_message['spent_life_for_force']
	local_game.do_change(game_player, card_ids, treat_ultras_as_single_force, use_free_force, spent_life_for_force)

func do_strike(player : Player, card_id : int, wild_strike: bool, ex_card_id : int,
		opponent_sets_first : bool = false, use_face_attack : bool = false) -> bool:
	var action_message = {
		'action_type': 'action_strike',
		'player_id': _get_player_remote_id(player),
		'card_id': card_id,
		'wild_strike': wild_strike,
		'ex_card_id': ex_card_id,
		'opponent_sets_first': opponent_sets_first,
		'use_face_attack': use_face_attack
	}
	_submit_game_message(action_message)
	return true

func process_strike(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	var card_id = action_message['card_id']
	var wild_strike = action_message['wild_strike']
	var ex_card_id = action_message['ex_card_id']
	var opponent_sets_first = action_message['opponent_sets_first']
	var use_face_attack = action_message['use_face_attack']
	local_game.do_strike(game_player, card_id, wild_strike, ex_card_id, opponent_sets_first, use_face_attack)

func do_force_for_armor(player : Player, card_ids : Array, use_free_force : bool = false, spent_life_for_force : int = 0) -> bool:
	var action_message = {
		'action_type': 'action_force_for_armor',
		'player_id': _get_player_remote_id(player),
		'card_ids': card_ids,
		'use_free_force': use_free_force,
		'spent_life_for_force': spent_life_for_force,
	}
	_submit_game_message(action_message)
	return true

func process_force_for_armor(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	var card_ids = action_message['card_ids']
	var use_free_force = action_message['use_free_force']
	var spent_life_for_force = action_message['spent_life_for_force']
	local_game.do_force_for_armor(game_player, card_ids, use_free_force, spent_life_for_force)

func do_mulligan(player : Player, card_ids : Array) -> bool:
	var action_message = {
		'action_type': 'action_mulligan',
		'player_id': _get_player_remote_id(player),
		'card_ids': card_ids,
	}
	_submit_game_message(action_message)
	return true

func process_mulligan(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	var card_ids = action_message['card_ids']
	local_game.do_mulligan(game_player, card_ids)

func do_boost(player : Player, card_id : int, payment_card_ids = [],
		use_free_force : bool = false, spent_life_for_force : int = 0, additional_boost_ids = [], facedown_override = null, infuse_payment : Variant = null) -> bool:
	var action_message = {
		'action_type': 'action_boost',
		'player_id': _get_player_remote_id(player),
		'card_id': card_id,
		'payment_card_ids': payment_card_ids,
		'use_free_force': use_free_force,
		'spent_life_for_force': spent_life_for_force,
		'additional_boost_ids': additional_boost_ids
	}
	if facedown_override != null:
		action_message['facedown_override'] = facedown_override
	if infuse_payment != null:
		action_message['infuse_payment'] = infuse_payment
	_submit_game_message(action_message)
	return true

func process_boost(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	var card_id = action_message['card_id']
	var payment_card_ids = action_message['payment_card_ids']
	var use_free_force = action_message['use_free_force']
	var spent_life_for_force = action_message['spent_life_for_force']
	var additional_boost_ids = action_message['additional_boost_ids']
	var facedown_override = null
	if action_message.has('facedown_override'):
		facedown_override = action_message['facedown_override']
	local_game.do_boost(game_player, card_id, payment_card_ids, use_free_force, spent_life_for_force, additional_boost_ids, facedown_override, action_message.get('infuse_payment'))

func do_choose_from_boosts(player : Player, card_ids : Array) -> bool:
	var action_message = {
		'action_type': 'action_choose_from_boosts',
		'player_id': _get_player_remote_id(player),
		'card_ids': card_ids,
	}
	_submit_game_message(action_message)
	return true

func process_choose_from_boosts(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	var card_ids = action_message['card_ids']
	local_game.do_choose_from_boosts(game_player, card_ids)

func do_cancel_tournelouse_transform_bonus_choice(player : Player) -> bool:
	var action_message = {
		'action_type': 'action_cancel_tournelouse_transform_bonus_choice',
		'player_id': _get_player_remote_id(player),
	}
	_submit_game_message(action_message)
	return true

func process_cancel_tournelouse_transform_bonus_choice(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	local_game.do_cancel_tournelouse_transform_bonus_choice(game_player)

func do_cancel_tournelouse_ouroboros_hand_choice(player : Player) -> bool:
	var action_message = {
		'action_type': 'action_cancel_tournelouse_ouroboros_hand_choice',
		'player_id': _get_player_remote_id(player),
	}
	_submit_game_message(action_message)
	return true

func process_cancel_tournelouse_ouroboros_hand_choice(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	local_game.do_cancel_tournelouse_ouroboros_hand_choice(game_player)

func do_cancel_tournelouse_ouroboros_transform_choice(player : Player) -> bool:
	var action_message = {
		'action_type': 'action_cancel_tournelouse_ouroboros_transform_choice',
		'player_id': _get_player_remote_id(player),
	}
	_submit_game_message(action_message)
	return true

func process_cancel_tournelouse_ouroboros_transform_choice(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	local_game.do_cancel_tournelouse_ouroboros_transform_choice(game_player)

func do_choose_from_discard(player : Player, card_ids : Array) -> bool:
	var action_message = {
		'action_type': 'action_choose_from_discard',
		'player_id': _get_player_remote_id(player),
		'card_ids': card_ids,
	}
	_submit_game_message(action_message)
	return true

func process_choose_from_discard(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	var card_ids = action_message['card_ids']
	local_game.do_choose_from_discard(game_player, card_ids)

func do_force_for_effect(player : Player, card_ids : Array, treat_ultras_as_single_force : bool, cancel : bool,
		use_free_force : bool = false, spent_life_for_force : int = 0) -> bool:
	var action_message = {
		'action_type': 'action_force_for_effect',
		'player_id': _get_player_remote_id(player),
		'card_ids': card_ids,
		'treat_ultras_as_single_force': treat_ultras_as_single_force,
		'cancel': cancel,
		'use_free_force': use_free_force,
		'spent_life_for_force': spent_life_for_force,
	}
	_submit_game_message(action_message)
	return true

func process_force_for_effect(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	var card_ids = action_message['card_ids']
	var treat_ultras_as_single_force = action_message['treat_ultras_as_single_force']
	var cancel = action_message['cancel']
	var use_free_force = action_message['use_free_force']
	var spent_life_for_force = action_message['spent_life_for_force']
	local_game.do_force_for_effect(game_player, card_ids, treat_ultras_as_single_force, cancel, use_free_force, spent_life_for_force)

func do_gauge_for_effect(player : Player, card_ids : Array) -> bool:
	var action_message = {
		'action_type': 'action_gauge_for_effect',
		'player_id': _get_player_remote_id(player),
		'card_ids': card_ids,
	}
	_submit_game_message(action_message)
	return true

func process_gauge_for_effect(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	var card_ids = action_message['card_ids']
	local_game.do_gauge_for_effect(game_player, card_ids)

func do_choose_to_discard(player : Player, card_ids : Array) -> bool:
	var action_message = {
		'action_type': 'action_choose_to_discard',
		'player_id': _get_player_remote_id(player),
		'card_ids': card_ids,
	}
	_submit_game_message(action_message)
	return true

func process_choose_to_discard(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	var card_ids = action_message['card_ids']
	local_game.do_choose_to_discard(game_player, card_ids)

func do_character_action(player : Player, card_ids : Array, action_idx : int = 0,
		use_free_force : bool = false, spent_life_for_force : int = 0) -> bool:
	var action_message = {
		'action_type': 'action_character_action',
		'player_id': _get_player_remote_id(player),
		'card_ids': card_ids,
		'action_idx': action_idx,
		'use_free_force': use_free_force,
		'spent_life_for_force': spent_life_for_force,
	}
	_submit_game_message(action_message)
	return true

func process_character_action(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	var card_ids = action_message['card_ids']
	var action_idx = action_message['action_idx']
	var use_free_force = action_message['use_free_force']
	var spent_life_for_force = action_message['spent_life_for_force']
	local_game.do_character_action(game_player, card_ids, action_idx, use_free_force, spent_life_for_force)

func do_bonus_turn_action(player : Player, action_index : int) -> bool:
	var action_message = {
		'action_type': 'action_bonus_action',
		'player_id': _get_player_remote_id(player),
		'action_index': action_index,
	}
	_submit_game_message(action_message)
	return true

func process_bonus_action(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	var action_index = action_message['action_index']
	local_game.do_bonus_turn_action(game_player, action_index)

func do_choose_from_topdeck(player : Player, card_id : int, action : String) -> bool:
	var action_message = {
		'action_type': 'action_choose_from_topdeck',
		'player_id': _get_player_remote_id(player),
		'card_id': card_id,
		'action': action,
	}
	_submit_game_message(action_message)
	return true

func process_choose_from_topdeck(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	var card_id = action_message['card_id']
	var action = action_message['action']
	local_game.do_choose_from_topdeck(game_player, card_id, action)

func do_choose_multiple_from_topdeck(player : Player, card_ids : Array, action : String) -> bool:
	var action_message = {
		'action_type': 'action_choose_multiple_from_topdeck',
		'player_id': _get_player_remote_id(player),
		'card_ids': card_ids,
		'action': action,
	}
	_submit_game_message(action_message)
	return true

func process_choose_multiple_from_topdeck(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	var card_ids = action_message['card_ids']
	var action = action_message['action']
	local_game.do_choose_multiple_from_topdeck(game_player, card_ids, action)

func do_emote(player : Player, is_image_emote : bool, emote : String):
	var action_message = {
		'action_type': 'action_emote',
		'player_id': _get_player_remote_id(player),
		'is_image_emote': is_image_emote,
		'emote': emote,
	}
	_submit_game_message(action_message)
	return true

func process_emote(action_message) -> void:
	var game_player = _get_player_from_remote_id(action_message['player_id'])
	var is_image_emote = action_message['is_image_emote']
	var emote = action_message['emote']
	local_game.do_emote(game_player, is_image_emote, emote)

func do_match_result(player_clock_remaining, opponent_clock_remaining):
	# Only the winner should be reporting.
	var winning_player_number = _player_info['player_number']
	var p1 = Enums.PlayerId.PlayerId_Player
	var p2 = Enums.PlayerId.PlayerId_Opponent
	var p1clock = player_clock_remaining
	var p2clock = opponent_clock_remaining
	if winning_player_number == 2:
		p1 = Enums.PlayerId.PlayerId_Opponent
		p2 = Enums.PlayerId.PlayerId_Player
		p1clock = opponent_clock_remaining
		p2clock = player_clock_remaining
	var action_message = {
		'action_type': 'match_result',
		'winning_player': winning_player_number,
		'p1life': _get_player(p1).life,
		'p2life': _get_player(p2).life,
		'p1clock': p1clock,
		'p2clock': p2clock,
	}
	_submit_game_message(action_message)
	return true

func do_quit(player_id : Enums.PlayerId, reason : Enums.GameOverReason):
	var remote_player_id = _player_info['id']
	if player_id == Enums.PlayerId.PlayerId_Opponent:
		remote_player_id = _opponent_info['id']
	var action_message = {
		'action_type': 'action_quit',
		'player_id': remote_player_id,
		'reason': reason,
	}
	_submit_game_message(action_message)
	return true

func process_quit(action_message):
	var player_id = Enums.PlayerId.PlayerId_Player
	if _player_info['id'] != action_message['player_id']:
		player_id = Enums.PlayerId.PlayerId_Opponent
	local_game.do_quit(player_id, action_message['reason'])

# In order to make sure a player only gets a game over for seeing the clock
# on their screen run out, this function assumes that the local player
# is the one whose clock ran out and should only be called when this is true.
func do_clock_ran_out():
	var action_message = {
		'action_type': 'action_clock_ran_out',
		'clock_ran_out_player': _player_info['id']
	}
	_submit_game_message(action_message)

func process_clock_ran_out(action_message):
	if _player_info['id'] == action_message['clock_ran_out_player']:
		local_game.do_clock_ran_out(Enums.PlayerId.PlayerId_Player)
	else:
		local_game.do_clock_ran_out(Enums.PlayerId.PlayerId_Opponent)
