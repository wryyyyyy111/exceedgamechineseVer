class_name AILearner
extends RefCounted

## Neural network learner for Exceed AI.
## 256-dim input → 128 → 64 → 32 → 12 → 1 (score adjustment)
## ~43K parameters, online SGD training with epsilon-greedy exploration.

const INPUT_DIM := 256
const LAYER_SIZES := [128, 64, 32, 12, 1]
const OUTPUT_RANGE := 5.0
const HISTORY_LENGTH := 5

# Network parameters
var _weights: Array = []      # [W0, W1, W2, W3, W4]  each is 2D array [rows][cols]
var _biases: Array = []       # [b0, b1, b2, b3, b4]  each is 1D array

# Cached forward-pass values for backprop
var _layer_inputs: Array = []   # pre-activation values per layer
var _layer_outputs: Array = []  # post-activation values per layer (layer_outputs[-1] = input)

# Training hyperparameters
var _lr: float = 0.005
var _momentum: float = 0.9
var _velocity_weights: Array = []  # momentum buffers
var _velocity_biases: Array = []

# Epsilon-greedy
var _epsilon: float = 0.10
var _epsilon_min: float = 0.02
var _epsilon_decay: float = 0.9995

# State tracking for training
var _train_count: int = 0
#todo var _explore_count: int = 0
var _total_reward: float = 0.0
var _running_loss: float = 0.0

# Turn history for feature extraction
var _turn_history: Array = []  # Array[Dictionary] with last HISTORY_LENGTH turns
#todo var _last_snapshot: Dictionary = {}  # snapshot before last decision
var _last_features: Array = []       # features from last forward pass
var _last_prediction: float = 0.0    # last prediction value

# Player assignment
#todo var _player_id: int = -1

# RNG
var _rng: RandomNumberGenerator = null


# ============================================================
# Initialization
# ============================================================

func _init() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.randomize()
	_init_network()
	print("[AILearner] Initialized: %d parameters, epsilon=%.2f, lr=%.4f" % [
		_get_parameter_count(), _epsilon, _lr])


func _init_network() -> void:
	_weights.clear()
	_biases.clear()
	_velocity_weights.clear()
	_velocity_biases.clear()

	var layer_dims: Array = [INPUT_DIM]
	for s in LAYER_SIZES: layer_dims.append(s)

	for l in range(layer_dims.size() - 1):
		var fan_in: int = layer_dims[l]
		var fan_out: int = layer_dims[l + 1]
		# Xavier initialization
		var limit: float = sqrt(6.0 / (fan_in + fan_out))

		var w: Array = []
		w.resize(fan_out)
		for i in range(fan_out):
			var row: Array = []
			row.resize(fan_in)
			for j in range(fan_in):
				row[j] = _rng.randf_range(-limit, limit)
			w[i] = row
		_weights.append(w)

		var b: Array = []
		b.resize(fan_out)
		for i in range(fan_out):
			b[i] = 0.0
		_biases.append(b)

		# Momentum buffers (same shape, initialized to 0)
		var vw: Array = []
		vw.resize(fan_out)
		for i in range(fan_out):
			var vrow: Array = []
			vrow.resize(fan_in)
			for j in range(fan_in):
				vrow[j] = 0.0
			vw[i] = vrow
		_velocity_weights.append(vw)

		var vb: Array = []
		vb.resize(fan_out)
		for i in range(fan_out):
			vb[i] = 0.0
		_velocity_biases.append(vb)


# ============================================================
# Matrix operations
# ============================================================

func _mat_vec_mul(matrix: Array, vector: Array) -> Array:
	# matrix: [rows][cols], vector: [cols] → result: [rows]
	var rows: int = matrix.size()
	var result: Array = []
	result.resize(rows)
	for i in range(rows):
		var row = matrix[i]
		var sum: float = 0.0
		var cols: int = row.size()
		for j in range(cols):
			sum += row[j] * vector[j]
		result[i] = sum
	return result


func _vec_add(a: Array, b: Array) -> Array:
	var n: int = a.size()
	var result: Array = []
	result.resize(n)
	for i in range(n):
		result[i] = a[i] + b[i]
	return result


func _vec_sub(a: Array, b: Array) -> Array:
	var n: int = a.size()
	var result: Array = []
	result.resize(n)
	for i in range(n):
		result[i] = a[i] - b[i]
	return result


func _vec_mul_scalar(vec: Array, scalar: float) -> Array:
	var n: int = vec.size()
	var result: Array = []
	result.resize(n)
	for i in range(n):
		result[i] = vec[i] * scalar
	return result


func _vec_scale_add(target: Array, vec: Array, scalar: float) -> void:
	for i in range(target.size()):
		target[i] += vec[i] * scalar


func _outer_product(a: Array, b: Array) -> Array:
	# a: [m], b: [n] → result: [m][n], result[i][j] = a[i] * b[j]
	var m: int = a.size()
	var n: int = b.size()
	var result: Array = []
	result.resize(m)
	for i in range(m):
		var row: Array = []
		row.resize(n)
		var ai: float = a[i]
		for j in range(n):
			row[j] = ai * b[j]
		result[i] = row
	return result


func _relu(x: float) -> float:
	return x if x > 0.0 else 0.0


func _relu_derivative(x: float) -> float:
	return 1.0 if x > 0.0 else 0.0


# ============================================================
# Forward pass
# ============================================================

