# The wrapper manages signals from a remote player, or the local player,
# so that the game engine and the interface don't have to care which is which.

class_name GameWrapper
extends Node

var current_game

func poll_for_events() -> Array:
	if current_game:
		return current_game.get_latest_events()
	return []

func get_combat_log(log_filters, player_color, opponent_color, card_color, start_index : int = 0) -> String:
	var log_string : String = current_game.get_combat_log(log_filters, start_index) \
		.replace("{_player_color}", player_color) \
		.replace("{_opponent_color}", opponent_color) \
		.replace("{_card_color}", card_color)
	return log_string

func get_combat_log_size() -> int:
	if current_game:
		return current_game.get_combat_log_size()
	return 0

func get_message_history() -> Array:
	if current_game:
		return current_game.get_message_history()
	return []

func get_pending_observer_messages() -> Array:
	if current_game and current_game.has_method("get_pending_observer_messages"):
		return current_game.get_pending_observer_messages()
	return []

func get_next_observer_message() -> Dictionary:
	if current_game and current_game.has_method("get_next_observer_message"):
		return current_game.get_next_observer_message()
	return {}

func is_ai_game() -> bool:
	return current_game is LocalGame

func initialize_local_game(player_deck, opponent_deck, randomize_first_player, image_loader):
	current_game = LocalGame.new(image_loader)
	var seed_value = randi()
	var first_player = Enums.PlayerId.PlayerId_Player
	if randomize_first_player and randi() % 2 == 0:
		first_player = Enums.PlayerId.PlayerId_Opponent
	current_game.initialize_game(player_deck,
		opponent_deck,
		"Player",
		"CPU",
		first_player,
		seed_value)
	current_game.draw_starting_hands_and_begin()

func initialize_remote_game(player_info,
		opponent_info,
		starting_player : Enums.PlayerId,
		seed_value : int,
		observer_mode : bool,
		replay_mode : bool,
		starting_message_queue : Array,
		image_loader : CardImageLoader):
	current_game = RemoteGame.new(image_loader)
	current_game.initialize_game(player_info,
		opponent_info,
		starting_player,
		seed_value,
		observer_mode,
		replay_mode,
		starting_message_queue)

# Deletes the current game
func end_game():
	current_game.teardown()
	current_game.free()
	current_game = null

func do_clock_ran_out():
	current_game.do_clock_ran_out()

func submit_quit(player : Enums.PlayerId, reason : Enums.GameOverReason):
	return current_game.do_quit(player, reason)

# Minato: trigger Outrun the Past before strike card selection.
# In online games this must go through the network so both local engines set up
# the same seal decision before the attack card is selected (Renea pattern).
func submit_minato_outrun_before_strike(player : Enums.PlayerId) -> bool:
	if current_game is LocalGame:
		var game_player = _get_player(player)
		game_player.minato_outrun_triggered_before_strike = true
		current_game.handle_strike_effect(-1, {
			"effect_type": "minato_outrun_the_past",
			"minato_otp_sealed": 0
		}, game_player)
		return true
	return current_game.do_minato_outrun_before_strike(_get_player(player))

func submit_renea_pre_strike_reveal(player : Enums.PlayerId, strike_response : bool = false) -> bool:
	if current_game is LocalGame:
		current_game._renea_begin_pre_strike_reveal(_get_player(player), not strike_response, strike_response)
		return true
	return current_game.do_renea_pre_strike_reveal(_get_player(player), strike_response)

func observer_process_next_message_from_queue():
	return current_game.observer_process_next_message_from_queue()

func _test_add_to_gauge(amount):
	current_game._test_add_to_gauge(amount)

func _get_player(id):
	return current_game._get_player(id)

func _guardian_rules_game() -> LocalGame:
	return current_game.local_game if current_game is RemoteGame else current_game

func strike_needs_guardian_declaration() -> bool:
	var rules = _guardian_rules_game()
	return rules != null and not rules.game_over and rules.active_strike == null \
		and rules.game_state in [Enums.GameState.GameState_PickAction, Enums.GameState.GameState_WaitForStrike] \
		and rules._has_heiqiyihu_guardian_option()

func get_guardian_effect_for_display(effect: Dictionary) -> Dictionary:
	var rules = _guardian_rules_game()
	if rules == null or rules.active_strike == null:
		return effect
	var source_id = effect.get("card_id", -1)
	var record = rules._get_heiqiyihu_virtual_guardian(source_id)
	if record.is_empty() or rules.card_db.get_card(source_id).definition["type"] != "special":
		return effect
	if effect.get("effect_type") not in [
		StrikeEffects.Powerup, StrikeEffects.Guardup, StrikeEffects.Speedup,
		StrikeEffects.Draw, StrikeEffects.MoveToAnySpace, StrikeEffects.Rangeup
	]:
		return effect
	var display_effect = effect.duplicate(true)
	display_effect.erase("override_description")
	return display_effect

