extends ExceedGutTest

func who_am_i():
	return "renea"

const GameScene = preload("res://scenes/game/game.tscn")

func make_game_with_deck(deck_id, base_id = ""):
	var game = GameScene.instantiate()
	game.set_not_started_directly()
	add_child(game)
	game.player_deck = {'id': deck_id}
	if base_id:
		game.player_deck['base_id'] = base_id
	return game

func test_entrance_plays_once_when_local_player_is_eugenia():
	var game = make_game_with_deck("eugenia")
	game.try_play_match_start_entrance()
	await get_tree().process_frame
	assert_not_null(game.entrance_animation, "Entrance animation should be created for Eugenia player")
	assert_true(game.entrance_animation.is_playing(), "Entrance animation should be playing")
	assert_false(game.entrance_animation.sprite_frames.get_animation_loop("entrance"),
			"Entrance animation should play exactly once (no loop)")
	assert_eq(game.entrance_animation.sprite_frames.get_frame_count("entrance"), 14,
			"Entrance animation should have all 14 frames")
	game.queue_free()
	await get_tree().process_frame

func test_no_entrance_when_local_player_is_not_eugenia():
	var game = make_game_with_deck("renea")
	game.try_play_match_start_entrance()
	await get_tree().process_frame
	assert_null(game.entrance_animation, "No entrance animation for non-Eugenia player")
	game.queue_free()
	await get_tree().process_frame

func test_entrance_plays_for_eugenia_skin_1():
	var game = make_game_with_deck("eugenia_1", "eugenia")
	game.try_play_match_start_entrance()
	await get_tree().process_frame
	assert_not_null(game.entrance_animation, "Entrance animation should play for Eugenia skin 1")
	assert_true(game.entrance_animation.is_playing(), "Skin 1 entrance animation should be playing")
	game.queue_free()
	await get_tree().process_frame

func test_entrance_plays_for_eugenia_skin_2():
	var game = make_game_with_deck("eugenia_2", "eugenia")
	game.try_play_match_start_entrance()
	await get_tree().process_frame
	assert_not_null(game.entrance_animation, "Entrance animation should play for Eugenia skin 2")
	assert_true(game.entrance_animation.is_playing(), "Skin 2 entrance animation should be playing")
	game.queue_free()
	await get_tree().process_frame

func test_no_entrance_for_other_character_skin():
	var game = make_game_with_deck("renea_1", "renea")
	game.try_play_match_start_entrance()
	await get_tree().process_frame
	assert_null(game.entrance_animation, "No entrance animation for other character's skin")
	game.queue_free()
	await get_tree().process_frame

func test_entrance_is_removed_after_finishing():
	var game = make_game_with_deck("eugenia")
	game.try_play_match_start_entrance()
	await get_tree().process_frame
	assert_not_null(game.entrance_animation)
	game._on_entrance_animation_finished()
	await get_tree().process_frame
	assert_null(game.entrance_animation, "Entrance animation should be cleaned up after finishing")
	game.queue_free()
	await get_tree().process_frame

func test_entrance_scaled_to_screen():
	var game = make_game_with_deck("eugenia")
	game.try_play_match_start_entrance()
	await get_tree().process_frame
	assert_not_null(game.entrance_animation)
	var frame_size = game.entrance_animation.sprite_frames.get_frame_texture("entrance", 0).get_size()
	var displayed_size = frame_size * game.entrance_animation.scale
	assert_lte(displayed_size.x, 1280.0, "Entrance width should fit the screen")
	assert_lte(displayed_size.y, 720.0, "Entrance height should fit the screen")
	game.queue_free()
	await get_tree().process_frame

# --- Eugenia awaken closeup ---

func test_awaken_entrance_plays_when_local_player_is_eugenia():
	var game = make_game_with_deck("eugenia")
	game._play_awaken_entrance()
	await get_tree().process_frame
	assert_not_null(game.awaken_animation, "Awaken animation should be created for Eugenia player")
	assert_true(game.awaken_animation.is_playing(), "Awaken animation should be playing")
	assert_false(game.awaken_animation.sprite_frames.get_animation_loop("awaken"),
			"Awaken animation should play exactly once (no loop)")
	assert_eq(game.awaken_animation.sprite_frames.get_frame_count("awaken"), 14,
			"Awaken animation should have all 14 frames")
	game.queue_free()
	await get_tree().process_frame

func test_awaken_entrance_plays_for_eugenia_skin():
	var game = make_game_with_deck("eugenia_2", "eugenia")
	game._play_awaken_entrance()
	await get_tree().process_frame
	assert_not_null(game.awaken_animation, "Awaken animation should play for Eugenia skin")
	assert_true(game.awaken_animation.is_playing(), "Skin awaken animation should be playing")
	game.queue_free()
	await get_tree().process_frame

func test_no_awaken_entrance_for_non_eugenia_player():
	var game = make_game_with_deck("renea")
	game._play_awaken_entrance()
	await get_tree().process_frame
	assert_null(game.awaken_animation, "No awaken animation for non-Eugenia player")
	game.queue_free()
	await get_tree().process_frame

func test_awaken_entrance_is_removed_after_finishing():
	var game = make_game_with_deck("eugenia")
	game._play_awaken_entrance()
	await get_tree().process_frame
	assert_not_null(game.awaken_animation)
	game._on_awaken_animation_finished()
	await get_tree().process_frame
	assert_null(game.awaken_animation, "Awaken animation should be cleaned up after finishing")
	game.queue_free()
	await get_tree().process_frame

# --- Eugenia Cat's Cradle hit closeup ---
# Hit closeup is split per side: the attacker's client plays the right-side
# frames, the defender's client plays the left-side frames. When both
# players attack with Cradle in the same strike, each client shows both.

func test_cats_cradle_right_entrance_plays_when_local_player_attacks():
	# Local Eugenia client playing Cat's Cradle (attacker side) -> right frames.
	var game = make_game_with_deck("eugenia")
	game._play_cats_cradle_entrance(true)
	await get_tree().process_frame
	assert_not_null(game.cats_cradle_animation_right, "Cat's Cradle right animation should be created for the attacker")
	assert_null(game.cats_cradle_animation_left, "Cat's Cradle left animation should NOT be created for the attacker")
	assert_true(game.cats_cradle_animation_right.is_playing(), "Cat's Cradle right animation should be playing")
	assert_false(game.cats_cradle_animation_right.sprite_frames.get_animation_loop("cats_cradle"),
			"Cat's Cradle right animation should play exactly once (no loop)")
	assert_eq(game.cats_cradle_animation_right.sprite_frames.get_frame_count("cats_cradle"), 14,
			"Cat's Cradle right animation should have all 14 frames")
	game.queue_free()
	await get_tree().process_frame

func test_cats_cradle_left_entrance_plays_when_opponent_attacks():
	# Non-Eugenia client, opponent (Eugenia) plays Cat's Cradle -> left frames.
	var game = make_game_with_deck("renea")
	game._play_cats_cradle_entrance(false)
	await get_tree().process_frame
	assert_not_null(game.cats_cradle_animation_left, "Cat's Cradle left animation should be created for the defender")
	assert_null(game.cats_cradle_animation_right, "Cat's Cradle right animation should NOT be created for the defender")
	assert_true(game.cats_cradle_animation_left.is_playing(), "Cat's Cradle left animation should be playing")
	assert_eq(game.cats_cradle_animation_left.sprite_frames.get_frame_count("cats_cradle"), 14,
			"Cat's Cradle left animation should have all 14 frames")
	game.queue_free()
	await get_tree().process_frame

func test_cats_cradle_left_and_right_play_side_by_side_when_both_players_attack():
	# Both players attack with Cat's Cradle in the same strike -> each client
	# shows both versions at the same time (right = local Cradle, left = opponent).
	var game = make_game_with_deck("eugenia")
	game._play_cats_cradle_entrance(true)
	game._play_cats_cradle_entrance(false)
	await get_tree().process_frame
	assert_not_null(game.cats_cradle_animation_right, "Right closeup should exist when local player attacks")
	assert_not_null(game.cats_cradle_animation_left, "Left closeup should exist when opponent attacks")
	assert_true(game.cats_cradle_animation_right.is_playing(), "Right closeup should be playing")
	assert_true(game.cats_cradle_animation_left.is_playing(), "Left closeup should be playing")
	game.queue_free()
	await get_tree().process_frame

func test_cats_cradle_right_entrance_is_removed_after_finishing():
	var game = make_game_with_deck("eugenia")
	game._play_cats_cradle_entrance(true)
	await get_tree().process_frame
	assert_not_null(game.cats_cradle_animation_right)
	game._on_cats_cradle_animation_finished(true)
	await get_tree().process_frame
	assert_null(game.cats_cradle_animation_right, "Cat's Cradle right animation should be cleaned up after finishing")
	game.queue_free()
	await get_tree().process_frame

func test_cats_cradle_left_entrance_is_removed_after_finishing():
	var game = make_game_with_deck("eugenia")
	game._play_cats_cradle_entrance(false)
	await get_tree().process_frame
	assert_not_null(game.cats_cradle_animation_left)
	game._on_cats_cradle_animation_finished(false)
	await get_tree().process_frame
	assert_null(game.cats_cradle_animation_left, "Cat's Cradle left animation should be cleaned up after finishing")
	game.queue_free()
	await get_tree().process_frame

