extends ExceedGutTest

class CaptureHeidiRemoteGame extends RemoteGame:
	var last_action_message = {}

	func _init():
		super(null)

	func _submit_game_message(action_message):
		last_action_message = action_message

func who_am_i():
	return "heidi"

func test_heidi_daggerstorm_remote_multiselect_forwards_complete_choice():
	var remote_game = CaptureHeidiRemoteGame.new()
	remote_game._player_info = {'id': 17}
	remote_game._opponent_info = {'id': 23}

	assert_true(remote_game.do_choose_multiple_from_topdeck(player1, [41, 52], "boost"))
	assert_true(remote_game.has_method("process_choose_multiple_from_topdeck"))
	assert_eq(remote_game.last_action_message, {
		'action_type': 'action_choose_multiple_from_topdeck',
		'player_id': 17,
		'card_ids': [41, 52],
		'action': "boost",
	})
	remote_game.free()

func test_heidi_animation_is_registered_for_web_loading():
	var animation_path := "res://assets/character_animations/heidi/animations.tres"
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(CdnAssetLoader.ANIMATION_MANIFEST_PATH))
	assert_true(manifest.has(animation_path))
	var resource_text := str(manifest.get(animation_path, ""))
	assert_true(resource_text.contains(
		'path="res://assets/portraits/custom.png" id="1_heidi"] ; cdn_path="res://assets/character_animations/heidi/heidi.png"'))
	var frames := load(animation_path) as SpriteFrames
	assert_not_null(frames)
	assert_eq(frames.get_frame_texture("idle", 0).resource_path, "res://assets/portraits/custom.png")
	var parsed := Character._parse_sprite_frames_tres(resource_text, animation_path.get_base_dir())
	assert_eq(parsed["texture_paths"].get("1_heidi", ""),
		"res://assets/character_animations/heidi/heidi.png")

func test_heidi_animation_loads_from_oss():
	var character := Character.new()
	var frames := await character._load_cdn_sprite_frames(
		"res://assets/character_animations/heidi/animations.tres", false)
	assert_not_null(frames)
	assert_true(frames.has_animation("idle"))
	assert_not_null(frames.get_frame_texture("idle", 0))
	character.free()

##
## 海蒂被动：结算任意加成时摸 1 张牌（on_any_boost，含纯持续加成）
## 特殊规则：开关扇（boost_multiple + return_to_hand）展示并执行的加成
## 替代了开关扇自身——开关扇不触发摸牌，被展示的加成触发 1 次；
## 若被展示的加成又打出另一张加成（机械天才 → 弃牌堆持续加成），
## 则视为 2 次效果，共触发 2 次摸牌。
##