func get_player_virtual_guardian_summary(player_id: Enums.PlayerId) -> Array:
	var summaries = []
	var rules = _guardian_rules_game()
	if rules == null or rules.active_strike == null:
		return summaries

	for record in rules.active_strike.heiqiyihu_guardian_records:
		if record["player"] != player_id:
			continue
		var boost = rules._get_heiqiyihu_guardian_boost(record)
		if boost["boost_type"] != "continuous":
			continue
		for original_effect in boost["effects"]:
			if original_effect.get("timing", "") in ["now", "immediate", "discarded", "start_of_next_turn"] \
			or original_effect.get("hide_effect", false) or original_effect.get("hide_in_boost_summary", false):
				continue
			var effect = original_effect.duplicate(true)
			effect["card_id"] = record["source_id"]
			var text = GameStrings.get_effect_text(get_guardian_effect_for_display(effect))
			summaries.append({"override_description": "守护 · %s：%s" % [boost["display_name"], text]})
	return summaries

func get_played_guardian_summary(player_id: Enums.PlayerId, records: Array, paid_huhuan_players: Array) -> Array:
	var summaries = []
	for record in records:
		if record["player"] != player_id:
			continue
		var source = get_card_database().get_card(record["source_id"])
		var boost = record["boost"]
		if boost["boost_type"] != "continuous":
			continue
		var is_special = source.definition["type"] == "special"
		var bonus = 1 + int(player_id in paid_huhuan_players) if is_special else 0
		for original_effect in boost["effects"]:
			if original_effect.get("timing", "") in ["now", "immediate", "discarded", "start_of_next_turn"] \
			or original_effect.get("hide_effect", false) or original_effect.get("hide_in_boost_summary", false):
				continue
			var effect = original_effect.duplicate(true)
			if is_special:
				match effect.get("effect_type"):
					StrikeEffects.Powerup, StrikeEffects.Guardup, StrikeEffects.Speedup, StrikeEffects.Draw:
						effect["amount"] += bonus
						effect.erase("override_description")
					StrikeEffects.MoveToAnySpace:
						effect["move_max"] += bonus
						effect.erase("override_description")
					StrikeEffects.Rangeup:
						effect["amount"] += bonus
						effect["amount2"] += bonus
						effect.erase("override_description")
			summaries.append({"override_description": "守护 · %s：%s" % [
				boost["display_name"], GameStrings.get_effect_text(effect)
			]})
	return summaries

func get_game_state() -> Enums.GameState:
	return current_game.get_game_state()

func has_active_strike() -> bool:
	return current_game and current_game.has_active_strike()

# True if the given card is one of the attack cards currently involved in the
# active strike (initiator / defender / in-progress extra attack).
func is_card_active_strike_card(card_id : int) -> bool:
	return current_game and current_game.is_card_active_strike_card(card_id)

# True when the active strike is a follow-up extra attack (Zsolt awaken chain
# attack, etc.), false for the strike's initial attack card. UI uses this to
# gate closeup effects that should only play on the MAIN attack card.
func is_current_strike_extra_attack() -> bool:
	return current_game \
		and current_game.has_active_strike() \
		and current_game.active_strike.extra_attack_in_progress

func get_active_player() -> Enums.PlayerId:
	return current_game.get_active_player()

func get_priority_player() -> Enums.PlayerId:
	return current_game.get_priority_player()

func get_decision_info() -> DecisionInfo:
	return current_game.get_decision_info()

func get_player_name(id):
	return _get_player(id).name

func get_player_life(id):
	return _get_player(id).life

func get_player_location(id):
	return _get_player(id).arena_location

func get_player_extra_width(id):
	return _get_player(id).extra_width

func get_player_deck_definition(id):
	return _get_player(id).deck_def

func get_player_deck_list(id):
	return _get_player(id).deck_list

func get_player_hand_size(id):
	return _get_player(id).hand.size()

func get_player_deck_size(id):
	return _get_player(id).deck.size()

func get_player_sealed_size(id):
	return _get_player(id).sealed.size()

func get_player_overdrive_size(id):
	return _get_player(id).overdrive.size()

func get_player_discardable_boost_count(id):
	return _get_player(id).get_boosts(true).size()

func get_player_discards_size(id):
	return _get_player(id).discards.size()