func forward(features: Array) -> float:
	## Returns a score adjustment in [-OUTPUT_RANGE, OUTPUT_RANGE]
	if features.size() != INPUT_DIM:
		push_error("[AILearner] forward: expected %d features, got %d" % [INPUT_DIM, features.size()])
		return 0.0

	_layer_inputs.clear()
	_layer_outputs.clear()

	var current: Array = features.duplicate()
	_layer_outputs.append(current)  # layer_outputs[0] = input

	var num_layers: int = _weights.size()

	for l in range(num_layers):
		var z: Array = _vec_add(_mat_vec_mul(_weights[l], current), _biases[l])
		_layer_inputs.append(z)

		if l < num_layers - 1:
			# Hidden layer: apply ReLU
			var a: Array = []
			a.resize(z.size())
			for i in range(z.size()):
				a[i] = _relu(z[i])
			current = a
		else:
			# Output layer: no activation (raw score adjustment)
			current = z
		_layer_outputs.append(current)

	# Store features for apply_reward (so backward() can train on this decision)
	_last_features = features.duplicate()

	# Output is a single scalar, clip to range
	var raw: float = current[0]
	return clamp(raw, -OUTPUT_RANGE, OUTPUT_RANGE)


# ============================================================
# Backward pass (SGD with momentum)
# ============================================================

func backward(reward: float) -> float:
	## Perform one SGD step. reward = target value for the last forward pass.
	## Returns the loss value.
	if _layer_inputs.size() == 0:
		return 0.0

	var num_layers: int = _weights.size()

	# Compute loss gradient w.r.t. output
	# MSE: loss = 0.5 * (prediction - reward)^2
	# dL/dpred = prediction - reward
	var prediction: float = _layer_outputs[num_layers][0]
	var loss: float = 0.5 * (prediction - reward) * (prediction - reward)

	# Gradient w.r.t. output layer (size 1)
	var delta: Array = [(prediction - reward)]  # dL/dz for output layer

	# Backprop through layers
	for l in range(num_layers - 1, -1, -1):
		var layer_input: Array = _layer_outputs[l]  # input to this layer
		var _layer_z: Array = _layer_inputs[l]         # pre-activation
		var w: Array = _weights[l]

		# Gradient w.r.t. weights: dL/dW = delta ⊗ layer_input^T
		var dW: Array = _outer_product(delta, layer_input)

		# Gradient w.r.t. biases: dL/db = delta
		var dB: Array = delta.duplicate()

		# Update weights with momentum
		var vw: Array = _velocity_weights[l]
		for i in range(dW.size()):
			var vrow = vw[i]
			var dw_row = dW[i]
			var wrow = w[i]
			for j in range(dw_row.size()):
				vrow[j] = _momentum * vrow[j] - _lr * dw_row[j]
				wrow[j] += vrow[j]

		# Update biases with momentum
		var vb: Array = _velocity_biases[l]
		var b: Array = _biases[l]
		for i in range(dB.size()):
			vb[i] = _momentum * vb[i] - _lr * dB[i]
			b[i] += vb[i]

		# Propagate delta to previous layer (if not first layer)
		if l > 0:
			# delta_prev = W^T @ delta ⊙ ReLU'(z_prev)
			# z_prev = _layer_inputs[l-1]
			var prev_z: Array = _layer_inputs[l - 1]
			var new_delta: Array = []
			new_delta.resize(prev_z.size())

			# Compute W^T @ delta
			for j in range(prev_z.size()):
				var s: float = 0.0
				for i in range(delta.size()):
					s += w[i][j] * delta[i]
				new_delta[j] = s * _relu_derivative(prev_z[j])

			delta = new_delta

	_running_loss = _running_loss * 0.9 + loss * 0.1
	_train_count += 1
	return loss


# ============================================================
# Decision interface
# ============================================================

func should_explore() -> bool:
	return _rng.randf() < _epsilon


func record_decision(features: Array, prediction: float) -> void:
	_last_features = features.duplicate()
	_last_prediction = prediction


func apply_reward(reward: float) -> float:
	## Apply reward signal to train the network. Returns loss.
	if _last_features.size() == 0:
		return 0.0
	# Forward pass to set up cached values, then backward
	forward(_last_features)
	var loss: float = backward(reward)
	# Decay epsilon
	_epsilon = max(_epsilon_min, _epsilon * _epsilon_decay)
	_total_reward += reward
	return loss


func snapshot_state(state) -> Dictionary:
	## Create a compact snapshot of game state for reward computation.
	var my = state.my_state
	var opp = state.opponent_state
	return {
		"my_hp": my.life,
		"opp_hp": opp.life,
		"my_hand": my.hand.size(),
		"opp_hand": opp.hand.size(),
		"my_gauge": my.gauge.size(),
		"opp_gauge": opp.gauge.size(),
		"my_location": my.arena_location,
		"opp_location": opp.arena_location,
		"distance": abs(my.arena_location - opp.arena_location),
	}


func compute_reward(prev_snapshot: Dictionary, current_state) -> float:
	## Compute reward: Δhp_diff * 2.0 + Δhand_diff * 0.5 + Δgauge_diff * 0.5
	if prev_snapshot.is_empty():
		return 0.0

	var my = current_state.my_state
	var opp = current_state.opponent_state

	# Previous values
	var prev_my_hp: int = prev_snapshot.get("my_hp", my.life)
	var prev_opp_hp: int = prev_snapshot.get("opp_hp", opp.life)
	var prev_my_hand: int = prev_snapshot.get("my_hand", my.hand.size())
	var prev_opp_hand: int = prev_snapshot.get("opp_hand", opp.hand.size())
	var prev_my_gauge: int = prev_snapshot.get("my_gauge", my.gauge.size())
	var prev_opp_gauge: int = prev_snapshot.get("opp_gauge", opp.gauge.size())

	# HP diff: higher is better for AI
	var hp_diff_before: int = prev_my_hp - prev_opp_hp
	var hp_diff_after: int = my.life - opp.life
	var delta_hp_diff: int = hp_diff_after - hp_diff_before

	# Hand diff
	var hand_diff_before: int = prev_my_hand - prev_opp_hand
	var hand_diff_after: int = my.hand.size() - opp.hand.size()
	var delta_hand_diff: int = hand_diff_after - hand_diff_before

	# Gauge diff
	var gauge_diff_before: int = prev_my_gauge - prev_opp_gauge
	var gauge_diff_after: int = my.gauge.size() - opp.gauge.size()
	var delta_gauge_diff: int = gauge_diff_after - gauge_diff_before

	var reward: float = delta_hp_diff * 2.0 + delta_hand_diff * 0.5 + delta_gauge_diff * 0.5
	return reward


