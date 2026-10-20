# 京乐春水（jinglechunshui）实现参考

本文记录当前京乐春水实现所实际采用的复用点和角色专用实现。卡牌数据位于 `data/decks/jinglechunshui.json` 的 `custom_card_definitions`；结算入口均为 `scenes/core/local_game.gd` 的 `handle_strike_effect()`。标准普通技不在本文范围内。

## 角色能力

| 部分 | 实现与函数参考 | 同类参考角色 | 是否新需求 |
|---|---|---|---|
| 常态被动：特殊技加成结算后可战斗 | `JingleChunShuiStrikeAfterSpecialBoost` 检查 `active_boost.card.definition.type == "special"` 后，用通用 `Choice` + `Strike` 建立可选战斗。`continue_resolve_boost()` 负责在加成效果完成后继续结算。 | Anji、Bang 等角色的角色能力也用通用 `Strike` 效果发起战斗。 | 是。筛选“仅特殊技加成且仅未觉醒”的规则由京乐专用 handler 新写。 |
| 常态主行动：付 2 生命，从怒气区打出特殊技加成，随后牌库顶进怒气 | `JingleChunShuiGaugeSpecialBoost` 复用 `can_boost_something()` 和 `DecisionType_BoostNow`，保留通常费用支付；`boost_finish_resolving_card()` 在持续加成实际入场后，读取 `jinglechunshui_gauge_boost_pending` 并复用 `AddTopDeckToGauge`。 | Syrus 的怒气区加成流程同样使用 `BoostNow`；Devis、Hakumen 使用 `AddTopDeckToGauge`。 | 是。需要“限定特殊技、付生命、结算成功后再放牌库顶进怒气”的组合流程，新增 flag 与角色分支。 |
| 觉醒被动：持续加成结算后抽 1 并可战斗 | `JingleChunShuiDrawAndStrikeAfterContinuousBoost` 筛选 continuous boost 后顺序调用通用 `Draw`、`Choice`、`Strike`。 | Anji 等角色使用通用 `Draw`/`Strike` 组合。 | 是。筛选“仅觉醒且仅持续加成”的时机规则由专用 handler 新写。 |
| 觉醒被动：双方回合开始时，当前回合玩家付 2 能量或受 1 伤害；可弃牌库顶代付 | `JingleChunShuiTurnStartToll` 通过 `start_of_next_turn` 与 `opponent_start_of_next_turn` 挂入回合开始队列；`JingleChunShuiTurnStartTollPay` 复用 `discard_topdeck()`、`ForceForEffect` 和 `TakeDamage`。代付仅限当前回合玩家。 | Anji、Geoffrey 等使用 `ForceForEffect` 支付选择。 | 是。牌库顶每 2 张折抵 1 能量、并与正常能量混合支付的菜单为京乐专用实现。 |

## 攻击效果参考

| 类型 | 卡牌 | 攻击效果的函数参考与实现 | 同类参考角色 | 是否新需求 |
|---|---|---|---|---|
| Special | `zhangui` | `dodge_at_range`、`Advance`、`Close`、`Armorup` 由通用 `handle_strike_effect()` 分支结算；整理阶段进入 `JingleChunShuiPlayBujingdule`。 | 多张通用卡复用 `dodge_at_range`；不精独乐跨区域加成无直接同类。 | 是。`JingleChunShuiPlayBujingdule` 枚举手牌、怒气、弃牌区，建立 `BoostNow`，并设 `ignore_costs` 和 `sustain_next_boost`。 |
| Special | `yingsong` | `Advance`、`ForceForEffect` 每点 `Powerup`、`moved_past_this_strike` 后 `GainAdvantage`。 | Anji 使用 `ForceForEffect`；标准 Dive 使用前进。 | 否，全部为通用效果组合。 |
| Special | `yinggui` | `SetStrikeX` 以 `RANGE_TO_OPPONENT` 设 X，随后 `Rangeup` 与 `IgnoreArmor`。 | Enkidu 使用 `set_strike_x`。 | 否，全部为通用效果组合。 |
| Special | `bujingdule` | `JingleChunShuiChooseTwo` 建立五项不可重复二选；后置以 `ForceForEffect` 支付成功后调用 `JingleChunShuiBujingduleReturn`，复用 `AddTopDeckToGauge` 与 `handle_strike_attack_immediate_removal()` 回手。 | Devis、Hakumen 使用 `AddTopDeckToGauge`。 | 是。不可重复二选和攻击牌支付后回手由京乐专用 handler 实现。 |
| Special | `yangui` | `JingleChunShuiYanguiNameNormal` 使用 `DecisionType_ReadingNormal`；内部调用 `discard_matching_or_reveal()`，弃牌成功则 `add_power_bonus()` 并设 `ignore_guard`。 | 读心流程参考标准 Focus 加成。 | 是。点名后的弃牌/展示结果与攻击修正绑定，使用京乐专用内部 handler。 |
| Ultra | `zhongyanzhimu` | `gauge_cost_exceed` 复用既有觉醒减费字段。`JingleChunShuiInvalidateIfOpponentDeckOverNine` 登记无效攻击；`JingleChunShuiDiscardTopdeckForPower` 用 `DecisionType_PickNumberFromRange` 选 0 至 9，再以 `discard_topdeck()` 和 `add_power_bonus()` 结算。 | 其它 Ultra 复用 `gauge_cost_exceed`；数字选择框架复用 `PickNumberFromRange`。 | 是。牌库大于 9 时无效与按可选弃牌数加威力，由京乐专用 handler 实现。 |
| Ultra | `yuyingzhong` | `gauge_cost_exceed`；`Advance`，以及 `moved_past_this_strike` 条件下 `Powerup`。 | 多张 Ultra 使用 `gauge_cost_exceed`；标准 Dive 使用前进。 | 否，全部为通用字段与效果组合。 |

