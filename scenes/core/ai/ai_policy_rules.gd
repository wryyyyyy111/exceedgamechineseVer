class_name AIPolicyRules
extends Node


# ============================================================
# Section 1: Math Utilities
# ============================================================

var __factorial_cache = {
	"cache_max": 7,
	0: 1, 1: 1, 2: 2, 3: 6, 4: 24,
	5: 120, 6: 720, 7: 5040,
}

func _factorial(n: int) -> int:
	if n not in __factorial_cache:
		for i in range(__factorial_cache["cache_max"] + 1, n + 1):
			__factorial_cache[i] = __factorial_cache[i-1] * i
	return __factorial_cache[n]


var __combinations_cache = {
	[0, 0]: 1, [1, 0]: 1, [1, 1]: 1,
	[2, 0]: 1, [2, 1]: 2, [2, 2]: 1,
}

func _combinations(n: int, r: int) -> int:
	if n < r:
		return 0
	if [n, r] not in __combinations_cache:
		if r == 0 or r == n:
			__combinations_cache[[n, r]] = 1
		else:
			__combinations_cache[[n, r]] = _combinations(n-1, r) + _combinations(n-1, r-1)
	return __combinations_cache[[n, r]]


## Return the probability of hitting at least one of the IDs in `cards_to_find` when
## choosing `num_draws` elements at random from `deck`, without replacement.
func _probability_of_drawing(cards_to_find: Array, num_draws: int, deck: Array) -> float:
	var total_cards = deck.size()
	var total_success_cards = 0
	for card in deck:
		if card in cards_to_find:
			total_success_cards += 1
	if total_success_cards == 0:
		return 0.0

	if num_draws == 1:
		return total_success_cards * 1.0 / total_cards

	if num_draws > total_cards:
		num_draws = total_cards

	var total_cases = _combinations(total_cards, num_draws)
	var total_miss_cases = _combinations(total_cards - total_success_cards, num_draws)
	var miss_probability = 1.0 * total_miss_cases / total_cases
	return 1.0 - miss_probability


# ============================================================
# Section 2: Card & Game State Evaluation
# ============================================================

## Evaluate how valuable a card is. Higher = more valuable, keep it.
## Used for discard/gauge/payment decisions.
func evaluate_card_value(card_id: int, ai_game_state: AIPlayer.AIGameState) -> float:
	if card_id == -1:
		return 0.0
	var card_db = ai_game_state.card_db
	var card: GameCard = card_db.get_card(card_id)
	if not card or not card.definition:
		return 0.0
	var defn: Dictionary = card.definition
	var value: float = 0.0

	# ---- Type base value ----
	match defn.get('type', ''):
		'ultra': value += 12.0
		'special': value += 6.0
		'normal': value += 2.0
		'decree_glorious': value += 15.0
		_: value += 2.0

	# ---- Strike potential ----
	var damage = defn.get('damage', 0)
	if damage > 0:
		value += damage * 1.5
	var guard_val = defn.get('guard', 0)
	if guard_val > 0:
		value += guard_val * 1.0

	# ---- Can it hit from current position? ----
	if can_card_hit(card_id, -1, ai_game_state):
		value += 8.0  # Big bonus for being immediately usable

	# ---- Gauge cost (higher cost = less flexible) ----
	var gauge_cost = defn.get('gauge_cost', 0)
	value -= gauge_cost * 2.0

	# ---- Boost quality ----
	var boost = defn.get('boost', {})
	if boost:
		match boost.get('boost_type', ''):
			'continuous': value += 3.0
			'transform': value += 4.0
			'overload': value += 5.0
			_: value += 2.0
		var boost_force_cost = boost.get('force_cost', 0)
		var boost_gauge_cost = boost.get('gauge_cost', 0)
		value -= max(boost_force_cost, boost_gauge_cost) * 0.5

	# ---- Force value (higher force = better for spending, so LOWER card value) ----
	# Cards with high force are "fuel" — we want to spend them first.
	var force_val = card_db.get_card_force_value(card_id)
	value -= force_val * 0.8

	# ---- Special properties ----
	if defn.get('cannot_discard', false):
		value += 2.0  # Harder to get rid of, treat as more valuable
	if defn.get('must_set_from_boost', false) or defn.get('may_set_from_boost', false):
		value += 2.0  # Can strike from boost — flexibility

	return value


## Evaluate how good a position is for the AI player.
## Returns a score — higher is better.
func evaluate_position(my_location: int, opponent_location: int, hand_ids: Array, ai_game_state: AIPlayer.AIGameState) -> float:
	var score: float = 0.0
	var distance = abs(my_location - opponent_location)
	if distance == 0:
		return -50.0  # Can't share space

	# Count strikes that can hit from this position
	var hitting_strikes = 0
	var total_strike_damage = 0
	for card_id in hand_ids:
		if card_id == -1:
			continue
		if _can_hit_from_position(card_id, my_location, opponent_location, ai_game_state):
			hitting_strikes += 1
			var card = ai_game_state.card_db.get_card(card_id)
			if card and card.definition:
				total_strike_damage += card.definition.get('damage', 0)

	score += hitting_strikes * 12.0
	score += total_strike_damage * 2.0

	# Prefer being at range 1-3 (standard strike range)
	if distance >= 1 and distance <= 3:
		score += 8.0
	# Being at extreme range is situational
	elif distance >= 7:
		score -= 3.0

	return score


