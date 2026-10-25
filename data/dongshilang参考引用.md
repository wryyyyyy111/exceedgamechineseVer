# 日番谷冬狮郎（dongshilang）实现参考引用

本文用于 Executor 实施 `dongshilang` 时的规则→实现映射。规则来源：

- 用户确认的 8 条落定规则（2026-10-21）。
- `E:/Godot/角色素材/加入新角色/ly-晓天/日番谷东狮郎/dongshilang-import.md` 卡面文本。

范围仅覆盖：角色能力、5 张冰晶（buddy）加成、7 张 special/ultra 的 attack/boost 口径。标准 GG normals 不在本文范围。

## 一、已落定规则与实现落点

| 规则 | 落定结论 | 主要实现入口 |
|---|---|---|
| 冰晶总量 | 额外卡按 **5 张**实现 | `data/decks/dongshilang.json` 的 `buddy_cards` + 5 张 `set_aside: true` 定义 |
| 退出觉醒判定 | 仅统计**我方 boost 区**冰晶数量 | `scenes/core/local_game.gd`（回合结束判定）、`Player.get_boosts()` 过滤 dongshilang 冰晶 |
| 区域建模 | 冰晶池用 `set_aside`；进入对局后用 `bleach_zone` | `scenes/core/player.gd`（`set_aside_cards` / `bleach_zone`），`local_game.gd` 区域迁移 |
| 觉醒时序 | 觉醒占主行动；附带执行 1 次“觉醒角色主行动”；该附带行动可取消 | `data/decks/dongshilang.json`（on_exceed/角色行动），`scenes/core/local_game.gd`（bonus/character action 流程） |
| 冰华突 Hit 计数 | 在 Hit 结算前，按本次战斗累计“穿越对手次数”逐次 +1 威力 | `scenes/core/local_game.gd`（移动/穿越记录 + hit 结算） |
| 冰刃额外伤害 | 取对手所用卡**原始印刷护甲值** | `scenes/core/local_game.gd`：读取 `active_strike.get_player_card(opponent).definition['armor']` |
| 龙霰架吃冰晶 | 享受 5 张冰晶赋予特殊技的**全部效果（数值+文本）** | `data/decks/dongshilang.json`（条件覆盖龙霰架）+ 必要时 `local_game.gd` 自定义处理 |
| HP Rank | `dongshilang` 评级 **A+** | `data/hp_rank_mode_manager.json`（T9） |

## 二、角色能力映射（ability / exceed ability / 角色主行动）

| 部分 | 卡面规则 | 实现口径 | 入口文件 | 是否需自定义 |
|---|---|---|---|---|
| 开局被动 | 从 5 张冰晶随机 2 张进 bleach_zone | 从 `set_aside_cards` 抽样 2 张，迁移到 `bleach_zone` 并发事件 | `data/decks/dongshilang.json`、`scenes/core/local_game.gd`、`scenes/core/player.gd` | 是 |
| 常态角色主行动 | 每回合 1 次，从 bleach_zone 打出 1 张冰晶加成；行动可取消 | 角色行动 effect 走 Boost 流程，`valid_zones = ["bleach"]`，`boost_amount = 1`，并接入取消回到 PickAction | `data/decks/dongshilang.json`、`scenes/core/player.gd`、`scenes/core/game_wrapper.gd`、`scenes/core/ai_player.gd`、`scenes/game/game.gd`、`scenes/core/local_game.gd` | 部分（bleach 作为 boost 来源链路） |
| 觉醒时 | 额外 1 张冰晶进 bleach_zone，并立刻执行 1 次觉醒角色主行动 | on_exceed 后：先迁移冰晶，再给予“附带角色行动”窗口（可取消） | `data/decks/dongshilang.json`、`scenes/core/local_game.gd` | 是 |
| 觉醒角色主行动 | 每回合 1 次，从 bleach_zone 打出 2 张冰晶加成；行动可取消 | 角色行动 effect 走多选 boost（`boost_amount = 2`），限制为冰晶定义 | 同上 | 部分 |
| 回合结束被动 | 若场上你的冰晶数量不为 5，退出觉醒 | 仅数我方 continuous boosts 中“dongshilang 冰晶”数量，不足/超出则 `revert` | `scenes/core/local_game.gd`、`scenes/core/strike_effects.gd`（复用 `revert`） | 是 |

## 三、冰晶 5 卡（buddy boost）映射

> 统一规则：5 张冰晶均为 continuous boost，且“此加成弃置时置入 bleach_zone”。

