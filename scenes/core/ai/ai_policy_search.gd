class_name AIPolicySearch
extends AIPolicyOmniscient

## AIPolicySearch — 前瞻搜索策略（比 AIPolicyOmniscient 更强、更稳定）。
##
## 与「全知」策略相比，本策略做了三件关键的事：
##   1. 攻击决策「前瞻化」：不再单看某张牌的分，而是显式模拟
##      「我出这张 → 对手用手里最克制我的牌还击 → 净血量交换是多少」，
##      用 worst-case 净交换作为攻击的核心判据（牌之间的克制关系）。
##   2. 回合决策「去随机化」：把原策略里大量 randf()/randi() 的
##      频率式选择，替换为确定性的优先级 + 统一评估，避免乱出招。
##   3. 难度旋钮：控制前瞻深度与决策噪声，可做成 4 档难度。

## 难度：0=简单 1=普通 2=困难 3=专家（默认专家）
var difficulty: int = 3

## 内置卡牌库 + 克制关系引擎
var _knowledge := AICardKnowledge.new()

## 移动行动限制：一局最多主动「移动」2 次，之后想变位置只能靠
## Cross/advance/retreat 等移动效果或角色位移技能。
## 近战型 AI（牌库远程牌 ≤ 2 张）放宽到 3 次，便于贴脸逼近。
var _move_count := 0
const MAX_MOVE_ACTIONS := 2
const MAX_MOVE_ACTIONS_MELEE := 3
var _melee_mode := false
var _move_limit := MAX_MOVE_ACTIONS


func _can_use_move() -> bool:
	return _move_count < _move_limit


## 统计牌库（deck_list，含未抽出的牌）里「能打到 4 距以上(range_max>=4)」的牌张数。
## 用于判断 AI 是否是近战型：远程牌极少 → 应积极贴脸逼近而非后退。
func _long_range_card_count(state: AIPlayer.AIGameState) -> int:
	var count := 0
	for cid in state.my_state.deck_list:
		if cid == null:
			continue
		var ddef = null
		if cid is Dictionary:
			ddef = cid.get("definition", null)
			if ddef == null and cid.has("id"):
				ddef = _get_global_card_def(str(cid["id"]))
		else:
			ddef = cid.definition
		if ddef == null or not (ddef is Dictionary):
			continue
		var rmax = ddef.get("range_max", -1)
		if rmax is String:
			rmax = -1
		if int(rmax) >= 4:
			count += 1
	return count

## 本回合是否抑制「非斩杀」的主动攻击（10% 概率）
var _turn_skip_strike: bool = false

## 刚 cancel 掉 GG 专注（gg_normal_focus）后，下一次行动必须开打（攻击）。
var _just_canceled_gg_focus: bool = false

## 作弊换牌：应战兜底（要走 wild swing）时，从牌库偷一张能反击的牌，无痕置换，每局 3 次
var _cheat_swap_count := 0
const CHEAT_SWAP_MAX := 3

## 分值换算：把「净血量交换」映射到统一分值（1 血 ≈ 8 分）
const EXCHANGE_WEIGHT := 8.0
## 把父类 _score_boost / _score_character_action 压到统一量纲
const BOOST_SCALE := 0.5
const CA_SCALE := 0.6


func set_difficulty(d: int) -> void:
	difficulty = clampi(d, 0, 3)
	print("[AI策略] 已启用 AIPolicySearch 前瞻策略，难度=%d" % difficulty)


## 低难度下的决策噪声（专家=0，简单≈最大）
func _decision_noise() -> float:
	return (3.0 - difficulty) * 2.5


# ============================================================
# 统一评估函数
# ============================================================

## 从 AI 视角评估整个棋盘状态，返回一个统一分值（越高越好）。
## 以「血量」为锚：1 血 ≈ 10 分，其余维度等比叠加。
func _evaluate(state: AIPlayer.AIGameState) -> float:
	var my = state.my_state
	var opp = state.opponent_state
	var s: float = 0.0

	# 1) 血量差（含斩杀阈值放大）
	s += (my.life - opp.life) * 10.0
	if opp.life <= 5:
		s += (6 - opp.life) * 12.0
	if my.life <= 5:
		s -= (6 - my.life) * 16.0

	# 2) 位置质量：距离理想距离越近越好
	var dist: int = _get_distance(state)
	var ideal: int = _get_ideal_distance(
		_classify_character(my, state), _classify_character(opp, state))
	s -= abs(dist - ideal) * 4.0

	# 3) 我方可达：当前手牌有几张能打中
	var my_hits: int = 0
	for cid in my.hand:
		if can_card_hit(cid, -1, state):
			my_hits += 1
	s += my_hits * 6.0

	# 4) 对手威胁：对手能打中我的牌越多越危险
	var opp_analysis: Dictionary = _opponent_can_do_now(state)
	s -= int(opp_analysis.get("can_hit_count", 0)) * 4.0
	if opp_analysis.get("can_kill_me", false):
		s -= 30.0

	# 5) 资源经济
	s += (my.hand.size() - opp.hand.size()) * 2.5
	s += (my.gauge.size() - opp.gauge.size()) * 1.5
	s += (my.continuous_boosts.size() - opp.continuous_boosts.size()) * 2.0

	# 6) 变身优势
	if my.exceeded and not opp.exceeded:
		s += 18.0

	return s


# ============================================================
# 攻击交换前瞻（克制关系核心）
# ============================================================

## 返回发起攻击时（带 EX 修正后）的有效卡面定义。
func _effective_strike_def(action, state: AIPlayer.AIGameState) -> Dictionary:
	var d = _get_def(action.card_id, state)
	if d == null:
		return {}
	if action.ex_card_id != -1:
		d = d.duplicate(true)
		for k in ["speed", "power", "guard", "armor"]:
			var v = d.get(k, 0)
			if not (v is String):
				d[k] = int(v) + 1
	# 应用 critical 数值加成（有 critical 能力 + 有怒气 + 是 Special 时）
	d = _apply_critical_to_def(d, state)
	return d


## 我方用 `action` 发起攻击时，对手手里「最克制我」的那张还击牌
## 带来的 worst-case 净血量交换（正=我赚，负=我亏）。
## 对手无牌能还击时返回 full damage（单方面命中）。
func _strike_worst_exchange(action, state: AIPlayer.AIGameState) -> Dictionary:
	var my_def: Dictionary = _effective_strike_def(action, state)
	if my_def.is_empty():
		return {"exchange": -99, "has_response": false}
	var distance: int = _get_distance(state)
	var opp_analysis: Dictionary = _opponent_can_do_now(state)
	var worst: int = 999
	var has_response: bool = false
	for cb in opp_analysis.get("cards_by_range", []):
		if not cb.get("in_range", false):
			continue
		var od = cb.get("defn", {})
		if od == null or od.is_empty():
			continue
		var e: int = _card_exchange_value(my_def, od, distance, false)
		if e < worst:
			worst = e
		has_response = true
	if not has_response:
		var power: int = _get_card_power(action.card_id, state)
		if action.ex_card_id != -1:
			power += 1
		worst = power
	return {"exchange": worst, "has_response": has_response}


## 牌面克制关系加分：我这张牌对「对手最强还击」的克制程度。
## 返回的分数叠加在净交换值之上，让 AI 明确「谁克谁」。
func _counter_bonus(action, state: AIPlayer.AIGameState, opp_analysis: Dictionary) -> float:
	var b: float = 0.0
	var defn = _get_def(action.card_id, state)
	if defn == null:
		return 0.0
	# 速度克制：我比对手最快牌还快 → 我先手，有机会直接击晕
	var my_speed: int = _get_card_speed(action.card_id, state, false)
	if action.ex_card_id != -1:
		my_speed += 1
	var opp_max_speed: int = int(opp_analysis.get("max_speed", 0))
	if my_speed > opp_max_speed:
		b += 14.0
	elif my_speed == opp_max_speed and my_speed > 0:
		b += 7.0  # 平速发起者先手
	# 破甲克护甲流：对手霸体高时，破甲牌价值飙升
	if _def_has_effect(defn, "ignore_armor") and int(opp_analysis.get("max_guard", 0)) >= 4:
		b += 9.0
	# 破防克格挡：对手手里有 Block 时，破防/穿透牌最克制
	if _def_has_effect(defn, "ignore_guard") and opp_analysis.get("has_block", false):
		b += 12.0
	# 我方护甲/霸体够硬 → 硬吃对手还击不虚
	var my_guard: int = _get_card_guard(action.card_id, state)
	if action.ex_card_id != -1:
		my_guard += 1
	if my_guard >= int(opp_analysis.get("max_power", 0)):
		b += 8.0
	# 被克制警示：对手破甲而我方依赖护甲 → 减分
	if opp_analysis.get("has_ignore_armor", false) and _get_card_armor(action.card_id, state) > 0:
		b -= 10.0
	# 被克制警示：对手破防(spike/dust 无视霸体)而我方依赖霸体(focus/sweep等) → 减分
	if opp_analysis.get("has_ignore_guard", false) and _get_card_guard(action.card_id, state) >= 4:
		b -= 10.0
	# 流派克制（内置卡牌库）：破防/穿透克制格挡与坦克，格挡被破甲克制
	var arch: String = _knowledge.classify(defn)
	if opp_analysis.get("has_block", false) and arch in ["spike", "guard_break"]:
		b += 12.0
	if arch in ["block", "tank"] and opp_analysis.get("has_ignore_armor", false):
		b -= 8.0
	if arch == "throw" and int(opp_analysis.get("max_guard", 0)) >= 4:
		b += 8.0  # 投技克高霸体
	return b


## 攻击动作的统一分值（前瞻后）。
func _value_strike(action, state: AIPlayer.AIGameState) -> float:
	if action.wild_swing:
		return 5.0
	var ex: Dictionary = _strike_worst_exchange(action, state)
	var s: float = float(ex["exchange"]) * EXCHANGE_WEIGHT

	# 斩杀
	if _can_kill(action.card_id, action.ex_card_id, state):
		s += 60.0

	var opp_analysis: Dictionary = _opponent_can_do_now(state)

	# 击晕潜力：我方威力超过对手最大霸体（破防则霸体视为 0，威力 > 0 即可击晕）
	var power: int = _get_card_power(action.card_id, state)
	if action.ex_card_id != -1:
		power += 1
	var _my_def_for_ig = _get_def(action.card_id, state)
	var _my_ig: bool = _def_has_effect(_my_def_for_ig, "ignore_guard") if _my_def_for_ig != null else false
	if _my_ig:
		if power > 0:
			s += 14.0  # 破防：无视霸体，威力 > 0 即可击晕（critical 破防牌如沙加特低位扫腿）
	elif power > int(opp_analysis.get("max_guard", 0)):
		s += 12.0

	# 牌面克制关系加分
	s += _counter_bonus(action, state, opp_analysis)

	# 效用效果
	var defn = _get_def(action.card_id, state)
	for ef in defn.get("effects", []):
		var et: String = str(ef.get("effect_type", ""))
		if et == "draw":
			s += int(ef.get("amount", 1)) * 6.0
		elif et == "opponent_discard_random":
			s += int(ef.get("amount", 1)) * 5.0
		elif et == "gain_advantage":
			s += 15.0

	# 费用
	s -= int(defn.get("gauge_cost", 0)) * 4.0

	# 闪避可行性：带 retreat（打了就跑）的牌（如 cross）主动攻击前，预判 retreat 后落点，
	# 躲不开对手反击（对手射程覆盖落点 / 场地边缘退不足）→ 大幅扣分，不用它主动打。
	if _def_has_effect(defn, "retreat") and not _retreat_safe(action.card_id, state):
		s -= 30.0
	return s