## Evaluate the overall board state from the AI's perspective.
func evaluate_board_state(ai_game_state: AIPlayer.AIGameState) -> float:
	var score: float = 0.0
	var my = ai_game_state.my_state
	var opp = ai_game_state.opponent_state

	# Life advantage
	var life_diff = opp.life - my.life
	score += life_diff * 5.0  # Positive when we're ahead

	# Hand size advantage
	var hand_diff = my.hand.size() - opp.hand.size()
	score += hand_diff * 3.0

	# Gauge advantage
	var gauge_diff = my.gauge.size() - opp.gauge.size()
	score += gauge_diff * 2.0

	# Position quality
	score += evaluate_position(my.arena_location, opp.arena_location, my.hand, ai_game_state)

	# Critical life thresholds
	if my.life <= 5:
		score -= (6 - my.life) * 8.0  # Big penalty for low life
	if opp.life <= 5:
		score += (6 - opp.life) * 6.0  # Bonus for opponent being low

	return score


## Get card IDs from an array, sorted by value (ascending — worst first).
func _sort_card_ids_by_value(card_ids: Array, ai_game_state: AIPlayer.AIGameState) -> Array:
	var scored = []
	for card_id in card_ids:
		scored.append({"id": card_id, "score": evaluate_card_value(card_id, ai_game_state)})
	scored.sort_custom(func(a, b): return a["score"] < b["score"])
	var result = []
	for entry in scored:
		result.append(entry["id"])
	return result


## Return the N worst (lowest value) card IDs from the given list.
func _get_worst_cards(card_ids: Array, count: int, ai_game_state: AIPlayer.AIGameState) -> Array:
	if count <= 0:
		return []
	var sorted = _sort_card_ids_by_value(card_ids, ai_game_state)
	var result = []
	for i in range(min(count, sorted.size())):
		result.append(sorted[i])
	return result


## Return the best (highest value) card ID from the given list.
func _get_best_card(card_ids: Array, ai_game_state: AIPlayer.AIGameState) -> int:
	if card_ids.is_empty():
		return -1
	var best_id = card_ids[0]
	var best_score = evaluate_card_value(best_id, ai_game_state)
	for card_id in card_ids:
		var score = evaluate_card_value(card_id, ai_game_state)
		if score > best_score:
			best_score = score
			best_id = card_id
	return best_id


# ============================================================
# Section 3: Range & Hit Detection
# ============================================================

func calculate_damage_for_strike(_check_player: Enums.PlayerId, ai_game_state: AIPlayer.AIGameState) -> int:
	var strike = ai_game_state.active_strike
	if not strike or not strike.active:
		return 4
	var card_id = strike.initiator_card_id
	if strike.initiator_ex_card_id != -1:
		card_id = strike.initiator_ex_card_id
	var card = ai_game_state.card_db.get_card(card_id)
	if card and card.definition:
		return card.definition.get('damage', 4)
	return 4


func get_locations_after_effect(effect, my_location, opponent_location, buddy_location):
	var direction = -1
	if my_location < opponent_location:
		direction = 1

	match effect['effect_type']:
		'advance':
			for i in range(effect['amount']):
				my_location += direction
				if my_location == opponent_location:
					my_location += direction
			my_location = clamp(my_location, 1, 9)
			if my_location == opponent_location:
				my_location -= direction
		'close':
			for i in range(effect['amount']):
				my_location += direction
				if my_location == opponent_location:
					my_location -= direction
					break
		'pull':
			for i in range(effect['amount']):
				opponent_location -= direction
				if my_location == opponent_location:
					opponent_location -= direction
			opponent_location = clamp(opponent_location, 1, 9)
			if my_location == opponent_location:
				opponent_location += direction
		'push':
			for i in range(effect['amount']):
				opponent_location += direction
			opponent_location = clamp(opponent_location, 1, 9)
		'retreat':
			for i in range(effect['amount']):
				my_location -= direction
			my_location = clamp(my_location, 1, 9)
		'place_buddy_onto_self':
			buddy_location = my_location

	if 'and' in effect:
		var and_result = get_locations_after_effect(effect['and'], my_location, opponent_location, buddy_location)
		my_location = and_result['my_location']
		opponent_location = and_result['opponent_location']

	var result = {
		"my_location": my_location,
		"opponent_location": opponent_location,
		"buddy_location": buddy_location
	}
	return result