func get_player_gauge_size(id):
	return _get_player(id).gauge.size()

func get_player_bleach_size(id):
	return _get_player(id).bleach_zone.size()

func has_player_bleach_zone(id):
	return _get_player(id).has_bleach_zone()

func get_player_bleach_zone_name(id):
	return _get_player(id).get_bleach_zone_name()

func is_player_bleach_zone_facedown(id):
	return _get_player(id).is_bleach_zone_facedown()

func get_player_reshuffle_remaining(id):
	return _get_player(id).reshuffle_remaining

func get_player_public_hand_info(id):
	return _get_player(id).get_public_hand_info()

func get_player_exceed_cost(id):
	return _get_player(id).get_exceed_cost()

func is_player_exceeded(id):
	return _get_player(id).exceeded

func is_player_infused(id):
	return _get_player(id).is_infused()

func get_player_seen_topdeck(id):
	return _get_player(id).get_seen_topdeck()

func get_player_mulligan_complete(id):
	return _get_player(id).mulligan_complete

func get_player_character_action(id, action_idx = 0):
	return _get_player(id).get_character_action(action_idx)

func get_player_character_action_shortcut_effect(id, action_idx = 0):
	var character_action = get_player_character_action(id, action_idx)
	if 'shortcut_effect_type' in character_action:
		var shortcut_effect_type = character_action['shortcut_effect_type']
		var found_effect = character_action['effect']
		var continue_searching = true
		while continue_searching:
			continue_searching = false
			if found_effect['effect_type'] == shortcut_effect_type:
				return found_effect
			elif 'and' in found_effect:
				found_effect = found_effect['and']
				continue_searching = true
	return {}

func get_player_character_action_count(id):
	return _get_player(id).get_character_action_count()

func get_player_extra_strike_option(id, action_idx = 0):
	return _get_player(id).get_extra_strike_option(action_idx)

func get_player_extra_strike_options_count(id):
	return _get_player(id).get_extra_strike_options_count()

func get_replacement_boost_description(id):
	return _get_player(id).get_replacement_boost_definition()["description"]

func get_bonus_actions(id):
	return _get_player(id).get_bonus_actions()
	
func get_once_per_game_mechanic_name(id):
	return _get_player(id).once_per_game_resource_name
	
func get_once_per_game_mechanic_available(id):
	return _get_player(id).once_per_game_resource > 0

func is_player_in_overdrive(id):
	var player = _get_player(id)
	if 'always_show_overdrive' in player.deck_def and player.deck_def['always_show_overdrive']:
		return true
	return _get_player(id).overdrive.size() > 0
	
func non_exceed_overdrive_active(id):
	var player = _get_player(id)
	return player.non_exceed_overdrive_active

func get_all_non_immediate_continuous_boost_effects(id):
	var game_player = _get_player(id)
	return game_player.get_all_non_immediate_continuous_boost_effects()

func is_player_sealed_area_secret(id):
	return _get_player(id).sealed_area_is_secret

func count_cards_in_deck_and_hand(player_id : Enums.PlayerId,
	card_str_id : String,
	override_card_list = null):
	var player = _get_player(player_id)
	var count = 0

	if override_card_list:
		for card in override_card_list:
			if card.definition['id'] == card_str_id:
				count += 1
	else:
		for card in player.deck:
			if card.definition['id'] == card_str_id:
				count += 1
		for card in player.hand:
			if card.definition['id'] == card_str_id:
				count += 1
		if player.sealed_area_is_secret:
			for card in player.sealed:
				if card.definition['id'] == card_str_id:
					count += 1
		for card in player.continuous_boosts:
			if card.definition['id'] == card_str_id and card.definition["boost"].get("facedown"):
				count += 1
		for key in player.underboost_map.keys():
			# Cards hidden under a boost are also counted as "in the deck".
			var cards_under_boost = player.get_cards_under_boost(key)
			for card in cards_under_boost:
				if card.definition['id'] == card_str_id:
					count += 1
		if player.is_stored_zone_facedown():
			# The player has a secret stored zone, these hidden cards should be counted.
			for card in player.set_aside_cards:
				if card.definition['id'] == card_str_id:
					count += 1

		var striking_card_ids = current_game.get_striking_card_ids_for_player(player)
		for striking_id in striking_card_ids:
			if striking_id == card_str_id:
				count += 1
	return count

func has_facedown_boosts(player_id : Enums.PlayerId):
	var player = _get_player(player_id)
	for card in player.continuous_boosts:
		if card.definition["boost"].get("facedown"):
			return true
	return false