func test_cats_cradle_right_entrance_deduped_on_second_call():
	# Calling _play_cats_cradle_entrance(true) twice should not create a
	# second right-side animation; the first one should still be playing.
	var game = make_game_with_deck("eugenia")
	game._play_cats_cradle_entrance(true)
	await get_tree().process_frame
	var first = game.cats_cradle_animation_right
	game._play_cats_cradle_entrance(true)
	await get_tree().process_frame
	assert_eq(game.cats_cradle_animation_right, first, "Second right-side play should reuse the existing animation")
	game.queue_free()
	await get_tree().process_frame

func test_cats_cradle_right_entrance_plays_for_eugenia_skin_1():
	# Skin decks keep base_id "eugenia"; the Cradle closeup must still fire
	# for the attacker side on both skins.
	var game = make_game_with_deck("eugenia_1", "eugenia")
	game._play_cats_cradle_entrance(true)
	await get_tree().process_frame
	assert_not_null(game.cats_cradle_animation_right, "Right closeup should play for Eugenia skin 1")
	assert_true(game.cats_cradle_animation_right.is_playing(), "Skin 1 right closeup should be playing")
	game.queue_free()
	await get_tree().process_frame

func test_cats_cradle_left_entrance_plays_for_eugenia_skin_2():
	var game = make_game_with_deck("eugenia_2", "eugenia")
	game._play_cats_cradle_entrance(false)
	await get_tree().process_frame
	assert_not_null(game.cats_cradle_animation_left, "Left closeup should play for Eugenia skin 2")
	assert_true(game.cats_cradle_animation_left.is_playing(), "Skin 2 left closeup should be playing")
	game.queue_free()
	await get_tree().process_frame

# --- Eugenia Queen of Hearts hit closeup ---
# Same per-side split as Cat's Cradle (right = attacker side, left = defender).

func test_qoh_right_entrance_plays_when_local_player_attacks():
	# Local Eugenia client playing Queen of Hearts (attacker side) -> right frames.
	var game = make_game_with_deck("eugenia")
	game._play_qoh_entrance(true)
	await get_tree().process_frame
	assert_not_null(game.qoh_animation_right, "Queen of Hearts right animation should be created for the attacker")
	assert_null(game.qoh_animation_left, "Queen of Hearts left animation should NOT be created for the attacker")
	assert_true(game.qoh_animation_right.is_playing(), "Queen of Hearts right animation should be playing")
	assert_false(game.qoh_animation_right.sprite_frames.get_animation_loop("qoh"),
			"Queen of Hearts right animation should play exactly once (no loop)")
	assert_eq(game.qoh_animation_right.sprite_frames.get_frame_count("qoh"), 14,
			"Queen of Hearts right animation should have all 14 frames")
	game.queue_free()
	await get_tree().process_frame

func test_qoh_left_entrance_plays_when_opponent_attacks():
	# Non-Eugenia client, opponent (Eugenia) plays Queen of Hearts -> left frames.
	var game = make_game_with_deck("renea")
	game._play_qoh_entrance(false)
	await get_tree().process_frame
	assert_not_null(game.qoh_animation_left, "Queen of Hearts left animation should be created for the defender")
	assert_null(game.qoh_animation_right, "Queen of Hearts right animation should NOT be created for the defender")
	assert_true(game.qoh_animation_left.is_playing(), "Queen of Hearts left animation should be playing")
	assert_eq(game.qoh_animation_left.sprite_frames.get_frame_count("qoh"), 14,
			"Queen of Hearts left animation should have all 14 frames")
	game.queue_free()
	await get_tree().process_frame

func test_qoh_left_and_right_play_side_by_side_when_both_players_attack():
	var game = make_game_with_deck("eugenia")
	game._play_qoh_entrance(true)
	game._play_qoh_entrance(false)
	await get_tree().process_frame
	assert_not_null(game.qoh_animation_right, "Right closeup should exist when local player attacks")
	assert_not_null(game.qoh_animation_left, "Left closeup should exist when opponent attacks")
	assert_true(game.qoh_animation_right.is_playing(), "Right closeup should be playing")
	assert_true(game.qoh_animation_left.is_playing(), "Left closeup should be playing")
	game.queue_free()
	await get_tree().process_frame

func test_qoh_right_entrance_is_removed_after_finishing():
	var game = make_game_with_deck("eugenia")
	game._play_qoh_entrance(true)
	await get_tree().process_frame
	assert_not_null(game.qoh_animation_right)
	game._on_qoh_animation_finished(true)
	await get_tree().process_frame
	assert_null(game.qoh_animation_right, "Queen of Hearts right animation should be cleaned up after finishing")
	game.queue_free()
	await get_tree().process_frame

func test_qoh_left_entrance_is_removed_after_finishing():
	var game = make_game_with_deck("eugenia")
	game._play_qoh_entrance(false)
	await get_tree().process_frame
	assert_not_null(game.qoh_animation_left)
	game._on_qoh_animation_finished(false)
	await get_tree().process_frame
	assert_null(game.qoh_animation_left, "Queen of Hearts left animation should be cleaned up after finishing")
	game.queue_free()
	await get_tree().process_frame

func test_qoh_right_entrance_plays_for_eugenia_skin_1():
	var game = make_game_with_deck("eugenia_1", "eugenia")
	game._play_qoh_entrance(true)
	await get_tree().process_frame
	assert_not_null(game.qoh_animation_right, "Right QOH closeup should play for Eugenia skin 1")
	assert_true(game.qoh_animation_right.is_playing(), "Skin 1 right QOH closeup should be playing")
	game.queue_free()
	await get_tree().process_frame

func test_qoh_left_entrance_plays_for_eugenia_skin_2():
	var game = make_game_with_deck("eugenia_2", "eugenia")
	game._play_qoh_entrance(false)
	await get_tree().process_frame
	assert_not_null(game.qoh_animation_left, "Left QOH closeup should play for Eugenia skin 2")
	assert_true(game.qoh_animation_left.is_playing(), "Skin 2 left QOH closeup should be playing")
	game.queue_free()
	await get_tree().process_frame

# --- Eugenia Queen of Hearts damage-resolve effect ---

func test_qoh_damage_effect_plays_when_local_player_is_eugenia():
	var game = make_game_with_deck("eugenia")
	game._play_qoh_damage_effect()
	await get_tree().process_frame
	assert_not_null(game.qoh_damage_animation, "Queen of Hearts damage effect should be created")
	assert_true(game.qoh_damage_animation.is_playing(), "Queen of Hearts damage effect should be playing")
	assert_false(game.qoh_damage_animation.sprite_frames.get_animation_loop("qoh_damage"),
			"Queen of Hearts damage effect should play exactly once (no loop)")
	assert_eq(game.qoh_damage_animation.sprite_frames.get_frame_count("qoh_damage"), 89,
			"Queen of Hearts damage effect should have all 89 frames")
	game.queue_free()
	await get_tree().process_frame

func test_qoh_damage_effect_plays_for_non_eugenia_player():
	# The damage-resolve effect is visible to BOTH players, same as the hit closeup.
	var game = make_game_with_deck("renea")
	game._play_qoh_damage_effect()
	await get_tree().process_frame
	assert_not_null(game.qoh_damage_animation, "Queen of Hearts damage effect should play on the opponent's client too")
	assert_true(game.qoh_damage_animation.is_playing(), "Opponent-side damage effect should be playing")
	game.queue_free()
	await get_tree().process_frame

func test_qoh_damage_effect_is_removed_after_finishing():
	var game = make_game_with_deck("eugenia")
	game._play_qoh_damage_effect()
	await get_tree().process_frame
	assert_not_null(game.qoh_damage_animation)
	game._on_qoh_damage_effect_finished()
	await get_tree().process_frame
	assert_null(game.qoh_damage_animation, "Queen of Hearts damage effect should be cleaned up after finishing")
	game.queue_free()
	await get_tree().process_frame

func test_qoh_damage_effect_plays_for_eugenia_skin_1():
	# The 10-second damage effect also keys off the card definition id, so it
	# fires for both skins too.
	var game = make_game_with_deck("eugenia_1", "eugenia")
	game._play_qoh_damage_effect()
	await get_tree().process_frame
	assert_not_null(game.qoh_damage_animation, "QOH damage effect should play for Eugenia skin 1")
	assert_true(game.qoh_damage_animation.is_playing(), "Skin 1 QOH damage effect should be playing")
	game.queue_free()
	await get_tree().process_frame

func test_qoh_damage_effect_plays_for_eugenia_skin_2():
	var game = make_game_with_deck("eugenia_2", "eugenia")
	game._play_qoh_damage_effect()
	await get_tree().process_frame
	assert_not_null(game.qoh_damage_animation, "QOH damage effect should play for Eugenia skin 2")
	assert_true(game.qoh_damage_animation.is_playing(), "Skin 2 QOH damage effect should be playing")
	game.queue_free()
	await get_tree().process_frame

# --- Eugenia Time for Tea (Plot Hook action skill) closeup ---

func test_tea_time_entrance_plays_once():
	var game = make_game_with_deck("eugenia")
	game._play_tea_time_entrance()
	await get_tree().process_frame
	assert_not_null(game.tea_time_animation, "Time for Tea closeup should be created")
	assert_true(game.tea_time_animation.is_playing(), "Time for Tea closeup should be playing")
	assert_false(game.tea_time_animation.sprite_frames.get_animation_loop("tea_time"),
			"Time for Tea closeup should play exactly once (no loop)")
	assert_eq(game.tea_time_animation.sprite_frames.get_frame_count("tea_time"), 14,
			"Time for Tea closeup should have all 14 frames")
	game.queue_free()
	await get_tree().process_frame