func test_heidi_passive_continuous_with_immediate_draws():
	# Playing a continuous boost whose effects include an "immediate" timing
	# (铁砂: cap_damage + immediate strike) should draw 1 card.
	position_players(player1, 5, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	player1.free_force = 1  # 铁砂 boost costs 1 force
	var cards_before = player1.deck.size()
	var howitzer = give_player_specific_card(player1, "heidi_selfpropelledhowitzer")
	# use_free_force=true: the 1-force cost is covered by free_force.
	assert_true(game_logic.do_boost(player1, howitzer, [], true))
	# 铁砂 is continuous and has an "immediate: strike" effect; any boost
	# resolution triggers the passive draw. The immediate strike puts the game
	# into WaitForStrike, so there is no end-of-turn draw to account for here.
	assert_eq(player1.deck.size(), cards_before - 1)

func test_heidi_passive_pure_continuous_draws():
	# Playing a pure continuous boost (no immediate/now effects) also draws 1
	# (the passive triggers on ANY boost resolution). Use 装甲兵 (continuous,
	# only during_strike effects).
	position_players(player1, 5, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	player1.free_force = 1  # 装甲兵 boost costs 1 force
	# 纯持续加成没有 immediate strike：boost 结算后 boost_play_cleanup 会触发
	# 回合末摸牌（check_hand_size_advance_turn）。用 skip_end_of_turn_draw 排除
	# 该干扰，使断言精确对应被动摸牌（恰好 1 张）。
	player1.skip_end_of_turn_draw = true
	var cards_before = player1.deck.size()
	var armor = give_player_specific_card(player1, "heidi_mechcannon")
	assert_true(game_logic.do_boost(player1, armor, [], true))
	# Passive draw on any boost — deck size decreases by exactly 1.
	assert_eq(player1.deck.size(), cards_before - 1)

##
## 海蒂觉醒技能：场上有持续加成时威力 + 2
##

func test_heidi_exceed_powerup_with_continuous_boost():
	# While exceeded with a continuous boost in play, all strikes gain +2 power.
	position_players(player1, 5, player2, 8)  # distance 3
	player1.discard_hand()
	player2.discard_hand()
	# Exceed Heidi first.
	give_gauge(player1, 3)
	assert_true(game_logic.do_exceed(player1, get_cards_from_gauge(player1, 3)))
	# Advance to player2 then back so player1 strikes next.
	advance_turn(player2)
	# Put a continuous boost in play: 装甲兵 via its parent 机械加农炮.
	player1.free_force = 1  # 装甲兵 boost costs 1 force
	var cannon = give_player_specific_card(player1, "heidi_mechcannon")
	assert_true(game_logic.do_boost(player1, cannon, [], true))
	# Now 装甲兵 (continuous) is in play. Strike with 匕首打击-插入
	# (range 1-3, power 2). Expected damage to opponent (life 30):
	# power 2 + exceed +2 + 装甲兵 during_strike +1 = 5, minus block armor 2
	# (p2 declines the when_hit force-for-armor: no hand cards to pay) = 3.
	advance_turn(player2)
	# 匕首打击的 hit 效果（boost_then_sustain）会创建 BoostNow 决策；清空手牌
	# 使其干净跳过（can_boost_something 手牌为空时不创建决策）。
	player1.discard_hand()
	execute_strike(player1, player2, "heidi_daggertrike", "standard_normal_block",
			false, false, [], [[]])
	# 30 - (5-2) = 27
	validate_life(player1, 30, player2, 27)

func test_heidi_exceed_no_powerup_without_continuous_boost():
	# Exceeded without any continuous boost: passive +2 does not apply.
	position_players(player1, 5, player2, 8)  # distance 3
	player1.discard_hand()
	player2.discard_hand()
	give_gauge(player1, 3)
	assert_true(game_logic.do_exceed(player1, get_cards_from_gauge(player1, 3)))
	advance_turn(player2)
	# No boost in play — strike with 匕首打击-插入 (power 2) vs block (armor 2):
	# damage = 2 - 2 = 0. (p2 declines the when_hit force-for-armor.)
	player1.discard_hand()
	execute_strike(player1, player2, "heidi_daggertrike", "standard_normal_block",
			false, false, [], [[]])
	validate_life(player1, 30, player2, 30)

##
## 铁砂 (cap_attack_damage_taken)
##

func test_heidi_ironsand_caps_damage_at_4():
	# 铁砂 (continuous, force_cost 1)：打出后立即 strike (immediate strike)。
	# 在这场立即战斗（双向）中 owner 承伤上限 4 (cap_attack_damage_taken，
	# 抵消护甲后)；战斗结束铁砂作为非维持持续加成自动弃置 —— 一次性效果，
	# 参考蕾米莉丝喷射汽油弹 (Napalm Stream) 的 during_strike cap 机制。
	position_players(player1, 5, player2, 7)  # distance 2
	player1.discard_hand()
	player2.discard_hand()
	player1.free_force = 1  # 铁砂 boost costs 1 force
	var howitzer = give_player_specific_card(player1, "heidi_selfpropelledhowitzer")
	assert_true(game_logic.do_boost(player1, howitzer, [], true))
	# 立即 strike：p1 顶牌 Sweep (power 6, speed 2) 进攻；p2 也出 Sweep 响应
	# （power 6 = p2 guard 6 → 6>6 不成立，p2 不晕 → Card2 反击）。
	# Card1: p1 Sweep 打 p2 → 6 伤 (p2 armor 0) → p2 24。
	# Card2: p2 Sweep 反击 p1 → 原始 6 → 铁砂 cap 4 → p1 只掉 4 → 26。
	set_player_topdeck(player1, "standard_normal_sweep")
	execute_strike(player1, player2, -1, "standard_normal_sweep", false, false, [], [])
	validate_life(player1, 26, player2, 24)
	# 战斗结束：铁砂未被打成维持（sustain_next_boost=false），cleanup 阶段
	# cleanup_continuous_boosts 自动将其弃置 → 不在持续加成区、已进弃牌堆。
	var in_play = false
	for card in player1.continuous_boosts:
		if card.definition['id'] == "heidi_selfpropelledhowitzer":
			in_play = true
	assert_false(in_play, "铁砂 should be auto-discarded after the immediate strike")
	var in_discards = false
	for card in player1.discards:
		if card.definition['id'] == "heidi_selfpropelledhowitzer":
			in_discards = true
	assert_true(in_discards, "铁砂 should be in the discard pile after auto-discard")

##
## 机械天才（匕首打击 boost）：从弃牌堆免费打出 1 张持续性加成
## 回归：开关扇 -> 机械天才 -> 选中弃牌堆持续加成时曾因 active_strike 为
## null（boost 阶段无 strike）而卡死，现应正常打出或干净跳过。
##

func test_heidi_mechanical_genius_plays_boost_with_free_force():
	# Play 机械天才 as a turn action with a 1-force continuous boost (装甲兵)
	# in the discard pile and a free force available: the boost should be
	# played (set as continuous) and the game must not stall.
	position_players(player1, 5, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	var armor = give_player_specific_card(player1, "heidi_mechcannon")
	player1.discard([armor])
	var mech_genius = give_player_specific_card(player1, "heidi_daggertrike")
	player1.free_force = 1
	assert_true(game_logic.do_boost(player1, mech_genius))
	assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseFromDiscard)
	assert_true(game_logic.do_choose_from_discard(player1, [armor]))
	# 装甲兵 should now be set as a continuous boost.
	var in_play = false
	for card in player1.continuous_boosts:
		if card.definition['id'] == "heidi_mechcannon":
			in_play = true
	assert_true(in_play, "装甲兵 should have been played from the discard pile")
	# Game must keep resolving (not stuck in ForceBoostSustainTopDiscard).
	assert_ne(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)

func test_heidi_mechanical_genius_ignores_force_cost_without_resources():
	# No free force and an empty hand: 机械天才 still plays the 1-force boost
	# for free and does not enter a payment decision.
	position_players(player1, 5, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	var armor = give_player_specific_card(player1, "heidi_mechcannon")
	player1.discard([armor])
	var mech_genius = give_player_specific_card(player1, "heidi_daggertrike")
	player1.free_force = 0
	assert_true(game_logic.do_boost(player1, mech_genius))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseFromDiscard)
	assert_true(game_logic.do_choose_from_discard(player1, [armor]))
	assert_true(player1.continuous_boosts.any(func(card): return card.id == armor),
			"装甲兵 should be played for free despite its printed force cost")
	assert_ne(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)

func test_heidi_mechanical_genius_does_not_spend_hand_for_force_cost():
	# A hand card is available, but 机械天才 must not spend it for the printed
	# force cost of the boost played from discard.
	position_players(player1, 5, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	var armor = give_player_specific_card(player1, "heidi_mechcannon")
	player1.discard([armor])
	var mech_genius = give_player_specific_card(player1, "heidi_daggertrike")
	var pay_card = give_player_specific_card(player1, "standard_normal_assault")
	player1.free_force = 0
	assert_true(game_logic.do_boost(player1, mech_genius))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseFromDiscard)
	assert_true(game_logic.do_choose_from_discard(player1, [armor]))
	# 装甲兵 now in play as a continuous boost.
	var in_play = false
	for card in player1.continuous_boosts:
		if card.definition['id'] == "heidi_mechcannon":
			in_play = true
	assert_true(in_play, "装甲兵 should be played without paying its force cost")
	assert_true(player1.is_card_in_hand(pay_card),
			"机械天才 should not discard a hand card for the played boost's force cost")
	# Game must keep resolving (not stuck).
	assert_ne(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)

func test_heidi_switch_fan_mech_genius_plays_stormgun_for_free():
	# Exact reported repro: 开关扇 -> 机械天才 -> choose 风暴枪 from the discard
	# pile for free. 风暴枪 has an immediate choice (advance/retreat) on its
	# boost, so after playing it, the game must offer that
	# choice (not stall), resolve it, put 风暴枪 in play, and return both 开关扇
	# and 机械天才 to hand.
	# NOTE: 风暴枪 is the boost name of the ultra card 铁路司机 (heidi_raildriver);
	# there is no separate "heidi_stormgun" card id.
	position_players(player1, 5, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	var stormgun = give_player_specific_card(player1, "heidi_raildriver")
	player1.discard([stormgun])
	var switch_fan = give_player_specific_card(player1, "heidi_ironknuckle")
	var mech_genius = give_player_specific_card(player1, "heidi_daggertrike")
	var pay_card = give_player_specific_card(player1, "standard_normal_assault")
	player1.free_force = 0
	# 1. Play 开关扇 as a turn action.
	assert_true(game_logic.do_boost(player1, switch_fan))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostNow)
	# 2. Reveal & execute 机械天才 from hand.
	assert_true(game_logic.do_boost(player1, mech_genius))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseFromDiscard)
	# 3. Choose 风暴枪 from the discard pile.
	assert_true(game_logic.do_choose_from_discard(player1, [stormgun]))
	# 4. 风暴枪's immediate choice (advance/retreat) must be offered without payment.
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice,
			"风暴枪's immediate choice must be offered without a payment decision")
	assert_true(player1.is_card_in_hand(pay_card), "机械天才 should not spend the available hand card")
	assert_true(game_logic.do_choice(player1, 0))
	# 7. 风暴枪 now in play as a continuous boost (the card is heidi_raildriver).
	var in_play = false
	for card in player1.continuous_boosts:
		if card.definition['id'] == "heidi_raildriver":
			in_play = true
	assert_true(in_play, "风暴枪 should be in play as a continuous boost")
	# 8. 机械天才 (the revealed boost) returns to hand via return_to_hand.
	#    开关扇 itself was played as a normal boost and is discarded (the
	#    revealed boost REPLACES 开关扇, per the boost_multiple rule).
	assert_true(player1.is_card_in_hand(mech_genius), "机械天才 should return to hand")
	assert_true(player1.is_card_in_discards(switch_fan), "开关扇 should be discarded as a played boost")
	# 9. Game keeps resolving (not stuck in a decision).
	assert_ne(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)