func is_card_in_gauge(player_id : Enums.PlayerId, card_id : int):
	var player = _get_player(player_id)
	for card in player.gauge:
		if card.id == card_id:
			return true
	return false

func is_card_in_bleach(player_id : Enums.PlayerId, card_id : int):
	return _get_player(player_id).is_card_in_bleach(card_id)

func is_card_in_hand(player_id : Enums.PlayerId, card_id : int):
	var player = _get_player(player_id)
	for card in player.hand:
		if card.id == card_id:
			return true
	return false

func is_card_in_boosts(player_id : Enums.PlayerId, card_id : int):
	var player = _get_player(player_id)
	for card in player.continuous_boosts:
		if card.id == card_id:
			return true
	return false

func is_card_sustained(player_id : Enums.PlayerId, card_id : int):
	var player = _get_player(player_id)
	return card_id in player.sustained_boosts

func is_card_in_discards(player_id : Enums.PlayerId, card_id : int):
	var player = _get_player(player_id)
	for card in player.discards:
		if card.id == card_id:
			return true
	return false

func is_card_in_sealed(player_id : Enums.PlayerId, card_id : int):
	var player = _get_player(player_id)
	for card in player.sealed:
		if card.id == card_id:
			return true
	return false

func is_card_set_aside(player_id : Enums.PlayerId, card_id : int):
	var player = _get_player(player_id)
	for card in player.set_aside_cards:
		if card.id == card_id:
			return true
	return false

func is_card_in_deck(player_id : Enums.PlayerId, card_id : int):
	var player = _get_player(player_id)
	for card in player.deck:
		if card.id == card_id:
			return true
	return false

func is_card_in_overdrive(player_id : Enums.PlayerId, card_id : int):
	var player = _get_player(player_id)
	for card in player.overdrive:
		if card.id == card_id:
			return true
	return false

func is_card_in_transforms(player_id : Enums.PlayerId, card_id : int):
	return _get_player(player_id).is_card_in_transforms(card_id)

func can_player_seal_transform_for_gauge(player_id : Enums.PlayerId):
	return _get_player(player_id).tournelouse_may_seal_for_gauge

func does_card_belong_to_player(player_id : Enums.PlayerId, card_id : int):
	var player = _get_player(player_id)
	return player.owns_card(card_id)

func get_player_top_cards(player_id : Enums.PlayerId, count : int) -> Array:
	var player = _get_player(player_id)
	var top_cards : Array = []
	for i in range(count):
		if player.deck.size() > i:
			top_cards.append(player.deck[i].id)
	return top_cards

func get_player_deck_card_ids_for_boost(player_id : Enums.PlayerId, limitation : String) -> Array:
	var player = _get_player(player_id)
	var card_ids : Array = []
	for card in player.deck:
		if limitation:
			if card.definition['boost']['boost_type'] == limitation or card.definition['type'] == limitation:
				if limitation == "transform" and player.has_card_name_in_zone(card, "transform"):
					continue
				card_ids.append(card.id)
		else:
			card_ids.append(card.id)
	return card_ids

func get_player_sustained_boosts(player_id : Enums.PlayerId) -> Array:
	return _get_player(player_id).sustained_boosts

func get_player_available_force(player_id : Enums.PlayerId):
	return _get_player(player_id).get_available_force()
	
func get_player_available_gauge(player_id : Enums.PlayerId):
	return _get_player(player_id).get_available_gauge()

func get_player_free_force(player_id : Enums.PlayerId, reason : String = ""):
	if reason == "CHANGE_CARDS" and _get_player(player_id).free_force_cc_only:
		return _get_player(player_id).free_force_cc_only
	return _get_player(player_id).free_force

func does_free_force_require_card_spent(player_id : Enums.PlayerId):
	return _get_player(player_id).free_force_cc_only

func get_player_force_cost_reduction(player_id : Enums.PlayerId):
	return _get_player(player_id).force_cost_reduction

func get_player_free_gauge(player_id : Enums.PlayerId):
	return _get_player(player_id).free_gauge

func get_player_force_for_cards(player_id : Enums.PlayerId,
	card_ids : Array,
	reason : String,
	treat_ultras_as_single_force : bool,
	use_free_force : bool):
	return _get_player(player_id).get_force_with_cards(card_ids, reason, treat_ultras_as_single_force, use_free_force)

func get_force_to_move_to(player_id : Enums.PlayerId, location : int):
	return _get_player(player_id).get_force_to_move_to(location)

func get_invalid_card_names(player_id : Enums.PlayerId) -> Array:
	var player = _get_player(player_id)
	return player.cards_invalid_during_strike