## 加成效果参考

| 类型 | 卡牌 | 加成效果的函数参考与实现 | 同类参考角色 | 是否新需求 |
|---|---|---|---|---|
| Special | `zhangui` | `was_hit` 条件下以 `SpendLife -> Draw -> DiscardRandom` 结算，否则仅 `Draw`。 | 多张牌使用 `was_hit` 和嵌套 `and`。 | 否，通用条件和效果链。 |
| Special | `yingsong` | 双方攻击命中时 `Powerup` 与 `IgnoreArmor`；对方效果通过 `for_other_player` 转发。 | 现有跨玩家加成牌使用 `for_other_player`。 | 否，通用数据模式。 |
| Special | `yinggui` | `strike_effect_after_opponent_sets` 在双方设置后、揭示前插入 `Choice`；选项使用 `Draw` 或 `SpendLife -> Choice(Advance/Retreat)`。 | 现有带 `strike_effect_after_opponent_sets` 的卡牌。 | 否，通用时机和效果组合。 |
| Special | `bujingdule` | `JingleChunShuiSlowestPlayerDamage` 比较双方 `spaces_moved_this_strike`，对唯一移动较少者 `TakeDamage(2)`。 | 无完全相同的双方自然移动比较。 | 是。比较逻辑及平手不伤害由京乐专用 handler 实现。 |
| Special | `yangui` | `JingleChunShuiAlternatingNormals` 与内部 handler 复用 `ReadingNormal`，双方依次声明；`begin_resolve_strike()` 读取声明记录并加威力，最终用 `Strike` 开战。 | Focus 加成的读心流程；Anji、Bang 等角色能力使用 `Strike`。 | 是。轮流声明、按声明次数强化、自动开战需要专用状态与 handler。 |
| Ultra | `zhongyanzhimu` | 常驻 `Powerup(1)`；立即 `Choice(SpendLife -> Strike / Pass)`；命中时令对手选 `DiscardRandom + ChooseDiscard(gauge)` 或 `DiscardTopdeck(4)`。 | Anji、Bang 等使用 `Strike`；Devis/Hakumen 使用牌库顶资源操作。 | 否，全部复用通用效果链。 |
| Ultra | `yuyingzhong` | 立即 `SpendLife -> Draw -> BonusAction`；后置 `GainLife(2)`。 | Enkidu 有生命支付后的额外行动。 | 否，全部为通用效果组合。 |

## 专用状态与验证

- `Player.jinglechunshui_gauge_boost_pending`：只服务常态主行动，避免普通怒气区加成也错误加入牌库顶。
- `Player.jinglechunshui_named_normal_powerups`、`jinglechunshui_alternating_names_remaining`、`jinglechunshui_yangui_reveal_ids`：服务 `yangui` 的轮流声明和本次战斗威力计算。
- `test/unit/test_jinglechunshui.gd` 覆盖常态/觉醒 UA、七张专属卡的攻击和加成流程；定向 GUT 结果为 `26/26 passed`。

## 维护约束

- 京乐专用判断必须以 `deck_def.id == "jinglechunshui"` 限制，不能改变其它角色的加成、回合开始或战斗流程。
- 新增专属卡应继续写在 `custom_card_definitions`，不要再写回全局 `data/card_definitions.json`。
- 角色专用 handler 的常量统一登记在 `scenes/core/strike_effects.gd`，显示文本登记在 `globals/game_strings.gd`。