func test_heidi_switch_fan_into_mechanical_genius():
	# Exact reported repro: 开关扇 (boost_multiple) selects 机械天才, which then
	# plays a continuous boost from the discard pile. Previously this crashed
	# on a null active_strike; now it must resolve fully.
	position_players(player1, 5, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	var armor = give_player_specific_card(player1, "heidi_mechcannon")
	player1.discard([armor])
	var switch_fan = give_player_specific_card(player1, "heidi_ironknuckle")
	var mech_genius = give_player_specific_card(player1, "heidi_daggertrike")
	player1.free_force = 1
	# Play 开关扇 -> BoostNow decision.
	assert_true(game_logic.do_boost(player1, switch_fan))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostNow)
	# Choose 机械天才 as the revealed-and-executed immediate boost.
	assert_true(game_logic.do_boost(player1, mech_genius))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseFromDiscard)
	# Choose 装甲兵 from the discard pile.
	assert_true(game_logic.do_choose_from_discard(player1, [armor]))
	# 装甲兵 set as continuous boost.
	var in_play = false
	for card in player1.continuous_boosts:
		if card.definition['id'] == "heidi_mechcannon":
			in_play = true
	assert_true(in_play, "装甲兵 should be played from the discard pile via 开关扇 -> 机械天才")
	# 机械天才 (switch fan's return_to_hand target) must return to hand.
	var in_hand = false
	for card in player1.hand:
		if card.id == mech_genius:
			in_hand = true
	assert_true(in_hand, "机械天才 should return to hand after resolving (return_to_hand)")
	# Game must keep resolving (not stuck).
	assert_ne(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)