# ============================================================
# Feature extraction (256 dimensions)
# ============================================================

func extract_features(state, is_response: bool = false) -> Array:
	## Convert AIGameState to a 256-dim float feature vector.
	var feats: Array = []
	feats.resize(INPUT_DIM)
	for k in range(INPUT_DIM):
		feats[k] = 0.0

	var my = state.my_state
	var opp = state.opponent_state
	var distance: int = abs(my.arena_location - opp.arena_location)
	var idx: int = 0

	# ── Group 0-9: My State (10 dims) ──
	feats[idx] = clamp(float(my.life) / 30.0, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(my.hand.size()) / 7.0, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(my.gauge.size()) / 10.0, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(my.continuous_boosts.size()) / 3.0, 0.0, 1.0); idx += 1
	feats[idx] = 1.0 if my.exceeded else 0.0; idx += 1
	feats[idx] = clamp(float(my.arena_location) / 9.0, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(my.deck_list.size()) / 30.0, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(my.discards.size()) / 20.0, 0.0, 1.0); idx += 1
	feats[idx] = 1.0 if my.reshuffle_remaining > 0 else 0.0; idx += 1
	feats[idx] = 0.0; idx += 1  # sealed not exposed in AIPlayerState

	# ── Group 10-19: Opponent State (10 dims) ──
	feats[idx] = clamp(float(opp.life) / 30.0, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(opp.hand.size()) / 7.0, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(opp.gauge.size()) / 10.0, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(opp.continuous_boosts.size()) / 3.0, 0.0, 1.0); idx += 1
	feats[idx] = 1.0 if opp.exceeded else 0.0; idx += 1
	feats[idx] = clamp(float(opp.arena_location) / 9.0, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(opp.deck_list.size()) / 30.0, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(opp.discards.size()) / 20.0, 0.0, 1.0); idx += 1
	feats[idx] = 1.0 if opp.reshuffle_remaining > 0 else 0.0; idx += 1
	feats[idx] = 0.0; idx += 1  # sealed not exposed in AIPlayerState

	# ── Group 20-25: Deltas (6 dims) ──
	feats[idx] = clamp(float(my.life - opp.life) / 30.0 + 0.5, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(my.hand.size() - opp.hand.size()) / 7.0 + 0.5, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(my.gauge.size() - opp.gauge.size()) / 10.0 + 0.5, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(my.arena_location - opp.arena_location) / 8.0 + 0.5, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(my.continuous_boosts.size() - opp.continuous_boosts.size()) / 3.0 + 0.5, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(my.deck_list.size() - opp.deck_list.size()) / 30.0 + 0.5, 0.0, 1.0); idx += 1

	# ── Group 26-37: Distance & Range (12 dims) ──
	for d in range(1, 10):
		feats[idx] = 1.0 if distance == d else 0.0; idx += 1
	feats[idx] = clamp(float(distance) / 9.0, 0.0, 1.0); idx += 1
	feats[idx] = 1.0 if distance <= 2 else (0.0 if distance >= 6 else 0.5); idx += 1
	# Count cards in hand that can hit at current distance
	var cards_in_range: int = 0
	for cid in my.hand:
		if _can_card_hit_simple(cid, state, is_response):
			cards_in_range += 1
	feats[idx] = clamp(float(cards_in_range) / 7.0, 0.0, 1.0); idx += 1

	# ── Group 38-49: Best Strike Quality (12 dims) ──
	var best_speed: int = 0
	var best_power: int = 0
	var best_armor: int = 0
	var best_guard: int = 0
	var best_is_ex: float = 0.0
	var best_can_kill: float = 0.0
	var best_has_ignore: float = 0.0
	var num_viable: int = 0
	for cid in my.hand:
		if _can_card_hit_simple(cid, state, is_response):
			if _is_block_card_simple(cid, state): continue
			num_viable += 1
			var spd: int = _get_card_speed_simple(cid, state, is_response)
			var pwr: int = _get_card_power_simple(cid, state)
			if spd > best_speed: best_speed = spd
			if pwr > best_power: best_power = pwr
			if _get_card_armor_simple(cid, state) > best_armor: best_armor = _get_card_armor_simple(cid, state)
			if _get_card_guard_simple(cid, state) > best_guard: best_guard = _get_card_guard_simple(cid, state)
			if pwr >= opp.life: best_can_kill = 1.0
			for ef in (_get_card_def(cid, state) if _get_card_def(cid, state) else {}).get("effects", []):
				if ef.get("effect_type") == "ignore_armor": best_has_ignore = 1.0; break
	feats[idx] = clamp(float(best_speed) / 10.0, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(best_power) / 10.0, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(best_armor) / 5.0, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(best_guard) / 8.0, 0.0, 1.0); idx += 1
	feats[idx] = best_is_ex; idx += 1
	feats[idx] = best_can_kill; idx += 1
	feats[idx] = best_has_ignore; idx += 1
	feats[idx] = clamp(float(num_viable) / 7.0, 0.0, 1.0); idx += 1
	# Speed vs curve
	var curve_speed: int = _get_curve_speed(distance)
	feats[idx] = clamp(float(best_speed - curve_speed) / 4.0 + 0.5, 0.0, 1.0); idx += 1
	# Opponent max speed estimate
	var opp_max_speed: int = _estimate_opp_max_speed(distance, state)
	feats[idx] = clamp(float(opp_max_speed) / 10.0, 0.0, 1.0); idx += 1
	# Speed advantage
	feats[idx] = clamp(float(best_speed - opp_max_speed) / 4.0 + 0.5, 0.0, 1.0); idx += 1

	# ── Group 50-57: Threat Assessment (8 dims) ──
	feats[idx] = clamp(float(opp_max_speed) / 10.0, 0.0, 1.0); idx += 1
	var opp_max_power: int = _estimate_opp_max_power(distance, state)
	feats[idx] = clamp(float(opp_max_power) / 10.0, 0.0, 1.0); idx += 1
	# Can opponent kill me?
	var opp_can_kill: float = 0.0
	for cid in opp.deck_list:
		var p = cid.definition.get("power", 0)
		if p is String: p = 0
		var rmin = cid.definition.get("range_min", 1)
		if rmin is String: rmin = 1
		var rmax = cid.definition.get("range_max", rmin + 3)
		if rmax is String: rmax = rmin + 3
		if rmin <= distance and distance <= rmax and p >= my.life:
			opp_can_kill = 1.0; break
	feats[idx] = opp_can_kill; idx += 1
	feats[idx] = best_can_kill; idx += 1
	# Remaining specials/ultras
	var opp_specials: int = _count_type_in_deck(opp, "special")
	var opp_ultras: int = _count_type_in_deck(opp, "ultra")
	feats[idx] = clamp(float(opp_specials) / 8.0, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(opp_ultras) / 4.0, 0.0, 1.0); idx += 1
	# Known hand (cards opponent revealed or we've seen)
	feats[idx] = clamp(float(_count_known_opp_hand(state)) / 7.0, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(opp.discards.size()) / 20.0, 0.0, 1.0); idx += 1

	# ── Group 58-63: Game Phase & Context (6 dims) ──
	var deck_remaining: int = my.deck_list.size()
	feats[idx] = 1.0 if deck_remaining > 20 else 0.0; idx += 1  # early
	feats[idx] = 1.0 if deck_remaining >= 10 and deck_remaining <= 20 else 0.0; idx += 1  # mid
	feats[idx] = 1.0 if deck_remaining < 10 else 0.0; idx += 1  # late
	feats[idx] = 1.0 if not is_response else 0.0; idx += 1  # is_initiator
	feats[idx] = 1.0 if is_response else 0.0; idx += 1  # is_responder
	feats[idx] = clamp(float(state.active_turn_player) / 2.0, 0.0, 1.0); idx += 1

	# ── Group 64-69: Boost Status (6 dims) ──
	var has_power: float = 0.0; var has_speed: float = 0.0
	var has_armor: float = 0.0; var has_guard: float = 0.0
	var has_crit: float = 0.0; var has_ignore_armor: float = 0.0
	for bid in my.continuous_boosts:
		var bdef = _get_card_def(bid, state)
		if bdef == null: continue
		bdef = bdef.get("boost", {})
		for bef in bdef.get("effects", []):
			var et = bef.get("effect_type", "")
			if et == "powerup": has_power = 1.0
			elif et == "speedup" or et == "attack_is_ex": has_speed = 1.0
			elif et == "armorup": has_armor = 1.0
			elif et == "guardup": has_guard = 1.0
			elif et == "critical": has_crit = 1.0
			elif et == "ignore_armor": has_ignore_armor = 1.0
	feats[idx] = has_power; idx += 1
	feats[idx] = has_speed; idx += 1
	feats[idx] = has_armor; idx += 1
	feats[idx] = has_guard; idx += 1
	feats[idx] = has_crit; idx += 1
	feats[idx] = has_ignore_armor; idx += 1

	# ── Group 70-79: Character Info (10 dims) ──
	var my_class: String = _classify_character_simple(my, state)
	feats[idx] = 1.0 if my_class == "melee" else 0.0; idx += 1
	feats[idx] = 1.0 if my_class == "ranged" else 0.0; idx += 1
	feats[idx] = 1.0 if my_class == "midrange" else 0.0; idx += 1
	var opp_class: String = _classify_character_simple(opp, state)
	feats[idx] = 1.0 if opp_class == "melee" else 0.0; idx += 1
	feats[idx] = 1.0 if opp_class == "ranged" else 0.0; idx += 1
	feats[idx] = 1.0 if opp_class == "midrange" else 0.0; idx += 1
	var season: int = my.deck_def.get("season", 0)
	feats[idx] = clamp(float(season) / 7.0, 0.0, 1.0); idx += 1
	feats[idx] = 1.0 if _has_critical_ability(my, state) else 0.0; idx += 1
	feats[idx] = 1.0 if _has_transform_ability(my, state) else 0.0; idx += 1
	# Ideal distance
	feats[idx] = clamp(float(_get_ideal_distance_simple(my_class, opp_class)) / 9.0, 0.0, 1.0); idx += 1

	# ── Group 80-95: Hand Composition (16 dims) ──
	var normal_counts: Dictionary = {}
	for cid in my.hand:
		var card_def = _get_card_def(cid, state)
		var ctype = card_def.get("type", "")
		if ctype == "normal":
			var cid_str = card_def.get("id", "")
			normal_counts[cid_str] = normal_counts.get(cid_str, 0) + 1
		elif ctype == "special":
			normal_counts["_special"] = normal_counts.get("_special", 0) + 1
		elif ctype == "ultra":
			normal_counts["_ultra"] = normal_counts.get("_ultra", 0) + 1
		if _is_block_card_simple(cid, state):
			normal_counts["_block"] = normal_counts.get("_block", 0) + 1

	var normal_names := ["gg_normal_grasp", "gg_normal_cross", "gg_normal_slash",
		"gg_normal_dive", "gg_normal_dust", "gg_normal_sweep",
		"gg_normal_focus", "gg_normal_block",
		"uni_normal_grasp", "uni_normal_cross", "uni_normal_slash",
		"uni_normal_dive", "uni_normal_dust", "uni_normal_sweep",
		"uni_normal_focus", "uni_normal_block"]
	for name in normal_names:
		feats[idx] = clamp(float(normal_counts.get(name, 0)) / 2.0, 0.0, 1.0); idx += 1

	# ── Group 96-99: Hand Composition Extended (4 dims) ──
	feats[idx] = clamp(float(normal_counts.get("_special", 0)) / 4.0, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(normal_counts.get("_ultra", 0)) / 2.0, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(normal_counts.get("_block", 0)) / 2.0, 0.0, 1.0); idx += 1
	# EX potential: count of cards with same-name pairs in hand
	var ex_possible: int = _count_ex_possible(my, state)
	feats[idx] = clamp(float(ex_possible) / 3.0, 0.0, 1.0); idx += 1

	# ── Group 100-159: Turn History (5 turns × 12 = 60 dims) ──
	for t in range(HISTORY_LENGTH):
		if t < _turn_history.size():
			var th = _turn_history[t]
			# action_type one-hot (6 dims)
			var at: String = th.get("action_type", "other")
			feats[idx] = 1.0 if at == "strike" else 0.0; idx += 1
			feats[idx] = 1.0 if at == "boost" else 0.0; idx += 1
			feats[idx] = 1.0 if at == "prepare" else 0.0; idx += 1
			feats[idx] = 1.0 if at == "move" else 0.0; idx += 1
			feats[idx] = 1.0 if at == "exceed" else 0.0; idx += 1
			feats[idx] = 1.0 if at == "other" else 0.0; idx += 1
			# Numeric values
			feats[idx] = clamp(float(th.get("damage_dealt", 0)) / 15.0, 0.0, 1.0); idx += 1
			feats[idx] = clamp(float(th.get("damage_taken", 0)) / 15.0, 0.0, 1.0); idx += 1
			feats[idx] = clamp(float(th.get("distance_change", 0)) / 4.0 + 0.5, 0.0, 1.0); idx += 1
			feats[idx] = clamp(float(th.get("hp_change", 0)) / 15.0 + 0.5, 0.0, 1.0); idx += 1
			feats[idx] = clamp(float(th.get("hand_change", 0)) / 3.0 + 0.5, 0.0, 1.0); idx += 1
			feats[idx] = 1.0 if th.get("hit_landed", false) else 0.0; idx += 1
		else:
			for k in range(12):
				feats[idx] = 0.0; idx += 1

	# ── Group 160-169: Combo & Synergy (10 dims) ──
	# Best boost score among available boosts
	var best_boost_score: float = 0.0
	for cid in my.hand:
		var bdef = (_get_card_def(cid, state) if _get_card_def(cid, state) else {}).get("boost", {})
		if bdef.is_empty(): continue
		var bs: float = _score_boost_simple(cid, state)
		if bs > best_boost_score: best_boost_score = bs
	feats[idx] = clamp(best_boost_score / 50.0, 0.0, 1.0); idx += 1
	# Cancel available
	var can_cancel: float = 1.0 if (my.gauge.size() >= 1 and best_speed >= 6) else 0.0
	feats[idx] = can_cancel; idx += 1
	# Gauge available for critical
	var gauge_for_crit: float = 1.0 if (my.gauge.size() >= 1 and _has_critical_ability(my, state)) else 0.0
	feats[idx] = gauge_for_crit; idx += 1
	# Boost saturation
	feats[idx] = clamp(float(my.continuous_boosts.size()) / 3.0, 0.0, 1.0); idx += 1
	# Hand size trend over history
	if _turn_history.size() >= 2:
		var prev_size: int = _turn_history[0].get("my_hand_size", my.hand.size())
		feats[idx] = clamp(float(my.hand.size() - prev_size) / 3.0 + 0.5, 0.0, 1.0)
	idx += 1
	# HP trend
	if _turn_history.size() >= 2:
		var prev_hp: int = _turn_history[0].get("my_hp", my.life)
		feats[idx] = clamp(float(my.life - prev_hp) / 10.0 + 0.5, 0.0, 1.0)
	idx += 1
	# Distance trend
	if _turn_history.size() >= 2:
		var prev_dist: int = _turn_history[0].get("distance", distance)
		feats[idx] = clamp(float(distance - prev_dist) / 4.0 + 0.5, 0.0, 1.0)
	idx += 1
	# Has reshuffle remaining
	feats[idx] = 1.0 if my.reshuffle_remaining > 0 else 0.0; idx += 1
	# My turn number
	feats[idx] = clamp(float(_train_count % 30) / 30.0, 0.0, 1.0); idx += 1
	# Reserved
	feats[idx] = 0.0; idx += 1

	# ── Group 170-179: Opponent Behavior (10 dims) ──
	# Opponent action distribution from history
	var opp_strike_count: int = 0
	var opp_boost_count: int = 0
	var opp_prepare_count: int = 0
	for th in _turn_history:
		if th.get("actor", "") == "opponent":
			var at = th.get("action_type", "")
			if at == "strike": opp_strike_count += 1
			elif at == "boost": opp_boost_count += 1
			elif at == "prepare": opp_prepare_count += 1
	var hist_size: int = max(_turn_history.size(), 1)
	feats[idx] = clamp(float(opp_strike_count) / float(hist_size) * 3.0, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(opp_boost_count) / float(hist_size) * 3.0, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(opp_prepare_count) / float(hist_size) * 3.0, 0.0, 1.0); idx += 1
	# Opp likely actions
	feats[idx] = 0.0; idx += 1  # reserved
	feats[idx] = 0.0; idx += 1
	feats[idx] = 0.0; idx += 1
	feats[idx] = 0.0; idx += 1
	feats[idx] = 0.0; idx += 1
	feats[idx] = 0.0; idx += 1
	feats[idx] = 0.0; idx += 1

	# ── Group 180-199: Advanced Features (20 dims) ──
	# Life lead
	var life_lead: int = my.life - opp.life
	feats[idx] = 1.0 if life_lead > 0 else 0.0; idx += 1
	feats[idx] = clamp(float(life_lead) / 20.0 + 0.5, 0.0, 1.0); idx += 1
	# Stun threat (can I be stunned?)
	feats[idx] = 1.0 if best_guard < opp_max_power else 0.0; idx += 1
	feats[idx] = 1.0 if opp_max_power >= 8 else 0.0; idx += 1
	# Speed at curve
	var at_curve: float = 1.0 if best_speed == _get_curve_speed(distance) else 0.0
	feats[idx] = at_curve; idx += 1
	# Above curve
	feats[idx] = 1.0 if best_speed > _get_curve_speed(distance) else 0.0; idx += 1
	# Hand quality (avg speed of cards in hand)
	var avg_hand_speed: float = 0.0
	var hand_count_for_avg: int = 0
	for cid in my.hand:
		var spd = _get_card_speed_simple(cid, state, is_response)
		if spd > 0:
			avg_hand_speed += float(spd)
			hand_count_for_avg += 1
	if hand_count_for_avg > 0: avg_hand_speed /= float(hand_count_for_avg)
	feats[idx] = clamp(avg_hand_speed / 10.0, 0.0, 1.0); idx += 1
	# Cards with guard >= 4
	var high_guard_count: int = 0
	for cid in my.hand:
		if _get_card_guard_simple(cid, state) >= 4: high_guard_count += 1
	feats[idx] = clamp(float(high_guard_count) / 4.0, 0.0, 1.0); idx += 1
	# Cards with ignore_armor
	var ignore_count: int = 0
	for cid in my.hand:
		for ef in (_get_card_def(cid, state) if _get_card_def(cid, state) else {}).get("effects", []):
			if ef.get("effect_type") == "ignore_armor": ignore_count += 1; break
	feats[idx] = clamp(float(ignore_count) / 2.0, 0.0, 1.0); idx += 1
	# Distance to ideal
	var my_class2: String = _classify_character_simple(my, state)
	var opp_class2: String = _classify_character_simple(opp, state)
	var ideal_dist: int = _get_ideal_distance_simple(my_class2, opp_class2)
	feats[idx] = clamp(float(abs(distance - ideal_dist)) / 8.0, 0.0, 1.0); idx += 1
	# Cards that can reach ideal distance
	var ideal_range_cards: int = 0
	for cid in my.hand:
		var rmin = _get_card_range_min_simple(cid, state)
		var rmax = _get_card_range_max_simple(cid, state)
		if rmin <= ideal_dist and ideal_dist <= rmax: ideal_range_cards += 1
	feats[idx] = clamp(float(ideal_range_cards) / 7.0, 0.0, 1.0); idx += 1
	# Reserved slots
	for k in range(8):
		feats[idx] = 0.0; idx += 1

	# ── Group 200-219: Matchup Features (20 dims) ──
	# My special count
	var my_specials: int = _count_type_in_deck(my, "special")
	feats[idx] = clamp(float(my_specials) / 8.0, 0.0, 1.0); idx += 1
	var my_ultras: int = _count_type_in_deck(my, "ultra")
	feats[idx] = clamp(float(my_ultras) / 4.0, 0.0, 1.0); idx += 1
	# Opponent special/ultra in discard
	var opp_discard_specials: int = 0
	var opp_discard_ultras: int = 0
	for did in opp.discards:
		var ct = ""
		var cdef = _get_card_def(did, state)
		if cdef != null: ct = cdef.get("type", "")
		if ct == "special": opp_discard_specials += 1
		elif ct == "ultra": opp_discard_ultras += 1
	feats[idx] = clamp(float(opp_discard_specials) / 4.0, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(opp_discard_ultras) / 2.0, 0.0, 1.0); idx += 1
	# Reserved
	for k in range(16):
		feats[idx] = 0.0; idx += 1

	# ── Group 220-239: Positional Features (20 dims) ──
	# Arena position relative to edges
	feats[idx] = clamp(float(my.arena_location - 1) / 8.0, 0.0, 1.0); idx += 1  # distance from left edge
	feats[idx] = clamp(float(9 - my.arena_location) / 8.0, 0.0, 1.0); idx += 1  # distance from right edge
	feats[idx] = clamp(float(opp.arena_location - 1) / 8.0, 0.0, 1.0); idx += 1
	feats[idx] = clamp(float(9 - opp.arena_location) / 8.0, 0.0, 1.0); idx += 1
	# Who is on left?
	feats[idx] = 1.0 if my.arena_location < opp.arena_location else 0.0; idx += 1
	# Can be cornered?
	feats[idx] = 1.0 if (my.arena_location <= 2 or my.arena_location >= 8) else 0.0; idx += 1
	feats[idx] = 1.0 if (opp.arena_location <= 2 or opp.arena_location >= 8) else 0.0; idx += 1
	# Reserved
	for k in range(13):
		feats[idx] = 0.0; idx += 1

	# ── Group 240-255: Misc & Padding (16 dims) ──
	# Response-specific flags
	feats[idx] = 1.0 if is_response else 0.0; idx += 1
	# Active strike state (for response decisions)
	if state.active_strike != null:
		feats[idx] = 1.0; idx += 1  # there is an active strike
		var init_card = state.active_strike.initiator_card_id
		feats[idx] = clamp(float(_get_card_speed_simple(init_card, state, false)) / 10.0, 0.0, 1.0); idx += 1
		feats[idx] = clamp(float(_get_card_power_simple(init_card, state)) / 10.0, 0.0, 1.0); idx += 1
	else:
		for k in range(3): feats[idx] = 0.0; idx += 1
	# Padding
	for k in range(12):
		feats[idx] = 0.0; idx += 1

	return feats