func get_will_not_hit_card_names(player_id : Enums.PlayerId) -> Array:
	var card_names = []
	var player = _get_player(player_id)
	if player.cards_that_will_not_hit.size() > 0:
		var card_db = get_card_database()
		for card in player.cards_that_will_not_hit:
			card_names.append(card_db.get_card_name_by_card_definition_id(card))
	return card_names

func get_plague_knight_discard_names(player_id : Enums.PlayerId) -> Array:
	var card_names = []
	var player = _get_player(player_id)
	if player.plague_knight_discard_names.size() > 0:
		for card in player.plague_knight_discard_names:
			card_names.append(card)
	return card_names

func get_buddy_name(player_id : Enums.PlayerId, buddy_id : String):
	return _get_player(player_id).get_buddy_name(buddy_id)

func get_face_attack_card(player_id : Enums.PlayerId):
	return _get_player(player_id).get_face_attack_card()

func get_life_for_force_amount(player_id : Enums.PlayerId):
	return _get_player(player_id).spend_life_for_force_amount

func get_life_for_gauge_amount(player_id : Enums.PlayerId):
	return _get_player(player_id).spend_life_for_gauge_amount

func get_valid_locations_for_buddy_effect(player_id : Enums.PlayerId, effect : Dictionary):
	var MinArenaLocation = 1
	var MaxArenaLocation = 9
	var locations = []

	var player = _get_player(player_id)
	var effect_type = effect['effect_type']
	var buddy_id = ""
	if 'buddy_id' in effect:
		buddy_id = effect['buddy_id']

	if effect_type == 'place_buddy_in_any_space':
		for i in range(MinArenaLocation, MaxArenaLocation + 1):
			locations.append(i)
	elif effect_type == 'move_buddy':
		var min_spaces = effect['amount']
		var max_spaces = effect['amount2']
		var buddy_location = player.get_buddy_location(buddy_id)
		for i in range(MinArenaLocation, MaxArenaLocation + 1):
			var distance = abs(buddy_location - i)
			if distance >= min_spaces and distance <= max_spaces:
				locations.append(i)
	elif effect_type == 'place_buddy_at_range':
		var range_min = effect['range_min']
		var range_max = effect['range_max']
		for i in range(MinArenaLocation, MaxArenaLocation + 1):
			var range_origin = player.get_closest_occupied_space_to(i)
			var distance = abs(range_origin - i)
			if distance >= range_min and distance <= range_max:
				locations.append(i)
	elif effect_type == 'move_any_boost':
		for i in range(MinArenaLocation, MaxArenaLocation + 1):
			if i in player.buddy_locations:
				locations.append(i)
	return locations

func get_card_index_in_discards(player_id : Enums.PlayerId, card_id : int):
	var player = _get_player(player_id)
	for i in range(len(player.discards)):
		var card = player.discards[i]
		if card.id == card_id:
			return i
	return -1

func get_ex_transform_copy(player_id : Enums.PlayerId, card_id : int) -> int:
	var card_db = current_game.get_card_database()
	var card = card_db.get_card(card_id)
	for hand_card in _get_player(player_id).hand:
		if hand_card.definition['id'] == card.definition['id'] and hand_card.id != card_id:
			return hand_card.id
	return -1

func other_player(id : Enums.PlayerId) -> Enums.PlayerId:
	if id == Enums.PlayerId.PlayerId_Player:
		return Enums.PlayerId.PlayerId_Opponent
	else:
		return Enums.PlayerId.PlayerId_Player

func get_card_database() -> CardDatabase:
	return current_game.get_card_database()

func get_player_extra_attack_card_options(player_id : Enums.PlayerId) -> Array:
	var cards = _get_player(player_id).get_cards_in_hand_of_type("can_pay_cost")
	var card_ids = []
	for card in cards:
		card_ids.append(card.id)
	return card_ids

func get_player_cards_in_hand_matching_types(player_id : Enums.PlayerId, types : Array) -> Array:
	return _get_player(player_id).get_cards_in_hand_matching_types(types)

func does_card_contain_range_to_opponent(player_id : Enums.PlayerId, card_id : int, only_character_effects : bool = false) -> bool:
	return _get_player(player_id).does_card_contain_range_to_opponent(card_id, only_character_effects)

func can_player_boost_from_gauge(player_id : Enums.PlayerId):
	return _get_player(player_id).can_boost_from_gauge
	
func can_player_boost_from_extra(player_id : Enums.PlayerId):
	return _get_player(player_id).can_boost_from_extra