##
## 战斗后整理阶段：机械天才（开关扇路径）打出的持续加成必须被弃置。
## 回归：此前 discard_effect 误设 sustain:true，导致该持续加成在战斗后
## cleanup_continuous_boosts 中被当作“维持”而保留。只有匕首风暴的击中
## 效果（boost_then_sustain_topdeck, sustain:true）可以维持。
##

func test_heidi_switch_fan_mech_genius_boost_discarded_after_strike():
	# Exact reported scenario: 开关扇 -> 机械天才 -> play a continuous boost
	# from the discard pile. That boost must NOT be sustained; the strike's
	# cleanup phase (StrikeState_Cleanup_Complete -> cleanup_continuous_boosts)
	# must discard it again.
	position_players(player1, 5, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	var armor = give_player_specific_card(player1, "heidi_mechcannon")
	player1.discard([armor])
	var switch_fan = give_player_specific_card(player1, "heidi_ironknuckle")
	var mech_genius = give_player_specific_card(player1, "heidi_daggertrike")
	player1.free_force = 1
	# 开关扇 -> 选择机械天才 -> 从弃牌堆选择装甲兵。
	assert_true(game_logic.do_boost(player1, switch_fan))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostNow)
	assert_true(game_logic.do_boost(player1, mech_genius))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseFromDiscard)
	assert_true(game_logic.do_choose_from_discard(player1, [armor]))
	# 装甲兵 in play as a continuous boost.
	var in_play = false
	for card in player1.continuous_boosts:
		if card.definition['id'] == "heidi_mechcannon":
			in_play = true
	assert_true(in_play, "装甲兵 should be in play as a continuous boost")
	# 关键断言：不得被标记为维持，否则战斗后 cleanup 不会弃置它。
	assert_false(armor in player1.sustained_boosts,
			"装甲兵 must NOT be sustained (only 匕首风暴's hit effect sustains)")
	# 机械天才 returns to hand.
	var in_hand = false
	for card in player1.hand:
		if card.id == mech_genius:
			in_hand = true
	assert_true(in_hand, "机械天才 should return to hand")
	# 清空手牌（机械天才与被动摸牌所得），确保匕首打击 hit 时机无可选的持续加成，
	# 从而本测试只验证机械天才路径（sustain:false）打出的持续加成在战斗后被弃置。
	player1.discard_hand()
	# player2 结束回合，player1 发起战斗。
	advance_turn(player2)
	execute_strike(player1, player2, "heidi_daggertrike", "standard_normal_block",
			false, false, [], [[]])
	# 战斗后的整理阶段必须弃置未维持的持续加成（回到弃牌堆）。
	var still_in_play = false
	for card in player1.continuous_boosts:
		if card.definition['id'] == "heidi_mechcannon":
			still_in_play = true
	assert_false(still_in_play, "装甲兵 should be cleaned up after the strike")
	assert_true(player1.is_card_in_discards(armor),
			"装甲兵 should return to the discard pile after the strike")