func test_tea_time_entrance_plays_for_eugenia_skin_2():
	var game = make_game_with_deck("eugenia_2", "eugenia")
	game._play_tea_time_entrance()
	await get_tree().process_frame
	assert_not_null(game.tea_time_animation, "Time for Tea closeup should play for Eugenia skin 2")
	assert_true(game.tea_time_animation.is_playing(), "Skin 2 Time for Tea closeup should be playing")
	game.queue_free()
	await get_tree().process_frame

func test_tea_time_entrance_deduped_on_second_call():
	var game = make_game_with_deck("eugenia")
	game._play_tea_time_entrance()
	await get_tree().process_frame
	var first = game.tea_time_animation
	game._play_tea_time_entrance()
	await get_tree().process_frame
	assert_eq(game.tea_time_animation, first, "Second play should reuse the existing animation")
	game.queue_free()
	await get_tree().process_frame

# --- Eugenia Cat's Cradle hit closeup (full-screen damage-resolve effect) ---

func test_cats_cradle_hit_plays_once():
	var game = make_game_with_deck("eugenia")
	game._play_cats_cradle_hit()
	await get_tree().process_frame
	assert_not_null(game.cats_cradle_hit_animation, "Cat's Cradle hit effect should be created")
	assert_true(game.cats_cradle_hit_animation.is_playing(), "Cat's Cradle hit effect should be playing")
	assert_false(game.cats_cradle_hit_animation.sprite_frames.get_animation_loop("cats_cradle_hit"),
			"Cat's Cradle hit effect should play exactly once (no loop)")
	assert_eq(game.cats_cradle_hit_animation.sprite_frames.get_frame_count("cats_cradle_hit"), 26,
			"Cat's Cradle hit effect should have all 26 frames")
	# Cover-scale: scale should be the larger of the two aspect ratios so the
	# image fills the screen with edge cropping (no letterboxing).
	var frame_size = game.cats_cradle_hit_animation.sprite_frames.get_frame_texture("cats_cradle_hit", 0).get_size()
	var displayed_size = frame_size * game.cats_cradle_hit_animation.scale
	assert_gte(displayed_size.x, 1280.0, "Cat's Cradle hit width should cover the screen")
	assert_gte(displayed_size.y, 720.0, "Cat's Cradle hit height should cover the screen")
	game.queue_free()
	await get_tree().process_frame

func test_cats_cradle_hit_plays_for_eugenia_skin_1():
	var game = make_game_with_deck("eugenia_1", "eugenia")
	game._play_cats_cradle_hit()
	await get_tree().process_frame
	assert_not_null(game.cats_cradle_hit_animation, "Cat's Cradle hit effect should play for Eugenia skin 1")
	assert_true(game.cats_cradle_hit_animation.is_playing(), "Skin 1 Cat's Cradle hit effect should be playing")
	game.queue_free()
	await get_tree().process_frame

func test_cats_cradle_hit_plays_for_eugenia_skin_2():
	var game = make_game_with_deck("eugenia_2", "eugenia")
	game._play_cats_cradle_hit()
	await get_tree().process_frame
	assert_not_null(game.cats_cradle_hit_animation, "Cat's Cradle hit effect should play for Eugenia skin 2")
	assert_true(game.cats_cradle_hit_animation.is_playing(), "Skin 2 Cat's Cradle hit effect should be playing")
	game.queue_free()
	await get_tree().process_frame

func test_cats_cradle_hit_deduped_on_second_call():
	var game = make_game_with_deck("eugenia")
	game._play_cats_cradle_hit()
	await get_tree().process_frame
	var first = game.cats_cradle_hit_animation
	game._play_cats_cradle_hit()
	await get_tree().process_frame
	assert_eq(game.cats_cradle_hit_animation, first, "Second play should reuse the existing animation")
	game.queue_free()
	await get_tree().process_frame

# --- Hit-gated ultra closeups: armed on activation, played only on hit ---

func test_cats_cradle_closeup_pending_cleared_on_miss():
	# A miss (Strike_Miss for the attacker side) must drop the armed closeup
	# and never create an animation.
	var game = make_game_with_deck("eugenia")
	game.cats_cradle_right_pending_this_strike = true
	game.qoh_right_pending_this_strike = true
	game._on_strike_miss({"event_player": Enums.PlayerId.PlayerId_Player, "number": -1, "event_type": Enums.EventType.EventType_Strike_Miss})
	await get_tree().process_frame
	assert_false(game.cats_cradle_right_pending_this_strike,
			"Miss should clear the armed Cat's Cradle closeup for the attacker side")
	assert_false(game.qoh_right_pending_this_strike,
			"Miss should clear the armed QOH closeup for the attacker side")
	assert_null(game.cats_cradle_animation_right, "Miss must not create any closeup animation")
	assert_null(game.qoh_animation_right, "Miss must not create any QOH animation")
	game.queue_free()
	await get_tree().process_frame

func test_cats_cradle_closeup_pending_kept_for_other_side_on_miss():
	# A miss by the OPPONENT only clears the opponent's (left) pending flags;
	# the local player's (right) pending closeup is untouched.
	var game = make_game_with_deck("eugenia")
	game.cats_cradle_right_pending_this_strike = true
	game.cats_cradle_left_pending_this_strike = true
	game._on_strike_miss({"event_player": Enums.PlayerId.PlayerId_Opponent, "number": -1, "event_type": Enums.EventType.EventType_Strike_Miss})
	await get_tree().process_frame
	assert_true(game.cats_cradle_right_pending_this_strike,
			"Local player's armed closeup survives the opponent's miss")
	assert_false(game.cats_cradle_left_pending_this_strike,
			"Opponent's armed closeup is cleared by the opponent's miss")
	game.queue_free()
	await get_tree().process_frame

func test_closeup_pending_all_cleared_at_strike_cleanup():
	# Whatever closeups are still armed at strike cleanup are dropped, so a
	# missed ultra never leaks its animation into the next strike.
	var game = make_game_with_deck("eugenia")
	game.cats_cradle_right_pending_this_strike = true
	game.cats_cradle_left_pending_this_strike = true
	game.qoh_right_pending_this_strike = true
	game.qoh_left_pending_this_strike = true
	game._on_end_of_strike()
	await get_tree().process_frame
	assert_false(game.cats_cradle_right_pending_this_strike, "Cleanup clears all armed closeups")
	assert_false(game.cats_cradle_left_pending_this_strike, "Cleanup clears all armed closeups")
	assert_false(game.qoh_right_pending_this_strike, "Cleanup clears all armed closeups")
	assert_false(game.qoh_left_pending_this_strike, "Cleanup clears all armed closeups")
	game.queue_free()
	await get_tree().process_frame

func test_no_closeup_leaks_into_next_strike_after_miss():
	# Regression: an ultra that MISSES must not leak its armed closeup into a
	# later strike. Scenario: strike A = local ultra armed then missed;
	# strike B = a normal attack that hits and deals damage. The damage in
	# strike B must NOT play any ultra animation.
	var game = make_game_with_deck("eugenia")
	# --- Strike A: ultra activated (pending armed), then MISSES ---
	# (Pending is set directly here; the arming judgement itself is exercised
	# in the engine tests and is game_wrapper-dependent.)
	game.cats_cradle_right_pending_this_strike = true
	game.qoh_right_pending_this_strike = true
	game._on_strike_miss({"event_player": Enums.PlayerId.PlayerId_Player,
		"number": 0, "event_type": Enums.EventType.EventType_Strike_Miss})
	game._on_end_of_strike()
	await get_tree().process_frame
	assert_false(game.cats_cradle_right_pending_this_strike,
			"Strike A miss must clear the armed Cat's Cradle closeup")
	assert_false(game.qoh_right_pending_this_strike,
			"Strike A miss must clear the armed QOH closeup")
	assert_null(game.cats_cradle_animation_right, "Strike A miss must not create a closeup")
	assert_null(game.qoh_animation_right, "Strike A miss must not create a QOH closeup")
	# --- Strike B: a normal attack that hits and deals damage ---
	game._on_strike_card_activation({"number": 2002})
	game._on_strike_hit({"number": 2002, "event_player": Enums.PlayerId.PlayerId_Player})
	game._on_damage({"event_player": Enums.PlayerId.PlayerId_Opponent,
		"number": 2, "extra_info": 28, "reason": "strike"})
	await get_tree().process_frame
	assert_false(game.cats_cradle_right_pending_this_strike,
			"Strike B: no leaked Cat's Cradle pending from the missed ultra")
	assert_false(game.qoh_right_pending_this_strike,
			"Strike B: no leaked QOH pending from the missed ultra")
	assert_null(game.cats_cradle_animation_right,
			"Strike B damage must not play the missed ultra's Cat's Cradle closeup")
	assert_null(game.qoh_animation_right,
			"Strike B damage must not play the missed ultra's QOH closeup")
	assert_null(game.qoh_damage_animation,
			"Strike B: normal attack must not play the QOH damage effect")
	assert_null(game.cats_cradle_hit_animation,
			"Strike B: normal attack must not play the Cradle hit effect")
	game.queue_free()
	await get_tree().process_frame

# --- Zsolt entrance / awaken / Fatal Eye animations (2026-08-19) ---

func test_entrance_plays_once_when_local_player_is_zsolt():
	var game = make_game_with_deck("zsolt")
	game.try_play_match_start_entrance()
	await get_tree().process_frame
	assert_not_null(game.entrance_animation, "Entrance animation should be created for Zsolt player")
	assert_true(game.entrance_animation.is_playing(), "Entrance animation should be playing")
	assert_false(game.entrance_animation.sprite_frames.get_animation_loop("entrance"),
			"Entrance animation should play exactly once (no loop)")
	assert_eq(game.entrance_animation.sprite_frames.get_frame_count("entrance"), 14,
			"Zsolt entrance animation should have all 14 frames")
	game.queue_free()
	await get_tree().process_frame