func can_player_boost(player_id : Enums.PlayerId,
		card_id : int,
		valid_zones : Array,
		limitation : String,
		ignore_costs : bool) -> bool:
	var zone_func_map = {
		"hand": is_card_in_hand,
		"gauge": is_card_in_gauge,
		"discard": is_card_in_discards,
		"extra": is_card_set_aside,
		"bleach": is_card_in_bleach,
		"deck": is_card_in_deck
	}

	var in_valid_zone = false
	for zone in valid_zones:
		var zone_func = zone_func_map.get(zone)
		if zone_func and zone_func.call(player_id, card_id):
			in_valid_zone = true
	if not in_valid_zone:
		return false

	var card_db = current_game.get_card_database()
	var card = card_db.get_card(card_id)

	# Umina Spiraling Descent: opponent cannot boost copies of the Dreamlands card.
	# Mirrors local_game.do_boost / _is_spiraling_match so banned cards are not
	# selectable in the UI (prevents the submit-then-rollback behavior).
	var sd_opponent = _get_player(current_game.get_other_player(player_id))
	if sd_opponent != null and sd_opponent.deck_def.get("id") == "umina" and sd_opponent.has_transform("umina_dark_thoughts"):
		var sd_banned = sd_opponent.get_umina_spiraling_target()
		if sd_banned != "" and current_game._is_spiraling_match(sd_banned, card):
			return false

	if limitation:
		if card.definition['id'] != limitation and card.definition['boost']['boost_type'] != limitation and card.definition['type'] != limitation:
			var is_tournelouse_normal_transform = _get_player(player_id).deck_def.get("id") == "tournelouse" and card.definition['type'] == "normal" and limitation == "transform" and not is_player_exceeded(player_id)
			if not is_tournelouse_normal_transform:
				return false
	if card.definition['type'] == "decree_glorious" and not is_player_exceeded(player_id):
		return false
	if card.definition["boost"].get("reaction_only", false):
		return false
	if card.definition['boost']['boost_type'] in ["transform", "overload", "none"] and limitation != "transform":
		return false

	if limitation == "transform" and _get_player(player_id).has_card_name_in_zone(card, "transform"):
		return false

	if ignore_costs:
		return true
	var gauge_cost = card_db.get_card_boost_gauge_cost(card_id)
	var force_cost = card_db.get_card_boost_force_cost(card_id)
	if gauge_cost > 0:
		var boosting_card_gauge_value = 0
		if is_card_in_gauge(player_id, card_id):
			boosting_card_gauge_value = 1
		var gauge_available = get_player_available_gauge(player_id) - boosting_card_gauge_value
		return gauge_cost <= gauge_available
	else:
		var boosting_card_force_value = 0
		if is_card_in_hand(player_id, card_id) or is_card_in_gauge(player_id, card_id):
			boosting_card_force_value = card_db.get_card_force_value(card_id)
		var force_available = get_player_available_force(player_id) - boosting_card_force_value
		return force_cost <= force_available

func can_player_ex_transform(player_id : Enums.PlayerId, card_id : int) -> bool:
	if not is_card_in_hand(player_id, card_id):
		return false

	var card_db = current_game.get_card_database()
	var card = card_db.get_card(card_id)
	var is_tournelouse_normal_transform = _get_player(player_id).deck_def.get("id") == "tournelouse" and card.definition['type'] == "normal" and not is_player_exceeded(player_id)
	if is_tournelouse_normal_transform:
		return not _get_player(player_id).has_card_name_in_zone(card, "transform")
	if card.definition['boost']['boost_type'] != "transform" and not is_tournelouse_normal_transform:
		return false

	# Umina Spiraling Descent: opponent cannot transform copies of the Dreamlands card.
	var sd_opponent = _get_player(current_game.get_other_player(player_id))
	if sd_opponent != null and sd_opponent.deck_def.get("id") == "umina" and sd_opponent.has_transform("umina_dark_thoughts"):
		var sd_banned = sd_opponent.get_umina_spiraling_target()
		if sd_banned != "" and current_game._is_spiraling_match(sd_banned, card):
			return false

	return get_ex_transform_copy(player_id, card_id) != -1

func can_do_prepare(player : Enums.PlayerId) -> bool:
	var game_player = _get_player(player)
	return current_game.can_do_prepare(game_player)

func can_do_move(player : Enums.PlayerId) -> bool:
	var game_player = _get_player(player)
	return current_game.can_do_move(game_player)

func can_do_change(player : Enums.PlayerId) -> bool:
	var game_player = _get_player(player)
	return current_game.can_do_change(game_player)

func can_do_exceed(player : Enums.PlayerId) -> bool:
	var game_player = _get_player(player)
	return current_game.can_do_exceed(game_player)