##
## UA 摸牌计数：开关扇展示并执行的加成替代开关扇自身。
## Case A：开关扇 -> 展示 1 张即时加成并执行 = 只触发 1 次摸牌（被展示的加成）。
## Case B：开关扇 -> 机械天才 -> 再从弃牌堆打出 1 张持续加成 = 2 次效果，
##         触发 2 次摸牌（机械天才 + 弃牌堆打出的加成）。
##

func test_heidi_switch_fan_draws_once():
	# 开关扇 reveals an immediate boost and executes its effect. The revealed
	# boost REPLACES 开关扇, so the passive draw triggers exactly once
	# (for the revealed boost), not twice.
	position_players(player1, 5, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	var switch_fan = give_player_specific_card(player1, "heidi_ironknuckle")
	var steel_pilot = give_player_specific_card(player1, "heidi_steelpilot")
	# boost 结算后 boost_play_cleanup 会触发回合末摸牌（check_hand_size_advance_turn）
	# ——排除该干扰，使 deck 计数只反映被动摸牌。
	player1.skip_end_of_turn_draw = true
	var cards_before = player1.deck.size()
	# 开关扇 -> BoostNow decision.
	assert_true(game_logic.do_boost(player1, switch_fan))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostNow)
	# Reveal 钢铁机师 and execute it. 钢铁机师's self-discard is optional；展示并执行时
	# 这张牌**仍在手牌里**，所以会给出「弃至多 6 张」的可选决策（放弃即可继续结算）。
	assert_true(game_logic.do_boost(player1, steel_pilot))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseToDiscard,
			"钢铁机师 的弃牌是可选决策")
	assert_true(game_logic.do_choose_to_discard(player1, []))
	# Exactly ONE draw: the revealed boost (钢铁机师) counts; 开关扇 itself is
	# replaced and must NOT trigger its own draw.
	assert_eq(player1.deck.size(), cards_before - 1,
			"开关扇 replaced by the revealed boost: exactly 1 passive draw expected")
	# 钢铁机师 returns to hand (return_to_hand).
	var in_hand = false
	for card in player1.hand:
		if card.id == steel_pilot:
			in_hand = true
	assert_true(in_hand, "钢铁机师 should return to hand after being revealed and executed")
	# Game must keep resolving (not stuck in a decision).
	assert_ne(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)

func test_heidi_switch_fan_mech_genius_draws_twice():
	# 开关扇 reveals 机械天才, which plays another boost from the discard pile.
	# That is 2 boost resolutions total (机械天才 + the discarded boost), so the
	# passive draws exactly 2 cards; 开关扇 itself is replaced and draws 0.
	position_players(player1, 5, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	var armor = give_player_specific_card(player1, "heidi_mechcannon")
	player1.discard([armor])
	var switch_fan = give_player_specific_card(player1, "heidi_ironknuckle")
	var mech_genius = give_player_specific_card(player1, "heidi_daggertrike")
	player1.free_force = 1
	# 排除回合末摸牌干扰，使 deck 计数只反映被动摸牌。
	player1.skip_end_of_turn_draw = true
	var cards_before = player1.deck.size()
	# 开关扇 -> 机械天才 -> 从弃牌堆选择装甲兵。
	assert_true(game_logic.do_boost(player1, switch_fan))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostNow)
	assert_true(game_logic.do_boost(player1, mech_genius))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_ChooseFromDiscard)
	assert_true(game_logic.do_choose_from_discard(player1, [armor]))
	# Exactly TWO draws: 机械天才 (1) + 装甲兵 played from discard (1);
	# 开关扇 is replaced and must not draw (otherwise it would be 3).
	assert_eq(player1.deck.size(), cards_before - 2,
			"机械天才 + discarded boost = 2 passive draws; 开关扇 replaced (0)")
	# 装甲兵 in play as a continuous boost; 机械天才 returned to hand.
	var in_play = false
	for card in player1.continuous_boosts:
		if card.definition['id'] == "heidi_mechcannon":
			in_play = true
	assert_true(in_play, "装甲兵 should be in play as a continuous boost")
	var in_hand = false
	for card in player1.hand:
		if card.id == mech_genius:
			in_hand = true
	assert_true(in_hand, "机械天才 should return to hand")
	# Game must keep resolving (not stuck).
	assert_ne(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)