func test_entrance_bottom_right_alignment_for_zsolt():
	var game = make_game_with_deck("zsolt")
	game.try_play_match_start_entrance()
	await get_tree().process_frame
	assert_not_null(game.entrance_animation, "Zsolt entrance should play")
	var frame_size = game.entrance_animation.sprite_frames.get_frame_texture("entrance", 0).get_size()
	var scale_factor = min(1280.0 / frame_size.x, 720.0 / frame_size.y) * 0.98
	var expected_x = 1280.0 - frame_size.x * scale_factor * 0.5
	var expected_y = 720.0 - frame_size.y * scale_factor * 0.5
	assert_almost_eq(game.entrance_animation.position.x, expected_x, 0.5,
			"Zsolt entrance should align to bottom-right (x)")
	assert_almost_eq(game.entrance_animation.position.y, expected_y, 0.5,
			"Zsolt entrance should align to bottom-right (y)")
	game.queue_free()
	await get_tree().process_frame

func test_awaken_plays_for_zsolt_bottom_right():
	var game = make_game_with_deck("zsolt")
	game._play_awaken_entrance()
	await get_tree().process_frame
	assert_not_null(game.awaken_animation, "Zsolt awaken animation should be created")
	assert_eq(game.awaken_animation.sprite_frames.get_frame_count("awaken"), 14,
			"Zsolt awaken animation should have all 14 frames")
	var frame_size = game.awaken_animation.sprite_frames.get_frame_texture("awaken", 0).get_size()
	var scale_factor = min(1280.0 / frame_size.x, 720.0 / frame_size.y) * 0.98
	var expected_x = 1280.0 - frame_size.x * scale_factor * 0.5
	var expected_y = 720.0 - frame_size.y * scale_factor * 0.5
	assert_almost_eq(game.awaken_animation.position.x, expected_x, 0.5,
			"Zsolt awaken should align to bottom-right (x)")
	assert_almost_eq(game.awaken_animation.position.y, expected_y, 0.5,
			"Zsolt awaken should align to bottom-right (y)")
	game.queue_free()
	await get_tree().process_frame

func test_fatal_eye_plays_once_bottom_left():
	var game = make_game_with_deck("zsolt")
	game._play_zsolt_fatal_eye()
	await get_tree().process_frame
	assert_not_null(game.fatal_eye_animation, "Fatal Eye closeup should be created")
	assert_true(game.fatal_eye_animation.is_playing(), "Fatal Eye closeup should be playing")
	assert_eq(game.fatal_eye_animation.sprite_frames.get_frame_count("fatal_eye"), 14,
			"Fatal Eye closeup should have all 14 frames")
	var frame_size = game.fatal_eye_animation.sprite_frames.get_frame_texture("fatal_eye", 0).get_size()
	var scale_factor = min(1280.0 / frame_size.x, 720.0 / frame_size.y) * 0.98
	var expected_x = frame_size.x * scale_factor * 0.5
	var expected_y = 720.0 - frame_size.y * scale_factor * 0.5
	assert_almost_eq(game.fatal_eye_animation.position.x, expected_x, 0.5,
			"Fatal Eye should align to bottom-left (x)")
	assert_almost_eq(game.fatal_eye_animation.position.y, expected_y, 0.5,
			"Fatal Eye should align to bottom-left (y)")
	game.queue_free()
	await get_tree().process_frame

func test_fatal_eye_deduped_on_second_call():
	var game = make_game_with_deck("zsolt")
	game._play_zsolt_fatal_eye()
	await get_tree().process_frame
	var first = game.fatal_eye_animation
	game._play_zsolt_fatal_eye()
	await get_tree().process_frame
	assert_eq(game.fatal_eye_animation, first, "Second play should reuse the existing animation")
	game.queue_free()
	await get_tree().process_frame

# --- Zsolt Wild Hunt hit closeup + damage effect (2026-08-19) ---

func test_zsolt_wild_hunt_left_closeup_plays_for_defender():
	var game = make_game_with_deck("zsolt")
	game._play_zsolt_wild_hunt_entrance(false)
	await get_tree().process_frame
	assert_not_null(game.wild_hunt_animation_left, "Wild Hunt left closeup should be created for defender")
	assert_eq(game.wild_hunt_animation_left.sprite_frames.get_frame_count("wild_hunt"), 14,
			"Wild Hunt left closeup should have 14 frames")
	var frame_size = game.wild_hunt_animation_left.sprite_frames.get_frame_texture("wild_hunt", 0).get_size()
	var scale_factor = min(1280.0 / frame_size.x, 720.0 / frame_size.y) * 0.98
	var expected_x = frame_size.x * scale_factor * 0.5
	var expected_y = frame_size.y * scale_factor * 0.5
	assert_almost_eq(game.wild_hunt_animation_left.position.x, expected_x, 0.5,
			"Wild Hunt left closeup should align to top-left (x)")
	assert_almost_eq(game.wild_hunt_animation_left.position.y, expected_y, 0.5,
			"Wild Hunt left closeup should align to top-left (y)")
	assert_null(game.wild_hunt_animation_right, "Defender side should not create a right closeup")
	game.queue_free()
	await get_tree().process_frame

func test_zsolt_wild_hunt_right_closeup_plays_for_attacker():
	var game = make_game_with_deck("zsolt")
	game._play_zsolt_wild_hunt_entrance(true)
	await get_tree().process_frame
	assert_not_null(game.wild_hunt_animation_right, "Wild Hunt right closeup should be created for attacker")
	var frame_size = game.wild_hunt_animation_right.sprite_frames.get_frame_texture("wild_hunt", 0).get_size()
	var scale_factor = min(1280.0 / frame_size.x, 720.0 / frame_size.y) * 0.98
	var displayed = frame_size * scale_factor
	var expected_x = 1280.0 - displayed.x * 0.5
	var expected_y = displayed.y * 0.5
	assert_almost_eq(game.wild_hunt_animation_right.position.x, expected_x, 0.5,
			"Wild Hunt right closeup should align to top-right (x)")
	assert_almost_eq(game.wild_hunt_animation_right.position.y, expected_y, 0.5,
			"Wild Hunt right closeup should align to top-right (y)")
	assert_null(game.wild_hunt_animation_left, "Attacker side should not create a left closeup")
	game.queue_free()
	await get_tree().process_frame

func test_zsolt_wild_hunt_damage_effect_full_screen():
	var game = make_game_with_deck("zsolt")
	game._play_zsolt_wild_hunt_damage()
	await get_tree().process_frame
	assert_not_null(game.wild_hunt_damage_animation, "Wild Hunt damage effect should be created")
	assert_eq(game.wild_hunt_damage_animation.sprite_frames.get_frame_count("wild_hunt_damage"), 34,
			"Wild Hunt damage effect should have 34 frames")
	assert_eq(game.wild_hunt_damage_animation.position, Vector2(640.0, 360.0),
			"Wild Hunt damage effect should be centered")
	# Cover scale: should fill (or exceed) the screen on both axes.
	var frame_size = game.wild_hunt_damage_animation.sprite_frames.get_frame_texture("wild_hunt_damage", 0).get_size()
	var expected_scale = max(1280.0 / frame_size.x, 720.0 / frame_size.y)
	assert_almost_eq(game.wild_hunt_damage_animation.scale.x, expected_scale, 0.01,
			"Wild Hunt damage effect should use cover scale (max)")
	game.queue_free()
	await get_tree().process_frame

func test_zsolt_wild_hunt_damage_deduped():
	var game = make_game_with_deck("zsolt")
	game._play_zsolt_wild_hunt_damage()
	await get_tree().process_frame
	var first = game.wild_hunt_damage_animation
	game._play_zsolt_wild_hunt_damage()
	await get_tree().process_frame
	assert_eq(game.wild_hunt_damage_animation, first, "Second damage call should reuse the existing animation")
	game.queue_free()
	await get_tree().process_frame

# --- Zsolt Fanatical Purification hit closeup + damage effect (2026-08-19) ---

func test_zsolt_purification_left_closeup_plays_for_defender():
	var game = make_game_with_deck("zsolt")
	game._play_zsolt_purification_entrance(false)
	await get_tree().process_frame
	assert_not_null(game.purification_animation_left, "Purification left closeup should be created for defender")
	assert_eq(game.purification_animation_left.sprite_frames.get_frame_count("purification"), 14,
			"Purification left closeup should have 14 frames")
	var frame_size = game.purification_animation_left.sprite_frames.get_frame_texture("purification", 0).get_size()
	var scale_factor = min(1280.0 / frame_size.x, 720.0 / frame_size.y) * 0.98
	var expected_x = frame_size.x * scale_factor * 0.5
	var expected_y = frame_size.y * scale_factor * 0.5
	assert_almost_eq(game.purification_animation_left.position.x, expected_x, 0.5,
			"Purification left closeup should align to top-left (x)")
	assert_almost_eq(game.purification_animation_left.position.y, expected_y, 0.5,
			"Purification left closeup should align to top-left (y)")
	assert_null(game.purification_animation_right, "Defender side should not create a right closeup")
	game.queue_free()
	await get_tree().process_frame