# ============================================================
# History management
# ============================================================

func record_turn(turn_data: Dictionary) -> void:
	_turn_history.insert(0, turn_data)
	while _turn_history.size() > HISTORY_LENGTH:
		_turn_history.pop_back()


# ============================================================
# Simple card accessors (self-contained, no dependency on policy)
# ============================================================

func _get_card_def(card_id: int, state):
	## Returns card definition or null if card not found.
	if card_id == -1: return null
	var card = state.card_db.get_card(card_id)
	if card == null: return null
	return card.definition


func _can_card_hit_simple(card_id: int, state, _is_response: bool) -> bool:
	if card_id == -1: return false
	var card_def = _get_card_def(card_id, state)
	if card_def == null: return false
	var gauge_cost = card_def.get("gauge_cost", 0)
	if gauge_cost > state.my_state.gauge.size(): return false
	var my_loc: int = state.my_state.arena_location
	var opp_loc: int = state.opponent_state.arena_location
	var distance: int = abs(my_loc - opp_loc)
	var rmin = card_def.get("range_min", 1)
	if rmin is String: rmin = 1
	var rmax = card_def.get("range_max", rmin + 3)
	if rmax is String: rmax = rmin + 3
	return rmin <= distance and distance <= rmax


func _is_block_card_simple(card_id: int, state) -> bool:
	if card_id == -1: return false
	var card_def = _get_card_def(card_id, state)
	if card_def == null: return false
	var cid = card_def.get("id", "")
	return "block" in cid.to_lower()