func can_do_reshuffle(player : Enums.PlayerId) -> bool:
	var game_player = _get_player(player)
	return current_game.can_do_reshuffle(game_player)

func can_do_boost(player : Enums.PlayerId) -> bool:
	var game_player = _get_player(player)
	return current_game.can_do_boost(game_player)

func can_do_ex_transform(player : Enums.PlayerId) -> bool:
	var game_player = _get_player(player)
	return current_game.can_do_ex_transform(game_player)

func can_do_strike(player : Enums.PlayerId) -> bool:
	var game_player = _get_player(player)
	return current_game.can_do_strike(game_player)

func can_move_to(player_id : Enums.PlayerId, location : int) -> bool:
	var game_player = _get_player(player_id)
	var ignore_force_req = false
	return game_player.can_move_to(location, ignore_force_req)

func can_do_character_action(player_id : Enums.PlayerId, action_idx : int = 0) -> bool:
	var game_player = _get_player(player_id)
	return game_player.can_do_character_action(action_idx)

### Action Functions ###

func submit_prepare(player : Enums.PlayerId) -> bool:
	var game_player = _get_player(player)
	return current_game.do_prepare(game_player)

func submit_reshuffle(player : Enums.PlayerId) -> bool:
	var game_player = _get_player(player)
	return current_game.do_reshuffle(game_player)

func submit_choice(player : Enums.PlayerId, choice_index : int) -> bool:
	var game_player = _get_player(player)
	return current_game.do_choice(game_player, choice_index)

func get_player_boost_cancel_cost(player_id : Enums.PlayerId, card_id : int) -> int:
	var game_player = _get_player(player_id)
	var card = current_game.get_card_database().get_card(card_id)
	if game_player.strike_on_boost_cleanup or game_player.wild_strike_on_boost_cleanup:
		return -1
	return game_player.get_boost_cancel_cost(card)

func can_player_cancel_boost(player_id : Enums.PlayerId, card_id : int) -> bool:
	return _get_player(player_id).can_cancel(current_game.get_card_database().get_card(card_id))

func submit_boost_cancel(player : Enums.PlayerId, gauge_card_ids : Array, doing_cancel : bool) -> bool:
	var game_player = _get_player(player)
	return current_game.do_boost_cancel(game_player, gauge_card_ids, doing_cancel)

func submit_boost_name_card_choice_effect(player : Enums.PlayerId, card_id : int) -> bool:
	var game_player = _get_player(player)
	return current_game.do_boost_name_card_choice_effect(game_player, card_id)

func submit_discard_to_max(player : Enums.PlayerId, card_ids : Array) -> bool:
	var game_player = _get_player(player)
	return current_game.do_discard_to_max(game_player, card_ids)

func submit_relocate_card_from_hand(player : Enums.PlayerId, card_ids : Array) -> bool:
	var game_player = _get_player(player)
	return current_game.do_relocate_card_from_hand(game_player, card_ids)

func set_pending_minato_seal_payment(force_amount : int, gauge_amount : int) -> void:
	if current_game is RemoteGame:
		current_game.set_pending_minato_seal_payment(force_amount, gauge_amount)

func clear_pending_minato_seal_payment() -> void:
	if current_game is RemoteGame:
		current_game.clear_pending_minato_seal_payment()

func submit_pay_strike_cost(
	player : Enums.PlayerId,
	card_ids : Array,
	wild_strike : bool,
	discard_ex_first : bool,
	use_free_force : bool,
	spent_life_for_force : int,
	pay_alternative_life_cost : bool,
	spent_life_for_gauge : int = 0
	) -> bool:
	var game_player = _get_player(player)
	return current_game.do_pay_strike_cost(
		game_player,
		card_ids,
		wild_strike,
		discard_ex_first,
		use_free_force,
		spent_life_for_force,
		pay_alternative_life_cost,
		spent_life_for_gauge
	)

func submit_exceed(player : Enums.PlayerId, card_ids : Array, spent_life_for_gauge : int = 0) -> bool:
	var game_player = _get_player(player)
	return current_game.do_exceed(game_player, card_ids, spent_life_for_gauge)

func submit_move(player : Enums.PlayerId, card_ids : Array, new_arena_location : int,
		use_free_force : bool, spent_life_for_force : int) -> bool:
	var game_player = _get_player(player)
	return current_game.do_move(game_player, card_ids, new_arena_location, use_free_force, spent_life_for_force)

func submit_change(player : Enums.PlayerId, card_ids : Array, treat_ultras_as_single_force : bool,
		use_free_force : bool, spent_life_for_force : int) -> bool:
	var game_player = _get_player(player)
	return current_game.do_change(game_player, card_ids, treat_ultras_as_single_force, use_free_force, spent_life_for_force)