## 主动攻击带 retreat（打了就跑）的牌前，预判 retreat 后落点，
## 判断 retreat 后对手能否反击击中。返回 true = 能躲开（安全），false = 躲不开。
func _retreat_safe(card_id: int, state: AIPlayer.AIGameState) -> bool:
	var defn = _get_def(card_id, state)
	if defn == null:
		return true
	var retreat := 0
	for eff in defn.get("effects", []):
		if eff.get("effect_type") == "retreat":
			var amt = eff.get("amount", 0)
			if amt is String:
				amt = 0
			retreat = max(retreat, int(amt))
	if retreat <= 0:
		return true  # 没有 retreat，无所谓闪避
	var my_loc: int = state.my_state.arena_location
	var opp_loc: int = state.opponent_state.arena_location
	var dir: int = -1 if my_loc < opp_loc else 1  # 远离对手方向
	var new_loc: int = my_loc + dir * retreat
	new_loc = clampi(new_loc, Enums.MinArenaLocation, Enums.MaxArenaLocation)
	var new_dist: int = abs(new_loc - opp_loc)
	var opp_at: Dictionary = _analyze_opponent_at_distance(new_dist, state)
	return int(opp_at.get("can_hit_count", 0)) == 0


## 移动动作的统一分值（前瞻：评估落点后的位置质量 + 对手在该距离的威胁）。
func _value_move(action, state: AIPlayer.AIGameState) -> float:
	var cur_dist: int = _get_distance(state)
	var new_dist: int = abs(action.location - state.opponent_state.arena_location)
	# 禁止后退：AI 不准主动后退移动，直接给极低分排除
	if new_dist > cur_dist:
		return -999.0
	var ideal: int = _get_ideal_distance(
		_classify_character(state.my_state, state),
		_classify_character(state.opponent_state, state))
	var s: float = -abs(new_dist - ideal) * 5.0

	# 近战型 AI：进入 3 距以内（贴脸，能发挥近战牌射程）额外加分
	if _melee_mode and new_dist <= 3:
		s += 15.0

	# 落点后我方有几张牌能打中
	var my_hits: int = 0
	for cid in state.my_state.hand:
		var rmin: int = _get_card_range_min(cid, state)
		var rmax: int = _get_card_range_max(cid, state)
		if rmin <= new_dist and new_dist <= rmax:
			my_hits += 1
	s += my_hits * 7.0

	# 对手在新距离的威胁
	var opp_at: Dictionary = _analyze_opponent_at_distance(new_dist, state)
	s -= int(opp_at.get("can_hit_count", 0)) * 4.0
	if opp_at.get("can_kill_me", false):
		s -= 30.0

	# 费用
	s -= action.force_card_ids.size() * 6.0
	if action.use_free_force:
		s += 4.0
	if _passes_through_opponent(action.location, state):
		s -= 10.0
	return s


## 用「卡牌定义」算 worst-case 净交换（不含 EX、不含 action 包装）。
func _worst_exchange_def(my_def: Dictionary, state: AIPlayer.AIGameState) -> int:
	if my_def.is_empty():
		return -99
	var distance: int = _get_distance(state)
	var opp_analysis: Dictionary = _opponent_can_do_now(state)
	var worst: int = 999
	var has_resp: bool = false
	for cb in opp_analysis.get("cards_by_range", []):
		if not cb.get("in_range", false):
			continue
		var od = cb.get("defn", {})
		if od == null or od.is_empty():
			continue
		var e: int = _card_exchange_value(my_def, od, distance, false)
		if e < worst:
			worst = e
		has_resp = true
	if not has_resp:
		worst = _sd_power(my_def)
	return worst


## 我手里现在有没有牌能在当前距离打中对手（用于判断加成是否白加）。
func _can_hit_opponent_now(state: AIPlayer.AIGameState) -> bool:
	for cid in state.my_state.hand:
		if can_card_hit(cid, -1, state):
			return true
	return false


## 这个加成是否带位移效果（advance/close/retreat/move_to_any_space/push/pull）。
## 带位移的加成即使现在打不中，也能靠位移接近，仍算有收益。
func _boost_has_movement(card_id: int, state: AIPlayer.AIGameState) -> bool:
	return _boost_has_effect(card_id, state, ["advance", "close", "retreat", "move_to_any_space", "push", "pull"])


## 递归判断一个 effect（含 choice / and 嵌套）是否包含任一给定效果类型。
func _effect_has_type_in_tree(effect: Dictionary, effect_types: Array) -> bool:
	if str(effect.get("effect_type", "")) in effect_types:
		return true
	var choice = effect.get("choice", [])
	if choice is Array:
		for sub in choice:
			if sub is Dictionary and _effect_has_type_in_tree(sub, effect_types):
				return true
	var and_eff = effect.get("and", {})
	if and_eff is Dictionary and not and_eff.is_empty():
		if _effect_has_type_in_tree(and_eff, effect_types):
			return true
	return false


## 这个加成是否包含任一给定效果类型（递归检查 choice/and 嵌套，如 cross 的 choice→advance/push/pull）。
func _boost_has_effect(card_id: int, state: AIPlayer.AIGameState, effect_types: Array) -> bool:
	var d = _get_def(card_id, state)
	if d == null:
		return false
	var bdef = d.get("boost", {})
	for be in bdef.get("effects", []):
		if _effect_has_type_in_tree(be, effect_types):
			return true
	return false


## 加成组合价值：加成是为「下次攻击」做铺垫。
## 遍历手牌里能打中的攻击牌，算「加成前 vs 加成后」其 worst-case
## 净交换的改善，改善越大说明这个加成越能强化下一次攻击。
func _boost_combo_bonus(boost_card_id: int, state: AIPlayer.AIGameState) -> float:
	var d = _get_def(boost_card_id, state)
	if d == null:
		return 0.0
	var bdef = d.get("boost", {})
	# 提取加成的属性加成（持续/即时）
	var power_bonus := 0
	var speed_bonus := 0
	var guard_bonus := 0
	var armor_bonus := 0
	for be in bdef.get("effects", []):
		var et: String = str(be.get("effect_type", ""))
		var amt = be.get("amount", 0)
		if amt is String:
			amt = 0
		match et:
			"powerup": power_bonus += int(amt)
			"speedup": speed_bonus += int(amt)
			"guardup": guard_bonus += int(amt)
			"armorup": armor_bonus += int(amt)
			"attack_is_ex": speed_bonus += 1
	if power_bonus == 0 and speed_bonus == 0 and guard_bonus == 0 and armor_bonus == 0:
		return 0.0
	# 遍历手牌，算加成前后最差交换的改善
	var distance: int = _get_distance(state)
	var best_improvement: int = 0
	for cid in state.my_state.hand:
		var my_def = _get_def(cid, state)
		if my_def == null:
			continue
		if not _range_hits(my_def, distance):
			continue
		var before: int = _worst_exchange_def(my_def, state)
		var boosted: Dictionary = my_def.duplicate(true)
		for key in ["power", "speed", "guard", "armor"]:
			var v = boosted.get(key, 0)
			if v is String:
				continue
			var bonus := 0
			if key == "power":
				bonus = power_bonus
			elif key == "speed":
				bonus = speed_bonus
			elif key == "guard":
				bonus = guard_bonus
			elif key == "armor":
				bonus = armor_bonus
			boosted[key] = int(v) + bonus
		var after: int = _worst_exchange_def(boosted, state)
		var improvement: int = after - before
		if improvement > best_improvement:
			best_improvement = improvement
	return float(best_improvement) * EXCHANGE_WEIGHT


## 加成动作的分值：效果感知评分 + 组合价值（为下次攻击铺垫）。
func _value_boost(action, state: AIPlayer.AIGameState) -> float:
	var s: float = _score_boost(action, state) * BOOST_SCALE
	s += _boost_combo_bonus(action.card_id, state)
	# 大幅提高 focus / block 加成的使用概率
	var sid: String = _get_card_id_str(action.card_id, state).to_lower()
	if "focus" in sid:
		s += 25.0
	if "block" in sid:
		s += 20.0
	# GG 专注（gg_normal_focus）：使用前必须有 ≥1 怒气（用于用完后的 cancel）
	if sid == "gg_normal_focus" and state.my_state.gauge.size() < 1:
		s -= 80.0

	# 加成前必须通过双方手牌确保「加成后能打中对手」，否则属性/铺垫加成毫无收益。
	# 豁免两类：① 带位移的加成（靠位移接近，仍有收益）；
	#           ② block 的 Parry（点名弃对手牌，与距离无关，用于处理威胁卡）。
	var is_block_boost := "block" in sid or _boost_has_effect(action.card_id, state, ["name_card_opponent_discards"])
	if not is_block_boost and not _boost_has_movement(action.card_id, state) and not _can_hit_opponent_now(state):
		s -= 40.0
	return s


## 角色技能时机知识：根据战局判断「现在该不该用技能、值多少」。
func _skill_timing_bonus(action, state: AIPlayer.AIGameState) -> float:
	var char_def = state.my_state.deck_def
	var abilities: Array = char_def.get("ability_effects", [])
	if state.my_state.exceeded:
		abilities = char_def.get("exceed_ability_effects", abilities)
	if action.action_idx < 0 or action.action_idx >= abilities.size():
		return 0.0
	var ab: Dictionary = abilities[action.action_idx]
	var eff_type: String = str(ab.get("effect_type", ""))
	var timing: String = str(ab.get("timing", ""))
	var b: float = 0.0
	var dist: int = _get_distance(state)
	var ideal: int = _get_ideal_distance(
		_classify_character(state.my_state, state),
		_classify_character(state.opponent_state, state))
	var opp_analysis: Dictionary = _opponent_can_do_now(state)

	# 1) 保命优先：对手能斩杀我时，治疗/护甲/后退类技能此刻价值最高
	if opp_analysis.get("can_kill_me", false):
		if eff_type in ["heal", "recover_cards", "armorup", "guardup", "retreat"] \
				or timing in ["heal"]:
			b += 30.0
	# 2) 斩杀铺垫：对手残血且技能能强化/逼近，为下回合斩杀服务
	if state.opponent_state.life <= 6:
		if eff_type in ["powerup", "advance", "move", "speedup"] or timing in ["move"]:
			b += 15.0
	# 3) 位置修正：够不着对手时，位移技能价值大增
	if eff_type == "move" or timing == "move":
		if abs(dist - ideal) >= 2:
			b += 20.0
		elif abs(dist - ideal) >= 1:
			b += 8.0
	# 4) 资源节奏：手牌/力槽告急时，抽牌/产力技能更值钱
	if eff_type in ["draw", "card_draw"] and state.my_state.hand.size() <= 3:
		b += 12.0
	if eff_type in ["generate_force", "generate_gauge"] and state.my_state.gauge.size() < 2:
		b += 10.0
	# 5) 费用惩罚：烧到 Ultra 或高费时不划算
	var force_cost: int = int(ab.get("force_cost", 0))
	if force_cost > 0 and action.card_ids.size() > 0:
		for cid in action.card_ids:
			var cdef = _get_def(cid, state)
			if cdef != null and cdef.get("type", "") == "ultra":
				b -= 20.0
	return b