func _get_card_speed_simple(card_id: int, state, is_response: bool) -> int:
	if card_id == -1: return 0
	var card_def = _get_card_def(card_id, state)
	if card_def == null: return 0
	var speed = card_def.get("speed", 0)
	if speed is String: return 20
	# Conditional effects
	for ef in card_def.get("effects", []):
		if ef.get("effect_type") == "speedup":
			var cond = ef.get("condition", "")
			if (cond == "not_initiated_strike" and is_response) or (cond == "is_critical" and false):
				speed += ef.get("amount", 0)
	# Continuous boosts
	for bid in state.my_state.continuous_boosts:
		var bdef = _get_card_def(bid, state)
		if bdef == null: continue
		for bef in bdef.get("boost", {}).get("effects", []):
			if bef.get("timing") == "during_strike":
				if bef.get("effect_type") == "speedup": speed += bef.get("amount", 0)
				elif bef.get("effect_type") == "attack_is_ex": speed += 1
	return speed


func _get_card_power_simple(card_id: int, state) -> int:
	if card_id == -1: return 0
	var card_def = _get_card_def(card_id, state)
	if card_def == null: return 0
	var p = card_def.get("power", 0)
	return 0 if p is String else p


func _get_card_armor_simple(card_id: int, state) -> int:
	if card_id == -1: return 0
	var card_def = _get_card_def(card_id, state)
	if card_def == null: return 0
	return card_def.get("armor", 0)