## Check if a card can hit given explicit positions (used for position evaluation).
func _can_hit_from_position(card_id: int, my_location: int, opponent_location: int, ai_game_state: AIPlayer.AIGameState) -> bool:
	if card_id == -1:
		return false

	var card: GameCard = ai_game_state.card_db.get_card(card_id)
	if not card or not card.definition:
		return false

	var blocks = ["gg_normal_block", "uni_normal_block", "standard_normal_block"]
	if card.definition['id'] in blocks:
		return true  # Blocks always "hit"

	var gauge_cost = card.definition.get('gauge_cost', 0)
	if gauge_cost > ai_game_state.my_state.gauge.size():
		return false

	var buddy_location = -1
	if ai_game_state.my_state.buddy_locations.size() > 0:
		buddy_location = ai_game_state.my_state.buddy_locations[0]
	var from_buddy = false
	for effect in card.definition.get('effects', []):
		if effect.get('timing', '') == "before":
			var result = get_locations_after_effect(effect, my_location, opponent_location, buddy_location)
			my_location = result['my_location']
			opponent_location = result['opponent_location']
			buddy_location = result['buddy_location']
		if effect.get('effect_type', '') == "calculate_range_from_buddy":
			from_buddy = true

	var distance_after_effects = abs(my_location - opponent_location)
	if from_buddy and buddy_location >= 0:
		distance_after_effects = abs(buddy_location - opponent_location)

	var range_min = card.definition.get('range_min', 1)
	if range_min is String:
		range_min = 1
	var range_max = card.definition.get('range_max', 99)
	if range_max is String:
		range_max = range_min + 3

	return range_min <= distance_after_effects and distance_after_effects <= range_max


func can_card_hit(card_id: int, ex_card_id: int, ai_game_state: AIPlayer.AIGameState) -> bool:
	if card_id == -1:
		return false

	var card: GameCard = ai_game_state.card_db.get_card(card_id)
	var ex_card = null
	if ex_card_id != -1:
		ex_card = ai_game_state.card_db.get_card(ex_card_id)
	var blocks = ["gg_normal_block", "uni_normal_block", "standard_normal_block"]
	if card.definition['id'] in blocks:
		if ex_card and ex_card.definition['id'] in blocks:
			# No EX Block!
			return false
		return true

	# Calculate gauge cost — use EX card's cost if EX is being used.
	var effective_gauge_cost = card.definition.get('gauge_cost', 0)
	if ex_card and ex_card.definition:
		effective_gauge_cost = ex_card.definition.get('gauge_cost', effective_gauge_cost)
	if effective_gauge_cost > ai_game_state.my_state.gauge.size():
		return false

	var my_location = ai_game_state.my_state.arena_location
	var opponent_location = ai_game_state.opponent_state.arena_location
	var buddy_location = -1
	if ai_game_state.my_state.buddy_locations.size() > 0:
		buddy_location = ai_game_state.my_state.buddy_locations[0]
	var from_buddy = false

	# Use EX card's effects for range calculation if EX is used.
	var effects = card.definition.get('effects', [])
	if ex_card and ex_card.definition:
		effects = ex_card.definition.get('effects', effects)

	for effect in effects:
		if effect.get('timing', '') == "before":
			var result = get_locations_after_effect(effect, my_location, opponent_location, buddy_location)
			my_location = result['my_location']
			opponent_location = result['opponent_location']
			buddy_location = result['buddy_location']
		if effect.get('effect_type', '') == "calculate_range_from_buddy":
			from_buddy = true

	var distance_after_effects = abs(my_location - opponent_location)
	if from_buddy and buddy_location >= 0:
		distance_after_effects = abs(buddy_location - opponent_location)

	# Use EX card's range if available.
	var range_min = card.definition.get('range_min', 1)
	var range_max = card.definition.get('range_max', 99)
	if ex_card and ex_card.definition:
		range_min = ex_card.definition.get('range_min', range_min)
		range_max = ex_card.definition.get('range_max', range_max)

	if range_min is String:
		range_min = 1
	if range_max is String:
		range_max = range_min + 3
	return range_min <= distance_after_effects and distance_after_effects <= range_max


# ============================================================
# Section 4: Action Scoring Helpers
# ============================================================

## Score a strike action. Higher = better.
func _score_strike(action, ai_game_state: AIPlayer.AIGameState) -> float:
	if action.wild_swing:
		return 25.0  # Wild swing — decent fallback

	var card = ai_game_state.card_db.get_card(action.card_id)
	if not card or not card.definition:
		return 0.0

	var score: float = 0.0
	var damage = card.definition.get('damage', 4)
	score += damage * 10.0
	score += card.definition.get('guard', 0) * 4.0

	if action.ex_card_id != -1:
		score += 18.0  # EX is significantly better

	var gauge_cost = card.definition.get('gauge_cost', 0)
	score -= gauge_cost * 5.0

	# Penalty if we're spending our last gauge
	if ai_game_state.my_state.gauge.size() <= gauge_cost + 1:
		score -= 15.0

	# Bonus if opponent life is low and this could finish them
	if ai_game_state.opponent_state.life <= damage:
		score += 50.0

	return score


## Score a move action.
func _score_move(action, ai_game_state: AIPlayer.AIGameState) -> float:
	var _new_dist = abs(action.location - ai_game_state.opponent_state.arena_location)
	var score: float = 0.0

	# Position quality
	score += evaluate_position(action.location, ai_game_state.opponent_state.arena_location,
		ai_game_state.my_state.hand, ai_game_state)

	# Prefer getting closer if we have strikes to use
	var current_hits = 0
	var new_hits = 0
	for card_id in ai_game_state.my_state.hand:
		if can_card_hit(card_id, -1, ai_game_state):
			current_hits += 1
		if _can_hit_from_position(card_id, action.location, ai_game_state.opponent_state.arena_location, ai_game_state):
			new_hits += 1

	if new_hits > current_hits:
		score += 20.0
	elif new_hits < current_hits and current_hits > 0:
		score -= 20.0  # Don't lose hitting positions

	# Cost of moving
	score -= action.force_card_ids.size() * 8.0
	if action.use_free_force:
		score += 4.0  # Free force is better than spending cards

	return score