func test_zsolt_purification_right_closeup_plays_for_attacker():
	var game = make_game_with_deck("zsolt")
	game._play_zsolt_purification_entrance(true)
	await get_tree().process_frame
	assert_not_null(game.purification_animation_right, "Purification right closeup should be created for attacker")
	var frame_size = game.purification_animation_right.sprite_frames.get_frame_texture("purification", 0).get_size()
	var scale_factor = min(1280.0 / frame_size.x, 720.0 / frame_size.y) * 0.98
	var displayed = frame_size * scale_factor
	var expected_x = 1280.0 - displayed.x * 0.5
	var expected_y = displayed.y * 0.5
	assert_almost_eq(game.purification_animation_right.position.x, expected_x, 0.5,
			"Purification right closeup should align to top-right (x)")
	assert_almost_eq(game.purification_animation_right.position.y, expected_y, 0.5,
			"Purification right closeup should align to top-right (y)")
	assert_null(game.purification_animation_left, "Attacker side should not create a left closeup")
	game.queue_free()
	await get_tree().process_frame

func test_zsolt_purification_damage_effect_full_screen():
	var game = make_game_with_deck("zsolt")
	game._play_zsolt_purification_damage()
	await get_tree().process_frame
	assert_not_null(game.purification_damage_animation, "Purification damage effect should be created")
	assert_eq(game.purification_damage_animation.sprite_frames.get_frame_count("purification_damage"), 22,
			"Purification damage effect should have 22 frames")
	assert_eq(game.purification_damage_animation.position, Vector2(640.0, 360.0),
			"Purification damage effect should be centered")
	var frame_size = game.purification_damage_animation.sprite_frames.get_frame_texture("purification_damage", 0).get_size()
	var expected_scale = max(1280.0 / frame_size.x, 720.0 / frame_size.y)
	assert_almost_eq(game.purification_damage_animation.scale.x, expected_scale, 0.01,
			"Purification damage effect should use cover scale (max)")
	game.queue_free()
	await get_tree().process_frame

func test_zsolt_purification_damage_deduped():
	var game = make_game_with_deck("zsolt")
	game._play_zsolt_purification_damage()
	await get_tree().process_frame
	var first = game.purification_damage_animation
	game._play_zsolt_purification_damage()
	await get_tree().process_frame
	assert_eq(game.purification_damage_animation, first, "Second damage call should reuse the existing animation")
	game.queue_free()
	await get_tree().process_frame

# --- Global animations toggle (2026-08-19) ---

func test_no_animations_when_toggle_off():
	var saved = GlobalSettings.AnimationsEnabled
	GlobalSettings.AnimationsEnabled = false
	var game = make_game_with_deck("eugenia")
	game.try_play_match_start_entrance()
	game._play_awaken_entrance()
	game._play_cats_cradle_entrance(true)
	game._play_qoh_entrance(false)
	game._play_tea_time_entrance()
	game._play_qoh_damage_effect()
	game._play_cats_cradle_hit()
	game._play_zsolt_fatal_eye()
	game._play_zsolt_wild_hunt_entrance(true)
	game._play_zsolt_wild_hunt_damage()
	game._play_zsolt_purification_entrance(false)
	game._play_zsolt_purification_damage()
	game._play_geoffrey_judgment_entrance(true)
	game._play_geoffrey_judgment_damage()
	game._play_geoffrey_crusader_entrance(false)
	game._play_geoffrey_crusader_damage()
	game._play_geoffrey_purification()
	game._play_iaquis_heart_entrance(true)
	game._play_iaquis_heart_damage()
	game._play_iaquis_descent_entrance(false)
	game._play_iaquis_descent_damage()
	await get_tree().process_frame
	assert_null(game.entrance_animation, "No entrance animation when toggle off")
	assert_null(game.awaken_animation, "No awaken animation when toggle off")
	assert_null(game.cats_cradle_animation_right, "No Cradle closeup when toggle off")
	assert_null(game.qoh_animation_left, "No QOH closeup when toggle off")
	assert_null(game.tea_time_animation, "No tea time closeup when toggle off")
	assert_null(game.qoh_damage_animation, "No QOH damage effect when toggle off")
	assert_null(game.cats_cradle_hit_animation, "No Cradle hit effect when toggle off")
	assert_null(game.fatal_eye_animation, "No Fatal Eye closeup when toggle off")
	assert_null(game.wild_hunt_animation_right, "No Wild Hunt closeup when toggle off")
	assert_null(game.wild_hunt_damage_animation, "No Wild Hunt damage effect when toggle off")
	assert_null(game.purification_animation_left, "No Purification closeup when toggle off")
	assert_null(game.purification_damage_animation, "No Purification damage effect when toggle off")
	assert_null(game.judgment_animation_right, "No Judgment closeup when toggle off")
	assert_null(game.judgment_damage_animation, "No Judgment damage effect when toggle off")
	assert_null(game.crusader_animation_left, "No Crusader closeup when toggle off")
	assert_null(game.crusader_damage_animation, "No Crusader damage effect when toggle off")
	assert_null(game.geoffrey_purification_animation, "No Purification closeup when toggle off")
	assert_null(game.heart_animation_right, "No Heart closeup when toggle off")
	assert_null(game.heart_damage_animation, "No Heart damage effect when toggle off")
	assert_null(game.descent_animation_left, "No Descent closeup when toggle off")
	assert_null(game.descent_damage_animation, "No Descent damage effect when toggle off")
	GlobalSettings.AnimationsEnabled = saved
	game.queue_free()
	await get_tree().process_frame

func test_animations_play_when_toggle_on():
	var saved = GlobalSettings.AnimationsEnabled
	GlobalSettings.AnimationsEnabled = true
	var game = make_game_with_deck("eugenia")
	game.try_play_match_start_entrance()
	await get_tree().process_frame
	assert_not_null(game.entrance_animation, "Entrance animation plays when toggle on")
	GlobalSettings.AnimationsEnabled = saved
	game.queue_free()
	await get_tree().process_frame

# --- Zsolt: no closeup/effect on extra attacks (chain attacks) (2026-08-19) ---

func test_zsolt_ultras_no_animation_when_extra_attack():
	# The closeups and full-screen damage effects only play when the ultra is
	# the MAIN attack card of the strike. Chain extra attacks (Zsolt awaken
	# combo) must not play them. The UI tracks the extra-attack phase from the
	# event stream (strike_is_extra_attack), not from the engine.
	var game = make_game_with_deck("zsolt")
	game.strike_is_extra_attack = true
	game._play_zsolt_wild_hunt_entrance(true)
	game._play_zsolt_wild_hunt_entrance(false)
	game._play_zsolt_wild_hunt_damage()
	game._play_zsolt_purification_entrance(true)
	game._play_zsolt_purification_entrance(false)
	game._play_zsolt_purification_damage()
	await get_tree().process_frame
	assert_null(game.wild_hunt_animation_right, "No Wild Hunt closeup on extra attack")
	assert_null(game.wild_hunt_animation_left, "No Wild Hunt left closeup on extra attack")
	assert_null(game.wild_hunt_damage_animation, "No Wild Hunt damage effect on extra attack")
	assert_null(game.purification_animation_right, "No Purification closeup on extra attack")
	assert_null(game.purification_animation_left, "No Purification left closeup on extra attack")
	assert_null(game.purification_damage_animation, "No Purification damage effect on extra attack")
	game.queue_free()
	await get_tree().process_frame

func test_zsolt_ultras_play_when_main_attack():
	# Same calls with the flag false (main attack) must play normally.
	var game = make_game_with_deck("zsolt")
	game.strike_is_extra_attack = false
	game._play_zsolt_wild_hunt_entrance(true)
	game._play_zsolt_wild_hunt_damage()
	game._play_zsolt_purification_entrance(false)
	game._play_zsolt_purification_damage()
	await get_tree().process_frame
	assert_not_null(game.wild_hunt_animation_right, "Wild Hunt closeup plays as main attack")
	assert_not_null(game.wild_hunt_damage_animation, "Wild Hunt damage effect plays as main attack")
	assert_not_null(game.purification_animation_left, "Purification closeup plays as main attack")
	assert_not_null(game.purification_damage_animation, "Purification damage effect plays as main attack")
	game.queue_free()
	await get_tree().process_frame

# --- Geoffrey Inviolable Judgment hit closeup + damage effect (2026-08-20) ---

func test_geoffrey_judgment_left_closeup_plays_for_defender():
	var game = make_game_with_deck("geoffrey")
	game._play_geoffrey_judgment_entrance(false)
	await get_tree().process_frame
	assert_not_null(game.judgment_animation_left, "Judgment left closeup should be created for defender")
	assert_eq(game.judgment_animation_left.sprite_frames.get_frame_count("judgment"), 14,
			"Judgment left closeup should have 14 frames")
	var frame_size = game.judgment_animation_left.sprite_frames.get_frame_texture("judgment", 0).get_size()
	var scale_factor = min(1280.0 / frame_size.x, 720.0 / frame_size.y) * 0.98
	var expected_x = frame_size.x * scale_factor * 0.5
	var expected_y = frame_size.y * scale_factor * 0.5
	assert_almost_eq(game.judgment_animation_left.position.x, expected_x, 0.5,
			"Judgment left closeup should align to top-left (x)")
	assert_almost_eq(game.judgment_animation_left.position.y, expected_y, 0.5,
			"Judgment left closeup should align to top-left (y)")
	assert_null(game.judgment_animation_right, "Defender side should not create a right closeup")
	game.queue_free()
	await get_tree().process_frame