##
## 匕首打击·插入（cleanup 时机 boost_then_sustain）：击中后、本次战斗结束后
## （整理阶段 cleanup）才免费从手牌打出 1 张持续加成并维持它。
## 关键：cleanup 在伤害结算之后 → 打出的持续加成 during_strike 效果【不】合并
## 本次伤害（区别于旧 hit 时机近似，参考哈扎马蛇骸击）；加成用于后续回合。
## 用 condition "hit_opponent" 保留"击中才触发"（cleanup 时机本身无条件执行）。
##

func test_heidi_daggertrike_cleanup_boost_sustains_no_damage_merge():
	# p1 匕首打击 (power 2, range 1-3) vs p2 block (armor 2) @ distance 3：
	# 命中。伤害 = 2 - 2 = 0（装甲兵 during_strike +1 在 cleanup 才打出，不合并）。
	# block 反击 (power 0, attack_does_not_hit) 不命中 -> p1 不掉血。
	# p2 的 when_hit 决策不付 armor (def [[]])；cleanup BoostNow 选装甲兵 (init [armor])。
	# 注意：该 boost 是免费的 (ignore_costs) —— 不给 free_force，验证 0 force 也可打出。
	position_players(player1, 5, player2, 8)  # distance 3
	player1.discard_hand()
	player2.discard_hand()
	var armor = give_player_specific_card(player1, "heidi_mechcannon")  # 手牌持续加成
	execute_strike(player1, player2, "heidi_daggertrike", "standard_normal_block",
			false, false, [armor], [[]])
	validate_life(player1, 30, player2, 30)
	# cleanup 打出的装甲兵被维持：仍在 continuous_boosts、未进弃牌堆。
	# 注意：按运行时 id（armor）精确匹配，避免初始手牌中随机同名牌干扰。
	var in_play = false
	for card in player1.continuous_boosts:
		if card.id == armor:
			in_play = true
	assert_true(in_play, "装甲兵 should be in play as a sustained continuous boost after cleanup")
	var in_discards = false
	for card in player1.discards:
		if card.id == armor:
			in_discards = true
	assert_false(in_discards, "装甲兵 should not have been discarded at cleanup")

##
## 匕首风暴·三倍插入（hit 时机 choose_boosts_from_top_deck）：命中时【先查看】
## 牌库顶 3 张，然后免费打出并维持其中【任意数量】的持续加成，其余牌弃掉。
## 打出的持续加成 during_strike 效果合并进本次伤害。
## 2026-09-15 修正：原实现是引擎自动逐张翻开并全部打出（玩家看不到也选不了），
## 现改为多选决策（ChooseFromTopDeck + select_multiple）。
##

func test_heidi_daggerstorm_choose_some_of_topdeck_boosts_sustain_and_add_power():
	position_players(player1, 5, player2, 8)  # distance 3
	player1.discard_hand()
	player2.discard_hand()
	give_gauge(player1, 3)
	# set_player_topdeck 依次把牌插到牌库最顶，故最后一次调用在最上面：
	#   牌库顶 3 张 = 装甲兵（持续加成）、破坏光束（即时加成，不可选）、无止境（持续加成）
	set_player_topdeck(player1, "heidi_daggerstorm")     # 无止境
	set_player_topdeck(player1, "heidi_steelpilot")      # 破坏光束（即时加成）
	set_player_topdeck(player1, "heidi_mechcannon")      # 装甲兵
	var armor_id = player1.deck[0].id
	var beam_id = player1.deck[1].id
	var storm_id = player1.deck[2].id
	var daggerstorm = give_player_specific_card(player1, "heidi_daggerstorm")
	var block = give_player_specific_card(player2, "standard_normal_block")
	var gauge_ids = get_cards_from_gauge(player1, 3)
	# 查看 3 张后选择其中 2 张持续加成（装甲兵 + 无止境）；破坏光束不选 -> 弃掉。
	# init_choices: [gauge 支付, 选中的卡 id 列表, action]。
	execute_strike(player1, player2, daggerstorm, block, false, false,
			[gauge_ids, [armor_id, storm_id], "boost"], [[]])
	# 伤害 = 3（匕首风暴）+ 1（装甲兵）+ 2（无止境）= 6 - 2（block armor）= 4 -> p2 26。
	validate_life(player1, 30, player2, 26)
	# 被选中的 2 张持续加成在战斗 Cleanup 后仍留场（被维持）。
	var boost_ids_in_play = []
	for card in player1.continuous_boosts:
		boost_ids_in_play.append(card.id)
	assert_true(armor_id in boost_ids_in_play, "装甲兵 should be set as a sustained boost")
	assert_true(storm_id in boost_ids_in_play, "无止境 should be set as a sustained boost")
	assert_false(beam_id in boost_ids_in_play, "the unchosen immediate boost must not be played")
	# 未被选中的第 3 张（破坏光束）直接进弃牌堆。
	var beam_discarded = false
	for card in player1.discards:
		if card.id == beam_id:
			beam_discarded = true
	assert_true(beam_discarded, "the unchosen card should be discarded")