func _get_card_guard_simple(card_id: int, state) -> int:
	if card_id == -1: return 0
	var card_def = _get_card_def(card_id, state)
	if card_def == null: return 0
	return card_def.get("guard", 0)


func _get_card_range_min_simple(card_id: int, state) -> int:
	if card_id == -1: return -1
	var card_def = _get_card_def(card_id, state)
	if card_def == null: return -1
	var r = card_def.get("range_min", 1)
	return 1 if r is String else r


func _get_card_range_max_simple(card_id: int, state) -> int:
	if card_id == -1: return -1
	var card_def = _get_card_def(card_id, state)
	if card_def == null: return -1
	var r = card_def.get("range_max", 1)
	return 4 if r is String else r


# ============================================================
# Helper functions
# ============================================================

func _get_curve_speed(distance: int) -> int:
	match distance:
		1: return 7
		2: return 6
		3: return 5
		4: return 4
		_: return 3


func _estimate_opp_max_speed(distance: int, state) -> int:
	var max_speed: int = 0
	for card in state.opponent_state.deck_list:
		if card.definition.get("type") != "normal": continue
		var cid = card.definition.get("id", "")
		if "block" in cid.to_lower(): continue
		var rmin = card.definition.get("range_min", 1)
		if rmin is String: rmin = 1
		var rmax = card.definition.get("range_max", rmin + 3)
		if rmax is String: rmax = rmin + 3
		if rmin <= distance and distance <= rmax:
			var speed = card.definition.get("speed", 0)
			if speed is String: speed = 0
			if speed > max_speed: max_speed = speed
	return max_speed