func test_geoffrey_judgment_right_closeup_plays_for_attacker():
	var game = make_game_with_deck("geoffrey")
	game._play_geoffrey_judgment_entrance(true)
	await get_tree().process_frame
	assert_not_null(game.judgment_animation_right, "Judgment right closeup should be created for attacker")
	var frame_size = game.judgment_animation_right.sprite_frames.get_frame_texture("judgment", 0).get_size()
	var scale_factor = min(1280.0 / frame_size.x, 720.0 / frame_size.y) * 0.98
	var displayed = frame_size * scale_factor
	var expected_x = 1280.0 - displayed.x * 0.5
	var expected_y = displayed.y * 0.5
	assert_almost_eq(game.judgment_animation_right.position.x, expected_x, 0.5,
			"Judgment right closeup should align to top-right (x)")
	assert_almost_eq(game.judgment_animation_right.position.y, expected_y, 0.5,
			"Judgment right closeup should align to top-right (y)")
	assert_null(game.judgment_animation_left, "Attacker side should not create a left closeup")
	game.queue_free()
	await get_tree().process_frame

func test_geoffrey_judgment_damage_effect_full_screen():
	var game = make_game_with_deck("geoffrey")
	game._play_geoffrey_judgment_damage()
	await get_tree().process_frame
	assert_not_null(game.judgment_damage_animation, "Judgment damage effect should be created")
	assert_eq(game.judgment_damage_animation.sprite_frames.get_frame_count("judgment_damage"), 29,
			"Judgment damage effect should have 29 frames")
	assert_eq(game.judgment_damage_animation.position, Vector2(640.0, 360.0),
			"Judgment damage effect should be centered")
	var frame_size = game.judgment_damage_animation.sprite_frames.get_frame_texture("judgment_damage", 0).get_size()
	var expected_scale = max(1280.0 / frame_size.x, 720.0 / frame_size.y)
	assert_almost_eq(game.judgment_damage_animation.scale.x, expected_scale, 0.01,
			"Judgment damage effect should use cover scale (max)")
	game.queue_free()
	await get_tree().process_frame

func test_geoffrey_judgment_damage_deduped():
	var game = make_game_with_deck("geoffrey")
	game._play_geoffrey_judgment_damage()
	await get_tree().process_frame
	var first = game.judgment_damage_animation
	game._play_geoffrey_judgment_damage()
	await get_tree().process_frame
	assert_eq(game.judgment_damage_animation, first, "Second damage call should reuse the existing animation")
	game.queue_free()
	await get_tree().process_frame

# --- Geoffrey Crusader's Oath hit closeup + damage effect (2026-08-20) ---

func test_geoffrey_crusader_left_closeup_plays_for_defender():
	var game = make_game_with_deck("geoffrey")
	game._play_geoffrey_crusader_entrance(false)
	await get_tree().process_frame
	assert_not_null(game.crusader_animation_left, "Crusader left closeup should be created for defender")
	assert_eq(game.crusader_animation_left.sprite_frames.get_frame_count("crusader"), 14,
			"Crusader left closeup should have 14 frames")
	var frame_size = game.crusader_animation_left.sprite_frames.get_frame_texture("crusader", 0).get_size()
	var scale_factor = min(1280.0 / frame_size.x, 720.0 / frame_size.y) * 0.98
	var expected_x = frame_size.x * scale_factor * 0.5
	var expected_y = frame_size.y * scale_factor * 0.5
	assert_almost_eq(game.crusader_animation_left.position.x, expected_x, 0.5,
			"Crusader left closeup should align to top-left (x)")
	assert_almost_eq(game.crusader_animation_left.position.y, expected_y, 0.5,
			"Crusader left closeup should align to top-left (y)")
	assert_null(game.crusader_animation_right, "Defender side should not create a right closeup")
	game.queue_free()
	await get_tree().process_frame

func test_geoffrey_crusader_right_closeup_plays_for_attacker():
	var game = make_game_with_deck("geoffrey")
	game._play_geoffrey_crusader_entrance(true)
	await get_tree().process_frame
	assert_not_null(game.crusader_animation_right, "Crusader right closeup should be created for attacker")
	var frame_size = game.crusader_animation_right.sprite_frames.get_frame_texture("crusader", 0).get_size()
	var scale_factor = min(1280.0 / frame_size.x, 720.0 / frame_size.y) * 0.98
	var displayed = frame_size * scale_factor
	var expected_x = 1280.0 - displayed.x * 0.5
	var expected_y = displayed.y * 0.5
	assert_almost_eq(game.crusader_animation_right.position.x, expected_x, 0.5,
			"Crusader right closeup should align to top-right (x)")
	assert_almost_eq(game.crusader_animation_right.position.y, expected_y, 0.5,
			"Crusader right closeup should align to top-right (y)")
	assert_null(game.crusader_animation_left, "Attacker side should not create a left closeup")
	game.queue_free()
	await get_tree().process_frame

func test_geoffrey_crusader_damage_effect_full_screen():
	var game = make_game_with_deck("geoffrey")
	game._play_geoffrey_crusader_damage()
	await get_tree().process_frame
	assert_not_null(game.crusader_damage_animation, "Crusader damage effect should be created")
	assert_eq(game.crusader_damage_animation.sprite_frames.get_frame_count("crusader_damage"), 26,
			"Crusader damage effect should have 26 frames")
	assert_eq(game.crusader_damage_animation.position, Vector2(640.0, 360.0),
			"Crusader damage effect should be centered")
	var frame_size = game.crusader_damage_animation.sprite_frames.get_frame_texture("crusader_damage", 0).get_size()
	var expected_scale = max(1280.0 / frame_size.x, 720.0 / frame_size.y)
	assert_almost_eq(game.crusader_damage_animation.scale.x, expected_scale, 0.01,
			"Crusader damage effect should use cover scale (max)")
	game.queue_free()
	await get_tree().process_frame

func test_geoffrey_crusader_damage_deduped():
	var game = make_game_with_deck("geoffrey")
	game._play_geoffrey_crusader_damage()
	await get_tree().process_frame
	var first = game.crusader_damage_animation
	game._play_geoffrey_crusader_damage()
	await get_tree().process_frame
	assert_eq(game.crusader_damage_animation, first, "Second damage call should reuse the existing animation")
	game.queue_free()
	await get_tree().process_frame

# --- Geoffrey entrance / awaken closeups (2026-08-20) ---

func test_geoffrey_entrance_closeup_plays_bottom_right():
	var game = make_game_with_deck("geoffrey")
	game.try_play_match_start_entrance()
	await get_tree().process_frame
	assert_not_null(game.entrance_animation, "Entrance animation should be created for Geoffrey player")
	assert_eq(game.entrance_animation.sprite_frames.get_frame_count("entrance"), 14,
			"Geoffrey entrance closeup should have 14 frames")
	var frame_size = game.entrance_animation.sprite_frames.get_frame_texture("entrance", 0).get_size()
	var scale_factor = min(1280.0 / frame_size.x, 720.0 / frame_size.y) * 0.98
	var expected_x = 1280.0 - frame_size.x * scale_factor * 0.5
	var expected_y = 720.0 - frame_size.y * scale_factor * 0.5
	assert_almost_eq(game.entrance_animation.position.x, expected_x, 0.5,
			"Geoffrey entrance closeup should align to bottom-right (x)")
	assert_almost_eq(game.entrance_animation.position.y, expected_y, 0.5,
			"Geoffrey entrance closeup should align to bottom-right (y)")
	game.queue_free()
	await get_tree().process_frame

func test_geoffrey_awaken_closeup_plays_bottom_right():
	var game = make_game_with_deck("geoffrey")
	game._play_awaken_entrance()
	await get_tree().process_frame
	assert_not_null(game.awaken_animation, "Awaken closeup should be created for Geoffrey player")
	assert_eq(game.awaken_animation.sprite_frames.get_frame_count("awaken"), 14,
			"Geoffrey awaken closeup should have 14 frames")
	var frame_size = game.awaken_animation.sprite_frames.get_frame_texture("awaken", 0).get_size()
	var scale_factor = min(1280.0 / frame_size.x, 720.0 / frame_size.y) * 0.98
	var expected_x = 1280.0 - frame_size.x * scale_factor * 0.5
	var expected_y = 720.0 - frame_size.y * scale_factor * 0.5
	assert_almost_eq(game.awaken_animation.position.x, expected_x, 0.5,
			"Geoffrey awaken closeup should align to bottom-right (x)")
	assert_almost_eq(game.awaken_animation.position.y, expected_y, 0.5,
			"Geoffrey awaken closeup should align to bottom-right (y)")
	game.queue_free()
	await get_tree().process_frame

func test_geoffrey_entrance_plays_for_geoffrey_skin():
	var game = make_game_with_deck("geoffrey_1", "geoffrey")
	game.try_play_match_start_entrance()
	await get_tree().process_frame
	assert_not_null(game.entrance_animation, "Entrance animation should play for Geoffrey skin")
	game.queue_free()
	await get_tree().process_frame

# --- Geoffrey: no closeup/effect on extra attacks (chain attacks) ---

func test_geoffrey_ultras_no_animation_when_extra_attack():
	var game = make_game_with_deck("geoffrey")
	game.strike_is_extra_attack = true
	game._play_geoffrey_judgment_entrance(true)
	game._play_geoffrey_judgment_entrance(false)
	game._play_geoffrey_judgment_damage()
	game._play_geoffrey_crusader_entrance(true)
	game._play_geoffrey_crusader_entrance(false)
	game._play_geoffrey_crusader_damage()
	await get_tree().process_frame
	assert_null(game.judgment_animation_right, "No Judgment closeup on extra attack")
	assert_null(game.judgment_animation_left, "No Judgment left closeup on extra attack")
	assert_null(game.judgment_damage_animation, "No Judgment damage effect on extra attack")
	assert_null(game.crusader_animation_right, "No Crusader closeup on extra attack")
	assert_null(game.crusader_animation_left, "No Crusader left closeup on extra attack")
	assert_null(game.crusader_damage_animation, "No Crusader damage effect on extra attack")
	game.queue_free()
	await get_tree().process_frame