## Score a boost action.
func _score_boost(action, ai_game_state: AIPlayer.AIGameState) -> float:
	if not (action is AIPlayer.BoostAction):
		return 0.0

	var card = ai_game_state.card_db.get_card(action.card_id)
	if not card or not card.definition:
		return 0.0

	var score: float = 0.0
	var boost = card.definition.get('boost', {})

	# Prefer continuous boosts (they persist)
	match boost.get('boost_type', ''):
		'continuous': score += 20.0
		'transform': score += 10.0
		'overload': score += 5.0
		_: score += 2.0

	# Don't boost if we already have enough continuous boosts
	if boost.get('boost_type', '') == 'continuous' and ai_game_state.my_state.continuous_boosts.size() >= 3:
		score -= 10.0

	# Cost penalty
	score -= action.payment_card_ids.size() * 5.0
	if action.use_free_force:
		score += 3.0

	# Slight random factor to avoid predictability
	score += randf() * 3.0

	return score


## Score a character action.
func _score_character_action(action, ai_game_state: AIPlayer.AIGameState) -> float:
	var score: float = 15.0
	score -= action.card_ids.size() * 5.0
	if action.use_free_force:
		score += 3.0

	var deck_id = ai_game_state.my_state.deck_def.get('id', '')
	if deck_id == 'bison':
		if ai_game_state.my_state.gauge.size() > 5:
			score -= 20.0
	elif deck_id == 'goldlewis':
		score += 10.0
	elif deck_id == 'hakumen':
		score += 8.0

	return score


# ============================================================
# Section 5: Main Turn Decision
# ============================================================

func pick_turn_action(possible_actions, ai_game_state):
	var my = ai_game_state.my_state
	var opp = ai_game_state.opponent_state

	# ---- Categorize actions ----
	var exceed_actions = []
	var strike_actions = []
	var move_actions = []
	var boost_actions = []
	var character_actions = []
	var change_actions = []
	var prepare_action = null
	var reshuffle_action = null

	for action in possible_actions:
		if action is AIPlayer.ExceedAction:
			exceed_actions.append(action)
		elif action is AIPlayer.StrikeAction:
			strike_actions.append(action)
		elif action is AIPlayer.MoveAction:
			move_actions.append(action)
		elif action is AIPlayer.BoostAction:
			boost_actions.append(action)
		elif action is AIPlayer.CharacterActionAction:
			character_actions.append(action)
		elif action is AIPlayer.ChangeCardsAction:
			change_actions.append(action)
		elif action is AIPlayer.PrepareAction:
			prepare_action = action
		elif action is AIPlayer.ReshuffleAction:
			reshuffle_action = action

	# ---- 1. Exceed if available (almost always correct) ----
	if exceed_actions.size() > 0:
		# Exceed if ahead on cards or life is critical
		if my.hand.size() >= opp.hand.size() or my.life <= 8:
			return exceed_actions[0]
		# Also exceed if we have gauge to spare
		if my.gauge.size() >= 5:
			return exceed_actions[0]

	# ---- 2. Evaluate strike options ----
	var valid_strikes = []
	var best_strike = null
	var best_strike_score: float = -9999.0
	for action in strike_actions:
		if can_card_hit(action.card_id, action.ex_card_id, ai_game_state):
			valid_strikes.append(action)

	if valid_strikes.size() > 0:
		# Are we in a good position to strike?
		best_strike = valid_strikes[0]
		best_strike_score = _score_strike(best_strike, ai_game_state)
		for action in valid_strikes:
			var s = _score_strike(action, ai_game_state)
			if s > best_strike_score:
				best_strike_score = s
				best_strike = action

		# Strike if:
		# - We have a lethal strike
		# - We have a very good strike (score > 50)
		# - We have more cards than opponent (we're ahead on tempo)
		# - Our hand is large (>= 6)
		var card_db = ai_game_state.card_db
		var strike_card = card_db.get_card(best_strike.card_id) if not best_strike.wild_swing else null
		var strike_damage = strike_card.definition.get('damage', 4) if strike_card else 2

		if strike_damage >= opp.life:
			return best_strike  # Lethal!
		if best_strike_score > 50.0:
			return best_strike
		if my.hand.size() >= opp.hand.size() + 2 and best_strike_score > 30.0:
			return best_strike
		if my.hand.size() >= 6 and best_strike_score > 25.0:
			return best_strike

	# ---- 3. Evaluate move options ----
	if move_actions.size() > 0:
		var best_move = move_actions[0]
		var best_move_score = _score_move(best_move, ai_game_state)
		for action in move_actions:
			var s = _score_move(action, ai_game_state)
			if s > best_move_score:
				best_move_score = s
				best_move = action

		# Move if we have no valid strikes at current position (need to reposition)
		if valid_strikes.size() == 0 and best_move_score > -10.0:
			return best_move
		# Move if position significantly improves
		var current_pos_score = evaluate_position(my.arena_location, opp.arena_location, my.hand, ai_game_state)
		if best_move_score > current_pos_score + 15.0:
			return best_move

	# ---- 4. Evaluate boost options ----
	if boost_actions.size() > 0 and my.continuous_boosts.size() < 4:
		var best_boost = boost_actions[0]
		var best_boost_score = _score_boost(best_boost, ai_game_state)
		for action in boost_actions:
			var s = _score_boost(action, ai_game_state)
			if s > best_boost_score:
				best_boost_score = s
				best_boost = action

		# Boost if we have good options and don't urgently need to strike
		if best_boost_score > 15.0 and my.hand.size() >= 4:
			# But prefer striking if we have good strikes
			if valid_strikes.size() == 0 or best_boost_score > best_strike_score + 10.0:
				return best_boost

	# ---- 5. Evaluate character actions ----
	if character_actions.size() > 0:
		# Skip character action for Bison with excess gauge
		var skip = false
		if my.deck_def.get('id', '') == 'bison' and my.gauge.size() > 3:
			skip = true

		if not skip:
			var best_ca = character_actions[0]
			var best_ca_score = _score_character_action(best_ca, ai_game_state)
			for action in character_actions:
				var s = _score_character_action(action, ai_game_state)
				if s > best_ca_score:
					best_ca_score = s
					best_ca = action

			if best_ca_score > 10.0 and randi() % 3 != 0:
				return best_ca

	# ---- 6. If low on cards, Change Cards or Prepare ----
	if my.hand.size() < 3:
		# Find the best change cards action (highest force generated)
		var best_change = null
		var best_change_force = 0
		for action in change_actions:
			var force_val = 0
			for card_id in action.card_ids:
				force_val += ai_game_state.card_db.get_card_force_value(card_id)
			if force_val > best_change_force:
				best_change_force = force_val
				best_change = action

		if best_change and best_change_force > 3:
			return best_change
		elif prepare_action:
			return prepare_action

	# ---- 7. If hand is moderate (3-5) and we have fewer cards ----
	if my.hand.size() < opp.hand.size() and my.hand.size() <= 5:
		if prepare_action:
			return prepare_action

	# ---- 8. Reshuffle if desperate ----
	if reshuffle_action and my.deck.size() < 2 and my.discards.size() > 3:
		if my.hand.size() <= 3:
			return reshuffle_action

	# ---- 9. If we still have valid strikes, go for it ----
	if valid_strikes.size() > 0:
		return valid_strikes[randi() % valid_strikes.size()]

	# ---- 10. Fallback: pick the best scoring action from what remains ----
	var best_action = possible_actions[0]
	var best_score = -9999.0
	for action in possible_actions:
		var s = 0.0
		if action is AIPlayer.StrikeAction:
			s = _score_strike(action, ai_game_state)
		elif action is AIPlayer.MoveAction:
			s = _score_move(action, ai_game_state)
		elif action is AIPlayer.BoostAction:
			s = _score_boost(action, ai_game_state)
		elif action is AIPlayer.CharacterActionAction:
			s = _score_character_action(action, ai_game_state)
		elif action is AIPlayer.ChangeCardsAction:
			s = action.card_ids.size() * 3.0
		elif action is AIPlayer.PrepareAction:
			s = 5.0
		elif action is AIPlayer.ReshuffleAction:
			s = 2.0
		elif action is AIPlayer.ExceedAction:
			s = 30.0
		if s > best_score:
			best_score = s
			best_action = action

	return best_action