## 角色技能动作的分值：父类评分 + 时机前瞻修正。
func _value_character(action, state: AIPlayer.AIGameState) -> float:
	var s: float = _score_character_action(action, state) * CA_SCALE
	s += _skill_timing_bonus(action, state)
	return s


func _value_prepare(state: AIPlayer.AIGameState) -> float:
	# 手牌越少，热身（抽牌）越值钱
	var hand: int = state.my_state.hand.size()
	if hand >= 6:
		return -60.0  # 6 牌及以上绝不热身
	if hand <= 2:
		return 34.0
	if hand <= 3:
		return 20.0
	if hand <= 4:
		return 9.0
	return 4.0  # 5 张：略微鼓励热身


func _value_exceed(state: AIPlayer.AIGameState) -> float:
	# 变身几乎总是好的，但手牌/资源太紧时优先级下降
	var s: float = 45.0
	if state.my_state.gauge.size() < 3:
		s -= 10.0
	return s


func _value_change(action, state: AIPlayer.AIGameState) -> float:
	# 换卡：手牌越缺、换来的力越多越值钱
	var force: int = 0
	for cid in action.card_ids:
		force += state.card_db.get_card_force_value(cid)
	var s: float = float(force) * 2.0
	if state.my_state.hand.size() <= 3:
		s += 8.0
	return s


## 手牌告急(≤2)时，找一个「用怒气/ultra 换牌补到手牌 6」的方案。
## 换牌机制：弃掉 card_ids(手牌+怒气牌)，每张生成 force(普通1/ultra2)，抽 force 张。
## 净手牌 = 当前手牌 - 弃掉的手牌 + force。目标 net ≈ 6。
func _best_refill_change(change_actions: Array, state: AIPlayer.AIGameState):
	var target := 6
	var hand: int = state.my_state.hand.size()
	var best = null
	var best_net := -999
	var best_v := -999999.0
	for action in change_actions:
		var force := 0
		var discard_from_hand := 0
		for cid in action.card_ids:
			force += state.card_db.get_card_force_value(cid)
			if state.my_state.hand.has(cid):
				discard_from_hand += 1
		var net: int = hand - discard_from_hand + force
		# 越接近 6 越好；用怒气牌换牌有代价（怒气宝贵），略惩罚
		var v: float = -abs(net - target) * 10.0
		var gauge_used: int = action.card_ids.size() - discard_from_hand
		v -= gauge_used * 4.0
		if net < target:
			v -= (target - net) * 6.0  # 抽不满额外惩罚
		if v > best_v:
			best_v = v
			best_net = net
			best = action
	# 只有确实补了牌（净手牌至少 +2）才换，否则不如热身/draw 加成
	if best != null and best_net >= hand + 2:
		return best
	return null


## 找带「抽牌(draw)」效果的加成（抽牌优先于热身）。
func _best_draw_boost(boost_actions: Array, state: AIPlayer.AIGameState):
	var best = null
	var best_v: float = -999999.0
	for ba in boost_actions:
		var d = _get_def(ba.card_id, state)
		if d == null:
			continue
		var bdef = d.get("boost", {})
		var has_draw: bool = false
		for be in bdef.get("effects", []):
			if str(be.get("effect_type", "")) == "draw":
				has_draw = true
				break
		if not has_draw:
			continue
		var v: float = _value_boost(ba, state)
		if v > best_v:
			best_v = v
			best = ba
	return best


## 找带「移动(advance/retreat/close/move_to_any_space/push/pull)」效果的加成（移动优先）。
func _best_move_boost(boost_actions: Array, state: AIPlayer.AIGameState):
	var best = null
	var best_v: float = -999999.0
	for ba in boost_actions:
		if not _boost_has_effect(ba.card_id, state, ["advance", "retreat", "close", "move_to_any_space", "push", "pull"]):
			continue
		var v: float = _value_boost(ba, state)
		# 近战型 AI：带 advance/close（前进）的加成（如 cross 前进 3 格）优先
		if _melee_mode and _boost_has_effect(ba.card_id, state, ["advance", "close"]):
			v += 25.0
		if v > best_v:
			best_v = v
			best = ba
	return best


# ============================================================
# 对手下一回合前瞻（核心：让 AI 真正「想远一步」）
# ============================================================

## 对手用 opp_def 发起攻击时，我方从手里选「净交换最优」的还击牌，
## 返回我方的净血量交换（正=我赚，负=我亏）。
func _my_best_response_exchange(opp_def: Dictionary, state: AIPlayer.AIGameState) -> int:
	var distance: int = _get_distance(state)
	var best: int = -99
	var has_option: bool = false
	for cid in state.my_state.hand:
		var my_def = _get_def(cid, state)
		if my_def == null:
			continue
		# 允许「射程外但带后撤/位移可躲招」的牌参与还击
		if not _range_hits(my_def, distance) and not _def_has_effect(my_def, "retreat"):
			continue
		var e: Dictionary = _eval_counter_response(my_def, opp_def, distance, true)
		var v: int = int(e.get("exchange", -99))
		if not has_option or v > best:
			best = v
			has_option = true
	if not has_option:
		# 我方无牌可还击 → 对手白打，我方净亏其完整伤害
		return -_effective_power(opp_def)
	return best


## 对手下一回合的「打击威胁」：对手从手里选最优攻击、我方选最优还击，
## 返回我方可能承受的最大净血量损失（正数=我会掉血）。
func _opponent_strike_threat(state: AIPlayer.AIGameState) -> float:
	var distance: int = _get_distance(state)
	var hand_counts := _opponent_hand_counts(state)  # 同名卡计数 → 判断对手能否 EX
	var worst_loss: float = 0.0
	for cid in state.opponent_state.hand:
		var opp_def = _get_def(cid, state)
		if opp_def == null:
			continue
		# 对手可 EX（两张同名卡）：四维 +1，否则 AI 低估对手的攻击/先手能力
		if int(hand_counts.get(cid, 0)) >= 2:
			opp_def = _apply_ex_to_def(opp_def)
		if not _range_hits(opp_def, distance):
			continue
		var my_net: int = _my_best_response_exchange(opp_def, state)
		var my_loss: float = float(-my_net)
		if my_loss > worst_loss:
			worst_loss = my_loss
	return worst_loss


## 对手的一张牌对我方的完整伤害（忽略我方护甲/霸体最坏情况）。
func _effective_power(opp_def: Dictionary) -> int:
	var p = opp_def.get("power", 0)
	return 0 if p is String else int(p)


# ============================================================
# 主回合决策
# ============================================================