func _estimate_opp_max_power(distance: int, state) -> int:
	var max_power: int = 0
	for card in state.opponent_state.deck_list:
		var ctype = card.definition.get("type", "")
		if ctype != "normal" and ctype != "special": continue
		var rmin = card.definition.get("range_min", 1)
		if rmin is String: rmin = 1
		var rmax = card.definition.get("range_max", rmin + 3)
		if rmax is String: rmax = rmin + 3
		if rmin <= distance and distance <= rmax:
			var p = card.definition.get("power", 0)
			if p is String: p = 0
			if p > max_power: max_power = p
	return max_power


func _count_type_in_deck(player_state, card_type: String) -> int:
	var count: int = 0
	for card in player_state.deck_list:
		if card.definition.get("type") == card_type: count += 1
	return count


func _count_known_opp_hand(state) -> int:
	# Estimate known opponent hand cards (simplified: use hand size)
	return state.opponent_state.hand.size()


func _count_ex_possible(player_state, state) -> int:
	# Count cards that have a duplicate in hand (EX potential)
	var name_counts: Dictionary = {}
	for cid in player_state.hand:
		var cname = (_get_card_def(cid, state) if _get_card_def(cid, state) else {}).get("id", "")
		name_counts[cname] = name_counts.get(cname, 0) + 1
	var ex_count: int = 0
	for cname in name_counts:
		if name_counts[cname] >= 2: ex_count += 1
	return ex_count


func _classify_character_simple(player_state, _state) -> String:
	var special_count: int = 0
	var ranged_count: int = 0
	var melee_count: int = 0
	for card in player_state.deck_list:
		if card.definition.get("type") != "special": continue
		special_count += 1
		var rmax = card.definition.get("range_max", 1)
		if rmax is String: rmax = 4
		if rmax >= 4: ranged_count += 1
		var rmin = card.definition.get("range_min", 1)
		if rmin is String: rmin = 1
		if rmin <= 1: melee_count += 1
	if special_count == 0: return "midrange"
	if float(ranged_count) / float(special_count) >= 0.5: return "ranged"
	if float(melee_count) / float(special_count) >= 0.5: return "melee"
	return "midrange"


func _get_ideal_distance_simple(my_class: String, opp_class: String) -> int:
	if my_class == "melee": return 1 if opp_class == "ranged" else 2
	if my_class == "ranged": return 5
	return 3 if opp_class == "melee" else 2


