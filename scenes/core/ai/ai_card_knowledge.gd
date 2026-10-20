class_name AICardKnowledge
extends RefCounted

## 全卡牌库 + 克制关系引擎（独立、自包含）。
##
## AI 内置一份「所有卡牌的知识库」：
##   1. 通过 CardDataManager.card_data 访问全部角色、全部卡牌的定义；
##   2. 把每张卡归入流派（block/focus/spike/throw/sweep/cross/assault/…）；
##   3. 对任意两张牌计算「谁克谁、为什么」，供攻击决策查询。


# ============================================================
# 基础取值（兼容 String 动态值）
# ============================================================

func _num(v) -> int:
	if v is String:
		return 20  # 动态速度按最快处理
	return int(v)


func speed_of(defn: Dictionary) -> int:
	return _num(defn.get("speed", 0))


func power_of(defn: Dictionary) -> int:
	var v = defn.get("power", 0)
	return 0 if v is String else int(v)


func guard_of(defn: Dictionary) -> int:
	var v = defn.get("guard", 0)
	return 0 if v is String else int(v)


func armor_of(defn: Dictionary) -> int:
	var v = defn.get("armor", 0)
	return 0 if v is String else int(v)


func has_effect(defn: Dictionary, effect_type: String) -> bool:
	for eff in defn.get("effects", []):
		if eff.get("effect_type") == effect_type:
			return true
		var and_eff = eff.get("and", {})
		if and_eff is Dictionary and and_eff.get("effect_type") == effect_type:
			return true
	return false


# ============================================================
# 卡牌流派分类
# ============================================================

## 把一张卡归入一个流派，用于克制关系判断与威胁自省。
func classify(defn: Dictionary) -> String:
	if defn.is_empty():
		return "unknown"
	var dl: String = str(defn.get("id", "")).to_lower()
	if "block" in dl:
		return "block"
	if "focus" in dl:
		return "focus"
	if "spike" in dl or dl == "gg_normal_dust":
		return "spike"
	if "throw" in dl or "grasp" in dl:
		return "throw"
	if "sweep" in dl:
		return "sweep"
	if "cross" in dl:
		return "cross"
	if "assault" in dl:
		return "assault"
	if "dive" in dl:
		return "dive"
	# 按效果特征兜底判断
	var ig: bool = has_effect(defn, "ignore_guard")
	var ia: bool = has_effect(defn, "ignore_armor")
	if ig and ia:
		return "spike"
	if ig:
		return "guard_break"
	if ia:
		return "armor_break"
	if has_effect(defn, "stun"):
		return "stunner"
	if speed_of(defn) >= 7:
		return "fast"
	if guard_of(defn) >= 5:
		return "tank"
	return "standard"


## 某流派克制谁（返回被它克制的流派列表）。
func counters_of(archetype: String) -> Array:
	match archetype:
		"spike", "guard_break":
			return ["block", "tank", "guard_break"]  # 破防/穿透克高霸体与格挡
		"armor_break":
			return ["tank", "armored"]
		"throw":
			return ["tank", "block"]
		"fast":
			return ["sweep", "slow"]
		"block":
			return ["sweep", "throw"]  # 格挡克重慢招
		"sweep":
			return ["block"]
		"stunner":
			return ["fast"]
		_:
			return []


## 某流派被谁克制。
func countered_by(archetype: String) -> Array:
	match archetype:
		"block", "tank":
			return ["spike", "guard_break", "armor_break"]
		"sweep":
			return ["fast", "block"]
		"throw":
			return ["block", "fast"]
		"focus":
			return ["spike"]
		_:
			return []


# ============================================================
# 两牌克制关系
# ============================================================

## 计算「我方 my_def 对 对手 opp_def」的克制关系（不含位移躲招，
## 精确的净交换由策略里的 _eval_counter_response 另行计算）。
## 返回 {label, reason, my_first, my_stuns, opp_stuns, my_win}。
func counter_relation(my_def: Dictionary, opp_def: Dictionary) -> Dictionary:
	var my_speed: int = speed_of(my_def)
	var opp_speed: int = speed_of(opp_def)
	var my_power: int = power_of(my_def)
	var opp_power: int = power_of(opp_def)
	var my_guard: int = guard_of(my_def)
	var opp_guard: int = guard_of(opp_def)
	var my_armor: int = armor_of(my_def)
	var opp_armor: int = armor_of(opp_def)
	var my_ig: bool = has_effect(my_def, "ignore_guard")
	var my_ia: bool = has_effect(my_def, "ignore_armor")
	var opp_ig: bool = has_effect(opp_def, "ignore_guard")
	var opp_ia: bool = has_effect(opp_def, "ignore_armor")

	# 先手判定：发起者平速胜
	var my_first: bool = my_speed >= opp_speed
	# 击晕判定：我方威力 > 对手有效霸体（破防则霸体视为 0）
	var my_stuns: bool = my_power > (0 if my_ig else opp_guard)
	var opp_stuns: bool = opp_power > (0 if opp_ig else my_guard)
	# 伤害
	var my_dmg: int = max(my_power - (0 if my_ia else opp_armor), 0)
	var opp_dmg: int = max(opp_power - (0 if opp_ia else my_armor), 0)

	var label: String = "even"
	var reasons: Array = []

	if my_first and my_stuns:
		label = "counter"
		reasons.append("先手击晕")
	elif not my_first and opp_stuns:
		label = "countered"
		reasons.append("被先手击晕")
	elif my_ia and opp_armor > 0:
		label = "counter"
		reasons.append("破甲")
	elif opp_ia and my_armor > 0:
		label = "countered"
		reasons.append("被破甲")
	elif my_ig and opp_guard >= 3:
		label = "counter"
		reasons.append("破防")
	elif my_dmg - opp_dmg >= 3:
		label = "counter"
		reasons.append("净赚%d血" % (my_dmg - opp_dmg))
	elif opp_dmg - my_dmg >= 3:
		label = "countered"
		reasons.append("净亏%d血" % (opp_dmg - my_dmg))

	return {
		"label": label,
		"reason": "、".join(reasons) if reasons.size() > 0 else "均势",
		"my_first": my_first,
		"my_stuns": my_stuns,
		"opp_stuns": opp_stuns,
		"my_win": my_first and (my_stuns or my_dmg >= opp_dmg),
	}


# ============================================================
# 全卡池查询
# ============================================================

## 从全卡池（所有角色的所有卡牌）里，找「最能克制 my_def」的对手卡牌定义。
## 用于威胁自省：知道自己这张牌怕什么。
func best_counter_in_pool(my_def: Dictionary) -> Dictionary:
	var pool: Dictionary = CardDataManager.card_data
	var best: Dictionary = {}
	var best_score: int = -999
	for def_id in pool:
		var opp_def: Dictionary = pool[def_id]
		if opp_def.get("type", "") != "normal" and opp_def.get("type", "") != "special":
			continue
		var rel: Dictionary = counter_relation(my_def, opp_def)
		var score: int = 0
		if rel["label"] == "countered":
			score = 10
		elif rel["opp_stuns"]:
			score = 8
		elif rel["label"] == "even":
			score = 1
		if score > best_score:
			best_score = score
			best = opp_def
	return best