func test_geoffrey_ultras_play_when_main_attack():
	var game = make_game_with_deck("geoffrey")
	game.strike_is_extra_attack = false
	game._play_geoffrey_judgment_entrance(true)
	game._play_geoffrey_judgment_damage()
	game._play_geoffrey_crusader_entrance(false)
	game._play_geoffrey_crusader_damage()
	await get_tree().process_frame
	assert_not_null(game.judgment_animation_right, "Judgment closeup plays as main attack")
	assert_not_null(game.judgment_damage_animation, "Judgment damage effect plays as main attack")
	assert_not_null(game.crusader_animation_left, "Crusader closeup plays as main attack")
	assert_not_null(game.crusader_damage_animation, "Crusader damage effect plays as main attack")
	game.queue_free()
	await get_tree().process_frame

# --- Geoffrey Compulsive Purification closeup (inquisition transform confirm) ---

func test_geoffrey_purification_plays_bottom_left():
	var game = make_game_with_deck("geoffrey")
	game._play_geoffrey_purification()
	await get_tree().process_frame
	assert_not_null(game.geoffrey_purification_animation, "Purification closeup should be created on confirm")
	assert_eq(game.geoffrey_purification_animation.sprite_frames.get_frame_count("geoffrey_purification"), 14,
		"Purification closeup should have 14 frames")
	var frame_size = game.geoffrey_purification_animation.sprite_frames.get_frame_texture("geoffrey_purification", 0).get_size()
	var scale_factor = min(1280.0 / frame_size.x, 720.0 / frame_size.y) * 0.98
	var expected_x = frame_size.x * scale_factor * 0.5
	var expected_y = 720.0 - frame_size.y * scale_factor * 0.5
	assert_almost_eq(game.geoffrey_purification_animation.position.x, expected_x, 0.5,
		"Purification closeup should align to bottom-left (x)")
	assert_almost_eq(game.geoffrey_purification_animation.position.y, expected_y, 0.5,
		"Purification closeup should align to bottom-left (y)")
	assert_not_null(load("res://assets/entrance_animations/geoffrey/geoffrey_purification_bonus_00.png"),
		"Bonus (easter-egg) frames should exist")
	game.queue_free()
	await get_tree().process_frame

func test_geoffrey_purification_deduped():
	var game = make_game_with_deck("geoffrey")
	game._play_geoffrey_purification()
	await get_tree().process_frame
	var first = game.geoffrey_purification_animation
	game._play_geoffrey_purification()
	await get_tree().process_frame
	assert_eq(game.geoffrey_purification_animation, first, "Second call should reuse the existing animation")
	game.queue_free()
	await get_tree().process_frame

func test_geoffrey_purification_cleanup_after_finish():
	var game = make_game_with_deck("geoffrey")
	game._play_geoffrey_purification()
	await get_tree().process_frame
	assert_not_null(game.geoffrey_purification_animation)
	game._on_geoffrey_purification_animation_finished()
	await get_tree().process_frame
	assert_null(game.geoffrey_purification_animation, "Purification closeup should be cleaned up after finishing")
	game.queue_free()
	await get_tree().process_frame

# --- Iaquis Dragon's Heart hit closeup + damage effect (2026-08-23) ---

func test_iaquis_heart_left_closeup_plays_for_defender():
	var game = make_game_with_deck("iaquis")
	game._play_iaquis_heart_entrance(false)
	await get_tree().process_frame
	assert_not_null(game.heart_animation_left, "Heart left closeup should be created for defender")
	assert_eq(game.heart_animation_left.sprite_frames.get_frame_count("heart"), 14,
		"Heart left closeup should have 14 frames")
	var frame_size = game.heart_animation_left.sprite_frames.get_frame_texture("heart", 0).get_size()
	var scale_factor = min(1280.0 / frame_size.x, 720.0 / frame_size.y) * 0.98
	var expected_x = frame_size.x * scale_factor * 0.5
	var expected_y = frame_size.y * scale_factor * 0.5
	assert_almost_eq(game.heart_animation_left.position.x, expected_x, 0.5,
		"Heart left closeup should align to top-left (x)")
	assert_almost_eq(game.heart_animation_left.position.y, expected_y, 0.5,
		"Heart left closeup should align to top-left (y)")
	assert_null(game.heart_animation_right, "Defender side should not create a right closeup")
	game.queue_free()
	await get_tree().process_frame

func test_iaquis_heart_right_closeup_plays_for_attacker():
	var game = make_game_with_deck("iaquis")
	game._play_iaquis_heart_entrance(true)
	await get_tree().process_frame
	assert_not_null(game.heart_animation_right, "Heart right closeup should be created for attacker")
	var frame_size = game.heart_animation_right.sprite_frames.get_frame_texture("heart", 0).get_size()
	var scale_factor = min(1280.0 / frame_size.x, 720.0 / frame_size.y) * 0.98
	var displayed = frame_size * scale_factor
	var expected_x = 1280.0 - displayed.x * 0.5
	var expected_y = displayed.y * 0.5
	assert_almost_eq(game.heart_animation_right.position.x, expected_x, 0.5,
		"Heart right closeup should align to top-right (x)")
	assert_almost_eq(game.heart_animation_right.position.y, expected_y, 0.5,
		"Heart right closeup should align to top-right (y)")
	assert_null(game.heart_animation_left, "Attacker side should not create a left closeup")
	game.queue_free()
	await get_tree().process_frame

func test_iaquis_heart_damage_effect_full_screen():
	var game = make_game_with_deck("iaquis")
	game._play_iaquis_heart_damage()
	await get_tree().process_frame
	assert_not_null(game.heart_damage_animation, "Heart damage effect should be created")
	assert_eq(game.heart_damage_animation.sprite_frames.get_frame_count("heart_damage"), 29,
		"Heart damage effect should have 29 frames")
	assert_eq(game.heart_damage_animation.position, Vector2(640.0, 360.0),
		"Heart damage effect should be centered")
	var frame_size = game.heart_damage_animation.sprite_frames.get_frame_texture("heart_damage", 0).get_size()
	var expected_scale = max(1280.0 / frame_size.x, 720.0 / frame_size.y)
	assert_almost_eq(game.heart_damage_animation.scale.x, expected_scale, 0.01,
		"Heart damage effect should use cover scale (max)")
	game.queue_free()
	await get_tree().process_frame

func test_iaquis_heart_damage_deduped():
	var game = make_game_with_deck("iaquis")
	game._play_iaquis_heart_damage()
	await get_tree().process_frame
	var first = game.heart_damage_animation
	game._play_iaquis_heart_damage()
	await get_tree().process_frame
	assert_eq(game.heart_damage_animation, first, "Second damage call should reuse the existing animation")
	game.queue_free()
	await get_tree().process_frame

# --- Iaquis Dragon's Descent hit closeup + damage effect (2026-08-23) ---

func test_iaquis_descent_left_closeup_plays_for_defender():
	var game = make_game_with_deck("iaquis")
	game._play_iaquis_descent_entrance(false)
	await get_tree().process_frame
	assert_not_null(game.descent_animation_left, "Descent left closeup should be created for defender")
	assert_eq(game.descent_animation_left.sprite_frames.get_frame_count("descent"), 14,
		"Descent left closeup should have 14 frames")
	var frame_size = game.descent_animation_left.sprite_frames.get_frame_texture("descent", 0).get_size()
	var scale_factor = min(1280.0 / frame_size.x, 720.0 / frame_size.y) * 0.98
	var expected_x = frame_size.x * scale_factor * 0.5
	var expected_y = frame_size.y * scale_factor * 0.5
	assert_almost_eq(game.descent_animation_left.position.x, expected_x, 0.5,
		"Descent left closeup should align to top-left (x)")
	assert_almost_eq(game.descent_animation_left.position.y, expected_y, 0.5,
		"Descent left closeup should align to top-left (y)")
	assert_null(game.descent_animation_right, "Defender side should not create a right closeup")
	game.queue_free()
	await get_tree().process_frame

func test_iaquis_descent_right_closeup_plays_for_attacker():
	var game = make_game_with_deck("iaquis")
	game._play_iaquis_descent_entrance(true)
	await get_tree().process_frame
	assert_not_null(game.descent_animation_right, "Descent right closeup should be created for attacker")
	var frame_size = game.descent_animation_right.sprite_frames.get_frame_texture("descent", 0).get_size()
	var scale_factor = min(1280.0 / frame_size.x, 720.0 / frame_size.y) * 0.98
	var displayed = frame_size * scale_factor
	var expected_x = 1280.0 - displayed.x * 0.5
	var expected_y = displayed.y * 0.5
	assert_almost_eq(game.descent_animation_right.position.x, expected_x, 0.5,
		"Descent right closeup should align to top-right (x)")
	assert_almost_eq(game.descent_animation_right.position.y, expected_y, 0.5,
		"Descent right closeup should align to top-right (y)")
	assert_null(game.descent_animation_left, "Attacker side should not create a left closeup")
	game.queue_free()
	await get_tree().process_frame

func test_iaquis_descent_damage_effect_full_screen():
	var game = make_game_with_deck("iaquis")
	game._play_iaquis_descent_damage()
	await get_tree().process_frame
	assert_not_null(game.descent_damage_animation, "Descent damage effect should be created")
	assert_eq(game.descent_damage_animation.sprite_frames.get_frame_count("descent_damage"), 54,
		"Descent damage effect should have 54 frames")
	assert_eq(game.descent_damage_animation.position, Vector2(640.0, 360.0),
		"Descent damage effect should be centered")
	var frame_size = game.descent_damage_animation.sprite_frames.get_frame_texture("descent_damage", 0).get_size()
	var expected_scale = max(1280.0 / frame_size.x, 720.0 / frame_size.y)
	assert_almost_eq(game.descent_damage_animation.scale.x, expected_scale, 0.01,
		"Descent damage effect should use cover scale (max)")
	game.queue_free()
	await get_tree().process_frame