func _has_critical_ability(player_state, _state) -> bool:
	var deck_def = player_state.deck_def
	var ability_list: Array = deck_def.get("ability_effects", [])
	if player_state.exceeded: ability_list = deck_def.get("exceed_ability_effects", ability_list)
	for ab_eff in ability_list:
		if ab_eff.get("timing") == "set_strike" and ab_eff.get("effect_type") == "gauge_for_effect":
			if ab_eff.get("overall_effect", {}).get("effect_type") == "critical":
				if ab_eff.get("gauge_max", 0) >= 1: return true
	return false


func _has_transform_ability(player_state, _state) -> bool:
	return player_state.deck_def.get("season", 0) == 2


func _score_boost_simple(card_id: int, state) -> float:
	# Simplified boost scoring for feature extraction
	var card_def = _get_card_def(card_id, state)
	if card_def == null: return 0.0
	var boost_def = card_def.get("boost", {})
	if boost_def.is_empty(): return 0.0
	var score: float = 0.0
	for effect in boost_def.get("effects", []):
		var et = effect.get("effect_type", "")
		var amount = effect.get("amount", 0)
		if et in ["powerup", "speedup", "attack_is_ex"]: score += amount * 15.0
		elif et in ["armorup", "guardup"]: score += amount * 8.0
		elif et in ["advance", "retreat", "push", "pull"]: score += amount * 8.0
		elif et == "draw": score += amount * 10.0
		elif et == "name_card_opponent_discards": score += 15.0
		else: score += 5.0
	if boost_def.get("boost_type") == "continuous": score += 6.0
	score -= boost_def.get("force_cost", 0) * 4.0
	return score


func _get_player_id(state) -> int:
	return state.my_state.player_id


# ============================================================
# Persistence
# ============================================================

func save_weights(path: String) -> void:
	var data: Dictionary = {
		"epsilon": _epsilon,
		"train_count": _train_count,
		"total_reward": _total_reward,
		"running_loss": _running_loss,
		"weights": _weights,
		"biases": _biases,
	}
	var json_str: String = JSON.stringify(data, "\t")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()
		print("[AILearner] Weights saved to %s (%d KB)" % [path, float(json_str.length()) / 1024.0])
	else:
		push_warning("[AILearner] Cannot save weights: %s" % path)


func load_weights(path: String) -> bool:
	if not FileAccess.file_exists(path):
		print("[AILearner] No saved weights at %s, using random init" % path)
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_warning("[AILearner] Cannot open weights file: %s" % path)
		return false
	var json_str: String = file.get_as_text()
	file.close()
	var json = JSON.new()
	var err = json.parse(json_str)
	if err != OK:
		push_warning("[AILearner] JSON parse error in weights file")
		return false
	var data: Dictionary = json.get_data()
	if data.is_empty(): return false

	# Restore weights and biases
	var loaded_w: Array = data.get("weights", [])
	var loaded_b: Array = data.get("biases", [])
	if loaded_w.size() != _weights.size() or loaded_b.size() != _biases.size():
		push_warning("[AILearner] Weight shape mismatch, using random init")
		return false

	# Validate shapes
	for l in range(loaded_w.size()):
		if loaded_w[l].size() != _weights[l].size():
			push_warning("[AILearner] Weight shape mismatch at layer %d" % l)
			return false
		if loaded_w[l][0].size() != _weights[l][0].size():
			push_warning("[AILearner] Weight shape mismatch at layer %d" % l)
			return false
		if loaded_b[l].size() != _biases[l].size():
			push_warning("[AILearner] Bias shape mismatch at layer %d" % l)
			return false

	# Sanitize: replace null values with 0.0 (JSON may contain nulls)
	for l in range(loaded_w.size()):
		for i in range(loaded_w[l].size()):
			for j in range(loaded_w[l][i].size()):
				if loaded_w[l][i][j] == null: loaded_w[l][i][j] = 0.0
		for i in range(loaded_b[l].size()):
			if loaded_b[l][i] == null: loaded_b[l][i] = 0.0
	_weights = loaded_w
	_biases = loaded_b
	var _ep = data.get("epsilon", _epsilon); _epsilon = _ep if _ep != null else _epsilon
	var _tc = data.get("train_count", 0); _train_count = _tc if _tc != null else 0
	var _tr = data.get("total_reward", 0.0); _total_reward = _tr if _tr != null else 0.0
	var _rl = data.get("running_loss", 0.0); _running_loss = _rl if _rl != null else 0.0

	# Reset momentum buffers
	_velocity_weights.clear()
	_velocity_biases.clear()
	for l in range(_weights.size()):
		var vw: Array = []
		vw.resize(_weights[l].size())
		for i in range(_weights[l].size()):
			var vrow: Array = []
			vrow.resize(_weights[l][i].size())
			for j in range(_weights[l][i].size()):
				vrow[j] = 0.0
			vw[i] = vrow
		_velocity_weights.append(vw)

		var vb: Array = []
		vb.resize(_biases[l].size())
		for i in range(_biases[l].size()):
			vb[i] = 0.0
		_velocity_biases.append(vb)

	print("[AILearner] Weights loaded from %s (epsilon=%.3f, trained=%d, reward=%.1f, loss=%.4f)" % [
		path, _epsilon, _train_count, _total_reward, _running_loss])
	return true


func _get_parameter_count() -> int:
	var total: int = 0
	for l in range(_weights.size()):
		for i in range(_weights[l].size()):
			total += _weights[l][i].size()
		total += _biases[l].size()
	return total


func get_epsilon() -> float:
	return _epsilon


func get_train_count() -> int:
	return _train_count


func get_running_loss() -> float:
	return _running_loss


func get_total_reward() -> float:
	return _total_reward


func set_lr(new_lr: float) -> void:
	_lr = new_lr


func set_epsilon(new_eps: float) -> void:
	_epsilon = new_eps
