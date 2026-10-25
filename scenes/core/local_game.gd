# This is the main game engine.
#
# Actions from either player are sent to this script via game_wrapper.gd.
# The wrapper protects the engine from having to care whether player inputs
# are from the local player, from a remote player, or were generated
# by the AI and then sent to game_wrapper.gd.

class_name LocalGame
extends Node2D

const NullNamedCard = "_"

# Conditions that shouldn't change during a strike
const StrikeStaticConditions = [
	"is_critical", "is_not_critical",
	"is_infused", "is_not_infused",
	"was_hit",
	"initiated_strike", "not_initiated_strike",
	"exceeded", "not_exceeded",
	"opponent_exceeded", "opponent_not_exceeded",
	"buddy_in_play",
	"boost_caused_start_of_turn_strike",
	"used_character_bonus",
	"used_character_action",
	"hit_opponent",
	"opponent_stunned",
	"initiated_face_up",
	"stunned", "not_stunned",
	"initiated_after_moving",
	"was_wild_swing",
	"last_turn_was_strike",
	"speed_greater_than",
	"is_special_or_ultra_attack", "is_normal_attack", "is_special_attack", "is_special_or_dongshilang_longxianjia_attack", "is_buddy_special_or_ultra_attack",
	"has_continuous_boost_attack", "min_continuous_boosts_attack", "pooky_gambling_normals",
	"discarded_matches_attack_speed",
	"canceled_this_turn",
]

var event_queue = []

func get_latest_events() -> Array:
	var events = event_queue
	if events.size() > 0:
		printlog("EVENT_QUEUE_POP size=%d active_turn=%s state=%s" % [events.size(), str(active_turn_player), Enums.GameState.keys()[game_state]])
	event_queue = []
	return events

var card_db : CardDatabase
var all_cards : Array = []
var game_over : bool = false
var game_over_winning_player : Player = null
var active_strike : Strike = null
var active_character_action : bool = false
var active_bonus_turn_action : bool = false
var active_exceed : bool = false
var active_overdrive : bool = false
var active_prepare : bool = false
var active_overdrive_boost_top_discard_on_cleanup : bool = false
var active_change_cards : bool = false
var active_special_draw_effect : bool = false
var active_post_action_effect : bool = false
var active_start_of_turn_effects : bool = false
var active_end_of_turn_effects : bool = false
var discard_to_max_after_end_turn_draw : bool = false
var end_of_turn_draw_resolved : bool = false
var end_of_turn_skip_eot_discard : bool = false
var _last_effect_source_player_id : int = -1
var _exceeded_wonderland_active = false
var remaining_overdrive_effects = []
var queued_effect_chain = {
	"effect": null,
	"chain": null,
}
var remaining_start_of_turn_effects = []
var remaining_end_of_turn_effects = []
var prepare_effects_resolved : int = 0
var post_action_effects_resolved : int = 0
var post_action_interruption : bool = false
var resolving_boost_before_queue : bool = false
var dongshilang_cross_count_this_strike : Dictionary = {}
var dongshilang_move_limit_remaining_this_strike : Dictionary = {}
var dongshilang_convert_advance_to_retreat_this_strike : Dictionary = {}
var dongshilang_pending_ice_action_boost_count : Dictionary = {}
var dongshilang_pending_ice_action_context : Dictionary = {}

var decision_info : DecisionInfo = DecisionInfo.new()
var active_boost : Boost = null
var preparing_boost_info : Dictionary = {}
var heiqiyihu_pending_thresholds : Array = []
var heiqiyihu_threshold_context : Dictionary = {}
var heiqiyihu_guardian_setup : Dictionary = {}
var heiqiyihu_pending_strike_request : Dictionary = {}

var game_state : Enums.GameState = Enums.GameState.GameState_NotStarted

var full_combat_log : Array = []

var image_loader : CardImageLoader
func _init(card_image_loader):
	image_loader = card_image_loader

func get_combat_log(log_type_filters, start_index : int = 0):
	var safe_start = clampi(start_index, 0, full_combat_log.size())
	var log_strings = []
	for index in range(safe_start, full_combat_log.size()):
		var item = full_combat_log[index]
		if item['log_type'] in log_type_filters:
			log_strings.append(_full_log_item_to_string(item))
	return "\n".join(log_strings)

func get_combat_log_size() -> int:
	return full_combat_log.size()

func get_message_history() -> Array:
	return []

func _full_log_item_to_string(log_item):
	var log_type = log_item['log_type']
	var log_player = log_item['log_player']
	var message = log_item['message']
	var prefix = ""

	var prefix_symbol = ""
	if log_type == Enums.LogType.LogType_Default:
		prefix_symbol += "**"
	if log_type == Enums.LogType.LogType_Action:
		prefix_symbol += "*"

	if log_player != null:
		if log_player == player:
			prefix += "[color={_player_color}]"
		if log_player == opponent:
			prefix += "[color={_opponent_color}]"
		prefix += "%s%s[/color] " % [prefix_symbol, log_player.name]
	else:
		prefix = prefix_symbol
	return prefix + message

func _log_card_name(card_name):
	return "[color={_card_color}]%s[/color]" % card_name

func _append_log_full(log_type : Enums.LogType, log_player : Player, message : String):
	full_combat_log.append({
		'log_type': log_type,
		'log_player': log_player,
		'message': message
	})

func _card_list_to_string(cards):
	if len(cards) > 0:
		var card_names = card_db.get_card_name(cards[0].id)
		for i in range(1, cards.size()):
			card_names += ", " + card_db.get_card_name(cards[i].id)
		return card_names
	return ""

func _get_boost_and_card_name(card):
	var card_name = card.definition['display_name']
	var facedown = card.definition['boost'].get("facedown")
	var boost_name = card.definition['boost']['display_name']
	if facedown:
		return _log_card_name("a facedown card")
	else:
		return _log_card_name("%s (%s)" % [boost_name, card_name])

func teardown():
	card_db.teardown()
	card_db.free()
	if image_loader and image_loader.test_mode:
		image_loader.free()
	decision_info.free()

func change_game_state(new_state : Enums.GameState):
	if game_state != Enums.GameState.GameState_GameOver:
		printlog("game_state update from %s to %s" % [Enums.GameState.keys()[game_state], Enums.GameState.keys()[new_state]])
		game_state = new_state
	else:
		_append_log_full(Enums.LogType.LogType_Default, game_over_winning_player, " 获胜！游戏结束")

func get_game_state() -> Enums.GameState:
	return game_state

func has_active_strike() -> bool:
	return active_strike != null

# True if the given card is one of the attack cards currently involved in the
# active strike (initiator / defender / in-progress extra attack). Used by the
# UI to distinguish "this card is actually attacking" from "this card was just
# played as a boost" (boosted cards briefly sit in the UI Striking area).
func is_card_active_strike_card(card_id : int) -> bool:
	if active_strike == null:
		return false
	if active_strike.initiator_card != null and active_strike.initiator_card.id == card_id:
		return true
	if active_strike.defender_card != null and active_strike.defender_card.id == card_id:
		return true
	if active_strike.extra_attack_in_progress \
			and active_strike.extra_attack_data.extra_attack_card != null \
			and active_strike.extra_attack_data.extra_attack_card.id == card_id:
		return true
	return false

func get_decision_info() -> DecisionInfo:
	return decision_info

func printlog(text):
	if GlobalSettings.is_logging_enabled():
		print(text)

func is_number(test_value):
	return test_value is int or test_value is float

func create_event(
	event_type : Enums.EventType,
	event_player : Enums.PlayerId,
	num : int,
	reason: String = "",
	extra_info = null,
	extra_info2 = null,
	extra_info3 = null
):
	# Defer only a new strike request, never an in-strike response. This lets
	# effect-driven declarations reach the same pre-selection phase as actions.
	if not active_strike and event_type in [
		Enums.EventType.EventType_ForceStartStrike,
		Enums.EventType.EventType_Strike_FromGauge,
		Enums.EventType.EventType_Strike_OpponentSetsFirst,
		Enums.EventType.EventType_Strike_EffectDoStrike
	] and _has_heiqiyihu_guardian_option():
		heiqiyihu_pending_strike_request = {
			"player": event_player,
			"opponent_first": event_type == Enums.EventType.EventType_Strike_OpponentSetsFirst,
			"required_wild": event_type == Enums.EventType.EventType_Strike_EffectDoStrike \
				and typeof(extra_info) == TYPE_DICTIONARY and extra_info.get("wild_swing", false)
		}
		return
	var card_name = card_db.get_card_name(num)
	var playerstr = "Player"
	if event_player == Enums.PlayerId.PlayerId_Opponent:
		playerstr = "Opponent"
	printlog("Event %s %s %d (card=%s)" % [Enums.EventType.keys()[event_type], playerstr, num, card_name])
	var new_event = {
		"event_name": Enums.EventType.keys()[event_type],
		"event_type": event_type,
		"event_player": event_player,
		"number": num,
		"reason": reason,
		"extra_info": extra_info,
		"extra_info2": extra_info2,
		"extra_info3": extra_info3,
	}
	event_queue.append(new_event)

func trigger_game_over(event_player : Enums.PlayerId, reason : Enums.GameOverReason):
	create_event(Enums.EventType.EventType_GameOver, event_player, reason)
	game_over = true
	game_over_winning_player = _get_player(get_other_player(event_player))
	change_game_state(Enums.GameState.GameState_GameOver)

func create_silent_pre_strike_event(performing_player : Player):
	create_event(Enums.EventType.EventType_ForceStartStrike, performing_player.my_id, 0, "", null, null, "silent_pre_strike")

enum StrikeState {
	StrikeState_None,
	StrikeState_Initiator_SetEffects,
	StrikeState_Defender_SetFirst,
	StrikeState_Defender_SetEffects,
	StrikeState_Initiator_RevealEffects,
	StrikeState_Defender_RevealEffects,
	StrikeState_Initiator_PayCosts,
	StrikeState_Defender_PayCosts,
	StrikeState_DuringStrikeBonuses,
	StrikeState_Card1_Activation,
	StrikeState_Card1_Before,
	StrikeState_Card1_DetermineHit,
	StrikeState_Card1_Hit,
	StrikeState_Card1_Hit_Response,
	StrikeState_Card1_ApplyDamage,
	StrikeState_Card1_After,
	StrikeState_Card2_Activation,
	StrikeState_Card2_Before,
	StrikeState_Card2_DetermineHit,
	StrikeState_Card2_Hit,
	StrikeState_Card2_Hit_Response,
	StrikeState_Card2_ApplyDamage,
	StrikeState_Card2_After,
	StrikeState_Cleanup,
	StrikeState_Cleanup_Player1Effects,
	StrikeState_Cleanup_Player1EffectsComplete,
	StrikeState_Cleanup_Player2Effects,
	StrikeState_EndOfStrike,
	StrikeState_EndOfStrike_Player1Effects,
	StrikeState_EndOfStrike_Player1EffectsComplete,
	StrikeState_EndOfStrike_Player2Effects,
	StrikeState_Cleanup_Complete
}

func get_current_strike_timing():
	if active_strike:
		if active_strike.extra_attack_in_progress:
			# Implement this later if we really need it or it makes sense.
			# Potentially needs to return the current timing of the main strike.
			assert(false)
			return "extra attack not implemented"
		else:
			match active_strike.strike_state:
				StrikeState.StrikeState_Initiator_SetEffects, StrikeState.StrikeState_Defender_SetFirst, StrikeState.StrikeState_Defender_SetEffects:
					return "set_strike"
				StrikeState.StrikeState_DuringStrikeBonuses:
					return "during_strike"
				StrikeState.StrikeState_Card1_Before, StrikeState.StrikeState_Card2_Before:
					return "before"
				StrikeState.StrikeState_Card1_Hit, StrikeState.StrikeState_Card2_Hit:
					return "hit"
				StrikeState.StrikeState_Card1_After, StrikeState.StrikeState_Card2_After:
					return "after"
				StrikeState.StrikeState_Cleanup, StrikeState.StrikeState_Cleanup_Player1Effects, StrikeState.StrikeState_Cleanup_Player2Effects:
					return "cleanup"
				_:
					return "other"
	return "no active strike"

func get_current_strike_timing_player_id():
	if active_strike:
		if active_strike.extra_attack_in_progress:
			# Implement this later if we really need it or it makes sense.
			assert(false)
			return active_strike.extra_attack_data.extra_attack_player.my_id
		else:
			match active_strike.strike_state:
				StrikeState.StrikeState_Initiator_SetEffects:
					return active_strike.initiator.my_id
				StrikeState.StrikeState_Defender_SetFirst, StrikeState.StrikeState_Defender_SetEffects:
					return active_strike.defender.my_id
				StrikeState.StrikeState_DuringStrikeBonuses:
					assert(false, "Unexpected call to get_current_strike_timing_player_id, investigate further.")
					return active_strike.initiator.my_id
				StrikeState.StrikeState_Card1_Before, StrikeState.StrikeState_Card1_Hit, StrikeState.StrikeState_Card1_After:
					return active_strike.get_player(1).my_id
				StrikeState.StrikeState_Card2_Before, StrikeState.StrikeState_Card2_Hit, StrikeState.StrikeState_Card2_After:
					return active_strike.get_player(2).my_id
				StrikeState.StrikeState_Cleanup_Player1Effects:
					return active_strike.initiator.my_id
				StrikeState.StrikeState_Cleanup_Player2Effects:
					return active_strike.defender.my_id
				_:
					assert(false, "Unexpected call to get_current_strike_timing_player_id, investigate further.")
					return active_strike.get_player(1).my_id
	# If no active strike, assume it is current active player.
	return active_turn_player

enum ExtraAttackState {
	ExtraAttackState_None,
	ExtraAttackState_PayCosts,
	ExtraAttackState_DuringStrikeBonuses,
	ExtraAttackState_Activation,
	ExtraAttackState_Before,
	ExtraAttackState_DetermineHit,
	ExtraAttackState_Hit,
	ExtraAttackState_Hit_Response,
	ExtraAttackState_Hit_ApplyDamage,
	ExtraAttackState_After,
	ExtraAttackState_Cleanup,
	ExtraAttackState_CleanupEffects,
	ExtraAttackState_Complete,
}

class ExtraAttackData:
	var extra_attack_in_progress = false
	var extra_attack_card : GameCard = null
	var extra_attack_player : Player = null
	var extra_attack_previous_attack_power_bonus = 0
	var extra_attack_previous_attack_speed_bonus = 0
	var extra_attack_previous_attack_range_effects = []
	var extra_attack_state = ExtraAttackState.ExtraAttackState_None
	var extra_attack_hit = false
	var extra_attack_hit_response_state = {}
	var extra_attack_remaining_effects = []
	var extra_attack_parent = null
	var extra_attack_always_miss = false
	var extra_attack_always_go_to_gauge = false
	var zsolt_max_damage_1 = false
	var zsolt_extra_transform = false

	func reset():
		extra_attack_in_progress = false
		extra_attack_card = null
		extra_attack_player = null
		extra_attack_previous_attack_power_bonus = 0
		extra_attack_previous_attack_speed_bonus = 0
		extra_attack_previous_attack_range_effects = []
		extra_attack_state = ExtraAttackState.ExtraAttackState_None
		extra_attack_hit = false
		extra_attack_remaining_effects = []
		extra_attack_parent = null
		extra_attack_always_miss = false
		extra_attack_always_go_to_gauge = false
		zsolt_max_damage_1 = false
		zsolt_extra_transform = false

class Strike:
	var initiator : Player
	var defender : Player
	var initiator_card : GameCard = null
	var initiator_ex_card : GameCard = null
	var defender_card : GameCard = null
	var defender_ex_card : GameCard = null
	var initiator_first : bool
	var initiator_wild_strike : bool = false
	var initiator_set_from_gauge : bool = false
	var initiator_set_from_boosts : bool = false
	var initiator_set_from_boost_space : int = -1
	var initiator_set_from_face_attack : bool = false
	var initiator_set_from_extra_strike_option : bool = false
	var initiator_set_face_up : bool = false
	var defender_set_face_up : bool = false
	var defender_wild_strike : bool = false
	var defender_set_from_boosts : bool = false
	var defender_set_from_boost_space : int = -1
	var defender_set_from_face_attack : bool = false
	var strike_state
	var hit_response_state : Dictionary = {}
	var starting_distance : int = -1
	var in_setup : bool = true
	var waiting_for_reading_response : bool = false
	var opponent_sets_first : bool = false
	var heiqiyihu_declared_before_set : bool = false
	var heiqiyihu_guardian_records : Array = []
	var heiqiyihu_xuhua_spent_ids : Dictionary = {}
	var heiqiyihu_required_wild : bool = false
	var heiqiyihu_required_face_attack : bool = false
	var remaining_effect_list : Array = []
	var effects_resolved_in_timing : int = 0
	var player1_hit : bool = false
	var player1_stunned : bool = false
	var player2_hit : bool = false
	var player2_stunned : bool = false
	var initiator_damage_taken = 0
	var defender_damage_taken = 0
	var remaining_forced_boosts = 0
	var remaining_forced_boosts_source = ""
	var remaining_forced_boosts_player_id = Enums.PlayerId.PlayerId_Player
	var remaining_forced_boosts_sustaining = false
	# Heidi 匕首风暴: preserved across multi-segment forced topdeck boosts, since
	# boost_play_cleanup clears decision_info between segments.
	var remaining_forced_boosts_ignore_costs = false
	# Explicit queue of card ids for the "topdeck_choice" forced-boost source
	# (Heidi 匕首风暴·三倍插入: the cards the player picked out of the looked-at
	# top cards). Played one at a time by do_chosen_topdeck_boost().
	var remaining_forced_boosts_card_ids : Array = []
	var cards_in_play: Array[GameCard] = []
	var deferred_extra_attack_cards: Array[Dictionary] = []
	var when_hit_effects_processed = []
	var queued_stop_on_space_boosts = []
	var cards_discarded_this_strike = 0
	var unknown_khadath_used = false

	var extra_attack_in_progress = false
	var extra_attack_data : ExtraAttackData = ExtraAttackData.new()

	func get_card(num : int):
		if initiator_first:
			if num == 1: return initiator_card
			return defender_card
		else:
			if num == 1: return defender_card
			return initiator_card

	func get_player(num : int):
		if initiator_first:
			if num == 1: return initiator
			return defender
		else:
			if num == 1: return defender
			return initiator

	func get_player_card(performing_player : Player) -> GameCard:
		if extra_attack_in_progress and performing_player == extra_attack_data.extra_attack_player:
			return extra_attack_data.extra_attack_card

		if performing_player == initiator:
			return initiator_card
		return defender_card

	func get_player_ex_card(performing_player : Player) -> GameCard:
		if extra_attack_in_progress and performing_player == extra_attack_data.extra_attack_player:
			return null

		if performing_player == initiator:
			return initiator_ex_card
		return defender_ex_card

	func get_player_wild_strike(performing_player : Player) -> bool:
		if extra_attack_in_progress and performing_player == extra_attack_data.extra_attack_player:
			return false

		if performing_player == initiator:
			return initiator_wild_strike
		return defender_wild_strike

	func get_player_strike_from_gauge(performing_player : Player) -> bool:
		if extra_attack_in_progress and performing_player == extra_attack_data.extra_attack_player:
			return false

		if performing_player == defender:
			return false
		# ensure that the strike from gauge wasn't invalidated
		return initiator_set_from_gauge and not initiator_wild_strike

	func get_player_set_from_boosts(performing_player : Player) -> bool:
		if extra_attack_in_progress and performing_player == extra_attack_data.extra_attack_player:
			return false

		# ensure that the strike from boosts wasn't invalidated
		if performing_player == initiator:
			return initiator_set_from_boosts and not initiator_wild_strike
		return defender_set_from_boosts and not defender_wild_strike

	func is_player_stunned(question_player : Player) -> bool:
		if get_player(1) == question_player:
			return player1_stunned
		return player2_stunned

	func set_player_stunned(stunned_player : Player):
		if get_player(1) == stunned_player:
			player1_stunned = true
		else:
			player2_stunned = true

	func did_player_hit_opponent(check_player : Player):
		if get_player(1) == check_player:
			return player1_hit
		return player2_hit

	func add_damage_taken(performing_player : Player, damage : int) -> void:
		if performing_player == initiator:
			initiator_damage_taken += damage
		else:
			defender_damage_taken += damage

	func get_damage_taken(performing_player : Player) -> int:
		if performing_player == initiator:
			return initiator_damage_taken
		return defender_damage_taken

	func will_be_ex(performing_player : Player) -> bool:
		if extra_attack_in_progress and performing_player == extra_attack_data.extra_attack_player:
			return false
		if performing_player.strike_stat_boosts.attack_copy_gauge_or_transform_becomes_ex:
			var player_card = get_player_card(performing_player)
			# 这个标记由卡牌的 on_strike_reveal 提前打上（因为 EX 会影响**付费用**的时机），
			# 但「同名牌在哪些区域才算」由卡面 condition_zones 决定，不能写死：
			#   Minato   Bus Stop / Fractured Memories → transform, sealed
			#   Remiliss Irradiate / Sequence          → gauge, gauge_spent, transform
			# 写死成 transform/sealed 会让 Remiliss「怒气区有同名牌 → 强力攻击 →
			# free_if_ex 免付怒气」在付费用时不成立（玩家被迫白付怒气）。
			for check_card in performing_player.get_continuous_boosts_and_transforms():
				for check_effect in check_card.definition['boost']['effects']:
					if check_effect.get('effect_type', '') != StrikeEffects.AttackIsEx:
						continue
					if check_effect.get('condition', '') != "copy_of_attack_in_zones":
						continue
					for check_zone in check_effect.get('condition_zones', []):
						if performing_player.has_card_name_in_zone(player_card, check_zone):
							return true
			# 兜底：数据里没写 condition_zones 时沿用旧行为（转化区 / 封印区）。
			if performing_player.has_card_name_in_zone(player_card, "transform"):
				return true
			if performing_player.has_card_name_in_zone(player_card, "sealed"):
				return true

		for boost_card in performing_player.continuous_boosts:
			var effects = boost_card.definition['boost']['effects']
			for effect in effects:
				if effect['timing'] == 'during_strike' and effect['effect_type'] == StrikeEffects.AttackIsEx:
					return true
		if performing_player.strike_stat_boosts.is_ex:
			return true
		if performing_player == initiator:
			return initiator_ex_card != null
		else:
			return defender_ex_card != null

class Boost:
	var playing_player : Player
	var card : GameCard
	var boosted_from_gauge = false
	var effects_resolved = 0
	var action_after_boost = false
	var strike_after_boost = false
	var strike_after_boost_opponent_first = false
	var strike_after_boost_auto_strike = false
	var discard_on_cleanup = false
	var shuffle_discard_on_cleanup = false
	var discarded_already = false
	var seal_on_cleanup = false
	var cancel_resolved = false
	var checked_counter = false
	var counters_resolved = 0
	var boost_negated = false
	var allow_cancel_after_negate = false
	var cleanup_to_gauge_card_ids = []
	var cleanup_to_bleach_card_ids = []
	var cleanup_to_hand_card_ids = []
	var parent_boost = null
	var queued_boosts = []
	var strike_after_boost_stored_id = null
	# Syrus: from-gauge instant boost (Memories from the Deep) - player chose
	# how to handle the seal vs. exceed-face now effect.
	var syrus_gauge_seal_choice_made = false
	var syrus_seal_after_exceed_pending = false
	# 「展示并执行」（海蒂 开关扇：boost_multiple + return_to_hand）：被展示的加成
	# 只执行效果，**不打出** —— 不离开手牌、不进入加成区、不给对手反制窗口。
	var reveal_only = false
	# Forced-boost state used when there is no active strike (Heidi 机械天才, an
	# immediate boost that plays a continuous boost from the discard pile).
	# Mirrors the fields on Strike so boost_then_sustain_topdiscard works in
	# both a strike context and a plain boost context.
	var remaining_forced_boosts = 0
	var remaining_forced_boosts_source = ""
	var remaining_forced_boosts_player_id = Enums.PlayerId.PlayerId_Player
	var remaining_forced_boosts_sustaining = false
	var remaining_forced_boosts_ignore_costs = false
	# Set when this boost's boost_multiple effect is a "reveal and execute"
	# replacement (Heidi 开关扇: boost_multiple + return_to_hand). The revealed
	# boost replaces this one, so this boost's own on_boost character effects
	# (e.g. UA "结算加成摸 1 张") must not trigger.
	var skip_on_boost_effects = false
	# Dongshilang: 冰晶角色主行动在整段（1~N 张冰晶）结束后，仅询问一次取消。
	var dongshilang_ice_character_action_cancel_once = false


var player : Player
var opponent : Player

var active_turn_player : Enums.PlayerId
var next_turn_player : Enums.PlayerId

var strike_happened_this_turn : bool = false
var last_turn_was_strike : bool = false

func get_active_player() -> Enums.PlayerId:
	return active_turn_player

func get_priority_player() -> Enums.PlayerId:
	match game_state:
		Enums.GameState.GameState_PickAction, Enums.GameState.GameState_DiscardDownToMax:
			return active_turn_player
		Enums.GameState.GameState_PlayerDecision, Enums.GameState.GameState_WaitForStrike, \
		Enums.GameState.GameState_Strike_Opponent_Response, Enums.GameState.GameState_Strike_Opponent_Set_First:
			return decision_info.player
		_:
			# Any other states are internal processing.
			return active_turn_player

var random_number_generator : RandomNumberGenerator = RandomNumberGenerator.new()

func shuffle_array(arr) -> void:
	var n = arr.size()
	for i in range(n - 1, 0, -1):
		var j = get_random_int() % (i + 1)
		var temp = arr[j]
		arr[j] = arr[i]
		arr[i] = temp

func get_random_int() -> int:
	return random_number_generator.randi()

func get_random_int_range(from : int, to : int) -> int:
	return random_number_generator.randi_range(from, to)

func initialize_game(
	player_deck,
	opponent_deck,
	player_name : String,
	opponent_name : String,
	first_player : Enums.PlayerId,
	seed_value : int
):
	player_deck = player_deck.duplicate(true)
	opponent_deck = opponent_deck.duplicate(true)
	random_number_generator.seed = seed_value
	card_db = CardDatabase.new(image_loader)
	CardDataManager.load_deck_if_custom(player_deck)
	CardDataManager.load_deck_if_custom(opponent_deck)
	var logic_player_deck = _normalize_deck_for_logic(player_deck)
	var logic_opponent_deck = _normalize_deck_for_logic(opponent_deck)
	var player_card_id_start = 100
	var opponent_card_id_start = 200
	if first_player == Enums.PlayerId.PlayerId_Opponent:
		player_card_id_start = 200
		opponent_card_id_start = 100
	player = Player.new(Enums.PlayerId.PlayerId_Player,
		player_name,
		self,
		card_db,
		logic_player_deck,
		player_card_id_start)
	opponent = Player.new(Enums.PlayerId.PlayerId_Opponent,
		opponent_name,
		self,
		card_db,
		logic_opponent_deck,
		opponent_card_id_start)

	active_turn_player = first_player
	next_turn_player = get_other_player(first_player)
	var starting_player = _get_player(active_turn_player)
	var second_player = _get_player(next_turn_player)
	starting_player.arena_location = 3
	starting_player.starting_location = 3
	if (starting_player.set_starting_face_attack) && (starting_player.starting_face_attack_id != ""):
		handle_strike_effect(
			-1,
			{
				"effect_type": StrikeEffects.SetFaceAttack,
				"card_id": starting_player.starting_face_attack_id
			},
			starting_player)
	if starting_player.buddy_starting_offset != Enums.BuddyStartsOutOfArena:
		var buddy_space = 3 + starting_player.buddy_starting_offset
		starting_player.place_buddy(buddy_space,
			starting_player.buddy_starting_id, true)
	second_player.arena_location = 7
	second_player.starting_location = 7
	if (second_player.set_starting_face_attack) && (second_player.starting_face_attack_id != ""):
		handle_strike_effect(
			-1,
			{
				"effect_type": StrikeEffects.SetFaceAttack,
				"card_id": second_player.starting_face_attack_id
			},
			second_player)
	if second_player.buddy_starting_offset != Enums.BuddyStartsOutOfArena:
		var buddy_space = 7 - second_player.buddy_starting_offset
		second_player.place_buddy(buddy_space, second_player.buddy_starting_id, true)
	starting_player.initial_shuffle()
	second_player.initial_shuffle()

func _normalize_deck_for_logic(deck_def: Dictionary) -> Dictionary:
	var normalized = deck_def.duplicate(true)
	var base_id = str(normalized.get("base_id", ""))
	if base_id.is_empty():
		base_id = str(normalized.get("id", ""))
	normalized["id"] = base_id
	return normalized

func draw_starting_hands_and_begin():
	var starting_player = _get_player(active_turn_player)
	var second_player = _get_player(next_turn_player)
	_append_log_full(Enums.LogType.LogType_Default, null,
		"游戏开始 - %s 使用 %s（先手） vs %s 使用 %s（后手）" % [starting_player.name,
			starting_player.deck_def['display_name'], second_player.name,
			second_player.deck_def['display_name']])
	starting_player.draw(Enums.StartingHandFirstPlayer + starting_player.starting_hand_size_bonus)
	second_player.draw(Enums.StartingHandSecondPlayer + second_player.starting_hand_size_bonus)
	change_game_state(Enums.GameState.GameState_Mulligan)
	create_event(Enums.EventType.EventType_MulliganDecision, player.my_id, 0)
	return true

# Thresholds are collected synchronously, but decisions start only at resumable
# boundaries. In particular, damage must finish stun/death bookkeeping first.
func _queue_heiqiyihu_thresholds(target : Player):
	if target == null or game_over or target.life <= 0 or target.exceeded:
		return
	if target.deck_def.get("id", "") != "heiqiyihu":
		return
	for threshold in [25, 15, 10]:
		if target.life <= threshold and threshold not in target.heiqiyihu_thresholds_used:
			target.heiqiyihu_thresholds_used.append(threshold)
			heiqiyihu_pending_thresholds.append({"player": target.my_id, "threshold": threshold})

func _begin_heiqiyihu_thresholds(resume_player : Player, resume_kind : String = "action") -> bool:
	if game_over or game_state == Enums.GameState.GameState_PlayerDecision:
		return false
	if not heiqiyihu_threshold_context.is_empty() or heiqiyihu_pending_thresholds.is_empty():
		return false
	heiqiyihu_threshold_context = {
		"state": game_state,
		"player": resume_player.my_id,
		"kind": resume_kind,
		"source_player_id": _last_effect_source_player_id
	}
	_offer_heiqiyihu_threshold_source()
	return true

func _offer_heiqiyihu_threshold_source():
	if game_over:
		heiqiyihu_pending_thresholds.clear()
		heiqiyihu_threshold_context.clear()
		return
	if heiqiyihu_pending_thresholds.is_empty():
		_resume_after_heiqiyihu_thresholds()
		return
	var pending = heiqiyihu_pending_thresholds[0]
	var target = _get_player(pending["player"])
	change_game_state(Enums.GameState.GameState_PlayerDecision)
	decision_info.clear()
	decision_info.type = Enums.DecisionType.DecisionType_EffectChoice
	decision_info.player = target.my_id
	decision_info.effect_type = StrikeEffects.HeiqiyihuThresholdSource
	decision_info.choice_card_id = -1
	decision_info.choice = [{
		"effect_type": StrikeEffects.HeiqiyihuThresholdSource,
		"source": "deck",
		"_choice_text": "将牌堆顶1张牌置入守护区"
	}]
	for hand_card in target.hand:
		decision_info.choice.append({
			"effect_type": StrikeEffects.HeiqiyihuThresholdSource,
			"source": "hand",
			"guardian_card_id": hand_card.id,
			"_choice_text": "将手牌「%s」置入守护区" % hand_card.definition["display_name"]
		})
	decision_info.effect = {"threshold": pending["threshold"]}
	create_event(Enums.EventType.EventType_Strike_EffectChoice, target.my_id, 0, "守护：选择1张牌")

func _do_heiqiyihu_threshold_choice(performing_player : Player, choice_index : int) -> bool:
	if game_state != Enums.GameState.GameState_PlayerDecision \
	or decision_info.player != performing_player.my_id \
	or choice_index < 0 or choice_index >= decision_info.choice.size():
		printlog("ERROR: Invalid Heiqiyihu threshold choice.")
		return false
	var selected = decision_info.choice[choice_index]
	var guardian : GameCard = null
	if selected["source"] == "hand":
		var selected_id = selected["guardian_card_id"]
		if not performing_player.is_card_in_hand(selected_id):
			printlog("ERROR: Heiqiyihu threshold hand card is no longer available.")
			return false
		guardian = card_db.get_card(selected_id)
		performing_player.remove_card_from_hand(selected_id, true, false)
	else:
		# The same retry/reshuffle/deckout semantics as Player.draw, without
		# ever inserting the selected card into the hand.
		while performing_player.deck.is_empty() and not game_over:
			performing_player.reshuffle_discard(false)
		if game_over:
			heiqiyihu_pending_thresholds.clear()
			heiqiyihu_threshold_context.clear()
			return true
		guardian = performing_player.deck[0]
		performing_player.remove_top_card_from_deck()
		performing_player.on_hand_removed_topdeck(guardian.id)
		performing_player.public_topdeck_id = -1
	performing_player.add_to_bleach(guardian)
	_append_log_full(Enums.LogType.LogType_CardInfo, performing_player,
		"生命阈值%s：将%s置入守护区。" % [
			str(heiqiyihu_pending_thresholds[0]["threshold"]), _log_card_name(guardian.definition["display_name"])])
	heiqiyihu_pending_thresholds.pop_front()
	_offer_heiqiyihu_threshold_source()
	return true

func _resume_after_heiqiyihu_thresholds():
	var context = heiqiyihu_threshold_context
	heiqiyihu_threshold_context = {}
	var resume_player = _get_player(context["player"])
	_last_effect_source_player_id = context["source_player_id"]
	change_game_state(context["state"])
	match context["kind"]:
		"opening":
			_finish_opening_mulligans()
		"strike":
			continue_resolve_strike()
		"hand_size":
			check_hand_size_advance_turn(resume_player)
		"action":
			continue_player_action_resolution(resume_player)
		"idle":
			if queued_effect_chain["effect"]:
				do_queued_effects(resume_player)
				if game_state != Enums.GameState.GameState_PlayerDecision and not game_over:
					change_game_state(context["state"])

func _finish_opening_mulligans():
	change_game_state(Enums.GameState.GameState_PickAction)
	_append_log_full(Enums.LogType.LogType_Default, _get_player(active_turn_player), "的回合开始！")
	create_event(Enums.EventType.EventType_AdvanceTurn, active_turn_player, 0)

func _has_heiqiyihu_guardian_option() -> bool:
	for candidate in [player, opponent]:
		if candidate and candidate.deck_def.get("id", "") == "heiqiyihu" \
		and not candidate.exceeded and not candidate.bleach_zone.is_empty():
			return true
	return false

func _begin_pending_heiqiyihu_strike() -> bool:
	if heiqiyihu_pending_strike_request.is_empty() or active_strike or active_boost \
	or game_over or game_state == Enums.GameState.GameState_PlayerDecision:
		return false
	var request = heiqiyihu_pending_strike_request
	heiqiyihu_pending_strike_request = {}
	return _declare_heiqiyihu_strike(_get_player(request["player"]),
		request["opponent_first"], request["required_wild"], request.get("required_face_attack", false))

func _declare_heiqiyihu_strike(initiator : Player, opponent_first : bool, required_wild : bool = false, required_face_attack : bool = false) -> bool:
	var restriction = decision_info.limitation if game_state == Enums.GameState.GameState_WaitForStrike else ""
	var source = decision_info.source if game_state == Enums.GameState.GameState_WaitForStrike else ""
	initialize_new_strike(initiator, opponent_first)
	active_strike.heiqiyihu_declared_before_set = true
	active_strike.heiqiyihu_required_wild = required_wild
	active_strike.heiqiyihu_required_face_attack = required_face_attack
	heiqiyihu_pending_strike_request = {}
	heiqiyihu_guardian_setup = {
		"players": [active_strike.initiator.my_id, active_strike.defender.my_id],
		"index": 0,
		"effects": [],
		"effect_index": 0,
		"owner": initiator.my_id,
		"source_id": -1,
		"restriction": restriction,
		"source": source
	}
	_append_log_full(Enums.LogType.LogType_Strike, initiator, "宣战：双方选择攻击牌前，结算守护。")
	change_game_state(Enums.GameState.GameState_Strike_Processing)
	_continue_heiqiyihu_guardian_setup()
	return true

func _continue_heiqiyihu_guardian_setup():
	if game_over or heiqiyihu_guardian_setup.is_empty() \
	or game_state == Enums.GameState.GameState_PlayerDecision:
		return
	var setup = heiqiyihu_guardian_setup
	while setup["effect_index"] < setup["effects"].size():
		var effect = setup["effects"][setup["effect_index"]]
		setup["effect_index"] += 1
		do_effect_if_condition_met(_get_player(setup["owner"]), setup["source_id"], effect, null)
		if game_over or game_state == Enums.GameState.GameState_PlayerDecision:
			return
	_finish_heiqiyihu_virtual_boost_play(setup["source_id"])
	setup["effects"] = []
	setup["effect_index"] = 0
	while setup["index"] < setup["players"].size():
		var guardian_player = _get_player(setup["players"][setup["index"]])
		if guardian_player.deck_def.get("id", "") != "heiqiyihu" \
		or guardian_player.exceeded or guardian_player.bleach_zone.is_empty():
			setup["index"] += 1
			continue
		change_game_state(Enums.GameState.GameState_PlayerDecision)
		decision_info.clear()
		decision_info.type = Enums.DecisionType.DecisionType_EffectChoice
		decision_info.player = guardian_player.my_id
		decision_info.effect_type = "heiqiyihu_guardian_before_set"
		decision_info.choice_card_id = -1
		decision_info.choice = []
		for guardian in guardian_player.bleach_zone:
			decision_info.choice.append({
				"effect_type": "heiqiyihu_guardian_before_set",
				"guardian_card_id": guardian.id,
				"_choice_text": "触发守护「%s」" % guardian.definition["display_name"]
			})
		decision_info.choice.append({"effect_type": StrikeEffects.Pass, "_choice_text": "不触发守护"})
		create_event(Enums.EventType.EventType_Strike_EffectChoice, guardian_player.my_id, 0, "双方选牌前：守护")
		return
	var restriction = setup["restriction"]
	var source = setup["source"]
	heiqiyihu_guardian_setup = {}
	if active_strike.opponent_sets_first:
		continue_setup_strike()
		return
	change_game_state(Enums.GameState.GameState_WaitForStrike)
	decision_info.clear()
	decision_info.type = Enums.DecisionType.DecisionType_StrikeNow
	decision_info.player = active_strike.initiator.my_id
	decision_info.limitation = restriction
	decision_info.source = source
	if active_strike.heiqiyihu_required_wild:
		do_strike(active_strike.initiator, -1, true, -1)
	elif active_strike.heiqiyihu_required_face_attack:
		do_strike(active_strike.initiator, -1, false, -1, false, true)
	elif active_strike.initiator.next_strike_from_gauge or active_strike.initiator.next_strike_from_sealed:
		create_event(Enums.EventType.EventType_Strike_FromGauge, active_strike.initiator.my_id, 0)
	else:
		create_event(Enums.EventType.EventType_ForceStartStrike, active_strike.initiator.my_id, 0)

func _do_heiqiyihu_guardian_choice(performing_player : Player, choice_index : int) -> bool:
	if decision_info.player != performing_player.my_id or choice_index < 0 \
	or choice_index >= decision_info.choice.size():
		printlog("ERROR: Invalid Heiqiyihu pre-set guardian choice.")
		return false
	var choice = decision_info.choice[choice_index]
	if choice["effect_type"] != StrikeEffects.Pass:
		var guardian_id = choice["guardian_card_id"]
		if performing_player.exceeded or not performing_player.is_card_in_bleach(guardian_id):
			printlog("ERROR: Heiqiyihu guardian is no longer available.")
			return false
		var guardian = performing_player.remove_card_from_bleach(guardian_id)
		performing_player.add_to_discards(guardian)
		var boost = guardian.definition["boost"].duplicate(true)
		active_strike.heiqiyihu_guardian_records.append({
			"player": performing_player.my_id,
			"source_id": guardian_id,
			"boost": boost
		})
		heiqiyihu_guardian_setup["owner"] = performing_player.my_id
		heiqiyihu_guardian_setup["source_id"] = guardian_id
		heiqiyihu_guardian_setup["effects"] = []
		for effect in boost["effects"]:
			if effect["timing"] in ["now", "immediate"]:
				var immediate = effect.duplicate(true)
				immediate["card_id"] = guardian_id
				_add_source_player_id_to_effect_tree(immediate, performing_player.my_id)
				heiqiyihu_guardian_setup["effects"].append(immediate)
	heiqiyihu_guardian_setup["index"] += 1
	change_game_state(Enums.GameState.GameState_Strike_Processing)
	_continue_heiqiyihu_guardian_setup()
	return true

func _offer_heiqiyihu_xuhua_recovery(performing_player : Player, source_id : int, destination : String):
	var choices = []
	for paid_id in active_strike.heiqiyihu_xuhua_spent_ids.get(source_id, []):
		if performing_player.is_card_in_discards(paid_id):
			choices.append({
				"effect_type": StrikeEffects.HeiqiyihuXuhuaRecoverCard,
				"paid_id": paid_id,
				"destination": destination,
				"_choice_text": "将「%s」置入%s" % [card_db.get_card_name(paid_id),
					"守护区" if destination == "bleach" else "怒气区"]
			})
	if choices.is_empty():
		active_strike.heiqiyihu_xuhua_spent_ids.erase(source_id)
	else:
		handle_strike_effect(source_id, {
			"effect_type": StrikeEffects.Choice, "choice": choices
		}, performing_player)

func _get_heiqiyihu_virtual_guardian(source_id : int) -> Dictionary:
	if active_strike:
		for record in active_strike.heiqiyihu_guardian_records:
			if record["source_id"] == source_id:
				return record
	return {}

func _get_heiqiyihu_guardian_boost(record : Dictionary) -> Dictionary:
	var boost = record["boost"].duplicate(true)
	var source = card_db.get_card(record["source_id"])
	if source.definition["type"] != "special":
		return boost
	var bonus = 1
	var owner = _get_player(record["player"])
	var attack = active_strike.get_player_card(owner)
	# Both attacks have paid (or been replaced) before these five boosts'
	# first strike timing. Never amplify from an invalidated original attack.
	if active_strike.strike_state >= StrikeState.StrikeState_DuringStrikeBonuses \
	and attack != null and attack.definition["id"] == "heiqiyihu_呼唤我的名字吧！":
		bonus += 1
	for effect in boost["effects"]:
		match effect["effect_type"]:
			StrikeEffects.Powerup, StrikeEffects.Guardup, StrikeEffects.Speedup, StrikeEffects.Draw:
				effect["amount"] += bonus
			StrikeEffects.MoveToAnySpace:
				effect["move_max"] += bonus
			StrikeEffects.Rangeup:
				effect["amount"] += bonus
				effect["amount2"] += bonus
	return boost

func _move_heiqiyihu_virtual_source(source_id : int, destination : String) -> bool:
	var record = _get_heiqiyihu_virtual_guardian(source_id)
	if record.is_empty():
		return false
	var owner = _get_player(record["player"])
	# The copied effects outlive the entity. Never fetch another copy by name,
	# or take this entity back from a new zone.
	if not owner.is_card_in_discards(source_id):
		return false
	var source_card = card_db.get_card(source_id)
	owner.remove_card_from_discards(source_id)
	match destination:
		"gauge":
			owner.add_to_gauge(source_card)
		"bleach":
			owner.add_to_bleach(source_card)
		"overdrive":
			owner.add_to_overdrive(source_card)
	_append_log_full(Enums.LogType.LogType_CardInfo, owner,
		"守护原卡%s移入%s。" % [_log_card_name(source_card.definition["display_name"]), destination])
	return true

func _finish_heiqiyihu_virtual_boost_play(source_id : int):
	var record = _get_heiqiyihu_virtual_guardian(source_id)
	if record.has("boost_play_destination"):
		_move_heiqiyihu_virtual_source(source_id, record["boost_play_destination"])
		record.erase("boost_play_destination")

func _heiqiyihu_virtual_forces_wild(guardian_player : Player) -> bool:
	if not active_strike or active_strike.initiator != guardian_player:
		return false
	for record in active_strike.heiqiyihu_guardian_records:
		if record["player"] == guardian_player.my_id:
			for effect in record["boost"]["effects"]:
				if effect["effect_type"] == "opponent_wild_swings":
					return true
	return false

func _test_add_to_gauge(amount: int):
	for i in range(amount):
		player.draw(1)
		var card = player.hand[0]
		player.remove_card_from_hand(card.id, true, false)
		player.add_to_gauge(card)
	return true

func get_card_database() -> CardDatabase:
	return card_db

func get_player_name(player_id : Enums.PlayerId) -> String:
	if player_id == Enums.PlayerId.PlayerId_Player:
		return player.name
	return opponent.name

# TODO: This function is frequently called from outside and probably shouldn't
# start with an underscore.
func _get_player(player_id : Enums.PlayerId) -> Player:
	if player_id == Enums.PlayerId.PlayerId_Player:
		return player
	return opponent

func get_other_player(test_player : Enums.PlayerId) -> Enums.PlayerId:
	if test_player == Enums.PlayerId.PlayerId_Player:
		return Enums.PlayerId.PlayerId_Opponent
	return Enums.PlayerId.PlayerId_Player

func _prepare_face_attack_for_strike(performing_player : Player) -> GameCard:
	var face_attack_card = performing_player.get_face_attack_card()
	if not face_attack_card:
		return null

	performing_player.get_set_aside_card(face_attack_card.definition['id'], true)
	performing_player.add_to_hand(face_attack_card, false)
	performing_player.next_strike_faceup = true
	performing_player.next_strike_from_face_attack = true
	return face_attack_card


func start_end_turn():
	active_end_of_turn_effects = true
	end_of_turn_draw_resolved = false
	end_of_turn_skip_eot_discard = false
	if _get_player(active_turn_player).did_strike_this_turn:
		# Any strike this turn suppresses the normal end-of-turn draw step.
		_get_player(active_turn_player).skip_end_of_turn_draw = true

	# Queue any end of turn character effects.
	var player_ending_turn = _get_player(active_turn_player)
	var effects = player_ending_turn.get_character_effects_at_timing("end_of_turn")
	for effect in effects:
		if effect.get('condition', '') != "did_end_of_turn_draw":
			remaining_end_of_turn_effects.append(effect)

	# Queue any end of turn boost effects.
	var boost_list = player_ending_turn.get_continuous_boosts_and_transforms()
	var minato_one_more_ride_queued = false
	for i in range(len(boost_list) - 1, -1, -1):
		var card = boost_list[i]
		for effect in card.definition['boost']['effects']:
			if effect['timing'] == "end_of_turn":
				if effect.get('condition', '') == "did_end_of_turn_draw":
					continue
				if card.id in player_ending_turn.end_of_turn_boost_delay_card_ids:
					# This effect is delayed a turn, so remove it from the list and skip it for now.
					player_ending_turn.end_of_turn_boost_delay_card_ids.erase(card.id)
					continue
				if effect.get('effect_type', '') == "minato_one_more_ride":
					if minato_one_more_ride_queued:
						continue
					minato_one_more_ride_queued = true
				effect['card_id'] = card.id
				remaining_end_of_turn_effects.append(effect)

	# 战斗在结算中途被结束（典型：Umina「Unknown Khadath」吞掉对手攻击后直接跳到
	# Cleanup）时，_umina_check_slipping_away 排队的 Move 1 只能等到下一次
	# do_queued_effects 才执行 —— 于是「置入幻梦境时」的触发被推迟到下一回合，
	# 时机错乱。这里在回合结束效果之前统一结算一次：
	# 此时 active_end_of_turn_effects 已置位，若排队效果产生决策，玩家选完后
	# continue_player_action_resolution 会自动续接 continue_end_turn()。
	if queued_effect_chain["effect"]:
		do_queued_effects(_get_player(active_turn_player))
		if game_state == Enums.GameState.GameState_PlayerDecision:
			return

	return continue_end_turn()

func continue_end_turn():
	var player_ending_turn = _get_player(active_turn_player)
	change_game_state(Enums.GameState.GameState_Boost_Processing)
	while remaining_end_of_turn_effects.size() > 0:
		var effect = remaining_end_of_turn_effects[0]
		remaining_end_of_turn_effects.erase(effect)
		var card_id = -1
		if 'card_id' in effect:
			card_id = effect['card_id']
		do_effect_if_condition_met(player_ending_turn, card_id, effect, null)
		if game_state == Enums.GameState.GameState_PlayerDecision:
			# Player has a decision to make, so stop mid-effect resolve.
			break

	if game_state != Enums.GameState.GameState_PlayerDecision:
		if not end_of_turn_draw_resolved:
			finish_end_turn_draw(player_ending_turn)
		else:
			active_end_of_turn_effects = false
			finish_end_turn_resolution(player_ending_turn)

func finish_end_turn_draw(performing_player : Player):
	end_of_turn_draw_resolved = true
	# 默认：跳过「回合结束抽牌」会连带跳过「弃牌到手牌上限」（superskullman Zap 等依赖此行为）。
	# 但标记了 eot_skip_draw_still_check_hand_limit 的效果（minato One More Ride、eugenia
	# Time for Tea 觉醒）只是「不抽牌」，手牌超过上限时仍须弃牌。
	var skip_eot_discard = (performing_player.skip_end_of_turn_draw and not performing_player.eot_skip_draw_still_check_hand_limit) or performing_player.has_passive("skip_eot_draw_and_discard")
	end_of_turn_skip_eot_discard = skip_eot_discard
	printlog("EOT_DRAW_BEGIN player=%s skip=%s draw_at_eot=%s hand=%d deck=%d queue=%d state=%s" % [
		performing_player.name,
		str(skip_eot_discard),
		str(performing_player.draw_at_end_of_turn),
		performing_player.hand.size(),
		performing_player.deck.size(),
		event_queue.size(),
		Enums.GameState.keys()[game_state],
	])
	if performing_player.skip_end_of_turn_draw or performing_player.has_passive("skip_eot_draw_and_discard"):
		performing_player.skip_end_of_turn_draw = false
		performing_player.eot_skip_draw_still_check_hand_limit = false
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "跳过回合结束抽牌。其手牌数为%s。" % len(performing_player.hand))
	else:
		# Set this regardless so characters that don't draw at end of turn know to do something else
		performing_player.did_end_of_turn_draw = true
		if performing_player.draw_at_end_of_turn:
			var from_bottom_str = ""
			if active_special_draw_effect and performing_player.dan_draw_choice_from_bottom:
				performing_player.draw(1, false, true)
				from_bottom_str = " from bottom of deck"
			else:
				performing_player.draw(1)
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "回合结束时抽%s。其手牌数现在为%s。" % [from_bottom_str, len(performing_player.hand)])
			printlog("EOT_DRAW_AFTER player=%s hand=%d deck=%d queue=%d" % [
				performing_player.name,
				performing_player.hand.size(),
				performing_player.deck.size(),
				event_queue.size(),
			])

	# Once the actual end-of-turn draw step is finished, later post-draw choices
	# must resume the end-turn pipeline instead of re-entering the special draw branch.
	active_special_draw_effect = false

	queue_end_of_turn_post_draw_effects(performing_player)
	if remaining_end_of_turn_effects.size() > 0:
		return continue_end_turn()

	active_end_of_turn_effects = false
	finish_end_turn_resolution(performing_player)

func queue_end_of_turn_post_draw_effects(performing_player : Player):
	var effects = performing_player.get_character_effects_at_timing("end_of_turn")
	for effect in effects:
		if effect.get('condition', '') == "did_end_of_turn_draw":
			remaining_end_of_turn_effects.append(effect)

	var boost_list = performing_player.get_continuous_boosts_and_transforms()
	for i in range(len(boost_list) - 1, -1, -1):
		var card = boost_list[i]
		for effect in card.definition['boost']['effects']:
			if effect['timing'] == "end_of_turn" and effect.get('condition', '') == "did_end_of_turn_draw":
				effect['card_id'] = card.id
				remaining_end_of_turn_effects.append(effect)

func finish_end_turn_resolution(performing_player : Player):
	if len(performing_player.hand) > performing_player.max_hand_size and not end_of_turn_skip_eot_discard \
	and not performing_player.heiqiyihu_skip_hand_limit_this_turn:
		discard_to_max_after_end_turn_draw = true
		change_game_state(Enums.GameState.GameState_DiscardDownToMax)
		create_event(Enums.EventType.EventType_HandSizeExceeded, performing_player.my_id, len(performing_player.hand) - performing_player.max_hand_size)
	else:
		advance_to_next_turn()

func advance_to_next_turn():
	# Reset effect source tracking for new turn
	_last_effect_source_player_id = -1
	# Double's sealed-card bonuses last only through the current turn.
	for double_player in [player, opponent]:
		double_player.double_true_face_stacks = 0
		double_player.double_nightmare_army_stacks = 0

	var player_ending_turn = _get_player(active_turn_player)
	var other_player = _get_player(get_other_player(active_turn_player))

	# Turn is over, reset state.
	player.did_end_of_turn_draw = false
	opponent.did_end_of_turn_draw = false
	# This flag is only meaningful for the turn that is ending.
	# Reset defensively on turn handoff in case an uncommon branch skipped its normal clear path.
	player.skip_end_of_turn_draw = false
	opponent.skip_end_of_turn_draw = false
	player.eot_skip_draw_still_check_hand_limit = false
	opponent.eot_skip_draw_still_check_hand_limit = false
	player.did_strike_this_turn = false
	opponent.did_strike_this_turn = false
	player.canceled_this_turn = false
	opponent.canceled_this_turn = false
	player.do_not_cleanup_buddy_this_turn = false
	opponent.do_not_cleanup_buddy_this_turn = false
	player.cancel_blocked_this_turn = false
	opponent.cancel_blocked_this_turn = false
	player.noelle_damage_toll_used_this_turn = false
	opponent.noelle_damage_toll_used_this_turn = false
	player.pre_strike_movement = 0
	opponent.pre_strike_movement = 0
	player.opponent_was_stunned_this_turn = false
	opponent.opponent_was_stunned_this_turn = false
	player.used_character_action = false
	opponent.used_character_action = false
	player.used_character_action_details = []
	opponent.used_character_action_details = []
	player.used_character_bonus = false
	opponent.used_character_bonus = false
	player.start_of_turn_strike = false
	opponent.start_of_turn_strike = false
	player.total_force_spent_this_turn = 0
	opponent.total_force_spent_this_turn = 0
	player.force_spent_before_strike = 0
	opponent.force_spent_before_strike = 0
	player.gauge_spent_before_strike = 0
	opponent.gauge_spent_before_strike = 0
	player.gauge_spent_this_strike = 0
	opponent.gauge_spent_this_strike = 0
	player.gauge_cards_spent_this_strike = []
	opponent.gauge_cards_spent_this_strike = []
	player.moved_self_this_strike = false
	opponent.moved_self_this_strike = false
	player.moved_past_this_strike = false
	opponent.moved_past_this_strike = false
	player.spaces_moved_this_strike = 0
	opponent.spaces_moved_this_strike = 0
	player.spaces_forced_moved_this_strike = 0
	opponent.spaces_forced_moved_this_strike = 0
	player.spaces_moved_or_forced_this_strike = 0
	opponent.spaces_moved_or_forced_this_strike = 0
	player.cards_that_will_not_hit = []
	opponent.cards_that_will_not_hit = []
	player.cards_invalid_during_strike = []
	opponent.cards_invalid_during_strike = []
	player.plague_knight_discard_names = []
	opponent.plague_knight_discard_names = []
	player.strike_action_disabled = false
	opponent.strike_action_disabled = false
	player.checked_post_action_effects = false
	opponent.checked_post_action_effects = false
	player.spent_gauge_this_turn = false
	opponent.spent_gauge_this_turn = false
	player.infused = false
	opponent.infused = false

	# Update strike turn tracking
	last_turn_was_strike = strike_happened_this_turn
	strike_happened_this_turn = false

	# Figure out next turn's player.
	active_turn_player = next_turn_player
	next_turn_player = get_other_player(active_turn_player)

	# Handle any end of turn exceed.
	if player_ending_turn.exceed_at_end_of_turn:
		player_ending_turn.exceed()
		player_ending_turn.exceed_at_end_of_turn = false
	if other_player.exceed_at_end_of_turn:
		other_player.exceed()
		other_player.exceed_at_end_of_turn = false

	if game_over:
		change_game_state(Enums.GameState.GameState_GameOver)
	else:
		var starting_turn_player = _get_player(active_turn_player)
		if starting_turn_player.is_overdrive_active() and starting_turn_player.overdrive.size() > 0:
			# Do overdrive effect.
			var overdrive_effects = [{
				"overdrive_action": true,
				"effect_type": StrikeEffects.ChooseDiscard,
				"source": "overdrive",
				"limitation": "",
				"destination": "discard",
				"amount": 1,
				"amount_min": 1
			}]
			overdrive_effects.append(starting_turn_player.get_overdrive_effect())
			overdrive_effects.append({
				"condition": "overdrive_empty",
				"effect_type": StrikeEffects.EndOverdrive
			})
			active_overdrive = true
			remaining_overdrive_effects = overdrive_effects
			_append_log_full(Enums.LogType.LogType_Default, starting_turn_player, "'s Overdrive Effects!")
			do_remaining_overdrive(starting_turn_player)
		elif starting_turn_player.is_overdrive_active() and starting_turn_player.overdrive.size() == 0:
			# Overdrive is empty, so revert to normal.
			starting_turn_player.end_overdrive()
			start_begin_turn()
		else:
			start_begin_turn()

func start_begin_turn():
	active_start_of_turn_effects = true
	player.heiqiyihu_skip_hand_limit_this_turn = false
	opponent.heiqiyihu_skip_hand_limit_this_turn = false
	# Defensive reset: the end-of-turn draw skip is only meant to affect the
	# turn it was set on, so clear it again when a fresh turn starts.
	player.skip_end_of_turn_draw = false
	opponent.skip_end_of_turn_draw = false
	player.eot_skip_draw_still_check_hand_limit = false
	opponent.eot_skip_draw_still_check_hand_limit = false
	player.zsolt_extra_attack_count = 0
	player.zsolt_awaken_offered = false
	player.seal_force_bonus_tmp = 0
	player.force_for_armor_apf_tmp = 0
	player.syrus_reckless_greed_used = false
	player.minato_outrun_triggered_before_strike = false
	opponent.zsolt_extra_attack_count = 0
	opponent.zsolt_awaken_offered = false
	opponent.seal_force_bonus_tmp = 0
	opponent.force_for_armor_apf_tmp = 0
	opponent.syrus_reckless_greed_used = false
	opponent.minato_outrun_triggered_before_strike = false
	player.pooky_drunken_fury_used = false
	opponent.pooky_drunken_fury_used = false
	player.pooky_zols_target_id = -1
	opponent.pooky_zols_target_id = -1
	player.pooky_zols_used_this_turn = false
	opponent.pooky_zols_used_this_turn = false
	player.renea_boost_from_briefcase_used = false
	opponent.renea_boost_from_briefcase_used = false

	# Handle any start of turn boost effects.
	# Iterate in reverse as items can be removed.
	var starting_turn_player = _get_player(active_turn_player)
	if starting_turn_player != null and starting_turn_player.deck_def.get("id") == "minato" and starting_turn_player.exceeded:
		var minato_discards = starting_turn_player.discards
		if minato_discards != null and minato_discards.size() > 0:
			minato_discards = minato_discards.duplicate()
			var minato_sealed_count = 0
			for minato_card in minato_discards:
				if starting_turn_player.is_card_in_discards(minato_card.id):
					do_seal_effect(starting_turn_player, minato_card.id, "discard")
					minato_sealed_count += 1
			starting_turn_player.minato_seal_power_bonus += minato_sealed_count
			_append_log_full(Enums.LogType.LogType_Effect, starting_turn_player, "封印其弃牌堆中的%s张牌。下一次攻击获得+%s威力。" % [minato_sealed_count, minato_sealed_count])
	# Umina exceed passive (umina.txt): look at top of deck, put into Dreamlands or discard
	if starting_turn_player != null and starting_turn_player.deck_def.get("id") == "umina" and starting_turn_player.exceeded:
		handle_strike_effect(-1, {"effect_type": "umina_begin_turn_dreamlands"}, starting_turn_player)
	remaining_start_of_turn_effects = get_all_effects_for_timing("start_of_next_turn", starting_turn_player, null)
	return continue_begin_turn()

func continue_begin_turn():
	var starting_turn_player = _get_player(active_turn_player)
	var other_player = _get_player(get_other_player(starting_turn_player.my_id))
	if game_state != Enums.GameState.GameState_PlayerDecision:
		change_game_state(Enums.GameState.GameState_Boost_Processing)
	while remaining_start_of_turn_effects.size() > 0:
		var effect = remaining_start_of_turn_effects[0]
		remaining_start_of_turn_effects.erase(effect)

		var card_id = -1
		if 'card_id' in effect:
			card_id = effect['card_id']

		if effect['timing'] == "start_of_next_turn":
			do_effect_if_condition_met(starting_turn_player, card_id, effect, null)
		elif effect['timing'] == "opponent_start_of_next_turn":
			# This timing fires on the non-active player at the start of every
			# turn. For boosts flagged with only_on_owner_opponent_turn, only
			# resolve on the turn of the boost owner's opponent.
			var resolve_opponent_turn_effect = true
			if effect.get('only_on_owner_opponent_turn', false):
				resolve_opponent_turn_effect = card_id >= 0 and card_db.get_card(card_id).owner_id == other_player.my_id
			if resolve_opponent_turn_effect:
				do_effect_if_condition_met(other_player, card_id, effect, null)
		else:
			assert(false, "Unexpected timing for start of turn effect")

		if game_state == Enums.GameState.GameState_PlayerDecision:
			# Player has a decision to make, so stop mid-effect resolve.
			break

	if game_state != Enums.GameState.GameState_PlayerDecision:
		# 排队效果（典型：Umina 觉醒后回合开始把牌放入幻梦境 → Slipping Away 的
		# Move 1）必须在进入行动阶段之前结算，否则会残留到下一次 do_queued_effects，
		# 触发时机被推迟。此时若产生决策，玩家选完后
		# continue_player_action_resolution 会因 active_start_of_turn_effects 仍为 true
		# 而重新进入本函数，把下面的收尾走完。
		if queued_effect_chain["effect"]:
			do_queued_effects(starting_turn_player)
			if game_state == Enums.GameState.GameState_PlayerDecision:
				return

		active_start_of_turn_effects = false

		# Transition to the pick action state, the player can now make their action for the turn.
		_append_log_full(Enums.LogType.LogType_Default, starting_turn_player, "'s Turn Start!")
		# Reset per-turn passive flags
		starting_turn_player.eugenia_normal_passive_used_this_turn = false
		other_player.eugenia_normal_passive_used_this_turn = false
		change_game_state(Enums.GameState.GameState_PickAction)
		decision_info.clear()
		create_event(Enums.EventType.EventType_AdvanceTurn, active_turn_player, 0)

		# Check if the player has to do a forced action for their turn.
		if starting_turn_player.effect_on_turn_start:
			var effect = starting_turn_player.effect_on_turn_start
			starting_turn_player.effect_on_turn_start = null
			# Pretend this is a character action.
			# Currently, this either does a choice which results in bonus action and boosting something
			# or causes a strike to begin. So execution will resume in do_choice or do_strike as if this
			# was the appropriate action
			active_character_action = true
			set_player_action_processing_state()
			do_effect_if_condition_met(starting_turn_player, -1, effect, null)
			# This is not expected to do anything currently, but potentially does some future-proofing.
			continue_player_action_resolution(starting_turn_player)

func initialize_new_strike(performing_player : Player, opponent_sets_first : bool):
	active_strike = Strike.new()
	active_strike.effects_resolved_in_timing = 0

	strike_happened_this_turn = true

	active_strike.opponent_sets_first = opponent_sets_first
	for jingle_reset_player in [player, opponent]:
		jingle_reset_player.jinglechunshui_character_power_mod = 0
		jingle_reset_player.jinglechunshui_character_speed_mod = 0
		jingle_reset_player.jinglechunshui_choose_first = false
		jingle_reset_player.jinglechunshui_yangui_reveal_ids.clear()
		jingle_reset_player.soifon_shunko_spent_this_strike = 0
	if opponent_sets_first:
		active_strike.strike_state = StrikeState.StrikeState_Defender_SetFirst
	else:
		active_strike.strike_state = StrikeState.StrikeState_Initiator_SetEffects

	player.strike_stat_boosts.clear()
	opponent.strike_stat_boosts.clear()
	player.bonus_actions = 0
	opponent.bonus_actions = 0
	dongshilang_cross_count_this_strike[player.my_id] = 0
	dongshilang_cross_count_this_strike[opponent.my_id] = 0
	dongshilang_move_limit_remaining_this_strike[player.my_id] = -1
	dongshilang_move_limit_remaining_this_strike[opponent.my_id] = -1
	dongshilang_convert_advance_to_retreat_this_strike[player.my_id] = false
	dongshilang_convert_advance_to_retreat_this_strike[opponent.my_id] = false

	active_strike.starting_distance = player.distance_to_opponent()

	player.zsolt_war_symphony_drew = false
	opponent.zsolt_war_symphony_drew = false

	active_strike.initiator = performing_player
	active_strike.defender = _get_player(get_other_player(performing_player.my_id))
	_discard_reese_valiant_guardian_on_opponent_strike(active_strike.defender)

	performing_player.renea_facedown_revealed = false
	var other_p = _get_player(get_other_player(performing_player.my_id))
	other_p.renea_facedown_revealed = false

func _discard_reese_valiant_guardian_on_opponent_strike(reese_player : Player):
	if reese_player.deck_def.get("id") != "reese":
		return
	for boost_card in reese_player.continuous_boosts.duplicate():
		if boost_card.definition.get("id") == "reese_valiantguardian":
			var card_name = card_db.get_card_name(boost_card.id)
			_append_log_full(Enums.LogType.LogType_CardInfo, reese_player, "弃置加成牌%s。" % _log_card_name(card_name))
			reese_player.remove_from_continuous_boosts(boost_card)

func _renea_reveal_facedown(renea_player : Player):
	if renea_player.deck_def.get("id") != "renea":
		return
	# Guard: already revealed in this strike via pre-strike path
	if renea_player.renea_facedown_revealed:
		return
	# Use pending order if set, otherwise collect only boosts with Now effects.
	var renea_fd_list = []
	var renea_from_pending = renea_player.renea_fd_pending.size() > 0
	if renea_player.renea_fd_pending.size() > 0:
		var renea_pending = renea_player.renea_fd_pending
		for renea_pid in renea_pending:
			for renea_bc in renea_player.continuous_boosts:
				if renea_bc.id == renea_pid and _renea_boost_has_now_effect(renea_bc):
					renea_fd_list.append(renea_bc)
					break
		renea_player.renea_fd_pending = []
	else:
		for renea_bc in renea_player.continuous_boosts:
			if renea_bc.definition.get("boost") and renea_bc.definition["boost"].get("facedown") and _renea_boost_has_now_effect(renea_bc):
				renea_fd_list.append(renea_bc)
	# Face up boosts without Now effects as part of the same reveal, but never
	# expose them as an effect-order choice.
	var renea_facedown_boosts = []
	for renea_bc in renea_player.continuous_boosts:
		if renea_bc.definition.get("boost") and renea_bc.definition["boost"].get("facedown"):
			renea_facedown_boosts.append(renea_bc)
	while renea_fd_list.size() > 0:
		# Skip order choice if coming from pending (order already chosen)
		if renea_fd_list.size() > 1 and not renea_from_pending and renea_player.my_id == Enums.PlayerId.PlayerId_Player:
			# Show order choice
			var order_choices = []
			for renea_oi in range(renea_fd_list.size()):
				var renea_ob = renea_fd_list[renea_oi]
				var renea_od = ""
				for renea_oe in renea_ob.definition['boost'].get('effects', []):
					if renea_oe['timing'] == "now" and renea_od.is_empty():
						renea_od = renea_oe.get("override_description", "")
						if renea_od.is_empty():
							if renea_oe['effect_type'] == "choice" and renea_oe.has("choice"):
								var renea_sub = []
								for renea_ce in renea_oe["choice"]:
									var renea_ct = renea_ce.get("effect_type", "").capitalize()
									if renea_ce.has("amount"):
										renea_ct += " " + str(renea_ce["amount"])
									renea_sub.append(renea_ct)
								renea_od = " / ".join(renea_sub)
							else:
								renea_od = renea_oe.get("effect_type", "").capitalize()
								if renea_oe.has("amount"):
									renea_od += " " + str(renea_oe["amount"])
				order_choices.append({
					"effect_type": "renea_reveal_fd_do",
					"boost_idx": renea_oi,
					"_choice_text": renea_od if not renea_od.is_empty() else "Boost %d" % (renea_oi + 1)
				})
			change_game_state(Enums.GameState.GameState_PlayerDecision)
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_EffectChoice
			decision_info.player = renea_player.my_id
			decision_info.choice = order_choices
			decision_info.choice_card_id = -1
			decision_info.effect_type = "renea_reveal_fd_order"
			create_event(Enums.EventType.EventType_Strike_EffectChoice, renea_player.my_id, 0, "Reveal Order")
			return
		# Process the first boost
		var renea_bc = renea_fd_list[0]
		renea_fd_list.remove_at(0)
		var renea_be_list = renea_bc.definition['boost'].get('effects')
		var renea_fd_had_choice = false
		if renea_be_list:
			for renea_be in renea_be_list:
				if renea_be['timing'] == "now":
					do_effect_if_condition_met(renea_player, renea_bc.id, renea_be, null)
					if game_state == Enums.GameState.GameState_PlayerDecision:
						renea_fd_had_choice = true
						break
		renea_bc.definition["boost"].erase("facedown")
		_append_log_full(Enums.LogType.LogType_CardInfo, renea_player, "reveals their face-down boost.")
		create_event(Enums.EventType.EventType_RevealCard, renea_player.my_id, renea_bc.id)
		if renea_fd_had_choice:
			return
		if not renea_player.renea_facedown_revealed:
			renea_player.renea_facedown_revealed = true
	for renea_bc in renea_facedown_boosts:
		if renea_bc.definition.get("boost") and renea_bc.definition["boost"].get("facedown"):
			renea_bc.definition["boost"].erase("facedown")
			_append_log_full(Enums.LogType.LogType_CardInfo, renea_player, "reveals their face-down boost.")
			create_event(Enums.EventType.EventType_RevealCard, renea_player.my_id, renea_bc.id)
	if not renea_player.renea_facedown_revealed:
		renea_player.renea_facedown_revealed = true

func _renea_boost_has_now_effect(boost_card : GameCard) -> bool:
	var boost_definition = boost_card.definition.get("boost", {})
	for boost_effect in boost_definition.get("effects", []):
		if boost_effect.get("timing") == "now":
			return true
	return false

func _renea_reveal_all_facedown_boosts(renea_player : Player) -> void:
	for boost_card in renea_player.continuous_boosts:
		if boost_card.definition.get("boost", {}).get("facedown", false):
			boost_card.definition["boost"].erase("facedown")
			_append_log_full(Enums.LogType.LogType_Effect, renea_player, "reveals face-down boost.")
			create_event(Enums.EventType.EventType_RevealCard, renea_player.my_id, boost_card.id)

# Renea pre-strike: collect facedown effects into list, fire ForceStartStrike when done
func _renea_begin_pre_strike_reveal(renea_player : Player, needs_force_start_strike : bool = true, strike_response : bool = false):
	if renea_player.deck_def.get("id") != "renea":
		return
	active_character_action = true
	renea_player.renea_facedown_revealed = false
	renea_player.renea_pre_strike_needs_fss = needs_force_start_strike
	renea_player.renea_pre_strike_response = strike_response
	handle_strike_effect(-1, {"effect_type": "renea_pre_strike_reveal"}, renea_player)

func _renea_process_next(renea_player : Player):
	var idx = renea_player.renea_pre_strike_index
	var list = renea_player.renea_pre_strike_effects
	while idx < list.size():
		var item = list[idx]
		renea_player.renea_pre_strike_index = idx + 1
		# Erase facedown before processing
		var bc = null
		for c in renea_player.continuous_boosts:
			if c.id == item.card_id:
				bc = c
				break
		if bc and bc.definition.get("boost", {}).get("facedown", false):
			bc.definition["boost"].erase("facedown")
			_append_log_full(Enums.LogType.LogType_Effect, renea_player, "reveals face-down boost.")
			create_event(Enums.EventType.EventType_RevealCard, renea_player.my_id, bc.id)
		# Process the effect
		var ef = item.effect.duplicate()
		ef["card_id"] = item.card_id
		ef["character_effect"] = true
		do_effect_if_condition_met(renea_player, item.card_id, ef, null)
		if game_state == Enums.GameState.GameState_PlayerDecision:
			return  # Will resume via continue_player_action_resolution
		idx = renea_player.renea_pre_strike_index
		# After each effect, let player reorder the remaining ones
		var remaining = list.size() - idx
		if remaining > 1 and renea_player.my_id == Enums.PlayerId.PlayerId_Player:
			var renea_oc_choices = []
			for renea_oci in range(idx, list.size()):
				var renea_item = list[renea_oci]
				var renea_od = renea_item["effect"].get("override_description", "")
				if renea_od.is_empty():
					renea_od = renea_item["effect"].get("effect_type", "").capitalize()
					if renea_item["effect"].has("amount"):
						renea_od += " " + str(renea_item["effect"]["amount"])
				renea_oc_choices.append({
					"effect_type": "renea_fd_order_first",
					"pre_strike_idx": renea_oci,
					"_choice_text": renea_od
				})
			change_game_state(Enums.GameState.GameState_PlayerDecision)
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_EffectChoice
			decision_info.player = renea_player.my_id
			decision_info.choice = renea_oc_choices
			decision_info.choice_card_id = -1
			decision_info.effect_type = "renea_fd_order_pre_strike"
			create_event(Enums.EventType.EventType_Strike_EffectChoice, renea_player.my_id, 0, "Reveal Order")
			return
	# All done - fire ForceStartStrike (Minato pattern: return true skips continue_player_action_resolution)
	handle_strike_effect(-1, {"effect_type": "renea_pre_strike_done"}, renea_player)

func continue_setup_strike():
	if active_strike.strike_state == StrikeState.StrikeState_Initiator_SetEffects:
		# Renea (offensive): reveal face-down boosts, process their Now effects
		if not active_strike.initiator.renea_facedown_revealed:
			_renea_reveal_facedown(active_strike.initiator)
			if game_state == Enums.GameState.GameState_PlayerDecision:
				return
		var initiator_set_strike_effects = active_strike.initiator.get_set_strike_effects(active_strike.initiator_card)
		while active_strike.effects_resolved_in_timing < initiator_set_strike_effects.size():
			var effect = initiator_set_strike_effects[active_strike.effects_resolved_in_timing]
			do_effect_if_condition_met(active_strike.initiator, -1, effect, null)
			if game_state == Enums.GameState.GameState_PlayerDecision:
				return

			active_strike.effects_resolved_in_timing += 1

		# All effects resolved, move to next state.
		active_strike.effects_resolved_in_timing = 0
		if active_strike.initiator_wild_strike and active_strike.initiator.delayed_wild_strike:
			# Do the wild swing now.
			active_strike.initiator.wild_strike()
			if game_over:
				return

			create_event(
				Enums.EventType.EventType_Strike_Started,
				active_strike.initiator.my_id,
				active_strike.initiator_card.id,
				"",
				false,
				false
			)

		if active_strike.initiator.is_infused():
			create_event(
				Enums.EventType.EventType_MarkInfused,
				active_strike.initiator.my_id,
				active_strike.initiator_card.id)

		if active_strike.opponent_sets_first:
			begin_resolve_strike()
		else:
			var minato_otp_defender = active_strike.defender
			var minato_otp_has_outrun = false
			if minato_otp_defender.deck_def.get("id") == "minato":
				for minato_otp_tf in minato_otp_defender.transforms:
					if minato_otp_tf.definition.get("id") == "minato_flight_13":
						minato_otp_has_outrun = true
						break
			if minato_otp_has_outrun and not minato_otp_defender.minato_outrun_triggered_before_strike:
				minato_otp_defender.minato_outrun_triggered_before_strike = true
				handle_strike_effect(-1, {"effect_type": "minato_outrun_the_past", "minato_otp_sealed": 0}, minato_otp_defender)
				if game_state == Enums.GameState.GameState_PlayerDecision:
					return
			# Renea's defensive UA begins only after the initiator's card and
			# all of its set-strike effects have resolved.
			if active_strike.defender.deck_def.get("id") == "renea" and not active_strike.defender.renea_facedown_revealed:
				var renea_has_facedown_boost = false
				for renea_boost in active_strike.defender.continuous_boosts:
					if renea_boost.definition.get("boost", {}).get("facedown", false):
						renea_has_facedown_boost = true
						break
				if renea_has_facedown_boost:
					_renea_begin_pre_strike_reveal(active_strike.defender, false, true)
					return
			strike_setup_defender_response()

	elif active_strike.strike_state == StrikeState.StrikeState_Defender_SetFirst:
		# Renea (defensive): reveal face-down boosts before defender sets card
		if not active_strike.defender.renea_facedown_revealed:
			_renea_reveal_facedown(active_strike.defender)
			if game_state == Enums.GameState.GameState_PlayerDecision:
				return
		var minato_otp_defender = active_strike.defender
		var minato_otp_has_outrun = false
		if minato_otp_defender.deck_def.get("id") == "minato":
			for minato_otp_tf in minato_otp_defender.transforms:
				if minato_otp_tf.definition.get("id") == "minato_flight_13":
					minato_otp_has_outrun = true
					break
		if minato_otp_has_outrun and not minato_otp_defender.minato_outrun_triggered_before_strike:
			minato_otp_defender.minato_outrun_triggered_before_strike = true
			handle_strike_effect(-1, {"effect_type": "minato_outrun_the_past", "minato_otp_sealed": 0}, minato_otp_defender)
			if game_state == Enums.GameState.GameState_PlayerDecision:
				return
		# Opponent will set first; check for restrictions on what they can set
		strike_setup_defender_response()

	elif active_strike.strike_state == StrikeState.StrikeState_Defender_SetEffects:
		if active_strike.waiting_for_reading_response:
			return

		var defender_set_strike_effects = active_strike.defender.get_set_strike_effects(active_strike.defender_card)
		while active_strike.effects_resolved_in_timing < defender_set_strike_effects.size():
			var effect = defender_set_strike_effects[active_strike.effects_resolved_in_timing]
			do_effect_if_condition_met(active_strike.defender, -1, effect, null)
			if game_state == Enums.GameState.GameState_PlayerDecision:
				return
			active_strike.effects_resolved_in_timing += 1

		# All effects resolved, move to next state.
		active_strike.effects_resolved_in_timing = 0
		if active_strike.defender_wild_strike and active_strike.defender.delayed_wild_strike:
			# Do the wild swing now.
			active_strike.defender.wild_strike()
			if game_over:
				return

			create_event(
				Enums.EventType.EventType_Strike_Response,
				active_strike.defender.my_id,
				active_strike.defender_card.id,
				"",
				false,
				false
			)

		if active_strike.defender.is_infused():
			create_event(
				Enums.EventType.EventType_MarkInfused,
				active_strike.defender.my_id,
				active_strike.defender_card.id)

		if active_strike.opponent_sets_first:
			strike_setup_initiator_response()
		else:
			begin_resolve_strike()

func strike_setup_defender_response():
	active_strike.strike_state = StrikeState.StrikeState_Defender_SetEffects
	change_game_state(Enums.GameState.GameState_Strike_Opponent_Response)
	var ask_for_response = true
	decision_info.clear()
	if active_strike.defender.reading_card_id:
		# The Reading effect goes here and will either force the player to strike
		# with the named card or to reveal their hand.
		# Umina（非觉醒）还能从幻梦境设置同名卡作为响应，且手牌/幻梦境同名卡可自由选择设置哪一张。
		var reading_cards = active_strike.defender.get_reading_card_in_hand()
		var reading_set_aside_cards = []
		if active_strike.defender.deck_def.get("id") == "umina" and not active_strike.defender.exceeded:
			reading_set_aside_cards = active_strike.defender.get_reading_card_in_set_aside()

		var has_hand_card = len(reading_cards) > 0
		var has_set_aside_card = len(reading_set_aside_cards) > 0

		if has_hand_card or has_set_aside_card:
			change_game_state(Enums.GameState.GameState_PlayerDecision)
			var defender_id = active_strike.defender.my_id

			decision_info.type = Enums.DecisionType.DecisionType_ChooseSimultaneousEffect
			decision_info.player = defender_id
			decision_info.choice = []

			var reading_display_name = ""
			if has_hand_card:
				var reading_card = reading_cards[0]
				reading_display_name = reading_card.definition['display_name']
				var ex_card_id = -1
				if len(reading_cards) >= 2:
					ex_card_id = reading_cards[1].id

				decision_info.choice.append(
					{ "effect_type": StrikeEffects.StrikeResponseReading, "card_id": reading_card.id }
				)
				decision_info.choice.append(
					{ "effect_type": StrikeEffects.StrikeResponseReading, "card_id": reading_card.id, "ex_card_id": ex_card_id, "_choice_disabled": ex_card_id == -1 }
				)

				# Add potential overloads as options for EX
				var overload_options = {}
				if reading_card.definition['type'] == "normal":
					for card in active_strike.defender.hand:
						if card.definition['id'] not in overload_options and card.definition['boost']['boost_type'] == "overload":
							overload_options[card.definition['id']] = card
				for overload_option_id in overload_options:
					var overload_card = overload_options[overload_option_id]
					decision_info.choice.append(
						{ "effect_type": StrikeEffects.StrikeResponseReading, "card_id": reading_card.id, "ex_card_id": overload_card.id, "overload_name": overload_card.definition['display_name'] }
					)

			# Umina：幻梦境里的同名卡也可作为响应来源
			for sa_card in reading_set_aside_cards:
				if reading_display_name == "":
					reading_display_name = sa_card.definition['display_name']
				decision_info.choice.append(
					{ "effect_type": StrikeEffects.StrikeResponseReading, "card_id": sa_card.id, "from_set_aside": true, "override_description": "从幻梦境设置%s" % sa_card.definition['display_name'] }
				)

			# 手牌没有目标牌时，允许选择「展示手牌」
			if not has_hand_card:
				decision_info.choice.append(
					{ "effect_type": "umina_reading_reveal_hand", "override_description": "展示手牌" }
				)

			create_event(Enums.EventType.EventType_Strike_EffectChoice, defender_id, 0, "Reading", reading_display_name)
			active_strike.waiting_for_reading_response = true
			ask_for_response = false
		else:
			_append_log_full(Enums.LogType.LogType_Effect, active_strike.defender, "没有被指定的牌。")
			active_strike.defender.reveal_hand()
			if active_strike.initiator.force_opponent_respond_wild_swing():
				create_event(Enums.EventType.EventType_Strike_ForceWildSwing, active_strike.initiator.my_id, 0)
				_append_log_full(Enums.LogType.LogType_Effect, active_strike.defender, "被强制进行疯狂攻击。")
				do_strike(active_strike.defender, -1, true, -1, active_strike.opponent_sets_first)
				ask_for_response = false
	elif active_strike.initiator.force_opponent_respond_wild_swing():
		create_event(Enums.EventType.EventType_Strike_ForceWildSwing, active_strike.initiator.my_id, 0)
		_append_log_full(Enums.LogType.LogType_Effect, active_strike.defender, "被强制进行疯狂攻击。")
		do_strike(active_strike.defender, -1, true, -1, active_strike.opponent_sets_first)
		ask_for_response = false
	if ask_for_response:
		decision_info.player = active_strike.defender.my_id
		if active_strike.opponent_sets_first:
			create_event(Enums.EventType.EventType_Strike_OpponentSetsFirst_DefenderSet, active_strike.defender.my_id, 0)
		else:
			create_event(Enums.EventType.EventType_Strike_DoResponseNow, active_strike.defender.my_id, 0)

func strike_setup_initiator_response():
	active_strike.strike_state = StrikeState.StrikeState_Initiator_SetEffects
	change_game_state(Enums.GameState.GameState_WaitForStrike)
	var ask_for_response = true
	decision_info.clear()
	if active_strike.initiator.next_strike_random_gauge:
		decision_info.player = active_strike.initiator.my_id
		do_strike(active_strike.initiator, -1, false, -1, active_strike.opponent_sets_first)
		ask_for_response = false
	if ask_for_response:
		decision_info.player = active_strike.initiator.my_id
		create_event(Enums.EventType.EventType_Strike_OpponentSetsFirst_InitiatorSet, active_strike.initiator.my_id, 0)

func begin_resolve_strike():
	# Strike is beginning, setup has been completed.
	active_strike.in_setup = false
	# 京乐春水的普通技不受角色卡分配的威力／速度修正。
	for jingle_normal_player in [active_strike.initiator, active_strike.defender]:
		var jingle_normal_card = active_strike.get_player_card(jingle_normal_player)
		if jingle_normal_card and jingle_normal_card.definition.get("type") == "normal":
			jingle_normal_player.remove_power_bonus(jingle_normal_player.jinglechunshui_character_power_mod)
			jingle_normal_player.strike_stat_boosts.speed -= jingle_normal_player.jinglechunshui_character_speed_mod
			jingle_normal_player.jinglechunshui_character_power_mod = 0
			jingle_normal_player.jinglechunshui_character_speed_mod = 0
	for jingle_player in [active_strike.initiator, active_strike.defender]:
		if jingle_player.deck_def.get("id") != "jinglechunshui" or jingle_player.jinglechunshui_named_normal_powerups.is_empty():
			continue
		for strike_player in [active_strike.initiator, active_strike.defender]:
			var strike_card = active_strike.get_player_card(strike_player)
			if strike_card and strike_card.definition['id'] in jingle_player.jinglechunshui_named_normal_powerups:
				strike_player.add_power_bonus(jingle_player.jinglechunshui_named_normal_powerups.count(strike_card.definition['id']))
		jingle_player.jinglechunshui_named_normal_powerups.clear()
		jingle_player.jinglechunshui_alternating_names_remaining = 0
	# Reset effect source tracking - set_strike effects (e.g. Eugenia's pass) may have
	# set it, but cost payment discards should not trigger Eugenia's passive.
	_last_effect_source_player_id = -1

	# Handle known cards, don't include wild swings.
	# However, wild swings do get removed from known cards if they were being tracked
	# from having been put on top deck.
	if not active_strike.get_player_wild_strike(active_strike.initiator):
		active_strike.initiator.on_hand_remove_public_card(active_strike.initiator_card.id)
		if active_strike.initiator_ex_card != null:
			active_strike.initiator.on_hand_remove_public_card(active_strike.initiator_ex_card.id)
	else:
		active_strike.initiator.on_hand_removed_topdeck(active_strike.initiator_card.id)

	if not active_strike.get_player_wild_strike(active_strike.defender):
		active_strike.defender.on_hand_remove_public_card(active_strike.defender_card.id)
		if active_strike.defender_ex_card != null:
			active_strike.defender.on_hand_remove_public_card(active_strike.defender_ex_card.id)
	else:
		active_strike.defender.on_hand_removed_topdeck(active_strike.defender_card.id)

	active_strike.initiator.update_public_hand_if_deck_empty()
	active_strike.defender.update_public_hand_if_deck_empty()

	create_event(Enums.EventType.EventType_Strike_Reveal, active_strike.initiator.my_id, 0)
	var initiator_name = active_strike.initiator.name
	var defender_name = active_strike.defender.name
	var initiator_card = card_db.get_card_name(active_strike.initiator_card.id)
	var defender_card = card_db.get_card_name(active_strike.defender_card.id)
	var initiator_ex = ""
	if active_strike.initiator_ex_card != null:
		initiator_ex = "EX "
	var defender_ex = ""
	if active_strike.defender_ex_card != null:
		defender_ex = "EX "
	_append_log_full(Enums.LogType.LogType_Strike, null, "战斗展示：%s的%s%s vs %s的%s%s！" % [initiator_name, initiator_ex, initiator_card, defender_name, defender_ex, defender_card])

	# Umina Dreamlands stun immunity: applies when attacking with the Dreamlands card
	# (face attack path handled in do_strike; Shadow Chorus copy is handled on reveal copy)
	var umina_si_p = null
	if active_strike.initiator.deck_def.get("id") == "umina":
		umina_si_p = active_strike.initiator
	elif active_strike.defender.deck_def.get("id") == "umina":
		umina_si_p = active_strike.defender
	if umina_si_p != null and not umina_si_p.exceeded and umina_si_p.set_aside_cards.size() > 0:
		var umina_si_dream = umina_si_p.set_aside_cards[0]
		var umina_si_attack = active_strike.get_player_card(umina_si_p)
		if umina_si_attack != null and _is_spiraling_match(umina_si_dream.definition.get("id", ""), umina_si_attack):
			umina_si_p.strike_stat_boosts.stun_immunity = true
			_append_log_full(Enums.LogType.LogType_Effect, umina_si_p, "has stun immunity from Dreamlands!")
			create_event(Enums.EventType.EventType_Strike_CharacterEffect, umina_si_p.my_id, -1, "", {"character_effect": true, "override_description": "Stun Immune (Dreamlands)"})

	# Handle EX
	if active_strike.initiator_ex_card != null:
		active_strike.initiator.strike_stat_boosts.set_ex()
	if active_strike.defender_ex_card != null:
		active_strike.defender.strike_stat_boosts.set_ex()

	# Begin initial state
	active_strike.effects_resolved_in_timing = 0
	active_strike.strike_state = StrikeState.StrikeState_Initiator_RevealEffects
	active_strike.remaining_effect_list = get_all_effects_for_timing("on_strike_reveal", active_strike.initiator, active_strike.initiator_card)

	active_strike.initiator.did_strike_this_turn = true
	active_strike.defender.did_strike_this_turn = true

	# Clear any setup stuff.
	player.extra_effect_after_set_strike = null
	opponent.extra_effect_after_set_strike = null

	continue_resolve_strike()

func get_total_speed(check_player, ignore_swap : bool = false):
	if check_player.strike_stat_boosts.swap_power_speed and not ignore_swap:
		return get_total_power(check_player, true)

	if check_player.strike_stat_boosts.overwrite_total_speed:
		return check_player.strike_stat_boosts.overwritten_total_speed

	var check_card = active_strike.get_player_card(check_player)
	var bonus_speed = check_player.strike_stat_boosts.speed * check_player.strike_stat_boosts.speed_bonus_multiplier
	if check_player.strike_stat_boosts.speedup_by_spaces_modifier > 0:
		# Note: This does not interact with speed multipliers.
		# If a later character has that, it will need to be implemented.
		var empty_spaces_between = check_player.distance_to_opponent() - 1
		bonus_speed += empty_spaces_between * check_player.strike_stat_boosts.speedup_by_spaces_modifier
	if check_player.strike_stat_boosts.speedup_per_boost_modifier > 0:
		# same note on speed multipliers
		var boosts_in_play = check_player.get_boosts().size()
		if check_player.strike_stat_boosts.speedup_per_boost_modifier_all_boosts:
			var opposing_player = _get_player(get_other_player(check_player.my_id))
			boosts_in_play += opposing_player.get_boosts().size()
		if boosts_in_play > 0:
			bonus_speed += check_player.strike_stat_boosts.speedup_per_boost_modifier * boosts_in_play
	if check_player.strike_stat_boosts.passive_speedup_per_card_in_hand != 0:
		var hand_size = len(check_player.hand)
		bonus_speed += hand_size * check_player.strike_stat_boosts.passive_speedup_per_card_in_hand
	if check_player.strike_stat_boosts.speedup_per_unique_sealed_normals_modifier != 0:
		var unique_normals = check_player.get_sealed_count_of_type("normal", true)
		bonus_speed += unique_normals * check_player.strike_stat_boosts.speedup_per_unique_sealed_normals_modifier
	for boost_card in check_player.continuous_boosts:
		if boost_card.has_meta("minato_dd_count"):
			bonus_speed += int(boost_card.get_meta("minato_dd_count"))
	# Hand-gated "always-on" speed bonuses, evaluated live against the current
	# hand (e.g. Baiken's "3 or fewer cards in hand" effects).
	for entry in check_player.strike_stat_boosts.conditional_hand_speedups:
		if _hand_condition_met(check_player, entry):
			bonus_speed += entry.amount
	if check_player.deck_def.get("id") == "soifon":
		var soifon_speed_bonus = 1 if check_player.exceeded else 2
		if check_player.soifon_shunko_spent_this_strike >= 2:
			bonus_speed += soifon_speed_bonus
		if check_player.soifon_shunko_spent_this_strike >= 3:
			bonus_speed += soifon_speed_bonus
		if check_card and check_card.definition.get("id") == "soifon_takigoi":
			bonus_speed += check_player.soifon_shunko_spent_this_strike
	var speed = get_card_stat(check_player, check_card, 'speed') + bonus_speed
	if active_strike and active_strike.extra_attack_in_progress:
		# If an extra attack character has ways to get speed multipliers, deal with that then.
		speed -= active_strike.extra_attack_data.extra_attack_previous_attack_speed_bonus
	return speed

func strike_determine_order():
	# Determine activation
	var initiator_speed = get_total_speed(active_strike.initiator)
	var defender_speed = get_total_speed(active_strike.defender)
	active_strike.initiator_first = initiator_speed >= defender_speed
	_append_log_full(Enums.LogType.LogType_Strike, null, "%s的速度为%s，%s的速度为%s。" % [active_strike.initiator.name, initiator_speed, active_strike.defender.name, defender_speed])

func do_effect_if_condition_met(
	performing_player : Player,
	card_id : int,
	effect,
	local_conditions : LocalStrikeConditions,
	recorded_failed_effects = null
	):

	if 'skip_if_boost_sustained' in effect and effect['skip_if_boost_sustained']:
		if card_id in performing_player.sustained_boosts:
			return

	if _is_dynamic_hand_stat_effect(effect) or is_effect_condition_met(performing_player, effect, local_conditions):
		handle_strike_effect(card_id, effect, performing_player)
	elif 'negative_condition_effect' in effect:
		var negative_condition_effect = effect['negative_condition_effect']
		do_effect_if_condition_met(performing_player, card_id, negative_condition_effect, local_conditions)
	elif recorded_failed_effects != null:
		recorded_failed_effects.append(effect)
func _is_dynamic_hand_stat_effect(effect) -> bool:
	return effect.get("timing", "") == "during_strike" \
		and effect.get("condition", "") in ["max_cards_in_hand", "min_cards_in_hand"] \
		and effect.get("effect_type", "") in [StrikeEffects.Speedup, StrikeEffects.Armorup]

func is_effect_condition_met(performing_player : Player, effect, local_conditions : LocalStrikeConditions):
	var other_player = _get_player(get_other_player(performing_player.my_id))
	if "condition" in effect:
		var condition = effect['condition']
		if condition == "headshot":
			# 特遣队员（carcass）的「爆头」：命中时手牌数等于距离即触发。
			# 两种放宽由持续加成提供（成对设置/撤销）：
			#   EGIS 武器平台 → 相差 1 也算
			#   恶魔子弹      → 无条件（只需击中）
			if performing_player.headshot_unconditional > 0:
				return true
			var headshot_hand = performing_player.hand.size()
			var headshot_distance = performing_player.distance_to_opponent()
			if headshot_hand == headshot_distance:
				return true
			if performing_player.headshot_allow_off_by_one > 0 and abs(headshot_hand - headshot_distance) <= 1:
				return true
			return false
		elif condition == "initiated_strike":
			var initiated_strike = active_strike.initiator == performing_player
			return initiated_strike
		elif condition == "not_initiated_strike":
			var initiated_strike = active_strike.initiator == performing_player
			return not initiated_strike
		elif condition == "yuanliuzhai_has_burn":
			if performing_player.deck_def.get("id") != "yuanliuzhai":
				return false
			for pressure_card in performing_player.bleach_zone:
				if pressure_card.definition.get("type", "") in ["normal", "special", "ultra"]:
					return true
			return false
		elif condition == "not_moved_self_this_strike":
			return not performing_player.moved_self_this_strike
		elif condition == "opponent_not_moved_this_strike":
			return not other_player.moved_self_this_strike
		elif condition == "at_distance":
			# 当前与对手的距离恰好等于 condition_amount。
			# （特遣队员主行动「枪斗术」：敌人在距离 1 时击退 1）
			return performing_player.distance_to_opponent() == effect.get("condition_amount", 0)
		elif condition == "initiated_at_range":
			var range_min = effect['range_min']
			var range_max = effect['range_max']
			if active_strike.initiator != performing_player:
				return false

			# check each space that the opponent occupied
			var starting_distance = active_strike.starting_distance
			var other_size = other_player.get_size()
			for i in range(other_size):
				if starting_distance+i >= range_min and starting_distance+i <= range_max:
					return true
			return false
		elif condition == "initiated_after_moving":
			var initiated_strike = active_strike.initiator == performing_player
			var required_amount = effect['condition_amount']
			return initiated_strike and performing_player.pre_strike_movement >= required_amount
		elif condition == "moved_during_strike":
			var required_amount = effect['condition_amount']
			return performing_player.spaces_moved_this_strike >= required_amount
		elif condition == "moved_past_this_strike":
			return performing_player.moved_past_this_strike
		elif condition == "was_moved_during_strike":
			var required_amount = effect['condition_amount']
			return performing_player.spaces_forced_moved_this_strike >= required_amount
		elif condition == "opponent_was_moved_during_strike":
			var required_amount = effect['condition_amount']
			return other_player.spaces_forced_moved_this_strike >= required_amount
		elif condition == "opponent_moved_or_was_moved":
			var required_amount = effect['condition_amount']
			return other_player.spaces_moved_or_forced_this_strike >= required_amount
		elif condition == "initiated_face_up":
			var initiated_strike = active_strike.initiator == performing_player
			return initiated_strike and active_strike.initiator_set_face_up
		elif condition == "is_normal_attack":
			return active_strike.get_player_card(performing_player).definition['type'] == "normal"
		elif condition == "deck_not_empty":
			return performing_player.deck.size() > 0
		elif condition == "top_deck_is_normal_attack":
			if performing_player.deck.size() > 0:
				return performing_player.deck[0].definition['type'] == "normal"
			return false
		elif condition == "is_buddy_special_or_ultra_attack":
			var buddy_id = ""
			if 'condition_buddy_id' in effect:
				buddy_id = effect['condition_buddy_id']
			var attack_type = active_strike.get_player_card(performing_player).definition['type']
			return performing_player.is_buddy_in_play(buddy_id) and (attack_type == "special" or attack_type == "ultra")
		elif condition == "is_special_attack":
			return active_strike.get_player_card(performing_player).definition['type'] == "special"
		elif condition == "is_special_or_dongshilang_longxianjia_attack":
			var attack_card = active_strike.get_player_card(performing_player)
			var special = attack_card.definition['type'] == "special"
			var is_longxianjia = attack_card.definition.get("id", "") == "dongshilang_龙霰架"
			return special or is_longxianjia
		elif condition == "is_special_or_ultra_attack":
			var special = active_strike.get_player_card(performing_player).definition['type'] == "special"
			var ultra = active_strike.get_player_card(performing_player).definition['type'] == "ultra"
			return special or ultra
		elif condition == "opponent_is_special_attack":
			return active_strike.get_player_card(other_player).definition['type'] == "special"
		elif condition == "is_ex_strike":
			return active_strike.will_be_ex(performing_player)
		elif condition == "at_edge_of_arena":
			return performing_player.is_at_edge_of_arena()
		elif condition == "in_center_three_spaces":
			for space_offset in [-1, 0, 1]:
				if performing_player.is_in_location(Enums.CenterArenaLocation + space_offset):
					return true
			return false
		elif condition == "opponent_in_center_three_spaces":
			for space_offset in [-1, 0, 1]:
				if other_player.is_in_location(Enums.CenterArenaLocation + space_offset):
					return true
			return false
		elif condition == "attack_still_in_play":
			var card = active_strike.get_player_card(performing_player)
			return card in active_strike.cards_in_play
		elif condition == "attacks_match_printed_speed":
			var card = active_strike.get_player_card(performing_player)
			var opposing_card = active_strike.get_player_card(other_player)
			var card_speed = card.definition['speed']
			var opposing_speed = opposing_card.definition['speed']
			if typeof(card_speed) != typeof(opposing_speed):
				return false
			return str(card_speed) == str(opposing_speed)
		elif condition == "opponent_printed_speed_greater":
			var card = active_strike.get_player_card(performing_player)
			var opposing_card = active_strike.get_player_card(other_player)
			var card_speed = card.definition['speed']
			var opposing_speed = opposing_card.definition['speed']
			if typeof(card_speed) != typeof(opposing_speed):
				return false
			return card_speed < opposing_speed
		elif condition == "opponent_printed_speed_less":
			var card = active_strike.get_player_card(performing_player)
			var opposing_card = active_strike.get_player_card(other_player)
			var card_speed = card.definition['speed']
			var opposing_speed = opposing_card.definition['speed']
			if typeof(card_speed) != typeof(opposing_speed):
				return false
			return card_speed > opposing_speed
		elif condition == "boost_in_play":
			return performing_player.get_boosts().size() > 0
		elif condition == "no_boost_in_play":
			return performing_player.get_boosts().size() == 0
		elif condition == "canceled_this_turn":
			return performing_player.canceled_this_turn
		elif condition == "not_canceled_this_turn":
			return not performing_player.canceled_this_turn
		elif condition == "copy_of_attack_in_zones":
			var zones = effect["condition_zones"]
			var card = active_strike.get_player_card(performing_player)
			for zone in zones:
				if performing_player.has_card_name_in_zone(card, zone):
					return true
			return false
		elif condition == "has_card_with_range_to_opponent":
			for card in performing_player.hand:
				if performing_player.does_card_contain_range_to_opponent(card.id):
					return true
			return false
		elif condition == "has_transform":
			var required_card = effect.get("required_transform_card")
			for card in performing_player.transforms:
				if card.definition["id"] == required_card:
					return true
			return false
		elif condition == "has_any_transform":
			return performing_player.transforms.size() > 0
		elif condition == "used_character_action":
			if not performing_player.used_character_action:
				return false
			elif 'condition_details' in effect:
				var target_details = effect['condition_details']
				var matching_details = false
				for used_action in performing_player.used_character_action_details:
					if used_action[0] == target_details[0] and used_action[1] == target_details[1]:
						matching_details = true
						break
				return matching_details
			else:
				return true
		elif condition == "used_character_bonus":
			return performing_player.used_character_bonus
		elif condition == "not_used_character_bonus":
			return not performing_player.used_character_bonus
		elif condition == "boost_caused_start_of_turn_strike":
			return performing_player.start_of_turn_strike
		elif condition == "hit_opponent":
			if active_strike.extra_attack_in_progress:
				return active_strike.extra_attack_data.extra_attack_hit
			else:
				return active_strike.did_player_hit_opponent(performing_player)
		elif condition == "not_hit_opponent":
			if active_strike.extra_attack_in_progress:
				return not active_strike.extra_attack_data.extra_attack_hit
			else:
				return not active_strike.did_player_hit_opponent(performing_player)
		elif condition == "not_this_turn_was_strike":
			return not strike_happened_this_turn
		elif condition == "last_turn_was_strike":
			return last_turn_was_strike
		elif condition == "not_last_turn_was_strike":
			return not last_turn_was_strike
		elif condition == "life_equals":
			var amount = effect['condition_amount']
			return performing_player.life == amount
		elif condition == "life_equal_or_below":
			var amount = effect['condition_amount']
			return performing_player.life <= amount
		elif condition == "life_less_than_opponent":
			return performing_player.life < other_player.life
		elif condition == "did_end_of_turn_draw":
			return performing_player.did_end_of_turn_draw
		elif condition == "discarded_matches_attack_speed":
			var discarded_card_ids = effect['discarded_card_ids']
			assert(discarded_card_ids.size() == 1)
			var card = card_db.get_card(discarded_card_ids[0])
			var speed_of_discarded = get_card_stat(performing_player, card, 'speed')
			var attack_card = active_strike.get_player_card(performing_player)
			var printed_speed_of_attack = get_card_stat(performing_player, attack_card, 'speed')
			return speed_of_discarded == printed_speed_of_attack
		elif condition == "not_full_close":
			return not local_conditions.fully_closed
		elif condition == "moved_less_than":
			var amount = effect['condition_amount']
			return local_conditions.movement_amount < amount
		elif condition == "moved_at_least":
			var amount = effect['condition_amount']
			return local_conditions.movement_amount >= amount
		elif condition == "advanced_through":
			return local_conditions.advanced_through
		elif condition == "not_advanced_through":
			return not local_conditions.advanced_through
		elif condition == "advanced_through_buddy":
			return local_conditions.advanced_through_buddy
		elif condition == "not_advanced_through_buddy":
			return not local_conditions.advanced_through_buddy
		elif condition == "not_full_push":
			return not local_conditions.fully_pushed
		elif condition == "not_full_pull":
			return not local_conditions.fully_pulled
		elif condition == "pushed_min_spaces":
			return local_conditions.push_amount >= effect['condition_amount']
		elif condition == "pulled_past":
			return local_conditions.pulled_past
		elif condition == "exceeded":
			return performing_player.exceeded
		elif condition == "not_exceeded":
			return not performing_player.exceeded
		elif condition == "opponent_exceeded":
			return other_player.exceeded
		elif condition == "opponent_not_exceeded":
			return not other_player.exceeded
		elif condition == "max_cards_in_gauge":
			var amount = effect['condition_amount']
			return performing_player.gauge.size() <= amount
		elif condition == "max_cards_in_hand":
			var amount = effect['condition_amount']
			return performing_player.hand.size() <= amount
		elif condition == "opponent_max_cards_in_hand":
			var amount = effect['condition_amount']
			return other_player.hand.size() <= amount
		elif condition == "fewer_cards_in_hand":
			return performing_player.hand.size() < other_player.hand.size()
		elif condition == "player_exceeded":
			return performing_player.exceeded
		elif condition == "opponent_initiated_strike":
			return active_strike.initiator == other_player
		elif condition == "opponent_was_stunned_this_turn":
			return performing_player.opponent_was_stunned_this_turn
		elif condition == "matches_named_card":
			var player_card = active_strike.get_player_card(performing_player)
			return player_card.definition['id'] == effect['condition_card_id']
		elif condition == "min_cards_in_deck":
			var amount = effect['condition_amount']
			return performing_player.deck.size() >= amount
		elif condition == "min_cards_in_discard":
			var amount = effect['condition_amount']
			return performing_player.discards.size() >= amount
		elif condition == "min_cards_in_hand":
			var amount = effect['condition_amount']
			return performing_player.hand.size() >= amount
		elif condition == "more_cards_in_hand_than_opponent":
			return performing_player.hand.size() > other_player.hand.size()
		elif condition == "min_cards_in_gauge":
			var amount = effect['condition_amount']
			if effect.get("condition_opponent"):
				return other_player.gauge.size() >= amount
			else:
				return performing_player.gauge.size() >= amount
		elif condition == "min_spaces_behind_opponent":
			var amount = effect['condition_amount']
			var spaces_behind = 0
			# Default to assuming player is to the right and counting from left to right.
			var start = Enums.MinArenaLocation
			var direction = 1
			if performing_player.arena_location < other_player.arena_location:
				# Player to left.
				# Count starting from max and stop when you find the player.
				start = Enums.MaxArenaLocation
				direction = -1
			for i in range(start, other_player.arena_location, direction):
				if other_player.is_in_location(i):
					break
				spaces_behind += 1
			return spaces_behind >= amount
		elif condition == "manual_reshuffle":
			return local_conditions.manual_reshuffle
		elif condition == "less_cards_than_opponent":
			return performing_player.hand.size() < other_player.hand.size()
		elif condition == "more_cards_than_opponent":
			return performing_player.hand.size() > other_player.hand.size()
		elif condition == "moved_past":
			return performing_player.moved_past_this_strike
		elif condition == "no_strike_caused":
			return game_state != Enums.GameState.GameState_WaitForStrike
		elif condition == "no_strike_this_turn":
			return not performing_player.did_strike_this_turn
		elif condition == "during_strike":
			return active_strike != null
		elif condition == "stunned":
			return active_strike.is_player_stunned(performing_player)
		elif condition == "not_stunned":
			return not active_strike.is_player_stunned(performing_player)
		elif condition == "no_active_strike":
			return active_strike == null
		elif condition == "any_buddy_in_opponent_space":
			var buddies = performing_player.get_buddies_on_opponent()
			return buddies.size() > 0
		elif condition == "not_any_buddy_in_opponent_space":
			var buddies = performing_player.get_buddies_on_opponent()
			return buddies.size() == 0
		elif condition == "any_buddy_adjacent_opponent_space":
			var buddies = performing_player.get_buddies_adjacent_opponent()
			return buddies.size() > 0
		elif condition == "any_buddy_in_or_adjacent_opponent_space":
			var buddies = performing_player.get_buddies_on_opponent() + performing_player.get_buddies_adjacent_opponent()
			return buddies.size() > 0
		elif condition == "buddy_in_opponent_space":
			var buddy_id = ""
			if 'condition_buddy_id' in effect:
				buddy_id = effect['condition_buddy_id']
			if not performing_player.is_buddy_in_play(buddy_id):
				return false
			return other_player.is_in_location(performing_player.get_buddy_location(buddy_id))
		elif condition == "any_buddy_in_play":
			for buddy_location in performing_player.buddy_locations:
				if buddy_location != -1:
					return true
		elif condition == "buddy_in_play":
			var buddy_id = ""
			if 'condition_buddy_id' in effect:
				buddy_id = effect['condition_buddy_id']
			if 'condition_extra' in effect and effect['condition_extra'] == "buddy_not_entered_play_this_strike":
				# If the buddy just entered play, this condition fails.
				if buddy_id in performing_player.strike_stat_boosts.buddies_that_entered_play_this_strike:
					return false
			return performing_player.is_buddy_in_play(buddy_id)
		elif condition == "not_buddy_in_play":
			var buddy_id = ""
			if 'condition_buddy_id' in effect:
				buddy_id = effect['condition_buddy_id']
			return not performing_player.is_buddy_in_play(buddy_id)
		elif condition == "on_buddy_space":
			var buddy_id = ""
			if 'condition_buddy_id' in effect:
				buddy_id = effect['condition_buddy_id']
			if not performing_player.is_buddy_in_play(buddy_id):
				return false
			return performing_player.is_in_location(performing_player.get_buddy_location(buddy_id))
		elif condition == "opponent_on_buddy_space":
			var buddy_id = ""
			if 'condition_buddy_id' in effect:
				buddy_id = effect['condition_buddy_id']
			if not performing_player.is_buddy_in_play(buddy_id):
				return false
			return other_player.is_in_location(performing_player.get_buddy_location(buddy_id))
		elif condition == "opponent_in_boost_space":
			var this_boost_location = performing_player.get_boost_location(effect['card_id'])
			return other_player.is_in_location(this_boost_location)
		elif condition == "boost_space_unoccupied":
			var this_boost_location = performing_player.get_boost_location(effect['card_id'])
			return not performing_player.is_in_location(this_boost_location) and not other_player.is_in_location(this_boost_location)
		elif condition == "boost_is_at_specific_range":
			var this_boost_location = performing_player.get_boost_location(effect['card_id'])
			var amount = effect['condition_amount']
			return performing_player.is_in_range_of_location(this_boost_location, amount, amount)
		elif condition == "buddy_between_attack_source":
			var buddy_id = ""
			if 'condition_buddy_id' in effect:
				buddy_id = effect['condition_buddy_id']
			if not performing_player.is_buddy_in_play(buddy_id):
				return false

			var pos1 = performing_player.get_closest_occupied_space_to(other_player.arena_location)
			var pos2 = get_attack_origin(other_player, performing_player.arena_location)
			var buddy_pos = performing_player.get_buddy_location(buddy_id)
			if pos1 < pos2: # opponent is on the right
				return buddy_pos > pos1 and buddy_pos < pos2
			else: # opponent is on the left
				return buddy_pos > pos2 and buddy_pos < pos1
		elif condition == "buddy_between_opponent":
			var buddy_id = ""
			if 'condition_buddy_id' in effect:
				buddy_id = effect['condition_buddy_id']
			if not performing_player.is_buddy_in_play(buddy_id):
				return false

			var pos1 = performing_player.get_closest_occupied_space_to(other_player.arena_location)
			var pos2 = other_player.get_closest_occupied_space_to(performing_player.arena_location)

			var buddy_pos = performing_player.get_buddy_location(buddy_id)
			if pos1 < pos2: # opponent is on the right
				return buddy_pos > pos1 and buddy_pos < pos2
			else: # opponent is on the left
				return buddy_pos > pos2 and buddy_pos < pos1
		elif condition == "boost_space_between_opponent":
			var pos1 = performing_player.get_closest_occupied_space_to(other_player.arena_location)
			var pos2 = other_player.get_closest_occupied_space_to(performing_player.arena_location)

			var this_boost_location = performing_player.get_boost_location(effect['card_id'])
			if pos1 < pos2: # opponent is on the right
				return this_boost_location > pos1 and this_boost_location < pos2
			else: # opponent is on the left
				return this_boost_location > pos2 and this_boost_location < pos1
		elif condition == "opponent_between_buddy":
			var include_buddy_space = 'include_buddy_space' in effect and effect['include_buddy_space']
			if 'condition_buddy_id' in effect:
				var buddy_id = effect['condition_buddy_id']
				return performing_player.is_opponent_between_buddy(buddy_id, other_player, include_buddy_space)
			elif 'condition_any_of_buddy_ids' in effect:
				for buddy_id in effect['condition_any_of_buddy_ids']:
					if performing_player.is_opponent_between_buddy(buddy_id, other_player, include_buddy_space):
						return true
				return false
			else:
				# Use default buddy id.
				return performing_player.is_opponent_between_buddy("", other_player, include_buddy_space)
		elif condition == "opponent_buddy_in_range":
			var buddy_id = effect['condition_buddy_id']
			var require_not_immune = 'condition_extra' in effect and effect['condition_extra'] == "buddy_not_immune_to_flip"
			if not other_player.is_buddy_in_play(buddy_id):
				return false
			if require_not_immune and other_player.strike_stat_boosts.buddy_immune_to_flip:
				return false
			if not active_strike:
				return false
			var buddy_location = other_player.get_buddy_location(buddy_id)
			var attack_card = active_strike.get_player_card(performing_player)
			return is_location_in_range(performing_player, attack_card, buddy_location) or performing_player.is_in_location(buddy_location)
		elif condition == "boost_space_in_range_towards_opponent":
			if not active_strike:
				return false
			var this_boost_location = performing_player.get_boost_location(effect['card_id'])
			var attack_card = active_strike.get_player_card(performing_player)

			# Check if boost is toward the opponent
			var self_pos = get_attack_origin(performing_player, other_player.arena_location)
			var opponent_pos = other_player.get_closest_occupied_space_to(performing_player.arena_location)
			if self_pos < opponent_pos and self_pos > this_boost_location:
				return false
			elif self_pos > opponent_pos and self_pos < this_boost_location:
				return false

			return is_location_in_range(performing_player, attack_card, this_boost_location)
		elif condition == "buddy_space_unoccupied":
			var buddy_id = ""
			if 'condition_buddy_id' in effect:
				buddy_id = effect['condition_buddy_id']
			if not performing_player.is_buddy_in_play(buddy_id):
				return false

			var buddy_location = performing_player.get_buddy_location(buddy_id)
			if performing_player.is_in_location(buddy_location) or other_player.is_in_location(buddy_location):
				return false

			return true
		elif condition == "opponent_at_edge_of_arena":
			return other_player.is_at_edge_of_arena()
		elif condition == "opponent_at_location":
			var location = effect['condition_detail']
			return other_player.is_in_location(location)
		elif condition == "opponent_at_max_range":
			assert(active_strike)
			var max_range = get_total_max_range(performing_player)
			var origin = get_attack_origin(performing_player, other_player.arena_location)
			return other_player.is_in_range_of_location(origin, max_range, max_range)
		elif condition == "opponent_at_min_range":
			assert(active_strike)
			var min_range = get_total_min_range(performing_player)
			var origin = get_attack_origin(performing_player, other_player.arena_location)
			return other_player.is_in_range_of_location(origin, min_range, min_range)
		elif condition == "opponent_stunned":
			return active_strike.is_player_stunned(other_player)
		elif condition == "overdrive_empty":
			return performing_player.overdrive.size() == 0
		elif condition == "range":
			var amount = effect['condition_amount']
			var origin = get_attack_origin(performing_player, other_player.arena_location)
			return other_player.is_in_range_of_location(origin, amount, amount)
		elif condition == "range_from_self":
			var amount = effect['condition_amount']
			var origin = performing_player.get_closest_occupied_space_to(other_player.arena_location)
			return other_player.is_in_range_of_location(origin, amount, amount)
		elif condition == "range_greater_or_equal":
			var amount = effect['condition_amount']
			var origin = get_attack_origin(performing_player, other_player.arena_location)
			var farthest_point = other_player.get_furthest_edge_from(origin)
			var distance = abs(origin - farthest_point)
			return distance >= amount
		elif condition == "range_multiple":
			var min_amount = effect["condition_amount_min"]
			var max_amount = effect["condition_amount_max"]
			var origin = get_attack_origin(performing_player, other_player.arena_location)
			return other_player.is_in_range_of_location(origin, min_amount, max_amount)
		elif condition == "strike_x_greater_than":
			var amount = effect['condition_amount']
			return performing_player.strike_stat_boosts.strike_x > amount
		elif condition == "was_hit":
			return performing_player.strike_stat_boosts.was_hit
		elif condition == "was_not_hit":
			return not performing_player.strike_stat_boosts.was_hit
		elif condition == "was_wild_swing":
			if active_strike:
				var detail = effect.get("condition_detail", false)
				var ignore_if_invalid_by_choice = detail and detail == "ignore_if_invalid_by_choice"
				if local_conditions and ignore_if_invalid_by_choice and local_conditions.invalid_by_choice:
					return false
				return active_strike.get_player_wild_strike(performing_player)
			return false
		elif condition == "was_not_wild_swing":
			if active_strike:
				return not active_strike.get_player_wild_strike(performing_player)
			return false
		elif condition == "was_strike_from_gauge":
			return active_strike.get_player_strike_from_gauge(performing_player)
		elif condition == "was_set_from_boosts":
			return active_strike.get_player_set_from_boosts(performing_player)
		elif condition == "is_critical":
			return performing_player.strike_stat_boosts.critical
		elif condition == "is_not_critical":
			return not performing_player.strike_stat_boosts.critical
		elif condition == "is_infused":
			return performing_player.is_infused()
		elif condition == "is_not_infused":
			return not performing_player.is_infused()
		elif condition == "choose_cards_from_top_deck_action":
			return decision_info.action == effect["condition_details"]
		elif condition == "total_powerup_greater_or_equal":
			var amount = effect["condition_amount"]
			var positive_boosted_power = performing_player.strike_stat_boosts.power_positive_only
			return positive_boosted_power >= amount
		elif condition == "opponent_total_guard_greater_or_equal":
			var amount = effect["condition_amount"]
			var total_guard = get_total_guard(other_player)
			return total_guard >= amount
		elif condition == "no_sealed_copy_of_attack":
			var card_id = active_strike.get_player_card(performing_player).definition["id"]
			for sealed_card in performing_player.sealed:
				if sealed_card.definition["id"] == card_id:
					return false
			return true
		elif condition == "speed_greater_than":
			if effect['condition_amount'] == "OPPONENT_SPEED":
				return get_total_speed(performing_player) > get_total_speed(other_player)
			else:
				return get_total_speed(performing_player) > effect['condition_amount']
		elif condition == "opponent_speed_less_or_equal":
			return get_total_speed(other_player) <= effect['condition_amount']
		elif condition == "spent_gauge_this_strike":
			return performing_player.gauge_spent_this_strike > 0
		elif condition == "top_discard_is_continous_boost":
			var top_discard_card = performing_player.get_top_discard_card()
			if top_discard_card:
				return top_discard_card.definition['boost']['boost_type'] == "continuous"
			else:
				return false
		elif condition == "opponent_top_discard_is_special":
			var top_discard_card = other_player.get_top_discard_card()
			if top_discard_card:
				return top_discard_card.definition['type'] == "special"
			else:
				return false
		elif condition == "can_continuous_boost_from_gauge":
			return performing_player.can_boost_something(['gauge'], 'continuous')
		elif condition == "has_continuous_boost":
			return performing_player.continuous_boosts.size() > 0
		elif condition == "has_continuous_boost_attack":
			if performing_player.continuous_boosts.size() == 0:
				return false
			if not active_strike:
				return false
			var attack_card = active_strike.get_player_card(performing_player)
			return attack_card != null and attack_card.definition['type'] in ["special", "ultra"]
		elif condition == "min_continuous_boosts_attack":
			var amount = effect['condition_amount']
			if performing_player.continuous_boosts.size() < amount:
				return false
			if not active_strike:
				return false
			var attack_card = active_strike.get_player_card(performing_player)
			return attack_card != null and attack_card.definition['type'] in ["special", "ultra"]
		elif condition == "min_continuous_boosts":
			var amount = effect['condition_amount']
			return performing_player.continuous_boosts.size() >= amount
		elif condition == "pooky_gambling_normals":
			if not active_strike:
				return false
			if not performing_player.strike_stat_boosts.pooky_normals_get_bonus:
				return false
			var attack_card = active_strike.get_player_card(performing_player)
			return attack_card != null and attack_card.definition['type'] == "normal"
		elif condition == "min_gauge":
			var amount = effect['condition_amount']
			return performing_player.gauge.size() >= amount
		elif condition == "not_discarding_boost":
			return active_boost and not active_boost.discard_on_cleanup
		elif condition == "not_sustained":
			var boost_card_id = effect["condition_card_id"]
			for card_id in performing_player.sustained_boosts:
				var card = card_db.get_card(card_id)
				if card.definition['id'] == boost_card_id:
					return false
			return true
		elif condition == "discarded_copy_of_attack":
			var card = active_strike.get_player_card(performing_player)
			return performing_player.get_copy_in_discards(card.definition['id']) != -1
		elif condition == "no_discarded_copy_of_attack":
			var card = active_strike.get_player_card(performing_player)
			return card != null and performing_player.get_copy_in_discards(card.definition['id']) == -1
		elif condition == "copy_of_attack_in_deck":
			var card = active_strike.get_player_card(performing_player)
			if card == null:
				return false
			for deck_card in performing_player.deck:
				if deck_card.definition.get("id", "") == card.definition.get("id", ""):
					return true
			return false
		elif condition == "boost_in_play_or_parents":
			var boost_name = effect["condition_detail"]
			for card in performing_player.continuous_boosts:
				if card.definition['boost']['display_name'] == boost_name:
					return true
			var check_parent_boost = active_boost
			while check_parent_boost:
				if check_parent_boost.card.definition['boost']['display_name'] == boost_name:
					return true
				check_parent_boost = check_parent_boost.parent_boost
			return false
		elif condition == "same_card_as_boost_in_hand":
			assert(active_boost)
			return performing_player.is_card_in_hand_match_normals(active_boost.card)
		elif condition == "boosted_from_gauge":
			assert(active_boost)
			return active_boost.boosted_from_gauge
		elif condition == "has_once_per_game_resource":
			return performing_player.once_per_game_resource > 0
		else:
			assert(false, "Unimplemented condition")
		# Unmet condition
		return false
	return true



func wait_for_mid_strike_boost():
	return game_state == Enums.GameState.GameState_PlayerDecision and decision_info.type == Enums.DecisionType.DecisionType_BoostNow

func _add_source_player_id_to_effect_tree(effect, source_player_id):
	effect['_source_player_id'] = source_player_id
	if 'and' in effect:
		_add_source_player_id_to_effect_tree(effect['and'], source_player_id)
	if 'discard_effect' in effect:
		_add_source_player_id_to_effect_tree(effect['discard_effect'], source_player_id)
	if StrikeEffects.Choice in effect:
		for choice in effect[StrikeEffects.Choice]:
			_add_source_player_id_to_effect_tree(choice, source_player_id)

func _is_strike_initiation_effect(effect) -> bool:
	return effect['effect_type'] in [
		StrikeEffects.StartOfTurnStrike,
		StrikeEffects.Strike,
		StrikeEffects.StrikeEffectAfterSetting,
		StrikeEffects.StrikeEffectAfterOpponentSets,
		StrikeEffects.StrikeFaceup,
		StrikeEffects.StrikeFromGauge,
		StrikeEffects.StrikeFromSealed,
		StrikeEffects.StrikeOpponentSetsFirst,
		StrikeEffects.StrikeRandomFromGauge,
		StrikeEffects.StrikeWithDeusExMachina,
		StrikeEffects.StrikeWithEx,
		StrikeEffects.StrikeWithThisBoost,
		StrikeEffects.StrikeWild,
	]

func _is_blocked_strike_initiation_during_active_strike(effect) -> bool:
	if not _is_strike_initiation_effect(effect):
		return false
	# This queues an effect for the opponent's completed strike setup; it never
	# initiates a second strike while the current one is active.
	if effect['effect_type'] == StrikeEffects.StrikeEffectAfterOpponentSets:
		return false
	# Morathi's delayed wild swing resolves after set-strike effects finish, so it
	# remains legal while a strike is already in progress.
	if effect['effect_type'] == StrikeEffects.StrikeWild and effect.get("auto_delayed_strike", false):
		return false
	return true

func _skip_strike_initiation_during_active_strike(effect, performing_player : Player) -> bool:
	if not active_strike:
		return false
	if not _is_blocked_strike_initiation_during_active_strike(effect):
		return false
	_append_log_full(Enums.LogType.LogType_Effect, performing_player, "战斗中不能再次发起战斗，该效果被跳过。")
	return true

func _is_action_resolution_in_progress() -> bool:
	return active_start_of_turn_effects or active_end_of_turn_effects or active_overdrive or active_boost \
		or active_character_action or active_exceed or active_change_cards or active_prepare \
		or active_special_draw_effect or active_post_action_effect or active_strike or preparing_boost_info

func _disable_strike_initiation_choices_during_active_strike(choices):
	if not active_strike:
		return choices
	for choice in choices:
		if _is_blocked_strike_initiation_during_active_strike(choice):
			choice["_choice_disabled"] = true
	return choices

func _disable_choices_requiring_sealed_cards(choices, performing_player : Player):
	for choice in choices:
		if choice.get("requires_sealed_cards", false) and performing_player.sealed.is_empty():
			choice["_choice_disabled"] = true
	return choices

func _jingle_yangui_choices(reveal_player : Player, owner_id : int, stage : int) -> Array:
	var choices = []
	var hand_ids = []
	for hand_card in reveal_player.hand:
		hand_ids.append(hand_card.id)
	if hand_ids.size() <= 3:
		choices.append({"_choice_text":"展示全部手牌", "effect_type":StrikeEffects.JingleChunShuiYanguiPick, "owner_id":owner_id, "stage":stage, "reveal_ids":hand_ids})
		return choices
	for first in range(hand_ids.size() - 2):
		for second in range(first + 1, hand_ids.size() - 1):
			for third in range(second + 1, hand_ids.size()):
				var ids = [hand_ids[first], hand_ids[second], hand_ids[third]]
				var names = []
				for reveal_id in ids:
					names.append(card_db.get_card_name(reveal_id))
				choices.append({"_choice_text":"展示：%s" % ", ".join(names), "effect_type":StrikeEffects.JingleChunShuiYanguiPick, "owner_id":owner_id, "stage":stage, "reveal_ids":ids})
	return choices

func handle_strike_effect(card_id : int, effect, performing_player : Player):
	printlog("STRIKE: Handling effect %s" % [effect])
	var original_performing_player_id = performing_player.my_id
	if 'for_other_player' in effect:
		performing_player = _get_player(get_other_player(performing_player.my_id))
	# Track who caused this effect for discard source checking (e.g. Eugenia passive)
	_last_effect_source_player_id = effect.get('_source_player_id', performing_player.my_id)
	# Never accept -1 as the source: it means the snapshot was taken while no
	# effect source was set (e.g. a ChooseSimultaneousEffect created after the
	# PayCosts reset). The executing player is the correct source in that case.
	if _last_effect_source_player_id == -1:
		_last_effect_source_player_id = performing_player.my_id
	if 'for_other_player' in effect and performing_player.strike_stat_boosts.heiqiyihu_prevent_opponent_moving_me:
		# Target switching must not turn the opponent's forced move into
		# the protected player's own movement.
		_last_effect_source_player_id = effect.get("_source_player_id", original_performing_player_id)
	var virtual_guardian = _get_heiqiyihu_virtual_guardian(card_id)
	if not virtual_guardian.is_empty() and _is_strike_initiation_effect(effect):
		_append_log_full(Enums.LogType.LogType_Effect, performing_player, "守护不会再次发起战斗，该子效果被跳过。")
		# Keep the legal tail of this atomic effect, including a pending choice.
		if effect.get("and"):
			do_effect_if_condition_met(performing_player, card_id, effect["and"], null)
		return
	if _skip_strike_initiation_during_active_strike(effect, performing_player):
		return
	if 'character_effect' in effect and effect['character_effect']:
		performing_player.strike_stat_boosts.active_character_effects.append(effect)
		create_event(Enums.EventType.EventType_Strike_CharacterEffect, performing_player.my_id, card_id, "", effect)
	var local_conditions = LocalStrikeConditions.new()
	var performing_start = performing_player.arena_location
	var opposing_player : Player = _get_player(get_other_player(performing_player.my_id))
	var other_start = opposing_player.arena_location
	var buddy_start = performing_player.get_buddy_location()
	var and_handled_elsewhere = false
	var resolved_effect_type = effect['effect_type']
	if resolved_effect_type in [
		StrikeEffects.Advance, StrikeEffects.AdvanceInternal, StrikeEffects.Close, StrikeEffects.CloseInternal,
		StrikeEffects.Retreat, StrikeEffects.RetreatInternal, StrikeEffects.MoveToSpace, StrikeEffects.MoveToAnySpace
	] and performing_player._heiqiyihu_blocks_opponent_movement():
		# Stop opponent-owned self-movement before its internal conversion can
		# switch targets again; keep any legal tail of the original effect.
		resolved_effect_type = StrikeEffects.Pass
	var movement_source_id = effect.get("card_id", card_id)
	if resolved_effect_type in [StrikeEffects.Advance, StrikeEffects.AdvanceInternal, StrikeEffects.Retreat, StrikeEffects.Close, StrikeEffects.CloseInternal] \
			and movement_source_id in performing_player.yuanliuzhai_blocked_boost_ids:
		_append_log_full(Enums.LogType.LogType_Effect, performing_player, "威眠阻止了该加成的自身移动。")
		resolved_effect_type = StrikeEffects.Pass
	match resolved_effect_type:
		StrikeEffects.HeiqiyihuShunbuCrossed:
			performing_player.strike_stat_boosts.range_includes_opponent = true
			performing_player.strike_stat_boosts.ignore_guard = true
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "瞬步越过对手：对手视为在攻击距离内，无视霸体。")
		"heiqiyihu_prevent_opponent_moving_me":
			performing_player.strike_stat_boosts.heiqiyihu_prevent_opponent_moving_me = true
		StrikeEffects.HeiqiyihuExceedDraw:
			performing_player.heiqiyihu_skip_hand_limit_this_turn = true
			performing_player.draw(max(2, performing_player.bleach_zone.size() * 2))
		StrikeEffects.HeiqiyihuPullAdjacent:
			var adjacent_choices = []
			var adjacent_spaces = []
			for destination in [performing_player.arena_location - 1, performing_player.arena_location + 1]:
				if destination < Enums.MinArenaLocation or destination > Enums.MaxArenaLocation \
				or opposing_player.is_overlapping_opponent(destination):
					continue
				adjacent_spaces.append(destination)
				adjacent_choices.append({
					"effect_type": StrikeEffects.Pull,
					"amount": opposing_player.movement_distance_between(opposing_player.arena_location, destination),
					"_choice_text": "将对手拉近至你的%s侧（%s号格）" % [
						"左" if destination < performing_player.arena_location else "右", destination]
				})
			if not adjacent_choices.is_empty():
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect
				decision_info.player = performing_player.my_id
				decision_info.choice_card_id = card_id
				decision_info.effect_type = StrikeEffects.Pull
				decision_info.choice = adjacent_choices
				decision_info.limitation = adjacent_spaces
				create_event(Enums.EventType.EventType_ChooseArenaLocationForEffect, performing_player.my_id, 0)
		StrikeEffects.HeiqiyihuAddGuardian:
			var guardian_choices = [{
				"effect_type": StrikeEffects.HeiqiyihuGuardianSource, "source": "deck",
				"_choice_text": "将牌堆顶1张牌置入守护区"
			}]
			for hand_card in performing_player.hand:
				guardian_choices.append({
					"effect_type": StrikeEffects.HeiqiyihuGuardianSource, "source": "hand",
					"guardian_card_id": hand_card.id,
					"_choice_text": "将手牌「%s」置入守护区" % hand_card.definition["display_name"]
				})
			handle_strike_effect(card_id, {
				"effect_type": StrikeEffects.Choice, "choice": guardian_choices
			}, performing_player)
		StrikeEffects.HeiqiyihuGuardianSource:
			var guardian : GameCard
			if effect["source"] == "hand":
				guardian = card_db.get_card(effect["guardian_card_id"])
				performing_player.remove_card_from_hand(guardian.id, true, false)
			else:
				# Same empty-deck semantics as the confirmed threshold source.
				while performing_player.deck.is_empty() and not game_over:
					performing_player.reshuffle_discard(false)
				if game_over:
					return
				guardian = performing_player.deck[0]
				performing_player.remove_top_card_from_deck()
				performing_player.on_hand_removed_topdeck(guardian.id)
				performing_player.public_topdeck_id = -1
			performing_player.add_to_bleach(guardian)
		StrikeEffects.HeiqiyihuXuhuaPayment:
			handle_strike_effect(card_id, {
				"effect_type": StrikeEffects.ForceForEffect,
				"force_max": 2, "min_force": 0,
				"heiqiyihu_xuhua_payment": true,
				"per_force_effect": {
					"effect_type": StrikeEffects.Guardup, "amount": 1,
					"combine_multiple_into_one": true
				}
			}, performing_player)
		StrikeEffects.HeiqiyihuXuhuaRecover:
			_offer_heiqiyihu_xuhua_recovery(performing_player, card_id, "bleach")
		StrikeEffects.HeiqiyihuXuhuaRecoverCard:
			var paid_id = effect["paid_id"]
			var recovered_card = card_db.get_card(paid_id)
			performing_player.remove_card_from_discards(paid_id)
			if effect["destination"] == "bleach":
				performing_player.add_to_bleach(recovered_card)
				_offer_heiqiyihu_xuhua_recovery(performing_player, card_id, "gauge")
			else:
				performing_player.add_to_gauge(recovered_card)
				active_strike.heiqiyihu_xuhua_spent_ids.erase(card_id)
		StrikeEffects.HeiqiyihuGetsugaCleanup:
			# This is one atomic Cleanup item, not separately sortable effects.
			# Gauge means the actual zone, not every card usable as Gauge.
			performing_player.discard_hand()
			performing_player.discard_gauge()
			if not virtual_guardian.is_empty():
				_move_heiqiyihu_virtual_source(card_id, "bleach")
			elif performing_player.is_card_in_continuous_boosts(card_id):
				performing_player.remove_from_continuous_boosts(card_db.get_card(card_id), "bleach")
			performing_player.exceed()
		"heiqiyihu_huhuan_guardian":
			# Cost is queried dynamically; amplification reads the final valid
			# attack only after PayCosts, not this earlier set-strike marker.
			pass
		StrikeEffects.ActivateNonExceedOverdrive:
			performing_player.non_exceed_overdrive_active = true
		StrikeEffects.AddAttackEffect:
			var effect_to_add = effect['added_effect']
			var to_add_timing = effect['added_effect']['timing']
			# A during-strike passive copied after that timing has begun must take
			# effect immediately; otherwise queue it at its normal timing.
			if to_add_timing == 'during_strike' and active_strike and active_strike.strike_state >= StrikeState.StrikeState_DuringStrikeBonuses:
				handle_strike_effect(card_id, effect_to_add, performing_player)
			else:
				var current_timing = get_current_strike_timing()
				var is_current_timing_player = true
				if current_timing in ['before', 'hit', 'after', 'cleanup']:
					is_current_timing_player = get_current_strike_timing_player_id() == performing_player.my_id
				effect_to_add['card_id'] = card_id
				if current_timing == to_add_timing and is_current_timing_player:
					add_remaining_effect(effect_to_add)
				else:
					performing_player.strike_stat_boosts.added_attack_effects.append(effect_to_add)
		StrikeEffects.AddAttackTriggers:
			var card_ids = effect["discarded_card_ids"]
			var include_passive = effect.get("include_passive", false)
			add_attack_triggers(performing_player, card_ids, true, include_passive)
		StrikeEffects.AddBoostToGaugeOnStrikeCleanup:
			if card_id == -1:
				assert(false, "ERROR: Unimplemented path to add_boost_to_gauge_on_strike_cleanup")
			if not virtual_guardian.is_empty():
				if effect.get("not_immediate", false):
					virtual_guardian["strike_cleanup_destination"] = "gauge"
				else:
					_move_heiqiyihu_virtual_source(card_id, "gauge")
			elif 'not_immediate' in effect and effect['not_immediate']:
				var card = card_db.get_card(card_id)
				var card_name = card_db.get_card_name(card.id)
				performing_player.add_boost_to_gauge_on_strike_cleanup(card_id)
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "其加成牌%s将置入怒气。" % _log_card_name(card_name))
			else:
				# Most effects that use this expect it to be added to gauge immediately
				var card = card_db.get_card(card_id)
				var card_name = card_db.get_card_name(card.id)
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将加成牌%s加入怒气。" % _log_card_name(card_name))
				performing_player.remove_from_continuous_boosts(card, "gauge")
		StrikeEffects.AddBoostToGaugeOnMove:
			if card_id == -1:
				assert(false)
				printlog("ERROR: Unimplemented path to add_boost_to_gauge_on_move")
			performing_player.set_add_boost_to_gauge_on_move(card_id)
		StrikeEffects.AddBoostToOverdriveDuringStrikeImmediately:
			if card_id == -1:
				assert(false)
				printlog("ERROR: Unimplemented path to add_boost_to_overdrive_during_strike_immediately")
			var card = card_db.get_card(card_id)
			var card_name = card_db.get_card_name(card.id)
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将加成牌%s加入超载。" % _log_card_name(card_name))
			if not virtual_guardian.is_empty():
				_move_heiqiyihu_virtual_source(card_id, "overdrive")
			else:
				performing_player.remove_from_continuous_boosts(card, "overdrive")
		StrikeEffects.AddHandToGauge:
			performing_player.add_hand_to_gauge()
		StrikeEffects.AddOpponentStrikeToGauge:
			opposing_player.strike_stat_boosts.move_strike_to_opponent_gauge = true
			handle_strike_attack_immediate_removal(opposing_player)
		StrikeEffects.AddPassive:
			var passive_name = effect["passive"]
			if performing_player.passive_effects.get(passive_name):
				performing_player.passive_effects[passive_name] += 1
			else:
				performing_player.passive_effects[passive_name] = 1
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "现在%s。" % effect['description'])
		StrikeEffects.AddRecursiveChoiceForOpponent:
			var recursive_effect = effect["recursive_effect"].duplicate(true)
			for choice in recursive_effect[StrikeEffects.Choice]:
				if choice.get("recursive"):
					choice["per_card_effect"] = effect.duplicate(true)
			do_effect_if_condition_met(opposing_player, card_id, recursive_effect, null)
		StrikeEffects.AddSetAsideCardToDeck:
			var card_name = performing_player.get_set_aside_card(effect['id']).definition['display_name']
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将抽取被移出的牌%s。" % _log_card_name(card_name))
			performing_player.add_set_aside_card_to_deck(effect['id'])
		StrikeEffects.AddToSetAsideImmediately:
			var card_definition_id = effect['card_id']
			var card_def = CardDataManager.get_card(card_definition_id)
			if card_def:
				# 这张卡是「运行时新建」的（如 Eugenia 的 Wonderland 标记），必须注意三点：
				#  ① id 要用**可种子化**的随机数（get_random_int）—— 联机双方 seed 相同才算得出同一个 id；
				#     用全局 randi() 会让 host/client 拿到不同的 id（不同步，随后按 id 找卡就会崩）。
				#  ② owner 必须是拥有者玩家 id —— 传随机数会让 add_to_discards 里
				#     「不是我的一律交给对手」的分支两边都不匹配，互相转交造成无限递归崩溃。
				#  ③ 要带上卡组里同名的图集，否则这张卡在 UI 上没有图，显示为空白/黑白占位卡。
				var next_id = get_random_int() % 100000 + 1000000
				while card_db.id_exists(next_id):
					next_id += 1
				var image_atlas = performing_player.get_deck_image_atlas_for(card_definition_id)
				var new_card = GameCard.new(next_id, card_def, performing_player.my_id, image_atlas, 0)
				card_db.add_card(new_card)
				performing_player.add_to_set_aside(new_card)
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "adds %s to set-aside (Wonderland)." % _log_card_name(new_card.definition['display_name']))
		StrikeEffects.AddStrikeToGaugeAfterCleanup:
			if effect.get("allow_bleach_zone", false) and performing_player.has_bleach_zone() and performing_player.deck_def.get("id", "") != "dongshilang":
				var gauge_effect = effect.duplicate(true)
				gauge_effect.erase("allow_bleach_zone")
				handle_strike_effect(card_id, {
					"effect_type": StrikeEffects.Choice,
					StrikeEffects.Choice: [
						{ "_choice_text": "加入怒气区", "effect_type": gauge_effect["effect_type"] },
						{ "_choice_text": "加入%s" % performing_player.get_bleach_zone_name(), "effect_type": StrikeEffects.MoveStrikeToBleach }
					]
				}, performing_player)
			elif active_strike.extra_attack_in_progress:
				active_strike.extra_attack_data.extra_attack_always_go_to_gauge = true
			else:
				performing_player.strike_stat_boosts.always_add_to_gauge = true
		StrikeEffects.AddStrikeToOverdriveAfterCleanup:
			performing_player.strike_stat_boosts.always_add_to_overdrive = true
			handle_strike_attack_immediate_removal(performing_player)
		StrikeEffects.AddToGaugeBoostPlayCleanup:
			if not virtual_guardian.is_empty():
				virtual_guardian["boost_play_destination"] = "gauge"
			elif effect.get("allow_bleach_zone", false) and performing_player.has_bleach_zone() and performing_player.deck_def.get("id", "") != "dongshilang":
				handle_strike_effect(card_id, {
					"effect_type": StrikeEffects.Choice,
					StrikeEffects.Choice: [
						{ "_choice_text": "加入怒气区", "effect_type": StrikeEffects.AddToGaugeBoostPlayCleanup },
						{ "_choice_text": "加入%s" % performing_player.get_bleach_zone_name(), "effect_type": StrikeEffects.MoveBoostToBleachOnCleanup }
					]
				}, performing_player)
			else:
				if active_boost.card.definition['boost']['boost_type'] == "continuous":
					active_boost.discard_on_cleanup = true
				active_boost.cleanup_to_gauge_card_ids.append(card_id)
		StrikeEffects.AddToGaugeImmediately:
			if not virtual_guardian.is_empty():
				_move_heiqiyihu_virtual_source(card_id, "gauge")
			elif effect.get("allow_bleach_zone", false) and performing_player.has_bleach_zone() and performing_player.deck_def.get("id", "") != "dongshilang":
				handle_strike_effect(card_id, {
					"effect_type": StrikeEffects.Choice,
					StrikeEffects.Choice: [
						{ "_choice_text": "加入怒气区", "effect_type": StrikeEffects.AddToGaugeImmediately },
						{ "_choice_text": "加入%s" % performing_player.get_bleach_zone_name(), "effect_type": StrikeEffects.MoveBoostToBleachImmediately }
					]
				}, performing_player)
			else:
				var card = card_db.get_card(card_id)
				var card_name = card_db.get_card_name(card.id)
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将加成牌%s加入怒气。" % _log_card_name(card_name))
				performing_player.remove_from_continuous_boosts(card, "gauge")
		StrikeEffects.MoveBoostToBleachOnCleanup:
			if not virtual_guardian.is_empty():
				virtual_guardian["boost_play_destination"] = "bleach"
			else:
				active_boost.cleanup_to_bleach_card_ids.append(card_id)
		StrikeEffects.MoveBoostToBleachImmediately:
			if not virtual_guardian.is_empty():
				_move_heiqiyihu_virtual_source(card_id, "bleach")
			else:
				var bleach_card = card_db.get_card(card_id)
				performing_player.remove_from_continuous_boosts(bleach_card, "bleach")
		StrikeEffects.AddToGaugeImmediatelyMidStrikeUndoEffects:
			var card = card_db.get_card(card_id)
			var card_name = card_db.get_card_name(card.id)
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将加成牌%s加入怒气。" % _log_card_name(card_name))
			if not virtual_guardian.is_empty():
				_move_heiqiyihu_virtual_source(card_id, "gauge")
			else:
				performing_player.remove_from_continuous_boosts(card, "gauge")
		StrikeEffects.AddBottomDiscardToGauge:
			var amount = 1
			if 'amount' in effect:
				amount = effect['amount']

			var actual_amount = min(amount, len(performing_player.discards))
			if actual_amount > 0:
				var card_ids = []
				for i in range(0, actual_amount):
					card_ids.append(performing_player.discards[i].id)
				var card_names = card_db.get_card_names(card_ids)
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将其弃牌堆底部%s张牌加入怒气：%s。" % [amount, _log_card_name(card_names)])
				performing_player.add_top_discard_to_gauge(amount, true)
			else:
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "其弃牌堆中没有可加入怒气的牌。")
		StrikeEffects.AddBottomDiscardToHand:
			var amount = 1
			if 'amount' in effect:
				amount = effect['amount']

			var actual_amount = min(amount, len(performing_player.discards))
			if actual_amount > 0:
				var card_ids = []
				for i in range(0, actual_amount):
					card_ids.append(performing_player.discards[i].id)
				var card_names = card_db.get_card_names(card_ids)
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将其弃牌堆底部%s张牌加入手牌：%s。" % [amount, _log_card_name(card_names)])
				performing_player.add_top_discard_to_gauge(amount, true, "hand")
			else:
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "其弃牌堆中没有可加入手牌的牌。")
		StrikeEffects.AddTopDiscardToHand:
			var amount = 1
			if 'amount' in effect:
				amount = effect['amount']

			var actual_amount = min(amount, len(performing_player.discards))
			if actual_amount > 0:
				var card_ids = []
				for i in range(performing_player.discards.size() - 1, performing_player.discards.size() - 1 - actual_amount, -1):
					card_ids.append(performing_player.discards[i].id)
				var card_names = card_db.get_card_names(card_ids)
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将其弃牌堆顶部%s张牌加入手牌：%s。" % [amount, _log_card_name(card_names)])
				performing_player.add_top_discard_to_gauge(amount, false, "hand")
			else:
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "其弃牌堆中没有可加入手牌的牌。")
		StrikeEffects.AddTopDeckToBottom:
			performing_player.add_top_deck_to_bottom()
		StrikeEffects.AddTopDeckToGauge:
			var target_player = performing_player
			if 'opponent' in effect and effect['opponent']:
				target_player = opposing_player
			var amount = 1
			if 'amount' in effect:
				amount = effect['amount']
				if str(amount) == "num_discarded_card_ids":
					amount = len(effect['discarded_card_ids'])
				elif str(amount) == "force_spent_this_turn":
					amount = performing_player.total_force_spent_this_turn

			var actual_amount = min(amount, len(target_player.deck))
			if actual_amount > 0:
				var card_names = _card_list_to_string(target_player.deck.slice(0, actual_amount))
				_append_log_full(Enums.LogType.LogType_CardInfo, target_player, "将其牌库顶部%s张牌加入怒气：%s。" % [amount, _log_card_name(card_names)])
				target_player.add_top_deck_to_gauge(amount)
			else:
				_append_log_full(Enums.LogType.LogType_CardInfo, target_player, "其牌库中没有可加入怒气的牌。")
		StrikeEffects.AddTopDiscardToGauge:
			var amount = 1
			if 'amount' in effect:
				amount = effect['amount']

			var target_player = performing_player
			if effect.get("opponent"):
				target_player = opposing_player

			var actual_amount = min(amount, len(target_player.discards))
			if actual_amount > 0:
				var card_ids = []
				for i in range(target_player.discards.size() - 1, target_player.discards.size() - 1 - actual_amount, -1):
					card_ids.append(target_player.discards[i].id)
				var card_names = card_db.get_card_names(card_ids)
				_append_log_full(Enums.LogType.LogType_CardInfo, target_player, "将其弃牌堆顶部%s张牌加入怒气：%s。" % [amount, _log_card_name(card_names)])
				target_player.add_top_discard_to_gauge(amount)
			else:
				_append_log_full(Enums.LogType.LogType_CardInfo, target_player, "其弃牌堆中没有可加入怒气的牌。")
		StrikeEffects.AddTopDiscardToOverdrive:
			var amount = 1
			if 'amount' in effect:
				amount = effect['amount']

			var actual_amount = min(amount, len(performing_player.discards))
			if actual_amount > 0:
				var card_ids = []
				for i in range(performing_player.discards.size() - 1, -1, -1):
					card_ids.append(performing_player.discards[i].id)
				var card_names = card_db.get_card_names(card_ids)
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将其弃牌堆顶部%s张牌加入超载：%s。" % [amount, _log_card_name(card_names)])
				performing_player.add_top_discard_to_overdrive(amount)
			else:
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "其弃牌堆中没有可加入超载的牌。")
		StrikeEffects.Advance:
			if performing_player.strike_stat_boosts.convert_advance_to_close:
				var converted_close_effect = effect.duplicate(true)
				converted_close_effect["effect_type"] = StrikeEffects.Close
				handle_strike_effect(card_id, converted_close_effect, performing_player)
				and_handled_elsewhere = true
			elif _dongshilang_is_advance_converted_to_retreat(performing_player):
				var converted_retreat_effect = effect.duplicate(true)
				converted_retreat_effect["effect_type"] = StrikeEffects.Retreat
				handle_strike_effect(card_id, converted_retreat_effect, performing_player)
			else:
				decision_info.clear()
				decision_info.source = StrikeEffects.Advance
				decision_info.amount = effect['amount']
				decision_info.limitation = { 'and': null }
				if 'and' in effect:
					decision_info.limitation['and'] = effect['and']
					# and effect is handled by internal version
					and_handled_elsewhere = true

				var stop_on_space = -1
				if 'stop_on_buddy_space' in effect:
					var buddy_location = performing_player.get_buddy_location(effect['stop_on_buddy_space'])
					if buddy_location != performing_player.arena_location and buddy_location != opposing_player.arena_location:
						stop_on_space = buddy_location

				var effects = performing_player.get_character_effects_at_timing("on_advance_or_close")
				for sub_effect in effects:
					do_effect_if_condition_met(performing_player, -1, sub_effect, null)
				if game_state != Enums.GameState.GameState_PlayerDecision:
					var advance_effect = effect.duplicate()
					advance_effect['effect_type'] = StrikeEffects.AdvanceInternal
					advance_effect['stop_on_space'] = stop_on_space
					handle_strike_effect(card_id, advance_effect, performing_player)
		StrikeEffects.AdvanceInternal:
			var amount = effect['amount']
			if str(amount) == "strike_x":
				amount = performing_player.strike_stat_boosts.strike_x
			amount += performing_player.strike_stat_boosts.increase_movement_effects_by
			amount = _dongshilang_limit_requested_movement(performing_player, amount)

			var stop_on_space = -1
			if 'stop_on_space' in effect:
				stop_on_space = effect['stop_on_space']
			var previous_location = performing_player.arena_location
			performing_player.advance(amount, stop_on_space, effect.get('stop_after_passing_opponent', false))
			var new_location = performing_player.arena_location
			var advance_amount = abs(performing_start - new_location)
			_append_log_full(Enums.LogType.LogType_CharacterMovement, performing_player, "前进%s，从格子%s移动到%s。" % [str(amount), str(previous_location), str(new_location)])
			if (performing_start < other_start and new_location > other_start) or (performing_start > other_start and new_location < other_start):
				# The opponent's space doesn't count as one you move through
				advance_amount -= 1
				local_conditions.advanced_through = true
				handle_advanced_through(performing_player, opposing_player)
				_dongshilang_register_cross_during_strike(performing_player)
				performing_player.moved_past_this_strike = true
				if performing_player.strike_stat_boosts.range_includes_if_moved_past:
					performing_player.strike_stat_boosts.range_includes_opponent = true
					_append_log_full(Enums.LogType.LogType_Effect, performing_player, "前进穿过了对手，使其进入距离！")
			if ((performing_player.is_in_or_left_of_location(buddy_start, performing_start) and performing_player.is_in_or_right_of_location(buddy_start, new_location)) or
					(performing_player.is_in_or_right_of_location(buddy_start, performing_start) and performing_player.is_in_or_left_of_location(buddy_start, new_location))):
				local_conditions.advanced_through_buddy = true
			local_conditions.movement_amount = advance_amount
			_dongshilang_consume_movement_limit(performing_player, advance_amount)
			# Ulrik: increment move counters from continuous boosts
			for boost in performing_player.continuous_boosts:
				for boost_effect in boost.definition['boost']['effects']:
					if boost_effect.get('effect_type') == StrikeEffects.IncrementBonusMovePowerCounters:
						boost.set_meta('bonus_move_power_counters', boost.get_meta('bonus_move_power_counters', 0) + advance_amount * boost_effect.get('amount', 1))
					if boost_effect.get('effect_type') == StrikeEffects.IncrementBonusMoveArmorCounters:
						boost.set_meta('bonus_move_armor_counters', boost.get_meta('bonus_move_armor_counters', 0) + advance_amount * boost_effect.get('amount', 1))
		StrikeEffects.Armorup:
			var armorup_cond = effect.get("condition", "")
			var armorup_cond_amount = effect.get("condition_amount", -1)
			if effect.get("timing", "") == "during_strike" \
					and armorup_cond in ["max_cards_in_hand", "min_cards_in_hand"]:
				# Hand-gated "always-on" armor bonus: register it and let
				# get_total_armor evaluate it live against the current hand.
				_append_hand_conditional_if_absent(performing_player.strike_stat_boosts.conditional_hand_armorups, effect['amount'], armorup_cond, armorup_cond_amount)
			else:
				performing_player.strike_stat_boosts.armor += effect['amount']
				create_event(Enums.EventType.EventType_Strike_ArmorUp, performing_player.my_id, effect['amount'])
		StrikeEffects.ArmorupDamageDealt:
			# If Tenacious Mist can be used as an additional attack, this implementation will be incorrect for that case
			var damage_dealt = active_strike.get_damage_taken(opposing_player)
			performing_player.strike_stat_boosts.armor += damage_dealt
			create_event(Enums.EventType.EventType_Strike_ArmorUp, performing_player.my_id, damage_dealt)
		StrikeEffects.ArmorupBonusArmorCounters:
			# Armor from bonus_armor_counters is now calculated dynamically in get_total_armor.
			# This effect only creates the event for UI feedback.
			var counter_amount = performing_player.bonus_armor_counters
			if counter_amount > 0:
				create_event(Enums.EventType.EventType_Strike_ArmorUp, performing_player.my_id, counter_amount)
		StrikeEffects.PowerupBonusMovePowerCounters:
			# Power from card-level move counters is calculated dynamically in get_total_power.
			# This effect only creates the event for UI feedback.
			var power_counter_amount = 0
			for boost in performing_player.continuous_boosts:
				power_counter_amount += boost.get_meta('bonus_move_power_counters', 0)
			if power_counter_amount > 0:
				create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, power_counter_amount)
		StrikeEffects.ArmorupBonusMoveArmorCounters:
			# Armor from card-level move counters is calculated dynamically in get_total_armor.
			# This effect only creates the event for UI feedback.
			var armor_counter_amount = 0
			for boost in performing_player.continuous_boosts:
				armor_counter_amount += boost.get_meta('bonus_move_armor_counters', 0)
			if armor_counter_amount > 0:
				create_event(Enums.EventType.EventType_Strike_ArmorUp, performing_player.my_id, armor_counter_amount)
		StrikeEffects.ArmorupCurrentPower:
			var current_power = get_total_power(performing_player)
			performing_player.strike_stat_boosts.armor += current_power
			create_event(Enums.EventType.EventType_Strike_ArmorUp, performing_player.my_id, current_power)
		StrikeEffects.ArmorupTimesGauge:
			var amount = performing_player.gauge.size() * effect['amount']
			performing_player.strike_stat_boosts.armor += amount
			create_event(Enums.EventType.EventType_Strike_ArmorUp, performing_player.my_id, amount)
		StrikeEffects.ArmorupOpponentPerForceSpentThisTurn:
			var amount = performing_player.total_force_spent_this_turn * effect['amount']
			opposing_player.strike_stat_boosts.armor += amount
			create_event(Enums.EventType.EventType_Strike_ArmorUp, opposing_player.my_id, amount)
		StrikeEffects.ArmorupPerContinuousBoost:
			var amount = effect["amount"] * performing_player.get_boosts().size()
			performing_player.strike_stat_boosts.armor += amount
			create_event(Enums.EventType.EventType_Strike_ArmorUp, performing_player.my_id, amount)
		StrikeEffects.AttackCopyGaugeOrTransformBecomesEx:
			performing_player.strike_stat_boosts.attack_copy_gauge_or_transform_becomes_ex = true
		StrikeEffects.AttackDoesNotHit:
			var affected_player = performing_player
			if 'opponent' in effect and effect['opponent']:
				affected_player = opposing_player
			affected_player.strike_stat_boosts.attack_does_not_hit = true
			if 'hide_notice' not in effect or not effect['hide_notice']:
				create_event(Enums.EventType.EventType_Strike_AttackDoesNotHit, affected_player.my_id, card_id)
		StrikeEffects.AttackIncludesRange:
			performing_player.strike_stat_boosts.attack_includes_ranges.append(effect['amount'])
		StrikeEffects.AttackIsEx:
			performing_player.strike_stat_boosts.set_ex()
			create_event(Enums.EventType.EventType_Strike_ExUp, performing_player.my_id, card_id)
		StrikeEffects.BecomeWide:
			performing_player.extra_width = 1
			var new_form_string = "3 spaces wide"
			if 'description' in effect:
				new_form_string = effect['description']
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "现在为%s！" % new_form_string)
			create_event(Enums.EventType.EventType_BecomeWide, performing_player.my_id, 0, "", "Tinker Tank")
		StrikeEffects.BlockOpponentMove:
			_append_log_full(Enums.LogType.LogType_Effect, opposing_player, "被阻止移动。")
			# 来源卡记账：加成效果在战斗里是**按来源加成逐条收集**的（收集时写入 effect["card_id"]），
			# 而 handle_strike_effect 收到的 card_id 常常是本次攻击的那张牌。用来源卡记账，
			# 才能做到「某个来源离场只解除它自己那一条」：同一张加成里的
			# during_strike + now 两条 block 只记一次，两个不同来源各记一条。
			var block_source_id = effect["card_id"] if (effect is Dictionary and effect.has("card_id")) else card_id
			if block_source_id != -1 and block_source_id not in opposing_player.block_opponent_move_source_ids:
				opposing_player.block_opponent_move_source_ids.append(block_source_id)
			opposing_player.cannot_move = true
			create_event(Enums.EventType.EventType_BlockMovement, opposing_player.my_id, card_id)
		StrikeEffects.RemoveBlockOpponentMove:
			# 与记录同源（同样优先取 effect["card_id"]）；完全取不到来源信息时按整体解除处理。
			var unblock_ids = []
			if card_id != -1:
				unblock_ids.append(card_id)
			if effect is Dictionary and effect.has("card_id") and effect["card_id"] != -1 and not unblock_ids.has(effect["card_id"]):
				unblock_ids.append(effect["card_id"])
			if unblock_ids.is_empty():
				opposing_player.block_opponent_move_source_ids.clear()
			else:
				for unblock_id in unblock_ids:
					opposing_player.block_opponent_move_source_ids.erase(unblock_id)
			if opposing_player.block_opponent_move_source_ids.is_empty():
				_append_log_full(Enums.LogType.LogType_Effect, opposing_player, "不再被阻止移动。")
				opposing_player.cannot_move = false
		StrikeEffects.BlockOpponentAdvanceClose:
			_append_log_full(Enums.LogType.LogType_Effect, opposing_player, "不能前进或逼近。")
			opposing_player.cannot_advance_or_close = true
			create_event(Enums.EventType.EventType_BlockMovement, opposing_player.my_id, card_id)
		StrikeEffects.RemoveBlockOpponentAdvanceClose:
			_append_log_full(Enums.LogType.LogType_Effect, opposing_player, "可以再次前进和逼近。")
			opposing_player.cannot_advance_or_close = false
		StrikeEffects.BonusAction:
			# You cannot take bonus actions during a strike.
			if not active_strike:
				active_boost.action_after_boost = true
				performing_player.strike_action_disabled = false
		StrikeEffects.JingleChunShuiOfferGame:
			if not active_strike or performing_player.deck_def.get("id") != "jinglechunshui":
				return
			if performing_player.get_available_force() < 1:
				return
			handle_strike_effect(card_id, {
				"effect_type": StrikeEffects.ForceForEffect,
				"force_max": 1,
				"required": effect.get("required", false),
				"per_force_effect": {"effect_type": StrikeEffects.JingleChunShuiStatChoice, "owner_id": performing_player.my_id},
				"overall_effect": null
			}, performing_player)
		StrikeEffects.JingleChunShuiStatChoice:
			var jingle_owner = _get_player(effect.get("owner_id", performing_player.my_id))
			var chooser = jingle_owner
			if active_strike and active_strike.initiator != jingle_owner and not jingle_owner.jinglechunshui_choose_first:
				chooser = _get_player(get_other_player(jingle_owner.my_id))
			handle_strike_effect(card_id, {
				"effect_type": StrikeEffects.Choice,
				StrikeEffects.Choice: [
					{"_choice_text":"速度+1，威力-2", "effect_type":StrikeEffects.JingleChunShuiApplyStatChoice, "fast":true},
					{"_choice_text":"速度-1，威力+2", "effect_type":StrikeEffects.JingleChunShuiApplyStatChoice, "fast":false}
				]
			}, chooser)
		StrikeEffects.JingleChunShuiApplyStatChoice:
			var chooser_power = -2 if effect.get("fast", false) else 2
			var chooser_speed = 1 if effect.get("fast", false) else -1
			performing_player.add_power_bonus(chooser_power)
			performing_player.strike_stat_boosts.speed += chooser_speed
			performing_player.jinglechunshui_character_power_mod += chooser_power
			performing_player.jinglechunshui_character_speed_mod += chooser_speed
			opposing_player.add_power_bonus(-chooser_power)
			opposing_player.strike_stat_boosts.speed -= chooser_speed
			opposing_player.jinglechunshui_character_power_mod -= chooser_power
			opposing_player.jinglechunshui_character_speed_mod -= chooser_speed
		StrikeEffects.JingleChunShuiExceedMove:
			handle_strike_effect(card_id, {"effect_type":StrikeEffects.JingleChunShuiMove, "amount":2}, performing_player)
		StrikeEffects.JingleChunShuiMove:
			var move_choices = [{"_choice_text":"不移动","effect_type":StrikeEffects.Pass}]
			for move_amount in range(1, effect.get("amount", 1) + 1):
				move_choices.append({"_choice_text":"前进%s格" % move_amount,"effect_type":StrikeEffects.Advance,"amount":move_amount})
				move_choices.append({"_choice_text":"后退%s格" % move_amount,"effect_type":StrikeEffects.Retreat,"amount":move_amount})
			handle_strike_effect(card_id, {"effect_type":StrikeEffects.Choice,StrikeEffects.Choice:move_choices}, performing_player)
		StrikeEffects.JingleChunShuiIgnoreCharacterMods:
			performing_player.remove_power_bonus(performing_player.jinglechunshui_character_power_mod)
			performing_player.strike_stat_boosts.speed -= performing_player.jinglechunshui_character_speed_mod
			performing_player.jinglechunshui_character_power_mod = 0
			performing_player.jinglechunshui_character_speed_mod = 0
		StrikeEffects.JingleChunShuiDoubleCharacterMods:
			performing_player.add_power_bonus(performing_player.jinglechunshui_character_power_mod)
			performing_player.strike_stat_boosts.speed += performing_player.jinglechunshui_character_speed_mod
		StrikeEffects.JingleChunShuiPayGaugeMove:
			handle_strike_effect(card_id, {"effect_type":StrikeEffects.GaugeForEffect,"gauge_max":1,"required":false,"per_gauge_effect":null,"overall_effect":{"effect_type":StrikeEffects.JingleChunShuiMove,"amount":1}}, performing_player)
		StrikeEffects.JingleChunShuiSustainAttackForForce:
			handle_strike_effect(card_id, {"effect_type":StrikeEffects.ForceForEffect,"force_max":1,"required":false,"per_force_effect":null,"overall_effect":{"effect_type":StrikeEffects.BoostThisThenSustain}}, performing_player)
		StrikeEffects.JingleChunShuiYingguiSpeed:
			var jingle_speed = get_total_speed(performing_player)
			if jingle_speed < 4:
				performing_player.add_power_bonus(-2)
				performing_player.add_range_bonus(-1, 0)
			elif jingle_speed > 4:
				performing_player.add_range_bonus(0, 2)
		StrikeEffects.JingleChunShuiChooseFirst:
			performing_player.jinglechunshui_choose_first = true
		StrikeEffects.JingleChunShuiRemoveArmor:
			performing_player.strike_stat_boosts.armor -= get_total_armor(performing_player)
		StrikeEffects.JingleChunShuiDrink:
			handle_strike_effect(card_id, {"effect_type":StrikeEffects.Choice,StrikeEffects.Choice:[{"_choice_text":"摸1张牌","effect_type":StrikeEffects.Draw,"amount":1,"and":{"effect_type":StrikeEffects.BonusAction}},{"_choice_text":"移动至多2格","effect_type":StrikeEffects.JingleChunShuiMove,"amount":2,"and":{"effect_type":StrikeEffects.BonusAction}}]}, performing_player)
		StrikeEffects.JingleChunShuiSplitChoice:
			handle_strike_effect(card_id, {"effect_type":StrikeEffects.Choice,StrikeEffects.Choice:[{"_choice_text":"移动至多4格","effect_type":StrikeEffects.JingleChunShuiSplitChoiceApply,"move_first":true},{"_choice_text":"摸2张牌","effect_type":StrikeEffects.JingleChunShuiSplitChoiceApply,"move_first":false}]}, performing_player)
		StrikeEffects.JingleChunShuiSplitChoiceApply:
			if effect.get("move_first", false):
				handle_strike_effect(card_id, {"effect_type":StrikeEffects.JingleChunShuiMove,"amount":4}, performing_player)
				handle_strike_effect(card_id, {"effect_type":StrikeEffects.Draw,"amount":2}, opposing_player)
			else:
				handle_strike_effect(card_id, {"effect_type":StrikeEffects.Draw,"amount":2}, performing_player)
				handle_strike_effect(card_id, {"effect_type":StrikeEffects.JingleChunShuiMove,"amount":4}, opposing_player)
		StrikeEffects.JingleChunShuiBoostToTopdeck:
			var topdeck_boost = card_db.get_card(card_id)
			if topdeck_boost and performing_player.is_card_in_continuous_boosts(card_id):
				performing_player.remove_from_continuous_boosts(topdeck_boost, StrikeEffects.Strike)
				performing_player.add_to_top_of_deck(topdeck_boost, true)
		StrikeEffects.FiliaThinningShearsZeroOpponent:
			opposing_player.strike_stat_boosts.overwrite_total_power = true
			opposing_player.strike_stat_boosts.overwritten_total_power = 0
			opposing_player.strike_stat_boosts.overwrite_total_speed = true
			opposing_player.strike_stat_boosts.overwritten_total_speed = 0
			opposing_player.strike_stat_boosts.overwrite_total_armor = true
			opposing_player.strike_stat_boosts.overwritten_total_armor = 0
			opposing_player.strike_stat_boosts.overwrite_total_guard = true
			opposing_player.strike_stat_boosts.overwritten_total_guard = 0
			opposing_player.strike_stat_boosts.overwrite_range_to_invalid = true
		StrikeEffects.FiliaTrichobezoarMiddlePush:
			if performing_player.is_in_location(5):
				handle_strike_effect(card_id, { "effect_type": StrikeEffects.Push, "amount": 3 }, performing_player)
		StrikeEffects.FiliaHairballAdvance:
			var remaining = effect.get("remaining", 0)
			if remaining > 0:
				handle_strike_effect(card_id, {
					"effect_type": StrikeEffects.Choice,
					StrikeEffects.Choice: [
						{"_choice_text": "停止前进", "effect_type": StrikeEffects.Pass},
						{"_choice_text": "前进1格（剩余%s次）" % remaining, "effect_type": StrikeEffects.Advance, "amount": 1,
							"and": {"effect_type": StrikeEffects.FiliaHairballAdvance, "remaining": remaining - 1}}
					]
				}, performing_player)
		StrikeEffects.DoubleStoreSealedAttackCard:
			var stored_ids = effect.get("discarded_card_ids", [])
			if stored_ids.size() > 0:
				performing_player.double_sealed_attack_card_id = stored_ids[0]
		StrikeEffects.DoubleRevealSealedAttackCard:
			var sealed_id = performing_player.double_sealed_attack_card_id
			if sealed_id != -1 and active_strike:
				create_event(Enums.EventType.EventType_RevealCard, performing_player.my_id, sealed_id)
				var attack_card = active_strike.get_player_card(performing_player)
				if attack_card and card_db.are_same_card(attack_card.id, sealed_id):
					performing_player.strike_stat_boosts.set_ex()
					_append_log_full(Enums.LogType.LogType_Effect, performing_player, "展示的封印牌与攻击同名，攻击视为强力攻击！")
				else:
					performing_player.draw(1)
					_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "展示的封印牌与攻击不同名，摸1张牌。")
			performing_player.double_sealed_attack_card_id = -1
		StrikeEffects.DoubleExceedAfterSeal:
			var sealed_count = effect.get("discarded_card_ids", []).size()
			if sealed_count > 0:
				handle_strike_effect(card_id, {"effect_type":StrikeEffects.ChooseDiscard,"source":"discard","destination":"deck_noshuffle","amount":sealed_count,"amount_min":0,"limitation":"","discard_effect":{"effect_type":StrikeEffects.ShuffleDeck}}, performing_player)
		StrikeEffects.DoubleGainCrowdAndSetX:
			performing_player.double_crowd_tokens += 1
			performing_player.set_strike_x(performing_player.double_crowd_tokens * 2)
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "获得1个从众指示物（共%s个），X=%s。" % [performing_player.double_crowd_tokens, performing_player.double_crowd_tokens * 2])
		StrikeEffects.DoubleWalkingFleshMoves:
			var move_count = effect.get("discarded_card_ids", []).size()
			if move_count > 0:
				handle_strike_effect(card_id, {"effect_type":StrikeEffects.DoubleWalkingFleshMoveStep,"remaining":move_count}, performing_player)
		StrikeEffects.DoubleWalkingFleshMoveStep:
			var remaining_moves = effect.get("remaining", 0)
			if remaining_moves > 0:
				handle_strike_effect(card_id, {"effect_type":StrikeEffects.Choice,StrikeEffects.Choice:[
					{"_choice_text":"前进2格","effect_type":StrikeEffects.Advance,"amount":2,"and":{"effect_type":StrikeEffects.DoubleWalkingFleshMoveStep,"remaining":remaining_moves-1}},
					{"_choice_text":"后退2格","effect_type":StrikeEffects.Retreat,"amount":2,"and":{"effect_type":StrikeEffects.DoubleWalkingFleshMoveStep,"remaining":remaining_moves-1}}
				]}, performing_player)
		StrikeEffects.DoubleReplicaLugerChoice:
			handle_strike_effect(card_id, {"effect_type":StrikeEffects.Choice,StrikeEffects.Choice:[
				{"_choice_text":"+1威力；前进1或2格","effect_type":StrikeEffects.Powerup,"amount":1,"and":{"effect_type":StrikeEffects.Choice,StrikeEffects.Choice:[{"_choice_text":"前进1格","effect_type":StrikeEffects.Advance,"amount":1},{"_choice_text":"前进2格","effect_type":StrikeEffects.Advance,"amount":2}]}},
				{"_choice_text":"+1威力；距离1攻击无法击中你","effect_type":StrikeEffects.Powerup,"amount":1,"and":{"effect_type":StrikeEffects.DodgeAtRange,"range_min":1,"range_max":1}},
				{"_choice_text":"前进1格；距离1攻击无法击中你","effect_type":StrikeEffects.Advance,"amount":1,"and":{"effect_type":StrikeEffects.DodgeAtRange,"range_min":1,"range_max":1}},
				{"_choice_text":"前进2格；距离1攻击无法击中你","effect_type":StrikeEffects.Advance,"amount":2,"and":{"effect_type":StrikeEffects.DodgeAtRange,"range_min":1,"range_max":1}}
			]}, performing_player)
		StrikeEffects.DoubleIllusionCopyTopDiscard:
			if active_strike and performing_player.discards.size() > 0:
				var illusion_card = active_strike.get_player_card(performing_player)
				var top_discard = performing_player.get_top_discard_card()
				if illusion_card and top_discard:
					performing_player.double_illusion_original_definition = illusion_card.definition.duplicate(true)
					illusion_card.definition = top_discard.definition.duplicate(true)
					_append_log_full(Enums.LogType.LogType_Effect, performing_player, "假象视为弃牌堆顶的%s。" % _log_card_name(top_discard.id))
		StrikeEffects.ParasoulCaptureMissedAttack:
			var opponent_attack = active_strike.get_player_card(opposing_player) if active_strike else null
			if opponent_attack and opponent_attack in active_strike.cards_in_play and int(opponent_attack.definition.get("range_min", -1)) != -1:
				handle_strike_effect(card_id, {"effect_type":StrikeEffects.AddOpponentStrikeToGauge}, performing_player)
		StrikeEffects.ParasoulExceedGaugeMatch:
			var parasoul_attack = active_strike.get_player_card(performing_player) if active_strike else null
			if parasoul_attack:
				for gauge_card in performing_player.gauge:
					if gauge_card.definition.get("id") == parasoul_attack.definition.get("id"):
						performing_player.strike_stat_boosts.power += 1
						performing_player.strike_stat_boosts.speed += 1
						performing_player.strike_stat_boosts.armor += 1
						performing_player.strike_stat_boosts.guard += 1
						break
		StrikeEffects.ParasoulSetXToGauge:
			performing_player.set_strike_x(performing_player.gauge.size())
		StrikeEffects.ParasoulSetXToGaugeCapped:
			performing_player.set_strike_x(min(performing_player.gauge.size(), int(effect.get("amount", 7))))
		StrikeEffects.ParasoulSetSpeedToGaugeCapped:
			performing_player.strike_stat_boosts.overwrite_total_speed = true
			performing_player.strike_stat_boosts.overwritten_total_speed = min(performing_player.gauge.size(), int(effect.get("amount", 7)))
		StrikeEffects.ParasoulGainGaugeForDamage:
			var damage_dealt = active_strike.get_damage_taken(opposing_player) if active_strike else 0
			if damage_dealt > 0:
				handle_strike_effect(card_id, {"effect_type":StrikeEffects.ChooseDiscard,"source":"discard","destination":"gauge","amount":damage_dealt,"amount_min":0,"limitation":""}, performing_player)
		StrikeEffects.ParasoulWhiteEgretDanceRefill:
			performing_player.add_top_deck_to_gauge(effect.get("discarded_card_ids", []).size())
		StrikeEffects.ParasoulTakeOpponentTopDiscard:
			var take_count = min(int(effect.get("amount", 4)), opposing_player.discards.size())
			for i in range(take_count):
				var taken_card = opposing_player.discards.pop_back()
				performing_player.add_to_gauge(taken_card)
		StrikeEffects.ParasoulHellBrigadeBonus:
			var opponent_attack = active_strike.get_player_card(opposing_player) if active_strike else null
			if opponent_attack:
				for gauge_card in performing_player.gauge:
					if gauge_card.definition.get("id") == opponent_attack.definition.get("id"):
						performing_player.strike_stat_boosts.power += 1
						performing_player.strike_stat_boosts.stun_immunity = true
						break
		StrikeEffects.ParasoulAdvanceGaugeCount:
			handle_strike_effect(card_id, {"effect_type":StrikeEffects.Advance,"amount":performing_player.gauge.size()}, performing_player)
		StrikeEffects.JingleChunShuiYanguiReveal:
			handle_strike_effect(card_id, {"effect_type":StrikeEffects.Choice,StrikeEffects.Choice:[{"_choice_text":"双方展示手牌","effect_type":StrikeEffects.JingleChunShuiYanguiResolve},{"_choice_text":"不发动","effect_type":StrikeEffects.Pass}]}, performing_player)
		StrikeEffects.JingleChunShuiYanguiResolve:
			handle_strike_effect(card_id, {"effect_type":StrikeEffects.Choice,StrikeEffects.Choice:_jingle_yangui_choices(performing_player, performing_player.my_id, 0)}, performing_player)
		StrikeEffects.JingleChunShuiYanguiPick:
			performing_player.jinglechunshui_yangui_reveal_ids = effect.get("reveal_ids", []).duplicate()
			var yangui_owner = _get_player(effect.get("owner_id", performing_player.my_id))
			if effect.get("stage", 0) == 0:
				var yangui_opponent = _get_player(get_other_player(yangui_owner.my_id))
				handle_strike_effect(card_id, {"effect_type":StrikeEffects.Choice,StrikeEffects.Choice:_jingle_yangui_choices(yangui_opponent, yangui_owner.my_id, 1)}, yangui_opponent)
			else:
				var yangui_other = _get_player(get_other_player(yangui_owner.my_id))
				var my_normals = 0
				var their_normals = 0
				for reveal_id in yangui_owner.jinglechunshui_yangui_reveal_ids:
					if card_db.get_card(reveal_id).definition.get("type") == "normal": my_normals += 1
				for reveal_id in yangui_other.jinglechunshui_yangui_reveal_ids:
					if card_db.get_card(reveal_id).definition.get("type") == "normal": their_normals += 1
				if my_normals > their_normals:
					yangui_owner.strike_stat_boosts.ignore_armor = true
					yangui_owner.strike_stat_boosts.ignore_guard = true
				else:
					yangui_other.add_power_bonus(1)
		StrikeEffects.JingleChunShuiStrikeAfterSpecialBoost:
			if performing_player.deck_def.get("id") != "jinglechunshui" or performing_player.exceeded:
				return
			if not active_boost or active_boost.card.definition['type'] != "special":
				return
			handle_strike_effect(card_id, {
				"effect_type": StrikeEffects.Choice,
				StrikeEffects.Choice: [
					{ "effect_type": StrikeEffects.Strike },
					{ "effect_type": StrikeEffects.Pass }
				],
				"override_description": "加成结算后，你可以发起战斗。"
			}, performing_player)
		StrikeEffects.JingleChunShuiDrawAndStrikeAfterContinuousBoost:
			if performing_player.deck_def.get("id") != "jinglechunshui" or not performing_player.exceeded:
				return
			if not active_boost or active_boost.card.definition['boost']['boost_type'] != "continuous":
				return
			handle_strike_effect(card_id, { "effect_type": StrikeEffects.Draw, "amount": 1 }, performing_player)
			if game_over:
				return
			handle_strike_effect(card_id, {
				"effect_type": StrikeEffects.Choice,
				StrikeEffects.Choice: [
					{ "effect_type": StrikeEffects.Strike },
					{ "effect_type": StrikeEffects.Pass }
				],
				"override_description": "抽1张牌后，你可以发起战斗。"
			}, performing_player)
		StrikeEffects.JingleChunShuiTurnStartToll:
			var jingle_owner = performing_player if performing_player.deck_def.get("id") == "jinglechunshui" else opposing_player
			if jingle_owner.deck_def.get("id") != "jinglechunshui" or not jingle_owner.exceeded:
				return
			var toll_player = _get_player(active_turn_player)
			var available_force = toll_player.get_available_force()
			handle_strike_effect(card_id, {
				"effect_type": StrikeEffects.Choice,
				StrikeEffects.Choice: [
					{ "_choice_text": "弃置牌库顶4张", "_choice_disabled": toll_player.deck.size() < 4, "effect_type": StrikeEffects.JingleChunShuiTurnStartTollPay, "topdeck_amount": 4, "force_amount": 0 },
					{ "_choice_text": "弃置牌库顶2张并支付1能量", "_choice_disabled": toll_player.deck.size() < 2 or available_force < 1, "effect_type": StrikeEffects.JingleChunShuiTurnStartTollPay, "topdeck_amount": 2, "force_amount": 1 },
					{ "_choice_text": "支付2能量", "_choice_disabled": available_force < 2, "effect_type": StrikeEffects.JingleChunShuiTurnStartTollPay, "topdeck_amount": 0, "force_amount": 2 },
					{ "_choice_text": "受1伤害", "effect_type": StrikeEffects.TakeDamage, "amount": 1 }
				],
				"override_description": "支付2能量，否则受1伤害。每弃置牌库顶2张可支付1能量。"
			}, toll_player)
		StrikeEffects.JingleChunShuiTurnStartTollPay:
			var topdeck_amount = effect.get("topdeck_amount", 0)
			var force_amount = effect.get("force_amount", 0)
			if performing_player.deck.size() < topdeck_amount or performing_player.get_available_force() < force_amount:
				handle_strike_effect(card_id, { "effect_type": StrikeEffects.TakeDamage, "amount": 1 }, performing_player)
				return
			for _i in range(topdeck_amount):
				performing_player.discard_topdeck()
			performing_player.total_force_spent_this_turn += int(topdeck_amount / 2.0)
			if force_amount > 0:
				handle_strike_effect(card_id, {
					"effect_type": StrikeEffects.ForceForEffect,
					"force_max": force_amount,
					"required": true,
					"per_force_effect": null,
					"overall_effect": { "effect_type": StrikeEffects.Pass }
				}, performing_player)
		StrikeEffects.JingleChunShuiGaugeSpecialBoost:
			if performing_player.deck_def.get("id") != "jinglechunshui" or performing_player.exceeded or performing_player.life <= 2:
				return
			if not performing_player.can_boost_something(["gauge"], "special"):
				return
			performing_player.spend_life(2)
			_append_log_full(Enums.LogType.LogType_Health, performing_player, "支付2生命发动角色行动。")
			create_event(Enums.EventType.EventType_ForceStartBoost, performing_player.my_id, 0, "", ["gauge"], "special", false)
			change_game_state(Enums.GameState.GameState_PlayerDecision)
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_BoostNow
			decision_info.player = performing_player.my_id
			decision_info.valid_zones = ["gauge"]
			decision_info.limitation = "special"
			decision_info.ignore_costs = false
			performing_player.jinglechunshui_gauge_boost_pending = true
		StrikeEffects.JingleChunShuiPlayBujingdule:
			if performing_player.deck_def.get("id") != "jinglechunshui" or not active_strike:
				return
			if effect.has("play_card_id"):
				var play_card = card_db.get_card(effect['play_card_id'])
				if not play_card:
					return
				var card_in_source = (effect['source'] == "hand" and performing_player.is_card_in_hand(play_card.id)) \
					or (effect['source'] == "gauge" and performing_player.is_card_in_gauge(play_card.id)) \
					or (effect['source'] == "discard" and performing_player.is_card_in_discards(play_card.id))
				if play_card.definition['id'] != "jinglechunshui_bujingdule" or not card_in_source:
					return
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_BoostNow
				decision_info.player = performing_player.my_id
				decision_info.valid_zones = [effect['source']]
				decision_info.limitation = ""
				decision_info.ignore_costs = true
				performing_player.sustain_next_boost = true
				create_event(Enums.EventType.EventType_EffectDoBoost, performing_player.my_id, play_card.id)
				return
			var bujingdule_choices = []
			for zone_name in ["hand", "gauge", "discard"]:
				var zone_cards = performing_player.hand if zone_name == "hand" else (performing_player.gauge if zone_name == "gauge" else performing_player.discards)
				for zone_card in zone_cards:
					if zone_card.definition['id'] == "jinglechunshui_bujingdule":
						bujingdule_choices.append({ "_choice_text": "从%s打出不精独乐" % zone_name, "effect_type": StrikeEffects.JingleChunShuiPlayBujingdule, "play_card_id": zone_card.id, "source": zone_name })
			if bujingdule_choices.size() > 0:
				bujingdule_choices.append({ "_choice_text": "放弃", "effect_type": StrikeEffects.Pass })
				handle_strike_effect(card_id, { "effect_type": StrikeEffects.Choice, StrikeEffects.Choice: bujingdule_choices }, performing_player)
		StrikeEffects.JingleChunShuiChooseTwo:
			if performing_player.deck_def.get("id") != "jinglechunshui" or not active_strike:
				return
			handle_strike_effect(card_id, {
				"effect_type": StrikeEffects.Choice,
				"multiple_amount": 2,
				StrikeEffects.Choice: [
					{ "_choice_text": "抽1张牌", "effect_type": StrikeEffects.Draw, "amount": 1 },
					{ "_choice_text": "前进1", "effect_type": StrikeEffects.Advance, "amount": 1 },
					{ "_choice_text": "后退1", "effect_type": StrikeEffects.Retreat, "amount": 1 },
					{ "_choice_text": "对手选择弃1张", "effect_type": StrikeEffects.OpponentDiscardChoose, "amount": 1, "jinglechunshui_choose_two_continuation": true },
					{ "_choice_text": "+1威力", "effect_type": StrikeEffects.Powerup, "amount": 1 }
				]
			}, performing_player)
		StrikeEffects.JingleChunShuiYanguiNameNormal:
			if performing_player.deck_def.get("id") != "jinglechunshui" or not active_strike:
				return
			change_game_state(Enums.GameState.GameState_PlayerDecision)
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_ReadingNormal
			decision_info.effect_type = StrikeEffects.JingleChunShuiYanguiNameNormalInternal
			decision_info.choice_card_id = card_id
			decision_info.player = performing_player.my_id
			create_event(Enums.EventType.EventType_ReadingNormal, performing_player.my_id, 0)
		StrikeEffects.JingleChunShuiYanguiNameNormalInternal:
			if performing_player.deck_def.get("id") != "jinglechunshui" or not active_strike:
				return
			var named_yangui_card = card_db.get_card(effect['card_id'])
			var hand_size_before = opposing_player.hand.size()
			opposing_player.discard_matching_or_reveal(named_yangui_card.definition['id'])
			if opposing_player.hand.size() < hand_size_before:
				performing_player.add_power_bonus(3)
				performing_player.strike_stat_boosts.ignore_guard = true
		StrikeEffects.JingleChunShuiAlternatingNormals:
			if performing_player.deck_def.get("id") != "jinglechunshui" or active_strike:
				return
			performing_player.jinglechunshui_named_normal_powerups.clear()
			performing_player.jinglechunshui_alternating_names_remaining = 2
			change_game_state(Enums.GameState.GameState_PlayerDecision)
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_ReadingNormal
			decision_info.effect_type = StrikeEffects.JingleChunShuiAlternatingNormalsInternal
			decision_info.choice_card_id = card_id
			decision_info.player = performing_player.my_id
			create_event(Enums.EventType.EventType_ReadingNormal, performing_player.my_id, 0)
		StrikeEffects.JingleChunShuiAlternatingNormalsInternal:
			var alternating_owner = performing_player
			if alternating_owner.deck_def.get("id") != "jinglechunshui" or alternating_owner.jinglechunshui_alternating_names_remaining == 0:
				alternating_owner = opposing_player
			if alternating_owner.deck_def.get("id") != "jinglechunshui" or alternating_owner.jinglechunshui_alternating_names_remaining == 0:
				return
			alternating_owner.jinglechunshui_named_normal_powerups.append(card_db.get_card(effect['card_id']).definition['id'])
			alternating_owner.jinglechunshui_alternating_names_remaining -= 1
			if alternating_owner.jinglechunshui_alternating_names_remaining > 0:
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_ReadingNormal
				decision_info.effect_type = StrikeEffects.JingleChunShuiAlternatingNormalsInternal
				decision_info.choice_card_id = card_id
				decision_info.player = opposing_player.my_id
				create_event(Enums.EventType.EventType_ReadingNormal, opposing_player.my_id, 0)
			else:
				handle_strike_effect(card_id, { "effect_type": StrikeEffects.Strike }, alternating_owner)
		StrikeEffects.JingleChunShuiDiscardTopdeckForPower:
			if performing_player.deck_def.get("id") != "jinglechunshui" or not active_strike:
				return
			if effect.has("chosen_amount"):
				var chosen_amount = mini(effect['chosen_amount'], mini(effect.get("amount", 9), performing_player.deck.size()))
				for _i in range(chosen_amount):
					performing_player.discard_topdeck()
				performing_player.add_power_bonus(chosen_amount)
				return
			var discard_max = mini(effect.get("amount", 9), performing_player.deck.size())
			var discard_choices = []
			var discard_limits = []
			for discard_amount in range(discard_max + 1):
				discard_choices.append({ "effect_type": StrikeEffects.JingleChunShuiDiscardTopdeckForPower, "chosen_amount": discard_amount, "amount": effect.get("amount", 9) })
				discard_limits.append(discard_amount)
			change_game_state(Enums.GameState.GameState_PlayerDecision)
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_PickNumberFromRange
			decision_info.player = performing_player.my_id
			decision_info.choice_card_id = card_id
			decision_info.choice = discard_choices
			decision_info.amount_min = 0
			decision_info.amount = discard_max
			decision_info.limitation = discard_limits
			create_event(Enums.EventType.EventType_PickNumberFromRange, performing_player.my_id, 0)
		StrikeEffects.JingleChunShuiOnExceed:
			if performing_player.deck_def.get("id") != "jinglechunshui":
				return
			handle_strike_effect(card_id, { "effect_type": StrikeEffects.Draw, "amount": 1 }, performing_player)
			if game_over:
				return
			handle_strike_effect(card_id, { "effect_type": StrikeEffects.TakeDamage, "amount": 2, "nonlethal": true }, performing_player)
			handle_strike_effect(card_id, { "effect_type": StrikeEffects.TakeDamage, "amount": 2, "nonlethal": true }, opposing_player)
		StrikeEffects.JingleChunShuiBujingduleReturn:
			if performing_player.deck_def.get("id") != "jinglechunshui" or not active_strike:
				return
			handle_strike_effect(card_id, { "effect_type": StrikeEffects.AddTopDeckToGauge, "amount": 1 }, performing_player)
			performing_player.strike_stat_boosts.return_attack_to_hand = true
			handle_strike_attack_immediate_removal(performing_player)
		StrikeEffects.JingleChunShuiSlowestPlayerDamage:
			if performing_player.deck_def.get("id") != "jinglechunshui" or not active_strike:
				return
			var bujingdule_card = card_db.get_card(card_id)
			if not bujingdule_card:
				return
			var strike_instance_id = active_strike.get_instance_id()
			if bujingdule_card.get_meta("jinglechunshui_cleanup_strike_id", -1) == strike_instance_id:
				return
			bujingdule_card.set_meta("jinglechunshui_cleanup_strike_id", strike_instance_id)
			if performing_player.spaces_moved_this_strike < opposing_player.spaces_moved_this_strike:
				handle_strike_effect(card_id, { "effect_type": StrikeEffects.TakeDamage, "amount": 2 }, performing_player)
			elif opposing_player.spaces_moved_this_strike < performing_player.spaces_moved_this_strike:
				handle_strike_effect(card_id, { "effect_type": StrikeEffects.TakeDamage, "amount": 2 }, opposing_player)
		StrikeEffects.JingleChunShuiInvalidateIfOpponentDeckOverNine:
			if performing_player.deck_def.get("id") != "jinglechunshui" or not active_strike:
				return
			if opposing_player.deck.size() > 9:
				var current_card = active_strike.get_player_card(performing_player)
				if current_card and current_card.definition['display_name'] not in performing_player.cards_invalid_during_strike:
					performing_player.cards_invalid_during_strike.append(current_card.definition['display_name'])
					_append_log_full(Enums.LogType.LogType_Effect, performing_player, "%s无效，因此将改为疯狂攻击。" % _log_card_name(current_card.definition['display_name']))
		StrikeEffects.SoifonPayShunko:
			if performing_player.deck_def.get("id") != "soifon" or not active_strike or performing_player.bleach_zone.is_empty():
				return
			handle_strike_effect(card_id, {"effect_type":StrikeEffects.GaugeForEffect,"valid_zone":"bleach","gauge_max":mini(3, performing_player.bleach_zone.size()),"min_gauge":0,"can_pass":true,"allow_partial_gauge_selection":true,"per_gauge_effect":{"effect_type":StrikeEffects.Pass},"overall_effect":{"effect_type":StrikeEffects.SoifonApplyShunko}}, performing_player)
		StrikeEffects.SoifonApplyShunko:
			if performing_player.deck_def.get("id") == "soifon":
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "支付了%s张瞬哄。" % performing_player.soifon_shunko_spent_this_strike)
		StrikeEffects.SoifonShunkoBeforeMove:
			if performing_player.deck_def.get("id") == "soifon" and performing_player.soifon_shunko_spent_this_strike >= 2:
				handle_strike_effect(card_id, {"effect_type":StrikeEffects.SoifonMoveUpTo,"amount":1}, performing_player)
		StrikeEffects.SoifonShunkoHitMove:
			if performing_player.deck_def.get("id") == "soifon" and performing_player.soifon_shunko_spent_this_strike >= 1:
				handle_strike_effect(card_id, {"effect_type":StrikeEffects.Choice,StrikeEffects.Choice:[{"_choice_text":"不移动对手","effect_type":StrikeEffects.Pass},{"_choice_text":"击退1格","effect_type":StrikeEffects.Push,"amount":1},{"_choice_text":"拉近1格","effect_type":StrikeEffects.Pull,"amount":1}]}, performing_player)
		StrikeEffects.SoifonShunkoAfterDamage:
			if performing_player.deck_def.get("id") == "soifon" and active_strike and performing_player.distance_to_opponent() == 2:
				handle_strike_effect(card_id, {"effect_type":StrikeEffects.TakeDamage,"amount":2 if performing_player.exceeded else 1,"opponent":true,"does_not_stun":true}, performing_player)
		StrikeEffects.SoifonShunkoCleanup:
			if performing_player.deck_def.get("id") == "soifon" and performing_player.exceeded and performing_player.soifon_shunko_spent_this_strike >= 3:
				handle_strike_effect(card_id, {"effect_type":StrikeEffects.GainAdvantage}, performing_player)
		StrikeEffects.SoifonMoveUpTo:
			var soifon_move_choices = [{"_choice_text":"不移动","effect_type":StrikeEffects.Pass}]
			for soifon_move_amount in range(1, effect.get("amount", 1) + 1):
				soifon_move_choices.append({"_choice_text":"前进%s格" % soifon_move_amount,"effect_type":StrikeEffects.Advance,"amount":soifon_move_amount})
				soifon_move_choices.append({"_choice_text":"后退%s格" % soifon_move_amount,"effect_type":StrikeEffects.Retreat,"amount":soifon_move_amount})
			handle_strike_effect(card_id, {"effect_type":StrikeEffects.Choice,StrikeEffects.Choice:soifon_move_choices}, performing_player)
		StrikeEffects.SoifonAdvanceUpTo:
			var soifon_advance_choices = [{"_choice_text":"不前进","effect_type":StrikeEffects.Pass}]
			for soifon_advance_amount in range(1, effect.get("amount", 1) + 1):
				soifon_advance_choices.append({"_choice_text":"前进%s格" % soifon_advance_amount,"effect_type":StrikeEffects.Advance,"amount":soifon_advance_amount})
			handle_strike_effect(card_id, {"effect_type":StrikeEffects.Choice,StrikeEffects.Choice:soifon_advance_choices}, performing_player)
		StrikeEffects.SoifonRetreatUpTo:
			var soifon_retreat_choices = [{"_choice_text":"不后退","effect_type":StrikeEffects.Pass}]
			for soifon_retreat_amount in range(1, effect.get("amount", 1) + 1):
				soifon_retreat_choices.append({"_choice_text":"后退%s格" % soifon_retreat_amount,"effect_type":StrikeEffects.Retreat,"amount":soifon_retreat_amount})
			handle_strike_effect(card_id, {"effect_type":StrikeEffects.Choice,StrikeEffects.Choice:soifon_retreat_choices}, performing_player)
		StrikeEffects.SoifonNigekiHit:
			if performing_player.deck_def.get("id") != "soifon" or not active_strike:
				return
			var nigeki_card = active_strike.get_player_card(performing_player)
			handle_strike_effect(card_id, {"effect_type":StrikeEffects.GainAdvantage}, performing_player)
			if nigeki_card and performing_player.has_card_name_in_zone(nigeki_card, "sealed"):
				handle_strike_effect(card_id, {"effect_type":StrikeEffects.Powerup,"amount":4}, performing_player)
			performing_player.strike_stat_boosts.seal_attack_on_cleanup = true
			if not performing_player.deck.is_empty():
				handle_strike_effect(card_id, {"effect_type":StrikeEffects.Choice,StrikeEffects.Choice:[{"_choice_text":"加入瞬哄","effect_type":StrikeEffects.SoifonTopdeckToShunko},{"_choice_text":"加入怒气区","effect_type":StrikeEffects.SoifonTopdeckToGauge}]}, performing_player)
		StrikeEffects.SoifonTopdeckToShunko:
			if not performing_player.deck.is_empty():
				performing_player.add_to_bleach(performing_player.deck.pop_front())
		StrikeEffects.SoifonTopdeckToGauge:
			if not performing_player.deck.is_empty():
				performing_player.add_to_gauge(performing_player.deck.pop_front())
		StrikeEffects.SoifonHankisousai:
			if not active_strike:
				return
			var soifon_attack = active_strike.get_player_card(performing_player)
			var soifon_opponent_attack = active_strike.get_player_card(opposing_player)
			# 反鬼相杀比较的是卡面印刷威力，不包含任何本次战斗加成。
			if soifon_attack and soifon_opponent_attack and int(soifon_attack.definition.get("power", 0)) == int(soifon_opponent_attack.definition.get("power", 0)):
				performing_player.strike_stat_boosts.attack_does_not_hit = true
				opposing_player.strike_stat_boosts.attack_does_not_hit = true
				if card_id not in performing_player.cleanup_boost_to_bleach_cards:
					performing_player.cleanup_boost_to_bleach_cards.append(card_id)
		"yuanliuzhai_discard_pressure":
			_yuanliuzhai_clear_pressure(performing_player, false)
		"yuanliuzhai_start_turn":
			if not performing_player.exceeded:
				_yuanliuzhai_clear_pressure(performing_player, true)
			performing_player.yuanliuzhai_pressure_protected_ids.clear()
		"yuanliuzhai_exceed_discard_pressure":
			var pressure_discarded = _yuanliuzhai_clear_pressure(performing_player, false)
			if pressure_discarded > 0:
				performing_player.draw(1)
		"yuanliuzhai_boost_to_pressure_if_empty":
			if performing_player.bleach_zone.is_empty() and active_boost:
				active_boost.cleanup_to_bleach_card_ids.append(card_id)
		"yuanliuzhai_jokaku_hit":
			handle_strike_effect(card_id, {"effect_type":StrikeEffects.GainAdvantage}, performing_player)
			performing_player.strike_stat_boosts.move_strike_to_bleach = true
			if active_strike:
				var jokaku = active_strike.get_player_card(performing_player)
				if jokaku and jokaku.id not in performing_player.yuanliuzhai_pressure_protected_ids:
					performing_player.yuanliuzhai_pressure_protected_ids.append(jokaku.id)
		"yuanliuzhai_ryujin_execute":
			if active_strike and active_strike.did_player_hit_opponent(performing_player) and opposing_player.life < 6:
				handle_strike_effect(card_id, {"effect_type":StrikeEffects.TakeDamage,"amount":99,"opponent":true}, performing_player)
		"yuanliuzhai_counter_cards":
			_yuanliuzhai_offer_counter_cards(performing_player)
		"yuanliuzhai_activate_shinra":
			_yuanliuzhai_activate_counter_card(performing_player, effect.get("card_id", -1), 2, true)
		"yuanliuzhai_activate_imin":
			_yuanliuzhai_activate_counter_card(performing_player, effect.get("card_id", -1), 2, false)
		"minato_power_per_sealed":
			var minato_sealed_count = performing_player.sealed.size()
			var minato_power_bonus = mini(int(minato_sealed_count / 4.0), 5)
			if minato_power_bonus > 0:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "封印区有%s张牌，获得+%s威力。" % [minato_sealed_count, minato_power_bonus])
				do_effect_if_condition_met(performing_player, card_id, {"effect_type": StrikeEffects.Powerup, "amount": minato_power_bonus, "character_effect": true}, null)
		"minato_advance_max":
			do_effect_if_condition_met(performing_player, card_id, {"effect_type": StrikeEffects.Advance, "amount": 99}, null)
		"minato_return_attack_to_hand":
			if not active_strike or active_strike.did_player_hit_opponent(performing_player):
				return
			# 只有「未命中且会被弃掉」的攻击卡才能回手。若攻击卡会因 after 效果加入怒气
			# （如 block 的 add_strike_to_gauge_after_cleanup 已设 always_add_to_gauge），
			# 则它不会被弃掉 → 不弹回手选择。block 被击晕时 after 不生效、
			# always_add_to_gauge 为 false → 会正常弃掉，可以回手。
			if performing_player.strike_stat_boosts.always_add_to_gauge:
				return
			var minato_attack_card = active_strike.get_player_card(performing_player)
			if minato_attack_card == null:
				return
			do_effect_if_condition_met(performing_player, card_id, {
				"effect_type": StrikeEffects.Choice,
				StrikeEffects.Choice: [
					{"_choice_text": "返回手牌", "effect_type": "minato_return_to_hand_do", "card_id": minato_attack_card.id},
					{"_choice_text": "放弃", "effect_type": StrikeEffects.Pass}
				],
				"override_description": "你的攻击未命中。将其返回手牌？"
			}, null)
		"minato_return_to_hand_do":
			performing_player.strike_stat_boosts.return_attack_to_hand = true
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "此次攻击将在清理后返回手牌。")
		"minato_discard_topdeck_retreat":
			var minato_dt_max = mini(effect.get("gauge_max", 3), performing_player.deck.size())
			if minato_dt_max == 0:
				return
			var minato_dt_choices = []
			for minato_dt_n in range(1, minato_dt_max + 1):
				minato_dt_choices.append({"_choice_text": "弃置%d张（后退%d）" % [minato_dt_n, minato_dt_n], "effect_type": "minato_discard_topdeck_retreat_do", "amount": minato_dt_n})
			minato_dt_choices.append({"_choice_text": "放弃", "effect_type": StrikeEffects.Pass})
			do_effect_if_condition_met(performing_player, card_id, {"effect_type": StrikeEffects.Choice, StrikeEffects.Choice: minato_dt_choices, "override_description": "弃置至多%d张牌库顶牌，每张后退1。" % minato_dt_max}, null)
		"minato_discard_topdeck_retreat_do":
			var minato_dtd_n = effect.get("amount", 0)
			for _i in range(minato_dtd_n):
				performing_player.discard_topdeck()
			do_effect_if_condition_met(performing_player, card_id, {"effect_type": StrikeEffects.Retreat, "amount": minato_dtd_n}, null)
		"minato_one_more_ride":
			if performing_player.sealed.size() > 0:
				var minato_omr_effect = {
					"effect_type": StrikeEffects.Choice,
					StrikeEffects.Choice: [
						{
							"effect_type": StrikeEffects.ChooseDiscard,
							"source": "sealed",
							"destination": "hand",
							"amount": 1,
							"amount_min": 0,
							"limitation": "",
							"and": { "effect_type": StrikeEffects.SkipEndOfTurnDraw, "still_check_hand_limit": true }
						},
						{ "effect_type": StrikeEffects.Pass }
					],
					"override_description": "One More Ride：你可以改为将1张封印区的牌返回手牌，而不是在回合结束时抽牌。"
				}
				handle_strike_effect(-1, minato_omr_effect, performing_player)
			else:
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "One More Ride未触发：封印区中没有牌。")
		"can_seal_for_force":
			pass
		"can_seal_for_gauge":
			pass
		"minato_outrun_the_past":
			var minato_otp_total = performing_player.discards.size() + performing_player.gauge.size()
			if minato_otp_total == 0:
				return
			if not active_strike:
				active_character_action = true
			change_game_state(Enums.GameState.GameState_PlayerDecision)
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_ChooseFromDiscard
			decision_info.player = performing_player.my_id
			decision_info.choice_card_id = card_id
			decision_info.source = "outrun_seal"
			decision_info.destination = "outrun_seal"
			decision_info.amount = 4
			decision_info.amount_min = 0
			decision_info.limitation = ""
			create_event(Enums.EventType.EventType_ChooseFromDiscard, performing_player.my_id, 0)
		"minato_daredevil":
			var minato_dd_max = mini(4, performing_player.deck.size())
			if minato_dd_max == 0:
				return
			var minato_dd_choices = []
			for minato_dd_n in range(1, minato_dd_max + 1):
				minato_dd_choices.append({"_choice_text": "封印%d张（+%d速度）" % [minato_dd_n, minato_dd_n], "effect_type": "minato_daredevil_do", "amount": minato_dd_n})
			minato_dd_choices.append({"_choice_text": "放弃", "effect_type": StrikeEffects.Pass})
			do_effect_if_condition_met(performing_player, card_id, {"effect_type": StrikeEffects.Choice, StrikeEffects.Choice: minato_dd_choices, "override_description": "封印至多%d张牌库顶牌，每张+1速度。" % minato_dd_max}, null)
		"minato_daredevil_do":
			var minato_ddd_n = effect.get("amount", 0)
			for _i in range(minato_ddd_n):
				performing_player.seal_topdeck()
			var minato_dd_card = null
			if active_boost and active_boost.card and active_boost.card.id == card_id:
				minato_dd_card = active_boost.card
			else:
				for boost_card in performing_player.continuous_boosts:
					if boost_card.id == card_id:
						minato_dd_card = boost_card
						break
			if minato_dd_card:
				minato_dd_card.set_meta("minato_dd_count", minato_ddd_n)
			create_event(Enums.EventType.EventType_Strike_SpeedUp, performing_player.my_id, minato_ddd_n)
		"minato_hellraiser":
			for _i in range(4):
				performing_player.discard_topdeck()
				opposing_player.discard_topdeck()
			if performing_player.sealed.size() > 0:
				do_effect_if_condition_met(performing_player, card_id, {"effect_type": StrikeEffects.ChooseDiscard, "source": "sealed", "destination": "hand", "amount": 2, "amount_min": 0, "limitation": ""}, null)
		StrikeEffects.BoostAdditional:
			assert(active_boost, "ERROR: Additional boost effect when a boost isn't in play")

			if 'discard_this_first' in effect and effect['discard_this_first']:
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "弃置加成牌%s。" % active_boost.card.definition['display_name'])
				active_boost.discarded_already = true
				performing_player.add_to_discards(active_boost.card)

			var valid_zones = ['hand']
			if 'valid_zones' in effect:
				valid_zones = effect['valid_zones']
			var ignore_costs = 'ignore_costs' in effect and effect['ignore_costs']
			if performing_player.can_boost_something(valid_zones, effect['limitation'], ignore_costs):
				create_event(Enums.EventType.EventType_ForceStartBoost, performing_player.my_id, 0, "", valid_zones, effect['limitation'], ignore_costs)
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_BoostNow
				decision_info.player = performing_player.my_id
				decision_info.valid_zones = valid_zones
				decision_info.limitation = effect['limitation']
				decision_info.ignore_costs = ignore_costs
			else:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "没有可用于加成的牌。")
		StrikeEffects.BoostAppliesIfOnBuddy:
			if card_id == -1:
				assert(false)
				printlog("ERROR: Unimplemented path to boost_applies_if_on_buddy")
			performing_player.set_boost_applies_if_on_buddy(card_id)
		StrikeEffects.BoostFromExtra:
			# This effect is expected to be a character action.
			if performing_player.can_boost_something(['extra'], effect['limitation']):
				create_event(Enums.EventType.EventType_ForceStartBoost, performing_player.my_id, 0, "", ['extra'], effect['limitation'])
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_BoostNow
				decision_info.player = performing_player.my_id
				decision_info.valid_zones = ['extra']
				decision_info.limitation = effect['limitation']
			else:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "没有可用于额外加成的有效牌。")
		StrikeEffects.BoostFromGauge:
			# This effect is expected to be a character action.
			if performing_player.can_boost_something(['gauge'], effect['limitation']):
				create_event(Enums.EventType.EventType_ForceStartBoost, performing_player.my_id, 0, "", ['gauge'], effect['limitation'])
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_BoostNow
				decision_info.player = performing_player.my_id
				decision_info.valid_zones = ['gauge']
				decision_info.limitation = effect['limitation']
			else:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "怒气中没有可用于加成的有效牌。")
		StrikeEffects.BoostDiscardedOverdrive:
			assert(active_overdrive)
			# Doing the boost here in handle_strike_effect is awkward as do_boost is ideal
			# Instead, set a flag and do it on overdrive cleanup.
			active_overdrive_boost_top_discard_on_cleanup = true
		StrikeEffects.BoostMultiple:
			var valid_zones = ['hand']
			if 'valid_zones' in effect:
				valid_zones = effect['valid_zones']
			var amount = effect['amount']
			var shuffle_discard_after = false
			if 'shuffle_discard_after' in effect:
				shuffle_discard_after = effect['shuffle_discard_after']
			var ignore_costs = false
			if 'ignore_costs' in effect:
				ignore_costs = effect['ignore_costs']
			# 预检也传入 ignore_costs：海蒂 开关扇（boost_multiple + ignore_costs: true +
			# return_to_hand）在玩家 force 不足以支付被展示加成的费用时，也必须能展示
			# 手牌中的即时加成（否则「免费展示并执行」被静默跳过）。
			if performing_player.can_boost_something(valid_zones, effect['limitation'], ignore_costs):
				create_event(Enums.EventType.EventType_ForceStartBoost, performing_player.my_id, amount, "", valid_zones, effect['limitation'], ignore_costs)
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_BoostNow
				decision_info.amount = amount
				decision_info.player = performing_player.my_id
				decision_info.valid_zones = valid_zones
				decision_info.limitation = effect['limitation']
				decision_info.ignore_costs = ignore_costs
				decision_info.extra_info = shuffle_discard_after
				if 'return_to_hand' in effect and effect['return_to_hand']:
					decision_info.return_boost_to_hand = true
					# 「展示并执行」（海蒂 开关扇）：被展示的加成替代本加成，故本加成自身的
					# on_boost 角色效果（如 UA「结算加成摸 1 张」）不触发。
					active_boost.skip_on_boost_effects = true
				performing_player.cancel_blocked_this_turn = true
			else:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "没有可用于加成的牌。")
		StrikeEffects.BoostOrRevealHand:
			# This effect is expected to be a character action.
			if performing_player.can_boost_something(['hand'], effect['limitation']):
				create_event(Enums.EventType.EventType_ForceStartBoost, performing_player.my_id, 0, "", ['hand'], effect['limitation'])
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_BoostNow
				decision_info.player = performing_player.my_id
				decision_info.valid_zones = ['hand']
				decision_info.limitation = effect['limitation']
			else:
				if "strike_instead_of_reveal" in effect and effect["strike_instead_of_reveal"]:
					change_game_state(Enums.GameState.GameState_WaitForStrike)
					decision_info.clear()
					decision_info.type = Enums.DecisionType.DecisionType_StrikeNow
					decision_info.player = performing_player.my_id
					if active_boost:
						# Don't send the event now, we're processing a boost.
						# That has code to set flags on the active_boost to strike after the boost.
						# There could be more effects before the strike occurs, so wait on the event until then
						# and we don't want to send it twice.
						pass
					else:
						create_event(Enums.EventType.EventType_ForceStartStrike, performing_player.my_id, 0)
						if active_post_action_effect:
							post_action_interruption = true
				else:
					_append_log_full(Enums.LogType.LogType_Effect, performing_player, "手牌中没有可用于加成的有效牌。")
					performing_player.reveal_hand()
		StrikeEffects.BoostSpecificCard:
			var boost_name = effect['boost_name']
			var boost_card_id = -1
			for card in performing_player.hand:
				if card.definition['boost']['display_name'] == boost_name:
					boost_card_id = card.id
					break
			if boost_card_id != -1:
				# Have to set this for do_boost to behave, though it's not technically a decision
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_BoostNow
				decision_info.player = performing_player.my_id
				decision_info.valid_zones = ['hand']
				decision_info.limitation = ""
				decision_info.ignore_costs = false
				create_event(Enums.EventType.EventType_EffectDoBoost, performing_player.my_id, boost_card_id)
		StrikeEffects.BoostThisThenSustain:
			# This effect is expected to be mid-strike.
			assert(active_strike)
			var card_name = card_db.get_card_name(card_id)
			performing_player.strike_stat_boosts.move_strike_to_boosts = true
			if 'dont_sustain' in effect: # Should eventually rename effect to be more general
				performing_player.strike_stat_boosts.move_strike_to_boosts_sustain = not effect['dont_sustain']
			var and_sustain_str = ""
			if performing_player.strike_stat_boosts.move_strike_to_boosts_sustain:
				and_sustain_str = " and sustains"
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "进行加成%s %s。" % [and_sustain_str, _log_card_name(card_name)])
			# This removes the attack from play, so it needs to affect stats.
			handle_strike_attack_immediate_removal(performing_player)
			if 'boost_effect' in effect:
				var boost_effect = effect['boost_effect']
				do_effect_if_condition_met(performing_player, card_id, boost_effect, null)
		StrikeEffects.BoostThenSustain:
			# This effect is expected to be mid-strike.
			assert(active_strike)
			var valid_zones = ['hand']
			if 'valid_zones' in effect:
				valid_zones = effect['valid_zones']
			var ignore_costs = false
			if 'ignore_costs' in effect:
				ignore_costs = effect['ignore_costs']
			var bonus_effect = null
			if 'play_boost_effect' in effect:
				bonus_effect = effect['play_boost_effect']
			# 预检也传入 ignore_costs，使「免费打出加成」（ignore_costs: true）在玩家 force
			# 不足以支付加成费用时（如 0 force 手牌有装甲兵/破坏光束）依然可用——海蒂
			# 匕首打击/铁路司机的整理阶段免费加成。对齐 BoostAdditional/BoostMultiple。
			if performing_player.can_boost_something(valid_zones, effect['limitation'], ignore_costs):
				create_event(Enums.EventType.EventType_ForceStartBoost, performing_player.my_id, 0, "", valid_zones, effect['limitation'], ignore_costs)
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_BoostNow
				decision_info.player = performing_player.my_id
				decision_info.valid_zones = valid_zones
				decision_info.limitation = effect['limitation']
				decision_info.ignore_costs = ignore_costs
				decision_info.bonus_effect = bonus_effect
				var sustain = true
				if 'sustain' in effect and not effect['sustain']:
					sustain = false
				performing_player.sustain_next_boost = sustain
				performing_player.cancel_blocked_this_turn = true
			else:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "没有可用于加成的牌。")
		StrikeEffects.BoostThenSustainTopdeck:
			# This effect is expected to be mid-strike.
			assert(active_strike)
			var top_deck_card = performing_player.get_top_deck_card()
			if top_deck_card:
				var skip = false
				if 'discard_if_not_continuous' in effect and effect['discard_if_not_continuous']:
					if top_deck_card.definition['boost']['boost_type'] != "continuous":
						skip = true
						performing_player.discard_topdeck()

				if not skip:
					var sustain = true
					if 'sustain' in effect and not effect['sustain']:
						sustain = false
					performing_player.cancel_blocked_this_turn = true
					change_game_state(Enums.GameState.GameState_PlayerDecision)
					decision_info.clear()
					decision_info.type = Enums.DecisionType.DecisionType_ForceBoostSustainTopdeck
					decision_info.player = performing_player.my_id
					if 'ignore_costs' in effect and effect['ignore_costs']:
						decision_info.ignore_costs = true
					active_strike.remaining_forced_boosts_sustaining = sustain
					active_strike.remaining_forced_boosts = effect['amount']
					active_strike.remaining_forced_boosts_source = "topdeck"
					active_strike.remaining_forced_boosts_player_id = performing_player.my_id
					# 跨多段强制加成保留 ignore_costs：boost_play_cleanup 会在每段之间
					# 清空 decision_info，不持久化则第 2 段起会丢失免费（海蒂 匕首风暴）。
					active_strike.remaining_forced_boosts_ignore_costs = decision_info.ignore_costs
			else:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "牌库中没有可用于加成的牌。")
		StrikeEffects.BoostThenSustainTopdiscard:
			# 强制打出状态：战斗中存于 strike，否则存于 active_boost（海蒂 机械天才
			# 是无战斗上下文的即时加成，active_strike 可能为 null）。
			var boost_card_id = performing_player.get_top_continuous_boost_in_discard()
			if boost_card_id != -1:
				var sustain = true
				if 'sustain' in effect and not effect['sustain']:
					sustain = false
				performing_player.cancel_blocked_this_turn = true
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_ForceBoostSustainTopDiscard
				decision_info.player = performing_player.my_id
				var forced_container = null
				if active_strike:
					forced_container = active_strike
				else:
					forced_container = active_boost
				forced_container.remaining_forced_boosts_sustaining = sustain
				var amount = effect['amount']
				if amount is String and amount == "DISCARDED_COUNT":
					amount = len(effect['discarded_card_ids'])
				forced_container.remaining_forced_boosts = amount
				forced_container.remaining_forced_boosts_source = "topdiscard"
				forced_container.remaining_forced_boosts_player_id = performing_player.my_id
				forced_container.remaining_forced_boosts_ignore_costs = effect.get('ignore_costs', false)
			else:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "弃牌堆中没有可用于加成的牌。")
		StrikeEffects.BoostThenStrike:
			# This effect is expected to be a character action.
			var valid_zones = ['hand']
			if 'valid_zones' in effect:
				valid_zones = effect['valid_zones']
			if performing_player.can_boost_something(valid_zones, effect['limitation']):
				create_event(Enums.EventType.EventType_ForceStartBoost, performing_player.my_id, 0, "", valid_zones, effect['limitation'])
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_BoostNow
				decision_info.player = performing_player.my_id
				decision_info.valid_zones = valid_zones
				decision_info.limitation = effect['limitation']
				performing_player.strike_on_boost_cleanup = true
				if 'wild_strike' in effect and effect['wild_strike']:
					performing_player.wild_strike_on_boost_cleanup = true
			else:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "没有可用于加成的牌。")
				if not active_boost:
					create_event(Enums.EventType.EventType_ForceStartStrike, performing_player.my_id, 0)
				change_game_state(Enums.GameState.GameState_WaitForStrike)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_StrikeNow
				decision_info.player = performing_player.my_id
		StrikeEffects.BoostAsOverdrive:
			# This effect will occur after all start of turn stuff is done.
			# This will be carried out as a special forced character action that
			# automatically happens at that time.
			performing_player.effect_on_turn_start = {
				"effect_type": StrikeEffects.Choice,
				StrikeEffects.Choice: [
					{
						"effect_type": StrikeEffects.BoostAsOverdriveInternal,
						"limitation": effect['limitation'],
						"valid_zones": effect['valid_zones'],
					},
					{
						"effect_type": StrikeEffects.Pass,
						"suppress_and_description": true,
						"and": {
							"effect_type": StrikeEffects.TakeBonusActions,
							"amount": 1
						}
					}
				]
			}
		StrikeEffects.BoostAsOverdriveInternal:
			# All overdrive/start of turn stuff is done and the player chose to boost.
			# They may not have a continuous boost, but
			# they need the bonus action regardless as this is in a weird forced character action timing.
			var valid_zones = effect['valid_zones']
			var limitation = effect['limitation']
			performing_player.bonus_actions = 1
			if performing_player.can_boost_something(valid_zones, effect['limitation']):
				create_event(Enums.EventType.EventType_ForceStartBoost, performing_player.my_id, 0, "", valid_zones, limitation)
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_BoostNow
				decision_info.player = performing_player.my_id
				decision_info.valid_zones = valid_zones
				decision_info.limitation = limitation
			else:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "没有可用于超载效果加成的牌。")
		StrikeEffects.BottomdeckFromHand:
			if len(performing_player.hand) > 0:
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_CardFromHandToGauge
				decision_info.player = performing_player.my_id
				decision_info.choice_card_id = card_id
				decision_info.destination = "bottomdeck"
				decision_info.valid_zones = ["hand"]
				var min_amount = effect['min_amount']
				var max_amount = effect['max_amount']
				if max_amount == -1:
					max_amount = len(performing_player.hand)
				decision_info.effect = {
					"min_amount": min_amount,
					"max_amount": max_amount,
				}
				if 'per_card_effect' in effect and effect['per_card_effect']:
					decision_info.bonus_effect = effect['per_card_effect']
				create_event(Enums.EventType.EventType_CardFromHandToGauge_Choice, performing_player.my_id, min_amount, "", max_amount)
		StrikeEffects.BuddyImmuneToFlip:
			performing_player.strike_stat_boosts.buddy_immune_to_flip = true
		StrikeEffects.CanSpendLifeForForce:
			performing_player.spend_life_for_force_amount = effect['amount']
		StrikeEffects.CanSpendLifeForGauge:
			performing_player.spend_life_for_gauge_amount = effect['amount']
		StrikeEffects.CannotDrawPassive:
			performing_player.cannot_draw += 1
			if performing_player.cannot_draw == 1:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "本回合无法抽牌！")
		StrikeEffects.CannotGoBelowLife:
			performing_player.strike_stat_boosts.cannot_go_below_life = effect['amount']
		StrikeEffects.CannotStun:
			performing_player.strike_stat_boosts.cannot_stun = true
		StrikeEffects.CapAttackDamageTaken:
			performing_player.strike_stat_boosts.cap_attack_damage_taken = effect['amount']
		StrikeEffects.Choice:
			var multiple = 1
			if 'multiple_amount' in effect:
				multiple = effect['multiple_amount']
			var choice_player = performing_player
			if 'opponent' in effect and effect['opponent']:
				choice_player = opposing_player
			change_game_state(Enums.GameState.GameState_PlayerDecision)
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_EffectChoice
			decision_info.player = choice_player.my_id
			if 'add_topdeck_card_name_to_choices' in effect:
				# Add a 'card_name' field to each choice that's in this array.
				for index in effect['add_topdeck_card_name_to_choices']:
					var choice = effect[StrikeEffects.Choice][index]
					var card_name = "nothing (deck empty)"
					if choice_player.deck.size() > 0:
						card_name = card_db.get_card_name(choice_player.deck[0].id)
					choice['card_name'] = card_name
			elif 'add_topdiscard_card_name_to_choices' in effect:
				# Add a 'card_name' field to each choice that's in this array.
				for index in effect['add_topdiscard_card_name_to_choices']:
					var choice = effect[StrikeEffects.Choice][index]
					var card_name = "nothing (discard empty)"
					if choice_player.discards.size() > 0:
						card_name = card_db.get_card_name(choice_player.discards[choice_player.discards.size() - 1].id)
					choice['card_name'] = card_name
			elif 'add_bottomdiscard_card_name_to_choices' in effect:
				# Add a 'card_name' field to each choice that's in this array.
				for index in effect['add_bottomdiscard_card_name_to_choices']:
					var choice = effect[StrikeEffects.Choice][index]
					var card_name = "nothing (discard empty)"
					if choice_player.discards.size() > 0:
						card_name = card_db.get_card_name(choice_player.discards[0].id)
					choice['card_name'] = card_name

			var choices = []
			for choice_source in effect[StrikeEffects.Choice]:
				var choice = choice_source.duplicate(true)
				if effect.has('card_id') and not choice.has('card_id'):
					choice['card_id'] = effect['card_id']
				if effect.get("preserve_source_on_choices"):
					_add_source_player_id_to_effect_tree(choice, _last_effect_source_player_id)
				choices.append(choice)
			choices = _disable_strike_initiation_choices_during_active_strike(choices)
			choices = _disable_choices_requiring_sealed_cards(choices, performing_player)
			decision_info.choice = choices
			decision_info.choice_card_id = card_id
			decision_info.multiple_choice_amount = multiple
			create_event(Enums.EventType.EventType_Strike_EffectChoice, choice_player.my_id, 0, "EffectOption")
		StrikeEffects.ChoiceAlteredValues:
			# Make a deep copy of the choices and replace any needed values.
			var updated_choices = effect[StrikeEffects.Choice].duplicate(true)
			for choice_effect in updated_choices:
				if str(choice_effect['amount']) == "TOTAL_POWER":
					choice_effect['amount'] = get_total_power(performing_player)
				elif str(choice_effect['amount']) == "strike_x":
					choice_effect['amount'] = performing_player.strike_stat_boosts.strike_x

			# Same as normal choice.
			updated_choices = _disable_strike_initiation_choices_during_active_strike(updated_choices)
			change_game_state(Enums.GameState.GameState_PlayerDecision)
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_EffectChoice
			decision_info.player = performing_player.my_id
			decision_info.choice = updated_choices
			decision_info.choice_card_id = card_id
			decision_info.source_player_id = effect.get("_source_player_id", _last_effect_source_player_id)
			create_event(Enums.EventType.EventType_Strike_EffectChoice, performing_player.my_id, 0, "EffectOption")
		StrikeEffects.ChooseCalculateRangeFromBuddy:
			var optional = 'optional' in effect and effect['optional']
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect
			decision_info.player = performing_player.my_id
			decision_info.choice_card_id = card_id
			decision_info.effect_type = StrikeEffects.CalculateRangeFromBuddyCurrentLocation
			decision_info.source = effect['buddy_name']
			decision_info.choice = []
			decision_info.limitation = []
			if optional:
				decision_info.limitation.append(0)
				decision_info.choice.append({
					"effect_type": StrikeEffects.Pass
				})

			for location in performing_player.buddy_locations:
				if location == -1:
					continue
				var buddy_id = performing_player.get_buddy_id_at_location(location)

				if location not in decision_info.limitation:
					decision_info.limitation.append(location)
					decision_info.choice.append({
						"effect_type": StrikeEffects.CalculateRangeFromBuddyCurrentLocation,
						"buddy_id": buddy_id
					})
			var actual_choices = len(decision_info.limitation)
			if optional:
				actual_choices -= 1

			# If the only option is to pass, just let this pass.
			if actual_choices > 0:
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				create_event(Enums.EventType.EventType_ChooseArenaLocationForEffect, performing_player.my_id, 0)
			else:
				assert(false, "Unexpected called choose_calculate_range_from_buddy but can't.")
		StrikeEffects.ChooseCardsFromTopDeck:
			# Manual swap for opponent-targeted effects (avoids double-swap with global for_other_player)
			var target_player = performing_player
			if effect.get('_target_other', false):
				target_player = opposing_player
			var look_amount = min(effect['look_amount'], target_player.deck.size())
			if look_amount == 0:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "其牌库中没有可查看的牌。")
				if 'strike_after' in effect and effect['strike_after']:
					if not active_boost:
						create_event(Enums.EventType.EventType_ForceStartStrike, performing_player.my_id, 0)
					change_game_state(Enums.GameState.GameState_WaitForStrike)
					decision_info.clear()
					decision_info.type = Enums.DecisionType.DecisionType_StrikeNow
					decision_info.player = performing_player.my_id
			elif look_amount > 0:
				_append_log_full(Enums.LogType.LogType_Effect, target_player, "looks at the top %s cards of their deck." % look_amount)
				target_player.cancel_blocked_this_turn = true
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_ChooseFromTopDeck
				decision_info.player = target_player.my_id
				decision_info.choice_card_id = card_id
				decision_info.action = effect['action_choices']
				decision_info.can_pass = effect['can_pass']
				decision_info.destination = effect['destination_unchosen']
				decision_info.effect = effect
				decision_info.amount = look_amount
				decision_info.bonus_effect = effect.get('and_not_passed', null)
				create_event(Enums.EventType.EventType_ChooseFromTopDeck, target_player.my_id, 0)

				if 'strike_after' in effect and effect['strike_after']:
					performing_player.strike_on_boost_cleanup = true
		StrikeEffects.ChooseBoostsFromTopDeck:
			# "Look at the top N cards. Free-play any number of the continuous
			# boosts among them and sustain them; discard the rest."
			# Reuses the ChooseFromTopDeck decision, but the decision accepts a
			# SET of cards (decision_info.select_multiple) and the cards chosen
			# are played one at a time by the forced-boost loop.
			assert(active_strike)
			var choose_look_amount = min(effect['look_amount'], performing_player.deck.size())
			if choose_look_amount <= 0:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "牌库中没有可查看的牌。")
			else:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "查看牌库顶的 %s 张牌。" % choose_look_amount)
				performing_player.cancel_blocked_this_turn = true
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_ChooseFromTopDeck
				decision_info.player = performing_player.my_id
				decision_info.choice_card_id = card_id
				decision_info.action = effect.get('action_choices', ["boost"])
				decision_info.can_pass = true
				decision_info.destination = effect.get('destination_unchosen', "discard")
				decision_info.limitation = effect.get('limitation', "")
				decision_info.effect = effect
				decision_info.amount = choose_look_amount
				decision_info.amount_min = 0
				decision_info.select_multiple = true
				create_event(Enums.EventType.EventType_ChooseFromTopDeck, performing_player.my_id, 0)
		StrikeEffects.ChooseDiscard:
			var source = "discard"
			var discard_effect = null
			var target_player = performing_player
			if effect.get("opponent"):
				target_player = opposing_player
			if 'discard_effect' in effect:
				discard_effect = effect['discard_effect']
			if 'source' in effect:
				source = effect['source']
			var choice_count = 0
			if source == "discard":
				choice_count = target_player.get_discard_count_of_type(effect['limitation'])
			elif source == "gauge":
				choice_count = target_player.get_gauge_count_of_type(effect['limitation'])
			elif source == "sealed":
				choice_count = target_player.get_sealed_count_of_type(effect['limitation'])
			elif source == "overdrive":
				choice_count = target_player.overdrive.size()
			else:
				assert(false, "Unimplemented source")
			if choice_count > 0:
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_ChooseFromDiscard
				decision_info.player = target_player.my_id
				decision_info.choice_card_id = card_id
				decision_info.source = source
				decision_info.limitation = effect['limitation']
				decision_info.destination = effect['destination']
				decision_info.bonus_effect = discard_effect
				decision_info.action = null
				if 'overdrive_action' in effect and effect['overdrive_action']:
					decision_info.action = "overdrive_action"
				var amount = 1
				if 'amount' in effect:
					amount = min(choice_count, effect['amount'])
				decision_info.amount = amount
				decision_info.amount_min = amount
				if 'amount_min' in effect:
					decision_info.amount_min = min(effect['amount_min'], amount)
				create_event(Enums.EventType.EventType_ChooseFromDiscard, target_player.my_id, amount)
			else:
				if effect['limitation']:
					_append_log_full(Enums.LogType.LogType_Effect, target_player, "在%s中没有%s牌。" % [effect['limitation'], source])
				else:
					_append_log_full(Enums.LogType.LogType_Effect, target_player, "在%s中没有牌。" % source)
		StrikeEffects.ChooseOpponentCardToDiscard:
			var choice_player = performing_player
			var choice_other_player = opposing_player
			if 'opponent' in effect and effect['opponent']:
				choice_player = opposing_player
				choice_other_player = performing_player
			var destination = effect.get('destination', 'discard')

			var cards_available = choice_other_player.get_card_ids_in_hand()
			if 'use_discarded_card_ids' in effect and effect['use_discarded_card_ids']:
				cards_available = effect['discarded_card_ids']
			var decision_effect = effect.duplicate()
			decision_effect['amount'] = 1
			if cards_available.size() > 0:
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_ChooseToDiscard
				decision_info.effect_type = StrikeEffects.ChooseOpponentCardToDiscardInternal
				decision_info.effect = decision_effect
				decision_info.source_player_id = decision_effect.get("_source_player_id", _last_effect_source_player_id)
				decision_info.choice_card_id = card_id
				decision_info.player = choice_player.my_id
				decision_info.choice = cards_available
				decision_info.limitation = ""
				decision_info.destination = destination
				create_event(Enums.EventType.EventType_ChooseOpponentCardToDiscard, choice_player.my_id, 0)
			else:
				_append_log_full(Enums.LogType.LogType_Effect, choice_other_player, "手牌中没有可弃置的牌。")
		StrikeEffects.ChooseOpponentCardToDiscardInternal:
			var card_ids = effect['card_ids']
			var card_names = card_db.get_card_names(card_ids)
			# Save/restore _last_effect_source_player_id so _on_player_discard
			# sees the original source (e.g. Eugenia) instead of the intermediate
			# performing_player (the one who chose, not the one who caused the effect).
			var _saved_source = _last_effect_source_player_id
			_last_effect_source_player_id = effect.get("_source_player_id", _last_effect_source_player_id)
			if effect.get('destination') == 'gauge':
				for chosen_card_id in card_ids:
					opposing_player.move_card_from_hand_to_gauge(chosen_card_id)
				_append_log_full(Enums.LogType.LogType_CardInfo, opposing_player, "由%s将%s张牌移入怒气：%s。" % [performing_player.name, str(card_ids.size()), _log_card_name(card_names)])
			else:
				_append_log_full(Enums.LogType.LogType_CardInfo, opposing_player, "有被%s弃置的牌：%s。" % [performing_player.name, _log_card_name(card_names)])
				opposing_player.discard(card_ids)
			_last_effect_source_player_id = _saved_source
		StrikeEffects.ChooseSustainBoost:
			var choice_count = performing_player.transforms.size() if effect.get("tournelouse_ouroboros") else performing_player.get_boosts().size()
			if not effect.get("tournelouse_ouroboros"):
				choice_count -= performing_player.sustained_boosts.size()
			if choice_count > 0:
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_ChooseFromBoosts
				decision_info.player = performing_player.my_id
				decision_info.choice_card_id = card_id
				decision_info.effect = effect
				var amount = 1
				if 'amount' in effect:
					amount = min(choice_count, effect['amount'])
				decision_info.amount = amount
				decision_info.amount_min = amount
				if 'amount_min' in effect:
					decision_info.amount_min = effect['amount_min']
				create_event(Enums.EventType.EventType_ChooseFromBoosts, performing_player.my_id, amount)
			else:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "没有更多可维持的加成。")
		StrikeEffects.Close:
			decision_info.clear()
			decision_info.source = StrikeEffects.Close
			decision_info.amount = effect['amount']
			decision_info.limitation = { 'and': null }
			if 'and' in effect:
				decision_info.limitation['and'] = effect['and']
				# and effect is handled by internal version
				and_handled_elsewhere = true

			var effects = performing_player.get_character_effects_at_timing("on_advance_or_close")
			for sub_effect in effects:
				do_effect_if_condition_met(performing_player, -1, sub_effect, null)
			if game_state != Enums.GameState.GameState_PlayerDecision:
				var close_effect = effect.duplicate()
				close_effect['effect_type'] = StrikeEffects.CloseInternal
				handle_strike_effect(card_id, close_effect, performing_player)
		StrikeEffects.CloseDamageTaken:
			var close_per = effect['amount']
			var damage_taken = active_strike.get_damage_taken(performing_player)
			var total_close = close_per * damage_taken
			if total_close > 0:
				var close_effect = {
					"effect_type": StrikeEffects.Close,
					"amount": total_close,
				}
				handle_strike_effect(card_id, close_effect, performing_player)
		StrikeEffects.CloseInternal:
			var amount = effect['amount']
			if str(amount) == "strike_x":
				amount = performing_player.strike_stat_boosts.strike_x
			amount += performing_player.strike_stat_boosts.increase_movement_effects_by
			amount = _dongshilang_limit_requested_movement(performing_player, amount)

			var previous_location = performing_player.arena_location
			performing_player.close(amount)
			var new_location = performing_player.arena_location
			var close_amount = abs(performing_start - new_location)
			local_conditions.fully_closed = close_amount == amount
			_append_log_full(Enums.LogType.LogType_CharacterMovement, performing_player, "逼近%s，从格子%s移动到%s。" % [str(amount), str(previous_location), str(new_location)])
			if 'save_spaces_as_strike_x' in effect and effect['save_spaces_as_strike_x']:
				_append_log_full(Enums.LogType.LogType_Strike, performing_player, "此次战斗的X被设为逼近的格数，%s。" % close_amount)
				performing_player.set_strike_x(close_amount)
			elif 'save_spaces_not_closed_as_strike_x' in effect and effect['save_spaces_not_closed_as_strike_x']:
				var not_closed = amount - close_amount
				_append_log_full(Enums.LogType.LogType_Strike, performing_player, "此次战斗的X被设为未逼近的格数，%s。" % not_closed)
				performing_player.set_strike_x(not_closed)
			local_conditions.movement_amount = close_amount
			_dongshilang_consume_movement_limit(performing_player, close_amount)
			# Ulrik: increment move counters from continuous boosts
			for boost in performing_player.continuous_boosts:
				for boost_effect in boost.definition['boost']['effects']:
					if boost_effect.get('effect_type') == StrikeEffects.IncrementBonusMovePowerCounters:
						boost.set_meta('bonus_move_power_counters', boost.get_meta('bonus_move_power_counters', 0) + close_amount * boost_effect.get('amount', 1))
					if boost_effect.get('effect_type') == StrikeEffects.IncrementBonusMoveArmorCounters:
						boost.set_meta('bonus_move_armor_counters', boost.get_meta('bonus_move_armor_counters', 0) + close_amount * boost_effect.get('amount', 1))
		StrikeEffects.CopyOtherHitEffect:
			var card = active_strike.get_player_card(performing_player)
			var hit_effects = get_all_effects_for_timing("hit", performing_player, card)

			var effect_options = []
			for possible_effect in hit_effects:
				if possible_effect['effect_type'] != StrikeEffects.CopyOtherHitEffect:
					effect_options.append(get_base_remaining_effect(possible_effect))

			if len(effect_options) > 0:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "正在复制另一个击中效果。")
				# Send choice to player
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_ChooseSimultaneousEffect
				decision_info.player = performing_player.my_id
				decision_info.source_player_id = performing_player.my_id
				decision_info.effect_type = StrikeEffects.CopyOtherHitEffect
				decision_info.choice = effect_options
				create_event(Enums.EventType.EventType_Strike_EffectChoice, performing_player.my_id, 0, "Duplicate")
			else:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "没有其他可复制的击中效果。")
		StrikeEffects.CopyOtherAfterEffect:
			var card = active_strike.get_player_card(performing_player)
			var after_effects = get_all_effects_for_timing("after", performing_player, card)
			var effect_options = []
			for possible_effect in after_effects:
				if possible_effect['effect_type'] != StrikeEffects.CopyOtherAfterEffect:
					effect_options.append(get_base_remaining_effect(possible_effect))
			if effect_options:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "正在复制另一个后置效果。")
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_ChooseSimultaneousEffect
				decision_info.player = performing_player.my_id
				decision_info.source_player_id = performing_player.my_id
				decision_info.effect_type = StrikeEffects.CopyOtherAfterEffect
				decision_info.choice = effect_options
				create_event(Enums.EventType.EventType_Strike_EffectChoice, performing_player.my_id, 0, "Duplicate")
			else:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "没有其他可复制的后置效果。")
		StrikeEffects.Critical:
			var crit_name = "Critical"
			if 'alt_crit_name' in effect:
				crit_name = effect['alt_crit_name']

			performing_player.strike_stat_boosts.critical = true
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "的战斗为%s！" % crit_name)
			var strike_card = active_strike.get_player_card(performing_player)
			create_event(Enums.EventType.EventType_Strike_Critical, performing_player.my_id, strike_card.id, crit_name)
		StrikeEffects.DisableBoostFromExtra:
			performing_player.can_boost_from_extra = false
		StrikeEffects.DiscardThis:
			if active_boost and not effect.get("ignore_active_boost"):
				active_boost.discard_on_cleanup = true
			else:
				var card = card_db.get_card(card_id)
				var card_name = card_db.get_card_name(card.id)
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "弃置加成牌%s。" % _log_card_name(card_name))
				performing_player.remove_from_continuous_boosts(card)
				opposing_player.remove_from_continuous_boosts(card)
		StrikeEffects.DiscardSameCardAsBoost:
			assert(active_boost)
			var boost_copy_id = performing_player.get_copy_in_hand_match_normals(active_boost.card)
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "弃置一张加成牌%s的复制。" % [_log_card_name(active_boost.card.definition['display_name'])])
			performing_player.discard([boost_copy_id])
		StrikeEffects.DiscardStoredCards:
			var card_ids = []
			for card in performing_player.set_aside_cards:
				card_ids.append(card.id)
			performing_player.discard(card_ids)
		StrikeEffects.DiscardStrikeAfterCleanup:
			performing_player.strike_stat_boosts.discard_attack_on_cleanup = true
		StrikeEffects.DiscardOpponentTopdeck:
			opposing_player.discard_topdeck()
		StrikeEffects.DiscardTopdeck:
			for _i in range(effect.get("amount", 1)):
				performing_player.discard_topdeck()
		StrikeEffects.DrawOrDiscardTo:
			handle_player_draw_or_discard_to_effect(performing_player, card_id, effect)
		StrikeEffects.DrawForCardInGauge:
			var draw_amount = performing_player.gauge.size()
			if 'per_gauge' in effect:
				draw_amount = floor(draw_amount / effect['per_gauge'])
			if draw_amount > 0:
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "抽%s张牌。" % draw_amount)
				performing_player.draw(draw_amount)
		StrikeEffects.DrawForCardInHand:
			var hand_size = performing_player.hand.size()
			if effect.get("and", {}).get("amount") == "draw_amount":
				effect = effect.duplicate(true)
				effect["and"]["amount"] = hand_size
			if hand_size > 0:
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "抽%s张牌。" % hand_size)
				performing_player.draw(hand_size)
		StrikeEffects.DrawTo:
			var target_hand_size = effect['amount']
			var hand_size = performing_player.hand.size()
			if hand_size < target_hand_size:
				var amount_to_draw = target_hand_size - hand_size
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "抽%s张牌，使手牌数达到%s。" % [amount_to_draw, target_hand_size])
				performing_player.draw(amount_to_draw)
		StrikeEffects.DiscardTo:
			var target_hand_size = effect['amount']
			var hand_size = performing_player.hand.size()
			if hand_size > target_hand_size:
				var amount_to_discard = hand_size - target_hand_size
				var discard_effect = {
					"effect_type": StrikeEffects.SelfDiscardChoose,
					"amount": amount_to_discard
				}
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "必须弃置%s张牌，使手牌数达到%s。" % [amount_to_discard, target_hand_size])
				handle_strike_effect(card_id, discard_effect, performing_player)
		StrikeEffects.OpponentDrawOrDiscardTo:
			handle_player_draw_or_discard_to_effect(opposing_player, card_id, effect)
		StrikeEffects.OpponentDrawTo:
			var target_hand_size = effect['amount']
			var hand_size = opposing_player.hand.size()
			if hand_size < target_hand_size:
				var amount_to_draw = target_hand_size - hand_size
				_append_log_full(Enums.LogType.LogType_CardInfo, opposing_player, "draws %s card(s) to reach a hand size of %s." % [amount_to_draw, target_hand_size])
				opposing_player.draw(amount_to_draw)
		StrikeEffects.DodgeAtRange:
			if 'special_range' in effect and effect['special_range'] == "OVERDRIVE_COUNT":
				var current_range = performing_player.overdrive.size()
				performing_player.strike_stat_boosts.dodge_at_range_late_calculate_with  = effect['special_range']
				create_event(Enums.EventType.EventType_Strike_DodgeAttacksAtRange, performing_player.my_id, current_range, "", current_range, "")
			else:
				var effect_card_id = card_id
				if 'card_id' in effect:
					effect_card_id = effect['card_id']
				performing_player.strike_stat_boosts.dodge_at_range_min[effect_card_id] = effect['range_min']
				performing_player.strike_stat_boosts.dodge_at_range_max[effect_card_id] = effect['range_max']
				var buddy_name = null
				if 'from_buddy' in effect:
					performing_player.strike_stat_boosts.dodge_at_range_from_buddy = effect['from_buddy']
					buddy_name = effect['buddy_name']
				create_event(Enums.EventType.EventType_Strike_DodgeAttacksAtRange, performing_player.my_id, effect['range_min'], "", effect['range_max'], buddy_name)
		StrikeEffects.DodgeAttacks:
			performing_player.strike_stat_boosts.dodge_attacks = true
			create_event(Enums.EventType.EventType_Strike_DodgeAttacks, performing_player.my_id, 0)
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "现在会闪避攻击！")
		StrikeEffects.DodgeFromOppositeBuddy:
			performing_player.strike_stat_boosts.dodge_from_opposite_buddy = true
			create_event(Enums.EventType.EventType_Strike_DodgeFromOppositeBuddy, performing_player.my_id, 0, "", effect['buddy_name'])
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "将闪避来自%s后方的对手的攻击！" % effect['buddy_name'])
		StrikeEffects.DodgeNormals:
			performing_player.strike_stat_boosts.dodge_normals = true
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "现在会闪避普通攻击！")
		StrikeEffects.Draw:
			var amount = effect['amount']
			if str(amount) == "strike_x":
				amount = performing_player.strike_stat_boosts.strike_x
			elif str(amount) == "GAUGE_COUNT":
				amount = performing_player.gauge.size()
			elif str(amount) == "SPACES_BETWEEN":
				amount = performing_player.distance_to_opponent() - 1
			amount += performing_player.strike_stat_boosts.increase_draw_effects_by

			var from_bottom = false
			var from_bottom_string = ""
			if 'from_bottom' in effect and effect['from_bottom']:
				from_bottom = true
				from_bottom_string = " from bottom of deck"

			if amount > 0:
				var target_player = performing_player
				if effect.get("opponent"):
					target_player = opposing_player
				target_player.draw(amount, false, from_bottom)
				_append_log_full(Enums.LogType.LogType_CardInfo, target_player, "抽%s张牌%s。" % [amount, from_bottom_string])
				var drawn_card_ids = target_player.hand.slice(-amount, target_player.hand.size()).map(func(item): return item.id)
				if effect.get("reveal"):
					target_player.reveal_card_ids(drawn_card_ids)
		StrikeEffects.DrawAnyNumber:
			var max_user_can_draw = performing_player.deck.size()
			if performing_player.reshuffle_remaining > 0:
				max_user_can_draw += performing_player.discards.size()
			# 卡上可以写 amount 当上限（「摸至多 N 张」）：只列 0..N 供选择。
			# 不写 amount 时维持「任意数量」的旧行为。非数字 amount（如 "GAUGE_COUNT"）忽略。
			var any_number_cap = effect.get('amount', null)
			if (typeof(any_number_cap) == TYPE_INT or typeof(any_number_cap) == TYPE_FLOAT) and int(any_number_cap) >= 0:
				max_user_can_draw = mini(max_user_can_draw, int(any_number_cap))

			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_PickNumberFromRange
			decision_info.player = performing_player.my_id
			decision_info.choice_card_id = card_id
			decision_info.effect_type = StrikeEffects.Draw
			decision_info.choice = []
			decision_info.amount_min = 0
			decision_info.amount = max_user_can_draw

			decision_info.limitation = []
			for i in range(max_user_can_draw + 1):
				decision_info.limitation.append(i)
				decision_info.choice.append({
					"effect_type": StrikeEffects.Draw,
					"amount": i
				})

			change_game_state(Enums.GameState.GameState_PlayerDecision)
			create_event(Enums.EventType.EventType_PickNumberFromRange, performing_player.my_id, 0)
		StrikeEffects.DiscardAttack:
			if active_strike:
				var strike_card = active_strike.get_player_card(performing_player)
				var card_name = strike_card.definition['display_name']
				performing_player.strike_stat_boosts.discard_attack_now = true
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "弃置其攻击%s。" % _log_card_name(card_name))
				handle_strike_attack_immediate_removal(performing_player)
		StrikeEffects.DiscardBoostInOpponentSpace:
			decision_info.clear()
			decision_info.destination = "discard"
			var boost_name = ""
			if 'boost_name' in effect:
				boost_name = effect['boost_name']
			if 'overall_effect' in effect:
				decision_info.effect = effect['overall_effect']
			else:
				decision_info.effect = null

			var valid_boosts = []
			for boost in performing_player.get_boosts(true):
				if boost_name and boost.definition['boost']['display_name'] != boost_name:
					continue
				var boost_location = performing_player.get_boost_location(boost.id)
				if boost_location != -1 and opposing_player.is_in_location(boost_location):
					valid_boosts.append(boost)

			if len(valid_boosts) == 1:
				var discard_effect = {
					"effect_type": StrikeEffects.DiscardContinuousBoostInternal,
					"card_id": valid_boosts[0].id,
				}
				handle_strike_effect(card_id, discard_effect, performing_player)
			elif len(valid_boosts) > 1:
				# Player gets to pick which continuous boost to discard.
				decision_info.limitation = "in_opponent_space"
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.type = Enums.DecisionType.DecisionType_ChooseDiscardContinuousBoost
				decision_info.effect_type = StrikeEffects.DiscardContinuousBoostInternal
				decision_info.choice_card_id = card_id
				decision_info.can_pass = false
				decision_info.player = performing_player.my_id
				decision_info.extra_info = boost_name
				create_event(Enums.EventType.EventType_Boost_DiscardContinuousChoice, performing_player.my_id, 1, "", boost_name)
		StrikeEffects.DiscardContinuousBoost:
			var my_boosts = performing_player.get_boosts(true)
			var opponent_boosts = opposing_player.get_boosts(true)
			decision_info.clear()
			decision_info.limitation = ""
			if 'limitation' in effect:
				decision_info.limitation = effect['limitation']
			decision_info.destination = "discard"
			if 'destination' in effect:
				decision_info.destination = effect['destination']

			if len(my_boosts) > 0 or (not decision_info.limitation == "mine" and len(opponent_boosts) > 0):
				# Player gets to pick which continuous boost to discard.
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.type = Enums.DecisionType.DecisionType_ChooseDiscardContinuousBoost
				decision_info.effect_type = StrikeEffects.DiscardContinuousBoostInternal
				decision_info.choice_card_id = card_id
				if 'overall_effect' in effect:
					decision_info.effect = effect['overall_effect']
				else:
					decision_info.effect = null
				decision_info.can_pass = not effect['required']
				decision_info.player = performing_player.my_id
				create_event(Enums.EventType.EventType_Boost_DiscardContinuousChoice, performing_player.my_id, 1)
		StrikeEffects.DiscardContinuousBoostInternal:
			var boost_to_discard_id = effect['card_id']
			if boost_to_discard_id != -1:
				var card = card_db.get_card(boost_to_discard_id)
				var boost_name = _get_boost_and_card_name(card)
				# Default destination is to discard.
				var destination = "discard"
				var log_action = "弃置"
				var log_suffix = ""
				var requested_destination = effect.get("destination", "")
				if requested_destination == "":
					requested_destination = decision_info.destination
				if requested_destination == "owner_hand":
					destination = "hand"
				elif requested_destination == "gauge":
					destination = "gauge"
					log_action = "将"
					log_suffix = "加入怒气"
				if performing_player.is_card_in_continuous_boosts(boost_to_discard_id):
					performing_player.remove_from_continuous_boosts(card, destination)
					_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "%s其加成%s%s。" % [log_action, boost_name, log_suffix])
				elif opposing_player.is_card_in_continuous_boosts(boost_to_discard_id):
					opposing_player.remove_from_continuous_boosts(card, destination)
					_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "%s%s的加成%s%s。" % [log_action, opposing_player.name, boost_name, log_suffix])

				# Do any bonus effect
				if decision_info.effect:
					handle_strike_effect(card_id, decision_info.effect, performing_player)
		StrikeEffects.DiscardHand:
			performing_player.discard_hand()
		StrikeEffects.DiscardOpponentGauge:
			if opposing_player.gauge.size() > 0:
				var opponent_chooses = effect.get('opponent_chooses', false)
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_ChooseDiscardOpponentGauge
				decision_info.effect_type = StrikeEffects.DiscardOpponentGaugeInternal
				decision_info.choice_card_id = card_id
				decision_info.amount = effect['amount2']
				decision_info.extra_info = opponent_chooses
				var instruction_text = effect.get("UI_instruction_text", "")
				if opponent_chooses:
					decision_info.player = opposing_player.my_id
					create_event(Enums.EventType.EventType_Boost_DiscardOpponentGauge, opposing_player.my_id, 0, instruction_text)
				else:
					decision_info.player = performing_player.my_id
					create_event(Enums.EventType.EventType_Boost_DiscardOpponentGauge, performing_player.my_id, 0, instruction_text)
		StrikeEffects.DiscardOpponentGaugeInternal:
			var chosen_card_id = effect['card_id']
			var card_name = card_db.get_card_name(chosen_card_id)
			if decision_info.extra_info:
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "从自己的怒气中弃置%s。" % _log_card_name(card_name))
				performing_player.discard([chosen_card_id])
			else:
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "从%s的怒气中弃置%s。" % [_log_card_name(card_name), opposing_player.name])
				opposing_player.discard([chosen_card_id])
		StrikeEffects.DiscardRandom:
			var discard_ids = performing_player.pick_random_cards_from_hand(effect['amount'])
			if discard_ids.size() > 0:
				if effect.get("record_discarded_amount"):
					active_strike.cards_discarded_this_strike += discard_ids.size()
				var discarded_names = card_db.get_card_names(discard_ids)
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "随机弃置牌：%s。" % _log_card_name(discarded_names))
				# Save/restore source so _on_player_discard sees the original
				# effect source (e.g. Eugenia) instead of the performing_player
				# (the one executing the discard).
				var _saved_source = _last_effect_source_player_id
				if '_source_player_id' in effect:
					_last_effect_source_player_id = effect['_source_player_id']
				performing_player.discard(discard_ids)
				_last_effect_source_player_id = _saved_source
		StrikeEffects.DiscardRandomAndAddTriggers:
			var cards_to_discard = performing_player.pick_random_cards_from_hand(1)
			if cards_to_discard.size() > 0:
				performing_player.discard(cards_to_discard)
				add_attack_triggers(performing_player, cards_to_discard, true)
				var discarded_name = card_db.get_card_name(cards_to_discard[0])
				performing_player.plague_knight_discard_names.append(discarded_name)
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "随机弃置牌：%s。" % _log_card_name(discarded_name))
		StrikeEffects.EffectPerCardInZone:
			var zone = effect['zone']
			var per_effect = effect['per_card_effect'].duplicate(true)
			var limitation = effect.get('limitation', "")
			var effect_times = 0
			var cards = []
			match zone:
				"transform":
					cards = performing_player.transforms
				"gauge":
					cards = performing_player.gauge
				"hand":
					cards = performing_player.hand
				"discard":
					cards = performing_player.discards
				"sealed":
					cards = performing_player.sealed
				"stored_cards":
					cards = performing_player.set_aside_cards
				"overdrive":
					cards = performing_player.overdrive
			match limitation:
				"range_to_opponent":
					for card in cards:
						var min_range = get_card_stat(performing_player, card, 'range_min')
						var max_range = get_card_stat(performing_player, card, 'range_max')
						min_range += performing_player.get_total_min_range_bonus(card)
						max_range += performing_player.get_total_max_range_bonus(card)
						var range_to_opponent = performing_player.distance_to_opponent()
						if min_range <= range_to_opponent and max_range >= range_to_opponent:
							effect_times += 1
				_:
					effect_times = cards.size()

			if effect_times > 0:
				if per_effect.get("combine_multiple_into_one"):
					per_effect["amount"] *= effect_times
					effect_times = 1
				for i in range(effect_times):
					# Assumes no decisions.
					do_effect_if_condition_met(performing_player, card_id, per_effect, null)
		StrikeEffects.EnableBoostFromGauge:
			performing_player.can_boost_from_gauge = true
		StrikeEffects.EnableEndOfTurnDraw:
			performing_player.draw_at_end_of_turn = true
		StrikeEffects.EndOverdrive:
			performing_player.end_overdrive()
		StrikeEffects.ExceedEndOfTurn:
			performing_player.exceed_at_end_of_turn = true
		StrikeEffects.ExceedNow:
			if _is_taisei_death_exceed_decision(performing_player, decision_info.effect):
				performing_player.taisei_death_exceed_override_life = _get_taisei_death_exceed_target_life(performing_player)
			performing_player.exceed()
		StrikeEffects.MayExceedNowWithCost:
			var exceed_cost = performing_player.get_exceed_cost()
			if performing_player.get_available_gauge() >= exceed_cost:
				# Prompt the player to select which gauge cards to spend to exceed.
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.player = performing_player.my_id
				decision_info.type = Enums.DecisionType.DecisionType_GaugeForEffect
				decision_info.choice_card_id = -1
				decision_info.effect = {
					"effect_type": StrikeEffects.GaugeForEffect,
					"gauge_max": exceed_cost,
					"min_gauge": exceed_cost,
					"can_pass": exceed_cost > 0,
					"decline_on_death_game_over": true,
					"per_gauge_effect": null,
					"overall_effect": {"effect_type": StrikeEffects.ExceedNow},
				}
				create_event(Enums.EventType.EventType_GaugeForEffect, performing_player.my_id, 0)
		StrikeEffects.ExceedOpponentNow:
			opposing_player.exceed()
			# hoping for the best here
		StrikeEffects.ExtraTriggerResolutions:
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "的前置/击中/后置效果将额外结算%s次！" % effect['amount'])
			duplicate_attack_triggers(performing_player, effect['amount'])
		StrikeEffects.FlipBuddyMissGetGauge:
			if active_strike.extra_attack_in_progress:
				active_strike.extra_attack_data.extra_attack_always_miss = true
				active_strike.extra_attack_data.extra_attack_always_go_to_gauge = true
			else:
				performing_player.strike_stat_boosts.attack_does_not_hit = true
				performing_player.strike_stat_boosts.always_add_to_gauge = true
			handle_strike_effect(
				-1,
				{
					'effect_type': StrikeEffects.SwapBuddy,
					"buddy_to_remove": effect['buddy_to_remove'],
					"buddy_to_place": effect['buddy_to_place'],
					"description": effect['swap_description']
				},
				opposing_player
			)
			var buddy_name = opposing_player.get_buddy_name(effect['buddy_to_remove'])
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "翻转%s，未命中%s。" % [buddy_name, opposing_player.name])
		StrikeEffects.ForceCostsReducedPassive:
			performing_player.force_cost_reduction += effect['amount']
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "现在其能量费用减少%s！" % performing_player.force_cost_reduction)
		StrikeEffects.RemoveForceCostsReducedPassive:
			performing_player.force_cost_reduction = max(0, performing_player.force_cost_reduction - effect['amount'])
			if performing_player.force_cost_reduction == 0:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "其能量费用不再减少。")
			else:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "现在其能量费用仅减少%s。" % performing_player.force_cost_reduction)
		StrikeEffects.GaugeCostsReducedPassive:
			if 'remove' in effect and effect['remove']:
				performing_player.free_gauge -= effect['amount']
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "其怒气费用不再减少。")
			else:
				performing_player.free_gauge += effect['amount']
				var reduction_str = "by %s" % str(effect['amount'])
				if effect['amount'] == 99:
					reduction_str = "to zero"
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "现在其怒气费用减少%s！" % reduction_str)
		"renea_return_normals_from_discard":
			# Paranormal Investigation hit: uses engine's choose_discard (same as Djanette's Return)
			# Defined in JSON with source:discard, destination:hand, limitation:normal
			pass
		"renea_mimetism_sustain":
			# Mimetism after: spend 2F to sustain a continuous boost
			var renea_boosts = performing_player.get_boosts(true)
			if renea_boosts.is_empty():
				return
			var renea_sustain_choices = [{"_choice_text": "Pass", "effect_type": "pass"}]
			for renea_sb in renea_boosts:
				renea_sustain_choices.append({
					"effect_type": "renea_mimetism_sustain_do",
					"boost_id": renea_sb.id,
					"_choice_text": "Sustain %s (2F)" % card_db.get_card_name(renea_sb.id)
				})
			do_effect_if_condition_met(performing_player, card_id, {
				"effect_type": StrikeEffects.ForceForEffect,
				"force_max": 2,
				"per_force_effect": null,
				"overall_effect": {
					"effect_type": StrikeEffects.Choice,
					StrikeEffects.Choice: renea_sustain_choices,
					"override_description": "Sustain a Continuous Boost?"
				},
				"override_description": "Spend 2 Force to sustain a Continuous Boost"
			}, null)
		"renea_mimetism_sustain_do":
			var renea_ms_id = effect.get("boost_id", -1)
			if renea_ms_id == -1 or not performing_player.is_card_in_continuous_boosts(renea_ms_id):
				return
			if renea_ms_id not in performing_player.sustained_boosts:
				performing_player.sustained_boosts.append(renea_ms_id)
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "sustains a Continuous Boost.")
		"renea_pakout":
			# Pakout: return this card to hand, then draw a card
			if card_id == -1:
				return
			var renea_pakout_card = null
			for renea_pc in performing_player.continuous_boosts:
				if renea_pc.id == card_id:
					renea_pakout_card = renea_pc
					break
			if renea_pakout_card:
				performing_player.remove_from_continuous_boosts(renea_pakout_card)
				performing_player.add_to_hand(renea_pakout_card, true)
				performing_player.draw(1)
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "Pakout: returns to hand and draws a card.")
			else:
				# Face-up placement resolves now/immediate effects BEFORE the boost is
				# added to continuous_boosts, so the card is not there yet. Cancel the
				# boost being played directly and finish it without placing it.
				if active_boost != null and active_boost.card != null and active_boost.card.id == card_id:
					performing_player.add_to_hand(active_boost.card, true)
					performing_player.draw(1)
					active_boost.discard_on_cleanup = true
					active_boost.discarded_already = true
					_append_log_full(Enums.LogType.LogType_Effect, performing_player, "Pakout: returns to hand and draws a card.")
		"renea_retreat_if_boost":
			# Lethal Force hit: if continuous boost in play, retreat 1
			if performing_player.get_boosts().size() > 0:
				do_effect_if_condition_met(performing_player, card_id, {
					"effect_type": StrikeEffects.Retreat,
					"amount": 1
				}, null)
		"renea_called_shot":
			# Called Shot hit: uses engine's name_card_opponent_discards (same as Block Parry)
			# Defined in JSON with discard_effect for +6 Power
			pass
		"renea_discard_opponent_gauge":
			# Neutralizer hit: if opponent exceeded, discard 2 from gauge
			var renea_dg_opp = _get_player(get_other_player(performing_player.my_id))
			if not renea_dg_opp.exceeded:
				return
			var renea_dg_amount = min(effect.get("amount", 2), renea_dg_opp.gauge.size())
			if renea_dg_amount <= 0:
				return
			var renea_dg_effect = {
				"effect_type": StrikeEffects.DiscardOpponentGauge,
				"amount2": 1
			}
			for _discard_index in range(1, renea_dg_amount):
				renea_dg_effect = {
					"effect_type": StrikeEffects.DiscardOpponentGauge,
					"amount2": 1,
					"and": renea_dg_effect
				}
			do_effect_if_condition_met(performing_player, card_id, renea_dg_effect, null)
		"renea_conspiracy_unearthed":
			# Conspiracy Unearthed: reveal opponent's hand, add your choice to gauge
			var renea_cu_opp = _get_player(get_other_player(performing_player.my_id))
			renea_cu_opp.reveal_hand()
			var renea_cu_choices = []
			for renea_cu_card in renea_cu_opp.hand:
				renea_cu_choices.append({
					"effect_type": "renea_conspiracy_unearthed_do",
					"card_id": renea_cu_card.id,
					"_choice_text": "Add %s to gauge" % card_db.get_card_name(renea_cu_card.id)
				})
			if renea_cu_choices.is_empty():
				return
			do_effect_if_condition_met(performing_player, card_id, {
				"effect_type": StrikeEffects.Choice,
				StrikeEffects.Choice: renea_cu_choices,
				"override_description": "Opponent's hand is revealed. Choose a card to add to their Gauge."
			}, null)
		"renea_conspiracy_unearthed_do":
			var renea_cu_id = effect.get("card_id", -1)
			if renea_cu_id == -1:
				return
			var renea_cu_opp = _get_player(get_other_player(performing_player.my_id))
			if not renea_cu_opp.is_card_in_hand(renea_cu_id):
				return
			var renea_cu_card = card_db.get_card(renea_cu_id)
			renea_cu_opp.remove_card_from_hand(renea_cu_id, true, false)
			renea_cu_opp.add_to_gauge(renea_cu_card)
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "%s is added to opponent's gauge." % _log_card_name(card_db.get_card_name(renea_cu_id)))
		"renea_pre_strike_reveal":
			# Minato pattern: collect facedown effects, process sequentially, fire FSS when done
			# Supports order choice when multiple "now" effects exist
			var renea_fd_list = []
			for renea_bc in performing_player.continuous_boosts:
				if renea_bc.definition.get("boost") and renea_bc.definition["boost"].get("facedown") and _renea_boost_has_now_effect(renea_bc):
					for renea_e in renea_bc.definition['boost'].get('effects', []):
						if renea_e['timing'] == "now":
							renea_fd_list.append({"card_id": renea_bc.id, "effect": renea_e})
			_renea_reveal_all_facedown_boosts(performing_player)
			if renea_fd_list.size() == 0:
				# No Now effects to process; all face-down boosts were still revealed.
				performing_player.renea_facedown_revealed = true
				active_character_action = false
				performing_player.renea_pre_strike_effects = []
				performing_player.renea_pre_strike_index = 0
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_None
				if performing_player.renea_pre_strike_response and active_strike:
					strike_setup_defender_response()
				else:
					create_silent_pre_strike_event(performing_player)
					change_game_state(Enums.GameState.GameState_PickAction)
				performing_player.renea_pre_strike_response = false
				return
			performing_player.renea_pre_strike_effects = renea_fd_list
			performing_player.renea_pre_strike_index = 0
			performing_player.renea_facedown_revealed = true
			# Order choice: if multiple "now" effects and human player, ask which to resolve first
			if renea_fd_list.size() > 1 and performing_player.my_id == Enums.PlayerId.PlayerId_Player:
				var renea_order_choices = []
				for renea_oi in range(renea_fd_list.size()):
					var renea_item = renea_fd_list[renea_oi]
					var renea_od = renea_item["effect"].get("override_description", "")
					if renea_od.is_empty():
						renea_od = renea_item["effect"].get("effect_type", "").capitalize()
						if renea_item["effect"].has("amount"):
							renea_od += " " + str(renea_item["effect"]["amount"])
					renea_order_choices.append({
						"effect_type": "renea_fd_order_first",
						"pre_strike_idx": renea_oi,
						"_choice_text": renea_od
					})
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_EffectChoice
				decision_info.player = performing_player.my_id
				decision_info.choice = renea_order_choices
				decision_info.choice_card_id = -1
				decision_info.effect_type = "renea_fd_order_pre_strike"
				create_event(Enums.EventType.EventType_Strike_EffectChoice, performing_player.my_id, 0, "Reveal Order")
				return
			# Single effect or AI: process directly
			_renea_process_next(performing_player)
		"renea_pre_strike_done":
			# All facedown effects processed
			active_character_action = false
			performing_player.renea_pre_strike_effects = []
			performing_player.renea_pre_strike_index = 0
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_None
			if performing_player.renea_pre_strike_needs_fss:
				# Pre-strike: fire ForceStartStrike to enter strike selection
				create_silent_pre_strike_event(performing_player)
				change_game_state(Enums.GameState.GameState_PickAction)
			elif performing_player.renea_pre_strike_response and active_strike:
				# Response: the strike already exists; resume defender card selection.
				strike_setup_defender_response()
			performing_player.renea_pre_strike_needs_fss = true  # reset to default
			performing_player.renea_pre_strike_response = false
		"renea_reveal_fd_do":
			# Player chose a specific boost to resolve first; reorder remaining list
			var renea_fd_idx = effect.get("boost_idx", -1)
			if renea_fd_idx >= 0:
				var renea_fd_player = performing_player
				var renea_fd_reorder = []
				for renea_fd_bc in renea_fd_player.continuous_boosts:
					if renea_fd_bc.definition.get("boost") and renea_fd_bc.definition["boost"].get("facedown"):
						renea_fd_reorder.append(renea_fd_bc.id)
				if renea_fd_idx < renea_fd_reorder.size():
					var chosen_id = renea_fd_reorder[renea_fd_idx]
					renea_fd_reorder.erase(chosen_id)
					renea_fd_reorder.insert(0, chosen_id)
					renea_fd_player.renea_fd_pending = renea_fd_reorder
		"renea_fd_order_first":
			# Pre-strike order choice: move chosen effect to current processing position
			var renea_order_idx = effect.get("pre_strike_idx", -1)
			var renea_base_idx = performing_player.renea_pre_strike_index
			if renea_order_idx >= 0 and renea_order_idx < performing_player.renea_pre_strike_effects.size() and renea_order_idx != renea_base_idx:
				var chosen = performing_player.renea_pre_strike_effects[renea_order_idx]
				performing_player.renea_pre_strike_effects.remove_at(renea_order_idx)
				performing_player.renea_pre_strike_effects.insert(renea_base_idx, chosen)
			_renea_process_next(performing_player)
		"renea_polling_leads":
			# Polling Leads: after resolving a boost, spend 1F, Move 1 (choice advance/retreat)
			do_effect_if_condition_met(performing_player, card_id, {
				"effect_type": StrikeEffects.ForceForEffect,
				"force_max": 1,
				"per_force_effect": null,
				"overall_effect": {
					"effect_type": StrikeEffects.Choice,
					StrikeEffects.Choice: [
						{"effect_type": StrikeEffects.Advance, "amount": 1},
						{"effect_type": StrikeEffects.Retreat, "amount": 1}
					]
				},
				"override_description": "Spend 1 Force to Move 1 (Polling Leads)"
			}, null)
		"renea_briefcase_hit":
			# Exceed passive hit: put the BOTTOM-most boost card of opponent's
			# discard into briefcase. Bottom = discards[0] (top of the pile is
			# the end of the array), so scan from index 0 upward.
			var renea_bh_opp = _get_player(get_other_player(performing_player.my_id))
			for renea_bh_i in range(renea_bh_opp.discards.size()):
				var renea_bh_card = renea_bh_opp.discards[renea_bh_i]
				var renea_bh_boost = renea_bh_card.definition.get("boost", {})
				var renea_bh_bt = renea_bh_boost.get("boost_type", "")
				if renea_bh_bt in ["continuous", "immediate"]:
					renea_bh_opp.remove_card_from_discards(renea_bh_card.id)
					performing_player.add_to_briefcase(renea_bh_card)
					_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "adds %s from bottom of opponent's discard to Briefcase." % _log_card_name(card_db.get_card_name(renea_bh_card.id)))
					break
		"renea_on_exceed":
			# On exceed: put top 3 cards of opponent's discard with continuous/immediate boosts into briefcase
			# Top of the discard pile is the END of the array, so scan downward
			# from the last index (removal above the cursor never shifts what we
			# already passed).
			var renea_oe_opp = _get_player(get_other_player(performing_player.my_id))
			var renea_oe_count = 0
			var renea_oe_i = renea_oe_opp.discards.size() - 1
			while renea_oe_i >= 0 and renea_oe_count < 3:
				var renea_oe_card = renea_oe_opp.discards[renea_oe_i]
				var renea_oe_boost = renea_oe_card.definition.get("boost", {})
				var renea_oe_bt = renea_oe_boost.get("boost_type", "")
				if renea_oe_bt in ["continuous", "immediate"]:
					renea_oe_opp.remove_card_from_discards(renea_oe_card.id)
					performing_player.add_to_briefcase(renea_oe_card)
					renea_oe_count += 1
					_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "adds %s to Briefcase." % _log_card_name(card_db.get_card_name(renea_oe_card.id)))
				renea_oe_i -= 1
			if renea_oe_count > 0:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "Briefcase now contains %s card(s)." % performing_player.set_aside_cards.size())
			# Reveal all facedown boosts and resolve their Now effects (pre-strike mechanism for PlayerDecision recovery)
			var renea_fd_effects = []
			for renea_bc in performing_player.continuous_boosts:
				if renea_bc.definition.get("boost") and renea_bc.definition["boost"].get("facedown"):
					for renea_e in renea_bc.definition['boost'].get('effects', []):
						if renea_e['timing'] == "now":
							renea_fd_effects.append({"card_id": renea_bc.id, "effect": renea_e})
			if renea_fd_effects.size() == 0:
				return
			performing_player.renea_pre_strike_effects = renea_fd_effects
			performing_player.renea_pre_strike_index = 0
			performing_player.renea_pre_strike_needs_fss = false  # exceed: don't fire ForceStartStrike
			performing_player.renea_facedown_revealed = true
			active_character_action = true
			if renea_fd_effects.size() > 1 and performing_player.my_id == Enums.PlayerId.PlayerId_Player:
				var renea_order_choices = []
				for renea_oi in range(renea_fd_effects.size()):
					var renea_item = renea_fd_effects[renea_oi]
					var renea_od = renea_item["effect"].get("override_description", "")
					if renea_od.is_empty():
						renea_od = renea_item["effect"].get("effect_type", "").capitalize()
						if renea_item["effect"].has("amount"):
							renea_od += " " + str(renea_item["effect"]["amount"])
					renea_order_choices.append({
						"effect_type": "renea_fd_order_first",
						"pre_strike_idx": renea_oi,
						"_choice_text": renea_od
					})
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_EffectChoice
				decision_info.player = performing_player.my_id
				decision_info.choice = renea_order_choices
				decision_info.choice_card_id = -1
				decision_info.effect_type = "renea_fd_order_pre_strike"
				create_event(Enums.EventType.EventType_Strike_EffectChoice, performing_player.my_id, 0, "Reveal Order")
				return
			_renea_process_next(performing_player)
		# ===== UMINA HANDLERS START =====
		"umina_place_hand_to_dreamlands":
			# Action: put a card from hand into Dreamlands (set_aside)
			if performing_player.exceeded:
				return
			# Uses CardFromHandToGauge UI to let player pick a card from hand
			var umina_ph_valid = []
			for umina_ph_c in performing_player.hand:
				# Shadow Chorus cannot enter Dreamlands
				if umina_ph_c.definition.get("id") == "umina_shadow_chorus":
					continue
				umina_ph_valid.append(umina_ph_c.id)
			if umina_ph_valid.size() == 0:
				return
			change_game_state(Enums.GameState.GameState_PlayerDecision)
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_CardFromHandToGauge
			decision_info.player = performing_player.my_id
			decision_info.choice_card_id = card_id
			decision_info.destination = "umina_dreamlands"
			decision_info.amount = 1
			decision_info.amount_min = 1
			decision_info.effect = {"restricted_to_card_ids": umina_ph_valid}
			create_event(Enums.EventType.EventType_CardFromHandToGauge_Choice, performing_player.my_id, 1, "", 1)
		"umina_place_hand_to_dreamlands_do":
			var umina_phd_card_id = effect.get("card_id_to_add", -1)
			if umina_phd_card_id < 0:
				return
			# Remove old card from Dreamlands first (discard if pre-exceed, return to hand if exceeded)
			if performing_player.set_aside_cards.size() > 0:
				var umina_phd_old = performing_player.set_aside_cards[0]
				if performing_player.exceeded:
					performing_player.add_to_hand(umina_phd_old, not performing_player.umina_dreamlands_facedown)
				else:
					performing_player.add_to_discards(umina_phd_old)
				performing_player.remove_card_from_set_aside(umina_phd_old.id)
			# Put chosen card into Dreamlands
			var umina_phd_card = card_db.get_card(umina_phd_card_id)
			performing_player.remove_card_from_hand(umina_phd_card_id, not performing_player.umina_dreamlands_facedown, false)
			performing_player.add_to_set_aside(umina_phd_card)
			if performing_player.umina_dreamlands_facedown:
				performing_player.umina_facedown_hand_dreamlands_id = umina_phd_card_id
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "places %s into Dreamlands." % _log_card_name(umina_phd_card_id))
			create_event(Enums.EventType.EventType_AddToStored, performing_player.my_id, umina_phd_card_id)
			_umina_check_slipping_away(performing_player, umina_phd_card_id)
		"umina_begin_turn_dreamlands":
			# Exceeded passive: look at top of deck, put into Dreamlands or discard
			if not performing_player.exceeded:
				return
			if performing_player.deck.size() == 0:
				return
			var umina_bt_card = performing_player.deck[0]
			var umina_bt_card_name = card_db.get_card_name(umina_bt_card.id)
			var umina_bt_choices = []
			# Shadow Chorus cannot enter Dreamlands
			if umina_bt_card.definition.get("id") != "umina_shadow_chorus":
				umina_bt_choices.append({"effect_type": "umina_begin_turn_dreamlands_put", "card_id": umina_bt_card.id, "override_description": "Put %s into Dreamlands" % umina_bt_card_name})
			umina_bt_choices.append({"effect_type": "umina_begin_turn_dreamlands_discard", "card_id": umina_bt_card.id, "override_description": "Discard %s" % umina_bt_card_name})
			do_effect_if_condition_met(performing_player, card_id, {
				"effect_type": StrikeEffects.Choice,
				StrikeEffects.Choice: umina_bt_choices,
				"override_description": "Dreamlands: Top card is %s" % umina_bt_card_name
			}, null)
		"umina_begin_turn_dreamlands_put":
			var umina_btp_card_id = effect.get("card_id", -1)
			if umina_btp_card_id < 0 or performing_player.deck.size() == 0:
				return
			# Handle old Dreamlands card
			if performing_player.set_aside_cards.size() > 0:
				var umina_btp_old = performing_player.set_aside_cards[0]
				if umina_btp_old.owner_id != performing_player.my_id:
					var umina_btp_owner = _get_player(umina_btp_old.owner_id)
					umina_btp_owner.add_to_hand(umina_btp_old, true)
				else:
					performing_player.add_to_hand(umina_btp_old, not performing_player.umina_dreamlands_facedown)
				performing_player.remove_card_from_set_aside(umina_btp_old.id)
			# Put topdeck into Dreamlands
			var umina_btp_card = card_db.get_card(umina_btp_card_id)
			performing_player.remove_card_from_deck(umina_btp_card_id)
			performing_player.add_to_set_aside(umina_btp_card)
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "puts topdeck into Dreamlands.")
			create_event(Enums.EventType.EventType_AddToStored, performing_player.my_id, umina_btp_card_id)
			_umina_check_slipping_away(performing_player, umina_btp_card_id)
		"umina_begin_turn_dreamlands_discard":
			var umina_btd_card_id = effect.get("card_id", -1)
			if umina_btd_card_id < 0 or performing_player.deck.size() == 0:
				return
			performing_player.discard([umina_btd_card_id])
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "discards topdeck.")
		"umina_flip_dreamlands":
			# On exceed: refresh buddy display (handled by event system)
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "Dreamlands flips to its exceeded side.")
		"umina_place_discard_to_dreamlands":
			# Terror Whispers hit: put a card from discard into Dreamlands
			# Uses engine's ChooseFromDiscard UI instead of choice list
			if performing_player.discards.size() == 0:
				return
			var umina_pdd_has_valid = false
			for umina_pdd_c in performing_player.discards:
				if umina_pdd_c.definition.get("id") != "umina_shadow_chorus":
					umina_pdd_has_valid = true
					break
			if not umina_pdd_has_valid:
				return
			change_game_state(Enums.GameState.GameState_PlayerDecision)
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_ChooseFromDiscard
			decision_info.player = performing_player.my_id
			decision_info.choice_card_id = card_id
			decision_info.source = "discard"
			decision_info.destination = "umina_dreamlands"
			decision_info.amount = 1
			decision_info.amount_min = 1
			decision_info.limitation = ""
			create_event(Enums.EventType.EventType_ChooseFromDiscard, performing_player.my_id, 0)
		"umina_place_discard_to_dreamlands_do":
			var umina_pdd_card_id = effect.get("card_id_to_add", -1)
			if umina_pdd_card_id < 0:
				return
			# Handle old Dreamlands card
			if performing_player.set_aside_cards.size() > 0:
				var umina_pdd_old = performing_player.set_aside_cards[0]
				if performing_player.exceeded and umina_pdd_old.owner_id != performing_player.my_id:
					var umina_pdd_owner = _get_player(umina_pdd_old.owner_id)
					umina_pdd_owner.add_to_hand(umina_pdd_old, true)
				elif performing_player.exceeded:
					performing_player.add_to_hand(umina_pdd_old, not performing_player.umina_dreamlands_facedown)
				else:
					performing_player.add_to_discards(umina_pdd_old)
				performing_player.remove_card_from_set_aside(umina_pdd_old.id)
			var umina_pdd_card = card_db.get_card(umina_pdd_card_id)
			performing_player.remove_card_from_discards(umina_pdd_card_id)
			performing_player.add_to_set_aside(umina_pdd_card)
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "puts card from discard into Dreamlands.")
			create_event(Enums.EventType.EventType_AddToStored, performing_player.my_id, umina_pdd_card_id)
		"umina_out_of_mind_hit":
			# Out of Mind hit: Dreamlands card → gauge + Power, or all hand → gauge + draw 3
			if performing_player.set_aside_cards.size() > 0:
				# Dreamlands has a card: add it to gauge, gain power
				var umina_oom_card = performing_player.set_aside_cards[0]
				if umina_oom_card.id not in performing_player.umina_revealed_dreamlands_ids:
					performing_player.umina_revealed_dreamlands_ids.append(umina_oom_card.id)
					create_event(Enums.EventType.EventType_RevealCard, performing_player.my_id, umina_oom_card.id)
					_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "reveals %s from Dreamlands!" % _log_card_name(card_db.get_card_name(umina_oom_card.id)))
				var umina_oom_power = umina_oom_card.definition.get("power", 0)
				if typeof(umina_oom_power) == TYPE_STRING:
					umina_oom_power = 0
				umina_oom_power = mini(umina_oom_power, 5)
				performing_player.remove_card_from_set_aside(umina_oom_card.id)
				performing_player.add_to_gauge(umina_oom_card)
				if umina_oom_power > 0:
					performing_player.strike_stat_boosts.power += umina_oom_power
					create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, umina_oom_power)
			else:
				# No Dreamlands card: move all hand to gauge, draw 3
				var umina_oom_hand_cards = performing_player.hand.duplicate()
				for umina_oom_hc in umina_oom_hand_cards:
					performing_player.remove_card_from_hand(umina_oom_hc.id, true, false)
					performing_player.add_to_gauge(umina_oom_hc)
				performing_player.draw(3)
		"umina_slipping_away":
			# Slipping Away: persistent passive, checked after each card placed into Dreamlands
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "Slipping Away active.")
		"umina_slipping_away_move":
			var umina_sa_choices = [
				{"effect_type": "advance", "amount": 1},
				{"effect_type": "retreat", "amount": 1}
			]
			do_effect_if_condition_met(performing_player, card_id, {
				"effect_type": StrikeEffects.Choice,
				StrikeEffects.Choice: umina_sa_choices,
				"override_description": "Slipping Away: Move 1"
			}, null)
		"umina_dark_reflections":
			# Dark Reflections: name a card, opponent discards copy or reveals hand
			# Uses engine's built-in NameCard_OpponentDiscards system with discard_effect
			do_effect_if_condition_met(performing_player, card_id, {
				"effect_type": StrikeEffects.NameCardOpponentDiscards,
				"discard_effect": { "effect_type": "umina_dark_reflections_place" }
			}, null)
		"umina_dark_reflections_place":
			# Called as discard_effect from NameCardOpponentDiscards / Dark Reflections
			# opposing_player just discarded a card (the named copy); move it to Dreamlands
			# Search discards first, then sealed (Celinka seal_instead_of_discarding)
			var umina_pd_card = null
			if opposing_player.discards.size() > 0:
				umina_pd_card = opposing_player.discards[opposing_player.discards.size() - 1]
			elif opposing_player.sealed.size() > 0:
				umina_pd_card = opposing_player.sealed[opposing_player.sealed.size() - 1]
			if umina_pd_card == null:
				return
			# Handle old Dreamlands card (return to its owner's hand when exceeded)
			if performing_player.set_aside_cards.size() > 0:
				var umina_pd_old = performing_player.set_aside_cards[0]
				if performing_player.exceeded and umina_pd_old.owner_id != performing_player.my_id:
					var umina_pd_owner = _get_player(umina_pd_old.owner_id)
					umina_pd_owner.add_to_hand(umina_pd_old, true)
				elif performing_player.exceeded:
					performing_player.add_to_hand(umina_pd_old, not performing_player.umina_dreamlands_facedown)
				else:
					performing_player.add_to_discards(umina_pd_old)
				performing_player.remove_card_from_set_aside(umina_pd_old.id)
			# Move the discarded card to Dreamlands (from discards or sealed)
			if umina_pd_card in opposing_player.discards:
				opposing_player.remove_card_from_discards(umina_pd_card.id)
			elif umina_pd_card in opposing_player.sealed:
				opposing_player.remove_card_from_sealed(umina_pd_card.id)
			performing_player.add_to_set_aside(umina_pd_card)
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "puts %s into Dreamlands via Dark Reflections." % _log_card_name(umina_pd_card.id))
			create_event(Enums.EventType.EventType_AddToStored, performing_player.my_id, umina_pd_card.id)
			_umina_check_slipping_away(performing_player, umina_pd_card.id)
		"umina_dark_thoughts_hit":
			# Dark Thoughts hit: opponent discards random 1, offer to put it into Dreamlands
			var umina_dt_before = opposing_player.discards.size()
			do_effect_if_condition_met(opposing_player, card_id, {
				"effect_type": StrikeEffects.DiscardRandom,
				"amount": 1
			}, null)
			var umina_dt_after = opposing_player.discards.size()
			if umina_dt_after > umina_dt_before:
				# A card was discarded, offer to put it into Dreamlands
				var umina_dt_new_discards = []
				for umina_dt_c in opposing_player.discards:
					var found = false
					for umina_dt_bc in opposing_player.discards.slice(0, umina_dt_before):
						if umina_dt_c.id == umina_dt_bc.id:
							found = true
							break
					if not found:
						umina_dt_new_discards.append(umina_dt_c)
				if umina_dt_new_discards.size() > 0:
					var umina_dt_discarded = umina_dt_new_discards[0]
					var umina_dt_card_name = card_db.get_card_name(umina_dt_discarded.id)
					# Shadow Chorus can never enter Dreamlands, so it cannot be placed
					var umina_dt_choices = []
					if umina_dt_discarded.definition.get("id") != "umina_shadow_chorus":
						umina_dt_choices.append({"effect_type": "umina_dark_thoughts_place", "card_id": umina_dt_discarded.id, "override_description": "将%s放入幻梦境" % umina_dt_card_name})
					umina_dt_choices.append({"effect_type": StrikeEffects.Pass, "override_description": "不把%s放入幻梦境" % umina_dt_card_name})
					do_effect_if_condition_met(performing_player, card_id, {
						"effect_type": StrikeEffects.Choice,
						StrikeEffects.Choice: umina_dt_choices,
						"override_description": "Dark Thoughts：对手弃置了%s" % umina_dt_card_name
					}, null)
		"umina_dark_thoughts_place":
			# Dark Thoughts hit choice: put the discarded card into Dreamlands
			var umina_dtp_id = effect.get("card_id", -1)
			if umina_dtp_id < 0:
				return
			var umina_dtp_card = null
			for umina_dtp_c in opposing_player.discards:
				if umina_dtp_c.id == umina_dtp_id:
					umina_dtp_card = umina_dtp_c
					break
			if umina_dtp_card == null:
				return
			# Handle old Dreamlands card (return to its owner's hand when exceeded)
			if performing_player.set_aside_cards.size() > 0:
				var umina_dtp_old = performing_player.set_aside_cards[0]
				if performing_player.exceeded and umina_dtp_old.owner_id != performing_player.my_id:
					var umina_dtp_owner = _get_player(umina_dtp_old.owner_id)
					umina_dtp_owner.add_to_hand(umina_dtp_old, true)
				elif performing_player.exceeded:
					performing_player.add_to_hand(umina_dtp_old, not performing_player.umina_dreamlands_facedown)
				else:
					performing_player.add_to_discards(umina_dtp_old)
				performing_player.remove_card_from_set_aside(umina_dtp_old.id)
			opposing_player.remove_card_from_discards(umina_dtp_id)
			performing_player.add_to_set_aside(umina_dtp_card)
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "puts discarded card into Dreamlands.")
			create_event(Enums.EventType.EventType_AddToStored, performing_player.my_id, umina_dtp_id)
			_umina_check_slipping_away(performing_player, umina_dtp_id)
		"umina_shadow_chorus_copy":
			# Shadow Chorus reveal: copy card from Dreamlands
			if performing_player.set_aside_cards.size() == 0:
				return  # No Dreamlands card, use own stats
			var umina_sc_copy = performing_player.set_aside_cards[0]
			if umina_sc_copy.id not in performing_player.umina_revealed_dreamlands_ids:
				performing_player.umina_revealed_dreamlands_ids.append(umina_sc_copy.id)
				create_event(Enums.EventType.EventType_RevealCard, performing_player.my_id, umina_sc_copy.id)
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "reveals %s from Dreamlands!" % _log_card_name(card_db.get_card_name(umina_sc_copy.id)))
			var umina_sc_def = umina_sc_copy.definition
			# Replace the strike card's definition with a copy of the Dreamlands card
			# This is temporary for this strike; the modified card goes to gauge/discard after
			var umina_sc_card = active_strike.get_player_card(performing_player)
			if umina_sc_card != null:
				if not performing_player.umina_shadow_chorus_restore.has(umina_sc_card.id):
					performing_player.umina_shadow_chorus_restore[umina_sc_card.id] = umina_sc_card.definition.duplicate(true)
				umina_sc_card.definition = umina_sc_def.duplicate(true)
				if not performing_player.exceeded and performing_player.deck_def.get("id") == "umina" and performing_player.deck_def.get("dreamlands_config", {}).get("stun_immunity"):
					performing_player.strike_stat_boosts.stun_immunity = true
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "copies %s from Dreamlands." % _log_card_name(umina_sc_copy.id))
			else:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "Shadow Chorus has no strike card to replace.")
		"umina_whispers_in_the_dark":
			# Whispers in the Dark: draw 1, then copy Dreamlands card's instant boost
			performing_player.draw(1)
			if performing_player.set_aside_cards.size() == 0:
				return
			var umina_witd_card = performing_player.set_aside_cards[0]
			if umina_witd_card.id not in performing_player.umina_revealed_dreamlands_ids:
				performing_player.umina_revealed_dreamlands_ids.append(umina_witd_card.id)
				create_event(Enums.EventType.EventType_RevealCard, performing_player.my_id, umina_witd_card.id)
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "reveals %s from Dreamlands!" % _log_card_name(card_db.get_card_name(umina_witd_card.id)))
			var umina_witd_boost = umina_witd_card.definition.get("boost", {})
			if umina_witd_boost.get("boost_type") == "immediate":
				# Execute the Dreamlands card's instant boost effect, ignoring force cost.
				# 逐条结算，并在产生玩家决策时中断、把剩余效果排队等玩家决策完后继续：
				# 若同步跑完整个列表，「专注 Reading = reading_normal + strike」这种
				# 先让玩家声明一张普通技、再发起战斗的加成，后续的 strike 会直接把
				# ReadingNormal 决策覆盖成 StrikeNow，玩家就再也选不到牌。
				# （对齐 continue_resolve_boost / _renea_process_next 的中断语义。）
				var umina_witd_immediate_effects = []
				for umina_witd_ef in umina_witd_boost.get("effects", []):
					if umina_witd_ef.get("timing") == "immediate":
						umina_witd_immediate_effects.append(umina_witd_ef)
				for umina_witd_idx in range(umina_witd_immediate_effects.size()):
					do_effect_if_condition_met(performing_player, umina_witd_card.id, umina_witd_immediate_effects[umina_witd_idx], null)
					if game_state == Enums.GameState.GameState_PlayerDecision or game_over:
						var umina_witd_remaining = umina_witd_immediate_effects.slice(umina_witd_idx + 1)
						if umina_witd_remaining.size() > 0:
							add_queued_effects(umina_witd_remaining)
						break
		"umina_unknown_khadath":
			# Unknown Khadath before: swallow opponent attack
			if active_strike == null:
				return
			var umina_uk_card = active_strike.get_player_card(opposing_player)
			if umina_uk_card != null and umina_uk_card.definition.get("type") != "faceattack":
				if opposing_player.umina_shadow_chorus_restore.has(umina_uk_card.id):
					umina_uk_card.definition = opposing_player.umina_shadow_chorus_restore[umina_uk_card.id].duplicate(true)
					opposing_player.umina_shadow_chorus_restore.erase(umina_uk_card.id)
				# Put opponent's attack into Dreamlands
				if performing_player.set_aside_cards.size() > 0:
					var umina_uk_old = performing_player.set_aside_cards[0]
					if performing_player.exceeded and umina_uk_old.owner_id != performing_player.my_id:
						var umina_uk_owner = _get_player(umina_uk_old.owner_id)
						umina_uk_owner.add_to_hand(umina_uk_old, true)
					elif performing_player.exceeded:
						performing_player.add_to_hand(umina_uk_old, not performing_player.umina_dreamlands_facedown)
					else:
						performing_player.add_to_discards(umina_uk_old)
					performing_player.remove_card_from_set_aside(umina_uk_old.id)
				performing_player.add_to_set_aside(umina_uk_card)
				create_event(Enums.EventType.EventType_AddToStored, performing_player.my_id, umina_uk_card.id)
				_umina_check_slipping_away(performing_player, umina_uk_card.id)
				# Add Khadath itself to gauge
				var umina_uk_self = active_strike.get_player_card(performing_player)
				if umina_uk_self != null:
					active_strike.cards_in_play.erase(umina_uk_self)
					performing_player.add_to_gauge(umina_uk_self)
				# End the strike — set flag, state machine skips to Cleanup
				active_strike.cards_in_play.clear()
				active_strike.remaining_effect_list.clear()
				active_strike.unknown_khadath_used = true
		"umina_dream_telling_power":
			# Dream Telling before: +P equal to Dreamlands card power (max +5)
			if performing_player.set_aside_cards.size() > 0:
				var umina_dt_card = performing_player.set_aside_cards[0]
				var umina_dt_power = umina_dt_card.definition.get("power", 0)
				if typeof(umina_dt_power) == TYPE_STRING:
					umina_dt_power = 0
				umina_dt_power = mini(umina_dt_power, 5)
				if umina_dt_power > 0:
					performing_player.strike_stat_boosts.power += umina_dt_power
					create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, umina_dt_power)
		"umina_call_of_dreamlands_hit":
			# Call of Dreamlands hit: reveal hands, +1P per special/ultra
			performing_player.reveal_hand()
			opposing_player.reveal_hand()
			var umina_cod_count = 0
			for umina_cod_card in performing_player.hand:
				if umina_cod_card.definition.get("type") in ["special", "ultra"]:
					umina_cod_count += 1
			for umina_cod_card in opposing_player.hand:
				if umina_cod_card.definition.get("type") in ["special", "ultra"]:
					umina_cod_count += 1
			if umina_cod_count > 0:
				performing_player.strike_stat_boosts.power += umina_cod_count
				create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, umina_cod_count)
		"umina_spiraling_descent":
			# Spiraling Descent: opponent cannot boost/attack with copies of Dreamlands card
			# Target is now read dynamically from Dreamlands via get_umina_spiraling_target()
			# Disabled if The Sleeper Wakes (from Call of the Dreamlands) is active
			if performing_player.has_transform("umina_call_of_the_dreamlands"):
				return
			if performing_player.set_aside_cards.size() > 0:
				var umina_sd_card = performing_player.set_aside_cards[0]
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "Spiraling Descent: copies of %s are invalid for opponent." % _log_card_name(umina_sd_card.id))
		"umina_sleeper_wakes":
			# The Sleeper Wakes: cards enter Dreamlands face-down
			performing_player.umina_dreamlands_facedown = true
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "Dreamlands cards will enter face-down.")
		"umina_terror_whispers_action":
			# Action: pay 2 gauge, then initiate a strike that forces opponent wild swing.
			if performing_player.get_available_gauge() < 2:
				return
			do_effect_if_condition_met(performing_player, card_id, {
				"effect_type": StrikeEffects.GaugeForEffect,
				"gauge_max": 2,
				"min_gauge": 2,
				"per_gauge_effect": null,
				"can_pass": true,
				"pass_as_cancel_to_pick_action": true,
				"overall_effect": {
					"effect_type": "umina_terror_whispers_start_strike"
				},
				"override_description": "花费2怒气以发起一场战斗"
			}, null)
		"umina_terror_whispers_start_strike":
			performing_player.opponent_next_strike_forced_wild_swing = true
			do_effect_if_condition_met(performing_player, card_id, {"effect_type": StrikeEffects.Strike}, null)
		"umina_seal_dreamlands_for_triggers":
			# set_strike: offer to seal Dreamlands card for attack triggers
			# Works both non-exceeded and exceeded (same timing as Iquais' exceed set_strike)
			if performing_player.set_aside_cards.size() == 0:
				return
			var umina_sdt_card = performing_player.set_aside_cards[0]
			var umina_sdt_card_name = card_db.get_card_name(umina_sdt_card.id)
			do_effect_if_condition_met(performing_player, -1, {
				"effect_type": StrikeEffects.Choice,
				StrikeEffects.Choice: [
					{
						"effect_type": "umina_do_seal_dreamlands",
						"card_id": umina_sdt_card.id,
						"override_description": "Seal %s to add its effects" % umina_sdt_card_name
					},
					{ "effect_type": "pass", "override_description": "Don't seal" }
				],
				"override_description": "Seal Dreamlands card for attack triggers?"
			}, null)
		"umina_do_seal_dreamlands":
			# Execute the seal + add_attack_triggers
			var umina_sd_card_id = effect.get("card_id", -1)
			if umina_sd_card_id < 0 or not performing_player.is_card_in_set_aside(umina_sd_card_id):
				return
			do_seal_effect(performing_player, umina_sd_card_id, "set_aside")
			add_attack_triggers(performing_player, [umina_sd_card_id], true)
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "seals Dreamlands card to add its effects to the attack!")
		"syrus_exceed_boost_to_gauge":
			var syrus_boosts = performing_player.continuous_boosts.duplicate()
			for syrus_boost in syrus_boosts:
				var boost_name = _get_boost_and_card_name(syrus_boost)
				performing_player.remove_from_continuous_boosts(syrus_boost, "gauge")
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将持续加成%s加入怒气。" % boost_name)
		"syrus_add_hand_to_gauge":
			var syrus_h2g_choices = []
			for syrus_hc in performing_player.hand:
				syrus_h2g_choices.append({
					"effect_type": "syrus_add_hand_to_gauge_internal",
					"card_id_to_add": syrus_hc.id,
					"override_description": "Add %s to gauge" % card_db.get_card_name(syrus_hc.id)
				})
			do_effect_if_condition_met(performing_player, card_id, {
				"effect_type": StrikeEffects.Choice,
				StrikeEffects.Choice: syrus_h2g_choices,
				"override_description": "Add a card from hand to gauge"
			}, null)
		"syrus_add_hand_to_gauge_internal":
			var syrus_h2g_card_id = effect.get("card_id_to_add", -1)
			if syrus_h2g_card_id == -1 or not performing_player.is_card_in_hand(syrus_h2g_card_id):
				return
			var syrus_h2g_card = card_db.get_card(syrus_h2g_card_id)
			performing_player.remove_card_from_hand(syrus_h2g_card_id, true, false)
			performing_player.add_to_gauge(syrus_h2g_card)
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将%s从手牌加入怒气。" % _log_card_name(card_db.get_card_name(syrus_h2g_card_id)))
		"syrus_return_to_hand_until_7":
			var syrus_target_hand = 7
			var syrus_needed = syrus_target_hand - performing_player.hand.size()
			if syrus_needed > 0:
				var syrus_discard_cards = performing_player.discards.duplicate()
				var syrus_to_move = mini(syrus_needed, syrus_discard_cards.size())
				# 用共享种子的 RNG 随机取牌：Array.shuffle() / randi() 走的是全局随机，
				# 联机时两端结果不同 → 双方状态分叉（用户报告的「Syrus 2G 击中效果不同步」）。
				for syrus_i in range(syrus_to_move):
					var syrus_pick = get_random_int() % syrus_discard_cards.size()
					var syrus_card = syrus_discard_cards[syrus_pick]
					syrus_discard_cards.remove_at(syrus_pick)
					performing_player.remove_card_from_discards(syrus_card.id)
					performing_player.add_to_hand(syrus_card, true)
					_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将%s从弃牌返回手牌。" % _log_card_name(card_db.get_card_name(syrus_card.id)))
			do_effect_if_condition_met(performing_player, card_id, { "effect_type": StrikeEffects.ShuffleDiscardInPlace }, null)
		"syrus_dredge_fury_keep_choice":
			var syrus_dfk_ids = performing_player.syrus_dredge_fury_spent_ids
			if syrus_dfk_ids.is_empty():
				return
			if syrus_dfk_ids.size() == 1:
				var syrus_dfk_id = syrus_dfk_ids[0]
				if performing_player.is_card_in_discards(syrus_dfk_id):
					var syrus_dfk_card = card_db.get_card(syrus_dfk_id)
					performing_player.remove_card_from_discards(syrus_dfk_id)
					performing_player.add_to_hand(syrus_dfk_card, true)
					_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将%s从弃牌返回手牌。" % _log_card_name(card_db.get_card_name(syrus_dfk_id)))
				return
			var syrus_dfk_choices = []
			for syrus_dfk_id in syrus_dfk_ids:
				syrus_dfk_choices.append({
					"_choice_text": "Keep %s" % card_db.get_card_name(syrus_dfk_id),
					"effect_type": "syrus_dredge_fury_retrieve",
					"card_id": syrus_dfk_id
				})
			do_effect_if_condition_met(performing_player, card_id, {
				"effect_type": StrikeEffects.Choice,
				StrikeEffects.Choice: syrus_dfk_choices,
				"override_description": "Choose one spent Gauge to add to hand"
			}, null)
		"syrus_dredge_fury_retrieve":
			var syrus_ret_id = effect.get("card_id", -1)
			if syrus_ret_id == -1 or not performing_player.is_card_in_discards(syrus_ret_id):
				return
			var syrus_ret_card = card_db.get_card(syrus_ret_id)
			performing_player.remove_card_from_discards(syrus_ret_id)
			performing_player.add_to_hand(syrus_ret_card, true)
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将%s从弃牌返回手牌。" % _log_card_name(card_db.get_card_name(syrus_ret_id)))
		"syrus_pull_to_range_2":
			var syrus_pt_opp = opposing_player.arena_location
			var syrus_pt_self_edge = performing_player.get_closest_occupied_space_to(syrus_pt_opp)
			var syrus_pt_range = abs(syrus_pt_self_edge - syrus_pt_opp)
			if syrus_pt_range > 2:
				do_effect_if_condition_met(performing_player, card_id, { "effect_type": StrikeEffects.Pull, "amount": syrus_pt_range - 2 }, null)
			elif syrus_pt_range < 2:
				do_effect_if_condition_met(performing_player, card_id, { "effect_type": StrikeEffects.Pull, "amount": 2 }, null)
		"syrus_silver_shadow":
			var syrus_ss_opp = opposing_player.arena_location
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect
			decision_info.player = performing_player.my_id
			decision_info.choice_card_id = card_id
			decision_info.effect_type = StrikeEffects.MoveToSpace
			decision_info.choice = []
			decision_info.limitation = []
			decision_info.extra_info = ""
			for syrus_ss_s in range(1, 10):
				if abs(syrus_ss_s - syrus_ss_opp) == 3:
					decision_info.limitation.append(syrus_ss_s)
					decision_info.choice.append({
						"effect_type": StrikeEffects.MoveToSpace,
						"amount": syrus_ss_s,
						"remove_buddies_encountered": 0
					})
			if not decision_info.choice.is_empty():
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				create_event(Enums.EventType.EventType_ChooseArenaLocationForEffect, performing_player.my_id, 0)
		"syrus_reckless_greed":
			if performing_player.syrus_reckless_greed_used:
				return
			var syrus_rg_boosts = performing_player.get_boosts(true)
			if syrus_rg_boosts.is_empty():
				return
			var syrus_rg_choices = [{"effect_type": StrikeEffects.Pass, "_choice_text": "Pass"}]
			for syrus_rg_b in syrus_rg_boosts:
				syrus_rg_choices.append({
					"effect_type": "syrus_reckless_greed_strike",
					"boost_id": syrus_rg_b.id,
					"_choice_text": "Discard %s & Strike" % card_db.get_card_name(syrus_rg_b.id)
				})
			do_effect_if_condition_met(performing_player, card_id, {
				"effect_type": StrikeEffects.Choice,
				StrikeEffects.Choice: syrus_rg_choices,
				"override_description": "Discard a Boost from play to Strike"
			}, null)
		"syrus_reckless_greed_strike":
			var syrus_rgs_id = effect.get("boost_id", -1)
			if syrus_rgs_id == -1:
				return
			var syrus_rgs_card = card_db.get_card(syrus_rgs_id)
			if syrus_rgs_card == null or not performing_player.is_card_in_continuous_boosts(syrus_rgs_id):
				return
			performing_player.remove_from_continuous_boosts(syrus_rgs_card)
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "弃置%s并立刻发动战斗！" % _log_card_name(card_db.get_card_name(syrus_rgs_id)))
			performing_player.syrus_reckless_greed_used = true
			do_effect_if_condition_met(performing_player, card_id, {"effect_type": StrikeEffects.Strike}, null)
		"syrus_gauge_seal_direct":
			# Player chose to seal the from-gauge instant boost directly.
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "封印加成牌%s。" % active_boost.card.definition['display_name'])
			do_seal_effect(performing_player, active_boost.card.id, "")
			active_boost.discarded_already = true
		"syrus_gauge_seal_after_exceed":
			# Player chose to resolve the exceed face now effect (Move up to 1)
			# before sealing. Replay the boost as the exceeded replacement
			# (facedown continuous boost), trigger its now/during_strike
			# effects, then seal it.
			var syrus_gse_replacement = performing_player.get_exceeded_replacement_boost_definition()
			if syrus_gse_replacement == null:
				# Fallback: no exceeded replacement defined, just seal.
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "封印加成牌%s。" % active_boost.card.definition['display_name'])
				do_seal_effect(performing_player, active_boost.card.id, "")
				active_boost.discarded_already = true
				return
			var syrus_gse_old_boost = active_boost.card.definition["boost"]
			active_boost.card.definition["replaced_boost"] = syrus_gse_old_boost
			active_boost.card.definition["boost"] = syrus_gse_replacement.duplicate(true)
			performing_player.add_to_continuous_boosts(active_boost.card)
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "将%s以背面持续加成重打出场。" % _log_card_name(card_db.get_card_name(active_boost.card.id)))
			# Trigger now / during_strike effects from the replacement boost.
			for syrus_gse_effect in active_boost.card.definition['boost']['effects']:
				if syrus_gse_effect['timing'] == "now" or (active_strike and syrus_gse_effect['timing'] == "during_strike"):
					do_effect_if_condition_met(performing_player, active_boost.card.id, syrus_gse_effect, null)
					if game_state == Enums.GameState.GameState_PlayerDecision:
						# The "now" effect (Move up to 1) is awaiting a choice;
						# seal after it resolves.
						active_boost.syrus_seal_after_exceed_pending = true
						return
			# No decision needed; seal immediately.
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "封印加成牌%s。" % active_boost.card.definition['display_name'])
			performing_player.remove_from_continuous_boosts(active_boost.card, "sealed")
			active_boost.discarded_already = true
		StrikeEffects.ForceForEffect:
			var force_player = performing_player
			if 'other_player' in effect and effect['other_player']:
				force_player = opposing_player
			var available_force = force_player.get_available_force()
			# Zsolt awaken: check hit and limit 2 per turn
			if effect.get("is_zsolt_awaken"):
				if not active_strike.did_player_hit_opponent(force_player):
					return
				if force_player.zsolt_extra_attack_count >= 2:
					return
			var can_do_something = false
			if effect.get('per_force_effect') != null and available_force > 0:
				can_do_something = true
			elif effect.get('overall_effect') and available_force >= effect['force_max']:
				can_do_something = true
			if can_do_something:
				# Zsolt awaken: mark offered only when actually showing the decision
				if effect.get("is_zsolt_awaken"):
					force_player.zsolt_awaken_offered = true
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.player = force_player.my_id
				decision_info.type = Enums.DecisionType.DecisionType_ForceForEffect
				decision_info.choice_card_id = card_id
				decision_info.effect = effect
				if effect.get("tournelouse_ouroboros_force"):
					decision_info.choice = _get_tournelouse_transform_hand_options(force_player)
				create_event(Enums.EventType.EventType_ForceForEffect, force_player.my_id, 0)
		StrikeEffects.GaugeForEffect:
			if active_strike and performing_player.strike_stat_boosts.may_generate_gauge_with_force and effect.get("valid_zone", "gauge") == "gauge":
				# Convert this to a force_for_effect instead.
				var changed_effect = {
					"effect_type": StrikeEffects.ForceForEffect,
					"per_force_effect": effect.get('per_gauge_effect', null),
					"overall_effect": effect.get('overall_effect', null),
					"force_max": effect['gauge_max'],
					"required": 'required' in effect and effect['required'],
				}
				handle_strike_effect(card_id, changed_effect, performing_player)
			else:
				var gauge_player = performing_player
				if 'other_player' in effect and effect['other_player']:
					gauge_player = opposing_player
				var available_gauge = gauge_player.get_available_gauge()
				if effect.get("valid_zone", "gauge") == "bleach":
					available_gauge = gauge_player.bleach_zone.size()
				if effect['gauge_max'] == -1:
					effect = effect.duplicate()
					effect['gauge_max'] = available_gauge
				var can_do_something = false
				# 用 get 取：卡定义漏写 per_gauge_effect 时不要报错中断（否则付怒效果会静默失效）。
				if effect.get('per_gauge_effect', null) and available_gauge > 0:
					can_do_something = true
				elif effect.get('overall_effect', null) and available_gauge >= effect['gauge_max']:
					can_do_something = true
				if can_do_something:
					change_game_state(Enums.GameState.GameState_PlayerDecision)
					decision_info.clear()
					decision_info.player = gauge_player.my_id
					decision_info.type = Enums.DecisionType.DecisionType_GaugeForEffect
					decision_info.choice_card_id = card_id
					decision_info.effect = effect
					create_event(Enums.EventType.EventType_GaugeForEffect, gauge_player.my_id, 0)
		StrikeEffects.GainAdvantage:
			next_turn_player = performing_player.my_id
			create_event(Enums.EventType.EventType_Strike_GainAdvantage, performing_player.my_id, 0)
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "获得优势！")
			# Zsolt transform 战争变奏曲: first time gaining advantage per battle, draw 1
			if performing_player.deck_def.get("id") == "zsolt" and not performing_player.zsolt_war_symphony_drew:
				for c in performing_player.transforms:
					if c.definition.get("id", "").find("zsolt_crossghostslash") >= 0:
						performing_player.zsolt_war_symphony_drew = true
						performing_player.draw(1, false, false)
						_append_log_full(Enums.LogType.LogType_Effect, performing_player, "抽1牌 来自 战争变奏曲.")
						break
		StrikeEffects.GainLife:
			var amount = effect['amount']
			if str(amount) == "LAST_SPENT_LIFE":
				amount = performing_player.last_spent_life
			var taisei_death_override_life = _consume_taisei_death_exceed_override_life(performing_player, amount)
			if taisei_death_override_life >= 0:
				performing_player.life = min(performing_player.get_life_cap(), taisei_death_override_life)
			else:
				performing_player.life = min(performing_player.get_life_cap(), performing_player.life + amount)
			create_event(Enums.EventType.EventType_Strike_GainLife, performing_player.my_id, amount, "", performing_player.life)
			_append_log_full(Enums.LogType.LogType_Health, performing_player, "回复%s生命，生命值来到%s！" % [str(amount), str(performing_player.life)])
			_recalc_life_conditional_boosts(performing_player)
		StrikeEffects.GainLifeDamageDealt:
			var damage_dealt = active_strike.get_damage_taken(opposing_player)
			if damage_dealt > 0:
				performing_player.life = min(performing_player.get_life_cap(), performing_player.life + damage_dealt)
				create_event(Enums.EventType.EventType_Strike_GainLife, performing_player.my_id, damage_dealt, "", performing_player.life)
				_append_log_full(Enums.LogType.LogType_Health, performing_player, "回复等同于造成伤害的%s生命，生命值来到%s！" % [str(damage_dealt), str(performing_player.life)])
				_recalc_life_conditional_boosts(performing_player)
		StrikeEffects.GaugeFromHand:
			var effect_player = performing_player
			if 'opponent' in effect and effect['opponent']:
				effect_player = opposing_player

			var card_type_limitation = effect.get("card_type_limitation", ["normal", "special", "ultra"])
			var valid_cards = effect_player.get_cards_in_hand_matching_types(card_type_limitation)
			var valid_ids = []
			for card in valid_cards:
				valid_ids.append(card.id)

			if len(valid_ids) > 0:
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_CardFromHandToGauge
				decision_info.player = effect_player.my_id
				decision_info.choice_card_id = card_id
				decision_info.destination = effect.get("destination", "gauge")
				decision_info.valid_zones = ["hand"]

				var min_amount = effect['min_amount']
				var max_amount = effect['max_amount']
				if 'amount_is_gauge_spent' in effect and effect['amount_is_gauge_spent']:
					min_amount = effect_player.gauge_spent_before_strike
					max_amount = effect_player.gauge_spent_before_strike
				var restricted_to_card_ids = valid_ids
				var show_restriction_list_ui = false
				var from_last_cards = effect.get("from_last_cards")
				if from_last_cards:
					restricted_to_card_ids = []
					show_restriction_list_ui = true
					for i in range(from_last_cards):
						restricted_to_card_ids.append(effect_player.hand[effect_player.hand.size() - 1 - i].id)

				if min_amount > effect_player.hand.size():
					min_amount = effect_player.hand.size()

				decision_info.effect = {
					"min_amount": min_amount,
					"max_amount": max_amount,
					"restricted_to_card_ids": restricted_to_card_ids,
					"show_restriction_list_ui": show_restriction_list_ui,
				}

				decision_info.bonus_effect = {}
				if 'per_card_effect' in effect and effect['per_card_effect']:
					decision_info.bonus_effect = effect['per_card_effect']
				create_event(Enums.EventType.EventType_CardFromHandToGauge_Choice, effect_player.my_id, min_amount, "", max_amount, restricted_to_card_ids)
			else:
				_append_log_full(Enums.LogType.LogType_Effect, effect_player, "手牌中没有可放入怒气的牌。")
		StrikeEffects.GenerateFreeForce:
			performing_player.free_force = effect['amount']
			if effect.get('zsolt_force_pool', false):
				performing_player.zsolt_force_pool += effect['amount']
				performing_player.free_force = 0
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "可以免费生成%s能量！" % performing_player.free_force)
		StrikeEffects.RemoveGenerateFreeForce:
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "不再生成免费能量。")
			performing_player.free_force = 0
		StrikeEffects.GenerateFreeForceCcOnly:
			performing_player.free_force_cc_only = effect['amount']
		StrikeEffects.GiveToPlayer:
			performing_player.strike_stat_boosts.move_strike_to_opponent_boosts = true
			handle_strike_attack_immediate_removal(performing_player)
		StrikeEffects.Guardup:
			var amount = effect['amount']
			if str(amount) == "strike_x":
				amount = performing_player.strike_stat_boosts.strike_x
			performing_player.strike_stat_boosts.guard += amount
			create_event(Enums.EventType.EventType_Strike_GuardUp, performing_player.my_id, amount)
		StrikeEffects.GuardupPerForceSpentThisTurn:
			var amount = performing_player.total_force_spent_this_turn * effect['amount']
			performing_player.strike_stat_boosts.guard += amount
			create_event(Enums.EventType.EventType_Strike_GuardUp, performing_player.my_id, amount)
		StrikeEffects.GuardupPerTwoCardsInHand:
			performing_player.strike_stat_boosts.guardup_per_two_cards_in_hand = true
			var hand_size = len(performing_player.hand)
			var guard_boost = floor(hand_size / 2.0)
			create_event(Enums.EventType.EventType_Strike_GuardUp, performing_player.my_id, guard_boost)
		StrikeEffects.GuardupPerGauge:
			performing_player.strike_stat_boosts.guardup_per_gauge = true
		StrikeEffects.GuardupIfCopyOfOpponentAttackInSealed:
			performing_player.strike_stat_boosts.guardup_if_copy_of_opponent_attack_in_sealed_modifier = effect["amount"]
			var opponent_attack = active_strike.get_player_card(opposing_player)
			if performing_player.has_card_name_in_zone(opponent_attack, "sealed"):
				# Even though this is a passive, show an event now to cover most cases.
				var guard_boost = effect["amount"]
				create_event(Enums.EventType.EventType_Strike_GuardUp, performing_player.my_id, guard_boost)
		StrikeEffects.HigherSpeedMisses:
			performing_player.strike_stat_boosts.higher_speed_misses = true
			if 'dodge_at_speed_greater_or_equal' in effect:
				var speed_dodge = effect['dodge_at_speed_greater_or_equal']
				performing_player.strike_stat_boosts.dodge_at_speed_greater_or_equal = speed_dodge
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "将闪避速度%s或更高的攻击！" % speed_dodge)
			else:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "将闪避速度更高的攻击！")
		StrikeEffects.LowerSpeedMisses:
			performing_player.strike_stat_boosts.lower_speed_misses = true
			if 'dodge_at_speed_lower_or_equal' in effect:
				var speed_dodge = effect['dodge_at_speed_lower_or_equal']
				performing_player.strike_stat_boosts.dodge_at_speed_lower_or_equal = speed_dodge
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "将闪避速度%s或更低的攻击！" % speed_dodge)
			else:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "将闪避速度更低的攻击！")
		StrikeEffects.IgnoreArmor:
			if 'opponent' in effect and effect['opponent']:
				opposing_player.strike_stat_boosts.ignore_armor = true
				_append_log_full(Enums.LogType.LogType_Effect, opposing_player, "获得无视护甲。")
			else:
				performing_player.strike_stat_boosts.ignore_armor = true
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "获得无视护甲。")
		StrikeEffects.IgnoreGuard:
			if 'opponent' in effect and effect['opponent']:
				opposing_player.strike_stat_boosts.ignore_guard = true
				_append_log_full(Enums.LogType.LogType_Effect, opposing_player, "获得无视霸体。")
			else:
				performing_player.strike_stat_boosts.ignore_guard = true
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "获得无视霸体。")
		StrikeEffects.IgnorePushAndPull:
			performing_player.strike_stat_boosts.ignore_push_and_pull = true
		StrikeEffects.IgnorePushAndPullPassiveBonus:
			performing_player.ignore_push_and_pull += 1
			if performing_player.ignore_push_and_pull == 1:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "不能被击退或拉近！")
		StrikeEffects.ImmediateForceForArmor:
			var offense_player = opposing_player
			var defense_player = performing_player
			if 'opponent' in effect and effect['opponent']:
				offense_player = performing_player
				defense_player = opposing_player
			var incoming_damage = calculate_damage(offense_player, defense_player)

			change_game_state(Enums.GameState.GameState_PlayerDecision)
			decision_info.clear()
			decision_info.player = defense_player.my_id
			decision_info.type = Enums.DecisionType.DecisionType_ForceForArmor
			decision_info.choice_card_id = card_id
			decision_info.limitation = "force"
			decision_info.amount = effect['amount']
			create_event(Enums.EventType.EventType_Strike_ForceForArmor, defense_player.my_id, incoming_damage, "", offense_player.strike_stat_boosts.ignore_armor)
		StrikeEffects.IncreaseDrawEffects:
			var amount = effect['amount']
			performing_player.strike_stat_boosts.increase_draw_effects_by += amount
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "的抽牌效果增加%s！" % amount)
		StrikeEffects.IncreaseForceSpentBeforeStrike:
			performing_player.force_spent_before_strike += 1
		StrikeEffects.IncreaseGaugeSpentBeforeStrike:
			performing_player.gauge_spent_before_strike += 1
		StrikeEffects.IncreaseMovementEffects:
			var amount = effect['amount']
			performing_player.strike_stat_boosts.increase_movement_effects_by += amount
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "的前进和后退效果增加%s！" % amount)
		StrikeEffects.IncreaseMove_OpponentEffects:
			var amount = effect['amount']
			performing_player.strike_stat_boosts.increase_move_opponent_effects_by += amount
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "的击退和拉近效果增加%s！" % amount)
		StrikeEffects.Infused:
			if not performing_player.is_infused():
				performing_player.infused = true
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "进入灌注状态！")
				create_event(Enums.EventType.EventType_Strike_Infuse, performing_player.my_id, -1, "Infused")
		StrikeEffects.InvertRange:
			performing_player.strike_stat_boosts.invert_range = true
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "反转其距离！")
		StrikeEffects.RemoveIgnorePushAndPullPassiveBonus:
			performing_player.ignore_push_and_pull -= 1
			if performing_player.ignore_push_and_pull == 0:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "不再无视击退和拉近。")
		"headshot_allow_off_by_one":
			performing_player.headshot_allow_off_by_one += 1
			if performing_player.headshot_allow_off_by_one == 1:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "爆头条件放宽：手牌数与距离相差1也算！")
		"remove_headshot_allow_off_by_one":
			performing_player.headshot_allow_off_by_one -= 1
			if performing_player.headshot_allow_off_by_one == 0:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "爆头条件恢复正常。")
		"headshot_unconditional":
			performing_player.headshot_unconditional += 1
			if performing_player.headshot_unconditional == 1:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "爆头不再有限制条件，只需击中即可！")
		"remove_headshot_unconditional":
			performing_player.headshot_unconditional -= 1
			if performing_player.headshot_unconditional == 0:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "爆头条件恢复正常。")
		"carcass_watch_guard":
			# 特遣队员「守望」：免疫位移（不能被移动 / 击退 / 拉近）+ 阻止时反击
			# （伤害在 player.gd 的两个阻止点结算）。
			# 「不能被穿越」改用引擎原语 opponent_cant_move_past（同杰弗里 3G 神圣裁决），
			# 由卡上 during_strike / cleanup 成对开关 —— 它是把标记记在**对手**身上
			# （opposing_player.cannot_move_past_opponent），记在自己身上只会拦住自己。
			performing_player.carcass_watch_guard += 1
			performing_player.strike_stat_boosts.ignore_push_and_pull = true
			if performing_player.carcass_watch_guard == 1:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "进入守望：不能被移动、击退、拉近或穿越！")
		"remove_carcass_watch_guard":
			performing_player.carcass_watch_guard -= 1
			if performing_player.carcass_watch_guard == 0:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "守望结束。")
		StrikeEffects.RemoveCannotDrawPassive:
			performing_player.cannot_draw -= 1
			if performing_player.cannot_draw == 0:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "可以再次抽牌。")
		StrikeEffects.LoseAllArmor:
			if active_strike:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "失去所有护甲！")
				var remaining_armor = get_total_armor(performing_player)
				performing_player.strike_stat_boosts.armor -= remaining_armor
		StrikeEffects.MayAdvanceBonusSpaces:
			var movement_type = decision_info.source
			var movement_amount = decision_info.amount
			var followups = decision_info.limitation

			var choice = [
				{
					'effect_type': movement_type + '_INTERNAL',
					'amount': movement_amount
				},
				{
					'effect_type': movement_type + '_INTERNAL',
					'amount': movement_amount + effect['amount']
				}
			]
			if followups['and']:
				choice[0]['and'] = followups['and']
				choice[1]['and'] = followups['and']

			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "可以额外%s%s格！" % [movement_type, movement_amount])
			change_game_state(Enums.GameState.GameState_PlayerDecision)
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_EffectChoice
			decision_info.player = performing_player.my_id
			decision_info.choice = choice
			decision_info.choice_card_id = card_id
			create_event(Enums.EventType.EventType_Strike_EffectChoice, performing_player.my_id, 0, "EffectOption")
		StrikeEffects.MayIgnoreMovementLimit:
			var movement_type = decision_info.source
			var movement_amount = decision_info.amount
			var followups = decision_info.limitation

			var limited_amount = min(movement_amount, performing_player.movement_limit)
			if movement_amount == limited_amount:
				# There's no choice, so just do nothing because it is irrelevant.
				pass
			else:
				var choice = [
					{
						'effect_type': movement_type + '_INTERNAL',
						'amount': movement_amount
					},
					{
						'effect_type': movement_type + '_INTERNAL',
						'amount': limited_amount
					}
				]
				if followups['and']:
					choice[0]['and'] = followups['and']
					choice[1]['and'] = followups['and']

				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "可以无视移动限制！")
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_EffectChoice
				decision_info.player = performing_player.my_id
				decision_info.choice = choice
				decision_info.choice_card_id = card_id
				create_event(Enums.EventType.EventType_Strike_EffectChoice, performing_player.my_id, 0, "EffectOption")
		StrikeEffects.MoveRandomCards:
			var card_count = effect['amount']
			var from_zone = effect['from_zone']
			var to_zone = effect['to_zone']
			var target_player = performing_player
			var effecting_player = performing_player
			if effect.get("opponent", false):
				target_player = opposing_player
			if from_zone == "hand" and to_zone == "discard":
				card_count -= target_player.strike_stat_boosts.reduce_discard_effects_by
				if card_count < 0:
					card_count = 0

			var card_ids = target_player.pick_random_cards_from_hand(card_count)
			if card_ids.size() > 0:
				var card_names = card_db.get_card_names(card_ids)
				if from_zone == "hand" and to_zone == "overdrive":
					_append_log_full(Enums.LogType.LogType_CardInfo, target_player, "随机弃置牌到对手的超载：%s。" % _log_card_name(card_names))
					target_player.discard(card_ids)
					effecting_player.move_cards_to_overdrive(card_ids, "opponent_discard")
				else:
					var action_word = "discards"
					var destination_str = ""
					if to_zone == "gauge":
						action_word = "moves"
						destination_str = "to Gauge"
						for to_gauge_card in card_ids:
							performing_player.move_card_from_hand_to_gauge(to_gauge_card)
					else:
						target_player.discard(card_ids)

					_append_log_full(Enums.LogType.LogType_CardInfo, target_player, "%s随机牌%s：%s。" % [action_word, destination_str, _log_card_name(card_ids)])
		StrikeEffects.MoveToSpace:
			var target_space = effect['amount']
			var remove_buddies_encountered = effect['remove_buddies_encountered']
			var previous_location = performing_player.arena_location
			var space = target_space
			var move_budget = _dongshilang_limit_requested_movement(performing_player, abs(target_space - previous_location))
			if move_budget <= 0:
				space = previous_location
			elif target_space > previous_location:
				space = previous_location + move_budget
			elif target_space < previous_location:
				space = previous_location - move_budget
			performing_player.move_to(space, false, remove_buddies_encountered)
			var new_location = performing_player.arena_location
			_append_log_full(Enums.LogType.LogType_CharacterMovement, performing_player, "从格子%s移动到%s。" % [str(previous_location), str(performing_player.arena_location)])

			var move_amount = abs(new_location - previous_location)
			if (performing_start < other_start and new_location > other_start) or (performing_start > other_start and new_location < other_start):
				move_amount -= 1
			move_amount = maxi(move_amount, 0)
			_dongshilang_consume_movement_limit(performing_player, move_amount)
			# Ulrik: increment move counters from continuous boosts
			for boost in performing_player.continuous_boosts:
				for boost_effect in boost.definition['boost']['effects']:
					if boost_effect.get('effect_type') == StrikeEffects.IncrementBonusMovePowerCounters:
						boost.set_meta('bonus_move_power_counters', boost.get_meta('bonus_move_power_counters', 0) + move_amount * boost_effect.get('amount', 1))
					if boost_effect.get('effect_type') == StrikeEffects.IncrementBonusMoveArmorCounters:
						boost.set_meta('bonus_move_armor_counters', boost.get_meta('bonus_move_armor_counters', 0) + move_amount * boost_effect.get('amount', 1))

			if (performing_start < other_start and new_location > other_start) or (performing_start > other_start and new_location < other_start):
				# The opponent's space doesn't count as one you move through
				local_conditions.advanced_through = true
				handle_advanced_through(performing_player, opposing_player)
				_dongshilang_register_cross_during_strike(performing_player)
				performing_player.moved_past_this_strike = true
				if performing_player.strike_stat_boosts.range_includes_if_moved_past:
					performing_player.strike_stat_boosts.range_includes_opponent = true
					_append_log_full(Enums.LogType.LogType_Effect, performing_player, "前进穿过了对手，使其进入距离！")
			if ((performing_player.is_in_or_left_of_location(buddy_start, performing_start) and performing_player.is_in_or_right_of_location(buddy_start, new_location)) or
					(performing_player.is_in_or_right_of_location(buddy_start, performing_start) and performing_player.is_in_or_left_of_location(buddy_start, new_location))):
				local_conditions.advanced_through_buddy = true
		StrikeEffects.MoveToAnySpace:
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect
			decision_info.player = performing_player.my_id
			decision_info.choice_card_id = card_id
			decision_info.effect_type = StrikeEffects.MoveToSpace
			decision_info.choice = []
			decision_info.extra_info = ""

			var remove_buddies_encountered = 0
			if 'remove_buddies_encountered' in effect:
				remove_buddies_encountered = effect['remove_buddies_encountered']
				decision_info.extra_info = "Remove the first %s %ss you move onto" % [remove_buddies_encountered, effect['buddy_name']]

			var move_min = 0
			var move_max = 8
			var move_in_attack_range = 'move_in_attack_range' in effect and effect['move_in_attack_range']
			if 'move_min' in effect:
				move_min = effect['move_min']
			if 'move_max' in effect:
				move_max = effect['move_max']

			var advance_only = 'advance_only' in effect and effect['advance_only']

			var and_effect = null
			if 'and' in effect:
				and_effect = effect['and']
				and_handled_elsewhere = true

			decision_info.limitation = []
			# If not moving is an option, enable StrikeEffects.Pass button
			if move_min == 0 or ('optional' in effect and effect['optional']):
				decision_info.limitation.append(0)
				decision_info.choice.append({
					"effect_type": StrikeEffects.Pass,
					"and": and_effect,
				})

			var nowhere_to_move = true
			var player_location = performing_player.arena_location
			var opponent_location = opposing_player.arena_location
			for i in range(Enums.MinArenaLocation, Enums.MaxArenaLocation+1):
				if not performing_player.can_move_to(i, true):
					continue

				if advance_only:
					if performing_player.is_left_of_location(opponent_location) and performing_player.is_right_of_location(i):
						continue
					elif performing_player.is_right_of_location(opponent_location) and performing_player.is_left_of_location(i):
						continue

				var valid_space = false
				if move_in_attack_range:
					var arena_distance = abs(i - get_attack_origin(performing_player, opponent_location))
					var min_range = get_total_min_range(performing_player)
					var max_range = get_total_max_range(performing_player)
					valid_space = min_range <= arena_distance and arena_distance <= max_range
				else:
					var movement_distance = performing_player.movement_distance_between(player_location, i)
					valid_space = move_min <= movement_distance and movement_distance <= move_max

				if valid_space:
					decision_info.limitation.append(i)
					decision_info.choice.append({
						"effect_type": StrikeEffects.MoveToSpace,
						"amount": i,
						"remove_buddies_encountered": remove_buddies_encountered,
						"and": and_effect,
					})
					nowhere_to_move = false

			if not nowhere_to_move:
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				create_event(Enums.EventType.EventType_ChooseArenaLocationForEffect, performing_player.my_id, 0)
			else:
				_append_log_full(Enums.LogType.LogType_CharacterMovement, performing_player, "没有可移动到的格子！")
				create_event(Enums.EventType.EventType_BlockMovement, performing_player.my_id, 0)
		StrikeEffects.NameCardOpponentDiscards:
			var amount = effect.get("amount", 1)
			change_game_state(Enums.GameState.GameState_PlayerDecision)
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_NameCard_OpponentDiscards
			decision_info.effect_type = StrikeEffects.NameCardOpponentDiscardsInternal
			decision_info.choice_card_id = card_id
			decision_info.player = performing_player.my_id
			decision_info.amount = amount
			decision_info.effect = effect
			decision_info.extra_info = []

			if 'discard_effect' in effect:
				decision_info.bonus_effect = effect['discard_effect']
			create_event(Enums.EventType.EventType_Boost_NameCardOpponentDiscards, performing_player.my_id, decision_info.amount)
		StrikeEffects.NameCardOpponentDiscardsInternal:
			var named_card_name = NullNamedCard
			if effect['card_id'] > 0:
				var named_card = card_db.get_card(effect['card_id'])
				# named_card is the individual card but
				# this should discard "by name", so instead of using that
				# match card.definition['id']'s instead.
				named_card_name = named_card.definition['id']
			decision_info.extra_info.append(named_card_name)
			if decision_info.amount > 1:
				# Naming multiple cards, so queue up another name card
				# and save this one in the extra info.
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.amount -= 1
				create_event(Enums.EventType.EventType_Boost_NameCardOpponentDiscards, performing_player.my_id, decision_info.amount)
			else:
				var before_discard_count = opposing_player.discards.size()
				var effect_copy = decision_info.effect
				var reveal_hand_after = effect_copy.get("reveal_hand_after", false)
				var discard_all_copies = effect_copy.get("discard_all_copies", false)
				for discard_name in decision_info.extra_info:
					opposing_player.discard_matching_or_reveal(
						discard_name,
						discard_all_copies,
						reveal_hand_after # skip_reveal=true if we're revealing the hand afterwards.
					)

				var discarded_card = before_discard_count < opposing_player.discards.size()
				if discarded_card and decision_info.bonus_effect:
					handle_strike_effect(decision_info.choice_card_id, decision_info.bonus_effect, performing_player)
				if reveal_hand_after:
					opposing_player.reveal_hand()
		StrikeEffects.NameRange:
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_PickNumberFromRange
			decision_info.player = performing_player.my_id
			decision_info.choice_card_id = card_id
			decision_info.choice = []
			decision_info.limitation = []
			if effect['target_effect'] == StrikeEffects.OpponentDiscardRangeOrReveal:
				decision_info.amount_min = 0
				decision_info.amount = 9
				decision_info.valid_zones = ["Range X", "Range N/A (-)"]
				decision_info.effect_type = "have opponent discard a card including that Range or reveal their hand"
				for i in range(decision_info.amount + 1):
					decision_info.limitation.append(i)
					decision_info.choice.append({
						"effect_type": StrikeEffects.OpponentDiscardRangeOrReveal,
						"target_range": i,
						"amount": 1
					})
				var next_num = decision_info.amount + 1
				for i in range(2):
					decision_info.limitation.append(next_num)
					decision_info.choice.append({
						"effect_type": StrikeEffects.OpponentDiscardRangeOrReveal,
						"target_range": decision_info.valid_zones[i],
						"amount": 1
					})

				change_game_state(Enums.GameState.GameState_PlayerDecision)
				create_event(Enums.EventType.EventType_PickNumberFromRange, performing_player.my_id, 0)
			else:
				assert(false, "Target effect for name_range not found.")
				decision_info.clear()
		StrikeEffects.NameSpeed:
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_PickNumberFromRange
			decision_info.player = performing_player.my_id
			decision_info.choice_card_id = card_id
			decision_info.choice = []
			decision_info.limitation = []
			if effect['target_effect'] == StrikeEffects.OpponentDiscardSpeedOrReveal:
				decision_info.amount_min = 0
				decision_info.amount = 10
				decision_info.valid_zones = ["Speed X"]
				decision_info.effect_type = "have opponent discard a card including that Speed or reveal their hand"
				for i in range(decision_info.amount + 1):
					decision_info.limitation.append(i)
					decision_info.choice.append({
						"effect_type": StrikeEffects.OpponentDiscardSpeedOrReveal,
						"target_speed": i,
						"amount": 1
					})
				var next_num = decision_info.amount + 1
				for i in range(1):
					decision_info.limitation.append(next_num)
					decision_info.choice.append({
						"effect_type": StrikeEffects.OpponentDiscardSpeedOrReveal,
						"target_speed": decision_info.valid_zones[i],
						"amount": 1
					})
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				create_event(Enums.EventType.EventType_PickNumberFromRange, performing_player.my_id, 0)
			else:
				assert(false, "Target effect for name_range not found.")
				decision_info.clear()
		StrikeEffects.NegateBoost:
			assert(active_boost)
			_append_log_full(Enums.LogType.LogType_Effect, active_boost.playing_player, "的加成效果被无效化。")
			active_boost.boost_negated = true
			if effect.get("allow_cancel_after_negate", false):
				active_boost.allow_cancel_after_negate = true
			active_boost.discard_on_cleanup = true
		StrikeEffects.OnlyHitsIfOpponentOnAnyBuddy:
			performing_player.strike_stat_boosts.only_hits_if_opponent_on_any_buddy = true
		StrikeEffects.OpponentDiscardNormalsOrReveal:
			var amount = effect['amount']
			amount -= opposing_player.strike_stat_boosts.reduce_discard_effects_by
			var adjusted_effect = effect.duplicate()
			adjusted_effect['amount'] = amount

			var normals_in_hand = opposing_player.get_cards_in_hand_of_type("normal")
			var normal_ids = []
			for card in normals_in_hand:
				normal_ids.append(card.id)
			if normal_ids.size() < amount:
				# Discard all normals and reveal hand.
				_append_log_full(Enums.LogType.LogType_Effect, opposing_player, "弃置所有普通技并展示其手牌。")
				opposing_player.discard(normal_ids)
				opposing_player.reveal_hand()
			elif amount > 0:
				# Opponent chooses which to discard, even if they only have that many to hide how many normals they have.
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_ChooseToDiscard
				decision_info.effect_type = StrikeEffects.OpponentDiscardChooseInternal
				decision_info.effect = adjusted_effect
				decision_info.bonus_effect = null
				decision_info.destination = "discard"
				decision_info.limitation = "normal"
				decision_info.can_pass = false

				decision_info.choice_card_id = card_id
				decision_info.player = opposing_player.my_id
				create_event(Enums.EventType.EventType_Strike_ChooseToDiscard, opposing_player.my_id, amount)
		StrikeEffects.OpponentDiscardRangeOrReveal:
			var target_range = effect['target_range']
			if target_range is String and target_range == "range_from_opponent":
				target_range = opposing_player.distance_to_opponent()

			var range_name_str = target_range
			if not target_range is String:
				range_name_str = "Range %s" % target_range
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "指定%s。" % range_name_str)
			var card_ids_in_range = []
			if target_range is String:
				if target_range == "Range X":
					# If the range is a string like "TOTAL_POWER".
					for card in opposing_player.hand:
						if card.definition['range_min'] is String or card.definition['range_max'] is String:
							card_ids_in_range.append(card.id)
				elif target_range == "Range N/A (-)":
					# If the range is -1 like Block.
					for card in opposing_player.hand:
						var card_range = card.definition['range_min']
						if is_number(card_range) and card_range == -1:
							card_ids_in_range.append(card.id)
				else:
					assert(false, "Unknown target range")
			else:
				# If the range is an actual number.
				for card in opposing_player.hand:
					# Evaluate any special ranges via get_card_stat.
					var card_range_min = get_card_stat(opposing_player, card, 'range_min')
					var card_range_max = get_card_stat(opposing_player, card, 'range_max')
					if is_number(card_range_min) and is_number(card_range_max):
						if target_range >= card_range_min and target_range <= card_range_max:
							card_ids_in_range.append(card.id)
					elif is_number(card_range_min) and target_range == card_range_min:
						card_ids_in_range.append(card.id)
					elif is_number(card_range_max) and target_range == card_range_max:
						card_ids_in_range.append(card.id)
			if card_ids_in_range.size() > 0:
				# Opponent must choose one of these cards to discard.
				var amount = effect['amount']
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_ChooseToDiscard
				decision_info.effect_type = StrikeEffects.OpponentDiscardChooseInternal
				decision_info.effect = effect
				decision_info.source_player_id = effect.get("_source_player_id", _last_effect_source_player_id)
				decision_info.bonus_effect = null
				decision_info.destination = "discard"
				decision_info.limitation = "from_array"
				if target_range is String:
					decision_info.extra_info = "include %s" % target_range
				else:
					decision_info.extra_info = "include Range %s" % target_range
				decision_info.choice = card_ids_in_range
				decision_info.can_pass = false
				decision_info.choice_card_id = card_id
				decision_info.player = opposing_player.my_id
				create_event(Enums.EventType.EventType_Strike_ChooseToDiscard, opposing_player.my_id, amount)
			else:
				# Didn't have any that matched, so forced to reveal hand.
				_append_log_full(Enums.LogType.LogType_Effect, opposing_player, "没有匹配的牌，因此其手牌被展示。")
				opposing_player.reveal_hand()
		StrikeEffects.OpponentDiscardSpeedOrReveal:
			var target_speed = effect['target_speed']
			var speed_name_str = target_speed
			if not target_speed is String:
				speed_name_str = "Speed %s" % target_speed
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "指定%s。" % speed_name_str)
			var card_ids_in_range = []
			if target_speed is String:
				if target_speed == "Speed X":
					# If the speed is a string like "CARDS_IN_HAND".
					for card in opposing_player.hand:
						if card.definition['speed'] is String:
							card_ids_in_range.append(card.id)
				else:
					assert(false, "Unknown target range")
			else:
				# If the range is an actual number.
				for card in opposing_player.hand:
					# Evaluate any special ranges via get_card_stat.
					var card_speed = get_card_stat(opposing_player, card, 'speed')
					if is_number(card_speed):
						if target_speed == card_speed:
							card_ids_in_range.append(card.id)
			if card_ids_in_range.size() > 0:
				# Opponent must choose one of these cards to discard.
				var amount = effect['amount']
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_ChooseToDiscard
				decision_info.effect_type = StrikeEffects.OpponentDiscardChooseInternal
				decision_info.effect = effect
				decision_info.source_player_id = effect.get("_source_player_id", _last_effect_source_player_id)
				decision_info.bonus_effect = null
				decision_info.destination = "discard"
				decision_info.limitation = "from_array"
				if target_speed is String:
					decision_info.extra_info = "include %s" % target_speed
				else:
					decision_info.extra_info = "include Speed %s" % target_speed
				decision_info.choice = card_ids_in_range
				decision_info.can_pass = false
				decision_info.choice_card_id = card_id
				decision_info.player = opposing_player.my_id
				create_event(Enums.EventType.EventType_Strike_ChooseToDiscard, opposing_player.my_id, amount)

			else:
				# Didn't have any that matched, so forced to reveal hand.
				_append_log_full(Enums.LogType.LogType_Effect, opposing_player, "没有匹配的牌，因此其手牌被展示。")
				opposing_player.reveal_hand()
		StrikeEffects.RemoveBuddyNearOpponent:
			var buddies = []
			var same_space_allowed = effect['same_space_allowed']
			var offset_allowed = effect['offset_allowed']
			var optional = 'optional' in effect and effect['optional']
			if same_space_allowed:
				buddies += performing_player.get_buddies_on_opponent()
			if offset_allowed == 1:
				buddies += performing_player.get_buddies_adjacent_opponent()

			if buddies.size() > 0:
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect
				decision_info.player = performing_player.my_id
				decision_info.choice_card_id = card_id
				decision_info.effect_type = StrikeEffects.RemoveBuddyNearOpponent
				decision_info.choice = []
				decision_info.limitation = []
				decision_info.source = effect['buddy_name']
				var and_with_bonus = effect.get('if_removed_effect')
				if optional:
					decision_info.limitation.append(0)
					decision_info.choice.append({
						"effect_type": StrikeEffects.Pass,
					})
				for buddy_id in buddies:
					decision_info.limitation.append(performing_player.get_buddy_location(buddy_id))
					decision_info.choice.append({
						"effect_type": StrikeEffects.RemoveBuddy,
						"buddy_id": buddy_id,
						"and": and_with_bonus
					})
				if decision_info.limitation.size() > 1:
					# There are multiple choices, so player must choose.
					change_game_state(Enums.GameState.GameState_PlayerDecision)
					create_event(Enums.EventType.EventType_ChooseArenaLocationForEffect, performing_player.my_id, 0)
				else:
					# Just do it immediately.
					handle_strike_effect(card_id, decision_info.choice[0], performing_player)
		StrikeEffects.RemoveXBuddies:
			if 'reset_strike_x' in effect and effect['reset_strike_x']:
				performing_player.strike_stat_boosts.strike_x = 0
			var buddies = performing_player.get_buddies_in_play()
			if buddies.size() > 0:
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect
				decision_info.player = performing_player.my_id
				decision_info.choice_card_id = card_id
				decision_info.effect_type = StrikeEffects.RemoveBuddyNearOpponent
				decision_info.choice = []
				decision_info.limitation = []
				decision_info.source = effect['buddy_name']
				# Add optional pass.
				decision_info.limitation.append(0)
				decision_info.choice.append({
					"effect_type": StrikeEffects.Pass,
				})
				var and_effect = null
				if buddies.size() == 1:
					# This is the last iteration, so do not include the remove_X_buddies recursive effect.
					pass
				else:
					and_effect = {
						"effect_type": StrikeEffects.RemoveXBuddies,
						"buddy_name": "Ice Spike",
					}
				for buddy_id in buddies:
					decision_info.limitation.append(performing_player.get_buddy_location(buddy_id))
					decision_info.choice.append({
						"effect_type": StrikeEffects.RemoveBuddy,
						"increase_strike_x": 1,
						"buddy_id": buddy_id,
						"and": and_effect
					})
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				create_event(Enums.EventType.EventType_ChooseArenaLocationForEffect, performing_player.my_id, 0)
		StrikeEffects.ReplaceWildSwing:
			# Assumption: this is still before any meaningful strike stats have happened.
			var attack_card = active_strike.get_player_card(performing_player)
			var previous_attack_goes_to = effect.get("previous_attack_to", "discard")
			performing_player.invalid_card_moved_elsewhere = true
			match previous_attack_goes_to:
				"gauge":
					performing_player.add_to_gauge(attack_card)
				"hand":
					performing_player.add_to_hand(attack_card, true)
				"discard":
					performing_player.add_to_discards(attack_card)
			if not effect.get("skip_swing"):
				performing_player.wild_strike(true)
		StrikeEffects.RevealCopyForAdvantage:
			var copy_id = effect['copy_id']
			# The player has selected to reveal a copy if they have one.
			# Otherwise, do nothing.
			var copy_card_id = performing_player.get_copy_in_hand(copy_id)
			if copy_card_id != -1:
				var card_name = card_db.get_card_name(copy_card_id)
				next_turn_player = performing_player.my_id
				performing_player.reveal_card_ids([copy_card_id])
				create_event(Enums.EventType.EventType_RevealCard, performing_player.my_id, copy_card_id)
				create_event(Enums.EventType.EventType_Strike_GainAdvantage, performing_player.my_id, 0)
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "展示其手牌中的一张%s复制。" % _log_card_name(card_name))
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "获得优势！")
		StrikeEffects.RevealHand:
			if 'opponent' in effect and effect['opponent']:
				opposing_player.reveal_hand()
			else:
				performing_player.reveal_hand()
		StrikeEffects.RevealSingleCard:
			var card_id_to_reveal = effect['card_id']
			performing_player.reveal_card_ids([card_id_to_reveal])
			var card_name = card_db.get_card_name(card_id_to_reveal)
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "reveals %s from hand." % _log_card_name(card_name))
		StrikeEffects.RevealHandAndTopdeck:
			if 'opponent' in effect and effect['opponent']:
				opposing_player.reveal_hand_and_topdeck()
			else:
				performing_player.reveal_hand_and_topdeck()
		StrikeEffects.RevealTopdeck:
			if 'opponent' in effect and effect['opponent']:
				opposing_player.reveal_topdeck()
			else:
				var reveal_to_both = false
				if 'reveal_to_both' in effect and effect['reveal_to_both']:
					reveal_to_both = true
				performing_player.reveal_topdeck(reveal_to_both)
		StrikeEffects.RevealStrike:
			if performing_player == active_strike.initiator:
				active_strike.initiator_set_face_up = true
				_append_log_full(Enums.LogType.LogType_Strike, performing_player, "以明置攻击发起！")
				var card_name = card_db.get_card_name(active_strike.initiator_card.id)
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "正以%s进行战斗。" % _log_card_name(card_name))
			else:
				active_strike.defender_set_face_up = true
				_append_log_full(Enums.LogType.LogType_Strike, performing_player, "以明置攻击应战！")
				var card_name = card_db.get_card_name(active_strike.defender_card.id)
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "正以%s进行战斗。" % _log_card_name(card_name))
			create_event(Enums.EventType.EventType_RevealStrike_OnePlayer, performing_player.my_id, 0)
		StrikeEffects.MayGenerateGaugeWithForce:
			performing_player.strike_stat_boosts.may_generate_gauge_with_force = true
		StrikeEffects.MayInvalidateUltras:
			performing_player.strike_stat_boosts.may_invalidate_ultras = true
		StrikeEffects.MoveBuddy:
			var buddy_id = ""
			if 'buddy_id' in effect:
				buddy_id = effect['buddy_id']
			decision_info.clear()
			decision_info.choice = []
			decision_info.limitation = []
			var optional = 'optional' in effect and effect['optional']
			if optional:
				decision_info.limitation.append(0)
				decision_info.choice.append({
					"effect_type": StrikeEffects.Pass
				})
			var min_spaces = effect['amount']
			var max_spaces = effect['amount2']
			for i in range(Enums.MinArenaLocation, Enums.MaxArenaLocation + 1):
				var distance = abs(performing_player.get_buddy_location() - i)
				if distance >= min_spaces and distance <= max_spaces:
					decision_info.limitation.append(i)
					var location_choice = {
						"effect_type": StrikeEffects.PlaceBuddyIntoSpace,
						"buddy_id": buddy_id,
						"amount": i
					}
					if 'strike_after' in effect and effect['strike_after']:
						location_choice["and"] = {
							"effect_type": StrikeEffects.Strike
						}
					decision_info.choice.append(location_choice)
			if decision_info.limitation.size() > 1 or (not optional and decision_info.limitation.size() > 0):
				decision_info.type = Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect
				decision_info.player = performing_player.my_id
				decision_info.choice_card_id = card_id
				decision_info.effect_type = StrikeEffects.PlaceBuddyIntoSpace
				decision_info.source = effect['buddy_name']
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				create_event(Enums.EventType.EventType_ChooseArenaLocationForEffect, performing_player.my_id, 0)
		StrikeEffects.MoveToBuddy:
			var buddy_id = ""
			if 'buddy_id' in effect:
				buddy_id = effect['buddy_id']
			var buddy_name = performing_player.get_buddy_name(buddy_id)
			var buddy_location = performing_player.get_buddy_location(buddy_id)
			var previous_location = performing_player.arena_location
			performing_player.move_to(buddy_location)
			_append_log_full(Enums.LogType.LogType_CharacterMovement, performing_player, "移动到%s，从格子%s移动到%s。" % [buddy_name, str(previous_location), str(performing_player.arena_location)])
		StrikeEffects.MoveToBoostSpace:
			var boost_buddy_id = performing_player.get_buddy_id_for_boost(card_id)
			var buddy_name = performing_player.get_buddy_name(boost_buddy_id)
			var buddy_location = performing_player.get_buddy_location(boost_buddy_id)
			var previous_location = performing_player.arena_location
			performing_player.move_to(buddy_location)
			_append_log_full(Enums.LogType.LogType_CharacterMovement, performing_player, "移动到%s，从格子%s移动到%s。" % [buddy_name, str(previous_location), str(performing_player.arena_location)])
		StrikeEffects.MultiplyPowerBonuses:
			performing_player.strike_stat_boosts.power_bonus_multiplier = max(effect['amount'], performing_player.strike_stat_boosts.power_bonus_multiplier)
		StrikeEffects.MultiplyPositivePowerBonuses:
			performing_player.strike_stat_boosts.power_bonus_multiplier_positive_only = max(effect['amount'], performing_player.strike_stat_boosts.power_bonus_multiplier_positive_only)
		StrikeEffects.MultiplySpeedBonuses:
			performing_player.strike_stat_boosts.speed_bonus_multiplier = max(effect['amount'], performing_player.strike_stat_boosts.speed_bonus_multiplier)
		StrikeEffects.NonlethalAttack:
			performing_player.strike_stat_boosts.deal_nonlethal_damage = true
		StrikeEffects.RegainOncePerGameResource:
			performing_player.once_per_game_resource = 1
		StrikeEffects.UseOncePerGameResource:
			performing_player.once_per_game_resource = 0
		StrikeEffects.OpponentCantMoveIfInRange:
			opposing_player.strike_stat_boosts.cannot_move_if_in_opponents_range = true
			_append_log_full(Enums.LogType.LogType_Effect, opposing_player, "在%s的距离内时被阻止移动。" % performing_player.name)
		StrikeEffects.OpponentCantMovePast:
			opposing_player.cannot_move_past_opponent = true
			create_event(Enums.EventType.EventType_Strike_OpponentCantMovePast, performing_player.my_id, 0)
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "不能被前进穿过！")
		StrikeEffects.OpponentCantMovePastBuddy:
			var buddy_id = ""
			if 'buddy_id' in effect:
				buddy_id = effect['buddy_id']
			else:
				buddy_id = performing_player.buddy_id_to_index.keys()[0]
			var buddy_name = performing_player.get_buddy_name(buddy_id)

			opposing_player.cannot_move_past_opponent_buddy_id = buddy_id
			create_event(Enums.EventType.EventType_Strike_OpponentCantMovePast, performing_player.my_id, 0, "", buddy_name)
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "的%s不能被前进穿过！" % buddy_name)
		StrikeEffects.RemoveOpponentCantMovePast:
			opposing_player.cannot_move_past_opponent = false
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "不再阻挡对手移动。")
		StrikeEffects.RemoveOpponentCantMovePastBuddy:
			var buddy_id = ""
			if 'buddy_id' in effect:
				buddy_id = effect['buddy_id']
			else:
				buddy_id = performing_player.buddy_id_to_index.keys()[0]
			var buddy_name = performing_player.get_buddy_name(buddy_id)

			opposing_player.cannot_move_past_opponent_buddy_id = null
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "的%s不再阻挡对手移动。" % buddy_name)
		StrikeEffects.ReturnAttackToTopOfDeck:
			if performing_player.my_id == active_turn_player:
				performing_player.skip_end_of_turn_draw = true
			if active_strike.extra_attack_in_progress:
				var extra_card = active_strike.extra_attack_data.extra_attack_card
				var extra_card_name = extra_card.definition['display_name']

				# Opponent's cards can never enter your deck or discard pile: discard
				# to the OWNER's discard pile instead of topdecking it.
				if extra_card.owner_id != performing_player.my_id:
					var owner_player = _get_player(extra_card.owner_id)
					if owner_player != null:
						_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将对手的攻击%s弃置到其弃牌堆。" % _log_card_name(extra_card_name))
						owner_player.add_to_discards(extra_card)
					else:
						performing_player.add_to_discards(extra_card)
				else:
					_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将其攻击%s返回到牌库顶。" % _log_card_name(extra_card_name))
					performing_player.add_to_top_of_deck(extra_card, true)
				active_strike.cards_in_play.erase(extra_card) #???
			else:
				performing_player.strike_stat_boosts.attack_to_topdeck_on_cleanup = true
				handle_strike_attack_immediate_removal(performing_player)
		StrikeEffects.ReturnAllCopiesOfTopDiscardToHand:
			performing_player.return_all_copies_of_top_discard_to_hand()
		StrikeEffects.Nothing:
			# Do nothing.
			pass
		StrikeEffects.OpponentDiscardChoose:
			if effect.get("jinglechunshui_choose_two_continuation", false):
				and_handled_elsewhere = true
			var allow_fewer = 'allow_fewer' in effect and effect['allow_fewer']
			var destination = "discard"
			if 'destination' in effect:
				destination = effect['destination']
			var discard_effect = null
			if 'discard_effect' in effect:
				discard_effect = effect['discard_effect']

			var this_effect = effect.duplicate()
			if str(this_effect['amount']) == "force_spent_before_strike":
				# intentionally performing_player, rather than choice_player
				this_effect['amount'] = performing_player.force_spent_before_strike
			elif str(this_effect['amount']) == "CARDS_DISCARDED_THIS_STRIKE":
				this_effect['amount'] = active_strike.cards_discarded_this_strike

			var discard_amount = this_effect['amount']
			if not allow_fewer:
				discard_amount -= opposing_player.strike_stat_boosts.reduce_discard_effects_by
				if discard_amount < 0:
					discard_amount = 0
			this_effect['amount'] = discard_amount

			if discard_amount > 0 and (opposing_player.hand.size() > discard_amount or (allow_fewer and opposing_player.hand.size() > 0)):
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_ChooseToDiscard
				decision_info.effect_type = StrikeEffects.OpponentDiscardChooseInternal
				decision_info.effect = this_effect
				decision_info.source_player_id = this_effect.get("_source_player_id", _last_effect_source_player_id)
				decision_info.bonus_effect = discard_effect
				decision_info.destination = destination
				decision_info.limitation = ""
				decision_info.can_pass = false

				decision_info.choice_card_id = card_id
				decision_info.player = opposing_player.my_id
				create_event(Enums.EventType.EventType_Strike_ChooseToDiscard, opposing_player.my_id, discard_amount, "", allow_fewer)
			else:
				create_event(Enums.EventType.EventType_Strike_ChooseToDiscard_Info, opposing_player.my_id, discard_amount)
				# Forced to discard whole hand.
				var card_ids = []
				if discard_amount > 0 and opposing_player.hand.size() > 0:
					assert(opposing_player.hand.size() <= discard_amount)
					card_ids = opposing_player.get_card_ids_in_hand()
					if destination == "discard":
						opposing_player.discard_hand()
					elif destination == "reveal":
						opposing_player.reveal_hand()

				if discard_effect:
					discard_effect = discard_effect.duplicate()
					discard_effect['discarded_card_ids'] = card_ids
					do_effect_if_condition_met(opposing_player, card_id, discard_effect, local_conditions)
				elif len(card_ids) < discard_amount and 'smaller_discard_effect' in effect:
					do_effect_if_condition_met(opposing_player, card_id, effect['smaller_discard_effect'], local_conditions)
		StrikeEffects.OpponentDiscardChooseInternal:
			var cards = effect['card_ids']
			var card_names = card_db.get_card_names(cards)
			if effect['destination'] == "discard":
				_append_log_full(Enums.LogType.LogType_CardInfo, opposing_player, "让%s选择要弃置的牌：%s。" % [performing_player.name, _log_card_name(card_names)])
				performing_player.discard(cards)
			elif effect['destination'] == "reveal":
				_append_log_full(Enums.LogType.LogType_CardInfo, opposing_player, "让%s选择要展示的牌：%s。" % [performing_player.name, _log_card_name(card_names)])
				performing_player.reveal_card_ids(cards)
				for revealed_card_id in cards:
					create_event(Enums.EventType.EventType_RevealCard, performing_player.my_id, revealed_card_id)
		StrikeEffects.OpponentDiscardHand:
			var num_discarded = opposing_player.hand.size()

			if opposing_player.strike_stat_boosts.reduce_discard_effects_by > 0:
				var manual_discard_effect = {
					"effect_type": StrikeEffects.OpponentDiscardChoose,
					"amount": num_discarded
				} # opponent_discard_choose will handle the smaller discard amount
				handle_strike_effect(card_id, manual_discard_effect, performing_player)
				num_discarded -= opposing_player.strike_stat_boosts.reduce_discard_effects_by
			else:
				opposing_player.discard_hand()

			if 'save_num_discarded_as_strike_x' in effect and effect['save_num_discarded_as_strike_x']:
				_append_log_full(Enums.LogType.LogType_Strike, performing_player, "此次战斗的X被设为弃置牌的数量，%s。" % num_discarded)
				performing_player.set_strike_x(num_discarded)
		StrikeEffects.OpponentDiscardRandom:
			var discard_amount = effect['amount']
			discard_amount -= opposing_player.strike_stat_boosts.reduce_discard_effects_by
			if discard_amount < 0:
				discard_amount = 0

			var discard_ids = opposing_player.pick_random_cards_from_hand(discard_amount)
			if discard_ids.size() > 0:
				var discarded_names = card_db.get_card_names(discard_ids)
				if 'destination' in effect and effect['destination'] == "overdrive":
					_append_log_full(Enums.LogType.LogType_CardInfo, opposing_player, "随机弃置牌到对手的超载：%s。" % _log_card_name(discarded_names))
					opposing_player.discard(discard_ids)
					performing_player.move_cards_to_overdrive(discard_ids, "opponent_discard")
				else:
					_append_log_full(Enums.LogType.LogType_CardInfo, opposing_player, "随机弃置牌：%s。" % _log_card_name(discarded_names))
					opposing_player.discard(discard_ids)
		"wonderland_add_card":
			_exceeded_wonderland_active = false
			var wc_id = effect['card_id']
			# Move card from discard or sealed to Wonderland, replacing old card
			var found = false
			for search_player in [opposing_player, performing_player]:
				# Search discards first
				for i in range(search_player.discards.size()):
					if search_player.discards[i].id == wc_id:
						var card = search_player.discards[i]
						search_player.discards.remove_at(i)
						if performing_player.set_aside_cards.size() > 0:
							var old = performing_player.set_aside_cards[0]
							performing_player.set_aside_cards.clear()
							if old.definition.get("id") == "wonderland":
								# Wonderland 标记卡：直接退役，不要塞进对手弃牌堆 ——
								# 塞进去会污染对手的弃牌堆数据（之后被洗回牌库、抽到手牌），
								# 在 UI 上表现为一张没有图的「黑白卡」。
								pass
							else:
								opposing_player.discards.append(old)
								create_event(Enums.EventType.EventType_AddToDiscard, opposing_player.my_id, old.id, "", 0)
						performing_player.add_to_set_aside(card)
						create_event(Enums.EventType.EventType_AddToStored, performing_player.my_id, card.id)
						_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "adds %s to Wonderland!" % _log_card_name(card.definition['display_name']))
						found = true
						break
				if found: break
				# Search sealed area (e.g. Celinka seal instead of discard)
				for i in range(search_player.sealed.size()):
					if search_player.sealed[i].id == wc_id:
						var card = search_player.sealed[i]
						search_player.sealed.remove_at(i)
						if performing_player.set_aside_cards.size() > 0:
							var old = performing_player.set_aside_cards[0]
							performing_player.set_aside_cards.clear()
							if old.definition.get("id") == "wonderland":
								# 同 discard 分支：占位标记卡直接退役，不污染对手弃牌堆。
								pass
							else:
								opposing_player.discards.append(old)
								create_event(Enums.EventType.EventType_AddToDiscard, opposing_player.my_id, old.id, "", 0)
						performing_player.add_to_set_aside(card)
						create_event(Enums.EventType.EventType_AddToStored, performing_player.my_id, card.id)
						_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "adds %s to Wonderland!" % _log_card_name(card.definition['display_name']))
						found = true
						break
				if found: break
		StrikeEffects.Pass:
			if performing_player.deck_def.get("id", "") == "dongshilang":
				var setup_once = effect.get("setup_once", false)
				var move_ice_amount = int(effect.get("ice_from_set_aside_to_bleach", 0))
				if move_ice_amount > 0:
					if not setup_once or not performing_player.dongshilang_opening_ice_setup_done:
						_dongshilang_move_ice_from_set_aside_to_bleach(performing_player, move_ice_amount, true)
						if setup_once:
							performing_player.dongshilang_opening_ice_setup_done = true

				if effect.get("grant_exceed_character_action", false):
					var exceed_actions = performing_player.deck_def.get("character_action_exceeded", [])
					var action_effect = {}
					if exceed_actions.size() > 0:
						action_effect = exceed_actions[0].get("effect", {})
					_dongshilang_start_ice_character_action(performing_player, action_effect, true)

				if effect.has("required_ice_boost_count"):
					var required_count = int(effect.get("required_ice_boost_count", 0))
					var count_type = effect.get("count_type", "ice_crystal")
					var current_count = _dongshilang_count_ice_in_boost_zone(performing_player, count_type)
					for ice_card in performing_player.bleach_zone:
						if ice_card.definition.get("type", "") == count_type:
							current_count += 1
					if current_count != required_count and performing_player.exceeded:
						performing_player.revert_exceed()

				var is_ice_character_action = effect.get("valid_zones", []).has("bleach") and effect.get("limitation", "") == "ice_crystal"
				if is_ice_character_action:
					_dongshilang_start_ice_character_action(performing_player, effect, false)
			# Do nothing.
			pass
		StrikeEffects.PlaceBoostInSpace:
			var in_attack_range = 'in_attack_range' in effect and effect['in_attack_range']
			var valid_locations = null
			if 'valid_locations' in effect:
				valid_locations = effect['valid_locations']
			var stop_on_space_effect = 'stop_on_space_effect' in effect and 'stop_on_space_effect'
			var boost_already_placed = 'boost_already_placed' in effect and effect['boost_already_placed']

			change_game_state(Enums.GameState.GameState_PlayerDecision)
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect
			decision_info.player = performing_player.my_id
			decision_info.choice_card_id = card_id
			decision_info.effect_type = StrikeEffects.PlaceBoostInSpace
			var boost_name = card_db.get_card(card_id).definition['boost']['display_name']
			decision_info.source = boost_name
			decision_info.choice = []
			decision_info.limitation = []
			var if_placed_effect = null
			if 'if_placed_effect' in effect:
				if_placed_effect = effect['if_placed_effect']
			if 'optional' in effect and effect['optional']:
				decision_info.limitation.append(0)
				decision_info.choice.append({
					"effect_type": StrikeEffects.Pass
				})
			for i in range(Enums.MinArenaLocation, Enums.MaxArenaLocation + 1):
				if in_attack_range and not is_location_in_range(performing_player, active_strike.get_player_card(performing_player), i):
					continue
				if valid_locations != null and i not in valid_locations:
					continue

				decision_info.limitation.append(i)
				decision_info.choice.append({
					"effect_type": StrikeEffects.PlaceBoostInSpaceInternal,
					"card_id": card_id,
					"location": i,
					"and": if_placed_effect,
					"stop_on_space_effect": stop_on_space_effect,
					"boost_already_placed": boost_already_placed
				})
			create_event(Enums.EventType.EventType_ChooseArenaLocationForEffect, performing_player.my_id, 0)
		StrikeEffects.PlaceBoostInSpaceInternal:
			var location = effect['location']
			var placed_card_id = effect['card_id']
			var stop_on_space_effect = effect['stop_on_space_effect']

			if effect['boost_already_placed'] or performing_player.get_boost_location(placed_card_id) != -1:
				# 已在场上（含「从加成区设置攻击」保留的攻击源）→ 更新位置而非重复放置。
				performing_player.change_boost_location(placed_card_id, location)
			else:
				performing_player.add_boost_to_location(placed_card_id, location, stop_on_space_effect)
		StrikeEffects.LightningrodStrike:
			var lightning_card_id = effect['card_id']
			var location = effect['location']
			var card_name = effect['card_name']

			# Remove lightning rod and put the card back in hand.
			var lightning_card = performing_player.remove_lightning_card(lightning_card_id, location)
			performing_player.add_to_hand(lightning_card, true)
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将Lightning Rod %s加入其手牌。" % _log_card_name(card_name))
			create_event(Enums.EventType.EventType_PlaceLightningRod, performing_player.my_id, lightning_card_id, "", location, false)

			# Deal the damage
			var damage_effect = {
				"effect_type": StrikeEffects.TakeDamage,
				"opponent": true,
				"nonlethal": true,
				"amount": 2
			}
			handle_strike_effect(lightning_card_id, damage_effect, performing_player)
		StrikeEffects.MoveToLightningrods:
			var valid_locations = []
			for i in range(Enums.MinArenaLocation, Enums.MaxArenaLocation + 1):
				var lightningzone = performing_player.get_lightningrod_zone_for_location(i)
				if len(lightningzone) > 0:
					if performing_player.can_move_to(i, true):
						if i not in valid_locations:
							valid_locations.append(i)
					elif opposing_player.is_in_location(i):
						# If the opponent is on a lightning rod, you can treat this like Close.
						var direction = 1
						if performing_player.arena_location < opposing_player.arena_location:
							direction = -1

						# Include the next available space closest to the opponent.
						# Loop from i towards the player.
						# The player's current space should be usable if they're adjacent to the opponent.
						for test_location in range(i, performing_player.arena_location + direction, direction):
							if performing_player.is_overlapping_opponent(test_location):
								continue
							if performing_player.can_move_to(test_location, true) or test_location == performing_player.arena_location:
								if performing_player.cannot_move:
									break
								if test_location not in valid_locations:
									valid_locations.append(test_location)
								break

			if len(valid_locations) > 0:
				# Let the player choose where to go.
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect
				decision_info.player = performing_player.my_id
				decision_info.choice_card_id = card_id
				decision_info.effect_type = StrikeEffects.MoveToSpace
				decision_info.choice = []
				decision_info.limitation = []
				decision_info.extra_info = ""

				for location in valid_locations:
					decision_info.limitation.append(location)
					decision_info.choice.append({
						"effect_type": StrikeEffects.MoveToSpace,
						"amount": location,
						"remove_buddies_encountered": false,
					})

				change_game_state(Enums.GameState.GameState_PlayerDecision)
				create_event(Enums.EventType.EventType_ChooseArenaLocationForEffect, performing_player.my_id, 0)
			else:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "没有可移动到的避雷针！")
		StrikeEffects.PlaceLightningrod:
			var source = effect['source']
			var limitation = effect['limitation']
			var lightning_card
			var valid_locations = []

			match limitation:
				"any":
					for i in range(Enums.MinArenaLocation, Enums.MaxArenaLocation + 1):
						valid_locations.append(i)
				"attack_range":
					assert(active_strike, "No active strike for lightningrod attack_range.")
					var attack_card = active_strike.get_player_card(performing_player)
					for i in range(Enums.MinArenaLocation, Enums.MaxArenaLocation + 1):
						if is_location_in_range(performing_player, attack_card, i):
							valid_locations.append(i)
				_:
					assert(false, "Unknown lightningrod limitation.")

			# Make sure not to handle the attack card before the range check above,
			# because discarding the attack card here will force the range check
			# to fail as the attack is no longer valid.
			match source:
				"top_discard":
					lightning_card = performing_player.get_top_discard_card()
				"this_attack_card":
					lightning_card = active_strike.get_player_card(performing_player)
					# If this is the current attack, get rid of it now, putting it on top the discard pile.
					# This is convenient since now lightning rods always come from the top discard card.
					performing_player.strike_stat_boosts.discard_attack_now_for_lightningrod = true
					handle_strike_attack_immediate_removal(performing_player)
				_:
					assert(false, "Unknown lightningrod source.")

			if lightning_card and valid_locations:
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect
				decision_info.player = performing_player.my_id
				decision_info.choice_card_id = card_id
				decision_info.effect_type = StrikeEffects.PlaceLightningrod
				decision_info.choice = []
				decision_info.limitation = []
				for i in valid_locations:
					decision_info.limitation.append(i)
					decision_info.choice.append({
						"effect_type": StrikeEffects.PlaceLightningrodInternal,
						"location": i,
					})
				create_event(Enums.EventType.EventType_ChooseArenaLocationForEffect, performing_player.my_id, 0)
		StrikeEffects.PlaceLightningrodInternal:
			var location = effect['location']
			performing_player.place_top_discard_as_lightningrod(location)
		StrikeEffects.PlaceBuddyAtRange:
			handle_place_buddy_at_range(performing_player, card_id, effect)
		StrikeEffects.PlaceBuddyIntoSpace:
			var space = effect['amount']
			var buddy_id = ""
			if 'buddy_id' in effect:
				buddy_id = effect['buddy_id']
			var old_buddy_pos = performing_player.get_buddy_location(buddy_id)
			performing_player.place_buddy(space, buddy_id)

			var buddy_name = performing_player.get_buddy_name(buddy_id)
			if old_buddy_pos == -1:
				_append_log_full(Enums.LogType.LogType_CharacterMovement, performing_player, "将%s移动到格子%s。" % [buddy_name, str(space)])
			else:
				_append_log_full(Enums.LogType.LogType_CharacterMovement, performing_player, "将%s从格子%s移动到%s。" % [buddy_name, str(old_buddy_pos), str(space)])

			if 'place_other_buddy_effect' in effect:
				handle_place_buddy_at_range(performing_player, card_id, effect['place_other_buddy_effect'])
		StrikeEffects.PlaceBuddyInAnySpace:
			var buddy_id = ""
			if 'buddy_id' in effect:
				buddy_id = effect['buddy_id']
			change_game_state(Enums.GameState.GameState_PlayerDecision)
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect
			decision_info.player = performing_player.my_id
			decision_info.choice_card_id = card_id
			decision_info.effect_type = StrikeEffects.PlaceBuddyIntoSpace
			decision_info.source = effect['buddy_name']
			decision_info.choice = []
			decision_info.limitation = []
			if 'optional' in effect and effect['optional']:
				decision_info.limitation.append(0)
				decision_info.choice.append({
					"effect_type": StrikeEffects.Pass
				})
			for i in range(Enums.MinArenaLocation, Enums.MaxArenaLocation + 1):
				decision_info.limitation.append(i)
				var new_choice = {
					"effect_type": StrikeEffects.PlaceBuddyIntoSpace,
					"buddy_id": buddy_id,
					"amount": i
				}
				if 'additional_effect' in effect:
					new_choice['and'] = effect['additional_effect']
				decision_info.choice.append(new_choice)
			create_event(Enums.EventType.EventType_ChooseArenaLocationForEffect, performing_player.my_id, 0)
		StrikeEffects.PlaceBuddyInAttackRange:
			var buddy_id = ""
			if 'buddy_id' in effect:
				buddy_id = effect['buddy_id']
			decision_info.clear()
			decision_info.choice = []
			decision_info.limitation = []
			var attack_card = active_strike.get_player_card(performing_player)
			var optional = 'optional' in effect and effect['optional']
			if optional:
				decision_info.limitation.append(0)
				decision_info.choice.append({
					"effect_type": StrikeEffects.Pass
				})
			for i in range(Enums.MinArenaLocation, Enums.MaxArenaLocation + 1):
				if is_location_in_range(performing_player, attack_card, i):
					decision_info.limitation.append(i)
					var new_choice = {
						"effect_type": StrikeEffects.PlaceBuddyIntoSpace,
						"buddy_id": buddy_id,
						"amount": i
					}
					if 'additional_effect' in effect:
						new_choice['and'] = effect['additional_effect']
					decision_info.choice.append(new_choice)
			if decision_info.limitation.size() > 1 or (not optional and decision_info.limitation.size() > 0):
				decision_info.type = Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect
				decision_info.player = performing_player.my_id
				decision_info.choice_card_id = card_id
				decision_info.effect_type = StrikeEffects.PlaceBuddyIntoSpace
				decision_info.source = effect['buddy_name']
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				create_event(Enums.EventType.EventType_ChooseArenaLocationForEffect, performing_player.my_id, 0)
		StrikeEffects.PlaceBuddyOntoOpponent:
			var buddy_id = ""
			if 'buddy_id' in effect:
				buddy_id = effect['buddy_id']
			var old_buddy_pos = performing_player.get_buddy_location(buddy_id)
			var buddy_name = performing_player.get_buddy_name(buddy_id)
			performing_player.place_buddy(opposing_player.arena_location, buddy_id)
			var space = performing_player.get_buddy_location(buddy_id)
			if old_buddy_pos == -1:
				_append_log_full(Enums.LogType.LogType_CharacterMovement, performing_player, "将%s移动到%s所在的格子%s。" % [buddy_name, opposing_player.name, str(space)])
			else:
				_append_log_full(Enums.LogType.LogType_CharacterMovement, performing_player, "将%s移动到%s，从格子%s移动到%s。" % [buddy_name, opposing_player.name, str(old_buddy_pos), str(space)])
		StrikeEffects.PlaceBuddyOntoSelf:
			var buddy_id = ""
			if 'buddy_id' in effect:
				buddy_id = effect['buddy_id']
			var old_buddy_pos = performing_player.get_buddy_location(buddy_id)
			var buddy_name = performing_player.get_buddy_name(buddy_id)
			performing_player.place_buddy(performing_player.arena_location, buddy_id)
			var space = performing_player.get_buddy_location(buddy_id)
			if old_buddy_pos == -1:
				_append_log_full(Enums.LogType.LogType_CharacterMovement, performing_player, "将%s移动到自己所在的格子%s。" % [buddy_name, str(space)])
			else:
				_append_log_full(Enums.LogType.LogType_CharacterMovement, performing_player, "将%s移动到自己处，从格子%s移动到%s。" % [buddy_name, str(old_buddy_pos), str(space)])
		StrikeEffects.PlaceTopdeckUnderBoost:
			performing_player.place_top_deck_under_boost(card_id)
		StrikeEffects.PlayBoostWithCardsUnder:
			performing_player.setup_boost_with_cards_under(card_id)
		StrikeEffects.DrawCardsUnderBoostAndRemove:
			var boost_name = card_db.get_card_name(card_id)
			var cards_under_boost = performing_player.get_cards_under_boost(card_id)
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将%s张位于%s下方的牌加入手牌。" % [len(cards_under_boost), boost_name])
			for card in cards_under_boost:
				performing_player.add_to_hand(card, false)
			performing_player.remove_boost_with_cards_under(card_id)
		StrikeEffects.PlaceNextBuddy:
			var require_unoccupied = effect['require_unoccupied']
			var destination = effect['destination']
			var num_buddies = effect['amount']
			var valid_new_positions = [1,2,3,4,5,6,7,8,9]
			var already_removed_buddy = 'already_removed_buddy' in effect and effect['already_removed_buddy']
			if already_removed_buddy and effect.get("valid_new_positions"):
				valid_new_positions = effect['valid_new_positions']
			else:
				# Filter based on destination requirements.
				match destination:
					"attack_range":
						var attack_card = active_strike.get_player_card(performing_player)
						for i in range(valid_new_positions.size() - 1, -1, -1):
							var check_position = valid_new_positions[i]
							if not is_location_in_range(performing_player, attack_card, check_position):
								valid_new_positions.remove_at(i)
					"anywhere":
						pass
					"adjacent_self":
						for i in range(valid_new_positions.size() - 1, -1, -1):
							var check_position = valid_new_positions[i]
							if not (check_position == performing_player.arena_location - 1 or check_position == performing_player.arena_location + 1):
								valid_new_positions.remove_at(i)
					"self":
						for i in range(valid_new_positions.size() - 1, -1, -1):
							var check_position = valid_new_positions[i]
							if not performing_player.is_in_location(check_position):
								valid_new_positions.remove_at(i)
					_:
						assert(false, "Unknown destination for place_next_buddy")

				# Filter based on requiring no players in those spaces.
				if require_unoccupied:
					for i in range(valid_new_positions.size() - 1, -1, -1):
						var check_position = valid_new_positions[i]
						if performing_player.is_in_location(check_position) or opposing_player.is_in_location(check_position):
							valid_new_positions.remove_at(i)
				# Filter out any location that already has your buddy.
				for i in range(valid_new_positions.size() - 1, -1, -1):
					var check_position = valid_new_positions[i]
					if check_position in performing_player.buddy_locations:
						valid_new_positions.remove_at(i)

			if valid_new_positions.size() > 0:
				var must_select_other_buddy_first = performing_player.are_all_buddies_in_play()
				# The player can now select one of these new spaces to place their buddy,
				# or they can select and existing buddy and remove it first.
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect
				decision_info.player = performing_player.my_id
				decision_info.choice_card_id = card_id
				decision_info.effect_type = StrikeEffects.PlaceNextBuddy
				decision_info.source = effect['buddy_name']
				decision_info.choice = []
				decision_info.limitation = []
				decision_info.extra_info = must_select_other_buddy_first
				var and_effect = null
				if 'and' in effect:
					and_effect = effect['and']
					and_handled_elsewhere = true
				if num_buddies > 1:
					# Placing multiple buddies, so turn the and effect into a copy of this effect.
					and_effect = {
						"effect_type": StrikeEffects.PlaceNextBuddy,
						"buddy_name": effect['buddy_name'],
						"amount": num_buddies - 1,
						"destination": destination,
						"require_unoccupied": require_unoccupied,
						"and": and_effect
					}
				for i in range(Enums.MinArenaLocation, Enums.MaxArenaLocation + 1):
					if not must_select_other_buddy_first and i in valid_new_positions:
						# The player elects to place the next available buddy here.
						decision_info.limitation.append(i)
						decision_info.choice.append({
							"effect_type": StrikeEffects.PlaceBuddyIntoSpace,
							"buddy_id": performing_player.get_next_free_buddy_id(),
							"amount": i,
							"and": and_effect
						})
					elif not already_removed_buddy and i in performing_player.buddy_locations:
						# The player elects to remove this buddy first.
						decision_info.limitation.append(i)
						decision_info.choice.append({
							"effect_type": StrikeEffects.RemoveBuddy,
							"buddy_id": performing_player.get_buddy_id_at_location(i),
							"and": {
								"effect_type": StrikeEffects.PlaceNextBuddy,
								"buddy_name": effect['buddy_name'],
								"amount": -1, # Additional already in the and effect.
								"already_removed_buddy": true,
								"require_unoccupied": require_unoccupied,
								"destination": destination,
								"and": and_effect
							}
						})
				if decision_info.choice.size() == 1:
					# Only one choice, so just do it immediately.
					handle_strike_effect(card_id, decision_info.choice[0], performing_player)
				else:
					change_game_state(Enums.GameState.GameState_PlayerDecision)
					create_event(Enums.EventType.EventType_ChooseArenaLocationForEffect, performing_player.my_id, 0)
			else:
				# No valid positions to put the buddy, so skip this.
				# The and effect will occur normally if one exists.
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "没有可放置%s的有效位置。" % effect['buddy_name'])
		StrikeEffects.MoveAnyBoost:
			var move_min = effect['amount_min']
			var move_max = effect['amount_max']
			var must_select_other_buddy_first = true
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect
			decision_info.player = performing_player.my_id
			decision_info.choice_card_id = card_id
			decision_info.effect_type = StrikeEffects.PlaceBoostInSpace
			decision_info.source = effect['boost_name']
			decision_info.choice = []
			decision_info.limitation = []
			decision_info.extra_info = must_select_other_buddy_first

			var location_choice_map = {}

			# First, the player has to select a boost to remove.
			# Then, they have to place it in a valid space.
			for boost in performing_player.continuous_boosts:
				if boost.definition['boost']['display_name'] != effect['boost_name']:
					continue
				var boost_id = boost.id
				var location = performing_player.get_boost_location(boost.id)
				if location == -1:
					continue

				var valid_locations = []
				for i in range(Enums.MinArenaLocation, Enums.MaxArenaLocation + 1):
					# Add this space if it is within the amount from the starting buddy location.
					if abs(location - i) >= move_min and abs(location - i) <= move_max:
						valid_locations.append(i)

				if valid_locations.size() > 0:
					var boost_str = _get_boost_and_card_name(boost)
					if location not in location_choice_map:
						location_choice_map[location] = []
					location_choice_map[location].append({
						"effect_type": StrikeEffects.PlaceBoostInSpace,
						"boost_name": boost_str,
						"card_id": boost_id,
						"boost_already_placed": true,
						"valid_locations": valid_locations
					})

			# Account for multiple boosts in the same space
			for location in range(Enums.MinArenaLocation, Enums.MaxArenaLocation + 1):
				if location not in location_choice_map:
					continue

				var location_choices = location_choice_map[location]
				decision_info.limitation.append(location)
				if len(location_choices) == 1:
					decision_info.choice.append(location_choices[0])
				else:
					var choice_effect = {
						"effect_type": StrikeEffects.Choice,
						StrikeEffects.Choice: location_choices
					}
					decision_info.choice.append(choice_effect)

			var actual_choices = len(decision_info.limitation)

			# If the only option is to pass, just let this pass.
			if actual_choices > 0:
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				create_event(Enums.EventType.EventType_ChooseArenaLocationForEffect, performing_player.my_id, 0)
			else:
				assert(false, "Unexpected called move_any_boost but can't.")
		StrikeEffects.MoveAnyBuddy:
			var move_to_opponent = 'to_opponent' in effect and effect['to_opponent']
			var move_min = effect['amount_min']
			var move_max = effect['amount_max']
			var optional = (move_min == 0)
			var must_select_other_buddy_first = true
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect
			decision_info.player = performing_player.my_id
			decision_info.choice_card_id = card_id
			decision_info.effect_type = StrikeEffects.PlaceNextBuddy
			decision_info.source = effect['buddy_name']
			decision_info.choice = []
			decision_info.limitation = []
			decision_info.extra_info = must_select_other_buddy_first
			if optional:
				decision_info.limitation.append(0)
				decision_info.choice.append({
					"effect_type": StrikeEffects.Pass
				})
			# First, the player has to select a buddy to remove.
			# Then, they have to place it in a valid space.
			for location in performing_player.buddy_locations:
				if location == -1:
					continue
				var buddy_id = performing_player.get_buddy_id_at_location(location)
				var valid_new_positions = []
				for i in range(Enums.MinArenaLocation, Enums.MaxArenaLocation + 1):
					var buddy_at_location = performing_player.get_buddy_id_at_location(i)
					if buddy_at_location != "" and buddy_at_location != buddy_id:
						# Skip if there is already a buddy here, but allow self.
						continue
					if move_to_opponent and opposing_player.is_in_location(i):
						valid_new_positions.append(i)
					else:
						# Add this space if it is within the amount from the starting buddy location.
						if abs(location - i) >= move_min and abs(location - i) <= move_max:
							valid_new_positions.append(i)

				if valid_new_positions.size() > 0:
					decision_info.limitation.append(location)
					decision_info.choice.append({
						"effect_type": StrikeEffects.RemoveBuddy,
						"buddy_id": buddy_id,
						"and": {
							"effect_type": StrikeEffects.PlaceNextBuddy,
							"buddy_name": effect['buddy_name'],
							"amount": -1,
							"already_removed_buddy": true,
							"require_unoccupied": false,
							"destination": "",
							"valid_new_positions": valid_new_positions
						}
					})
			var actual_choices = len(decision_info.limitation)
			if optional:
				actual_choices -= 1

			# If the only option is to pass, just let this pass.
			if actual_choices > 0:
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				create_event(Enums.EventType.EventType_ChooseArenaLocationForEffect, performing_player.my_id, 0)
			else:
				assert(false, "Unexpected called move_any_buddy but can't.")
		StrikeEffects.PassivePowerupPerCardInHand:
			var amount_per_hand = effect['amount']
			performing_player.strike_stat_boosts.passive_powerup_per_card_in_hand = amount_per_hand
			var hand_size = performing_player.hand.size()
			var total_powerup = amount_per_hand * hand_size
			if total_powerup != 0:
				create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, total_powerup)
		StrikeEffects.PassiveSpeedupPerCardInHand:
			var amount_per_hand = effect['amount']
			performing_player.strike_stat_boosts.passive_speedup_per_card_in_hand = amount_per_hand
			var hand_size = performing_player.hand.size()
			var total_speedup = amount_per_hand * hand_size
			if total_speedup != 0:
				create_event(Enums.EventType.EventType_Strike_SpeedUp, performing_player.my_id, total_speedup)
		StrikeEffects.PlayAttackFromHand:
			# Zsolt awaken: mark max damage 1 and count
			if effect.get("is_zsolt_awaken") and active_strike:
				active_strike.extra_attack_data.zsolt_max_damage_1 = true
				performing_player.zsolt_extra_attack_count += 1
			# Implement the choice via discard effect.
			var discard_effect = {
				"effect_type": StrikeEffects.SelfDiscardChoose,
				"optional": true,
				"amount": 1,
				"destination": "play_attack",
			}
			# Non-Zsolt: only show cards the player can afford to pay for
			if not effect.get("is_zsolt_awaken"):
				discard_effect["limitation"] = "can_pay_cost"
			handle_strike_effect(card_id, discard_effect, performing_player)
		StrikeEffects.PowerModifyPerBuddyBetween:
			performing_player.strike_stat_boosts.power_modify_per_buddy_between += effect['amount']
		StrikeEffects.Powerup:
			var amount = effect['amount']
			if str(amount) == "strike_x":
				amount = performing_player.strike_stat_boosts.strike_x
			elif str(amount) == "DISCARDED_COUNT":
				amount = performing_player.discards.size()
			var multiplier = 1
			if 'multiplier' in effect:
				multiplier = effect['multiplier']
			amount = amount * multiplier
			performing_player.add_power_bonus(amount)
			var life_threshold = effect.get("condition_amount", -1) if effect.get("condition", "") == "life_equal_or_below" else -1
			_register_life_conditional_boost(performing_player, "powerup", amount, life_threshold)
			if life_threshold >= 0:
				_register_life_conditional_chain(performing_player, effect.get("and"), life_threshold)
			create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, amount)
		StrikeEffects.PowerupBothPlayers:
			var amount = effect['amount']
			performing_player.add_power_bonus(amount)
			opposing_player.add_power_bonus(amount)
			create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, amount)
			create_event(Enums.EventType.EventType_Strike_PowerUp, opposing_player.my_id, amount)
		StrikeEffects.PowerupPerArmorUsed:
			var armor_consumed = performing_player.strike_stat_boosts.consumed_armor
			var power_change = armor_consumed * effect['amount']
			performing_player.add_power_bonus(power_change)
			create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, power_change)
		StrikeEffects.PowerupPerBoostInPlay:
			var boosts_in_play = performing_player.get_boosts().size()
			if boosts_in_play > 0:
				var amount = effect['amount'] * boosts_in_play
				performing_player.add_power_bonus(amount)
				create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, effect['amount'] * boosts_in_play)
		StrikeEffects.PowerupPerCardInHand:
			var amount_per_hand = effect['amount']
			var hand_size = performing_player.hand.size()
			var total_powerup = amount_per_hand * hand_size
			if 'amount_max' in effect:
				total_powerup = min(total_powerup, effect['amount_max'])
			if total_powerup > 0:
				performing_player.add_power_bonus(total_powerup)
				create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, total_powerup)
		StrikeEffects.PowerupPerCardInOpponentHand:
			var amount_per_hand = effect['amount']
			var hand_size = opposing_player.hand.size()
			if 'per_card' in effect:
				hand_size = floor(hand_size / effect['per_card'])
			var total_powerup = amount_per_hand * hand_size
			if total_powerup != 0:
				performing_player.add_power_bonus(total_powerup)
				create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, total_powerup)
		StrikeEffects.PowerupPerDamageTaken:
			var reese_damage_taken = active_strike.get_damage_taken(performing_player)
			var reese_powerup = effect['amount'] * reese_damage_taken
			if reese_powerup > 0:
				performing_player.add_power_bonus(reese_powerup)
				create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, reese_powerup)
		StrikeEffects.PowerupPerMoreCardsInHand:
			var reese_card_diff = max(0, performing_player.hand.size() - opposing_player.hand.size())
			var reese_powerup2 = effect['amount'] * reese_card_diff
			if reese_powerup2 > 0:
				performing_player.add_power_bonus(reese_powerup2)
				create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, reese_powerup2)
		StrikeEffects.PowerupPerForceSpentThisTurn:
			var amount = performing_player.total_force_spent_this_turn * effect['amount']
			performing_player.add_power_bonus(amount)
			create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, amount)
		StrikeEffects.PowerupPerGauge:
			var amount_per_gauge = effect['amount']
			var count_player = performing_player
			if effect.get("count_opponent"):
				count_player = opposing_player
			var gauge_size = count_player.gauge.size()
			var total_powerup = amount_per_gauge * gauge_size
			var amount_max = effect.get("amount_max", 999)
			total_powerup = min(total_powerup, amount_max)
			if total_powerup > 0:
				performing_player.add_power_bonus(total_powerup)
				create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, total_powerup)
		StrikeEffects.PowerupPerTransform:
			var amount_per_transform = effect['amount']
			var count_player = performing_player
			if effect.get("count_opponent"):
				count_player = opposing_player
			var transform_size = count_player.transforms.size()
			var total_powerup = amount_per_transform * transform_size
			var amount_max = effect.get("amount_max", 999)
			total_powerup = min(total_powerup, amount_max)
			if total_powerup > 0:
				performing_player.add_power_bonus(total_powerup)
				create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, total_powerup)
		StrikeEffects.PowerupPerGuard:
			var guard = get_total_guard(performing_player)
			if guard > 0:
				var bonus_power = effect['amount'] * guard
				if 'maximum' in effect:
					bonus_power = min(bonus_power, effect['maximum'])
				performing_player.add_power_bonus(bonus_power)
				create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, bonus_power)
		StrikeEffects.PowerupPerArmor:
			var armor = get_total_armor(performing_player)
			if armor > 0:
				var bonus_power = effect['amount'] * armor
				if 'maximum' in effect:
					bonus_power = min(bonus_power, effect['maximum'])
				performing_player.add_power_bonus(bonus_power)
				create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, bonus_power)
		StrikeEffects.PowerupPerSpeed:
			var speed = get_total_speed(performing_player)
			if speed > 0:
				var bonus_power = effect['amount'] * speed
				if 'maximum' in effect:
					bonus_power = min(bonus_power, effect['maximum'])
				performing_player.add_power_bonus(bonus_power)
				create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, bonus_power)
		StrikeEffects.PowerupPerPower:
			var power = get_total_power(performing_player)
			if power > 0:
				var bonus_power = effect['amount'] * power
				if 'maximum' in effect:
					bonus_power = min(bonus_power, effect['maximum'])
				performing_player.add_power_bonus(bonus_power)
				create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, bonus_power)
		StrikeEffects.PowerupPerSealedAmount:
			performing_player.strike_stat_boosts.powerup_per_sealed_amount_divisor = effect['divisor']
			performing_player.strike_stat_boosts.powerup_per_sealed_amount_max = effect['max']
			create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, 5, StrikeEffects.PowerupPerSealedAmount)
		StrikeEffects.PowerupPerSpentGaugeMatchingRangeToOpponent:
			var amount_per_gauge = effect['amount']
			var matching_count = 0
			var player_location = performing_player.arena_location
			var opponent_location = opposing_player.arena_location
			var opponent_width = opposing_player.extra_width
			for payment_card_id in performing_player.strike_stat_boosts.strike_payment_card_ids:
				var payment_card = card_db.get_card(payment_card_id)
				var printed_min = get_card_stat(performing_player, payment_card, 'range_min')
				var printed_max = get_card_stat(performing_player, payment_card, 'range_max')

				for opponent_space_offset in range(-opponent_width, opponent_width+1):
					var opponent_space = opponent_location + opponent_space_offset
					var distance : int = abs(player_location - opponent_space)
					if printed_min <= distance and distance <= printed_max:
						matching_count += 1
						break

			var total_powerup = amount_per_gauge * matching_count
			if total_powerup > 0:
				performing_player.add_power_bonus(total_powerup)
				create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, total_powerup)
		StrikeEffects.PowerupPerSealedNormal:
			var sealed_normals = performing_player.get_sealed_count_of_type("normal")
			if sealed_normals > 0:
				var bonus_power = effect['amount'] * sealed_normals
				if 'maximum' in effect:
					bonus_power = min(bonus_power, effect['maximum'])
				performing_player.add_power_bonus(bonus_power)
				create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, bonus_power)
		StrikeEffects.PowerupDamageTaken:
			var power_per_damage = effect['amount']
			var damage_taken = active_strike.get_damage_taken(performing_player)
			var total_powerup = power_per_damage * damage_taken
			# Checking for negative damage taken so that powerup is in expected "direction"
			if total_powerup != 0 and damage_taken > 0:
				performing_player.add_power_bonus(total_powerup)
				create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, total_powerup)
		StrikeEffects.PowerupDiscardedCardPrintedPower:
			var discarded_card_id = effect["discarded_card_ids"][0]
			var discarded_card = card_db.get_card(discarded_card_id)
			var printed_power = max(get_card_stat(performing_player, discarded_card, 'power'), 0)
			if printed_power > 0:
				performing_player.add_power_bonus(printed_power)
				create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, printed_power)
			var card_name = card_db.get_card_name(discarded_card_id)
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "获得%s的印刷威力：%s！" % [_log_card_name(card_name), printed_power])
		StrikeEffects.PowerupOpponent:
			opposing_player.add_power_bonus(effect['amount'])
			create_event(Enums.EventType.EventType_Strike_PowerUp, opposing_player.my_id, effect['amount'])
		StrikeEffects.PowerArmorUpIfSealedOrTransformedCopyOfAttack:
			performing_player.strike_stat_boosts.power_armor_up_if_sealed_or_transformed_copy_of_attack = true
			var attack_card = active_strike.get_player_card(performing_player)
			if performing_player.has_card_name_in_zone(attack_card, "sealed") or performing_player.has_card_name_in_zone(attack_card, "transform"):
				create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, 1)
				create_event(Enums.EventType.EventType_Strike_ArmorUp, performing_player.my_id, 1)
		StrikeEffects.Pull:
			var previous_location = opposing_player.arena_location
			var amount = effect['amount']
			amount += performing_player.strike_stat_boosts.increase_move_opponent_effects_by

			performing_player.pull(amount)

			var new_location = opposing_player.arena_location
			var pull_amount = opposing_player.movement_distance_between(other_start, new_location)
			local_conditions.fully_pulled = pull_amount == effect['amount']
			if (other_start < performing_start and new_location > performing_start) or (other_start > performing_start and new_location < performing_start):
				local_conditions.pulled_past = true

			_append_log_full(Enums.LogType.LogType_CharacterMovement, opposing_player, "被拉近%s，从格子%s移动到%s。" % [str(amount), str(previous_location), str(new_location)])
		StrikeEffects.PullAnyNumberOfSpacesAndGainPower:
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect
			decision_info.player = performing_player.my_id
			decision_info.choice_card_id = card_id
			decision_info.effect_type = StrikeEffects.PullToSpaceAndGainPower
			decision_info.choice = []
			decision_info.extra_info = ""
			decision_info.limitation = []

			decision_info.limitation.append(0)
			decision_info.choice.append({ "effect_type": StrikeEffects.Pass })

			var player_location = performing_player.arena_location
			var opponent_location = opposing_player.arena_location
			var nowhere_to_pull = true
			for i in range(Enums.MinArenaLocation, Enums.MaxArenaLocation+1):
				if opposing_player.is_overlapping_opponent(i):
					continue
				if opponent_location == i:
					continue
				if player_location < opponent_location and i > opponent_location:
					continue
				if player_location > opponent_location and i < opponent_location:
					continue
				decision_info.limitation.append(i)
				decision_info.choice.append({
					"effect_type": StrikeEffects.PullToSpaceAndGainPower,
					"amount": i
				})
				nowhere_to_pull = false

			if not nowhere_to_pull:
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				create_event(Enums.EventType.EventType_ChooseArenaLocationForEffect, performing_player.my_id, 0)
		StrikeEffects.PullToRange:
			var target_range = effect['amount']
			var target_closest_location
			var previous_location = opposing_player.arena_location
			var previous_closest_location = opposing_player.get_closest_occupied_space_to(performing_player.arena_location)
			var origin = performing_player.get_closest_occupied_space_to(previous_location)
			var starting_range = abs(previous_closest_location - origin)
			if performing_player.is_left_of_location(previous_closest_location):
				if starting_range >= target_range:
					# Past target range; opponent should end on the right
					target_closest_location = min(origin + target_range, Enums.MaxArenaLocation)
				else:
					# Closer than target range; opponent should end on left
					target_closest_location = max(origin - target_range, Enums.MinArenaLocation)
			else:
				# If player is to the right
				if starting_range >= target_range:
					# Past target range; opponent should end on the left
					target_closest_location = max(origin - target_range, Enums.MinArenaLocation)
				else:
					# Closer than target range; opponent should end on right
					target_closest_location = min(origin + target_range, Enums.MaxArenaLocation)

			var pull_needed = opposing_player.movement_distance_between(previous_closest_location, target_closest_location, true)
			performing_player.pull(pull_needed)
			var new_location = opposing_player.arena_location
			_append_log_full(Enums.LogType.LogType_CharacterMovement, opposing_player, "被拉近至距离%s，从格子%s移动到%s。" % [str(target_range), str(previous_location), str(new_location)])
		StrikeEffects.PullToSpaceAndGainPower:
			var space = effect['amount']
			var previous_location = opposing_player.arena_location
			var distance = opposing_player.movement_distance_between(space, previous_location)
			if space == previous_location:
				# This effect should only be called with an actual attempt to pull.
				assert(false)
			elif space < previous_location and performing_player.arena_location < previous_location \
			or space > previous_location and performing_player.arena_location > previous_location:
				performing_player.pull(distance)
				var new_location = opposing_player.arena_location
				var pull_amount = opposing_player.movement_distance_between(previous_location, new_location)
				local_conditions.fully_pulled = pull_amount == effect['amount']
				if (other_start < performing_start and new_location > performing_start) or (other_start > performing_start and new_location < performing_start):
					local_conditions.pulled_past = true
				performing_player.add_power_bonus(pull_amount)
				create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, pull_amount)
				_append_log_full(Enums.LogType.LogType_CharacterMovement, opposing_player, "被拉近%s，从格子%s移动到%s。" % [str(distance), str(previous_location), str(new_location)])
			else:
				# This effect should not be called with a push.
				assert(false)
		StrikeEffects.PullNotPast:
			var previous_location = opposing_player.arena_location
			performing_player.pull_not_past(effect['amount'])
			var new_location = opposing_player.arena_location
			_append_log_full(Enums.LogType.LogType_CharacterMovement, opposing_player, "被拉近%s且不会越过%s，从格子%s移动到%s。" % [str(effect['amount']), performing_player.name, str(previous_location), str(new_location)])
		StrikeEffects.PullFromSource:
			var attack_source_location = get_attack_origin(performing_player, opposing_player.arena_location)
			var skip_on_source = effect.get("skip_if_on_source", false)
			if opposing_player.is_in_location(attack_source_location):
				if not skip_on_source:
					# Make choice to push or pull.
					var choice_effect = {
						"effect_type": StrikeEffects.Choice,
						StrikeEffects.Choice: [
							{ "effect_type": StrikeEffects.Push, "amount": effect['amount'] },
							{ "effect_type": StrikeEffects.Pull, "amount": effect['amount'] }
						]
					}
					for choice in choice_effect[StrikeEffects.Choice]:
						if 'and' in choice:
							choice['and'] = effect['and']
					handle_strike_effect(card_id, choice_effect, performing_player)
				# else: do nothing
			else:
				var previous_location = opposing_player.arena_location
				# Convert this to a regular push or pull.
				if attack_source_location < previous_location:
					# Source to the left of opponent. Move to the left.
					if performing_player.arena_location < previous_location:
						# Player to the left of opponent. Pull opponent left.
						performing_player.pull(effect['amount'])
					else:
						# Player to the right of opponent. Push opponent left.
						performing_player.push(effect['amount'])
					pass
				else:
					# Source to the right of opponent. Move to the right.
					if performing_player.arena_location < previous_location:
						# Player to the left of opponent. Push opponent right.
						performing_player.push(effect['amount'])
					else:
						# Player to the right of opponent. Pull opponent right.
						performing_player.pull(effect['amount'])
				var new_location = opposing_player.arena_location
				_append_log_full(Enums.LogType.LogType_CharacterMovement, opposing_player, "从位于%s的攻击来源处被拉近%s，从格子%s移动到%s。" % [str(effect['amount']), str(attack_source_location), str(previous_location), str(new_location)])
		StrikeEffects.PullToBuddy:
			var amount = effect['amount']
			var buddy_id = ""
			if 'buddy_id' in effect:
				buddy_id = effect['buddy_id']
			var buddy_location = performing_player.get_buddy_location(buddy_id)
			var previous_location = opposing_player.arena_location
			if buddy_location == previous_location:
				# Choice since opponent is on buddy.
				var choice_effect = {
					"effect_type": StrikeEffects.Choice,
					StrikeEffects.Choice: [
						{ "effect_type": StrikeEffects.Push, "amount": amount },
						{ "effect_type": StrikeEffects.Pull, "amount": amount }
					]
				}
				for choice in choice_effect[StrikeEffects.Choice]:
					if 'and' in choice:
						choice['and'] = effect['and']
				handle_strike_effect(card_id, choice_effect, performing_player)
			else:
				# Convert this to a regular push or pull.
				if buddy_location < previous_location:
					# Buddy to the left of opponent. Move to the left.
					if performing_player.arena_location < previous_location:
						# Player to the left of opponent. Pull to move left,
						# otherwise push.
						performing_player.pull(amount)
					else:
						performing_player.push(amount)
				else:
					# Buddy to the right of opponent. Move to the right.
					if performing_player.arena_location < previous_location:
						# Player to the left of opponent. Push to move opponent right,
						# otherwise, pull.
						performing_player.push(amount)
					else:
						performing_player.pull(amount)
				var new_location = opposing_player.arena_location
				var buddy_name = performing_player.get_buddy_name(buddy_id)
				_append_log_full(Enums.LogType.LogType_CharacterMovement, opposing_player, "被朝向%s拉近%s，从格子%s移动到%s。" % [str(effect['amount']), buddy_name, str(previous_location), str(new_location)])
		StrikeEffects.Push:
			var set_x_to_buddy_spaces_entered = 'save_buddy_spaces_entered_as_strike_x' in effect and effect['save_buddy_spaces_entered_as_strike_x']
			var previous_location = opposing_player.arena_location
			var amount = effect['amount']
			if str(amount) == "OPPONENT_SPEED":
				amount = get_total_speed(opposing_player)
			amount += performing_player.strike_stat_boosts.increase_move_opponent_effects_by

			performing_player.push(amount, set_x_to_buddy_spaces_entered)
			var new_location = opposing_player.arena_location
			var push_amount = abs(other_start - new_location)
			local_conditions.push_amount = push_amount
			local_conditions.fully_pushed = push_amount == amount
			if 'save_unpushed_spaces_as_strike_x' in effect and effect['save_unpushed_spaces_as_strike_x']:
				var unpushed_spaces = amount - push_amount
				_append_log_full(Enums.LogType.LogType_Strike, performing_player, "此次战斗的X被设为未击退的格数，%s。" % unpushed_spaces)
				performing_player.set_strike_x(unpushed_spaces)
			_append_log_full(Enums.LogType.LogType_CharacterMovement, opposing_player, "被击退%s，从格子%s移动到%s。" % [str(amount), str(previous_location), str(new_location)])
		StrikeEffects.PushSelf:
			var previous_location = performing_player.arena_location
			var amount = effect['amount']
			amount += opposing_player.strike_stat_boosts.increase_move_opponent_effects_by

			opposing_player.push(amount)
			var new_location = performing_player.arena_location
			var push_amount = performing_player.movement_distance_between(performing_start, new_location)
			local_conditions.push_amount = push_amount
			local_conditions.fully_pushed = push_amount == amount
			_append_log_full(Enums.LogType.LogType_CharacterMovement, performing_player, "被击退%s，从格子%s移动到%s。" % [str(amount), str(previous_location), str(new_location)])
		StrikeEffects.PushFromSource:
			var attack_source_location = get_attack_origin(performing_player, opposing_player.arena_location)
			if opposing_player.is_in_location(attack_source_location):
				# Make choice to push or pull.
				var choice_effect = {
					"effect_type": StrikeEffects.Choice,
					StrikeEffects.Choice: [
						{ "effect_type": StrikeEffects.Push, "amount": effect['amount'] },
						{ "effect_type": StrikeEffects.Pull, "amount": effect['amount'] }
					]
				}
				for choice in choice_effect[StrikeEffects.Choice]:
					if 'and' in choice:
						choice['and'] = effect['and']
				handle_strike_effect(card_id, choice_effect, performing_player)
			else:
				var previous_location = opposing_player.arena_location
				# Convert this to a regular push or pull.
				if attack_source_location < previous_location:
					# Source to the left of opponent. Move to the right.
					if performing_player.arena_location < previous_location:
						# Player to the left of opponent. Push to move opponent right.
						performing_player.push(effect['amount'])
					else:
						# Player to the right of opponent. Pull to move opponent right.
						performing_player.pull(effect['amount'])
					pass
				else:
					# Source to the right of opponent. Move to the left.
					if performing_player.arena_location < previous_location:
						# Player to the left of opponent. Pull to move opponent left.
						performing_player.pull(effect['amount'])
					else:
						# Player to the right of opponent. Push to move opponent left.
						performing_player.push(effect['amount'])
				var new_location = opposing_player.arena_location
				var push_amount = opposing_player.movement_distance_between(other_start, new_location)
				local_conditions.push_amount = push_amount
				local_conditions.fully_pushed = push_amount == effect['amount']
				_append_log_full(Enums.LogType.LogType_CharacterMovement, opposing_player, "从位于%s的攻击来源处被击退%s，从格子%s移动到%s。" % [str(effect['amount']), str(attack_source_location), str(previous_location), str(new_location)])
		StrikeEffects.PushOrPullToAnySpace:
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect
			decision_info.player = performing_player.my_id
			decision_info.choice_card_id = card_id
			decision_info.effect_type = StrikeEffects.PushOrPullToSpace
			decision_info.choice = []
			decision_info.extra_info = ""
			decision_info.limitation = []

			decision_info.limitation.append(0)
			decision_info.choice.append({ "effect_type": StrikeEffects.Pass })

			var opponent_location = opposing_player.arena_location
			for i in range(Enums.MinArenaLocation, Enums.MaxArenaLocation+1):
				if opposing_player.is_overlapping_opponent(i):
					continue
				if opponent_location == i:
					continue
				decision_info.limitation.append(i)
				decision_info.choice.append({
					"effect_type": StrikeEffects.PushOrPullToSpace,
					"amount": i
				})

			change_game_state(Enums.GameState.GameState_PlayerDecision)
			create_event(Enums.EventType.EventType_ChooseArenaLocationForEffect, performing_player.my_id, 0)
		StrikeEffects.PushOrPullToSpace:
			var space = effect['amount']
			var previous_location = opposing_player.arena_location
			var distance = opposing_player.movement_distance_between(space, previous_location)
			# Convert this to a regular push or pull.
			if space == previous_location:
				# This effect should only be called with an actual attempt to push or pull.
				assert(false)
			elif space < previous_location and performing_player.arena_location < previous_location \
			or space > previous_location and performing_player.arena_location > previous_location:
				performing_player.pull(distance)
				var new_location = opposing_player.arena_location
				var pull_amount = opposing_player.movement_distance_between(other_start, new_location)
				local_conditions.fully_pulled = pull_amount == effect['amount']
				if (other_start < performing_start and new_location > performing_start) or (other_start > performing_start and new_location < performing_start):
					local_conditions.pulled_past = true
				_append_log_full(Enums.LogType.LogType_CharacterMovement, opposing_player, "被拉近%s，从格子%s移动到%s。" % [str(distance), str(previous_location), str(new_location)])
			else:
				performing_player.push(distance)
				var new_location = opposing_player.arena_location
				var push_amount = opposing_player.movement_distance_between(previous_location, new_location)
				local_conditions.push_amount = push_amount
				local_conditions.fully_pushed = push_amount == effect['amount']
				_append_log_full(Enums.LogType.LogType_CharacterMovement, opposing_player, "被击退%s，从格子%s移动到%s。" % [str(distance), str(previous_location), str(new_location)])
		StrikeEffects.PushToAttackMaxRange:
			var attack_max_range = get_total_max_range(performing_player)
			var furthest_location
			var previous_location = opposing_player.arena_location
			var origin = performing_player.get_closest_occupied_space_to(previous_location)
			if performing_player.arena_location < opposing_player.arena_location:
				furthest_location = max(origin + attack_max_range, Enums.MinArenaLocation)
			else:
				furthest_location = min(origin - attack_max_range, Enums.MaxArenaLocation)
			var push_needed = abs(furthest_location - opposing_player.get_closest_occupied_space_to(performing_player.arena_location))
			performing_player.push(push_needed)
			var new_location = opposing_player.arena_location
			_append_log_full(Enums.LogType.LogType_CharacterMovement, opposing_player, "被击退至该攻击的最大距离%s，从格子%s移动到%s。" % [str(attack_max_range), str(previous_location), str(new_location)])
		StrikeEffects.PushToRange:
			var target_range = effect['amount']
			var furthest_location
			var previous_location = opposing_player.arena_location
			var origin = performing_player.get_closest_occupied_space_to(previous_location)
			if performing_player.arena_location < opposing_player.arena_location:
				furthest_location = max(origin + target_range, Enums.MinArenaLocation)
			else:
				furthest_location = min(origin - target_range, Enums.MaxArenaLocation)
			var push_needed = abs(furthest_location - opposing_player.get_closest_occupied_space_to(performing_player.arena_location))
			performing_player.push(push_needed)
			var new_location = opposing_player.arena_location
			_append_log_full(Enums.LogType.LogType_CharacterMovement, opposing_player, "被击退至距离%s，从格子%s移动到%s。" % [str(target_range), str(previous_location), str(new_location)])
		StrikeEffects.PushDamageDealt:
			var damage_dealt = active_strike.get_damage_taken(opposing_player)
			if damage_dealt > 0:
				handle_strike_effect(card_id, {"effect_type": StrikeEffects.Push, "amount": damage_dealt}, performing_player)
		StrikeEffects.RangeIncludesBoostSpace:
			performing_player.strike_stat_boosts.range_includes_boost_spaces.append(effect['card_id'])
		StrikeEffects.RangeIncludesIfMovedPast:
			performing_player.strike_stat_boosts.range_includes_if_moved_past = true
		StrikeEffects.RangeIncludesLightningrods:
			performing_player.strike_stat_boosts.range_includes_lightningrods = true
		StrikeEffects.Rangeup:
			if _is_meilian_discard_range_effect(effect, performing_player):
				pass
			else:
				var target_player = performing_player
				if effect.get("opponent"):
					target_player = opposing_player
				var special_only = effect.get("special_only", false)
				var normal_only = effect.get("normal_only", false)
				var rangeup_reason = ""
				if special_only:
					rangeup_reason = "special_only"
				var min_amount = effect['amount']
				if str(min_amount) == "strike_x":
					min_amount = target_player.strike_stat_boosts.strike_x
				var max_amount = effect['amount2']
				if str(max_amount) == "strike_x":
					max_amount = target_player.strike_stat_boosts.strike_x

				target_player.add_range_bonus(min_amount, max_amount, special_only, normal_only, effect.get("character_effect", false))
				create_event(Enums.EventType.EventType_Strike_RangeUp, target_player.my_id, min_amount, rangeup_reason, max_amount)
		StrikeEffects.RangeupBothPlayers:
			performing_player.add_range_bonus(effect['amount'], effect['amount2'], false)
			create_event(Enums.EventType.EventType_Strike_RangeUp, performing_player.my_id, effect['amount'], "", effect['amount2'])
			opposing_player.add_range_bonus(effect['amount'], effect['amount2'], false)
			create_event(Enums.EventType.EventType_Strike_RangeUp, opposing_player.my_id, effect['amount'], "", effect['amount2'])
		StrikeEffects.RangeupIfExModifier:
			performing_player.strike_stat_boosts.rangeup_min_if_ex_modifier = effect['amount']
			performing_player.strike_stat_boosts.rangeup_max_if_ex_modifier = effect['amount2']
			if active_strike.will_be_ex(performing_player):
				create_event(Enums.EventType.EventType_Strike_RangeUp, performing_player.my_id, effect['amount'], "", effect['amount2'])
		StrikeEffects.RangeupPerBoostInPlay:
			var boosts_in_play = performing_player.get_boosts().size()
			if 'all_boosts' in effect and effect['all_boosts']:
				boosts_in_play += opposing_player.get_boosts().size()
			if boosts_in_play > 0:
				var min_bonus = effect['amount'] * boosts_in_play
				var max_bonus = effect['amount2'] * boosts_in_play
				performing_player.add_range_bonus(min_bonus, max_bonus, false)
				create_event(Enums.EventType.EventType_Strike_RangeUp, performing_player.my_id, min_bonus, "", max_bonus)
		StrikeEffects.RangeupPerBoostModifier:
			performing_player.strike_stat_boosts.rangeup_min_per_boost_modifier = effect['amount']
			performing_player.strike_stat_boosts.rangeup_max_per_boost_modifier = effect['amount2']
			performing_player.strike_stat_boosts.rangeup_per_boost_modifier_all_boosts = false
			var boosts_in_play = performing_player.get_boosts().size()
			if 'all_boosts' in effect and effect['all_boosts']:
				performing_player.strike_stat_boosts.rangeup_per_boost_modifier_all_boosts = true
				boosts_in_play += opposing_player.get_boosts().size()
			if boosts_in_play > 0:
				create_event(Enums.EventType.EventType_Strike_RangeUp, performing_player.my_id, effect['amount'] * boosts_in_play, "", effect['amount2'] * boosts_in_play)
		StrikeEffects.RangeupPerCardInHand:
			var hand_size = performing_player.hand.size()
			if hand_size > 0:
				var min_bonus = effect['amount'] * hand_size
				var max_bonus = effect['amount2'] * hand_size
				performing_player.add_range_bonus(min_bonus, max_bonus, false)
				create_event(Enums.EventType.EventType_Strike_RangeUp, performing_player.my_id, min_bonus, "", max_bonus)
		StrikeEffects.RangeupPerForceSpentThisTurn:
			var min_bonus = performing_player.total_force_spent_this_turn * effect['amount']
			var max_bonus = performing_player.total_force_spent_this_turn * effect['amount2']
			performing_player.add_range_bonus(min_bonus, max_bonus, false)
			create_event(Enums.EventType.EventType_Strike_RangeUp, performing_player.my_id, min_bonus, "", max_bonus)
		StrikeEffects.RangeupPerSealedNormal:
			var sealed_normals = performing_player.get_sealed_count_of_type("normal")
			if sealed_normals > 0:
				var min_bonus = effect['amount'] * sealed_normals
				var max_bonus = effect['amount2'] * sealed_normals
				performing_player.add_range_bonus(min_bonus, max_bonus, false)
				create_event(Enums.EventType.EventType_Strike_RangeUp, performing_player.my_id, min_bonus, "", max_bonus)
		StrikeEffects.RangeupDiscardedCardPrintedRange:
			var discarded_card_id = effect["discarded_card_ids"][0]
			var discarded_card = card_db.get_card(discarded_card_id)
			var printed_range_min = max(get_card_stat(performing_player, discarded_card, 'range_min'), 0)
			var printed_range_max = max(get_card_stat(performing_player, discarded_card, 'range_max'), 0)
			performing_player.add_range_bonus(printed_range_min, printed_range_max)
			create_event(Enums.EventType.EventType_Strike_RangeUp, performing_player.my_id, printed_range_min, "", printed_range_max)
			var card_name = card_db.get_card_name(discarded_card_id)
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "获得%s的印刷射程：%s~%s！" % [_log_card_name(card_name), printed_range_min, printed_range_max])
		StrikeEffects.ReadingNormal:
			# Cannot do Reading during a strike.
			if not active_strike:
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_ReadingNormal
				decision_info.effect_type = StrikeEffects.ReadingNormalInternal
				decision_info.choice_card_id = card_id
				decision_info.player = performing_player.my_id
				create_event(Enums.EventType.EventType_ReadingNormal, performing_player.my_id, 0)
		StrikeEffects.ReadingNormalInternal:
			var named_card = card_db.get_card(effect['card_id'])
			# named_card is the individual card but
			# this should discard "by name", so instead of using that
			# match card.definition['id']'s instead.
			opposing_player.next_strike_with_or_reveal(named_card.definition['id'])
		StrikeEffects.RemoveBuddy:
			if 'increase_strike_x' in effect:
				performing_player.strike_stat_boosts.strike_x += effect['increase_strike_x']
			var buddy_id = ""
			if 'buddy_id' in effect:
				buddy_id = effect['buddy_id']
			var buddy_was_in_play = performing_player.is_buddy_in_play(buddy_id)
			var buddy_name = performing_player.get_buddy_name(buddy_id)
			var silent = 'silent' in effect and effect['silent']
			if not silent:
				_append_log_full(Enums.LogType.LogType_CharacterMovement, performing_player, "将%s移出场上。" % buddy_name)
			performing_player.remove_buddy(buddy_id, silent)
			if buddy_was_in_play and active_strike:
				# Handle character effects like Litchi where removing buddy mid-strike
				# Can have an effect on the stats.
				var char_effects = performing_player.get_character_effects_at_timing("during_strike")
				for char_effect in char_effects:
					if char_effect['condition'] == "not_buddy_in_play":
						do_effect_if_condition_met(performing_player, -1, char_effect, null)
					elif char_effect['condition'] == "buddy_in_play":
						# Not implemented - if someone has an effect that needs to go away, do that here.
						assert(false)
		StrikeEffects.DoNotRemoveBuddy:
			performing_player.do_not_cleanup_buddy_this_turn = true
		StrikeEffects.CalculateRangeFromBuddy:
			performing_player.strike_stat_boosts.calculate_range_from_buddy = true
			performing_player.strike_stat_boosts.calculate_range_from_buddy_id = ""
			if 'buddy_id' in effect:
				performing_player.strike_stat_boosts.calculate_range_from_buddy_id = effect['buddy_id']
		StrikeEffects.CalculateRangeFromBuddyCurrentLocation:
			var buddy_id = ""
			if 'buddy_id' in effect:
				buddy_id = effect['buddy_id']
			performing_player.strike_stat_boosts.calculate_range_from_space = performing_player.get_buddy_location(buddy_id)
		StrikeEffects.CalculateRangeFromCenter:
			performing_player.strike_stat_boosts.calculate_range_from_space = Enums.CenterArenaLocation
		StrikeEffects.CalculateRangeFromSetFromBoostSpace:
			if performing_player == active_strike.initiator:
				performing_player.strike_stat_boosts.calculate_range_from_space = active_strike.initiator_set_from_boost_space
			else:
				performing_player.strike_stat_boosts.calculate_range_from_space = active_strike.defender_set_from_boost_space
		StrikeEffects.ReduceDiscardAmount:
			var amount = effect['amount']
			performing_player.strike_stat_boosts.reduce_discard_effects_by += amount
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "的弃牌数量减少%s！" % amount)
		StrikeEffects.ReshuffleDiscardIntoDeck:
			performing_player.reshuffle_discard(false, true)
		StrikeEffects.Retreat:
			decision_info.clear()
			decision_info.source = StrikeEffects.Retreat
			decision_info.amount = effect['amount']
			decision_info.limitation = { 'and': null }
			if 'and' in effect:
				decision_info.limitation['and'] = effect['and']
				# and effect is handled by internal version
				and_handled_elsewhere = true

			var effects = performing_player.get_character_effects_at_timing("on_retreat")
			for sub_effect in effects:
				do_effect_if_condition_met(performing_player, -1, sub_effect, null)
			if game_state != Enums.GameState.GameState_PlayerDecision:
				var retreat_effect = effect.duplicate()
				retreat_effect['effect_type'] = StrikeEffects.RetreatInternal
				handle_strike_effect(card_id, retreat_effect, performing_player)
		StrikeEffects.RetreatInternal:
			var amount = effect['amount']
			if str(amount) == "strike_x":
				amount = performing_player.strike_stat_boosts.strike_x
			amount += performing_player.strike_stat_boosts.increase_movement_effects_by
			amount = _dongshilang_limit_requested_movement(performing_player, amount)

			var previous_location = performing_player.arena_location
			performing_player.retreat(amount)
			var new_location = performing_player.arena_location
			var retreat_amount = abs(performing_start - new_location)
			local_conditions.fully_retreated = retreat_amount == amount
			local_conditions.movement_amount = retreat_amount
			_dongshilang_consume_movement_limit(performing_player, retreat_amount)
			# Ulrik: increment move counters from continuous boosts
			for boost in performing_player.continuous_boosts:
				for boost_effect in boost.definition['boost']['effects']:
					if boost_effect.get('effect_type') == StrikeEffects.IncrementBonusMovePowerCounters:
						boost.set_meta('bonus_move_power_counters', boost.get_meta('bonus_move_power_counters', 0) + retreat_amount * boost_effect.get('amount', 1))
					if boost_effect.get('effect_type') == StrikeEffects.IncrementBonusMoveArmorCounters:
						boost.set_meta('bonus_move_armor_counters', boost.get_meta('bonus_move_armor_counters', 0) + retreat_amount * boost_effect.get('amount', 1))
			_append_log_full(Enums.LogType.LogType_CharacterMovement, performing_player, "后退%s，从格子%s移动到%s。" % [str(amount), str(previous_location), str(new_location)])
		StrikeEffects.RepeatEffectOptionally:
			if active_strike:
				var amount = effect['amount']
				if str(amount) == "GAUGE_COUNT":
					amount = performing_player.gauge.size()
				var not_optional = 'not_optional' in effect and effect['not_optional']
				var first_not_automatic = 'first_not_automatic' in effect and effect['first_not_automatic']
				if str(amount) == "every_two_sealed_normals":
					var sealed_normals = performing_player.get_sealed_count_of_type("normal")
					@warning_ignore("integer_division")
					amount = int(sealed_normals / 2)
				elif str(amount) == "strike_x":
					amount = performing_player.strike_stat_boosts.strike_x

				var linked_effect = effect['linked_effect']
				if amount > 0:
					var repeat_effect = {
							"card_id": card_id,
							"effect_type": StrikeEffects.RepeatEffectOptionally,
							"amount": amount-1,
							"not_optional": not_optional,
							"linked_effect": linked_effect
						}
					if not not_optional:
						repeat_effect = {
							"card_id": card_id,
							"effect_type": StrikeEffects.Choice,
							StrikeEffects.Choice: [
								repeat_effect,
								{ "effect_type": StrikeEffects.Pass }
							]
						}
					add_remaining_effect(repeat_effect)
				if not first_not_automatic:
					handle_strike_effect(card_id, linked_effect, performing_player)
		StrikeEffects.RepeatPrintedTriggersOnExAttack:
			performing_player.strike_stat_boosts.repeat_printed_triggers_on_ex_attack = effect.get("amount")
		StrikeEffects.ResetCharacterPositions:
			performing_player.move_to(performing_player.starting_location, true)
			opposing_player.move_to(opposing_player.starting_location, true)
			_append_log_full(Enums.LogType.LogType_CharacterMovement, null, "双方玩家都回到起始位置！")
		StrikeEffects.ReturnAllCardsGaugeToHand:
			var card_names = ""
			for card in performing_player.gauge:
				card_names += card_db.get_card_name(card.id) + ", "
			if card_names:
				card_names = card_names.substr(0, card_names.length() - 2)
			performing_player.return_all_cards_gauge_to_hand()
		StrikeEffects.ReturnAttackToHand:
			performing_player.strike_stat_boosts.return_attack_to_hand = true
			if 'not_immediate' not in effect or not effect['not_immediate']:
				handle_strike_attack_immediate_removal(performing_player)
		StrikeEffects.ReturnSealedWithSameSpeed:
			var sealed_card_id = decision_info.amount
			var sealed_card = card_db.get_card(sealed_card_id)
			var target_card = null
			for card in performing_player.sealed:
				if get_card_stat(performing_player, card, 'speed') == get_card_stat(performing_player, sealed_card, 'speed'):
					target_card = card
					break
			if target_card:
				var card_name = target_card.definition["display_name"]
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将速度为%s的封印牌加入手牌：%s。" % [sealed_card.definition['speed'], _log_card_name(card_name)])
				performing_player.move_card_from_sealed_to_hand(target_card.id)
		StrikeEffects.ReturnThisBoostToHandStrikeEffect:
			var card_name = card_db.get_card_name(card_id)
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将加成牌%s返回手牌。" % _log_card_name(card_name))
			var card = card_db.get_card(card_id)
			performing_player.remove_from_continuous_boosts(card, "hand")
		StrikeEffects.ReturnThisToHandImmediateBoost:
			var card_name = card_db.get_card_name(card_id)
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将加成牌%s返回手牌。" % _log_card_name(card_name))
			if active_boost:
				active_boost.cleanup_to_hand_card_ids.append(card_id)
		StrikeEffects.Revert:
			performing_player.revert_exceed()
		StrikeEffects.SavePower:
			var amount = effect['amount']
			performing_player.saved_power = amount
		StrikeEffects.UseSavedPowerAsPrintedPower:
			performing_player.strike_stat_boosts.overwrite_printed_power = true
			performing_player.strike_stat_boosts.overwritten_printed_power = performing_player.saved_power
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "将其攻击的印刷威力设为%s！" % performing_player.saved_power)
		StrikeEffects.UseTopDiscardAsPrintedPower:
			if len(performing_player.discards) > 0:
				var card = performing_player.get_top_discard_card()
				var power = max(get_card_stat(performing_player, card, 'power'), 0)
				performing_player.strike_stat_boosts.overwritten_printed_power = power
				var card_name = card_db.get_card_name(card.id)
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "将其攻击的印刷威力设为弃牌堆顶%s的威力，即%s！" % [_log_card_name(card_name), power])
			else:
				performing_player.strike_stat_boosts.overwritten_printed_power = 0
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "没有弃牌，其攻击的印刷威力被设为0。")
			performing_player.strike_stat_boosts.overwrite_printed_power = true
		StrikeEffects.Say:
			var say_text = effect["text"]
			create_event(Enums.EventType.EventType_Say, performing_player.my_id, 0, "", say_text)
		StrikeEffects.SealAttackOnCleanup:
			performing_player.strike_stat_boosts.seal_attack_on_cleanup = true
		StrikeEffects.SealCardInternal:
			decision_info.amount = effect['seal_card_id']
			var effects = performing_player.get_character_effects_at_timing("on_seal")
			for sub_effect in effects:
				do_effect_if_condition_met(performing_player, -1, sub_effect, null)

			# note that this doesn't support effects causing decisions
			var seal_effect = effect.duplicate()
			seal_effect['effect_type'] = StrikeEffects.SealCardCompleteInternal
			seal_effect['silent'] = false
			seal_effect['and'] = null
			if 'silent' in effect:
				seal_effect['silent'] = effect['silent']
			handle_strike_effect(card_id, seal_effect, performing_player)
		StrikeEffects.SealCardCompleteInternal:
			var card = card_db.get_card(effect['seal_card_id'])
			var silent = effect['silent']
			if effect['source']:
				performing_player.seal_from_location(card.id, effect['source'], silent)
			else:
				performing_player.add_to_sealed(card, silent)
			if performing_player.deck_def.get("id") == "double":
				if card.definition.get("id") == "double_nightmare_legion":
					performing_player.double_true_face_stacks += 1
				elif card.definition.get("id") == "double_tight_following":
					performing_player.double_nightmare_army_stacks += 1
		StrikeEffects.SealContinuousBoosts:
			var player_boosts = performing_player.continuous_boosts.duplicate()
			for boost_card in player_boosts:
				var card_name = card_db.get_card_name(boost_card.id)
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "封印加成牌%s。" % _log_card_name(card_name))
				performing_player.remove_from_continuous_boosts(boost_card, "sealed")
		StrikeEffects.SealInsteadOfDiscarding:
			performing_player.seal_instead_of_discarding = true
		StrikeEffects.SealThis:
			if active_boost:
				# Part of a boost.
				active_boost.seal_on_cleanup = true
			else:
				# Part of an attack.
				performing_player.strike_stat_boosts.seal_attack_on_cleanup = true
		StrikeEffects.SealThisBoost:
			var card = card_db.get_card(card_id)
			var card_name = card_db.get_card_name(card.id)
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "封印加成牌%s。" % _log_card_name(card_name))
			performing_player.remove_from_continuous_boosts(card, "sealed")
			opposing_player.remove_from_continuous_boosts(card, "sealed")
		StrikeEffects.SealTopdeck:
			performing_player.seal_topdeck()
		StrikeEffects.SealDiscard:
			performing_player.seal_discard()
		StrikeEffects.SealHand:
			performing_player.seal_hand()
		StrikeEffects.SelfDiscardChoose:
			var optional = 'optional' in effect and effect['optional']
			var limitation = effect.get("limitation", "")
			var limitation_amount = effect.get("limitation_amount", 0)
			var ask_even_if_no_valid_cards = effect.get("ask_even_if_no_valid_cards", false)
			if str(limitation_amount) == "strike_x":
				limitation_amount = performing_player.strike_stat_boosts.strike_x
			var destination = effect.get("destination", "discard")
			var discard_effect = effect.get("discard_effect", null)
			var allow_fewer = effect.get("allow_fewer", false)
			var source = effect.get("source", "hand")
			var cards_available = []
			if source == "hand":
				cards_available = performing_player.get_cards_in_hand_of_type(limitation, limitation_amount)
			elif source == "hand/gauge":
				cards_available = performing_player.get_cards_in_hand_of_type(limitation)
				cards_available += performing_player.get_cards_in_gauge_of_type(limitation)
			elif source == "boosts":
				cards_available = performing_player.get_cards_in_boosts_of_type(limitation)
			else:
				assert(false, "Discarding from zone %s not implemented." % source)

			var this_effect = effect.duplicate()
			if str(this_effect['amount']) == "force_spent_before_strike":
				# intentionally performing_player, rather than choice_player
				this_effect['amount'] = performing_player.force_spent_before_strike
			elif str(this_effect['amount']) == "strike_x":
				this_effect['amount'] = performing_player.strike_stat_boosts.strike_x
			elif source == "boosts" and this_effect['amount'] == -1:
				this_effect['amount'] = cards_available.size()
				this_effect['allow_fewer'] = true
				allow_fewer = true
			# Even if #cards == effect amount, still do the choosing manually because of all the additional
			# functionality that has been added to this besides discarding.
			if cards_available.size() >= this_effect['amount'] or (optional and (cards_available.size() > 0 or ask_even_if_no_valid_cards)):
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_ChooseToDiscard
				decision_info.effect_type = StrikeEffects.SelfDiscardChooseInternal
				decision_info.effect = this_effect
				decision_info.source_player_id = this_effect.get("_source_player_id", _last_effect_source_player_id)
				decision_info.choice_card_id = card_id
				decision_info.player = performing_player.my_id
				decision_info.source = source
				decision_info.destination = destination
				decision_info.limitation = limitation
				decision_info.bonus_effect = discard_effect
				decision_info.can_pass = optional
				if source == "boosts":
					decision_info.amount = this_effect['amount']
					decision_info.amount_min = 0 if allow_fewer else this_effect['amount']

				if limitation == "last_drawn_cards":
					decision_info.limitation = "from_array"
					decision_info.extra_info = "card_names"
					decision_info.choice = cards_available.map(func(item): return item.id)

				create_event(Enums.EventType.EventType_Strike_ChooseToDiscard, performing_player.my_id, this_effect['amount'], "", allow_fewer)
			else:
				if not optional and cards_available.size() > 0:
					if source != "hand":
						assert(false, "Mandatory discards from non-hand zones not implemented.")
					create_event(Enums.EventType.EventType_Strike_ChooseToDiscard_Info, performing_player.my_id, this_effect['amount'])
					# Forced to discard whole hand.
					var card_ids = performing_player.get_card_ids_in_hand()
					if destination == "discard":
						performing_player.discard_hand()
					elif destination == "sealed":
						performing_player.seal_hand()
					elif destination == "reveal":
						performing_player.reveal_hand()

					if discard_effect:
						discard_effect = discard_effect.duplicate()
						discard_effect['discarded_card_ids'] = card_ids
						do_effect_if_condition_met(performing_player, card_id, discard_effect, local_conditions)
				elif cards_available.size() == 0:
					if source == "hand" and destination == "reveal":
						_append_log_full(Enums.LogType.LogType_Effect, performing_player, "手牌中没有可展示的牌。")
						if 'and' in this_effect and this_effect['and']['effect_type'] == StrikeEffects.SavePower:
							performing_player.saved_power = 0
		StrikeEffects.SetDanDrawChoice:
			performing_player.dan_draw_choice = true
		StrikeEffects.SetDanDrawChoiceInternal:
			performing_player.dan_draw_choice_from_bottom = effect['from_bottom']
		StrikeEffects.SetEnchantressDrawChoice:
			performing_player.enchantress_draw_choice = true
		StrikeEffects.SetEndOfTurnBoostDelay:
			performing_player.set_end_of_turn_boost_delay(card_id)
		StrikeEffects.SetFaceAttack:
			performing_player.face_attack_id = effect['card_id']
		StrikeEffects.SetMaxHandSize:
			performing_player.max_hand_size = effect['amount']
			var new_size_string = "3 spaces wide"
			if 'description' in effect:
				new_size_string = effect['description']
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "的最大手牌数现在为%s！" % new_size_string)
		StrikeEffects.SetStrikeX:
			var extra_info = []
			if 'extra_info' in effect:
				extra_info = effect['extra_info']
			var source = effect.get('source', effect.get('special_amount', ''))
			do_set_strike_x(performing_player, source, extra_info)
		StrikeEffects.SetTotalPower:
			performing_player.strike_stat_boosts.overwrite_total_power = true
			performing_player.strike_stat_boosts.overwritten_total_power = effect['amount']
		StrikeEffects.SetUsedCharacterBonus:
			performing_player.used_character_bonus = true
		StrikeEffects.SelfDiscardChooseInternal:
			var card_ids = effect['card_ids']
			var card_names = card_db.get_card_names(card_ids)
			var discard_source = effect.get('discard_source', "hand")
			if discard_source == "hand" and effect['destination'] == "discard":
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "弃置所选牌：%s。" % _log_card_name(card_names))
				# Save/restore source for passive triggers (e.g. Eugenia Wonderland)
				var _saved_source = _last_effect_source_player_id
				if '_source_player_id' in effect:
					_last_effect_source_player_id = effect['_source_player_id']
				performing_player.discard(card_ids)
				_last_effect_source_player_id = _saved_source
			elif discard_source == "hand" and effect['destination'] == "sealed":
				if performing_player.sealed_area_is_secret:
					_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将%s张牌背面封印。" % str(len(card_ids)))
				else:
					_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "封印所选牌：%s。" % _log_card_name(card_names))
				for seal_card_id in card_ids:
					do_seal_effect(performing_player, seal_card_id, "hand")
			elif discard_source == "hand" and effect['destination'] == "reveal":
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "展示所选牌：%s。" % _log_card_name(card_names))
				performing_player.reveal_card_ids(card_ids)
				for revealed_card_id in card_ids:
					create_event(Enums.EventType.EventType_RevealCard, performing_player.my_id, revealed_card_id)
				if 'and' in effect and effect['and']['effect_type'] == StrikeEffects.SavePower:
					# Specifically get the printed power.
					var card_power = card_db.get_card(card_ids[0]).definition['power']
					effect['and']['amount'] = card_power
			elif discard_source == "hand" and effect['destination'] == "opponent_overdrive":
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将所选牌弃置到对手的超载：%s。" % _log_card_name(card_names))
				performing_player.discard(card_ids)
				opposing_player.move_cards_to_overdrive(card_ids, "opponent_discard")
			elif discard_source == "hand" and effect['destination'] == "play_attack":
				# Can do 0 to pass.
				if card_ids.size() == 1:
					begin_extra_attack(performing_player, card_ids[0])
			elif discard_source in ["hand", "hand/gauge"] and effect['destination'] == "replacement_boost":
				var replacement_boost = performing_player.get_replacement_boost_definition()
				performing_player.play_replacement_boosts(card_ids, replacement_boost)
			elif discard_source == "boosts":
				var boost_destination = effect['destination']
				assert(boost_destination in ["discard", "hand"], "Unsupported destination for discard from boosts")
				for boost_card_id in card_ids:
					var boost_card = card_db.get_card(boost_card_id)
					if performing_player.is_card_in_continuous_boosts(boost_card_id):
						performing_player.remove_from_continuous_boosts(boost_card, boost_destination)
					elif opposing_player.is_card_in_continuous_boosts(boost_card_id):
						opposing_player.remove_from_continuous_boosts(boost_card, boost_destination)
			else:
				# Nothing else implemented.
				assert(false)
		StrikeEffects.SetLifePerGauge:
			var gauge = len(performing_player.gauge)
			var amount_per_gauge = effect['amount']
			var maximum = performing_player.get_life_cap()
			if 'maximum' in effect:
				maximum = min(int(effect['maximum']), performing_player.get_life_cap())
			var amount = gauge * amount_per_gauge
			amount = min(maximum, amount)
			performing_player.life = amount
			create_event(Enums.EventType.EventType_Strike_GainLife, performing_player.my_id, amount, "", performing_player.life)
			_append_log_full(Enums.LogType.LogType_Health, performing_player, "其生命被设为%s！" % [str(performing_player.life)])
			_recalc_life_conditional_boosts(performing_player)
		StrikeEffects.ShuffleDeck:
			performing_player.random_shuffle_deck()
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "洗切了其牌库。")
			create_event(Enums.EventType.EventType_ReshuffleDeck, performing_player.my_id, 0)
		StrikeEffects.ShuffleDiscardInPlace:
			performing_player.random_shuffle_discard_in_place()
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "洗切了其弃牌堆。")
			create_event(Enums.EventType.EventType_ReshuffleDiscardInPlace, performing_player.my_id, 0)
		StrikeEffects.ShuffleIntoDeckFromHand:
			if len(performing_player.hand) > 0:
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_CardFromHandToGauge
				decision_info.player = performing_player.my_id
				decision_info.choice_card_id = card_id
				decision_info.destination = "deck"
				decision_info.valid_zones = ["hand"]
				var min_amount = effect['min_amount']
				var max_amount = effect['max_amount']
				decision_info.effect = {
					"min_amount": min_amount,
					"max_amount": max_amount,
				}
				create_event(Enums.EventType.EventType_CardFromHandToGauge_Choice, performing_player.my_id, min_amount, "", max_amount)
		StrikeEffects.ShuffleHandToDeck:
			performing_player.shuffle_hand_to_deck()
		StrikeEffects.ShuffleSealedToDeck:
			var card_names = ""
			for card in performing_player.sealed:
				card_names += card_db.get_card_name(card.id) + ", "
			if card_names:
				card_names = card_names.substr(0, card_names.length() - 2)
			performing_player.shuffle_sealed_to_deck()
		StrikeEffects.SidestepTransparentFoe:
			change_game_state(Enums.GameState.GameState_PlayerDecision)
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_Sidestep
			decision_info.effect_type = StrikeEffects.SidestepInternal
			decision_info.choice_card_id = card_id
			decision_info.player = performing_player.my_id
			create_event(Enums.EventType.EventType_Boost_Sidestep, performing_player.my_id, 0)
		StrikeEffects.SidestepDialogue:
			# this exists purely for ui, no-op here
			pass
		StrikeEffects.SidestepInternal:
			var named_card = card_db.get_card(effect['card_id'])
			# named_card is the individual card but
			# this should match "by name", so instead of using that
			# match card.definition['id']'s instead.
			opposing_player.cards_that_will_not_hit.append(named_card.definition['id'])
		StrikeEffects.SkipEndOfTurnDraw:
			performing_player.skip_end_of_turn_draw = true
			# still_check_hand_limit：只跳过抽牌，仍要弃到手上限
			# （minato One More Ride / eugenia Time for Tea 觉醒）
			if effect.get("still_check_hand_limit", false):
				performing_player.eot_skip_draw_still_check_hand_limit = true
		StrikeEffects.ReduceOpponentPrepareDraw:
			performing_player.reduce_opponent_prepare_draw = true
		StrikeEffects.SpecialsInvalid:
			performing_player.specials_invalid = effect['enabled']
		StrikeEffects.SpecificCardDiscardToHand:
			var card_name = effect['card_name']
			var copy_id = effect['copy_id']
			var return_effect = null
			if 'return_effect' in effect:
				return_effect = effect['return_effect']

			var copy_card_id = performing_player.get_copy_in_discards(copy_id)
			if copy_card_id != -1:
				performing_player.move_card_from_discard_to_hand(copy_card_id)
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将一张%s的复制从弃牌堆移到手牌。" % _log_card_name(card_name))
				if return_effect:
					do_effect_if_condition_met(performing_player, card_id, return_effect, null)
			else:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "弃牌堆中没有%s的复制。" % _log_card_name(card_name))
		StrikeEffects.SpecificCardDiscardToGauge:
			var card_name = effect['card_name']
			var copy_id = effect['copy_id']

			var copy_card_id = performing_player.get_copy_in_discards(copy_id)
			if copy_card_id != -1:
				performing_player.move_card_from_discard_to_gauge(copy_card_id)
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将一张%s的复制从弃牌堆移到怒气。" % _log_card_name(card_name))
			else:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "弃牌堆中没有%s的复制。" % _log_card_name(card_name))
		StrikeEffects.SpecificCardSealFromGauge:
			var card_name = effect['card_name']
			var copy_id = effect['copy_id']
			var seal_effect = null
			if 'seal_effect' in effect:
				seal_effect = effect['seal_effect']

			var copy_card_id = performing_player.get_copy_in_gauge(copy_id)
			if copy_card_id != -1:
				performing_player.move_card_from_gauge_to_sealed(copy_card_id)
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "从怒气中封印一张%s的复制。" % _log_card_name(card_name))
				if seal_effect:
					do_effect_if_condition_met(performing_player, card_id, seal_effect, null)
			else:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "怒气中没有%s的复制。" % _log_card_name(card_name))
		StrikeEffects.Speedup:
			var speed_amount = effect['amount']
			var speed_cond = effect.get("condition", "")
			var speed_cond_amount = effect.get("condition_amount", -1)
			if effect.get("timing", "") == "during_strike" \
					and speed_cond in ["max_cards_in_hand", "min_cards_in_hand"]:
				# Hand-gated "always-on" speed bonus: register it and let
				# get_total_speed evaluate it live against the current hand.
				_append_hand_conditional_if_absent(performing_player.strike_stat_boosts.conditional_hand_speedups, speed_amount, speed_cond, speed_cond_amount)
			else:
				performing_player.strike_stat_boosts.speed += speed_amount
				var speed_life_threshold = speed_cond_amount if speed_cond == "life_equal_or_below" else -1
				_register_life_conditional_boost(performing_player, "speedup", speed_amount, speed_life_threshold)
				if speed_life_threshold >= 0:
					_register_life_conditional_chain(performing_player, effect.get("and"), speed_life_threshold)
				create_event(Enums.EventType.EventType_Strike_SpeedUp, performing_player.my_id, speed_amount)
		StrikeEffects.SpeedupAmountInGauge:
			var amount = performing_player.gauge.size()
			performing_player.strike_stat_boosts.speed += amount
			create_event(Enums.EventType.EventType_Strike_SpeedUp, performing_player.my_id, amount)
		StrikeEffects.SpeedupBySpacesModifier:
			performing_player.strike_stat_boosts.speedup_by_spaces_modifier = effect['amount']
			# Count empty spaces so distance - 1.
			var empty_spaces_between = performing_player.distance_to_opponent() - 1
			create_event(Enums.EventType.EventType_Strike_SpeedUp, performing_player.my_id, empty_spaces_between)
		StrikeEffects.SpeedupPerBoostModifier:
			performing_player.strike_stat_boosts.speedup_per_boost_modifier = effect['amount']
			performing_player.strike_stat_boosts.speedup_per_boost_modifier_all_boosts = false
			var boosts_in_play = performing_player.get_boosts().size()
			if 'all_boosts' in effect and effect['all_boosts']:
				performing_player.strike_stat_boosts.speedup_per_boost_modifier_all_boosts = true
				boosts_in_play += opposing_player.get_boosts().size()
			if boosts_in_play > 0:
				create_event(Enums.EventType.EventType_Strike_SpeedUp, performing_player.my_id, effect['amount'] * boosts_in_play)
		StrikeEffects.SpeedupPerBoostInPlay:
			var boosts_in_play = performing_player.get_boosts().size()
			if 'all_boosts' in effect and effect['all_boosts']:
				boosts_in_play += opposing_player.get_boosts().size()
			if boosts_in_play > 0:
				performing_player.strike_stat_boosts.speed += effect['amount'] * boosts_in_play
				create_event(Enums.EventType.EventType_Strike_SpeedUp, performing_player.my_id, effect['amount'] * boosts_in_play)
		StrikeEffects.SpeedupPerForceSpentThisTurn:
			var amount = performing_player.total_force_spent_this_turn * effect['amount']
			performing_player.strike_stat_boosts.speed += amount
			create_event(Enums.EventType.EventType_Strike_SpeedUp, performing_player.my_id, amount)
		StrikeEffects.SpeedupPerUniqueSealedNormals:
			performing_player.strike_stat_boosts.speedup_per_unique_sealed_normals_modifier = effect['amount']
			var unique_sealed_normals = performing_player.get_sealed_count_of_type("normal", true)
			if unique_sealed_normals > 0:
				create_event(Enums.EventType.EventType_Strike_SpeedUp, performing_player.my_id, effect['amount'] * unique_sealed_normals)
		StrikeEffects.SpendAllForceAndSaveAmount:
			var force_amount = performing_player.get_available_force()
			var card_names = ""
			if performing_player.hand.size() > 0:
				card_names = ": " + performing_player.hand[0].definition['display_name']
				for i in range(1, len(performing_player.hand)):
					card_names += ", " + performing_player.hand[i].definition['display_name']
			if performing_player.gauge.size() > 0:
				if card_names == "":
					card_names += ": "
				else:
					card_names += ", "
				card_names += performing_player.gauge[0].definition['display_name']
				for i in range(1, len(performing_player.gauge)):
					card_names += ", " + performing_player.gauge[i].definition['display_name']
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "花费手牌和怒气中的所有牌以生成%s能量%s。" % [force_amount, _log_card_name(card_names)])
			performing_player.discard_hand()
			performing_player.discard_gauge()
			performing_player.force_spent_before_strike = force_amount
		StrikeEffects.SpendAllGaugeAndSaveAmount:
			var gauge_amount = performing_player.get_available_gauge()
			var card_names = ""
			if performing_player.gauge.size() > 0:
				card_names = ": " + performing_player.gauge[0].definition['display_name']
				for i in range(1, len(performing_player.gauge)):
					card_names += ", " + performing_player.gauge[i].definition['display_name']
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "从其怒气中弃置全部%s张牌%s。" % [gauge_amount, _log_card_name(card_names)])
			performing_player.discard_gauge()
			performing_player.gauge_spent_before_strike = gauge_amount
		StrikeEffects.SpendLife:
			var amount = effect['amount']
			performing_player.spend_life(amount)
		StrikeEffects.SetLife:
			var amount = effect['amount']
			var taisei_death_override_life = _consume_taisei_death_exceed_override_life(performing_player, amount)
			if taisei_death_override_life >= 0:
				performing_player.life = min(performing_player.get_life_cap(), taisei_death_override_life)
			else:
				performing_player.life = min(performing_player.get_life_cap(), amount)
			create_event(Enums.EventType.EventType_Strike_GainLife, performing_player.my_id, 0, "", performing_player.life)
			_append_log_full(Enums.LogType.LogType_Health, performing_player, "将生命设为%s！" % [str(performing_player.life)])
			_recalc_life_conditional_boosts(performing_player)
		StrikeEffects.IncrementBonusArmorCounters:
			performing_player.bonus_armor_counters += performing_player.last_spent_life
			if performing_player.bonus_armor_counters > 0:
				create_event(Enums.EventType.EventType_Strike_CharacterEffect, performing_player.my_id, card_id, "", {
					"character_effect": true,
					"effect_type": StrikeEffects.Armorup,
					"amount": performing_player.bonus_armor_counters,
				})
		StrikeEffects.AddBonusArmorCounters:
			performing_player.bonus_armor_counters += effect['amount']
		StrikeEffects.AddBonusGuardCounters:
			performing_player.bonus_guard_counters += effect['amount']
		StrikeEffects.ResetBonusArmorCounters:
			performing_player.bonus_armor_counters = 0
		StrikeEffects.ResetBonusGuardCounters:
			performing_player.bonus_guard_counters = 0
		StrikeEffects.GuardupBonusGuardCounters:
			# Guard from bonus_guard_counters is calculated dynamically in
			# get_total_guard; this effect only creates the event for UI feedback.
			var support_guard_amount = performing_player.bonus_guard_counters
			if support_guard_amount > 0:
				create_event(Enums.EventType.EventType_Strike_GuardUp, performing_player.my_id, support_guard_amount)
		StrikeEffects.OpponentPowerup:
			opposing_player.strike_stat_boosts.power += effect['amount']
			create_event(Enums.EventType.EventType_Strike_PowerUp, opposing_player.my_id, effect['amount'])
		StrikeEffects.StartOfTurnStrike:
			performing_player.start_of_turn_strike = true
			performing_player.effect_on_turn_start = { "effect_type": StrikeEffects.Strike }
		StrikeEffects.ForceStrikeAfterBoost:
			# Used inside boost effects to trigger a normal strike after boost
			# cleanup (Reese Invitation / Mix). Sets WaitForStrike so
			# continue_resolve_boost marks strike_after_boost and boost_play_cleanup
			# enters the generic strike path (discarding the boost card and
			# letting the player choose any attack).
			change_game_state(Enums.GameState.GameState_WaitForStrike)
		StrikeEffects.Strike:
			# Cannot strike during a strike.
			if not active_strike:
				if effect.get("opponent_forced_wild", false):
					performing_player.opponent_next_strike_forced_wild_swing = true
				change_game_state(Enums.GameState.GameState_WaitForStrike)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_StrikeNow
				decision_info.player = performing_player.my_id
				if active_boost:
					# Don't send the event now, we're processing a boost.
					# That has code to set flags on the active_boost to strike after the boost.
					# There could be more effects before the strike occurs, so wait on the event until then
					# and we don't want to send it twice.
					pass
				else:
					create_event(Enums.EventType.EventType_ForceStartStrike, performing_player.my_id, 0)
					if active_post_action_effect:
						post_action_interruption = true
		StrikeEffects.StrikeEffectAfterSetting:
			# Cannot strike during a strike.
			if not active_strike:
				if not active_boost:
					create_event(Enums.EventType.EventType_ForceStartStrike, performing_player.my_id, 0)
				change_game_state(Enums.GameState.GameState_WaitForStrike)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_StrikeNow
				decision_info.player = performing_player.my_id
				performing_player.extra_effect_after_set_strike = effect['after_set_effect']
		StrikeEffects.StrikeEffectAfterOpponentSets:
			var after_set_effect = effect.get("after_set_effect", effect.get("added_effect", null))
			if after_set_effect == null:
				return
			if active_strike:
				# If the opponent has not set yet, resolve this after their set effects.
				# Otherwise both attacks are already set, so resolve it immediately.
				if active_strike.get_player_card(opposing_player) == null:
					var deferred_after_set_effect = after_set_effect.duplicate(true)
					deferred_after_set_effect["for_other_player"] = true
					opposing_player.extra_effect_after_set_strike = deferred_after_set_effect
				else:
					handle_strike_effect(card_id, after_set_effect, performing_player)
			else:
				if not active_boost:
					create_event(Enums.EventType.EventType_ForceStartStrike, performing_player.my_id, 0)
				change_game_state(Enums.GameState.GameState_WaitForStrike)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_StrikeNow
				decision_info.player = performing_player.my_id
				opposing_player.extra_effect_after_set_strike = after_set_effect
		StrikeEffects.StrikeFaceup:
			# Cannot strike during a strike.
			if not active_strike:
				var disable_wild_swing = 'disable_wild_swing' in effect and effect['disable_wild_swing']
				var disable_ex = 'disable_ex' in effect and effect['disable_ex']
				if not active_boost:
					create_event(Enums.EventType.EventType_ForceStartStrike, performing_player.my_id, 0, "", disable_wild_swing, disable_ex)
				change_game_state(Enums.GameState.GameState_WaitForStrike)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_StrikeNow
				decision_info.player = performing_player.my_id
				performing_player.next_strike_faceup = true
		StrikeEffects.StrikeFromGauge:
			# Cannot strike during a strike.
			if not active_strike:
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_StrikeNow
				decision_info.player = performing_player.my_id
				decision_info.source = "gauge"
				if len(performing_player.gauge) > 0:
					if not active_boost: # Boosts will send strikes on their own
						create_event(Enums.EventType.EventType_Strike_FromGauge, performing_player.my_id, 0)
					change_game_state(Enums.GameState.GameState_WaitForStrike)
					performing_player.next_strike_faceup = true
					performing_player.next_strike_from_gauge = true
				else:
					change_game_state(Enums.GameState.GameState_WaitForStrike)
					_append_log_full(Enums.LogType.LogType_Effect, performing_player, "没有可用于战斗的怒气。")
					if active_boost:
						performing_player.next_strike_from_gauge = true
					else:
						var strike_info = {
							"card_id": -1,
							"wild_swing": true,
							"ex_card_id": -1
						}
						create_event(Enums.EventType.EventType_Strike_EffectDoStrike, performing_player.my_id, 0, "", strike_info)
		StrikeEffects.StrikeFromSealed:
			# Cannot strike during a strike.
			if not active_strike:
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_StrikeNow
				decision_info.player = performing_player.my_id
				decision_info.source = "sealed"
				if len(performing_player.sealed) > 0:
					change_game_state(Enums.GameState.GameState_WaitForStrike)
					performing_player.next_strike_faceup = not performing_player.sealed_area_is_secret
					performing_player.next_strike_from_sealed = true
					if not active_boost: # Boosts will send strikes on their own
						create_event(Enums.EventType.EventType_Strike_FromGauge, performing_player.my_id, 0)
				else:
					change_game_state(Enums.GameState.GameState_WaitForStrike)
					var strike_info = {
						"card_id": -1,
						"wild_swing": true,
						"ex_card_id": -1
					}
					_append_log_full(Enums.LogType.LogType_Effect, performing_player, "没有可用于战斗的封印牌。")
					if not active_boost: # Boosts will send strikes on their own
						create_event(Enums.EventType.EventType_Strike_EffectDoStrike, performing_player.my_id, 0, "", strike_info)
		StrikeEffects.StrikeOpponentSetsFirst:
			# Cannot strike during a strike.
			if not active_strike:
				create_event(Enums.EventType.EventType_Strike_OpponentSetsFirst, performing_player.my_id, 0)
				change_game_state(Enums.GameState.GameState_Strike_Opponent_Set_First)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_StrikeNow
				decision_info.player = performing_player.my_id
		StrikeEffects.StrikeRandomFromGauge:
			# Cannot strike during a strike.
			if not active_strike:
				create_event(Enums.EventType.EventType_Strike_OpponentSetsFirst, performing_player.my_id, 0)
				change_game_state(Enums.GameState.GameState_Strike_Opponent_Set_First)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_StrikeNow
				decision_info.player = performing_player.my_id
				performing_player.next_strike_random_gauge = true
		StrikeEffects.StrikeResponseReading:
			var card = effect['card_id']
			var ex_card = -1
			if 'ex_card_id' in effect:
				ex_card = effect['ex_card_id']
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "拥有被指定的牌！")
			change_game_state(Enums.GameState.GameState_Strike_Opponent_Response)
			var strike_info = {
				"card_id": card,
				"wild_swing": false,
				"ex_card_id": ex_card
			}
			create_event(Enums.EventType.EventType_Strike_EffectDoStrike, performing_player.my_id, 0, "", strike_info)
		"umina_reading_reveal_hand":
			# Umina（非觉醒）读心响应：手牌没有目标牌、幻梦境有目标牌时，选择「展示手牌」。
			# 走正常亮手牌流程：亮手牌后 defender 自由设置攻击（或 initiator 强制 wild swing）。
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "没有被指定的牌。")
			performing_player.reveal_hand()
			if active_strike != null:
				change_game_state(Enums.GameState.GameState_Strike_Opponent_Response)
				decision_info.clear()
				decision_info.player = performing_player.my_id
				if active_strike.initiator.force_opponent_respond_wild_swing():
					create_event(Enums.EventType.EventType_Strike_ForceWildSwing, active_strike.initiator.my_id, 0)
					_append_log_full(Enums.LogType.LogType_Effect, performing_player, "被强制进行疯狂攻击。")
					do_strike(performing_player, -1, true, -1, active_strike.opponent_sets_first)
				else:
					if active_strike.opponent_sets_first:
						create_event(Enums.EventType.EventType_Strike_OpponentSetsFirst_DefenderSet, performing_player.my_id, 0)
					else:
						create_event(Enums.EventType.EventType_Strike_DoResponseNow, performing_player.my_id, 0)
		StrikeEffects.StrikeWithDeusExMachina:
			if not active_strike:
				change_game_state(Enums.GameState.GameState_AutoStrike)
				decision_info.clear()
				decision_info.effect_type = "happychaos_deusexmachina"
		StrikeEffects.StrikeWithEx:
			# Cannot strike during a strike.
			if not active_strike:
				if performing_player.can_ex_strike_with_something():
					change_game_state(Enums.GameState.GameState_WaitForStrike)
					decision_info.clear()
					decision_info.type = Enums.DecisionType.DecisionType_StrikeNow
					decision_info.player = performing_player.my_id
					if performing_player.has_ex_boost():
						# Then any attack would be a valid EX
						create_event(Enums.EventType.EventType_ForceStartStrike, performing_player.my_id, 0)
					else:
						decision_info.limitation = "EX"
						var disable_wild_swing = true
						create_event(Enums.EventType.EventType_ForceStartStrike, performing_player.my_id, 0, "", disable_wild_swing)
		StrikeEffects.StrikeWithThisBoost:
			# Assumes that a boost is in play.
			if active_boost:
				change_game_state(Enums.GameState.GameState_AutoStrike)
				decision_info.clear()
				decision_info.effect_type = active_boost.card.definition['id']
				decision_info.type = Enums.DecisionType.DecisionType_StrikeNow
				decision_info.player = performing_player.my_id
		StrikeEffects.StrikeWild:
			# If a character has delayed wild strikes, they use this for the choices
			# but the strike will automatically occur after the set strike effects finish.
			if not effect.get("auto_delayed_strike", false):
				var opponent_forced_wild = effect.get("opponent_forced_wild", false)
				performing_player.opponent_next_strike_forced_wild_swing = opponent_forced_wild
				change_game_state(Enums.GameState.GameState_WaitForStrike)
				var strike_info = {
					"card_id": -1,
					"wild_swing": true,
					"ex_card_id": -1
				}
				create_event(Enums.EventType.EventType_Strike_EffectDoStrike, performing_player.my_id, 0, "", strike_info)
		StrikeEffects.StunImmunity:
			var is_color_spray_immunity = performing_player.deck_def.get("id") == "eugenia" \
				and card_id >= 0 \
				and card_db.get_card(card_id).definition.get("id") == "eugenia_colorful_mist" \
				and effect.get("timing", "") == "during_strike" \
				and effect.get("condition", "") == "opponent_max_cards_in_hand"
			# Color Spray is checked live in check_for_stun, not latched for the strike.
			if not is_color_spray_immunity:
				performing_player.strike_stat_boosts.stun_immunity = true
		StrikeEffects.SustainAllBoosts:
			for boost in performing_player.continuous_boosts:
				if boost.id not in performing_player.sustained_boosts:
					performing_player.sustained_boosts.append(boost.id)
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "维持所有持续性加成。")
			create_event(Enums.EventType.EventType_SustainBoost, performing_player.my_id, -1)
		StrikeEffects.SustainThis:
			performing_player.sustained_boosts.append(card_id)
			if 'hide_effect' not in effect or not effect['hide_effect']:
				var card = card_db.get_card(card_id)
				var boost_name = _get_boost_and_card_name(card)
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "维持其持续性加成%s。" % boost_name)
				create_event(Enums.EventType.EventType_SustainBoost, performing_player.my_id, card_id)
		StrikeEffects.SwapBuddy:
			var buddy_id_to_remove = effect['buddy_to_remove']
			var buddy_id_to_place = effect['buddy_to_place']
			performing_player.swap_buddy(buddy_id_to_remove, buddy_id_to_place, effect['description'])
		StrikeEffects.SwapDeckAndDiscard:
			performing_player.swap_deck_and_discard()
		StrikeEffects.SwapDeckAndSealed:
			performing_player.swap_deck_and_sealed()
		StrikeEffects.SwapPowerSpeed:
			performing_player.strike_stat_boosts.swap_power_speed = true
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "交换其威力和速度！")
		StrikeEffects.SwitchSpacesWithBuddy:
			var old_space = performing_player.arena_location
			var old_buddy_space = performing_player.get_buddy_location()
			performing_player.move_to(old_buddy_space)
			performing_player.place_buddy(old_space)
			_append_log_full(Enums.LogType.LogType_CharacterMovement, performing_player, "从格子%s移动到%s。" % [str(old_space), str(performing_player.arena_location)])
			_append_log_full(Enums.LogType.LogType_CharacterMovement, performing_player, "将%s从格子%s移动到%s。" % [performing_player.get_buddy_name(), str(old_buddy_space), str(performing_player.get_buddy_location())])
		StrikeEffects.TakeBonusActions:
			var silent = false
			if 'silent' in effect:
				silent = effect['silent']

			# Cannot take bonus actions during a strike.
			if not active_strike:
				var num = effect['amount']
				performing_player.bonus_actions += num
				performing_player.cancel_blocked_this_turn = true
				performing_player.strike_action_disabled = false
				if 'disable_strike_action' in effect and effect['disable_strike_action']:
					performing_player.strike_action_disabled = true
				if not silent:
					_append_log_full(Enums.LogType.LogType_Effect, performing_player, "获得%s次额外行动！" % str(num))
		StrikeEffects.TakeDamage:
			var nonlethal = 'nonlethal' in effect and effect['nonlethal']
			var damaged_player = performing_player
			if 'opponent' in effect and effect['opponent']:
				damaged_player = opposing_player
			var damage = effect['amount']
			var damage_prevention = 0
			if active_strike:
				damage_prevention = get_total_armor(damaged_player)
			var unmitigated_damage = max(0, damage - damage_prevention)
			var used_armor = damage - unmitigated_damage
			if active_strike:
				damaged_player.strike_stat_boosts.consumed_armor += used_armor
			if damaged_player.has_passive("discard_2x_topdeck_instead_of_damage"):
				var cards_to_discard = 2 * unmitigated_damage
				unmitigated_damage = 0
				for i in range(cards_to_discard):
					damaged_player.discard_topdeck()

			var actual_damage_taken = unmitigated_damage
			if nonlethal and unmitigated_damage >= damaged_player.life:
				actual_damage_taken = damaged_player.life - 1
			damaged_player.life -= actual_damage_taken
			create_event(Enums.EventType.EventType_Strike_TookDamage, damaged_player.my_id, actual_damage_taken, "", damaged_player.life)
			if used_armor > 0:
				_append_log_full(Enums.LogType.LogType_Health, damaged_player, "受到%s点非致命伤害（其中%s被护甲抵挡），生命值来到%s！" % [str(unmitigated_damage), str(used_armor), str(damaged_player.life)])
			else:
				_append_log_full(Enums.LogType.LogType_Health, damaged_player, "受到%s点非致命伤害，生命值来到%s！" % [str(unmitigated_damage), str(damaged_player.life)])
			if active_strike:
				active_strike.add_damage_taken(damaged_player, unmitigated_damage)
				check_for_stun(damaged_player, false)
			if damaged_player.life <= 0:
				trigger_game_over(damaged_player.my_id, Enums.GameOverReason.GameOverReason_Life)
		StrikeEffects.TopdeckFromHand:
			if len(performing_player.hand) > 0:
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_CardFromHandToGauge
				decision_info.player = performing_player.my_id
				decision_info.choice_card_id = card_id
				decision_info.destination = "topdeck"
				decision_info.valid_zones = ["hand"]
				var min_amount = effect['min_amount']
				var max_amount = effect['max_amount']
				decision_info.effect = {
					"min_amount": min_amount,
					"max_amount": max_amount,
				}
				create_event(Enums.EventType.EventType_CardFromHandToGauge_Choice, performing_player.my_id, min_amount, "", max_amount)
		StrikeEffects.AllowDuplicateNormalTransform:
			performing_player.tournelouse_allow_duplicate_transform = true
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "可以拥有第二张同名普通技转化。")
		StrikeEffects.MaySealTransformForGauge:
			performing_player.tournelouse_may_seal_for_gauge = true
		StrikeEffects.SealTransformForPowerup, StrikeEffects.SealTransformForArmorup:
			if performing_player.transforms.size() > 0:
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_ChooseFromBoosts
				decision_info.player = performing_player.my_id
				decision_info.choice_card_id = card_id
				decision_info.amount = 1
				decision_info.amount_min = 1
				decision_info.effect = effect
				create_event(Enums.EventType.EventType_ChooseFromBoosts, performing_player.my_id, 1)
		StrikeEffects.TournelouseTransformAnyFromHand:
			var choices = []
			choices.append({ "_choice_text": "完成（抽3）", "effect_type": StrikeEffects.Draw, "amount": 3 })
			for hand_card in performing_player.hand:
				if hand_card.definition['boost']['boost_type'] == "transform" or (performing_player.deck_def.get("id") == "tournelouse" and hand_card.definition['type'] == "normal" and not performing_player.exceeded):
					if not performing_player.has_card_name_in_zone(hand_card, "transform"):
						choices.append({
							"_choice_text": "转化 " + hand_card.definition['display_name'],
							"effect_type": StrikeEffects.TournelouseBargeistTransform,
							"transform_card_id": hand_card.id
						})
			change_game_state(Enums.GameState.GameState_PlayerDecision)
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_EffectChoice
			decision_info.player = performing_player.my_id
			decision_info.choice_card_id = card_id
			decision_info.choice = choices
			create_event(Enums.EventType.EventType_Strike_EffectChoice, performing_player.my_id, 0, "EffectOption")
		StrikeEffects.TournelouseBargeistTransform, StrikeEffects.TournelouseNormalTransform:
			var transform_card_id = effect.get("transform_card_id", effect.get("card_id", -1))
			if transform_card_id != -1 and performing_player.is_card_in_hand(transform_card_id):
				do_ex_transform(performing_player, transform_card_id, -1, false, true)
				if effect['effect_type'] == StrikeEffects.TournelouseBargeistTransform:
					add_remaining_effect({ "effect_type": StrikeEffects.TournelouseTransformAnyFromHand, "card_id": card_id })
		StrikeEffects.TournelouseOuroboros:
			if performing_player.transforms.size() == 0 or _get_tournelouse_transform_hand_options(performing_player).size() == 0:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "没有可交换的手牌和转化牌。")
			else:
				var force_effect = {
					"effect_type": StrikeEffects.ForceForEffect,
					"force_max": 1,
					"required": true,
					"tournelouse_ouroboros_force": true,
					"per_force_effect": null,
					"overall_effect": {
						"effect_type": StrikeEffects.Pass
					}
				}
				handle_strike_effect(card_id, force_effect, performing_player)
		StrikeEffects.TransformAttack:
			# This effect is expected to be at the end of a strike.
			assert(active_strike)
			var card_name = card_db.get_card_name(card_id)
			if 'card_name' in effect:
				card_name = effect['card_name']
			performing_player.strike_stat_boosts.move_strike_to_transforms = true
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "转化%s。" % [_log_card_name(card_name)])

			# Handling immediate effects; expected to be non-blocking, mostly to establish toggles e.g.
			var transform_card = card_db.get_card(card_id)
			var is_tournelouse_normal_pre_exceed = performing_player.deck_def.get("id") == "tournelouse" and transform_card.definition['type'] == "normal" and not performing_player.exceeded
			if not is_tournelouse_normal_pre_exceed:
				var transform_effects = card_db.get_card_boost_effects_now_immediate(transform_card)
				for transform_effect in transform_effects:
					do_effect_if_condition_met(performing_player, card_id, transform_effect, null)
		StrikeEffects.MoveStrikeToBleach:
			performing_player.strike_stat_boosts.move_strike_to_bleach = true
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "选择将攻击加入%s。" % performing_player.get_bleach_zone_name())
		StrikeEffects.WhenHitForceForArmor:
			if 'use_gauge_instead' in effect and effect['use_gauge_instead']:
				# Ignore if already using Block's force version.
				if performing_player.strike_stat_boosts.when_hit_force_for_armor != "force":
					performing_player.strike_stat_boosts.when_hit_force_for_armor = "gauge"
			else:
				performing_player.strike_stat_boosts.when_hit_force_for_armor = "force"
		StrikeEffects.ZeroVector:
			change_game_state(Enums.GameState.GameState_PlayerDecision)
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_ZeroVector
			decision_info.effect_type = StrikeEffects.ZeroVectorInternal
			decision_info.choice_card_id = card_id
			decision_info.bonus_effect = true
			decision_info.player = performing_player.my_id
			create_event(Enums.EventType.EventType_Boost_ZeroVector, performing_player.my_id, 0)
		StrikeEffects.ZeroVectorInternal:
			var named_id = effect['card_id']
			if named_id != -1:
				var named_card = card_db.get_card(named_id)
				# named_card is the individual card but
				# this should match "by name", so instead of using that
				# match on the display name, because Dive hits all Dives but Dust doesn't hit Spike.
				performing_player.cards_invalid_during_strike.append(named_card.definition['display_name'])
				opposing_player.cards_invalid_during_strike.append(named_card.definition['display_name'])
		StrikeEffects.ZeroVectorDialogue:
			# this exists purely for ui, no-op here
			pass
		StrikeEffects.ZsoltNormalPassive:
			# Zsolt normal passive: normals gain "hit: advance or retreat up to 1"
			var check_card = active_strike.get_player_card(performing_player) if active_strike else null
			if check_card and performing_player.deck_def.get("id") == "zsolt":
				if check_card.definition.get("type") == "normal":
					var choice_effect = {
						"effect_type": StrikeEffects.Choice,
						"choice": [
							{ "effect_type": StrikeEffects.Advance, "amount": 1 },
							{ "effect_type": StrikeEffects.Retreat, "amount": 1 },
							{ "effect_type": StrikeEffects.Pass, "amount": 0 }
						],
						"character_effect": true,
						"hide_effect": false
					}
					do_effect_if_condition_met(performing_player, card_id, choice_effect, null)
				else:
					# Remove from display for non-normals
					var idx = performing_player.strike_stat_boosts.added_attack_effects.find(effect)
					if idx >= 0:
						performing_player.strike_stat_boosts.added_attack_effects.remove_at(idx)
		StrikeEffects.ZsoltTransformExtra:
			# Zsolt: mark extra attack card for transform (per-extra-attack flag)
			if active_strike and active_strike.extra_attack_in_progress:
				var ea_card_name = effect.get("card_name", card_db.get_card_name(card_id))
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "will transform extra attack %s." % [_log_card_name(ea_card_name)])
				active_strike.extra_attack_data.zsolt_extra_transform = true
		StrikeEffects.SquiglyDarkTutelage:
			var normal_counts := {}
			for search_card in performing_player.deck + performing_player.discards:
				if search_card.definition.get("type", "") == "normal":
					var normal_definition_id = search_card.definition.get("id", "")
					normal_counts[normal_definition_id] = normal_counts.get(normal_definition_id, 0) + 1
			var choices := []
			for choice_definition_id in normal_counts.keys():
				var definition = CardDataManager.get_card(choice_definition_id)
				choices.append({
					"_choice_text": "将至多2张%s加入手牌" % definition.get("display_name", choice_definition_id),
					"effect_type": StrikeEffects.SquiglyDarkTutelageTake,
					"definition_id": choice_definition_id
				})
			if choices.is_empty():
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "牌库和弃牌堆中没有普通技。")
			else:
				do_effect_if_condition_met(performing_player, card_id, {
					"effect_type": StrikeEffects.Choice,
					StrikeEffects.Choice: choices,
					"override_description": "选择一种普通技，将至多2张同名牌加入手牌。"
				}, null)
		StrikeEffects.SquiglyDarkTutelageTake:
			var target_definition = effect.get("definition_id", "")
			var cards_taken = 0
			for discard_card in performing_player.discards.duplicate():
				if cards_taken >= 2:
					break
				if discard_card.definition.get("id", "") == target_definition:
					performing_player.move_card_from_discard_to_hand(discard_card.id)
					cards_taken += 1
			for deck_card in performing_player.deck.duplicate():
				if cards_taken >= 2:
					break
				if deck_card.definition.get("id", "") == target_definition:
					performing_player.remove_card_from_deck(deck_card.id)
					performing_player.add_to_hand(deck_card, true)
					cards_taken += 1
			performing_player.random_shuffle_deck()
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将%s张同名普通技加入手牌，然后洗切牌库。" % cards_taken)
		StrikeEffects.SquiglyCroise:
			if performing_player.deck.size() < 3:
				if performing_player.reshuffle_remaining <= 0:
					_append_log_full(Enums.LogType.LogType_Effect, performing_player, "已经使用过洗牌，无法查看牌库顶3张牌。")
					return
				performing_player.reshuffle_discard(false)
			var look_amount = mini(3, performing_player.deck.size())
			if look_amount > 0:
				do_effect_if_condition_met(performing_player, card_id, {
					"effect_type": StrikeEffects.ChooseCardsFromTopDeck,
					"look_amount": look_amount,
					"action_choices": ["add_to_hand"],
					"can_pass": false,
					"destination_unchosen": "topdeck",
					"shuffle_after": true
				}, null)
		StrikeEffects.SquiglyCenterStage:
			if performing_player.arena_location == 5 or opposing_player.arena_location == 5:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "场地中央格已被占据。")
			else:
				do_effect_if_condition_met(performing_player, card_id, {
					"effect_type": StrikeEffects.MoveToSpace,
					"amount": 5,
					"remove_buddies_encountered": 0,
					"and": { "effect_type": StrikeEffects.Pull, "amount": 1 }
				}, null)
		StrikeEffects.SquiglyReturnAttackAndCopies:
			var attack_card = active_strike.get_player_card(performing_player) if active_strike else null
			if attack_card != null:
				var attack_definition_id = attack_card.definition.get("id", "")
				handle_strike_effect(card_id, { "effect_type": StrikeEffects.ReturnAttackToHand }, performing_player)
				for discard_card in performing_player.discards.duplicate():
					if discard_card.definition.get("id", "") == attack_definition_id:
						performing_player.move_card_from_discard_to_hand(discard_card.id)
		"eugenia_passive_mark_used":
			if performing_player.deck_def.get("id") == "eugenia":
				performing_player.eugenia_normal_passive_used_this_turn = true
		"pooky_stunned_draw":
			# Exceed passive: when stunned, may draw 1 card
			do_effect_if_condition_met(performing_player, card_id, {
				"effect_type": StrikeEffects.Choice,
				StrikeEffects.Choice: [
					{ "effect_type": "draw", "amount": 1, "override_description": "Draw 1 card", "pooky_stunned_draw_on_death": true },
					{ "effect_type": "pass", "override_description": "No", "pooky_stunned_draw_on_death": true }
				],
				"override_description": "You are stunned. Draw a card?"
			}, null)
		"pooky_gambling_reveal":
			# Gambling? I'm In! reveal: move attack card to boosts as Continuous Boost (sustained), replace with Wild Swing
			var pooky_gr_card = active_strike.get_player_card(performing_player)
			if pooky_gr_card == null:
				return
			# Mark card as handled so strike cleanup skips it
			performing_player.invalid_card_moved_elsewhere = true
			active_strike.cards_in_play.erase(pooky_gr_card)
			# Add to continuous boosts directly (card has no real attack stats — Range/Power N/A)
			performing_player.add_to_continuous_boosts(pooky_gr_card)
			# Replace attack card with wild swing (top of deck)
			performing_player.wild_strike(true)
			var pooky_replacement_card = active_strike.get_player_card(performing_player)
			if pooky_replacement_card != null:
				for replacement_effect in get_all_effects_for_timing("on_strike_reveal", performing_player, pooky_replacement_card):
					add_remaining_effect(replacement_effect)
			# Extend ability bonuses to normal attacks this strike
			performing_player.strike_stat_boosts.pooky_normals_get_bonus = true
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "reveals Gambling? I'm In! and replaces it with a Wild Swing!")
		"pooky_range_per_cb":
			# Long in the Tooth: +0-1 Range per Continuous Boost
			var pooky_rpc_count = performing_player.continuous_boosts.size()
			if pooky_rpc_count > 0:
				performing_player.strike_stat_boosts.range_effects.append({
					"min_range": 0,
					"max_range": pooky_rpc_count,
					"special_only": false
				})
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "gains +0-%s Range from Continuous Boosts." % pooky_rpc_count)
		"pooky_power_per_cb":
			# Drunken Rampage hit: +2 Power per Continuous Boost
			var pooky_ppc_count = performing_player.continuous_boosts.size()
			if pooky_ppc_count > 0:
				var pooky_ppc_power = pooky_ppc_count * 2
				performing_player.strike_stat_boosts.power += pooky_ppc_power
				create_event(Enums.EventType.EventType_Strike_PowerUp, performing_player.my_id, pooky_ppc_power)
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "gains +%s Power from Continuous Boosts." % pooky_ppc_power)
		"pooky_drunken_fury_on_boost":
			# Drunken Fury: on_any_boost → first Instant Boost → pay 1F → Strike (resolves after Zol's Recipe)
			if performing_player.deck_def.get("id") != "pooky" or not active_boost:
				return
			if active_boost.card.definition['boost']['boost_type'] != "immediate":
				return
			if performing_player.pooky_drunken_fury_used:
				return
			performing_player.pooky_drunken_fury_used = true
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "Drunken Fury triggers.")
			do_effect_if_condition_met(performing_player, active_boost.card.id, {
				"effect_type": StrikeEffects.ForceForEffect,
				"per_force_effect": null,
				"force_max": 1,
				"min_force": 0,
				"overall_effect": {
					"effect_type": "pooky_drunken_fury_strike",
					"override_description": "Strike"
				}
			}, null)
			if game_state == Enums.GameState.GameState_PlayerDecision:
				return
		"pooky_drunken_fury_strike":
			# Drunken Fury overall_effect: enter strike selection after boost cleanup
			if active_boost:
				active_boost.strike_after_boost = true
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "Drunken Fury: enters strike selection!")
		"pooky_zols_recipe":
			# Zol's Secret Recipe (placeholder - unused, actual logic in pooky_zols_on_boost)
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "Zol's Secret Recipe ready.")
		"pooky_zols_on_boost":
			# Zol's Secret Recipe: on_any_boost → first Instant Boost → pay 1F → face-down CB
			if performing_player.deck_def.get("id") != "pooky" or not active_boost:
				return
			if active_boost.card.definition['boost']['boost_type'] != "immediate":
				return
			# 「每回合首次使用即时加成」：一触发就视为已用掉这次机会（无论玩家之后是否付 1 能量）。
			# 之前只靠 pooky_zols_target_id 判断，而成功转化会把它清回 -1，
			# 于是同一回合再打一张即时加成会被再转化一次。
			if performing_player.pooky_zols_used_this_turn:
				return
			if performing_player.pooky_zols_target_id != -1:
				return
			performing_player.pooky_zols_used_this_turn = true
			performing_player.pooky_zols_target_id = -2  # in-progress guard
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "Zol's Secret Recipe triggers.")
			do_effect_if_condition_met(performing_player, active_boost.card.id, {
				"effect_type": StrikeEffects.ForceForEffect,
				"per_force_effect": null,
				"force_max": 1,
				"min_force": 0,
				"overall_effect": {
					"effect_type": "pooky_set_zols_target",
					"card_id": active_boost.card.id,
					"override_description": "put into play as a facedown Continuous Boost"
				}
			}, null)
			if game_state == Enums.GameState.GameState_PlayerDecision:
				return
		"pooky_set_zols_target":
			# Zol's Recipe ForceForEffect overall_effect: mark this card for conversion
			var pooky_zst_card_id = effect.get("card_id", -1)
			if pooky_zst_card_id != -1:
				performing_player.pooky_zols_target_id = pooky_zst_card_id
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "Zol's Secret Recipe marks card for conversion.")
		"noelle_damage_toll":
			# 诺艾尔 常态/觉醒技能：一回合一次，战斗中受到伤害时支付1能量（惩罚）。
			# 触发点见 apply_damage（仅实际伤害>0 时触发，被护甲完全抵消不触发）。
			# 强制支付照 gordeau 觉醒行动（character_action_exceeded）的写法，两个字段缺一不可：
			#   required: true                   → game.gd can_cancel = false（不能取消/跳过）
			#   overall_effect 非 null（Nothing）→ game.gd require_max = force_max（必须付满1，不能付0确认）
			# 只设 required 仍可付 0 点；只设 overall_effect 仍可取消。
			if performing_player.noelle_damage_toll_used_this_turn:
				return
			performing_player.noelle_damage_toll_used_this_turn = true
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "受到伤害，必须支付1能量。")
			do_effect_if_condition_met(performing_player, -1, {
				"effect_type": StrikeEffects.ForceForEffect,
				"force_max": 1,
				"required": true,
				"per_force_effect": null,
				"overall_effect": { "effect_type": StrikeEffects.Nothing },
				"override_description": "支付1能量"
			}, null)
		"noelle_magic_shotgun":
			# 魔法霰弹（诺艾尔纯白之箭的加成，持续性）：
			# 你的普通技获得「击中：对手选择随机弃1张牌，或让你威力+2」。
			if not active_strike:
				return
			handle_strike_effect(card_id, {
				"effect_type": StrikeEffects.Choice,
				StrikeEffects.Choice: [
					{ "_choice_text": "随机弃置1张手牌", "effect_type": "noelle_magic_shotgun_discard" },
					{ "_choice_text": "让%s威力+2" % performing_player.name, "effect_type": "noelle_magic_shotgun_power" }
				],
				"override_description": "魔法霰弹：随机弃1张手牌，或让对手威力+2。"
			}, opposing_player)
		"noelle_magic_shotgun_discard":
			# 由对手（选择者）执行：随机弃置1张自己的手牌
			handle_strike_effect(card_id, { "effect_type": StrikeEffects.DiscardRandom, "amount": 1 }, performing_player)
		"noelle_magic_shotgun_power":
			# 由对手（选择者）执行：改为让诺艾尔（攻击方）威力+2
			handle_strike_effect(card_id, { "effect_type": StrikeEffects.Powerup, "amount": 2 }, opposing_player)
		StrikeEffects.DongshilangIcebladeAfterStunBonusDamage:
			if not active_strike:
				return
			if not active_strike.is_player_stunned(opposing_player):
				return
			var dongshilang_opponent_attack = active_strike.get_player_card(opposing_player)
			if not dongshilang_opponent_attack:
				return
			var dongshilang_printed_armor = int(dongshilang_opponent_attack.definition.get("armor", 0))
			if dongshilang_printed_armor > 0:
				handle_strike_effect(card_id, {
					"effect_type": StrikeEffects.TakeDamage,
					"amount": dongshilang_printed_armor,
					"opponent": true
				}, performing_player)
		StrikeEffects.DongshilangIceCloneNoGaugeOnHit:
			if not active_strike:
				return
			opposing_player.strike_stat_boosts.discard_attack_on_cleanup = true
		StrikeEffects.DongshilangIceCloneHitPowerIfWasHit:
			if not active_strike:
				return
			if active_strike.did_player_hit_opponent(opposing_player):
				handle_strike_effect(card_id, {
					"effect_type": StrikeEffects.Powerup,
					"amount": 1
				}, performing_player)
		StrikeEffects.DongshilangZekkuAfterRangeBonusDamage:
			if not active_strike:
				return
			var dongshilang_max_range = get_total_max_range(performing_player)
			var dongshilang_attack_origin = get_attack_origin(performing_player, opposing_player.arena_location)
			var dongshilang_extra_range = dongshilang_max_range + 1
			if not opposing_player.is_in_range_of_location(dongshilang_attack_origin, dongshilang_extra_range, dongshilang_extra_range):
				return
			var dongshilang_life_before = opposing_player.life
			handle_strike_effect(card_id, {
				"effect_type": StrikeEffects.TakeDamage,
				"amount": 1,
				"opponent": true
			}, performing_player)
			if opposing_player.life < dongshilang_life_before:
				performing_player.strike_stat_boosts.always_add_to_gauge = true
		StrikeEffects.DongshilangRhombusHitPowerdownIfNoArmor:
			if not active_strike:
				return
			if get_total_armor(performing_player) <= 0:
				handle_strike_effect(card_id, {
					"effect_type": StrikeEffects.Powerup,
					"amount": -1
				}, performing_player)
		StrikeEffects.DongshilangHyotenScaleByIceBoost:
			var hyoten_ice_count = _dongshilang_count_ice_in_boost_zone(performing_player)
			if hyoten_ice_count > 0:
				handle_strike_effect(card_id, {
					"effect_type": StrikeEffects.Speedup,
					"amount": hyoten_ice_count
				}, performing_player)
				handle_strike_effect(card_id, {
					"effect_type": StrikeEffects.Powerup,
					"amount": hyoten_ice_count * 2
				}, performing_player)
				handle_strike_effect(card_id, {
					"effect_type": StrikeEffects.Rangeup,
					"amount": 0,
					"amount2": hyoten_ice_count
				}, performing_player)
		StrikeEffects.DongshilangDiscardAllOtherBoosts:
			var all_boosts_to_discard = []
			for current_boost in performing_player.continuous_boosts:
				if current_boost.id != card_id:
					all_boosts_to_discard.append(current_boost.id)
			for current_boost in opposing_player.continuous_boosts:
				if current_boost.id != card_id:
					all_boosts_to_discard.append(current_boost.id)
			for discard_boost_id in all_boosts_to_discard:
				handle_strike_effect(card_id, {
					"effect_type": StrikeEffects.DiscardContinuousBoostInternal,
					"card_id": discard_boost_id,
					"destination": "discard"
				}, performing_player)
		StrikeEffects.DongshilangBinghuatuHitPowerupPerCross:
			var cross_count = int(dongshilang_cross_count_this_strike.get(performing_player.my_id, 0))
			if cross_count > 0:
				handle_strike_effect(card_id, {
					"effect_type": StrikeEffects.Powerup,
					"amount": cross_count
				}, performing_player)
		StrikeEffects.DongshilangLimitSelfMoveToOneThisStrike:
			var remaining = int(dongshilang_move_limit_remaining_this_strike.get(performing_player.my_id, -1))
			if remaining < 0 or remaining > 1:
				dongshilang_move_limit_remaining_this_strike[performing_player.my_id] = 1
		StrikeEffects.DongshilangConvertAdvanceToRetreat:
			dongshilang_convert_advance_to_retreat_this_strike[performing_player.my_id] = true
		StrikeEffects.ConvertAdvanceToClose:
			performing_player.strike_stat_boosts.convert_advance_to_close = true
		"dongshilang_begin_ice_boost_now":
			var dongshilang_amount = maxi(int(effect.get("amount", 1)), 1)
			var dongshilang_valid_zones = effect.get("valid_zones", ["bleach"])
			var dongshilang_limitation = effect.get("limitation", "ice_crystal")
			var dongshilang_ignore_costs = effect.get("ignore_costs", false)
			if performing_player.can_boost_something(dongshilang_valid_zones, dongshilang_limitation, dongshilang_ignore_costs):
				create_event(Enums.EventType.EventType_ForceStartBoost, performing_player.my_id, dongshilang_amount, "", dongshilang_valid_zones, dongshilang_limitation, dongshilang_ignore_costs)
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_BoostNow
				decision_info.amount = dongshilang_amount
				decision_info.player = performing_player.my_id
				decision_info.valid_zones = dongshilang_valid_zones
				decision_info.limitation = dongshilang_limitation
				decision_info.ignore_costs = dongshilang_ignore_costs
				decision_info.dongshilang_ice_character_action_cancel_once = true
			else:
				_append_log_full(Enums.LogType.LogType_Effect, performing_player, "没有可用于加成的冰晶。")
		_:
			assert(false, "ERROR: Unhandled effect type: %s" % effect['effect_type'])

	_queue_heiqiyihu_thresholds(performing_player)
	_queue_heiqiyihu_thresholds(opposing_player)
	var threshold_resume_kind = "action"
	if not active_strike and not _is_action_resolution_in_progress():
		threshold_resume_kind = "idle"
	_begin_heiqiyihu_thresholds(performing_player, threshold_resume_kind)
	_begin_pending_heiqiyihu_strike()

	if "and" in effect and effect['and'] and not and_handled_elsewhere:
		var and_effect = effect['and'].duplicate()
		if performing_player.strike_stat_boosts.heiqiyihu_prevent_opponent_moving_me \
		and _last_effect_source_player_id == opposing_player.my_id \
		and not and_effect.has("_source_player_id"):
			and_effect["_source_player_id"] = _last_effect_source_player_id
		var currently_set_card_id = and_effect.get("card_id", -1)
		# If currently_set_card_id is a string or something besides -1, then don't bother setting it.
		# Godot requires you check for the type of the variable before comparing it to -1.
		if typeof(currently_set_card_id) == TYPE_INT and currently_set_card_id == -1:
			and_effect["card_id"] = card_id
		if effect.get('pass_discards_to_and', false):
			and_effect["discarded_card_ids"] = effect["discarded_card_ids"]
		if game_state == Enums.GameState.GameState_PlayerDecision:
			add_queued_effect(and_effect, local_conditions,
				performing_player.my_id if not virtual_guardian.is_empty() else -1)
		else:
			var saved_source = _last_effect_source_player_id
			do_effect_if_condition_met(performing_player, card_id, and_effect, local_conditions)
			_last_effect_source_player_id = saved_source

func change_stats_when_attack_leaves_play(performing_player : Player):
	# Set total power and speed to invalid (0).
	# Set range to invalid - NOTE! If a buddy character can remove attacks, check all buddy range check functions.
	# Lose printed armor/guard values but keep boosts/powerups.
	# Lose focus ignore push/pull.
	# Lose block when_hit_force_for_armor
	var card = active_strike.get_player_card(performing_player)

	# Invalid stats.
	performing_player.strike_stat_boosts.overwrite_total_power = true
	performing_player.strike_stat_boosts.overwritten_total_power = 0
	performing_player.strike_stat_boosts.overwrite_total_speed = true
	performing_player.strike_stat_boosts.overwritten_total_speed = 0
	performing_player.strike_stat_boosts.overwrite_range_to_invalid = true

	# Remove printed stats by subtracting from bonuses.
	performing_player.strike_stat_boosts.armor -= get_card_stat(performing_player, card, "armor")
	performing_player.strike_stat_boosts.guard -= get_card_stat(performing_player, card, "guard")

	# Assumption! No character that currently has attacks returning to play can gain
	# the focus or block passives twice from a boost and a card somehow.
	# You would also lose ignore armor/guard but that shouldn't matter.
	performing_player.strike_stat_boosts.ignore_push_and_pull = false
	performing_player.strike_stat_boosts.heiqiyihu_prevent_opponent_moving_me = false
	performing_player.strike_stat_boosts.when_hit_force_for_armor = ""

	# This currently assumes that this would always from the played attack
	performing_player.strike_stat_boosts.higher_speed_misses = false

	# For Platinum, she can remove an attack in the After step that also has an After effect
	# still in remaining effects.
	# Try to find any of this card effects at this timing still in remaining effects and remove them.
	if performing_player.deck_def.get("id") == "platinum":
		for effect in active_strike.remaining_effect_list.duplicate():
			if effect.get("card_id", -1) == card.id:
				active_strike.remaining_effect_list.erase(effect)
	else:
		var current_timing = get_current_strike_timing()
		var card_effects = card_db.get_card_effects_at_timing(card, current_timing)
		for effect in active_strike.remaining_effect_list:
			if effect in card_effects:
				active_strike.remaining_effect_list.erase(effect)

	# If a character that can do this has Cleanup effects on the strike,
	# this needs to be added here somehow as well.

# Slipping Away: check if active and offer ForceForEffect → Move 1
func _umina_check_slipping_away(performing_player : Player, _card_id : int):
	if performing_player.deck_def.get("id") != "umina":
		return
	for umina_sa_tf in performing_player.transforms:
		if umina_sa_tf.definition.get("boost", {}).get("display_name") == "Slipping Away":
			# Queue — fire after current action resolves (avoids nested decision)
			# 归属者记成 Umina 自己：即使在对手回合置入幻梦境（例如用 Khadath /
			# Dark Thoughts 应战），也必须由 Umina 付能量并移动。
			add_queued_effect({
				"effect_type": StrikeEffects.ForceForEffect,
				"per_force_effect": null,
				"force_max": 1,
				"min_force": 0,
				"overall_effect": {
					"effect_type": "umina_slipping_away_move",
					"override_description": "Move 1"
				}
			}, null, performing_player.my_id)
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "Slipping Away ready to trigger after current action.")
			return

# Umina Spiraling Descent / Dreamlands stun immunity: check if a card is a copy of
# the target Dreamlands card.
# Normals match by speed (cross-season) ONLY when BOTH are normal. A normal and a
# special/ultra are never the same card name — even at the same speed (e.g. a 7-speed
# Grasp vs a 7-speed Terror Whispers must NOT match). Non-normal cards match by exact ID.
func _is_spiraling_match(target_def_id : String, check_card : GameCard) -> bool:
	if check_card == null:
		return false
	var target_card_def = CardDataManager.get_card(target_def_id)
	if target_card_def == null:
		return false
	if check_card.definition.get("type") == "normal" and target_card_def.get("type") == "normal":
		return check_card.definition.get("speed", -1) == target_card_def.get("speed", -1)
	return check_card.definition.get("id", "") == target_def_id

func handle_place_buddy_at_range(performing_player : Player, card_id, effect):
	# The player can place on either side within min/max range.
	var range_min = effect['range_min']
	var range_max = effect['range_max']
	decision_info.choice = []
	decision_info.limitation = []
	for i in range(Enums.MinArenaLocation, Enums.MaxArenaLocation + 1):
		var range_origin = performing_player.get_closest_occupied_space_to(i)
		var distance = abs(range_origin - i)
		if distance >= range_min and distance <= range_max:
			decision_info.limitation.append(i)
			var buddy_id = ""
			if 'buddy_id' in effect:
				buddy_id = effect['buddy_id']
			var choice = {
				"effect_type": StrikeEffects.PlaceBuddyIntoSpace,
				"buddy_id": buddy_id,
				"amount": i
			}
			if 'then_place_other_buddy' in effect and effect['then_place_other_buddy']:
				var other_buddy_id = ""
				if 'other_buddy_id' in effect:
					other_buddy_id = effect['other_buddy_id']
				choice['place_other_buddy_effect'] = {
					"effect_type": StrikeEffects.PlaceBuddyAtRange,
					"buddy_id": other_buddy_id,
					"buddy_name": effect['other_buddy_name'],
					"range_min": range_min,
					"range_max": range_max
				}
			decision_info.choice.append(choice)
	if decision_info.limitation.size() > 0:
		decision_info.type = Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect
		decision_info.player = performing_player.my_id
		decision_info.choice_card_id = card_id
		decision_info.effect_type = StrikeEffects.PlaceBuddyIntoSpace
		decision_info.source = effect['buddy_name']
		change_game_state(Enums.GameState.GameState_PlayerDecision)
		create_event(Enums.EventType.EventType_ChooseArenaLocationForEffect, performing_player.my_id, 0)

func do_seal_effect(performing_player : Player, card_id : int, source : String, silent : bool = false):
	var seal_effect = {
		"effect_type": StrikeEffects.SealCardInternal,
		"seal_card_id": card_id,
		"source": source,
		"silent": silent
	}
	handle_strike_effect(-1, seal_effect, performing_player)

func handle_player_draw_or_discard_to_effect(performing_player : Player, card_id, effect):
	var target_hand_size = effect['amount']
	if str(target_hand_size) == 'other_player_hand_size':
		var other_player = _get_player(get_other_player(performing_player.my_id))
		target_hand_size = other_player.hand.size()
	var hand_size = performing_player.hand.size()
	if hand_size < target_hand_size:
		var amount_to_draw = target_hand_size - hand_size
		performing_player.draw(amount_to_draw)
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "抽%s张牌，使手牌数达到%s。" % [amount_to_draw, target_hand_size])
		if 'per_draw_effect' in effect and amount_to_draw > 0:
			var per_draw_effect = effect['per_draw_effect'].duplicate()
			per_draw_effect['amount'] = amount_to_draw * per_draw_effect['amount']
			handle_strike_effect(card_id, per_draw_effect, performing_player)
	elif hand_size > target_hand_size:
		var amount_to_discard = hand_size - target_hand_size
		var discard_effect = {}
		if effect.get('random_discard', false):
			discard_effect = {
				"effect_type": StrikeEffects.DiscardRandom,
				"amount": amount_to_discard
			}
		else:
			discard_effect = {
				"effect_type": StrikeEffects.SelfDiscardChoose,
				"amount": amount_to_discard
			}
		# Carry the effect source for passive triggers (e.g. Eugenia Wonderland)
		# so _on_player_discard sees the original source, not the intermediate
		# performing_player (who executes the discard, not who caused it).
		discard_effect['_source_player_id'] = _last_effect_source_player_id
		if 'and' in effect:
			discard_effect['discard_effect'] = effect['and']
		_append_log_full(Enums.LogType.LogType_Effect, performing_player, "必须弃置%s张牌，使手牌数达到%s。" % [amount_to_discard, target_hand_size])
		handle_strike_effect(card_id, discard_effect, performing_player)
	else:
		pass

func get_card_stat(check_player : Player, card : GameCard, stat : String) -> int:
	if stat == 'power' and check_player.strike_stat_boosts.overwrite_printed_power:
		return check_player.strike_stat_boosts.overwritten_printed_power

	var value = card.definition[stat]
	if str(value) == "X":
		if active_strike:
			return check_player.strike_stat_boosts.strike_x
		else:
			assert(false, "ERROR: No support for interpreting X outside of strikes")
	elif str(value) == "CARDS_IN_HAND":
		value = check_player.hand.size()
	elif str(value) == "CARDS_IN_HAND_MAX_7":
		value = min(check_player.hand.size(), 7)
	elif str(value) == "TOTAL_POWER":
		assert(stat != 'power')
		value = get_total_power(check_player, false, card)
	elif str(value) == "RANGE_TO_OPPONENT":
		value = check_player.distance_to_opponent()
	elif str(value) == "INCLUDE_OPPONENT_IF_MOVED_PAST":
		value = -1
		# NOTE: This probably isn't necessary for any mechanics as the card that uses this
		# does the effect range_includes_if_moved_past.
		# However, this will be slightly wrong if someone has a +range boost of any kind.
		# If a character can do that and also cares about range, then worry about that then.
		if active_strike and check_player.strike_stat_boosts.range_includes_opponent:
			value = check_player.distance_to_opponent()

	var stat_limit = value
	if stat == 'speed' and 'max_base_speed' in card.definition:
		stat_limit = card.definition['max_base_speed']
	if stat == 'power' and 'max_base_power' in card.definition:
		stat_limit = card.definition['max_base_power']
	value = min(value, stat_limit)
	return value

func get_striking_card_ids_for_player(check_player : Player) -> Array:
	var card_ids = []
	if active_strike:
		if active_strike.initiator == check_player:
			if active_strike.initiator_card:
				card_ids.append(active_strike.initiator_card.definition['id'])
			if active_strike.initiator_ex_card:
				card_ids.append(active_strike.initiator_ex_card.definition['id'])
		elif active_strike.defender == check_player:
			if active_strike.defender_card:
				card_ids.append(active_strike.defender_card.definition['id'])
			if active_strike.defender_ex_card:
				card_ids.append(active_strike.defender_ex_card.definition['id'])
	return card_ids

func add_attack_triggers(performing_player : Player, card_ids : Array, set_character_effect : bool = false, include_passive : bool = false):
	for card_id in card_ids:
		var card = card_db.get_card(card_id)
		var card_name = card_db.get_card_name(card.id)
		var effect_list = []
		if include_passive:
			effect_list = card.definition['effects']
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "将把%s的所有效果加入其攻击！" % _log_card_name(card_name))
		else:
			_append_log_full(Enums.LogType.LogType_Effect, performing_player, "将把%s的前置/击中/后置效果加入其攻击！" % _log_card_name(card_name))
			for timing in ["before", "hit", "after"]:
				effect_list += card_db.get_card_effects_at_timing(card, timing)
		for card_effect in effect_list:
			var added_effect = {
				"effect_type": StrikeEffects.AddAttackEffect,
				"added_effect": card_effect.duplicate()
			}

			if set_character_effect:
				added_effect['character_effect'] = true
			handle_strike_effect(-1, added_effect, performing_player)

func duplicate_attack_triggers(performing_player : Player, amount : int):
	var card = active_strike.get_player_card(performing_player)

	var effects = []
	for timing in ["before", "hit", "after"]:
		effects += get_all_effects_for_timing(timing, performing_player, card)
	for i in range(amount):
		performing_player.strike_stat_boosts.added_attack_effects += effects

func get_boost_effects_at_timing(timing_name : String, performing_player : Player):
	var effects = []
	for boost_card in performing_player.get_continuous_boosts_and_transforms():
		# Renea: skip facedown continuous boosts (effects not active until revealed)
		if performing_player.deck_def.get("id") == "renea" and boost_card.definition["boost"].get("facedown"):
			continue
		for effect in boost_card.definition['boost']['effects']:
			if effect['timing'] == timing_name:
				var effect_with_id = effect.duplicate(true)
				effect_with_id['card_id'] = boost_card.id
				effects.append(effect_with_id)
	# Virtual guardians are not continuous_boost entities. Their immediate
	# effects were consumed before setting attacks; no next-turn hooks survive.
	if active_strike and timing_name not in ["now", "immediate", "start_of_next_turn"]:
		for record in active_strike.heiqiyihu_guardian_records:
			if record["player"] != performing_player.my_id:
				continue
			for effect in _get_heiqiyihu_guardian_boost(record)["effects"]:
				if effect["timing"] == timing_name:
					var virtual_effect = effect.duplicate(true)
					virtual_effect["card_id"] = record["source_id"]
					_add_source_player_id_to_effect_tree(virtual_effect, record["player"])
					effects.append(virtual_effect)
	return effects

func get_all_effects_for_timing(
	timing_name : String,
	performing_player : Player,
	card : GameCard,
	ignore_condition : bool = true,
	only_card_and_bonus_effects : bool = false
) -> Array:
	var card_effects = []
	var card_id = -1
	var duplicate_card_effects = 0
	if performing_player.strike_stat_boosts.repeat_printed_triggers_on_ex_attack and active_strike.will_be_ex(performing_player):
		if timing_name in ["before", "hit", "after"]:
			duplicate_card_effects = performing_player.strike_stat_boosts.repeat_printed_triggers_on_ex_attack
	if card:
		card_id = card.id
		card_effects = card_db.get_card_effects_at_timing(card, timing_name)
		if duplicate_card_effects:
			for i in range(duplicate_card_effects):
				card_effects += card_db.get_card_effects_at_timing(card, timing_name)
		for effect in card_effects:
			effect['card_id'] = card_id
	var boost_effects = get_boost_effects_at_timing(timing_name, performing_player)
	var character_effects = performing_player.get_character_effects_at_timing(timing_name)
	for effect in character_effects:
		effect['card_id'] = card_id
	var bonus_effects = performing_player.get_bonus_effects_at_timing(timing_name)

	var both_players_boost_effects = []
	both_players_boost_effects += get_boost_effects_at_timing("both_players_" + timing_name, performing_player)
	var other_player = _get_player(get_other_player(performing_player.my_id))
	both_players_boost_effects += get_boost_effects_at_timing("both_players_" + timing_name, other_player)

	# Check for opponent-given effects
	var opponent_given_effects = other_player.get_character_effects_at_timing("opponent_" + timing_name)
	opponent_given_effects += get_boost_effects_at_timing("opponent_" + timing_name, other_player)

	var all_effects = []
	for effect in card_effects:
		if ignore_condition or is_effect_condition_met(performing_player, effect, null):
			all_effects.append(effect)
		elif 'negative_condition_effect' in effect:
			all_effects.append(effect['negative_condition_effect'])
	if not only_card_and_bonus_effects:
		for effect in boost_effects:
			if ignore_condition or is_effect_condition_met(performing_player, effect, null):
				all_effects.append(effect)
			elif 'negative_condition_effect' in effect:
				all_effects.append(effect['negative_condition_effect'])
		for effect in both_players_boost_effects:
			if ignore_condition or is_effect_condition_met(performing_player, effect, null):
				all_effects.append(effect)
			elif 'negative_condition_effect' in effect:
				all_effects.append(effect['negative_condition_effect'])
		for effect in character_effects:
			if ignore_condition or is_effect_condition_met(performing_player, effect, null):
				all_effects.append(effect)
			elif 'negative_condition_effect' in effect:
				all_effects.append(effect['negative_condition_effect'])
	for effect in opponent_given_effects:
		if ignore_condition or is_effect_condition_met(performing_player, effect, null):
			all_effects.append(effect)
		elif 'negative_condition_effect' in effect:
			all_effects.append(effect['negative_condition_effect'])
	for effect in bonus_effects:
		if ignore_condition or is_effect_condition_met(performing_player, effect, null):
			all_effects.append(effect)
		elif 'negative_condition_effect' in effect:
			all_effects.append(effect['negative_condition_effect'])
	if timing_name == "hit" and performing_player.deck_def.get("id") == "double":
		for i in range(performing_player.double_true_face_stacks):
			all_effects.append({"effect_type":StrikeEffects.Powerup,"amount":1,"character_effect":true,"card_id":card_id})
		for i in range(performing_player.double_nightmare_army_stacks):
			all_effects.append({"effect_type":StrikeEffects.Draw,"amount":1,"character_effect":true,"card_id":card_id})
		if performing_player.exceeded:
			var repeated_hit_effects = all_effects.duplicate(true)
			all_effects.append_array(repeated_hit_effects)

	for effect in all_effects:
		if not 'card_id' in effect:
			effect['card_id'] = card_id
		if 'negative_condition_effect' in effect:
			effect['negative_condition_effect']['card_id'] = card_id
	return all_effects

func get_remaining_effect_count():
	if active_strike.extra_attack_in_progress:
		return active_strike.extra_attack_data.extra_attack_remaining_effects.size()
	else:
		return active_strike.remaining_effect_list.size()

func add_remaining_effect(effect):
	if active_strike.extra_attack_in_progress:
		active_strike.extra_attack_data.extra_attack_remaining_effects.append(effect)
	else:
		active_strike.remaining_effect_list.append(effect)

func erase_remaining_effect(effect):
	if active_strike.extra_attack_in_progress:
		active_strike.extra_attack_data.extra_attack_remaining_effects.erase(effect)
	else:
		active_strike.remaining_effect_list.erase(effect)

func remove_remaining_effect(effect, card_id):
	# This function is not intended to be called from extra attacks.
	assert(not active_strike.extra_attack_in_progress)
	if active_strike.extra_attack_in_progress:
		printlog("ERROR: Unexpected call during extra attacks.")
		return

	var base_effect = get_base_remaining_effect(effect)
	if active_strike and 'timing' in base_effect:
		for remaining_effect in active_strike.remaining_effect_list:
			if remaining_effect['timing'] == base_effect['timing'] and remaining_effect['card_id'] == card_id:
				active_strike.remaining_effect_list.erase(remaining_effect)
				break

func get_base_remaining_effect(effect):
	var remaining_effect_list = active_strike.remaining_effect_list
	if active_strike.extra_attack_in_progress:
		remaining_effect_list = active_strike.extra_attack_data.extra_attack_remaining_effects

	# Gets the base effect in the active strike's remaining effect list
	if 'is_negative_effect' in effect and effect['is_negative_effect']:
		# Find the actual effect this goes with, to avoid revealing condition outcomes early
		for remaining_effect in remaining_effect_list:
			if 'negative_condition_effect' in remaining_effect:
				if remaining_effect['negative_condition_effect'] == effect:
					return remaining_effect
	return effect

func sort_next_remaining_effects_to_choose(performing_player : Player):
	var remaining_effects = active_strike.remaining_effect_list
	if active_strike.extra_attack_in_progress:
		remaining_effects = active_strike.extra_attack_data.extra_attack_remaining_effects

	var effects_to_choose = {
		"condition_met": [],
		"condition_unmet": []
	}
	for effect in remaining_effects:
		if is_effect_condition_met(performing_player, effect, null):
			effects_to_choose["condition_met"].append(effect)
		elif 'negative_condition_effect' in effect and is_effect_condition_met(performing_player, effect['negative_condition_effect'], null):
			effects_to_choose["condition_met"].append(effect['negative_condition_effect'])
		else:
			# Should only be here if there was an effect that wasn't met
			assert("condition" in effect)
			if effect["condition"] not in StrikeStaticConditions:
				effects_to_choose["condition_unmet"].append(effect)
	return effects_to_choose

func reset_remaining_effects():
	if active_strike.extra_attack_in_progress:
		active_strike.extra_attack_data.extra_attack_remaining_effects = []
	else:
		active_strike.remaining_effect_list = []

func get_first_remaining_effect():
	if active_strike.extra_attack_in_progress:
		return active_strike.extra_attack_data.extra_attack_remaining_effects[0]
	else:
		return active_strike.remaining_effect_list[0]

func do_remaining_effects(performing_player : Player, next_state):

	while (active_strike.queued_stop_on_space_boosts or get_remaining_effect_count() > 0) and not game_state == Enums.GameState.GameState_PlayerDecision:
		# Before normal effect handling, proccess boosts whose spaces have just been entered
		if active_strike.queued_stop_on_space_boosts:
			var entered_boost_id = active_strike.queued_stop_on_space_boosts.pop_front()
			var entered_boost_card = card_db.get_card(entered_boost_id)
			var owning_player = _get_player(entered_boost_card.owner_id)
			var effect = entered_boost_card.definition['boost']['stop_on_space_effect']

			do_effect_if_condition_met(owning_player, entered_boost_id, effect, null)
			if game_state == Enums.GameState.GameState_PlayerDecision:
				break

		elif get_remaining_effect_count() > 1:
			# Check to see if any of these effects actually have their condition met (or have a negative condition).
			# If more than 1, send only those choices to the player.
			# If only 1 does, remove it from the list and do it immediately.
			# If none do, this is over, clear out the list.
			var effects_to_choose = sort_next_remaining_effects_to_choose(performing_player)
			var condition_met_effects = effects_to_choose["condition_met"]
			var condition_unmet_effects = effects_to_choose["condition_unmet"]

			# Check if any of these effects want to be resolved immediately
			# If so, just pick the first one.
			# This is done to reduce unnecessary choice dialogs for the user (ie. exceed Hazama).
			if condition_met_effects.size() + condition_unmet_effects.size() > 1:
				for effect in condition_met_effects + condition_unmet_effects:
					if 'resolve_before_simultaneous_effects' in effect and effect['resolve_before_simultaneous_effects']:
						condition_met_effects = [effect]
						condition_unmet_effects = []
						break

			# See if at least one effect can be resolved, potentially satisfying another's condition
			if condition_met_effects and condition_met_effects.size() + condition_unmet_effects.size() > 1:
				# Send choice to player
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_ChooseSimultaneousEffect
				decision_info.player = performing_player.my_id
				decision_info.source_player_id = performing_player.my_id
				decision_info.choice = []
				decision_info.limitation = []
				for effect in condition_met_effects:
					decision_info.choice.append(get_base_remaining_effect(effect))
					decision_info.limitation.append(true)
				for effect in condition_unmet_effects:
					decision_info.choice.append(get_base_remaining_effect(effect))
					decision_info.limitation.append(false)
				create_event(Enums.EventType.EventType_Strike_EffectChoice, performing_player.my_id, 0, "EffectOrder")
				break
			elif condition_met_effects.size() == 1:
				# Use the base effect to account for negative effects.
				var effect = get_base_remaining_effect(condition_met_effects[0])
				erase_remaining_effect(effect)
				do_effect_if_condition_met(performing_player, effect['card_id'], effect, null)

				if game_state == Enums.GameState.GameState_PlayerDecision:
					break
			else:
				# No more effects have their conditions met.
				reset_remaining_effects()
		else:
			# Only 1 effect in the list, do it.
			var effect = get_first_remaining_effect()
			reset_remaining_effects()
			do_effect_if_condition_met(performing_player, effect['card_id'], effect, null)

			if game_state == Enums.GameState.GameState_PlayerDecision:
				break
		if game_over:
			return

	if not active_strike.queued_stop_on_space_boosts and get_remaining_effect_count() == 0 and not game_state == Enums.GameState.GameState_PlayerDecision:
		active_strike.effects_resolved_in_timing = 0
		# Zsolt awaken: trigger after all after effects
		if next_state in [StrikeState.StrikeState_Card2_Activation, StrikeState.StrikeState_Cleanup] \
				and performing_player.deck_def.get("id") == "zsolt" and performing_player.exceeded:
			var is_hit = active_strike.did_player_hit_opponent(performing_player)
			if is_hit and performing_player.zsolt_extra_attack_count < 2 and not performing_player.zsolt_awaken_offered \
					and (performing_player.zsolt_extra_attack_count == 0 or active_strike.extra_attack_data.extra_attack_hit):
				var awaken_effect = {
					"effect_type": StrikeEffects.ForceForEffect,
					"is_zsolt_awaken": true,
					"overall_effect": null,
					"force_max": 1,
					"per_force_effect": {
						"effect_type": StrikeEffects.PlayAttackFromHand,
						"is_zsolt_awaken": true,
						"override_description": "execute an attack from your hand"
					}
				}
				handle_strike_effect(-1, awaken_effect, performing_player)
				# Only prevent state advancement if a decision was actually shown
				if game_state == Enums.GameState.GameState_PlayerDecision:
					return
		if active_strike.extra_attack_in_progress:
			active_strike.extra_attack_data.extra_attack_state = next_state
		else:
			active_strike.strike_state = next_state

func do_remaining_overdrive(performing_player : Player):
	change_game_state(Enums.GameState.GameState_Boost_Processing)
	while remaining_overdrive_effects.size() > 0:
		var effect = remaining_overdrive_effects[0]
		remaining_overdrive_effects.erase(effect)
		do_effect_if_condition_met(performing_player, -1, effect, null)
		if game_state == Enums.GameState.GameState_PlayerDecision:
			# Player has a decision to make, so stop mid-effect resolve.
			break

	if game_state != Enums.GameState.GameState_PlayerDecision:
		# Overdrive Cleanup
		if active_overdrive_boost_top_discard_on_cleanup:
			active_overdrive_boost_top_discard_on_cleanup = false
			# Assumption! The top discarded card is a continuous boost and
			# that boost has NO choices or decisions, it just goes into play.
			# do_boost will complete all the way through boost resolution.
			# Also, this boost has no cost.
			var card = performing_player.get_top_discard_card()
			# Put the card in the hand so do_boost has easy access.
			performing_player.move_card_from_discard_to_hand(card.id)

			# Prep gamestate so we can boost.
			change_game_state(Enums.GameState.GameState_PlayerDecision)
			decision_info.type = Enums.DecisionType.DecisionType_BoostNow
			do_boost(performing_player, card.id, [])

		# Very explicitly don't unset active_overdrive until after do_boost, so boost knows we're in overdrive doing this.
		# Also, there should be no decisions so we're good to advance the turn.
		active_overdrive = false
		start_begin_turn()

func add_queued_effect(effect : Dictionary, local_conditions : LocalStrikeConditions = null, queued_player_id : int = -1):
	var new_chain = {
		"effect": effect,
		"chain": queued_effect_chain,
		"local_conditions": local_conditions,
		# -1 = 沿用调用 do_queued_effects 时传入的玩家。
		# 非负则指定该效果的归属玩家（例如 Umina 在对手回合置入幻梦境而排队的
		# Slipping Away，必须由 Umina 自己结算，而不是当前回合玩家）。
		"queued_player_id": queued_player_id,
	}
	queued_effect_chain = new_chain

func add_queued_effects(effects : Array):
	for i in range(len(effects) - 1, -1, -1):
		var effect = effects[i]
		add_queued_effect(effect)

func do_queued_effects(performing_player : Player):
	if game_state not in [
		Enums.GameState.GameState_WaitForStrike,
		Enums.GameState.GameState_Strike_Opponent_Set_First,
		Enums.GameState.GameState_Strike_Opponent_Response
	]:
		if active_strike:
			change_game_state(Enums.GameState.GameState_Strike_Processing)
		else:
			change_game_state(Enums.GameState.GameState_Boost_Processing)

	while queued_effect_chain["effect"]:
		var effect = queued_effect_chain["effect"]
		var chain = queued_effect_chain["chain"]
		var local_conditions = queued_effect_chain["local_conditions"]
		var queued_player_id = queued_effect_chain.get("queued_player_id", -1)

		var after_resolution = false
		if 'after_resolution' in effect:
			after_resolution = effect['after_resolution']
		if after_resolution and resolving_boost_before_queue:
			break

		if chain:
			queued_effect_chain = chain
		else:
			queued_effect_chain["effect"] = null

		var effect_player = performing_player
		if queued_player_id >= 0 and queued_player_id != performing_player.my_id:
			effect_player = _get_player(queued_player_id)

		var card_id = effect.get("card_id", -1)
		do_effect_if_condition_met(effect_player, card_id, effect, local_conditions)
		if game_state == Enums.GameState.GameState_PlayerDecision or game_over:
			# Player has a decision to make, so stop mid-effect resolve.
			break

func _yuanliuzhai_clear_pressure(performing_player : Player, to_gauge : bool) -> int:
	var moved := 0
	for pressure_card in performing_player.bleach_zone.duplicate():
		if pressure_card.id in performing_player.yuanliuzhai_pressure_protected_ids:
			continue
		performing_player.remove_card_from_bleach(pressure_card.id)
		if to_gauge:
			performing_player.add_to_gauge(pressure_card)
		else:
			performing_player.add_to_discards(pressure_card)
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将威压区的%s%s。" % [_log_card_name(pressure_card.definition["display_name"]), "置入怒气区" if to_gauge else "弃置"])
		moved += 1
	return moved

func _yuanliuzhai_find_hand_card(performing_player : Player, definition_id : String) -> int:
	for hand_card in performing_player.hand:
		if hand_card.definition.get("id") == definition_id:
			return hand_card.id
	return -1

func _yuanliuzhai_counter_copies_publicly_unavailable(performing_player : Player, definition_id : String) -> bool:
	var unavailable_count := 0
	# Only public zones may rule out the response window without exposing hidden cards.
	for zone in [performing_player.discards, performing_player.bleach_zone]:
		for card in zone:
			if card.owner_id == performing_player.my_id and card.definition.get("id") == definition_id:
				unavailable_count += 1
	return unavailable_count >= 2

func _yuanliuzhai_effect_has_self_movement(effect, owned_by_booster : bool = true) -> bool:
	if typeof(effect) != TYPE_DICTIONARY:
		return false
	if effect.get("for_other_player", false):
		owned_by_booster = not owned_by_booster
	if owned_by_booster and effect.get("effect_type", "") in [StrikeEffects.Advance, StrikeEffects.Retreat, StrikeEffects.Close]:
		return true
	for nested_key in ["and", "negative_condition_effect", "added_effect"]:
		if effect.has(nested_key) and _yuanliuzhai_effect_has_self_movement(effect[nested_key], owned_by_booster):
			return true
	for choice_effect in effect.get("choice", []):
		if _yuanliuzhai_effect_has_self_movement(choice_effect, owned_by_booster != bool(effect.get("opponent", false))):
			return true
	return false

func _yuanliuzhai_offer_counter_cards(performing_player : Player):
	if not active_boost or active_boost.playing_player == performing_player:
		return
	var choices := []
	var is_continuous = active_boost.card.definition["boost"]["boost_type"] == "continuous"
	var boost_moves_self := false
	for boost_effect in active_boost.card.definition["boost"].get("effects", []):
		if _yuanliuzhai_effect_has_self_movement(boost_effect):
			boost_moves_self = true
			break
	if not is_continuous and not boost_moves_self:
		return
	var can_offer_shinra = is_continuous and not _yuanliuzhai_counter_copies_publicly_unavailable(performing_player, "yuanliuzhai_netsu_jigoku")
	var shinra_id = _yuanliuzhai_find_hand_card(performing_player, "yuanliuzhai_netsu_jigoku")
	if can_offer_shinra and shinra_id >= 0 and performing_player.life >= 2:
		choices.append({
			"effect_type": "yuanliuzhai_activate_shinra", "card_id": shinra_id,
			"_choice_text": "弃置森罗并支付2点生命：弃置双方所有持续性加成并无效当前加成"
		})
	var imin_id = _yuanliuzhai_find_hand_card(performing_player, "yuanliuzhai_onibi")
	var can_offer_imin = boost_moves_self and not _yuanliuzhai_counter_copies_publicly_unavailable(performing_player, "yuanliuzhai_onibi")
	if can_offer_imin and imin_id >= 0 and performing_player.life >= 2:
		choices.append({
			"effect_type": "yuanliuzhai_activate_imin", "card_id": imin_id,
			"_choice_text": "弃置威眠并支付2点生命：阻止该张加成离场前的所有自身移动"
		})
	if not can_offer_shinra and choices.is_empty():
		return
	choices.append({"effect_type": StrikeEffects.Pass, "_choice_text": "不响应"})
	handle_strike_effect(-1, {"effect_type": StrikeEffects.Choice, "choice": choices}, performing_player)

func _yuanliuzhai_activate_counter_card(performing_player : Player, counter_card_id : int, life_cost : int, is_shinra : bool):
	var expected_definition = "yuanliuzhai_netsu_jigoku" if is_shinra else "yuanliuzhai_onibi"
	if not active_boost or active_boost.playing_player == performing_player \
			or (is_shinra and active_boost.card.definition["boost"]["boost_type"] != "continuous") \
			or not performing_player.is_card_in_hand(counter_card_id) \
			or card_db.get_card(counter_card_id).definition["id"] != expected_definition \
			or performing_player.life < life_cost:
		printlog("ERROR: Invalid Yuanliuzhai counter target, card or life payment.")
		return
	var countered_boost = active_boost
	performing_player.discard([counter_card_id])
	performing_player.spend_life(life_cost)
	if game_over:
		return
	if is_shinra:
		handle_strike_effect(countered_boost.card.id, {
			"effect_type": StrikeEffects.NegateBoost, "allow_cancel_after_negate": true
		}, performing_player)
		for boost_owner in [player, opponent]:
			for boost_card in boost_owner.continuous_boosts.duplicate():
				boost_owner.remove_from_continuous_boosts(boost_card, "discard")
	else:
		var boost_owner = countered_boost.playing_player
		if countered_boost.card.id not in boost_owner.yuanliuzhai_blocked_boost_ids:
			boost_owner.yuanliuzhai_blocked_boost_ids.append(countered_boost.card.id)
		_append_log_full(Enums.LogType.LogType_Effect, performing_player, "威眠：阻止%s离场前的所有自身移动。" % _log_card_name(countered_boost.card.definition["display_name"]))

func do_set_strike_x(performing_player : Player, source : String, extra_info):

	var value = 0
	match source:
		"RANGE_TO_OPPONENT":
			value = performing_player.distance_to_opponent()
			_append_log_full(Enums.LogType.LogType_Strike, performing_player, "此次战斗的X被设为与对手的距离，%s。" % value)
		"amount_or_cards_left_in_deck":
			var amount = min(extra_info, performing_player.deck.size())
			value = amount
		"random_gauge_power":
			if len(performing_player.gauge) > 0:
				var random_gauge_idx = get_random_int() % len(performing_player.gauge)
				var card = performing_player.gauge[random_gauge_idx]
				var power = get_card_stat(performing_player, card, 'power')
				value = max(power, 0)
				var card_name = card_db.get_card_name(card.id)
				_append_log_full(Enums.LogType.LogType_Strike, performing_player, "此次战斗的X被设为怒气中%s的威力，%s。" % [_log_card_name(card_name), value])
				create_event(Enums.EventType.EventType_RevealRandomGauge, performing_player.my_id, card.id)
			else:
				_append_log_full(Enums.LogType.LogType_Strike, performing_player, "怒气中没有牌，因此X被设为0。")
		"top_discard_power":
			if len(performing_player.discards) > 0:
				var card = performing_player.get_top_discard_card()
				var power = get_card_stat(performing_player, card, 'power')
				value = max(power, 0)
				var card_name = card_db.get_card_name(card.id)
				_append_log_full(Enums.LogType.LogType_Strike, performing_player, "此次战斗的X被设为弃牌堆顶%s的威力，%s。" % [_log_card_name(card_name), value])
			else:
				_append_log_full(Enums.LogType.LogType_Strike, performing_player, "没有弃牌，因此X被设为0。")
		"top_deck_power":
			if len(performing_player.deck) > 0:
				var card = performing_player.get_top_deck_card()
				var power = get_card_stat(performing_player, card, 'power')
				value = max(power, 0)
				var card_name = card_db.get_card_name(card.id)
				_append_log_full(Enums.LogType.LogType_Strike, performing_player, "此次战斗的X被设为牌库顶%s的威力，%s。" % [_log_card_name(card_name), value])
			else:
				_append_log_full(Enums.LogType.LogType_Strike, performing_player, "其牌库为空，因此X被设为0。")
		"opponent_speed":
			if active_strike:
				if performing_player == active_strike.initiator:
					var defender_speed = get_total_speed(active_strike.defender)
					value = max(defender_speed, 0)
				else:
					var initiator_speed = get_total_speed(active_strike.initiator)
					value = max(initiator_speed, 0)
				_append_log_full(Enums.LogType.LogType_Strike, performing_player, "此次战斗的X被设为对手的速度，%s。" % value)
		"force_spent_before_strike":
			value = performing_player.force_spent_before_strike
			_append_log_full(Enums.LogType.LogType_Strike, performing_player, "此次战斗的X被设为已花费的能量，%s。" % value)
		"gauge_spent_before_strike":
			value = performing_player.gauge_spent_before_strike
			_append_log_full(Enums.LogType.LogType_Strike, performing_player, "此次战斗的X被设为已花费的怒气，%s。" % value)
		"copies_in_gauge":
			var card_id = extra_info['card_id']
			var card_name = extra_info['card_name']
			for card in performing_player.gauge:
				if card.definition['id'] == card_id:
					value += 1
			_append_log_full(Enums.LogType.LogType_Strike, performing_player, "此次战斗的X被设为怒气中%s的复制数量，%s。" % [_log_card_name(card_name), value])
		"cards_in_hand":
			value = len(performing_player.hand)
			_append_log_full(Enums.LogType.LogType_Strike, performing_player, "此次战斗的X被设为手牌数量，%s。" % value)
		"lightningsrods_in_opponent_space":
			var opposing_player = _get_player(get_other_player(performing_player.my_id))
			for i in range(Enums.MinArenaLocation, Enums.MaxArenaLocation + 1):
				if opposing_player.is_in_location(i):
					var lightningzone = performing_player.get_lightningrod_zone_for_location(i)
					value += len(lightningzone)
			_append_log_full(Enums.LogType.LogType_Strike, opposing_player, "位于%s个Lightning Rod上。" % [value])
		"ultras_used_to_pay_gauge_cost":
			for payment_card_id in performing_player.strike_stat_boosts.strike_payment_card_ids:
				var payment_card = card_db.get_card(payment_card_id)
				if payment_card.definition['type'] == "ultra":
					value += 1
		_:
			assert(false, "Unknown source for setting X")

	performing_player.set_strike_x(value)

func do_effects_for_timing(
	timing_name : String,
	performing_player : Player,
	card : GameCard,
	next_state,
	only_card_and_bonus_effects : bool = false,
	recorded_failed_effects = null
	):
	var effects = card_db.get_card_effects_at_timing(card, timing_name)
	var boost_effects = get_boost_effects_at_timing(timing_name, performing_player)
	var character_effects = performing_player.get_character_effects_at_timing(timing_name)
	var bonus_effects = performing_player.get_bonus_effects_at_timing(timing_name)
	if only_card_and_bonus_effects:
		boost_effects = []
		character_effects = []

	# Effects are resolved in the order:
	# Card > Continuous Boost > Character > Bonus
	while true:
		var boost_effects_resolved = active_strike.effects_resolved_in_timing - len(effects)
		var character_effects_resolved = boost_effects_resolved - len(boost_effects)
		var bonus_effects_resolved = character_effects_resolved - len(character_effects)
		if active_strike.effects_resolved_in_timing < len(effects):
			# Resolve card effects
			var effect = effects[active_strike.effects_resolved_in_timing]
			do_effect_if_condition_met(performing_player, card.id, effect, null, recorded_failed_effects)
			if game_state == Enums.GameState.GameState_PlayerDecision:
				# Player has a decision to make, so stop mid-effect resolve.
				break

			# Effect was resolved, continue loop to resolve more.
			active_strike.effects_resolved_in_timing += 1
		elif boost_effects_resolved < len(boost_effects):
			# Resolve boost effects
			var effect = boost_effects[boost_effects_resolved]
			do_effect_if_condition_met(performing_player, card.id, effect, null, recorded_failed_effects)
			if game_state == Enums.GameState.GameState_PlayerDecision:
				# Player has a decision to make, so stop mid-effect resolve.
				break

			# Effect was resolved, continue loop to resolve more.
			active_strike.effects_resolved_in_timing += 1
		elif character_effects_resolved < len(character_effects):
			# Resolve character effects
			var effect = character_effects[character_effects_resolved]
			do_effect_if_condition_met(performing_player, card.id, effect, null, recorded_failed_effects)
			if game_state == Enums.GameState.GameState_PlayerDecision:
				# Player has a decision to make, so stop mid-effect resolve.
				break

			# Effect was resolved, continue loop to resolve more.
			active_strike.effects_resolved_in_timing += 1
		elif bonus_effects_resolved < len(bonus_effects):
			# Resolve bonus effects
			var effect = bonus_effects[bonus_effects_resolved]
			do_effect_if_condition_met(performing_player, card.id, effect, null, recorded_failed_effects)
			if game_state == Enums.GameState.GameState_PlayerDecision:
				# Player has a decision to make, so stop mid-effect resolve.
				break

			# Effect was resolved, continue loop to resolve more.
			active_strike.effects_resolved_in_timing += 1
		else:
			# Cleanup
			if active_strike.extra_attack_in_progress:
				active_strike.extra_attack_data.extra_attack_state = next_state
			else:
				active_strike.strike_state = next_state
			active_strike.effects_resolved_in_timing = 0
			break

func is_location_in_range(attacking_player, card, test_location : int):
	if get_card_stat(attacking_player, card, 'range_min') == -1 or attacking_player.strike_stat_boosts.overwrite_range_to_invalid:
		return false
	var min_range = get_total_min_range(attacking_player)
	var max_range = get_total_max_range(attacking_player)
	var in_range_return_value = true
	if attacking_player.strike_stat_boosts.invert_range:
		in_range_return_value = false

	if attacking_player.strike_stat_boosts.calculate_range_from_buddy:
		if not attacking_player.is_buddy_in_play(attacking_player.strike_stat_boosts.calculate_range_from_buddy_id):
			return false
	var attack_source_location = get_attack_origin(attacking_player, test_location)

	var distance : int = abs(attack_source_location - test_location)
	if min_range <= distance and distance <= max_range:
		return in_range_return_value
	for included_range in attacking_player.strike_stat_boosts.attack_includes_ranges:
		if included_range == distance:
			return in_range_return_value
	return not in_range_return_value

func in_range(attacking_player, defending_player, card, combat_logging=false):
	if attacking_player.strike_stat_boosts.attack_does_not_hit or attacking_player.strike_stat_boosts.overwrite_range_to_invalid:
		return false
	if active_strike and active_strike.extra_attack_in_progress:
		if active_strike.extra_attack_data.extra_attack_always_miss:
			return false
	if attacking_player.strike_stat_boosts.only_hits_if_opponent_on_any_buddy:
		var buddies = attacking_player.get_buddies_on_opponent()
		if buddies.size() == 0:
			return false
	if defending_player.strike_stat_boosts.dodge_attacks:
		if combat_logging:
			_append_log_full(Enums.LogType.LogType_Effect, defending_player, "正在闪避攻击！")
		return false

	if defending_player.strike_stat_boosts.dodge_normals and card.definition['type'] == "normal":
		if combat_logging:
			_append_log_full(Enums.LogType.LogType_Effect, defending_player, "正在闪避普通攻击！")
		return false

	if defending_player.strike_stat_boosts.dodge_from_opposite_buddy and defending_player.is_buddy_in_play():
		var buddy_pos = defending_player.get_buddy_location()
		var dodging = false
		if attacking_player.is_left_of_location(buddy_pos) and defending_player.is_right_of_location(buddy_pos):
			dodging = true
		elif attacking_player.is_right_of_location(buddy_pos) and defending_player.is_left_of_location(buddy_pos):
				dodging = true
		if dodging:
			if combat_logging:
				_append_log_full(Enums.LogType.LogType_Effect, defending_player, "闪避来自%s后方的攻击！" % defending_player.get_buddy_name())
			return false

	var standard_source = true
	if attacking_player.strike_stat_boosts.calculate_range_from_buddy:
		standard_source = false
		if not attacking_player.is_buddy_in_play(attacking_player.strike_stat_boosts.calculate_range_from_buddy_id):
			return false
	if attacking_player.strike_stat_boosts.calculate_range_from_space != -1:
		standard_source = false
	var attack_source_location = get_attack_origin(attacking_player, defending_player.arena_location)

	var defender_location = defending_player.arena_location
	var defender_width = defending_player.extra_width
	var opponent_in_range = false
	for boost_id in attacking_player.strike_stat_boosts.range_includes_boost_spaces:
		var boost_location = attacking_player.get_boost_location(boost_id)
		if boost_location != -1 and defending_player.is_in_location(boost_location):
			_append_log_full(Enums.LogType.LogType_Strike, defending_player, "位于此攻击射程包含的加成格上。")
			opponent_in_range = true
			break
	if not opponent_in_range and attacking_player.strike_stat_boosts.range_includes_lightningrods and attacking_player.is_opponent_on_lightningrod():
		opponent_in_range = true
		_append_log_full(Enums.LogType.LogType_Strike, defending_player, "位于一个Lightning Rod上。")
	elif not opponent_in_range and attacking_player.strike_stat_boosts.range_includes_opponent:
		opponent_in_range = true
	elif not opponent_in_range:
		for defender_space_offset in range(-defender_width, defender_width+1):
			var defender_space = defender_location + defender_space_offset
			if is_location_in_range(attacking_player, card, defender_space):
				opponent_in_range = true
				break

		var min_range = get_total_min_range(attacking_player)
		var max_range = get_total_max_range(attacking_player)
		if active_strike.extra_attack_in_progress:
			min_range -= attacking_player.get_total_min_range_bonus(card, active_strike.extra_attack_data.extra_attack_previous_attack_range_effects)
			max_range -= attacking_player.get_total_max_range_bonus(card, active_strike.extra_attack_data.extra_attack_previous_attack_range_effects)
		var range_string = str(min_range)
		if min_range != max_range:
			range_string += "-%s" % str(max_range)
		var include_str = ""
		if attacking_player.strike_stat_boosts.attack_includes_ranges:
			include_str = " (including range(s) %s)" % ", ".join(attacking_player.strike_stat_boosts.attack_includes_ranges)
		var invert_str = ""
		if attacking_player.strike_stat_boosts.invert_range:
			invert_str = ", but inverted"
		_append_log_full(Enums.LogType.LogType_Strike, attacking_player, "距离为%s%s%s。" % [range_string, include_str, invert_str])

	# Apply special late calculation range dodges
	if defending_player.strike_stat_boosts.dodge_at_range_late_calculate_with == "OVERDRIVE_COUNT":
		var overdrive_count = defending_player.overdrive.size()
		defending_player.strike_stat_boosts.dodge_at_range_min[-2] = overdrive_count
		defending_player.strike_stat_boosts.dodge_at_range_max[-2] = overdrive_count

	# Range dodge
	if defending_player.strike_stat_boosts.dodge_at_range_min:
		for dodge_key in defending_player.strike_stat_boosts.dodge_at_range_min:
			var dodge_range_min = defending_player.strike_stat_boosts.dodge_at_range_min[dodge_key]
			var dodge_range_max = defending_player.strike_stat_boosts.dodge_at_range_max[dodge_key]

			var dodge_range_string = str(dodge_range_min)
			if dodge_range_max != dodge_range_min:
				dodge_range_string += "-%s" % str(dodge_range_max)

			if defending_player.strike_stat_boosts.dodge_at_range_from_buddy:
				var buddy_location = defending_player.get_buddy_location()
				var buddy_attack_source_location = attack_source_location
				if standard_source:
					buddy_attack_source_location = attacking_player.get_closest_occupied_space_to(buddy_location)
				var buddy_distance = abs(buddy_attack_source_location - buddy_location)
				if dodge_range_min <= buddy_distance and buddy_distance <= dodge_range_max:
					if combat_logging:
						_append_log_full(Enums.LogType.LogType_Effect, defending_player, "正在闪避来自%s、距离为%s的攻击！" % [dodge_range_string, defending_player.get_buddy_name()])
					return false
			else:
				if defending_player.is_in_range_of_location(attack_source_location, dodge_range_min, dodge_range_max):
					if combat_logging:
						_append_log_full(Enums.LogType.LogType_Effect, defending_player, "正在闪避距离为%s的攻击！" % dodge_range_string)
					return false

	# Speed dodge
	var attacking_speed = get_total_speed(attacking_player)
	var defending_speed = get_total_speed(defending_player)
	if defending_player.strike_stat_boosts.higher_speed_misses:
		var speed_dodge = defending_player.strike_stat_boosts.dodge_at_speed_greater_or_equal
		if speed_dodge > 0:
			if attacking_speed >= speed_dodge:
				if combat_logging:
					_append_log_full(Enums.LogType.LogType_Effect, defending_player, "正在闪避速度高于%s的攻击！" % str(speed_dodge))
				return false
		elif attacking_speed > defending_speed:
			if combat_logging:
				_append_log_full(Enums.LogType.LogType_Effect, defending_player, "正在闪避更高速度的攻击！")
			return false

	if defending_player.strike_stat_boosts.lower_speed_misses:
		var speed_dodge = defending_player.strike_stat_boosts.dodge_at_speed_lower_or_equal
		if speed_dodge > 0:
			if attacking_speed <= speed_dodge:
				if combat_logging:
					_append_log_full(Enums.LogType.LogType_Effect, defending_player, "正在闪避速度%s或更低的攻击！" % str(speed_dodge))
				return false

	return opponent_in_range

func handle_advanced_through(performing_player : Player, other_player : Player):
	var effects = get_all_effects_for_timing("moved_past", performing_player, null, false)
	# Assume no decisions.
	for effect in effects:
		if effect['timing'] == "moved_past":
			if is_effect_condition_met(performing_player, effect, null):
				do_effect_if_condition_met(performing_player, effect["card_id"], effect, null)
		elif effect['timing'] == "opponent_moved_past":
			if is_effect_condition_met(other_player, effect, null):
				do_effect_if_condition_met(other_player, effect["card_id"], effect, null)

func get_total_power(performing_player : Player, ignore_swap : bool = false, card : GameCard = null):
	if performing_player.strike_stat_boosts.swap_power_speed and not ignore_swap:
		return get_total_speed(performing_player, true)

	if performing_player.strike_stat_boosts.overwrite_total_power:
		return performing_player.strike_stat_boosts.overwritten_total_power

	assert(card or active_strike, "ERROR: No card or active strike to get power from.")
	if active_strike:
		card = active_strike.get_player_card(performing_player)
		if active_strike.extra_attack_in_progress:
			card = active_strike.extra_attack_data.extra_attack_card

	var power = get_card_stat(performing_player, card, 'power')
	# If some character multiplies both all bonuses and positive bonuses, that will need to be considered carefully.
	# For now, just assert we're not doing that.
	assert(performing_player.strike_stat_boosts.power_bonus_multiplier == 1 or performing_player.strike_stat_boosts.power_bonus_multiplier_positive_only == 1)

	var boosted_power = performing_player.strike_stat_boosts.power
	var positive_boosted_power = performing_player.strike_stat_boosts.power_positive_only
	if performing_player.deck_def.get("id") == "soifon" and card.definition.get("id") == "soifon_jakuho_raikoben":
		boosted_power += performing_player.soifon_shunko_spent_this_strike
	if performing_player.deck_def.get("id") == "yuanliuzhai":
		var pressure_types := {}
		for pressure_card in performing_player.bleach_zone:
			pressure_types[pressure_card.definition.get("type", "")] = true
		if pressure_types.has("special"):
			boosted_power += 1
			positive_boosted_power += 1
		if pressure_types.has("ultra"):
			boosted_power += 2
			positive_boosted_power += 2
	if performing_player.strike_stat_boosts.power_modify_per_buddy_between:
		# NOTE: This does not interact with the positive power multiplier.
		# If someone ever needs that, this needs to be updated.
		var buddy_count = performing_player.count_buddies_between_opponent()
		boosted_power += buddy_count * performing_player.strike_stat_boosts.power_modify_per_buddy_between

	if performing_player.strike_stat_boosts.power_armor_up_if_sealed_or_transformed_copy_of_attack:
		if performing_player.has_card_name_in_zone(card, "sealed") or performing_player.has_card_name_in_zone(card, "transform"):
			boosted_power += 1
			positive_boosted_power += 1

	if performing_player.strike_stat_boosts.powerup_per_sealed_amount_divisor:
		var sealed_count : int = performing_player.sealed.size()
		@warning_ignore('integer_division')
		var sealed_powerup : int = sealed_count / performing_player.strike_stat_boosts.powerup_per_sealed_amount_divisor
		sealed_powerup = min(sealed_powerup, performing_player.strike_stat_boosts.powerup_per_sealed_amount_max)
		boosted_power += sealed_powerup
		positive_boosted_power += sealed_powerup

	# account for passive bonus from hand size
	if performing_player.strike_stat_boosts.passive_powerup_per_card_in_hand != 0:
		var hand_size = len(performing_player.hand)
		var hand_size_power_bonus = hand_size * performing_player.strike_stat_boosts.passive_powerup_per_card_in_hand
		boosted_power += hand_size_power_bonus
		if hand_size_power_bonus > 0:
			positive_boosted_power += hand_size_power_bonus

	# Multiply all power bonuses.
	var power_modifier = boosted_power * performing_player.strike_stat_boosts.power_bonus_multiplier

	# Multiply positive power bonuses and add that in.
	var positive_multiplier_bonus = positive_boosted_power
	positive_multiplier_bonus *= (performing_player.strike_stat_boosts.power_bonus_multiplier_positive_only - 1)
	power_modifier += positive_multiplier_bonus

	if active_strike and active_strike.extra_attack_in_progress:
		# If an extra attack character has ways to get power multipliers, deal with that then.
		power_modifier = performing_player.strike_stat_boosts.power - active_strike.extra_attack_data.extra_attack_previous_attack_power_bonus
	var move_power_total = 0
	for boost in performing_player.continuous_boosts:
		move_power_total += boost.get_meta('bonus_move_power_counters', 0)
	return power + power_modifier + move_power_total

func get_total_armor(performing_player : Player):
	if performing_player.strike_stat_boosts.overwrite_total_armor:
		return performing_player.strike_stat_boosts.overwritten_total_armor

	var card = active_strike.get_player_card(performing_player)
	if card == null:
		return 0
	var armor = card.definition['armor']
	var armor_modifier = performing_player.strike_stat_boosts.armor - performing_player.strike_stat_boosts.consumed_armor

	if performing_player.strike_stat_boosts.power_armor_up_if_sealed_or_transformed_copy_of_attack:
		if performing_player.has_card_name_in_zone(card, "sealed") or performing_player.has_card_name_in_zone(card, "transform"):
			armor_modifier += 1

	# Demonheart: bonus_armor_counters provides live armor throughout the strike
	armor_modifier += performing_player.bonus_armor_counters
	# Hand-gated "always-on" armor bonuses, evaluated live against the current
	# hand (e.g. Baiken Hiiragi / Enchantress Fire Wave).
	for entry in performing_player.strike_stat_boosts.conditional_hand_armorups:
		if _hand_condition_met(performing_player, entry):
			armor_modifier += entry.amount
	# Ulrik: sum move armor counters from all continuous boosts
	var move_armor_total = 0
	for boost in performing_player.continuous_boosts:
		move_armor_total += boost.get_meta('bonus_move_armor_counters', 0)
	armor_modifier += move_armor_total

	return max(0, armor + armor_modifier)

func get_total_guard(performing_player : Player):
	if performing_player.strike_stat_boosts.overwrite_total_guard:
		return performing_player.strike_stat_boosts.overwritten_total_guard

	var card = active_strike.get_player_card(performing_player)
	if card == null:
		return 0
	var guard = get_card_stat(performing_player, card, 'guard')
	var guard_modifier = performing_player.strike_stat_boosts.guard

	if performing_player.strike_stat_boosts.guardup_per_gauge:
		guard_modifier += len(performing_player.gauge)

	if performing_player.strike_stat_boosts.guardup_per_two_cards_in_hand:
		var hand_size = len(performing_player.hand)
		guard_modifier += floor(hand_size / 2.0)

	if performing_player.strike_stat_boosts.guardup_if_copy_of_opponent_attack_in_sealed_modifier:
		var opposing_player = _get_player(get_other_player(performing_player.my_id))
		var opponent_attack = active_strike.get_player_card(opposing_player)
		if performing_player.has_card_name_in_zone(opponent_attack, "sealed"):
			guard_modifier += performing_player.strike_stat_boosts.guardup_if_copy_of_opponent_attack_in_sealed_modifier

	# Reese Support: bonus_guard_counters provides live guard throughout the strike
	guard_modifier += performing_player.bonus_guard_counters

	return guard + guard_modifier

func get_total_min_range(performing_player : Player):
	assert(active_strike)
	var card = active_strike.get_player_card(performing_player)
	if active_strike.extra_attack_in_progress:
		card = active_strike.extra_attack_data.extra_attack_card

	var min_range = get_card_stat(performing_player, card, 'range_min')
	var min_range_modifier = performing_player.get_total_min_range_bonus(card)
	if performing_player.strike_stat_boosts.rangeup_min_per_boost_modifier > 0:
		var boosts_in_play = performing_player.get_boosts().size()
		if performing_player.strike_stat_boosts.rangeup_per_boost_modifier_all_boosts:
			var opposing_player = _get_player(get_other_player(performing_player.my_id))
			boosts_in_play += opposing_player.get_boosts().size()
		if boosts_in_play > 0:
			min_range_modifier += performing_player.strike_stat_boosts.rangeup_min_per_boost_modifier * boosts_in_play
	if performing_player.strike_stat_boosts.rangeup_min_if_ex_modifier > 0:
		if active_strike.will_be_ex(performing_player):
			min_range_modifier += performing_player.strike_stat_boosts.rangeup_min_if_ex_modifier
	return min_range + min_range_modifier

func _is_meilian_discard_range_effect(effect, performing_player : Player) -> bool:
	return performing_player.deck_def.get("id") == "meilian" \
		and effect.get("character_effect", false) \
		and effect.get("condition") == "copy_of_attack_in_zones" \
		and effect.get("condition_zones", []) == ["discard"] \
		and effect.get("effect_type") == StrikeEffects.Rangeup

func _get_meilian_dynamic_max_range_bonus(performing_player : Player, card : GameCard) -> int:
	if performing_player.deck_def.get("id") != "meilian" or card == null:
		return 0
	if performing_player.has_card_name_in_zone(card, "discard"):
		return 2 if performing_player.exceeded else 1
	return 0

func get_total_max_range(performing_player : Player):
	assert(active_strike)
	var card = active_strike.get_player_card(performing_player)
	if active_strike.extra_attack_in_progress:
		card = active_strike.extra_attack_data.extra_attack_card

	var max_range = get_card_stat(performing_player, card, 'range_max')
	var max_range_modifier = performing_player.get_total_max_range_bonus(card)
	max_range_modifier += _get_meilian_dynamic_max_range_bonus(performing_player, card)
	if performing_player.strike_stat_boosts.rangeup_max_per_boost_modifier > 0:
		var boosts_in_play = performing_player.get_boosts().size()
		if performing_player.strike_stat_boosts.rangeup_per_boost_modifier_all_boosts:
			var opposing_player = _get_player(get_other_player(performing_player.my_id))
			boosts_in_play += opposing_player.get_boosts().size()
		if boosts_in_play > 0:
			max_range_modifier += performing_player.strike_stat_boosts.rangeup_max_per_boost_modifier * boosts_in_play
	if performing_player.strike_stat_boosts.rangeup_max_if_ex_modifier > 0:
		if active_strike.will_be_ex(performing_player):
			max_range_modifier += performing_player.strike_stat_boosts.rangeup_max_if_ex_modifier
	return max_range + max_range_modifier

func get_attack_origin(performing_player : Player, target_location : int):
	var origin = performing_player.get_closest_occupied_space_to(target_location)
	if performing_player.strike_stat_boosts.calculate_range_from_buddy:
		origin = performing_player.get_buddy_location(performing_player.strike_stat_boosts.calculate_range_from_buddy_id)
	elif performing_player.strike_stat_boosts.calculate_range_from_space != -1:
		origin = performing_player.strike_stat_boosts.calculate_range_from_space
	return origin

func calculate_damage(offense_player : Player, defense_player : Player) -> int:
	var power = get_total_power(offense_player)
	# Zsolt awaken: extra attack power is capped at 1 (before armor)
	if active_strike.extra_attack_in_progress and active_strike.extra_attack_data.zsolt_max_damage_1:
		power = min(power, 1)
	var armor = get_total_armor(defense_player)
	if offense_player.strike_stat_boosts.ignore_armor:
		armor = 0
	var damage_after_armor = max(power - armor, 0)
	return damage_after_armor

func _eugenia_color_spray_stun_immunity_now(check_player : Player, defense_card : GameCard) -> bool:
	if check_player.deck_def.get("id") != "eugenia":
		return false
	if defense_card == null or defense_card.definition.get("id") != "eugenia_colorful_mist":
		return false
	var other_player = _get_player(get_other_player(check_player.my_id))
	if not other_player:
		return false
	return other_player.hand.size() <= 2

func check_for_stun(check_player : Player, ignore_guard : bool):

	if active_strike.is_player_stunned(check_player):
		# If they're already stunned, can't stun again.
		return

	var total_damage = active_strike.get_damage_taken(check_player)
	var defense_card = active_strike.get_player_card(check_player)
	if defense_card == null:
		return
	var guard = get_total_guard(check_player)
	_append_log_full(Enums.LogType.LogType_Strike, null, "眩晕检查：总伤害%s vs 霸体%s。" % [total_damage, guard])
	if ignore_guard:
		_append_log_full(Enums.LogType.LogType_Strike, _get_player(get_other_player(check_player.my_id)), "无视霸体！")
		guard = 0

	guard = max(guard, 0)
	if total_damage > guard:
		var umina_dynamic_stun_immunity = false
		if check_player.deck_def.get("id") == "umina" and not check_player.exceeded and check_player.set_aside_cards.size() > 0:
			var umina_si_dream = check_player.set_aside_cards[0]
			umina_dynamic_stun_immunity = _is_spiraling_match(umina_si_dream.definition.get("id", ""), defense_card)
		if check_player.strike_stat_boosts.stun_immunity or _eugenia_color_spray_stun_immunity_now(check_player, defense_card) or umina_dynamic_stun_immunity:
			_append_log_full(Enums.LogType.LogType_Strike, check_player, "具有免疫眩晕！")
			create_event(Enums.EventType.EventType_Strike_Stun_Immunity, check_player.my_id, defense_card.id)
		else:
			_append_log_full(Enums.LogType.LogType_Strike, check_player, "被眩晕！")
			create_event(Enums.EventType.EventType_Strike_Stun, check_player.my_id, defense_card.id)
			active_strike.set_player_stunned(check_player)
			# Reese passive tracking: stunner records this turn's stun.
			var stunner = _get_player(get_other_player(check_player.my_id))
			stunner.opponent_was_stunned_this_turn = true

			# Pooky and Londrekia's passives belong to the stunned player; other
			# on-stunned abilities, such as Reese's, belong to the stunner.
			var stunned_player_abilities = ["pooky", "londrekia"]
			var stun_effect_player = check_player if check_player.deck_def.get("id") in stunned_player_abilities else stunner
			if stun_effect_player.deck_def.get("id") != "pooky" or stun_effect_player == check_player:
				var effects = stun_effect_player.get_character_effects_at_timing("on_stunned")
				for effect in effects:
					do_effect_if_condition_met(stun_effect_player, -1, effect, null)

func apply_damage(offense_player : Player, defense_player : Player):
	var power = get_total_power(offense_player)
	var armor = get_total_armor(defense_player)

	defense_player.strike_stat_boosts.was_hit = true

	_append_log_full(Enums.LogType.LogType_Strike, null, "伤害计算：总威力%s vs 总护甲%s。" % [str(power), str(armor)])

	if offense_player.strike_stat_boosts.ignore_armor:
		_append_log_full(Enums.LogType.LogType_Strike, offense_player, "无视护甲！")
		armor = 0

	var damage_after_armor = calculate_damage(offense_player, defense_player)
	if offense_player.strike_stat_boosts.deal_nonlethal_damage:
		_append_log_full(Enums.LogType.LogType_Health, offense_player, "的攻击造成非致命伤害。")
		damage_after_armor = min(damage_after_armor, defense_player.life-1)
	if defense_player.strike_stat_boosts.cap_attack_damage_taken != -1:
		_append_log_full(Enums.LogType.LogType_Health, offense_player, "的攻击伤害上限为%s。" % [str(defense_player.strike_stat_boosts.cap_attack_damage_taken)])
		damage_after_armor = min(damage_after_armor, defense_player.strike_stat_boosts.cap_attack_damage_taken)

	var consumed_armor = power - damage_after_armor
	if defense_player.has_passive("discard_2x_topdeck_instead_of_damage"):
		var cards_to_discard = 2 * damage_after_armor
		damage_after_armor = 0
		for i in range(cards_to_discard):
			defense_player.discard_topdeck()

	# Decrease life.
	defense_player.life -= damage_after_armor
	if defense_player.strike_stat_boosts.cannot_go_below_life > 0:
		defense_player.life = max(defense_player.life, defense_player.strike_stat_boosts.cannot_go_below_life)
	if armor > 0:
		defense_player.strike_stat_boosts.consumed_armor += consumed_armor
	create_event(Enums.EventType.EventType_Strike_TookDamage, defense_player.my_id, damage_after_armor, "", defense_player.life)

	_append_log_full(Enums.LogType.LogType_Health, defense_player, "受到%s点伤害，生命值来到%s！" % [str(damage_after_armor), str(defense_player.life)])

	active_strike.add_damage_taken(defense_player, damage_after_armor)

	if defense_player.deck_def.get("id") == "noelle" and defense_player.life <= 0:
		_append_log_full(Enums.LogType.LogType_Default, defense_player, "生命已归零！")
		on_death(defense_player)
		return

	# 战斗中「受到实际伤害」时触发受伤者自己的角色技能（Noelle 常态/觉醒的支付1能量惩罚）。
	# 注意：只有实际伤害 > 0 才触发（被护甲完全抵消不触发）。
	if damage_after_armor > 0:
		for dmg_taken_effect in defense_player.get_character_effects_at_timing("on_strike_damage_taken"):
			do_effect_if_condition_met(defense_player, -1, dmg_taken_effect, null)
			if game_state == Enums.GameState.GameState_PlayerDecision:
				break

	if offense_player.strike_stat_boosts.cannot_stun:
		_append_log_full(Enums.LogType.LogType_Strike, offense_player, "的攻击不能造成眩晕！")
	else:
		check_for_stun(defense_player, offense_player.strike_stat_boosts.ignore_guard)

	if defense_player.life <= 0:
		_append_log_full(Enums.LogType.LogType_Default, defense_player, "生命已归零！")
		on_death(defense_player)
	_queue_heiqiyihu_thresholds(defense_player)

func on_death(performing_player):
	if 'on_death' in performing_player.deck_def:
		do_effect_if_condition_met(performing_player, -1, performing_player.deck_def['on_death'], null)
	if performing_player.life <= 0:
		# Defer game over if there's a pending decision that may restore life:
		# 1) Player exceeded and is choosing an on_exceed effect (e.g., gain life).
		# 2) Player is selecting gauge cards to pay the exceed cost on death (not yet exceeded).
		if game_state == Enums.GameState.GameState_PlayerDecision and \
				(performing_player.exceeded or \
				(decision_info.type == Enums.DecisionType.DecisionType_GaugeForEffect and \
				decision_info.player == performing_player.my_id)):
			if not _is_pooky_stunned_draw_choice(performing_player):
				return
		trigger_game_over(performing_player.my_id, Enums.GameOverReason.GameOverReason_Life)

func _is_taisei_death_exceed_decision(performing_player : Player, effect) -> bool:
	if performing_player.deck_def.get("id") != "taisei":
		return false
	if not performing_player.deck_def.has("hp_rank_taisei_exceed_life"):
		return false
	if performing_player.life > 0:
		return false
	if not (effect is Dictionary):
		return false
	if not effect.get("decline_on_death_game_over", false):
		return false
	var overall_effect = effect.get("overall_effect", null)
	if not (overall_effect is Dictionary):
		return false
	return overall_effect.get("effect_type", "") == StrikeEffects.ExceedNow

func _get_taisei_death_exceed_target_life(performing_player : Player) -> int:
	return max(int(performing_player.deck_def.get("hp_rank_taisei_exceed_life", 10)), 1)

func _consume_taisei_death_exceed_override_life(performing_player : Player, effect_amount : int) -> int:
	if performing_player.deck_def.get("id") != "taisei":
		return -1
	if performing_player.taisei_death_exceed_override_life < 0:
		return -1
	if effect_amount != 10:
		return -1
	var override_life = performing_player.taisei_death_exceed_override_life
	performing_player.taisei_death_exceed_override_life = -1
	return override_life

func _is_pooky_stunned_draw_choice(performing_player : Player) -> bool:
	if performing_player.deck_def.get("id") != "pooky":
		return false
	if game_state != Enums.GameState.GameState_PlayerDecision:
		return false
	if decision_info.player != performing_player.my_id:
		return false
	if decision_info.type != Enums.DecisionType.DecisionType_EffectChoice:
		return false
	if decision_info.choice == null:
		return false
	for choice_effect in decision_info.choice:
		if choice_effect.get("pooky_stunned_draw_on_death", false):
			return true
	return false

func _append_life_conditional_if_absent(list, amount, threshold):
	for entry in list:
		if entry.amount == amount:
			return
	list.append({"amount": amount, "threshold": threshold, "applied": false})

# Register a hand-gated "always-on" stat bonus for live evaluation in
# get_total_speed / get_total_armor. cond is "max_cards_in_hand" (bonus while
# hand <= cond_amount) or "min_cards_in_hand" (bonus while hand >= cond_amount).
func _append_hand_conditional_if_absent(list, amount, cond, cond_amount):
	var max_hand = cond_amount if cond == "max_cards_in_hand" else -1
	var min_hand = cond_amount if cond == "min_cards_in_hand" else -1
	for entry in list:
		if entry.amount == amount and entry.max_hand == max_hand and entry.min_hand == min_hand:
			return
	list.append({"amount": amount, "max_hand": max_hand, "min_hand": min_hand})

func _hand_condition_met(target_player : Player, entry) -> bool:
	if entry.max_hand >= 0 and target_player.hand.size() > entry.max_hand:
		return false
	if entry.min_hand >= 0 and target_player.hand.size() < entry.min_hand:
		return false
	return true

func _scan_life_conditional_boosts(target_player : Player):
	for card in target_player.get_continuous_boosts_and_transforms():
		for effect in card.definition['boost']['effects']:
			if effect.get('timing') != "during_strike":
				continue
			_scan_life_conditional_effect(target_player, effect)

func _scan_life_conditional_effect(target_player : Player, effect):
	if effect.get("condition", "") == "life_equal_or_below":
		var threshold = effect.get("condition_amount", 0)
		var etype = effect.get("effect_type", "")
		var amt = effect.get("amount", 1)
		if etype == StrikeEffects.Powerup:
			_append_life_conditional_if_absent(target_player.strike_stat_boosts.conditional_life_powerups, amt, threshold)
		elif etype == StrikeEffects.Speedup:
			_append_life_conditional_if_absent(target_player.strike_stat_boosts.conditional_life_speedups, amt, threshold)
		if effect.get("and") is Dictionary:
			_register_life_conditional_chain(target_player, effect["and"], threshold)
	elif effect.get("and") is Dictionary:
		_scan_life_conditional_effect(target_player, effect["and"])

func _register_life_conditional_chain(target_player : Player, and_effect, threshold : int):
	if and_effect is Dictionary:
		var etype = and_effect.get("effect_type", "")
		var amt = and_effect.get("amount", 1)
		if etype == StrikeEffects.Powerup:
			_append_life_conditional_if_absent(target_player.strike_stat_boosts.conditional_life_powerups, amt, threshold)
		elif etype == StrikeEffects.Speedup:
			_append_life_conditional_if_absent(target_player.strike_stat_boosts.conditional_life_speedups, amt, threshold)
		if and_effect.get("and") is Dictionary:
			_register_life_conditional_chain(target_player, and_effect["and"], threshold)

func _register_life_conditional_boost(target_player : Player, effect_type : String, amount : int, threshold : int):
	var list = target_player.strike_stat_boosts.conditional_life_powerups if effect_type == "powerup" else target_player.strike_stat_boosts.conditional_life_speedups
	for entry in list:
		if entry.amount == amount and not entry.applied:
			entry.applied = true
			return
	if threshold >= 0:
		list.append({"amount": amount, "threshold": threshold, "applied": true})

func _recalc_life_conditional_boosts(target_player : Player):
	_queue_heiqiyihu_thresholds(target_player)
	var boosts = target_player.strike_stat_boosts
	for entry in boosts.conditional_life_powerups:
		var ok = target_player.life <= entry.threshold
		if ok and not entry.applied:
			target_player.add_power_bonus(entry.amount)
			entry.applied = true
		elif not ok and entry.applied:
			target_player.add_power_bonus(-entry.amount)
			entry.applied = false
	for entry in boosts.conditional_life_speedups:
		var ok = target_player.life <= entry.threshold
		if ok and not entry.applied:
			boosts.speed += entry.amount
			entry.applied = true
		elif not ok and entry.applied:
			boosts.speed -= entry.amount
			entry.applied = false

func get_gauge_cost(performing_player : Player, card, check_if_card_in_hand = false):
	var gauge_cost = card.definition['gauge_cost']
	if card.definition["id"] == "heiqiyihu_呼唤我的名字吧！" and active_strike \
	and not active_strike.heiqiyihu_guardian_records.is_empty():
		gauge_cost = 3
	var is_ex = active_strike.will_be_ex(performing_player)
	if 'gauge_cost_ex' in card.definition and is_ex:
		gauge_cost = card.definition['gauge_cost_ex']
	if 'gauge_cost_exceed' in card.definition and performing_player.exceeded:
		gauge_cost = card.definition['gauge_cost_exceed']

	if 'gauge_cost_reduction' in card.definition:
		match card.definition['gauge_cost_reduction']:
			"per_sealed_normal":
				var sealed_normals = performing_player.get_sealed_count_of_type("normal")
				gauge_cost = max(0, gauge_cost - sealed_normals)
			"per_card_copy_in_gauge":
				var card_id = card.definition['gauge_cost_reduction_card_id']
				for gauge_card in performing_player.gauge:
					if gauge_card.definition['id'] == card_id:
						gauge_cost -= 1
				gauge_cost = max(0, gauge_cost)
			"per_boost_in_play":
				var boosts_in_play = performing_player.get_boosts().size()
				gauge_cost = max(0, gauge_cost - boosts_in_play)
			"per_boost_in_play_of_type":
				var reduction_boost_type = card.definition.get("gauge_cost_reduction_boost_type", "")
				if reduction_boost_type != "":
					var typed_boosts_in_play = 0
					for boost_card in performing_player.get_boosts():
						if boost_card.definition.get("type", "") == reduction_boost_type:
							typed_boosts_in_play += 1
					gauge_cost = max(0, gauge_cost - typed_boosts_in_play)
			"free_if_ex":
				if is_ex:
					gauge_cost = 0
			"free_if_no_cards_in_hand":
				var hand_size = performing_player.hand.size()
				if check_if_card_in_hand and card in performing_player.hand:
					hand_size -= 1
				if hand_size == 0:
					gauge_cost = 0
			"free_if_no_deck_and_discard":
				if performing_player.deck.size() == 0 and performing_player.discards.size() == 0:
					gauge_cost = 0
			"free_if_4_specials_in_overdrive":
				var different_special_count = 0
				var found_specials = []
				for overdrive_card in performing_player.overdrive:
					if overdrive_card.definition['type'] == "special" and not overdrive_card.definition['id'] in found_specials:
						different_special_count += 1
						found_specials.append(overdrive_card.definition['id'])
				if different_special_count == 4:
					gauge_cost = 0
			"free_if_wild":
				if active_strike.get_player_wild_strike(performing_player):
					gauge_cost = 0
			"set_to_range_to_opponent":
				var range_to_opponent = performing_player.distance_to_opponent()
				gauge_cost = range_to_opponent

	return gauge_cost


func get_force_cost(performing_player : Player, card):
	var force_cost = card.definition['force_cost']
	if 'force_cost_crit' in card.definition and performing_player.strike_stat_boosts.critical:
		force_cost = card.definition['force_cost_crit']

	return force_cost

func get_alternative_life_cost(performing_player : Player, card):
	var alternative_life_cost = card.definition.get("alternative_life_cost", 0)
	if alternative_life_cost:
		var alternative_cost_requirement = card.definition.get("alternative_cost_requirement")
		if alternative_cost_requirement:
			match alternative_cost_requirement:
				"was_wild_swing":
					if not active_strike.get_player_wild_strike(performing_player):
						alternative_life_cost = 0
	return alternative_life_cost

func _resolve_pooky_reveal_after_paycost_wild_swing(performing_player : Player):
	if performing_player.deck_def.get("id") != "pooky":
		return
	var replacement_card = active_strike.get_player_card(performing_player)
	if replacement_card == null or replacement_card.definition.get("id", "") != "pooky_gamblingimin":
		return
	# In pay-cost wild swing branches, reveal effects are not re-entered automatically.
	for replacement_effect in get_all_effects_for_timing("on_strike_reveal", performing_player, replacement_card):
		add_remaining_effect(replacement_effect)
	do_remaining_effects(performing_player, active_strike.strike_state)

func ask_for_cost(performing_player, card, next_state):
	var gauge_cost = get_gauge_cost(performing_player, card)
	var force_cost = get_force_cost(performing_player, card)
	var alternative_life_cost = get_alternative_life_cost(performing_player, card)
	var card_has_printed_cost = card.definition['gauge_cost'] > 0 or card.definition['force_cost'] > 0
	var is_special = card.definition['type'] == "special"
	var is_ultra = card.definition['type'] == "ultra"
	var is_ex = active_strike.get_player_ex_card(performing_player) != null
	var gauge_discard_reminder = false
	if 'gauge_discard_reminder' in card.definition:
		gauge_discard_reminder = true

	if performing_player.strike_stat_boosts.may_generate_gauge_with_force and gauge_cost > 0:
		# Convert the gauge cost to a force cost.
		force_cost = gauge_cost
		gauge_cost = 0

	var card_in_invalid_list = card.definition['display_name'] in performing_player.cards_invalid_during_strike

	var invalidate_if_not_faceup = 'invalid_if_not_set_face_up' in card.definition and card.definition['invalid_if_not_set_face_up']
	var invalid_because_facedown = false
	if invalidate_if_not_faceup:
		if performing_player == active_strike.initiator:
			invalid_because_facedown = not active_strike.initiator_set_face_up
		else:
			invalid_because_facedown = not active_strike.defender_set_face_up

	var invalidate_if_not_set_from_boosts = 'must_set_from_boost' in card.definition and card.definition['must_set_from_boost']
	var invalid_because_not_set_from_boosts = false
	if invalidate_if_not_set_from_boosts:
		if performing_player == active_strike.initiator:
			invalid_because_not_set_from_boosts = not active_strike.initiator_set_from_boosts
		else:
			invalid_because_not_set_from_boosts = not active_strike.defender_set_from_boosts

	# Umina Spiraling Descent: opponent's attack is invalid if it matches the Dreamlands card.
	# Goes through the standard invalid flow (discard attack + wild swing) below instead of
	# blanking stats, matching the existing "invalid" keyword behavior (e.g. Galdred No Escape).
	var umina_sd_banning_player = _get_player(get_other_player(performing_player.my_id))
	var umina_sd_banned = ""
	if umina_sd_banning_player != null and umina_sd_banning_player.deck_def.get("id") == "umina" and umina_sd_banning_player.has_transform("umina_dark_thoughts"):
		umina_sd_banned = umina_sd_banning_player.get_umina_spiraling_target()
	var card_invalid_by_spiraling_descent = umina_sd_banned != "" and _is_spiraling_match(umina_sd_banned, card)
	var card_forced_invalid = (is_special and performing_player.specials_invalid) or card_in_invalid_list or invalid_because_facedown or invalid_because_not_set_from_boosts or card_invalid_by_spiraling_descent
	# Even if the cost can be paid for free, if the card has a cost wild swing is allowed.
	var was_wild_swing = active_strike.get_player_wild_strike(performing_player)
	var can_invalidate_ultra = is_ultra and performing_player.strike_stat_boosts.may_invalidate_ultras
	# Some cards explicitly remain valid when wild-swung (e.g. Lily Magic Bullet).
	var valid_when_wild_swing = 'valid_when_wild_swing' in card.definition and card.definition['valid_when_wild_swing']
	var can_invalidate_anyway = ((was_wild_swing and card_has_printed_cost) and not valid_when_wild_swing) or can_invalidate_ultra

	# Extra attacks live outside of lots of rules.
	# They cannot fail to pay the cost.
	if active_strike.extra_attack_in_progress:
		was_wild_swing = false
		card_forced_invalid = false
		can_invalidate_anyway = false

	if performing_player.can_pay_cost_with([], force_cost, gauge_cost, false, 0) and not card_forced_invalid and not can_invalidate_anyway:
		if active_strike.extra_attack_in_progress:
			active_strike.extra_attack_data.extra_attack_state = next_state
		else:
			active_strike.strike_state = next_state
	else:
		if not card_forced_invalid and performing_player.can_pay_cost(force_cost, gauge_cost, alternative_life_cost):
			change_game_state(Enums.GameState.GameState_PlayerDecision)
			decision_info.player = performing_player.my_id
			if was_wild_swing or can_invalidate_anyway:
				decision_info.type = Enums.DecisionType.DecisionType_PayStrikeCost_CanWild
			else:
				decision_info.type = Enums.DecisionType.DecisionType_PayStrikeCost_Required

			var still_use_gauge = card.definition['gauge_cost'] > 0 and not performing_player.strike_stat_boosts.may_generate_gauge_with_force
			var still_use_force = card.definition['force_cost'] > 0
			if gauge_cost > 0 or still_use_gauge:
				decision_info.limitation = "gauge"
				decision_info.cost = gauge_cost
				create_event(Enums.EventType.EventType_Strike_PayCost_Gauge, performing_player.my_id, card.id, "", gauge_discard_reminder, is_ex, alternative_life_cost)
			elif force_cost > 0 or still_use_force:
				decision_info.limitation = "force"
				decision_info.cost = force_cost
				create_event(Enums.EventType.EventType_Strike_PayCost_Force, performing_player.my_id, card.id, "", false, is_ex)
			else:
				assert(false, "ERROR: Expected card to have a force to pay")
			_append_log_full(Enums.LogType.LogType_Strike, performing_player, "正在选择牌以支付%s费用。" % decision_info.limitation)
		else:
			# Failed to pay the cost by default.
			_append_log_full(Enums.LogType.LogType_Strike, performing_player, "无法验证%s，因此其进行疯狂攻击。" % card.definition['display_name'])
			performing_player.invalidate_card(card)
			if performing_player == active_strike.initiator:
				if active_strike.initiator_ex_card != null:
					performing_player.add_to_discards(active_strike.initiator_ex_card)
					active_strike.initiator_ex_card = null
					performing_player.strike_stat_boosts.remove_ex()
			else:
				if active_strike.defender_ex_card != null:
					performing_player.add_to_discards(active_strike.defender_ex_card)
					active_strike.defender_ex_card = null
					performing_player.strike_stat_boosts.remove_ex()
			var new_wild_card = null
			while new_wild_card == null:
				performing_player.wild_strike(true);
				if game_over:
					return
				new_wild_card = active_strike.get_player_card(performing_player)
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "疯狂攻击%s！" % new_wild_card.definition['display_name'])
				is_special = new_wild_card.definition['type'] == "special"
				card_forced_invalid = (is_special and performing_player.specials_invalid)
				if umina_sd_banned != "" and _is_spiraling_match(umina_sd_banned, new_wild_card):
					_append_log_full(Enums.LogType.LogType_Strike, performing_player, "'s wild swing is invalid by Spiraling Descent, so they wild swing.")
					performing_player.invalidate_card(new_wild_card)
					new_wild_card = null
				elif card_forced_invalid:
					_append_log_full(Enums.LogType.LogType_Strike, performing_player, "其特殊技无效，因此其进行疯狂攻击。")
					performing_player.invalidate_card(new_wild_card)
					new_wild_card = null
			_resolve_pooky_reveal_after_paycost_wild_swing(performing_player)
			create_event(Enums.EventType.EventType_Strike_PayCost_Unable, performing_player.my_id, new_wild_card.id)

func do_hit_response_effects(offense_player : Player, defense_player : Player, incoming_damage : int, hit_response_state : Dictionary, next_state):
	# If more of these are added, need to sequence them to ensure all handled correctly.

	var defender_card = active_strike.get_player_card(defense_player)

	if not hit_response_state:
		hit_response_state['effects'] = get_all_effects_for_timing("when_hit", defense_player, defender_card)
		hit_response_state['effect_index'] = 0
	var effects = hit_response_state['effects']
	var effect_index = hit_response_state['effect_index']
	while effect_index < len(effects):
		var effect = effects[effect_index]
		effect_index += 1 # So it goes to the next effect when returning

		var first_time_only = 'first_time_only' in effect and effect['first_time_only']
		if first_time_only and effect in active_strike.when_hit_effects_processed:
			continue
		active_strike.when_hit_effects_processed.append(effect)
		var card_id = -1
		if 'card_id' in effect:
			card_id = effect['card_id']
		do_effect_if_condition_met(defense_player, card_id, effect, null)
		if game_state == Enums.GameState.GameState_PlayerDecision:
			hit_response_state['effect_index'] = effect_index
			return

		if game_over:
			change_game_state(Enums.GameState.GameState_GameOver)
			return

	hit_response_state.clear()
	if active_strike.extra_attack_in_progress:
		active_strike.extra_attack_data.extra_attack_state = next_state
	else:
		active_strike.strike_state = next_state

	if defense_player.strike_stat_boosts.when_hit_force_for_armor:
		change_game_state(Enums.GameState.GameState_PlayerDecision)
		decision_info.clear()
		decision_info.player = defense_player.my_id
		decision_info.type = Enums.DecisionType.DecisionType_ForceForArmor
		decision_info.choice_card_id = defender_card.id
		decision_info.limitation = defense_player.strike_stat_boosts.when_hit_force_for_armor
		decision_info.amount = 2
		create_event(Enums.EventType.EventType_Strike_ForceForArmor, defense_player.my_id, incoming_damage, "", offense_player.strike_stat_boosts.ignore_armor)

func log_boosts_in_play():
	var card_names = "None"
	var initiator_boosts = active_strike.initiator.get_boosts(false, true)
	if initiator_boosts.size() > 0:
		card_names = card_db.get_card_name(initiator_boosts[0].id)
		for i in range(1, initiator_boosts.size()):
			var card = initiator_boosts[i]
			card_names += ", " + card_db.get_card_name(card.id)
		_append_log_full(Enums.LogType.LogType_Strike, active_strike.initiator, "有生效中的持续性加成：%s" % _log_card_name(card_names))

	card_names = "None"
	var defender_boosts = active_strike.defender.get_boosts(false, true)
	if defender_boosts.size() > 0:
		card_names = card_db.get_card_name(defender_boosts[0].id)
		for i in range(1, defender_boosts.size()):
			var card = defender_boosts[i]
			card_names += ", " + card_db.get_card_name(card.id)
		_append_log_full(Enums.LogType.LogType_Strike, active_strike.defender, "有生效中的持续性加成：%s" % _log_card_name(card_names))

func continue_resolve_strike():
	if active_strike.in_setup:
		continue_setup_strike()
		return
	elif active_strike.extra_attack_in_progress:
		continue_extra_attack()
		return

	change_game_state(Enums.GameState.GameState_Strike_Processing)

	while true:
		if game_over:
			change_game_state(Enums.GameState.GameState_GameOver)
			break
		# Cards might change due to paying costs, so get them every loop.
		# Do NOT use before strike_determine_order and the StrikeState_DuringStrikeBonuses state has been called.
		var card1 = active_strike.get_card(1)
		var card2 = active_strike.get_card(2)
		var player1 = active_strike.get_player(1)
		var player2 = active_strike.get_player(2)

		if game_state == Enums.GameState.GameState_PlayerDecision:
			var player_name = get_player_name(decision_info.player)
			printlog("STRIKE: Pausing for decision %s %s" % [player_name, Enums.DecisionType.keys()[decision_info.type]])
			break
		if _begin_heiqiyihu_thresholds(active_strike.initiator, "strike"):
			break

		printlog("STRIKE: processing state %s " % [StrikeState.keys()[active_strike.strike_state]])
		match active_strike.strike_state:
			StrikeState.StrikeState_Initiator_RevealEffects:
				do_remaining_effects(active_strike.initiator, StrikeState.StrikeState_Defender_RevealEffects)
				if active_strike.strike_state == StrikeState.StrikeState_Defender_RevealEffects:
					active_strike.remaining_effect_list = get_all_effects_for_timing("on_strike_reveal", active_strike.defender, active_strike.defender_card)
			StrikeState.StrikeState_Defender_RevealEffects:
				do_remaining_effects(active_strike.defender, StrikeState.StrikeState_Initiator_PayCosts)
			StrikeState.StrikeState_Initiator_PayCosts:
				# Discard any EX cards
				if active_strike.initiator_ex_card != null:
					active_strike.initiator.add_to_discards(active_strike.initiator_ex_card)
				# Ask player to pay for this card if applicable.
				ask_for_cost(active_strike.initiator, active_strike.initiator_card, StrikeState.StrikeState_Defender_PayCosts)
			StrikeState.StrikeState_Defender_PayCosts:
				# Discard any EX cards
				if active_strike.defender_ex_card != null:
					active_strike.defender.add_to_discards(active_strike.defender_ex_card)
				# Ask player to pay for this card if applicable.
				ask_for_cost(active_strike.defender, active_strike.defender_card, StrikeState.StrikeState_DuringStrikeBonuses)
			StrikeState.StrikeState_DuringStrikeBonuses:
				active_strike.cards_in_play += [active_strike.initiator_card, active_strike.defender_card]
				_scan_life_conditional_boosts(active_strike.initiator)
				_scan_life_conditional_boosts(active_strike.defender)
				_append_log_full(Enums.LogType.LogType_Strike, active_strike.initiator, "以%s发起；%s以%s应战。" % [active_strike.initiator_card.definition['display_name'], active_strike.defender.name, active_strike.defender_card.definition['display_name']])
				log_boosts_in_play()
				var during_strike_failed_effects_initiator = []
				var during_strike_failed_effects_defender = []
				do_effects_for_timing(
					"during_strike",
					active_strike.initiator,
					active_strike.initiator_card,
					StrikeState.StrikeState_DuringStrikeBonuses,
					false,
					during_strike_failed_effects_initiator
				)
				# Should never be interrupted by player decisions.
				do_effects_for_timing(
					"during_strike",
					active_strike.defender,
					active_strike.defender_card,
					StrikeState.StrikeState_DuringStrikeBonuses,
					false,
					during_strike_failed_effects_defender
				)

				# Retry any effects that the condition failed but they might be true now!
				var check_failed_effects = true
				while check_failed_effects:
					# As long as there are effects being resolved, keep resolving them.
					check_failed_effects = false
					# Iterate through during_strike_failed_effects in reverse as we're removing items.
					for i in range(len(during_strike_failed_effects_initiator)-1, -1, -1):
						var effect = during_strike_failed_effects_initiator[i]
						if is_effect_condition_met(active_strike.initiator, effect, null):
							handle_strike_effect(active_strike.initiator_card.id, effect, active_strike.initiator)
							during_strike_failed_effects_initiator.erase(effect)
							check_failed_effects = true

					for i in range(len(during_strike_failed_effects_defender)-1, -1, -1):
						var effect = during_strike_failed_effects_defender[i]
						if is_effect_condition_met(active_strike.defender, effect, null):
							handle_strike_effect(active_strike.defender_card.id, effect, active_strike.defender)
							during_strike_failed_effects_defender.erase(effect)
							check_failed_effects = true

				active_strike.strike_state = StrikeState.StrikeState_Card1_Activation

				strike_determine_order()
			StrikeState.StrikeState_Card1_Activation:
				var card_name = card_db.get_card_name(card1.id)
				_append_log_full(Enums.LogType.LogType_Strike, player1, "先以%s进行战斗！" % _log_card_name(card_name))
				create_event(Enums.EventType.EventType_Strike_CardActivation, active_strike.get_player(1).my_id, card1.id)
				active_strike.strike_state = StrikeState.StrikeState_Card1_Before
				active_strike.remaining_effect_list = get_all_effects_for_timing("before", player1, card1)
			StrikeState.StrikeState_Card1_Before:
				if active_strike.unknown_khadath_used:
					active_strike.strike_state = StrikeState.StrikeState_Cleanup
					continue
				do_remaining_effects(player1, StrikeState.StrikeState_Card1_DetermineHit)
			StrikeState.StrikeState_Card1_DetermineHit:
				if active_strike.unknown_khadath_used:
					active_strike.strike_state = StrikeState.StrikeState_Cleanup
					continue
				var hit = determine_if_attack_hits(player1, player2, card1)
				if hit:
					active_strike.player1_hit = true
					active_strike.strike_state = StrikeState.StrikeState_Card1_Hit
					active_strike.remaining_effect_list = get_all_effects_for_timing("hit", player1, card1)
					if player1.deck_def.get("id") == "zsolt" and card1.definition.get("type") == "normal" and not player1.exceeded:
						active_strike.remaining_effect_list.append({
							"effect_type": StrikeEffects.Choice,
							"card_id": card1.id,
							"choice": [
								{ "effect_type": StrikeEffects.Advance, "amount": 1 },
								{ "effect_type": StrikeEffects.Retreat, "amount": 1 },
								{ "effect_type": StrikeEffects.Pass, "amount": 0 }
							],
							"character_effect": true,
							"hide_effect": false
						})
				else:
					active_strike.strike_state = StrikeState.StrikeState_Card1_After
					active_strike.remaining_effect_list = get_all_effects_for_timing("after", player1, card1)
			StrikeState.StrikeState_Card1_Hit:
				do_remaining_effects(player1, StrikeState.StrikeState_Card1_Hit_Response)
			StrikeState.StrikeState_Card1_Hit_Response:
				var incoming_damage = calculate_damage(player1, player2)
				do_hit_response_effects(player1, player2, incoming_damage, active_strike.hit_response_state, StrikeState.StrikeState_Card1_ApplyDamage)
			StrikeState.StrikeState_Card1_ApplyDamage:
				apply_damage(player1, player2)
				active_strike.strike_state = StrikeState.StrikeState_Card1_After
				active_strike.remaining_effect_list = get_all_effects_for_timing("after", player1, card1)
				if game_over:
					active_strike.strike_state = StrikeState.StrikeState_Cleanup
			StrikeState.StrikeState_Card1_After:
				do_remaining_effects(player1, StrikeState.StrikeState_Card2_Activation)
			StrikeState.StrikeState_Card2_Activation:
				var card_name = card_db.get_card_name(card2.id)
				if active_strike.player2_stunned:
					_append_log_full(Enums.LogType.LogType_Strike, player2, "被眩晕，因此%s不发动！" % _log_card_name(card_name))
					active_strike.strike_state = StrikeState.StrikeState_Cleanup
				else:
					_append_log_full(Enums.LogType.LogType_Strike, player2, "以%s应战！" % _log_card_name(card_name))
					create_event(Enums.EventType.EventType_Strike_CardActivation, active_strike.get_player(2).my_id, card2.id)
					active_strike.strike_state = StrikeState.StrikeState_Card2_Before
					active_strike.remaining_effect_list = get_all_effects_for_timing("before", player2, card2)
			StrikeState.StrikeState_Card2_Before:
				if active_strike.unknown_khadath_used:
					active_strike.strike_state = StrikeState.StrikeState_Cleanup
					continue
				do_remaining_effects(player2, StrikeState.StrikeState_Card2_DetermineHit)
			StrikeState.StrikeState_Card2_DetermineHit:
				if active_strike.unknown_khadath_used:
					active_strike.strike_state = StrikeState.StrikeState_Cleanup
					continue
				var hit = determine_if_attack_hits(player2, player1, card2)
				if hit:
					active_strike.player2_hit = true
					active_strike.strike_state = StrikeState.StrikeState_Card2_Hit
					active_strike.remaining_effect_list = get_all_effects_for_timing("hit", player2, card2)
					if player2.deck_def.get("id") == "zsolt" and card2.definition.get("type") == "normal" and not player2.exceeded:
						active_strike.remaining_effect_list.append({
							"effect_type": StrikeEffects.Choice,
							"card_id": card2.id,
							"choice": [
								{ "effect_type": StrikeEffects.Advance, "amount": 1 },
								{ "effect_type": StrikeEffects.Retreat, "amount": 1 },
								{ "effect_type": StrikeEffects.Pass, "amount": 0 }
							],
							"character_effect": true,
							"hide_effect": false
						})
				else:
					active_strike.strike_state = StrikeState.StrikeState_Card2_After
					active_strike.remaining_effect_list = get_all_effects_for_timing("after", player2, card2)
			StrikeState.StrikeState_Card2_Hit:
				do_remaining_effects(player2, StrikeState.StrikeState_Card2_Hit_Response)
			StrikeState.StrikeState_Card2_Hit_Response:
				var incoming_damage = calculate_damage(player2, player1)
				do_hit_response_effects(player2, player1, incoming_damage, active_strike.hit_response_state, StrikeState.StrikeState_Card2_ApplyDamage)
			StrikeState.StrikeState_Card2_ApplyDamage:
				apply_damage(player2, player1)
				active_strike.strike_state = StrikeState.StrikeState_Card2_After
				active_strike.remaining_effect_list = get_all_effects_for_timing("after", player2, card2)
				if game_over:
					active_strike.strike_state = StrikeState.StrikeState_Cleanup
			StrikeState.StrikeState_Card2_After:
				do_remaining_effects(player2, StrikeState.StrikeState_Cleanup)
			StrikeState.StrikeState_Cleanup:
				_append_log_full(Enums.LogType.LogType_Strike, null, "开始战斗整理阶段。")
				active_strike.strike_state = StrikeState.StrikeState_Cleanup_Player1Effects
				active_strike.remaining_effect_list = get_all_effects_for_timing("cleanup", active_strike.initiator, active_strike.initiator_card)
				strike_add_transform_option(active_strike.initiator, active_strike.initiator_card)
				strike_add_bleach_option(active_strike.initiator, active_strike.initiator_card)
			StrikeState.StrikeState_Cleanup_Player1Effects:
				do_remaining_effects(active_strike.initiator, StrikeState.StrikeState_Cleanup_Player1EffectsComplete)
			StrikeState.StrikeState_Cleanup_Player1EffectsComplete:
				active_strike.strike_state = StrikeState.StrikeState_Cleanup_Player2Effects
				active_strike.remaining_effect_list = get_all_effects_for_timing("cleanup", active_strike.defender, active_strike.defender_card)
				strike_add_transform_option(active_strike.defender, active_strike.defender_card)
				strike_add_bleach_option(active_strike.defender, active_strike.defender_card)
			StrikeState.StrikeState_Cleanup_Player2Effects:
				do_remaining_effects(active_strike.defender, StrikeState.StrikeState_EndOfStrike)
			StrikeState.StrikeState_EndOfStrike:
				_append_log_full(Enums.LogType.LogType_Strike, null, "开始战斗结束效果。")
				active_strike.strike_state = StrikeState.StrikeState_EndOfStrike_Player1Effects
				active_strike.remaining_effect_list = get_all_effects_for_timing("endofstrike", active_strike.initiator, active_strike.initiator_card)
			StrikeState.StrikeState_EndOfStrike_Player1Effects:
				do_remaining_effects(active_strike.initiator, StrikeState.StrikeState_EndOfStrike_Player1EffectsComplete)
			StrikeState.StrikeState_EndOfStrike_Player1EffectsComplete:
				active_strike.strike_state = StrikeState.StrikeState_EndOfStrike_Player2Effects
				active_strike.remaining_effect_list = get_all_effects_for_timing("endofstrike", active_strike.defender, active_strike.defender_card)
			StrikeState.StrikeState_EndOfStrike_Player2Effects:
				do_remaining_effects(active_strike.defender, StrikeState.StrikeState_Cleanup_Complete)
			StrikeState.StrikeState_Cleanup_Complete:
				_umina_restore_shadow_chorus_definitions(active_strike.initiator)
				_umina_restore_shadow_chorus_definitions(active_strike.defender)
				# Handle cleanup effects that cause attack cards to leave play before the standard timing
				handle_strike_attack_cleanup(active_strike.initiator, active_strike.initiator_card)
				handle_strike_attack_cleanup(active_strike.defender, active_strike.defender_card)

				# Remove any Reading effects
				player1.reading_card_id = ""
				player2.reading_card_id = ""

				# Cleanup any continuous boosts.
				for record in active_strike.heiqiyihu_guardian_records:
					if record.has("strike_cleanup_destination"):
						_move_heiqiyihu_virtual_source(record["source_id"], record["strike_cleanup_destination"])
				active_strike.initiator.cleanup_continuous_boosts()
				active_strike.defender.cleanup_continuous_boosts()

				# Cleanup attacks, if hit, move card to gauge, otherwise move to discard.
				if active_strike.initiator_card in active_strike.cards_in_play:
					strike_send_attack_to_discard_or_gauge(active_strike.initiator, active_strike.initiator_card)
				if active_strike.defender_card in active_strike.cards_in_play:
					strike_send_attack_to_discard_or_gauge(active_strike.defender, active_strike.defender_card)
				
				# Process any deferred extra attack cards
				for deferred in active_strike.deferred_extra_attack_cards:
					var ea_card = deferred["card"]
					var ea_player = deferred["player"]
					var ea_hit = deferred["hit"]
					if ea_card not in active_strike.cards_in_play:
						continue
					# Only allow transform for cards with transform boost
					var ea_transform = false
					if ea_card.definition.get("boost", {}).get("boost_type") == "transform":
						ea_transform = active_strike.extra_attack_data.zsolt_extra_transform \
								or ea_player.strike_stat_boosts.move_strike_to_transforms
					if ea_transform:
						_append_log_full(Enums.LogType.LogType_CardInfo, ea_player, "transforms extra attack %s." % _log_card_name(ea_card.definition['display_name']))
						if not ea_player.add_to_transforms(ea_card):
							if ea_hit or active_strike.extra_attack_data.extra_attack_always_go_to_gauge:
								ea_player.add_to_gauge(ea_card)
							else:
								ea_player.add_to_discards(ea_card)
					elif ea_hit or active_strike.extra_attack_data.extra_attack_always_go_to_gauge:
						ea_player.add_to_gauge(ea_card)
					else:
						ea_player.add_to_discards(ea_card)
					active_strike.cards_in_play.erase(ea_card)
				active_strike.deferred_extra_attack_cards.clear()

				assert(active_strike.cards_in_play.size() == 0,
						"ERROR: %s still in play after strike should have been cleaned up" %
								", ".join(active_strike.cards_in_play.map(
										func (card): return "%s" % card)))

				# Remove all stat boosts.
				player.strike_stat_boosts.clear()
				opponent.strike_stat_boosts.clear()
				if player.deck_def.get("id") == "minato" and player.exceeded and player.minato_seal_power_bonus > 0:
					player.minato_seal_power_bonus = 0
				if opponent.deck_def.get("id") == "minato" and opponent.exceeded and opponent.minato_seal_power_bonus > 0:
					opponent.minato_seal_power_bonus = 0
				player.gauge_spent_this_strike = 0
				opponent.gauge_spent_this_strike = 0
				player.gauge_cards_spent_this_strike = []
				opponent.gauge_cards_spent_this_strike = []

				# Cleanup UI
				create_event(Enums.EventType.EventType_Strike_Cleanup, player1.my_id, -1)

				var active_turn_player_ref = _get_player(active_turn_player)
				active_strike = null
				if game_over:
					change_game_state(Enums.GameState.GameState_GameOver)
				elif active_character_action or active_exceed or active_change_cards or active_prepare or active_special_draw_effect or active_post_action_effect:
					set_player_action_processing_state()
					continue_player_action_resolution(_get_player(active_turn_player))
				else:
					active_turn_player_ref.skip_end_of_turn_draw = true
					start_end_turn()
				break

	if game_state == Enums.GameState.GameState_PlayerDecision and decision_info.type == Enums.DecisionType.DecisionType_ForceBoostSustainTopdeck:
		do_topdeck_boost()
	elif game_state == Enums.GameState.GameState_PlayerDecision and decision_info.type == Enums.DecisionType.DecisionType_ForceBoostSustainTopDiscard:
		do_discard_boost()

func strike_add_transform_option(performing_player : Player, card : GameCard):
	assert(active_strike)

	if performing_player.has_card_name_in_zone(card, "transform"):
		return

	# Umina Shadow Chorus：影分身只是临时套用了幻梦境那张牌的定义，它本身不是转化卡。
	# 因此即使复制到的是转化卡，也不能让影分身去转化 —— 否则没转化的 Shadow Chorus
	# 会被放进转化区，之后「同名卡」相关判定（击晕免疫 / 螺旋降下 / 读心）就全乱了。
	# （定义要到 Cleanup_Complete 才还原，那时已分辨不出来，故必须在此拦截。）
	if performing_player.umina_shadow_chorus_restore.has(card.id):
		return

	var hit = active_strike.player1_hit
	if active_strike.get_player(2) == performing_player:
		hit = active_strike.player2_hit

	if hit and (card.definition['boost']['boost_type'] == "transform" or (performing_player.deck_def.get("id") == "tournelouse" and card.definition['type'] == "normal" and not performing_player.exceeded)):
		var added_effect = {
			"card_id": -1,
			"effect_type": StrikeEffects.Choice,
			"override_description": "选择是否转化%s" % card.definition['display_name'],
			StrikeEffects.Choice: [
				{
					"effect_type": StrikeEffects.TransformAttack,
					"card_name": card.definition['display_name'],
					"card_id": card.id
				},
				{ "effect_type": StrikeEffects.Pass }
			]
		}
		add_remaining_effect(added_effect)

func strike_add_bleach_option(performing_player : Player, card : GameCard):
	assert(active_strike)
	if not performing_player.has_bleach_zone():
		return
	if performing_player.deck_def.get("id", "") in ["dongshilang", "yuanliuzhai"]:
		return
	if performing_player.deck_def.get("base_id", performing_player.deck_def.get("id", "")) == "heiqiyihu":
		# Guardians are obtained only by this character's explicit effects,
		# not by the shared special/ultra hit destination option.
		return
	if performing_player.strike_stat_boosts.seal_attack_on_cleanup:
		return
	var hit = active_strike.player1_hit
	if active_strike.get_player(2) == performing_player:
		hit = active_strike.player2_hit
	if not hit or card.definition.get("type") not in ["special", "ultra"]:
		return
	add_remaining_effect({
		"card_id": card.id,
		"effect_type": StrikeEffects.Choice,
		StrikeEffects.Choice: [
			{
				"_choice_text": "加入%s" % performing_player.get_bleach_zone_name(),
				"effect_type": StrikeEffects.MoveStrikeToBleach,
				"card_id": card.id
			},
			{
				"_choice_text": "加入怒气区",
				"effect_type": StrikeEffects.Pass
			}
		]
	})

func handle_strike_attack_immediate_removal(performing_player : Player):
	var other_player = _get_player(get_other_player(performing_player.my_id))
	var card = active_strike.get_player_card(performing_player)
	_restore_double_illusion_definition(performing_player, card)
	var card_name = card.definition['display_name']

	# NOTE: Currently, active strike will still have this card set as the active_strike player card.
	# Potentially removing that may break things.
	# As long as all state/stats is correctly updated though, it should be okay
	# unless some card effect that references something on that card and it should
	# behave differently if the strike card is gone.

	change_stats_when_attack_leaves_play(performing_player)

	if performing_player.strike_stat_boosts.discard_attack_now or performing_player.strike_stat_boosts.discard_attack_now_for_lightningrod:
		# No logline since there will be a log about this in the lightning rod effect.
		performing_player.add_to_discards(card)
		active_strike.cards_in_play.erase(card)
	elif performing_player.strike_stat_boosts.move_strike_to_opponent_gauge:
		_append_log_full(Enums.LogType.LogType_CardInfo, other_player, "将对手的攻击%s加入其怒气！" % _log_card_name(card_name))
		other_player.add_to_gauge(card)
		active_strike.cards_in_play.erase(card)
	elif performing_player.strike_stat_boosts.return_attack_to_hand:
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将其攻击%s返回手牌。" % _log_card_name(card_name))
		performing_player.add_to_hand(card, true)
		active_strike.cards_in_play.erase(card)
	elif performing_player.strike_stat_boosts.move_strike_to_opponent_boosts:
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "的攻击%s被设为%s的持续性加成。" % [_log_card_name(card_name), other_player.name])
		other_player.add_to_continuous_boosts(card)
		other_player.sustained_boosts.append(card.id)
		active_strike.cards_in_play.erase(card)
	elif performing_player.strike_stat_boosts.move_strike_to_boosts:
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "的攻击%s被设为持续性加成。" % _log_card_name(card_name))
		performing_player.add_to_continuous_boosts(card)
		if performing_player.strike_stat_boosts.move_strike_to_boosts_sustain:
			performing_player.sustained_boosts.append(card.id)
		active_strike.cards_in_play.erase(card)
	elif performing_player.strike_stat_boosts.attack_to_topdeck_on_cleanup:
		# Opponent's cards can never enter your deck or discard pile. If this
		# attack card belongs to the opponent (e.g. borrowed by renea / eugenia /
		# umina), discard it to the OWNER's discard pile instead of topdecking it.
		if card.owner_id != performing_player.my_id:
			var owner_player = _get_player(card.owner_id)
			if owner_player != null:
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将对手的攻击%s弃置到其弃牌堆。" % _log_card_name(card_name))
				owner_player.add_to_discards(card)
			else:
				performing_player.add_to_discards(card)
		else:
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将其攻击%s返回到牌库顶。" % _log_card_name(card_name))
			performing_player.add_to_top_of_deck(card, true)
		active_strike.cards_in_play.erase(card)
	elif performing_player.strike_stat_boosts.always_add_to_overdrive:
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将其攻击%s加入超载。" % _log_card_name(card_name))
		performing_player.add_to_overdrive(card)
		active_strike.cards_in_play.erase(card)
	else:
		assert(false, "ERROR: Unexpected call to attack removal but state doesn't match.")

func handle_strike_attack_cleanup(performing_player : Player, card):
	_restore_double_illusion_definition(performing_player, card)
	var card_name = card.definition['display_name']
	var set_from_face_attack = false
	if performing_player == active_strike.initiator:
		set_from_face_attack = active_strike.initiator_set_from_face_attack
	else:
		set_from_face_attack = active_strike.defender_set_from_face_attack

	if card not in active_strike.cards_in_play:
		# Already removed from play mid-strike
		return

	if set_from_face_attack:
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将其攻击%s放回待用。" % _log_card_name(card_name))
		performing_player.add_to_set_aside(card)
		create_event(Enums.EventType.EventType_SetCardAside, performing_player.my_id, card.id)
		active_strike.cards_in_play.erase(card)
	elif performing_player.is_set_aside_card(card.id):
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将其攻击%s移出待用。" % _log_card_name(card_name))
		create_event(Enums.EventType.EventType_SetCardAside, performing_player.my_id, card.id)
		active_strike.cards_in_play.erase(card)
	elif performing_player.strike_stat_boosts.seal_attack_on_cleanup:
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "封印其攻击%s。" % _log_card_name(card_name))
		do_seal_effect(performing_player, card.id, "")
		active_strike.cards_in_play.erase(card)
	elif performing_player.strike_stat_boosts.discard_attack_on_cleanup:
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "弃置其攻击%s。" % _log_card_name(card_name))
		performing_player.add_to_discards(card)
		active_strike.cards_in_play.erase(card)
	elif performing_player.strike_stat_boosts.return_attack_to_hand:
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将其攻击%s返回手牌。" % _log_card_name(card_name))
		performing_player.add_to_hand(card, true)
		active_strike.cards_in_play.erase(card)
	elif performing_player.strike_stat_boosts.move_strike_to_boosts:
		# 整理阶段把攻击卡改为持续性加成（如 Noelle 设置炸弹：未命中则重新设置）。
		# 与 handle_strike_attack_immediate_removal 中的同名分支保持一致。
		# 注意本函数在 cleanup_continuous_boosts() 之前执行，维持标记可正常生效。
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将其攻击%s设为持续性加成。" % _log_card_name(card_name))
		performing_player.add_to_continuous_boosts(card)
		if performing_player.strike_stat_boosts.move_strike_to_boosts_sustain:
			performing_player.sustained_boosts.append(card.id)
		active_strike.cards_in_play.erase(card)

	# 从加成区设置攻击的卡彻底离场（回手/封印/弃牌/移出）后，移除场上的攻击源图标。
	# move_strike_to_boosts（重新变加成）除外——卡仍在场上，攻击源图标继续保留。
	if performing_player.get_boost_location(card.id) != -1 \
			and not performing_player.strike_stat_boosts.move_strike_to_boosts:
		performing_player.remove_boost_in_location(card.id)

func strike_send_attack_to_discard_or_gauge(performing_player : Player, card):
	_restore_double_illusion_definition(performing_player, card)
	var hit = active_strike.player1_hit
	var stat_boosts = performing_player.strike_stat_boosts
	if active_strike.get_player(2) == performing_player:
		hit = active_strike.player2_hit
	# Extra attack card: use extra_attack_hit
	if active_strike.extra_attack_data and active_strike.extra_attack_data.extra_attack_card == card:
		hit = active_strike.extra_attack_data.extra_attack_hit
	var card_name = card.definition['display_name']

	if performing_player.strike_stat_boosts.move_strike_to_transforms:
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "转化其攻击%s。" % _log_card_name(card_name))
		if performing_player.deck_def.get("id") == "tournelouse" and card.definition['type'] == "normal" and not performing_player.exceeded:
			card.definition["replaced_boost"] = card.definition["boost"].duplicate(true)
			card.definition["boost"] = {
				"boost_type": "transform",
				"force_cost": -1,
				"cancel_cost": -1,
				"display_name": card.definition['display_name'],
				"effects": [{
					"timing": "during_strike",
					"condition": "is_special_or_ultra_attack",
					"effect_type": StrikeEffects.Powerup,
					"amount": 1,
					"character_effect": true
				}],
				"description": "Transformed normal: +1 Power to Special/Ultra attacks"
			}
		if not performing_player.add_to_transforms(card):
			if hit or stat_boosts.always_add_to_gauge:
				performing_player.add_to_gauge(card)
			else:
				performing_player.add_to_discards(card)
	elif stat_boosts.move_strike_to_bleach:
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将其攻击%s加入%s。" % [_log_card_name(card_name), performing_player.get_bleach_zone_name()])
		performing_player.add_to_bleach(card)
	elif hit or stat_boosts.always_add_to_gauge:
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将其攻击%s加入怒气。" % _log_card_name(card_name))
		performing_player.add_to_gauge(card)
	else:
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "弃置其攻击%s。" % _log_card_name(card_name))
		performing_player.add_to_discards(card)
	active_strike.cards_in_play.erase(card)
	# 从加成区设置攻击的卡彻底离场（进怒气/弃牌）后，移除场上的攻击源图标。
	if performing_player.get_boost_location(card.id) != -1:
		performing_player.remove_boost_in_location(card.id)

func _restore_double_illusion_definition(performing_player : Player, card : GameCard) -> void:
	if performing_player.deck_def.get("id") == "double" and performing_player.double_illusion_original_definition != null:
		card.definition = performing_player.double_illusion_original_definition
		performing_player.double_illusion_original_definition = null

func begin_extra_attack(performing_player : Player, card_id : int):
	assert(active_strike)
	# The player is mid-strike and playing an extra attack card.
	# These are the steps of extra attack:
	# * Pay its cost.
	# * Put it into play, gaining any Armor, Guard, and passive effects on it.
	# * Perform its Before effects, then check its Range.
	# * If it hit, perform its Hit effects.
	# * If it hit, deal damage equal to its printed Power.
	# * Perform its After effects.
	# * At the end of the Strike, if the additional attack hit, add it to your Gauge. Otherwise, discard it.
	# * Note that bonuses and effects that apply to your attack (e.g., Continuous Boost effects such as "+2 Power") only apply to your initial attack unless they specify "Your attacks have [...]" (as the Graviton does).
	#
	# Since the strike is still active, there is a hook in continue_resolve_strike
	# that goes to continue_extra_attack if there is an extra attack active.
	# This way all things that work during strikes will also work during extra attacks.
	#
	# As you gain passive effects, those will go straight into strike_stat_boosts.
	# However, for damage calculation, subtract the saved power bonus as that does not apply.
	# Also, for hit calculation range bonuses do not apply.
	#

	# Also extra attacks can happen inside of extra attacks, so do a linked list thing to handle that
	if active_strike.extra_attack_in_progress:
		var new_extra_attack_data = ExtraAttackData.new()
		new_extra_attack_data.extra_attack_parent = active_strike.extra_attack_data
		active_strike.extra_attack_data = new_extra_attack_data
	else:
		active_strike.extra_attack_in_progress = true
		# Save zsolt_max_damage before reset (PlayAttackFromHand may have set it)
		# Don't save zsolt_extra_transform — each extra attack's transform choice is independent
		var saved_zsolt_max_damage = active_strike.extra_attack_data.zsolt_max_damage_1
		active_strike.extra_attack_data.reset()
		active_strike.extra_attack_data.zsolt_max_damage_1 = saved_zsolt_max_damage
	active_strike.extra_attack_data.extra_attack_card = card_db.get_card(card_id)
	active_strike.extra_attack_data.extra_attack_player = performing_player
	active_strike.extra_attack_data.extra_attack_previous_attack_power_bonus = performing_player.strike_stat_boosts.power
	active_strike.extra_attack_data.extra_attack_previous_attack_speed_bonus = performing_player.strike_stat_boosts.speed
	active_strike.extra_attack_data.extra_attack_previous_attack_range_effects = performing_player.strike_stat_boosts.range_effects
	# Zsolt awaken: skip cost payment
	if active_strike.extra_attack_data.zsolt_max_damage_1:
		active_strike.extra_attack_data.extra_attack_state = ExtraAttackState.ExtraAttackState_DuringStrikeBonuses
	else:
		active_strike.extra_attack_data.extra_attack_state = ExtraAttackState.ExtraAttackState_PayCosts
	active_strike.extra_attack_data.extra_attack_hit = false

	# Other relevant passives that need to be undone.
	# If other extra attack characters are added, consider what else might be needed.
	# For example: If an extra attack character can have positive power bonus boosts, those need to be removed too.
	performing_player.strike_stat_boosts.ignore_armor = false
	performing_player.strike_stat_boosts.ignore_guard = false

	# Extra attacks are unaffected by the attack_does_not_hit effect from hitting Nirvana or the effect on Block.
	performing_player.strike_stat_boosts.attack_does_not_hit = false
	performing_player.strike_stat_boosts.overwrite_total_power = false

	# This can happen with more After effects to resolve.
	# This should be fine as we use a different remaining effects list.
	# Also, nothing that uses active_strike.effects_resolved_in_timing should be active.
	# If a new timing is added for extra attacks, then more state may need to be preserved.
	active_strike.effects_resolved_in_timing = 0
	active_strike.extra_attack_data.extra_attack_remaining_effects = []

	# Remove the card from the hand, it is now in the striking area.
	# Notify via an event.
	performing_player.remove_card_from_hand(card_id, true, false)
	create_event(Enums.EventType.EventType_Strike_Started_ExtraAttack, performing_player.my_id, card_id, "")

	var card_name = card_db.get_card_name(card_id)
	_append_log_full(Enums.LogType.LogType_Strike, performing_player, "以%s进行一次额外攻击。" % [_log_card_name(card_name)])

	continue_resolve_strike()

func continue_extra_attack():
	change_game_state(Enums.GameState.GameState_Strike_Processing)

	var attacker_player = active_strike.extra_attack_data.extra_attack_player
	var attacker_card = active_strike.extra_attack_data.extra_attack_card
	var defender_player = _get_player(get_other_player(attacker_player.my_id))

	while true:
		if game_over:
			change_game_state(Enums.GameState.GameState_GameOver)
			break

		if game_state == Enums.GameState.GameState_PlayerDecision:
			var player_name = get_player_name(decision_info.player)
			printlog("EXTRA ATTACK: Pausing for decision %s %s" % [player_name, Enums.DecisionType.keys()[decision_info.type]])
			break

		printlog("EXTRA ATTACK: processing state %s " % [ExtraAttackState.keys()[active_strike.extra_attack_data.extra_attack_state]])
		match active_strike.extra_attack_data.extra_attack_state:
			ExtraAttackState.ExtraAttackState_PayCosts:
				# Ask player to pay for this card if applicable.
				ask_for_cost(attacker_player, attacker_card, ExtraAttackState.ExtraAttackState_DuringStrikeBonuses)
			ExtraAttackState.ExtraAttackState_DuringStrikeBonuses:
				do_effects_for_timing("during_strike", attacker_player, attacker_card, ExtraAttackState.ExtraAttackState_Activation, true)
			ExtraAttackState.ExtraAttackState_Activation:
				# Gain armor/guard from the card.
				attacker_player.strike_stat_boosts.armor += get_card_stat(attacker_player, attacker_card, "armor")
				attacker_player.strike_stat_boosts.guard += get_card_stat(attacker_player, attacker_card, "guard")
				# Do the attack starting at Before.
				active_strike.extra_attack_data.extra_attack_state = ExtraAttackState.ExtraAttackState_Before
				active_strike.extra_attack_data.extra_attack_remaining_effects = get_all_effects_for_timing("before", attacker_player, attacker_card, true, true)
			ExtraAttackState.ExtraAttackState_Before:
				do_remaining_effects(attacker_player, ExtraAttackState.ExtraAttackState_DetermineHit)
			ExtraAttackState.ExtraAttackState_DetermineHit:
				var hit = determine_if_attack_hits(attacker_player, defender_player, attacker_card)
				if hit:
					active_strike.extra_attack_data.extra_attack_hit = true
					active_strike.extra_attack_data.extra_attack_state = ExtraAttackState.ExtraAttackState_Hit
					active_strike.extra_attack_data.extra_attack_remaining_effects = get_all_effects_for_timing("hit", attacker_player, attacker_card, true, true)
				else:
					active_strike.extra_attack_data.extra_attack_state = ExtraAttackState.ExtraAttackState_After
					active_strike.extra_attack_data.extra_attack_remaining_effects = get_all_effects_for_timing("after", attacker_player, attacker_card, true, true)
			ExtraAttackState.ExtraAttackState_Hit:
				do_remaining_effects(attacker_player, ExtraAttackState.ExtraAttackState_Hit_Response)
			ExtraAttackState.ExtraAttackState_Hit_Response:
				var incoming_damage = calculate_damage(attacker_player, defender_player)
				do_hit_response_effects(attacker_player, defender_player, incoming_damage, active_strike.extra_attack_data.extra_attack_hit_response_state, ExtraAttackState.ExtraAttackState_Hit_ApplyDamage)
			ExtraAttackState.ExtraAttackState_Hit_ApplyDamage:
				apply_damage(attacker_player, defender_player)
				active_strike.extra_attack_data.extra_attack_state = ExtraAttackState.ExtraAttackState_After
				active_strike.extra_attack_data.extra_attack_remaining_effects = get_all_effects_for_timing("after", attacker_player, attacker_card, true, true)
				if game_over:
					active_strike.strike_state = ExtraAttackState.ExtraAttackState_Cleanup
			ExtraAttackState.ExtraAttackState_After:
				do_remaining_effects(attacker_player, ExtraAttackState.ExtraAttackState_Cleanup)
			ExtraAttackState.ExtraAttackState_Cleanup:
				active_strike.extra_attack_data.extra_attack_state = ExtraAttackState.ExtraAttackState_CleanupEffects
				active_strike.extra_attack_data.extra_attack_remaining_effects = get_all_effects_for_timing("cleanup", attacker_player, attacker_card, true, true)
				# Extra attack transform option (skip if transform zone already has same name)
				if attacker_card.definition['boost']['boost_type'] == "transform" \
						and active_strike.extra_attack_data.extra_attack_hit \
						and not attacker_player.has_card_name_in_zone(attacker_card, "transform"):
					var added_effect = {
						"card_id": -1,
						"effect_type": StrikeEffects.Choice,
						"choice": [
							{ "effect_type": StrikeEffects.ZsoltTransformExtra, "card_name": attacker_card.definition['display_name'], "card_id": attacker_card.id, "_choice_text": "转化" },
							{ "effect_type": StrikeEffects.Pass }
						]
					}
					active_strike.extra_attack_data.extra_attack_remaining_effects.append(added_effect)
			ExtraAttackState.ExtraAttackState_CleanupEffects:
				do_remaining_effects(attacker_player, ExtraAttackState.ExtraAttackState_Complete)
			ExtraAttackState.ExtraAttackState_Complete:
				var card_name = attacker_card.definition['display_name']
				# Zsolt: defer to main strike cleanup (needed for transform choice)
				if active_strike.extra_attack_data.zsolt_max_damage_1:
					if attacker_card not in active_strike.cards_in_play:
						active_strike.cards_in_play.append(attacker_card)
					if attacker_player.strike_stat_boosts.move_strike_to_transforms:
						_append_log_full(Enums.LogType.LogType_CardInfo, attacker_player, "will transform their extra attack %s." % _log_card_name(card_name))
					_append_log_full(Enums.LogType.LogType_CardInfo, attacker_player, "额外攻击造成最大1点伤害。")
					# Clear awaken offered flag so second extra attack can trigger
					attacker_player.zsolt_awaken_offered = false
					# Record for cleanup processing (handles multiple extra attacks)
					var deferred_entry = {
						"card": attacker_card,
						"player": attacker_player,
						"hit": active_strike.extra_attack_data.extra_attack_hit
					}
					active_strike.deferred_extra_attack_cards.append(deferred_entry)
				else:
					# Non-Zsolt: immediate cleanup (original behavior)
					if active_strike.extra_attack_data.extra_attack_hit or active_strike.extra_attack_data.extra_attack_always_go_to_gauge:
						_append_log_full(Enums.LogType.LogType_CardInfo, attacker_player, "adds their extra attack %s to gauge." % _log_card_name(card_name))
						attacker_player.add_to_gauge(attacker_card)
					else:
						_append_log_full(Enums.LogType.LogType_CardInfo, attacker_player, "弃置其额外攻击%s。" % _log_card_name(card_name))
						attacker_player.add_to_discards(attacker_card)
					active_strike.cards_in_play.erase(attacker_card)

				# Finally, resume the original strike (unless there was another extra attack to deal with).
				if game_over:
					change_game_state(Enums.GameState.GameState_GameOver)
				else:
					if active_strike.extra_attack_data.extra_attack_parent:
						active_strike.extra_attack_data = active_strike.extra_attack_data.extra_attack_parent
						# surely this won't change the attacking player
						attacker_card = active_strike.extra_attack_data.extra_attack_card
						continue
					else:
						active_strike.extra_attack_in_progress = false
						continue_resolve_strike()
				break

func determine_if_attack_hits(attacker_player : Player, defender_player : Player, card : GameCard):
	var card_name = card_db.get_card_name(card.id)
	if attacker_player.strike_stat_boosts.calculate_range_from_buddy:
		var buddy_location = attacker_player.get_buddy_location(attacker_player.strike_stat_boosts.calculate_range_from_buddy_id)
		var buddy_name = attacker_player.get_buddy_name(attacker_player.strike_stat_boosts.calculate_range_from_buddy_id)
		_append_log_full(Enums.LogType.LogType_Strike, null, "距离检查：从%s的%s（格子%s）攻击至%s（格子%s）。" % [attacker_player.name, buddy_name, buddy_location, defender_player.name, defender_player.arena_location])
	elif attacker_player.strike_stat_boosts.calculate_range_from_space != -1:
		_append_log_full(Enums.LogType.LogType_Strike, null, "距离检查：%s从格子%s攻击至%s（格子%s）。" % [attacker_player.name, attacker_player.strike_stat_boosts.calculate_range_from_space, defender_player.name, defender_player.arena_location])
	else:
		_append_log_full(Enums.LogType.LogType_Strike, null, "距离检查：从%s（格子%s）攻击至%s（格子%s）。" % [attacker_player.name, attacker_player.arena_location, defender_player.name, defender_player.arena_location])

	if in_range(attacker_player, defender_player, card, true) and not card.definition['id'] in attacker_player.cards_that_will_not_hit:
		_append_log_full(Enums.LogType.LogType_Strike, attacker_player, "以%s命中！" % _log_card_name(card_name))
		# Explicit hit event so the UI can play hit-only closeups (ultras) at
		# the right moment: after the hit is confirmed but before hit effects
		# resolve, and never on a miss.
		create_event(Enums.EventType.EventType_Strike_Hit, attacker_player.my_id, card.id)
		return true
	else:
		var extra_details = ""
		if card.definition['id'] in attacker_player.cards_that_will_not_hit:
			extra_details = "the named card "
		_append_log_full(Enums.LogType.LogType_Strike, attacker_player, "以%s%s未命中！" % [extra_details, _log_card_name(card_name)])
		create_event(Enums.EventType.EventType_Strike_Miss, attacker_player.my_id, 0)
		return false

func do_topdeck_boost():
	var performing_player = _get_player(active_strike.remaining_forced_boosts_player_id)
	performing_player.sustain_next_boost = active_strike.remaining_forced_boosts_sustaining
	active_strike.remaining_forced_boosts -= 1

	performing_player.draw(1, true)
	change_game_state(Enums.GameState.GameState_PlayerDecision)
	decision_info.type = Enums.DecisionType.DecisionType_BoostNow
	# 恢复跨段保留的免费标记（海蒂 匕首风暴：第 2 段起仍免费）。
	decision_info.ignore_costs = active_strike.remaining_forced_boosts_ignore_costs
	do_boost(performing_player, performing_player.hand[performing_player.hand.size()-1].id)

func do_chosen_topdeck_boost():
	# Plays the next card the player picked out of the top cards they looked at
	# (Heidi 匕首风暴·三倍插入). The cards are already in hand, so unlike
	# do_topdeck_boost() nothing needs to be drawn here.
	var card_ids = active_strike.remaining_forced_boosts_card_ids
	if card_ids.is_empty():
		return
	var card_id = card_ids.pop_front()
	var performing_player = _get_player(active_strike.remaining_forced_boosts_player_id)
	performing_player.sustain_next_boost = active_strike.remaining_forced_boosts_sustaining
	active_strike.remaining_forced_boosts -= 1

	change_game_state(Enums.GameState.GameState_PlayerDecision)
	decision_info.clear()
	decision_info.type = Enums.DecisionType.DecisionType_BoostNow
	decision_info.ignore_costs = active_strike.remaining_forced_boosts_ignore_costs
	do_boost(performing_player, card_id)

func do_discard_boost():
	# 强制打出状态：战斗中存于 strike，否则存于 active_boost（海蒂 机械天才
	# 是无战斗上下文的即时加成）。
	var forced_container = null
	if active_strike:
		forced_container = active_strike
	else:
		forced_container = active_boost
	var performing_player = _get_player(forced_container.remaining_forced_boosts_player_id)
	performing_player.sustain_next_boost = forced_container.remaining_forced_boosts_sustaining
	forced_container.remaining_forced_boosts -= 1

	var boost_card_id = performing_player.get_top_continuous_boost_in_discard()
	if boost_card_id == -1:
		# 弃牌堆已无可打出的加成，干净跳过、继续解析。
		performing_player.sustain_next_boost = false
		change_game_state(Enums.GameState.GameState_Boost_Processing)
		decision_info.clear()
		continue_player_action_resolution(performing_player)
		return
	var boost_cost = card_db.get_card(boost_card_id).definition['boost'].get('force_cost', 0)
	if forced_container.remaining_forced_boosts_ignore_costs:
		_play_forced_discard_boost(performing_player, boost_card_id, true)
		return
	if boost_cost <= 0 or performing_player.can_pay_cost_with([], boost_cost, 0, true, 0):
		# 免费，或免费力足够：直接打出。
		_play_forced_discard_boost(performing_player, boost_card_id)
		return
	# 该持续加成有费用且免费力不足：请求玩家弃手牌支付（force for effect），
	# 符合「如果有费用需要支付费用」。玩家可取消，卡留在弃牌堆、解析继续。
	change_game_state(Enums.GameState.GameState_PlayerDecision)
	decision_info.clear()
	decision_info.type = Enums.DecisionType.DecisionType_ForceForEffect
	decision_info.player = performing_player.my_id
	decision_info.choice_card_id = boost_card_id
	decision_info.effect = {
		"effect_type": StrikeEffects.ForceForEffect,
		"force_max": boost_cost,
		"per_force_effect": null,
		"overall_effect": null,
		"required": false,
		"pay_for_forced_boost_discard": true,
		"forced_boost_card_id": boost_card_id,
	}
	create_event(Enums.EventType.EventType_ForceForEffect, performing_player.my_id, boost_cost)

func _play_forced_discard_boost(performing_player : Player, boost_card_id : int, already_paid : bool = false):
	# 共用的「打出强制持续加成」步骤：费用免费/免费力足够时立即使用，也在玩家
	# 弃手牌支付成功后使用。already_paid 会置 ignore_costs，避免 do_boost 二次计费。
	performing_player.move_card_from_discard_to_hand(boost_card_id)
	change_game_state(Enums.GameState.GameState_PlayerDecision)
	decision_info.clear()
	decision_info.type = Enums.DecisionType.DecisionType_BoostNow
	if already_paid:
		decision_info.ignore_costs = true
	do_boost(performing_player, boost_card_id, [], true)

func begin_resolve_boost(performing_player : Player, card_id : int, additional_boost_ids = [], shuffle_discard_after : bool = false, overwrite_current_active : bool = false):
	var dongshilang_cancel_once = decision_info.dongshilang_ice_character_action_cancel_once \
		and performing_player.deck_def.get("id", "") == "dongshilang"
	if dongshilang_cancel_once:
		var consumed_count = 1 + additional_boost_ids.size()
		_dongshilang_consume_pending_ice_action_boosts(performing_player, consumed_count)

	# If boosting multiple cards, treat as parent boosts to "queue" them
	var more_boosts_to_play = true
	while more_boosts_to_play:
		var new_boost = Boost.new()
		if active_boost:
			if overwrite_current_active:
				new_boost.action_after_boost = active_boost.action_after_boost
				new_boost.strike_after_boost = active_boost.strike_after_boost
				new_boost.strike_after_boost_opponent_first = active_boost.strike_after_boost_opponent_first
				new_boost.strike_after_boost_auto_strike = active_boost.strike_after_boost_auto_strike
				new_boost.queued_boosts = active_boost.queued_boosts
				new_boost.strike_after_boost_stored_id = active_boost.strike_after_boost_stored_id
			else:
				new_boost.parent_boost = active_boost

		active_boost = new_boost
		active_boost.playing_player = performing_player
		active_boost.card = card_db.get_card(card_id)
		active_boost.dongshilang_ice_character_action_cancel_once = dongshilang_cancel_once
		active_boost.shuffle_discard_on_cleanup = shuffle_discard_after
		active_boost.boosted_from_gauge = performing_player.is_card_in_gauge(card_id)
		# 「展示并执行」（海蒂 开关扇：boost_multiple + return_to_hand）：被展示的加成
		# **不打出** —— 不离开手牌、不进入加成区、不给对手反制窗口，只把它的
		# now / immediate 效果执行一次（区域转移在 boost_finish_resolving_card 里跳过）。
		if decision_info.return_boost_to_hand:
			active_boost.reveal_only = true

		if active_boost.reveal_only:
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "展示加成牌%s并执行其效果。" % active_boost.card.definition['display_name'])
			create_event(Enums.EventType.EventType_RevealCard, performing_player.my_id, card_id)
		else:
			var secret = active_boost.card.definition["boost"].get("facedown", false)
			performing_player.remove_card_from_hand(card_id, not secret, false)
			performing_player.remove_card_from_gauge(card_id)
			performing_player.remove_card_from_discards(card_id)
			# Renea exceed: track briefcase boost usage (check before removal)
			var renea_was_in_set_aside = performing_player.is_card_in_set_aside(card_id)
			performing_player.remove_card_from_set_aside(card_id)
			performing_player.remove_card_from_bleach(card_id)
			performing_player.remove_card_from_deck(card_id)
			if renea_was_in_set_aside and performing_player.deck_def.get("id") == "renea" and performing_player.exceeded:
				if not performing_player.renea_boost_from_briefcase_used:
					performing_player.renea_boost_from_briefcase_used = true
					performing_player.bonus_actions = 1
			var facedown = active_boost.card.definition["boost"].get("facedown")
			create_event(Enums.EventType.EventType_Boost_Played, performing_player.my_id, card_id, "", facedown)

		if additional_boost_ids:
			card_id = additional_boost_ids.pop_front()
			# Must offset effects_resolved because the boost-chaining functionality assumes that
			#  boost_aditional will be an effect of the boost itself
			active_boost.effects_resolved -= 1
		else:
			more_boosts_to_play = false

	# Resolve all immediate/now effects
	# If continuous, put it into continous boost tracking.
	resolving_boost_before_queue = true
	continue_resolve_boost()

func continue_resolve_boost():
	if game_state in [Enums.GameState.GameState_WaitForStrike, Enums.GameState.GameState_Strike_Opponent_Set_First, Enums.GameState.GameState_AutoStrike]:
		active_boost.strike_after_boost = true
		if game_state == Enums.GameState.GameState_Strike_Opponent_Set_First:
			active_boost.strike_after_boost_opponent_first = true
		if game_state == Enums.GameState.GameState_AutoStrike:
			active_boost.strike_after_boost_auto_strike = true
	change_game_state(Enums.GameState.GameState_Boost_Processing)

	var effects = card_db.get_card_boost_effects_now_immediate(active_boost.card)
	# Renea: face-down continuous boosts skip now/immediate effects until reveal
	if active_boost.playing_player.deck_def.get("id") == "renea" and active_boost.card.definition["boost"].get("facedown"):
		effects = []
	var character_effects = active_boost.playing_player.get_on_boost_effects(active_boost.card)
	if active_strike and active_boost.playing_player.deck_def.get("id") == "jinglechunshui":
		character_effects = character_effects.filter(func(effect): return not effect.get("character_effect", false))
	if active_boost.skip_on_boost_effects:
		# 本加成已被「展示并执行」的加成替代（海蒂 开关扇：boost_multiple +
		# return_to_hand）。它自身的 on_boost 角色效果（如「结算加成摸 1 张」）
		# 不得触发；被展示的加成算作那一次唯一的结算。
		character_effects = []
	var other_player = _get_player(get_other_player(active_boost.playing_player.my_id))
	# 「展示并执行」的加成不是「打出」，对手不能反制 / 无效化它。
	var counter_effects = []
	if not active_boost.reveal_only:
		counter_effects = other_player.get_counter_boost_effects()
	var boosted_definition_id = active_boost.card.definition.get("id", "")
	while true:
		if game_state in [Enums.GameState.GameState_WaitForStrike, Enums.GameState.GameState_Strike_Opponent_Set_First, Enums.GameState.GameState_AutoStrike]:
			active_boost.strike_after_boost = true
			if game_state == Enums.GameState.GameState_Strike_Opponent_Set_First:
				active_boost.strike_after_boost_opponent_first = true
			if game_state == Enums.GameState.GameState_AutoStrike:
				active_boost.strike_after_boost_auto_strike = true

		if not active_boost.checked_counter:
			if active_boost.boost_negated:
				active_boost.checked_counter = true
			elif active_boost.counters_resolved < len(counter_effects):
				var effect = counter_effects[active_boost.counters_resolved]
				if _should_skip_geoffrey_compulsive_purification_counter(other_player, effect, boosted_definition_id):
					active_boost.counters_resolved += 1
					continue
				do_effect_if_condition_met(other_player, -1, effect, null)
				if game_over or game_state == Enums.GameState.GameState_PlayerDecision:
					break

				active_boost.counters_resolved += 1
				# Finish the counter phase before boost decisions can advance effects_resolved.
				continue
			else:
				active_boost.checked_counter = true
		if active_boost.boost_negated and active_boost.effects_resolved < len(effects) + len(character_effects):
			active_boost.effects_resolved = len(effects) + len(character_effects)

		if active_boost.effects_resolved < len(effects):
			var effect = effects[active_boost.effects_resolved]
			do_effect_if_condition_met(active_boost.playing_player, active_boost.card.id, effect, null)
			if game_state == Enums.GameState.GameState_PlayerDecision:
				break

			active_boost.effects_resolved += 1
		elif active_boost.effects_resolved < len(effects) + len(character_effects):
			# Resolve character effects.
			var character_effect_index = active_boost.effects_resolved - len(effects)
			var effect = character_effects[character_effect_index]
			if active_boost.strike_after_boost \
					and active_boost.playing_player.deck_def.get("id") == "jinglechunshui" \
					and effect.get("character_effect", false):
				active_boost.effects_resolved += 1
				continue
			do_effect_if_condition_met(active_boost.playing_player, active_boost.card.id, effect, null)
			if game_state == Enums.GameState.GameState_PlayerDecision:
				break

			active_boost.effects_resolved += 1

		elif active_boost.effects_resolved < len(effects) + len(character_effects) + 1:
			# After all effects are resolved, discard/move the card then check for cancel.
			boost_finish_resolving_card(active_boost.playing_player)
			active_boost.effects_resolved += 1
			if game_state == Enums.GameState.GameState_PlayerDecision:
				break

			var dongshilang_defer_cancel = active_boost.dongshilang_ice_character_action_cancel_once and active_boost.parent_boost != null
			if not dongshilang_defer_cancel:
				if active_boost.dongshilang_ice_character_action_cancel_once and active_boost.parent_boost == null:
					var pending_ice_boosts = _dongshilang_get_pending_ice_action_count(active_boost.playing_player)
					if pending_ice_boosts > 0:
						var pending_context = _dongshilang_get_pending_ice_action_context(active_boost.playing_player)
						var pending_valid_zones = pending_context.get("valid_zones", ["bleach"])
						var pending_limitation = pending_context.get("limitation", "ice_crystal")
						var pending_ignore_costs = pending_context.get("ignore_costs", false)
						if active_boost.playing_player.can_boost_something(pending_valid_zones, pending_limitation, pending_ignore_costs):
							change_game_state(Enums.GameState.GameState_PlayerDecision)
							decision_info.clear()
							decision_info.type = Enums.DecisionType.DecisionType_BoostNow
							decision_info.player = active_boost.playing_player.my_id
							decision_info.amount = pending_ice_boosts
							decision_info.valid_zones = pending_valid_zones
							decision_info.limitation = pending_limitation
							decision_info.ignore_costs = pending_ignore_costs
							decision_info.dongshilang_ice_character_action_cancel_once = true
							create_event(Enums.EventType.EventType_ForceStartBoost, active_boost.playing_player.my_id, pending_ice_boosts, "", pending_valid_zones, pending_limitation, pending_ignore_costs)
							break
						_dongshilang_clear_pending_ice_action(active_boost.playing_player)

				var cancel_cost = _get_effective_boost_cancel_cost(active_boost.playing_player, active_boost.card)
				if cancel_cost != -1 and active_boost.playing_player.get_available_gauge() >= cancel_cost and not active_boost.strike_after_boost and (not active_boost.boost_negated or active_boost.allow_cancel_after_negate):
					_dongshilang_clear_pending_ice_action(active_boost.playing_player)
					change_game_state(Enums.GameState.GameState_PlayerDecision)
					decision_info.type = Enums.DecisionType.DecisionType_BoostCancel
					decision_info.player = active_boost.playing_player.my_id
					decision_info.choice = cancel_cost
					create_event(Enums.EventType.EventType_Boost_CancelDecision, active_boost.playing_player.my_id, cancel_cost)
					break
		else:
			if not active_boost.parent_boost:
				resolving_boost_before_queue = false
				do_queued_effects(active_boost.playing_player)
			# If do_queued_effects put us in PlayerDecision, the caller
			# (e.g. do_choose_from_topdeck with "boost"/"strike") needs the
			# boost cleaned up before proceeding. Force cleanup here so
			# active_boost doesn't leak into the next action.
			if game_state == Enums.GameState.GameState_PlayerDecision and active_boost.action_after_boost:
				boost_play_cleanup(active_boost.playing_player)
			if game_state == Enums.GameState.GameState_PlayerDecision:
				break

			if active_boost:
				boost_play_cleanup(active_boost.playing_player)
			break

		if game_over:
			break

	# Safety net: if the loop exited without boost_play_cleanup (e.g. via
	# do_queued_effects PlayerDecision break above AND action_after_boost
	# not set), and active_boost is somehow still dangling, detach it to
	# prevent parent_boost nesting in subsequent do_boost calls.
	if active_boost and not active_boost.parent_boost and not active_boost.action_after_boost:
		if not active_strike and game_state != Enums.GameState.GameState_PlayerDecision:
			boost_play_cleanup(active_boost.playing_player)
		elif active_strike and game_state != Enums.GameState.GameState_PlayerDecision:
			active_boost = null
			change_game_state(Enums.GameState.GameState_Strike_Processing)

func _should_skip_geoffrey_compulsive_purification_counter(counter_player : Player, counter_effect : Dictionary, boosted_definition_id : String) -> bool:
	if counter_player.deck_def.get("id", "") != "geoffrey":
		return false
	if boosted_definition_id not in [
		"king_decree_lordlymight",
		"king_decree_kinglystrut",
		"king_decree_paytowin",
		"king_decree_magnificentcape",
	]:
		return false
	if counter_effect.get("effect_type", "") != StrikeEffects.ForceForEffect:
		return false
	if counter_effect.get("force_max", -1) != 2:
		return false
	var overall_effect = counter_effect.get("overall_effect", null)
	if overall_effect == null:
		return false
	return overall_effect.get("effect_type", "") == StrikeEffects.NegateBoost

func boost_finish_resolving_card(performing_player : Player):
	# Reset effect source tracking for next action
	_last_effect_source_player_id = -1
	# 「展示并执行」：这张牌始终没有离开手牌，也没有进入加成区 —— 效果结算完毕后
	# 不做任何区域转移（不弃置、不设为持续加成、不「返回手牌」）。
	if active_boost.reveal_only:
		active_boost.discarded_already = true
		return
	# Syrus + Memories from the Deep: when an instant boost is played from the
	# gauge, the boost will be sealed (seal_on_cleanup). If Syrus has exceeded,
	# the exceed face now effect ("Move up to 1") would normally be skipped by
	# the seal. Let the player choose: seal directly, or resolve the exceed
	# face effect first and seal afterwards.
	if performing_player.deck_def.get("id") == "syrus" \
			and active_boost.card.definition['boost']['boost_type'] == "immediate" \
			and active_boost.seal_on_cleanup \
			and performing_player.exceeded \
			and not active_boost.discarded_already \
			and not active_boost.syrus_gauge_seal_choice_made:
		active_boost.syrus_gauge_seal_choice_made = true
		var gauge_seal_choices = [
			{ "effect_type": "syrus_gauge_seal_direct", "_choice_text": "直接封印该加成" },
			{ "effect_type": "syrus_gauge_seal_after_exceed", "_choice_text": "先执行觉醒面效果（移动至多1格）再封印" }
		]
		change_game_state(Enums.GameState.GameState_PlayerDecision)
		decision_info.clear()
		decision_info.type = Enums.DecisionType.DecisionType_EffectChoice
		decision_info.player = performing_player.my_id
		decision_info.choice_card_id = active_boost.card.id
		decision_info.choice = gauge_seal_choices
		create_event(Enums.EventType.EventType_Strike_EffectChoice, performing_player.my_id, 0, "EffectOption")
		return

	var syrus_should_replace = false
	var syrus_replacement_def = null
	var syrus_boost_name = ""
	if performing_player.deck_def.get("id") == "syrus" \
			and active_boost.card.definition['boost']['boost_type'] == "immediate" \
			and not active_boost.discard_on_cleanup \
			and not active_boost.seal_on_cleanup \
			and not active_boost.discarded_already:
		syrus_should_replace = true
		syrus_boost_name = active_boost.card.definition['display_name']
		if performing_player.exceeded:
			syrus_replacement_def = performing_player.get_exceeded_replacement_boost_definition()
		else:
			syrus_replacement_def = performing_player.get_replacement_boost_definition()
	# All boost immediate/now effects are done.
	# If continuous, add to player.
	# If immediate, add to discard.
	if active_boost.card.definition['boost']['boost_type'] == "continuous" and not active_boost.discard_on_cleanup:
		performing_player.add_to_continuous_boosts(active_boost.card)
		if performing_player.deck_def.get("id") == "jinglechunshui" and performing_player.jinglechunshui_gauge_boost_pending:
			performing_player.jinglechunshui_gauge_boost_pending = false
			handle_strike_effect(active_boost.card.id, { "effect_type": StrikeEffects.AddTopDeckToGauge }, performing_player)
		if active_strike:
			# Do the during_strike effects and add any before effects to the remaining effects list.
			for effect in active_boost.card.definition['boost']['effects']:
				if effect['timing'] == "during_strike":
					do_effect_if_condition_met(performing_player, active_boost.card.id, effect, null)
			if active_boost.card.definition['id'] == "jinglechunshui_bujingdule" \
					and active_strike.strike_state in [StrikeState.StrikeState_Cleanup_Player1Effects, StrikeState.StrikeState_Cleanup_Player2Effects]:
				for effect in active_boost.card.definition['boost']['effects']:
					if effect['timing'] == "cleanup":
						do_effect_if_condition_met(performing_player, active_boost.card.id, effect, null)

		if performing_player.sustain_next_boost:
			performing_player.sustained_boosts.append(active_boost.card.id)
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将%s设为并维持为持续性加成。" % _get_boost_and_card_name(active_boost.card))
		else:
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将%s设为持续性加成。" % _get_boost_and_card_name(active_boost.card))
	elif not active_boost.discarded_already:
		# Pooky Zol's Secret Recipe: redirect to face-down Continuous Boost
		if performing_player.deck_def.get("id") == "pooky" \
				and performing_player.pooky_zols_target_id == active_boost.card.id:
			performing_player.pooky_zols_target_id = -1
			var pooky_zc_def = {
				"boost_type": "continuous",
				"facedown": true,
				"force_cost": 0,
				"cancel_cost": -1,
				"display_name": "Zol's Brew",
				"effects": []
			}
			# 原件必须存进 replaced_boost：卡对象是实体卡（definition 为每张卡独立副本），
			# 直接改写会让这张牌**永久**变成「无效果面朝下持续加成」，之后抽到再用就没有
			# 即时加成的效果了（玩家反馈的「效果丢失」），而且每次复用都会白拿一个持续加成。
			# 存进 replaced_boost 后，离开加成区时 player.do_discarded_effects_for_boost /
			# remove_from_transforms 会自动还原（与 Syrus「重打出场」同一惯例）。
			active_boost.card.definition["replaced_boost"] = active_boost.card.definition["boost"]
			active_boost.card.definition["boost"] = pooky_zc_def
			performing_player.add_to_continuous_boosts(active_boost.card)
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "Zol's Secret Recipe places %s as a facedown Continuous Boost." % _log_card_name(active_boost.card.id))
		elif active_boost.seal_on_cleanup:
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "封印加成牌%s。" % active_boost.card.definition['display_name'])
			do_seal_effect(performing_player, active_boost.card.id, "")
		elif active_boost.strike_after_boost_auto_strike:
			performing_player.add_to_set_aside(active_boost.card)
		elif active_boost.card.id in active_boost.cleanup_to_gauge_card_ids:
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将加成牌%s加入怒气。" % active_boost.card.definition['display_name'])
			performing_player.add_to_gauge(active_boost.card)
		elif active_boost.card.id in active_boost.cleanup_to_bleach_card_ids:
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将加成牌%s加入%s。" % [active_boost.card.definition['display_name'], performing_player.get_bleach_zone_name()])
			performing_player.add_to_bleach(active_boost.card)
		elif active_boost.card.id in active_boost.cleanup_to_hand_card_ids:
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将加成牌%s返回手牌。" % active_boost.card.definition['display_name'])
			performing_player.add_to_hand(active_boost.card, true)
		else:
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "弃置加成牌%s。" % active_boost.card.definition['display_name'])
			performing_player.add_to_discards(active_boost.card)

	if syrus_should_replace and syrus_replacement_def != null:
		performing_player.remove_card_from_discards(active_boost.card.id)
		active_boost.card.definition["replaced_boost"] = active_boost.card.definition["boost"]
		active_boost.card.definition["boost"] = syrus_replacement_def.duplicate(true)
		performing_player.add_to_continuous_boosts(active_boost.card)
		_append_log_full(Enums.LogType.LogType_Effect, performing_player, "将%s以背面持续加成重打出场。" % _log_card_name(syrus_boost_name))
		for effect in active_boost.card.definition['boost']['effects']:
			if effect['timing'] == "now" or (active_strike and effect['timing'] == "during_strike"):
				do_effect_if_condition_met(performing_player, active_boost.card.id, effect, null)
				if game_state == Enums.GameState.GameState_PlayerDecision:
					break

	performing_player.sustain_next_boost = false
	if game_state in [Enums.GameState.GameState_WaitForStrike, Enums.GameState.GameState_Strike_Opponent_Set_First,  Enums.GameState.GameState_AutoStrike]:
		active_boost.strike_after_boost = true
		if game_state == Enums.GameState.GameState_Strike_Opponent_Set_First:
			active_boost.strike_after_boost_opponent_first = true
		if game_state == Enums.GameState.GameState_AutoStrike:
			active_boost.strike_after_boost_auto_strike = true

func boost_play_cleanup(performing_player : Player):
	if game_state != Enums.GameState.GameState_PlayerDecision:
		decision_info.clear()
	if not performing_player.is_card_in_continuous_boosts(active_boost.card.id):
		performing_player.yuanliuzhai_blocked_boost_ids.erase(active_boost.card.id)
	# Syrus: from-gauge instant boost (Memories from the Deep) whose exceed-face
	# now effect (Move up to 1) resolved first; seal the replayed continuous
	# boost now that the effect finished.
	if active_boost and active_boost.syrus_seal_after_exceed_pending:
		active_boost.syrus_seal_after_exceed_pending = false
		if performing_player.is_card_in_continuous_boosts(active_boost.card.id):
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "封印加成牌%s。" % active_boost.card.definition['display_name'])
			performing_player.remove_from_continuous_boosts(active_boost.card, "sealed")
		active_boost.discarded_already = true
	if active_boost and active_boost.parent_boost == null and active_boost.dongshilang_ice_character_action_cancel_once:
		_dongshilang_clear_pending_ice_action(performing_player)
	# Account for boosts that played other boosts
	if active_boost.parent_boost:
		var parent_boost = active_boost.parent_boost
		var parent_is_dongshilang_cancel_chain = parent_boost.dongshilang_ice_character_action_cancel_once \
			and parent_boost.checked_counter \
			and parent_boost.effects_resolved > 0 \
			and not active_strike
		if parent_is_dongshilang_cancel_chain:
			active_boost = parent_boost
			var pending_ice_boosts = _dongshilang_get_pending_ice_action_count(performing_player)
			if pending_ice_boosts > 0:
				var pending_context = _dongshilang_get_pending_ice_action_context(performing_player)
				var pending_valid_zones = pending_context.get("valid_zones", ["bleach"])
				var pending_limitation = pending_context.get("limitation", "ice_crystal")
				var pending_ignore_costs = pending_context.get("ignore_costs", false)
				if performing_player.can_boost_something(pending_valid_zones, pending_limitation, pending_ignore_costs):
					change_game_state(Enums.GameState.GameState_PlayerDecision)
					decision_info.clear()
					decision_info.type = Enums.DecisionType.DecisionType_BoostNow
					decision_info.player = performing_player.my_id
					decision_info.amount = pending_ice_boosts
					decision_info.valid_zones = pending_valid_zones
					decision_info.limitation = pending_limitation
					decision_info.ignore_costs = pending_ignore_costs
					decision_info.dongshilang_ice_character_action_cancel_once = true
					create_event(Enums.EventType.EventType_ForceStartBoost, performing_player.my_id, pending_ice_boosts, "", pending_valid_zones, pending_limitation, pending_ignore_costs)
					return
				_dongshilang_clear_pending_ice_action(performing_player)

			var cancel_cost = _get_effective_boost_cancel_cost(performing_player, active_boost.card)
			if cancel_cost != -1 and performing_player.get_available_gauge() >= cancel_cost and not active_boost.strike_after_boost and (not active_boost.boost_negated or active_boost.allow_cancel_after_negate):
				_dongshilang_clear_pending_ice_action(performing_player)
				change_game_state(Enums.GameState.GameState_PlayerDecision)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_BoostCancel
				decision_info.player = performing_player.my_id
				decision_info.choice = cancel_cost
				create_event(Enums.EventType.EventType_Boost_CancelDecision, performing_player.my_id, cancel_cost)
				return

		if active_strike:
			_boost_play_cleanup_update_effects(performing_player)

		# Pass on any relevant fields.
		active_boost.parent_boost.action_after_boost = active_boost.parent_boost.action_after_boost or active_boost.action_after_boost
		active_boost.parent_boost.strike_after_boost = active_boost.parent_boost.strike_after_boost or active_boost.strike_after_boost
		active_boost.parent_boost.strike_after_boost_opponent_first = active_boost.parent_boost.strike_after_boost_opponent_first or active_boost.strike_after_boost_opponent_first
		active_boost.parent_boost.strike_after_boost_auto_strike = active_boost.parent_boost.strike_after_boost_auto_strike or active_boost.strike_after_boost_auto_strike
		active_boost.parent_boost.queued_boosts = active_boost.queued_boosts
		active_boost.parent_boost.strike_after_boost_stored_id = active_boost.strike_after_boost_stored_id

		# Go back to the parent boost.
		active_boost = active_boost.parent_boost
		active_boost.effects_resolved += 1
		continue_resolve_boost()
		return

	if active_boost.queued_boosts:
		var next_boost_id = active_boost.queued_boosts.pop_front()
		begin_resolve_boost(performing_player, next_boost_id, [], active_boost.shuffle_discard_on_cleanup, true)
		return

	if active_boost.shuffle_discard_on_cleanup:
		var shuffle_effect = { "effect_type": StrikeEffects.ShuffleDiscardInPlace }
		handle_strike_effect(-1, shuffle_effect, performing_player)

	var preparing_strike = false
	if performing_player.strike_on_boost_cleanup and not active_boost.strike_after_boost and not active_strike:
		if performing_player.wild_strike_on_boost_cleanup:
			var wild_effect = { "effect_type": StrikeEffects.StrikeWild }
			handle_strike_effect(-1, wild_effect, performing_player)
		else:
			active_boost.strike_after_boost = true
			# event creation handled below
		active_character_action = false
		preparing_strike = true
		decision_info.clear()
		decision_info.type = Enums.DecisionType.DecisionType_StrikeNow
		decision_info.player = performing_player.my_id
	performing_player.strike_on_boost_cleanup = false
	performing_player.wild_strike_on_boost_cleanup = false

	if active_boost.strike_after_boost and not active_strike:
		if active_boost.strike_after_boost_opponent_first:
			change_game_state(Enums.GameState.GameState_Strike_Opponent_Set_First)
		elif active_boost.strike_after_boost_stored_id != null:
			change_game_state(Enums.GameState.GameState_PickAction)
			do_strike(performing_player, active_boost.strike_after_boost_stored_id, false, -1)
		else:
			if active_boost.strike_after_boost_auto_strike:
				# Return boost to hand
				var card = active_boost.card
				performing_player.add_to_hand(card, false)
				# Strike with it
				change_game_state(Enums.GameState.GameState_PickAction)
				performing_player.next_strike_faceup = true
				do_strike(performing_player, card.id, false, -1)

				#change_game_state(Enums.GameState.GameState_AutoStrike)
				#decision_info.type = Enums.DecisionType.DecisionType_StrikeNow
				#decision_info.player = performing_player.my_id
				#decision_info.effect_type = active_boost.card.definition['id']
				#var strike_info = {
					#"card_id": active_boost.card.id,
				performing_player.jinglechunshui_gauge_boost_pending = true
					#"wild_swing": false,
					#"ex_card_id": -1
				#}
				#create_event(Enums.EventType.EventType_Strike_EffectDoStrike, performing_player.my_id, 0, "", strike_info)
			else:
				change_game_state(Enums.GameState.GameState_WaitForStrike)
				decision_info.clear()
				decision_info.type = Enums.DecisionType.DecisionType_StrikeNow
				decision_info.player = performing_player.my_id
				if performing_player.next_strike_from_sealed:
					decision_info.source = "sealed"
					create_event(Enums.EventType.EventType_Strike_FromGauge, performing_player.my_id, 0)
				elif performing_player.next_strike_from_gauge:
					if len(performing_player.gauge) > 0:
						decision_info.source = "gauge"
						create_event(Enums.EventType.EventType_Strike_FromGauge, performing_player.my_id, 0)
					else:
						var strike_info = {
							"card_id": -1,
							"wild_swing": true,
							"ex_card_id": -1
						}
						create_event(Enums.EventType.EventType_Strike_EffectDoStrike, performing_player.my_id, 0, "", strike_info)
				else:
					create_event(Enums.EventType.EventType_ForceStartStrike, performing_player.my_id, 0)
		active_boost = null
		preparing_strike = true
	elif active_boost.action_after_boost and not active_strike:
		if game_state == Enums.GameState.GameState_PlayerDecision:
			# Resolve the pending decision first, then grant the extra action.
			performing_player.bonus_actions += 1
		else:
			_append_log_full(Enums.LogType.LogType_Action, performing_player, "执行额外一动！")
			create_event(Enums.EventType.EventType_Boost_ActionAfterBoost, performing_player.my_id, 0)
			change_game_state(Enums.GameState.GameState_PickAction)
		active_boost = null
	else:
		if active_strike:
			_boost_play_cleanup_update_effects(performing_player)

			# Continue resolving the strike (or doing another boost if you're doing Faust things...)
			var handled_weird_boost = false
			if active_strike.remaining_forced_boosts > 0:
				if active_strike.remaining_forced_boosts_source == "topdeck" and performing_player.deck.size() > 0:
					handled_weird_boost = true
					active_boost = null
					do_topdeck_boost()
				elif active_strike.remaining_forced_boosts_source == "topdiscard":
					var boost_card_id = performing_player.get_top_continuous_boost_in_discard()
					if boost_card_id != -1:
						handled_weird_boost = true
						active_boost = null
						do_discard_boost()
				elif active_strike.remaining_forced_boosts_source == "topdeck_choice":
					if not active_strike.remaining_forced_boosts_card_ids.is_empty():
						handled_weird_boost = true
						active_boost = null
						do_chosen_topdeck_boost()

			if not handled_weird_boost:
				active_strike.remaining_forced_boosts = 0
				active_strike.remaining_forced_boosts_card_ids = []
				active_boost = null
				active_strike.effects_resolved_in_timing += 1
				continue_resolve_strike()
		else:
			active_boost = null
			if not preparing_strike and not active_overdrive:
				check_hand_size_advance_turn(performing_player)
	_begin_pending_heiqiyihu_strike()

func _boost_play_cleanup_update_effects(performing_player : Player):
	# 被无效化的加成（如杰弗里 强制净化 / Inquisition 的 counter_boost）不得把它的
	# before / during_strike / hit / after 效果注入本次战斗 —— 否则「前置：前进1」
	# 这类效果在无效之后照样结算。之前只跳过了加成自身的 now/immediate 效果。
	if active_boost and active_boost.boost_negated:
		return
	# 「展示并执行」的加成不在场，不得把它的 timing 效果注入本次战斗。
	if active_boost and active_boost.reveal_only:
		return
	# Add this boost's effects to the current effect list if the taming matches.
	var current_strike_timing = get_current_strike_timing()
	var is_current_timing_player = true
	if current_strike_timing in ['before', 'hit', 'after', 'cleanup']:
		is_current_timing_player = performing_player.my_id == get_current_strike_timing_player_id()
	for effect in active_boost.card.definition['boost']['effects']:
		var matches_timing = false
		if effect['timing'] == current_strike_timing and is_current_timing_player:
			matches_timing = true
		elif current_strike_timing == "before" and effect['timing'] == "both_players_before":
			matches_timing = true
		elif current_strike_timing == "after" and effect['timing'] == "both_players_after":
			matches_timing = true

		if matches_timing:
			effect['card_id'] = active_boost.card.id
			active_strike.remaining_effect_list.append(effect)

func can_do_prepare(performing_player : Player):
	if game_state != Enums.GameState.GameState_PickAction:
		return false
	if active_turn_player != performing_player.my_id:
		return false
	return true

func can_do_move(performing_player : Player):
	if game_state != Enums.GameState.GameState_PickAction:
		return false
	if active_turn_player != performing_player.my_id:
		return false

	# Check if the player can generate force
	var force_needed = 1
	var player_location = performing_player.arena_location
	# If cornered, will need 2 force to get out
	# Left corner
	if performing_player.get_closest_occupied_space_to(Enums.MinArenaLocation) == Enums.MinArenaLocation:
		if performing_player.is_overlapping_opponent(player_location+1):
			force_needed = 2
	# Right corner
	elif performing_player.get_closest_occupied_space_to(Enums.MaxArenaLocation) == Enums.MaxArenaLocation:
		if performing_player.is_overlapping_opponent(player_location-1):
			force_needed = 2

	var force_available = performing_player.get_available_force()
	# Lily (and similar passives): retreat cost reduction also lowers the
	# move-action force gate. The exact target-space cost is validated in
	# can_move_to / do_move via get_force_to_move_to.
	for effect in performing_player.get_character_effects_at_timing("on_retreat_cost"):
		if effect.get('effect_type') == StrikeEffects.RetreatCostReduced:
			force_needed = max(0, force_needed - effect.get('amount', 1))
			break
	if force_available >= force_needed:
		return true
	return false

func can_do_change(performing_player : Player):
	if game_state != Enums.GameState.GameState_PickAction:
		return false
	if active_turn_player != performing_player.my_id:
		return false

	return true

func can_do_exceed(performing_player : Player):
	if game_state != Enums.GameState.GameState_PickAction:
		return false
	if active_turn_player != performing_player.my_id:
		return false
	if performing_player.exceeded:
		return false

	# 按「支付点数」算：怒气区的枪灵值 2 点。原先按张数（len(gauge) + free_gauge）算，
	# 于是怒气区只有 2 张枪灵（=4 点，够付 4 点觉醒费）时，觉醒行动选项会被禁用。
	var gauge_available = performing_player.get_available_gauge()
	if performing_player.deck_def.get("id") == "minato" and not performing_player.exceeded:
		gauge_available += int(performing_player.discards.size() / 3.0)
	var exceed_cost = performing_player.get_exceed_cost()
	if gauge_available >= exceed_cost:
		return true

	# Check if life can supplement gauge
	if performing_player.spend_life_for_gauge_amount > 0:
		var gauge_shortfall = exceed_cost - gauge_available
		var life_needed = gauge_shortfall * performing_player.spend_life_for_gauge_amount
		if performing_player.life > life_needed:
			return true

	return false

func can_do_reshuffle(performing_player : Player):
	if game_state != Enums.GameState.GameState_PickAction:
		return false
	if active_turn_player != performing_player.my_id:
		return false
	if len(performing_player.discards) == 0:
		return false
	return performing_player.reshuffle_remaining > 0

func can_do_boost(performing_player : Player):
	if game_state != Enums.GameState.GameState_PickAction and not wait_for_mid_strike_boost():
		return false
	if active_turn_player != performing_player.my_id and not wait_for_mid_strike_boost():
		return false

	return true

func can_do_ex_transform(performing_player : Player):
	if game_state != Enums.GameState.GameState_PickAction:
		return false
	if active_turn_player != performing_player.my_id:
		return false

	var transform_options = []
	var tl_not_exceeded = performing_player.deck_def.get("id") == "tournelouse" and not performing_player.exceeded
	for card in performing_player.hand:
		if tl_not_exceeded and card.definition['type'] == "normal" and not performing_player.has_card_name_in_zone(card, "transform"):
			return true
		if card.definition['boost']['boost_type'] != "transform":
			continue
		var card_name = card.definition['display_name']
		if card_name in transform_options:
			return true
		transform_options.append(card_name)

	return false

func can_do_strike(performing_player : Player):
	if game_state == Enums.GameState.GameState_WaitForStrike and decision_info.player == performing_player.my_id:
		return true
	if game_state != Enums.GameState.GameState_PickAction:
		return false
	if active_turn_player != performing_player.my_id:
		return false
	if performing_player.strike_action_disabled:
		return false
	# Can always wild swing!

	return true

func check_post_action_effects(performing_player : Player):

	# Queue any end of turn character effects
	var post_action_effects = performing_player.get_character_effects_at_timing("after_non_strike_action")
	# Queue any end of turn boost effects.
	var boost_list = performing_player.get_continuous_boosts_and_transforms()
	for i in range(len(boost_list) - 1, -1, -1):
		var card = boost_list[i]
		for effect in card.definition['boost']['effects']:
			if effect['timing'] == "after_non_strike_action":
				effect['card_id'] = card.id
				post_action_effects.append(effect)

	# process effects, break if in choice state
	while true:
		if post_action_effects_resolved < len(post_action_effects):
			var effect = post_action_effects[post_action_effects_resolved]
			do_effect_if_condition_met(performing_player, -1, effect, null)
			if game_state == Enums.GameState.GameState_PlayerDecision:
				break
			post_action_effects_resolved += 1
		else:
			active_post_action_effect = false
			performing_player.checked_post_action_effects = true
			if not post_action_interruption:
				check_hand_size_advance_turn(performing_player)
			break

		if game_over:
			break

	# after out of effects

func check_hand_size_advance_turn(performing_player : Player):

	assert(not active_strike)
	_queue_heiqiyihu_thresholds(player)
	_queue_heiqiyihu_thresholds(opponent)
	if _begin_heiqiyihu_thresholds(performing_player, "hand_size"):
		return

	if not performing_player.checked_post_action_effects:
		active_post_action_effect = true
		post_action_effects_resolved = 0
		post_action_interruption = false
		check_post_action_effects(performing_player)
		return

	if performing_player.bonus_actions > 0:
		change_game_state(Enums.GameState.GameState_PickAction)
		performing_player.bonus_actions -= 1
		performing_player.checked_post_action_effects = false
		if performing_player.bonus_actions == 0:
			_append_log_full(Enums.LogType.LogType_Action, performing_player, "执行额外一动！")
		else:
			_append_log_full(Enums.LogType.LogType_Action, performing_player, "执行额外一动！（剩余%s次）" % performing_player.bonus_actions)
		create_event(Enums.EventType.EventType_Boost_ActionAfterBoost, performing_player.my_id, performing_player.bonus_actions)
	elif performing_player.dan_draw_choice and not active_special_draw_effect and not performing_player.skip_end_of_turn_draw:
		var choice_effect = {
			"effect_type": StrikeEffects.Choice,
			StrikeEffects.Choice: [
				{ "effect_type": StrikeEffects.SetDanDrawChoiceInternal, "from_bottom": false },
				{ "effect_type": StrikeEffects.SetDanDrawChoiceInternal, "from_bottom": true }
			]
		}
		handle_strike_effect(-1, choice_effect, performing_player)
		active_special_draw_effect = true
	elif performing_player.enchantress_draw_choice and not active_special_draw_effect and not performing_player.skip_end_of_turn_draw:
		var choice_effect = {
			"effect_type": StrikeEffects.Choice,
			StrikeEffects.Choice: [
				{ "effect_type": StrikeEffects.DrawTo, "amount": 7 },
				{ "effect_type": StrikeEffects.Draw, "amount": 1 }
			]
		}
		handle_strike_effect(-1, choice_effect, performing_player)
		active_special_draw_effect = true
	elif performing_player.has_passive("geoffrey_untainted_passive") and performing_player.life <= 5 and not performing_player.did_strike_this_turn and not active_special_draw_effect and not performing_player.skip_end_of_turn_draw:
		var choice_effect = {
			"effect_type": StrikeEffects.Choice,
			StrikeEffects.Choice: [
				{ "effect_type": StrikeEffects.GainLife, "amount": 1, "and": { "effect_type": StrikeEffects.SkipEndOfTurnDraw } },
				{ "effect_type": StrikeEffects.Pass }
			]
		}
		handle_strike_effect(-1, choice_effect, performing_player)
		active_special_draw_effect = true
	else:
		start_end_turn()

# Called by player.gd after any discard to trigger passive abilities (e.g. Eugenia)
func _on_player_discard(discarding_player, card_ids : Array):
	# 注意：card_ids 只包含「从手牌弃掉的牌」（player.discard 只把这类牌报过来）。
	# Eugenia 的两个被动都以「对手弃掉手牌」为前提；从怒气区 / 场上 / 牌库
	# 进弃牌堆不该触发（例：Aluraune's Kiss 会让对手弃怒气牌）。
	if not discarding_player or card_ids.size() == 0:
		return
	var other_player = _get_player(get_other_player(discarding_player.my_id))
	if not other_player:
		return
	var saved_source = _last_effect_source_player_id
	
	# Eugenia Normal Passive: ターン1回 - あなたが相手にカードを捨てさせた時
	# "Once per turn, when you make opponent discard"
	if other_player.deck_def.get("id") == "eugenia" and not other_player.eugenia_normal_passive_used_this_turn and not other_player.exceeded:
		# Must be: opponent (not Eugenia) discarding
		if discarding_player.my_id == other_player.my_id:
			return
		# Must be: Eugenia's effect causing the discard
		if _last_effect_source_player_id != other_player.my_id:
			return
		if card_ids.size() > 0 and card_db:
			# Collect all hand cards with matching speed
			var match_cards = []
			var matched_speeds = {}
			for discard_id in card_ids:
				var discarded_card = card_db.get_card(discard_id)
				if not discarded_card:
					continue
				var discarded_speed = discarded_card.definition.get("speed", -1)
				if str(discarded_speed) != "X" or active_strike:
					discarded_speed = get_card_stat(discarding_player, discarded_card, 'speed')
				if discarded_speed in matched_speeds:
					continue
				matched_speeds[discarded_speed] = true
				for hand_card in other_player.hand:
					var hand_speed = hand_card.definition.get("speed", -2)
					if str(hand_speed) != "X" or active_strike:
						hand_speed = get_card_stat(other_player, hand_card, 'speed')
					if hand_speed == discarded_speed:
						match_cards.append(hand_card)
			
			# Build choice: each matching card + Pass
			var choices = [{"_choice_text": "跳过(不展示手牌)", "effect_type": StrikeEffects.Pass}]
			for hc in match_cards:
				var card_name = card_db.get_card_name(hc.id)
				var hand_speed = hc.definition.get("speed", "?")
				if str(hand_speed) != "X" or active_strike:
					hand_speed = get_card_stat(other_player, hc, 'speed')
				choices.append({
					"_choice_text": card_name + " (S" + str(hand_speed) + ")",
					"effect_type": StrikeEffects.RevealSingleCard,
					"card_id": hc.id,
					"and": {
						"effect_type": "eugenia_passive_mark_used",
						"and": {
							"effect_type": StrikeEffects.TakeDamage,
							"opponent": true,
							"amount": 2,
							"nonlethal": true
						}
					}
				})
			
			if match_cards.size() > 0:
				_append_log_full(Enums.LogType.LogType_Effect, other_player, "may reveal a matching card to deal 2 non-lethal damage!")
			
			if game_state != Enums.GameState.GameState_PlayerDecision:
				var choice_effect = {
					"effect_type": StrikeEffects.Choice,
					StrikeEffects.Choice: choices,
					"_source_player_id": saved_source
				}
				handle_strike_effect(-1, choice_effect, other_player)
				_last_effect_source_player_id = saved_source
			else:
				# Mid-decision: just log and auto-trigger first match if any
				if match_cards.size() > 0:
					var hc = match_cards[0]
					var card_name = card_db.get_card_name(hc.id)
					_append_log_full(Enums.LogType.LogType_Effect, other_player, "reveals %s and deals 2 non-lethal damage!" % _log_card_name(card_name))
					other_player.eugenia_normal_passive_used_this_turn = true
					other_player.reveal_card_ids([hc.id])
					var damage_effect = {
						"effect_type": StrikeEffects.TakeDamage,
						"opponent": true,
						"amount": 2,
						"nonlethal": true,
						"_source_player_id": saved_source
					}
					handle_strike_effect(-1, damage_effect, other_player)
					_last_effect_source_player_id = saved_source
	
	# Eugenia Exceeded Passive: When opponent discards by effect,
	# you may choose one to put into your set_aside (Wonderland).
	if other_player.deck_def.get("id") == "eugenia" and other_player.exceeded:
		if card_ids.size() > 0:
			# Must be: opponent (not Eugenia) discarding
			if discarding_player.my_id == other_player.my_id:
				return
			# Must be: Eugenia's effect causing the discard
			if _last_effect_source_player_id != other_player.my_id:
				# _source_player_id in ChooseOpponentCardToDiscardInternal
				# should have already restored the correct source before
				# discard(). If it didn't, the source doesn't match → reject.
				return
			
			# Build choice to pick a card to add to Wonderland, or pass
			var choices = [{"_choice_text": "跳过", "effect_type": StrikeEffects.Pass}]
			for cid in card_ids:
				var cname = card_db.get_card_name(cid)
				if cname:
					choices.append({
						"_choice_text": cname,
						"effect_type": "wonderland_add_card",
						"card_id": cid
					})
			if game_state != Enums.GameState.GameState_PlayerDecision:
				var choice_effect = {
					"effect_type": StrikeEffects.Choice,
					StrikeEffects.Choice: choices,
					"_source_player_id": saved_source
				}
				handle_strike_effect(-1, choice_effect, other_player)
				_last_effect_source_player_id = saved_source
			else:
				# Mid-decision fallback: don't drop Eugenia exceeded UA trigger.
				# Mirror normal-side behavior by resolving immediately.
				var picked_id = card_ids[0]
				var picked_name = card_db.get_card_name(picked_id)
				_append_log_full(Enums.LogType.LogType_Effect, other_player, "将%s放入Wonderland。" % _log_card_name(picked_name))
				var wonderland_effect = {
					"effect_type": "wonderland_add_card",
					"card_id": picked_id,
					"_source_player_id": saved_source
				}
				handle_strike_effect(-1, wonderland_effect, other_player)
				_last_effect_source_player_id = saved_source
	
	_last_effect_source_player_id = saved_source

func do_prepare(performing_player) -> bool:
	printlog("MainAction: PREPARE by %s" % [performing_player.name])
	if not can_do_prepare(performing_player):
		printlog("ERROR: Tried to Prepare but can't.")
		return false

	create_event(Enums.EventType.EventType_Prepare, performing_player.my_id, 0)
	_append_log_full(Enums.LogType.LogType_Action, performing_player, "回合行动：热身")
	_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "抽一张牌。")
	var draw_amount = 1
	var other_player = _get_player(get_other_player(performing_player.my_id))
	if other_player.reduce_opponent_prepare_draw:
		draw_amount = 0
	performing_player.draw(draw_amount)
	printlog("PREPARE_DRAW_COMPLETE player=%s drew=%d hand=%d deck=%d queue=%d state=%s" % [
		performing_player.name,
		draw_amount,
		performing_player.hand.size(),
		performing_player.deck.size(),
		event_queue.size(),
		Enums.GameState.keys()[game_state],
	])

	active_prepare = true
	prepare_effects_resolved = 0
	continue_resolve_prepare(performing_player)
	return true

func continue_resolve_prepare(performing_player : Player):
	# Assuming that a strike can't be started in here
	change_game_state(Enums.GameState.GameState_Boost_Processing)

	var boost_effects = get_boost_effects_at_timing("on_prepare", performing_player)
	var character_effects = performing_player.get_character_effects_at_timing("on_prepare")
	for effect in character_effects:
		effect['card_id'] = -1
	var prepare_effects = boost_effects + character_effects

	while true:
		if prepare_effects_resolved < len(prepare_effects):
			var effect = prepare_effects[prepare_effects_resolved]
			do_effect_if_condition_met(performing_player, -1, effect, null)
			if game_state == Enums.GameState.GameState_PlayerDecision:
				break
			prepare_effects_resolved += 1
		else:
			active_prepare = false
			check_hand_size_advance_turn(performing_player)
			break

		if game_over:
			break

func handle_spend_life_for_force(performing_player : Player, spent_life : int) -> bool:
	if spent_life > performing_player.life:
		printlog("ERROR: Tried to spend more life than player had.")
		return false

	if spent_life > 0:
		performing_player.spend_life(spent_life)
		#if active_strike:
			#active_strike.add_damage_taken(damaged_player, unmitigated_damage)
			#check_for_stun(damaged_player, false)
	return true

func handle_spend_life_cost(performing_player : Player, spent_life : int) -> bool:
	if spent_life > performing_player.life:
		printlog("ERROR: Tried to spend more life than player had.")
		return false

	if spent_life > 0:
		performing_player.spend_life(spent_life)
	return true

func do_discard_to_max(performing_player : Player, card_ids) -> bool:
	printlog("SubAction: DISCARD_TO_MAX by %s - %s" % [get_player_name(performing_player.my_id), card_ids])
	if performing_player.my_id != active_turn_player:
		printlog("ERROR: Tried to discard for wrong player.")
		return false
	if game_state != Enums.GameState.GameState_DiscardDownToMax:
		printlog("ERROR: Tried to discard wrong game state.")
		return false

	for id in card_ids:
		if not performing_player.is_card_in_hand(id):
			# Card not found, error
			printlog("ERROR: Tried to discard cards that aren't in hand.")
			return false

	if len(performing_player.hand) - len(card_ids) > performing_player.max_hand_size:
		printlog("ERROR: Not discarding enough cards")
		return false

	var card_names = card_db.get_card_name(card_ids[0])
	for i in range(1, card_ids.size()):
		card_names += ", " + card_db.get_card_name(card_ids[i])
	_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "弃置至其最大手牌数：%s。" % _log_card_name(card_names))

	performing_player.discard(card_ids)
	if discard_to_max_after_end_turn_draw:
		discard_to_max_after_end_turn_draw = false
		advance_to_next_turn()
	else:
		start_end_turn()
	return true

func do_reshuffle(performing_player : Player) -> bool:
	printlog("MainAction: RESHUFFLE by %s" % [performing_player.name])
	if not can_do_reshuffle(performing_player):
		printlog("ERROR: Tried to reshuffle but can't.")
		return false

	_append_log_full(Enums.LogType.LogType_Action, performing_player, "回合行动：手动洗切")
	performing_player.reshuffle_discard(true)
	check_hand_size_advance_turn(performing_player)
	return true

func do_move(performing_player : Player, card_ids, new_arena_location, use_free_force : bool = false, spent_life_for_force : int = 0) -> bool:
	printlog("MainAction: MOVE by %s to %s" % [performing_player.name, str(new_arena_location)])
	if not performing_player.validate_heiqiyihu_payment(card_ids):
		return false
	if not can_do_move(performing_player):
		printlog("ERROR: Cannot perform the move action for this player.")
		return false

	var ignore_force_req = false
	if not performing_player.can_move_to(new_arena_location, ignore_force_req):
		printlog("ERROR: Unable to move to that arena location.")
		return false

	# Ensure cards are in hand/gauge
	for id in card_ids:
		if not performing_player.is_card_in_hand(id) and not performing_player.is_card_in_gauge(id) \
		and not performing_player.is_heiqiyihu_guardian_resource(id):
			# Card not found, error
			printlog("ERROR: Tried to discard cards that aren't in hand/gauge.")
			return false

	# Ensure cards generate enough force.
	var required_force = performing_player.get_force_to_move_to(new_arena_location)
	var generated_force = performing_player.get_force_with_cards(card_ids, "MOVE", false, use_free_force)
	generated_force += performing_player.get_force_from_spent_life(spent_life_for_force)

	if generated_force < required_force:
		printlog("ERROR: Not enough force with these cards to move there.")
		return false
	performing_player.total_force_spent_this_turn += required_force

	performing_player.discard(card_ids, 0, true)
	if not handle_spend_life_for_force(performing_player, spent_life_for_force):
		return false
	if game_over:
		return true

	# Move the player.
	var old_location = performing_player.arena_location
	performing_player.move_to(new_arena_location)

	var move_amount = abs(new_arena_location - old_location)
	var other_loc = _get_player(get_other_player(performing_player.my_id)).arena_location
	if (old_location < other_loc and new_arena_location > other_loc) or (old_location > other_loc and new_arena_location < other_loc):
		move_amount -= 1

	# Ulrik: increment move counters from continuous boosts
	for boost in performing_player.continuous_boosts:
		for boost_effect in boost.definition['boost']['effects']:
			if boost_effect.get('effect_type') == StrikeEffects.IncrementBonusMovePowerCounters:
				boost.set_meta('bonus_move_power_counters', boost.get_meta('bonus_move_power_counters', 0) + move_amount * boost_effect.get('amount', 1))
			if boost_effect.get('effect_type') == StrikeEffects.IncrementBonusMoveArmorCounters:
				boost.set_meta('bonus_move_armor_counters', boost.get_meta('bonus_move_armor_counters', 0) + move_amount * boost_effect.get('amount', 1))

	# Logging.
	var card_names = ""
	if card_ids.size() > 0:
		card_names = card_db.get_card_name(card_ids[0])
		for i in range(1, card_ids.size()):
			card_names += ", " + card_db.get_card_name(card_ids[i])
	else:
		card_names = "passive bonus"
	_append_log_full(Enums.LogType.LogType_Action, performing_player, "回合行动：移动")
	if len(card_ids) > 0:
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "通过弃置%s生成能量以移动。" % _log_card_name(card_names))
	_append_log_full(Enums.LogType.LogType_CharacterMovement, performing_player, "从格子%s移动到%s。" % [str(old_location), str(new_arena_location)])

	# On move effects, treat same as character action.
	var effects = get_all_effects_for_timing("on_move_action", performing_player, null)
	add_queued_effects(effects)
	active_character_action = true
	if game_state != Enums.GameState.GameState_PlayerDecision:
		set_player_action_processing_state()
		continue_player_action_resolution(performing_player)
	return true

func do_change(performing_player : Player, card_ids, treat_ultras_as_single_force : bool, use_free_force : bool = false, spent_life_for_force : int = 0) -> bool:
	printlog("MainAction: CHANGE_CARDS by %s - %s" % [performing_player.name, card_ids])
	if not performing_player.validate_heiqiyihu_payment(card_ids):
		return false
	if not can_do_change(performing_player):
		printlog("ERROR: Cannot do change action for this player.")
		return false

	var has_card_from_gauge = false
	for id in card_ids:
		if performing_player.is_card_in_gauge(id):
			has_card_from_gauge = true

		if not performing_player.is_card_in_hand(id) and not performing_player.is_card_in_gauge(id) \
		and not performing_player.is_heiqiyihu_guardian_resource(id):
			# Card not found, error
			printlog("ERROR: Tried to discard cards that aren't in hand or gauge.")
			return false

	create_event(Enums.EventType.EventType_ChangeCards, performing_player.my_id, 0)
	var force_generated = performing_player.get_force_with_cards(card_ids, "CHANGE_CARDS", treat_ultras_as_single_force, use_free_force)
	performing_player.discard(card_ids, 0, true)

	force_generated += performing_player.get_force_from_spent_life(spent_life_for_force)
	if not handle_spend_life_for_force(performing_player, spent_life_for_force):
		return false
	if game_over:
		return true

	# Handle Guile's Change Cards strike bonus
	var can_strike_after_change = false
	if performing_player.guile_change_cards_bonus and has_card_from_gauge and performing_player.exceeded:
		can_strike_after_change = true

	_append_log_full(Enums.LogType.LogType_Action, performing_player, "回合行动：换牌")
	if len(card_ids) > 0:
		var card_names = card_db.get_card_names(card_ids)
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "通过弃置%s生成能量。" % _log_card_name(card_names))
	else:
		_append_log_full(Enums.LogType.LogType_Effect, performing_player, "生成%s能量。" % force_generated)
	_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "抽%s张牌。" % force_generated)
	performing_player.draw(force_generated)
	performing_player.total_force_spent_this_turn += force_generated

	active_change_cards = true
	# Handle Guile's Exceed strike bonus
	# Otherwise just end the turn.
	if can_strike_after_change:
		# Need to give the player a choice to strike.
		handle_strike_effect(
			-1,
			{
				"effect_type": StrikeEffects.Choice,
				StrikeEffects.Choice: [
					{ "effect_type": StrikeEffects.Strike },
					{ "effect_type": StrikeEffects.Pass }
				]
			},
			performing_player
		)
	else:
		set_player_action_processing_state()
		continue_player_action_resolution(performing_player)

	return true

func do_exceed(performing_player : Player, card_ids : Array, spent_life_for_gauge : int = 0) -> bool:
	printlog("MainAction: EXCEED by %s - %s" % [performing_player.name, card_ids])
	if not performing_player.validate_heiqiyihu_payment(card_ids, true):
		return false
	if game_state != Enums.GameState.GameState_PickAction:
		printlog("ERROR: Tried to exceed but not in correct game state.")
		return false
	if performing_player.my_id != active_turn_player:
		printlog("ERROR: Tried to exceed for wrong player.")
		return false
	for id in card_ids:
		if not performing_player.is_card_in_gauge(id) and not performing_player.is_heiqiyihu_guardian_resource(id):
			# Card not found, error
			printlog("ERROR: Tried to exceed with cards that not in gauge.")
			return false

	var gauge_from_life = performing_player.get_gauge_from_spent_life(spent_life_for_gauge)
	# 按支付点数算：「枪灵」一类在怒气区的卡值 2 点（原先是 len(card_ids) 按张数）
	var total_gauge_available = performing_player.get_gauge_payment_value_for_cards(card_ids) + gauge_from_life + min(performing_player.free_gauge, performing_player.get_exceed_cost())
	if total_gauge_available < performing_player.get_exceed_cost():
		printlog("ERROR: Tried to exceed with too few cards.")
		return false

	performing_player.free_gauge = 0

	if spent_life_for_gauge > 0:
		performing_player.spend_life(spent_life_for_gauge)
		_append_log_full(Enums.LogType.LogType_Health, performing_player, "花费%s生命，为觉醒生成%s怒气！" % [str(spent_life_for_gauge), str(gauge_from_life)])

	_append_log_full(Enums.LogType.LogType_Action, performing_player, "回合行动：觉醒")
	if performing_player.has_overdrive:
		performing_player.move_cards_to_overdrive(card_ids, "gauge")
	else:
		var card_names = card_db.get_card_names(card_ids)
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "从怒气中花费%s张牌：%s" % [len(card_ids), _log_card_name(card_names)])
		performing_player.discard(card_ids, 0, true)

	performing_player.exceed()
	if game_state == Enums.GameState.GameState_AutoStrike:
		performing_player.face_attack_id = decision_info.effect_type
		if _has_heiqiyihu_guardian_option():
			# The rule specifies a face attack, not a card chosen by the
			# player. Leave it in set-aside until guardians finish.
			heiqiyihu_pending_strike_request = {
				"player": performing_player.my_id,
				"opponent_first": false,
				"required_wild": false,
				"required_face_attack": true
			}
			change_game_state(Enums.GameState.GameState_PickAction)
			_begin_pending_heiqiyihu_strike()
			return true
		var card = _prepare_face_attack_for_strike(performing_player)
		if not card:
			printlog("ERROR: Tried to auto-strike with a missing set aside card.")
			return false
		# Strike with it
		change_game_state(Enums.GameState.GameState_PickAction)
		do_strike(performing_player, card.id, false, -1)
	elif game_state != Enums.GameState.GameState_WaitForStrike and game_state != Enums.GameState.GameState_PlayerDecision:
		active_exceed = true
		set_player_action_processing_state()
		continue_player_action_resolution(performing_player)
	elif game_state == Enums.GameState.GameState_PlayerDecision:
		# Some other player action will result in the end turn finishing.
		# Striking is the end of an exceed so don't set this to true.
		active_exceed = true
	return true

func do_boost(performing_player : Player, card_id : int, payment_card_ids : Array = [], use_free_force = false, spent_life_for_force : int = 0, additional_boost_ids : Array = [], facedown_override = null) -> bool:
	printlog("MainAction: BOOST by %s - %s" % [get_player_name(performing_player.my_id), card_db.get_card_id(card_id)])
	if game_state != Enums.GameState.GameState_PickAction or performing_player.my_id != active_turn_player:
		if not wait_for_mid_strike_boost():
			printlog("ERROR: Tried to boost but not your turn")
			assert(false)
			return false

	var card = card_db.get_card(card_id)
	if not performing_player.validate_heiqiyihu_payment(payment_card_ids, card.definition["boost"].has("gauge_cost")):
		return false
	if performing_player.deck_def.get("id") == "heiqiyihu" and card_id in payment_card_ids:
		printlog("ERROR: A boost cannot also be its own payment.")
		return false
	if facedown_override != null and card.definition['boost']['boost_type'] == "continuous":
		if facedown_override:
			card.definition["boost"]["facedown"] = true
		elif "facedown" in card.definition["boost"]:
			card.definition["boost"].erase("facedown")
	if card.definition["boost"].get("reaction_only", false):
		printlog("ERROR: Reaction-only cards cannot be played as boosts.")
		return false
	# Umina Spiraling Descent: opponent cannot boost copies of the Dreamlands card
	var uma_sd_opponent = _get_player(get_other_player(performing_player.my_id))
	if uma_sd_opponent.deck_def.get("id") == "umina" and uma_sd_opponent.has_transform("umina_dark_thoughts"):
		var uma_sd_banned = uma_sd_opponent.get_umina_spiraling_target()
		if uma_sd_banned != "" and _is_spiraling_match(uma_sd_banned, card):
			printlog("Spiraling Descent: %s cannot boost %s" % [get_player_name(performing_player.my_id), card_db.get_card_name(card_id)])
			return false
	# Redirection to transform handler
	if card.definition['boost']['boost_type'] == "transform" or (performing_player.deck_def.get("id") == "tournelouse" and card.definition['type'] == "normal" and not performing_player.exceeded and (len(payment_card_ids) == 1 or decision_info.limitation == "transform")):
		if len(payment_card_ids) == 1 or decision_info.limitation == "transform":
			var ex_card_id = -1
			if len(payment_card_ids) > 0:
				ex_card_id = payment_card_ids[0]
			return do_ex_transform(performing_player, card_id, ex_card_id)
		else:
			printlog("ERROR: Tried to transform as action without a second copy")
			assert(false)
			return false

	if card.definition['boost']['boost_type'] == "overload":
		printlog("ERROR: Tried to boost a card with an overload")
		assert(false)
		return false

	# boost_type "none"（如 carcass 的「枪灵」）：卡面显示 N/A，不可以作为加成打出。
	if card.definition['boost']['boost_type'] == "none":
		printlog("ERROR: Tried to boost a card whose boost is N/A")
		return false

	if not decision_info.ignore_costs:
		if 'gauge_cost' in card.definition['boost']:
			var gauge_cost = card.definition['boost']['gauge_cost']
			# 按支付点数算：「枪灵」一类在怒气区的卡值 2 点（原先是 len(payment_card_ids) 按张数）
			var generated_gauge = performing_player.get_gauge_payment_value_for_cards(payment_card_ids) + performing_player.free_gauge
			if generated_gauge < gauge_cost:
				printlog("ERROR: Tried to boost action but can't pay gauge cost with these cards.")
				return false
		else:
			var force_cost = card.definition['boost']['force_cost']
			# Treasure exceeded UA: on your turn, your boost Force costs are reduced by 1.
			if game_state == Enums.GameState.GameState_PickAction \
					and performing_player.my_id == active_turn_player \
					and performing_player.deck_def.get("id") == "treasure" \
					and performing_player.exceeded:
				force_cost = max(0, force_cost - 1)
			if not performing_player.can_pay_cost_with(payment_card_ids, force_cost, 0, use_free_force, spent_life_for_force):
				printlog("ERROR: Tried to boost action but can't pay force cost with these cards.")
				return false
			performing_player.total_force_spent_this_turn += force_cost

	if additional_boost_ids:
		if decision_info.amount <= 1:
			printlog("ERROR: Tried to boost with multiple cards when not allowed.")
			return false

	if game_state == Enums.GameState.GameState_PickAction:
		_append_log_full(Enums.LogType.LogType_Action, performing_player, "回合行动：加成")

	_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "加成%s。" % _get_boost_and_card_name(card))

	if payment_card_ids.size() > 0:
		var card_names = card_db.get_card_name(payment_card_ids[0])
		for i in range(1, payment_card_ids.size()):
			card_names += ", " + card_db.get_card_name(payment_card_ids[i])
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "弃置牌以支付该加成费用：%s。" % _log_card_name(card_names))
		performing_player.discard(payment_card_ids, 0, true)
	if not handle_spend_life_for_force(performing_player, spent_life_for_force):
		return false
	if game_over:
		return true

	var shuffle_discard_on_boost_cleanup = false or decision_info.extra_info

	# Bonus effects for playing a boost, assumed to be non-blocking
	if decision_info.bonus_effect:
		do_effect_if_condition_met(performing_player, -1, decision_info.bonus_effect, null)

	# Resolve character effects that happen after payment but before the boost itself.
	var before_boost_effects = performing_player.get_character_effects_at_timing("before_boost_effects")
	assert(len(before_boost_effects) <= 1, "Multiple before_boost_effects require explicit sequencing")
	for before_boost_effect in before_boost_effects:
		do_effect_if_condition_met(performing_player, -1, before_boost_effect, null)
		if game_state == Enums.GameState.GameState_PlayerDecision:
			preparing_boost_info = {
				'performing_player': performing_player,
				'card_id': card_id,
				'additional_boost_ids': additional_boost_ids,
				'shuffle_discard_on_boost_cleanup': shuffle_discard_on_boost_cleanup
			}
			return true

	begin_resolve_boost(performing_player, card_id, additional_boost_ids, shuffle_discard_on_boost_cleanup)
	return true

func do_ex_transform(performing_player : Player, card_id : int, ex_card_id : int, continue_after_transform : bool = true, allow_single_card_transform : bool = false):
	printlog("Redirected to EX Transform")
	var card = card_db.get_card(card_id)
	var is_tournelouse_transform_choice = performing_player.deck_def.get("id") == "tournelouse" and \
		decision_info.type == Enums.DecisionType.DecisionType_EffectChoice and \
		performing_player.my_id == decision_info.player
	var is_tournelouse_ouroboros_transform_choice = performing_player.deck_def.get("id") == "tournelouse" and \
		decision_info.type == Enums.DecisionType.DecisionType_ChooseFromBoosts and \
		decision_info.effect != null and decision_info.effect.get("tournelouse_ouroboros_return_transform") and \
		performing_player.my_id == decision_info.player
	if not (game_state == Enums.GameState.GameState_PickAction and performing_player.my_id == active_turn_player) and \
	   not (decision_info.limitation == "transform" and performing_player.my_id == decision_info.player) and \
	   not is_tournelouse_transform_choice and \
	   not is_tournelouse_ouroboros_transform_choice:
		printlog("ERROR: Tried to EX transform but not your turn")
		assert(false)
		return false

	var is_tournelouse_normal_pre_exceed = performing_player.deck_def.get("id") == "tournelouse" and card.definition['type'] == "normal" and not performing_player.exceeded
	if card.definition['boost']['boost_type'] != "transform":
		if not is_tournelouse_normal_pre_exceed:
			printlog("ERROR: Tried to transform a card without a transform")
			assert(false)
			return false
		card.definition["replaced_boost"] = card.definition["boost"].duplicate(true)
		card.definition["boost"] = {
			"boost_type": "transform",
			"force_cost": -1,
			"cancel_cost": -1,
			"display_name": card.definition['display_name'],
			"effects": [
				{
					"timing": "during_strike",
					"condition": "is_special_or_ultra_attack",
					"effect_type": StrikeEffects.Powerup,
					"amount": 1,
					"character_effect": true
				}
			],
			"description": "Transformed normal: +1 Power to Special/Ultra attacks"
		}

	if ex_card_id == -1:
		if not allow_single_card_transform and decision_info.limitation != "transform" and not is_tournelouse_normal_pre_exceed:
			printlog("ERROR: Tried to transform without a second card with invalid effect")
			assert(false)
			return false
	else:
		var ex_card = card_db.get_card(ex_card_id)
		if card.definition['display_name'] != ex_card.definition['display_name']:
			printlog("ERROR: Tried to EX transform with mismatching cards")
			assert(false)
			return false

	if performing_player.has_card_name_in_zone(card, "transform"):
		printlog("ERROR: Tried to transform a previously-transformed card")
		assert(false)
		return false

	if game_state == Enums.GameState.GameState_PickAction:
		_append_log_full(Enums.LogType.LogType_Action, performing_player, "回合行动：EX转化")
	_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "转化%s。" % _get_boost_and_card_name(card))

	var card_name = card.definition['display_name']
	if ex_card_id != -1:
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "弃置另一张%s的复制。" % _log_card_name(card_name))
		performing_player.discard([ex_card_id])

	if performing_player.is_card_in_hand(card_id):
		performing_player.remove_card_from_hand(card_id, true, false)
	elif performing_player.is_card_in_deck(card_id):
		performing_player.remove_card_from_deck(card_id)
	create_event(Enums.EventType.EventType_Boost_Played, performing_player.my_id, card_id, "Transform")
	performing_player.add_to_transforms(card)
	if active_strike:
		for boost_effect in card.definition['boost']['effects']:
			if boost_effect['timing'] == "during_strike":
				do_effect_if_condition_met(performing_player, card.id, boost_effect, null)

	# Handling immediate effects; expected to be non-blocking, mostly to establish toggles e.g.
	if not is_tournelouse_normal_pre_exceed:
		var effects = card_db.get_card_boost_effects_now_immediate(card)
		for effect in effects:
			do_effect_if_condition_met(performing_player, card_id, effect, null)

	if game_state == Enums.GameState.GameState_PickAction:
		check_hand_size_advance_turn(performing_player)
	elif continue_after_transform:
		change_game_state(Enums.GameState.GameState_Boost_Processing)
		continue_player_action_resolution(performing_player)

	return true

func do_strike(
	performing_player : Player,
	card_id : int,
	wild_strike: bool,
	ex_card_id : int,
	opponent_sets_first : bool = false,
	use_face_attack : bool = false
) -> bool:
	var guardian_declaration = not active_strike and _has_heiqiyihu_guardian_option()
	if guardian_declaration:
		printlog("MainAction: STRIKE declaration by %s (attack not selected)" % get_player_name(performing_player.my_id))
	else:
		printlog("MainAction: STRIKE by %s card %s wild %s" % [get_player_name(performing_player.my_id), card_db.get_card_id(card_id), str(wild_strike)])
	if not heiqiyihu_guardian_setup.is_empty():
		printlog("ERROR: Attack selection must wait for both guardian phases.")
		return false
	if game_state == Enums.GameState.GameState_PickAction:
		if performing_player.my_id != active_turn_player:
			printlog("ERROR: Tried to strike but not current player")
			return false
	elif game_state == Enums.GameState.GameState_Strike_Opponent_Response:
		if performing_player.my_id != get_other_player(active_turn_player):
			printlog("ERROR: Strike response from wrong player.")
			return false
	elif game_state == Enums.GameState.GameState_Strike_Opponent_Set_First:
		if performing_player.my_id != active_turn_player:
			printlog("ERROR: Tried to strike but not current player")
			return false
		if not opponent_sets_first:
			printlog("ERROR: Inconsistent state for opponent setting first on Strike.")
			return false
	elif game_state == Enums.GameState.GameState_WaitForStrike:
		if performing_player.my_id != decision_info.player:
			printlog("ERROR: Strike response from wrong player.")
			return false
	if guardian_declaration:
		return _declare_heiqiyihu_strike(performing_player, opponent_sets_first)
	var resuming_guardian_declaration = active_strike and active_strike.heiqiyihu_declared_before_set \
		and active_strike.initiator == performing_player and active_strike.initiator_card == null
	if resuming_guardian_declaration:
		opponent_sets_first = active_strike.opponent_sets_first

	# ex_card_id being non -1 means it is an extra strike option.
	var ex_strike = not wild_strike and ex_card_id != -1
	if str(decision_info.limitation) == "EX":
		if not ex_strike and not performing_player.has_ex_boost():
			printlog("ERROR: Tried to strike without an EX when one was required.")
			return false

	# 左右开弓：与不同名卡组成强力攻击时，永远视为左右开弓的强力攻击，
	# 无论玩家把它选为主攻击牌还是搭档牌，另一张牌都作为被弃掉的搭档牌。
	if ex_strike and card_db.get_card(card_id) != null and card_db.get_card(ex_card_id) != null:
		var main_def = card_db.get_card(card_id).definition
		var partner_def = card_db.get_card(ex_card_id).definition
		if partner_def.get("may_ex_with_any_card", false) and \
				not main_def.get("may_ex_with_any_card", false):
			var swapped_card_id = card_id
			card_id = ex_card_id
			ex_card_id = swapped_card_id

	if use_face_attack:
		var face_attack_card = _prepare_face_attack_for_strike(performing_player)
		if face_attack_card:
			card_id = face_attack_card.id
		else:
			printlog("ERROR: Could not find face attack to strike with.")
			return false

	var strike_set_from_face_attack = performing_player.next_strike_from_face_attack

	var strike_from_boosts = false
	if performing_player.next_strike_from_gauge:
		if not wild_strike and not performing_player.is_card_in_gauge(card_id):
			if not (game_state == Enums.GameState.GameState_Strike_Opponent_Set_First or performing_player.next_strike_random_gauge):
				printlog("ERROR: Tried to strike with a card not in gauge.")
				return false
		if ex_strike:
			printlog("ERROR: Tried to ex strike from gauge.")
			return false
	elif performing_player.next_strike_from_sealed:
		if not wild_strike and not performing_player.is_card_in_sealed(card_id):
			if not game_state == Enums.GameState.GameState_Strike_Opponent_Set_First:
				printlog("ERROR: Tried to strike with a card not in sealed.")
				return false
		if ex_strike:
			printlog("ERROR: Tried to ex strike from sealed.")
			return false
	else:
		var strike_from_set_aside = false
		if wild_strike and ex_card_id != -1:
			# This is an extra strike option and the id is the extra strike index.
			if ex_card_id >= performing_player.get_extra_strike_options_count():
				printlog("ERROR: Tried to strike with an invalid extra strike id.")
				return false
		elif not wild_strike and not performing_player.is_card_in_hand(card_id):
			if performing_player.is_card_in_set_aside(card_id):
				# Umina 觉醒后幻梦境翻面变成 face attack，不能再直接选中幻梦境里的卡战斗
				# （只能通过 set_strike 封印其 before/hit/after 效果附加到攻击）。Eugenia 不受此限。
				if performing_player.deck_def.get("id") == "umina" and performing_player.exceeded:
					printlog("ERROR: Tried to strike with Dreamlands card after exceed.")
					return false
				strike_from_set_aside = true
			elif performing_player.is_card_in_continuous_boosts(card_id):
				strike_from_boosts = true
				var card = card_db.get_card(card_id)
				var must_set_from_boost = 'must_set_from_boost' in card.definition and card.definition['must_set_from_boost']
				var may_set_from_boost = 'may_set_from_boost' in card.definition and card.definition['may_set_from_boost']
				if not must_set_from_boost and not may_set_from_boost:
					printlog("ERROR: Tried to strike with a card not in hand.")
					return false
				elif ex_strike:
					printlog("ERROR: Tried to EX strike from boost area.")
					return false
			elif not strike_from_set_aside and not (game_state == Enums.GameState.GameState_Strike_Opponent_Set_First or performing_player.next_strike_random_gauge):
				printlog("ERROR: Tried to strike with a card not in hand.")
				return false
		if ex_strike and not performing_player.is_card_in_hand(ex_card_id):
			printlog("ERROR: Tried to strike with a ex card not in hand.")
			return false
	if ex_strike and not card_db.are_same_card(card_id, ex_card_id):
		var attack_card_def = card_db.get_card(card_id).definition
		var ex_card_def = card_db.get_card(ex_card_id).definition
		# 左右开弓（may_ex_with_any_card）：可与任意其他牌配对成强力攻击。
		var may_ex_with_any_card = attack_card_def.get("may_ex_with_any_card", false) or \
				ex_card_def.get("may_ex_with_any_card", false)
		if not may_ex_with_any_card and attack_card_def['type'] == "normal" and \
				ex_card_def['boost']['boost_type'] != "overload":
			printlog("ERROR: Tried to strike with a ex card that doesn't match.")
			return false

	# Begin the strike
	var delayed_wild_strike = wild_strike and performing_player.delayed_wild_strike

	# Lay down the strike
	match game_state:
		Enums.GameState.GameState_PickAction, Enums.GameState.GameState_WaitForStrike:
			if not opponent_sets_first and not resuming_guardian_declaration:
				initialize_new_strike(performing_player, opponent_sets_first)
				if game_state == Enums.GameState.GameState_PickAction:
					_append_log_full(Enums.LogType.LogType_Action, performing_player, "回合行动：战斗")
				_append_log_full(Enums.LogType.LogType_Strike, performing_player, "发起一场战斗！")

			if wild_strike and ex_card_id != -1:
				# This is striking with an extra strike option.
				var strike_option = performing_player.get_extra_strike_option(ex_card_id)
				active_strike.initiator_set_from_extra_strike_option = true
				_append_log_full(Enums.LogType.LogType_Strike, performing_player,
					"从%s设置其攻击。" % [strike_option["option_name"]])
				match strike_option["effect_type"]:
					"strike_with_buddy_card":
						# This effect assumes there is 1 card in the set aside zone.
						for effect in strike_option["special_effects"]:
							handle_strike_effect(-1, effect, performing_player)
						performing_player.strike_with_set_aside_card(0)
						card_id = active_strike.initiator_card.id
			elif wild_strike:
				_append_log_full(Enums.LogType.LogType_Strike, performing_player, "进行疯狂攻击！")
				performing_player.next_strike_from_gauge = false
				if delayed_wild_strike:
					performing_player.wild_strike_delayed()
				else:
					performing_player.wild_strike()
					if game_over:
						return true
					card_id = active_strike.initiator_card.id
			elif performing_player.next_strike_random_gauge:
				performing_player.random_gauge_strike()
				performing_player.next_strike_random_gauge = false
				if game_over:
					return true
				card_id = active_strike.initiator_card.id
			else:
				active_strike.initiator_card = card_db.get_card(card_id)
				if strike_set_from_face_attack:
					active_strike.initiator_set_from_face_attack = true
					performing_player.next_strike_from_face_attack = false
				if performing_player.next_strike_from_gauge:
					performing_player.remove_card_from_gauge(card_id)
					active_strike.initiator_set_from_gauge = true
					performing_player.next_strike_from_gauge = false
				elif performing_player.next_strike_from_sealed:
					performing_player.remove_card_from_sealed(card_id)
					performing_player.next_strike_from_sealed = false
				elif strike_from_boosts:
					if card_id in performing_player.boost_id_locations:
						active_strike.initiator_set_from_boost_space = performing_player.get_boost_location(card_id)
					performing_player.remove_from_continuous_boosts(card_db.get_card(card_id), StrikeEffects.Strike)
					active_strike.initiator_set_from_boosts = true
					# 标注攻击源位置，方便双方查看（最多 2 张地面炸弹，靠位置区分）
					if active_strike.initiator_set_from_boost_space != -1:
						var wof_boost_name = card_db.get_card(card_id).definition.get("boost", {}).get("display_name", "加成")
						_append_log_full(Enums.LogType.LogType_Strike, performing_player,
							"从加成区的%s（位置%s）设置攻击。" % [wof_boost_name, str(active_strike.initiator_set_from_boost_space)])
				elif performing_player.is_card_in_set_aside(card_id) and performing_player.deck_def.get("id") in ["eugenia", "umina"]:
					# Eugenia strikes with a real card directly from Wonderland (set-aside);
					# Umina strikes with a real card directly from Dreamlands (set-aside).
					# The card leaves the special zone and resolves normally after the strike
					# (gauge on hit, discard otherwise). Other characters that use a set-aside
					# card copy it into hand first (e.g. Happy Chaos "Deus Ex Machina") and
					# must keep the original in set-aside for reuse on a later exceed.
					performing_player.remove_from_set_aside(card_id)
					active_strike.initiator.next_strike_faceup = true
					var set_aside_zone_name = performing_player.deck_def.get("stored_zone_info", {}).get("name", "set-aside")
					_append_log_full(Enums.LogType.LogType_Strike, performing_player, "sets their attack from %s!" % set_aside_zone_name)
					# Umina Dreamlands stun immunity (non-exceeded only): set here at commit
					# time so it does not depend on the card still being in set-aside at reveal.
					if performing_player.deck_def.get("id") == "umina" and not performing_player.exceeded and performing_player.deck_def.get("dreamlands_config", {}).get("stun_immunity"):
						performing_player.strike_stat_boosts.stun_immunity = true
						_append_log_full(Enums.LogType.LogType_Effect, performing_player, "has stun immunity from Dreamlands!")
						create_event(Enums.EventType.EventType_Strike_CharacterEffect, performing_player.my_id, -1, "", {"character_effect": true, "override_description": "Stun Immune (Dreamlands)"})
					if performing_player.deck_def.get("id") == "eugenia" and performing_player.exceeded:
						var power_effect = {"effect_type": StrikeEffects.Powerup, "amount": 1, "character_effect": true}
						var speed_effect = {"effect_type": StrikeEffects.Speedup, "amount": 1, "character_effect": true}
						handle_strike_effect(-1, power_effect, performing_player)
						handle_strike_effect(-1, speed_effect, performing_player)
				else:
					performing_player.remove_card_from_hand(card_id, false, true)

				if ex_strike:
					_append_log_full(Enums.LogType.LogType_Strike, performing_player, "设置一个强力攻击！")
					active_strike.initiator_ex_card = card_db.get_card(ex_card_id)
					performing_player.remove_card_from_hand(ex_card_id, false, true)
				else:
					_append_log_full(Enums.LogType.LogType_Strike, performing_player, "设置其攻击。")

			var reveal_immediately = false
			if active_strike.initiator.next_strike_faceup or strike_from_boosts:
				reveal_immediately = true
				active_strike.initiator_set_face_up = true
				active_strike.initiator.next_strike_faceup = false
				var card_name = card_db.get_card_name(card_id)
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将%s设为明置攻击！" % _log_card_name(card_name))

			# Eugenia wonderland bonus: +1 Power and +1 Speed (applied after initialize_new_strike cleared boosts)
			if use_face_attack and performing_player.deck_def.get("id") == "eugenia" and performing_player.exceeded:
				var power_effect = {"effect_type": StrikeEffects.Powerup, "amount": 1, "character_effect": true}
				var speed_effect = {"effect_type": StrikeEffects.Speedup, "amount": 1, "character_effect": true}
				handle_strike_effect(-1, power_effect, performing_player)
				handle_strike_effect(-1, speed_effect, performing_player)

			if performing_player.deck_def.get("id") == "minato" and performing_player.exceeded and performing_player.minato_seal_power_bonus > 0:
				var minato_power_amt = performing_player.minato_seal_power_bonus
				create_event(Enums.EventType.EventType_Strike_CharacterEffect, performing_player.my_id, -1, "", {"character_effect": true, "override_description": "觉醒：下一次攻击获得+%d威力。" % minato_power_amt})
				handle_strike_effect(-1, {"effect_type": StrikeEffects.Powerup, "amount": minato_power_amt, "character_effect": true, "override_description": "觉醒：下一次攻击获得+%d威力。" % minato_power_amt}, performing_player)
			if opponent.deck_def.get("id") == "minato" and opponent.exceeded and opponent.minato_seal_power_bonus > 0:
				var minato_power_amt_o = opponent.minato_seal_power_bonus
				create_event(Enums.EventType.EventType_Strike_CharacterEffect, opponent.my_id, -1, "", {"character_effect": true, "override_description": "觉醒：下一次攻击获得+%d威力。" % minato_power_amt_o})
				handle_strike_effect(-1, {"effect_type": StrikeEffects.Powerup, "amount": minato_power_amt_o, "character_effect": true, "override_description": "觉醒：下一次攻击获得+%d威力。" % minato_power_amt_o}, opponent)

			# Send the EX first as that is visual and logic is triggered off the regular one.
			if not delayed_wild_strike:
				if ex_strike:
					create_event(Enums.EventType.EventType_Strike_Started_Ex, performing_player.my_id, ex_card_id, "", reveal_immediately)
				create_event(Enums.EventType.EventType_Strike_Started, performing_player.my_id, card_id, "", reveal_immediately, ex_strike)
			continue_setup_strike()

		Enums.GameState.GameState_Strike_Opponent_Set_First:
			if opponent_sets_first: # should always be true
				if not resuming_guardian_declaration:
					initialize_new_strike(performing_player, opponent_sets_first)
				var opponent_name = _get_player(get_other_player(performing_player.my_id)).name
				_append_log_full(Enums.LogType.LogType_Strike, performing_player, "发起一场战斗！%s将先设置其攻击。" % opponent_name)
				if performing_player.deck_def.get("id") == "minato" and performing_player.exceeded and performing_player.minato_seal_power_bonus > 0:
					var minato_pw = performing_player.minato_seal_power_bonus
					create_event(Enums.EventType.EventType_Strike_CharacterEffect, performing_player.my_id, -1, "", {"character_effect": true, "override_description": "觉醒：下一次攻击获得+%d威力。" % minato_pw})
					handle_strike_effect(-1, {"effect_type": StrikeEffects.Powerup, "amount": minato_pw, "character_effect": true, "override_description": "觉醒：下一次攻击获得+%d威力。" % minato_pw}, performing_player)
				if opponent.deck_def.get("id") == "minato" and opponent.exceeded and opponent.minato_seal_power_bonus > 0:
					var minato_pw_o = opponent.minato_seal_power_bonus
					create_event(Enums.EventType.EventType_Strike_CharacterEffect, opponent.my_id, -1, "", {"character_effect": true, "override_description": "觉醒：下一次攻击获得+%d威力。" % minato_pw_o})
					handle_strike_effect(-1, {"effect_type": StrikeEffects.Powerup, "amount": minato_pw_o, "character_effect": true, "override_description": "觉醒：下一次攻击获得+%d威力。" % minato_pw_o}, opponent)
				continue_setup_strike()

		Enums.GameState.GameState_Strike_Opponent_Response:
			if active_strike.waiting_for_reading_response:
				active_strike.waiting_for_reading_response = false
				# Reset effect counter due to reading card choice
				active_strike.effects_resolved_in_timing = 0

			if wild_strike and ex_card_id != -1:
				# This is striking with an extra strike option.
				var strike_option = performing_player.get_extra_strike_option(ex_card_id)
				_append_log_full(Enums.LogType.LogType_Strike, performing_player,
					"从%s设置其攻击。" % [strike_option["option_name"]])
				match strike_option["effect_type"]:
					"strike_with_buddy_card":
						# This effect assumes there is 1 card in the set aside zone.
						for effect in strike_option["special_effects"]:
							handle_strike_effect(-1, effect, performing_player)
						performing_player.strike_with_set_aside_card(0)
						card_id = active_strike.defender_card.id
			elif wild_strike:
				_append_log_full(Enums.LogType.LogType_Strike, performing_player, "进行疯狂攻击！")
				if delayed_wild_strike:
					performing_player.wild_strike_delayed()
				else:
					performing_player.wild_strike()
					if game_over:
						return true
					card_id = active_strike.defender_card.id
			else:
				active_strike.defender_card = card_db.get_card(card_id)
				if strike_set_from_face_attack:
					active_strike.defender_set_from_face_attack = true
					performing_player.next_strike_from_face_attack = false
				if strike_from_boosts:
					if card_id in performing_player.boost_id_locations:
						active_strike.defender_set_from_boost_space = performing_player.get_boost_location(card_id)
					performing_player.remove_from_continuous_boosts(card_db.get_card(card_id), StrikeEffects.Strike)
					active_strike.defender_set_from_boosts = true
					# 标注攻击源位置，方便双方查看（最多 2 张地面炸弹，靠位置区分）
					if active_strike.defender_set_from_boost_space != -1:
						var wof_boost_name = card_db.get_card(card_id).definition.get("boost", {}).get("display_name", "加成")
						_append_log_full(Enums.LogType.LogType_Strike, performing_player,
							"从加成区的%s（位置%s）设置攻击。" % [wof_boost_name, str(active_strike.defender_set_from_boost_space)])
				elif performing_player.is_card_in_set_aside(card_id) and performing_player.deck_def.get("id") in ["eugenia", "umina"]:
					# Defender responds with a real card directly from Wonderland/Dreamlands
					# (set-aside). It leaves the special zone and resolves normally.
					performing_player.remove_from_set_aside(card_id)
					active_strike.defender.next_strike_faceup = true
					var defend_set_aside_zone_name = performing_player.deck_def.get("stored_zone_info", {}).get("name", "set-aside")
					_append_log_full(Enums.LogType.LogType_Strike, performing_player, "sets their attack from %s!" % defend_set_aside_zone_name)
					# Eugenia exceeded：用奇境卡牌战斗 +1 威力 / +1 速度。
					# 与发起方同一写法（内联在这一支里），不要靠通用的「明置」标记去判：
					# next_strike_faceup 是**玩家级、跨战斗残留**的标记，之前防御方的加成读它，
					# 导致之后任何一次应战（包括疯狂攻击）都被当成奇境面攻而多吃 +1/+1。
					if performing_player.deck_def.get("id") == "eugenia" and performing_player.exceeded:
						handle_strike_effect(-1, {"effect_type": StrikeEffects.Powerup, "amount": 1, "character_effect": true}, performing_player)
						handle_strike_effect(-1, {"effect_type": StrikeEffects.Speedup, "amount": 1, "character_effect": true}, performing_player)
					active_strike.defender.next_strike_faceup = false
					# Umina Dreamlands stun immunity (non-exceeded only): set here at commit
					# time so it does not depend on the card still being in set-aside at reveal.
					if performing_player.deck_def.get("id") == "umina" and not performing_player.exceeded and performing_player.deck_def.get("dreamlands_config", {}).get("stun_immunity"):
						performing_player.strike_stat_boosts.stun_immunity = true
						_append_log_full(Enums.LogType.LogType_Effect, performing_player, "has stun immunity from Dreamlands!")
						create_event(Enums.EventType.EventType_Strike_CharacterEffect, performing_player.my_id, -1, "", {"character_effect": true, "override_description": "Stun Immune (Dreamlands)"})
				else:
					performing_player.remove_card_from_hand(card_id, false, true)

				if ex_strike:
					_append_log_full(Enums.LogType.LogType_Strike, performing_player, "设置一个强力攻击！")
					active_strike.defender_ex_card = card_db.get_card(ex_card_id)
					performing_player.remove_card_from_hand(ex_card_id, false, true)
				else:
					_append_log_full(Enums.LogType.LogType_Strike, performing_player, "设置其攻击。")

			if not delayed_wild_strike:
				# Send the EX first as that is visual and logic is triggered off the regular one.
				if ex_strike:
					create_event(Enums.EventType.EventType_Strike_Response_Ex, performing_player.my_id, ex_card_id)
				create_event(Enums.EventType.EventType_Strike_Response, performing_player.my_id, card_id, "", strike_from_boosts, ex_strike)
			# Eugenia wonderland bonus: defender face attack
			# 只认「本次战斗确实是用奇境面攻应战」（use_face_attack / 上面那一支已内联加过）。
			# 不要再读 defender.next_strike_faceup —— 那是玩家级残留标记，会让疯狂攻击也吃 +1/+1。
			if use_face_attack and performing_player.deck_def.get("id") == "eugenia" and performing_player.exceeded:
				var power_effect = {"effect_type": StrikeEffects.Powerup, "amount": 1, "character_effect": true}
				var speed_effect = {"effect_type": StrikeEffects.Speedup, "amount": 1, "character_effect": true}
				handle_strike_effect(-1, power_effect, performing_player)
				handle_strike_effect(-1, speed_effect, performing_player)
			continue_setup_strike()
	return true

func do_pay_strike_cost(
	performing_player : Player,
	card_ids : Array,
	wild_strike : bool,
	discard_ex_first : bool = true,
	use_free_force = false,
	spent_life_for_force : int = 0,
	pay_alternative_life_cost : bool = false,
	spent_life_for_gauge : int = 0
	) -> bool:
	printlog("SubAction: PAY_STRIKE by %s cards %s wild %s" % [performing_player.name, card_ids, str(wild_strike)])
	if game_state != Enums.GameState.GameState_PlayerDecision:
		printlog("ERROR: Tried to pay costs but not in decision state.")
		return false
	if decision_info.type != Enums.DecisionType.DecisionType_PayStrikeCost_CanWild and decision_info.type != Enums.DecisionType.DecisionType_PayStrikeCost_Required:
		printlog("ERROR: Tried to pay costs but not in correct decision type.")
		return false
	var card = active_strike.get_player_card(performing_player)
	if decision_info.type == Enums.DecisionType.DecisionType_PayStrikeCost_Required and wild_strike:
		# Only allowed if you can't pay the cost.
		var force_cost = get_force_cost(performing_player, card)
		var gauge_cost = get_gauge_cost(performing_player, card)
		if performing_player.can_pay_cost(force_cost, gauge_cost):
			printlog("ERROR: Tried to wild strike when not allowed.")
			return false
	if decision_info.player != performing_player.my_id:
		printlog("ERROR: Tried to pay costs for wrong player.")
		return false

	if wild_strike:
		var invalid_by_choice = decision_info.type == Enums.DecisionType.DecisionType_PayStrikeCost_CanWild
		_append_log_full(Enums.LogType.LogType_Strike, performing_player, "选择进行疯狂攻击，而不是验证%s。" % card.definition['display_name'])
		# Replace existing card with a wild strike
		var current_card = active_strike.get_player_card(performing_player)
		performing_player.invalidate_card(current_card, invalid_by_choice)
		performing_player.wild_strike(true)
		var new_card = active_strike.get_player_card(performing_player)
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "疯狂攻击%s！" % new_card.definition['display_name'])
		_resolve_pooky_reveal_after_paycost_wild_swing(performing_player)
	else:
		var force_cost = get_force_cost(performing_player, card)
		var gauge_cost = get_gauge_cost(performing_player, card)
		var alternative_life_cost = get_alternative_life_cost(performing_player, card)
		if alternative_life_cost == 0 and pay_alternative_life_cost:
			printlog("ERROR: Tried to pay alternative cost but there isn't one.")
			return false
		if performing_player.strike_stat_boosts.may_generate_gauge_with_force:
			# Convert the gauge cost to a force cost.
			force_cost = gauge_cost
			gauge_cost = 0

		if not pay_alternative_life_cost:
			# If they aren't paying the alternate cost, zero it out so it isn't considered.
			alternative_life_cost = 0

		if performing_player.can_pay_cost_with(
			card_ids,
			force_cost,
			gauge_cost,
			use_free_force,
			spent_life_for_force,
			alternative_life_cost,
			spent_life_for_gauge
			):
			performing_player.strike_stat_boosts.strike_payment_card_ids = card_ids
			if card_ids.size() > 0:
				var card_names = card_db.get_card_name(card_ids[0])
				for i in range(1, card_ids.size()):
					card_names += ", " + card_db.get_card_name(card_ids[i])
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "通过弃置%s进行验证。" % _log_card_name(card_names))
			else:
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "通过被动加成进行验证。")

			if not handle_spend_life_for_force(performing_player, spent_life_for_force):
				return false
			if spent_life_for_gauge > 0:
				performing_player.spend_life(spent_life_for_gauge)
				_append_log_full(Enums.LogType.LogType_Health, performing_player, "花费%s生命以生成怒气！" % [str(spent_life_for_gauge)])
			if pay_alternative_life_cost and not handle_spend_life_cost(performing_player, alternative_life_cost):
				return false

			if game_over:
				return true

			var where_to_discard = 0
			if not discard_ex_first and active_strike.get_player_ex_card(performing_player) != null:
				where_to_discard = 1
			var cards_to_discard = []
			var transforms_to_seal = []
			for payment_card_id in card_ids:
				if performing_player.tournelouse_may_seal_for_gauge and performing_player.is_card_in_transforms(payment_card_id):
					transforms_to_seal.append(payment_card_id)
				else:
					cards_to_discard.append(payment_card_id)
			if cards_to_discard.size() > 0:
				performing_player.discard(cards_to_discard, where_to_discard, true)
			for transform_card_id in transforms_to_seal:
				var transform_card = card_db.get_card(transform_card_id)
				performing_player.remove_from_transforms(transform_card)
				performing_player.add_to_sealed(transform_card)
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "封印%s来生成怒气。" % _log_card_name(transform_card.definition['display_name']))
			performing_player.tournelouse_may_seal_for_gauge = false
			performing_player.total_force_spent_this_turn += force_cost

			if active_strike.extra_attack_in_progress:
				active_strike.extra_attack_data.extra_attack_state = ExtraAttackState.ExtraAttackState_DuringStrikeBonuses
			else:
				match active_strike.strike_state:
					StrikeState.StrikeState_Initiator_PayCosts:
						active_strike.strike_state = StrikeState.StrikeState_Defender_PayCosts
					StrikeState.StrikeState_Defender_PayCosts:
						active_strike.strike_state = StrikeState.StrikeState_DuringStrikeBonuses
		else:
			printlog("ERROR: Tried to pay costs but not correct cards.")
			return false
	continue_resolve_strike()
	return true

func do_force_for_armor(performing_player : Player, card_ids : Array, use_free_force : bool = false, spent_life_for_force : int = 0) -> bool:
	printlog("SubAction: FORCEARMOR by %s cards %s" % [performing_player.name, card_ids])
	if game_state != Enums.GameState.GameState_PlayerDecision or decision_info.type != Enums.DecisionType.DecisionType_ForceForArmor:
		printlog("ERROR: Tried to force for armor but not in decision state.")
		return false
	if decision_info.player != performing_player.my_id:
		printlog("ERROR: Tried to force for armor for wrong player.")
		return false

	var use_gauge_instead = decision_info.limitation == "gauge"
	if not performing_player.validate_heiqiyihu_payment(card_ids, use_gauge_instead):
		return false
	if use_gauge_instead:
		for card_id in card_ids:
			if not performing_player.is_card_in_gauge(card_id) and not performing_player.is_heiqiyihu_guardian_resource(card_id):
				printlog("ERROR: Tried to force(gauge) for armor with card not in gauge.")
				return false
	else:
		for card_id in card_ids:
			if not performing_player.is_card_in_hand(card_id) and not performing_player.is_card_in_gauge(card_id) \
			and not performing_player.is_heiqiyihu_guardian_resource(card_id):
				printlog("ERROR: Tried to force for armor with card not in hand or gauge.")
				return false

	var force_generated = 0
	if use_gauge_instead:
		# 用怒气卡顶能量换护甲（Snow Slash 一类）。原先是按张数 len(card_ids)，
		# 但「枪灵」这类卡在怒气区应按点数算（2 点），所以逐张取支付点数。
		force_generated = performing_player.get_gauge_payment_value_for_cards(card_ids)
	else:
		force_generated = performing_player.get_force_with_cards(card_ids, "FORCE_FOR_ARMOR", false, use_free_force)
	force_generated += performing_player.get_force_from_spent_life(spent_life_for_force)
	if not handle_spend_life_for_force(performing_player, spent_life_for_force):
		return false
	if game_over:
		return true
	performing_player.total_force_spent_this_turn += force_generated

	if force_generated > 0:
		var card_names = ""
		if card_ids.size() > 0:
			card_names = card_db.get_card_name(card_ids[0])
			for i in range(1, card_ids.size()):
				card_names += ", " + card_db.get_card_name(card_ids[i])
		else:
			card_names = "passive bonus"
		if use_gauge_instead:
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "花费怒气获得护甲：%s。" % _log_card_name(card_names))
		else:
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "弃置牌作为获得护甲的能量：%s。" % _log_card_name(card_names))
		var armor_per_force = performing_player.force_for_armor_apf_tmp if performing_player.force_for_armor_apf_tmp > 0 else decision_info.amount
		performing_player.force_for_armor_apf_tmp = 0
		var saved_source = _last_effect_source_player_id
		_last_effect_source_player_id = -1
		var spent_gauge_with_holywarding = (
			performing_player.transforms.any(func(card): return card.definition.get("id") == "emogine_holywarding")
			and card_ids.any(func(card_id): return performing_player.is_card_in_gauge(card_id))
		)
		performing_player.discard(card_ids, 0, spent_gauge_with_holywarding)
		_last_effect_source_player_id = saved_source
		handle_strike_effect(decision_info.choice_card_id, {'effect_type': StrikeEffects.Armorup, 'amount': force_generated * armor_per_force}, performing_player)
	continue_resolve_strike()
	return true

func do_boost_cancel(performing_player : Player, gauge_card_ids : Array, doing_cancel : bool) -> bool:
	printlog("SubAction: BOOST_CANCEL by %s cards %s cancel %s" % [performing_player.name, gauge_card_ids, str(doing_cancel)])
	if not performing_player.validate_heiqiyihu_payment(gauge_card_ids, true):
		return false
	if game_state != Enums.GameState.GameState_PlayerDecision or decision_info.type != Enums.DecisionType.DecisionType_BoostCancel:
		printlog("ERROR: Tried to cancel boost but not in decision state.")
		return false
	if decision_info.player != performing_player.my_id:
		printlog("ERROR: Tried to boost cancel wrong player.")
		return false
	if not active_boost:
		printlog("ERROR: Tried to cancel boost but no active boost.")
		return false
	var cancel_cost = _get_effective_boost_cancel_cost(performing_player, active_boost.card)
	if cancel_cost < 0:
		printlog("ERROR: Tried to cancel boost but this boost cannot be canceled.")
		return false
	# 按支付点数算：「枪灵」一类在怒气区的卡值 2 点（原先是 len(gauge_card_ids) 按张数）
	if doing_cancel and performing_player.get_gauge_payment_value_for_cards(gauge_card_ids) < cancel_cost:
		printlog("ERROR: Tried to cancel boost with too few cards.")
		return false
	for id in gauge_card_ids:
		if not performing_player.is_card_in_gauge(id) and not performing_player.is_heiqiyihu_guardian_resource(id):
			# Card not found, error
			printlog("ERROR: Tried to cancel boost with cards that aren't in gauge.")
			return false

	change_game_state(Enums.GameState.GameState_Boost_Processing)

	if doing_cancel:
		var card_names = card_db.get_card_name(gauge_card_ids[0])
		for i in range(1, gauge_card_ids.size()):
			card_names += ", " + card_db.get_card_name(gauge_card_ids[i])
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "花费怒气以取消，弃置%s。" % _log_card_name(card_names))
		performing_player.discard(gauge_card_ids, 0, true)
		performing_player.on_cancel_boost()
		active_boost.action_after_boost = true

	# Ky, for example, has a choice after canceling the first time.
	if game_state != Enums.GameState.GameState_PlayerDecision:
		boost_play_cleanup(performing_player)
	return true

## Select cards from `performing_player`'s hand to be moved. The destination of
## the move is not specified, and is instead defined by the currently active
## decision.
func do_relocate_card_from_hand(performing_player : Player, card_ids : Array) -> bool:
	printlog("SubAction: RELOCATE_CARD_FROM_HAND by %s: %s" % [get_player_name(performing_player.my_id), card_ids])
	if decision_info.player != performing_player.my_id:
		printlog("ERROR: Tried to do_relocate_card_from_hand for wrong player.")
		return false
	if game_state != Enums.GameState.GameState_PlayerDecision or decision_info.type != Enums.DecisionType.DecisionType_CardFromHandToGauge:
		printlog("ERROR: Tried to do_relocate_card_from_hand but not in decision state.")
		return false
	for card_id in card_ids:
		var restricted_to_card_ids = decision_info.effect.get("restricted_to_card_ids", [])
		if restricted_to_card_ids:
			if not card_id in restricted_to_card_ids:
				printlog("ERROR: Tried to do_relocate_card_from_hand with card not in restricted list.")
				return false
		if not performing_player.is_card_in_hand(card_id):
			printlog("ERROR: Tried to do_relocate_card_from_hand with card not in hand.")
			return false

	if card_ids.size() > 0:
		for card_id in card_ids:
			if decision_info.destination == "gauge":
				performing_player.move_card_from_hand_to_gauge(card_id)
			elif decision_info.destination == "topdeck":
				performing_player.move_card_from_hand_to_deck(card_id)
			elif decision_info.destination == "bottomdeck":
				performing_player.move_card_from_hand_to_deck(card_id, 0, true)
			elif decision_info.destination == "deck":
				performing_player.shuffle_card_from_hand_to_deck(card_id)
			elif decision_info.destination == "stored_cards":
				var secret = performing_player.is_stored_zone_facedown()
				performing_player.move_card_from_hand_to_stored_cards(card_id, secret)
			elif decision_info.destination == "bleach":
				var pressure_card = card_db.get_card(card_id)
				performing_player.remove_card_from_hand(card_id, true, false)
				performing_player.add_to_bleach(pressure_card)
			elif decision_info.destination == "umina_dreamlands":
				# Umina Dreamlands: move card from hand to set_aside, handle old card
				var umina_ph_card = card_db.get_card(card_id)
				if umina_ph_card != null:
					if performing_player.set_aside_cards.size() > 0:
						var umina_ph_old = performing_player.set_aside_cards[0]
						if performing_player.exceeded and umina_ph_old.owner_id != performing_player.my_id:
							var umina_ph_owner = _get_player(umina_ph_old.owner_id)
							umina_ph_owner.add_to_hand(umina_ph_old, true)
						elif performing_player.exceeded:
							performing_player.add_to_hand(umina_ph_old, not performing_player.umina_dreamlands_facedown)
						else:
							performing_player.add_to_discards(umina_ph_old)
						performing_player.remove_card_from_set_aside(umina_ph_old.id)
					performing_player.remove_card_from_hand(card_id, not performing_player.umina_dreamlands_facedown, false)
					performing_player.add_to_set_aside(umina_ph_card)
					if performing_player.umina_dreamlands_facedown:
						performing_player.umina_facedown_hand_dreamlands_id = card_id
					_append_log_full(Enums.LogType.LogType_Effect, performing_player, "places %s into Dreamlands." % _log_card_name(umina_ph_card.id))
					create_event(Enums.EventType.EventType_AddToStored, performing_player.my_id, card_id)
					_umina_check_slipping_away(performing_player, card_id)
			else:
				assert(false, "Unhandled destination %s for do_relocate_card_from_hand" % decision_info.destination)

	# Log message
	if decision_info.destination == "gauge":
		var card_names = card_db.get_card_names(card_ids)
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将%s张牌从手牌移到怒气：%s" % [str(card_ids.size()), _log_card_name(card_names)])
	elif decision_info.destination == "topdeck":
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将%s张牌从手牌移到牌库顶。" % str(card_ids.size()))
	elif decision_info.destination == "bottomdeck":
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将%s张牌从手牌移到牌库底。" % str(card_ids.size()))
	elif decision_info.destination == "deck":
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将%s张手牌洗入牌库。" % str(card_ids.size()))
	elif decision_info.destination == "stored_cards":
		var stored_zone_name = performing_player.get_stored_zone_name()
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将%s张牌从手牌移到%s。" % [str(card_ids.size()), stored_zone_name])
	elif decision_info.destination == "bleach":
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将%s张牌从手牌移到%s。" % [str(card_ids.size()), performing_player.get_bleach_zone_name()])

	set_player_action_processing_state()

	if decision_info.bonus_effect and card_ids.size() > 0:
		var per_card_effect = decision_info.bonus_effect.duplicate()
		per_card_effect['amount'] = card_ids.size() * per_card_effect.get("amount", 1)
		do_effect_if_condition_met(performing_player, decision_info.choice_card_id, per_card_effect, null)

	continue_player_action_resolution(performing_player)
	return true

func do_boost_name_card_choice_effect(performing_player : Player, card_id : int) -> bool:
	var card_name = "the card " + card_db.get_card_name(card_id)
	if card_id == -1:
		card_name = "a nonexistent card"
	printlog("SubAction: BOOST_NAME_CARD by %s; named %s" % [get_player_name(performing_player.my_id), card_name])
	if decision_info.player != performing_player.my_id:
		printlog("ERROR: Tried to name card for wrong player.")
		return false
	if game_state != Enums.GameState.GameState_PlayerDecision:
		printlog("ERROR: Tried to make a choice but not in decision state.")
		return false

	var effect = {
		"effect_type": decision_info.effect_type,
		"card_id": card_id,
	}
	_append_log_full(Enums.LogType.LogType_Effect, performing_player, "指定%s。" % _log_card_name(card_name))
	set_player_action_processing_state()
	handle_strike_effect(decision_info.choice_card_id, effect, performing_player)
	continue_player_action_resolution(performing_player)
	return true

func do_choice(performing_player : Player, choice_index : int) -> bool:
	printlog("SubAction: CHOICE by %s card %s" % [performing_player.name, str(choice_index)])
	if not heiqiyihu_threshold_context.is_empty():
		return _do_heiqiyihu_threshold_choice(performing_player, choice_index)
	if not heiqiyihu_guardian_setup.is_empty() \
	and decision_info.effect_type == "heiqiyihu_guardian_before_set":
		return _do_heiqiyihu_guardian_choice(performing_player, choice_index)
	if decision_info.player != performing_player.my_id:
		printlog("ERROR: Tried to name card for wrong player.")
		return false
	if game_state != Enums.GameState.GameState_PlayerDecision:
		if _is_action_resolution_in_progress():
			printlog("Ignoring stale choice after resolution already continued.")
			return true
		printlog("ERROR: Tried to make a choice but not in decision state.")
		return false
	if decision_info.choice == null or choice_index >= len(decision_info.choice):
		printlog("ERROR: Tried to make a choice that doesn't exist.")
		return false

	var card_id = decision_info.choice_card_id
	var effect = decision_info.choice[choice_index].duplicate()
	if effect.get("effect_type") == StrikeEffects.HeiqiyihuGuardianSource \
	and effect.get("source") == "hand" \
	and not performing_player.is_card_in_hand(effect["guardian_card_id"]):
		printlog("ERROR: Guardian source is no longer in hand.")
		return false
	if effect.get("effect_type") == StrikeEffects.HeiqiyihuXuhuaRecoverCard \
	and not performing_player.is_card_in_discards(effect["paid_id"]):
		printlog("ERROR: Xuhua payment is no longer in the discard pile.")
		return false
	if effect.get("requires_sealed_cards", false) and performing_player.sealed.is_empty():
		printlog("ERROR: Tried to make a choice that requires sealed cards with an empty sealed area.")
		return false
	if effect.get("_choice_disabled", false) and active_strike and _is_strike_initiation_effect(effect):
		_append_log_full(Enums.LogType.LogType_Effect, performing_player, "战斗中不能再次发起战斗，该效果被跳过。")
		effect["effect_type"] = StrikeEffects.Pass
	if 'card_id' in effect:
		card_id = effect['card_id']
	var copying_effect = false
	if decision_info.effect_type:
		copying_effect = decision_info.effect_type in [StrikeEffects.CopyOtherHitEffect, StrikeEffects.CopyOtherAfterEffect]
	if decision_info.multiple_choice_amount > 1:
		# This is a "choose multiple" effect, so the player can choose again
		# from the remaining effects.
		# Add an "and" to the effect the player chose.
		# Only include choices from the original that weren't chosen.
		# NOTE: This assumes that none of the effects have "and" on them already.
		var remaining_choices = decision_info.multiple_choice_amount - 1
		var choice_list = []
		for i in range(decision_info.choice.size()):
			if i != choice_index:
				choice_list.append(decision_info.choice[i])
		var and_choice_effect = {
			"effect_type": StrikeEffects.Choice,
				StrikeEffects.Choice: choice_list,
				"multiple_amount": remaining_choices
		}
		effect['and'] = and_choice_effect

	set_player_action_processing_state()

	if decision_info.type == Enums.DecisionType.DecisionType_ChooseSimultaneousEffect:
		if copying_effect:
			# If we're duplicating an effect, no need to remove it yet
			decision_info.effect_type = ""
		else:
			# This was the player choosing what to do next.
			# Remove this effect from the remaining effects.
			erase_remaining_effect(get_base_remaining_effect(effect))

	if '_source_player_id' not in effect:
		if decision_info.source_player_id != -1:
			effect['_source_player_id'] = decision_info.source_player_id
		else:
			effect['_source_player_id'] = _last_effect_source_player_id

	var saved_source = _last_effect_source_player_id
	do_effect_if_condition_met(performing_player, card_id, effect, null)
	# Only restore the previous source when the effect resolved immediately.
	# If the effect left the game waiting on a decision (e.g. Fire's
	# ForceForEffect), keep the effect owner's source LIVE so that a payment
	# discard made during that decision is attributed to the effect owner and
	# not to a stale pre-effect source (which could wrongly trigger Eugenia's
	# "you made opponent discard" passive).
	if game_state != Enums.GameState.GameState_PlayerDecision:
		_last_effect_source_player_id = saved_source
	continue_player_action_resolution(performing_player)
	return true

func set_player_action_processing_state():
	if active_start_of_turn_effects or active_end_of_turn_effects or active_overdrive or active_boost \
	or active_character_action or active_exceed or active_change_cards or active_prepare \
	or active_special_draw_effect or active_post_action_effect or preparing_boost_info:
		game_state = Enums.GameState.GameState_Boost_Processing
	elif active_strike:
		game_state = Enums.GameState.GameState_Strike_Processing
	else:
		printlog("ERROR: Unexpected game state - no active thing to be resolving?")
		assert(false)

func continue_player_action_resolution(performing_player : Player):
	# This function is intended to be called at the end of the various do_* functions
	# that are called by the game wrapper to resolve player actions/decisions.
	if game_over:
		return
	if _begin_heiqiyihu_thresholds(performing_player):
		return
	if not heiqiyihu_guardian_setup.is_empty():
		if game_state != Enums.GameState.GameState_PlayerDecision:
			var guardian_owner = _get_player(heiqiyihu_guardian_setup["owner"])
			do_queued_effects(guardian_owner)
			_continue_heiqiyihu_guardian_setup()
		return
	if _begin_pending_heiqiyihu_strike():
		return

	# Renea pre-strike: continue processing next facedown effect
	# Don't proceed if a PlayerDecision is pending (e.g. a "now" effect created a choice)
	if performing_player.renea_pre_strike_effects.size() > 0 and performing_player.renea_pre_strike_index < performing_player.renea_pre_strike_effects.size() \
	and game_state != Enums.GameState.GameState_PlayerDecision:
		_renea_process_next(performing_player)
		return
	# Renea pre-strike: after the last effect's PlayerDecision resolves, fire ForceStartStrike
	if performing_player.renea_pre_strike_effects.size() > 0 and performing_player.renea_pre_strike_index >= performing_player.renea_pre_strike_effects.size():
		handle_strike_effect(-1, {"effect_type": "renea_pre_strike_done"}, performing_player)
		return
	if performing_player.renea_pre_strike_effects.size() == 0 and performing_player.renea_pre_strike_index == 0 and game_state == Enums.GameState.GameState_PickAction and not active_boost:
		return

	# Handle the wacky forced boost cases (Faust/Platinum/Hazama),
	# then, if the player has a decision it just returns.
	# If they don't, call the appropriate continue/do_remaining function
	# depending on what is active.
	if game_state == Enums.GameState.GameState_PlayerDecision and decision_info.type == Enums.DecisionType.DecisionType_ForceBoostSustainTopdeck:
		# Handle stupid Faust case.
		do_topdeck_boost()
	elif game_state == Enums.GameState.GameState_PlayerDecision and decision_info.type == Enums.DecisionType.DecisionType_ForceBoostSustainTopDiscard:
		do_discard_boost()
	else:
		if game_state not in [
			Enums.GameState.GameState_PlayerDecision,
			Enums.GameState.GameState_PickAction,
			Enums.GameState.GameState_DiscardDownToMax,
			Enums.GameState.GameState_WaitForStrike,
		]:
			if active_boost and not active_boost.checked_counter:
				# A counter-boost temporarily gives control to the opponent; the
				# original player's queued effects must wait until it finishes.
				pass
			else:
				do_queued_effects(performing_player)

		if game_state != Enums.GameState.GameState_PlayerDecision:
			if active_special_draw_effect:
				check_hand_size_advance_turn(performing_player)
			elif active_post_action_effect:
				post_action_effects_resolved += 1
				check_post_action_effects(performing_player)
			elif active_end_of_turn_effects:
				continue_end_turn()
			elif active_start_of_turn_effects:
				continue_begin_turn()
			elif active_overdrive:
				do_remaining_overdrive(performing_player)
			elif preparing_boost_info:
				var boost_performing_player = preparing_boost_info['performing_player']
				var boost_card_id = preparing_boost_info['card_id']
				var boost_additional_boost_ids = preparing_boost_info['additional_boost_ids']
				var boost_shuffle_discard_on_boost_cleanup = preparing_boost_info['shuffle_discard_on_boost_cleanup']
				preparing_boost_info = {}
				begin_resolve_boost(boost_performing_player, boost_card_id, boost_additional_boost_ids, boost_shuffle_discard_on_boost_cleanup)
			elif active_boost:
				if active_boost.checked_counter:
					active_boost.effects_resolved += 1
				else:
					active_boost.counters_resolved += 1
				continue_resolve_boost()
			elif active_strike:
				active_strike.effects_resolved_in_timing += 1
				continue_resolve_strike()
			elif active_character_action:
				active_character_action = false
				active_bonus_turn_action = false
				if game_state != Enums.GameState.GameState_WaitForStrike and game_state != Enums.GameState.GameState_Strike_Opponent_Set_First:
					check_hand_size_advance_turn(performing_player)
			elif active_exceed:
				active_exceed = false
				if game_state != Enums.GameState.GameState_WaitForStrike:
					check_hand_size_advance_turn(performing_player)
			elif active_change_cards:
				active_change_cards = false
				if game_state != Enums.GameState.GameState_WaitForStrike:
					check_hand_size_advance_turn(performing_player)
			elif active_prepare:
				prepare_effects_resolved += 1
				continue_resolve_prepare(performing_player)
			else:
				# End of turn states (pick action for next player or discard down for current) or strikes are expected.
				if game_state == Enums.GameState.GameState_PickAction or game_state == Enums.GameState.GameState_DiscardDownToMax or game_state == Enums.GameState.GameState_WaitForStrike:
					pass
				else:
					assert(false, "ERROR: Unexpected game state - no active action resolution")

func _dongshilang_register_cross_during_strike(performing_player : Player):
	if not active_strike:
		return
	var current_cross_count = int(dongshilang_cross_count_this_strike.get(performing_player.my_id, 0))
	dongshilang_cross_count_this_strike[performing_player.my_id] = current_cross_count + 1

func _dongshilang_get_move_limit_remaining(performing_player : Player) -> int:
	return int(dongshilang_move_limit_remaining_this_strike.get(performing_player.my_id, -1))

func _dongshilang_limit_requested_movement(performing_player : Player, requested_amount : int) -> int:
	var remaining = _dongshilang_get_move_limit_remaining(performing_player)
	if remaining < 0:
		return requested_amount
	return mini(requested_amount, maxi(remaining, 0))

func _dongshilang_consume_movement_limit(performing_player : Player, moved_amount : int):
	var remaining = _dongshilang_get_move_limit_remaining(performing_player)
	if remaining < 0:
		return
	dongshilang_move_limit_remaining_this_strike[performing_player.my_id] = maxi(remaining - moved_amount, 0)

func _dongshilang_is_advance_converted_to_retreat(performing_player : Player) -> bool:
	return bool(dongshilang_convert_advance_to_retreat_this_strike.get(performing_player.my_id, false))
func _dongshilang_get_ice_cards_in_set_aside(performing_player : Player) -> Array:
	var cards : Array = []
	for card in performing_player.set_aside_cards:
		if card.definition.get("type", "") == "ice_crystal":
			cards.append(card)
	return cards

func _dongshilang_move_ice_from_set_aside_to_bleach(performing_player : Player, amount : int, random_pick : bool = true) -> int:
	var ice_cards = _dongshilang_get_ice_cards_in_set_aside(performing_player)
	var move_count = mini(amount, ice_cards.size())
	var moved = 0
	for _i in range(move_count):
		var pick_idx = 0
		if random_pick and ice_cards.size() > 1:
			pick_idx = randi() % ice_cards.size()
		var chosen_card = ice_cards[pick_idx]
		ice_cards.remove_at(pick_idx)
		performing_player.remove_card_from_set_aside(chosen_card.id)
		performing_player.add_to_bleach(chosen_card)
		moved += 1
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将冰晶%s置入%s。" % [_log_card_name(chosen_card.definition.get("display_name", "")), performing_player.get_bleach_zone_name()])
	return moved

func _dongshilang_count_ice_in_boost_zone(performing_player : Player, count_type : String = "ice_crystal") -> int:
	var count = 0
	for card in performing_player.continuous_boosts:
		if card.definition.get("type", "") == count_type:
			count += 1
	return count

func _dongshilang_set_pending_ice_action(performing_player : Player, amount : int, valid_zones : Array, limitation : String, ignore_costs : bool):
	dongshilang_pending_ice_action_boost_count[performing_player.my_id] = maxi(amount, 0)
	dongshilang_pending_ice_action_context[performing_player.my_id] = {
		"valid_zones": valid_zones.duplicate(),
		"limitation": limitation,
		"ignore_costs": ignore_costs,
	}

func _dongshilang_get_pending_ice_action_count(performing_player : Player) -> int:
	return int(dongshilang_pending_ice_action_boost_count.get(performing_player.my_id, 0))

func _dongshilang_consume_pending_ice_action_boosts(performing_player : Player, consumed_count : int):
	if consumed_count <= 0:
		return
	var pending_count = _dongshilang_get_pending_ice_action_count(performing_player)
	dongshilang_pending_ice_action_boost_count[performing_player.my_id] = maxi(pending_count - consumed_count, 0)

func _dongshilang_get_pending_ice_action_context(performing_player : Player) -> Dictionary:
	return dongshilang_pending_ice_action_context.get(performing_player.my_id, {})

func _dongshilang_clear_pending_ice_action(performing_player : Player):
	dongshilang_pending_ice_action_boost_count.erase(performing_player.my_id)
	dongshilang_pending_ice_action_context.erase(performing_player.my_id)


func _dongshilang_start_ice_character_action(performing_player : Player, effect, _clear_active_exceed_on_cancel : bool = false):
	var amount = maxi(int(effect.get("amount", 1)), 1)
	var valid_zones = effect.get("valid_zones", ["bleach"])
	var limitation = effect.get("limitation", "ice_crystal")
	var ignore_costs = effect.get("ignore_costs", false)
	_dongshilang_set_pending_ice_action(performing_player, amount, valid_zones, limitation, ignore_costs)
	var begin_action_effect = {
		"effect_type": "dongshilang_begin_ice_boost_now",
		"amount": amount,
		"valid_zones": valid_zones,
		"limitation": limitation,
		"ignore_costs": ignore_costs
	}
	do_effect_if_condition_met(performing_player, -1, begin_action_effect, null)

func _get_effective_boost_cancel_cost(performing_player : Player, card : GameCard) -> int:
	# Apply Player.can_cancel's context gate before looking up printed or
	# character-action costs. A cost override must never grant permission to
	# cancel a mid-strike boost or bypass an explicit cancellation restriction.
	# All window creation and submission paths share this query; affordability
	# remains the caller's responsibility (declining a valid window costs 0).
	if card == null or active_strike or performing_player.cancel_blocked_this_turn \
			or performing_player.strike_on_boost_cleanup or performing_player.wild_strike_on_boost_cleanup:
		return -1
	var resolving_this_boost = active_boost and active_boost.playing_player == performing_player and active_boost.card == card
	if resolving_this_boost and (active_boost.strike_after_boost or (active_boost.boost_negated and not active_boost.allow_cancel_after_negate)):
		return -1
	var cancel_cost = performing_player.get_boost_cancel_cost(card)
	if cancel_cost != -1:
		return cancel_cost
	var ice_action_context = active_character_action or active_exceed \
			or (resolving_this_boost and active_boost.dongshilang_ice_character_action_cancel_once)
	if performing_player.deck_def.get("id", "") == "dongshilang" and ice_action_context and card.definition.get("type", "") == "ice_crystal":
		return 1
	return -1

func _resolve_opening_setup_once_effects():
	for setup_player in [player, opponent]:
		if setup_player == null:
			continue
		if setup_player.deck_def.get("id", "") != "dongshilang":
			continue
		var ability_effects = setup_player.deck_def.get("ability_effects", [])
		for setup_effect in ability_effects:
			if setup_effect.get("timing", "") == "start_of_next_turn" and setup_effect.get("setup_once", false):
				do_effect_if_condition_met(setup_player, -1, setup_effect, null)

func do_mulligan(performing_player : Player, card_ids : Array) -> bool:
	printlog("InitialAction: MULLIGAN by %s cards %s" % [performing_player.name, card_ids])
	if performing_player.mulligan_complete:
		printlog("ERROR: Tried to mulligan but already done.")
		return false
	if game_state != Enums.GameState.GameState_Mulligan:
		printlog("ERROR: Tried to mulligan but not in correct game state.")
		return false

	for card_id in card_ids:
		if not performing_player.is_card_in_hand(card_id):
			printlog("ERROR: Tried to mulligan with card not in hand.")
			return false

	performing_player.mulligan(card_ids)
	_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "调度%s张牌。" % str(len(card_ids)))
	if player.mulligan_complete and opponent.mulligan_complete:
		_resolve_opening_setup_once_effects()
		_queue_heiqiyihu_thresholds(_get_player(active_turn_player))
		_queue_heiqiyihu_thresholds(_get_player(next_turn_player))
		if not _begin_heiqiyihu_thresholds(_get_player(active_turn_player), "opening"):
			_finish_opening_mulligans()
	else:
		create_event(Enums.EventType.EventType_MulliganDecision, get_other_player(performing_player.my_id), 0)
	return true

func do_choose_from_boosts(performing_player : Player, card_ids : Array) -> bool:
	printlog("SubAction: CHOOSE FROM BOOSTS by %s cards: %s" % [performing_player.name, str(card_ids)])
	if game_state != Enums.GameState.GameState_PlayerDecision or decision_info.type != Enums.DecisionType.DecisionType_ChooseFromBoosts:
		printlog("ERROR: Tried to choose from boosts but not in correct game state.")
		return false

	# Validation.
	if card_ids.size() < decision_info.amount_min or card_ids.size() > decision_info.amount:
		printlog("ERROR: Tried to choose from boosts with wrong number of cards.")
		return false

	var choose_effect = decision_info.effect
	var choosing_transform = choose_effect and (choose_effect.get("effect_type") in [StrikeEffects.SealTransformForPowerup, StrikeEffects.SealTransformForArmorup] or choose_effect.get("tournelouse_ouroboros") or choose_effect.get("tournelouse_ouroboros_return_transform"))
	for card_id in card_ids:
		if choosing_transform:
			if not performing_player.is_card_in_transforms(card_id):
				printlog("ERROR: Tried to choose from transforms with card not in transforms.")
				return false
		elif not performing_player.is_card_in_continuous_boosts(card_id):
			printlog("ERROR: Tried to choose from boosts with card not in boosts.")
			return false
		if choose_effect.get("tournelouse_ouroboros_return_transform") and _is_tournelouse_ouroboros_bargeist_return_blocked(performing_player, card_id, choose_effect.get("hand_card_id", -1)):
			printlog("ERROR: Tried to return Bargeist Fang while using it to transform a duplicate normal.")
			return false
		if choose_effect.get("tournelouse_ouroboros_return_transform") and card_id in choose_effect.get("paid_card_ids", []):
			printlog("ERROR: Tried to return a card already chosen for Ouroboros force payment.")
			return false

	if choosing_transform and choose_effect.get("effect_type") in [StrikeEffects.SealTransformForPowerup, StrikeEffects.SealTransformForArmorup]:
		set_player_action_processing_state()
		for card_id in card_ids:
			var transform_card = card_db.get_card(card_id)
			performing_player.remove_from_transforms(transform_card)
			performing_player.add_to_sealed(transform_card)
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "封印%s。" % _log_card_name(transform_card.definition['display_name']))
			var stat_effect = { "effect_type": StrikeEffects.Powerup if choose_effect.get("effect_type") == StrikeEffects.SealTransformForPowerup else StrikeEffects.Armorup, "amount": choose_effect.get("amount", 2), "character_effect": true }
			handle_strike_effect(decision_info.choice_card_id, stat_effect, performing_player)
		continue_player_action_resolution(performing_player)
		return true
	if choosing_transform and choose_effect.get("tournelouse_ouroboros_return_transform"):
		var transform_card = card_db.get_card(card_ids[0])
		var hand_card_id = choose_effect["hand_card_id"]
		_perform_tournelouse_ouroboros_payment(performing_player, choose_effect.get("paid_card_ids", []), choose_effect.get("paid_card_sources", []))
		if not do_ex_transform(performing_player, hand_card_id, -1, false, true):
			printlog("ERROR: Tried to transform Ouroboros hand card through normal transform flow.")
			return false
		performing_player.remove_from_transforms(transform_card)
		performing_player.add_to_hand(transform_card, true)
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将转化牌%s返回手牌。" % _log_card_name(transform_card.definition['display_name']))
		if _is_action_resolution_in_progress():
			set_player_action_processing_state()
			continue_player_action_resolution(performing_player)
		return true

	# Move the cards.
	for card_id in card_ids:
		create_event(Enums.EventType.EventType_SustainBoost, performing_player.my_id, card_id)
		performing_player.sustained_boosts.append(int(card_id))
		var boost_name = _get_boost_and_card_name(card_db.get_card(card_id))
		_append_log_full(Enums.LogType.LogType_Effect, performing_player, "维持其持续性加成%s。" % boost_name)

	set_player_action_processing_state()
	continue_player_action_resolution(performing_player)
	return true

func do_cancel_tournelouse_transform_bonus_choice(performing_player : Player) -> bool:
	printlog("SubAction: CANCEL TOURNELOUSE TRANSFORM BONUS CHOICE by %s" % performing_player.name)
	if decision_info.player != performing_player.my_id:
		printlog("ERROR: Tried to cancel transform bonus choice for wrong player.")
		return false
	if game_state != Enums.GameState.GameState_PlayerDecision or decision_info.type != Enums.DecisionType.DecisionType_ChooseFromBoosts:
		printlog("ERROR: Tried to cancel transform bonus choice but not in correct game state.")
		return false

	var choose_effect = decision_info.effect
	if choose_effect == null or not (choose_effect.get("effect_type") in [StrikeEffects.SealTransformForPowerup, StrikeEffects.SealTransformForArmorup]):
		printlog("ERROR: Tried to cancel transform bonus choice for unsupported effect.")
		return false

	var amount = choose_effect.get("amount", 2)
	var source_card_id = decision_info.choice_card_id
	var choices = [
		{ "effect_type": StrikeEffects.Pass },
		{ "effect_type": StrikeEffects.SealTransformForPowerup, "amount": amount },
		{ "effect_type": StrikeEffects.SealTransformForArmorup, "amount": amount }
	]
	change_game_state(Enums.GameState.GameState_PlayerDecision)
	decision_info.clear()
	decision_info.type = Enums.DecisionType.DecisionType_EffectChoice
	decision_info.player = performing_player.my_id
	decision_info.choice_card_id = source_card_id
	decision_info.choice = choices
	create_event(Enums.EventType.EventType_Strike_EffectChoice, performing_player.my_id, 0, "EffectOption")
	return true

func _can_tournelouse_transform_card_from_hand(performing_player : Player, card_id : int, excluded_card_ids : Array = []) -> bool:
	if card_id in excluded_card_ids or not performing_player.is_card_in_hand(card_id):
		return false
	var card = card_db.get_card(card_id)
	var can_transform = card.definition['boost']['boost_type'] == "transform"
	can_transform = can_transform or (performing_player.deck_def.get("id") == "tournelouse" and card.definition['type'] == "normal" and not performing_player.exceeded)
	return can_transform and not performing_player.has_card_name_in_zone(card, "transform")

func _is_tournelouse_ouroboros_bargeist_return_blocked(performing_player : Player, transform_card_id : int, hand_card_id : int) -> bool:
	if transform_card_id == -1 or hand_card_id == -1:
		return false
	var transform_card = card_db.get_card(transform_card_id)
	if transform_card.definition.get("id") != "tournelouse_bargeist_fang":
		return false
	var hand_card = card_db.get_card(hand_card_id)
	if performing_player.deck_def.get("id") != "tournelouse" or performing_player.exceeded or hand_card.definition['type'] != "normal":
		return false
	for existing_transform in performing_player.transforms:
		if existing_transform.id != transform_card_id and existing_transform.definition['display_name'] == hand_card.definition['display_name']:
			return true
	return false

func _get_tournelouse_transform_hand_options(performing_player : Player, excluded_card_ids : Array = []) -> Array:
	var choices = []
	for hand_card in performing_player.hand:
		if _can_tournelouse_transform_card_from_hand(performing_player, hand_card.id, excluded_card_ids):
			choices.append(hand_card.id)
	return choices

func _get_tournelouse_ouroboros_paid_sources(performing_player : Player, card_ids : Array) -> Array:
	var sources = []
	for card_id in card_ids:
		if performing_player.is_card_in_hand(card_id):
			sources.append("hand")
		elif performing_player.is_card_in_gauge(card_id):
			sources.append("gauge")
		else:
			sources.append("")
	return sources

func _begin_tournelouse_ouroboros_hand_choice(performing_player : Player, source_card_id : int, paid_card_ids : Array, paid_card_sources : Array) -> bool:
	var hand_options = _get_tournelouse_transform_hand_options(performing_player, paid_card_ids)
	if hand_options.size() == 0:
		printlog("ERROR: Tried to start Ouroboros without a legal hand transform option.")
		return false
	change_game_state(Enums.GameState.GameState_PlayerDecision)
	decision_info.clear()
	decision_info.type = Enums.DecisionType.DecisionType_ChooseToDiscard
	decision_info.player = performing_player.my_id
	decision_info.choice_card_id = source_card_id
	decision_info.effect_type = StrikeEffects.TournelouseOuroboros
	decision_info.effect = {
		"amount": 1,
		"tournelouse_ouroboros_select_hand": true,
		"paid_card_ids": paid_card_ids,
		"paid_card_sources": paid_card_sources
	}
	decision_info.choice = hand_options
	decision_info.destination = ""
	decision_info.limitation = "from_array"
	decision_info.can_pass = true
	create_event(Enums.EventType.EventType_Strike_ChooseToDiscard, performing_player.my_id, 1)
	return true

func _begin_tournelouse_ouroboros_transform_choice(performing_player : Player, source_card_id : int, hand_card_id : int, paid_card_ids : Array, paid_card_sources : Array) -> bool:
	change_game_state(Enums.GameState.GameState_PlayerDecision)
	decision_info.clear()
	decision_info.type = Enums.DecisionType.DecisionType_ChooseFromBoosts
	decision_info.player = performing_player.my_id
	decision_info.choice_card_id = source_card_id
	decision_info.amount = 1
	decision_info.amount_min = 1
	decision_info.effect = {
		"effect_type": StrikeEffects.TournelouseOuroborosSelectTransform,
		"tournelouse_ouroboros_return_transform": true,
		"hand_card_id": hand_card_id,
		"paid_card_ids": paid_card_ids,
		"paid_card_sources": paid_card_sources
	}
	create_event(Enums.EventType.EventType_ChooseFromBoosts, performing_player.my_id, 1)
	return true

func _perform_tournelouse_ouroboros_payment(performing_player : Player, paid_card_ids : Array, paid_card_sources : Array):
	for i in range(paid_card_ids.size()):
		var paid_card_id = paid_card_ids[i]
		var source = paid_card_sources[i] if i < paid_card_sources.size() else ""
		if source == "hand" and performing_player.is_card_in_hand(paid_card_id):
			performing_player.discard([paid_card_id], 0, true)
		elif source == "gauge" and performing_player.is_card_in_gauge(paid_card_id):
			performing_player.discard([paid_card_id], 0, true)
	performing_player.total_force_spent_this_turn += 1

func do_cancel_tournelouse_ouroboros_hand_choice(performing_player : Player) -> bool:
	if decision_info.player != performing_player.my_id:
		printlog("ERROR: Tried to cancel Ouroboros hand choice for wrong player.")
		return false
	if game_state != Enums.GameState.GameState_PlayerDecision or decision_info.type != Enums.DecisionType.DecisionType_ChooseToDiscard:
		printlog("ERROR: Tried to cancel Ouroboros hand choice but not in correct game state.")
		return false
	var effect = decision_info.effect
	if effect == null or not effect.get("tournelouse_ouroboros_select_hand"):
		printlog("ERROR: Tried to cancel unsupported Ouroboros hand choice.")
		return false
	var source_card_id = decision_info.choice_card_id
	var force_effect = {
		"effect_type": StrikeEffects.ForceForEffect,
		"force_max": 1,
		"required": true,
		"tournelouse_ouroboros_force": true,
		"per_force_effect": null,
		"overall_effect": { "effect_type": StrikeEffects.Pass }
	}
	change_game_state(Enums.GameState.GameState_PlayerDecision)
	decision_info.clear()
	decision_info.player = performing_player.my_id
	decision_info.type = Enums.DecisionType.DecisionType_ForceForEffect
	decision_info.choice_card_id = source_card_id
	decision_info.effect = force_effect
	decision_info.choice = _get_tournelouse_transform_hand_options(performing_player)
	create_event(Enums.EventType.EventType_ForceForEffect, performing_player.my_id, 0)
	return true

func do_cancel_tournelouse_ouroboros_transform_choice(performing_player : Player) -> bool:
	if decision_info.player != performing_player.my_id:
		printlog("ERROR: Tried to cancel Ouroboros transform choice for wrong player.")
		return false
	if game_state != Enums.GameState.GameState_PlayerDecision or decision_info.type != Enums.DecisionType.DecisionType_ChooseFromBoosts:
		printlog("ERROR: Tried to cancel Ouroboros transform choice but not in correct game state.")
		return false
	var effect = decision_info.effect
	if effect == null or not effect.get("tournelouse_ouroboros_return_transform"):
		printlog("ERROR: Tried to cancel unsupported Ouroboros transform choice.")
		return false
	return _begin_tournelouse_ouroboros_hand_choice(performing_player, decision_info.choice_card_id, effect.get("paid_card_ids", []), effect.get("paid_card_sources", []))

func do_choose_from_discard(performing_player : Player, card_ids : Array) -> bool:
	printlog("SubAction: CHOOSE FROM DISCARD by %s cards: %s" % [performing_player.name, str(card_ids)])
	if game_state != Enums.GameState.GameState_PlayerDecision or decision_info.type != Enums.DecisionType.DecisionType_ChooseFromDiscard:
		printlog("ERROR: Tried to choose from discard but not in correct game state.")
		return false

	# Validation.
	if card_ids.size() < decision_info.amount_min or card_ids.size() > decision_info.amount:
		printlog("ERROR: Tried to choose from discard with wrong number of cards.")
		return false

	for card_id in card_ids:
		if decision_info.source == "discard":
			if not performing_player.is_card_in_discards(card_id):
				printlog("ERROR: Tried to choose from discard with card not in discard.")
				return false
		elif decision_info.source == "gauge":
			if not performing_player.is_card_in_gauge(card_id):
				printlog("ERROR: Tried to choose from gauge with card not in gauge.")
				return false
		elif decision_info.source == "sealed":
			if not performing_player.is_card_in_sealed(card_id):
				printlog("ERROR: Tried to choose from discard with card not in sealed.")
				return false
		elif decision_info.source == "overdrive":
			if not performing_player.is_card_in_overdrive(card_id):
				printlog("ERROR: Tried to choose from discard with card not in overdrive.")
				return false
		elif decision_info.source == "outrun_seal":
			if not performing_player.is_card_in_discards(card_id) and not performing_player.is_card_in_gauge(card_id):
				printlog("ERROR: Tried to choose from discard/gauge for Outrun with card in neither zone.")
				return false
		elif decision_info.source == "discard" and decision_info.destination == "umina_dreamlands":
			# Umina Terror Whispers: accept from discard, validate Shadow Chorus restriction
			if not performing_player.is_card_in_discards(card_id):
				printlog("ERROR: Tried to choose from discard for Umina Dreamlands, card not in discard.")
				return false
			var umina_tw_card = card_db.get_card(card_id)
			if umina_tw_card and umina_tw_card.definition.get("id") == "umina_shadow_chorus":
				printlog("ERROR: Shadow Chorus cannot enter Dreamlands.")
				return false
		else:
			printlog("ERROR: Tried to choose from discard with unknown source.")
			return false

	for card_id in card_ids:
		var card = card_db.get_card(card_id)
		var limitation = decision_info.limitation
		match limitation:
			"normal":
				if card.definition['type'] != "normal":
					printlog("ERROR: Tried to choose from discard with card that doesn't meet limitation normal.")
					return false
			"special":
				if card.definition['type'] != "special":
					printlog("ERROR: Tried to choose from discard with card that doesn't meet limitation special.")
					return false
			"ultra":
				if card.definition['type'] != "ultra":
					printlog("ERROR: Tried to choose from discard with card that doesn't meet limitation ultra.")
					return false
			"normal/special":
				if card.definition['type'] not in ["normal", "special"]:
					printlog("ERROR: Tried to choose from discard with card that doesn't meet limitation normal/special.")
					return false
			"special/ultra":
				if card.definition['type'] not in ["special", "ultra"]:
					printlog("ERROR: Tried to choose from discard with card that doesn't meet limitation special/ultra.")
					return false
			"continuous":
				if card.definition['boost']['boost_type'] != "continuous":
					printlog("ERROR: Tried to choose from discard with card that doesn't meet limitation continuous.")
					return false
			_:
				pass

	# Move the cards.
	var secret_zones = false
	var minato_outrun_sealed_count = 0
	for card_id in card_ids:
		var destination = decision_info.destination
		if decision_info.source == "discard":
			match destination:
				"deck":
					performing_player.move_card_from_discard_to_deck(card_id)
				"deck_noshuffle":
					performing_player.move_card_from_discard_to_deck(card_id, false)
				"gauge":
					performing_player.move_card_from_discard_to_gauge(card_id)
				"hand":
					performing_player.move_card_from_discard_to_hand(card_id)
				"lightningrod_any_space":
					# Bring this card to the top of the discard pile.
					# The discard_effect will place it as a lightning rod from there.
					performing_player.bring_card_to_top_of_discard(card_id)
				"overdrive":
					performing_player.move_cards_to_overdrive([card_id], "discard")
				"sealed":
					do_seal_effect(performing_player, card_id, "discard")
				"play_boost":
					# This effect currently is expected to put the discarded cards on top of the discard pile.
					# Then the discard_effect is expected to be boost_then_sustain_topdiscard.
					# Assumption that a character doing this doesn't have boosts that alter the discard pile.
					# If a character can put things into discard as a boost, then this could
					# be modified to use the bottom of the discard, or some other zone.
					performing_player.bring_card_to_top_of_discard(card_id)
				"umina_dreamlands":
					# Umina Terror Whispers: put discarded card into Dreamlands
					var umina_tw_dest_card = card_db.get_card(card_id)
					if umina_tw_dest_card != null:
						# Handle old Dreamlands card (return to its owner's hand when exceeded)
						if performing_player.set_aside_cards.size() > 0:
							var umina_tw_old = performing_player.set_aside_cards[0]
							if performing_player.exceeded and umina_tw_old.owner_id != performing_player.my_id:
								var umina_tw_owner = _get_player(umina_tw_old.owner_id)
								umina_tw_owner.add_to_hand(umina_tw_old, true)
							elif performing_player.exceeded:
								performing_player.add_to_hand(umina_tw_old, not performing_player.umina_dreamlands_facedown)
							else:
								performing_player.add_to_discards(umina_tw_old)
							performing_player.remove_card_from_set_aside(umina_tw_old.id)
						performing_player.remove_card_from_discards(card_id)
						performing_player.add_to_set_aside(umina_tw_dest_card)
						_append_log_full(Enums.LogType.LogType_Effect, performing_player, "puts %s from discard into Dreamlands." % _log_card_name(umina_tw_dest_card.id))
						create_event(Enums.EventType.EventType_AddToStored, performing_player.my_id, card_id)
						_umina_check_slipping_away(performing_player, card_id)
				_:
					printlog("ERROR: Choose from discard destination not implemented.")
					assert(false, "Choose from discard destination not implemented.")
					return false
		elif decision_info.source == "gauge":
			match destination:
				"discard":
					performing_player.discard([card_id])
				"owner_hand":
					var gauge_card = card_db.get_card(card_id)
					performing_player.remove_card_from_gauge(card_id)
					var card_owner = _get_player(gauge_card.owner_id)
					card_owner.add_to_hand(gauge_card, true)
				_:
					printlog("ERROR: Choose from gauge destination not implemented.")
					assert(false, "Choose from gauge destination not implemented.")
					return false
		elif decision_info.source == "sealed":
			match destination:
				"hand":
					performing_player.move_card_from_sealed_to_hand(card_id)
					secret_zones = performing_player.sealed_area_is_secret
				"gauge":
					performing_player.move_card_from_sealed_to_gauge(card_id)
				"deck":
					performing_player.move_card_from_sealed_to_top_deck(card_id)
					secret_zones = performing_player.sealed_area_is_secret
				_:
					printlog("ERROR: Choose from sealed destination not implemented.")
					assert(false, "Choose from sealed destination not implemented.")
					return false

		elif decision_info.source == "overdrive":
			match destination:
				"discard":
					performing_player.discard([card_id])
				"hand":
					# Drop the discard event because we really just want the add to hand event.
					performing_player.discard([card_id])
					performing_player.move_card_from_discard_to_hand(card_id)
				_:
					printlog("ERROR: Choose from overdrive destination not implemented.")
					assert(false, "Choose from overdrive destination not implemented.")
					return false

		elif decision_info.source == "outrun_seal":
			if performing_player.is_card_in_discards(card_id):
				do_seal_effect(performing_player, card_id, "discard")
			elif performing_player.is_card_in_gauge(card_id):
				var sealed_card = card_db.get_card(card_id)
				performing_player.remove_card_from_gauge(card_id)
				performing_player.add_to_sealed(sealed_card)
			minato_outrun_sealed_count += 1

		else:
			printlog("ERROR: Choose from discard source not implemented.")
			assert(false, "Choose from discard source not implemented.")
			return false

	var dest_name = decision_info.destination
	if dest_name == "deck":
		dest_name = "top of deck"
	var card_names = card_db.get_card_names(card_ids)
	if decision_info.source == "sealed" and decision_info.destination == "deck" and card_ids.size() > 0:
		performing_player.random_shuffle_deck()
	if decision_info.destination == "play_boost":
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "从%s打出%s。" % [_log_card_name(card_names), decision_info.source])
	elif secret_zones:
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将%s张牌从%s移到%s。" % [str(len(card_ids)), decision_info.source, dest_name])
	else:
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将牌从%s移到%s：%s。" % [decision_info.source, dest_name, _log_card_name(card_names)])

	set_player_action_processing_state()

	# Do any bonus effect.
	if card_ids.size() > 0 and decision_info.bonus_effect:
		var effect = decision_info.bonus_effect
		effect['discarded_card_ids'] = card_ids
		do_effect_if_condition_met(performing_player, decision_info.choice_card_id, effect, null)

	if decision_info.source == "outrun_seal":
		var minato_otp_draw = int(minato_outrun_sealed_count / 2.0)
		_append_log_full(Enums.LogType.LogType_Effect, performing_player, "Outrun the Past：封印了%s张牌。" % minato_outrun_sealed_count)
		if minato_otp_draw > 0:
			do_effect_if_condition_met(performing_player, decision_info.choice_card_id, {"effect_type": StrikeEffects.Draw, "amount": minato_otp_draw, "discarded_card_ids": card_ids}, null)
		if active_strike and active_strike.strike_state in [StrikeState.StrikeState_Initiator_SetEffects, StrikeState.StrikeState_Defender_SetFirst]:
			strike_setup_defender_response()
			return true
		if not active_strike and active_character_action:
			active_character_action = false
			create_silent_pre_strike_event(performing_player)
			change_game_state(Enums.GameState.GameState_PickAction)
			return true

	continue_player_action_resolution(performing_player)
	return true

func do_force_for_effect(performing_player : Player, card_ids : Array, treat_ultras_as_single_force : bool, cancel : bool = false, use_free_force : bool = false, spent_life_for_force : int = 0) -> bool:
	printlog("SubAction: FORCE_FOR_EFFECT by %s cards %s" % [performing_player.name, card_ids])
	if not performing_player.validate_heiqiyihu_payment(card_ids):
		return false
	if game_state != Enums.GameState.GameState_PlayerDecision or decision_info.type != Enums.DecisionType.DecisionType_ForceForEffect:
		printlog("ERROR: Tried to force for effect but not in decision state.")
		return false
	if decision_info.player != performing_player.my_id:
		printlog("ERROR: Tried to force for armor for wrong player.")
		return false
	if cancel and decision_info.effect.get("required", false) and not decision_info.effect.get("tournelouse_ouroboros_force", false):
		printlog("ERROR: Tried to cancel a required force payment.")
		return false

	for card_id in card_ids:
		if not performing_player.is_card_in_hand(card_id) and not performing_player.is_card_in_gauge(card_id) \
		and not performing_player.is_heiqiyihu_guardian_resource(card_id):
			printlog("ERROR: Tried to force for effect with card not in hand or gauge.")
			return false

	# Remember whether this force_for_effect's overall_effect negates a boost
	# (Geoffrey Compulsive Purification fingerprint) so the confirmation event
	# can tell UI clients which closeup to play. decision_info is cleared
	# during processing below.
	var ffe_paid_negates_boost = false
	if decision_info.effect != null:
		var ffe_overall = decision_info.effect.get("overall_effect", null)
		ffe_paid_negates_boost = ffe_overall != null and ffe_overall.get("effect_type", "") == "negate_boost"

	if decision_info.effect.get("tournelouse_ouroboros_force"):
		if cancel:
			change_game_state(Enums.GameState.GameState_PickAction)
			active_character_action = false
			continue_player_action_resolution(performing_player)
			return true
		if card_ids.size() != 1:
			printlog("ERROR: Ouroboros must pay exactly one card for force.")
			return false
		if performing_player.is_card_in_hand(card_ids[0]) and performing_player.hand.size() <= 1:
			printlog("ERROR: Ouroboros cannot pay the last hand card.")
			return false
		var force_for_ouroboros = performing_player.get_force_with_cards(card_ids, "FORCE_FOR_EFFECT", treat_ultras_as_single_force, use_free_force)
		if force_for_ouroboros < 1:
			printlog("ERROR: Ouroboros force payment did not generate enough force.")
			return false
		if _get_tournelouse_transform_hand_options(performing_player, card_ids).size() == 0:
			printlog("ERROR: Ouroboros payment leaves no legal hand card to transform.")
			return false
		var paid_card_sources = _get_tournelouse_ouroboros_paid_sources(performing_player, card_ids)
		return _begin_tournelouse_ouroboros_hand_choice(performing_player, decision_info.choice_card_id, card_ids.duplicate(), paid_card_sources)

	var force_generated = performing_player.get_force_with_cards(card_ids, "FORCE_FOR_EFFECT", treat_ultras_as_single_force, use_free_force)
	force_generated += performing_player.get_force_from_spent_life(spent_life_for_force)
	if cancel:
		force_generated = 0
		if active_bonus_turn_action:
			active_character_action = false
			active_bonus_turn_action = false
		if decision_info.effect.get("cancel_resume_strike") or active_strike:
			change_game_state(Enums.GameState.GameState_Strike_Processing)
		elif active_start_of_turn_effects or active_end_of_turn_effects or active_overdrive or active_boost \
		or active_character_action or active_exceed or active_change_cards or active_prepare \
		or active_special_draw_effect or active_post_action_effect:
			set_player_action_processing_state()
		else:
			change_game_state(Enums.GameState.GameState_PickAction)
		continue_player_action_resolution(performing_player)
		return true
	var ultras = 0
	# If not treating ultras as a single force, count them
	# to allow overpaying.
	if not treat_ultras_as_single_force:
		for card_id in card_ids:
			var force_value = card_db.get_card_force_value(card_id)
			if force_value == 2:
				ultras += 1

	if performing_player.force_cost_reduction > decision_info.effect['force_max']:
		if decision_info.effect['force_max'] == -1:
			force_generated += performing_player.force_cost_reduction
		else:
			force_generated = decision_info.effect['force_max']

	if decision_info.effect['force_max'] != -1 and force_generated > decision_info.effect['force_max']:
		if force_generated - ultras <= decision_info.effect['force_max']:
			force_generated = decision_info.effect['force_max']
		else:
			printlog("ERROR: Tried to force for effect with too much force.")
			return false
	performing_player.total_force_spent_this_turn += force_generated

	if decision_info.effect.get("heiqiyihu_xuhua_payment", false) and force_generated > 0:
		var source_id = decision_info.choice_card_id
		var spent_ids = active_strike.heiqiyihu_xuhua_spent_ids.get(source_id, [])
		for paid_id in card_ids:
			if paid_id not in spent_ids:
				spent_ids.append(paid_id)
		active_strike.heiqiyihu_xuhua_spent_ids[source_id] = spent_ids

	var continuation_player = performing_player
	if 'continuation_switch_player_control' in decision_info.effect and decision_info.effect['continuation_switch_player_control']:
		continuation_player = _get_player(get_other_player(performing_player.my_id))

	set_player_action_processing_state()
	if force_generated > 0:
		# ForceForEffect confirmation event: emitted once when the payment
		# takes effect, so both clients can play an effect closeup at the same
		# moment (e.g. Geoffrey Compulsive Purification). "bonus" is rolled
		# here once so both clients agree on the easter-egg variant.
		create_event(Enums.EventType.EventType_ForceForEffectConfirmed, performing_player.my_id, 0, "",
				{"negate_boost": ffe_paid_negates_boost, "bonus": randf() < 0.2})
		var card_names = ""
		if card_ids.size() > 0:
			card_names = card_db.get_card_name(card_ids[0])
			for i in range(1, card_ids.size()):
				card_names += ", " + card_db.get_card_name(card_ids[i])
		else:
			card_names = "passive bonus"

		var decision_effect = null
		var effect_times = 0
		if decision_info.effect.get('per_force_effect') != null:
			decision_effect = decision_info.effect['per_force_effect']
			var interval = 1.0
			if 'force_effect_interval' in decision_info.effect:
				interval = decision_info.effect['force_effect_interval']
			effect_times = floor(force_generated / interval)
			if force_generated > 0 and decision_effect.get('combine_multiple_into_one'):
				# This will work on a single nested "and" that has an amount.
				# If it doesn't have an amount, this won't work as expected.
				decision_effect = decision_effect.duplicate(true)
				decision_effect['amount'] = effect_times * decision_effect['amount']
				var and_effect = decision_effect.get('and')
				if and_effect and and_effect.get("amount"):
					and_effect['amount'] = effect_times * and_effect['amount']
				effect_times = 1
		elif decision_info.effect.get('overall_effect'):
			decision_effect = decision_info.effect['overall_effect']
			effect_times = 1

		# decision_effect is null when neither per_force_effect nor overall_effect is
		# set (Heidi 机械天才 pays a forced boost's cost from hand). Guard against
		# "in" on null, mirroring the check used elsewhere in the engine.
		var to_overdrive = decision_effect != null and 'spent_cards_to_overdrive' in decision_effect and decision_effect['spent_cards_to_overdrive']
		if to_overdrive:
			var hand_cards = []
			var gauge_cards = []
			var guardian_cards = []
			for card_id in card_ids:
				if performing_player.is_card_in_hand(card_id):
					hand_cards.append(card_id)
				elif performing_player.is_card_in_gauge(card_id):
					gauge_cards.append(card_id)
				elif performing_player.is_heiqiyihu_guardian_resource(card_id):
					guardian_cards.append(card_id)
				else:
					assert(false)
					printlog("ERROR: Unexpected source for force sent to overdrive: card id %s" % card_id)
			performing_player.move_cards_to_overdrive(hand_cards, "hand")
			performing_player.move_cards_to_overdrive(gauge_cards, "gauge")
			if not guardian_cards.is_empty():
				performing_player.move_cards_to_overdrive(guardian_cards, "bleach")
		else:
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "通过弃置%s生成能量。" % _log_card_name(card_names))
			performing_player.discard(card_ids, 0, true)

		# Zsolt transform UI: only show Mad Dog / Press the Attack bonus preview after paying force.
		if performing_player.deck_def.get("id") == "zsolt" and not decision_info.effect.get("is_zsolt_awaken") and effect_times > 0:
			var preview_effect = decision_info.effect.get('per_force_effect', null)
			if preview_effect != null:
				preview_effect = preview_effect.duplicate(true)
				if preview_effect.get("effect_type") in [StrikeEffects.Powerup, StrikeEffects.Speedup] and preview_effect.get("amount", 0) == 1 and decision_info.effect.get("force_max", -1) == 1:
					preview_effect["character_effect"] = true
					performing_player.strike_stat_boosts.active_character_effects.append(preview_effect)
					create_event(Enums.EventType.EventType_Strike_CharacterEffect, performing_player.my_id, decision_info.choice_card_id, "", preview_effect)


		var queued_per_force_effects = []
		for i in range(0, effect_times):
			var queued_effect = decision_effect.duplicate(true)
			if decision_info.choice_card_id != -1:
				queued_effect['card_id'] = decision_info.choice_card_id
			queued_per_force_effects.append(queued_effect)
		add_queued_effects(queued_per_force_effects)
		# Counter-boost force payments such as Geoffrey's Compulsive
		# Purification belong to the countering player and must negate the boost
		# before counter resolution advances. Other queued effects still wait for
		# the original boost player, which preserves Miyuki's control ownership.
		if active_boost and not active_boost.checked_counter \
				and decision_effect != null \
				and decision_effect.get("effect_type", "") == StrikeEffects.NegateBoost:
			do_queued_effects(performing_player)

		if decision_info.effect.get('pay_for_forced_boost_discard'):
			# 海蒂 机械天才（boost_then_sustain_topdiscard）：玩家已从手牌支付该持续
			# 加成的 force 费用。免费力是永不扣减的预算，需计入可支付判断。
			# 足够 → 打出该加成；否则干净跳过（卡留在弃牌堆）并继续解析。
			var boost_cost = decision_info.effect['force_max']
			var available_force = force_generated + performing_player.free_force
			if available_force >= boost_cost:
				_play_forced_discard_boost(performing_player, decision_info.effect['forced_boost_card_id'], true)
			else:
				performing_player.sustain_next_boost = false
				_append_log_full(Enums.LogType.LogType_Effect, performing_player,
					"无法支付该持续加成的%s能量，它将留在弃牌堆。" % boost_cost)
				continue_player_action_resolution(performing_player)
			return true

		if not handle_spend_life_for_force(performing_player, spent_life_for_force):
			return false
		if game_over:
			return true

	continue_player_action_resolution(continuation_player)
	return true

func _spent_cards_flag(effect_container, decision_effect, key : String) -> bool:
	if decision_effect != null and decision_effect.get(key, false):
		return true
	if effect_container == null:
		return false
	if effect_container.get(key, false):
		return true
	var overall_effect = effect_container.get('overall_effect', null)
	if overall_effect != null and overall_effect.get(key, false):
		return true
	return false

func _umina_restore_shadow_chorus_definitions(performing_player : Player) -> void:
	if performing_player == null or performing_player.umina_shadow_chorus_restore.is_empty():
		return
	if active_strike == null:
		performing_player.umina_shadow_chorus_restore.clear()
		return
	for card in active_strike.cards_in_play:
		if card.owner_id != performing_player.my_id:
			continue
		if performing_player.umina_shadow_chorus_restore.has(card.id):
			card.definition = performing_player.umina_shadow_chorus_restore[card.id].duplicate(true)
	performing_player.umina_shadow_chorus_restore.clear()

func do_gauge_for_effect(performing_player : Player, card_ids : Array) -> bool:
	printlog("SubAction: GAUGE_FOR_EFFECT by %s cards %s" % [performing_player.name, card_ids])
	if not performing_player.validate_heiqiyihu_payment(card_ids, true):
		return false
	if game_state != Enums.GameState.GameState_PlayerDecision or decision_info.type != Enums.DecisionType.DecisionType_GaugeForEffect:
		printlog("ERROR: Tried to gauge for effect but not in decision state.")
		return false
	if decision_info.player != performing_player.my_id:
		printlog("ERROR: Tried to gauge for armor for wrong player.")
		return false

	var payment_zone = decision_info.effect.get("valid_zone", "gauge")
	for card_id in card_ids:
		var in_valid_zone = performing_player.is_card_in_gauge(card_id)
		if payment_zone == "bleach":
			in_valid_zone = performing_player.is_card_in_bleach(card_id)
		elif payment_zone == "gauge" and performing_player.deck_def.get("id") == "soifon" and performing_player.exceeded:
			in_valid_zone = in_valid_zone or performing_player.is_card_in_bleach(card_id)
		elif payment_zone == "gauge" and performing_player.is_heiqiyihu_guardian_resource(card_id):
			in_valid_zone = true
		if not in_valid_zone:
			printlog("ERROR: Tried to pay for effect with card outside %s." % payment_zone)
			return false
	if 'require_specific_card_id' in decision_info.effect:
		var required_card_id = decision_info.effect['require_specific_card_id']
		for card_id in card_ids:
			if card_db.get_card(card_id).definition['id'] != required_card_id:
				printlog("ERROR: Invalid card id selected for card-specific gauge for effect.")
				return false

	if 'valid_card_types' in decision_info.effect:
		for card_id in card_ids:
			if card_db.get_card(card_id).definition['type'] not in decision_info.effect['valid_card_types']:
				printlog("ERROR: Invalid card type selected for type-specific gauge for effect.")
				return false

	# Cap free gauge to the max gauge cost of the effect.
	var free_gauge_used = 0
	if payment_zone == "gauge":
		free_gauge_used = min(performing_player.free_gauge, decision_info.effect['gauge_max'])
	# 怒气卡是「弹性支付」：每张至少 1 点、至多其面值（枪灵 = 2 点）。
	# 所以这组卡能支付的点数是一个区间 —— 面值 2 的卡会自动适配成 1 或 2 点，
	# 不会因为「这次只需要 1 点」而被当成超付拒掉（和 move 按需取格数同一思路）。
	var gauge_value_range = performing_player.get_gauge_payment_value_range(card_ids)
	var gauge_max_value = free_gauge_used + gauge_value_range[1]
	var gauge_min_value = free_gauge_used + gauge_value_range[0]
	# 实际支付点数：不超过效果上限，能付多少付多少。
	var gauge_generated = min(gauge_max_value, decision_info.effect['gauge_max'])

	if decision_info.effect.get("can_pass", false) and gauge_max_value == 0:
		if decision_info.effect.get("pass_as_cancel_to_pick_action", false):
			change_game_state(Enums.GameState.GameState_PickAction)
			decision_info.clear()
			active_character_action = false
			continue_player_action_resolution(performing_player)
			return true
		set_player_action_processing_state()
		if decision_info.effect.get("decline_on_death_game_over", false) and performing_player.life <= 0:
			trigger_game_over(performing_player.my_id, Enums.GameOverReason.GameOverReason_Life)
			return true
		continue_player_action_resolution(performing_player)
		return true

	if gauge_min_value > decision_info.effect['gauge_max']:
		printlog("ERROR: Tried to gauge for effect with too many cards.")
		return false

	if 'min_gauge' in decision_info.effect and gauge_generated < decision_info.effect['min_gauge']:
		printlog("ERROR: Tried to gauge for effect with too few cards (required %s, got %s)." % [decision_info.effect['min_gauge'], gauge_generated])
		return false

	set_player_action_processing_state()

	var zero_cost_taisei_death_exceed = performing_player.deck_def.get("id") == "taisei" \
			and decision_info.effect.get("decline_on_death_game_over", false) \
			and gauge_generated == 0 \
			and decision_info.effect.get("gauge_max", -1) == 0 \
			and decision_info.effect.get("min_gauge", -1) == 0 \
			and decision_info.effect.get("overall_effect", null) \
			and decision_info.effect["overall_effect"].get("effect_type", "") == StrikeEffects.ExceedNow
	if zero_cost_taisei_death_exceed:
		do_effect_if_condition_met(performing_player, decision_info.choice_card_id, decision_info.effect["overall_effect"], null)
	elif gauge_generated > 0:
		var card_names = ""
		if card_ids.size() > 0:
			card_names = card_db.get_card_name(card_ids[0])
			for i in range(1, card_ids.size()):
				card_names += ", " + card_db.get_card_name(card_ids[i])
		else:
			card_names = "passive bonus"

		var decision_effect = {}
		var effect_times = 0
		var per_gauge_only = true
		if decision_info.effect.get('per_gauge_effect', null):
			decision_effect = decision_info.effect['per_gauge_effect']
			effect_times = gauge_generated
			if gauge_generated > 0 and 'combine_multiple_into_one' in decision_effect and decision_effect['combine_multiple_into_one']:
				# This assumes this effect has no "and" effects.
				decision_effect = decision_effect.duplicate()
				decision_effect['amount'] = effect_times * decision_effect['amount']
				effect_times = 1
		if decision_info.effect['overall_effect']:
			per_gauge_only = false

		var to_hand = _spent_cards_flag(decision_info.effect, decision_effect, 'spent_cards_to_hand')
		var to_overdrive = _spent_cards_flag(decision_info.effect, decision_effect, 'spent_cards_to_overdrive')
		if to_hand:
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将牌从怒气返回手牌：%s。" % _log_card_name(card_names))
		elif to_overdrive:
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将牌从怒气加入超载：%s。" % _log_card_name(card_names))
		elif payment_zone == "bleach":
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "花费%s张%s：%s。" % [str(gauge_generated), performing_player.get_bleach_zone_name(), _log_card_name(card_names)])
		else:
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "花费%s怒气，弃置%s。" % [str(gauge_generated), _log_card_name(card_names)])

		# Move the spent cards to the right place.
		if to_hand:
			for card_id in card_ids:
				if performing_player.is_heiqiyihu_guardian_resource(card_id):
					var guardian_card = performing_player.remove_card_from_bleach(card_id)
					performing_player.add_to_hand(guardian_card, true)
				else:
					performing_player.move_card_from_gauge_to_hand(card_id)
		elif to_overdrive:
			var gauge_ids = []
			var guardian_ids = []
			for card_id in card_ids:
				if performing_player.is_heiqiyihu_guardian_resource(card_id):
					guardian_ids.append(card_id)
				else:
					gauge_ids.append(card_id)
			performing_player.move_cards_to_overdrive(gauge_ids, "gauge")
			if not guardian_ids.is_empty():
				performing_player.move_cards_to_overdrive(guardian_ids, "bleach")
		else:
			performing_player.syrus_dredge_fury_spent_ids = card_ids.duplicate()
			performing_player.discard(card_ids, 0, true)
		if not per_gauge_only:
			var per_effect = decision_info.effect.get('per_gauge_effect', null)
			if per_effect:
				var per_effect_times = gauge_generated
				var per_dup = per_effect
				if 'combine_multiple_into_one' in per_effect and per_effect['combine_multiple_into_one']:
					per_dup = per_dup.duplicate()
					per_dup['amount'] = gauge_generated * per_dup['amount']
					per_effect_times = 1
				for i in range(0, per_effect_times):
					do_effect_if_condition_met(performing_player, decision_info.choice_card_id, per_dup, null)
			var over_effect = decision_info.effect.get('overall_effect', null)
			if over_effect:
				do_effect_if_condition_met(performing_player, decision_info.choice_card_id, over_effect, null)
		else:
			for i in range(0, effect_times):
				do_effect_if_condition_met(performing_player, decision_info.choice_card_id, decision_effect, null)

	if decision_info.bonus_effect:
		handle_strike_effect(decision_info.choice_card_id, decision_info.bonus_effect, performing_player)

	continue_player_action_resolution(performing_player)
	return true

func do_choose_to_discard(performing_player : Player, card_ids):
	var card_names = card_db.get_card_names(card_ids)
	printlog("SubAction: %s choosing to discard %s" % [get_player_name(performing_player.my_id), card_names])
	if decision_info.player != performing_player.my_id:
		printlog("ERROR: Tried to choose to discard for wrong player.")
		return false
	if game_state != Enums.GameState.GameState_PlayerDecision:
		printlog("ERROR: Tried to make a choice but not in decision state.")
		return false

	if decision_info.effect.get("tournelouse_ouroboros_select_hand"):
		if card_ids.size() != 1 or not _can_tournelouse_transform_card_from_hand(performing_player, card_ids[0], decision_info.effect.get("paid_card_ids", [])):
			printlog("ERROR: Tried to choose an illegal hand card for Ouroboros transform.")
			return false
		return _begin_tournelouse_ouroboros_transform_choice(performing_player, decision_info.choice_card_id, card_ids[0], decision_info.effect.get("paid_card_ids", []), decision_info.effect.get("paid_card_sources", []))

	var target_opponent = false
	var target_player = performing_player
	var other_player = _get_player(get_other_player(performing_player.my_id))
	if decision_info.effect['effect_type'] == StrikeEffects.ChooseOpponentCardToDiscard:
		target_opponent = true
		target_player = other_player

	var amount = decision_info.effect['amount']
	var allow_fewer = 'allow_fewer' in decision_info.effect and decision_info.effect['allow_fewer']
	if not (decision_info.can_pass or amount == -1 or allow_fewer):
		if len(card_ids) != amount and target_player.hand.size() >= amount:
			printlog("ERROR: Tried to choose to discard wrong number of cards.")
			return false

	var source = decision_info.source if decision_info.source else "hand"
	for card_id in card_ids:
		if not target_opponent:
			if source == "hand" and not performing_player.is_card_in_hand(card_id):
				printlog("ERROR: Tried to choose to discard with card not in hand.")
				return false
			if source == "hand/gauge" and not (performing_player.is_card_in_hand(card_id) or performing_player.is_card_in_gauge(card_id)):
				printlog("ERROR: Tried to choose to discard with card not in hand/gauge.")
				return false
			if source == "boosts" and not performing_player.is_card_in_continuous_boosts(card_id):
				printlog("ERROR: Tried to choose to discard with card not in boosts.")
				return false
		else:
			if source == "hand" and not other_player.is_card_in_hand(card_id):
				printlog("ERROR: Tried to discard opponent card not in their hand.")
				return false
			if source == "hand/gauge" and not (other_player.is_card_in_hand(card_id) or other_player.is_card_in_gauge(card_id)):
				printlog("ERROR: Tried to discard opponent card not in their hand/gauge.")
				return false
			if source == "boosts" and not other_player.is_card_in_continuous_boosts(card_id):
				printlog("ERROR: Tried to discard opponent card not in their boosts.")
				return false

		if decision_info.limitation and decision_info.limitation not in ["can_pay_cost", "from_array", "same-named", "range_to_opponent"]:
			var card = card_db.get_card(card_id)
			if card.definition['type'] != decision_info.limitation:
				printlog("ERROR: Tried to choose to discard with card that doesn't meet limitation.")
				return false

	var skip_effect = false
	if len(card_ids) == 0:
		skip_effect = true

	var effect = {
		"effect_type": decision_info.effect_type,
		"card_ids": card_ids,
		"destination": decision_info.destination,
		"discard_source": source,
		"_source_player_id": decision_info.source_player_id if decision_info.source_player_id != -1 else _last_effect_source_player_id
	}
	var jinglechunshui_choose_two_followup = null
	if decision_info.effect.get("jinglechunshui_choose_two_continuation", false) and decision_info.effect.get("and", null):
		# The opponent selected a discard, but JingLeChunShui must choose the
		# remaining option of Bujingdule's five-choose-two effect.
		jinglechunshui_choose_two_followup = decision_info.effect["and"].duplicate(true)
		jinglechunshui_choose_two_followup["multiple_amount"] = 1
	var repeat_bonus_times = 0
	var repeat_bonus_effect = null
	if not skip_effect and decision_info.bonus_effect:
		var per_discard_effect = 'per_discard' in decision_info.bonus_effect and decision_info.bonus_effect['per_discard']
		if per_discard_effect:
			repeat_bonus_effect = decision_info.bonus_effect.duplicate()
			repeat_bonus_times = len(card_ids)
		else:
			effect['and'] = decision_info.bonus_effect.duplicate()
			effect['and']['discarded_card_ids'] = card_ids
	if len(card_ids) < decision_info.effect['amount'] and 'smaller_discard_effect' in decision_info.effect:
		effect['and'] = decision_info.effect['smaller_discard_effect'].duplicate()

	set_player_action_processing_state()

	do_effect_if_condition_met(performing_player, decision_info.choice_card_id, effect, null)
	if jinglechunshui_choose_two_followup:
		var followup_player = _get_player(effect["_source_player_id"])
		handle_strike_effect(decision_info.choice_card_id, jinglechunshui_choose_two_followup, followup_player)
	if repeat_bonus_effect:
		for i in range(repeat_bonus_times):
			handle_strike_effect(decision_info.choice_card_id, repeat_bonus_effect, performing_player)
	continue_player_action_resolution(performing_player)
	return true

func do_character_action(performing_player : Player, card_ids, action_idx : int = 0, use_free_force = false, spent_life_for_force : int = 0):
	printlog("MainAction: CHARACTER_ACTION %s by %s" % [str(action_idx), get_player_name(performing_player.my_id)])
	if game_state != Enums.GameState.GameState_PickAction:
		printlog("ERROR: Tried to character action but not in correct game state.")
		return false

	if performing_player.my_id != active_turn_player:
		printlog("ERROR: Tried to character action but not current player")
		return false

	var action = performing_player.get_character_action(action_idx)
	var force_cost = action['force_cost']
	var gauge_cost = action['gauge_cost']
	if not performing_player.can_pay_cost_with(card_ids, force_cost, gauge_cost, use_free_force, spent_life_for_force):
		printlog("ERROR: Tried to character action but can't pay cost with these cards.")
		return false

	var action_name = "角色主行动"
	if 'action_name' in action:
		action_name = action['action_name']
	_append_log_full(Enums.LogType.LogType_Action, performing_player, "回合行动：%s" % action_name)
	# Spend the cards used to pay the cost.
	if card_ids.size() > 0:
		var card_names = card_db.get_card_name(card_ids[0])
		for i in range(1, card_ids.size()):
			card_names += ", " + card_db.get_card_name(card_ids[0])
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "通过弃置%s支付该行动费用。" % _log_card_name(card_names))
		performing_player.discard(card_ids)
	if not handle_spend_life_for_force(performing_player, spent_life_for_force):
		return false
	if game_over:
		return true
	performing_player.total_force_spent_this_turn += force_cost

	# Do the character action effects.
	create_event(Enums.EventType.EventType_CharacterAction, performing_player.my_id, 0)
	performing_player.used_character_action = true
	var exceed_detail = "exceed" if performing_player.exceeded else "default"
	performing_player.used_character_action_details.append([exceed_detail, action_idx])
	active_character_action = true
	active_bonus_turn_action = false
	do_effect_if_condition_met(performing_player, -1, action['effect'], null)
	if game_state not in [
			Enums.GameState.GameState_WaitForStrike,
			Enums.GameState.GameState_PlayerDecision,
			Enums.GameState.GameState_Strike_Opponent_Set_First,
			Enums.GameState.GameState_Strike_Opponent_Response
	] and not wait_for_mid_strike_boost():
		check_hand_size_advance_turn(performing_player)
	if game_state != Enums.GameState.GameState_PlayerDecision:
		active_character_action = false
	return true

func do_bonus_turn_action(performing_player : Player, action_index : int):
	printlog("MainAction: BONUS_ACTION by %s" % [get_player_name(performing_player.my_id)])
	if game_state != Enums.GameState.GameState_PickAction:
		printlog("ERROR: Tried to bonus action but not in correct game state.")
		return false

	if performing_player.my_id != active_turn_player:
		printlog("ERROR: Tried to bonus action but not current player")
		return false

	var actions = performing_player.get_bonus_actions()
	if action_index >= len(actions):
		printlog("ERROR: Tried to bonus action with invalid index.")
		return false

	var chosen_action = actions[action_index]
	var bonus_force_cost = int(chosen_action.get("force_cost", 0))
	var bonus_gauge_cost = int(chosen_action.get("gauge_cost", 0))
	if performing_player.get_available_force() < bonus_force_cost:
		printlog("ERROR: Tried to bonus action without enough force.")
		return false
	if performing_player.get_available_gauge() < bonus_gauge_cost:
		printlog("ERROR: Tried to bonus action without enough gauge.")
		return false

	var action_name = "Special Action"
	if 'text' in chosen_action:
		action_name = chosen_action['text']
	_append_log_full(Enums.LogType.LogType_Action, performing_player, "回合行动：%s" % action_name)

	# Handle the bonus action effects as a character action.
	add_queued_effect(chosen_action)
	active_character_action = true
	active_bonus_turn_action = true
	set_player_action_processing_state()
	continue_player_action_resolution(performing_player)
	return true

func do_choose_multiple_from_topdeck(performing_player : Player, chosen_card_ids : Array, _action : String) -> bool:
	# Multi-select sibling of do_choose_from_topdeck, used by effects that let
	# the player look at the top N cards and pick ANY NUMBER of them (Heidi
	# 匕首风暴·三倍插入). The chosen cards are played for free - and sustained
	# when the effect asks for it - while every looked-at card that was not
	# chosen is discarded.
	printlog("SubAction: CHOOSE_MULTIPLE_FROM_TOPDECK by %s cards %s" % [get_player_name(performing_player.my_id), str(chosen_card_ids)])
	if game_state != Enums.GameState.GameState_PlayerDecision or decision_info.type != Enums.DecisionType.DecisionType_ChooseFromTopDeck:
		printlog("ERROR: Tried to choose from topdeck but not in correct game state.")
		return false

	var effect = decision_info.effect
	if effect == null:
		effect = {}
	var look_amount = min(decision_info.amount, performing_player.deck.size())

	# Snapshot the looked-at cards before anything moves.
	var looked_ids = []
	for i in range(look_amount):
		looked_ids.append(performing_player.deck[i].id)

	# Only accept cards that were actually looked at and that the effect allows
	# (e.g. "continuous" only). Anything else is treated as not chosen.
	var limitation = effect.get('limitation', "")
	var chosen_ids = []
	for id in chosen_card_ids:
		if not (id in looked_ids) or chosen_ids.has(id):
			continue
		if limitation != "":
			var picked_card = card_db.get_card(id)
			if picked_card.definition['boost']['boost_type'] != limitation and picked_card.definition['type'] != limitation:
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "无法将 %s 作为加成打出。" % _log_card_name(card_db.get_card_name(id)))
				continue
		chosen_ids.append(id)

	var leftover_ids = []
	for id in looked_ids:
		if not chosen_ids.has(id):
			leftover_ids.append(id)

	# Every looked-at card leaves the deck. The chosen ones go to hand (they
	# are boosted from there); the rest go straight to the discard pile.
	for id in looked_ids:
		var looked_card = card_db.get_card(id)
		performing_player.remove_card_from_deck(id)
		performing_player.add_to_hand(looked_card, false)

	if not leftover_ids.is_empty():
		performing_player.discard(leftover_ids)
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "弃置未选择的牌：%s。" % _log_card_name(card_db.get_card_names(leftover_ids)))

	set_player_action_processing_state()

	if chosen_ids.is_empty() or not active_strike:
		# Nothing chosen: the effect is done, resume normal resolution.
		_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "没有将任何牌设为加成。")
		decision_info.clear()
		continue_player_action_resolution(performing_player)
		return true

	# Queue the chosen cards; do_chosen_topdeck_boost() plays them one at a
	# time so each one goes through the usual boost cleanup, which is what
	# applies the per-boost sustain flag and ignore_costs.
	active_strike.remaining_forced_boosts = chosen_ids.size()
	active_strike.remaining_forced_boosts_source = "topdeck_choice"
	active_strike.remaining_forced_boosts_player_id = performing_player.my_id
	active_strike.remaining_forced_boosts_sustaining = effect.get('sustain', true)
	active_strike.remaining_forced_boosts_ignore_costs = effect.get('ignore_costs', false)
	active_strike.remaining_forced_boosts_card_ids = chosen_ids
	decision_info.clear()
	do_chosen_topdeck_boost()
	return true

func do_choose_from_topdeck(performing_player : Player, chosen_card_id : int, action : String):
	printlog("SubAction: CHOOSE_FROM_TOPDECK by %s" % [get_player_name(performing_player.my_id)])
	if game_state != Enums.GameState.GameState_PlayerDecision or decision_info.type != Enums.DecisionType.DecisionType_ChooseFromTopDeck:
		printlog("ERROR: Tried to choose from topdeck but not in correct game state.")
		return false

	if decision_info.select_multiple:
		# Multi-select decision (choose any number): a single-card submit is
		# just the degenerate case of the set-based handler.
		var multi_ids = [] if chosen_card_id == -1 else [chosen_card_id]
		return do_choose_multiple_from_topdeck(performing_player, multi_ids, action)

	# Support for_other_player: use the actual player who made the choice
	var target_player = performing_player
	if decision_info.player != performing_player.my_id:
		target_player = _get_player(decision_info.player)

	var destination = decision_info.destination
	var look_amount = decision_info.amount

	var passed = false
	if action == StrikeEffects.Pass:
		passed = true
		chosen_card_id = -1

	var leftover_card_ids = []
	var draw_selected_from_top = decision_info.effect and decision_info.effect.get("draw_selected_from_top", false)
	var move_selected_directly_to_hand = decision_info.effect \
		and decision_info.effect.get("move_selected_directly_to_hand", false)
	var move_selected_directly_to_topdeck = action == "topdeck" \
		and decision_info.effect \
		and decision_info.effect.get("move_selected_directly_to_topdeck", false)
	if move_selected_directly_to_hand:
		if not passed:
			var looked_card_ids = []
			for i in range(look_amount):
				looked_card_ids.append(target_player.deck[i].id)
			if chosen_card_id not in looked_card_ids:
				printlog("ERROR: Tried to add a card to hand that was not in the viewed deck cards.")
				return false
			var chosen_card = card_db.get_card(chosen_card_id)
			target_player.remove_card_from_deck(chosen_card_id)
			target_player.add_to_hand(chosen_card, false)
		if decision_info.effect.get("shuffle_after", false):
			target_player.random_shuffle_deck()
	elif move_selected_directly_to_topdeck:
		var looked_card_ids = []
		for i in range(look_amount):
			looked_card_ids.append(target_player.deck[i].id)
		if chosen_card_id not in looked_card_ids:
			printlog("ERROR: Tried to topdeck a card that was not in the viewed deck cards.")
			return false
		var chosen_card = card_db.get_card(chosen_card_id)
		target_player.remove_card_from_deck(chosen_card_id)
		target_player.add_to_top_of_deck(chosen_card, false)
	elif draw_selected_from_top:
		if passed:
			target_player.random_shuffle_deck()
		elif action == "add_to_hand":
			var looked_card_ids = []
			for i in range(look_amount):
				looked_card_ids.append(target_player.deck[i].id)
			if chosen_card_id not in looked_card_ids:
				printlog("ERROR: Tried to draw a card that was not in the viewed deck cards.")
				return false
			var chosen_card = card_db.get_card(chosen_card_id)
			target_player.remove_card_from_deck(chosen_card_id)
			target_player.add_to_top_of_deck(chosen_card, false)
			target_player.draw(1)
			_append_log_full(Enums.LogType.LogType_CardInfo, target_player, "抽1张牌。")
		else:
			printlog("ERROR: Unsupported action for draw-selected-from-top effect.")
			return false
	else:
		for i in range(look_amount):
			var id = performing_player.deck[i].id
			if chosen_card_id != id:
				leftover_card_ids.append(id)

		var will_replace_leftovers = false
		if destination == "topdeck":
			will_replace_leftovers = true
		target_player.draw(look_amount, false, false, not will_replace_leftovers)
		var leftover_card_names = card_db.get_card_names(leftover_card_ids)
		match destination:
			"discard":
				target_player.discard(leftover_card_ids)
				_append_log_full(Enums.LogType.LogType_CardInfo, target_player, "discards the unchosen cards: %s." % _log_card_name(leftover_card_names))
			"topdeck":
				for card_id in leftover_card_ids:
					target_player.move_card_from_hand_to_deck(card_id)
				if decision_info.effect and decision_info.effect.get("shuffle_after"):
					target_player.random_shuffle_deck()
				target_player.update_public_hand_if_deck_empty()
			_:
				printlog("ERROR: Choose from topdeck destination not implemented.")
				assert(false, "Choose from topdeck destination not implemented.")
				return false

	# If this effect came from a boost and another action is about to happen, cleanup that boost before continuing.
	set_player_action_processing_state()
	decision_info.action = action

	var did_strike_or_boost = false
	var real_actions = ["boost", StrikeEffects.Strike, StrikeEffects.Pass]
	if action in real_actions and active_boost:
		active_boost.action_after_boost = true
		active_boost.effects_resolved += 1
		continue_resolve_boost()

	# Now the boost is done and we are in the pick action state.
	match action:
		"boost":
			# 顶牌效果可以要求「免费 / 限定加成」：把 effect 上的 ignore_costs /
			# limitation 传给随后的 do_boost（海蒂 匕首风暴曾用此路径；现有卡无此字段时为空操作）。
			if decision_info.effect:
				if decision_info.effect.get("ignore_costs"):
					decision_info.ignore_costs = true
				if 'limitation' in decision_info.effect and decision_info.effect['limitation'] != "":
					decision_info.limitation = decision_info.effect['limitation']
			change_game_state(Enums.GameState.GameState_PlayerDecision)
			decision_info.type = Enums.DecisionType.DecisionType_BoostNow
			do_boost(target_player, chosen_card_id)
			did_strike_or_boost = true
		"boost_after_current":
			assert(active_boost, "ERROR: Expected a boost to be active for boost_after_current.")
			active_boost.queued_boosts.append(chosen_card_id)
			# Set aside to avoid it being spent for something else
			target_player.move_card_from_hand_to_stored_cards(chosen_card_id, false)
		StrikeEffects.Strike:
			change_game_state(Enums.GameState.GameState_PickAction)
			do_strike(target_player, chosen_card_id, false, -1)
			did_strike_or_boost = true
		"strike_after_current":
			assert(active_boost, "ERROR: Expected a boost to be active for boost_after_current.")
			change_game_state(Enums.GameState.GameState_WaitForStrike)
			decision_info.clear()
			decision_info.type = Enums.DecisionType.DecisionType_StrikeNow
			decision_info.player = target_player.my_id
			active_boost.strike_after_boost_stored_id = chosen_card_id
		"add_to_hand":
			# We've already drawn the cards we looked at
			if not draw_selected_from_top:
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将其中一张牌加入手牌。")
		"add_to_gauge":
			performing_player.move_card_from_hand_to_gauge(chosen_card_id)
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将其中一张牌加入怒气：%s。" % _log_card_name(card_db.get_card_name(chosen_card_id)))
		"add_to_overdrive":
			performing_player.move_cards_to_overdrive([chosen_card_id], "hand")
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将其中一张牌加入超载：%s。" % _log_card_name(card_db.get_card_name(chosen_card_id)))
		"add_to_sealed":
			do_seal_effect(performing_player, chosen_card_id, "hand")
			if performing_player.sealed_area_is_secret:
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将其中一张牌加入背面封印。")
			else:
				_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将其中一张牌加入封印：%s。" % _log_card_name(card_db.get_card_name(chosen_card_id)))
		"add_to_topdeck_under":
			assert(leftover_card_ids.size() == 1 or leftover_card_ids.size() == 0)
			# If this was the last card in deck, leftover_card_ids.size is 0, so this card goes on top.
			var destination_index = leftover_card_ids.size()
			performing_player.move_card_from_hand_to_deck(chosen_card_id, destination_index)
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将剩余的牌放回其牌库顶。")
		"add_to_topdeck_under_2":
			# The assumption for this ability is that the player returned 2 cards
			# to the top of their deck and this goes under them.
			assert(leftover_card_ids.size() == 2)
			var destination_index = leftover_card_ids.size()
			performing_player.move_card_from_hand_to_deck(chosen_card_id, destination_index)
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将剩余的牌放回其牌库顶。")
		"topdeck":
			if not move_selected_directly_to_topdeck:
				for card_id in leftover_card_ids:
					performing_player.move_card_from_hand_to_deck(card_id)
				performing_player.move_card_from_hand_to_deck(chosen_card_id)
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "将其中一张牌放回牌库顶。")
		"discard":
			performing_player.discard([chosen_card_id])
			_append_log_full(Enums.LogType.LogType_CardInfo, performing_player, "弃置其中一张牌：%s。" % _log_card_name(card_db.get_card_name(chosen_card_id)))
		StrikeEffects.Pass:
			if not active_strike:
				check_hand_size_advance_turn(performing_player)
		_:
			assert(false, "Unknown action for choose from topdeck.")

	# Resolve chained search effects before cleaning up the boost. Monologue,
	# for example, performs a second deck choice after the first selected card.
	if not passed and game_state != Enums.GameState.GameState_PlayerDecision:
		if decision_info.bonus_effect:
			handle_strike_effect(decision_info.choice_card_id, decision_info.bonus_effect, performing_player)
			if game_state == Enums.GameState.GameState_PlayerDecision:
				return true

	# If it wasn't a "real" action, clean up the boost now
	if action not in real_actions and active_boost:
		if game_state != Enums.GameState.GameState_PlayerDecision:
			active_boost.effects_resolved += 1
			continue_resolve_boost()
	else:
		# If this choose started a strike or boost, don't try to continue the player action resolution.
		if not did_strike_or_boost:
			# Came from somewhere else (maybe exceed or character action?)
			continue_player_action_resolution(performing_player)
	return true

func do_quit(player_id : Enums.PlayerId, reason : Enums.GameOverReason):
	printlog("InitialAction: QUIT by %s" % [get_player_name(player_id)])
	var performing_player = _get_player(player_id)
	if reason == Enums.GameOverReason.GameOverReason_Quit:
		_append_log_full(Enums.LogType.LogType_Default, performing_player, "投降认输。")
	else:
		_append_log_full(Enums.LogType.LogType_Default, performing_player, "离开了游戏。")
	if game_state == Enums.GameState.GameState_GameOver:
		printlog("ERROR: Game already over.")
		return false

	create_event(Enums.EventType.EventType_GameOver, player_id, reason)
	return true

func do_clock_ran_out(player_id : Enums.PlayerId):
	printlog("InitialAction: CLOCK RAN OUT by %s" % [get_player_name(player_id)])
	var performing_player = _get_player(player_id)
	_append_log_full(Enums.LogType.LogType_Default, performing_player, "计时耗尽。")
	if game_state == Enums.GameState.GameState_GameOver:
		printlog("ERROR: Game already over.")
		return false

	create_event(Enums.EventType.EventType_GameOver, player_id, Enums.GameOverReason.GameOverReason_ClockRanOut)
	return true

func do_emote(performing_player : Player, is_image_emote : bool, emote : String):
	printlog("Emote by %s: %s" % [get_player_name(performing_player.my_id), emote])
	create_event(Enums.EventType.EventType_Emote, performing_player.my_id, is_image_emote, emote)
	return true

func do_match_result(_player_clock_remaining, _opponent_clock_remaining):
	return true