func test_iaquis_descent_damage_deduped():
	var game = make_game_with_deck("iaquis")
	game._play_iaquis_descent_damage()
	await get_tree().process_frame
	var first = game.descent_damage_animation
	game._play_iaquis_descent_damage()
	await get_tree().process_frame
	assert_eq(game.descent_damage_animation, first, "Second damage call should reuse the existing animation")
	game.queue_free()
	await get_tree().process_frame

# --- Iaquis entrance / awaken closeups (2026-08-23) ---

func test_iaquis_entrance_closeup_plays_bottom_right():
	var game = make_game_with_deck("iaquis")
	game.try_play_match_start_entrance()
	await get_tree().process_frame
	assert_not_null(game.entrance_animation, "Entrance animation should be created for Iaquis player")
	assert_eq(game.entrance_animation.sprite_frames.get_frame_count("entrance"), 14,
		"Iaquis entrance closeup should have 14 frames")
	var frame_size = game.entrance_animation.sprite_frames.get_frame_texture("entrance", 0).get_size()
	var scale_factor = min(1280.0 / frame_size.x, 720.0 / frame_size.y) * 0.98
	var expected_x = 1280.0 - frame_size.x * scale_factor * 0.5
	var expected_y = 720.0 - frame_size.y * scale_factor * 0.5
	assert_almost_eq(game.entrance_animation.position.x, expected_x, 0.5,
		"Iaquis entrance closeup should align to bottom-right (x)")
	assert_almost_eq(game.entrance_animation.position.y, expected_y, 0.5,
		"Iaquis entrance closeup should align to bottom-right (y)")
	game.queue_free()
	await get_tree().process_frame

func test_iaquis_awaken_closeup_plays_bottom_right():
	var game = make_game_with_deck("iaquis")
	game._play_awaken_entrance()
	await get_tree().process_frame
	assert_not_null(game.awaken_animation, "Awaken closeup should be created for Iaquis player")
	assert_eq(game.awaken_animation.sprite_frames.get_frame_count("awaken"), 14,
		"Iaquis awaken closeup should have 14 frames")
	var frame_size = game.awaken_animation.sprite_frames.get_frame_texture("awaken", 0).get_size()
	var scale_factor = min(1280.0 / frame_size.x, 720.0 / frame_size.y) * 0.98
	var expected_x = 1280.0 - frame_size.x * scale_factor * 0.5
	var expected_y = 720.0 - frame_size.y * scale_factor * 0.5
	assert_almost_eq(game.awaken_animation.position.x, expected_x, 0.5,
		"Iaquis awaken closeup should align to bottom-right (x)")
	assert_almost_eq(game.awaken_animation.position.y, expected_y, 0.5,
		"Iaquis awaken closeup should align to bottom-right (y)")
	game.queue_free()
	await get_tree().process_frame

# --- Iaquis: no closeup/effect on extra attacks (chain attacks) ---

func test_iaquis_ultras_no_animation_when_extra_attack():
	var game = make_game_with_deck("iaquis")
	game.strike_is_extra_attack = true
	game._play_iaquis_heart_entrance(true)
	game._play_iaquis_heart_entrance(false)
	game._play_iaquis_heart_damage()
	game._play_iaquis_descent_entrance(true)
	game._play_iaquis_descent_entrance(false)
	game._play_iaquis_descent_damage()
	await get_tree().process_frame
	assert_null(game.heart_animation_right, "No Heart closeup on extra attack")
	assert_null(game.heart_animation_left, "No Heart left closeup on extra attack")
	assert_null(game.heart_damage_animation, "No Heart damage effect on extra attack")
	assert_null(game.descent_animation_right, "No Descent closeup on extra attack")
	assert_null(game.descent_animation_left, "No Descent left closeup on extra attack")
	assert_null(game.descent_damage_animation, "No Descent damage effect on extra attack")
	game.queue_free()
	await get_tree().process_frame

func test_iaquis_ultras_play_when_main_attack():
	var game = make_game_with_deck("iaquis")
	game.strike_is_extra_attack = false
	game._play_iaquis_heart_entrance(true)
	game._play_iaquis_heart_damage()
	game._play_iaquis_descent_entrance(false)
	game._play_iaquis_descent_damage()
	await get_tree().process_frame
	assert_not_null(game.heart_animation_right, "Heart closeup plays as main attack")
	assert_not_null(game.heart_damage_animation, "Heart damage effect plays as main attack")
	assert_not_null(game.descent_animation_left, "Descent closeup plays as main attack")
	assert_not_null(game.descent_damage_animation, "Descent damage effect plays as main attack")
	game.queue_free()
	await get_tree().process_frame

# --- Ultra damage effects require the card to have ACTIVATED (2026-08-23) ---
# A wild-swing ultra whose cost was declined (PayCost_Unable -> invalidated)
# stays in strike_attack_card_ids but NEVER activates, so it must not count
# for the full-screen damage effect. Only cards with a Strike_CardActivation
# event (cost paid, card took effect) count.

func test_geoffrey_judgment_damage_requires_activated_card():
	default_game_setup("geoffrey")
	var game = make_game_with_deck("geoffrey")
	game.game_wrapper.current_game = game_logic
	var card_id = give_player_specific_card(player2, "geoffrey_inviolablejudgment")
	game.strike_attack_card_ids = [card_id]
	game.strike_activated_card_ids = []
	assert_false(game._is_geoffrey_judgment_dealing_damage_to(Enums.PlayerId.PlayerId_Player),
			"Un-activated ultra (wild swing declined) must not count for the damage effect")
	game.strike_activated_card_ids = [card_id]
	assert_true(game._is_geoffrey_judgment_dealing_damage_to(Enums.PlayerId.PlayerId_Player),
			"Activated ultra should count for the damage effect")
	game.queue_free()
	await get_tree().process_frame

func test_qoh_damage_requires_activated_card():
	default_game_setup("eugenia")
	var game = make_game_with_deck("eugenia")
	game.game_wrapper.current_game = game_logic
	var card_id = give_player_specific_card(player2, "eugenia_queen_of_hearts")
	game.strike_attack_card_ids = [card_id]
	game.strike_activated_card_ids = []
	assert_false(game._is_qoh_strike_dealing_damage_to(Enums.PlayerId.PlayerId_Player),
			"Un-activated QOH must not count for the damage effect")
	game.strike_activated_card_ids = [card_id]
	assert_true(game._is_qoh_strike_dealing_damage_to(Enums.PlayerId.PlayerId_Player),
			"Activated QOH should count for the damage effect")
	game.queue_free()
	await get_tree().process_frame

# --- Iaquis initial-skill face-attack closeup + stun easter-egg (2026-08-23) ---

func test_iaquis_faceup_closeup_plays_center():
	var game = make_game_with_deck("iaquis")
	game._play_iaquis_faceup(false)
	await get_tree().process_frame
	assert_not_null(game.iaquis_faceup_animation, "Faceup closeup should be created")
	assert_eq(game.iaquis_faceup_animation.sprite_frames.get_frame_count("iaquis_faceup"), 25,
			"Faceup closeup should have 25 frames")
	assert_eq(game.iaquis_faceup_animation.position, Vector2(640.0, 360.0),
			"Faceup closeup should be screen-centered")
	assert_not_null(load("res://assets/entrance_animations/iaquis/iaquis_faceup_bonus_00.png"),
			"Stun easter-egg frames should exist")
	game.queue_free()
	await get_tree().process_frame

func test_iaquis_faceup_bonus_plays_center():
	var game = make_game_with_deck("iaquis")
	game._play_iaquis_faceup(true)
	await get_tree().process_frame
	assert_not_null(game.iaquis_faceup_animation, "Bonus closeup should be created")
	assert_eq(game.iaquis_faceup_animation.sprite_frames.get_frame_count("iaquis_faceup"), 25,
			"Bonus closeup should have 25 frames")
	assert_eq(game.iaquis_faceup_animation.position, Vector2(640.0, 360.0),
			"Bonus closeup should be screen-centered")
	game.queue_free()
	await get_tree().process_frame

func test_iaquis_faceup_deduped_and_cleanup():
	var game = make_game_with_deck("iaquis")
	game._play_iaquis_faceup(false)
	await get_tree().process_frame
	var first = game.iaquis_faceup_animation
	game._play_iaquis_faceup(false)
	await get_tree().process_frame
	assert_eq(game.iaquis_faceup_animation, first, "Second call should reuse the existing animation")
	game._on_iaquis_faceup_animation_finished()
	await get_tree().process_frame
	assert_null(game.iaquis_faceup_animation, "Faceup closeup should be cleaned up after finishing")
	game.queue_free()
	await get_tree().process_frame

func test_is_player_iaquis_detects_deck():
	default_game_setup("iaquis")
	var game = make_game_with_deck("iaquis")
	game.game_wrapper.current_game = game_logic
	assert_true(game._is_player_iaquis(Enums.PlayerId.PlayerId_Opponent),
			"Opponent (iaquis deck) should be detected")
	assert_false(game._is_player_iaquis(Enums.PlayerId.PlayerId_Player),
			"Local player (renea deck) should not be detected as iaquis")
	game.queue_free()
	await get_tree().process_frame