# ============================================================
# Section 6: Sub-Decision Functions
# ============================================================

func pick_boost_action(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	if possible_actions.size() == 1:
		return possible_actions[0]

	# Prefer continuous boosts; within same type pick random
	var continuous = []
	var others = []
	for action in possible_actions:
		if action is AIPlayer.BoostAction:
			var card = ai_game_state.card_db.get_card(action.card_id)
			if card and card.definition.get('boost', {}).get('boost_type', '') == 'continuous':
				continuous.append(action)
			else:
				others.append(action)

	if continuous.size() > 0 and ai_game_state.my_state.continuous_boosts.size() < 4:
		return continuous[randi() % continuous.size()]
	if others.size() > 0:
		return others[randi() % others.size()]
	return possible_actions[randi() % possible_actions.size()]


func pick_pay_strike_force_cost(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	if possible_actions.size() == 1:
		return possible_actions[0]

	# Prefer actions that spend fewer / lower-value cards
	var best_action = possible_actions[0]
	var best_cost = 9999.0
	for action in possible_actions:
		if action.wild_swing:
			# Wild swing costs nothing — prefer if we need to save cards
			if ai_game_state.my_state.hand.size() <= 3:
				return action
			continue
		var cost: float = 0.0
		for card_id in action.card_ids:
			cost += evaluate_card_value(card_id, ai_game_state)
		cost += action.card_ids.size() * 2.0
		if action.use_free_force:
			cost -= 3.0  # Free force is good
		if cost < best_cost:
			best_cost = cost
			best_action = action
	return best_action


func pick_pay_strike_gauge_cost(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	if possible_actions.size() == 1:
		return possible_actions[0]

	# Prefer actions that spend lower-value gauge cards
	var best_action = possible_actions[0]
	var best_cost = 9999.0
	for action in possible_actions:
		if action.wild_swing:
			if ai_game_state.my_state.hand.size() <= 3:
				return action
			continue
		var cost: float = 0.0
		for card_id in action.card_ids:
			cost += evaluate_card_value(card_id, ai_game_state)
		if cost < best_cost:
			best_cost = cost
			best_action = action
	return best_action


func pick_effect_choice(possible_actions: Array, _ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	if possible_actions.size() == 1:
		return possible_actions[0]

	# For choice effects, prefer higher index options (usually more impactful)
	# Add slight randomness
	if randi() % 3 == 0:
		return possible_actions[randi() % possible_actions.size()]
	return possible_actions[possible_actions.size() - 1]


func pick_force_for_armor(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	if possible_actions.size() == 1:
		return possible_actions[0]

	var armor_base = 2
	var expected_damage = calculate_damage_for_strike(ai_game_state.my_state.player_id, ai_game_state)

	# Try to exactly match or slightly exceed expected damage
	var exact_matches = []
	var close_matches = []
	for action in possible_actions:
		if action is AIPlayer.ForceForArmorAction:
			var force_generated = 0
			for card_id in action.card_ids:
				force_generated += ai_game_state.card_db.get_card_force_value(card_id)
			var armor_total = armor_base + force_generated * 2

			if armor_total == expected_damage or armor_total == expected_damage + 1:
				exact_matches.append(action)
			elif armor_total >= expected_damage and armor_total <= expected_damage + 3:
				close_matches.append(action)

	# Prefer exact matches, spending lowest-value cards
	var candidates = exact_matches if exact_matches.size() > 0 else close_matches
	if candidates.size() > 0:
		var best = candidates[0]
		var match_best_cost = 9999.0
		for action in candidates:
			var cost: float = 0.0
			for card_id in action.card_ids:
				cost += evaluate_card_value(card_id, ai_game_state)
			if cost < match_best_cost:
				match_best_cost = cost
				best = action
		return best

	# Fallback: spend minimal cards for reasonable armor
	var best_action = possible_actions[0]
	var best_cost = 9999.0
	for action in possible_actions:
		var force_generated = 0
		for card_id in action.card_ids:
			force_generated += ai_game_state.card_db.get_card_force_value(card_id)
		var armor_total = armor_base + force_generated * 2

		# Prefer actions that match or exceed expected damage
		var cost: float = 0.0
		for card_id in action.card_ids:
			cost += evaluate_card_value(card_id, ai_game_state)
		if armor_total < expected_damage:
			cost += (expected_damage - armor_total) * 20.0  # Heavy penalty for under-armoring
		elif armor_total > expected_damage + 4:
			cost += (armor_total - expected_damage - 4) * 5.0  # Light penalty for over-armoring

		if cost < best_cost:
			best_cost = cost
			best_action = action
	return best_action


func pick_strike(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	if possible_actions.size() == 1:
		return possible_actions[0]

	# Separate valid strikes from wild swings
	var valid_strikes = []
	var wild_actions = []
	for action in possible_actions:
		if action is AIPlayer.StrikeAction:
			if action.wild_swing:
				wild_actions.append(action)
			elif can_card_hit(action.card_id, action.ex_card_id, ai_game_state):
				valid_strikes.append(action)

	# If we have valid strikes, pick the best one
	if valid_strikes.size() > 0:
		var best = valid_strikes[0]
		var best_score = _score_strike(best, ai_game_state)
		for action in valid_strikes:
			var s = _score_strike(action, ai_game_state)
			if s > best_score:
				best_score = s
				best = action
		return best

	# Fallback to wild swing
	if wild_actions.size() > 0:
		return wild_actions[0]

	return possible_actions[randi() % possible_actions.size()]


func pick_strike_response(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	if possible_actions.size() == 1:
		return possible_actions[0]

	var strike_choices = []
	var wild_action = null
	for action in possible_actions:
		if action is AIPlayer.StrikeAction:
			if action.wild_swing:
				wild_action = action
				continue
			if can_card_hit(action.card_id, action.ex_card_id, ai_game_state):
				strike_choices.append(action)

	if strike_choices.size() > 0:
		# Pick the best strike response
		var best = strike_choices[0]
		var best_score = _score_strike(best, ai_game_state)
		for action in strike_choices:
			var s = _score_strike(action, ai_game_state)
			if s > best_score:
				best_score = s
				best = action
		return best

	if wild_action:
		return wild_action

	return possible_actions[randi() % possible_actions.size()]


func pick_discard_to_max(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	if possible_actions.size() == 1:
		return possible_actions[0]

	# Discard the lowest-value cards
	var best_action = possible_actions[0]
	var best_cost = 9999.0
	for action in possible_actions:
		var cost: float = 0.0
		for card_id in action.card_ids:
			cost += evaluate_card_value(card_id, ai_game_state)
		if cost < best_cost:
			best_cost = cost
			best_action = action
	return best_action


func pick_cancel(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	if possible_actions.size() == 1:
		return possible_actions[0]

	# Decide whether to cancel based on:
	# 1. Is the effect worth canceling? (hard to determine generically)
	# 2. Can we afford the gauge cost?
	# Default: cancel if gauge is plentiful and we don't spend our best cards
	var cancel_actions = []
	var no_cancel = null
	for action in possible_actions:
		if action.cancel:
			cancel_actions.append(action)
		else:
			no_cancel = action

	# If gauge is plentiful (> 3), cancel with lowest value cards
	if ai_game_state.my_state.gauge.size() > 3 and cancel_actions.size() > 0:
		var best_cancel = cancel_actions[0]
		var best_cost = 9999.0
		for action in cancel_actions:
			var cost: float = 0.0
			for card_id in action.card_ids:
				cost += evaluate_card_value(card_id, ai_game_state)
			if cost < best_cost:
				best_cost = cost
				best_cancel = action
		return best_cancel

	# Otherwise don't cancel
	if no_cancel:
		return no_cancel
	return possible_actions[0]


func pick_discard_continuous(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	if possible_actions.size() == 1:
		return possible_actions[0]

	# Prefer discarding opponent's boosts over our own
	var opponent_boosts = []
	var our_boosts = []
	var pass_action = null
	for action in possible_actions:
		if action is AIPlayer.DiscardContinuousBoostAction:
			if action.card_id == -1:
				pass_action = action
			elif not action.mine:
				opponent_boosts.append(action)
			else:
				our_boosts.append(action)

	# Discard opponent's boost if possible — pick the one on the best card
	if opponent_boosts.size() > 0:
		var best = opponent_boosts[0]
		var best_score = -9999.0
		for action in opponent_boosts:
			var card = ai_game_state.card_db.get_card(action.card_id)
			var score = 0.0
			if card and card.definition:
				score += card.definition.get('damage', 0) * 3.0
				if card.definition.get('type', '') == 'ultra':
					score += 10.0
			if score > best_score:
				best_score = score
				best = action
		return best

	# Otherwise discard our lowest-value boost
	if our_boosts.size() > 0:
		var best = our_boosts[0]
		var best_cost = 9999.0
		for action in our_boosts:
			var cost = evaluate_card_value(action.card_id, ai_game_state)
			if cost < best_cost:
				best_cost = cost
				best = action
		return best

	if pass_action:
		return pass_action
	return possible_actions[randi() % possible_actions.size()]


func pick_discard_opponent_gauge(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	if possible_actions.size() == 1:
		return possible_actions[0]

	# Discard opponent's most valuable gauge card
	var best_action = possible_actions[0]
	var best_score = -9999.0
	for action in possible_actions:
		if action is AIPlayer.DiscardGaugeAction:
			var score = evaluate_card_value(action.card_id, ai_game_state)
			if score > best_score:
				best_score = score
				best_action = action
	return best_action


func pick_name_opponent_card(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	if possible_actions.size() == 1:
		return possible_actions[0]

	# Name a card that would be impactful — prefer ultras and specials
	var ultras = []
	var specials = []
	var normals = []
	for action in possible_actions:
		if action is AIPlayer.NameCardAction:
			var card = ai_game_state.card_db.get_card(action.card_id)
			if card and card.definition:
				match card.definition.get('type', ''):
					'ultra': ultras.append(action)
					'special': specials.append(action)
					_: normals.append(action)

	if ultras.size() > 0:
		return ultras[randi() % ultras.size()]
	if specials.size() > 0:
		return specials[randi() % specials.size()]
	if normals.size() > 0:
		return normals[randi() % normals.size()]
	return possible_actions[randi() % possible_actions.size()]


func pick_card_hand_to_gauge(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	if possible_actions.size() == 1:
		return possible_actions[0]

	# Gauge the lowest-value cards from hand
	var best_action = possible_actions[0]
	var best_cost = 9999.0
	for action in possible_actions:
		var cost: float = 0.0
		for card_id in action.card_ids:
			cost += evaluate_card_value(card_id, ai_game_state)
		if cost < best_cost:
			best_cost = cost
			best_action = action
	return best_action


func pick_mulligan(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	if possible_actions.size() == 1:
		return possible_actions[0]

	# Strategy: keep cards that can hit, ultras, specials, high guard.
	# Mulligan low-value normals that don't hit.
	var best_action = possible_actions[0]  # Default: mulligan nothing (keep all)
	var best_score = -9999.0

	for action in possible_actions:
		# Cards NOT in action.card_ids are kept
		var keep_ids = []
		for card_id in ai_game_state.my_state.hand:
			if card_id not in action.card_ids:
				keep_ids.append(card_id)

		# Score the kept hand
		var score: float = 0.0
		for card_id in keep_ids:
			var card = ai_game_state.card_db.get_card(card_id)
			if not card or not card.definition:
				continue

			# Hitting is most important
			if can_card_hit(card_id, -1, ai_game_state):
				score += card.definition.get('damage', 0) * 3.0
				score += 10.0  # Base bonus for being hittable

			# Type bonuses
			match card.definition.get('type', ''):
				'ultra': score += 15.0
				'special': score += 8.0
				_: score += 0.0

			# Guard value
			score += card.definition.get('guard', 0) * 2.0

			# Gauge cost penalty (expensive cards are less flexible early)
			score -= card.definition.get('gauge_cost', 0) * 1.5

		if score > best_score:
			best_score = score
			best_action = action

	return best_action


func pick_choose_from_boosts(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	if possible_actions.size() == 1:
		return possible_actions[0]

	# Choose boosts with the best effects to keep
	var best_action = possible_actions[0]
	var best_score = -9999.0
	for action in possible_actions:
		var score: float = 0.0
		for card_id in action.card_ids:
			score += evaluate_card_value(card_id, ai_game_state)
		if score > best_score:
			best_score = score
			best_action = action
	return best_action


func pick_choose_from_discard(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	if possible_actions.size() == 1:
		return possible_actions[0]

	# Pick the highest-value cards from discard
	var best_action = possible_actions[0]
	var best_score = -9999.0
	for action in possible_actions:
		var score: float = 0.0
		for card_id in action.card_ids:
			score += evaluate_card_value(card_id, ai_game_state)
		if score > best_score:
			best_score = score
			best_action = action
	return best_action


func pick_force_for_effect(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	if possible_actions.size() == 1:
		return possible_actions[0]

	# Spend the lowest-value cards for the effect
	var best_action = possible_actions[0]
	var best_cost = 9999.0
	for action in possible_actions:
		var cost: float = 0.0
		for card_id in action.card_ids:
			cost += evaluate_card_value(card_id, ai_game_state)
		if action.use_free_force:
			cost -= 3.0
		if cost < best_cost:
			best_cost = cost
			best_action = action
	return best_action


func pick_gauge_for_effect(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	if possible_actions.size() == 1:
		return possible_actions[0]

	# Spend the lowest-value gauge cards
	var best_action = possible_actions[0]
	var best_cost = 9999.0
	for action in possible_actions:
		var cost: float = 0.0
		for card_id in action.card_ids:
			cost += evaluate_card_value(card_id, ai_game_state)
		if cost < best_cost:
			best_cost = cost
			best_action = action
	return best_action


func pick_choose_to_discard(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	if possible_actions.size() == 1:
		return possible_actions[0]

	# Discard the lowest-value cards
	var best_action = possible_actions[0]
	var best_cost = 9999.0
	for action in possible_actions:
		var cost: float = 0.0
		for card_id in action.card_ids:
			cost += evaluate_card_value(card_id, ai_game_state)
		if cost < best_cost:
			best_cost = cost
			best_action = action
	return best_action


func pick_choose_opponent_card_to_discard(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	if possible_actions.size() == 1:
		return possible_actions[0]

	# Discard opponent's highest-value card
	var best_action = possible_actions[0]
	var best_score = -9999.0
	for action in possible_actions:
		if action is AIPlayer.ChooseToDiscardAction:
			var score: float = 0.0
			for card_id in action.card_ids:
				score += evaluate_card_value(card_id, ai_game_state)
			if score > best_score:
				best_score = score
				best_action = action
	return best_action


func pick_choose_from_topdeck(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	if possible_actions.size() == 1:
		return possible_actions[0]

	# Group actions by the action type
	var pass_action = null
	var action_groups = {}
	for action in possible_actions:
		if action is AIPlayer.ChooseFromTopdeckAction:
			if action.action == "pass":
				pass_action = action
				continue
			if action.action not in action_groups:
				action_groups[action.action] = []
			action_groups[action.action].append(action)

	# For each action type, pick based on card value
	# Generally: keep high-value cards on top (draw), bottom low-value ones
	var best_action = possible_actions[0]
	var best_score = -9999.0

	for action in possible_actions:
		if action is AIPlayer.ChooseFromTopdeckAction:
			if action.action == "pass":
				continue  # Only pass if nothing else makes sense

			var score = evaluate_card_value(action.card_id, ai_game_state)

			# Adjust based on what we're doing with the card
			match action.action:
				"draw", "keep", "hand":
					score += 5.0  # Good cards to hand
				"discard", "bottom", "bottomdeck":
					score = -score  # Want to bottom/discard BAD cards
				"gauge":
					score = -score  # Want to gauge LOW value cards
				"play", "strike":
					score += 10.0
				"seal":
					score += 3.0
				_:
					score += 0.0

			if score > best_score:
				best_score = score
				best_action = action

	if pass_action and best_score < 0.0:
		return pass_action

	return best_action


func pick_choose_arena_location_for_effect(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	if possible_actions.size() == 1:
		return possible_actions[0]

	# Avoid pass (location 0) if there are other options
	var non_pass = []
	var pass_action = null
	for action in possible_actions:
		if action.location == 0:
			pass_action = action
		else:
			non_pass.append(action)

	if non_pass.size() == 0:
		return pass_action if pass_action else possible_actions[0]

	# Score each location by position quality
	var best_action = non_pass[0]
	var best_score = -9999.0
	for action in non_pass:
		var score = evaluate_position(action.location, ai_game_state.opponent_state.arena_location,
			ai_game_state.my_state.hand, ai_game_state)
		if score > best_score:
			best_score = score
			best_action = action
	return best_action


func pick_number_from_range_for_effect(possible_actions: Array, _ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	if possible_actions.size() == 1:
		return possible_actions[0]

	# Usually higher numbers are better (more damage, more cards drawn, etc.)
	# Pick the highest available ~70% of the time, random otherwise
	if randi() % 10 < 7:
		var max_action = possible_actions[0]
		for action in possible_actions:
			if action.number > max_action.number:
				max_action = action
		return max_action
	return possible_actions[randi() % possible_actions.size()]


# Stub — can be expanded for more sophisticated hand analysis.
func get_hand_card_probabilities():
	pass


# Stub — can be expanded for matchup-specific knowledge.
func evaluate_card_matchup(_card1, _card2):
	pass