func pick_turn_action(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	var state: AIPlayer.AIGameState = ai_game_state
	_sort_state = state
	_cache_state(state)
	# 10% 概率本回合抑制「非斩杀」的主动攻击
	_turn_skip_strike = randf() < 0.1

	# 近战型判定：牌库里能打到 4 距以上的牌 ≤ 2 张 → 积极贴脸逼近，移动上限放宽到 3 次
	_melee_mode = _long_range_card_count(state) <= 2
	_move_limit = MAX_MOVE_ACTIONS_MELEE if _melee_mode else MAX_MOVE_ACTIONS

	var my = state.my_state
	var opp_analysis: Dictionary = _opponent_can_do_now(state)
	# 对手下一回合若自由行动，对我造成的最大净伤害（前瞻核心）
	var opp_threat: float = _opponent_strike_threat(state)

	# ---- GG 专注 cancel 后必须开打：跳过搜索/加成/热身，直接强制攻击 ----
	if _just_canceled_gg_focus:
		_just_canceled_gg_focus = false
		var force_best = null
		var force_best_v: float = -999999.0
		for act in possible_actions:
			if not (act is AIPlayer.StrikeAction):
				continue
			if act.wild_swing or _is_block_card(act.card_id, state):
				continue
			if not can_card_hit(act.card_id, act.ex_card_id, state):
				continue
			var fv: float = _value_strike(act, state)
			if fv > force_best_v:
				force_best_v = fv
				force_best = act
		if force_best != null:
			print("[AI强制开打] GG专注 cancel 后强制攻击")
			_record_turn_history("strike", state)
			return force_best
		# 没有能打中的攻击牌 → 落到正常逻辑（逼近/蓄势）

	# ---- Carl Swangee 专属：贴身反击流主动特化（斩杀/摸牌/贴脸加成/ex dive）----
	if _is_carl(state):
		var carl_turn = _carl_turn(possible_actions, state)
		if carl_turn != null:
			return carl_turn

	# ---- 0) 多层搜索（困难/专家难度）：先跑 minimax，命中就直接用 ----
	if difficulty >= 2:
		var searched = search_best_action(possible_actions, state)
		if searched != null:
			if searched is AIPlayer.MoveAction and not _can_use_move():
				pass  # 移动次数用尽，忽略搜索结果，走启发式（会改走位移效果）
			elif searched is AIPlayer.StrikeAction and _turn_skip_strike and not (not searched.wild_swing and _can_kill(searched.card_id, searched.ex_card_id, state)):
				pass  # 本回合抑制主动攻击（斩杀除外），走启发式
			else:
				if searched is AIPlayer.MoveAction:
					_move_count += 1
				_record_turn_history("search", state)
				return searched

	# ---- 分类 ----
	var exceed_actions := []
	var strike_actions := []
	var boost_actions := []
	var move_actions := []
	var character_actions := []
	var change_actions := []
	var prepare_action = null
	var reshuffle_action = null
	for action in possible_actions:
		if action is AIPlayer.ExceedAction:
			exceed_actions.append(action)
		elif action is AIPlayer.StrikeAction:
			if action.wild_swing or can_card_hit(action.card_id, action.ex_card_id, state):
				strike_actions.append(action)
		elif action is AIPlayer.BoostAction:
			boost_actions.append(action)
		elif action is AIPlayer.MoveAction:
			move_actions.append(action)
		elif action is AIPlayer.PrepareAction:
			prepare_action = action
		elif action is AIPlayer.ReshuffleAction:
			reshuffle_action = action
		elif action is AIPlayer.CharacterActionAction:
			character_actions.append(action)
		elif action is AIPlayer.ChangeCardsAction:
			change_actions.append(action)

	# ---- 可命中的攻击（不含 wild swing、不含 block：block 不用于主动攻击）----
	var valid_strikes := []
	for sa in strike_actions:
		if not sa.wild_swing and not _is_block_card(sa.card_id, state):
			valid_strikes.append(sa)

	# ---- 1) 斩杀检查（克制感知：先手打断风险——对手更快且能命中时，低速斩杀牌会被打断）----
	var kill_strike = null
	for sa in valid_strikes:
		if not _can_kill(sa.card_id, sa.ex_card_id, state):
			continue
		var my_speed: int = _get_card_speed(sa.card_id, state, false)
		if sa.ex_card_id != -1:
			my_speed += 1
		# 斩杀安全条件：我能先手（平速发起者先手），或对手完全打不中我（无法打断）
		if my_speed >= int(opp_analysis.get("max_speed", 0)) or int(opp_analysis.get("can_hit_count", 0)) == 0:
			kill_strike = sa
			break
	if kill_strike != null:
		_record_turn_history("strike", state)
		return kill_strike

	# ---- 1.5) 手牌告急(≤3) → 强制补牌：只能 prepare/换牌/draw 加成，其余不准 ----
	if my.hand.size() <= 3:
		# 优先：换牌补到手牌 6（用怒气/ultra，ultra=2 force）
		var refill_change = _best_refill_change(change_actions, state)
		if refill_change != null:
			_record_turn_history("change", state)
			return refill_change
		# 其次：带 draw 的加成
		var draw_boost = _best_draw_boost(boost_actions, state)
		if draw_boost != null:
			_record_turn_history("boost", state)
			return draw_boost
		# 最后：热身
		if prepare_action != null:
			_record_turn_history("prepare", state)
			return prepare_action
		# 没有任何补牌手段 → 落到后续逻辑（无法补牌只能干别的）

	# ---- 2) 单方面命中：对手当前距离完全打不中我 → 白嫖伤害 ----
	if int(opp_analysis.get("can_hit_count", 0)) == 0 and valid_strikes.size() > 0 and not _turn_skip_strike:
		var best_uni = null
		var best_uni_v: float = -999999.0
		for sa in valid_strikes:
			var v: float = _value_strike(sa, state)
			if v > best_uni_v:
				best_uni_v = v
				best_uni = sa
		if best_uni != null and best_uni_v > 0.0:
			_record_turn_history("strike", state)
			return best_uni

	# ---- 3) 有利交换：worst-case 净交换为正（对手最克制我的牌也换不过我）----
	var best_strike = null
	var best_strike_exchange: int = -999
	for sa in valid_strikes:
		var e: int = int(_strike_worst_exchange(sa, state)["exchange"])
		if e > best_strike_exchange:
			best_strike_exchange = e
			best_strike = sa
	if best_strike != null and best_strike_exchange >= 2 and not _turn_skip_strike:
		_record_turn_history("strike", state)
		return best_strike

	# ---- 3.5) 生死防御：对手下回合能打死我，而我现在打不死他们 → 优先防守 ----
	if opp_threat >= float(my.life) and kill_strike == null:
		# 找防御牌：block / 高霸体（注意：block 允许在这里作为防御用，不是主动攻击）
		var best_def = null
		var best_def_v: float = -999999.0
		for sa in strike_actions:
			var sid: String = _get_card_id_str(sa.card_id, state).to_lower()
			var g: int = _get_card_guard(sa.card_id, state)
			if "block" in sid or g >= 4:
				var v: float = _value_strike(sa, state)
				if v > best_def_v:
					best_def_v = v
					best_def = sa
		if best_def != null:
			_record_turn_history("strike", state)
			return best_def

	# ---- 3.7) Reading 连招：专注加成时 75% 概率采用全知点名（父类成熟战术）----
	if boost_actions.size() > 0 and valid_strikes.size() > 0 and randf() < 0.75:
		var reading = _try_reading_combo(state, boost_actions, valid_strikes)
		if reading != null:
			_record_turn_history("boost", state)
			return reading

	# ---- 4) 够不着对手 → 想方设法逼近 ----
	var any_hit: bool = false
	for cid in my.hand:
		if can_card_hit(cid, -1, state):
			any_hit = true
			break
	if not any_hit:
		# 优先角色技能移动
		var best_move_ca = null
		var best_move_ca_v: float = -999999.0
		for ca in character_actions:
			var v: float = _value_character(ca, state)
			if v > best_move_ca_v:
				best_move_ca_v = v
				best_move_ca = ca
		if best_move_ca != null and best_move_ca_v > 6.0:
			_record_turn_history("character", state)
			return best_move_ca
		# 再考虑带位移的加成（近战型 AI 优先前进类加成，如 cross 前进 3 格）
		var best_move_boost = null
		var best_move_boost_v: float = -999999.0
		for ba in boost_actions:
			var has_mv: bool = _boost_has_effect(ba.card_id, state, ["advance", "retreat", "close", "move_to_any_space", "push", "pull"])
			var v: float = _value_boost(ba, state) + (15.0 if has_mv else 0.0)
			if _melee_mode and _boost_has_effect(ba.card_id, state, ["advance", "close"]):
				v += 25.0  # 近战型：前进类加成（cross advance 3）优先贴脸
			if v > best_move_boost_v:
				best_move_boost_v = v
				best_move_boost = ba
		if best_move_boost != null and best_move_boost_v > 8.0:
			_record_turn_history("boost", state)
			return best_move_boost
		# 最后普通移动（受移动次数限制，禁止后退：后退 _value_move 返回 -999）
		var best_move = null
		var best_move_v: float = -999999.0
		for ma in move_actions:
			var v: float = _value_move(ma, state)
			if v > best_move_v:
				best_move_v = v
				best_move = ma
		if best_move != null and best_move_v > -900.0 and _can_use_move():
			_move_count += 1
			_record_turn_history("move", state)
			return best_move

	# ---- 5.5) 牌库告急(≤13 张) → 主动重洗补充牌库 ----
	if reshuffle_action != null and my.deck.size() <= 13 and my.discards.size() > 0:
		_record_turn_history("reshuffle", state)
		return reshuffle_action

	# ---- 6) 变身（托内鲁斯除外：它的 exceed 会封印 transform，得不偿失）----
	if exceed_actions.size() > 0:
		var _deck_id: String = str(state.my_state.deck_def.get("id", ""))
		if _deck_id != "tournelouse":
			var my_profile: Dictionary = _get_character_profile(my, state)
			var exceed_threshold: int = 6
			if float(my_profile.get("aggro_score", 0.5)) >= 0.8:
				exceed_threshold = 5
			if my.hand.size() >= exceed_threshold:
				_record_turn_history("exceed", state)
				return exceed_actions[0]

	# ---- 7) 统一评估：攻击 vs 加成 vs 角色技能 vs 热身 ----
	# 关键前瞻：攻击动作已在本回合结算交换（_value_strike 含净交换）；
	# 而非攻击动作会让对手下一回合自由打我，需扣除 opp_threat。
	# 注意：不要过重，否则会把加成/热身全部压成负分，导致 AI 几乎不出加成。
	var passive_penalty: float = min(opp_threat * 2.0, 12.0)
	var candidates := []
	if best_strike != null and not _turn_skip_strike:
		candidates.append({"action": best_strike, "score": _value_strike(best_strike, state)})
	var best_boost = null
	var best_boost_v: float = -999999.0
	for ba in boost_actions:
		var v: float = _value_boost(ba, state)
		if v > best_boost_v:
			best_boost_v = v
			best_boost = ba
	if best_boost != null:
		candidates.append({"action": best_boost, "score": best_boost_v - passive_penalty})
	var best_ca = null
	var best_ca_v: float = -999999.0
	for ca in character_actions:
		var v: float = _value_character(ca, state)
		if v > best_ca_v:
			best_ca_v = v
			best_ca = ca
	if best_ca != null:
		candidates.append({"action": best_ca, "score": best_ca_v - passive_penalty})
	if prepare_action != null:
		candidates.append({"action": prepare_action, "score": _value_prepare(state) - passive_penalty})
	if change_actions.size() > 0 and my.hand.size() < 4:
		var best_change = null
		var best_change_v: float = -999999.0
		for ca2 in change_actions:
			var v: float = _value_change(ca2, state)
			if v > best_change_v:
				best_change_v = v
				best_change = ca2
		if best_change != null:
			candidates.append({"action": best_change, "score": best_change_v - passive_penalty})

	if candidates.size() > 0:
		candidates.sort_custom(_sort_by_score_desc)
		var top = candidates[0]
		# 专家难度：完全确定性取最优；低难度：在前 N 名里加入噪声
		if difficulty >= 3:
			return top["action"]
		var k: int = mini(candidates.size(), difficulty + 1)
		var idx: int = randi() % k
		return candidates[idx]["action"]

	# ---- 8) 兜底 ----
	if valid_strikes.size() > 0 and not _turn_skip_strike:
		_record_turn_history("strike", state)
		return best_strike if best_strike != null else valid_strikes[0]
	if reshuffle_action != null and my.deck.size() < 2 and my.discards.size() > 3 and my.hand.size() <= 3:
		return reshuffle_action
	if my.hand.size() <= 5:
		var draw_boost8 = _best_draw_boost(boost_actions, state)
		if draw_boost8 != null:
			_record_turn_history("boost", state)
			return draw_boost8
		if prepare_action != null:
			_record_turn_history("prepare", state)
			return prepare_action
	if best_boost != null:
		_record_turn_history("boost", state)
		return best_boost
	if best_ca != null:
		_record_turn_history("character", state)
		return best_ca
	# 优先移动加成，其次普通移动
	var move_boost = _best_move_boost(boost_actions, state)
	if move_boost != null:
		_record_turn_history("boost", state)
		return move_boost
	var best_move2 = null
	var best_move2_v: float = -999999.0
	for ma in move_actions:
		var v: float = _value_move(ma, state)
		if v > best_move2_v:
			best_move2_v = v
			best_move2 = ma
	if best_move2 != null and best_move2_v > -900.0 and _can_use_move():
		_move_count += 1
		_record_turn_history("move", state)
		return best_move2
	return possible_actions[randi() % possible_actions.size()]


# ============================================================
# 攻击选择（主动出击 / 被迫出击）
# ============================================================

## 用 maximin 策略选牌：对每张候选牌，算它对「对手最克制还击」的
## worst-case 交换，选 worst-case 最高的那张（最不会被克制）。
func pick_strike(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	var state: AIPlayer.AIGameState = ai_game_state
	_sort_state = state
	_cache_state(state)

	var best = null
	var best_v: float = -999999.0
	var wild = null
	for action in possible_actions:
		if not (action is AIPlayer.StrikeAction):
			continue
		if action.wild_swing:
			if wild == null:
				wild = action
			continue
		if not can_card_hit(action.card_id, action.ex_card_id, state):
			continue
		if _is_block_card(action.card_id, state):
			continue  # 不用 block 主动发起战斗（block 是防御/弃牌加成用途）
		var v: float = _value_strike(action, state)
		if v > best_v:
			best_v = v
			best = action
	if best != null:
		return best
	if wild != null:
		return wild
	return possible_actions[randi() % possible_actions.size()]


# ============================================================
# Carl Swangee（第二季）专属策略：贴身反击流
# 被动：对手 special 时我方护甲+1；觉醒后 normal 威力+2
# 核心：不主动攻击，贴身后用克制牌反击；special 优先干扰/回收
# ============================================================

func _is_carl(state: AIPlayer.AIGameState) -> bool:
	return str(state.my_state.deck_def.get("id", "")) == "carlswangee"

## 我方牌型 key
func _carl_key(card_id: int, state: AIPlayer.AIGameState) -> String:
	var s: String = _get_card_id_str(card_id, state).to_lower()
	if "grasp" in s or "throw" in s: return "grasp"
	if "cross" in s: return "cross"
	if "sweep" in s: return "sweep"
	if "focus" in s: return "focus"
	if "spike" in s or "dust" in s: return "spike"
	if "assault" in s: return "assault"
	if "dive" in s: return "dive"
	if "block" in s: return "block"
	if "disarming" in s: return "disarming"
	if "improvised" in s: return "improvised"
	if "cease" in s: return "cease"
	if "powershort" in s: return "powershort"
	if "elbow" in s: return "elbow"
	if "autonomic" in s: return "autonomic"
	if "authorized" in s: return "authorized"
	return "other"

## 对手攻击牌型 key
func _carl_opp_key(opp: Dictionary) -> String:
	if opp.get("is_throw", false): return "grasp"
	if opp.get("is_cross", false): return "cross"
	if opp.get("is_sweep", false): return "sweep"
	if opp.get("is_focus", false): return "focus"
	if opp.get("is_spike", false): return "spike"
	if opp.get("is_assault", false): return "assault"
	if "dive" in str(opp.get("id_str", "")): return "dive"
	if opp.get("is_block", false): return "block"
	return "other"

## 我方 retreat 受场地边界限制的最大后退量
func _carl_retreat_cap(state: AIPlayer.AIGameState) -> int:
	var my_loc: int = state.my_state.arena_location
	var opp_loc: int = state.opponent_state.arena_location
	if my_loc < opp_loc:
		return my_loc - Enums.MinArenaLocation
	return Enums.MaxArenaLocation - my_loc

## Carl 反击计划：按 距离 + 对手牌型 + 是否ex 返回候选 spec 列表。
## spec: "key"=普通牌 / "key:ex"=ex攻击 / "key:dodge"=需能躲开 / "highspeed"=高速换血
func _carl_plan(distance: int, opp_key: String, opp_is_ex: bool) -> Array:
	match opp_key:
		"grasp":
			if distance <= 1:
				return ["cease", "powershort", "sweep", "focus", "grasp:ex"]
		"cross":
			if distance <= 1:
				return ["grasp", "cross:ex"]
			if distance == 2:
				return ["cross:ex", "block"]
		"sweep":
			if opp_is_ex:
				return []
			if distance == 1:
				return ["cease", "powershort", "elbow", "cross:dodge", "sweep:ex", "focus", "dive", "highspeed"]
			if distance == 2:
				return ["cease", "powershort", "spike", "cross:dodge", "sweep:ex", "focus", "dive", "highspeed"]
			if distance == 3:
				return ["cease", "dive", "spike", "sweep:ex", "focus", "cross:dodge", "highspeed"]
		"focus":
			if distance == 1:
				return ["elbow", "sweep", "powershort", "cross"]
			if distance == 2:
				return ["spike", "sweep", "powershort", "cross"]
		"spike":
			if distance == 2:
				return ["disarming", "assault", "cross", "spike:ex", "dive"]
			if distance == 3:
				return ["disarming", "assault", "dive", "spike:ex", "cross"]
		"assault":
			if distance >= 1 and distance <= 3:
				if opp_is_ex:
					return ["sweep", "focus", "cease", "powershort"]
				return ["disarming", "assault:ex", "sweep", "focus", "cease", "powershort", "improvised"]
		"dive":
			if distance == 3:
				if opp_is_ex:
					return ["disarming", "assault:ex", "block", "cross"]
				return ["disarming", "dive:ex", "assault", "improvised"]
			if distance == 4:
				if opp_is_ex:
					return ["cease", "sweep", "focus"]
				return ["cease", "powershort", "sweep", "focus", "improvised", "dive:ex"]
	return []

## 按 spec 从 possible_actions 找匹配动作（必须能击中对手；可选需 ex / 需能躲开）
func _carl_find(possible_actions: Array, state: AIPlayer.AIGameState, key: String, require_ex: bool, opp_def: Dictionary, distance: int, cap: int, need_dodge: bool):
	for action in possible_actions:
		if not (action is AIPlayer.StrikeAction):
			continue
		if action.wild_swing:
			continue
		if _carl_key(action.card_id, state) != key:
			continue
		if require_ex != (action.ex_card_id != -1):
			continue
		if need_dodge and not _retreat_safe(action.card_id, state):
			continue
		var my_def: Dictionary = _effective_strike_def(action, state)
		if my_def.is_empty():
			continue
		var e: Dictionary = _eval_counter_response(my_def, opp_def, distance, true, cap)
		if not e.get("my_hit", false):
			continue
		return action
	return null

## 高速换血：能击中对手的牌里选速度最快的
func _carl_highspeed(possible_actions: Array, state: AIPlayer.AIGameState, opp_def: Dictionary, distance: int, cap: int):
	var best = null
	var best_speed: int = -1
	for action in possible_actions:
		if not (action is AIPlayer.StrikeAction):
			continue
		if action.wild_swing:
			continue
		var key: String = _carl_key(action.card_id, state)
		if key in ["block", "autonomic"]:
			continue
		var my_def: Dictionary = _effective_strike_def(action, state)
		if my_def.is_empty():
			continue
		var e: Dictionary = _eval_counter_response(my_def, opp_def, distance, true, cap)
		if not e.get("my_hit", false):
			continue
		var spd = my_def.get("speed", 0)
		if spd is String: spd = 20
		if int(spd) > best_speed:
			best_speed = int(spd)
			best = action
	return best

## Carl 专属应战决策（贴手反击流）
func _carl_response(possible_actions: Array, state: AIPlayer.AIGameState):
	var opp: Dictionary = _analyze_opponent_strike(state)
	if not opp.get("has_strike", false):
		return null
	var opp_def: Dictionary = opp.get("defn", {})
	if opp_def.is_empty():
		return null
	var distance: int = _get_distance(state)
	var opp_is_ex: bool = opp.get("ex_card_id", -1) != -1
	var opp_key: String = _carl_opp_key(opp)
	var opp_speed: int = int(opp.get("speed", 0))
	var cap: int = _carl_retreat_cap(state)
	var gauge: int = state.my_state.gauge.size()
	var wild = null
	for a in possible_actions:
		if a is AIPlayer.StrikeAction and a.wild_swing:
			wild = a
			break

	# 最高优先①：autonomicresponse 反制 normal（非 dive/cross），1~3 距 + 怒气≥2
	if distance >= 1 and distance <= 3 and opp.get("type", "") == "normal" \
			and opp_key not in ["dive", "cross"] and gauge >= 2:
		for a in possible_actions:
			if a is AIPlayer.StrikeAction and not a.wild_swing and _carl_key(a.card_id, state) == "autonomic":
				var md: Dictionary = _effective_strike_def(a, state)
				var me: Dictionary = _eval_counter_response(md, opp_def, distance, true, cap)
				if me.get("my_hit", false):
					return a

	# 最高优先②：authorizedforce 反制（1距 + 玩家<6速 + 怒气≥4）
	if distance == 1 and opp_speed < 6 and gauge >= 4:
		for a in possible_actions:
			if a is AIPlayer.StrikeAction and not a.wild_swing and _carl_key(a.card_id, state) == "authorized":
				return a

	# 映射表
	var plan: Array = _carl_plan(distance, opp_key, opp_is_ex)
	for spec in plan:
		var s: String = str(spec)
		if s == "highspeed":
			var hs = _carl_highspeed(possible_actions, state, opp_def, distance, cap)
			if hs != null:
				return hs
			continue
		var key: String = s
		var require_ex: bool = false
		var need_dodge: bool = false
		if s.ends_with(":ex"):
			key = s.trim_suffix(":ex")
			require_ex = true
		elif s.ends_with(":dodge"):
			key = s.trim_suffix(":dodge")
			need_dodge = true
		var act = _carl_find(possible_actions, state, key, require_ex, opp_def, distance, cap, need_dodge)
		if act != null:
			return act

	# 兜底：先作弊换牌（偷牌库里的反击牌），再 wild
	var cheat = _try_cheat_response(state)
	if cheat != null:
		return cheat
	return wild

## Carl 专属主动攻击特化（贴身反击流：克制主动攻击）
func _carl_turn(possible_actions: Array, state: AIPlayer.AIGameState):
	var distance: int = _get_distance(state)
	var gauge: int = state.my_state.gauge.size()
	var opp_analysis: Dictionary = _analyze_opponent_at_distance(distance, state)
	var opp_max_speed: int = int(opp_analysis.get("max_speed", 0))

	# 1) authorizedforce 斩杀：1距 + 怒气≥4 + 对手无>5速牌 → 最高优先主动攻击
	if distance == 1 and gauge >= 4 and opp_max_speed <= 5:
		for a in possible_actions:
			if a is AIPlayer.StrikeAction and not a.wild_swing and _carl_key(a.card_id, state) == "authorized":
				_record_turn_history("strike", state)
				return a

	# 2) 贴身 1距：手牌 <6 优先热身摸牌
	if distance == 1 and state.my_state.hand.size() < 6:
		for a in possible_actions:
			if a is AIPlayer.PrepareAction:
				_record_turn_history("prepare", state)
				return a

	# 3) 远距离：优先用 cross/disarming/cease 加成贴脸
	if distance >= 3:
		var best_mb = null
		var best_mb_v: float = -999999.0
		for a in possible_actions:
			if a is AIPlayer.BoostAction:
				var key: String = _carl_key(a.card_id, state)
				if key in ["cross", "disarming", "cease"]:
					var v: float = _value_boost(a, state)
					if v > best_mb_v:
						best_mb_v = v
						best_mb = a
		if best_mb != null:
			_record_turn_history("boost", state)
			return best_mb

	# 4) 4距 对手无>5速牌 → ex dive 主动进攻
	if distance == 4 and opp_max_speed <= 5:
		for a in possible_actions:
			if a is AIPlayer.StrikeAction and not a.wild_swing \
					and _carl_key(a.card_id, state) == "dive" and a.ex_card_id != -1:
				_record_turn_history("strike", state)
				return a

	return null


## 作弊换牌：应战兜底（本要 wild swing）时，从牌库偷一张能有效反击的牌，
## 并把手里价值最低的废牌无痕塞回牌库（直接操作数组，不触发事件，玩家察觉不到）。
## 每局最多 CHEAT_SWAP_MAX 次。返回一个 StrikeAction，或 null（不换）。
func _try_cheat_response(state: AIPlayer.AIGameState):
	if _cheat_swap_count >= CHEAT_SWAP_MAX:
		return null
	var opp: Dictionary = _analyze_opponent_strike(state)
	if not opp.get("has_strike", false):
		return null
	var opp_def: Dictionary = opp.get("defn", {})
	if opp_def.is_empty():
		return null
	var distance: int = _get_distance(state)
	var my_loc: int = state.my_state.arena_location
	var opp_loc: int = state.opponent_state.arena_location
	var cap: int = (my_loc - Enums.MinArenaLocation) if my_loc < opp_loc else (Enums.MaxArenaLocation - my_loc)
	var real = state.player  # 真实 Player（可改 hand/deck）
	if real == null or real.deck.is_empty():
		return null

	# 从牌库找能有效反击的牌：能命中 + 净交换最优 + 付得起怒气
	var best_card = null
	var best_v: float = -1e9
	for card in real.deck:
		var def: Dictionary = card.definition
		var gc = def.get("gauge_cost", 0)
		if int(gc) > state.my_state.gauge.size():
			continue
		var adef: Dictionary = _apply_boost_stats(def, state, false)
		var e: Dictionary = _eval_counter_response(adef, opp_def, distance, true, cap)
		if not e.get("my_hit", false):
			continue
		var v: float = float(e.get("exchange", -99)) * EXCHANGE_WEIGHT
		if e.get("stunned", false):
			v += 25.0
		if not e.get("opp_hit", false):
			v += 10.0
		if v > best_v:
			best_v = v
			best_card = card
	if best_card == null:
		return null

	# 找手里价值最低的废牌（优先 block，其次低 force 的 normal）
	var worst_card = null
	var worst_v: float = 1e9
	for card in real.hand:
		var def: Dictionary = card.definition
		var sid: String = str(def.get("id", "")).to_lower()
		var v: float = 0.0
		if "block" in sid:
			v = -50.0  # block 应战兜底时最没价值，最优先牺牲
		else:
			v = float(state.card_db.get_card_force_value(card.id)) * 10.0
			if def.get("type", "") != "normal":
				v += 20.0  # special/ultra 是核心牌，尽量不牺牲
		if v < worst_v:
			worst_v = v
			worst_card = card
	if worst_card == null or worst_card.id == best_card.id:
		return null

	# 无痕置换：直接操作数组（不触发任何事件）
	real.deck.erase(best_card)
	real.hand.erase(worst_card)
	real.deck.append(worst_card)
	real.hand.append(best_card)

	_cheat_swap_count += 1
	return AIPlayer.StrikeAction.new(best_card.id, -1, false)


## 应战：三级决策——先手打断 → 预判落位反击 → 疯狂攻击兜底。
## 1) 先手打断：速度严格快于对手、且当前距离（或我 before 拉近后）能命中 → 我先手打断。
## 2) 预判落位反击：对手先手会 advance/close 落地，我用「落位能命中 + 霸体够不被击晕」的牌反击；
##    block 挡全（对手不破防时零损）也归这一级，但斩杀威胁时 block 保命优先。
## 3) 疯狂攻击兜底：任何牌都无法有效反击 → wild swing 节约手牌。
func pick_strike_response(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	var state: AIPlayer.AIGameState = ai_game_state
	_sort_state = state
	_cache_state(state)

	# Carl Swangee 专属：贴身反击流（映射表 + 反制优先）
	if _is_carl(state):
		var carl_resp = _carl_response(possible_actions, state)
		if carl_resp != null:
			return carl_resp

	var opp_strike: Dictionary = _analyze_opponent_strike(state)
	var opp_def: Dictionary = opp_strike.get("defn", {}) if opp_strike.get("has_strike", false) else {}
	var opp_can_kill: bool = opp_strike.get("can_kill_me", false)
	var opp_speed: int = int(opp_strike.get("speed", 0))
	var opp_power: int = int(opp_strike.get("power", 0))
	var opp_ignore_guard: bool = opp_strike.get("has_ignore_guard", false)
	var distance: int = _get_distance(state)
	# 我方 retreat 受场地边界的最大后退量（用于「位移闪避」可行性判定：边缘退不满）
	var my_retreat_cap: int = -1  # -1 = 不限制
	var _my_loc: int = state.my_state.arena_location
	var _opp_loc: int = state.opponent_state.arena_location
	if _my_loc < _opp_loc:
		my_retreat_cap = _my_loc - Enums.MinArenaLocation
	else:
		my_retreat_cap = Enums.MaxArenaLocation - _my_loc

	var interrupt = null          # 第一级：先手打断
	var interrupt_v: float = -_SEARCH_INF
	var counter = null            # 第二级：预判落位反击（带来收益）
	var counter_v: float = -_SEARCH_INF
	var block = null              # 第二级：block 挡全（减少损失）
	var block_v: float = -_SEARCH_INF
	var wild = null               # 第三级：疯狂攻击
	var any_response = null       # 兜底：无对手信息时按主动攻击价值
	var any_response_v: float = -_SEARCH_INF

	for action in possible_actions:
		if not (action is AIPlayer.StrikeAction):
			continue
		if action.wild_swing:
			if wild == null:
				wild = action
			continue
		var my_def: Dictionary = _effective_strike_def(action, state)
		if my_def.is_empty():
			continue

		if opp_def.is_empty():
			var v0: float = _value_strike(action, state)
			if v0 > any_response_v:
				any_response_v = v0
				any_response = action
			continue

		var my_speed = my_def.get("speed", 0)
		if my_speed is String: my_speed = 20
		var my_guard = my_def.get("guard", 0)
		if my_guard is String: my_guard = 0
		var is_block: bool = _is_block_card(action.card_id, state)

		# ---- block：格挡挡全（对手不破防时零损吃下）----
		if is_block:
			var bv: float
			if opp_ignore_guard:
				# 对手破防：block 无法免疫，只能靠护甲减伤 → 价值有限
				bv = float(max(opp_power - _get_card_armor(action.card_id, state), 0)) * 8.0 + 4.0
			else:
				bv = float(opp_power) * 10.0 + 12.0
				if opp_power >= 4:
					bv += 12.0   # 高伤害，挡下很值
				if opp_can_kill:
					bv += 50.0   # 对手能斩杀我 → 保命压倒一切
			if bv > block_v:
				block_v = bv
				block = action
			continue

		# ---- 先手打断：速度严格快于对手，且先手能命中 → 才算有效打断 ----
		var e: Dictionary = _eval_counter_response(my_def, opp_def, distance, true, my_retreat_cap)
		if my_speed > opp_speed and e.get("my_hit", false):
			var iv: float = float(e.get("exchange", -99)) * EXCHANGE_WEIGHT
			if e.get("stunned", false):
				iv += 25.0       # 我先手击晕 → 对手整张牌作废
			if not e.get("opp_hit", false):
				iv += 10.0       # 单方面命中
			iv += 15.0           # 先手打断的主动性收益
			if iv > interrupt_v:
				interrupt_v = iv
				interrupt = action
			continue

		# ---- 预判落位反击：必须「能命中对手」才有反击价值（打不中的牌不如省手牌）----
		if e.get("my_hit", false):
			var cv: float = float(e.get("exchange", -99)) * EXCHANGE_WEIGHT
			if e.get("stunned", false):
				cv += 25.0       # 反击击晕对手
			if not e.get("opp_hit", false):
				cv += 10.0       # 单方面命中
			cv += 8.0            # 预判落位反击成功
			# 霸体够硬，不被对手先手击晕 → 反击更稳
			if my_guard >= opp_power:
				cv += 12.0
			# 对手能斩杀我 → 高霸体防御额外加分
			if opp_can_kill and my_guard >= 4:
				cv += 20.0
			# 抽牌/弃对手牌等效用
			for ef in my_def.get("effects", []):
				var et: String = str(ef.get("effect_type", ""))
				if et == "draw":
					cv += int(ef.get("amount", 1)) * 6.0
				elif et == "opponent_discard_random":
					cv += int(ef.get("amount", 1)) * 5.0
			if cv > counter_v:
				counter_v = cv
				counter = action
		# 兜底：记录交换值最高的牌（含打不中的），作为「无有效反击」时的最后手段
		var any_v: float = float(e.get("exchange", -99)) * EXCHANGE_WEIGHT
		if any_v > any_response_v:
			any_response_v = any_v
			any_response = action

	# === 三级决策 ===
	# 1) 先手打断（最主动，最高优先）
	if interrupt != null:
		return interrupt
	# 2a) 对手能斩杀我 → block 保命优先于反击
	if opp_can_kill and block != null:
		return block
	# 2b) 预判落位反击（能命中对手，带来收益）
	if counter != null:
		return counter
	# 2c) block 挡全（减少损失）
	if block != null:
		return block
	# 3) 疯狂攻击：无有效反击 → 先作弊换牌（偷牌库里的反击牌），再 wild swing
	if wild != null:
		var cheat = _try_cheat_response(state)
		if cheat != null:
			return cheat
		return wild
	# 4) 最后兜底：打不中的牌（比 wild 还差，只在无 wild 时用）
	if any_response != null:
		return any_response
	return possible_actions[randi() % possible_actions.size()]


## 花力槽换护甲：每次防御（尤其格挡）时，加护甲直到会受到的伤害 ≤ 1。
## 与父类相比：读真实的「每点能量换多少护甲」（decision_info.amount），
## 而非硬编码 +2，并明确以「伤害≤1」为目标。
func pick_force_for_armor(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	var state: AIPlayer.AIGameState = ai_game_state

	# 支付模式: "force"(弃牌支付) 或 "gauge"(怒气支付, 每张怒气牌=1能量)
	var is_gauge_mode: bool = false
	var gl = state.true_original()
	if gl and gl.decision_info and gl.decision_info.limitation == "gauge":
		is_gauge_mode = true

	# 兜底：支付 0（不弃牌、不用免费能量）
	var min_action = null
	for action in possible_actions:
		if action is AIPlayer.ForceForArmorAction and action.card_ids.size() == 0 and not action.use_free_force:
			min_action = action
			break
	if min_action == null:
		for action in possible_actions:
			if action is AIPlayer.ForceForArmorAction:
				min_action = action
				break
	if min_action == null:
		return possible_actions[0]

	# 没有正在进行的打击 / 对手无视护甲 → 不支付
	var opp_strike: Dictionary = _analyze_opponent_strike(state)
	if not opp_strike.get("has_strike", false):
		print("[AI护甲] 未识别到对手攻击(has_strike=false) — 不支付能量")
		return min_action
	if opp_strike.get("has_ignore_armor", false):
		print("[AI护甲] 对手无视护甲 — 不支付能量")
		return min_action

	# 对手最终威力（含对手加成区 during_strike 的 powerup）
	var opp_power: int = int(opp_strike.get("power", 0))
	for bid in state.opponent_state.continuous_boosts:
		var bc = state.card_db.get_card(bid)
		if bc and bc.definition:
			for bef in bc.definition.get("boost", {}).get("effects", []):
				if bef.get("timing") == "during_strike" and bef.get("effect_type") == "powerup":
					opp_power += int(bef.get("amount", 0))

	# 我方当前护甲（防守牌护甲 + EX +1 + 我方加成区 during_strike 的 armorup）
	var my_armor: int = 0
	var did: int = state.active_strike.defender_card_id
	if did != -1:
		my_armor = _get_card_armor(did, state)
		if state.active_strike.defender_ex_card_id != -1:
			my_armor += 1
	for bid in state.my_state.continuous_boosts:
		var bc = state.card_db.get_card(bid)
		if bc and bc.definition:
			for bef in bc.definition.get("boost", {}).get("effects", []):
				if bef.get("timing") == "during_strike" and bef.get("effect_type") == "armorup":
					my_armor += int(bef.get("amount", 0))

	# 每点能量换多少护甲（读实际值，兜底 2）
	var apf := 2
	if gl and gl.decision_info and int(gl.decision_info.amount) > 0:
		apf = int(gl.decision_info.amount)

	# 目标：伤害 ≤ 1
	var need_armor: int = max(opp_power - 1 - my_armor, 0)
	if need_armor <= 0:
		return min_action
	var force_needed: int = int(ceil(float(need_armor) / float(apf)))

	# 自身力槽减免 + 免费能量
	var my_real = state.my_state.true_original()
	var base_force := 0
	var free_force := 0
	if my_real:
		base_force = int(my_real.force_cost_reduction)
		free_force = int(my_real.free_force)
	if force_needed <= base_force:
		return min_action

	# 计算某个支付方案实际产生的「能量」值
	var _fg_of = func(action) -> int:
		if is_gauge_mode:
			return action.card_ids.size()  # 怒气: 每张牌=1能量
		var fg: int = base_force
		if action.use_free_force:
			fg += free_force
		for cid in action.card_ids:
			fg += state.card_db.get_card_force_value(cid)
		return fg

	# 选支付方案：恰好达标 / 最小溢出 / 尽量接近
	var exact = null
	var over = null
	var over_fg := 999
	for action in possible_actions:
		if not (action is AIPlayer.ForceForArmorAction):
			continue
		var fg: int = _fg_of.call(action)
		if fg == force_needed:
			if exact == null or action.card_ids.size() < exact.card_ids.size():
				exact = action
		elif fg > force_needed and fg < over_fg:
			over_fg = fg
			over = action
	if exact != null:
		print("[AI护甲] 对手威力%d 我方护甲%d → 支付%d能量(+%d甲) 压到≤1点伤害" % [opp_power, my_armor, force_needed, force_needed * apf])
		return exact
	if over != null:
		print("[AI护甲] 对手威力%d 我方护甲%d → 溢出支付%d能量" % [opp_power, my_armor, over_fg])
		return over
	# 能量不够达标 → 取支付最多能量的方案（尽量接近目标）
	var best = null
	var best_fg := -1
	for action in possible_actions:
		if not (action is AIPlayer.ForceForArmorAction):
			continue
		var fg: int = _fg_of.call(action)
		if fg > best_fg:
			best_fg = fg
			best = action
	if best_fg > 0:
		print("[AI护甲] 能量不足(需%d)，支付最多%d能量" % [force_needed, best_fg])
	return best if best != null else min_action


## 加成选择：确定性地选评分最高的那张（父类这里带随机）。
func pick_boost_action(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	if possible_actions.size() == 1:
		return possible_actions[0]
	var state: AIPlayer.AIGameState = ai_game_state
	_sort_state = state
	var best = possible_actions[0]
	var best_v: float = -999999.0
	for action in possible_actions:
		var v: float = _score_boost(action, state)
		if v > best_v:
			best_v = v
			best = action
	return best


## 加成取消决策：GG 专注（gg_normal_focus）用完一定要 cancel（花 1 怒气）。
func pick_cancel(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	var state: AIPlayer.AIGameState = ai_game_state
	var gl = state.true_original()
	if gl and gl.active_boost and gl.active_boost.card:
		var bid: String = str(gl.active_boost.card.definition.get('id', ''))
		if bid == "gg_normal_focus":
			# 用完必 cancel：挑一个 cancel=true 的动作（尽量少花怒气卡）
			var best_cancel = null
			var best_cnt := 999
			for action in possible_actions:
				if action is AIPlayer.CancelAction and action.cancel:
					if action.card_ids.size() < best_cnt:
						best_cnt = action.card_ids.size()
						best_cancel = action
			if best_cancel != null:
				_just_canceled_gg_focus = true  # cancel 后下一次行动必须开打
				return best_cancel
	return super.pick_cancel(possible_actions, ai_game_state)


## 覆写点名：block 的 Parry 加成（name_card_opponent_discards）要精确处理
## 对手对 AI 威胁最大的卡（无法反击的高速卡 / 高伤害卡），Reading 走父类。
func pick_name_opponent_card(possible_actions: Array, ai_game_state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	var state: AIPlayer.AIGameState = ai_game_state
	_cache_state(state)
	var distance: int = _get_distance(state)

	# 上下文检测：Parry（可点任意类型，含 special/ultra）vs Reading（只点 normal）
	var is_reading_context: bool = true
	for action in possible_actions:
		if action is AIPlayer.NameCardAction:
			var defn = _get_def(action.card_id, state)
			if defn and defn.get("type", "") != "normal":
				is_reading_context = false
				break

	# Reading（专注加成）走父类成熟逻辑（20%全知 / 80%推断）
	if is_reading_context:
		return super.pick_name_opponent_card(possible_actions, ai_game_state)

	# 对手手牌 id 集合（用于判断候选牌是否真在对手手里）
	var in_hand_names: Array = []
	for cid in state.opponent_state.hand:
		var d = _get_def(cid, state)
		if d:
			in_hand_names.append(d.get("id", ""))

	# 我方最快速度（用于判断对手哪张高速卡「我无法先手反击」）
	var my_max_speed: int = 0
	for cid in state.my_state.hand:
		var ms = _get_card_speed(cid, state)
		if ms > my_max_speed:
			my_max_speed = ms

	# Parry 场景：精确点「威胁最大」的卡
	var scored := []
	for action in possible_actions:
		if not (action is AIPlayer.NameCardAction):
			continue
		var defn = _get_def(action.card_id, state)
		if defn == null:
			continue
		var def_id: String = defn.get("id", "")
		var s: float = 0.0
		if def_id in in_hand_names:
			s += 30.0
			var spd = defn.get("speed", 0)
			var pwr = defn.get("power", 0)
			if spd is String: spd = 0
			if pwr is String: pwr = 0
			s += int(spd) * 4.0     # 高速卡威胁最大
			s += int(pwr) * 2.5    # 高伤害卡
			var ctype: String = defn.get("type", "")
			match ctype:
				"ultra": s += 14.0
				"special": s += 7.0
				_: s += 1.0
			# 射程内（对手当前能用它打中我）→ 威胁更大
			var rmin = defn.get("range_min", 1)
			var rmax = defn.get("range_max", rmin + 3)
			if rmin is String: rmin = 1
			if rmax is String: rmax = rmin + 3
			if int(rmin) <= distance and distance <= int(rmax):
				s += 12.0
			# 速度快到我完全无法先手反击 → 最该处理掉
			if int(spd) > my_max_speed:
				s += 15.0
		else:
			s -= 20.0  # 不在对手手里，点了没用
		scored.append({"action": action, "score": s})

	if scored.is_empty():
		return possible_actions[randi() % possible_actions.size()]
	scored.sort_custom(_sort_by_score_desc)
	if scored[0]["score"] > 0.0:
		return scored[0]["action"]
	return possible_actions[randi() % possible_actions.size()]


# ============================================================
# 多层搜索（minimax + α-β 剪枝，粗粒度前向模型）
# ============================================================
# 全知+1层前瞻只能「看清对手下一招」，真正的棋感来自往前推演多条线。
# 这里用一个「决策相关的轻量棋盘」做有限深度搜索：
#   建模   = 位置 / 血量 / 手牌 / 力槽数 / 加成数 / 变身态
#   攻击   = 复用父类 _eval_counter_response（忠于真实规则）
#   抽牌   = 用「期望卡」近似，限制深度避免误差累积
# 迭代加深：从 MIN 层逐层加深到 MAX 层，每层间受时间预算约束，
# 超时就退回上一层结果，兼顾「看得深」与「不卡顿」。

const SEARCH_MIN_DEPTH := 2
const SEARCH_MAX_DEPTH := 4
const SEARCH_TIME_BUDGET_MS := 45
const SEARCH_STRIKE_BRANCH := 4   # 每方最多考虑前 N 张攻击牌
const SEARCH_MOVE_BRANCH := 3     # 每方最多考虑前 N 个移动落点
const _SEARCH_INF := 1.0e9


func _sd_power(d: Dictionary) -> int:
	var v = d.get("power", 0)
	return 0 if v is String else int(v)


func _ss_make(state: AIPlayer.AIGameState) -> Dictionary:
	var s := {}
	s["my_loc"] = state.my_state.arena_location
	s["opp_loc"] = state.opponent_state.arena_location
	s["my_life"] = state.my_state.life
	s["opp_life"] = state.opponent_state.life
	var mh := []
	for cid in state.my_state.hand:
		var d = _get_def(cid, state)
		if d != null:
			mh.append(d)
	s["my_hand"] = mh
	var oh := []
	for cid in state.opponent_state.hand:
		var d = _get_def(cid, state)
		if d != null:
			oh.append(d)
	s["opp_hand"] = oh
	s["my_gauge"] = state.my_state.gauge.size()
	s["opp_gauge"] = state.opponent_state.gauge.size()
	s["my_boosts"] = state.my_state.continuous_boosts.size()
	s["opp_boosts"] = state.opponent_state.continuous_boosts.size()
	s["my_exceeded"] = state.my_state.exceeded
	s["opp_exceeded"] = state.opponent_state.exceeded
	return s


func _ss_dist(s: Dictionary) -> int:
	return abs(int(s["my_loc"]) - int(s["opp_loc"]))


func _ss_eval(s: Dictionary, my_class: String, opp_class: String) -> float:
	var sc := 0.0
	sc += (int(s["my_life"]) - int(s["opp_life"])) * 10.0
	if int(s["opp_life"]) <= 5:
		sc += (6 - int(s["opp_life"])) * 12.0
	if int(s["my_life"]) <= 5:
		sc -= (6 - int(s["my_life"])) * 16.0
	var ideal: int = _get_ideal_distance(my_class, opp_class)
	sc -= abs(_ss_dist(s) - ideal) * 4.0
	sc += (s["my_hand"].size() - s["opp_hand"].size()) * 2.5
	sc += (int(s["my_gauge"]) - int(s["opp_gauge"])) * 1.5
	sc += (int(s["my_boosts"]) - int(s["opp_boosts"])) * 4.0  # 加成价值（持续效果）
	if s["my_exceeded"] and not s["opp_exceeded"]:
		sc += 18.0
	if not s["my_exceeded"] and s["opp_exceeded"]:
		sc -= 18.0
	return sc


func _dummy_card() -> Dictionary:
	return {
		"id": "search_dummy", "type": "normal",
		"speed": 3, "power": 3, "guard": 2, "armor": 0,
		"range_min": 1, "range_max": 3, "effects": [],
	}


## 攻击方用 striker_def 发起，防守方选最优还击，返回「我方视角」的分值。
func _ss_strike_card_value(s: Dictionary, striker_def: Dictionary, is_me: bool) -> float:
	var defender_hand = s["opp_hand"] if is_me else s["my_hand"]
	var dist: int = _ss_dist(s)
	var worst: int = 999
	var has_resp: bool = false
	for dd in defender_hand:
		if not _range_hits(dd, dist):
			continue
		var e: Dictionary = _eval_counter_response(striker_def, dd, dist, false)
		var ex: int = int(e.get("exchange", -99))
		if ex < worst:
			worst = ex
		has_resp = true
	if not has_resp:
		worst = _sd_power(striker_def)  # 防守方打不中，攻方白打
	var my_net: int = worst if is_me else -worst
	return float(my_net) * EXCHANGE_WEIGHT


## 攻击方从手里选「交换价值最高」的那张攻击（对手视角已换算成我方分值）。
func _ss_strike_best_value(s: Dictionary, is_me: bool) -> float:
	var hand = s["my_hand"] if is_me else s["opp_hand"]
	var dist: int = _ss_dist(s)
	var best: float = -_SEARCH_INF
	for d in hand:
		if not _range_hits(d, dist):
			continue
		var v: float = _ss_strike_card_value(s, d, is_me)
		if v > best:
			best = v
	return best


## 粗粒度应用动作到搜索棋盘，返回新棋盘（复制）。
func _ss_apply(s: Dictionary, a: Dictionary, is_me: bool) -> Dictionary:
	var ns: Dictionary = s.duplicate(true)
	var hand_key := "my_hand" if is_me else "opp_hand"
	var boost_key := "my_boosts" if is_me else "opp_boosts"
	var gauge_key := "my_gauge" if is_me else "opp_gauge"
	var loc_key := "my_loc" if is_me else "opp_loc"
	var exc_key := "my_exceeded" if is_me else "opp_exceeded"
	match a["type"]:
		"move":
			ns[loc_key] = a["loc"]
		"boost":
			var h: Array = ns[hand_key].duplicate()
			if h.size() > 0:
				h.pop_front()
			ns[hand_key] = h
			ns[boost_key] = int(ns[boost_key]) + 1
			# 应用加成的主要效果（粗略）：抽牌 / 位移
			var bd = a.get("card", {})
			if bd is Dictionary and not bd.is_empty():
				var boost = bd.get("boost", {})
				for be in boost.get("effects", []):
					var et: String = str(be.get("effect_type", ""))
					var amt = be.get("amount", 1)
					if amt is String:
						amt = 1
					if et == "draw":
						for i in range(int(amt)):
							h.append(_dummy_card())
						ns[hand_key] = h
					elif et == "advance" or et == "close":
						_ss_move(ns, is_me, int(amt))
					elif et == "retreat":
						_ss_move(ns, is_me, -int(amt))
		"prepare":
			var h2: Array = ns[hand_key].duplicate()
			h2.append(_dummy_card())
			ns[hand_key] = h2
		"exceed":
			ns[exc_key] = true
			ns[gauge_key] = max(int(ns[gauge_key]) - 2, 0)
		"character":
			pass
	return ns


## 搜索棋盘里移动「当前行动方」：toward>0 朝对手靠拢，<0 远离。
func _ss_move(ns: Dictionary, is_me: bool, toward: int) -> void:
	var my_loc: int = int(ns["my_loc"])
	var opp_loc: int = int(ns["opp_loc"])
	var dir: int = 1 if my_loc < opp_loc else -1
	var mover: int = my_loc if is_me else opp_loc
	var other: int = opp_loc if is_me else my_loc
	var new_loc: int = mover + dir * toward
	new_loc = clampi(new_loc, 1, 9)
	if new_loc == other:
		new_loc -= dir
	new_loc = clampi(new_loc, 1, 9)
	if is_me:
		ns["my_loc"] = new_loc
	else:
		ns["opp_loc"] = new_loc


## 深层（对手/我方假想回合）的粗粒度动作枚举。
func _ss_hypo_actions(s: Dictionary, is_me: bool, my_class: String, opp_class: String) -> Array:
	var out := []
	var hand = s["my_hand"] if is_me else s["opp_hand"]
	var dist: int = _ss_dist(s)
	# 攻击：交换价值最高的前 N 张
	var strikes := []
	for d in hand:
		if _range_hits(d, dist):
			strikes.append({"type": "strike", "card": d, "score": _ss_strike_card_value(s, d, is_me)})
	strikes.sort_custom(func(a, b): return a["score"] > b["score"])
	for i in range(min(strikes.size(), SEARCH_STRIKE_BRANCH)):
		out.append({"type": "strike", "card": strikes[i]["card"]})
	# 移动：朝理想距离方向，取 1~3 个落点
	var my_loc: int = int(s["my_loc"]) if is_me else int(s["opp_loc"])
	var opp_loc: int = int(s["opp_loc"]) if is_me else int(s["my_loc"])
	var ideal: int = _get_ideal_distance(my_class, opp_class)
	var targets := {}
	for delta in [-2, -1, 0, 1, 2]:
		var t: int = opp_loc + delta if my_loc <= opp_loc else opp_loc - delta
		t = clampi(t, 1, 9)
		if t == my_loc or t == opp_loc:
			continue
		var key: float = abs(abs(t - opp_loc) - ideal)
		if not targets.has(key):
			targets[key] = t
	var sorted_keys = targets.keys()
	sorted_keys.sort()
	for i in range(min(sorted_keys.size(), SEARCH_MOVE_BRANCH)):
		out.append({"type": "move", "loc": targets[sorted_keys[i]]})
	# 加成 / 热身 / 变身
	if hand.size() > 1:
		var boost_card = null
		for d in hand:
			if d is Dictionary and not d.get("boost", {}).is_empty():
				boost_card = d
				break
		if boost_card == null:
			boost_card = hand[0]
		out.append({"type": "boost", "card": boost_card})
	out.append({"type": "prepare"})
	if int(s["my_gauge"] if is_me else s["opp_gauge"]) >= 2 and not (s["my_exceeded"] if is_me else s["opp_exceeded"]):
		out.append({"type": "exceed"})
	return out


func _ss_action_value(s: Dictionary, a: Dictionary, is_me: bool, depth: int, alpha: float, beta: float, my_class: String, opp_class: String) -> float:
	if a["type"] == "strike":
		return _ss_strike_card_value(s, a["card"], is_me)
	var ns: Dictionary = _ss_apply(s, a, is_me)
	return _ss_minimax(ns, depth - 1, alpha, beta, not is_me, my_class, opp_class)


func _ss_minimax(s: Dictionary, depth: int, alpha: float, beta: float, is_me: bool, my_class: String, opp_class: String) -> float:
	if depth <= 0:
		return _ss_eval(s, my_class, opp_class)
	var actions: Array = _ss_hypo_actions(s, is_me, my_class, opp_class)
	if actions.is_empty():
		return _ss_eval(s, my_class, opp_class)
	if is_me:
		var value: float = -_SEARCH_INF
		for a in actions:
			var v: float = _ss_action_value(s, a, true, depth, alpha, beta, my_class, opp_class)
			if v > value:
				value = v
			if value > alpha:
				alpha = value
			if alpha >= beta:
				break
		return value
	else:
		var value: float = _SEARCH_INF
		for a in actions:
			var v: float = _ss_action_value(s, a, false, depth, alpha, beta, my_class, opp_class)
			if v < value:
				value = v
			if value < beta:
				beta = value
			if alpha >= beta:
				break
		return value


## 根节点动作映射（带 orig 引用），并做分支裁剪。
func _root_coarse_actions(possible_actions: Array, state: AIPlayer.AIGameState, s: Dictionary) -> Array:
	var out := []
	var strikes := []
	var moves := []
	var boosts := []
	for a in possible_actions:
		if a is AIPlayer.StrikeAction:
			if a.wild_swing:
				continue
			if not can_card_hit(a.card_id, a.ex_card_id, state):
				continue
			if _is_block_card(a.card_id, state):
				continue  # 不用 block 主动发起战斗
			var d: Dictionary = _effective_strike_def(a, state)
			strikes.append({"type": "strike", "card": d, "orig": a, "score": _ss_strike_card_value(s, d, true)})
		elif a is AIPlayer.MoveAction:
			if _can_use_move():
				var _nd: int = abs(a.location - state.opponent_state.arena_location)
				if _nd <= _get_distance(state):  # 禁止后退移动
					moves.append({"type": "move", "loc": a.location, "orig": a})
		elif a is AIPlayer.BoostAction:
			boosts.append({"type": "boost", "orig": a})
		elif a is AIPlayer.PrepareAction:
			out.append({"type": "prepare", "orig": a})
		elif a is AIPlayer.ExceedAction:
			if str(state.my_state.deck_def.get("id", "")) != "tournelouse":  # 托内鲁斯不 exceed
				out.append({"type": "exceed", "orig": a})
		elif a is AIPlayer.CharacterActionAction:
			out.append({"type": "character", "orig": a})
	strikes.sort_custom(func(a, b): return a["score"] > b["score"])
	for i in range(min(strikes.size(), SEARCH_STRIKE_BRANCH)):
		out.append({"type": "strike", "card": strikes[i]["card"], "orig": strikes[i]["orig"]})
	moves.sort_custom(func(a, b): return _value_move(a["orig"], state) > _value_move(b["orig"], state))
	for i in range(min(moves.size(), SEARCH_MOVE_BRANCH)):
		out.append({"type": "move", "loc": moves[i]["loc"], "orig": moves[i]["orig"]})
	if boosts.size() > 0:
		boosts.sort_custom(func(a, b): return _value_boost(a["orig"], state) > _value_boost(b["orig"], state))
		out.append({"type": "boost", "orig": boosts[0]["orig"], "card": _get_def(boosts[0]["orig"].card_id, state)})
	return out


## 根节点单个动作的分值：加成走精确价值（已前瞻），其余走 minimax 推演 depth 层。
func _eval_root_action(s: Dictionary, a: Dictionary, state: AIPlayer.AIGameState, depth: int, my_class: String, opp_class: String) -> float:
	if a["type"] == "boost" and a.has("orig"):
		# 加成：直接用真实价值（含组合价值 + focus/block 加分 + 抽牌/位移），
		# 不再走粗粒度 minimax——因为 _value_boost 已经通过 _boost_combo_bonus
		# 精确算出了「加成后我最好攻击牌的净交换改善」，等于已经前瞻过了。
		# 缩放 0.5，让加成的分值量纲与「攻击净交换×8」可比（否则加成会碾压攻击）。
		return _value_boost(a["orig"], state) * 0.5
	return _ss_action_value(s, a, true, depth, -_SEARCH_INF, _SEARCH_INF, my_class, opp_class)


## 入口：迭代加深搜索（minimax + α-β 剪枝）选出最优动作；返回 AIPlayer 动作或 null（调用方兜底）。
func search_best_action(possible_actions: Array, state: AIPlayer.AIGameState):
	if possible_actions.is_empty():
		return null
	var s: Dictionary = _ss_make(state)
	var my_class: String = _classify_character(state.my_state, state)
	var opp_class: String = _classify_character(state.opponent_state, state)
	var root_actions: Array = _root_coarse_actions(possible_actions, state, s)
	if root_actions.is_empty():
		return null

	var deadline: int = Time.get_ticks_msec() + SEARCH_TIME_BUDGET_MS
	var best = null

	# 迭代加深：从 MIN 层逐层加深到 MAX 层，任一层超时就退回上一层结果。
	for depth in range(SEARCH_MIN_DEPTH, SEARCH_MAX_DEPTH + 1):
		if Time.get_ticks_msec() > deadline:
			break
		var layer_best = null
		var layer_best_v: float = -_SEARCH_INF
		var layer_complete := true
		for a in root_actions:
			if Time.get_ticks_msec() > deadline:
				layer_complete = false
				break
			var v: float = _eval_root_action(s, a, state, depth, my_class, opp_class)
			if v > layer_best_v:
				layer_best_v = v
				layer_best = a
		if layer_complete and layer_best != null:
			best = layer_best
		else:
			break  # 本层未跑完（超时），用上一层结果

	if best != null and best.has("orig"):
		# 供调试验证：打印搜索选中的动作类型 + 克制标签
		var _t: String = str(best["type"])
		var _label: String = ""
		if best["type"] == "strike" and best.has("card"):
			var _oppc = null
			if s["opp_hand"].size() > 0:
				_oppc = s["opp_hand"][0]
			if _oppc != null:
				_label = " 克制:" + str(_knowledge.counter_relation(best["card"], _oppc)["label"])
		print("[AI搜索] 决策=%s%s" % [_t, _label])
		return best["orig"]
	return null