func submit_strike(
	player : Enums.PlayerId,
	card_id : int,
	wild_strike: bool,
	ex_card_id : int,
	opponent_sets_first : bool = false,
	use_face_attack : bool = false
) -> bool:
	var game_player = _get_player(player)
	return current_game.do_strike(game_player, card_id, wild_strike, ex_card_id, opponent_sets_first, use_face_attack)

func submit_force_for_armor(player : Enums.PlayerId, card_ids : Array, use_free_force : bool, spent_life_for_force : int) -> bool:
	var game_player = _get_player(player)
	return current_game.do_force_for_armor(game_player, card_ids, use_free_force, spent_life_for_force)

func submit_mulligan(player : Enums.PlayerId, card_ids : Array) -> bool:
	var game_player = _get_player(player)
	return current_game.do_mulligan(game_player, card_ids)

func submit_boost(player : Enums.PlayerId, card_id : int, payment_card_ids,
		use_free_force : bool, spent_life_for_force : int, additional_boost_ids : Array = [], facedown_override = null) -> bool:
	var game_player = _get_player(player)
	return current_game.do_boost(game_player, card_id, payment_card_ids, use_free_force, spent_life_for_force, additional_boost_ids, facedown_override)

func submit_choose_from_boosts(player: Enums.PlayerId, card_ids : Array) -> bool:
	var game_player = _get_player(player)
	return current_game.do_choose_from_boosts(game_player, card_ids)

func submit_cancel_tournelouse_transform_bonus_choice(player: Enums.PlayerId) -> bool:
	var game_player = _get_player(player)
	return current_game.do_cancel_tournelouse_transform_bonus_choice(game_player)

func submit_cancel_tournelouse_ouroboros_hand_choice(player: Enums.PlayerId) -> bool:
	var game_player = _get_player(player)
	return current_game.do_cancel_tournelouse_ouroboros_hand_choice(game_player)

func submit_cancel_tournelouse_ouroboros_transform_choice(player: Enums.PlayerId) -> bool:
	var game_player = _get_player(player)
	return current_game.do_cancel_tournelouse_ouroboros_transform_choice(game_player)

func submit_choose_from_discard(player: Enums.PlayerId, card_ids : Array) -> bool:
	var game_player = _get_player(player)
	return current_game.do_choose_from_discard(game_player, card_ids)

func submit_force_for_effect(player: Enums.PlayerId, card_ids : Array, treat_ultras_as_single_force : bool, cancel : bool = false,
		use_free_force : bool = false, spent_life_for_force : int = 0) -> bool:
	var game_player = _get_player(player)
	return current_game.do_force_for_effect(game_player, card_ids, treat_ultras_as_single_force, cancel,
		use_free_force, spent_life_for_force)

func submit_gauge_for_effect(player: Enums.PlayerId, card_ids : Array) -> bool:
	var game_player = _get_player(player)
	return current_game.do_gauge_for_effect(game_player, card_ids)

func submit_choose_to_discard(player: Enums.PlayerId, card_ids : Array) -> bool:
	var game_player = _get_player(player)
	return current_game.do_choose_to_discard(game_player, card_ids)

func submit_character_action(player: Enums.PlayerId,
	card_ids : Array,
	action_idx : int = 0,
	use_free_force = false,
	spent_life_for_force : int = 0) -> bool:
	var game_player = _get_player(player)
	return current_game.do_character_action(game_player, card_ids, action_idx, use_free_force, spent_life_for_force)

func submit_bonus_turn_action(player: Enums.PlayerId, action_index : int) -> bool:
	var game_player = _get_player(player)
	return current_game.do_bonus_turn_action(game_player, action_index)

func submit_choose_from_topdeck(player: Enums.PlayerId, card_id : int, action : String) -> bool:
	var game_player = _get_player(player)
	return current_game.do_choose_from_topdeck(game_player, card_id, action)

func submit_choose_multiple_from_topdeck(player: Enums.PlayerId, card_ids : Array, action : String) -> bool:
	var game_player = _get_player(player)
	return current_game.do_choose_multiple_from_topdeck(game_player, card_ids, action)

func submit_emote(player: Enums.PlayerId, is_image_emote : bool, emote : String):
	var game_player = _get_player(player)
	return current_game.do_emote(game_player, is_image_emote, emote)

func submit_match_result(player_clock_remaining, opponent_clock_remaining):
	return current_game.do_match_result(player_clock_remaining, opponent_clock_remaining)