func test_heidi_daggerstorm_can_choose_none_of_topdeck_cards():
	position_players(player1, 5, player2, 8)  # distance 3
	player1.discard_hand()
	player2.discard_hand()
	give_gauge(player1, 3)
	set_player_topdeck(player1, "heidi_mechcannon")
	set_player_topdeck(player1, "heidi_mechcannon")
	set_player_topdeck(player1, "heidi_mechcannon")
	var top_ids = [player1.deck[0].id, player1.deck[1].id, player1.deck[2].id]
	var daggerstorm = give_player_specific_card(player1, "heidi_daggerstorm")
	var block = give_player_specific_card(player2, "standard_normal_block")
	var gauge_ids = get_cards_from_gauge(player1, 3)
	# 查看 3 张后一张都不选（pass）：3 张全部弃掉，不打出任何加成。
	execute_strike(player1, player2, daggerstorm, block, false, false,
			[gauge_ids, -1, "pass"], [[]])
	# 伤害 = 3（匕首风暴）- 2（block armor）= 1 -> p2 29。
	validate_life(player1, 30, player2, 29)
	for card in player1.continuous_boosts:
		assert_false(card.id in top_ids, "no looked-at card should be played as a boost")
	for card_id in top_ids:
		var found_in_discards = false
		for card in player1.discards:
			if card.id == card_id:
				found_in_discards = true
		assert_true(found_in_discards, "every looked-at card should be discarded when none is chosen")

##
## 铁路司机（ultra，cleanup 时机 boost_then_sustain）：击中后、本次战斗结束后
## （整理阶段）免费从手牌打出 1 张【任意】加成；若是持续加成则维持（留场），
## 若是即时加成则结算后直接弃置（boost_then_sustain 的维持只作用于持续加成）。
## 打出的加成 during_strike 效果【不】合并本次伤害（cleanup 在伤害结算后）。
##

func test_heidi_raildriver_cleanup_continuous_boost_sustains():
	# p1 铁路司机 (power 6, range 1-2, ultra 3 gauge) vs p2 block @ distance 2：
	# 命中 -> 6 > block guard 3 -> p2 晕（block 不反击，p1 不掉血）。
	# 伤害 = 6 - 2 (block armor) = 4（装甲兵 during_strike +1 不合并）-> p2 26。
	# p2 when_hit 不付 armor (def [[]])；cleanup BoostNow 选装甲兵 (init [gauge_ids, armor])。
	# 免费语义：不给 free_force（0 force），依赖引擎 ignore_costs 免费打出。
	position_players(player1, 5, player2, 7)  # distance 2
	player1.discard_hand()
	player2.discard_hand()
	var armor = give_player_specific_card(player1, "heidi_mechcannon")
	var raildriver = give_player_specific_card(player1, "heidi_raildriver")
	var block = give_player_specific_card(player2, "standard_normal_block")
	give_gauge(player1, 3)
	var gauge_ids = get_cards_from_gauge(player1, 3)
	execute_strike(player1, player2, raildriver, block, false, false,
			[gauge_ids, armor], [[]])
	validate_life(player1, 30, player2, 26)
	# cleanup 打出的持续加成（装甲兵）被维持：留场、未弃置。
	var in_play = false
	for card in player1.continuous_boosts:
		if card.id == armor:
			in_play = true
	assert_true(in_play, "装甲兵 should be in play as a sustained continuous boost after 铁路司机 cleanup")
	var in_discards = false
	for card in player1.discards:
		if card.id == armor:
			in_discards = true
	assert_false(in_discards, "装甲兵 should not have been discarded")

func test_heidi_raildriver_cleanup_immediate_boost_discarded():
	# cleanup 打出的是【即时加成】（破坏光束，钢铁机师 boost，optional 自弃手牌）：
	# 结算其立即效果后直接进弃牌堆——不被维持、不进持续加成区
	# （"如果是持续性加成，那么维持它"：即时加成不属于持续加成）。
	# 免费语义：破坏光束 force_cost 2，不给 free_force（0 force），
	# 依赖引擎 ignore_costs 免费打出。
	position_players(player1, 5, player2, 7)  # distance 2
	player1.discard_hand()
	player2.discard_hand()
	var steel_pilot = give_player_specific_card(player1, "heidi_steelpilot")
	var raildriver = give_player_specific_card(player1, "heidi_raildriver")
	var block = give_player_specific_card(player2, "standard_normal_block")
	give_gauge(player1, 3)
	var gauge_ids = get_cards_from_gauge(player1, 3)
	execute_strike(player1, player2, raildriver, block, false, false,
			[gauge_ids, steel_pilot], [[]])
	validate_life(player1, 30, player2, 26)
	# 破坏光束（即时加成）打完进弃牌堆；不在持续加成区（不维持）。
	assert_true(player1.is_card_in_discards(steel_pilot),
			"破坏光束 (immediate boost) should be discarded after resolving")
	var in_play = false
	for card in player1.continuous_boosts:
		if card.id == steel_pilot:
			in_play = true
	assert_false(in_play, "immediate boost should not enter continuous_boosts")

