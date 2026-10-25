extends ExceedGutTest

## Axl Bomber（Axl Low 的 3 速特殊技）：
## 击中应「前进2格，然后你可以支付1怒气获得优势」。
## 中文数据曾经丢掉「击中：前进2」，并把付怒效果错并进了 during_strike 里。

func who_am_i():
	return "axl"

func test_axl_bomber_has_hit_advance_and_optional_advantage():
	var card = CardDataManager.get_card("axl_axlbomber")
	assert_eq(card["type"], "special")
	assert_eq(card["speed"], 3, "应为 3 速特殊技")

	var during_powerup = false
	var hit_advance = false
	for e in card["effects"]:
		if e["timing"] == "during_strike" and e["effect_type"] == "powerup":
			assert_eq(e["amount"], 2, "发起战斗时 +2 威力")
			assert_false(e.has("and"), "付怒效果不该挂在 during_strike 上")
			during_powerup = true
		elif e["timing"] == "hit" and e["effect_type"] == "advance":
			assert_eq(e["amount"], 2, "击中应前进 2 格")
			var follow = e.get("and", {})
			assert_eq(follow.get("effect_type"), "gauge_for_effect", "然后可以支付 1 怒气")
			assert_eq(follow.get("gauge_max"), 1)
			var overall = follow.get("overall_effect", {})
			assert_eq(typeof(overall), TYPE_DICTIONARY)
			assert_eq(overall.get("effect_type"), "gain_advantage",
					"支付后获得优势")
			hit_advance = true

	assert_true(during_powerup, "应有 during_strike 的 +2 威力")
	assert_true(hit_advance, "应有「击中：前进2」（之前丢失的那条）")