| 冰晶卡 | 文本拆解 | 实现口径 | 入口文件 | 是否需自定义 |
|---|---|---|---|---|
| 冰刃 | 特殊技得：威力+1；后置：若击晕对手，额外造成对手卡面护甲值伤害 | `powerup +1` 可复用；“额外伤害=对手印刷护甲”需专用 effect | `data/decks/dongshilang.json`、`scenes/core/local_game.gd`、`scenes/core/strike_effects.gd` | 是（额外伤害部分） |
| 冰之虚像 | 特殊技得：对手击中你无法获得怒气；击中：若你被击中，威力+1 | “若你被击中则+1”复用 `condition: was_hit`；“无法获得怒气”需拦截对手命中进怒流程 | 同上 | 是（禁怒部分） |
| 滑翔 | 特殊技得：Before 前进3 | 直接复用 `advance`（before） | `data/decks/dongshilang.json` | 否 |
| 绝空 | 特殊技得：After 在攻击最大距离+1范围造成1伤；若以此法伤害则该特殊技进怒气 | 需按“当前攻击最大距离+1”动态判定并在伤害成功后迁移攻击牌到 gauge | `scenes/core/local_game.gd`、`scenes/core/strike_effects.gd`、`data/decks/dongshilang.json` | 是 |
| 棱形冰壁 | 特殊技得：护甲+2；Hit：若你没有护甲，威力-1 | `armorup +2` 可复用；“无护甲时-1威力”需新增条件（或专用 effect） | 同上 | 是（无护甲判定） |
| 全部冰晶的弃置回收 | 弃置时回 bleach_zone | 复用 `move_boost_to_bleach_on_cleanup` / `move_boost_to_bleach_immediately` 迁移链路 | `scenes/core/local_game.gd`、`scenes/core/player.gd`、`data/decks/dongshilang.json` | 否（复用现有链路） |

## 四、特超 7 卡映射（attack + boost）

| 卡牌 | Attack 实现口径 | Boost 实现口径 | 入口文件 | 是否需自定义 |
|---|---|---|---|---|
| 冰天百花葬（Ultra） | 每有 1 张冰晶加成：速度+1、威力+2、距离+0~1；计数对象为“我方冰晶加成” | 摄人寒气：`powerup +2`；Now 弃置场上除自身外所有加成（双方） | `data/decks/dongshilang.json`、`scenes/core/local_game.gd`、`scenes/core/strike_effects.gd` | 是（冰晶计数 + 全场清加成） |
| 龙霰架（Ultra） | 每有 1 张冰晶加成怒气-1（仅冰晶计数）；Hit 击退1；并享受冰晶全部文本 | 天象从临：从 bleach_zone 打 1 张冰晶加成，然后发起战斗（`boost_then_strike` 变体） | 同上 + `player/game_wrapper/ai_player/game` 的 boost 来源扩展 | 是（怒气减免按冰晶计数） |
| 冰华突（Special） | Before 前进2；Hit 按“本次战斗穿越次数”逐次 +1 威力 | 霜天：速度+1、威力-2；Hit 将此卡置入怒气区 | `data/decks/dongshilang.json`、`scenes/core/local_game.gd` | 是（穿越次数累计） |
| 冰龙旋尾（Special） | Before 前进1；Hit：击退1，若未完整击退则威力+2（可复用 `not_full_push` 条件） | 红莲龙：威力+1；Now 若距离=1，移动1并将此卡置入怒气区 | `data/decks/dongshilang.json` | 否（可数据化复用） |
| 端坐于霜天（Special） | 对手无法移动你（可复用 `ignore_push_and_pull`）；你本次战斗通过任何效果至多移动1格（需战斗期移动上限） | 冰轮丸：Before 前进4 | `data/decks/dongshilang.json`、`scenes/core/local_game.gd`、`scenes/core/strike_effects.gd` | 是（自身移动上限） |
| 群鸟冰柱（Special） | 你的前进效果改为后退（战斗期改写 advance→retreat） | 千年冰牢：战斗中对手无法移动（可复用 `block_opponent_move`） | `data/decks/dongshilang.json`、`scenes/core/local_game.gd`、`scenes/core/strike_effects.gd` | 是（前进改后退） |
| 真空冰刃（Special） | 无视护甲（`ignore_armor`） | 铁灰：后退1，弃置对手1个加成（`retreat + discard_continuous_boost`） | `data/decks/dongshilang.json` | 否 |

## 五、建议新增自定义 effect_type（供后续任务使用）

以下名称用于实现分工和测试命名对齐；具体命名以 T5-T7 实际提交为准：

- `dongshilang_setup_random_ice_to_bleach`
- `dongshilang_exceed_add_ice_and_bonus_character_action`
- `dongshilang_revert_if_ice_boost_not_five`
- `dongshilang_iceblade_stun_bonus_printed_armor_damage`
- `dongshilang_icephantom_prevent_opponent_gauge_on_hit`
- `dongshilang_zekong_after_max_range_plus_one`
- `dongshilang_diamondwall_powerdown_if_no_armor`
- `dongshilang_hyotenhyakkaso_scale_by_ice_boost`
- `dongshilang_discard_all_other_boosts`
- `dongshilang_longxianjia_gauge_reduction_by_ice_boost`
- `dongshilang_binghuatu_hit_powerup_per_cross_count`
- `dongshilang_limit_self_move_to_one_this_strike`
- `dongshilang_convert_advance_to_retreat`

## 六、测试映射约束（供 T8 直接落表）

- 角色能力测试：
  - 开局随机 2 冰晶入 bleach_zone；
  - 觉醒时额外 1 冰晶 + 附带角色行动；
  - 常态/觉醒态角色行动次数（1/2）与取消行为；
  - 回合结束按“我方 boost 区冰晶数==5”判定是否退出觉醒。
- 卡牌测试：
  - 12 张自定义卡逐张覆盖 attack 与 boost 两部分；
  - 特别断言：冰刃按印刷护甲补伤、龙霰架完整吃冰晶文本、冰华突按穿越次数加威力。

## 七、实施边界

- 本文只定义实现口径，不直接改动运行时代码。
- `data/hp_rank_mode_manager.json` 的 A+ 更新保留到 T9。
- 仅客户端仓库实现，不涉及 `E:\Godot\exceedgameserver-main`。