##
## 钢铁机师（hit 击退 4 + 每未击退 1 格威力 +1）：击退必须自动结算，
## 不得弹出"选择同时结算效果"对话框（效果带 resolve_before_simultaneous_effects）。
##

func test_heidi_steelpilot_auto_push_four_and_powerup_from_unpushed():
	# p1 钢铁机师 (power 2, range 1-2, speed 4) vs p2 block @ 距离 1。
	# 命中 -> 自动击退 4 格：p2 由 6 推到场地最右 9（实际 3 格，未推 1 格）。
	# 未推 1 格 -> strike_x = 1 -> 威力 +1。伤害 = 2 + 1 - block armor 2 = 1 -> p2 29。
	# 引擎不得要求玩家选择同时结算效果（否则 execute_strike 会报
	# "missing input for DecisionType_ChooseSimultaneousEffect"）。
	position_players(player1, 5, player2, 6)
	player1.discard_hand()
	player2.discard_hand()
	var pilot = give_player_specific_card(player1, "heidi_steelpilot")
	var block = give_player_specific_card(player2, "standard_normal_block")
	execute_strike(player1, player2, pilot, block, false, false, [], [[]])
	validate_positions(player1, 5, player2, 9)
	validate_life(player1, 30, player2, 29)

##
## 风暴枪加成（铁路司机的 boost）："前进或后退至多 2 格"必须包含"原地不动"，
## 引擎用 StrikeEffects.Pass（什么都不做）表示不动。
##

func test_heidi_stormgun_choice_includes_stay_in_place():
	position_players(player1, 5, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	var stormgun = give_player_specific_card(player1, "heidi_raildriver")
	player1.free_force = 1
	# 风暴枪 boost force_cost 1：用免费力支付。
	assert_true(game_logic.do_boost(player1, stormgun, [], true),
			"风暴枪 should be boostable with free force")
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_EffectChoice)
	var choices = game_logic.decision_info.choice
	assert_eq(choices.size(), 5, "风暴枪 choice should offer 5 options incl. staying in place")
	assert_eq(choices[4]['effect_type'], "pass",
			"the last option must be the 'stay in place' (pass) option")
	# 选择原地不动 -> 双方位置不变，结算正常完成。
	assert_true(game_logic.do_choice(player1, 4))
	validate_positions(player1, 5, player2, 7)
	assert_ne(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)

## 展示并执行 = 不打出：被展示的卡始终留在手牌、不进入加成区，也不产生「打出加成」事件。
func test_heidi_switch_fan_reveal_does_not_play_the_card():
	position_players(player1, 5, player2, 7)
	player1.discard_hand()
	player2.discard_hand()
	var switch_fan = give_player_specific_card(player1, "heidi_ironknuckle")
	var steel_pilot = give_player_specific_card(player1, "heidi_steelpilot")
	player1.skip_end_of_turn_draw = true
	assert_true(game_logic.do_boost(player1, switch_fan))
	assert_eq(game_logic.decision_info.type, Enums.DecisionType.DecisionType_BoostNow)
	game_logic.get_latest_events()  # 清空事件队列，只看被展示那张牌产生的事件
	assert_true(game_logic.do_boost(player1, steel_pilot))
	var events = game_logic.get_latest_events()
	validate_not_has_event(events, Enums.EventType.EventType_Boost_Played, player1, steel_pilot)
	validate_has_event(events, Enums.EventType.EventType_RevealCard, player1, steel_pilot)
	assert_true(player1.is_card_in_hand(steel_pilot), "被展示的加成应始终留在手牌")
	assert_eq(player1.continuous_boosts.size(), 0, "被展示的加成不应进入加成区")
	# 结算完（放弃钢铁机师 的可选弃牌）后不应卡在决策里。
	if game_logic.game_state == Enums.GameState.GameState_PlayerDecision:
		assert_true(game_logic.do_choose_to_discard(player1, []))
	assert_ne(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
	# 开关扇 本身是正常打出的即时加成，结算完毕后进入弃牌堆。
	assert_true(player1.is_card_in_discards(switch_fan), "开关扇 本身仍是被正常打出的")
