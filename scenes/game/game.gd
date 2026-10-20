# This is an instance of the game.
class_name Game
extends Node2D

signal returning_from_game
signal load_characters_complete
signal loading_status_changed(status_text : String)
signal replay_save_finished

const UseHugeCard = false

const Test_StartWithGauge = false

const CardBaseScene = preload("res://scenes/card/card_base.tscn")
const CardPopoutScene = preload("res://scenes/game/card_popout.tscn")
const CharacterScene = preload("res://scenes/game/character.tscn")
const BackgroundManager = preload("res://globals/game_background_manager.gd")
const HpRankModeManagerScript = preload("res://globals/hp_rank_mode_manager.gd")

@onready var player_emote : EmoteDisplay = $PlayerEmote
@onready var opponent_emote : EmoteDisplay = $OpponentEmote

@onready var damage_popup_template = preload("res://scenes/game/damage_popup.tscn")
@onready var arena_layout = $ArenaNode/RowButtons
@onready var arena_graphics = $ArenaNode/RowPlatforms
@onready var friend_track_layer : TextureRect = $FriendTrackLayer
@onready var enemy_track_layer : TextureRect = $EnemyTrackLayer
@onready var background_image : TextureRect = $BackgroundImage
@onready var rotation_layout_overlay : ColorRect = $RotationLayoutOverlay

var friend_track_overlay_layers : Array[TextureRect] = []
var enemy_track_overlay_layers : Array[TextureRect] = []

@onready var huge_card : Sprite2D = $HugeCard

@onready var emote_dialog : EmoteDialog = $EmoteDialog
@onready var modal_dialog : ModalDialog = $ModalDialog
@onready var surrender_button : Button = $PlayerLife/SurrenderButton

@onready var save_replay_button = $PlayerZones/SaveReplayButton
@onready var file_dialog = $FileDialog

@onready var slideout_dialog : SlideoutDialog = $SlideoutDialog

const OffScreen = Vector2(-1000, -1000)
const ChoiceCopyIdRangeStart = 70000
const RevealCopyIdRangeStart = 80000
const ReferenceScreenIdRangeStart = 90000
const NoticeOffsetY = 50
const BaseViewportSize = Vector2(1280.0, 720.0)

const SlideoutStartPosition = Vector2(1280, 380)

var starting_timer : float = GlobalSettings.DefaultStartingTimer
var player_clock_remaining : float = GlobalSettings.DefaultStartingTimer
var opponent_clock_remaining : float = GlobalSettings.DefaultStartingTimer
var enforce_timer = GlobalSettings.DefaultEnforceTimer
var minimum_time_per_choice = GlobalSettings.DefaultMinimumTimePerChoice
var current_clock_user : Enums.PlayerId = Enums.PlayerId.PlayerId_Unassigned
var new_clock_user_assigned : bool = false
const GameTimerClockServerDelay : float = 0.2
var clock_delay_remaining : float = -1
var player_notified_of_clock : bool = false

const ChoiceTextLengthSoftCap = 45
const ChoiceTextLengthHardCap = 60
const MaxBonusPanelWidth = 225

const CardPopoutZIndex = 5

const StrikeRevealDelay : float = 2.0
const MoveDelay : float = 1.0
const BoostDelay : float = 2.0
const SmallNoticeDelay : float = 1.0
# TODO const AutoThinkingEmoteDelay : float = 12.0
# TODO const AutoThinkingEmoteText := "思考中……"
const WebRuntimeAnimationBacklogThreshold : int = 8
const WebRuntimeAnimationBacklogScale : float = 0.25
const WebRuntimeAnimationMinimumDelay : float = 0.1
const WebRuntimeLoadYieldBatchSize : int = 4
const MobileWebRuntimeLoadYieldBatchSize : int = 1
const MobileWebProblematicNormalsCardScale : float = 1.0
const WebRuntimeArenaVisualYieldFrames : int = 1
const WebRuntimeEventYieldBatchSize : int = 6
const WebRuntimeEventYieldDelay : float = 0.05
const WebRuntimeRotationSettleFrames : int = 2
const WebRuntimeMinimumViewportSize := Vector2(320.0, 240.0)
const WebRuntimeMaximumInvalidViewportRetries : int = 8
const ReplaySaveDirectory := "user://replays/"
const WebRuntimeBacklogThresholdModerate : int = 12
const WebRuntimeBacklogThresholdSevere : int = 24
const WebRuntimeEventBudgetUnlimited : int = -1
const WebRuntimeEventBudgetModerate : int = 8
const WebRuntimeEventBudgetSevere : int = 4
const WebRuntimeSlowFrameWarningDelta : float = 0.05
const WebRuntimeSlowFrameSevereDelta : float = 0.085
const WebRuntimeSlowFrameWarningCount : int = 1
const WebRuntimeSlowFrameSevereCount : int = 3
const WebRuntimeRecoveryStableFrames : int = 45
const ShowRuntimeHealthDebugOverlay : bool = true

enum RuntimeBacklogLevel {
	RuntimeBacklogLevel_None,
	RuntimeBacklogLevel_Moderate,
	RuntimeBacklogLevel_Severe,
}

enum RuntimeFramePressureLevel {
	RuntimeFramePressureLevel_None,
	RuntimeFramePressureLevel_Warning,
	RuntimeFramePressureLevel_Severe,
}

enum RuntimeHealthState {
	RuntimeHealthState_Healthy,
	RuntimeHealthState_Warning,
	RuntimeHealthState_Backlogged,
	RuntimeHealthState_Recovery,
}

var remaining_delay = 0
var hp_rank_mode_manager = HpRankModeManagerScript.new()
var restore_fast_forward_pending := false
var restore_fast_forwarding := false
var events_to_process = []
var runtime_health_debug_overlay_enabled : bool = false
var runtime_backlog_level : int = RuntimeBacklogLevel.RuntimeBacklogLevel_None
var runtime_health_state : int = RuntimeHealthState.RuntimeHealthState_Healthy
var runtime_pending_event_pressure_count : int = 0
var runtime_slow_frame_count : int = 0
var runtime_stable_frame_count : int = WebRuntimeRecoveryStableFrames
var runtime_last_frame_delta : float = 0.0
var runtime_event_batch_in_progress : bool = false
var deferred_player_hand_layout : bool = false
var deferred_opponent_hand_layout : bool = false
var deferred_card_count_refresh : bool = false

var damage_popup_pool:Array[DamagePopup] = []

var insert_ai_pause = false
var popout_instruction_info = null
var ignore_queue_notifications = false

var ChoiceTagRegex = RegEx.new()

var first_run_done = false
var first_run_in_progress = false
var setup_characters_complete = false
var hold_match_entry_processing : bool = false
var select_card_require_min = 0
var select_card_require_max = 0
var select_card_restriction_ids = []
var select_card_show_restriction_list_ui = false
var select_card_name_card_both_players = false
var select_card_must_be_max_or_min = false
var select_card_require_force = 0
var select_card_up_to_force = 0
var select_card_destination = ""
var select_gauge_require_card_id = ""
var select_gauge_require_card_name = ""
var select_gauge_valid_card_types = []
var select_boost_options = {}
var select_card_name_boost_restriction = ""
var selected_boost_to_pay_for = -1
var selected_boost_facedown_override = null
var instructions_ok_allowed = false
var instructions_cancel_allowed = false
var instructions_strike_options = {}
var instructions_pay_alternative_life_cost = 0
var instructions_ex_allowed = false
var instructions_ex_required = false
var instructions_face_attack_card = null
var selected_cards = []
var mulligan_selected_card_ids_tmp : Array = []
var enabled_reminder_text = false
var arena_locations_clickable = []
var selected_arena_location = 0
var force_for_armor_incoming_damage = 0
var force_for_armor_ignore_armor = false
var force_for_armor_amount = 2
var popout_exlude_card_ids = []
var selected_character_action = 0
var cached_player_location = 0
var cached_opponent_location = 0
var reference_popout_toggle_enabled = false
var reference_popout_toggle = false
var opponent_cards_before_reshuffle = []
var treat_ultras_as_single_force = false
var discard_ex_first_for_strike = false
var use_free_force = false
var can_spend_life_for_force = false
var can_spend_life_for_gauge = false
var can_seal_for_force = false
var can_seal_for_gauge = false
var minato_sealed_gauge = 0
var current_pay_costs_is_ex = false
var preparing_character_action = false
var prepared_character_action_data = {}
var choice_popout_title = ""

var player_deck
var opponent_deck
var resolved_arena_style : String = BackgroundManager.DEFAULT_BACKGROUND_ID

# Match-start entrance animation (Eugenia closeup, played once after the versus splash).
const EugeniaEntranceFrameCount = 14
const EugeniaEntranceFrameBase = "res://assets/entrance_animations/eugenia/frame_%02d.png"
const EugeniaEntranceFps = 10.0
# Eugenia awaken closeup (played once when the local Eugenia player exceeds).
const EugeniaAwakenFrameCount = 14
const EugeniaAwakenFrameBase = "res://assets/entrance_animations/eugenia/awaken_%02d.png"
const EugeniaAwakenFps = 10.0
# Eugenia Cat's Cradle hit closeup. Each client picks the side that matches its
# own perspective: the attacker's client plays the right-side frames, the
# defender's client plays the left-side frames. When both players attack with
# Cat's Cradle in the same strike, both clients show both versions side by
# side. Triggers off the discard event the Cradle's hit effect produces.
const EugeniaCatsCradleLeftFrameBase = "res://assets/entrance_animations/eugenia/cats_cradle_left_%02d.png"
const EugeniaCatsCradleRightFrameBase = "res://assets/entrance_animations/eugenia/cats_cradle_right_%02d.png"
const EugeniaCatsCradleFrameCount = 14
const EugeniaCatsCradleFps = 10.0
# Eugenia Queen of Hearts hit closeup. Same attacker/defender split as Cat's
# Cradle (right = attacker side, left = defender side).
const EugeniaQohLeftFrameBase = "res://assets/entrance_animations/eugenia/qoh_left_%02d.png"
const EugeniaQohRightFrameBase = "res://assets/entrance_animations/eugenia/qoh_right_%02d.png"
const EugeniaQohFrameCount = 14
const EugeniaQohFps = 10.0
# Eugenia Queen of Hearts damage-resolve effect (played once when damage from a
# Queen of Hearts strike is resolved, after all hit effects). 89 jpg frames.
const EugeniaQohDamageFrameCount = 89
const EugeniaQohDamageFrameBase = "res://assets/entrance_animations/eugenia/qoh_damage_%03d.jpg"
const EugeniaQohDamageFps = 10.0
# Time for Tea (Eugenia's action skill Plot Hook -> Time for Tea) closeup,
# triggered after the force_for_effect payment completes and the opponent
# discards as the overall_effect.
const EugeniaTeaTimeFrameCount = 14
const EugeniaTeaTimeFrameBase = "res://assets/entrance_animations/eugenia/tea_time_%02d.png"
const EugeniaTeaTimeFps = 10.0
# Cat's Cradle hit closeup, full-screen damage-resolve effect (played once
# when damage from a Cat's Cradle strike is resolved, after all hit effects).
# Like qoh_damage, both clients see it once per strike.
const EugeniaCatsCradleHitFrameCount = 26
const EugeniaCatsCradleHitFrameBase = "res://assets/entrance_animations/eugenia/cats_cradle_hit_%02d.png"
const EugeniaCatsCradleHitFps = 10.0
# Zsolt match-start entrance closeup (bottom-right corner).
const ZsoltEntranceFrameCount = 14
const ZsoltEntranceFrameBase = "res://assets/entrance_animations/zsolt/frame_%02d.png"
const ZsoltEntranceFps = 10.0
# Zsolt awaken closeup (bottom-right corner).
const ZsoltAwakenFrameCount = 14
const ZsoltAwakenFrameBase = "res://assets/entrance_animations/zsolt/awaken_%02d.png"
const ZsoltAwakenFps = 10.0
# Zsolt Fatal Eye effect closeup (bottom-left corner), played when Fatal Eye
# takes effect (card activation, after any costs are paid).
const ZsoltFatalEyeFrameCount = 14
const ZsoltFatalEyeFrameBase = "res://assets/entrance_animations/zsolt/fatal_eye_%02d.png"
const ZsoltFatalEyeFps = 10.0
# Zsolt Wild Hunt (ultra) effect closeup, per-side like Eugenia's Cat's Cradle
# / Queen of Hearts: local client plays the right-side frames (attacker
# perspective, top-right corner), opponent client plays the left-side frames
# (defender perspective, top-left corner). Both clients replay the same event
# stream, so each sees its own side. Wild Hunt can chain into follow-up
# extra attacks (Zsolt awaken); the effect closeup is gated to the MAIN
# attack card only via the UI-tracked `strike_is_extra_attack` flag (set from
# Strike_Started / Strike_Started_ExtraAttack events; NOT queried from the
# engine, because events are replayed asynchronously).
const ZsoltWildHuntFrameCount = 14
const ZsoltWildHuntLeftFrameBase = "res://assets/entrance_animations/zsolt/zsolt_wild_hunt_left_%02d.png"
const ZsoltWildHuntRightFrameBase = "res://assets/entrance_animations/zsolt/zsolt_wild_hunt_right_%02d.png"
const ZsoltWildHuntFps = 10.0
# Zsolt Wild Hunt damage-resolve effect, full-screen, played once when the
# damage from a Wild Hunt strike is resolved (after all hit effects). Both
# clients see it, like qoh_damage / cats_cradle_hit. Gated to the MAIN attack
# card so chain attacks don't double-fire it.
const ZsoltWildHuntDamageFrameCount = 34
const ZsoltWildHuntDamageFrameBase = "res://assets/entrance_animations/zsolt/zsolt_wild_hunt_damage_%02d.png"
const ZsoltWildHuntDamageFps = 10.0
# Zsolt Fanatical Purification (净世焚剑, ultra) effect closeup, per-side like
# Wild Hunt: local client plays the right frames (attacker perspective,
# top-right), opponent client plays the left frames (top-left). Gated to the
# MAIN attack card so chain extra attacks don't re-fire it.
const ZsoltPurificationFrameCount = 14
const ZsoltPurificationLeftFrameBase = "res://assets/entrance_animations/zsolt/zsolt_purification_left_%02d.png"
const ZsoltPurificationRightFrameBase = "res://assets/entrance_animations/zsolt/zsolt_purification_right_%02d.png"
const ZsoltPurificationFps = 10.0
# Zsolt Fanatical Purification damage-resolve effect, full-screen, one per
# strike, gated to the MAIN attack card.
const ZsoltPurificationDamageFrameCount = 22
const ZsoltPurificationDamageFrameBase = "res://assets/entrance_animations/zsolt/zsolt_purification_damage_%02d.png"
const ZsoltPurificationDamageFps = 10.0
# Geoffrey Inviolable Judgment (神圣裁决, ultra) effect closeup, per-side like
# Wild Hunt / Purification: local client plays the right frames (attacker
# perspective, top-right), opponent client plays the left frames (top-left).
# Gated to the MAIN attack card so chain extra attacks don't re-fire it.
const GeoffreyJudgmentFrameCount = 14
const GeoffreyJudgmentLeftFrameBase = "res://assets/entrance_animations/geoffrey/geoffrey_judgment_left_%02d.png"
const GeoffreyJudgmentRightFrameBase = "res://assets/entrance_animations/geoffrey/geoffrey_judgment_right_%02d.png"
const GeoffreyJudgmentFps = 10.0
# Geoffrey Inviolable Judgment damage-resolve effect, full-screen, one per
# strike, gated to the MAIN attack card.
const GeoffreyJudgmentDamageFrameCount = 29
const GeoffreyJudgmentDamageFrameBase = "res://assets/entrance_animations/geoffrey/geoffrey_judgment_damage_%02d.png"
const GeoffreyJudgmentDamageFps = 10.0
# Geoffrey Crusader's Oath (圣教军誓言, ultra) effect closeup, per-side like
# Wild Hunt / Purification. Gated to the MAIN attack card.
const GeoffreyCrusaderFrameCount = 14
const GeoffreyCrusaderLeftFrameBase = "res://assets/entrance_animations/geoffrey/geoffrey_crusader_left_%02d.png"
const GeoffreyCrusaderRightFrameBase = "res://assets/entrance_animations/geoffrey/geoffrey_crusader_right_%02d.png"
const GeoffreyCrusaderFps = 10.0
# Geoffrey Crusader's Oath damage-resolve effect, full-screen, one per strike.
const GeoffreyCrusaderDamageFrameCount = 26
const GeoffreyCrusaderDamageFrameBase = "res://assets/entrance_animations/geoffrey/geoffrey_crusader_damage_%02d.png"
const GeoffreyCrusaderDamageFps = 10.0
# Geoffrey entrance / awaken closeups (frame_ / awaken_ frames, 14 frames each),
# both aligned to the bottom-right corner, local player only.
const GeoffreyEntranceFrameCount = 14
const GeoffreyEntranceFrameBase = "res://assets/entrance_animations/geoffrey/frame_%02d.png"
const GeoffreyEntranceFps = 10.0
const GeoffreyAwakenFrameCount = 14
const GeoffreyAwakenFrameBase = "res://assets/entrance_animations/geoffrey/awaken_%02d.png"
const GeoffreyAwakenFps = 10.0
# Geoffrey Compulsive Purification (inquisition transform, 强制净化) effect
# closeup: bottom-left corner. Plays when the Geoffrey player presses OK to
# confirm the force_for_effect payment (the negation takes effect), never on
# cancel. 20% chance plays the bonus (easter-egg) version.
const GeoffreyPurificationFrameCount = 14
const GeoffreyPurificationFrameBase = "res://assets/entrance_animations/geoffrey/geoffrey_purification_%02d.png"
const GeoffreyPurificationBonusFrameBase = "res://assets/entrance_animations/geoffrey/geoffrey_purification_bonus_%02d.png"
const GeoffreyPurificationFps = 10.0
const GeoffreyPurificationBonusChance = 0.2
# Iaquis Dragon's Heart (潜龙之心, ultra 2G) effect closeup, per-side like
# Wild Hunt / Purification: local attacker -> right frames (top-right),
# opponent defender -> left frames (top-left). Gated to the MAIN attack
# card so chain extra attacks don't re-fire it.
const IaquisHeartFrameCount = 14
const IaquisHeartLeftFrameBase = "res://assets/entrance_animations/iaquis/iaquis_heart_left_%02d.png"
const IaquisHeartRightFrameBase = "res://assets/entrance_animations/iaquis/iaquis_heart_right_%02d.png"
const IaquisHeartFps = 10.0
# Iaquis Dragon's Heart damage-resolve effect, full-screen, one per strike.
const IaquisHeartDamageFrameCount = 29
const IaquisHeartDamageFrameBase = "res://assets/entrance_animations/iaquis/iaquis_heart_damage_%02d.png"
const IaquisHeartDamageFps = 10.0
# Iaquis Dragon's Descent (翔龙爆裂斩, ultra 3G) effect closeup, per-side.
const IaquisDescentFrameCount = 14
const IaquisDescentLeftFrameBase = "res://assets/entrance_animations/iaquis/iaquis_descent_left_%02d.png"
const IaquisDescentRightFrameBase = "res://assets/entrance_animations/iaquis/iaquis_descent_right_%02d.png"
const IaquisDescentFps = 10.0
# Iaquis Dragon's Descent damage-resolve effect, full-screen (54 frames).
const IaquisDescentDamageFrameCount = 54
const IaquisDescentDamageFrameBase = "res://assets/entrance_animations/iaquis/iaquis_descent_damage_%02d.png"
const IaquisDescentDamageFps = 10.0
# Iaquis entrance / awaken closeups (frame_ / awaken_, 14 frames each),
# bottom-right corner, local player only.
const IaquisEntranceFrameCount = 14
const IaquisEntranceFrameBase = "res://assets/entrance_animations/iaquis/frame_%02d.png"
const IaquisEntranceFps = 10.0
const IaquisAwakenFrameCount = 14
const IaquisAwakenFrameBase = "res://assets/entrance_animations/iaquis/awaken_%02d.png"
const IaquisAwakenFps = 10.0
# Iaquis initial-skill face-attack closeup (龙男ua特写) + stun easter-egg
# (龙男ua彩蛋特写): 25 frames each, screen center, both clients play.
const IaquisFaceupFrameCount = 25
const IaquisFaceupFrameBase = "res://assets/entrance_animations/iaquis/iaquis_faceup_%02d.png"
const IaquisFaceupBonusFrameBase = "res://assets/entrance_animations/iaquis/iaquis_faceup_bonus_%02d.png"
const IaquisFaceupFps = 10.0
const EntranceScreenWidth = 1280.0
const EntranceScreenHeight = 720.0

var entrance_animation : AnimatedSprite2D
var entrance_animation_layer : CanvasLayer
var awaken_animation : AnimatedSprite2D
var awaken_animation_layer : CanvasLayer
# Cat's Cradle hit closeup, kept per-side so both clients can run left and
# right versions at the same time (e.g. when both players attack with Cradle
# in the same strike, the local client shows the local Cradle as right and
# the opponent's Cradle as left, side by side).
var cats_cradle_animation_left : AnimatedSprite2D
var cats_cradle_animation_layer_left : CanvasLayer
var cats_cradle_animation_right : AnimatedSprite2D
var cats_cradle_animation_layer_right : CanvasLayer
# Queen of Hearts hit closeup, same per-side split as Cat's Cradle.
var qoh_animation_left : AnimatedSprite2D
var qoh_animation_layer_left : CanvasLayer
var qoh_animation_right : AnimatedSprite2D
var qoh_animation_layer_right : CanvasLayer
var qoh_damage_animation : AnimatedSprite2D
var qoh_damage_animation_layer : CanvasLayer
# Time for Tea (Eugenia's action skill) closeup: triggered after the
# force_for_effect payment completes and the opponent discards a card as the
# overall_effect. Set by _on_force_for_effect, consumed by _on_discard_event.
var tea_time_animation : AnimatedSprite2D
var tea_time_animation_layer : CanvasLayer
var tea_time_pending : bool = false
# Cat's Cradle hit closeup, full-screen damage-resolve effect (one per strike).
var cats_cradle_hit_animation : AnimatedSprite2D
var cats_cradle_hit_animation_layer : CanvasLayer
var cats_cradle_hit_played_this_strike : bool = false
# Zsolt Fatal Eye effect closeup (one per strike, bottom-left corner).
var fatal_eye_animation : AnimatedSprite2D
var fatal_eye_animation_layer : CanvasLayer
var fatal_eye_played_this_strike : bool = false
# Zsolt Wild Hunt hit closeup, per-side (both clients show their own side
# during the same strike, side by side when both attack with Wild Hunt).
var wild_hunt_animation_left : AnimatedSprite2D
var wild_hunt_animation_layer_left : CanvasLayer
var wild_hunt_animation_right : AnimatedSprite2D
var wild_hunt_animation_layer_right : CanvasLayer
var wild_hunt_left_played_this_strike : bool = false
var wild_hunt_right_played_this_strike : bool = false
# Zsolt Wild Hunt damage-resolve effect (full-screen, one per strike).
var wild_hunt_damage_animation : AnimatedSprite2D
var wild_hunt_damage_animation_layer : CanvasLayer
var wild_hunt_damage_played_this_strike : bool = false
# Zsolt Fanatical Purification hit closeup, per-side (same as Wild Hunt).
var purification_animation_left : AnimatedSprite2D
var purification_animation_layer_left : CanvasLayer
var purification_animation_right : AnimatedSprite2D
var purification_animation_layer_right : CanvasLayer
var purification_left_played_this_strike : bool = false
var purification_right_played_this_strike : bool = false
# Zsolt Fanatical Purification damage-resolve effect (full-screen, one per strike).
var purification_damage_animation : AnimatedSprite2D
var purification_damage_animation_layer : CanvasLayer
var purification_damage_played_this_strike : bool = false
# Geoffrey Inviolable Judgment hit closeup, per-side (same as Wild Hunt).
var judgment_animation_left : AnimatedSprite2D
var judgment_animation_layer_left : CanvasLayer
var judgment_animation_right : AnimatedSprite2D
var judgment_animation_layer_right : CanvasLayer
var judgment_left_played_this_strike : bool = false
var judgment_right_played_this_strike : bool = false
# Geoffrey Inviolable Judgment damage-resolve effect (full-screen, one per strike).
var judgment_damage_animation : AnimatedSprite2D
var judgment_damage_animation_layer : CanvasLayer
var judgment_damage_played_this_strike : bool = false
# Geoffrey Crusader's Oath hit closeup, per-side (same as Wild Hunt).
var crusader_animation_left : AnimatedSprite2D
var crusader_animation_layer_left : CanvasLayer
var crusader_animation_right : AnimatedSprite2D
var crusader_animation_layer_right : CanvasLayer
var crusader_left_played_this_strike : bool = false
var crusader_right_played_this_strike : bool = false
# Geoffrey Crusader's Oath damage-resolve effect (full-screen, one per strike).
var crusader_damage_animation : AnimatedSprite2D
var crusader_damage_animation_layer : CanvasLayer
var crusader_damage_played_this_strike : bool = false
# Geoffrey Compulsive Purification (inquisition transform) effect closeup
# (bottom-left, one at a time).
var geoffrey_purification_animation : AnimatedSprite2D
var geoffrey_purification_animation_layer : CanvasLayer
# Iaquis Dragon's Heart hit closeup, per-side (same as Wild Hunt).
var heart_animation_left : AnimatedSprite2D
var heart_animation_layer_left : CanvasLayer
var heart_animation_right : AnimatedSprite2D
var heart_animation_layer_right : CanvasLayer
var heart_left_played_this_strike : bool = false
var heart_right_played_this_strike : bool = false
# Iaquis Dragon's Heart damage-resolve effect (full-screen, one per strike).
var heart_damage_animation : AnimatedSprite2D
var heart_damage_animation_layer : CanvasLayer
var heart_damage_played_this_strike : bool = false
# Iaquis Dragon's Descent hit closeup, per-side.
var descent_animation_left : AnimatedSprite2D
var descent_animation_layer_left : CanvasLayer
var descent_animation_right : AnimatedSprite2D
var descent_animation_layer_right : CanvasLayer
var descent_left_played_this_strike : bool = false
var descent_right_played_this_strike : bool = false
# Iaquis Dragon's Descent damage-resolve effect (full-screen, one per strike).
var descent_damage_animation : AnimatedSprite2D
var descent_damage_animation_layer : CanvasLayer
var descent_damage_played_this_strike : bool = false
# Iaquis initial-skill face-attack closeup (screen center, both clients play
# on RevealStrike_OnePlayer) and the stun easter-egg variant.
var iaquis_faceup_animation : AnimatedSprite2D
var iaquis_faceup_animation_layer : CanvasLayer
# True while the current strike: Iaquis chose the face-up attack (reveal_strike
# from the initial ability) / Iaquis landed a hit on the opponent. Reset every
# strike so the stun easter-egg never leaks into the next fight.
var iaquis_faceup_this_strike : bool = false
var iaquis_hit_opponent_this_strike : bool = false
# Card ids set as attack cards in the current strike. The UI populates this
# from Strike_Started / Strike_Response events so hit-closeup and damage-effect
# triggers can tell "this card is actually attacking" from "this card is just a
# boost that briefly sits in the Striking area". We deliberately track it in
# the UI (not via the engine's active_strike) because events are replayed
# asynchronously and active_strike may already be gone by the time the UI
# processes a discard/damage event.
var strike_attack_card_ids : Array = []
# Card ids whose gauge/force cost was actually PAID and the card ACTIVATED
# (Strike_CardActivation event) in the current strike. A wild-swing card
# whose cost was declined (PayCost_Unable -> invalidated) never activates,
# so it must not count for damage-effect animations even though it sits in
# strike_attack_card_ids.
var strike_activated_card_ids : Array = []
# True while the current strike is an EXTRA attack (chain attack, e.g. Zsolt
# awaken). The UI tracks this from the event stream (Strike_Started sets it
# false, Strike_Started_ExtraAttack sets it true) instead of querying the
# engine live, because events are replayed asynchronously and
# active_strike.extra_attack_in_progress is already reset by the time the UI
# processes the extra attack's activation/damage events.
var strike_is_extra_attack : bool = false
# Cat's Cradle hit closeup: at most one per side per strike (local player
# attacks -> right, opponent attacks -> left). Both can fire in the same
# strike when both players use Cradle.
var cats_cradle_left_played_this_strike : bool = false
var cats_cradle_right_played_this_strike : bool = false
# The closeups are NOT played on card activation: we only arm a pending flag
# there (the strike may still miss). The pending flag is consumed when the
# engine confirms the hit (Strike_Hit), or cleared on a miss / at cleanup.
var cats_cradle_left_pending_this_strike : bool = false
var cats_cradle_right_pending_this_strike : bool = false
# Queen of Hearts hit closeup: same per-side split.
var qoh_left_played_this_strike : bool = false
var qoh_right_played_this_strike : bool = false
var qoh_left_pending_this_strike : bool = false
var qoh_right_pending_this_strike : bool = false
# One Queen of Hearts damage-resolve effect per strike (both clients see it once).
var qoh_damage_effect_played_this_strike : bool = false

func is_tournelouse_transform_bonus_choice() -> bool:
	if not game_wrapper:
		return false
	var decision_effect = game_wrapper.get_decision_info().effect
	return decision_effect != null and decision_effect.get("effect_type") in [StrikeEffects.SealTransformForPowerup, StrikeEffects.SealTransformForArmorup]

func is_tournelouse_transform_zone_choice() -> bool:
	if not game_wrapper:
		return false
	var decision_effect = game_wrapper.get_decision_info().effect
	return decision_effect != null and (is_tournelouse_transform_bonus_choice() or decision_effect.get("tournelouse_ouroboros") or decision_effect.get("tournelouse_ouroboros_return_transform"))

func is_tournelouse_ouroboros_force_choice() -> bool:
	if not game_wrapper:
		return false
	var decision_effect = game_wrapper.get_decision_info().effect
	return decision_effect != null and decision_effect.get("tournelouse_ouroboros_force")

func is_tournelouse_ouroboros_hand_choice() -> bool:
	if not game_wrapper:
		return false
	var decision_effect = game_wrapper.get_decision_info().effect
	return decision_effect != null and decision_effect.get("tournelouse_ouroboros_select_hand")

func is_tournelouse_ouroboros_transform_return_choice() -> bool:
	if not game_wrapper:
		return false
	var decision_effect = game_wrapper.get_decision_info().effect
	return decision_effect != null and decision_effect.get("tournelouse_ouroboros_return_transform")

func is_tournelouse_ouroboros_legal_hand_transform(card_id : int) -> bool:
	if not game_wrapper:
		return false
	var decision_info = game_wrapper.get_decision_info()
	return decision_info.choice != null and card_id in decision_info.choice

func is_tournelouse_ouroboros_paid_card(card_id : int) -> bool:
	if not game_wrapper:
		return false
	var decision_effect = game_wrapper.get_decision_info().effect
	return decision_effect != null and card_id in decision_effect.get("paid_card_ids", [])

func is_tournelouse_ouroboros_bargeist_return_blocked(card_id : int) -> bool:
	if not game_wrapper:
		return false
	var decision_info = game_wrapper.get_decision_info()
	var decision_effect = decision_info.effect
	if decision_effect == null or not decision_effect.get("tournelouse_ouroboros_return_transform"):
		return false
	if game_wrapper.get_card_database().get_card(card_id).definition.get("id") != "tournelouse_bargeist_fang":
		return false
	var hand_card_id = decision_effect.get("hand_card_id", -1)
	if hand_card_id == -1:
		return false
	var hand_card = game_wrapper.get_card_database().get_card(hand_card_id)
	if hand_card.definition['type'] != "normal":
		return false
	for boost_card in $AllCards/PlayerBoosts.get_children():
		if boost_card.card_id != card_id and game_wrapper.is_card_in_transforms(Enums.PlayerId.PlayerId_Player, boost_card.card_id):
			var transform_card = game_wrapper.get_card_database().get_card(boost_card.card_id)
			if transform_card.definition['display_name'] == hand_card.definition['display_name']:
				return true
	return false

enum ModalDialogType {
	ModalDialogType_None,
	ModalDialogType_ExitToMenu,
	ModalDialogType_Surrender,
	ModalDialogType_CardInform,
}

var modal_dialog_type : ModalDialogType = ModalDialogType.ModalDialogType_None

enum CardPopoutType {
	CardPopoutType_GaugePlayer,
	CardPopoutType_GaugeOpponent,
	CardPopoutType_SealedPlayer,
	CardPopoutType_SealedOpponent,
	CardPopoutType_OverdrivePlayer,
	CardPopoutType_OverdriveOpponent,
	CardPopoutType_DiscardPlayer,
	CardPopoutType_DiscardOpponent,
	CardPopoutType_BoostPlayer,
	CardPopoutType_BoostOpponent,
	CardPopoutType_ReferencePlayer,
	CardPopoutType_ReferenceOpponent,
	CardPopoutType_BuddyPlayer,
	CardPopoutType_BuddyOpponent,
	CardPopoutType_RevealedOpponent,
	CardPopoutType_ChoiceZone,
	CardPopoutType_BleachPlayer,
	CardPopoutType_BleachOpponent,
}

var popout_type_showing : CardPopoutType = CardPopoutType.CardPopoutType_GaugePlayer

enum UIState {
	UIState_Initializing,
	UIState_GameOver,
	UIState_PickTurnAction,
	UIState_MakeChoice,
	UIState_SelectCards,
	UIState_SelectArenaLocation, # 5
	UIState_WaitingOnOpponent,
	UIState_PlayingAnimation,
	UIState_WaitForGameServer,
}

enum UISubState {
	UISubState_None,
	UISubState_SelectCards_BoostCancel,
	UISubState_SelectCards_CharacterAction_Force,
	UISubState_SelectCards_CharacterAction_Gauge,
	UISubState_SelectCards_ChooseBoostsToSustain,
	UISubState_SelectCards_ChooseDiscardToDestination,
	UISubState_SelectCards_ChooseFromTopdeck,
	UISubState_SelectCards_ChooseOpponentCardToDiscard,
	UISubState_SelectCards_DiscardContinuousBoost,
	UISubState_SelectCards_DiscardOpponentGauge,
	UISubState_SelectCards_DiscardFromReference,
	UISubState_SelectCards_MoveActionGenerateForce,
	UISubState_SelectCards_PlayBoost,
	UISubState_SelectCards_DiscardCards,
	UISubState_SelectCards_DiscardCards_Choose,
	UISubState_SelectCards_DiscardCardsToGauge,
	UISubState_SelectCards_ForceForBoost,
	UISubState_SelectCards_ForceForChange,
	UISubState_SelectCards_Exceed, # 16
	UISubState_SelectCards_Mulligan,
	UISubState_SelectCards_StrikeForce,
	UISubState_SelectCards_StrikeGauge,
	UISubState_SelectCards_StrikeCard,
	UISubState_SelectCards_StrikeCard_FromGauge,
	UISubState_SelectCards_StrikeCard_FromSealed,
	UISubState_SelectCards_StrikeResponseCard,
	UISubState_SelectCards_OpponentSetsFirst_StrikeCard,
	UISubState_SelectCards_OpponentSetsFirst_StrikeResponseCard,
	UISubState_SelectCards_ForceForArmor,
	UISubState_SelectCards_ForceForEffect,
	UISubState_SelectCards_GaugeForArmor,
	UISubState_SelectCards_GaugeForEffect,
	UISubState_SelectArena_MoveResponse,
	UISubState_SelectArena_EffectChoice,
	UISubState_PickNumberFromRange,
	UISubState_SelectCards_GaugeForBoost
}

var ui_state : UIState = UIState.UIState_Initializing
var ui_sub_state : UISubState = UISubState.UISubState_None

var previous_ui_state : UIState = UIState.UIState_Initializing
var previous_ui_sub_state : UISubState = UISubState.UISubState_None

var game_wrapper : GameWrapper = GameWrapper.new()
var ai_player : AIPlayer
@onready var card_popout_parent : Node2D = $CardPopoutParent
@onready var choice_zone_parent : Node2D = $AllCards/ChoiceZone
@onready var player_character_card : CharacterCardBase  = $PlayerDeck/PlayerCharacterCard
@onready var player_buddy_character_card : CharacterCardBase  = $PlayerDeck/PlayerBuddyCharacterCard
@onready var opponent_character_card : CharacterCardBase  = $OpponentDeck/OpponentCharacterCard
@onready var opponent_buddy_character_card : CharacterCardBase  = $OpponentDeck/OpponentBuddyCharacterCard
@onready var player_buddies : Array[Character] = [$PlayerBuddy, $PlayerBuddy2, $PlayerBuddy3, $PlayerBuddy4, $PlayerBuddy5, $PlayerBuddy6]
@onready var opponent_buddies : Array[Character] = [$OpponentBuddy, $OpponentBuddy2, $OpponentBuddy3, $OpponentBuddy4, $OpponentBuddy5, $OpponentBuddy6]
@onready var foreground_buddies_parent : Node2D = $ForegroundBuddies
@onready var background_buddies_parent : Node2D = $BackgroundBuddies
@onready var game_over_stuff = $GameOverStuff
@onready var game_over_ko_image : TextureRect = $GameOverStuff/KOImage
@onready var game_over_label = $GameOverStuff/GameOverLabel
@onready var opponent_name_label : Label = $OpponentDeck/OpponentName
@onready var player_bonus_panel = $PlayerStrike/CharBonusPanel
@onready var opponent_bonus_panel = $OpponentStrike/CharBonusPanel
@onready var player_bonus_label = $PlayerStrike/CharBonusPanel/MarginContainer/VBox/AbilityLabel
@onready var opponent_bonus_label = $OpponentStrike/CharBonusPanel/MarginContainer/VBox/AbilityLabel
@onready var action_menu : ActionMenu = $AllCards/ActionContainer/ActionMenu
@onready var action_menu_container : HBoxContainer = $AllCards/ActionContainer
@onready var choice_popout_button : Button = $ChoicePopoutShowButton
@onready var combat_log : CombatLog = $CombatLog
@onready var observer_next_button : Button = $ObserverNextButton
@onready var observer_previous_button : Button = $ObserverPreviousButton
@onready var observer_play_to_live_button : Button = $ObserverPlayToLive
@onready var player_lightningrods : Node2D = $PlayerLightningRods
@onready var opponent_lightningrods : Node2D = $OpponentLightningRods
@onready var turnstart_audio : AudioStreamPlayer = $TurnStartAudio
@onready var runtime_health_debug_toggle_button : Button = $RuntimeHealthDebugToggleButton
@onready var runtime_health_debug_panel : PanelContainer = $RuntimeHealthDebugPanel
@onready var runtime_health_debug_label : Label = $RuntimeHealthDebugPanel/MarginContainer/Label
@onready var boostinfo_dict : Dictionary = {
	Enums.PlayerId.PlayerId_Player: [
		$PlayerZones/BoostInfoContainer/PlayerBoostInfoButton1,
		$PlayerZones/BoostInfoContainer/PlayerBoostInfoButton2
	],
	Enums.PlayerId.PlayerId_Opponent: [
		$OpponentZones/BoostInfoContainer/OpponentBoostInfoButton1,
		$OpponentZones/BoostInfoContainer/OpponentBoostInfoButton2
	]
}
@onready var boostinfo_parent_dict : Dictionary = {
	Enums.PlayerId.PlayerId_Player: $PlayerZones/BoostInfoContainer,
	Enums.PlayerId.PlayerId_Opponent: $OpponentZones/BoostInfoContainer
}

var player_lightningrod_tracking = {}
var opponent_lightningrod_tracking = {}
var player_underboost_tracking = []
var opponent_underboost_tracking = []

var current_instruction_text : String = ""
var current_action_menu_choices : Array = []
var current_effect_choices : Array = []
var current_effect_extra_choice_text : Array = []
var current_topdeck_choosing_player = Enums.PlayerId.PlayerId_Player
var instructions_number_picker_min = -1
var instructions_number_picker_max = -1
var show_thinking_spinner_in : float = 0
const ThinkingSpinnerWaitBeforeShowTime = 1.0
# TODO var auto_thinking_emote_elapsed : float = 0
var starting_message = null
var replay_saving_enabled = false
var observer_mode = false
var observer_live = false
var replay_mode = false
var replay_seek_target : int = -1
var exiting = false
var surrender_in_progress = false
var resources_released = false
var network_reconnect_paused = false
const CombatLogVisibleEntryLimit = 500
var combat_log_rendered_entries : int = 0
var combat_log_rendered_start_index : int = 0

var CenterCardOval = Vector2.ZERO
var HorizontalRadius = 0.0
var VerticalRadius = 0.0
var _viewport_layout_ready = false
var _responsive_position_nodes : Array = []
var _responsive_anchor_roots : Array = []
var _viewport_layout_generation : int = 0
var _rotation_layout_in_progress : bool = false
var _last_stable_viewport_size := Vector2.ZERO

func printlog(text):
	if GlobalSettings.is_logging_enabled():
		print("UI: %s" % text)

# Called when the node enters the scene tree for the first time.
var started_directly : bool = true
var image_loader : CardImageLoader

func set_not_started_directly():
	started_directly = false

func set_match_entry_processing_held(held : bool):
	hold_match_entry_processing = held

# Play the match-start entrance closeup exactly once, right after the versus
# splash is dismissed. Only the client whose LOCAL player picked Eugenia /
# Zsolt plays it (player_deck is always the local player's deck). Skin decks
# keep the base id in "base_id" (e.g. eugenia_1 -> eugenia), so skins are
# covered too. Both closeups align to the bottom-right corner.
func _is_local_player_eugenia() -> bool:
	if player_deck == null:
		return false
	return str(player_deck.get("base_id", player_deck.get("id", ""))) == "eugenia"

func _is_local_player_zsolt() -> bool:
	if player_deck == null:
		return false
	return str(player_deck.get("base_id", player_deck.get("id", ""))) == "zsolt"

func _is_local_player_geoffrey() -> bool:
	if player_deck == null:
		return false
	return str(player_deck.get("base_id", player_deck.get("id", ""))) == "geoffrey"

func _is_local_player_iaquis() -> bool:
	if player_deck == null:
		return false
	return str(player_deck.get("base_id", player_deck.get("id", ""))) == "iaquis"

func try_play_match_start_entrance():
	if not GlobalSettings.AnimationsEnabled:
		return
	if entrance_animation:
		return
	var frame_count = 0
	var frame_base = ""
	var fps = 10.0
	if _is_local_player_eugenia():
		frame_count = EugeniaEntranceFrameCount
		frame_base = EugeniaEntranceFrameBase
		fps = EugeniaEntranceFps
	elif _is_local_player_zsolt():
		frame_count = ZsoltEntranceFrameCount
		frame_base = ZsoltEntranceFrameBase
		fps = ZsoltEntranceFps
	elif _is_local_player_geoffrey():
		frame_count = GeoffreyEntranceFrameCount
		frame_base = GeoffreyEntranceFrameBase
		fps = GeoffreyEntranceFps
	elif _is_local_player_iaquis():
		frame_count = IaquisEntranceFrameCount
		frame_base = IaquisEntranceFrameBase
		fps = IaquisEntranceFps
	else:
		return
	var sf := SpriteFrames.new()
	sf.add_animation("entrance")
	sf.set_animation_loop("entrance", false)
	sf.set_animation_speed("entrance", fps)
	for i in range(frame_count):
		var tex = load(frame_base % i)
		if tex:
			sf.add_frame("entrance", tex)
	if sf.get_frame_count("entrance") == 0:
		return
	entrance_animation_layer = CanvasLayer.new()
	entrance_animation_layer.layer = 100
	add_child(entrance_animation_layer)
	entrance_animation = AnimatedSprite2D.new()
	entrance_animation.sprite_frames = sf
	var frame_size = sf.get_frame_texture("entrance", 0).get_size()
	var scale_factor = 1.0
	if frame_size.x > 0.0 and frame_size.y > 0.0:
		scale_factor = min(EntranceScreenWidth / frame_size.x, EntranceScreenHeight / frame_size.y) * 0.98
		entrance_animation.scale = Vector2(scale_factor, scale_factor)
	# Align the entrance closeup to the bottom-right corner of the screen.
	entrance_animation.position = Vector2(
		EntranceScreenWidth - frame_size.x * scale_factor * 0.5,
		EntranceScreenHeight - frame_size.y * scale_factor * 0.5
	)
	entrance_animation_layer.add_child(entrance_animation)
	entrance_animation.animation_finished.connect(_on_entrance_animation_finished)
	entrance_animation.play("entrance")

func _on_entrance_animation_finished():
	if entrance_animation_layer:
		entrance_animation_layer.queue_free()
	entrance_animation_layer = null
	entrance_animation = null

# Play the Eugenia awaken closeup exactly once, when the LOCAL Eugenia player
# exceeds. Only that player's client shows it.
func _play_awaken_entrance():
	if not GlobalSettings.AnimationsEnabled:
		return
	if awaken_animation:
		return
	var frame_count = 0
	var frame_base = ""
	var fps = 10.0
	# Zsolt and Geoffrey awaken closeups align to the bottom-right corner;
	# Eugenia stays centered.
	var is_bottom_right = false
	if _is_local_player_eugenia():
		frame_count = EugeniaAwakenFrameCount
		frame_base = EugeniaAwakenFrameBase
		fps = EugeniaAwakenFps
	elif _is_local_player_zsolt():
		frame_count = ZsoltAwakenFrameCount
		frame_base = ZsoltAwakenFrameBase
		fps = ZsoltAwakenFps
		is_bottom_right = true
	elif _is_local_player_geoffrey():
		frame_count = GeoffreyAwakenFrameCount
		frame_base = GeoffreyAwakenFrameBase
		fps = GeoffreyAwakenFps
		is_bottom_right = true
	elif _is_local_player_iaquis():
		frame_count = IaquisAwakenFrameCount
		frame_base = IaquisAwakenFrameBase
		fps = IaquisAwakenFps
		is_bottom_right = true
	else:
		return
	var sf := SpriteFrames.new()
	sf.add_animation("awaken")
	sf.set_animation_loop("awaken", false)
	sf.set_animation_speed("awaken", fps)
	for i in range(frame_count):
		var tex = load(frame_base % i)
		if tex:
			sf.add_frame("awaken", tex)
	if sf.get_frame_count("awaken") == 0:
		return
	awaken_animation_layer = CanvasLayer.new()
	awaken_animation_layer.layer = 100
	add_child(awaken_animation_layer)
	awaken_animation = AnimatedSprite2D.new()
	awaken_animation.sprite_frames = sf
	var frame_size = sf.get_frame_texture("awaken", 0).get_size()
	var scale_factor = 1.0
	if frame_size.x > 0.0 and frame_size.y > 0.0:
		scale_factor = min(EntranceScreenWidth / frame_size.x, EntranceScreenHeight / frame_size.y) * 0.98
		awaken_animation.scale = Vector2(scale_factor, scale_factor)
	if is_bottom_right:
		# Zsolt awaken closeup aligns to the bottom-right corner.
		awaken_animation.position = Vector2(
			EntranceScreenWidth - frame_size.x * scale_factor * 0.5,
			EntranceScreenHeight - frame_size.y * scale_factor * 0.5
		)
	else:
		awaken_animation.position = Vector2(EntranceScreenWidth * 0.5, EntranceScreenHeight * 0.5)
	awaken_animation_layer.add_child(awaken_animation)
	awaken_animation.animation_finished.connect(_on_awaken_animation_finished)
	awaken_animation.play("awaken")

func _on_awaken_animation_finished():
	if awaken_animation_layer:
		awaken_animation_layer.queue_free()
	awaken_animation_layer = null
	awaken_animation = null

# Play the Eugenia Cat's Cradle hit closeup exactly once when a Cat's Cradle
# attack lands (its hit effect makes the opponent discard, so we trigger off
# that discard event while the card is still the active strike). Both clients
# replay the same events, so both sides see it.
#
# is_local=true means the local player is the Cradle attacker -> play the
# right-side frames (attacker's perspective). is_local=false means the
# opponent is the attacker -> play the left-side frames (defender's
# perspective). When both players attack with Cradle in the same strike,
# both sides fire and play side by side on each client.
func _play_cats_cradle_entrance(is_local : bool):
	if not GlobalSettings.AnimationsEnabled:
		return
	var frame_base : String
	if is_local:
		if cats_cradle_animation_right:
			return
		frame_base = EugeniaCatsCradleRightFrameBase
	else:
		if cats_cradle_animation_left:
			return
		frame_base = EugeniaCatsCradleLeftFrameBase
	var sf := SpriteFrames.new()
	sf.add_animation("cats_cradle")
	sf.set_animation_loop("cats_cradle", false)
	sf.set_animation_speed("cats_cradle", EugeniaCatsCradleFps)
	for i in range(EugeniaCatsCradleFrameCount):
		var tex = load(frame_base % i)
		if tex:
			sf.add_frame("cats_cradle", tex)
	if sf.get_frame_count("cats_cradle") == 0:
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = sf
	var frame_size = sf.get_frame_texture("cats_cradle", 0).get_size()
	if frame_size.x > 0.0 and frame_size.y > 0.0:
		var scale_factor = min(EntranceScreenWidth / frame_size.x, EntranceScreenHeight / frame_size.y) * 0.98
		sprite.scale = Vector2(scale_factor, scale_factor)
		# Corner alignment: the LOCAL player's ultra effect closeup hugs the
		# TOP-RIGHT corner, the opponent's version hugs the TOP-LEFT corner.
		var displayed_size = frame_size * scale_factor
		if is_local:
			sprite.position = Vector2(EntranceScreenWidth - displayed_size.x * 0.5, displayed_size.y * 0.5)
		else:
			sprite.position = Vector2(displayed_size.x * 0.5, displayed_size.y * 0.5)
	layer.add_child(sprite)
	sprite.animation_finished.connect(_on_cats_cradle_animation_finished.bind(is_local))
	sprite.play("cats_cradle")
	if is_local:
		cats_cradle_animation_right = sprite
		cats_cradle_animation_layer_right = layer
	else:
		cats_cradle_animation_left = sprite
		cats_cradle_animation_layer_left = layer

func _on_cats_cradle_animation_finished(is_local : bool):
	if is_local:
		if cats_cradle_animation_layer_right:
			cats_cradle_animation_layer_right.queue_free()
		cats_cradle_animation_layer_right = null
		cats_cradle_animation_right = null
	else:
		if cats_cradle_animation_layer_left:
			cats_cradle_animation_layer_left.queue_free()
		cats_cradle_animation_layer_left = null
		cats_cradle_animation_left = null

# True if a Cat's Cradle card is the active strike and belongs to the local
# player (is_local=true) or to the opponent (is_local=false).
# True if the given card (activated in the current strike) is a Cat's Cradle
# belonging to the local player (is_local=true) or to the opponent
# (is_local=false). Triggered from Strike_CardActivation, i.e. after the
# ultra's gauge cost was paid - a pure battle-flow timing, unrelated to the
# card's hit effects.
func _is_cats_cradle_strike_attacking(is_local : bool, card_id : int) -> bool:
	if game_wrapper == null or game_wrapper.current_game == null:
		return false
	var logic_card = game_wrapper.get_card_database().get_card(card_id)
	if logic_card == null or logic_card.definition.get("id", "") != "eugenia_cats_cradle":
		return false
	var belongs_to_local = game_wrapper.does_card_belong_to_player(Enums.PlayerId.PlayerId_Player, card_id)
	return belongs_to_local == is_local

# Play the Eugenia Queen of Hearts hit closeup exactly once when a Queen of
# Hearts attack lands (its hit effect makes the opponent discard their hand, so
# we trigger off that discard event while the card is still the active strike).
# Both clients replay the same event stream, so both sides see it.
#
# is_local=true means the local player is the Queen of Hearts attacker ->
# play the right-side frames (attacker's perspective). is_local=false means
# the opponent is the attacker -> play the left-side frames (defender's
# perspective). When both players attack with Queen of Hearts in the same
# strike, both sides fire and play side by side on each client.
func _play_qoh_entrance(is_local : bool):
	if not GlobalSettings.AnimationsEnabled:
		return
	var frame_base : String
	if is_local:
		if qoh_animation_right:
			return
		frame_base = EugeniaQohRightFrameBase
	else:
		if qoh_animation_left:
			return
		frame_base = EugeniaQohLeftFrameBase
	var sf := SpriteFrames.new()
	sf.add_animation("qoh")
	sf.set_animation_loop("qoh", false)
	sf.set_animation_speed("qoh", EugeniaQohFps)
	for i in range(EugeniaQohFrameCount):
		var tex = load(frame_base % i)
		if tex:
			sf.add_frame("qoh", tex)
	if sf.get_frame_count("qoh") == 0:
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = sf
	var frame_size = sf.get_frame_texture("qoh", 0).get_size()
	if frame_size.x > 0.0 and frame_size.y > 0.0:
		var scale_factor = min(EntranceScreenWidth / frame_size.x, EntranceScreenHeight / frame_size.y) * 0.98
		sprite.scale = Vector2(scale_factor, scale_factor)
		# Corner alignment: the LOCAL player's ultra effect closeup hugs the
		# TOP-RIGHT corner, the opponent's version hugs the TOP-LEFT corner.
		var displayed_size = frame_size * scale_factor
		if is_local:
			sprite.position = Vector2(EntranceScreenWidth - displayed_size.x * 0.5, displayed_size.y * 0.5)
		else:
			sprite.position = Vector2(displayed_size.x * 0.5, displayed_size.y * 0.5)
	layer.add_child(sprite)
	sprite.animation_finished.connect(_on_qoh_animation_finished.bind(is_local))
	sprite.play("qoh")
	if is_local:
		qoh_animation_right = sprite
		qoh_animation_layer_right = layer
	else:
		qoh_animation_left = sprite
		qoh_animation_layer_left = layer

func _on_qoh_animation_finished(is_local : bool):
	if is_local:
		if qoh_animation_layer_right:
			qoh_animation_layer_right.queue_free()
		qoh_animation_layer_right = null
		qoh_animation_right = null
	else:
		if qoh_animation_layer_left:
			qoh_animation_layer_left.queue_free()
		qoh_animation_layer_left = null
		qoh_animation_left = null

# True if a Queen of Hearts card is the active strike and belongs to the local
# player (is_local=true) or to the opponent (is_local=false).
# True if the given card (activated in the current strike) is a Queen of
# Hearts belonging to the local player (is_local=true) or to the opponent
# (is_local=false). Triggered from Strike_CardActivation (after the ultra's
# gauge cost was paid) - a pure battle-flow timing, unrelated to hit effects.
func _is_qoh_strike_attacking(is_local : bool, card_id : int) -> bool:
	if game_wrapper == null or game_wrapper.current_game == null:
		return false
	var logic_card = game_wrapper.get_card_database().get_card(card_id)
	if logic_card == null or logic_card.definition.get("id", "") != "eugenia_queen_of_hearts":
		return false
	var belongs_to_local = game_wrapper.does_card_belong_to_player(Enums.PlayerId.PlayerId_Player, card_id)
	return belongs_to_local == is_local

# Play the Eugenia Queen of Hearts damage-resolve effect exactly once, when the
# damage from a Queen of Hearts strike is resolved (after all hit effects).
# The struck player is whoever is NOT the Queen of Hearts' owner. Both clients
# replay the same event stream, so both sides see it at the same time.
func _play_qoh_damage_effect():
	if not GlobalSettings.AnimationsEnabled:
		return
	if qoh_damage_animation:
		return
	var sf := SpriteFrames.new()
	sf.add_animation("qoh_damage")
	sf.set_animation_loop("qoh_damage", false)
	sf.set_animation_speed("qoh_damage", EugeniaQohDamageFps)
	for i in range(EugeniaQohDamageFrameCount):
		var tex = load(EugeniaQohDamageFrameBase % i)
		if tex:
			sf.add_frame("qoh_damage", tex)
	if sf.get_frame_count("qoh_damage") == 0:
		return
	qoh_damage_animation_layer = CanvasLayer.new()
	qoh_damage_animation_layer.layer = 100
	add_child(qoh_damage_animation_layer)
	qoh_damage_animation = AnimatedSprite2D.new()
	qoh_damage_animation.sprite_frames = sf
	qoh_damage_animation.position = Vector2(EntranceScreenWidth * 0.5, EntranceScreenHeight * 0.5)
	var frame_size = sf.get_frame_texture("qoh_damage", 0).get_size()
	if frame_size.x > 0.0 and frame_size.y > 0.0:
		# Cover the whole screen (no letterboxing, edges overflow and get
		# cropped instead of leaving black bars).
		var scale_factor = max(EntranceScreenWidth / frame_size.x, EntranceScreenHeight / frame_size.y)
		qoh_damage_animation.scale = Vector2(scale_factor, scale_factor)
	qoh_damage_animation_layer.add_child(qoh_damage_animation)
	qoh_damage_animation.animation_finished.connect(_on_qoh_damage_effect_finished)
	qoh_damage_animation.play("qoh_damage")

func _on_qoh_damage_effect_finished():
	if qoh_damage_animation_layer:
		qoh_damage_animation_layer.queue_free()
	qoh_damage_animation_layer = null
	qoh_damage_animation = null

# Play the Eugenia Cat's Cradle hit closeup, full-screen damage-resolve
# effect exactly once, when the damage from a Cat's Cradle strike is resolved
# (after all hit effects). Like the QOH damage effect, both clients see it at
# the same time and at most once per strike.
func _play_cats_cradle_hit():
	if not GlobalSettings.AnimationsEnabled:
		return
	if cats_cradle_hit_animation:
		return
	var sf := SpriteFrames.new()
	sf.add_animation("cats_cradle_hit")
	sf.set_animation_loop("cats_cradle_hit", false)
	sf.set_animation_speed("cats_cradle_hit", EugeniaCatsCradleHitFps)
	for i in range(EugeniaCatsCradleHitFrameCount):
		var tex = load(EugeniaCatsCradleHitFrameBase % i)
		if tex:
			sf.add_frame("cats_cradle_hit", tex)
	if sf.get_frame_count("cats_cradle_hit") == 0:
		return
	cats_cradle_hit_animation_layer = CanvasLayer.new()
	cats_cradle_hit_animation_layer.layer = 100
	add_child(cats_cradle_hit_animation_layer)
	cats_cradle_hit_animation = AnimatedSprite2D.new()
	cats_cradle_hit_animation.sprite_frames = sf
	cats_cradle_hit_animation.position = Vector2(EntranceScreenWidth * 0.5, EntranceScreenHeight * 0.5)
	var frame_size = sf.get_frame_texture("cats_cradle_hit", 0).get_size()
	if frame_size.x > 0.0 and frame_size.y > 0.0:
		# Cover the whole screen (no letterboxing).
		var scale_factor = max(EntranceScreenWidth / frame_size.x, EntranceScreenHeight / frame_size.y)
		cats_cradle_hit_animation.scale = Vector2(scale_factor, scale_factor)
	cats_cradle_hit_animation_layer.add_child(cats_cradle_hit_animation)
	cats_cradle_hit_animation.animation_finished.connect(_on_cats_cradle_hit_animation_finished)
	cats_cradle_hit_animation.play("cats_cradle_hit")

func _on_cats_cradle_hit_animation_finished():
	if cats_cradle_hit_animation_layer:
		cats_cradle_hit_animation_layer.queue_free()
	cats_cradle_hit_animation_layer = null
	cats_cradle_hit_animation = null

# Play the Time for Tea (Plot Hook -> Time for Tea) action closeup once.
# Triggered from _on_discard_event when the opponent discards a card as the
# overall_effect of the force_for_effect that _on_force_for_effect flagged.
func _play_tea_time_entrance():
	if not GlobalSettings.AnimationsEnabled:
		return
	if tea_time_animation:
		return
	var sf := SpriteFrames.new()
	sf.add_animation("tea_time")
	sf.set_animation_loop("tea_time", false)
	sf.set_animation_speed("tea_time", EugeniaTeaTimeFps)
	for i in range(EugeniaTeaTimeFrameCount):
		var tex = load(EugeniaTeaTimeFrameBase % i)
		if tex:
			sf.add_frame("tea_time", tex)
	if sf.get_frame_count("tea_time") == 0:
		return
	tea_time_animation_layer = CanvasLayer.new()
	tea_time_animation_layer.layer = 100
	add_child(tea_time_animation_layer)
	tea_time_animation = AnimatedSprite2D.new()
	tea_time_animation.sprite_frames = sf
	var frame_size = sf.get_frame_texture("tea_time", 0).get_size()
	var scale_factor = 1.0
	if frame_size.x > 0.0 and frame_size.y > 0.0:
		scale_factor = min(EntranceScreenWidth / frame_size.x, EntranceScreenHeight / frame_size.y) * 0.98
		tea_time_animation.scale = Vector2(scale_factor, scale_factor)
	# Align the tea time closeup to the bottom-left corner of the screen.
	tea_time_animation.position = Vector2(
		frame_size.x * scale_factor * 0.5,
		EntranceScreenHeight - frame_size.y * scale_factor * 0.5
	)
	tea_time_animation_layer.add_child(tea_time_animation)
	tea_time_animation.animation_finished.connect(_on_tea_time_animation_finished)
	tea_time_animation.play("tea_time")

func _on_tea_time_animation_finished():
	if tea_time_animation_layer:
		tea_time_animation_layer.queue_free()
	tea_time_animation_layer = null
	tea_time_animation = null

# Play the Zsolt Fatal Eye effect closeup exactly once per strike, when a
# Fatal Eye attack card activates (takes effect, after any costs are paid).
# Both clients replay the same event stream, so both sides see it. Aligns to
# the bottom-left corner of the screen.
func _play_zsolt_fatal_eye():
	if not GlobalSettings.AnimationsEnabled:
		return
	if fatal_eye_animation:
		return
	var sf := SpriteFrames.new()
	sf.add_animation("fatal_eye")
	sf.set_animation_loop("fatal_eye", false)
	sf.set_animation_speed("fatal_eye", ZsoltFatalEyeFps)
	for i in range(ZsoltFatalEyeFrameCount):
		var tex = load(ZsoltFatalEyeFrameBase % i)
		if tex:
			sf.add_frame("fatal_eye", tex)
	if sf.get_frame_count("fatal_eye") == 0:
		return
	fatal_eye_animation_layer = CanvasLayer.new()
	fatal_eye_animation_layer.layer = 100
	add_child(fatal_eye_animation_layer)
	fatal_eye_animation = AnimatedSprite2D.new()
	fatal_eye_animation.sprite_frames = sf
	var frame_size = sf.get_frame_texture("fatal_eye", 0).get_size()
	var scale_factor = 1.0
	if frame_size.x > 0.0 and frame_size.y > 0.0:
		scale_factor = min(EntranceScreenWidth / frame_size.x, EntranceScreenHeight / frame_size.y) * 0.98
		fatal_eye_animation.scale = Vector2(scale_factor, scale_factor)
	# Align the Fatal Eye closeup to the bottom-left corner of the screen.
	fatal_eye_animation.position = Vector2(
		frame_size.x * scale_factor * 0.5,
		EntranceScreenHeight - frame_size.y * scale_factor * 0.5
	)
	fatal_eye_animation_layer.add_child(fatal_eye_animation)
	fatal_eye_animation.animation_finished.connect(_on_zsolt_fatal_eye_animation_finished)
	fatal_eye_animation.play("fatal_eye")

func _on_zsolt_fatal_eye_animation_finished():
	if fatal_eye_animation_layer:
		fatal_eye_animation_layer.queue_free()
	fatal_eye_animation_layer = null
	fatal_eye_animation = null

# True if the activating card is Zsolt's Fatal Eye (either player's).
func _is_zsolt_fatal_eye_activating(card_id : int) -> bool:
	if game_wrapper == null or game_wrapper.current_game == null:
		return false
	var logic_card = game_wrapper.get_card_database().get_card(card_id)
	return logic_card != null and logic_card.definition.get("id", "") == "zsolt_deathglare"

# Play the Zsolt Wild Hunt hit closeup exactly once per side per strike, when
# a Wild Hunt attack takes effect (card activation). Per-side like
# _play_cats_cradle_entrance: the local attacker's client plays the right
# frames (top-right corner), the defender's client plays the left frames
# (top-left corner). Gated to the MAIN attack card so Zsolt's chain extra
# attacks don't fire the closeup.
#
# is_local=true means the local player is the Wild Hunt attacker; is_local=false
# means the opponent is the attacker.
func _play_zsolt_wild_hunt_entrance(is_local : bool):
	if not GlobalSettings.AnimationsEnabled:
		return
	# Only the MAIN attack card of the strike gets the closeup: chain extra
	# attacks must not re-fire it. Tracked via the event stream (not the
	# engine) because events are replayed asynchronously.
	if strike_is_extra_attack:
		return
	var frame_base : String
	if is_local:
		if wild_hunt_animation_right:
			return
		frame_base = ZsoltWildHuntRightFrameBase
	else:
		if wild_hunt_animation_left:
			return
		frame_base = ZsoltWildHuntLeftFrameBase
	var sf := SpriteFrames.new()
	sf.add_animation("wild_hunt")
	sf.set_animation_loop("wild_hunt", false)
	sf.set_animation_speed("wild_hunt", ZsoltWildHuntFps)
	for i in range(ZsoltWildHuntFrameCount):
		var tex = load(frame_base % i)
		if tex:
			sf.add_frame("wild_hunt", tex)
	if sf.get_frame_count("wild_hunt") == 0:
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = sf
	var frame_size = sf.get_frame_texture("wild_hunt", 0).get_size()
	var scale_factor = 1.0
	if frame_size.x > 0.0 and frame_size.y > 0.0:
		scale_factor = min(EntranceScreenWidth / frame_size.x, EntranceScreenHeight / frame_size.y) * 0.98
		sprite.scale = Vector2(scale_factor, scale_factor)
	# Top corner alignment: right frames -> top-right, left frames -> top-left.
	var displayed_size = frame_size * scale_factor
	if is_local:
		sprite.position = Vector2(EntranceScreenWidth - displayed_size.x * 0.5, displayed_size.y * 0.5)
		wild_hunt_animation_right = sprite
		wild_hunt_animation_layer_right = layer
	else:
		sprite.position = Vector2(displayed_size.x * 0.5, displayed_size.y * 0.5)
		wild_hunt_animation_left = sprite
		wild_hunt_animation_layer_left = layer
	layer.add_child(sprite)
	sprite.animation_finished.connect(_on_zsolt_wild_hunt_animation_finished.bind(is_local))
	sprite.play("wild_hunt")

func _on_zsolt_wild_hunt_animation_finished(is_local : bool):
	if is_local:
		if wild_hunt_animation_layer_right:
			wild_hunt_animation_layer_right.queue_free()
		wild_hunt_animation_layer_right = null
		wild_hunt_animation_right = null
	else:
		if wild_hunt_animation_layer_left:
			wild_hunt_animation_layer_left.queue_free()
		wild_hunt_animation_layer_left = null
		wild_hunt_animation_left = null

# True if the given card is Zsolt's Wild Hunt (either player's).
func _is_zsolt_wild_hunt(card_id : int) -> bool:
	if game_wrapper == null or game_wrapper.current_game == null:
		return false
	var logic_card = game_wrapper.get_card_database().get_card(card_id)
	return logic_card != null and logic_card.definition.get("id", "") == "zsolt_madhunt"

# True if the damaging card is Zsolt's Wild Hunt being played by the given
# player. Same pattern as _is_cats_cradle_strike_dealing_damage_to: the damage
# effect fires when the Wild Hunt attacker deals damage to the opponent.
func _is_zsolt_wild_hunt_dealing_damage_to(player) -> bool:
	if game_wrapper == null or game_wrapper.current_game == null:
		return false
	for card_id in strike_attack_card_ids:
		var logic_card = game_wrapper.get_card_database().get_card(card_id)
		if card_id in strike_activated_card_ids and logic_card != null and logic_card.definition.get("id", "") == "zsolt_madhunt":
			var wild_hunt_is_players = game_wrapper.does_card_belong_to_player(Enums.PlayerId.PlayerId_Player, card_id)
			if wild_hunt_is_players and player == Enums.PlayerId.PlayerId_Opponent:
				return true
			if not wild_hunt_is_players and player == Enums.PlayerId.PlayerId_Player:
				return true
	return false

# Play the Zsolt Wild Hunt damage-resolve effect (full-screen), once per strike,
# when Wild Hunt damage is actually resolved. Gated to the MAIN attack card
# so chain extra attacks don't re-fire it.
func _play_zsolt_wild_hunt_damage():
	if not GlobalSettings.AnimationsEnabled:
		return
	# Only the MAIN attack card's damage plays the full-screen effect.
	if strike_is_extra_attack:
		return
	if wild_hunt_damage_animation:
		return
	var sf := SpriteFrames.new()
	sf.add_animation("wild_hunt_damage")
	sf.set_animation_loop("wild_hunt_damage", false)
	sf.set_animation_speed("wild_hunt_damage", ZsoltWildHuntDamageFps)
	for i in range(ZsoltWildHuntDamageFrameCount):
		var tex = load(ZsoltWildHuntDamageFrameBase % i)
		if tex:
			sf.add_frame("wild_hunt_damage", tex)
	if sf.get_frame_count("wild_hunt_damage") == 0:
		return
	wild_hunt_damage_animation_layer = CanvasLayer.new()
	wild_hunt_damage_animation_layer.layer = 100
	add_child(wild_hunt_damage_animation_layer)
	wild_hunt_damage_animation = AnimatedSprite2D.new()
	wild_hunt_damage_animation.sprite_frames = sf
	wild_hunt_damage_animation.position = Vector2(EntranceScreenWidth * 0.5, EntranceScreenHeight * 0.5)
	var frame_size = sf.get_frame_texture("wild_hunt_damage", 0).get_size()
	if frame_size.x > 0.0 and frame_size.y > 0.0:
		# Cover the whole screen (no letterboxing).
		var scale_factor = max(EntranceScreenWidth / frame_size.x, EntranceScreenHeight / frame_size.y)
		wild_hunt_damage_animation.scale = Vector2(scale_factor, scale_factor)
	wild_hunt_damage_animation_layer.add_child(wild_hunt_damage_animation)
	wild_hunt_damage_animation.animation_finished.connect(_on_zsolt_wild_hunt_damage_finished)
	wild_hunt_damage_animation.play("wild_hunt_damage")

func _on_zsolt_wild_hunt_damage_finished():
	if wild_hunt_damage_animation_layer:
		wild_hunt_damage_animation_layer.queue_free()
	wild_hunt_damage_animation_layer = null
	wild_hunt_damage_animation = null

# Play the Zsolt Fanatical Purification hit closeup exactly once per side per
# strike, when a Fanatical Purification attack takes effect (card activation).
# Per-side like Wild Hunt: local attacker -> right frames (top-right corner),
# opponent defender -> left frames (top-left corner). Gated to the MAIN attack
# card so chain extra attacks don't fire the closeup.
#
# is_local=true means the local player is the Purification attacker.
func _play_zsolt_purification_entrance(is_local : bool):
	if not GlobalSettings.AnimationsEnabled:
		return
	# Only the MAIN attack card of the strike gets the closeup.
	if strike_is_extra_attack:
		return
	var frame_base : String
	if is_local:
		if purification_animation_right:
			return
		frame_base = ZsoltPurificationRightFrameBase
	else:
		if purification_animation_left:
			return
		frame_base = ZsoltPurificationLeftFrameBase
	var sf := SpriteFrames.new()
	sf.add_animation("purification")
	sf.set_animation_loop("purification", false)
	sf.set_animation_speed("purification", ZsoltPurificationFps)
	for i in range(ZsoltPurificationFrameCount):
		var tex = load(frame_base % i)
		if tex:
			sf.add_frame("purification", tex)
	if sf.get_frame_count("purification") == 0:
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = sf
	var frame_size = sf.get_frame_texture("purification", 0).get_size()
	var scale_factor = 1.0
	if frame_size.x > 0.0 and frame_size.y > 0.0:
		scale_factor = min(EntranceScreenWidth / frame_size.x, EntranceScreenHeight / frame_size.y) * 0.98
		sprite.scale = Vector2(scale_factor, scale_factor)
	# Top corner alignment: right frames -> top-right, left frames -> top-left.
	var displayed_size = frame_size * scale_factor
	if is_local:
		sprite.position = Vector2(EntranceScreenWidth - displayed_size.x * 0.5, displayed_size.y * 0.5)
		purification_animation_right = sprite
		purification_animation_layer_right = layer
	else:
		sprite.position = Vector2(displayed_size.x * 0.5, displayed_size.y * 0.5)
		purification_animation_left = sprite
		purification_animation_layer_left = layer
	layer.add_child(sprite)
	sprite.animation_finished.connect(_on_zsolt_purification_animation_finished.bind(is_local))
	sprite.play("purification")

func _on_zsolt_purification_animation_finished(is_local : bool):
	if is_local:
		if purification_animation_layer_right:
			purification_animation_layer_right.queue_free()
		purification_animation_layer_right = null
		purification_animation_right = null
	else:
		if purification_animation_layer_left:
			purification_animation_layer_left.queue_free()
		purification_animation_layer_left = null
		purification_animation_left = null

# True if the given card is Zsolt's Fanatical Purification (either player's).
func _is_zsolt_purification(card_id : int) -> bool:
	if game_wrapper == null or game_wrapper.current_game == null:
		return false
	var logic_card = game_wrapper.get_card_database().get_card(card_id)
	return logic_card != null and logic_card.definition.get("id", "") == "zsolt_purifyingsword"

# True if the damaging card is Zsolt's Fanatical Purification being played by
# the given player (same pattern as Wild Hunt / cats_cradle).
func _is_zsolt_purification_dealing_damage_to(player) -> bool:
	if game_wrapper == null or game_wrapper.current_game == null:
		return false
	for card_id in strike_attack_card_ids:
		var logic_card = game_wrapper.get_card_database().get_card(card_id)
		if card_id in strike_activated_card_ids and logic_card != null and logic_card.definition.get("id", "") == "zsolt_purifyingsword":
			var purif_is_players = game_wrapper.does_card_belong_to_player(Enums.PlayerId.PlayerId_Player, card_id)
			if purif_is_players and player == Enums.PlayerId.PlayerId_Opponent:
				return true
			if not purif_is_players and player == Enums.PlayerId.PlayerId_Player:
				return true
	return false

# Play the Zsolt Fanatical Purification damage-resolve effect (full-screen),
# once per strike, when Purification damage is resolved. Gated to the MAIN
# attack card so chain extra attacks don't re-fire it.
func _play_zsolt_purification_damage():
	if not GlobalSettings.AnimationsEnabled:
		return
	# Only the MAIN attack card's damage plays the full-screen effect.
	if strike_is_extra_attack:
		return
	if purification_damage_animation:
		return
	var sf := SpriteFrames.new()
	sf.add_animation("purification_damage")
	sf.set_animation_loop("purification_damage", false)
	sf.set_animation_speed("purification_damage", ZsoltPurificationDamageFps)
	for i in range(ZsoltPurificationDamageFrameCount):
		var tex = load(ZsoltPurificationDamageFrameBase % i)
		if tex:
			sf.add_frame("purification_damage", tex)
	if sf.get_frame_count("purification_damage") == 0:
		return
	purification_damage_animation_layer = CanvasLayer.new()
	purification_damage_animation_layer.layer = 100
	add_child(purification_damage_animation_layer)
	purification_damage_animation = AnimatedSprite2D.new()
	purification_damage_animation.sprite_frames = sf
	purification_damage_animation.position = Vector2(EntranceScreenWidth * 0.5, EntranceScreenHeight * 0.5)
	var frame_size = sf.get_frame_texture("purification_damage", 0).get_size()
	if frame_size.x > 0.0 and frame_size.y > 0.0:
		# Cover the whole screen (no letterboxing).
		var scale_factor = max(EntranceScreenWidth / frame_size.x, EntranceScreenHeight / frame_size.y)
		purification_damage_animation.scale = Vector2(scale_factor, scale_factor)
	purification_damage_animation_layer.add_child(purification_damage_animation)
	purification_damage_animation.animation_finished.connect(_on_zsolt_purification_damage_finished)
	purification_damage_animation.play("purification_damage")

func _on_zsolt_purification_damage_finished():
	if purification_damage_animation_layer:
		purification_damage_animation_layer.queue_free()
	purification_damage_animation_layer = null
	purification_damage_animation = null

# True if the given card is Geoffrey's Inviolable Judgment (either player's).
func _is_geoffrey_judgment(card_id : int) -> bool:
	if game_wrapper == null or game_wrapper.current_game == null:
		return false
	var logic_card = game_wrapper.get_card_database().get_card(card_id)
	return logic_card != null and logic_card.definition.get("id", "") == "geoffrey_inviolablejudgment"

# True if the damaging card is Geoffrey's Inviolable Judgment being played by
# the given player (same pattern as Wild Hunt / Purification).
func _is_geoffrey_judgment_dealing_damage_to(player) -> bool:
	if game_wrapper == null or game_wrapper.current_game == null:
		return false
	for card_id in strike_attack_card_ids:
		var logic_card = game_wrapper.get_card_database().get_card(card_id)
		if card_id in strike_activated_card_ids and logic_card != null and logic_card.definition.get("id", "") == "geoffrey_inviolablejudgment":
			var judgment_is_players = game_wrapper.does_card_belong_to_player(Enums.PlayerId.PlayerId_Player, card_id)
			if judgment_is_players and player == Enums.PlayerId.PlayerId_Opponent:
				return true
			if not judgment_is_players and player == Enums.PlayerId.PlayerId_Player:
				return true
	return false

# Play the Geoffrey Inviolable Judgment hit closeup exactly once per side per
# strike, when a Judgment attack takes effect (card activation). Per-side like
# Wild Hunt: local attacker -> right frames (top-right corner), opponent
# defender -> left frames (top-left corner). Gated to the MAIN attack card so
# chain extra attacks don't fire the closeup.
#
# is_local=true means the local player is the Judgment attacker.
func _play_geoffrey_judgment_entrance(is_local : bool):
	if not GlobalSettings.AnimationsEnabled:
		return
	# Only the MAIN attack card of the strike gets the closeup.
	if strike_is_extra_attack:
		return
	var frame_base : String
	if is_local:
		if judgment_animation_right:
			return
		frame_base = GeoffreyJudgmentRightFrameBase
	else:
		if judgment_animation_left:
			return
		frame_base = GeoffreyJudgmentLeftFrameBase
	var sf := SpriteFrames.new()
	sf.add_animation("judgment")
	sf.set_animation_loop("judgment", false)
	sf.set_animation_speed("judgment", GeoffreyJudgmentFps)
	for i in range(GeoffreyJudgmentFrameCount):
		var tex = load(frame_base % i)
		if tex:
			sf.add_frame("judgment", tex)
	if sf.get_frame_count("judgment") == 0:
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = sf
	var frame_size = sf.get_frame_texture("judgment", 0).get_size()
	var scale_factor = 1.0
	if frame_size.x > 0.0 and frame_size.y > 0.0:
		scale_factor = min(EntranceScreenWidth / frame_size.x, EntranceScreenHeight / frame_size.y) * 0.98
		sprite.scale = Vector2(scale_factor, scale_factor)
	# Top corner alignment: right frames -> top-right, left frames -> top-left.
	var displayed_size = frame_size * scale_factor
	if is_local:
		sprite.position = Vector2(EntranceScreenWidth - displayed_size.x * 0.5, displayed_size.y * 0.5)
		judgment_animation_right = sprite
		judgment_animation_layer_right = layer
	else:
		sprite.position = Vector2(displayed_size.x * 0.5, displayed_size.y * 0.5)
		judgment_animation_left = sprite
		judgment_animation_layer_left = layer
	layer.add_child(sprite)
	sprite.animation_finished.connect(_on_geoffrey_judgment_animation_finished.bind(is_local))
	sprite.play("judgment")

func _on_geoffrey_judgment_animation_finished(is_local : bool):
	if is_local:
		if judgment_animation_layer_right:
			judgment_animation_layer_right.queue_free()
		judgment_animation_layer_right = null
		judgment_animation_right = null
	else:
		if judgment_animation_layer_left:
			judgment_animation_layer_left.queue_free()
		judgment_animation_layer_left = null
		judgment_animation_left = null

# Play the Geoffrey Inviolable Judgment damage-resolve effect (full-screen),
# once per strike, when Judgment damage is resolved. Gated to the MAIN attack
# card so chain extra attacks don't re-fire it.
func _play_geoffrey_judgment_damage():
	if not GlobalSettings.AnimationsEnabled:
		return
	# Only the MAIN attack card's damage plays the full-screen effect.
	if strike_is_extra_attack:
		return
	if judgment_damage_animation:
		return
	var sf := SpriteFrames.new()
	sf.add_animation("judgment_damage")
	sf.set_animation_loop("judgment_damage", false)
	sf.set_animation_speed("judgment_damage", GeoffreyJudgmentDamageFps)
	for i in range(GeoffreyJudgmentDamageFrameCount):
		var tex = load(GeoffreyJudgmentDamageFrameBase % i)
		if tex:
			sf.add_frame("judgment_damage", tex)
	if sf.get_frame_count("judgment_damage") == 0:
		return
	judgment_damage_animation_layer = CanvasLayer.new()
	judgment_damage_animation_layer.layer = 100
	add_child(judgment_damage_animation_layer)
	judgment_damage_animation = AnimatedSprite2D.new()
	judgment_damage_animation.sprite_frames = sf
	judgment_damage_animation.position = Vector2(EntranceScreenWidth * 0.5, EntranceScreenHeight * 0.5)
	var frame_size = sf.get_frame_texture("judgment_damage", 0).get_size()
	if frame_size.x > 0.0 and frame_size.y > 0.0:
		# Cover the whole screen (no letterboxing).
		var scale_factor = max(EntranceScreenWidth / frame_size.x, EntranceScreenHeight / frame_size.y)
		judgment_damage_animation.scale = Vector2(scale_factor, scale_factor)
	judgment_damage_animation_layer.add_child(judgment_damage_animation)
	judgment_damage_animation.animation_finished.connect(_on_geoffrey_judgment_damage_finished)
	judgment_damage_animation.play("judgment_damage")

func _on_geoffrey_judgment_damage_finished():
	if judgment_damage_animation_layer:
		judgment_damage_animation_layer.queue_free()
	judgment_damage_animation_layer = null
	judgment_damage_animation = null

# True if the given card is Geoffrey's Crusader's Oath (either player's).
func _is_geoffrey_crusader(card_id : int) -> bool:
	if game_wrapper == null or game_wrapper.current_game == null:
		return false
	var logic_card = game_wrapper.get_card_database().get_card(card_id)
	return logic_card != null and logic_card.definition.get("id", "") == "geoffrey_crusadersoath"

# True if the damaging card is Geoffrey's Crusader's Oath being played by the
# given player (same pattern as Wild Hunt / Purification).
func _is_geoffrey_crusader_dealing_damage_to(player) -> bool:
	if game_wrapper == null or game_wrapper.current_game == null:
		return false
	for card_id in strike_attack_card_ids:
		var logic_card = game_wrapper.get_card_database().get_card(card_id)
		if card_id in strike_activated_card_ids and logic_card != null and logic_card.definition.get("id", "") == "geoffrey_crusadersoath":
			var crusader_is_players = game_wrapper.does_card_belong_to_player(Enums.PlayerId.PlayerId_Player, card_id)
			if crusader_is_players and player == Enums.PlayerId.PlayerId_Opponent:
				return true
			if not crusader_is_players and player == Enums.PlayerId.PlayerId_Player:
				return true
	return false

# Play the Geoffrey Crusader's Oath hit closeup exactly once per side per
# strike, when a Crusader's Oath attack takes effect (card activation).
# Per-side like Wild Hunt. Gated to the MAIN attack card.
#
# is_local=true means the local player is the Crusader's Oath attacker.
func _play_geoffrey_crusader_entrance(is_local : bool):
	if not GlobalSettings.AnimationsEnabled:
		return
	# Only the MAIN attack card of the strike gets the closeup.
	if strike_is_extra_attack:
		return
	var frame_base : String
	if is_local:
		if crusader_animation_right:
			return
		frame_base = GeoffreyCrusaderRightFrameBase
	else:
		if crusader_animation_left:
			return
		frame_base = GeoffreyCrusaderLeftFrameBase
	var sf := SpriteFrames.new()
	sf.add_animation("crusader")
	sf.set_animation_loop("crusader", false)
	sf.set_animation_speed("crusader", GeoffreyCrusaderFps)
	for i in range(GeoffreyCrusaderFrameCount):
		var tex = load(frame_base % i)
		if tex:
			sf.add_frame("crusader", tex)
	if sf.get_frame_count("crusader") == 0:
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = sf
	var frame_size = sf.get_frame_texture("crusader", 0).get_size()
	var scale_factor = 1.0
	if frame_size.x > 0.0 and frame_size.y > 0.0:
		scale_factor = min(EntranceScreenWidth / frame_size.x, EntranceScreenHeight / frame_size.y) * 0.98
		sprite.scale = Vector2(scale_factor, scale_factor)
	# Top corner alignment: right frames -> top-right, left frames -> top-left.
	var displayed_size = frame_size * scale_factor
	if is_local:
		sprite.position = Vector2(EntranceScreenWidth - displayed_size.x * 0.5, displayed_size.y * 0.5)
		crusader_animation_right = sprite
		crusader_animation_layer_right = layer
	else:
		sprite.position = Vector2(displayed_size.x * 0.5, displayed_size.y * 0.5)
		crusader_animation_left = sprite
		crusader_animation_layer_left = layer
	layer.add_child(sprite)
	sprite.animation_finished.connect(_on_geoffrey_crusader_animation_finished.bind(is_local))
	sprite.play("crusader")

func _on_geoffrey_crusader_animation_finished(is_local : bool):
	if is_local:
		if crusader_animation_layer_right:
			crusader_animation_layer_right.queue_free()
		crusader_animation_layer_right = null
		crusader_animation_right = null
	else:
		if crusader_animation_layer_left:
			crusader_animation_layer_left.queue_free()
		crusader_animation_layer_left = null
		crusader_animation_left = null

# Play the Geoffrey Crusader's Oath damage-resolve effect (full-screen), once
# per strike, when Crusader's Oath damage is resolved. Gated to the MAIN
# attack card so chain extra attacks don't re-fire it.
func _play_geoffrey_crusader_damage():
	if not GlobalSettings.AnimationsEnabled:
		return
	# Only the MAIN attack card's damage plays the full-screen effect.
	if strike_is_extra_attack:
		return
	if crusader_damage_animation:
		return
	var sf := SpriteFrames.new()
	sf.add_animation("crusader_damage")
	sf.set_animation_loop("crusader_damage", false)
	sf.set_animation_speed("crusader_damage", GeoffreyCrusaderDamageFps)
	for i in range(GeoffreyCrusaderDamageFrameCount):
		var tex = load(GeoffreyCrusaderDamageFrameBase % i)
		if tex:
			sf.add_frame("crusader_damage", tex)
	if sf.get_frame_count("crusader_damage") == 0:
		return
	crusader_damage_animation_layer = CanvasLayer.new()
	crusader_damage_animation_layer.layer = 100
	add_child(crusader_damage_animation_layer)
	crusader_damage_animation = AnimatedSprite2D.new()
	crusader_damage_animation.sprite_frames = sf
	crusader_damage_animation.position = Vector2(EntranceScreenWidth * 0.5, EntranceScreenHeight * 0.5)
	var frame_size = sf.get_frame_texture("crusader_damage", 0).get_size()
	if frame_size.x > 0.0 and frame_size.y > 0.0:
		# Cover the whole screen (no letterboxing).
		var scale_factor = max(EntranceScreenWidth / frame_size.x, EntranceScreenHeight / frame_size.y)
		crusader_damage_animation.scale = Vector2(scale_factor, scale_factor)
	crusader_damage_animation_layer.add_child(crusader_damage_animation)
	crusader_damage_animation.animation_finished.connect(_on_geoffrey_crusader_damage_finished)
	crusader_damage_animation.play("crusader_damage")

func _on_geoffrey_crusader_damage_finished():
	if crusader_damage_animation_layer:
		crusader_damage_animation_layer.queue_free()
	crusader_damage_animation_layer = null
	crusader_damage_animation = null

# True if the current decision is Geoffrey's Compulsive Purification
# (inquisition transform) force_for_effect: a ForceForEffect decision whose
# overall_effect is negate_boost (unique to geoffrey_inquisition).
func _is_geoffrey_inquisition_force_for_effect() -> bool:
	if game_wrapper == null or game_wrapper.current_game == null:
		return false
	var decision_info = game_wrapper.get_decision_info()
	if decision_info == null or decision_info.type != Enums.DecisionType.DecisionType_ForceForEffect:
		return false
	var effect = decision_info.effect
	if effect == null:
		return false
	var overall_effect = effect.get("overall_effect", null)
	return overall_effect != null and overall_effect.get("effect_type", "") == "negate_boost"

# Play the Geoffrey Compulsive Purification closeup (bottom-left corner).
# Both clients play it when the engine confirms the force_for_effect payment
# (EventType_ForceForEffectConfirmed with negate_boost=true). bonus_roll: pass
# the bonus flag from the event (-1.0 = roll locally, e.g. in tests) so both
# clients agree on the 20% easter-egg variant.
func _play_geoffrey_purification(bonus_roll : float = -1.0):
	if not GlobalSettings.AnimationsEnabled:
		return
	if geoffrey_purification_animation:
		return
	var use_bonus = false
	if bonus_roll >= 0.0:
		use_bonus = bonus_roll >= 1.0
	else:
		use_bonus = randf() < GeoffreyPurificationBonusChance
	var frame_base = GeoffreyPurificationFrameBase
	if use_bonus:
		frame_base = GeoffreyPurificationBonusFrameBase
	var sf := SpriteFrames.new()
	sf.add_animation("geoffrey_purification")
	sf.set_animation_loop("geoffrey_purification", false)
	sf.set_animation_speed("geoffrey_purification", GeoffreyPurificationFps)
	for i in range(GeoffreyPurificationFrameCount):
		var tex = load(frame_base % i)
		if tex:
			sf.add_frame("geoffrey_purification", tex)
	if sf.get_frame_count("geoffrey_purification") == 0:
		return
	geoffrey_purification_animation_layer = CanvasLayer.new()
	geoffrey_purification_animation_layer.layer = 100
	add_child(geoffrey_purification_animation_layer)
	geoffrey_purification_animation = AnimatedSprite2D.new()
	geoffrey_purification_animation.sprite_frames = sf
	var frame_size = sf.get_frame_texture("geoffrey_purification", 0).get_size()
	var scale_factor = 1.0
	if frame_size.x > 0.0 and frame_size.y > 0.0:
		scale_factor = min(EntranceScreenWidth / frame_size.x, EntranceScreenHeight / frame_size.y) * 0.98
		geoffrey_purification_animation.scale = Vector2(scale_factor, scale_factor)
	# Bottom-left corner alignment (same as Fatal Eye / tea time).
	geoffrey_purification_animation.position = Vector2(
		frame_size.x * scale_factor * 0.5,
		EntranceScreenHeight - frame_size.y * scale_factor * 0.5
	)
	geoffrey_purification_animation_layer.add_child(geoffrey_purification_animation)
	geoffrey_purification_animation.animation_finished.connect(_on_geoffrey_purification_animation_finished)
	geoffrey_purification_animation.play("geoffrey_purification")

func _on_geoffrey_purification_animation_finished():
	if geoffrey_purification_animation_layer:
		geoffrey_purification_animation_layer.queue_free()
	geoffrey_purification_animation_layer = null
	geoffrey_purification_animation = null

# Engine confirmed a force_for_effect payment (both clients receive this).
# Geoffrey Compulsive Purification plays the closeup here: bottom-left, both
# clients see it, easter-egg variant decided by the engine roll (synced).
func _on_force_for_effect_confirmed(event):
	var extra = event.get("extra_info", null)
	if extra == null or not extra.get("negate_boost", false):
		return
	var bonus_roll = 1.0 if extra.get("bonus", false) else 0.0
	_play_geoffrey_purification(bonus_roll)

# True if the given card is Iaquis's Dragon's Heart (either player's).
func _is_iaquis_heart(card_id : int) -> bool:
	if game_wrapper == null or game_wrapper.current_game == null:
		return false
	var logic_card = game_wrapper.get_card_database().get_card(card_id)
	return logic_card != null and logic_card.definition.get("id", "") == "iaquis_dragonsheart"

# True if the damaging card is Iaquis's Dragon's Heart being played by the
# given player (same pattern as Wild Hunt / Purification).
func _is_iaquis_heart_dealing_damage_to(player) -> bool:
	if game_wrapper == null or game_wrapper.current_game == null:
		return false
	for card_id in strike_attack_card_ids:
		var logic_card = game_wrapper.get_card_database().get_card(card_id)
		if card_id in strike_activated_card_ids and logic_card != null and logic_card.definition.get("id", "") == "iaquis_dragonsheart":
			var heart_is_players = game_wrapper.does_card_belong_to_player(Enums.PlayerId.PlayerId_Player, card_id)
			if heart_is_players and player == Enums.PlayerId.PlayerId_Opponent:
				return true
			if not heart_is_players and player == Enums.PlayerId.PlayerId_Player:
				return true
	return false

# Play the Iaquis Dragon's Heart hit closeup exactly once per side per
# strike, when a Dragon's Heart attack takes effect (card activation).
# Per-side like Wild Hunt. Gated to the MAIN attack card.
#
# is_local=true means the local player is the Dragon's Heart attacker.
func _play_iaquis_heart_entrance(is_local : bool):
	if not GlobalSettings.AnimationsEnabled:
		return
	# Only the MAIN attack card of the strike gets the closeup.
	if strike_is_extra_attack:
		return
	var frame_base : String
	if is_local:
		if heart_animation_right:
			return
		frame_base = IaquisHeartRightFrameBase
	else:
		if heart_animation_left:
			return
		frame_base = IaquisHeartLeftFrameBase
	var sf := SpriteFrames.new()
	sf.add_animation("heart")
	sf.set_animation_loop("heart", false)
	sf.set_animation_speed("heart", IaquisHeartFps)
	for i in range(IaquisHeartFrameCount):
		var tex = load(frame_base % i)
		if tex:
			sf.add_frame("heart", tex)
	if sf.get_frame_count("heart") == 0:
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = sf
	var frame_size = sf.get_frame_texture("heart", 0).get_size()
	var scale_factor = 1.0
	if frame_size.x > 0.0 and frame_size.y > 0.0:
		scale_factor = min(EntranceScreenWidth / frame_size.x, EntranceScreenHeight / frame_size.y) * 0.98
		sprite.scale = Vector2(scale_factor, scale_factor)
	# Top corner alignment: right frames -> top-right, left frames -> top-left.
	var displayed_size = frame_size * scale_factor
	if is_local:
		sprite.position = Vector2(EntranceScreenWidth - displayed_size.x * 0.5, displayed_size.y * 0.5)
		heart_animation_right = sprite
		heart_animation_layer_right = layer
	else:
		sprite.position = Vector2(displayed_size.x * 0.5, displayed_size.y * 0.5)
		heart_animation_left = sprite
		heart_animation_layer_left = layer
	layer.add_child(sprite)
	sprite.animation_finished.connect(_on_iaquis_heart_animation_finished.bind(is_local))
	sprite.play("heart")

func _on_iaquis_heart_animation_finished(is_local : bool):
	if is_local:
		if heart_animation_layer_right:
			heart_animation_layer_right.queue_free()
		heart_animation_layer_right = null
		heart_animation_right = null
	else:
		if heart_animation_layer_left:
			heart_animation_layer_left.queue_free()
		heart_animation_layer_left = null
		heart_animation_left = null

# Play the Iaquis Dragon's Heart damage-resolve effect (full-screen), once
# per strike, when Dragon's Heart damage is resolved. Gated to the MAIN
# attack card so chain extra attacks don't re-fire it.
func _play_iaquis_heart_damage():
	if not GlobalSettings.AnimationsEnabled:
		return
	# Only the MAIN attack card's damage plays the full-screen effect.
	if strike_is_extra_attack:
		return
	if heart_damage_animation:
		return
	var sf := SpriteFrames.new()
	sf.add_animation("heart_damage")
	sf.set_animation_loop("heart_damage", false)
	sf.set_animation_speed("heart_damage", IaquisHeartDamageFps)
	for i in range(IaquisHeartDamageFrameCount):
		var tex = load(IaquisHeartDamageFrameBase % i)
		if tex:
			sf.add_frame("heart_damage", tex)
	if sf.get_frame_count("heart_damage") == 0:
		return
	heart_damage_animation_layer = CanvasLayer.new()
	heart_damage_animation_layer.layer = 100
	add_child(heart_damage_animation_layer)
	heart_damage_animation = AnimatedSprite2D.new()
	heart_damage_animation.sprite_frames = sf
	heart_damage_animation.position = Vector2(EntranceScreenWidth * 0.5, EntranceScreenHeight * 0.5)
	var frame_size = sf.get_frame_texture("heart_damage", 0).get_size()
	if frame_size.x > 0.0 and frame_size.y > 0.0:
		# Cover the whole screen (no letterboxing).
		var scale_factor = max(EntranceScreenWidth / frame_size.x, EntranceScreenHeight / frame_size.y)
		heart_damage_animation.scale = Vector2(scale_factor, scale_factor)
	heart_damage_animation_layer.add_child(heart_damage_animation)
	heart_damage_animation.animation_finished.connect(_on_iaquis_heart_damage_finished)
	heart_damage_animation.play("heart_damage")

func _on_iaquis_heart_damage_finished():
	if heart_damage_animation_layer:
		heart_damage_animation_layer.queue_free()
	heart_damage_animation_layer = null
	heart_damage_animation = null

# True if the given card is Iaquis's Dragon's Descent (either player's).
func _is_iaquis_descent(card_id : int) -> bool:
	if game_wrapper == null or game_wrapper.current_game == null:
		return false
	var logic_card = game_wrapper.get_card_database().get_card(card_id)
	return logic_card != null and logic_card.definition.get("id", "") == "iaquis_dragonsdescent"

# True if the damaging card is Iaquis's Dragon's Descent being played by the
# given player (same pattern as Wild Hunt / Purification).
func _is_iaquis_descent_dealing_damage_to(player) -> bool:
	if game_wrapper == null or game_wrapper.current_game == null:
		return false
	for card_id in strike_attack_card_ids:
		var logic_card = game_wrapper.get_card_database().get_card(card_id)
		if card_id in strike_activated_card_ids and logic_card != null and logic_card.definition.get("id", "") == "iaquis_dragonsdescent":
			var descent_is_players = game_wrapper.does_card_belong_to_player(Enums.PlayerId.PlayerId_Player, card_id)
			if descent_is_players and player == Enums.PlayerId.PlayerId_Opponent:
				return true
			if not descent_is_players and player == Enums.PlayerId.PlayerId_Player:
				return true
	return false

# Play the Iaquis Dragon's Descent hit closeup exactly once per side per
# strike, when a Dragon's Descent attack takes effect (card activation).
# Per-side like Wild Hunt. Gated to the MAIN attack card.
#
# is_local=true means the local player is the Dragon's Descent attacker.
func _play_iaquis_descent_entrance(is_local : bool):
	if not GlobalSettings.AnimationsEnabled:
		return
	# Only the MAIN attack card of the strike gets the closeup.
	if strike_is_extra_attack:
		return
	var frame_base : String
	if is_local:
		if descent_animation_right:
			return
		frame_base = IaquisDescentRightFrameBase
	else:
		if descent_animation_left:
			return
		frame_base = IaquisDescentLeftFrameBase
	var sf := SpriteFrames.new()
	sf.add_animation("descent")
	sf.set_animation_loop("descent", false)
	sf.set_animation_speed("descent", IaquisDescentFps)
	for i in range(IaquisDescentFrameCount):
		var tex = load(frame_base % i)
		if tex:
			sf.add_frame("descent", tex)
	if sf.get_frame_count("descent") == 0:
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = sf
	var frame_size = sf.get_frame_texture("descent", 0).get_size()
	var scale_factor = 1.0
	if frame_size.x > 0.0 and frame_size.y > 0.0:
		scale_factor = min(EntranceScreenWidth / frame_size.x, EntranceScreenHeight / frame_size.y) * 0.98
		sprite.scale = Vector2(scale_factor, scale_factor)
	# Top corner alignment: right frames -> top-right, left frames -> top-left.
	var displayed_size = frame_size * scale_factor
	if is_local:
		sprite.position = Vector2(EntranceScreenWidth - displayed_size.x * 0.5, displayed_size.y * 0.5)
		descent_animation_right = sprite
		descent_animation_layer_right = layer
	else:
		sprite.position = Vector2(displayed_size.x * 0.5, displayed_size.y * 0.5)
		descent_animation_left = sprite
		descent_animation_layer_left = layer
	layer.add_child(sprite)
	sprite.animation_finished.connect(_on_iaquis_descent_animation_finished.bind(is_local))
	sprite.play("descent")

func _on_iaquis_descent_animation_finished(is_local : bool):
	if is_local:
		if descent_animation_layer_right:
			descent_animation_layer_right.queue_free()
		descent_animation_layer_right = null
		descent_animation_right = null
	else:
		if descent_animation_layer_left:
			descent_animation_layer_left.queue_free()
		descent_animation_layer_left = null
		descent_animation_left = null

# Play the Iaquis Dragon's Descent damage-resolve effect (full-screen), once
# per strike, when Dragon's Descent damage is resolved. Gated to the MAIN
# attack card so chain extra attacks don't re-fire it.
func _play_iaquis_descent_damage():
	if not GlobalSettings.AnimationsEnabled:
		return
	# Only the MAIN attack card's damage plays the full-screen effect.
	if strike_is_extra_attack:
		return
	if descent_damage_animation:
		return
	var sf := SpriteFrames.new()
	sf.add_animation("descent_damage")
	sf.set_animation_loop("descent_damage", false)
	sf.set_animation_speed("descent_damage", IaquisDescentDamageFps)
	for i in range(IaquisDescentDamageFrameCount):
		var tex = load(IaquisDescentDamageFrameBase % i)
		if tex:
			sf.add_frame("descent_damage", tex)
	if sf.get_frame_count("descent_damage") == 0:
		return
	descent_damage_animation_layer = CanvasLayer.new()
	descent_damage_animation_layer.layer = 100
	add_child(descent_damage_animation_layer)
	descent_damage_animation = AnimatedSprite2D.new()
	descent_damage_animation.sprite_frames = sf
	descent_damage_animation.position = Vector2(EntranceScreenWidth * 0.5, EntranceScreenHeight * 0.5)
	var frame_size = sf.get_frame_texture("descent_damage", 0).get_size()
	if frame_size.x > 0.0 and frame_size.y > 0.0:
		# Cover the whole screen (no letterboxing).
		var scale_factor = max(EntranceScreenWidth / frame_size.x, EntranceScreenHeight / frame_size.y)
		descent_damage_animation.scale = Vector2(scale_factor, scale_factor)
	descent_damage_animation_layer.add_child(descent_damage_animation)
	descent_damage_animation.animation_finished.connect(_on_iaquis_descent_damage_finished)
	descent_damage_animation.play("descent_damage")

func _on_iaquis_descent_damage_finished():
	if descent_damage_animation_layer:
		descent_damage_animation_layer.queue_free()
	descent_damage_animation_layer = null
	descent_damage_animation = null

# True if the given player id's deck is Iaquis (initial-ability checks).
func _is_player_iaquis(player_id) -> bool:
	if game_wrapper == null or game_wrapper.current_game == null:
		return false
	var deck = game_wrapper.get_player_deck_definition(player_id)
	return deck != null and deck.get("id", "") == "iaquis"

# Play the Iaquis initial-skill face-attack closeup (screen center). Both
# clients play it on the RevealStrike_OnePlayer event. bonus=true plays the
# stun easter-egg variant (龙男ua彩蛋特写).
func _play_iaquis_faceup(bonus : bool = false):
	if not GlobalSettings.AnimationsEnabled:
		return
	if iaquis_faceup_animation:
		# The normal face-up closeup (2.5s) may still be playing when the stun
		# easter-egg fires; the easter-egg replaces it.
		if not bonus:
			return
		_on_iaquis_faceup_animation_finished()
	var frame_base = IaquisFaceupBonusFrameBase if bonus else IaquisFaceupFrameBase
	var sf := SpriteFrames.new()
	sf.add_animation("iaquis_faceup")
	sf.set_animation_loop("iaquis_faceup", false)
	sf.set_animation_speed("iaquis_faceup", IaquisFaceupFps)
	for i in range(IaquisFaceupFrameCount):
		var tex = load(frame_base % i)
		if tex:
			sf.add_frame("iaquis_faceup", tex)
	if sf.get_frame_count("iaquis_faceup") == 0:
		return
	iaquis_faceup_animation_layer = CanvasLayer.new()
	iaquis_faceup_animation_layer.layer = 100
	add_child(iaquis_faceup_animation_layer)
	iaquis_faceup_animation = AnimatedSprite2D.new()
	iaquis_faceup_animation.sprite_frames = sf
	var frame_size = sf.get_frame_texture("iaquis_faceup", 0).get_size()
	var scale_factor = 1.0
	if frame_size.x > 0.0 and frame_size.y > 0.0:
		scale_factor = min(EntranceScreenWidth / frame_size.x, EntranceScreenHeight / frame_size.y) * 0.98
		iaquis_faceup_animation.scale = Vector2(scale_factor, scale_factor)
	# Screen center.
	iaquis_faceup_animation.position = Vector2(EntranceScreenWidth * 0.5, EntranceScreenHeight * 0.5)
	iaquis_faceup_animation_layer.add_child(iaquis_faceup_animation)
	iaquis_faceup_animation.animation_finished.connect(_on_iaquis_faceup_animation_finished)
	iaquis_faceup_animation.play("iaquis_faceup")

func _on_iaquis_faceup_animation_finished():
	if iaquis_faceup_animation_layer:
		iaquis_faceup_animation_layer.queue_free()
	iaquis_faceup_animation_layer = null
	iaquis_faceup_animation = null

func _is_qoh_strike_dealing_damage_to(player) -> bool:
	if game_wrapper == null or game_wrapper.current_game == null:
		return false
	# Only attack cards set in this strike count (boosts never damage).
	for card_id in strike_attack_card_ids:
		var logic_card = game_wrapper.get_card_database().get_card(card_id)
		if card_id in strike_activated_card_ids and logic_card != null and logic_card.definition.get("id", "") == "eugenia_queen_of_hearts":
			var qoh_is_players = game_wrapper.does_card_belong_to_player(Enums.PlayerId.PlayerId_Player, card_id)
			if qoh_is_players and player == Enums.PlayerId.PlayerId_Opponent:
				return true
			if not qoh_is_players and player == Enums.PlayerId.PlayerId_Player:
				return true
	return false

# True if a Cat's Cradle is the active strike attack card and the damaged
# player is whoever is NOT the Cradle's owner (mirrors _is_qoh_strike_dealing_damage_to).
func _is_cats_cradle_strike_dealing_damage_to(player) -> bool:
	if game_wrapper == null or game_wrapper.current_game == null:
		return false
	for card_id in strike_attack_card_ids:
		var logic_card = game_wrapper.get_card_database().get_card(card_id)
		if card_id in strike_activated_card_ids and logic_card != null and logic_card.definition.get("id", "") == "eugenia_cats_cradle":
			var cradle_is_players = game_wrapper.does_card_belong_to_player(Enums.PlayerId.PlayerId_Player, card_id)
			if cradle_is_players and player == Enums.PlayerId.PlayerId_Opponent:
				return true
			if not cradle_is_players and player == Enums.PlayerId.PlayerId_Player:
				return true
	return false

func _ready():
	image_loader = CardImageLoader.new()
	image_loader.defer_registered_card_images = false
	image_loader.lazy_multi_card_textures = false
	add_child(image_loader)
	resolved_arena_style = BackgroundManager.resolve_background_id(GlobalSettings.ArenaStyle)
	_initialize_track_overlay_layers()
	_update_runtime_health_debug_toggle_button()
	if runtime_health_debug_panel:
		runtime_health_debug_panel.visible = false
	_initialize_responsive_layout_state()
	if get_viewport() and not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	_refresh_viewport_layout_metrics()
	_last_stable_viewport_size = Vector2(get_viewport().content_scale_size)

	NetworkManager.connect("players_update", _on_players_update)
	NetworkManager.connect("reconnect_state_changed", _on_reconnect_state_changed)
	NetworkManager.connect("waiting_for_opponent_reconnect_changed", _on_waiting_for_opponent_reconnect_changed)
	NetworkManager.connect("matchlog_upload_finished", _on_matchlog_upload_finished)
	_update_network_reconnect_pause()

	if started_directly:
		# Started this scene directly.
		var vs_info = {
			'player_deck': CardDataManager.get_deck_test_deck(),
			'opponent_deck': CardDataManager.get_deck_test_deck(),
			'randomize_first_vs_ai': false
		}
		begin_local_game(vs_info)
		initialization_after_begin_game()

func _initialize_track_overlay_layers():
	if not friend_track_overlay_layers.is_empty() or not enemy_track_overlay_layers.is_empty():
		return

	for i in range(2):
		var friend_overlay = _create_track_overlay_layer(friend_track_layer, "FriendTrackLayerExtra%d" % [i + 1])
		add_child(friend_overlay)
		move_child(friend_overlay, friend_track_layer.get_index() + i + 1)
		friend_track_overlay_layers.append(friend_overlay)

	for i in range(2):
		var enemy_overlay = _create_track_overlay_layer(enemy_track_layer, "EnemyTrackLayerExtra%d" % [i + 1])
		add_child(enemy_overlay)
		move_child(enemy_overlay, enemy_track_layer.get_index() + i + 1)
		enemy_track_overlay_layers.append(enemy_overlay)

func _create_track_overlay_layer(template_layer : TextureRect, layer_name : String) -> TextureRect:
	var track_layer := TextureRect.new()
	track_layer.name = layer_name
	track_layer.offset_left = template_layer.offset_left
	track_layer.offset_top = template_layer.offset_top
	track_layer.offset_right = template_layer.offset_right
	track_layer.offset_bottom = template_layer.offset_bottom
	track_layer.mouse_filter = template_layer.mouse_filter
	track_layer.expand_mode = template_layer.expand_mode
	track_layer.stretch_mode = template_layer.stretch_mode
	track_layer.visible = false
	return track_layer

func _clear_track_overlays(layers : Array[TextureRect]):
	for layer in layers:
		layer.texture = null
		layer.visible = false

func _update_track_overlays_for_character(
		layers : Array[TextureRect],
		arena_style : String,
		prefix : String,
		center_location : int,
		extra_width : int,
		uses_classic_arena : bool):
	if uses_classic_arena or extra_width <= 0:
		_clear_track_overlays(layers)
		return

	var overlay_index = 0
	for offset in range(-extra_width, extra_width + 1):
		if offset == 0:
			continue
		if overlay_index >= layers.size():
			break
		var board_location = center_location + offset
		var overlay_texture : Texture2D = null
		if board_location >= 1 and board_location <= 9:
			overlay_texture = BackgroundManager.get_arena_texture(arena_style, prefix, 10 - board_location)
		layers[overlay_index].texture = overlay_texture
		layers[overlay_index].visible = overlay_texture != null
		overlay_index += 1

	for i in range(overlay_index, layers.size()):
		layers[i].texture = null
		layers[i].visible = false

func _prepare_track_overlays_for_character(
		layers : Array[TextureRect],
		arena_style : String,
		prefix : String,
		center_location : int,
		extra_width : int,
		uses_classic_arena : bool):
	if uses_classic_arena or extra_width <= 0:
		_clear_track_overlays(layers)
		return

	var overlay_index = 0
	for offset in range(-extra_width, extra_width + 1):
		if offset == 0:
			continue
		if overlay_index >= layers.size():
			break
		var board_location = center_location + offset
		var overlay_texture : Texture2D = null
		if board_location >= 1 and board_location <= 9:
			overlay_texture = await BackgroundManager.load_arena_texture(arena_style, prefix, 10 - board_location)
		layers[overlay_index].texture = overlay_texture
		layers[overlay_index].visible = overlay_texture != null
		overlay_index += 1
		await _yield_web_arena_visual_frame()

	for i in range(overlay_index, layers.size()):
		layers[i].texture = null
		layers[i].visible = false

func _yield_web_arena_visual_frame():
	if not _is_web_runtime():
		return
	for _frame in range(WebRuntimeArenaVisualYieldFrames):
		await get_tree().process_frame

func _prepare_initial_arena_visuals():
	_emit_loading_status("准备场地背景")
	var arena_style := resolved_arena_style
	var uses_classic_arena := BackgroundManager.uses_classic_arena(arena_style)
	arena_graphics.visible = uses_classic_arena
	if not uses_classic_arena:
		_emit_loading_status("准备场地地砖")
		await BackgroundManager.preload_all_arena_tiles(arena_style)
		await _yield_web_arena_visual_frame()
		_emit_loading_status("准备场地背景")
	background_image.texture = await BackgroundManager.load_background_texture(arena_style)
	await _yield_web_arena_visual_frame()

	var player_extra_width = 0
	if $PlayerCharacter.is_wide:
		player_extra_width = game_wrapper.get_player_extra_width(Enums.PlayerId.PlayerId_Player)
	var opponent_extra_width = 0
	if $OpponentCharacter.is_wide:
		opponent_extra_width = game_wrapper.get_player_extra_width(Enums.PlayerId.PlayerId_Opponent)

	friend_track_layer.texture = null if uses_classic_arena else await BackgroundManager.load_arena_texture(
		arena_style, "B", 10 - cached_player_location)
	await _yield_web_arena_visual_frame()
	enemy_track_layer.texture = null if uses_classic_arena else await BackgroundManager.load_arena_texture(
		arena_style, "R", 10 - cached_opponent_location)
	await _yield_web_arena_visual_frame()
	await _prepare_track_overlays_for_character(
		friend_track_overlay_layers,
		arena_style,
		"B",
		cached_player_location,
		player_extra_width,
		uses_classic_arena)
	await _prepare_track_overlays_for_character(
		enemy_track_overlay_layers,
		arena_style,
		"R",
		cached_opponent_location,
		opponent_extra_width,
		uses_classic_arena)

func _exit_tree():
	_release_match_resources()

func _release_match_resources():
	if resources_released:
		return
	resources_released = true
	BackgroundManager.clear_match_texture_cache()
	if NetworkManager.is_connected("players_update", _on_players_update):
		NetworkManager.disconnect("players_update", _on_players_update)
	if NetworkManager.is_connected("reconnect_state_changed", _on_reconnect_state_changed):
		NetworkManager.disconnect("reconnect_state_changed", _on_reconnect_state_changed)
	if NetworkManager.is_connected("waiting_for_opponent_reconnect_changed", _on_waiting_for_opponent_reconnect_changed):
		NetworkManager.disconnect("waiting_for_opponent_reconnect_changed", _on_waiting_for_opponent_reconnect_changed)
	if NetworkManager.is_connected("matchlog_upload_finished", _on_matchlog_upload_finished):
		NetworkManager.disconnect("matchlog_upload_finished", _on_matchlog_upload_finished)
	close_popout()
	clear_choice_zone()
	if game_wrapper and game_wrapper.current_game:
		game_wrapper.end_game()
	if image_loader:
		image_loader.teardown()
		image_loader.queue_free()
		image_loader = null

func initialization_after_begin_game():
	surrender_in_progress = false
	if not game_wrapper.is_ai_game():
		$AIMoveButton.visible = false
	else:
		#! 浅墨ai 入门 和 超级 版本切换
		var ai_policy : Node = AIPolicyRules.new()
		if GlobalSettings.AIMode == "omniscient":
			ai_policy = AIPolicyOmniscient.new()
		ai_player = AIPlayer.new(game_wrapper.current_game, game_wrapper.current_game.opponent, ai_policy)
	$PlayerLife.set_life(game_wrapper.get_player_life(Enums.PlayerId.PlayerId_Player))
	$OpponentLife.set_life(game_wrapper.get_player_life(Enums.PlayerId.PlayerId_Opponent))
	game_over_stuff.visible = false
	if not observer_mode:
		$PlayerLife.set_clock(starting_timer)
		$OpponentLife.set_clock(starting_timer)

	player_bonus_panel.visible = false
	opponent_bonus_panel.visible = false
	player_bonus_label.text = ""
	opponent_bonus_label.text = ""

	var observer_room_mode = observer_mode and not replay_mode
	observer_next_button.visible = observer_mode
	observer_previous_button.visible = replay_mode
	observer_play_to_live_button.visible = observer_room_mode
	$ObserverJumpToLatest.visible = observer_room_mode
	_update_surrender_button_visibility()
	_update_replay_step_buttons()

	save_replay_button.visible = false
	file_dialog.visible = false

	for i in range(1, 10):
		player_lightningrod_tracking[i] = {
			"card_ids": [],
			"character": null,
		}
		opponent_lightningrod_tracking[i] = {
			"card_ids": [],
			"character": null,
		}

	var location_index = 0
	for child in $ArenaNode/RowLightningInfoButtons.get_children():
		if location_index == 0 or location_index == 10:
			# Skip margin containers
			location_index += 1
			continue
		assert(child is LocationInfoButtonPair)
		child.button_pressed.connect(func(player_id): _on_locationinfobuttonpair_pressed(player_id, location_index))
		location_index += 1

	ChoiceTagRegex.compile("\\[.*\\]")

	setup_characters()
	_viewport_layout_ready = true
	_refresh_viewport_layout_metrics(true)

func _on_viewport_size_changed():
	if not _viewport_layout_ready:
		_refresh_viewport_layout_metrics(false)
		return
	_schedule_rotation_layout_refresh()

func _schedule_rotation_layout_refresh():
	_viewport_layout_generation += 1
	var layout_generation := _viewport_layout_generation
	if not _rotation_layout_in_progress:
		_rotation_layout_in_progress = true
		rotation_layout_overlay.visible = true
		GlobalSettings.set_web_rotation_render_scale(_is_mobile_web_runtime())
		_begin_rotation_layout_visual_pause()
		_run_rotation_layout_refresh(layout_generation)

static func is_rotation_layout_request_current(request_generation : int, current_generation : int) -> bool:
	return request_generation == current_generation

static func is_rotation_viewport_size_valid(viewport_size : Vector2) -> bool:
	return viewport_size.x >= WebRuntimeMinimumViewportSize.x and viewport_size.y >= WebRuntimeMinimumViewportSize.y

func _begin_rotation_layout_visual_pause():
	$OpponentDeck/ThinkingIndicator.visible = false
	_finish_all_card_animations()
	_finish_all_character_animations()
	for popup in find_children("*", "DamagePopup", true, false):
		popup.pause_for_rotation_layout()
	player_emote.pause_for_rotation_layout()
	opponent_emote.pause_for_rotation_layout()

func _run_rotation_layout_refresh(layout_generation : int, invalid_viewport_retries := 0):
	for _frame in range(WebRuntimeRotationSettleFrames):
		await get_tree().process_frame
	if not is_rotation_layout_request_current(layout_generation, _viewport_layout_generation):
		_run_rotation_layout_refresh(_viewport_layout_generation)
		return

	var viewport_size := Vector2(get_viewport().content_scale_size)
	if not is_rotation_viewport_size_valid(viewport_size):
		if invalid_viewport_retries >= WebRuntimeMaximumInvalidViewportRetries:
			_apply_responsive_root_layout(_last_stable_viewport_size)
			_finish_rotation_layout_refresh()
			return
		await get_tree().process_frame
		_run_rotation_layout_refresh(_viewport_layout_generation, invalid_viewport_retries + 1)
		return
	await get_tree().process_frame
	if not is_rotation_layout_request_current(layout_generation, _viewport_layout_generation):
		_run_rotation_layout_refresh(_viewport_layout_generation)
		return
	var confirmed_viewport_size := Vector2(get_viewport().content_scale_size)
	if confirmed_viewport_size != viewport_size:
		_run_rotation_layout_refresh(_viewport_layout_generation)
		return
	if not is_rotation_viewport_size_valid(confirmed_viewport_size):
		_finish_rotation_layout_refresh()
		return
	_last_stable_viewport_size = confirmed_viewport_size

	_apply_responsive_root_layout(_last_stable_viewport_size)
	await get_tree().process_frame
	if not is_rotation_layout_request_current(layout_generation, _viewport_layout_generation):
		_run_rotation_layout_refresh(_viewport_layout_generation)
		return

	_layout_player_hand_now(true)
	_layout_player_hand_now(false)
	_finish_all_card_animations()
	await get_tree().process_frame
	if not is_rotation_layout_request_current(layout_generation, _viewport_layout_generation):
		_run_rotation_layout_refresh(_viewport_layout_generation)
		return

	_refresh_world_positions_after_layout()
	_finish_all_character_animations()
	_finish_rotation_layout_refresh()

func _finish_rotation_layout_refresh():
	GlobalSettings.set_web_rotation_render_scale(false)
	rotation_layout_overlay.visible = false
	_rotation_layout_in_progress = false

func _is_mobile_web_runtime() -> bool:
	return MobileRuntimeFlags.is_mobile_resource_runtime()

func _finish_all_card_animations():
	for card in find_children("*", "CardBase", true, false):
		card.finish_animation_immediately()

func _finish_all_character_animations():
	$PlayerCharacter.finish_movement()
	$OpponentCharacter.finish_movement()
	for buddy in player_buddies:
		buddy.finish_movement()
	for buddy in opponent_buddies:
		buddy.finish_movement()
	for location in range(1, 10):
		var player_rod = player_lightningrod_tracking.get(location, {}).get("character")
		if player_rod != null:
			player_rod.finish_movement()
		var opponent_rod = opponent_lightningrod_tracking.get(location, {}).get("character")
		if opponent_rod != null:
			opponent_rod.finish_movement()

func _initialize_responsive_layout_state():
	if _responsive_position_nodes.size() > 0 or _responsive_anchor_roots.size() > 0:
		return

	for node in [
		$ArenaNode,
		$OpponentLife,
		$PlayerLife,
		$PlayerZones,
		$OpponentZones,
		$PlayerBoostZone,
		$OpponentBoostZone,
		$ChoicePopoutShowButton,
		$ObserverNextButton,
		$ObserverPreviousButton,
		$ObserverPlayToLive,
		$ExitToMenu,
		$HugeCard,
		$EmoteButton,
		$AllCards/PlayerDiscardButton,
		$AllCards/OpponentDiscardButton,
	]:
		_responsive_position_nodes.append({
			"node": node,
			"base_position": node.position,
		})

	for entry in [
		{"root": $PlayerDeck, "anchor": $PlayerDeck/DeckButton},
		{"root": $OpponentDeck, "anchor": $OpponentDeck/DeckButton},
		{"root": $PlayerStrike, "anchor": $PlayerStrike/StrikeZone},
		{"root": $OpponentStrike, "anchor": $OpponentStrike/StrikeZone},
		{"root": $OpponentHand, "anchor": $OpponentHand/HandSpawn},
	]:
		_responsive_anchor_roots.append({
			"root": entry["root"],
			"base_anchor_position": entry["anchor"].position,
		})

func _scale_base_position(base_position : Vector2, viewport_scale : Vector2) -> Vector2:
	return Vector2(base_position.x * viewport_scale.x, base_position.y * viewport_scale.y)

static func get_rotation_safe_position(target_position : Vector2, node_size : Vector2, viewport_size : Vector2) -> Vector2:
	return Vector2(
		clampf(target_position.x, -node_size.x, viewport_size.x),
		clampf(target_position.y, -node_size.y, viewport_size.y))

func _apply_responsive_root_layout(viewport_size : Vector2):
	var viewport_scale = Vector2(
		viewport_size.x / BaseViewportSize.x,
		viewport_size.y / BaseViewportSize.y
	)

	for entry in _responsive_position_nodes:
		var node = entry["node"]
		var scaled_position := _scale_base_position(entry["base_position"], viewport_scale)
		var node_size : Vector2 = node.size if node is Control else Vector2.ZERO
		node.position = get_rotation_safe_position(scaled_position, node_size, viewport_size)

	for entry in _responsive_anchor_roots:
		var root = entry["root"]
		var base_anchor_position : Vector2 = entry["base_anchor_position"]
		var scaled_anchor_position := _scale_base_position(base_anchor_position, viewport_scale) - base_anchor_position
		var root_size : Vector2 = root.size if root is Control else Vector2.ZERO
		root.position = get_rotation_safe_position(scaled_anchor_position, root_size, viewport_size)

	$Background.size = viewport_size
	$ArenaNode/RowButtons.size.x = viewport_size.x
	$ArenaNode/RowPlatforms.custom_minimum_size.x = viewport_size.x
	$ArenaNode/RowPlatforms.size.x = viewport_size.x
	$ArenaNode/RowLightningInfoButtons.custom_minimum_size.x = viewport_size.x
	$ArenaNode/RowLightningInfoButtons.size.x = viewport_size.x
	$AllCards/ActionContainer.size.x = viewport_size.x
	rotation_layout_overlay.size = viewport_size

func _refresh_world_positions_after_layout():
	if not first_run_done:
		return

	if cached_player_location > 0:
		move_character_to_arena_square($PlayerCharacter, cached_player_location, true, Character.CharacterAnim.CharacterAnim_None)
	if cached_opponent_location > 0:
		move_character_to_arena_square($OpponentCharacter, cached_opponent_location, true, Character.CharacterAnim.CharacterAnim_None)

	var player_logic = game_wrapper.current_game.player if game_wrapper.current_game else null
	var opponent_logic = game_wrapper.current_game.opponent if game_wrapper.current_game else null

	for buddy in player_buddies:
		if buddy.visible and player_logic:
			var buddy_location = player_logic.get_buddy_location(buddy.get_buddy_id())
			if buddy_location != -1:
				move_character_to_arena_square(buddy, buddy_location, true, Character.CharacterAnim.CharacterAnim_None, -1)

	for buddy in opponent_buddies:
		if buddy.visible and opponent_logic:
			var buddy_location = opponent_logic.get_buddy_location(buddy.get_buddy_id())
			if buddy_location != -1:
				move_character_to_arena_square(buddy, buddy_location, true, Character.CharacterAnim.CharacterAnim_None, -1)

	for location in range(1, 10):
		var player_rod = player_lightningrod_tracking.get(location, {}).get("character")
		if player_rod != null:
			move_character_to_arena_square(player_rod, location, true, Character.CharacterAnim.CharacterAnim_None, -1)
		var opponent_rod = opponent_lightningrod_tracking.get(location, {}).get("character")
		if opponent_rod != null:
			move_character_to_arena_square(opponent_rod, location, true, Character.CharacterAnim.CharacterAnim_None, -1)

	update_character_facing()
	update_arena_squares()

func _refresh_viewport_layout_metrics(relayout_hands := false):
	if not is_inside_tree() or get_viewport() == null:
		return

	var viewport_size = Vector2(get_viewport().content_scale_size)
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		return

	_apply_responsive_root_layout(viewport_size)

	CenterCardOval = viewport_size * Vector2(0.5, 1.35)
	HorizontalRadius = viewport_size.x * 0.55
	VerticalRadius = viewport_size.y * 0.4

	if not relayout_hands or not _viewport_layout_ready:
		return

	layout_player_hand(true)
	layout_player_hand(false)
	_refresh_world_positions_after_layout()

func _on_players_update(_players, _matches, _queues : Array, newly_available_match : bool):
	if (game_wrapper.is_ai_game() or observer_mode) and newly_available_match:
		# Let the player know there is a match they could join.
		show_match_available_notification()

func show_match_available_notification():
	if not ignore_queue_notifications:
		var viewport_size = Vector2(get_viewport().content_scale_size) if get_viewport() else BaseViewportSize
		slideout_dialog.position = Vector2(viewport_size.x, SlideoutStartPosition.y * viewport_size.y / BaseViewportSize.y)
		slideout_dialog.visible = true
		#slideout_dialog.set_fields(
		#	"A match is available!",
		#	"Exit to Menu",
		#	"Ignore",
		#	"Don't show this again"
		#)
		slideout_dialog.set_fields(
			"有人在队列中等待！",
			"回到主页面",
			"忽略",
			"不再显示此弹框"
		)
		# Start a tween to slide it in to view by moving it left by its width.
		var tween = create_tween()
		tween.tween_property(slideout_dialog, "position", slideout_dialog.position - Vector2(slideout_dialog.size.x, 0), 0.5)
		tween.play()

func _on_locationinfobuttonpair_pressed(player, location):
	var rod_tracking = player_lightningrod_tracking
	if player == Enums.PlayerId.PlayerId_Opponent:
		rod_tracking = opponent_lightningrod_tracking

	var card_db = game_wrapper.get_card_database()
	var info_str : String = ""
	for card_id in rod_tracking[location]["card_ids"]:
		info_str += card_db.get_card_name(card_id) + "\n"
	if info_str:
		info_str = info_str.erase(len(info_str)-1)
		modal_dialog.set_text_fields("Lightning Rods:\n%s" % info_str, "", "Close")
		modal_dialog_type = ModalDialogType.ModalDialogType_CardInform

func begin_local_game(vs_info):
	replay_saving_enabled = false
	player_deck = vs_info['player_deck']
	opponent_deck = vs_info['opponent_deck']
	var randomize_first_player = vs_info['randomize_first_vs_ai']
	game_wrapper.initialize_local_game(player_deck, opponent_deck, randomize_first_player, image_loader)

func begin_remote_game(game_start_message):
	starting_message = game_start_message.duplicate(true)
	observer_mode = 'observer_mode' in game_start_message and game_start_message['observer_mode']
	replay_mode = 'replay_mode' in game_start_message and game_start_message['replay_mode']
	replay_seek_target = int(game_start_message.get('replay_seek_target', -1))
	# Replay files should always read from observer_log; restore_log is a
	# reconnect snapshot and may end at a disconnect boundary.
	var has_restore_log = game_start_message.has('restore_log') and game_start_message['restore_log'].size() > 0
	var is_replay_step_rebuild = bool(game_start_message.get('replay_step_rebuild', false))
	restore_fast_forward_pending = has_restore_log and (not replay_mode or replay_seek_target >= 0 or is_replay_step_rebuild)
	restore_fast_forwarding = false
	replay_saving_enabled = true
	# Add a few seconds to starting timers to account for loading screen
	starting_timer = game_start_message['starting_timer'] + 4
	enforce_timer = game_start_message['enforce_timer']
	minimum_time_per_choice = game_start_message['minimum_time_per_choice']
	player_clock_remaining = starting_timer
	opponent_clock_remaining = starting_timer

	var starting_message_queue = []
	if replay_mode and observer_mode and game_start_message.has('observer_log'):
		starting_message_queue = game_start_message['observer_log']
	elif game_start_message.has('restore_log'):
		starting_message_queue = game_start_message['restore_log']
	elif observer_mode:
		starting_message_queue = game_start_message['observer_log']

	var p1deck
	if game_start_message.get('player1_custom_deck'):
		p1deck = game_start_message['player1_custom_deck']
	else:
		p1deck = CardDataManager.get_deck_from_str_id(game_start_message['player1_deck_id'])
	var p2deck
	if game_start_message.get('player2_custom_deck'):
		p2deck = game_start_message['player2_custom_deck']
	else:
		p2deck = CardDataManager.get_deck_from_str_id(game_start_message['player2_deck_id'])
	p1deck["asset_deck_id"] = str(game_start_message["player1_deck_id"])
	p2deck["asset_deck_id"] = str(game_start_message["player2_deck_id"])

	var queue_id = str(game_start_message.get("queue_id", ""))
	if hp_rank_mode_manager.is_hp_rank_queue(queue_id):
		var hp_rank_result = hp_rank_mode_manager.build_match_starting_hp(
			queue_id,
			str(game_start_message['player1_deck_id']),
			str(game_start_message['player2_deck_id'])
		)
		if hp_rank_result.get("valid", false):
			p1deck = hp_rank_mode_manager.apply_starting_hp_to_deck(
				p1deck,
				int(hp_rank_result["player1_starting_life"]),
				int(hp_rank_result["player1_life_cap"])
			)
			if hp_rank_result.get("player1_character", "") == "taisei":
				p1deck["hp_rank_taisei_exceed_life"] = hp_rank_mode_manager.get_taisei_exceed_life(
					"taisei",
					str(hp_rank_result.get("player2_tier", "")),
					10
				)
			p2deck = hp_rank_mode_manager.apply_starting_hp_to_deck(
				p2deck,
				int(hp_rank_result["player2_starting_life"]),
				int(hp_rank_result["player2_life_cap"])
			)
			if hp_rank_result.get("player2_character", "") == "taisei":
				p2deck["hp_rank_taisei_exceed_life"] = hp_rank_mode_manager.get_taisei_exceed_life(
					"taisei",
					str(hp_rank_result.get("player1_tier", "")),
					10
				)
		else:
			push_warning("HP rank mode config invalid for this match: %s" % str(hp_rank_result.get("error", "unknown")))

	var player1_info = {
		'name': game_start_message['player1_name'],
		'id': game_start_message['player1_id'],
		'deck_id': game_start_message['player1_deck_id'],
		'deck': p1deck,
		'player_number': 1,
		'custom_deck': game_start_message['player1_custom_deck'],
	}
	var player2_info = {
		'name': game_start_message['player2_name'],
		'id': game_start_message['player2_id'],
		'deck_id': game_start_message['player2_deck_id'],
		'deck': p2deck,
		'player_number': 2,
		'custom_deck': game_start_message['player2_custom_deck'],
	}
	var seed_value = game_start_message['seed_value']
	var starting_player = Enums.PlayerId.PlayerId_Player
	var my_player_info
	var opponent_player_info
	var perspective_player_id = game_start_message.get('your_player_id', game_start_message['player1_id'] if observer_mode else 0)

	if perspective_player_id == game_start_message['player1_id']:
		my_player_info = player1_info
		player_deck = player1_info['deck']
		opponent_player_info = player2_info
		opponent_deck = player2_info['deck']
		if game_start_message['starting_player_id'] == game_start_message['player2_id']:
			starting_player = Enums.PlayerId.PlayerId_Opponent
	else:
		my_player_info = player2_info
		player_deck = player2_info['deck']
		opponent_player_info = player1_info
		opponent_deck = player1_info['deck']
		if game_start_message['starting_player_id'] == game_start_message['player1_id']:
			starting_player = Enums.PlayerId.PlayerId_Opponent

	player_deck = CardDataManager.convert_floats_to_ints(player_deck)
	opponent_deck = CardDataManager.convert_floats_to_ints(opponent_deck)

	game_wrapper.initialize_remote_game(my_player_info,
		opponent_player_info,
		starting_player,
		seed_value,
		observer_mode,
		replay_mode,
		starting_message_queue,
		image_loader)

func set_player_as_clock_user(player_id : Enums.PlayerId):
	current_clock_user = player_id
	new_clock_user_assigned = true

func is_player_overdrive_visible(player_id : Enums.PlayerId):
	return game_wrapper.is_player_in_overdrive(player_id)

func add_buddy_to_zone(player : Enums.PlayerId, buddy : Node2D, buddy_id):
	var deck_def = player_deck
	var buddies = player_buddies
	if player == Enums.PlayerId.PlayerId_Opponent:
		deck_def = opponent_deck
		buddies = opponent_buddies
	var buddy_index = 0
	if 'buddy_cards' in deck_def and deck_def['buddy_cards']:
		for i in range(len(deck_def['buddy_cards'])):
			if buddy_id == deck_def['buddy_cards'][i]:
				buddy_index = i
				break
	var is_foreground_buddy = 'buddy_cards_foreground' in deck_def and deck_def['buddy_cards_foreground'][buddy_index]
	var zone = background_buddies_parent
	if is_foreground_buddy:
		zone = foreground_buddies_parent
	buddy.get_parent().remove_child(buddy)
	zone.add_child(buddy)

	# Keep buddies in the specific order in their definition so they layer correctly.
	# For example, Rachel's George is in front of Ivy Blossom.
	var child_index = 0
	var children = zone.get_children()
	for buddy_node in buddies:
		if buddy_node in children:
			zone.move_child(buddy_node, child_index)
			child_index += 1

func setup_characters():
	_emit_loading_status("准备角色动画")
	await $PlayerCharacter.load_character(image_loader, player_deck, player_deck['id'])
	await $OpponentCharacter.load_character(image_loader, opponent_deck, opponent_deck['id'])

	if 'buddy_card' in player_deck:
		player_buddies[0].visible = false
		await player_buddies[0].load_character(image_loader, player_deck, player_deck['buddy_card'])
		player_buddies[0].set_buddy_id(player_deck['buddy_card'])
	if 'buddy_card' in opponent_deck:
		opponent_buddies[0].visible = false
		await opponent_buddies[0].load_character(image_loader, opponent_deck, opponent_deck['buddy_card'])
		opponent_buddies[0].set_buddy_id(opponent_deck['buddy_card'])
	if 'buddy_cards' in player_deck:
		if 'no_buddy_card_graphics' in player_deck and player_deck['no_buddy_card_graphics']:
			pass
		else:
			for i in range(0, player_deck['buddy_cards'].size()):
				player_buddies[i].visible = false
				await player_buddies[i].load_character(image_loader, player_deck, player_deck['buddy_card_graphics_id'][i])
				player_buddies[i].set_buddy_id(player_deck['buddy_cards'][i])
	if 'buddy_cards' in opponent_deck:
		if 'no_buddy_card_graphics' in opponent_deck and opponent_deck['no_buddy_card_graphics']:
			pass
		else:
			for i in range(0, opponent_deck['buddy_cards'].size()):
				opponent_buddies[i].visible = false
				await opponent_buddies[i].load_character(image_loader, opponent_deck, opponent_deck['buddy_card_graphics_id'][i])
				opponent_buddies[i].set_buddy_id(opponent_deck['buddy_cards'][i])
	if player_deck['id'] == opponent_deck['id']:
		$OpponentCharacter.modulate = Color(1, 0.38, 0.55)
		for buddy in opponent_buddies:
			buddy.modulate = Color(1, 0.38, 0.55)
	$PlayerZones/PlayerSealed.visible = 'has_sealed_area' in player_deck and player_deck['has_sealed_area']
	$OpponentZones/OpponentSealed.visible = 'has_sealed_area' in opponent_deck and opponent_deck['has_sealed_area']
	$PlayerZones/PlayerBleach.visible = typeof(player_deck.get("stored_bleach_info")) == TYPE_DICTIONARY
	$OpponentZones/OpponentBleach.visible = typeof(opponent_deck.get("stored_bleach_info")) == TYPE_DICTIONARY
	if $PlayerZones/PlayerBleach.visible:
		$PlayerZones/PlayerBleach.set_label(player_deck["stored_bleach_info"].get("name", "特殊区域"))
	if $OpponentZones/OpponentBleach.visible:
		$OpponentZones/OpponentBleach.set_label(opponent_deck["stored_bleach_info"].get("name", "特殊区域"))
	if 'sealed_area_is_secret' in opponent_deck and opponent_deck['sealed_area_is_secret']:
		$OpponentZones/OpponentSealed.hidden_sealed()
	$PlayerZones/PlayerOverdrive.visible = is_player_overdrive_visible(Enums.PlayerId.PlayerId_Player)
	$OpponentZones/OpponentOverdrive.visible = is_player_overdrive_visible(Enums.PlayerId.PlayerId_Opponent)
	_emit_loading_status("准备角色卡")
	setup_character_card(player_character_card, player_deck, player_buddy_character_card)
	setup_character_card(opponent_character_card, opponent_deck, opponent_buddy_character_card)

	setup_characters_complete = true
	_emit_loading_status("准备游戏界面")

func _emit_loading_status(status_text : String):
	print("[GameLoading] ", status_text)
	loading_status_changed.emit(status_text)

func setup_character_card(character_card, deck, buddy_character_card):
	character_card.set_name_text(deck['display_name'])

	var loaded_character_image = await image_loader.get_card_image(
		deck['image_resources']['character_default']['url'], 0)
	var loaded_exceed_image = await image_loader.get_card_image(
		deck['image_resources']['character_exceeded']['url'], 0)
	character_card.set_image(loaded_character_image, loaded_exceed_image)
	await runtime_yield_for_loading_batch(1)

	var on_exceed_text = ""
	if 'on_exceed' in deck:
		on_exceed_text = GameStrings.get_on_exceed_text(deck['on_exceed'])
	var effect_text = on_exceed_text + GameStrings.get_effects_text(deck['ability_effects'])
	var exceed_text = GameStrings.get_effects_text(deck['exceed_ability_effects'])
	character_card.set_effect(effect_text, exceed_text)
	character_card.set_cost(deck['exceed_cost'])

	# Setup buddy if they have one.
	var created_buddy_cards = []
	if 'hide_buddy_reference' in deck and deck['hide_buddy_reference']:
		buddy_character_card.visible = false
	elif 'buddy_card' in deck:
		# Some buddies (e.g. Wonderland/Briefcase) should only appear after exceed.
		var deck_logic_id = str(deck.get("base_id", deck.get("id", "")))
		var hide_buddy_until_exceeded = deck_logic_id in ["eugenia", "renea"] and deck.get("buddy_exceeds", false)
		buddy_character_card.visible = not hide_buddy_until_exceeded
		buddy_character_card.hide_focus()
		var buddy_card_id = deck['buddy_card']

		var loaded_buddy_image = await image_loader.get_card_image(
			deck['image_resources'][buddy_card_id]['url'], 0)
		var loaded_buddy_exceed_image = loaded_buddy_image
		if 'buddy_exceeds' in deck and deck['buddy_exceeds']:
			loaded_buddy_exceed_image = await image_loader.get_card_image(
				deck['image_resources'][buddy_card_id + '_exceeded']['url'], 0)
			if loaded_buddy_exceed_image == null:
				loaded_buddy_exceed_image = loaded_buddy_image
		buddy_character_card.set_image(loaded_buddy_image, loaded_buddy_exceed_image)
		await runtime_yield_for_loading_batch(1)
	elif 'buddy_cards' in deck:
		buddy_character_card.visible = true
		buddy_character_card.hide_focus()
		var default_buddy = deck['buddy_cards'][0]
		if 'buddy_card_graphic_override' in deck:
			default_buddy = deck['buddy_card_graphic_override'][0]
		created_buddy_cards.append(default_buddy)

		var loaded_buddy_image = await image_loader.get_card_image(
			deck['image_resources'][default_buddy]['url'], 0)
		var loaded_buddy_exceed_image = loaded_buddy_image
		if 'buddy_exceeds' in deck and deck['buddy_exceeds']:
			loaded_buddy_exceed_image = await image_loader.get_card_image(
				deck['image_resources'][default_buddy + '_exceeded']['url'], 0)
			if loaded_buddy_exceed_image == null:
				loaded_buddy_exceed_image = loaded_buddy_image
		buddy_character_card.set_image(loaded_buddy_image, loaded_buddy_exceed_image)
		await runtime_yield_for_loading_batch(1)

		# Add remaining buddies as extras.
		for i in range(1, deck['buddy_cards'].size()):
			var buddy_id = deck['buddy_cards'][i]
			if 'buddy_card_graphic_override' in deck:
				buddy_id = deck['buddy_card_graphic_override'][i]
			if buddy_id in created_buddy_cards:
				# Skip any that share graphics.
				continue
			created_buddy_cards.append(buddy_id)

			loaded_buddy_image = await image_loader.get_card_image(
				deck['image_resources'][buddy_id]['url'], 0)
			loaded_buddy_exceed_image = loaded_buddy_image
			if 'buddy_exceeds' in deck and deck['buddy_exceeds']:
				loaded_buddy_exceed_image = await image_loader.get_card_image(
					deck['image_resources'][buddy_id + '_exceeded']['url'], 0)
				if loaded_buddy_exceed_image == null:
					loaded_buddy_exceed_image = loaded_buddy_image
			buddy_character_card.set_extra_image(i, loaded_buddy_image, loaded_buddy_exceed_image)
			await runtime_yield_for_loading_batch(i + 1)
	else:
		buddy_character_card.visible = false

func finish_initialization():
	opponent_name_label.text = game_wrapper.get_player_name(Enums.PlayerId.PlayerId_Opponent)
	_emit_loading_status("准备卡牌")
	await spawn_all_cards()

func test_init():
	if Test_StartWithGauge:
		game_wrapper._test_add_to_gauge(4)
		var events = game_wrapper.poll_for_events()
		_handle_events(events)
		layout_player_hand(true)
		_update_buttons()

func first_run():
	move_character_to_arena_square($PlayerCharacter, game_wrapper.get_player_location(Enums.PlayerId.PlayerId_Player), true, Character.CharacterAnim.CharacterAnim_None)
	move_character_to_arena_square($OpponentCharacter, game_wrapper.get_player_location(Enums.PlayerId.PlayerId_Opponent), true, Character.CharacterAnim.CharacterAnim_None)
	cached_player_location = game_wrapper.get_player_location(Enums.PlayerId.PlayerId_Player)
	cached_opponent_location = game_wrapper.get_player_location(Enums.PlayerId.PlayerId_Opponent)
	await _prepare_initial_arena_visuals()
	update_arena_squares()
	_update_buttons()

	await finish_initialization()
	if _fast_forward_restored_game_if_needed():
		_sync_ui_state_after_restore()
	else:
		change_ui_state(UIState.UIState_WaitForGameServer)
	first_run_done = true
	load_characters_complete.emit()

func create_character_reference_card(exceeded : bool, zone, image_resources, deck_def = {}):
	var image_url = image_resources['character_default']['url']
	if exceeded:
		image_url = image_resources['character_exceeded']['url']
	var definition := _character_fallback_definition(deck_def, exceeded)
	var card_name := str(deck_def.get("display_name", "角色"))
	if exceeded:
		card_name += "（觉醒）"
	await _create_reference_card(image_url, card_name, zone, CardBase.CharacterCardReferenceId, definition)

func create_buddy_reference_card(buddy_id, exceeded : bool, zone, click_buddy_id, image_resources):
	var image_url = image_resources[buddy_id]['url']
	if exceeded:
		image_url = image_resources[buddy_id + '_exceeded']['url']
	await _create_reference_card(image_url, "Extra Card", zone, click_buddy_id)

func _create_reference_card(image_url : String, card_name : String, zone,
		card_id : int, definition = {}):
	var new_card : CardBase = CardBaseScene.instantiate()
	zone.add_child(new_card)

	var url_loaded_image = await image_loader.get_card_image(image_url, 0)

	new_card.initialize_card(
		card_id,
		url_loaded_image,
		"",
		false,
		card_name,
		"",
		definition
	)
	new_card.name = card_name
	new_card.raised_card.connect(on_card_raised)
	new_card.lowered_card.connect(on_card_lowered)

	new_card.set_card_and_focus(OffScreen, 0, CardBase.ReferenceCardScale)
	new_card.resting_scale = CardBase.ReferenceCardScale
	new_card.change_state(CardBase.CardState.CardState_Offscreen)
	new_card.flip_card_to_front(true)

	if card_id not in [CardBase.CharacterCardReferenceId, CardBase.BuddyCardReferenceId]:
		new_card.clicked_card.connect(on_card_clicked)

func _character_fallback_definition(deck_def: Dictionary, exceeded: bool) -> Dictionary:
	var definition := {
		"reference_label": "觉醒角色" if exceeded else "角色",
		"exceed_cost": deck_def.get("exceed_cost", 0),
		"effects": [],
	}
	if exceeded:
		if deck_def.has("on_exceed"):
			definition["effects"].append(deck_def["on_exceed"])
		definition["effects"].append_array(deck_def.get("exceed_ability_effects", []))
	else:
		definition["effects"].append_array(deck_def.get("ability_effects", []))
	return definition

func spawn_deck(deck_list,
		deck_card_zone,
		copy_zone,
		buddy_graphic_list,
		buddy_copy_zone,
		allow_click_buddy,
		set_aside_zone,
		is_opponent,
		image_resources):
	if is_opponent:
		_emit_loading_status("准备对手卡组")
	else:
		_emit_loading_status("准备玩家卡组")
	var card_db = game_wrapper.get_card_database()
	var card_back_url = image_resources['cardback']['url']
	var deck_owner_text = "对手" if is_opponent else "玩家"
	var current_card_index = 0
	var total_card_count = deck_list.size()

	# 与主菜单参考卡路径保持一致：先把整副牌的 atlas 元数据和索引注册进当前 image_loader，
	# 避免对局内 create_card 先于完整 atlas 信息落地，导致参考卡缓存成错误纹理。
	# Deck cards load their fronts when they enter a visible zone. Registering
	# every atlas index here materializes the whole deck during scene setup.

	for _ref_key in image_resources:
		var image_resource = image_resources[_ref_key]
		var atlas_data = get_normalized_deck_image_atlas_data(image_resource, _ref_key)
		var preload_problematic_normals = is_problematic_mobile_normal_atlas(
				atlas_data, _is_mobile_web_runtime())
		if preload_problematic_normals:
			_emit_loading_status("准备%s普通技图集" % deck_owner_text)
			image_loader.load_image_page(atlas_data)
			await image_loader.get_card_image(atlas_data["url"], 0, atlas_data)
		else:
			image_loader.load_image_page(atlas_data)

	for card in deck_list:
		var logic_card : GameCard = card_db.get_card(card.id)
		
		if logic_card.reference_only:
			continue
		current_card_index += 1
		_emit_loading_status("准备%s卡组 %d/%d" % [deck_owner_text, current_card_index, total_card_count])
		
		var new_card = await create_card(card.id, logic_card.definition, logic_card.get_image_url_index_data(), card_back_url,
			deck_card_zone, is_opponent, logic_card.definition['display_name'], logic_card.definition['boost']['display_name'])
		if observer_mode and not replay_mode:
			new_card.skip_flip_when_drawing = true
		if logic_card.set_aside:
			reparent_to_zone(new_card, set_aside_zone)
		new_card.set_card_and_focus(OffScreen, 0, null)
		await runtime_yield_for_loading_batch(current_card_index)

	# Full deck references are built on first use. Keep only the small extra-card
	# set available during startup so hidden reference cards do not load both decks.
	_clear_node_children(copy_zone)
	if not buddy_graphic_list.is_empty():
		_clear_node_children(buddy_copy_zone)
	var created_buddy_cards = []
	var buddy_card_id_links = {}
	if allow_click_buddy:
		for deck_card in deck_list:
			var buddy_logic_card : GameCard = card_db.get_card(deck_card.id)
			if buddy_logic_card.definition['id'] in buddy_graphic_list:
				buddy_card_id_links[buddy_logic_card.definition['id']] = deck_card.id
	for buddy_id in buddy_graphic_list:
		if buddy_id in created_buddy_cards:
			continue
		created_buddy_cards.append(buddy_id)
		var buddy_card_id = buddy_card_id_links.get(buddy_id, CardBase.BuddyCardReferenceId)
		await create_buddy_reference_card(
			buddy_id,
			false,
			buddy_copy_zone,
			buddy_card_id,
			image_resources)
		await runtime_yield_for_loading_batch(created_buddy_cards.size())

func _clear_node_children(node : Node):
	while node.get_child_count() > 0:
		var child = node.get_child(0)
		node.remove_child(child)
		child.queue_free()

func rebuild_reference_copy_zone(deck_list,
		copy_zone,
		buddy_graphic_list,
		buddy_copy_zone,
		allow_click_buddy,
		is_opponent,
		image_resources,
		deck_def = {},
		deck_owner_text : String = ""):
	_clear_node_children(copy_zone)
	if not buddy_graphic_list.is_empty():
		_clear_node_children(buddy_copy_zone)

	await create_character_reference_card(false, copy_zone, image_resources, deck_def)
	await runtime_yield_for_loading_batch(1)
	await create_character_reference_card(true, copy_zone, image_resources, deck_def)
	await runtime_yield_for_loading_batch(2)

	if deck_owner_text != "":
		_emit_loading_status("准备%s参考卡" % deck_owner_text)

	var previous_def_id = ""
	var buddy_card_id_links = {}
	var reference_card_count = 0
	var card_back_url = image_resources['cardback']['url']
	var card_db = game_wrapper.get_card_database()
	for card in deck_list:
		var logic_card : GameCard = card_db.get_card(card.id)

		# Associates clickable buddy cards with deck cards;
		#   only accounts for one copy, ignored if allow_click_buddy is false
		if logic_card.definition['id'] in buddy_graphic_list:
			buddy_card_id_links[logic_card.definition['id']] = card.id

		if logic_card.hide_from_reference:
			continue
		if previous_def_id != logic_card.definition['id'] or logic_card.reference_only:
			var copy_card = await create_card(card.id + ReferenceScreenIdRangeStart, logic_card.definition,
				logic_card.get_image_url_index_data(), card_back_url, copy_zone, is_opponent,
				logic_card.definition['display_name'], logic_card.definition['boost']['display_name'])
			if logic_card.reference_only:
				copy_card.hide_count = true
			copy_card.set_card_and_focus(OffScreen, 0, CardBase.ReferenceCardScale)
			copy_card.resting_scale = CardBase.ReferenceCardScale
			copy_card.change_state(CardBase.CardState.CardState_Offscreen)
			copy_card.flip_card_to_front(true)
			previous_def_id = card.definition['id']
			reference_card_count += 1
			await runtime_yield_for_loading_batch(reference_card_count)

	# Setup buddy if they have one.
	var created_buddy_cards = []
	if buddy_graphic_list:
		for buddy_id in buddy_graphic_list:
			if buddy_id in created_buddy_cards:
				# Skip any that share graphics.
				continue
			created_buddy_cards.append(buddy_id)
			var buddy_card_id = CardBase.BuddyCardReferenceId
			if allow_click_buddy and buddy_card_id_links:
				buddy_card_id = buddy_card_id_links[buddy_id]
			await create_buddy_reference_card(buddy_id, false, buddy_copy_zone, buddy_card_id, image_resources)
			await runtime_yield_for_loading_batch(created_buddy_cards.size())

func spawn_damage_popup(value:String, notice_player : Enums.PlayerId):
	if restore_fast_forwarding:
		return
	if _should_skip_low_priority_visuals():
		return
	var popup = get_damage_popup()
	var pos = get_notice_position(notice_player)
	pos.y -= NoticeOffsetY
	var height = NoticeOffsetY
	add_child(popup)
	popup.set_values_and_animate(value, pos, height)

func get_damage_popup() -> DamagePopup:
	if damage_popup_pool.size() > 0:
		return damage_popup_pool.pop_front()
	else:
		var new_popup = damage_popup_template.instantiate()
		new_popup.tree_exiting.connect(
			func():damage_popup_pool.append(new_popup))
		return new_popup

func spawn_emote(
	player_id : Enums.PlayerId,
	is_image_emote : bool,
	emote : String
):
	if restore_fast_forwarding:
		return
	if _should_skip_low_priority_visuals():
		return
	var emote_display = opponent_emote
	if player_id == Enums.PlayerId.PlayerId_Player:
		emote_display = player_emote
	var pos = get_notice_position(player_id)
	pos.y -= NoticeOffsetY
	if game_wrapper.get_player_location(player_id) > 5:
		pos.x -= 50
	var height = NoticeOffsetY
	emote_display.play_emote(is_image_emote, emote, pos, height)

func spawn_all_cards():
	_emit_loading_status("准备卡牌资源")
	var player_buddy_graphics = []
	var opponent_buddy_graphics = []
	for deck_graphic_pair in [[player_deck, player_buddy_graphics], [opponent_deck, opponent_buddy_graphics]]:
		var deck = deck_graphic_pair[0]
		var graphic_list = deck_graphic_pair[1]
		if 'hide_buddy_reference' in deck and deck['hide_buddy_reference']:
			continue
		elif 'buddy_card' in deck:
			graphic_list.append(deck['buddy_card'])
			if 'buddy_exceeds' in deck and deck['buddy_exceeds']:
				graphic_list.append(deck['buddy_card'] + "_exceeded")
		elif 'buddy_card_graphic_override' in deck:
			for buddy_card in deck['buddy_card_graphic_override']:
				graphic_list.append(buddy_card)
		elif 'buddy_cards' in deck:
			for buddy_card in deck['buddy_cards']:
				graphic_list.append(buddy_card)
				if 'buddy_exceeds' in deck and deck['buddy_exceeds']:
					graphic_list.append(buddy_card + "_exceeded")

	var player_can_click_buddy = player_deck.get("link_extra_cards_to_buddies", false)
	var opponent_can_click_buddy = opponent_deck.get("link_extra_cards_to_buddies", false)

	var player_image_resources = player_deck['image_resources']
	var opponent_image_resources = opponent_deck['image_resources']

	await spawn_deck(game_wrapper.get_player_deck_list(Enums.PlayerId.PlayerId_Player), $AllCards/PlayerDeck, $AllCards/PlayerAllCopy,
		player_buddy_graphics, $AllCards/PlayerBuddyCopy, player_can_click_buddy, $AllCards/PlayerSetAside, false, player_image_resources)
	await spawn_deck(game_wrapper.get_player_deck_list(Enums.PlayerId.PlayerId_Opponent), $AllCards/OpponentDeck, $AllCards/OpponentAllCopy,
		opponent_buddy_graphics, $AllCards/OpponentBuddyCopy, opponent_can_click_buddy, $AllCards/OpponentSetAside, true, opponent_image_resources)
	_emit_loading_status("准备完成")

func get_arena_location_button(arena_location):
	var target_square = arena_layout.get_child(arena_location - 1)
	var button = target_square.get_node("Button")
	return button

func get_arena_square_center(arena_location : int) -> Vector2:
	var separation = arena_layout.get_theme_constant("separation")
	var total_width = 0.0
	for index in range(arena_layout.get_child_count()):
		var square = arena_layout.get_child(index)
		var square_width = square.size.x if square.size.x > 0 else square.custom_minimum_size.x
		total_width += square_width
		if index > 0:
			total_width += separation

	var target_square = arena_layout.get_child(arena_location - 1)
	var target_width = target_square.size.x if target_square.size.x > 0 else target_square.custom_minimum_size.x
	var target_height = target_square.size.y if target_square.size.y > 0 else target_square.custom_minimum_size.y
	var start_x = arena_layout.global_position.x + maxf((arena_layout.size.x - total_width) / 2.0, 0.0)
	var center_x = start_x + target_width / 2.0 + (arena_location - 1) * (target_width + separation)
	var center_y = arena_layout.global_position.y + target_height / 2.0
	return Vector2(center_x, center_y)

func move_character_to_arena_square(character,
		arena_location,
		immediate: bool,
		move_anim : Character.CharacterAnim,
		buddy_offset : int = 0
):
	if restore_fast_forwarding:
		immediate = true
	var target_position = get_arena_square_center(arena_location)
	var offset_y = $ArenaNode/RowButtons.position.y
	target_position.y -= character.get_size().y * character.scale.y / 2 + offset_y + character.vertical_offset
	if buddy_offset != 0:
		target_position.x += buddy_offset * (character.get_size().x * character.scale.x /4) + character.horizontal_offset_buddy
	if character.use_buddy_extra_offset:
		# Adjust the buddy to account for having multiple of the same buddy.
		target_position.x += buddy_offset * 20
		target_position.y += 15
	target_position = character.get_parent().to_local(target_position)
	if immediate:
		character.snap_to(target_position)
		update_character_facing()
	else:
		character.move_to(target_position, move_anim)

func update_character_facing():
	var character = $PlayerCharacter
	var other_character = $OpponentCharacter
	var to_left = character.position.x < other_character.position.x
	character.set_facing(to_left)
	other_character.set_facing(not to_left)

	for buddy in player_buddies:
		if buddy.visible:
			to_left = buddy.position.x < other_character.position.x
			buddy.set_facing(to_left)
	for buddy in opponent_buddies:
		if buddy.visible:
			to_left = buddy.position.x < character.position.x
			buddy.set_facing(to_left)

func _finish_character_movement_animations():
	$PlayerCharacter.finish_movement()
	$OpponentCharacter.finish_movement()
	for buddy in player_buddies:
		buddy.finish_movement()
	for buddy in opponent_buddies:
		buddy.finish_movement()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if exiting:
		return
	if not first_run_done:
		if not first_run_in_progress:
			if not setup_characters_complete:
				# Wait for the characters to finish loading.
				return
			first_run_in_progress = true
			await first_run()
		return
	_update_runtime_frame_health(delta)
	_update_network_reconnect_pause()
	if hold_match_entry_processing:
		$OpponentDeck/ThinkingIndicator.visible = false
		return
	if network_reconnect_paused:
		$OpponentDeck/ThinkingIndicator.visible = false
		return
	if ui_state == UIState.UIState_PlayingAnimation:
		remaining_delay -= delta
		if remaining_delay <= 0:
			# Animation is finished playing.
			_finish_character_movement_animations()
			update_character_facing()
			remaining_delay = 0
			if len(events_to_process) > 0:
				var temp_events = events_to_process
				events_to_process = []
				_handle_events(temp_events)
			else:
				change_ui_state(previous_ui_state, previous_ui_sub_state)
	else:
		var events = game_wrapper.poll_for_events()
		if events.size() > 0:
			_handle_events(events)
			_refresh_combat_log_if_visible()
		elif ui_state == UIState.UIState_WaitForGameServer:
			var game_state = game_wrapper.get_game_state()
			if game_state == Enums.GameState.GameState_PickAction:
				if game_wrapper.get_active_player() == Enums.PlayerId.PlayerId_Player and not observer_mode:
					change_ui_state(UIState.UIState_PickTurnAction, UISubState.UISubState_None)
				else:
					change_ui_state(UIState.UIState_WaitingOnOpponent, UISubState.UISubState_None)
		elif ui_state == UIState.UIState_WaitingOnOpponent:
			# Advance the AI game automatically.
			_on_ai_move_button_pressed()

		if events.size() == 0 and observer_live:
			game_wrapper.observer_process_next_message_from_queue()

	# Update opponent thinking spinner
	if _rotation_layout_in_progress:
		$OpponentDeck/ThinkingIndicator.visible = false
	elif ui_state == UIState.UIState_WaitingOnOpponent or ui_state == UIState.UIState_WaitForGameServer:
		if not $OpponentDeck/ThinkingIndicator.visible and show_thinking_spinner_in < 0:
			# Start the countdown
			show_thinking_spinner_in = ThinkingSpinnerWaitBeforeShowTime
		else:
			show_thinking_spinner_in -= delta
			if show_thinking_spinner_in < 0:
				$OpponentDeck/ThinkingIndicator.visible = true
				$OpponentDeck/ThinkingIndicator.radial_initial_angle += delta * 360
	else:
		$OpponentDeck/ThinkingIndicator.visible = false

	# TODO _process_auto_thinking_emote(delta)

	_process_clock(delta)

# TODO func _process_auto_thinking_emote(delta):
# TODO 	if not _should_track_auto_thinking_emote():
# TODO 		_reset_auto_thinking_emote_timer()
# TODO 		return
# TODO
# TODO 	auto_thinking_emote_elapsed += delta
# TODO 	if auto_thinking_emote_elapsed < AutoThinkingEmoteDelay:
# TODO 		return
# TODO
# TODO 	if game_wrapper.submit_emote(Enums.PlayerId.PlayerId_Player, false, AutoThinkingEmoteText):
# TODO 		_note_visible_turn_progress()
# TODO
# TODO func _should_track_auto_thinking_emote() -> bool:
# TODO 	if observer_mode or replay_mode or network_reconnect_paused:
# TODO 		return false
# TODO 	if game_wrapper.get_active_player() != Enums.PlayerId.PlayerId_Player:
# TODO 		return false
# TODO 	return _is_player_interaction_ui_state(ui_state)

func _is_player_interaction_ui_state(state : int) -> bool:
	return state in [UIState.UIState_PickTurnAction, UIState.UIState_MakeChoice, UIState.UIState_SelectCards, UIState.UIState_SelectArenaLocation]

# TODO func _note_visible_turn_progress():
# TODO 	auto_thinking_emote_elapsed = 0
# TODO
# TODO func _reset_auto_thinking_emote_timer():
# TODO 	auto_thinking_emote_elapsed = 0

func _process_clock(delta):
	if network_reconnect_paused:
		return
	if clock_delay_remaining > 0:
		clock_delay_remaining -= delta
		if clock_delay_remaining <= 0:
			# Courtesy delay is over, assign the clock user.
			if current_clock_user == Enums.PlayerId.PlayerId_Unassigned:
				set_player_as_clock_user(game_wrapper.get_priority_player())

	if current_clock_user != Enums.PlayerId.PlayerId_Unassigned and ui_state != UIState.UIState_GameOver:
		if events_to_process.size() > 0:
			# Don't count down the clock while there are events to process.
			player_notified_of_clock = false
			return
		elif is_mulligan_done():
			if current_clock_user == Enums.PlayerId.PlayerId_Player:
				player_clock_remaining -= delta
				if new_clock_user_assigned:
					new_clock_user_assigned = false
					if enforce_timer and player_clock_remaining < minimum_time_per_choice:
						player_clock_remaining = minimum_time_per_choice
				if not player_notified_of_clock:
					player_notified_of_clock = true
					if GlobalSettings.GameSoundsEnabled and not observer_mode:
						turnstart_audio.play()
			elif current_clock_user == Enums.PlayerId.PlayerId_Opponent:
				if new_clock_user_assigned:
					new_clock_user_assigned = false
					if enforce_timer and opponent_clock_remaining < minimum_time_per_choice:
						opponent_clock_remaining = minimum_time_per_choice
				opponent_clock_remaining -= delta
				player_notified_of_clock = false
		else:
			# Mulligan is special in that both clocks count
			if not game_wrapper.get_player_mulligan_complete(Enums.PlayerId.PlayerId_Player):
				player_clock_remaining -= delta
			if not game_wrapper.get_player_mulligan_complete(Enums.PlayerId.PlayerId_Opponent):
				opponent_clock_remaining -= delta
		_update_clocks()

func is_mulligan_done():
	return game_wrapper.get_player_mulligan_complete(Enums.PlayerId.PlayerId_Player) and game_wrapper.get_player_mulligan_complete(Enums.PlayerId.PlayerId_Opponent)

func _update_clocks():
	if game_wrapper.is_ai_game(): return
	if observer_mode: return
	$PlayerLife.set_clock(player_clock_remaining, enforce_timer and player_clock_remaining <= minimum_time_per_choice)
	$OpponentLife.set_clock(opponent_clock_remaining, enforce_timer and opponent_clock_remaining <= minimum_time_per_choice)
	if enforce_timer and player_clock_remaining <= 0:
		game_wrapper.do_clock_ran_out()

func _on_reconnect_state_changed(_state : Dictionary):
	_update_network_reconnect_pause()
	_update_buttons()

func _on_waiting_for_opponent_reconnect_changed(_is_waiting : bool, _seconds : int):
	_update_network_reconnect_pause()
	_update_buttons()

func _update_network_reconnect_pause():
	network_reconnect_paused = not game_wrapper.is_ai_game() and not replay_mode and (NetworkManager.is_reconnect_active() or NetworkManager.is_waiting_for_opponent_reconnect())
	_update_surrender_button_visibility()

func begin_delay(delay : float, remaining_events : Array):
	if ui_state != UIState.UIState_PlayingAnimation:
		previous_ui_state = ui_state
		previous_ui_sub_state = ui_sub_state
	change_ui_state(UIState.UIState_PlayingAnimation, UISubState.UISubState_None)
	remaining_delay = get_runtime_animation_delay(
		delay,
		remaining_events.size(),
		_is_web_runtime(),
		_should_apply_web_backlog_judge())
	events_to_process = remaining_events

static func get_runtime_animation_delay(
		delay : float,
		pending_event_count : int,
		web_runtime : bool,
		enable_backlog_judge : bool = true) -> float:
	if not web_runtime:
		return delay
	var scaled_delay = delay / GlobalSettings.get_current_web_animation_speed()
	if not enable_backlog_judge or pending_event_count <= WebRuntimeAnimationBacklogThreshold:
		return scaled_delay
	var compressed_delay = maxf(WebRuntimeAnimationMinimumDelay, delay * WebRuntimeAnimationBacklogScale)
	return compressed_delay / GlobalSettings.get_current_web_animation_speed()

static func get_runtime_backlog_level(pending_event_count : int, web_runtime : bool) -> int:
	if not web_runtime or pending_event_count < WebRuntimeBacklogThresholdModerate:
		return RuntimeBacklogLevel.RuntimeBacklogLevel_None
	if pending_event_count >= WebRuntimeBacklogThresholdSevere:
		return RuntimeBacklogLevel.RuntimeBacklogLevel_Severe
	return RuntimeBacklogLevel.RuntimeBacklogLevel_Moderate

static func get_runtime_event_budget(pending_event_count : int, web_runtime : bool) -> int:
	match get_runtime_backlog_level(pending_event_count, web_runtime):
		RuntimeBacklogLevel.RuntimeBacklogLevel_Moderate:
			return WebRuntimeEventBudgetModerate
		RuntimeBacklogLevel.RuntimeBacklogLevel_Severe:
			return WebRuntimeEventBudgetSevere
		_:
			return WebRuntimeEventBudgetUnlimited

static func get_runtime_frame_pressure_level(slow_frame_count : int, web_runtime : bool) -> int:
	if not web_runtime:
		return RuntimeFramePressureLevel.RuntimeFramePressureLevel_None
	if slow_frame_count >= WebRuntimeSlowFrameSevereCount:
		return RuntimeFramePressureLevel.RuntimeFramePressureLevel_Severe
	if slow_frame_count >= WebRuntimeSlowFrameWarningCount:
		return RuntimeFramePressureLevel.RuntimeFramePressureLevel_Warning
	return RuntimeFramePressureLevel.RuntimeFramePressureLevel_None

static func get_runtime_backlog_level_name(level : int) -> String:
	match level:
		RuntimeBacklogLevel.RuntimeBacklogLevel_Moderate:
			return "Moderate"
		RuntimeBacklogLevel.RuntimeBacklogLevel_Severe:
			return "Severe"
		_:
			return "None"

static func get_runtime_frame_pressure_level_name(level : int) -> String:
	match level:
		RuntimeFramePressureLevel.RuntimeFramePressureLevel_Warning:
			return "Warning"
		RuntimeFramePressureLevel.RuntimeFramePressureLevel_Severe:
			return "Severe"
		_:
			return "None"

static func get_runtime_health_state_name(state : int) -> String:
	match state:
		RuntimeHealthState.RuntimeHealthState_Warning:
			return "Warning"
		RuntimeHealthState.RuntimeHealthState_Backlogged:
			return "Backlogged"
		RuntimeHealthState.RuntimeHealthState_Recovery:
			return "Recovery"
		_:
			return "Healthy"

static func get_runtime_event_budget_name(budget : int) -> String:
	if budget == WebRuntimeEventBudgetUnlimited:
		return "Unlimited"
	return str(budget)

static func get_runtime_health_debug_color(state : int) -> Color:
	match state:
		RuntimeHealthState.RuntimeHealthState_Warning:
			return Color("ffd54f")
		RuntimeHealthState.RuntimeHealthState_Backlogged:
			return Color("ff8a65")
		RuntimeHealthState.RuntimeHealthState_Recovery:
			return Color("80deea")
		_:
			return Color("c5e1a5")

static func get_runtime_health_state(current_state : int, pending_event_count : int, slow_frame_count : int, stable_frame_count : int, web_runtime : bool) -> int:
	if not web_runtime:
		return RuntimeHealthState.RuntimeHealthState_Healthy
	var backlog_level = get_runtime_backlog_level(pending_event_count, true)
	var frame_pressure_level = get_runtime_frame_pressure_level(slow_frame_count, true)
	var pressure_level = maxi(backlog_level, frame_pressure_level)
	if pressure_level >= RuntimeBacklogLevel.RuntimeBacklogLevel_Severe:
		return RuntimeHealthState.RuntimeHealthState_Backlogged
	if pressure_level >= RuntimeBacklogLevel.RuntimeBacklogLevel_Moderate:
		return RuntimeHealthState.RuntimeHealthState_Warning
	if current_state != RuntimeHealthState.RuntimeHealthState_Healthy:
		if stable_frame_count < WebRuntimeRecoveryStableFrames:
			return RuntimeHealthState.RuntimeHealthState_Recovery
	return RuntimeHealthState.RuntimeHealthState_Healthy

static func get_runtime_event_budget_for_health_state(health_state : int, enable_backlog_judge : bool = true) -> int:
	if not enable_backlog_judge:
		return WebRuntimeEventBudgetUnlimited
	match health_state:
		RuntimeHealthState.RuntimeHealthState_Backlogged:
			return WebRuntimeEventBudgetSevere
		RuntimeHealthState.RuntimeHealthState_Warning, RuntimeHealthState.RuntimeHealthState_Recovery:
			return WebRuntimeEventBudgetModerate
		_:
			return WebRuntimeEventBudgetUnlimited

func _should_apply_web_backlog_judge() -> bool:
	return _is_web_runtime() and GlobalSettings.should_skip_web_backlog_by_health()

static func should_yield_runtime_batch(processed_count : int, batch_size : int, web_runtime : bool) -> bool:
	return web_runtime and batch_size > 0 and processed_count > 0 and processed_count % batch_size == 0

static func get_runtime_load_yield_batch_size(mobile_web_runtime : bool) -> int:
	return MobileWebRuntimeLoadYieldBatchSize if mobile_web_runtime else WebRuntimeLoadYieldBatchSize

func runtime_yield_for_loading_batch(processed_count : int):
	var batch_size = get_runtime_load_yield_batch_size(_is_mobile_web_runtime())
	if should_yield_runtime_batch(processed_count, batch_size, _is_web_runtime()):
		await get_tree().process_frame

func _update_runtime_frame_health(delta : float):
	runtime_last_frame_delta = delta
	if not _is_web_runtime() or restore_fast_forwarding:
		runtime_pending_event_pressure_count = 0
		runtime_health_state = RuntimeHealthState.RuntimeHealthState_Healthy
		runtime_slow_frame_count = 0
		runtime_stable_frame_count = WebRuntimeRecoveryStableFrames
		_request_runtime_health_debug_overlay_refresh()
		return
	if delta >= WebRuntimeSlowFrameSevereDelta:
		runtime_slow_frame_count += 2
		runtime_stable_frame_count = 0
	elif delta >= WebRuntimeSlowFrameWarningDelta:
		runtime_slow_frame_count += 1
		runtime_stable_frame_count = 0
	else:
		runtime_slow_frame_count = maxi(0, runtime_slow_frame_count - 1)
		runtime_stable_frame_count += 1
	_update_runtime_health_state(events_to_process.size())

func _update_runtime_health_state(pending_event_count : int):
	runtime_pending_event_pressure_count = pending_event_count
	if restore_fast_forwarding:
		runtime_backlog_level = RuntimeBacklogLevel.RuntimeBacklogLevel_None
		runtime_health_state = RuntimeHealthState.RuntimeHealthState_Healthy
		_request_runtime_health_debug_overlay_refresh()
		return
	runtime_backlog_level = get_runtime_backlog_level(pending_event_count, _is_web_runtime())
	runtime_health_state = get_runtime_health_state(runtime_health_state, pending_event_count, runtime_slow_frame_count, runtime_stable_frame_count, _is_web_runtime())
	_request_runtime_health_debug_overlay_refresh()

func _begin_runtime_event_batch(batch_event_count : int):
	runtime_event_batch_in_progress = true
	_update_runtime_health_state(batch_event_count + events_to_process.size())

func _end_runtime_event_batch():
	_flush_deferred_ui_updates()
	runtime_event_batch_in_progress = false
	_update_runtime_health_state(events_to_process.size())

func _should_defer_runtime_ui_refreshes() -> bool:
	return _is_web_runtime() \
		and GlobalSettings.should_skip_web_backlog_by_health() \
		and runtime_event_batch_in_progress \
		and runtime_health_state != RuntimeHealthState.RuntimeHealthState_Healthy

func _should_skip_low_priority_visuals() -> bool:
	if _rotation_layout_in_progress:
		return true
	if not _is_web_runtime() or restore_fast_forwarding:
		return false
	if not GlobalSettings.should_skip_web_backlog_by_health():
		return false
	return runtime_health_state == RuntimeHealthState.RuntimeHealthState_Backlogged

func _should_skip_bonus_label_visuals() -> bool:
	if not _is_web_runtime() or restore_fast_forwarding:
		return false
	if not GlobalSettings.should_skip_web_backlog_by_health():
		return false
	return runtime_health_state != RuntimeHealthState.RuntimeHealthState_Healthy

func _should_show_runtime_health_debug_overlay() -> bool:
	return ShowRuntimeHealthDebugOverlay and _is_web_runtime() and runtime_health_debug_overlay_enabled

func _update_runtime_health_debug_toggle_button():
	if runtime_health_debug_toggle_button == null:
		return
	runtime_health_debug_toggle_button.visible = ShowRuntimeHealthDebugOverlay and _is_web_runtime()
	runtime_health_debug_toggle_button.text = "关闭\n性能窗" if runtime_health_debug_overlay_enabled else "显示\n性能窗"

func _request_runtime_health_debug_overlay_refresh():
	if not _should_show_runtime_health_debug_overlay():
		return
	_refresh_runtime_health_debug_overlay()

func _refresh_runtime_health_debug_overlay():
	if runtime_health_debug_panel == null or runtime_health_debug_label == null:
		return
	var should_show = _should_show_runtime_health_debug_overlay()
	runtime_health_debug_panel.visible = should_show
	_update_runtime_health_debug_toggle_button()
	if not should_show:
		return
	var frame_pressure_level = get_runtime_frame_pressure_level(runtime_slow_frame_count, true)
	var event_budget = get_runtime_event_budget_for_health_state(runtime_health_state, _should_apply_web_backlog_judge())
	runtime_health_debug_label.modulate = get_runtime_health_debug_color(runtime_health_state)
	runtime_health_debug_label.text = "运行时健康度\n状态: %s\n事件压力: %s (%d)\n帧压力: %s (%.1fms)\n%s\n慢帧计数: %d\n稳定帧: %d/%d\n事件预算: %s\n批处理中: %s\n延迟队列: %d\n快进重建: %s" % [
		get_runtime_health_state_name(runtime_health_state),
		get_runtime_backlog_level_name(runtime_backlog_level),
		runtime_pending_event_pressure_count,
		get_runtime_frame_pressure_level_name(frame_pressure_level),
		runtime_last_frame_delta * 1000.0,
		MobileResourceBudget.get_debug_text(),
		runtime_slow_frame_count,
		runtime_stable_frame_count,
		WebRuntimeRecoveryStableFrames,
		get_runtime_event_budget_name(event_budget),
		"是" if runtime_event_batch_in_progress else "否",
		events_to_process.size(),
		"是" if restore_fast_forwarding else "否",
	]

func _on_runtime_health_debug_toggle_button_pressed():
	runtime_health_debug_overlay_enabled = not runtime_health_debug_overlay_enabled
	if not runtime_health_debug_overlay_enabled:
		if runtime_health_debug_panel:
			runtime_health_debug_panel.visible = false
		_update_runtime_health_debug_toggle_button()
		return
	_refresh_runtime_health_debug_overlay()

func _request_layout_player_hand(is_player : bool):
	if is_player:
		deferred_player_hand_layout = true
	else:
		deferred_opponent_hand_layout = true
	deferred_card_count_refresh = true

func _flush_deferred_ui_updates():
	var refresh_player_hand = deferred_player_hand_layout
	var refresh_opponent_hand = deferred_opponent_hand_layout
	var refresh_card_counts = deferred_card_count_refresh
	deferred_player_hand_layout = false
	deferred_opponent_hand_layout = false
	deferred_card_count_refresh = false
	if refresh_player_hand:
		_layout_player_hand_now(true)
	if refresh_opponent_hand:
		_layout_player_hand_now(false)
	if refresh_card_counts:
		_update_card_counts_now()

func _is_web_runtime() -> bool:
	return OS.has_feature("web")

static func is_problematic_mobile_normal_atlas(
		image_data, is_mobile_web_runtime : bool, require_first_three : bool = false) -> bool:
	var matches_atlas = is_mobile_web_runtime \
			and image_data \
			and image_data.get("season", 0) in [1, 6] \
			and image_data.get("image_name", "") == "normals"
	return matches_atlas and (
			not require_first_three or image_data.get("index", -1) in [0, 1, 2])

static func get_normalized_deck_image_atlas_data(image_resource : Dictionary, image_name : String) -> Dictionary:
	var atlas_data = image_resource.duplicate(true)
	atlas_data["image_name"] = image_name
	if image_name == "normals":
		atlas_data["force_cropped_textures"] = true
	return atlas_data

func _refresh_problematic_reference_normals(image_resources : Dictionary):
	if not _is_mobile_web_runtime() or not image_resources.has("normals"):
		return
	var atlas_data = get_normalized_deck_image_atlas_data(image_resources["normals"], "normals")
	if not is_problematic_mobile_normal_atlas(atlas_data, true):
		return
	image_loader.invalidate_loaded_image(atlas_data["url"])
	image_loader.load_image_page(atlas_data)
	await image_loader.get_card_image(atlas_data["url"], 0, atlas_data)

func get_discard_location(discard_node):
	var discard_pos = discard_node.global_position + discard_node.size * discard_node.scale /2
	return discard_pos

func discard_card(card, discard_node, new_parent, is_player : bool, from_top : int):
	var discard_pos = get_discard_location(discard_node)
	# Make sure the card is faceup.
	make_card_revealed(card)
	card.discard_to(discard_pos, CardBase.CardState.CardState_Discarded)
	reparent_to_zone(card, new_parent, from_top)
	layout_player_hand(is_player)

func get_deck_button(is_player : bool):
	if is_player:
		return $PlayerDeck/DeckButton
	else:
		return $OpponentDeck/DeckButton

func get_deck_button_position(is_player : bool):
	var button = get_deck_button(is_player)
	var deck_position = button.global_position + (button.size * button.scale)/2
	return deck_position

func get_stored_card_position(is_player : bool):
	var stored_zone = player_bonus_panel
	if not is_player:
		stored_zone = opponent_bonus_panel
	return stored_zone.global_position + (stored_zone.size * stored_zone.scale)/2

func get_hand_zone(is_player : bool):
	if is_player:
		return $AllCards/PlayerHand
	else:
		return $AllCards/OpponentHand

func draw_card(card_id : int, is_player : bool):
	var card = add_card_to_hand(card_id, is_player)
	_load_card_front_if_needed(card)

	# Start the card at the deck.
	card.set_card_and_focus(get_deck_button_position(is_player), null, null)

	layout_player_hand(is_player)

func update_card_counts():
	if _should_defer_runtime_ui_refreshes():
		deferred_card_count_refresh = true
		return
	_update_card_counts_now()

func _update_card_counts_now():
	$OpponentHand/OpponentHandBox/OpponentNumCards.text = str(game_wrapper.get_player_hand_size(Enums.PlayerId.PlayerId_Opponent))

	$PlayerLife.set_deck_size(game_wrapper.get_player_deck_size(Enums.PlayerId.PlayerId_Player))
	$OpponentLife.set_deck_size(game_wrapper.get_player_deck_size(Enums.PlayerId.PlayerId_Opponent))

	$PlayerLife.set_discard_size(game_wrapper.get_player_discards_size(Enums.PlayerId.PlayerId_Player), game_wrapper.get_player_reshuffle_remaining(Enums.PlayerId.PlayerId_Player))
	$OpponentLife.set_discard_size(game_wrapper.get_player_discards_size(Enums.PlayerId.PlayerId_Opponent), game_wrapper.get_player_reshuffle_remaining(Enums.PlayerId.PlayerId_Opponent))

	$PlayerZones/PlayerGauge.set_details($AllCards/PlayerGauge.get_child_count())
	$OpponentZones/OpponentGauge.set_details($AllCards/OpponentGauge.get_child_count())
	$PlayerZones/PlayerBleach.set_details(game_wrapper.get_player_bleach_size(Enums.PlayerId.PlayerId_Player))
	$OpponentZones/OpponentBleach.set_details(game_wrapper.get_player_bleach_size(Enums.PlayerId.PlayerId_Opponent))

	$PlayerZones/PlayerSealed.set_details(game_wrapper.get_player_sealed_size(Enums.PlayerId.PlayerId_Player))
	$OpponentZones/OpponentSealed.set_details(game_wrapper.get_player_sealed_size(Enums.PlayerId.PlayerId_Opponent))

	$PlayerZones/PlayerOverdrive.set_details(game_wrapper.get_player_overdrive_size(Enums.PlayerId.PlayerId_Player))
	$OpponentZones/OpponentOverdrive.set_details(game_wrapper.get_player_overdrive_size(Enums.PlayerId.PlayerId_Opponent))

	$PlayerZones/PlayerOverdrive.visible = is_player_overdrive_visible(Enums.PlayerId.PlayerId_Player)
	$OpponentZones/OpponentOverdrive.visible = is_player_overdrive_visible(Enums.PlayerId.PlayerId_Opponent)

func get_card_node_name(id):
	return "Card_" + str(id)

func create_card(id, card_def, image_url_index, cardback_url, parent, is_opponent : bool, card_name, boost_name) -> CardBase:
	var new_card : CardBase = CardBaseScene.instantiate()
	parent.add_child(new_card)
	var strike_cost = card_def['gauge_cost']
	if strike_cost == 0:
		strike_cost = card_def['force_cost']

	var url_loaded_image = null
	var is_hidden_deck_card = parent in [$AllCards/PlayerDeck, $AllCards/OpponentDeck]
	var defer_problematic_normal = is_hidden_deck_card and is_problematic_mobile_normal_atlas(
			image_url_index, _is_mobile_web_runtime(), true)
	var load_front_image = not defer_problematic_normal and (
			_is_mobile_web_runtime() or not is_hidden_deck_card)
	if image_url_index and load_front_image:
		url_loaded_image = await image_loader.get_card_image(image_url_index["url"], image_url_index["index"], image_url_index)
	var url_loaded_cardback = null
	if cardback_url:
		url_loaded_cardback = await image_loader.get_card_image(cardback_url, 0)

	new_card.initialize_card(
		id,
		url_loaded_image,
		url_loaded_cardback,
		is_opponent,
		card_name,
		boost_name
	)
	if image_url_index:
		new_card.set_meta("image_url_index", image_url_index.duplicate(true))

	new_card.name = get_card_node_name(id)
	new_card.raised_card.connect(on_card_raised)
	new_card.lowered_card.connect(on_card_lowered)
	new_card.clicked_card.connect(on_card_clicked)
	return new_card

func add_card_to_hand(id : int, is_player : bool) -> CardBase:
	var card = find_card_on_board(id)
	card.finish_animation_immediately()
	if not is_player:
		if replay_mode and GlobalSettings.ReplayShowOpponentHand:
			pass
		else:
			card.manual_flip_needed = true
	var hand_zone = get_hand_zone(is_player)
	card.get_parent().remove_child(card)
	hand_zone.add_child(card)
	hand_zone.move_child(card, hand_zone.get_child_count() - 1)
	return card

func _load_card_front_if_needed(card : CardBase):
	if card == null or card.card_url_loaded_image != null:
		return
	if not card.has_meta("image_url_index"):
		return
	var image_url_index = card.get_meta("image_url_index")
	var loaded_image = await image_loader.get_card_image(
		image_url_index["url"], image_url_index["index"], image_url_index)
	if is_instance_valid(card) and loaded_image:
		card.set_loaded_front_image(loaded_image)

func on_card_raised(card):
	# Get card's position in the PlayerHand node's children.
	var parent = card.get_parent()
	if parent == $AllCards/PlayerHand or parent == $AllCards/Striking:
		if UseHugeCard:
			huge_card.visible = true
			huge_card.texture = card.fancy_card.texture
		card.saved_hand_index = card.get_index()

		# Move card to the end of the children list.
		parent.move_child(card, parent.get_child_count() - 1)

func on_card_lowered(card):
	if UseHugeCard:
		huge_card.visible = false
	if card.saved_hand_index != -1:
		# Move card back to its saved position.
		var parent = card.get_parent()
		if card.saved_hand_index >= parent.get_child_count():
			card.saved_hand_index = parent.get_child_count() - 1
		parent.move_child(card, card.saved_hand_index)
		card.saved_hand_index = -1

func is_card_in_player_reference(reference_cards, card_id):
	for card in reference_cards:
		if card.card_id == card_id:
			return true
	return false

func can_select_card(card):
	if observer_mode:
		return false
	# Character card and buddy placeholder reference cards are display-only and must never be selectable.
	if card.card_id in [CardBase.CharacterCardReferenceId, CardBase.BuddyCardReferenceId]:
		return false

	var in_gauge = game_wrapper.is_card_in_gauge(Enums.PlayerId.PlayerId_Player, card.card_id)
	#todo var in_bleach = game_wrapper.is_card_in_bleach(Enums.PlayerId.PlayerId_Player, card.card_id)
	var in_opponent_gauge = game_wrapper.is_card_in_gauge(Enums.PlayerId.PlayerId_Opponent, card.card_id)
	var in_hand = game_wrapper.is_card_in_hand(Enums.PlayerId.PlayerId_Player, card.card_id)
	var in_discard = game_wrapper.is_card_in_discards(Enums.PlayerId.PlayerId_Player, card.card_id)
	var in_sealed = game_wrapper.is_card_in_sealed(Enums.PlayerId.PlayerId_Player, card.card_id)
	var in_set_aside = game_wrapper.is_card_set_aside(Enums.PlayerId.PlayerId_Player, card.card_id)
	var in_overdrive = game_wrapper.is_card_in_overdrive(Enums.PlayerId.PlayerId_Player, card.card_id)
	var in_player_boosts = game_wrapper.is_card_in_boosts(Enums.PlayerId.PlayerId_Player, card.card_id)
	var in_player_transforms = game_wrapper.is_card_in_transforms(Enums.PlayerId.PlayerId_Player, card.card_id)
	var in_opponent_transforms = game_wrapper.is_card_in_transforms(Enums.PlayerId.PlayerId_Opponent, card.card_id)
	var in_transforms = in_player_transforms or in_opponent_transforms
	var is_sustained = game_wrapper.is_card_sustained(Enums.PlayerId.PlayerId_Player, card.card_id)
	var in_opponent_boosts = game_wrapper.is_card_in_boosts(Enums.PlayerId.PlayerId_Opponent, card.card_id)
	var in_player_reference = is_card_in_player_reference($AllCards/PlayerAllCopy.get_children(), card.card_id)
	var in_opponent_reference = is_card_in_player_reference($AllCards/OpponentAllCopy.get_children(), card.card_id)
	var in_choice_zone = is_card_in_player_reference(choice_zone_parent.get_children(), card.card_id)
	var player_logic = game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	var stored_zone_info = player_logic.deck_def.get("stored_zone_info")
	if player_logic.exceeded and player_logic.deck_def.get("stored_zone_info_exceeded"):
		stored_zone_info = player_logic.deck_def["stored_zone_info_exceeded"]
	var can_set_from_stored_zone_for_attack = stored_zone_info and stored_zone_info.get("can_set_for_attack", false)

	# Renea: briefcase boost limited to once per turn — once used, briefcase
	# cards must be unselectable (grayed out) instead of selectable-with-popup.
	if in_set_aside and player_logic.deck_def.get("id") == "renea" and player_logic.exceeded and player_logic.renea_boost_from_briefcase_used:
		return false

	if ui_state == UIState.UIState_PickTurnAction:
		if in_player_boosts:
			var card_db = game_wrapper.get_card_database()
			var logic_card = card_db.get_card(card.card_id)
			if 'must_set_from_boost' in logic_card.definition and logic_card.definition['must_set_from_boost']:
				return true
			if 'may_set_from_boost' in logic_card.definition and logic_card.definition['may_set_from_boost']:
				return true
			return false
		elif in_set_aside:
			if can_set_from_stored_zone_for_attack and game_wrapper.can_do_strike(Enums.PlayerId.PlayerId_Player):
				return true
			if game_wrapper.can_player_boost_from_extra(Enums.PlayerId.PlayerId_Player):
				return game_wrapper.can_player_boost(Enums.PlayerId.PlayerId_Player, card.card_id, ['extra'], "", true)
			return false
		return in_hand or in_gauge
	match ui_sub_state:
		UISubState.UISubState_SelectCards_DiscardCards, UISubState.UISubState_SelectCards_DiscardCardsToGauge:
			if select_card_restriction_ids and not card.card_id in select_card_restriction_ids:
				return false
			return in_hand and len(selected_cards) < select_card_require_max
		UISubState.UISubState_SelectCards_DiscardCards_Choose:
			if is_tournelouse_ouroboros_hand_choice():
				return in_hand and not is_tournelouse_ouroboros_paid_card(card.card_id) and is_tournelouse_ouroboros_legal_hand_transform(card.card_id) and len(selected_cards) < select_card_require_max
			var discard_decision = game_wrapper.get_decision_info()
			var limitation = discard_decision.limitation
			var meets_limitation = true
			var game_card = game_wrapper.get_card_database().get_card(card.card_id)
			var card_type = game_card.definition['type']
			var card_name = game_card.definition['display_name']
			match limitation:
				"can_pay_cost":
					var card_options = game_wrapper.get_player_extra_attack_card_options(Enums.PlayerId.PlayerId_Player)
					meets_limitation = card.card_id in card_options
				"normal":
					meets_limitation = card_type == "normal"
				"ultra":
					meets_limitation = card_type == "ultra"
				"special":
					meets_limitation = card_type == "special"
				"normal/special":
					meets_limitation = card_type in ["normal", "special"]
				"special/ultra":
					meets_limitation = card_type in ["special", "ultra"]
				"from_array":
					var card_ids = game_wrapper.get_decision_info().choice
					meets_limitation = card.card_id in card_ids
				"same-named":
					meets_limitation = true
					for selected_card in selected_cards:
						var compare_card = game_wrapper.get_card_database().get_card(selected_card.card_id)
						if compare_card.definition['display_name'] != card_name:
							meets_limitation = false
							break
				"range_to_opponent":
					var discard_effect = game_wrapper.get_decision_info().effect
					var range_only_character = discard_effect and discard_effect.get("range_only_character_effects", false)
					meets_limitation = game_wrapper.does_card_contain_range_to_opponent(
							Enums.PlayerId.PlayerId_Player, card.card_id, range_only_character)
				_:
					meets_limitation = true
			var in_source = in_player_boosts if discard_decision.source == "boosts" else in_hand
			if discard_decision.source == "hand/gauge":
				in_source = in_hand or in_gauge
			return in_source and meets_limitation and len(selected_cards) < select_card_require_max
		UISubState.UISubState_SelectCards_StrikeGauge:
			var can_use_transforms = game_wrapper.can_player_seal_transform_for_gauge(Enums.PlayerId.PlayerId_Player) or game_wrapper.can_player_seal_transform_for_gauge(Enums.PlayerId.PlayerId_Opponent)
			return (in_gauge or (can_use_transforms and in_transforms)) and len(selected_cards) < select_card_require_max
		UISubState.UISubState_SelectCards_Exceed, UISubState.UISubState_SelectCards_BoostCancel:
			return in_gauge and len(selected_cards) < select_card_require_max
		UISubState.UISubState_SelectCards_MoveActionGenerateForce, UISubState.UISubState_SelectCards_ForceForChange, UISubState.UISubState_SelectCards_ForceForArmor:
			return in_gauge or in_hand
		UISubState.UISubState_SelectCards_GaugeForArmor:
			return in_gauge
		UISubState.UISubState_SelectCards_StrikeForce:
			return in_gauge or in_hand
		UISubState.UISubState_SelectCards_ChooseBoostsToSustain:
			if is_tournelouse_transform_zone_choice():
					return in_player_transforms and not is_tournelouse_ouroboros_paid_card(card.card_id) and len(selected_cards) < select_card_require_max
			return in_player_boosts and not is_sustained and len(selected_cards) < select_card_require_max
		UISubState.UISubState_SelectCards_CharacterAction_Force:
			var new_force = game_wrapper.get_card_database().get_card_force_value(card.card_id)
			var force_player = game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
			if force_player.is_card_in_gauge(card.card_id):
				new_force = max(new_force, force_player.get_gauge_card_force_value_for(card.card_id))
			return (in_gauge or in_hand) and can_selected_cards_pay_force(select_card_require_force, new_force)
		UISubState.UISubState_SelectCards_CharacterAction_Gauge:
			return in_gauge and len(selected_cards) < select_card_require_max
		UISubState.UISubState_SelectCards_ForceForEffect:
			if is_tournelouse_ouroboros_force_choice() and in_hand and game_wrapper.get_player_hand_size(Enums.PlayerId.PlayerId_Player) <= 1:
				return false
			var force_selected = get_force_in_selected_cards()
			var new_force = game_wrapper.get_card_database().get_card_force_value(card.card_id)
			var force_player = game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
			if force_player.is_card_in_gauge(card.card_id):
				new_force = max(new_force, force_player.get_gauge_card_force_value_for(card.card_id))
			var total_force = force_selected + new_force
			var within_force_limit = select_card_up_to_force == -1 or total_force <= select_card_up_to_force
			return (in_gauge or in_hand) and (within_force_limit or can_selected_cards_pay_force(select_card_up_to_force, new_force))
		UISubState.UISubState_SelectCards_GaugeForEffect:
			var valid_id = true
			var valid_type = true
			var card_db = game_wrapper.get_card_database()
			var logic_card = card_db.get_card(card.card_id)
			if select_gauge_require_card_id:
				valid_id = logic_card.definition['id'] == select_gauge_require_card_id
			if select_gauge_valid_card_types:
				valid_type = logic_card.definition['type'] in select_gauge_valid_card_types
			return in_gauge and valid_id and valid_type and len(selected_cards) < select_card_require_max
		UISubState.UISubState_SelectCards_StrikeCard, UISubState.UISubState_SelectCards_StrikeResponseCard, UISubState.UISubState_SelectCards_OpponentSetsFirst_StrikeCard, UISubState.UISubState_SelectCards_OpponentSetsFirst_StrikeResponseCard, UISubState.UISubState_SelectCards_Mulligan:
			if in_player_boosts:
				var card_db = game_wrapper.get_card_database()
				var logic_card = card_db.get_card(card.card_id)
				if 'must_set_from_boost' in logic_card.definition and logic_card.definition['must_set_from_boost']:
					return true
				if 'may_set_from_boost' in logic_card.definition and logic_card.definition['may_set_from_boost']:
					return true
				return false
			if in_set_aside and ui_sub_state != UISubState.UISubState_SelectCards_Mulligan:
				return can_set_from_stored_zone_for_attack
			return in_hand
		UISubState.UISubState_SelectCards_StrikeCard_FromGauge:
			return in_gauge
		UISubState.UISubState_SelectCards_StrikeCard_FromSealed:
			return in_sealed
		UISubState.UISubState_SelectCards_PlayBoost:
			var select_boost_valid_zones = select_boost_options['valid_zones']
			var select_boost_limitation = select_boost_options['limitation']
			var select_boost_ignore_costs = select_boost_options['ignore_costs']
			var select_boost_amount = select_boost_options['boost_amount']

			var valid_amount = false
			if select_boost_amount <= 1:
				valid_amount = len(selected_cards) == 0
			else:
				valid_amount = len(selected_cards) < select_boost_amount

			var valid_card = false
			# Checks if it's the EX transform action
			if !select_boost_limitation and game_wrapper.can_player_ex_transform(Enums.PlayerId.PlayerId_Player, card.card_id):
				if game_wrapper.can_do_ex_transform(Enums.PlayerId.PlayerId_Player): # checks timing
					valid_card = true
			else:
				valid_card = game_wrapper.can_player_boost(Enums.PlayerId.PlayerId_Player, card.card_id, select_boost_valid_zones, select_boost_limitation, select_boost_ignore_costs)
			return valid_amount and valid_card
		UISubState.UISubState_SelectCards_ForceForBoost:
			return (in_gauge or in_hand) and selected_boost_to_pay_for != card.card_id
		UISubState.UISubState_SelectCards_GaugeForBoost:
			return in_gauge and selected_boost_to_pay_for != card.card_id
		UISubState.UISubState_SelectCards_DiscardContinuousBoost:
			var limitation = game_wrapper.get_decision_info().limitation
			if limitation in ["mine", "in_opponent_space"] and in_opponent_boosts:
				return false
			if not in_player_boosts and not in_opponent_boosts:
				return false
			if len(selected_cards) < select_card_require_max:
				var card_db = game_wrapper.get_card_database()
				var logic_card = card_db.get_card(card.card_id)
				if limitation == "in_opponent_space" and select_card_name_boost_restriction:
					if logic_card.definition['boost']['display_name'] != select_card_name_boost_restriction:
						return false
				if 'cannot_discard' in logic_card.definition['boost'] and logic_card.definition['boost']['cannot_discard']:
					return false
				return true
			return false
		UISubState.UISubState_SelectCards_DiscardOpponentGauge:
			return in_opponent_gauge and len(selected_cards) < select_card_require_max
		UISubState.UISubState_SelectCards_DiscardFromReference:
			var in_appropriate_reference = in_opponent_reference
			if select_card_name_card_both_players:
				in_appropriate_reference = in_opponent_reference or in_player_reference
			return in_appropriate_reference and len(selected_cards) < select_card_require_max
		UISubState.UISubState_SelectCards_ChooseDiscardToDestination:
			var card_db = game_wrapper.get_card_database()
			var logic_card = card_db.get_card(card.card_id)
			var card_type = logic_card.definition['type']
			var limitation = game_wrapper.get_decision_info().limitation
			var source = game_wrapper.get_decision_info().source
			# Umina Terror Whispers: Shadow Chorus cannot enter Dreamlands
			if source == "discard" and game_wrapper.get_decision_info().destination == "umina_dreamlands":
				if logic_card.definition.get("id") == "umina_shadow_chorus":
					return false
			var meets_limitation = false
			match limitation:
				"normal":
					meets_limitation = card_type == "normal"
				"special":
					meets_limitation = card_type == "special"
				"ultra":
					meets_limitation = card_type == "ultra"
				"normal/special":
					meets_limitation = card_type in ["normal", "special"]
				"special/ultra":
					meets_limitation = card_type in ["special", "ultra"]
				"continuous":
					meets_limitation = logic_card.definition['boost']['boost_type'] == "continuous"
				"transform":
					meets_limitation = logic_card.definition['boost']['boost_type'] == "transform"
				_:
					meets_limitation = true
			var in_correct_source = false
			match source:
				"discard":
					in_correct_source = in_discard
				"gauge":
					in_correct_source = in_gauge
				"sealed":
					in_correct_source = in_sealed
				"overdrive":
					in_correct_source = in_overdrive
				"outrun_seal":
					in_correct_source = in_discard or in_gauge
				_:
					in_correct_source = false
			return in_correct_source and len(selected_cards) < select_card_require_max and meets_limitation
		UISubState.UISubState_SelectCards_ChooseFromTopdeck, UISubState.UISubState_SelectCards_ChooseOpponentCardToDiscard:
			if not in_choice_zone or len(selected_cards) >= select_card_require_max:
				return false
			if ui_sub_state == UISubState.UISubState_SelectCards_ChooseFromTopdeck:
				# 效果限定了看牌能做什么时（例如「只能打出持续性加成」），
				# 不允许勾选不符合条件的牌。
				var topdeck_limitation = game_wrapper.get_decision_info().limitation
				if topdeck_limitation:
					var topdeck_card_db = game_wrapper.get_card_database()
					var topdeck_logic_card = topdeck_card_db.get_card(card.card_id)
					return card_meets_boost_limitation(topdeck_logic_card, topdeck_limitation)
			return true

func card_meets_boost_limitation(logic_card, limitation) -> bool:
	if limitation == null or limitation == "":
		return true
	match limitation:
		"normal":
			return logic_card.definition['type'] == "normal"
		"special":
			return logic_card.definition['type'] == "special"
		"ultra":
			return logic_card.definition['type'] == "ultra"
		"normal/special":
			return logic_card.definition['type'] in ["normal", "special"]
		"special/ultra":
			return logic_card.definition['type'] in ["special", "ultra"]
		"continuous":
			return logic_card.definition['boost']['boost_type'] == "continuous"
		"transform":
			return logic_card.definition['boost']['boost_type'] == "transform"
	return true

func clear_selected_cards():
	for card in selected_cards:
		if is_instance_valid(card):
			modify_card_selection(card, false)
	selected_cards = []

func deselect_all_cards():
	clear_selected_cards()

func get_selected_card_ids() -> Array:
	var selected_card_ids : Array = []
	for card in selected_cards:
		if is_instance_valid(card):
			selected_card_ids.append(card.card_id)
	return selected_card_ids

func _is_local_mulligan_selection_context() -> bool:
	if not game_wrapper or observer_mode:
		return false
	if game_wrapper.get_player_mulligan_complete(Enums.PlayerId.PlayerId_Player):
		return false
	if ui_state == UIState.UIState_SelectCards and ui_sub_state == UISubState.UISubState_SelectCards_Mulligan:
		return true
	if ui_state == UIState.UIState_PlayingAnimation \
			and previous_ui_state == UIState.UIState_SelectCards \
			and previous_ui_sub_state == UISubState.UISubState_SelectCards_Mulligan:
		return true
	return false

func _cache_local_mulligan_selection_if_needed():
	if not _is_local_mulligan_selection_context():
		if game_wrapper and game_wrapper.get_player_mulligan_complete(Enums.PlayerId.PlayerId_Player):
			mulligan_selected_card_ids_tmp = []
		return
	mulligan_selected_card_ids_tmp = get_selected_card_ids()

func _restore_local_mulligan_selection_if_needed():
	if not game_wrapper or observer_mode:
		return
	if game_wrapper.get_player_mulligan_complete(Enums.PlayerId.PlayerId_Player):
		mulligan_selected_card_ids_tmp = []
		return
	if mulligan_selected_card_ids_tmp.is_empty():
		return
	clear_selected_cards()
	_restore_selected_cards_by_ids(mulligan_selected_card_ids_tmp)
	# Keep cache aligned with cards that still exist after event/animation updates.
	mulligan_selected_card_ids_tmp = get_selected_card_ids()

func _restore_selected_cards_by_ids(selected_card_ids : Array):
	for card_id in selected_card_ids:
		var card = find_card_on_board_or_null(card_id)
		if card == null:
			continue
		selected_cards.append(card)
		modify_card_selection(card, true)

func find_card_on_board_or_null(card_id) -> CardBase:
	# Same search as find_card_on_board(), but safe for rebuilt reference zones.
	var zones = $AllCards.get_children()
	for zone in zones:
		if zone is Node2D:
			var zone_cards = zone.get_children()
			for zone_card in zone_cards:
				if zone_card.card_id == card_id:
					return zone_card
	return null

func modify_card_selection(card, selected):
	card.set_selected(selected)
	if card_popout_parent.get_child_count() > 0:
		var popout = card_popout_parent.get_child(0)
		popout.modify_card_selection(card.card_id, selected)

func on_card_clicked(card : CardBase):
	if observer_mode:
		return

	# If in selection mode, select/deselect card.
	# Otherwise, if picking turn action, toggle quick action selection.
	if ui_state == UIState.UIState_SelectCards or ui_state == UIState.UIState_PickTurnAction:
		var index = -1
		for i in range(len(selected_cards)):
			if selected_cards[i].card_id == card.card_id:
				index = i
				break

		if index == -1:
			# Selected, add to cards.
			if can_select_card(card):
				selected_cards.append(card)
				modify_card_selection(card, true)
		else:
			# Deselect
			selected_cards.remove_at(index)
			modify_card_selection(card, false)
		if ui_state == UIState.UIState_SelectCards and ui_sub_state == UISubState.UISubState_SelectCards_Mulligan:
			mulligan_selected_card_ids_tmp = get_selected_card_ids()
		_update_buttons(true)

func _on_card_popout_card_clicked(card_id : int):
	var card = find_card_on_board(card_id)
	if card:
		on_card_clicked(card)

func sort_cards(cards, mix_ultras : bool, speed_only : bool):
	cards.sort_custom(
		# For descending order use > 0
		func(a: Node, b: Node):
			assert(a is CardBase)
			assert(b is CardBase)
			var card_a = a as CardBase
			var card_b = b as CardBase
			var sort_key_a = game_wrapper.get_card_database().get_card_sort_key(card_a.card_id, mix_ultras, speed_only)
			var sort_key_b = game_wrapper.get_card_database().get_card_sort_key(card_b.card_id, mix_ultras, speed_only)
			return sort_key_a < sort_key_b
	)

func sort_player_hand(hand_zone):
	# Only intended to be called for the player, not opponent.
	var sorted_nodes = hand_zone.get_children()
	sorted_nodes.sort_custom(
		# For descending order use > 0
		func(a: Node, b: Node):
			assert(a is CardBase)
			assert(b is CardBase)
			var card_a = a as CardBase
			var card_b = b as CardBase
			var sort_key_a = game_wrapper.get_card_database().get_card_sort_key(card_a.card_id)
			var sort_key_b = game_wrapper.get_card_database().get_card_sort_key(card_b.card_id)
			return sort_key_a < sort_key_b
	)

	for i in range(sorted_nodes.size()):
		hand_zone.move_child(sorted_nodes[i], i)

func layout_player_hand(is_player : bool):
	if _should_defer_runtime_ui_refreshes():
		_request_layout_player_hand(is_player)
		return
	_layout_player_hand_now(is_player)

func _layout_player_hand_now(is_player : bool):
	var hand_zone = get_hand_zone(is_player)
	var num_cards = len(hand_zone.get_children())
	if num_cards > 0:
		if is_player:
			update_eyes_on_hand_icons()
			if num_cards == 1:
				var card : CardBase = hand_zone.get_child(0)
				var angle = deg_to_rad(90)
				var ovalAngleVector = Vector2(HorizontalRadius * cos(angle), -VerticalRadius * sin(angle))
				var dst_pos = CenterCardOval + ovalAngleVector
				card.set_resting_position(dst_pos, 0)
			else:
				sort_player_hand(hand_zone)
				var min_angle = deg_to_rad(60)
				var max_angle = deg_to_rad(120)
				var max_angle_diff = deg_to_rad(10)

				var angle_diff = (max_angle - min_angle) / (num_cards - 1)
				if angle_diff > max_angle_diff:
					angle_diff = max_angle_diff
					var total_angle = min_angle + angle_diff * (num_cards - 1)
					var extra_angle = (max_angle - total_angle) / 2
					min_angle += extra_angle
					max_angle -= extra_angle

				# Force lower all the cards so we don't get any weirdness when they reposition
				var cards = []
				for card in hand_zone.get_children():
					cards.append(card)
				for card in cards:
					on_card_lowered(card)

				for i in range(num_cards):
					var card : CardBase = hand_zone.get_child(num_cards - i - 1)

					# Calculate the angle for this card, distributing the cards evenly between min_angle and max_angle
					var angle = min_angle + i * (max_angle - min_angle) / (num_cards - 1)

					var ovalAngleVector = Vector2(HorizontalRadius * cos(angle), -VerticalRadius * sin(angle))
					var dst_pos = CenterCardOval + ovalAngleVector # - size/2
					var dst_rot = (90 - rad_to_deg(angle)) / 4
					card.change_state(CardBase.CardState.CardState_InHand)
					card.set_resting_position(dst_pos, dst_rot)
		else:
			var spawn_spot = $OpponentHand/HandSpawn
			var hand_center = spawn_spot.global_position + spawn_spot.size * spawn_spot.scale /2
			if replay_mode and GlobalSettings.ReplayShowOpponentHand:
				# Make sure the cards are visible.
				hand_center.y += 85
			var min_x = hand_center.x - 200
			var max_x = hand_center.x + 200
			if num_cards == 1:
				var pos = Vector2(hand_center.x, hand_center.y)
				var card : CardBase = hand_zone.get_child(0)
				card.set_resting_position(pos, 0)
			elif num_cards > 1:
				var step = (max_x - min_x) / (num_cards - 1)
				step = min(step, CardBase.get_opponent_hand_card_size().x / 1.5)
				var new_diff = step * (num_cards - 1)
				max_x = hand_center.x + new_diff / 2
				min_x = hand_center.x - new_diff / 2

				# Shuffle children in hand_zone if not a replay.
				if not replay_mode:
					var children = hand_zone.get_children()
					for child in children:
						hand_zone.move_child(child, randi() % num_cards)

				for i in range(num_cards):
					var pos = Vector2(min_x + step * i, hand_center.y)
					var card : CardBase = hand_zone.get_child(i)
					card.change_state(CardBase.CardState.CardState_InHand)
					card.set_resting_position(pos, 0)

	_update_card_counts_now()

func update_eyes_on_hand_icons():
	if observer_mode:
		return
	var public_hand_info = game_wrapper.get_player_public_hand_info(Enums.PlayerId.PlayerId_Player)
	var all_player_cards = get_all_player_cards()
	for card in all_player_cards:
		# These are cards in hand, so the ids are correct.
		var id = card.card_id
		var logic_card = game_wrapper.get_card_database().get_card(id)
		var card_str_id = logic_card.definition['id']
		var known_count = 0
		var questionable_count = 0
		var on_topdeck = false
		# Only update shows the icons on the cards in hand.
		if game_wrapper.is_card_in_hand(Enums.PlayerId.PlayerId_Player, id):
			if card_str_id in public_hand_info['known']:
				known_count = public_hand_info['known'][card_str_id]
			if card_str_id in public_hand_info['questionable']:
				questionable_count = public_hand_info['questionable'][card_str_id]
			on_topdeck = card_str_id == public_hand_info['topdeck']
		card.update_hand_icons(known_count, questionable_count, on_topdeck, true)

func _log_event(event):
	var num = event['number']
	var card_db = game_wrapper.get_card_database()
	var card_name = card_db.get_card_id(num)
	printlog("Event %s num=%s (card=%s)" % [Enums.EventType.keys()[event['event_type']], event['number'], card_name])

func get_notice_position(notice_player : Enums.PlayerId):
	if notice_player == Enums.PlayerId.PlayerId_Player:
		return $PlayerCharacter.position
	else:
		return $OpponentCharacter.position

func _stat_notice_event(event):
	var player = event['event_player']
	var number = event['number']
	var notice_text = ""
	match event['event_type']:
		Enums.EventType.EventType_BlockMovement:
			notice_text = "移动被阻挡！"
		Enums.EventType.EventType_Strike_ArmorUp:
			var text = ""
			if number > 0:
				text += "+"
			notice_text = "%s%s 护甲" % [text, number]
		Enums.EventType.EventType_Strike_AttackDoesNotHit:
			notice_text = "未击中！"
		Enums.EventType.EventType_CharacterAction:
			notice_text = "角色行动"
		Enums.EventType.EventType_Strike_Critical:
			notice_text = "%s!" % event['reason']
		Enums.EventType.EventType_Strike_Infuse:
			notice_text = "灌注！"
		Enums.EventType.EventType_Strike_DodgeAttacks:
			notice_text = "闪避攻击！"
		Enums.EventType.EventType_Strike_DodgeAttacksAtRange:
			if number == event['extra_info']:
				notice_text = "在距离 %s 闪避" % number
			else:
				notice_text = "在距离 %s-%s 闪避" % [number, event['extra_info']]
			if event['extra_info2']:
				notice_text += " 来自 %s" % event['extra_info2']
		Enums.EventType.EventType_Strike_DodgeFromOppositeBuddy:
			notice_text = "从 %s 身后闪避" % [event['extra_info']]
		Enums.EventType.EventType_Strike_ExUp:
			notice_text = "EX战斗！"
		Enums.EventType.EventType_Strike_GainAdvantage:
			notice_text = "+优势！"
		Enums.EventType.EventType_Strike_GuardUp:
			var text = ""
			if number > 0:
				text += "+"
			notice_text = "%s%s 霸体" % [text, number]
		Enums.EventType.EventType_Strike_IgnoredPushPull:
			notice_text = "未被移动！"
		Enums.EventType.EventType_Strike_Miss:
			notice_text = "未击中！"
		Enums.EventType.EventType_Strike_OpponentCantMovePast:
			var movement_text = "前进"
			if event['extra_info']:
				movement_text = "穿过 %s 的移动" % event['extra_info']
			notice_text = "阻挡%s！" % movement_text
		Enums.EventType.EventType_Strike_PowerUp:
			var text = ""
			if event['reason'] == "powerup_per_sealed_amount":
				notice_text  = "每有 %s 张封印，+1 威力" % number
			else:
				if number > 0:
					text += "+"
				notice_text = "%s%s 威力" % [text, number]
		Enums.EventType.EventType_Strike_RandomGaugeStrike:
			notice_text = "从怒气中战斗！"
		Enums.EventType.EventType_Strike_RangeUp:
			var number2 = event['extra_info']
			var prefix = ""
			if event['reason'] == "special_only":
				prefix = "特殊技"
			var firstplus = ""
			if number >= 0:
				firstplus = "+"
			var secondplus = ""
			if number2 >= 0:
				secondplus = "+"
			if number == number2:
				notice_text = "%s%s%s 距离" % [prefix, firstplus, number]
			else:
				notice_text = "%s%s%s - %s%s 距离" % [prefix, firstplus, number, secondplus, number2]
		Enums.EventType.EventType_Strike_SetX:
			notice_text = "X 为 %s" % number
		Enums.EventType.EventType_Strike_SpeedUp:
			var text = ""
			if number > 0:
				text += "+"
			notice_text = "%s%s 速度" % [text, number]
		Enums.EventType.EventType_Strike_Stun:
			notice_text = "被击晕！"
		Enums.EventType.EventType_Strike_Stun_Immunity:
			notice_text = "免疫击晕！"
		Enums.EventType.EventType_SustainBoost:
			notice_text = "维持加成"
		Enums.EventType.EventType_Strike_WildStrike:
			notice_text = "疯狂攻击！"
		Enums.EventType.EventType_SwapSealedAndDeck:
			notice_text = "交换封印区与牌库"
		Enums.EventType.EventType_EndOverdrive:
			notice_text = "超驱结束"

	spawn_damage_popup(notice_text, player)
	return SmallNoticeDelay

func _on_say(event):
	var player = event['event_player']
	var text = event['extra_info']
	spawn_emote(player, false, text)
	return SmallNoticeDelay

func _set_card_bonus(card_id, bonus, value=true):
	var card = find_card_on_board(card_id)
	match bonus:
		"ex":
			card.set_ex(value)
		"wild":
			card.set_wild(value)
		"critical":
			card.set_crit(value)
		"infuse":
			card.set_infuse(value)
		_:
			assert(false, "Set card bonus for unknown effect")

func _on_stunned(event):
	var card = find_card_on_board(event['number'])
	var player = event['event_player']
	var is_player = player == Enums.PlayerId.PlayerId_Player
	# Iaquis stun easter-egg: only when this strike's attack was set face-up
	# (initial ability) AND Iaquis never hit the opponent this strike.
	if _is_player_iaquis(player) and iaquis_faceup_this_strike and not iaquis_hit_opponent_this_strike:
		_play_iaquis_faceup(true)
	card.set_stun(true)
	if is_player:
		$PlayerCharacter.play_stunned()
	else:
		$OpponentCharacter.play_stunned()
	return _stat_notice_event(event)

func _on_end_of_strike():
	# Iaquis face-up / stun-easter-egg per-strike flags: cleared at strike
	# end so they never leak into the next fight.
	iaquis_faceup_this_strike = false
	iaquis_hit_opponent_this_strike = false
	# Strike cleanup: end any ultra closeups that were armed but never played
	# (e.g. the attack missed). Whatever is still pending here is dropped.
	_clear_all_pending_strike_closeups()
	player_bonus_panel.visible = false
	opponent_bonus_panel.visible = false
	for zone in $AllCards.get_children():
		if zone is Node2D:
			for card in zone.get_children():
				card.set_backlight_visible(false)
				card.set_stun(false)
				card.clear_bonuses()

func _on_advance_turn(event):
	var active_player : Enums.PlayerId = game_wrapper.get_active_player()
	var is_local_player_active = active_player == Enums.PlayerId.PlayerId_Player
	$PlayerLife.set_turn_indicator(is_local_player_active)
	$OpponentLife.set_turn_indicator(not is_local_player_active)

	if is_local_player_active and not observer_mode:
		change_ui_state(UIState.UIState_PickTurnAction, UISubState.UISubState_None)
		deselect_all_cards()
		close_popout()
	else:
		change_ui_state(UIState.UIState_WaitingOnOpponent, UISubState.UISubState_None)

	player_bonus_panel.visible = false
	opponent_bonus_panel.visible = false
	prepared_character_action_data = {}

	# 事件处理时 active_player 可能已变化，提示必须以事件创建时的回合玩家为准。
	spawn_damage_popup("回合开始！", event['event_player'])
	return SmallNoticeDelay

func _on_post_boost_action(event):
	var player = event['event_player']
	spawn_damage_popup("额外行动", player)
	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		change_ui_state(UIState.UIState_PickTurnAction, UISubState.UISubState_None)
		deselect_all_cards()
		close_popout()
	else:
		ai_take_turn()
	return SmallNoticeDelay

func _on_boost_cancel_decision(event):
	var player = event['event_player']
	var gauge_cost = event['number']
	spawn_damage_popup("取消？", player)
	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		begin_gauge_selection(gauge_cost, false, UISubState.UISubState_SelectCards_BoostCancel)
	else:
		ai_boost_cancel_decision(gauge_cost)
	return SmallNoticeDelay

func _on_boost_canceled(event):
	var player = event['event_player']
	spawn_damage_popup("取消！", player)
	return SmallNoticeDelay

func _on_continuous_boost_added(event):
	var player = event['event_player']
	var is_facedown = event["extra_info"]
	var card = find_card_on_board_or_null(event['number'])
	var boost_zone = $PlayerBoostZone
	var boost_card_loc = $AllCards/PlayerBoosts

	if player == Enums.PlayerId.PlayerId_Opponent:
		boost_zone = $OpponentBoostZone
		boost_card_loc = $AllCards/OpponentBoosts

	var pos = get_boost_zone_center(boost_zone)
	if card == null:
		# 卡片控件不在棋盘上。这发生在从弃牌堆打出的持续加成（海蒂 机械天才）：
		# 控件可能还在移动中或从未建立。补建一个放到加成区，而不是让原来的
		# find_card_on_board() assert 中断整个事件处理（那样加成既不进加成区
		# 也不进加成栏）。
		_create_missing_boost_card(event['number'], player, pos)
		return SmallNoticeDelay
	if not is_facedown:
		make_card_revealed(card)
	else:
		card.flip_card_to_front(false)
	card.discard_to(pos, CardBase.CardState.CardState_InBoost)
	reparent_to_zone(card, boost_card_loc)
	spawn_damage_popup("+ 持续性加成", player)
	return SmallNoticeDelay

func _create_missing_boost_card(card_id : int, player, pos : Vector2) -> void:
	# Async helper for _on_continuous_boost_added: rebuild a boost widget whose
	# node was no longer on the board so the boost zone / boost summary show it.
	print("WARNING: continuous boost card %s was not on the board; creating its widget." % card_id)
	var card_db = game_wrapper.get_card_database()
	var logic_card : GameCard = card_db.get_card(card_id)
	if logic_card == null:
		return
	var boost_card_loc = $AllCards/PlayerBoosts
	if player == Enums.PlayerId.PlayerId_Opponent:
		boost_card_loc = $AllCards/OpponentBoosts
	var is_opponent = player == Enums.PlayerId.PlayerId_Opponent
	var new_card = await create_card(card_id, logic_card.definition, logic_card.get_image_url_index_data(),
			"", boost_card_loc, is_opponent, logic_card.definition['display_name'],
			logic_card.definition['boost']['display_name'])
	new_card.set_card_and_focus(OffScreen, 0, CardBase.ReferenceCardScale)
	new_card.change_state(CardBase.CardState.CardState_Offscreen)
	new_card.flip_card_to_front(true)
	new_card.discard_to(pos, CardBase.CardState.CardState_InBoost)
	spawn_damage_popup("+ 持续性加成", player)

func _on_transform_added(event):
	var player = event['event_player']
	var card = find_card_on_board(event['number'])
	make_card_revealed(card)
	var boost_zone = $PlayerBoostZone
	var boost_card_loc = $AllCards/PlayerBoosts

	if player == Enums.PlayerId.PlayerId_Opponent:
		boost_zone = $OpponentBoostZone
		boost_card_loc = $AllCards/OpponentBoosts

	var pos = get_boost_zone_center(boost_zone)
	card.discard_to(pos, CardBase.CardState.CardState_InBoost)
	reparent_to_zone(card, boost_card_loc)
	spawn_damage_popup("+ 转化", player)
	return SmallNoticeDelay

func _on_discard_continuous_boost_begin(event):
	var player = event['event_player']
	var decision_info = game_wrapper.get_decision_info()
	var limitation = decision_info.limitation
	var can_pass = decision_info.can_pass
	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		# Show the boost window.
		var instruction_qualifier = "一个"
		if limitation in ["mine", "in_opponent_space"] or game_wrapper.get_player_discardable_boost_count(player) == 0:
			instruction_qualifier = "你的"
		clear_selected_cards()
		select_card_require_min = 1
		select_card_require_max = 1
		var action_word = ""
		var extra_info = ""
		match decision_info.destination:
			"owner_hand":
				action_word = "Return"
				extra_info = " to its owner's hand."
			_:
				action_word = "Discard"
		var instruction_text = "%s %s 持续性加成%s." % [action_word, instruction_qualifier, extra_info]
		popout_instruction_info = {
			"popout_type": CardPopoutType.CardPopoutType_BoostOpponent,
			"instruction_text": instruction_text,
			"ok_text": "OK",
			"cancel_text": "略过",
			"ok_enabled": true,
			"cancel_visible": can_pass,
		}
		enable_instructions_ui(instruction_text, true, can_pass, {})
		if limitation == "in_opponent_space":
			select_card_name_boost_restriction = event['extra_info']
			_on_player_boost_zone_clicked_zone(false)
		elif limitation == "mine" or game_wrapper.get_player_discardable_boost_count(Enums.PlayerId.PlayerId_Opponent) == 0:
			_on_player_boost_zone_clicked_zone(false)
		else:
			_on_opponent_boost_zone_clicked_zone(false)
		change_ui_state(UIState.UIState_SelectCards, UISubState.UISubState_SelectCards_DiscardContinuousBoost)
	else:
		ai_discard_continuous_boost(limitation, can_pass, event['extra_info'])

func _on_discard_opponent_gauge(event):
	var player = event['event_player']
	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		var instruction_text = event.get("reason", "")
		if instruction_text.is_empty():
			instruction_text = "选择一张对手的怒气牌来弃置。"
		# Show the gauge window.
		_on_opponent_gauge_gauge_clicked(false)
		clear_selected_cards()
		select_card_require_min = 1
		select_card_require_max = 1
		var cancel_allowed = false
		popout_instruction_info = {
			"popout_type": CardPopoutType.CardPopoutType_GaugeOpponent,
			"instruction_text": instruction_text,
			"ok_text": "OK",
			"cancel_text": "",
			"ok_enabled": true,
			"cancel_visible": false,
		}
		enable_instructions_ui(instruction_text, true, cancel_allowed, {})

		change_ui_state(UIState.UIState_SelectCards, UISubState.UISubState_SelectCards_DiscardOpponentGauge)
	else:
		ai_discard_opponent_gauge()

func _on_name_opponent_card_begin(event):
	var player = event['event_player']
	spawn_damage_popup("命名卡牌", player)
	var normal_only = event['event_type'] == Enums.EventType.EventType_ReadingNormal or event['event_type'] == Enums.EventType.EventType_Boost_Sidestep
	var can_name_fake_card = event['event_type'] == Enums.EventType.EventType_Boost_NameCardOpponentDiscards or event['event_type'] == Enums.EventType.EventType_Boost_ZeroVector
	var amount = event.get('number', 1)

	var cancel_text = "展示手牌"
	if event['event_type'] == Enums.EventType.EventType_Boost_ZeroVector or amount > 1:
		cancel_text = "命名不存在的卡牌"

	if game_wrapper.get_decision_info().bonus_effect:
		select_card_name_card_both_players = true
	else:
		select_card_name_card_both_players = false

	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		var instruction_text = "命名一张对手的卡牌。"
		if select_card_name_card_both_players:
			instruction_text = "命名一张卡牌。"

		clear_selected_cards()
		select_card_require_min = 1
		select_card_require_max = 1
		var cancel_allowed = can_name_fake_card
		popout_instruction_info = {
			"popout_type": CardPopoutType.CardPopoutType_ReferenceOpponent,
			"instruction_text": instruction_text,
			"ok_text": "OK",
			"cancel_text": cancel_text,
			"ok_enabled": true,
			"cancel_visible": cancel_allowed,
			"normal_only": normal_only,
		}
		enable_instructions_ui(instruction_text, true, cancel_allowed, {})
		change_ui_state(UIState.UIState_SelectCards, UISubState.UISubState_SelectCards_DiscardFromReference)
		_on_opponent_reference_button_pressed(false, true, false)
	else:
		ai_name_opponent_card(normal_only, select_card_name_card_both_players)
	return SmallNoticeDelay

func _on_boost_played(event):
	var player = event['event_player']
	var card = find_card_on_board(event['number'])
	var is_transform = event['reason'] == "Transform"
	var is_facedown = event["extra_info"]
	if not is_facedown:
		make_card_revealed(card)
	var target_zone = $PlayerStrike/StrikeZone
	var is_player = player == Enums.PlayerId.PlayerId_Player
	if not is_player:
		target_zone = $OpponentStrike/StrikeZone
	_move_card_to_strike_area(card, target_zone, $AllCards/Striking, is_player, false)

	var boost_text = "Boost!"
	if is_transform:
		boost_text = "Transform!"
	spawn_damage_popup(boost_text, player)
	return BoostDelay

func _on_choose_card_hand_to_gauge(event):
	var player = event['event_player']
	var min_amount = event['number']
	var max_amount = event['extra_info']
	var restricted_to_card_ids = event['extra_info2']

	var decision_info = game_wrapper.get_decision_info()
	select_card_destination = decision_info.destination
	var show_restriction_list_ui = decision_info.effect.get("show_restriction_list_ui", false)
	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		if prepared_character_action_data_available('gauge_from_hand'):
			var selected_card_ids = prepared_character_action_data['hand_to_gauge_cards']
			var success = game_wrapper.submit_relocate_card_from_hand(Enums.PlayerId.PlayerId_Player, selected_card_ids)
			if success:
				if prepared_character_action_data.get('effect_type') != 'gauge_from_hand' or select_card_destination != "stored_cards":
					prepared_character_action_data = {}
				change_ui_state(UIState.UIState_WaitForGameServer)
		else:
			begin_discard_cards_selection(
				min_amount,
				max_amount,
				UISubState.UISubState_SelectCards_DiscardCardsToGauge,
				false,
				restricted_to_card_ids,
				show_restriction_list_ui
			)
	else:
		ai_choose_card_hand_to_gauge(min_amount, max_amount, restricted_to_card_ids)

func _on_choose_from_boosts(event):
	var player = event['event_player']
	select_card_require_min = game_wrapper.get_decision_info().amount_min
	select_card_require_max = game_wrapper.get_decision_info().amount
	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		_on_player_boost_zone_clicked_zone(false)
		clear_selected_cards()
		var cancel_allowed = false
		if select_card_require_min == 0 or is_tournelouse_transform_bonus_choice() or is_tournelouse_ouroboros_transform_return_choice():
			cancel_allowed = true
		enable_instructions_ui("", true, cancel_allowed)
		change_ui_state(UIState.UIState_SelectCards, UISubState.UISubState_SelectCards_ChooseBoostsToSustain)
	else:
		ai_choose_from_boosts(select_card_require_max)

func _on_choose_from_discard(event):
	var player = event['event_player']
	var limitation = game_wrapper.get_decision_info().limitation
	var destination = game_wrapper.get_decision_info().destination
	var source = game_wrapper.get_decision_info().source
	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		# Show the correct popout window.
		if source == "discard":
			_on_player_discard_button_pressed(false)
		elif source == "gauge":
			_on_player_gauge_gauge_clicked(false)
		elif source == "sealed":
			_on_player_sealed_clicked(false)
		elif source == "overdrive":
			_on_player_overdrive_gauge_clicked(false)
		elif source == "outrun_seal":
			_on_player_discard_button_pressed(false)
		clear_selected_cards()
		select_card_require_min = game_wrapper.get_decision_info().amount_min
		select_card_require_max = game_wrapper.get_decision_info().amount
		if limitation:
			limitation = limitation + " "
		var card_select_count_str = "1 %scard" % limitation
		if select_card_require_min == select_card_require_max and select_card_require_min > 1:
			card_select_count_str = "%s %scards" % [select_card_require_min, limitation]
		elif select_card_require_max > 1:
			card_select_count_str = "%s-%s %scards" % [select_card_require_min, select_card_require_max, limitation]
		var destination_str = destination
		if destination == "deck_noshuffle":
			destination_str = "top deck"
		var special_from_str = ""
		if source == "gauge":
			special_from_str = " from Gauge"
		elif source == "outrun_seal":
			special_from_str = "（可从弃牌或怒气选择）"
		var instruction = "选择 %s 来移动到 %s%s." % [card_select_count_str, destination_str, special_from_str]
		if source == "outrun_seal":
			instruction = "选择至多4张弃牌或怒气来封印。每封印2张，抽1张牌，然后进入选攻击。"
		if destination == "lightningrod_any_space":
			instruction = "从你的弃牌堆中选择一张卡牌放到场地中的一格作为避雷针。"
		var popout_type = CardPopoutType.CardPopoutType_DiscardPlayer
		if source == "sealed":
			popout_type = CardPopoutType.CardPopoutType_SealedPlayer
		elif source == "overdrive":
			popout_type = CardPopoutType.CardPopoutType_OverdrivePlayer
		elif source == "gauge":
			popout_type = CardPopoutType.CardPopoutType_GaugePlayer
		var action = game_wrapper.get_decision_info().action
		if action and action == "overdrive_action":
			# Special text instruction for the overdrive effect.
			instruction = "超载效果:\n从你的超载区中选择一张卡牌弃掉。"
		popout_instruction_info = {
			"popout_type": popout_type,
			"instruction_text": instruction,
			"ok_text": "确定",
			"cancel_text": "",
			"ok_enabled": true,
			"cancel_visible": false,
		}
		var cancel_allowed = false
		if select_card_require_min == 0:
			cancel_allowed = true

		enable_instructions_ui(instruction, true, cancel_allowed)
		change_ui_state(UIState.UIState_SelectCards, UISubState.UISubState_SelectCards_ChooseDiscardToDestination)
	else:
		ai_choose_from_discard(game_wrapper.get_decision_info().amount)

func _on_choose_from_topdeck(event):
	var player = event['event_player']
	var decision_info = game_wrapper.get_decision_info()
	var action_choices = decision_info.action
	var can_pass = decision_info.can_pass
	var look_amount = decision_info.amount
	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		# Online: each client maps itself as Player, only shows own choices
		# Local hotseat / AI: show interface for both players
		begin_choose_from_topdeck(action_choices, look_amount, can_pass)
	else:
		# AI opponent picks randomly
		ai_choose_from_topdeck(action_choices, look_amount, can_pass)

func get_string_for_action_choice(choice):
	match choice:
		"strike":
			return "战斗"
		"strike_after_current":
			return "战斗(在当前加成(s)后)"
		"boost":
			return "Boost"
		"boost_after_current":
			return "加成(在当前加成(s)后)"
		"add_to_hand":
			return "添加到手牌"
		"add_to_gauge":
			return "添加到怒气"
		"add_to_sealed":
			return "添加到封印区"
		"add_to_overdrive":
			return "添加到超载区"
		"add_to_topdeck_under":
			return "添加到牌组顶第2张的位置"
		"add_to_topdeck_under_2":
			return "添加到牌组顶第3张的位置"
		"discard":
			return "丢弃"
		"topdeck":
			return "牌组顶"
	return ""

#	func get_string_for_action_choice(choice):
#	match choice:
#		"strike":
#			return "Strike"
#		"strike_after_current":
#			return "Strike (after current Boost(s))"
#		"boost":
#			return "Boost"
#		"boost_after_current":
#			return "Boost (after current Boost(s))"
#		"add_to_hand":
#			return "Add to Hand"
#		"add_to_gauge":
#			return "Add to Gauge"
#		"add_to_sealed":
#			return "Add to Sealed"
#		"add_to_overdrive":
#			return "Add to Overdrive"
#		"add_to_topdeck_under":
#			return "Add to deck 2nd from top"
#		"add_to_topdeck_under_2":
#			return "Add to deck 3rd from top"
#		"discard":
#			return "Discard"
#		"topdeck":
#			return "Top of Deck"
#	return ""

func begin_choose_from_topdeck(action_choices, look_amount, can_pass, player = Enums.PlayerId.PlayerId_Player):
	current_topdeck_choosing_player = player
	var card_ids = game_wrapper.get_player_top_cards(player, look_amount)
	var card_db = game_wrapper.get_card_database()
	var is_wanderlust_choose = _is_wanderlust_choose_from_topdeck()
	if is_wanderlust_choose:
		var reference_order = _get_deck_reference_order_for_player(player)
		card_ids.sort_custom(func(a, b):
			var card_a = card_db.get_card(a)
			var card_b = card_db.get_card(b)
			var id_a = card_a.definition.get("id", "") if card_a else ""
			var id_b = card_b.definition.get("id", "") if card_b else ""
			var order_a = reference_order.get(id_a, 9999)
			var order_b = reference_order.get(id_b, 9999)
			if order_a == order_b:
				return a < b
			return order_a < order_b
		)
	elif _should_shuffle_choose_from_topdeck_display():
		card_ids.shuffle()
	for card_id in card_ids:
		var card = find_card_on_board(card_id)
		_load_card_front_if_needed(card)
		card.flip_card_to_front(true)
		reparent_to_zone(card, choice_zone_parent)
		if is_wanderlust_choose:
			var logic_card = card_db.get_card(card_id)
			if logic_card:
				var card_str_id = logic_card.definition.get("id", "")
				if card_str_id != "":
					var count = game_wrapper.count_cards_in_deck_and_hand(player, card_str_id)
					card.set_remaining_count(count)

	var button1 = get_string_for_action_choice(action_choices[0])
	var button2 = ""
	var button3 = ""
	if action_choices.size() > 1:
		button2 = get_string_for_action_choice(action_choices[1])
	if action_choices.size() > 2:
		button3 = get_string_for_action_choice(action_choices[2])

	# 「任意数量」变体（海蒂 匕首风暴·三倍插入）：可选择 0..看牌数 张，而不是恰好一张。
	var topdeck_decision_info = game_wrapper.get_decision_info()
	var select_multiple = topdeck_decision_info.select_multiple
	var instruction_text = "Choose a card:"
	if select_multiple:
		instruction_text = "Choose any number of cards (or pass):"

	clear_selected_cards()
	if select_multiple:
		select_card_require_min = max(topdeck_decision_info.amount_min, 0)
		select_card_require_max = max(look_amount, 1)
	else:
		select_card_require_min = 1
		select_card_require_max = 1
	var cancel_allowed = can_pass
	popout_instruction_info = {
		"popout_type": CardPopoutType.CardPopoutType_ChoiceZone,
		"instruction_text": instruction_text,
		"ok_text": button1,
		"ok2_text": button2,
		"ok3_text": button3,
		"cancel_text": "Pass",
		"ok_enabled": true,
		"cancel_visible": can_pass,
	}
	if select_multiple:
		enable_instructions_ui("选择任意数量的卡牌（或跳过）：", false, cancel_allowed, {})
	else:
		enable_instructions_ui("选择一张卡牌：", false, cancel_allowed, {})
	choice_popout_title = "牌库顶"
	if topdeck_decision_info.effect.get("move_selected_directly_to_hand", false):
		choice_popout_title += "（一次确认一张）"
	_on_choice_popout_show_button_pressed()

	change_ui_state(UIState.UIState_SelectCards, UISubState.UISubState_SelectCards_ChooseFromTopdeck)

func _is_wanderlust_choose_from_topdeck() -> bool:
	if game_wrapper == null:
		return false
	var decision_info = game_wrapper.get_decision_info()
	if decision_info == null or decision_info.type != Enums.DecisionType.DecisionType_ChooseFromTopDeck:
		return false
	if decision_info.choice_card_id < 0:
		return false
	var source_card = game_wrapper.get_card_database().get_card(decision_info.choice_card_id)
	if source_card == null:
		return false
	return source_card.definition.get("id", "") == "eugenia_queen_of_hearts"

func _is_meilian_leishenshiyan_choose_from_topdeck() -> bool:
	if game_wrapper == null:
		return false
	var decision_info = game_wrapper.get_decision_info()
	if decision_info == null or decision_info.type != Enums.DecisionType.DecisionType_ChooseFromTopDeck:
		return false
	if decision_info.choice_card_id < 0:
		return false
	var source_card = game_wrapper.get_card_database().get_card(decision_info.choice_card_id)
	if source_card == null:
		return false
	return source_card.definition.get("id", "") == "meilian_leishenshiyan"

func _should_shuffle_choose_from_topdeck_display() -> bool:
	var decision_info = game_wrapper.get_decision_info()
	return decision_info != null and (
		decision_info.effect.get("shuffle_display", false)
		or _is_meilian_leishenshiyan_choose_from_topdeck()
	)

func _get_deck_reference_order_for_player(player : Enums.PlayerId) -> Dictionary:
	var order_map = {}
	var deck_list = game_wrapper.get_player_deck_list(player)
	var card_db = game_wrapper.get_card_database()
	var order_index = 0
	for card in deck_list:
		var logic_card = card_db.get_card(card.id)
		if logic_card == null:
			continue
		var card_str_id = logic_card.definition.get("id", "")
		if card_str_id != "" and not order_map.has(card_str_id):
			order_map[card_str_id] = order_index
			order_index += 1
	return order_map

func _clear_choice_zone_remaining_labels():
	for card in choice_zone_parent.get_children():
		if card and card.has_method("clear_label"):
			card.clear_label()

func _on_choose_opponent_card_to_discard(event):
	var player = event['event_player']
	var decision_info = game_wrapper.get_decision_info()
	var card_ids = decision_info.choice
	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		begin_choose_opponent_card_to_discard(card_ids)
	else:
		ai_choose_opponent_card_to_discard(card_ids)

func begin_choose_opponent_card_to_discard(card_ids):
	clear_choice_zone()
	var card_db = game_wrapper.get_card_database()
	var created_count = 0
	for card_id in card_ids:
		var logic_card : GameCard = card_db.get_card(card_id)
		var copy_card = await create_card(card_id + ChoiceCopyIdRangeStart, logic_card.definition,
			logic_card.get_image_url_index_data(), "", choice_zone_parent, true,
			logic_card.definition['display_name'], logic_card.definition['boost']['display_name'])
		copy_card.set_card_and_focus(OffScreen, 0, CardBase.ReferenceCardScale)
		copy_card.resting_scale = CardBase.ReferenceCardScale
		copy_card.change_state(CardBase.CardState.CardState_Offscreen)
		copy_card.flip_card_to_front(true)
		created_count += 1
		await runtime_yield_for_loading_batch(created_count)

	clear_selected_cards()
	select_card_require_min = 1
	select_card_require_max = 1
	popout_instruction_info = {
		"popout_type": CardPopoutType.CardPopoutType_ChoiceZone,
		"instruction_text": "Choose a card:",
		"ok_text": "Discard",
		"ok2_text": "",
		"cancel_text": "",
		"ok_enabled": true,
		"cancel_visible": false
	}
	enable_instructions_ui("选择一张卡牌：", false, false, {})
	choice_popout_title = "对手的卡牌"
	_on_choice_popout_show_button_pressed(false)

	change_ui_state(UIState.UIState_SelectCards, UISubState.UISubState_SelectCards_ChooseOpponentCardToDiscard)

func _on_discard_event(event):
	var player = event['event_player']
	var discard_id = event['number']
	var from_top = event['extra_info']
	var card = find_card_on_board(discard_id)
	if player == Enums.PlayerId.PlayerId_Player:
		discard_card(card, $PlayerDeck/Discard, $AllCards/PlayerDiscards, true, from_top)
	else:
		discard_card(card, $OpponentDeck/Discard, $AllCards/OpponentDiscards, false, from_top)
	# Time for Tea (Plot Hook) action: trigger the closeup when the
	# opponent discards as the force_for_effect's overall_effect.
	if tea_time_pending and player == Enums.PlayerId.PlayerId_Opponent:
		tea_time_pending = false
		_play_tea_time_entrance()
	update_card_counts()

func find_card_on_board(card_id) -> CardBase:
	# Find a given card among the Hand, Strike, Gauge, Boost, and Discard areas.
	var zones = $AllCards.get_children()
	for zone in zones:
		if zone is Node2D:
			var zone_cards = zone.get_children()
			for zone_card in zone_cards:
				if zone_card.card_id == card_id:
					return zone_card
	assert(false, "ERROR: Unable to find card %s on board." % card_id)
	return null

func get_all_player_cards() -> Array:
	var found_cards = []
	found_cards += $AllCards/PlayerBoosts.get_children()
	found_cards += $AllCards/PlayerDeck.get_children()
	found_cards += $AllCards/PlayerDiscards.get_children()
	found_cards += $AllCards/PlayerGauge.get_children()
	found_cards += $AllCards/PlayerBleach.get_children()
	found_cards += $AllCards/PlayerHand.get_children()
	found_cards += $AllCards/PlayerOverdrive.get_children()
	found_cards += $AllCards/PlayerSealed.get_children()
	found_cards += $AllCards/Striking.get_children()
	return found_cards

func reparent_to_zone(card, zone, from_top : int = 0):
	card.get_parent().remove_child(card)
	zone.add_child(card)
	if from_top > 0:
		# Use negative because this is from the end.
		# Add 1 since -1 would just be on the end where it already is.
		from_top += 1
		zone.move_child(card, -from_top)

func _on_add_to_gauge(event):
	var player = event['event_player']
	var card = find_card_on_board(event['number'])
	make_card_revealed(card)
	var gauge_panel = $PlayerZones/PlayerGauge
	var gauge_card_loc = $AllCards/PlayerGauge
	if player == Enums.PlayerId.PlayerId_Opponent:
		gauge_panel = $OpponentZones/OpponentGauge
		gauge_card_loc = $AllCards/OpponentGauge

	var pos = gauge_panel.get_center_pos()
	var is_player = player == Enums.PlayerId.PlayerId_Player
	if card.get_parent() == $AllCards/PlayerDeck or card.get_parent() == $AllCards/OpponentDeck:
		card.set_card_and_focus(get_deck_button_position(is_player), null, null)
	card.discard_to(pos, CardBase.CardState.CardState_InGauge)
	reparent_to_zone(card, gauge_card_loc)
	layout_player_hand(is_player)
	spawn_damage_popup("+ 怒气", player)
	return SmallNoticeDelay

func _on_add_to_bleach(event):
	var player = event['event_player']
	var card = find_card_on_board(event['number'])
	var panel = $PlayerZones/PlayerBleach
	var card_zone = $AllCards/PlayerBleach
	if player == Enums.PlayerId.PlayerId_Opponent:
		panel = $OpponentZones/OpponentBleach
		card_zone = $AllCards/OpponentBleach
	var facedown = game_wrapper.is_player_bleach_zone_facedown(player)
	if not facedown:
		make_card_revealed(card)
	card.flip_card_to_front(not facedown)
	card.discard_to(panel.get_center_pos(), CardBase.CardState.CardState_InGauge)
	reparent_to_zone(card, card_zone)
	layout_player_hand(player == Enums.PlayerId.PlayerId_Player)
	spawn_damage_popup("+ %s" % game_wrapper.get_player_bleach_zone_name(player), player)
	return SmallNoticeDelay

func _on_add_to_sealed(event):
	var player = event['event_player']
	var card = find_card_on_board(event['number'])
	var sealed_panel = $PlayerZones/PlayerSealed
	var sealed_card_loc = $AllCards/PlayerSealed
	var keep_hidden = false
	var is_zone_secret = game_wrapper.is_player_sealed_area_secret(player)
	if player == Enums.PlayerId.PlayerId_Opponent:
		sealed_panel = $OpponentZones/OpponentSealed
		sealed_card_loc = $AllCards/OpponentSealed
		keep_hidden = game_wrapper.is_player_sealed_area_secret(player)

	if observer_mode:
		keep_hidden = is_zone_secret

	if not keep_hidden:
		_load_card_front_if_needed(card)
	card.flip_card_to_front(not keep_hidden)
	var pos = sealed_panel.get_center_pos()
	var is_player = player == Enums.PlayerId.PlayerId_Player
	if card.get_parent() == $AllCards/PlayerDeck or card.get_parent() == $AllCards/OpponentDeck:
		card.set_card_and_focus(get_deck_button_position(is_player), null, null)
	card.discard_to(pos, CardBase.CardState.CardState_InGauge)
	reparent_to_zone(card, sealed_card_loc)
	layout_player_hand(is_player)

	var display_popup = true
	if 'extra_info' in event:
		display_popup = event['extra_info']
	if display_popup:
		spawn_damage_popup("+ 封印", player)
		return SmallNoticeDelay
	return 0

func _on_add_to_overdrive(event):
	var player = event['event_player']
	var card = find_card_on_board(event['number'])
	make_card_revealed(card)
	var overdrive_panel = $PlayerZones/PlayerOverdrive
	var overdrive_card_loc = $AllCards/PlayerOverdrive
	if player == Enums.PlayerId.PlayerId_Opponent:
		overdrive_panel = $OpponentZones/OpponentOverdrive
		overdrive_card_loc = $AllCards/OpponentOverdrive

	var pos = overdrive_panel.get_center_pos()
	var is_player = player == Enums.PlayerId.PlayerId_Player
	if card.get_parent() == $AllCards/PlayerDeck or card.get_parent() == $AllCards/OpponentDeck:
		card.set_card_and_focus(get_deck_button_position(is_player), null, null)
	card.discard_to(pos, CardBase.CardState.CardState_InGauge)
	reparent_to_zone(card, overdrive_card_loc)
	layout_player_hand(is_player)
	spawn_damage_popup("+ 超驱", player)
	return SmallNoticeDelay

func _on_add_to_stored(event):
	var player = event['event_player']
	var card = find_card_on_board(event['number'])
	var facedown = event['extra_info']
	# If no facedown info in event, check the player's stored zone config (Umina The Sleeper Wakes)
	if facedown == null:
		facedown = game_wrapper._get_player(player).is_stored_zone_facedown()
	if not facedown:
		make_card_revealed(card)

	var is_player = player == Enums.PlayerId.PlayerId_Player
	var stored_pos = get_stored_card_position(is_player)
	card.discard_to(stored_pos, CardBase.CardState.CardState_InDeck)
	reparent_to_zone(card, get_set_aside_zone(is_player))
	layout_player_hand(is_player)

func get_deck_zone(is_player : bool):
	if is_player:
		return $AllCards/PlayerDeck
	else:
		return $AllCards/OpponentDeck

func get_set_aside_zone(is_player : bool):
	if is_player:
		return $AllCards/PlayerSetAside
	else:
		return $AllCards/OpponentSetAside

func _on_add_to_deck(event):
	var player = event['event_player']
	var is_player = player == Enums.PlayerId.PlayerId_Player
	var card = find_card_on_board(event['number'])
	card.flip_card_to_front(false)
	var deck_position = get_deck_button_position(is_player)
	card.discard_to(deck_position, CardBase.CardState.CardState_InDeck)
	reparent_to_zone(card, get_deck_zone(is_player))
	layout_player_hand(is_player)

func _on_set_card_aside(event):
	var player = event['event_player']
	var is_player = player == Enums.PlayerId.PlayerId_Player
	var card = find_card_on_board(event['number'])
	var deck_position = get_deck_button_position(is_player)
	card.discard_to(deck_position, CardBase.CardState.CardState_InDeck)
	reparent_to_zone(card, get_set_aside_zone(is_player))
	layout_player_hand(is_player)

func _on_add_to_hand(event):
	var player = event['event_player']
	var is_player = player == Enums.PlayerId.PlayerId_Player
	var card = find_card_on_board(event['number'])
	card.reset()
	var reveal = is_player
	if observer_mode:
		reveal = false
	if reveal:
		_load_card_front_if_needed(card)
	card.flip_card_to_front(reveal)
	add_card_to_hand(card.card_id, is_player)
	layout_player_hand(is_player)

func _on_draw_event(event):
	var player = event['event_player']
	var card_drawn_id = event['number']
	var is_player = player == Enums.PlayerId.PlayerId_Player
	printlog("CLIENT_DRAW_VISUAL player=%s is_player=%s card=%d ui=%s pending=%d hand=%d" % [
		str(player),
		str(is_player),
		card_drawn_id,
		str(ui_state),
		events_to_process.size(),
		game_wrapper.get_player_hand_size(player),
	])
	draw_card(card_drawn_id, is_player)
	update_card_counts()
	#spawn_damage_popup("Draw", player)

func _on_exceed_event(event):
	var player = event['event_player']
	if player == Enums.PlayerId.PlayerId_Player:
		if 'exceed_animation' in player_deck:
			$PlayerCharacter.set_exceed(true, image_loader, player_deck, player_deck['exceed_animation'])
			move_character_to_arena_square($PlayerCharacter, game_wrapper.get_player_location(Enums.PlayerId.PlayerId_Player), true, Character.CharacterAnim.CharacterAnim_None)
		else:
			$PlayerCharacter.set_exceed(true, image_loader, player_deck)
		player_character_card.exceed(true)
		player_buddy_character_card.exceed(true)
		if player_deck.get('buddy_exceeds'):
			player_buddy_character_card.visible = true
		player_bonus_panel.visible = false
		# Eugenia awaken closeup: only the local Eugenia player sees it.
		_play_awaken_entrance()

	else:
		if 'exceed_animation' in opponent_deck:
			$OpponentCharacter.set_exceed(true, image_loader, opponent_deck, opponent_deck['exceed_animation'])
			move_character_to_arena_square($OpponentCharacter, game_wrapper.get_player_location(Enums.PlayerId.PlayerId_Opponent), true, Character.CharacterAnim.CharacterAnim_None)
		else:
			$OpponentCharacter.set_exceed(true, image_loader, opponent_deck)
		opponent_character_card.exceed(true)
		opponent_buddy_character_card.exceed(true)
		if opponent_deck.get('buddy_exceeds'):
			opponent_buddy_character_card.visible = true
		opponent_bonus_panel.visible = false

	spawn_damage_popup("觉醒！", player)
	return SmallNoticeDelay

func _on_exceed_revert_event(event):
	var player = event['event_player']
	if player == Enums.PlayerId.PlayerId_Player:
		if 'exceed_animation' in player_deck:
			$PlayerCharacter.set_exceed(false, image_loader, player_deck, player_deck['id'])
			move_character_to_arena_square($PlayerCharacter, game_wrapper.get_player_location(Enums.PlayerId.PlayerId_Player), true, Character.CharacterAnim.CharacterAnim_None)
		else:
			$PlayerCharacter.set_exceed(false, image_loader, player_deck)
		player_character_card.exceed(false)
		player_buddy_character_card.exceed(false)
		if player_deck.get('buddy_exceeds'):
			player_buddy_character_card.visible = false

	else:
		if 'exceed_animation' in opponent_deck:
			$OpponentCharacter.set_exceed(false, image_loader, opponent_deck, opponent_deck['id'])
			move_character_to_arena_square($OpponentCharacter, game_wrapper.get_player_location(Enums.PlayerId.PlayerId_Opponent), true, Character.CharacterAnim.CharacterAnim_None)
		else:
			$OpponentCharacter.set_exceed(false, image_loader, opponent_deck)
		opponent_character_card.exceed(false)
		opponent_buddy_character_card.exceed(false)
		if opponent_deck.get('buddy_exceeds'):
			opponent_buddy_character_card.visible = false

	spawn_damage_popup("退出觉醒！", player)
	return SmallNoticeDelay

func _on_become_wide(event):
	var player = event['event_player']
	var character_object
	var deck_def
	if player == Enums.PlayerId.PlayerId_Player:
		character_object = $PlayerCharacter
		deck_def = player_deck
	else:
		character_object = $OpponentCharacter
		deck_def = opponent_deck

	character_object.is_wide = true
	if 'wide_animation' in deck_def:
		character_object.load_character(image_loader, deck_def, deck_def['wide_animation'], false)

		var parent = character_object.get_parent()
		var target_idx = parent.get_children().find($WideCharacterMarker)
		assert(target_idx != -1)
		parent.move_child(character_object, target_idx)

		move_character_to_arena_square(character_object, game_wrapper.get_player_location(player), true, Character.CharacterAnim.CharacterAnim_None)
		update_arena_squares()

	var popup_text = "Expand"
	if event['extra_info']:
		popup_text = event['extra_info']
	spawn_damage_popup("%s!" % popup_text, player)
	return SmallNoticeDelay

func _on_force_start_boost(event):
	var player = event['event_player']
	var valid_zones = event['extra_info']
	var limitation = event['extra_info2']
	var ignore_costs = event['extra_info3'] or false

	var boost_amount = 1
	if event['number'] > 1:
		boost_amount = event['number']

	spawn_damage_popup("加成！", player)
	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		if prepared_character_action_data_available('boost_from_gauge'):
			var boost_card = prepared_character_action_data['boost_card']
			var boost_force = prepared_character_action_data['boost_force']
			var success = game_wrapper.submit_boost(Enums.PlayerId.PlayerId_Player, boost_card, boost_force, use_free_force, get_spent_life_for_force())
			if success:
				prepared_character_action_data = {}
				change_ui_state(UIState.UIState_WaitForGameServer)
		else:
			begin_boost_choosing(false, valid_zones, limitation, ignore_costs, boost_amount)
	else:
		ai_do_boost(valid_zones, limitation, ignore_costs, boost_amount)
	return SmallNoticeDelay

func _on_force_start_strike(event):
	var player = event['event_player']
	var disable_wild_swing = false
	var disable_ex = false
	var require_ex = false
	var silent_pre_strike = event.get('extra_info3', null) == "silent_pre_strike"
	if event['extra_info']: #not null
		disable_wild_swing = event['extra_info']
	if event['extra_info2']:
		disable_ex = event['extra_info2']
	var decision_info = game_wrapper.get_decision_info()
	if decision_info.limitation == "EX":
		require_ex = true
	if not silent_pre_strike:
		spawn_damage_popup("战斗！", player)
	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		if prepared_character_action_data_available('strike'):
			var success = false
			if 'wild_swing' in prepared_character_action_data and prepared_character_action_data['wild_swing']:
				success = game_wrapper.submit_strike(Enums.PlayerId.PlayerId_Player, -1, true, -1)
			else:
				var card_id = prepared_character_action_data['card_id']
				var ex_card_id = prepared_character_action_data['ex_card_id']
				success = game_wrapper.submit_strike(Enums.PlayerId.PlayerId_Player, card_id, false, ex_card_id)
			if success:
				prepared_character_action_data = {}
				change_ui_state(UIState.UIState_WaitForGameServer)
		else:
			begin_strike_choosing(false, false, false, disable_wild_swing, disable_ex, require_ex)
	else:
		ai_forced_strike(disable_wild_swing, disable_ex, require_ex)
	return 0.0 if silent_pre_strike else SmallNoticeDelay

func _on_strike_from_gauge(event):
	var player = event['event_player']
	spawn_damage_popup("战斗！", player)

	var decision_info = game_wrapper.get_decision_info()
	var source = decision_info.source
	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		begin_gauge_strike_choosing(false, false, source)
	else:
		ai_strike_from_gauge(source)
	return SmallNoticeDelay

func _on_strike_opponent_sets_first(event):
	var player = event['event_player']
	spawn_damage_popup("战斗！", player)
	if restore_fast_forwarding:
		return SmallNoticeDelay
	if not observer_mode:
		game_wrapper.submit_strike(player, -1, false, -1, true)
	return SmallNoticeDelay

func _on_strike_opponent_sets_first_defender_set(event):
	var player = event['event_player']
	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		begin_strike_choosing(false, false, true)
	else:
		ai_forced_strike()

func _on_force_wild_swing(event):
	var player = event['event_player']
	spawn_damage_popup("强制疯狂攻击！", player)
	return SmallNoticeDelay

func _on_game_over(event):
	printlog("GAME OVER for %s" % game_wrapper.get_player_name(event['event_player']))
	if not game_wrapper.is_ai_game() and not observer_mode:
		NetworkManager.set_active_remote_match_finished(true)
	game_over_stuff.visible = true
	var normal_game_over = event['number'] in [
		Enums.GameOverReason.GameOverReason_Life,
		Enums.GameOverReason.GameOverReason_Decked,
		Enums.GameOverReason.GameOverReason_Quit,
	]
	game_over_ko_image.visible = normal_game_over
	game_over_label.visible = not normal_game_over
	save_replay_button.visible = replay_saving_enabled
	change_ui_state(UIState.UIState_GameOver, UISubState.UISubState_None)
	_update_buttons()
	var player = event['event_player']
	if player == Enums.PlayerId.PlayerId_Player:
		game_over_label.text = "失败"
	else:
		game_over_label.text = "胜利！"
		if not observer_mode and not restore_fast_forwarding:
			game_wrapper.submit_match_result(player_clock_remaining, opponent_clock_remaining)

func _update_surrender_button_visibility():
	if surrender_button == null:
		return
	surrender_button.visible = not observer_mode and not replay_mode and not exiting and ui_state != UIState.UIState_GameOver
	surrender_button.disabled = surrender_in_progress or network_reconnect_paused

func _on_prepare(event):
	var player = event['event_player']
	printlog("CLIENT_PREPARE_VISUAL player=%s ui=%s pending=%d" % [str(player), str(ui_state), events_to_process.size()])
	spawn_damage_popup("热身！", player)
	return SmallNoticeDelay

func _on_change_cards(event):
	var player = event['event_player']
	spawn_damage_popup("换牌！", player)
	return SmallNoticeDelay

func _on_hand_size_exceeded(event):
	var player = event['event_player']
	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		begin_discard_cards_selection(event['number'], event['number'],UISubState.UISubState_SelectCards_DiscardCards)
	else:
		# AI or other player wait
		ai_discard(event)

func _on_choose_to_discard(event, informative_only : bool):
	var player = event['event_player']
	var amount = event['number']
	var allow_fewer = false or event['extra_info']
	var decision_info = game_wrapper.get_decision_info()
	var can_pass = decision_info.can_pass
	if informative_only or not can_pass:
		if not decision_info.destination in ["reveal", "sealed", "opponent_overdrive", "lightningrod_any_space"]:
			var amount_string = "Forced Discard %s" % str(amount)
			if amount == -1:
				amount_string = "Discard Cards"
			spawn_damage_popup(amount_string, player)
	if not informative_only:
		var limitation = decision_info.limitation
		if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
			if prepared_character_action_data_available("self_discard_choose"):
				var discard_ids = prepared_character_action_data['discard_ids']
				var success = game_wrapper.submit_choose_to_discard(Enums.PlayerId.PlayerId_Player, discard_ids)
				if success:
					prepared_character_action_data = {}
					change_ui_state(UIState.UIState_WaitForGameServer)
			else:
				var min_amount = amount
				var max_amount = amount
				if decision_info.source == "boosts":
					min_amount = decision_info.amount_min
					max_amount = decision_info.amount
				elif amount == -1:
					min_amount = 0
					max_amount = game_wrapper.get_player_hand_size(player)
				elif allow_fewer:
					min_amount = 0
				begin_discard_cards_selection(min_amount, max_amount, UISubState.UISubState_SelectCards_DiscardCards_Choose, can_pass)
		else:
			# AI or other player wait
			ai_choose_to_discard(amount, limitation, can_pass, allow_fewer)
	return SmallNoticeDelay


func change_ui_state(new_state, new_sub_state = null):
	if ui_state == UIState.UIState_GameOver:
		return

	if new_state != null:
		printlog("UI: State change %s to %s" % [UIState.keys()[ui_state], UIState.keys()[new_state]])
		ui_state = new_state
	else:
		printlog("UI: State = %s" % UIState.keys()[ui_state])

	if new_sub_state != null:
		printlog("UI: Sub state change %s to %s" % [UISubState.keys()[ui_sub_state], UISubState.keys()[new_sub_state]])
		ui_sub_state = new_sub_state
	else:
		printlog("UI: Sub state = %s" % UISubState.keys()[ui_sub_state])
	update_card_counts()
	_update_surrender_button_visibility()
	_update_buttons()

	if new_state == UIState.UIState_WaitingOnOpponent or new_state == UIState.UIState_WaitForGameServer:
		# TODO _reset_auto_thinking_emote_timer()
		show_thinking_spinner_in = -1
		current_clock_user = Enums.PlayerId.PlayerId_Unassigned
		clock_delay_remaining = GameTimerClockServerDelay
	elif new_state == UIState.UIState_PlayingAnimation:
		# TODO _reset_auto_thinking_emote_timer()
		current_clock_user = Enums.PlayerId.PlayerId_Unassigned
		clock_delay_remaining = GameTimerClockServerDelay
	else:
		set_player_as_clock_user(Enums.PlayerId.PlayerId_Player)

func set_instructions(text):
	current_instruction_text = text

func update_discard_selection_message_choose():
	if is_tournelouse_ouroboros_hand_choice():
		set_instructions("从手牌选择一张牌转化")
		return

	var decision_info = game_wrapper.get_decision_info()
	var destination = decision_info.destination
	if preparing_character_action:
		destination = prepared_character_action_data['destination']
	var num_remaining = select_card_require_min - len(selected_cards)
	if select_card_require_min == 0:
		num_remaining = select_card_require_max - len(selected_cards)
	if decision_info.source == "boosts" and not preparing_character_action:
		set_instructions("从你的加成区选择至多%s张牌，移至弃牌区，每弃掉1张，威力+2。" % num_remaining)
		return
	var bonus = ""
	if decision_info.bonus_effect and not preparing_character_action:
		var effect_text = GameStrings.get_effect_text(decision_info.bonus_effect, false, false, false, "")
		bonus = "\nfor %s" % effect_text
		if 'per_discard' in decision_info.bonus_effect and decision_info.bonus_effect['per_discard']:
			bonus += " for each"
	if destination == "play_attack":
		set_instructions("选择你手牌中的一张牌，移至出牌区并作为额外攻击打出。")
	else:
		var destination_str = destination
		if destination == "replacement_boost":
			destination_str = game_wrapper.get_replacement_boost_description(Enums.PlayerId.PlayerId_Player)
		var optional_string = ""
		if select_card_require_min == 0:
			optional_string = "至多"
		var source_str = "手牌"
		if decision_info.source == "hand/gauge":
			source_str = "怒气区或手牌"
		if decision_info.limitation and not preparing_character_action:
			if decision_info.limitation == "from_array":
				if decision_info.extra_info == "card_names":
					var card_names = []
					for card_id in decision_info.choice:
						card_names.append(game_wrapper.get_card_database().get_card_name(card_id))
					var card_names_str = '/'.join(card_names)
					if card_names.size() > 2:
						card_names_str = ""
						for i in range(card_names.size()):
							card_names_str += card_names[i]
							if i == card_names.size() - 1:
								break
							if i % 2 == 0:
								card_names_str += "/"
							else:
								card_names_str += "\n"
					set_instructions("再从你的%s中选择%s%s张牌，移至%s。\n可选项：%s" % [source_str, optional_string, num_remaining, destination_str, card_names_str])
				else:
					set_instructions("再从你的%s中选择%s%s张满足%s的牌，移至%s。" % [source_str, optional_string, num_remaining, decision_info.extra_info, destination_str])
			else:
				var limitation_str = decision_info.limitation
				if decision_info.limitation == "range_to_opponent":
					limitation_str = "与对手距离匹配"
				set_instructions("再从你的%s中选择%s%s张%s牌，移至%s%s。" % [source_str, optional_string, num_remaining, limitation_str, destination_str, bonus])
		else:
			set_instructions("再从你的%s中选择%s%s张牌，移至%s%s。" % [source_str, optional_string, num_remaining, destination_str, bonus])

func update_discard_selection_message():
	var num_remaining = select_card_require_min - len(selected_cards)
	set_instructions("再从你的手牌中选择%s张牌来弃置。" % num_remaining)

func update_sustain_selection_message():
	if select_card_require_min == select_card_require_max:
		var num_remaining = select_card_require_min - len(selected_cards)
		if is_tournelouse_transform_bonus_choice():
			set_instructions("再从你的加成中选择%s张牌来封印。" % num_remaining)
		elif is_tournelouse_ouroboros_transform_return_choice():
			set_instructions("从加成区选择一张转化牌回手")
		else:
			set_instructions("再从你的加成中选择%s张牌来维持。" % num_remaining)
	else:
		var num_remaining = select_card_require_max - len(selected_cards)
		set_instructions("至多再从你的加成中选择%s张牌来维持。" % [num_remaining])

func update_discard_to_gauge_selection_message():
	var phrase = "放入你的怒气"
	match select_card_destination:
		"topdeck":
			phrase = "放到你的牌库顶"
		"bottomdeck":
			phrase = "放到你的牌库底（按选择顺序）"
		"deck":
			phrase = "放入你的牌库"
		"stored_cards":
			phrase = "放置"
	if preparing_character_action:
		phrase += " 用于%s" % prepared_character_action_data['action_name']
	if select_card_restriction_ids and select_card_show_restriction_list_ui:
		var cardnames = []
		for card_id in select_card_restriction_ids:
			cardnames.append(game_wrapper.get_card_database().get_card_name(card_id))
		phrase += "。\n可选项：%s" % '/'.join(cardnames)
	if select_card_require_min == select_card_require_max:
		var num_remaining = select_card_require_min - len(selected_cards)
		set_instructions("再从你的手牌中选择%s张牌来%s。" % [num_remaining, phrase])
	else:
		var num_remaining = select_card_require_max - len(selected_cards)
		set_instructions("至多再从你的手牌中选择%s张牌来%s。" % [num_remaining, phrase])

func get_selected_gauge_payment_value() -> int:
	# 选中的怒气卡「最多」能支付的点数（枪灵 = 2 点，其余 = 1 点）。
	# 注意怒气卡是弹性支付：每张最少也贡献 1 点，所以判定请用 get_gauge_generated_range()。
	var gauge_player = game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	var total = 0
	for card in selected_cards:
		total += gauge_player.get_gauge_payment_value(card.card_id)
	return total

func get_selected_gauge_payment_min_value() -> int:
	# 选中的怒气卡「最少」要支付的点数（每张至少 1 点）。
	return selected_cards.size()

func get_gauge_generated_fixed_bonus() -> int:
	# 与选卡无关的固定部分：免费怒气 / 消耗生命 / 封印弃牌。
	var fixed = min(game_wrapper.get_player_free_gauge(Enums.PlayerId.PlayerId_Player), select_card_require_max)
	fixed += get_gauge_from_spent_life()
	if can_seal_for_gauge:
		fixed += int(action_menu.number_panel_current_number / 3.0)
	return fixed

func get_gauge_generated_range() -> Array:
	# 当前选择能支付的点数区间 [最少, 最多]：每张怒气卡至少 1 点、至多其面值（枪灵 2 点）。
	# 「枪灵」因此在只需 1 点时自动作为 1 点、需要 2 点时作为 2 点，不会被当成超付。
	var fixed = get_gauge_generated_fixed_bonus()
	return [fixed + get_selected_gauge_payment_min_value(), fixed + get_selected_gauge_payment_value()]

func get_gauge_generated():
	# 实际会支付的点数（用于显示）：不超过需求上限，能付多少付多少。
	var gauge_range = get_gauge_generated_range()
	if select_card_require_max <= 0:
		return gauge_range[1]
	return clampi(select_card_require_max, gauge_range[0], gauge_range[1])

func gauge_selection_meets_requirement() -> bool:
	# 怒气卡可弹性支付 1..面值 点，所以只要「可支付区间」与「需求区间」有交集就能确认。
	# 对全部面值为 1 的卡，这等价于原先的「点数在 min..max 之间」。
	var gauge_range = get_gauge_generated_range()
	return gauge_range[0] <= select_card_require_max and gauge_range[1] >= select_card_require_min

func update_gauge_selection_message():
	if ui_sub_state == UISubState.UISubState_SelectCards_GaugeForArmor:
		# 用怒气卡顶能量换护甲（没有上限，付得越多护甲越高）：按面值取满，
		# 所以这里直接用选中的合计面值，而不是带需求上限的 get_gauge_generated()。
		var gauge_generated = get_selected_gauge_payment_value()
		var force_generated_str = "%s 点怒气已选择。" % [gauge_generated]
		var damage_after_armor = max(0, force_for_armor_incoming_damage - force_for_armor_amount * gauge_generated)
		var ignore_armor_str = ""
		if force_for_armor_ignore_armor:
			damage_after_armor = force_for_armor_incoming_damage
			ignore_armor_str = "护甲被无视！"
		set_instructions("每花费 1 点怒气提供 +%s 护甲。\n%s\n%s你将受到 %s 点伤害。" % [force_for_armor_amount, force_generated_str, ignore_armor_str, damage_after_armor])
	else:
		var gauge_from_life = get_gauge_from_spent_life()
		var num_remaining = select_card_require_min - get_gauge_generated()
		var discard_reminder = ""
		if enabled_reminder_text:
			discard_reminder = "\n最后选择的牌将位于弃牌堆顶。"
		var life_info = ""
		if can_spend_life_for_gauge and gauge_from_life > 0:
			life_info = "（其中 %s 来自消耗生命）" % gauge_from_life
		elif can_seal_for_gauge and action_menu.number_panel_current_number > 0:
			life_info = "（其中 %s 来自封印弃牌）" % int(action_menu.number_panel_current_number / 3.0)
		set_instructions("再选择%s张怒气牌。%s%s" % [max(0, num_remaining), life_info, discard_reminder])

func update_gauge_for_effect_message():
	var effect_str = ""
	var decision_effect = game_wrapper.get_decision_info().effect
	if preparing_character_action:
		decision_effect = prepared_character_action_data['effect']
	var to_hand = 'spent_cards_to_hand' in decision_effect and decision_effect['spent_cards_to_hand']
	var source_card_name = game_wrapper.get_card_database().get_card_name(game_wrapper.get_decision_info().choice_card_id)
	var is_shunko_payment = decision_effect.get("valid_zone", "gauge") == "bleach" \
			and game_wrapper._get_player(Enums.PlayerId.PlayerId_Player).deck_def.get("id") == "soifon"
	if is_shunko_payment:
		var selected_shunko = len(selected_cards)
		set_instructions("支付至多 %s 张『瞬哄』以获得角色能力的层叠效果。\n已选择 %s 张『瞬哄』。" % [decision_effect['gauge_max'], selected_shunko])
		return
	var gauge_name_str = "怒气"
	if select_gauge_require_card_name:
		gauge_name_str = "怒气中名为 %s 的牌" % select_gauge_require_card_name
	elif select_gauge_valid_card_types:
		gauge_name_str = "怒气中的%s" % '/'.join(select_gauge_valid_card_types)

	if decision_effect['per_gauge_effect']:
		var effect = decision_effect['per_gauge_effect']
		var effect_text = GameStrings.get_effect_text(effect, false, false, false, source_card_name)
		if to_hand:
			effect_str = "至多将 %s 张%s返回你的手牌，每张触发一次：%s。" % [decision_effect['gauge_max'], gauge_name_str, effect_text]
		else:
			effect_str = "至多花费 %s 张%s，每张触发一次：%s。" % [decision_effect['gauge_max'], gauge_name_str, effect_text]
	elif _effect_has_overall_effect(decision_effect):
		var effect = decision_effect['overall_effect']
		var effect_text = GameStrings.get_effect_text(effect, false, false, false, source_card_name)
		if to_hand:
			if effect_text:
				effect_str = "将 %s 张%s返回你的手牌，以获得：%s。" % [decision_effect['gauge_max'], gauge_name_str, effect_text]
			else:
				effect_str = "将 %s 张%s返回你的手牌。" % [decision_effect['gauge_max'], gauge_name_str]
		else:
			effect_str = "花费 %s 张%s，以获得：%s。" % [decision_effect['gauge_max'], gauge_name_str, effect_text]
	# 被动奖励 = 免费怒气 / 消耗生命 / 封印弃牌等与选卡无关的固定部分
	var passive_bonus = get_gauge_generated_fixed_bonus()
	if passive_bonus > 0:
		effect_str += "\n被动奖励提供了 %s 点怒气。" % passive_bonus
	effect_str += "\n已产生 %s 点怒气。" % [get_gauge_generated()]
	# Strip tags that currently aren't supported.
	effect_str = effect_str.replace("[b]", "").replace("[/b]", "")
	set_instructions(effect_str)

func update_gauge_selection_for_cancel_message():
	var num_remaining = select_card_require_min - get_gauge_generated()
	set_instructions("选择%s张怒气牌来使用取消。" % num_remaining)

func get_force_in_selected_cards():
	var card_ids = []
	for card in selected_cards:
		card_ids.append(card.card_id)
	var reason = ""
	if ui_sub_state == UISubState.UISubState_SelectCards_ForceForChange:
		reason = "CHANGE_CARDS"

	var total_force = game_wrapper.get_player_force_for_cards(Enums.PlayerId.PlayerId_Player, card_ids, reason, treat_ultras_as_single_force, use_free_force)
	total_force += get_force_from_spent_life()
	return total_force

func get_force_from_spent_life():
	if can_spend_life_for_force:
		var life_per_force = game_wrapper.get_life_for_force_amount(Enums.PlayerId.PlayerId_Player)
		if life_per_force > 0:
			return action_menu.get_current_number_picker_value() / life_per_force
	return 0

func can_selected_cards_pay_force(force_cost : int, bonus_card_force_value : int = 0):
	var max_force_selected = game_wrapper.get_player_force_cost_reduction(Enums.PlayerId.PlayerId_Player)
	if use_free_force:
		max_force_selected += game_wrapper.get_player_free_force(Enums.PlayerId.PlayerId_Player)
	max_force_selected += get_spent_life_for_force()
	if can_seal_for_force:
		max_force_selected += action_menu.number_panel_current_number
	var flexible_force = 0
	var card_db = game_wrapper.get_card_database()
	var force_player = game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	for card in selected_cards:
		var value_of_card = card_db.get_card_force_value(card.card_id)
		if force_player.deck_def.get("id") == "soifon" and force_player.is_card_in_bleach(card.card_id):
			value_of_card = 1
		elif force_player.is_card_in_gauge(card.card_id):
			value_of_card = max(value_of_card, force_player.get_gauge_card_force_value_for(card.card_id))
		max_force_selected += value_of_card
		flexible_force += max(0, value_of_card - 1)
	flexible_force += max(0, bonus_card_force_value - 1)
	max_force_selected += bonus_card_force_value
	var min_force_selected = max_force_selected - flexible_force
	for i in range(min_force_selected, max_force_selected + 1):
		if i == force_cost:
			return true
	return false


func update_force_generation_message():
	var force_selected = get_force_in_selected_cards()
	var force_from_free_bonus = game_wrapper.get_player_force_cost_reduction(Enums.PlayerId.PlayerId_Player)
	if use_free_force:
		var reason = ""
		if ui_sub_state == UISubState.UISubState_SelectCards_ForceForChange:
			reason = "CHANGE_CARDS"
		force_from_free_bonus += game_wrapper.get_player_free_force(Enums.PlayerId.PlayerId_Player, reason)

	var extra_force_source_strings = []
	if force_from_free_bonus > 0:
		extra_force_source_strings.append("%s 来自被动奖励" % force_from_free_bonus)
	if can_spend_life_for_force:
		extra_force_source_strings.append("%s 来自消耗生命" % get_force_from_spent_life())
	if can_seal_for_force and action_menu.number_panel_current_number > 0:
		extra_force_source_strings.append("%s 来自封印弃牌" % action_menu.number_panel_current_number)
	var force_from_free_string = ""
	if len(extra_force_source_strings) > 0:
		force_from_free_string = "（%s）" % ", ".join(extra_force_source_strings)

	var force_generated_str = "已产生 %s 点能量%s。" % [force_selected, force_from_free_string]
	match ui_sub_state:
		UISubState.UISubState_SelectCards_MoveActionGenerateForce, UISubState.UISubState_SelectCards_CharacterAction_Force:
			set_instructions("选择牌来产生 %s 点能量。\n%s" % [select_card_require_force, force_generated_str])
		UISubState.UISubState_SelectCards_ForceForBoost:
			set_instructions("选择牌来产生 %s 点能量，以支付此次加成。\n%s" % [select_card_require_force, force_generated_str])
		UISubState.UISubState_SelectCards_ForceForChange:
			set_instructions("选择牌来产生能量，以抽取新牌。\n%s" % [force_generated_str])
		UISubState.UISubState_SelectCards_ForceForArmor:
			var damage_after_armor = max(0, force_for_armor_incoming_damage - force_for_armor_amount * force_selected)
			var ignore_armor_str = ""
			if force_for_armor_ignore_armor:
				damage_after_armor = force_for_armor_incoming_damage
				ignore_armor_str = "护甲被无视！"
			set_instructions("选择牌来产生能量，每点提供 +%s 护甲。\n%s\n%s你将受到 %s 点伤害。" % [force_for_armor_amount, force_generated_str, ignore_armor_str, damage_after_armor])
		UISubState.UISubState_SelectCards_StrikeForce:
			set_instructions("选择牌来为此次战斗产生 %s 点能量。\n%s" % [select_card_require_force, force_generated_str])
		UISubState.UISubState_SelectCards_ForceForEffect:
			var effect_str = ""
			var decision_effect = game_wrapper.get_decision_info().effect
			if preparing_character_action:
				decision_effect = prepared_character_action_data['effect']
			var source_card_name = game_wrapper.get_card_database().get_card_name(game_wrapper.get_decision_info().choice_card_id)
			if decision_effect['per_force_effect']:
				var effect = decision_effect['per_force_effect']
				var effect_text = GameStrings.get_effect_text(effect, false, false, false, source_card_name)
				var force_str = "至多 %s" % decision_effect['force_max']
				if decision_effect['force_max'] == -1:
					force_str = "任意数量的"
				var per_force_str = "能量"
				if 'force_effect_interval' in decision_effect:
					per_force_str = "%s 点能量" % decision_effect['force_effect_interval']
				effect_str = "产生%s点能量，以每%s触发一次：%s。" % [force_str, per_force_str, effect_text]
			elif _effect_has_overall_effect(decision_effect):
				var effect = decision_effect['overall_effect']
				var effect_text = GameStrings.get_effect_text(effect, false, false, false, source_card_name)
				effect_str = "产生 %s 点能量，以获得：%s。" % [decision_effect['force_max'], effect_text]
			if 'force_discard_reminder' in decision_effect and decision_effect['force_discard_reminder']:
				effect_str += "\n最后选择的牌将位于弃牌堆顶。"
			effect_str += "\n%s" % [force_generated_str]
			set_instructions(effect_str)

func enable_instructions_ui(
	message,
	can_ok,
	can_cancel,
	strike_options = {},
	can_ex : bool = true,
	choices = [],
	show_number_picker : bool = false,
	extra_choice_text = [],
	require_ex = false,
	face_attack_card = null,
	alternative_life_cost : int = 0
	):
	set_instructions(message)
	instructions_ok_allowed = can_ok
	instructions_cancel_allowed = can_cancel
	instructions_strike_options = strike_options
	instructions_pay_alternative_life_cost = alternative_life_cost
	instructions_ex_allowed = can_ex
	instructions_ex_required = require_ex
	current_effect_choices = choices if choices != null else []
	current_effect_extra_choice_text = extra_choice_text if extra_choice_text != null else []
	instructions_number_picker_min = -1
	instructions_number_picker_max = -1
	instructions_face_attack_card = face_attack_card
	if show_number_picker:
		instructions_number_picker_min = game_wrapper.get_decision_info().amount_min
		instructions_number_picker_max = game_wrapper.get_decision_info().amount

func begin_discard_cards_selection(
	number_to_discard_min,
	number_to_discard_max,
	next_sub_state,
	can_cancel_always : bool = false,
	restricted_to_card_ids = [],
	show_restriction_list_ui = false
):
	clear_selected_cards()
	select_card_require_min = number_to_discard_min
	select_card_require_max = number_to_discard_max
	select_card_restriction_ids = restricted_to_card_ids
	select_card_show_restriction_list_ui = show_restriction_list_ui
	var cancel_allowed = number_to_discard_min == 0 or can_cancel_always
	enable_instructions_ui("", true, cancel_allowed)
	change_ui_state(UIState.UIState_SelectCards, next_sub_state)

func begin_generate_force_selection(amount, can_cancel : bool = true, wild_swing_allowed : bool = false, ex_discard_order_checkbox : bool = false, skip_zsolt_popup : bool = false):
	# Show the gauge window.
	_on_player_gauge_gauge_clicked(false)
	treat_ultras_as_single_force = false
	discard_ex_first_for_strike = true
	var required_force = amount
	var reason = ""
	if ui_sub_state == UISubState.UISubState_SelectCards_ForceForChange:
		reason = "CHANGE_CARDS"
	# Zsolt Battle Instinct: let player choose how much free force to use
	var p = game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	# Treasure exceeded UA: on your turn, each boost action gets -1 Force cost.
	if ui_sub_state == UISubState.UISubState_SelectCards_ForceForBoost \
			and p.deck_def.get("id") == "treasure" \
			and p.exceeded \
			and game_wrapper.get_active_player() == Enums.PlayerId.PlayerId_Player:
		required_force = max(0, required_force - 1)
	# During strike resolution, auto-use the pool to avoid await freeze
	var in_strike = game_wrapper.has_active_strike()
	if p.zsolt_force_pool > 0 and in_strike and not skip_zsolt_popup:
		p.free_force = p.zsolt_force_pool if required_force <= 0 else min(p.zsolt_force_pool, required_force)
	if p.zsolt_force_pool > 0 and not skip_zsolt_popup and not in_strike:
		await _choose_zsolt_free_force_from_pool(p)
	use_free_force = game_wrapper.get_player_free_force(Enums.PlayerId.PlayerId_Player, reason) > 0
	can_spend_life_for_force = game_wrapper.get_life_for_force_amount(Enums.PlayerId.PlayerId_Player) > 0
	can_seal_for_force = p.deck_def.get("id") == "minato" and not p.exceeded and p.discards.size() > 0
	current_pay_costs_is_ex = ex_discard_order_checkbox
	action_menu.set_force_ultra_toggle(false)
	action_menu.set_discard_ex_first_toggle(true)
	action_menu.set_free_force_toggle(use_free_force)

	clear_selected_cards()
	select_card_require_force = required_force
	var strike_options = {
		"wild_swing_allowed": wild_swing_allowed,
	}
	enable_instructions_ui("", true, can_cancel, strike_options)

	change_ui_state(UIState.UIState_SelectCards)
	update_force_generation_message()

func _choose_zsolt_free_force_from_pool(player):
	player.free_force = 0
	var pool_amount = player.zsolt_force_pool
	current_action_menu_choices = []
	for i in range(pool_amount + 1):
		current_action_menu_choices.append({"action": func(): pass})
	var previous_popout_instruction_info = popout_instruction_info
	popout_instruction_info = {
		"popout_type": CardPopoutType.CardPopoutType_GaugePlayer,
		"instruction_text": "选择本次要使用的免费能量数量（0-%s）。" % pool_amount,
		"ok_text": "",
		"cancel_text": "",
		"ok_enabled": false,
		"cancel_visible": false,
	}
	_on_player_gauge_gauge_clicked(false)
	var options = []
	for i in range(pool_amount + 1):
		options.append({"text": str(i)})
	action_menu.set_choices("使用多少免费能量?", options, false, -1, -1, false, false, false)
	action_menu.visible = true
	var idx = await action_menu.choice_selected
	popout_instruction_info = previous_popout_instruction_info
	close_popout()
	player.free_force = idx

func begin_gauge_selection(
	amount : int,
	wild_swing_allowed : bool,
	sub_state : UISubState,
	enable_reminder : bool = false,
	ex_discard_order_checkbox : bool = false,
	alternative_life_cost : int = 0
	):
	# Show the gauge window.
	_on_player_gauge_gauge_clicked(false)
	clear_selected_cards()
	current_pay_costs_is_ex = ex_discard_order_checkbox
	discard_ex_first_for_strike = true
	action_menu.set_discard_ex_first_toggle(true)
	enabled_reminder_text = true if enable_reminder else false
	if amount != -1:
		select_card_require_min = amount
		select_card_require_max = amount
	var seal_p = game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	can_seal_for_gauge = seal_p.deck_def.get("id") == "minato" and not seal_p.exceeded and seal_p.discards.size() >= 3
	var cancel_allowed = false
	match sub_state:
		UISubState.UISubState_SelectCards_Exceed, UISubState.UISubState_SelectCards_BoostCancel, UISubState.UISubState_SelectCards_CharacterAction_Gauge, UISubState.UISubState_SelectCards_GaugeForBoost:
			cancel_allowed = true
		UISubState.UISubState_SelectCards_GaugeForEffect:
			var decision_info = game_wrapper.get_decision_info()
			cancel_allowed = select_card_require_min == 0 or preparing_character_action or decision_info.effect.get("can_pass", false)
	var strike_options = {
		"wild_swing_allowed": wild_swing_allowed,
	}
	enable_instructions_ui(
		"",
		true,
		cancel_allowed,
		strike_options,
		true,
		[],
		false,
		[],
		false,
		null,
		alternative_life_cost
	)

	change_ui_state(UIState.UIState_SelectCards, sub_state)

func begin_effect_choice(choices, instruction_text : String, extra_choice_text, can_cancel = false):
	enable_instructions_ui(instruction_text, false, can_cancel, {}, false, choices, false, extra_choice_text)
	change_ui_state(UIState.UIState_MakeChoice, UISubState.UISubState_None)

func begin_strike_choosing(
	strike_response : bool,
	cancel_allowed : bool,
	opponent_sets_first : bool = false,
	disable_wild_swing : bool = false,
	disable_ex : bool = false,
	require_ex = false
):
	clear_selected_cards()
	select_card_require_min = 1
	select_card_require_max = 1
	var can_cancel = cancel_allowed and not strike_response
	var character_action_str = ""
	if preparing_character_action:
		character_action_str = "，使用%s" % prepared_character_action_data['action_name']
	var attack_string = "一张牌"
	if require_ex:
		attack_string = "一张EX攻击"
	var dialogue = "选择%s来进行战斗%s。" % [attack_string, character_action_str]
	var cards_that_will_not_hit = game_wrapper.get_will_not_hit_card_names(Enums.PlayerId.PlayerId_Player)
	if cards_that_will_not_hit.size() > 0:
		for card in cards_that_will_not_hit:
			dialogue += "\n" + card + " 不会击中。"
	var cards_invalid_during_strike = game_wrapper.get_invalid_card_names(Enums.PlayerId.PlayerId_Player)
	if cards_invalid_during_strike.size() > 0:
		for card in cards_invalid_during_strike:
			dialogue += "\n" + card + " 无效。"
	var plague_knight_discard_names = game_wrapper.get_plague_knight_discard_names(Enums.PlayerId.PlayerId_Opponent)
	if plague_knight_discard_names.size() > 0:
		for card in plague_knight_discard_names:
			dialogue += "\nPlague Knight 弃置了 " + card + "。"
	var face_attack_card = game_wrapper.get_face_attack_card(Enums.PlayerId.PlayerId_Player)
	var extra_strike_options_count = game_wrapper.get_player_extra_strike_options_count(Enums.PlayerId.PlayerId_Player)
	var strike_options = {
		"wild_swing_allowed": not disable_wild_swing,
		"extra_strike_options_count": extra_strike_options_count
	}
	enable_instructions_ui(dialogue, true, can_cancel, strike_options, not disable_ex,
		[], false, [], require_ex, face_attack_card)
	var new_sub_state
	if strike_response:
		if opponent_sets_first:
			new_sub_state = UISubState.UISubState_SelectCards_OpponentSetsFirst_StrikeResponseCard
		else:
			new_sub_state = UISubState.UISubState_SelectCards_StrikeResponseCard
	else:
		if opponent_sets_first:
			new_sub_state = UISubState.UISubState_SelectCards_OpponentSetsFirst_StrikeCard
		else:
			new_sub_state = UISubState.UISubState_SelectCards_StrikeCard
	change_ui_state(UIState.UIState_SelectCards, new_sub_state)

func begin_gauge_strike_choosing(strike_response : bool, cancel_allowed : bool, source : String):
	# Show the correct window.
	if source == "gauge":
		_on_player_gauge_gauge_clicked(false)
	elif source == "sealed":
		_on_player_sealed_clicked(false)

	clear_selected_cards()
	select_card_require_min = 1
	select_card_require_max = 1
	var can_cancel = cancel_allowed and not strike_response
	enable_instructions_ui("从%s中选择一张牌来进行战斗。" % source, true, can_cancel)
	var new_sub_state
	if strike_response:
		# Is there any character that does this? will need new sub-state if so
		assert(false)
	else:
		if source == "gauge":
			new_sub_state = UISubState.UISubState_SelectCards_StrikeCard_FromGauge
		elif source == "sealed":
			new_sub_state = UISubState.UISubState_SelectCards_StrikeCard_FromSealed
	change_ui_state(UIState.UIState_SelectCards, new_sub_state)

func begin_boost_choosing(can_cancel : bool, valid_zones : Array, limitation : String, ignore_costs : bool, boost_amount : int):
	clear_selected_cards()
	selected_boost_facedown_override = null
	var count_str = "一张"
	var plural = ""
	select_card_require_min = 1
	if boost_amount <= 1:
		select_card_require_max = 1
	else:
		select_card_require_max = boost_amount
		count_str = "至多 %s 张" % boost_amount
		plural = "(s)"
	select_boost_options = {
		"can_cancel": can_cancel,
		"valid_zones": valid_zones,
		"limitation": limitation,
		"ignore_costs": ignore_costs,
		"boost_amount": boost_amount
	}
	var limitation_str = "card%s" % plural
	if limitation and limitation != "transform":
		limitation_str = limitation + " boost%s" % plural
	var character_action_str = ""
	if preparing_character_action:
		character_action_str = "，用于%s" % prepared_character_action_data['action_name']
	var zone_str = '/'.join(valid_zones)

	var available_boost_actions = []
	if game_wrapper.can_do_boost(Enums.PlayerId.PlayerId_Player):
		available_boost_actions.append("boost")
	if game_wrapper.can_do_ex_transform(Enums.PlayerId.PlayerId_Player):
		available_boost_actions.append("transform")
	var available_boost_action_str = '/'.join(available_boost_actions)
	if limitation == "transform":
		available_boost_action_str = "transform"

	var instructions = "从%s中选择%s%s来%s%s。" % [zone_str, count_str, limitation_str, available_boost_action_str, character_action_str]
	if 'gauge' in valid_zones:
		_on_player_gauge_gauge_clicked(false)
	elif 'discard' in valid_zones: # can't open two zones at once
		_on_player_discard_button_pressed(false)
	elif 'extra' in valid_zones:
		_on_player_buddy_button_pressed(true, false)
	elif 'deck' in valid_zones:
		var deck_card_ids = game_wrapper.get_player_deck_card_ids_for_boost(Enums.PlayerId.PlayerId_Player, limitation)
		for card_id in deck_card_ids:
			var card = find_card_on_board(card_id)
			if card:
				_load_card_front_if_needed(card)
				card.flip_card_to_front(true)
				reparent_to_zone(card, choice_zone_parent)
		choice_popout_title = "牌库"
		_on_choice_popout_show_button_pressed(false)

	enable_instructions_ui(instructions, true, can_cancel)
	change_ui_state(UIState.UIState_SelectCards, UISubState.UISubState_SelectCards_PlayBoost)

func _on_move_event(event):
	var player = event['event_player']
	var other_player = game_wrapper.other_player(player)
	var other_player_location = game_wrapper.get_player_location(other_player)
	var move_amount = event['extra_info']
	var destination = event['number']
	var move_anim = Character.CharacterAnim.CharacterAnim_WalkForward
	var original_position = event['extra_info2']
	var is_far = abs(original_position - destination) >= 2
	var is_forward = ((destination > original_position and other_player_location > original_position)
		or (destination < original_position and other_player_location < original_position))
	match event['reason']:
		"advance":
			spawn_damage_popup("前进 %s" % str(move_amount), player)
			move_anim = Character.CharacterAnim.CharacterAnim_WalkForward
			if is_far:
				move_anim = Character.CharacterAnim.CharacterAnim_Run
		"close":
			spawn_damage_popup("逼近 %s" % str(move_amount), player)
			move_anim = Character.CharacterAnim.CharacterAnim_WalkForward
			if is_far:
				move_anim = Character.CharacterAnim.CharacterAnim_Run
		"move":
			spawn_damage_popup("移动", player)
			if is_forward:
				move_anim = Character.CharacterAnim.CharacterAnim_WalkForward
				if is_far:
					move_anim = Character.CharacterAnim.CharacterAnim_Run
			else:
				move_anim = Character.CharacterAnim.CharacterAnim_WalkBackward
				if is_far:
					move_anim = Character.CharacterAnim.CharacterAnim_DashBack
		"push":
			spawn_damage_popup("被击退 %s" % str(move_amount), player)
			move_anim = Character.CharacterAnim.CharacterAnim_Pushed
		"pull":
			spawn_damage_popup("被拉近 %s" % str(move_amount), player)
			move_anim = Character.CharacterAnim.CharacterAnim_Pulled
		"retreat":
			spawn_damage_popup("后退 %s" % str(move_amount), player)
			move_anim = Character.CharacterAnim.CharacterAnim_WalkBackward
			if is_far:
				move_anim = Character.CharacterAnim.CharacterAnim_DashBack

	#spawn_damage_popup("Move", player)
	if player == Enums.PlayerId.PlayerId_Player:
		move_character_to_arena_square($PlayerCharacter, destination, false,  move_anim)
		cached_player_location = game_wrapper.get_player_location(Enums.PlayerId.PlayerId_Player)
	else:
		move_character_to_arena_square($OpponentCharacter, destination, false, move_anim)
		cached_opponent_location = game_wrapper.get_player_location(Enums.PlayerId.PlayerId_Opponent)

	update_arena_squares()
	return MoveDelay

func _on_mulligan_decision(event):
	var player = event['event_player']
	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		if not game_wrapper.get_player_mulligan_complete(player) and not _is_local_mulligan_selection_context():
			clear_selected_cards()
			mulligan_selected_card_ids_tmp = []
			select_card_require_min = 1
			select_card_require_max = game_wrapper.get_player_hand_size(player)
			var can_cancel = true
			enable_instructions_ui("选择要调度的牌。", true, can_cancel)
			change_ui_state(UIState.UIState_SelectCards, UISubState.UISubState_SelectCards_Mulligan)
		elif game_wrapper.get_player_mulligan_complete(player):
			mulligan_selected_card_ids_tmp = []
	elif game_wrapper.is_ai_game():
		ai_mulligan_decision()

func _on_reshuffle_discard(event):
	var player = event['event_player']
	spawn_damage_popup("洗牌！", player)
	if player == Enums.PlayerId.PlayerId_Player:
		var cards = $AllCards/PlayerDiscards.get_children()
		for card in cards:
			card.get_parent().remove_child(card)
			$AllCards/PlayerDeck.add_child(card)
			card.flip_card_to_front(false)
			card.reset(OffScreen)
	else:
		var cards = $AllCards/OpponentDiscards.get_children()
		for card in cards:
			card.get_parent().remove_child(card)
			$AllCards/OpponentDeck.add_child(card)
			card.flip_card_to_front(false)
			card.reset(OffScreen)
		# Show opponent's reshuffle cards
		reference_popout_toggle_enabled = true
		opponent_cards_before_reshuffle = event['extra_info']
	close_popout()
	update_card_counts()
	return SmallNoticeDelay

func _on_shuffle_deck(event):
	var player = event['event_player']
	if player == Enums.PlayerId.PlayerId_Player:
		update_eyes_on_hand_icons()

func _on_reshuffle_discard_in_place(event):
	var player = event['event_player']
	var card_parent
	if player == Enums.PlayerId.PlayerId_Player:
		card_parent = $AllCards/PlayerDiscards
	else:
		card_parent = $AllCards/OpponentDiscards
	var cards = card_parent.get_children()
	var new_order = {}

	for card in cards:
		var card_index = game_wrapper.get_card_index_in_discards(player, card.card_id)
		new_order[card_index] = card
	for i in range(len(new_order)):
		card_parent.move_child(new_order[i], i)

func _on_reshuffle_deck_mulligan(_event):
	#printlog("UI: TODO: In place reshuffle deck. No cards actually move though.")
	pass

func reset_revealed_cards():
	var current_children = $AllCards/OpponentRevealed.get_children()
	for i in range(len(current_children)-1, -1, -1):
		var card = current_children[i]
		card.get_parent().remove_child(card)
		card.queue_free()

func add_revealed_card(card_id : int):
	var card_db = game_wrapper.get_card_database()
	var logic_card : GameCard = card_db.get_card(card_id)
	var copy_card = await create_card(card_id + RevealCopyIdRangeStart, logic_card.definition, logic_card.get_image_url_index_data(),
		"", $AllCards/OpponentRevealed, true, logic_card.definition['display_name'], logic_card.definition['boost']['display_name'])
	copy_card.set_card_and_focus(OffScreen, 0, CardBase.ReferenceCardScale)
	copy_card.resting_scale = CardBase.ReferenceCardScale
	copy_card.change_state(CardBase.CardState.CardState_Offscreen)
	copy_card.flip_card_to_front(true)

func _on_reveal_card_from_hand(event):
	var player = event['event_player']
	# Renea: if this is a facedown boost reveal, flip the card visual face-up.
	# Hand reveals must stay hidden in the hand zone because the engine already
	# tracks them as known cards for the public hand display.
	var reveal_card = find_card_on_board(event['number'])
	if reveal_card:
		var parent_zone = reveal_card.get_parent()
		var in_hand_zone = parent_zone == $AllCards/PlayerHand or parent_zone == $AllCards/OpponentHand
		if not in_hand_zone:
			make_card_revealed(reveal_card)
	spawn_damage_popup("卡牌已展示！", player)
	if player == Enums.PlayerId.PlayerId_Player:
		update_eyes_on_hand_icons()
	return SmallNoticeDelay

func _on_reveal_hand(event):
	var player = event['event_player']
	spawn_damage_popup("手牌已展示！", player)
	if player == Enums.PlayerId.PlayerId_Player:
		update_eyes_on_hand_icons()
	return SmallNoticeDelay

func _on_reveal_random_gauge(event):
	var player = event['event_player']
	spawn_damage_popup("随机怒气牌！", player)

	return SmallNoticeDelay

func _on_reveal_topdeck(event):
	var player = event['event_player']
	spawn_damage_popup("牌库顶已展示！", player)
	if player == Enums.PlayerId.PlayerId_Player:
		update_eyes_on_hand_icons()
	return SmallNoticeDelay

func _on_swap_deck_and_discard(event):
	var player = event['event_player']
	var is_player = player == Enums.PlayerId.PlayerId_Player
	var deck_zone = $AllCards/PlayerDeck if is_player else $AllCards/OpponentDeck
	var discard_zone = $AllCards/PlayerDiscards if is_player else $AllCards/OpponentDiscards
	var discard_button = $PlayerDeck/Discard if is_player else $OpponentDeck/Discard

	var deck_cards = deck_zone.get_children()
	var discard_cards_arr = discard_zone.get_children()

	for card in deck_cards:
		if card is CardBase:
			make_card_revealed(card)
			var pos = get_discard_location(discard_button)
			card.discard_to(pos, CardBase.CardState.CardState_Discarded)
			reparent_to_zone(card, discard_zone)

	for card in discard_cards_arr:
		if card is CardBase:
			card.flip_card_to_front(false)
			reparent_to_zone(card, deck_zone)

	update_card_counts()
	if not is_player:
		reference_popout_toggle_enabled = true
		opponent_cards_before_reshuffle = event.get("extra_info", [])
	if is_player:
		layout_player_hand(true)
	else:
		layout_player_hand(false)
	return SmallNoticeDelay

func _move_card_to_strike_area(card, strike_area, new_parent, is_player : bool, is_ex : bool):
	if card.state == CardBase.CardState.CardState_InStrike:
		return

	card.set_position_if_at_position(OffScreen, get_deck_button_position(is_player))
	var pos = strike_area.global_position + strike_area.size * strike_area.scale /2
	if is_ex:
		pos.x += CardBase.get_hand_card_size().x
	card.discard_to(pos, CardBase.CardState.CardState_InStrike)
	card.get_parent().remove_child(card)
	new_parent.add_child(card)
	layout_player_hand(is_player)

func _on_strike_started(event, is_ex : bool, is_wild : bool = false):
	# Per-strike animation flags reset on every attack-card-set event (both
	# initiator and responder events pass through here, so reset unconditionally
	# to preserve the original behavior).
	cats_cradle_left_played_this_strike = false
	cats_cradle_right_played_this_strike = false
	cats_cradle_left_pending_this_strike = false
	cats_cradle_right_pending_this_strike = false
	cats_cradle_hit_played_this_strike = false
	qoh_left_played_this_strike = false
	qoh_right_played_this_strike = false
	qoh_left_pending_this_strike = false
	qoh_right_pending_this_strike = false
	qoh_damage_effect_played_this_strike = false
	wild_hunt_left_played_this_strike = false
	wild_hunt_right_played_this_strike = false
	wild_hunt_damage_played_this_strike = false
	purification_left_played_this_strike = false
	purification_right_played_this_strike = false
	purification_damage_played_this_strike = false
	judgment_left_played_this_strike = false
	judgment_right_played_this_strike = false
	judgment_damage_played_this_strike = false
	crusader_left_played_this_strike = false
	crusader_right_played_this_strike = false
	crusader_damage_played_this_strike = false
	heart_left_played_this_strike = false
	heart_right_played_this_strike = false
	heart_damage_played_this_strike = false
	descent_left_played_this_strike = false
	descent_right_played_this_strike = false
	descent_damage_played_this_strike = false
	fatal_eye_played_this_strike = false
	# The tracked attack-card set is only cleared when the INITIATOR sets their
	# card (new strike); responder events just append their card to the set.
	if event['event_type'] in [
		Enums.EventType.EventType_Strike_Started,
		Enums.EventType.EventType_Strike_Started_Ex,
		Enums.EventType.EventType_Strike_RandomGaugeStrike,
	]:
		strike_attack_card_ids = []
		strike_activated_card_ids = []
		# A new MAIN strike begins: the extra-attack flag is reset here so
		# later extra attacks (chain attacks) can be distinguished.
		strike_is_extra_attack = false
	if event['number'] not in strike_attack_card_ids:
		strike_attack_card_ids.append(event['number'])
	var player = event['event_player']
	var card = find_card_on_board(event['number'])
	var immediate_reveal_event = false
	match event['event_type']:
		Enums.EventType.EventType_Strike_PayCost_Unable:
			immediate_reveal_event = true
	var reveal_immediately = immediate_reveal_event or event['extra_info'] == true
	if reveal_immediately:
		make_card_revealed(card)

	var is_ex_strike = 'extra_info2' in event and event['extra_info2']
	if is_ex_strike:
		_set_card_bonus(event['number'], "ex")
	if is_wild:
		_set_card_bonus(event['number'], "wild")

	if player == Enums.PlayerId.PlayerId_Player:
		_move_card_to_strike_area(card, $PlayerStrike/StrikeZone, $AllCards/Striking, true, is_ex)
	else:
		# Opponent started strike, player has to respond.
		_move_card_to_strike_area(card, $OpponentStrike/StrikeZone, $AllCards/Striking, false, is_ex)

func _on_strike_started_extra_attack(event):
	var player = event['event_player']
	var card = find_card_on_board(event['number'])
	strike_is_extra_attack = true
	if event['number'] not in strike_attack_card_ids:
		strike_attack_card_ids.append(event['number'])
	# Immediately reveal it.
	make_card_revealed(card)
	if player == Enums.PlayerId.PlayerId_Player:
		_move_card_to_strike_area(card, $PlayerStrike/StrikeZone, $AllCards/Striking, true, false)
	else:
		_move_card_to_strike_area(card, $OpponentStrike/StrikeZone, $AllCards/Striking, false, false)


func _on_strike_do_response_now(event):
	var player = event['event_player']
	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		begin_strike_choosing(true, false)
	else:
		ai_strike_response()

func _on_strike_opponent_sets_first_initiator_set(event):
	var player = event['event_player']
	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		begin_strike_choosing(true, false, true)
	else:
		# Pass flag to indicate this is the initiator setting after opponent.
		ai_strike_response(true)

func make_card_revealed(card):
	_load_card_front_if_needed(card)
	card.flip_card_to_front(true)

	# Update hand icons for cards owned by the player.
	var logic_card = game_wrapper.get_card_database().get_card(card.card_id)
	var owner_player = logic_card.owner_id
	if owner_player == Enums.PlayerId.PlayerId_Player:
		update_eyes_on_hand_icons()

func _on_strike_reveal(_event):
	var strike_cards = $AllCards/Striking.get_children()
	for card in strike_cards:
		make_card_revealed(card)
	return StrikeRevealDelay

func _on_strike_reveal_one_player(event):
	var player = event['event_player']
	spawn_damage_popup("战斗牌正面朝上！", player)
	# Iaquis initial-skill face-attack closeup: plays when the Iaquis player
	# chooses the face-up strike (reveal_strike from the initial ability). Both
	# clients replay this event, so both see it. Also marks the strike for the
	# stun easter-egg.
	if _is_player_iaquis(player):
		iaquis_faceup_this_strike = true
		_play_iaquis_faceup(false)
	# Reveal it for both players because it could be my wild swing.
	var strike_cards = $AllCards/Striking.get_children()
	for card in strike_cards:
		if game_wrapper.does_card_belong_to_player(player, card.card_id):
			make_card_revealed(card)
	return SmallNoticeDelay

func _on_strike_card_activation(event):
	var strike_cards = $AllCards/Striking.get_children()
	var card_id = event['number']
	for card in strike_cards:
		card.set_backlight_visible(card.card_id == card_id)
	# This card's cost was paid and it ACTIVATED (took effect). Damage-effect
	# animations must only fire for activated cards.
	if card_id not in strike_activated_card_ids:
		strike_activated_card_ids.append(card_id)
	# Ultra effect closeup: plays right when the ultra card activates, i.e.
	# right after its gauge cost was paid = the ultra TAKES EFFECT. This is the
	# "effect moment" - an announcement of the ultra firing - and is completely
	# independent of the card's hit effects AND of whether the attack will
	# land (a missed ultra still shows its effect closeup). Attacker's client
	# plays the right-side frames, defender's client plays the left-side
	# frames; both sides replay the same event stream, so each sees its own
	# side. The damage-resolve animations (qoh_damage / cats_cradle_hit) are a
	# separate thing: they play on Strike_TookDamage, only when damage lands.
	if not cats_cradle_right_played_this_strike and _is_cats_cradle_strike_attacking(true, card_id):
		cats_cradle_right_played_this_strike = true
		_play_cats_cradle_entrance(true)
	if not cats_cradle_left_played_this_strike and _is_cats_cradle_strike_attacking(false, card_id):
		cats_cradle_left_played_this_strike = true
		_play_cats_cradle_entrance(false)
	if not qoh_right_played_this_strike and _is_qoh_strike_attacking(true, card_id):
		qoh_right_played_this_strike = true
		_play_qoh_entrance(true)
	if not qoh_left_played_this_strike and _is_qoh_strike_attacking(false, card_id):
		qoh_left_played_this_strike = true
		_play_qoh_entrance(false)
	# Zsolt Fatal Eye effect closeup: single bottom-left version, both clients
	# see it when a Fatal Eye takes effect.
	if not fatal_eye_played_this_strike and _is_zsolt_fatal_eye_activating(card_id):
		fatal_eye_played_this_strike = true
		_play_zsolt_fatal_eye()
	# Zsolt Wild Hunt hit closeup: per-side (right for attacker, left for
	# defender), top-corner alignment. Gated to the MAIN attack card so
	# chain extra attacks don't re-fire the closeup.
	if not wild_hunt_right_played_this_strike and _is_zsolt_wild_hunt(card_id) \
			and game_wrapper.does_card_belong_to_player(Enums.PlayerId.PlayerId_Player, card_id):
		wild_hunt_right_played_this_strike = true
		_play_zsolt_wild_hunt_entrance(true)
	if not wild_hunt_left_played_this_strike and _is_zsolt_wild_hunt(card_id) \
			and game_wrapper.does_card_belong_to_player(Enums.PlayerId.PlayerId_Opponent, card_id):
		wild_hunt_left_played_this_strike = true
		_play_zsolt_wild_hunt_entrance(false)
	# Zsolt Fanatical Purification hit closeup: same per-side pattern.
	if not purification_right_played_this_strike and _is_zsolt_purification(card_id) \
			and game_wrapper.does_card_belong_to_player(Enums.PlayerId.PlayerId_Player, card_id):
		purification_right_played_this_strike = true
		_play_zsolt_purification_entrance(true)
	if not purification_left_played_this_strike and _is_zsolt_purification(card_id) \
			and game_wrapper.does_card_belong_to_player(Enums.PlayerId.PlayerId_Opponent, card_id):
		purification_left_played_this_strike = true
		_play_zsolt_purification_entrance(false)
	# Geoffrey Inviolable Judgment hit closeup: per-side pattern (same as
	# Wild Hunt / Purification). Gated to the MAIN attack card.
	if not judgment_right_played_this_strike and _is_geoffrey_judgment(card_id) \
			and game_wrapper.does_card_belong_to_player(Enums.PlayerId.PlayerId_Player, card_id):
		judgment_right_played_this_strike = true
		_play_geoffrey_judgment_entrance(true)
	if not judgment_left_played_this_strike and _is_geoffrey_judgment(card_id) \
			and game_wrapper.does_card_belong_to_player(Enums.PlayerId.PlayerId_Opponent, card_id):
		judgment_left_played_this_strike = true
		_play_geoffrey_judgment_entrance(false)
	# Geoffrey Crusader's Oath hit closeup: same per-side pattern.
	if not crusader_right_played_this_strike and _is_geoffrey_crusader(card_id) \
			and game_wrapper.does_card_belong_to_player(Enums.PlayerId.PlayerId_Player, card_id):
		crusader_right_played_this_strike = true
		_play_geoffrey_crusader_entrance(true)
	if not crusader_left_played_this_strike and _is_geoffrey_crusader(card_id) \
			and game_wrapper.does_card_belong_to_player(Enums.PlayerId.PlayerId_Opponent, card_id):
		crusader_left_played_this_strike = true
		_play_geoffrey_crusader_entrance(false)
	# Iaquis Dragon's Heart hit closeup: per-side pattern.
	if not heart_right_played_this_strike and _is_iaquis_heart(card_id) \
			and game_wrapper.does_card_belong_to_player(Enums.PlayerId.PlayerId_Player, card_id):
		heart_right_played_this_strike = true
		_play_iaquis_heart_entrance(true)
	if not heart_left_played_this_strike and _is_iaquis_heart(card_id) \
			and game_wrapper.does_card_belong_to_player(Enums.PlayerId.PlayerId_Opponent, card_id):
		heart_left_played_this_strike = true
		_play_iaquis_heart_entrance(false)
	# Iaquis Dragon's Descent hit closeup: same per-side pattern.
	if not descent_right_played_this_strike and _is_iaquis_descent(card_id) \
			and game_wrapper.does_card_belong_to_player(Enums.PlayerId.PlayerId_Player, card_id):
		descent_right_played_this_strike = true
		_play_iaquis_descent_entrance(true)
	if not descent_left_played_this_strike and _is_iaquis_descent(card_id) \
			and game_wrapper.does_card_belong_to_player(Enums.PlayerId.PlayerId_Opponent, card_id):
		descent_left_played_this_strike = true
		_play_iaquis_descent_entrance(false)
	return SmallNoticeDelay

func _on_strike_hit(event):
	# Iaquis: remember when the Iaquis player landed a hit this strike (used to
	# gate the stun easter-egg: it only plays if Iaquis NEVER hit the opponent).
	if _is_player_iaquis(event['event_player']):
		iaquis_hit_opponent_this_strike = true
	# Fallback consumer of any armed ultra closeup on the confirmed hit. The
	# effect closeups are normally played directly at card activation (see
	# _on_strike_card_activation), so the pending flags are usually false and
	# this is a no-op - but if a pending flag is ever set (e.g. a future
	# hit-gated animation), it is consumed here on the engine's Strike_Hit.
	var card_id = event['number']
	var played_any = false
	if cats_cradle_right_pending_this_strike and _is_cats_cradle_strike_attacking(true, card_id):
		cats_cradle_right_pending_this_strike = false
		cats_cradle_right_played_this_strike = true
		_play_cats_cradle_entrance(true)
		played_any = true
	if cats_cradle_left_pending_this_strike and _is_cats_cradle_strike_attacking(false, card_id):
		cats_cradle_left_pending_this_strike = false
		cats_cradle_left_played_this_strike = true
		_play_cats_cradle_entrance(false)
		played_any = true
	if qoh_right_pending_this_strike and _is_qoh_strike_attacking(true, card_id):
		qoh_right_pending_this_strike = false
		qoh_right_played_this_strike = true
		_play_qoh_entrance(true)
		played_any = true
	if qoh_left_pending_this_strike and _is_qoh_strike_attacking(false, card_id):
		qoh_left_pending_this_strike = false
		qoh_left_played_this_strike = true
		_play_qoh_entrance(false)
		played_any = true
	return SmallNoticeDelay if played_any else 0.0

# Clear the pending (not yet played) ultra closeups for one side. Used as a
# safety net on a confirmed miss and at strike cleanup.
func _clear_pending_strike_closeups_for(player):
	if player == Enums.PlayerId.PlayerId_Player:
		cats_cradle_right_pending_this_strike = false
		qoh_right_pending_this_strike = false
	else:
		cats_cradle_left_pending_this_strike = false
		qoh_left_pending_this_strike = false

func _clear_all_pending_strike_closeups():
	cats_cradle_left_pending_this_strike = false
	cats_cradle_right_pending_this_strike = false
	qoh_left_pending_this_strike = false
	qoh_right_pending_this_strike = false

func _on_strike_miss(event):
	# Safety net: drop any armed closeup for the attacker side. Effect
	# closeups play at activation (missed or not), so this is usually a no-op.
	_clear_pending_strike_closeups_for(event['event_player'])
	return _stat_notice_event(event)

func _on_strike_attack_does_not_hit(event):
	# Safety net: a defense effect declared this attack will not hit, drop any
	# armed closeup for that side. (determine_if_attack_hits will then also
	# emit Strike_Miss, so this is a belt-and-suspenders early clear.)
	_clear_pending_strike_closeups_for(event['event_player'])
	return _stat_notice_event(event)

func _on_strike_character_effect(event):
	var player = event['event_player']
	var effect = event['extra_info']
	var label_text : String = ""
	label_text += GameStrings.get_effect_text(effect, false, true, true, "", true)
	if label_text.is_empty():
		return
	_add_bonus_label_text(player, label_text)

func _add_bonus_label_text(player, new_text : String):
	if _should_skip_bonus_label_visuals():
		return
	var bonus_panel = player_bonus_panel
	var bonus_label = player_bonus_label
	if player == Enums.PlayerId.PlayerId_Opponent:
		bonus_panel = opponent_bonus_panel
		bonus_label = opponent_bonus_label

	if not bonus_panel.visible:
		bonus_panel.visible = true
		bonus_label.text = ""

	for line in new_text.split("\n", false):
		bonus_label.text += "* "
		for word in line.split(" ", false):
			bonus_label.text += word + " "
			if bonus_label.get_content_width() > MaxBonusPanelWidth:
				# Undo and put it on a new line
				bonus_label.text = bonus_label.text.trim_suffix(word + " ")
				bonus_label.text += "\n    " + word + " "
		bonus_label.text += "\n"

func _on_effect_choice(event):
	var player = event['event_player']
	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		if prepared_character_action_data_available("choice"):
			var choice = prepared_character_action_data['choice']
			var success = game_wrapper.submit_choice(Enums.PlayerId.PlayerId_Player, choice)
			if success:
				prepared_character_action_data = {}
				change_ui_state(UIState.UIState_WaitForGameServer)
			return

		var instruction_text = "选择一个效果："
		var extra_choice_text = []

		if event['reason'] == "EffectOrder":
			instruction_text = "选择先结算哪个效果："

			var decision_info = game_wrapper.get_decision_info()
			var choices = decision_info.choice
			var effect_met_flags = decision_info.limitation
			assert(len(choices) == len(effect_met_flags))
			for effect_met in effect_met_flags:
				if effect_met:
					extra_choice_text.append("")
				else:
					extra_choice_text.append("[color=red][lb]失败[rb][/color] ")

		if event['reason'] == "Duplicate":
			instruction_text = "选择要复制哪个效果："
		if event['reason'] == "Reading":
			instruction_text = "你必须以 %s 进行战斗。" % event['extra_info']
		begin_effect_choice(game_wrapper.get_decision_info().choice, instruction_text, extra_choice_text, false)
	else:
		ai_effect_choice(event)

func _on_effect_do_strike(event):
	var player = event['event_player']
	var strike_info = event['extra_info']
	var card_id = strike_info['card_id']
	var wild_swing = strike_info['wild_swing']
	var ex_card_id = strike_info['ex_card_id']
	if restore_fast_forwarding:
		return
	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		game_wrapper.submit_strike(player, card_id, wild_swing, ex_card_id)
	else:
		ai_strike_effect_do_strike(card_id, wild_swing, ex_card_id)

func _on_effect_do_boost(event):
	var player = event['event_player']
	var card_id = event['number']
	if restore_fast_forwarding:
		return
	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		var facedown_override = null
		var placement_choice = await _get_renea_boost_placement_choice(player, card_id)
		if placement_choice == -1:
			return
		if placement_choice >= 0:
			facedown_override = placement_choice == 1
		game_wrapper.submit_boost(player, card_id, [], false, 0, [], facedown_override)
	else:
		ai_effect_do_boost(card_id)

func _on_pay_cost_gauge(event):
	var player = event['event_player']
	var enable_reminder = event['extra_info']
	var is_ex = event['extra_info2']
	var alternative_life_cost = event['extra_info3']
	var gauge_cost = game_wrapper.get_decision_info().cost
	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		can_spend_life_for_gauge = game_wrapper.get_life_for_gauge_amount(Enums.PlayerId.PlayerId_Player) > 0
		var wild_swing_allowed = game_wrapper.get_decision_info().type == Enums.DecisionType.DecisionType_PayStrikeCost_CanWild
		begin_gauge_selection(
			gauge_cost,
			wild_swing_allowed,
			UISubState.UISubState_SelectCards_StrikeGauge,
			enable_reminder,
			is_ex,
			alternative_life_cost
		)
	else:
		ai_pay_cost(gauge_cost, false, alternative_life_cost)

func _on_pay_cost_force(event):
	var player = event['event_player']
	var force_cost = game_wrapper.get_decision_info().cost
	var is_ex = event['extra_info2']
	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		var can_cancel = false
		var wild_swing_allowed = game_wrapper.get_decision_info().type == Enums.DecisionType.DecisionType_PayStrikeCost_CanWild
		change_ui_state(null, UISubState.UISubState_SelectCards_StrikeForce)
		begin_generate_force_selection(force_cost, can_cancel, wild_swing_allowed, is_ex)
	else:
		ai_pay_cost(force_cost, true)

func _on_pay_cost_failed(event):
	# Do the wild swing deal.
	return _on_strike_started(event, false)

func _on_force_for_armor(event):
	var player = event['event_player']
	var use_gauge_instead = game_wrapper.get_decision_info().limitation == "gauge"
	force_for_armor_incoming_damage = event['number']
	force_for_armor_ignore_armor = event['extra_info']
	force_for_armor_amount = game_wrapper.get_decision_info().amount
	var armor_player = game_wrapper._get_player(player)
	if armor_player != null:
		armor_player.force_for_armor_apf_tmp = force_for_armor_amount
	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		if use_gauge_instead:
			begin_gauge_selection(-1, false, UISubState.UISubState_SelectCards_GaugeForArmor)
		else:
			change_ui_state(null, UISubState.UISubState_SelectCards_ForceForArmor)
			begin_generate_force_selection(-1)
	else:
		ai_force_for_armor(event)

func _on_force_for_effect(event):
	var player = event['event_player']
	var effect = game_wrapper.get_decision_info().effect
	# Flag the next opponent discard as the Time for Tea (Plot Hook) action
	# closeup trigger, if this force_for_effect belongs to Time for Tea.
	if effect and effect.get('card_id', -1) != -1:
		var tea_source_card = game_wrapper.get_card_database().get_card(effect['card_id'])
		if tea_source_card != null and tea_source_card.definition.get("id", "") == "eugenia_illusion_bind":
			tea_time_pending = true
	if player == Enums.PlayerId.PlayerId_Player  and not observer_mode:
		if prepared_character_action_data_available("force_for_effect"):
			var card_ids = prepared_character_action_data['force_ids']
			var ultras_as_single = prepared_character_action_data['treat_ultras_as_single_force']
			var success = game_wrapper.submit_force_for_effect(Enums.PlayerId.PlayerId_Player, card_ids, ultras_as_single)
			if success:
				prepared_character_action_data = {}
				change_ui_state(UIState.UIState_WaitForGameServer)
			return
			
		# Zsolt: auto-use free force up to force_max (no popup during ForceForEffect)
		var p = game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
		if p.zsolt_force_pool > 0:
			p.free_force = min(p.zsolt_force_pool, effect['force_max'])
		change_ui_state(null, UISubState.UISubState_SelectCards_ForceForEffect)
		select_card_up_to_force = effect['force_max']
		var require_max = -1
		if _effect_has_overall_effect(effect):
			require_max = select_card_up_to_force
		var can_cancel = true
		if 'required' in effect and effect['required']:
			can_cancel = false
		if is_tournelouse_ouroboros_force_choice():
			can_cancel = true
		begin_generate_force_selection(require_max, can_cancel, false, false, true)
	else:
		ai_force_for_effect(effect)

func _effect_has_overall_effect(effect):
	return 'overall_effect' in effect and effect['overall_effect'] != null

func _effect_allows_partial_gauge_selection(effect):
	return effect.get('allow_partial_gauge_selection', false)

func _on_gauge_for_effect(event):
	var player = event['event_player']
	var effect = game_wrapper.get_decision_info().effect
	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		if prepared_character_action_data_available("gauge_for_effect"):
			var card_ids = prepared_character_action_data['gauge_ids']
			var success = game_wrapper.submit_gauge_for_effect(Enums.PlayerId.PlayerId_Player, card_ids)
			if success:
				prepared_character_action_data = {}
				change_ui_state(UIState.UIState_WaitForGameServer)
			return

		select_card_require_min = 0
		if 'required' in effect and effect['required']:
			select_card_require_min = effect['gauge_max']
		select_card_require_max = effect['gauge_max']
		if _effect_has_overall_effect(effect) and not _effect_allows_partial_gauge_selection(effect):
			select_card_must_be_max_or_min = true
		else:
			select_card_must_be_max_or_min = false
		select_gauge_require_card_id = ""
		select_gauge_require_card_name = ""
		select_gauge_valid_card_types = []
		if 'require_specific_card_id' in effect:
			select_gauge_require_card_id = effect['require_specific_card_id']
			select_gauge_require_card_name = effect['require_specific_card_name']
		if 'valid_card_types' in effect:
			select_gauge_valid_card_types = effect['valid_card_types']
		begin_gauge_selection(-1, false, UISubState.UISubState_SelectCards_GaugeForEffect)
		if effect.get("valid_zone", "gauge") == "bleach":
			_on_player_bleach_clicked(false)
	else:
		ai_gauge_for_effect(effect)

func _on_emote(event):
	var player = event['event_player']
	var is_image_emote = event['number']
	var emote = event['reason']
	if GlobalSettings.MuteEmotes:
		return

	spawn_emote(player, is_image_emote, emote)

func _on_damage(event):
	var player = event['event_player']
	var life = event['extra_info']
	var reason = event['reason']
	var play_animation = true
	if reason == "spend":
		play_animation = false
	if restore_fast_forwarding:
		play_animation = false
	var damage_taken = event['number']
	if player == Enums.PlayerId.PlayerId_Player:
		$PlayerLife.set_life(life)
		if play_animation:
			$PlayerCharacter.play_hit()
	else:
		$OpponentLife.set_life(life)
		if play_animation:
			$OpponentCharacter.play_hit()
	# Queen of Hearts damage-resolve effect: after all hit effects, when the
	# damage is resolved. Both clients replay the same events, so both sides
	# see it at the same time, once per strike. Skip life-payment spends.
	if play_animation and not qoh_damage_effect_played_this_strike \
			and _is_qoh_strike_dealing_damage_to(player):
		qoh_damage_effect_played_this_strike = true
		_play_qoh_damage_effect()
	# Cat's Cradle hit closeup, full-screen damage-resolve effect: same
	# timing as the QOH one, plays once per strike when the Cradle's damage
	# is resolved.
	if play_animation and not cats_cradle_hit_played_this_strike \
			and _is_cats_cradle_strike_dealing_damage_to(player):
		cats_cradle_hit_played_this_strike = true
		_play_cats_cradle_hit()
	# Zsolt Wild Hunt damage-resolve effect: full-screen, same timing as
	# qoh_damage / cats_cradle_hit. Gated to the MAIN attack card.
	if play_animation and not wild_hunt_damage_played_this_strike \
			and _is_zsolt_wild_hunt_dealing_damage_to(player):
		wild_hunt_damage_played_this_strike = true
		_play_zsolt_wild_hunt_damage()
	# Zsolt Fanatical Purification damage-resolve effect: same pattern.
	if play_animation and not purification_damage_played_this_strike \
			and _is_zsolt_purification_dealing_damage_to(player):
		purification_damage_played_this_strike = true
		_play_zsolt_purification_damage()
	# Geoffrey Inviolable Judgment damage-resolve effect: same pattern.
	if play_animation and not judgment_damage_played_this_strike \
			and _is_geoffrey_judgment_dealing_damage_to(player):
		judgment_damage_played_this_strike = true
		_play_geoffrey_judgment_damage()
	# Geoffrey Crusader's Oath damage-resolve effect: same pattern.
	if play_animation and not crusader_damage_played_this_strike \
			and _is_geoffrey_crusader_dealing_damage_to(player):
		crusader_damage_played_this_strike = true
		_play_geoffrey_crusader_damage()
	# Iaquis Dragon's Heart damage-resolve effect: same pattern.
	if play_animation and not heart_damage_played_this_strike \
			and _is_iaquis_heart_dealing_damage_to(player):
		heart_damage_played_this_strike = true
		_play_iaquis_heart_damage()
	# Iaquis Dragon's Descent damage-resolve effect: same pattern.
	if play_animation and not descent_damage_played_this_strike \
			and _is_iaquis_descent_dealing_damage_to(player):
		descent_damage_played_this_strike = true
		_play_iaquis_descent_damage()
	spawn_damage_popup("%s 点伤害" % str(damage_taken), player)
	return SmallNoticeDelay

func _on_gain_life(event):
	var player = event['event_player']
	var life = event['extra_info']
	var life_gained = event['number']
	if player == Enums.PlayerId.PlayerId_Player:
		$PlayerLife.set_life(life)
	else:
		$OpponentLife.set_life(life)
	spawn_damage_popup("+%d 生命" % life_gained, player)
	return SmallNoticeDelay

func _get_buddy_from_id(player_id : Enums.PlayerId, buddy_id : String):
	if player_id == Enums.PlayerId.PlayerId_Player:
		for buddy in player_buddies:
			if buddy.get_buddy_id() == buddy_id:
				return buddy
	else:
		for buddy in opponent_buddies:
			if buddy.get_buddy_id() == buddy_id:
				return buddy
	assert(false)
	return null

func _on_place_buddy(event):
	var player = event['event_player']
	var buddy_location = event['number']
	var buddy_id = event['extra_info']
	var silent = event['extra_info2']
	var extra_offset = event['extra_info3']
	var extra_description = event['reason']

	var action_text = "Place"
	if buddy_location == -1:
		action_text = "Remove"

	var buddy = _get_buddy_from_id(player, buddy_id)
	add_buddy_to_zone(player, buddy, buddy_id)
	buddy.set_buddy_extra_offset(extra_offset)
	if buddy_location == -1:
		buddy.visible = false
	else:
		var immediate = not buddy.visible
		buddy.visible = true
		move_character_to_arena_square(buddy, buddy_location, immediate, Character.CharacterAnim.CharacterAnim_WalkForward, -1)

	if not silent:
		if extra_description:
			spawn_damage_popup(extra_description, player)
		else:
			spawn_damage_popup("%s %s" % [action_text, game_wrapper.get_buddy_name(player, buddy_id)], player)
		return SmallNoticeDelay
	return 0

func add_lightning_rod(rod_parent, rod_tracking, location, card_id, player):
	var rods_at_location = rod_tracking[location]
	if len(rods_at_location['card_ids']) == 0:
		# Create a new character for this and add it to rod_parent.
		var new_character = CharacterScene.instantiate()
		rod_parent.add_child(new_character)
		var deck_def = player_deck
		if player == Enums.PlayerId.PlayerId_Opponent:
			deck_def = opponent_deck
		new_character.load_character(image_loader, deck_def, "rachel_lightningrod", false)
		rods_at_location['character'] = new_character
		var immediate = true
		move_character_to_arena_square(new_character, location, immediate, Character.CharacterAnim.CharacterAnim_WalkForward, -1)
	rods_at_location['card_ids'].append(card_id)

func remove_lightning_rod(rod_parent, rod_tracking, location, card_id):
	var rods_at_location = rod_tracking[location]
	rods_at_location['card_ids'].erase(card_id)
	if len(rods_at_location['card_ids']) == 0:
		rod_parent.remove_child(rods_at_location['character'])
		rods_at_location['character'].queue_free()
		rods_at_location['character'] = null

func update_lightningrod_info(player, rod_tracking, location):
	var rods_at_location = rod_tracking[location]
	var count =len(rods_at_location['card_ids'])
	var pair = $ArenaNode/RowLightningInfoButtons.get_child(location)
	pair.set_number(player, count)
	# Iterate through all locations for both players
	# and update the count of lightning rods at each location.
	pass

func _on_place_lightningrod(event):
	var player = event['event_player']
	var card_id = event['number']
	var location = event['extra_info']
	var place = event['extra_info2']

	var rod_parent = player_lightningrods
	var rod_tracking = player_lightningrod_tracking
	if player == Enums.PlayerId.PlayerId_Opponent:
		rod_parent = opponent_lightningrods
		rod_tracking = opponent_lightningrod_tracking

	# Add or remove the rod as appropriate.
	if place:
		add_lightning_rod(rod_parent, rod_tracking, location, card_id, player)

		# Move the card to the set aside zone.
		var is_player = player == Enums.PlayerId.PlayerId_Player
		var card = find_card_on_board(card_id)
		var deck_position = get_deck_button_position(is_player)
		card.discard_to(deck_position, CardBase.CardState.CardState_InDeck)
		reparent_to_zone(card, get_set_aside_zone(is_player))
	else:
		remove_lightning_rod(rod_parent, rod_tracking, location, card_id)
	update_lightningrod_info(player, rod_tracking, location)
	return SmallNoticeDelay

func setup_underboost_info(player, underboost_tracking, index, boost_card_id):
	underboost_tracking.append({
		"card_ids": [],
		"boost_card": boost_card_id
	})
	var boostinfo = boostinfo_dict[player][index]
	boostinfo.set_visibility(true)
	boostinfo_parent_dict[player].visible = true

func add_underboost_card(underboost_tracking, index, card_id):
	var cards_under_boost = underboost_tracking[index]
	cards_under_boost['card_ids'].append(card_id)

func reset_underboost_info(player, underboost_tracking, index):
	underboost_tracking.remove_at(index)
	var boostinfo = boostinfo_dict[player][index]
	boostinfo.reset()

	if not underboost_tracking:
		boostinfo_parent_dict[player].visible = false

func update_underboost_info(player, underboost_tracking, index):
	var cards_under_boost = underboost_tracking[index]
	var count = len(cards_under_boost['card_ids'])
	var boostinfo = boostinfo_dict[player][index]
	boostinfo.set_number(count)

func _on_place_underboost(event):
	var player = event['event_player']
	var boost_card_id = event['number']
	var new_card_id = event['extra_info']
	var place = event['extra_info2']

	var underboost_tracking = player_underboost_tracking
	if player == Enums.PlayerId.PlayerId_Opponent:
		underboost_tracking = opponent_underboost_tracking
	var index = 0
	for underboost_info in underboost_tracking:
		if underboost_info['boost_card'] == boost_card_id:
			break
		index += 1

	if new_card_id == -1:
		if place:
			# Set up boost info indicator
			setup_underboost_info(player, underboost_tracking, index, boost_card_id)
		else:
			# Remove boost info indicator
			reset_underboost_info(player, underboost_tracking, index)
	else:
		# Add new card under boost
		add_underboost_card(underboost_tracking, index, new_card_id)

		# Move the card to the set aside zone.
		var is_player = player == Enums.PlayerId.PlayerId_Player
		var card = find_card_on_board(new_card_id)
		card.flip_card_to_front(false)
		var deck_position = get_deck_button_position(is_player)
		card.discard_to(deck_position, CardBase.CardState.CardState_InDeck)
		reparent_to_zone(card, get_set_aside_zone(is_player))

		update_underboost_info(player, underboost_tracking, index)
	return SmallNoticeDelay

func _handle_events(events):
	_cache_local_mulligan_selection_if_needed()

	_begin_runtime_event_batch(events.size())
	var delay = 0
	var event_budget = get_runtime_event_budget_for_health_state(runtime_health_state, _should_apply_web_backlog_judge())
	for event_index in range(events.size()):
		var event = events[event_index]
		if event['event_type'] in [Enums.EventType.EventType_Prepare, Enums.EventType.EventType_Draw, Enums.EventType.EventType_AdvanceTurn]:
			printlog("CLIENT_HANDLE_EVENT type=%s player=%s num=%d pending=%d ui=%s queued=%d observer=%s" % [
				Enums.EventType.keys()[event['event_type']],
				str(event['event_player']),
				event['number'],
				events.size() - event_index,
				str(ui_state),
				events_to_process.size(),
				str(observer_mode),
			])
		_log_event(event)
		if event.get("event_name") == "EventType_SwapDeckAndDiscard":
			delay = _on_swap_deck_and_discard(event)
			if delay != 0:
				var remaining_events = events.slice(event_index + 1)
				_end_runtime_event_batch()
				remaining_delay = get_runtime_animation_delay(
					delay,
					remaining_events.size(),
					_is_web_runtime(),
					_should_apply_web_backlog_judge())
				events_to_process = remaining_events
				change_ui_state(UIState.UIState_PlayingAnimation)
				return
			continue
		match event['event_type']:
			Enums.EventType.EventType_AddToGauge:
				delay = _on_add_to_gauge(event)
			Enums.EventType.EventType_AddToBleach:
				delay = _on_add_to_bleach(event)
			Enums.EventType.EventType_AddToDeck:
				_on_add_to_deck(event)
			Enums.EventType.EventType_AddToDiscard:
				_on_discard_event(event)
			Enums.EventType.EventType_AddToHand:
				_on_add_to_hand(event)
			Enums.EventType.EventType_AddToOverdrive:
				delay = _on_add_to_overdrive(event)
			Enums.EventType.EventType_AddToStored:
				_on_add_to_stored(event)
			Enums.EventType.EventType_AdvanceTurn:
				delay = _on_advance_turn(event)
			Enums.EventType.EventType_BecomeWide:
				delay = _on_become_wide(event)
			Enums.EventType.EventType_BlockMovement:
				delay = _stat_notice_event(event)
			Enums.EventType.EventType_Boost_ActionAfterBoost:
				delay = _on_post_boost_action(event)
			Enums.EventType.EventType_Boost_CancelDecision:
				delay = _on_boost_cancel_decision(event)
			Enums.EventType.EventType_Boost_Canceled:
				delay = _on_boost_canceled(event)
			Enums.EventType.EventType_Boost_Continuous_Added:
				delay = _on_continuous_boost_added(event)
			Enums.EventType.EventType_Boost_DiscardContinuousChoice:
				_on_discard_continuous_boost_begin(event)
			Enums.EventType.EventType_Boost_DiscardOpponentGauge:
				_on_discard_opponent_gauge(event)
			Enums.EventType.EventType_Boost_NameCardOpponentDiscards:
				delay = _on_name_opponent_card_begin(event)
			Enums.EventType.EventType_Boost_Sidestep:
				delay = _on_name_opponent_card_begin(event)
			Enums.EventType.EventType_Boost_ZeroVector:
				delay = _on_name_opponent_card_begin(event)
			Enums.EventType.EventType_Boost_Played:
				delay = _on_boost_played(event)
			Enums.EventType.EventType_CardFromHandToGauge_Choice:
				_on_choose_card_hand_to_gauge(event)
			Enums.EventType.EventType_ChangeCards:
				delay = _on_change_cards(event)
			Enums.EventType.EventType_CharacterAction:
				delay = _stat_notice_event(event)
			Enums.EventType.EventType_ChooseArenaLocationForEffect:
				_on_choose_arena_location_for_effect(event)
			Enums.EventType.EventType_ChooseFromBoosts:
				_on_choose_from_boosts(event)
			Enums.EventType.EventType_ChooseFromDiscard:
				_on_choose_from_discard(event)
			Enums.EventType.EventType_ChooseFromTopDeck:
				_on_choose_from_topdeck(event)
			Enums.EventType.EventType_ChooseOpponentCardToDiscard:
				_on_choose_opponent_card_to_discard(event)
			Enums.EventType.EventType_Draw:
				_on_draw_event(event)
			Enums.EventType.EventType_Emote:
				_on_emote(event)
			Enums.EventType.EventType_EffectDoBoost:
				_on_effect_do_boost(event)
			Enums.EventType.EventType_EndOverdrive:
				delay = _stat_notice_event(event)
			Enums.EventType.EventType_Exceed:
				delay = _on_exceed_event(event)
			Enums.EventType.EventType_ExceedRevert:
				delay = _on_exceed_revert_event(event)
			Enums.EventType.EventType_ForceStartBoost:
				delay = _on_force_start_boost(event)
			Enums.EventType.EventType_ForceStartStrike:
				delay = _on_force_start_strike(event)
			Enums.EventType.EventType_ForceForEffect:
				_on_force_for_effect(event)
			Enums.EventType.EventType_ForceForEffectConfirmed:
				_on_force_for_effect_confirmed(event)
			Enums.EventType.EventType_GaugeForEffect:
				_on_gauge_for_effect(event)
			Enums.EventType.EventType_Strike_ForceWildSwing:
				delay = _on_force_wild_swing(event)
			Enums.EventType.EventType_GameOver:
				_on_game_over(event)
			Enums.EventType.EventType_HandSizeExceeded:
				_on_hand_size_exceeded(event)
			Enums.EventType.EventType_Move:
				delay = _on_move_event(event)
			Enums.EventType.EventType_MulliganDecision:
				_on_mulligan_decision(event)
			Enums.EventType.EventType_PlaceBuddy:
				delay = _on_place_buddy(event)
			Enums.EventType.EventType_PlaceCardUnderBoost:
				delay = _on_place_underboost(event)
			Enums.EventType.EventType_PlaceLightningRod:
				delay = _on_place_lightningrod(event)
			Enums.EventType.EventType_PickNumberFromRange:
				_on_pick_number_from_range(event)
			Enums.EventType.EventType_SwapSealedAndDeck:
				delay = _stat_notice_event(event)
			Enums.EventType.EventType_Prepare:
				delay = _on_prepare(event)
			Enums.EventType.EventType_ReadingNormal:
				delay = _on_name_opponent_card_begin(event)
			Enums.EventType.EventType_ReshuffleDeck:
				_on_shuffle_deck(event)
			Enums.EventType.EventType_ReshuffleDiscard:
				delay = _on_reshuffle_discard(event)
			Enums.EventType.EventType_ReshuffleDiscardInPlace:
				_on_reshuffle_discard_in_place(event)
			Enums.EventType.EventType_ReshuffleDeck_Mulligan:
				_on_reshuffle_deck_mulligan(event)
			Enums.EventType.EventType_RevealCard:
				delay = _on_reveal_card_from_hand(event)
			Enums.EventType.EventType_RevealHand:
				delay = _on_reveal_hand(event)
			Enums.EventType.EventType_RevealStrike_OnePlayer:
				delay = _on_strike_reveal_one_player(event)
			Enums.EventType.EventType_RevealRandomGauge:
				delay = _on_reveal_random_gauge(event)
			Enums.EventType.EventType_RevealTopDeck:
				delay = _on_reveal_topdeck(event)
			Enums.EventType.EventType_Say:
				delay = _on_say(event)
			Enums.EventType.EventType_Seal:
				delay = _on_add_to_sealed(event)
			Enums.EventType.EventType_SetCardAside:
				_on_set_card_aside(event)
			Enums.EventType.EventType_Strike_ArmorUp:
				delay = _stat_notice_event(event)
			Enums.EventType.EventType_Strike_AttackDoesNotHit:
				delay = _on_strike_attack_does_not_hit(event)
			Enums.EventType.EventType_Strike_CardActivation:
				delay = _on_strike_card_activation(event)
			Enums.EventType.EventType_Strike_CharacterEffect:
				_on_strike_character_effect(event)
			Enums.EventType.EventType_Strike_ChooseToDiscard:
				delay = _on_choose_to_discard(event, false)
			Enums.EventType.EventType_Strike_ChooseToDiscard_Info:
				delay = _on_choose_to_discard(event, true)
			Enums.EventType.EventType_Strike_Cleanup:
				_on_end_of_strike()
			Enums.EventType.EventType_Strike_Critical:
				_set_card_bonus(event['number'], "critical")
				delay = _stat_notice_event(event)
			Enums.EventType.EventType_MarkInfused:
				_set_card_bonus(event['number'], "infuse")
				_add_bonus_label_text(event['event_player'], "[color=sky_blue]灌注！[/color]\n")
			Enums.EventType.EventType_Strike_DodgeAttacks, Enums.EventType.EventType_Strike_DodgeAttacksAtRange, Enums.EventType.EventType_Strike_DodgeFromOppositeBuddy:
				delay = _stat_notice_event(event)
			Enums.EventType.EventType_Strike_DoResponseNow:
				_on_strike_do_response_now(event)
			Enums.EventType.EventType_Strike_EffectChoice:
				_on_effect_choice(event)
			Enums.EventType.EventType_Strike_EffectDoStrike:
				_on_effect_do_strike(event)
			Enums.EventType.EventType_Strike_ExUp:
				delay = _stat_notice_event(event)
			Enums.EventType.EventType_Strike_ForceForArmor:
				_on_force_for_armor(event)
			Enums.EventType.EventType_Strike_GainAdvantage:
				delay = _stat_notice_event(event)
			Enums.EventType.EventType_Strike_GainLife:
				delay = _on_gain_life(event)
			Enums.EventType.EventType_Strike_GuardUp:
				delay = _stat_notice_event(event)
			Enums.EventType.EventType_Strike_IgnoredPushPull:
				delay = _stat_notice_event(event)
			Enums.EventType.EventType_Strike_Infuse:
				update_boost_summary(Enums.PlayerId.PlayerId_Player, $AllCards/PlayerBoosts, $PlayerBoostZone)
				update_boost_summary(Enums.PlayerId.PlayerId_Opponent, $AllCards/OpponentBoosts, $OpponentBoostZone)
				delay = _stat_notice_event(event)
			Enums.EventType.EventType_Strike_Miss:
				delay = _on_strike_miss(event)
			Enums.EventType.EventType_Strike_Hit:
				delay = _on_strike_hit(event)
			Enums.EventType.EventType_Strike_OpponentCantMovePast:
				delay = _stat_notice_event(event)
			Enums.EventType.EventType_Strike_FromGauge:
				delay = _on_strike_from_gauge(event)
			Enums.EventType.EventType_Strike_OpponentSetsFirst:
				delay = _on_strike_opponent_sets_first(event)
			Enums.EventType.EventType_Strike_OpponentSetsFirst_DefenderSet:
				_on_strike_opponent_sets_first_defender_set(event)
			Enums.EventType.EventType_Strike_OpponentSetsFirst_InitiatorSet:
				_on_strike_opponent_sets_first_initiator_set(event)
			Enums.EventType.EventType_Strike_PayCost_Gauge:
				_on_pay_cost_gauge(event)
			Enums.EventType.EventType_Strike_PayCost_Force:
				_on_pay_cost_force(event)
			Enums.EventType.EventType_Strike_PayCost_Unable:
				_on_pay_cost_failed(event)
			Enums.EventType.EventType_Strike_PowerUp:
				delay = _stat_notice_event(event)
			Enums.EventType.EventType_Strike_RandomGaugeStrike:
				_on_strike_started(event, false)
				delay = _stat_notice_event(event)
			Enums.EventType.EventType_Strike_RangeUp:
				delay = _stat_notice_event(event)
			Enums.EventType.EventType_Strike_Response:
				_on_strike_started(event, false)
			Enums.EventType.EventType_Strike_Response_Ex:
				_on_strike_started(event, true)
			Enums.EventType.EventType_Strike_Reveal:
				delay = _on_strike_reveal(event)
			Enums.EventType.EventType_Strike_SetX:
				delay = _stat_notice_event(event)
			Enums.EventType.EventType_Strike_SpeedUp:
				delay = _stat_notice_event(event)
			Enums.EventType.EventType_Strike_Started:
				_on_strike_started(event, false)
			Enums.EventType.EventType_Strike_Started_Ex:
				_on_strike_started(event, true)
			Enums.EventType.EventType_Strike_Started_ExtraAttack:
				_on_strike_started_extra_attack(event)
			Enums.EventType.EventType_Strike_Stun:
				delay = _on_stunned(event)
			Enums.EventType.EventType_Strike_Stun_Immunity:
				delay = _stat_notice_event(event)
			Enums.EventType.EventType_SustainBoost:
				delay = _stat_notice_event(event)
			Enums.EventType.EventType_Strike_TookDamage:
				delay = _on_damage(event)
			Enums.EventType.EventType_Strike_WildStrike:
				_on_strike_started(event, false, true)
				delay = _stat_notice_event(event)
			Enums.EventType.EventType_Transform_Added:
				delay = _on_transform_added(event)
			_:
				printlog("ERROR: UNHANDLED EVENT")
				assert(false)

		# If a UI animation needs to play or pause events,
		# break off the remaining events and handle them later.
		if delay != 0 and not restore_fast_forwarding:
			var remaining_events = events.slice(event_index + 1)
			_end_runtime_event_batch()
			_restore_local_mulligan_selection_if_needed()
			begin_delay(delay, remaining_events)
			return
		elif delay == 0 and not restore_fast_forwarding and event_budget != WebRuntimeEventBudgetUnlimited and event_index + 1 >= event_budget and event_index + 1 < events.size():
			var remaining_events = events.slice(event_index + 1)
			_end_runtime_event_batch()
			_restore_local_mulligan_selection_if_needed()
			begin_delay(0.0, remaining_events)
			return
		elif delay == 0 and not restore_fast_forwarding and should_yield_runtime_batch(event_index + 1, WebRuntimeEventYieldBatchSize, _is_web_runtime()) and event_index + 1 < events.size():
			var remaining_events = events.slice(event_index + 1)
			_end_runtime_event_batch()
			_restore_local_mulligan_selection_if_needed()
			begin_delay(WebRuntimeEventYieldDelay, remaining_events)
			return
	_end_runtime_event_batch()
	_restore_local_mulligan_selection_if_needed()


func _fast_forward_restored_game_if_needed() -> bool:
	if not restore_fast_forward_pending:
		return false
	restore_fast_forward_pending = false
	restore_fast_forwarding = true
	var replay_messages_processed = 0
	while true:
		var events = game_wrapper.poll_for_events()
		if not events.is_empty():
			_handle_events(events)

		var consumed_observer_message = false
		var replay_target_reached = replay_mode and replay_seek_target >= 0 \
			and replay_messages_processed >= replay_seek_target
		if observer_mode and not replay_target_reached:
			consumed_observer_message = game_wrapper.observer_process_next_message_from_queue()
			if consumed_observer_message:
				replay_messages_processed += 1

		if events.is_empty() and not consumed_observer_message:
			break
	_refresh_combat_log_if_visible()
	_settle_fast_forward_visual_state()
	restore_fast_forwarding = false
	if observer_mode and not replay_mode:
		observer_next_button.disabled = true
		observer_next_button.text = "LIVE"
		observer_live = true
		observer_play_to_live_button.text = "Pause"
	_update_replay_step_buttons()
	return true

func _on_observer_jump_to_latest_pressed():
	if not observer_mode or replay_mode:
		return
	if not starting_message:
		return

	var restore_start_data : Dictionary = starting_message.duplicate(true)
	var restore_log : Array = game_wrapper.get_message_history().duplicate(true)
	var pending_messages : Array = game_wrapper.get_pending_observer_messages()
	if pending_messages.size() > 0:
		restore_log.append_array(pending_messages)

	restore_start_data["restore_log"] = restore_log
	restore_start_data["observer_mode"] = true
	restore_start_data["replay_mode"] = false
	restore_start_data["your_player_id"] = restore_start_data.get("your_player_id", restore_start_data.get("player1_id", 0))

	var vs_info = {
		'player_name': game_wrapper.get_player_name(Enums.PlayerId.PlayerId_Player),
		'player_deck': game_wrapper.get_player_deck_definition(Enums.PlayerId.PlayerId_Player),
		'player_random_tag': "",
		'opponent_name': game_wrapper.get_player_name(Enums.PlayerId.PlayerId_Opponent),
		'opponent_deck': game_wrapper.get_player_deck_definition(Enums.PlayerId.PlayerId_Opponent),
		'opponent_random_tag': "",
		'randomize_first_vs_ai': false,
	}

	var main_scene = get_parent()
	if main_scene and main_scene.has_method("_on_main_menu_start_remote_game"):
		main_scene.call_deferred("_on_main_menu_start_remote_game", vs_info, restore_start_data)

func _sync_ui_state_after_restore():
	if ui_state == UIState.UIState_GameOver:
		return
	if _is_player_interaction_ui_state(ui_state):
		_update_buttons()
		return

	var game_state = game_wrapper.get_game_state()
	if game_state == Enums.GameState.GameState_PickAction:
		if game_wrapper.get_active_player() == Enums.PlayerId.PlayerId_Player and not observer_mode:
			change_ui_state(UIState.UIState_PickTurnAction, UISubState.UISubState_None)
		else:
			change_ui_state(UIState.UIState_WaitingOnOpponent, UISubState.UISubState_None)
		return

	if game_state == Enums.GameState.GameState_PlayerDecision:
		var decision_info = game_wrapper.get_decision_info()
		if decision_info.player == Enums.PlayerId.PlayerId_Player and not observer_mode:
			if _restore_local_player_decision_ui(decision_info):
				return
		else:
			change_ui_state(UIState.UIState_WaitingOnOpponent, UISubState.UISubState_None)
			return

	change_ui_state(UIState.UIState_WaitForGameServer, UISubState.UISubState_None)

func _restore_local_player_decision_ui(decision_info : DecisionInfo) -> bool:
	match decision_info.type:
		Enums.DecisionType.DecisionType_BoostCancel:
			begin_gauge_selection(decision_info.choice, false, UISubState.UISubState_SelectCards_BoostCancel)
			return true
		Enums.DecisionType.DecisionType_BoostNow:
			begin_boost_choosing(false, decision_info.valid_zones, decision_info.limitation, decision_info.ignore_costs, maxi(decision_info.amount, 1))
			return true
		Enums.DecisionType.DecisionType_ChooseArenaLocationForEffect:
			_on_choose_arena_location_for_effect({"event_player": decision_info.player})
			return true
		Enums.DecisionType.DecisionType_ChooseDiscardContinuousBoost:
			_on_discard_continuous_boost_begin({"event_player": decision_info.player, "extra_info": decision_info.extra_info})
			return true
		Enums.DecisionType.DecisionType_ChooseDiscardOpponentGauge:
			_on_discard_opponent_gauge({"event_player": decision_info.player})
			return true
		Enums.DecisionType.DecisionType_ChooseFromBoosts:
			_on_choose_from_boosts({"event_player": decision_info.player})
			return true
		Enums.DecisionType.DecisionType_ChooseFromDiscard:
			_on_choose_from_discard({"event_player": decision_info.player})
			return true
		Enums.DecisionType.DecisionType_ChooseFromTopDeck:
			_on_choose_from_topdeck({"event_player": decision_info.player})
			return true
		Enums.DecisionType.DecisionType_ChooseSimultaneousEffect, Enums.DecisionType.DecisionType_EffectChoice:
			begin_effect_choice(decision_info.choice, "选择一个效果：", [], decision_info.can_pass)
			return true
		Enums.DecisionType.DecisionType_ForceForEffect:
			_on_force_for_effect({"event_player": decision_info.player})
			return true
		Enums.DecisionType.DecisionType_GaugeForEffect:
			_on_gauge_for_effect({"event_player": decision_info.player})
			return true
		Enums.DecisionType.DecisionType_NameCard_OpponentDiscards, Enums.DecisionType.DecisionType_ReadingNormal, Enums.DecisionType.DecisionType_Sidestep, Enums.DecisionType.DecisionType_ZeroVector:
			_restore_name_card_decision_ui(decision_info)
			return true
		Enums.DecisionType.DecisionType_ChooseToDiscard:
			begin_discard_cards_selection(maxi(0, decision_info.amount_min if decision_info.amount_min != 999 else decision_info.amount), decision_info.amount, UISubState.UISubState_SelectCards_DiscardCards_Choose, decision_info.can_pass)
			return true
		Enums.DecisionType.DecisionType_PayStrikeCost_Required, Enums.DecisionType.DecisionType_PayStrikeCost_CanWild:
			if decision_info.limitation == "gauge":
				begin_gauge_selection(decision_info.cost, decision_info.type == Enums.DecisionType.DecisionType_PayStrikeCost_CanWild, UISubState.UISubState_SelectCards_StrikeGauge)
			else:
				change_ui_state(null, UISubState.UISubState_SelectCards_StrikeForce)
				begin_generate_force_selection(decision_info.cost, false, decision_info.type == Enums.DecisionType.DecisionType_PayStrikeCost_CanWild)
			return true
		Enums.DecisionType.DecisionType_PickNumberFromRange:
			_on_pick_number_from_range({"event_player": decision_info.player})
			return true
		Enums.DecisionType.DecisionType_ForceForArmor:
			_on_force_for_armor({"event_player": decision_info.player, "number": 0, "extra_info": false})
			return true
		Enums.DecisionType.DecisionType_CardFromHandToGauge:
			_on_choose_card_hand_to_gauge({"event_player": decision_info.player, "number": decision_info.amount_min, "extra_info": decision_info.amount, "extra_info2": decision_info.choice})
			return true
		Enums.DecisionType.DecisionType_StrikeNow:
			begin_strike_choosing(false, false)
			return true
		_:
			return false

func _restore_name_card_decision_ui(decision_info : DecisionInfo):
	var can_name_fake_card = decision_info.type in [Enums.DecisionType.DecisionType_NameCard_OpponentDiscards, Enums.DecisionType.DecisionType_ZeroVector]
	var normal_only = decision_info.type in [Enums.DecisionType.DecisionType_ReadingNormal, Enums.DecisionType.DecisionType_Sidestep]
	var cancel_text = "展示手牌"
	if decision_info.type == Enums.DecisionType.DecisionType_ZeroVector or decision_info.amount > 1:
		cancel_text = "命名不存在的卡牌"
	select_card_name_card_both_players = decision_info.bonus_effect != null
	var instruction_text = "命名一张对手的卡牌。"
	if select_card_name_card_both_players:
		instruction_text = "命名一张卡牌。"
	clear_selected_cards()
	select_card_require_min = 1
	select_card_require_max = 1
	popout_instruction_info = {
		"popout_type": CardPopoutType.CardPopoutType_ReferenceOpponent,
		"instruction_text": instruction_text,
		"ok_text": "OK",
		"cancel_text": cancel_text,
		"ok_enabled": true,
		"cancel_visible": can_name_fake_card,
		"normal_only": normal_only,
	}
	enable_instructions_ui(instruction_text, true, can_name_fake_card, {})
	change_ui_state(UIState.UIState_SelectCards, UISubState.UISubState_SelectCards_DiscardFromReference)
	_on_opponent_reference_button_pressed(false, true, false)

func _settle_fast_forward_visual_state():
	for card in find_children("*", "CardBase", true, false):
		card.finish_animation_immediately()
	$PlayerLife.finish_animation_immediately()
	$OpponentLife.finish_animation_immediately()
	layout_player_hand(true)
	layout_player_hand(false)
	_refresh_world_positions_after_layout()
	update_card_counts()
	_update_clocks()


func _update_buttons(no_number_picker_update : bool = false):
	var button_choices = []
	# Update main action selection UI

	if not no_number_picker_update:
		action_menu.number_panel_current_number = 0

	if network_reconnect_paused:
		action_menu.visible = false
		action_menu_container.visible = false
		current_action_menu_choices = []
		return

	var action_buttons_visible = ui_state == UIState.UIState_PickTurnAction
	if action_buttons_visible:
		player_bonus_panel.visible = false
		opponent_bonus_panel.visible = false
		var show_chaos_direct_strike_prompt = _should_show_chaos_direct_strike_prompt()
		if len(selected_cards) == 0:
			set_instructions("选择一个行动：")
			instructions_ok_allowed = false
			instructions_cancel_allowed = false
			instructions_strike_options = {}
			instructions_pay_alternative_life_cost = 0
			instructions_face_attack_card = null
			button_choices.append({ "text": "移动", "action": _on_move_button_pressed, "disabled": not game_wrapper.can_do_move(Enums.PlayerId.PlayerId_Player) })
			button_choices.append({ "text": "热身", "action": _wrap_with_confirmation("热身", _on_prepare_button_pressed), "disabled": not game_wrapper.can_do_prepare(Enums.PlayerId.PlayerId_Player) })
			button_choices.append({ "text": "换牌", "action": _on_change_button_pressed, "disabled": not game_wrapper.can_do_change(Enums.PlayerId.PlayerId_Player) })
			var exceed_cost = game_wrapper.get_player_exceed_cost(Enums.PlayerId.PlayerId_Player)
			if exceed_cost >= 0 and not game_wrapper.is_player_exceeded(Enums.PlayerId.PlayerId_Player):
				button_choices.append({ "text": "觉醒! (%s 怒气)" % exceed_cost, "action": _on_exceed_button_pressed, "disabled": not game_wrapper.can_do_exceed(Enums.PlayerId.PlayerId_Player) })
			if game_wrapper.can_do_reshuffle(Enums.PlayerId.PlayerId_Player):
				button_choices.append({ "text": "手动重洗", "action": _on_reshuffle_button_pressed, "disabled": false })
			var ex_transform_available = game_wrapper.can_do_ex_transform(Enums.PlayerId.PlayerId_Player)
			var ex_transform_text = "/Transform" if ex_transform_available else ""
			button_choices.append({ "text": "加成" + ex_transform_text, "action": _wrap_with_confirmation("加成", _on_boost_button_pressed), "disabled": not (game_wrapper.can_do_boost(Enums.PlayerId.PlayerId_Player) or ex_transform_available) })
			var turn_strike_action : Callable = _on_strike_button_pressed
			if show_chaos_direct_strike_prompt:
				turn_strike_action = _wrap_with_chaos_direct_strike_confirmation(_on_strike_button_pressed)
			button_choices.append({ "text": "战斗", "action": turn_strike_action, "disabled": not game_wrapper.can_do_strike(Enums.PlayerId.PlayerId_Player) })
			for i in range(game_wrapper.get_player_character_action_count(Enums.PlayerId.PlayerId_Player)):
				var char_action = game_wrapper.get_player_character_action(Enums.PlayerId.PlayerId_Player, i)
				var action_possible = game_wrapper.can_do_character_action(Enums.PlayerId.PlayerId_Player, i)
				var action_name = "角色主行动"
				if 'action_name' in char_action:
					action_name = char_action['action_name']
				var force_cost = char_action['force_cost']
				var gauge_cost = char_action['gauge_cost']
				var additional_text = ""
				if force_cost > 0:
					additional_text += " (%s 能量)" % force_cost
				if gauge_cost > 0:
					additional_text += " (%s 怒气)" % gauge_cost
				button_choices.append({ "text": "%s%s" % [action_name, additional_text], "action": func(): _on_character_action_pressed(i), "disabled": not action_possible })
			var bonus_available_actions = game_wrapper.get_bonus_actions(Enums.PlayerId.PlayerId_Player)
			for i in range(bonus_available_actions.size()):
				var bonus_action = bonus_available_actions[i]
				var action_text = bonus_action['text']
				var bonus_index = i
				var bonus_force_cost = int(bonus_action.get("force_cost", 0))
				var bonus_gauge_cost = int(bonus_action.get("gauge_cost", 0))
				var bonus_disabled = game_wrapper.get_player_available_force(Enums.PlayerId.PlayerId_Player) < bonus_force_cost \
					or game_wrapper.get_player_available_gauge(Enums.PlayerId.PlayerId_Player) < bonus_gauge_cost
				button_choices.append({ "text": action_text, "action": func(): _on_bonus_action_pressed(bonus_index), "disabled": bonus_disabled })
		else:
			var card_db = game_wrapper.get_card_database()
			var card_name = "这些牌"
			var strike_text = "攻击"
			var boost_text = "加成"
			var can_strike = false
			var can_boost = false
			var can_ex_transform = false
			var only_in_hand = true
			var only_in_gauge = true
			var only_in_hand_or_gauge = true
			var only_in_boosts = true
			var only_set_aside = true
			var allow_change_cards = true
			for card in selected_cards:
				var not_hand_or_gauge = false
				
				if not game_wrapper.is_card_in_hand(Enums.PlayerId.PlayerId_Player, card.card_id):
					only_in_hand = false
				else:
					not_hand_or_gauge = true

				if not game_wrapper.is_card_in_gauge(Enums.PlayerId.PlayerId_Player, card.card_id):
					only_in_gauge = false
				else:
					not_hand_or_gauge = true
					
				if not_hand_or_gauge:
					only_in_hand_or_gauge = false

				if not game_wrapper.is_card_set_aside(Enums.PlayerId.PlayerId_Player, card.card_id):
					only_set_aside = false
				else:
					allow_change_cards = false

				if not game_wrapper.is_card_in_boosts(Enums.PlayerId.PlayerId_Player, card.card_id):
					only_in_boosts = false
				else:
					allow_change_cards = false
			if only_in_hand:
				if len(selected_cards) == 1:
					can_strike = true
					var logic_card = card_db.get_card(selected_cards[0].card_id)
					if logic_card.definition["boost"]["boost_type"] == "transform" and game_wrapper.can_player_ex_transform(Enums.PlayerId.PlayerId_Player, selected_cards[0].card_id):
						boost_text = "EX 转化"
						can_ex_transform = true
					else:
						can_boost = game_wrapper.can_player_boost(Enums.PlayerId.PlayerId_Player, selected_cards[0].card_id, ["hand"], "", false)
				elif len(selected_cards) == 2:
					var card1 = selected_cards[0]
					var card2 = selected_cards[1]
					if card_db.are_same_card(card1.card_id, card2.card_id):
						can_strike = true
						strike_text = "EX 攻击"

						if game_wrapper.can_player_ex_transform(Enums.PlayerId.PlayerId_Player, card1.card_id):
							can_ex_transform = true
							boost_text = "EX 转化"
					elif card_db.get_card(card1.card_id).definition['type'] == "normal" and \
							card_db.get_card(card2.card_id).definition['boost']['boost_type'] == "overload":
						can_strike = true
						strike_text = "EX 攻击"
					elif card_db.get_card(card1.card_id).definition.get("may_ex_with_any_card", false) or \
							card_db.get_card(card2.card_id).definition.get("may_ex_with_any_card", false):
						# 左右开弓：可与任意其他（不同名）牌配对成强力攻击。
						can_strike = true
						strike_text = "EX 攻击"
			elif only_in_boosts:
				if len(selected_cards) == 1:
					var logic_card = card_db.get_card(selected_cards[0].card_id)
					var must_set_from_boost = 'must_set_from_boost' in logic_card.definition and logic_card.definition['must_set_from_boost']
					var may_set_from_boost = 'may_set_from_boost' in logic_card.definition and logic_card.definition['may_set_from_boost']
					can_strike = must_set_from_boost or may_set_from_boost
			elif only_set_aside:
				if len(selected_cards) == 1:
					var set_aside_player = game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
					var set_aside_zone_info = set_aside_player.deck_def.get("stored_zone_info")
					if set_aside_player.exceeded and set_aside_player.deck_def.get("stored_zone_info_exceeded"):
						set_aside_zone_info = set_aside_player.deck_def["stored_zone_info_exceeded"]
					var can_set_from_stored_zone_for_attack = set_aside_zone_info and set_aside_zone_info.get("can_set_for_attack", false)
					can_strike = can_set_from_stored_zone_for_attack and game_wrapper.can_do_strike(Enums.PlayerId.PlayerId_Player)
					if game_wrapper.can_player_boost_from_extra(Enums.PlayerId.PlayerId_Player):
						can_boost = game_wrapper.can_player_boost(Enums.PlayerId.PlayerId_Player, selected_cards[0].card_id, ['extra'], "", false)
			elif only_in_gauge:
				if len(selected_cards) == 1 and game_wrapper.can_player_boost_from_gauge(Enums.PlayerId.PlayerId_Player):
					can_boost = game_wrapper.can_player_boost(Enums.PlayerId.PlayerId_Player, selected_cards[0].card_id, ['gauge'], "", false)

			if can_strike:
				card_name = card_db.get_card(selected_cards[0].card_id).definition['display_name']
				strike_text += " (%s)" % card_name
			if can_boost or can_ex_transform:
				var boost_name = card_db.get_card(selected_cards[0].card_id).definition['boost']['display_name']
				boost_text += " (%s)" % boost_name

			set_instructions("对%s执行什么操作？" % card_name)
			instructions_ok_allowed = false
			instructions_cancel_allowed = false
			instructions_strike_options = {}
			instructions_pay_alternative_life_cost = 0
			instructions_face_attack_card = null
			var shortcut_strike_action : Callable = _wrap_with_confirmation(strike_text, _on_shortcut_strike_pressed)
			if show_chaos_direct_strike_prompt:
				shortcut_strike_action = _wrap_with_chaos_direct_strike_confirmation(_on_shortcut_strike_pressed)
			button_choices.append({ "text": strike_text, "action": shortcut_strike_action, "disabled": not can_strike or not game_wrapper.can_do_strike(Enums.PlayerId.PlayerId_Player) })
			button_choices.append({ "text": boost_text, "action": _wrap_with_confirmation(boost_text, _on_shortcut_boost_pressed),
				"disabled": (not can_boost or not game_wrapper.can_do_boost(Enums.PlayerId.PlayerId_Player)) and (not can_ex_transform or not game_wrapper.can_do_ex_transform(Enums.PlayerId.PlayerId_Player)) })

			# Check for character actions with card-related shortcuts
			for i in range(game_wrapper.get_player_character_action_count(Enums.PlayerId.PlayerId_Player)):
				var char_action = game_wrapper.get_player_character_action(Enums.PlayerId.PlayerId_Player, i)
				var action_has_shortcut = false
				var shortcut_condition_met = false
				var action_name = ""
				var skip_effect_addon = false
				# NOTE: this quick-select shortcut button path doesn't pay force/gauge costs
				# before submitting, so only offer it for free character actions. Actions with
				# a cost (e.g. Carcass's 枪斗术/子弹呼啸) are still reachable via the normal
				# character action button, which properly prompts for cost payment first.
				if 'shortcut_effect_type' in char_action and char_action.get('force_cost', 0) == 0 and char_action.get('gauge_cost', 0) == 0:
					var shortcut_effect = game_wrapper.get_player_character_action_shortcut_effect(Enums.PlayerId.PlayerId_Player, i)
					if char_action['shortcut_effect_type'] == "strike":
						action_has_shortcut = true
						action_name = "攻击 用 "
						#action_name = "Strike with "
						shortcut_condition_met = can_strike
					elif char_action['shortcut_effect_type'] == "gauge_from_hand":
						action_has_shortcut = true
						var destination = char_action.get("shortcut_destination_name", "")
						if destination:
							action_name = "放进 %s" % destination
							#action_name = "Place in %s" % destination
							skip_effect_addon = true
						else:
							action_name = "放入怒气区 为了 "
							#action_name = "Move to Gauge for "
						var min_cards = shortcut_effect['min_amount']
						var max_cards = shortcut_effect['max_amount']
						var card_type_limitation = shortcut_effect.get("card_type_limitation", ["normal", "special", "ultra"])
						var valid_card_count = min_cards <= len(selected_cards) and len(selected_cards) <= max_cards
						var valid_card_types = true
						for card in selected_cards:
							var logic_card = card_db.get_card(card.card_id)
							if logic_card.definition['type'] not in card_type_limitation:
								valid_card_types = false
								break
						shortcut_condition_met = valid_card_count and only_in_hand and valid_card_types
					elif char_action['shortcut_effect_type'] == "self_discard_choose":
						action_has_shortcut = true
						action_name = "弃置 为了 "
						#action_name = "Discard for "
						var min_cards = shortcut_effect['amount']
						var max_cards = shortcut_effect['amount']
						if shortcut_effect['amount'] == -1:
							min_cards = 0
							max_cards = game_wrapper.get_player_hand_size(Enums.PlayerId.PlayerId_Player)
						var valid_card_count = min_cards <= len(selected_cards) and len(selected_cards) <= max_cards
						shortcut_condition_met = valid_card_count and only_in_hand
					elif char_action['shortcut_effect_type'] == "boost_from_gauge":
						action_has_shortcut = true
						action_name = "加成 用 "
						#action_name = "Boost with "
						if len(selected_cards) == 1:
							var valid_zones = ['gauge']
							var limitation = ""
							if 'limitation' in shortcut_effect:
								limitation = shortcut_effect['limitation']
							shortcut_condition_met = game_wrapper.can_player_boost(Enums.PlayerId.PlayerId_Player, selected_cards[0].card_id, valid_zones, limitation, false)
					elif char_action['shortcut_effect_type'] == "gauge_for_effect":
						action_has_shortcut = true
						action_name = "支付 为了 "
						#action_name = "Spend for "
						var min_cards = 0
						if 'required' in shortcut_effect and shortcut_effect['required']:
							min_cards = shortcut_effect['gauge_max']
						var max_cards = shortcut_effect['gauge_max']
						var valid_card_count = min_cards <= len(selected_cards) and len(selected_cards) <= max_cards
						shortcut_condition_met = valid_card_count and only_in_gauge
					elif char_action['shortcut_effect_type'] == "force_for_effect":
						action_has_shortcut = true
						action_name = "支付 为了 "
						#action_name = "Spend for "
						var required_force = shortcut_effect['force_max']
						shortcut_condition_met = only_in_hand_or_gauge and can_selected_cards_pay_force(required_force)

				if action_has_shortcut:
					var action_possible = game_wrapper.can_do_character_action(Enums.PlayerId.PlayerId_Player, i)
					if not skip_effect_addon:
						if 'action_name' in char_action:
							action_name += char_action['action_name']
						else:
							action_name += "角色主行动"
					var force_cost = char_action['force_cost']
					var gauge_cost = char_action['gauge_cost']
					# NOTE: at the moment shortcuts aren't used for any effects with a cost, may not behave properly otherwise
					assert(force_cost == 0 and gauge_cost == 0)
					button_choices.append({ "text": action_name, "action": func(): _on_shortcut_character_action_pressed(i), "disabled": not action_possible or not shortcut_condition_met })

			button_choices.append({ "text": "换牌", "action": _on_shortcut_change_pressed, "disabled": not game_wrapper.can_do_change(Enums.PlayerId.PlayerId_Player) or not allow_change_cards })
			button_choices.append({ "text": "取消选择卡牌", "action": _on_shortcut_cancel_pressed, "disabled": false })

	# Update instructions UI visibility
	var instructions_visible = false
	match ui_state:
		UIState.UIState_SelectCards, UIState.UIState_SelectArenaLocation, UIState.UIState_MakeChoice:
			instructions_visible = true

	# Update instructions UI Buttons
	if popout_instruction_info:
		popout_instruction_info['ok_enabled'] = can_press_ok()
	update_popout_instructions()
	if instructions_ok_allowed:
		button_choices.append({ "text": "确定", "action": func(): _on_instructions_ok_button_pressed(0), "disabled": not can_press_ok() })

	var cancel_text = "取消"
	var current_decision_info = game_wrapper.get_decision_info()
	if not preparing_character_action:
		match ui_sub_state:
			UISubState.UISubState_SelectCards_BoostCancel, UISubState.UISubState_SelectCards_Mulligan, UISubState.UISubState_SelectCards_DiscardCardsToGauge, UISubState.UISubState_SelectCards_ChooseDiscardToDestination:
				cancel_text = "取消" if is_tournelouse_ouroboros_force_choice() else "跳过"
			UISubState.UISubState_SelectCards_ChooseBoostsToSustain:
				cancel_text = "取消" if is_tournelouse_transform_bonus_choice() or is_tournelouse_ouroboros_transform_return_choice() else "跳过"
			UISubState.UISubState_SelectCards_ChooseFromTopdeck, UISubState.UISubState_SelectCards_ChooseOpponentCardToDiscard:
				cancel_text = "跳过"
			UISubState.UISubState_SelectArena_EffectChoice:
				cancel_text = "跳过"
			UISubState.UISubState_SelectCards_GaugeForEffect:
				cancel_text = "取消" if current_decision_info.effect and current_decision_info.effect.get("pass_as_cancel_to_pick_action", false) else "跳过"
			_:
				cancel_text = "取消"

	# Update instructions message
	var ultra_force_toggle = false
	var ex_discard_order_toggle = false
	var free_force_toggle = false
	var show_life_for_force_counter = false
	if ui_state == UIState.UIState_SelectCards:
		match ui_sub_state:
			UISubState.UISubState_SelectCards_DiscardCards:
				update_discard_selection_message()
			UISubState.UISubState_SelectCards_DiscardCards_Choose:
				update_discard_selection_message_choose()
			UISubState.UISubState_SelectCards_ChooseBoostsToSustain:
				update_sustain_selection_message()
			UISubState.UISubState_SelectCards_DiscardCardsToGauge:
				update_discard_to_gauge_selection_message()
			UISubState.UISubState_SelectCards_MoveActionGenerateForce, UISubState.UISubState_SelectCards_CharacterAction_Force:
				free_force_toggle = game_wrapper.get_player_free_force(Enums.PlayerId.PlayerId_Player) > 0
				show_life_for_force_counter = true
				update_force_generation_message()
			UISubState.UISubState_SelectCards_ForceForBoost:
				free_force_toggle = game_wrapper.get_player_free_force(Enums.PlayerId.PlayerId_Player) > 0
				show_life_for_force_counter = true
				var boost_card = game_wrapper.get_card_database().get_card(selected_boost_to_pay_for)
				if boost_card and boost_card.definition.get("id", "") == "devis_lifedrain":
					update_force_generation_message()
			UISubState.UISubState_SelectCards_ForceForChange:
				ultra_force_toggle = true
				free_force_toggle = game_wrapper.get_player_free_force(Enums.PlayerId.PlayerId_Player, "CHANGE_CARDS") > 0
				show_life_for_force_counter = true
				update_force_generation_message()
			UISubState.UISubState_SelectCards_ForceForArmor:
				free_force_toggle = game_wrapper.get_player_free_force(Enums.PlayerId.PlayerId_Player) > 0
				show_life_for_force_counter = true
				update_force_generation_message()
			UISubState.UISubState_SelectCards_ForceForEffect:
				ultra_force_toggle = true
				free_force_toggle = game_wrapper.get_player_free_force(Enums.PlayerId.PlayerId_Player) > 0
				show_life_for_force_counter = true
				if is_tournelouse_ouroboros_force_choice():
					set_instructions("选择支付1F")
				else:
					update_force_generation_message()
			UISubState.UISubState_SelectCards_StrikeForce:
				ex_discard_order_toggle = current_pay_costs_is_ex
				free_force_toggle = game_wrapper.get_player_free_force(Enums.PlayerId.PlayerId_Player) > 0
				show_life_for_force_counter = true
				update_force_generation_message()
			UISubState.UISubState_SelectCards_GaugeForArmor:
				update_gauge_selection_message()
			UISubState.UISubState_SelectCards_StrikeGauge:
				ex_discard_order_toggle = current_pay_costs_is_ex
				update_gauge_selection_message()
			UISubState.UISubState_SelectCards_GaugeForEffect:
				update_gauge_for_effect_message()
			UISubState.UISubState_SelectCards_BoostCancel:
				update_gauge_selection_for_cancel_message()
			UISubState.UISubState_SelectCards_Exceed, UISubState.UISubState_SelectCards_CharacterAction_Gauge, UISubState.UISubState_SelectCards_GaugeForBoost:
				update_gauge_selection_message()

	# Update arena location selection buttons
	for i in range(1, 10):
		var arena_button = get_arena_location_button(i)
		arena_button.visible = (ui_state == UIState.UIState_SelectArenaLocation and i in arena_locations_clickable)

	# Update boost zones
	update_boost_summary(Enums.PlayerId.PlayerId_Player, $AllCards/PlayerBoosts, $PlayerBoostZone)
	update_boost_summary(Enums.PlayerId.PlayerId_Opponent, $AllCards/OpponentBoosts, $OpponentBoostZone)

	choice_popout_button.visible = ui_sub_state in [UISubState.UISubState_SelectCards_ChooseFromTopdeck, UISubState.UISubState_SelectCards_ChooseOpponentCardToDiscard]

	for i in range(current_effect_choices.size()):
		var choice = current_effect_choices[i]
		var card_text = ""
		if current_effect_extra_choice_text:
			card_text = current_effect_extra_choice_text[i]

		var choice_value = i
		if "_choice_value" in choice:
			choice_value = choice["_choice_value"]
		if "_choice_text" in choice:
			card_text += choice["_choice_text"]
		else:
			card_text = get_effect_text_with_card_name(choice, card_text)

		var disabled = false
		if "_choice_disabled" in choice and choice["_choice_disabled"]:
			disabled = true
		elif _choice_spend_life_would_ko_player(choice):
			disabled = true

		if "_choice_func" in choice:
			button_choices.append({ "text": card_text, "action": choice["_choice_func"], "disabled": disabled })
		else:
			button_choices.append({ "text": card_text, "action": func(): _on_choice_pressed(choice_value), "disabled": disabled })

	if instructions_cancel_allowed:
		button_choices.append({ "text": cancel_text, "action": _on_instructions_cancel_button_pressed })
	if instructions_strike_options.get("wild_swing_allowed"):
		button_choices.append({ "text": "疯狂攻击", "action": _on_wild_swing_button_pressed })
	if instructions_strike_options.get("extra_strike_options_count"):
		for i in range(instructions_strike_options["extra_strike_options_count"]):
			var strike_option = game_wrapper.get_player_extra_strike_option(Enums.PlayerId.PlayerId_Player, i)
			if strike_option:
				var button_text = get_effect_text_with_card_name(strike_option, "", true)
				button_choices.append({ "text": button_text, "action": func(): _on_extra_strike_button_pressed(i) })
	if instructions_pay_alternative_life_cost:
		button_choices.append({ "text": "支付 %s 生命" % instructions_pay_alternative_life_cost, "action": _on_pay_alternative_life_cost_button_pressed })
	if ui_state == UIState.UIState_SelectCards and ui_sub_state in [UISubState.UISubState_SelectCards_StrikeCard, UISubState.UISubState_SelectCards_StrikeResponseCard, UISubState.UISubState_SelectCards_OpponentSetsFirst_StrikeCard, UISubState.UISubState_SelectCards_OpponentSetsFirst_StrikeResponseCard]:
		instructions_face_attack_card = game_wrapper.get_face_attack_card(Enums.PlayerId.PlayerId_Player)
	else:
		instructions_face_attack_card = null
	if instructions_face_attack_card:
		var face_attack_player = game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
		if not (face_attack_player.face_attack_id and face_attack_player.face_attack_id == face_attack_player.deck_def.get("buddy_card", "")):
			var face_card_name = instructions_face_attack_card.definition['display_name']
			button_choices.append({ "text": "使用 %s 攻击" % face_card_name, "action": _on_face_attack_button_pressed })

	if can_spend_life_for_force and show_life_for_force_counter:
		instructions_number_picker_min = 0
		instructions_number_picker_max = game_wrapper.get_player_life(Enums.PlayerId.PlayerId_Player)

	if can_spend_life_for_gauge and ui_sub_state in [UISubState.UISubState_SelectCards_StrikeGauge, UISubState.UISubState_SelectCards_Exceed]:
		var life_per_gauge = game_wrapper.get_life_for_gauge_amount(Enums.PlayerId.PlayerId_Player)
		instructions_number_picker_min = 0
		instructions_number_picker_max = game_wrapper.get_player_life(Enums.PlayerId.PlayerId_Player)
		if life_per_gauge > 1:
			instructions_number_picker_max = int(instructions_number_picker_max / life_per_gauge) * life_per_gauge
			action_menu.number_picker_step = life_per_gauge

	action_menu.number_picker_step = 1
	if can_seal_for_force and show_life_for_force_counter:
		var seal_force_player = game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
		var force_limit = max(0, select_card_require_force - seal_force_player.force_cost_reduction) if select_card_require_force > 0 else 99
		instructions_number_picker_min = 0
		instructions_number_picker_max = mini(seal_force_player.discards.size(), force_limit)
	if can_seal_for_gauge and ui_sub_state in [UISubState.UISubState_SelectCards_StrikeGauge, UISubState.UISubState_SelectCards_GaugeForBoost, UISubState.UISubState_SelectCards_GaugeForEffect, UISubState.UISubState_SelectCards_CharacterAction_Gauge, UISubState.UISubState_SelectCards_BoostCancel, UISubState.UISubState_SelectCards_Exceed]:
		var seal_gauge_player = game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
		var gauge_want = select_card_require_max if select_card_require_max > 0 else 99
		instructions_number_picker_min = 0
		instructions_number_picker_max = mini(seal_gauge_player.discards.size(), gauge_want * 3)
		action_menu.number_picker_step = 3

	# Set the Action Menu state
	var action_menu_hidden = false
	match ui_state:
		UIState.UIState_PlayingAnimation, UIState.UIState_WaitForGameServer, UIState.UIState_GameOver:
			action_menu_hidden = true
		UIState.UIState_WaitingOnOpponent:
			action_menu_hidden = true
	action_menu.visible = not action_menu_hidden and (button_choices.size() > 0 or instructions_visible)
	action_menu_container.visible = action_menu.visible
	action_menu.set_choices(
		current_instruction_text,
		button_choices,
		ultra_force_toggle,
		instructions_number_picker_min,
		instructions_number_picker_max,
		ex_discard_order_toggle,
		free_force_toggle,
		no_number_picker_update
	)
	current_action_menu_choices = button_choices

func get_effect_text_with_card_name(effect, current_text, skip_condition : bool = false):
	var card_name = ""
	var card_text = current_text
	if 'card_name' in effect:
		card_name = effect['card_name']
	card_text += GameStrings.get_effect_text(effect, false, true, skip_condition, card_name)
	if len(_choice_text_without_tags(card_text)) > ChoiceTextLengthSoftCap:
		var real_break_idx = 0
		var visible_break_idx = 0
		var in_tag = false
		while visible_break_idx < ChoiceTextLengthSoftCap-1:
			if in_tag:
				if card_text[real_break_idx] == ']':
					in_tag = false
			else:
				if card_text[real_break_idx] == '[':
					in_tag = true
				else:
					visible_break_idx += 1
			real_break_idx += 1

		while real_break_idx < len(card_text)-1 and card_text[real_break_idx] != " ":
			if in_tag:
				if card_text[real_break_idx] == ']':
					in_tag = false
			else:
				if card_text[real_break_idx] == '[':
					in_tag = true
				else:
					visible_break_idx += 1
			real_break_idx += 1
			if visible_break_idx >= ChoiceTextLengthHardCap:
				break
		if real_break_idx < len(card_text) - 1:
			if card_text[real_break_idx] == " ":
				card_text = card_text.substr(0, real_break_idx) + "\n" + card_text.substr(real_break_idx+1)
			else:
				card_text = card_text.substr(0, real_break_idx) + "-\n" + card_text.substr(real_break_idx)
	return card_text

func _get_current_effect_choice_player_id():
	var choice_player_id = game_wrapper.get_decision_info().player
	if choice_player_id in [Enums.PlayerId.PlayerId_Player, Enums.PlayerId.PlayerId_Opponent]:
		return choice_player_id
	return Enums.PlayerId.PlayerId_Player

func _choice_spend_life_would_ko_player(choice) -> bool:
	if choice.get("effect_type") != StrikeEffects.SpendLife:
		return false
	var life_cost = choice.get("amount", 0)
	if not (life_cost is int or life_cost is float):
		return false
	return game_wrapper.get_player_life(_get_current_effect_choice_player_id()) - life_cost <= 0

func _choice_text_without_tags(choice_text):
	return ChoiceTagRegex.sub(choice_text, "", true)

func update_boost_summary(player_id, boosts_card_holder, boost_box):
	var card_ids = []
	var card_db = game_wrapper.get_card_database()
	var summary_player = game_wrapper._get_player(player_id)
	for card in boosts_card_holder.get_children():
		var nantaca_card_has_left_boosts = summary_player.deck_def.get("id") == "nantaca" and (
			summary_player.is_card_in_hand(card.card_id)
			or summary_player.is_card_in_gauge(card.card_id)
			or summary_player.is_card_in_discards(card.card_id)
			or summary_player.is_card_in_sealed(card.card_id)
			or summary_player.is_card_in_overdrive(card.card_id)
			or summary_player.is_card_in_bleach(card.card_id)
		)
		if nantaca_card_has_left_boosts:
			continue
		card_ids.append(card.card_id)
	var transform_effects = []
	var normal_effects = []
	if summary_player.deck_def.get("id") == "minato" and summary_player.exceeded and summary_player.minato_seal_power_bonus > 0:
		normal_effects.append({
			"override_description": "觉醒：你的下一次攻击获得+%d威力。" % int(summary_player.minato_seal_power_bonus)
		})
	if summary_player.deck_def.get("id") == "beheaded" and summary_player.exceeded:
		normal_effects.append({
			"override_description": "觉醒：速度+1，威力+1"
		})
	if summary_player.deck_def.get("id") == "jinglechunshui":
		for normal_id in summary_player.jinglechunshui_named_normal_powerups:
			var normal_name = card_db.get_card_name_by_card_definition_id(normal_id)
			var speed_start = normal_name.find("（")
			if speed_start != -1:
				normal_name = normal_name.substr(0, speed_start)
			normal_effects.append({
				"override_description": "双方 %s 威力+1" % normal_name
			})
	var tournelouse_normal_transform_total = 0
	var nantaca_ua_boost_total = 0
	for card_id in card_ids:
		var card = card_db.get_card(card_id)
		if card.definition['type'] == "normal" and card.definition.has("replaced_boost") and card.definition['boost']['boost_type'] == "transform":
			tournelouse_normal_transform_total += 1
		if summary_player.deck_def.get("id") == "nantaca" and not game_wrapper.is_card_in_sealed(player_id, card_id) and card.definition['boost'].get("stack_in_boost_summary", false):
			nantaca_ua_boost_total += 1
	var tournelouse_normal_transform_count = 0
	var nantaca_ua_boost_count = 0
	for card_id in card_ids:
		var card = card_db.get_card(card_id)
		if game_wrapper.is_card_in_sealed(player_id, card_id):
			# Skip cards that are moving out of the boost area.
			continue
		var is_tournelouse_normal_transform = card.definition['type'] == "normal" and card.definition.has("replaced_boost") and card.definition['boost']['boost_type'] == "transform"
		var add_to_effects = normal_effects
		if card.definition['boost']['boost_type'] == "immediate":
			# Immediate boosts can be here because of facedown,
			# but ignore them as we don't want that text to show.
			continue
		if card.definition['boost']['boost_type'] == "transform":
			add_to_effects = transform_effects
			if not is_tournelouse_normal_transform:
				if card.definition['boost'].has('override_description'):
					add_to_effects.append({
						"override_description": card.definition['boost']['override_description']
					})
				elif card.definition['boost'].has('description'):
					add_to_effects.append({
						"override_description": card.definition['boost']['description']
					})
		if is_tournelouse_normal_transform:
			tournelouse_normal_transform_count += 1
		var is_nantaca_ua_boost = summary_player.deck_def.get("id") == "nantaca" and card.definition['boost'].get("stack_in_boost_summary", false)
		if is_nantaca_ua_boost:
			nantaca_ua_boost_count += 1
			if nantaca_ua_boost_count != nantaca_ua_boost_total:
				continue
			var nantaca_ua_description = card.definition['boost']['effects'][0].get(
				"override_description",
				card.definition['boost'].get("description", "")
			)
			add_to_effects.append({
				"override_description": "%s X %d" % [nantaca_ua_description, nantaca_ua_boost_total]
			})
			continue
		# Renea: skip effects for face-down continuous boosts
		var is_renea_player = game_wrapper._get_player(player_id).deck_def.get("id") == "renea"
		var renea_skip_fd = is_renea_player and card.definition["boost"].get("facedown")

		if 'stop_on_space_effect' in card.definition['boost']:
			var stop_on_space_effect = card.definition['boost']['stop_on_space_effect'].duplicate()
			stop_on_space_effect['timing'] = "on_stop_on_space"
			add_to_effects.append(stop_on_space_effect)
		if card.definition['id'] == "minato_streetcar_disaster" and card.has_meta("minato_dd_count"):
			add_to_effects.append({
				"effect_type": StrikeEffects.Speedup,
				"amount": int(card.get_meta("minato_dd_count"))
			})
		if not renea_skip_fd:
			for effect in card.definition['boost']['effects']:
				if effect.get("hide_in_boost_summary", false):
					continue
				# "now" effects are hidden unless the card data explicitly marks persistent summary text.
				if effect['timing'] == "now" and not effect.get("show_in_boost_summary", false):
					continue
				if effect['timing'] == "discarded":
					continue
				if is_tournelouse_normal_transform and tournelouse_normal_transform_count != tournelouse_normal_transform_total:
					continue
				var effect_to_add = effect
				if is_tournelouse_normal_transform and tournelouse_normal_transform_count == tournelouse_normal_transform_total:
					effect_to_add = effect.duplicate(true)
					effect_to_add["and"] = {
						"condition": "count_numbers",
						"condition_amount": tournelouse_normal_transform_count,
						"effect_type": StrikeEffects.Nothing
					}
				add_to_effects.append(effect_to_add)

	var boost_summary = ""
	# Head with once-per-game mechanic tracking
	var non_exceed_overdrive_active = game_wrapper.non_exceed_overdrive_active(player_id)
	if non_exceed_overdrive_active:
		boost_summary += "[color=cyan]超驱已激活！[/color]\n"
	
	var once_per_game_mechanic = game_wrapper.get_once_per_game_mechanic_name(player_id)
	if once_per_game_mechanic:
		var once_per_game_mechanic_available = game_wrapper.get_once_per_game_mechanic_available(player_id)
		if once_per_game_mechanic_available:
			boost_summary += "[color=gold](%s 可用！)[/color]\n" % once_per_game_mechanic
		else:
			boost_summary += "[color=gray](%s 已使用)[/color]\n" % once_per_game_mechanic

	if game_wrapper.is_player_infused(player_id):
		boost_summary += "[color=sky_blue]灌注！[/color]\n"

	for effect in normal_effects:
		if 'hide_effect' not in effect or not effect['hide_effect']:
			boost_summary += GameStrings.get_effect_text(effect) + "\n"
	for effect in transform_effects:
		if 'hide_effect' not in effect or not effect['hide_effect']:
			var skip_timing = true
			var umina_tf_text = GameStrings.get_effect_text(effect, false, skip_timing)
			# Umina Spiraling Descent: mark as invalid when The Sleeper Wakes is active
			if effect.has('effect_type') and effect['effect_type'] == "umina_spiraling_descent":
				var umina_sd_player = game_wrapper._get_player(player_id)
				if umina_sd_player.umina_dreamlands_facedown:
					umina_tf_text += " [color=gray](Invalid)[/color]"
			boost_summary += "[color=purple][TF][/color] " + umina_tf_text + "\n"

	# Renea: show count of face-down boosts
	var renea_fd_count = 0
	var renea_is_renea = game_wrapper._get_player(player_id).deck_def.get("id") == "renea"
	if renea_is_renea:
		for renea_fd_card in boosts_card_holder.get_children():
			var renea_fd_card_def = card_db.get_card(renea_fd_card.card_id)
			if renea_fd_card_def and renea_fd_card_def.definition["boost"].get("facedown"):
				renea_fd_count += 1
		if renea_fd_count > 0:
			boost_summary += "[color=gray]? face-down boost × %d[/color]\n" % renea_fd_count

	# Ulrik move counters: aggregate by boost name, display totals
	var ulrik_player = game_wrapper._get_player(player_id)
	var name_power_totals = {}
	var name_armor_totals = {}
	var name_seen = {}
	var has_bonus_armor_counter_transform = false
	if summary_player.bonus_armor_counters > 0:
		for card_id in card_ids:
			var bonus_counter_card = card_db.get_card(card_id)
			for boost_effect in bonus_counter_card.definition['boost']['effects']:
				if boost_effect.get('effect_type') == StrikeEffects.IncrementBonusArmorCounters:
					has_bonus_armor_counter_transform = true
					break
			if has_bonus_armor_counter_transform:
				break
	for boost_card in ulrik_player.continuous_boosts:
		var boost_name = boost_card.definition['boost']['display_name']
		for boost_effect in boost_card.definition['boost']['effects']:
			if boost_effect.get('effect_type') == "increment_bonus_move_power_counters":
				name_seen[boost_name] = true
				var pctr = boost_card.get_meta('bonus_move_power_counters', 0)
				name_power_totals[boost_name] = name_power_totals.get(boost_name, 0) + pctr
			if boost_effect.get('effect_type') == "increment_bonus_move_armor_counters":
				name_seen[boost_name] = true
				var actr = boost_card.get_meta('bonus_move_armor_counters', 0)
				name_armor_totals[boost_name] = name_armor_totals.get(boost_name, 0) + actr
	for boost_name in name_seen:
		var pow_total = name_power_totals.get(boost_name, 0)
		var arm_total = name_armor_totals.get(boost_name, 0)
		if pow_total > 0 and arm_total > 0:
			boost_summary += "[color=cyan]%s: Power +%d, Armor +%d[/color]\n" % [boost_name, pow_total, arm_total]
		elif pow_total > 0:
			boost_summary += "[color=cyan]%s: Power +%d[/color]\n" % [boost_name, pow_total]
		elif arm_total > 0:
			boost_summary += "[color=cyan]%s: Armor +%d[/color]\n" % [boost_name, arm_total]
		else:
			boost_summary += "[color=cyan]%s[/color]\n" % boost_name
	if has_bonus_armor_counter_transform:
		boost_summary += "[color=cyan]+%d护甲[/color]\n" % summary_player.bonus_armor_counters

	# Reese Support boost (Chivalry): live accumulated armor/guard counters
	var reese_support_armor = 0
	var reese_support_guard = 0
	for boost_card in ulrik_player.continuous_boosts:
		if boost_card.definition.get('id', '') == "reese_chivalry":
			reese_support_armor = summary_player.bonus_armor_counters
			reese_support_guard = summary_player.bonus_guard_counters
			continue
		for boost_effect in boost_card.definition['boost']['effects']:
			if boost_effect.get('effect_type') == StrikeEffects.AddBonusArmorCounters:
				reese_support_armor = summary_player.bonus_armor_counters
			if boost_effect.get('effect_type') == StrikeEffects.AddBonusGuardCounters:
				reese_support_guard = summary_player.bonus_guard_counters
	if reese_support_armor > 0 or reese_support_guard > 0:
		boost_summary += "[color=cyan]累积: 护甲 +%d, 霸体 +%d[/color]\n" % [reese_support_armor, reese_support_guard]

	for card_id in card_ids:
		var card = card_db.get_card(card_id)
		var must_set_from_boost = 'must_set_from_boost' in card.definition and card.definition['must_set_from_boost']
		var may_set_from_boost = 'may_set_from_boost' in card.definition and card.definition['may_set_from_boost']
		if must_set_from_boost or may_set_from_boost:
			var attack_name = card.definition['display_name']
			# 场上的加成（如诺艾尔的地面炸弹）可能同时存在多张，标出各自所在格，
			# 让玩家知道该选哪一张发起战斗。
			var boost_location = summary_player.get_boost_location(card_id)
			if boost_location != -1:
				boost_summary += "[color=green](可以将 %s（位置%s） 设为攻击！)[/color]\n" % [attack_name, str(boost_location)]
			else:
				boost_summary += "[color=green](可以将 %s 设为攻击！)[/color]\n" % attack_name
	boost_box.set_text(boost_summary)

func update_arena_squares():
	var arena_style := resolved_arena_style
	var uses_classic_arena := BackgroundManager.uses_classic_arena(arena_style)
	arena_graphics.visible = uses_classic_arena
	background_image.texture = BackgroundManager.get_background_texture(arena_style)

	var player_extra_width = 0
	if $PlayerCharacter.is_wide:
		player_extra_width = game_wrapper.get_player_extra_width(Enums.PlayerId.PlayerId_Player)
	var opponent_extra_width = 0
	if $OpponentCharacter.is_wide:
		opponent_extra_width = game_wrapper.get_player_extra_width(Enums.PlayerId.PlayerId_Opponent)

	friend_track_layer.texture = null if uses_classic_arena else BackgroundManager.get_arena_texture(
		arena_style, "B", 10 - cached_player_location)
	enemy_track_layer.texture = null if uses_classic_arena else BackgroundManager.get_arena_texture(
		arena_style, "R", 10 - cached_opponent_location)
	_update_track_overlays_for_character(
		friend_track_overlay_layers,
		arena_style,
		"B",
		cached_player_location,
		player_extra_width,
		uses_classic_arena)
	_update_track_overlays_for_character(
		enemy_track_overlay_layers,
		arena_style,
		"R",
		cached_opponent_location,
		opponent_extra_width,
		uses_classic_arena)

	for i in range(1, 10):
		var square : ArenaSquare = arena_graphics.get_child(i - 1)
		if i >= cached_player_location - player_extra_width and i <= cached_player_location + player_extra_width:
			square.set_self_occupied()
		elif i >= cached_opponent_location - opponent_extra_width and i <= cached_opponent_location + opponent_extra_width:
			square.set_enemy_occupied()
		else:
			square.set_empty()

func selected_cards_between_min_and_max() -> bool:
	var selected_count = len(selected_cards)
	return selected_count >= select_card_require_min && selected_count <= select_card_require_max

func can_press_ok():
	if observer_mode:
		return false

	if ui_state == UIState.UIState_SelectCards:
		match ui_sub_state:
			UISubState.UISubState_SelectCards_StrikeGauge:
				return gauge_selection_meets_requirement()
			UISubState.UISubState_SelectCards_Exceed:
				return gauge_selection_meets_requirement()
			UISubState.UISubState_SelectCards_DiscardCards:
				return selected_cards_between_min_and_max()
			UISubState.UISubState_SelectCards_BoostCancel, UISubState.UISubState_SelectCards_DiscardContinuousBoost, UISubState.UISubState_SelectCards_DiscardFromReference:
				return selected_cards_between_min_and_max()
			UISubState.UISubState_SelectCards_ChooseDiscardToDestination, UISubState.UISubState_SelectCards_DiscardCards_Choose, UISubState.UISubState_SelectCards_DiscardOpponentGauge:
				if is_tournelouse_ouroboros_hand_choice() and selected_cards.size() == 1 and is_tournelouse_ouroboros_paid_card(selected_cards[0].card_id):
					return false
				return selected_cards_between_min_and_max()
			UISubState.UISubState_SelectCards_DiscardCardsToGauge, UISubState.UISubState_SelectCards_Mulligan, UISubState.UISubState_SelectCards_CharacterAction_Gauge:
				return selected_cards_between_min_and_max()
			UISubState.UISubState_SelectCards_ChooseBoostsToSustain:
				if is_tournelouse_ouroboros_transform_return_choice() and selected_cards.size() == 1:
					return not is_tournelouse_ouroboros_paid_card(selected_cards[0].card_id) and not is_tournelouse_ouroboros_bargeist_return_blocked(selected_cards[0].card_id)
				return selected_cards_between_min_and_max()
			UISubState.UISubState_SelectCards_ChooseFromTopdeck, UISubState.UISubState_SelectCards_ChooseOpponentCardToDiscard:
				return selected_cards_between_min_and_max()
			UISubState.UISubState_SelectCards_MoveActionGenerateForce, UISubState.UISubState_SelectCards_CharacterAction_Force:
				return can_selected_cards_pay_force(select_card_require_force)
			UISubState.UISubState_SelectCards_ForceForChange:
				var force_selected = get_force_in_selected_cards()
				if can_seal_for_force:
					force_selected += action_menu.number_panel_current_number
				if use_free_force and game_wrapper.does_free_force_require_card_spent(Enums.PlayerId.PlayerId_Player):
					return force_selected >= 2
				return force_selected >= 1
			UISubState.UISubState_SelectCards_StrikeCard, UISubState.UISubState_SelectCards_StrikeResponseCard, UISubState.UISubState_SelectCards_OpponentSetsFirst_StrikeCard, UISubState.UISubState_SelectCards_OpponentSetsFirst_StrikeResponseCard:
				# As a special exception, allow 2 cards if exactly 2 cards and they're the same card.
				# EX attacks can't be set from boosts, however.
				if len(selected_cards) == 2:
					if not instructions_ex_allowed:
						return false
					if (game_wrapper.is_card_in_boosts(Enums.PlayerId.PlayerId_Player, selected_cards[0].card_id) or
						game_wrapper.is_card_in_boosts(Enums.PlayerId.PlayerId_Player, selected_cards[1].card_id)):
							return false
					var card_db = game_wrapper.get_card_database()
					var card1 = selected_cards[0]
					var card2 = selected_cards[1]
					if card_db.are_same_card(card1.card_id, card2.card_id):
						return true
					if card_db.get_card(card1.card_id).definition['type'] == "normal" and \
							card_db.get_card(card2.card_id).definition['boost']['boost_type'] == "overload":
								return true
					# 左右开弓：可与任意其他（不同名）牌配对成强力攻击。
					return card_db.get_card(card1.card_id).definition.get("may_ex_with_any_card", false) or \
							card_db.get_card(card2.card_id).definition.get("may_ex_with_any_card", false)
				elif len(selected_cards) == 1:
					return not instructions_ex_required
				return false
			UISubState.UISubState_SelectCards_StrikeForce:
				return can_selected_cards_pay_force(select_card_require_force)
			UISubState.UISubState_SelectCards_StrikeCard_FromGauge:
				# This one doesn't allow EX strikes
				return len(selected_cards) == 1
			UISubState.UISubState_SelectCards_StrikeCard_FromSealed:
				# same
				return len(selected_cards) == 1
			UISubState.UISubState_SelectCards_ForceForArmor, UISubState.UISubState_SelectCards_GaugeForArmor:
				return true
			UISubState.UISubState_SelectCards_ForceForEffect:
				var force_selected = get_force_in_selected_cards()
				if is_tournelouse_ouroboros_force_choice():
					if force_selected < 1 or selected_cards.size() != 1:
						return false
					var selected_card_id = selected_cards[0].card_id
					if game_wrapper.is_card_in_hand(Enums.PlayerId.PlayerId_Player, selected_card_id) and game_wrapper.get_player_hand_size(Enums.PlayerId.PlayerId_Player) <= 1:
						return false
					var decision_choice = game_wrapper.get_decision_info().choice
					if decision_choice != null:
						for hand_option in decision_choice:
							if hand_option != selected_card_id:
								return true
					return not game_wrapper.is_card_in_hand(Enums.PlayerId.PlayerId_Player, selected_card_id)
				if select_card_require_force == -1:
					var within_force_limit = select_card_up_to_force == -1 or force_selected <= select_card_up_to_force
					return within_force_limit or can_selected_cards_pay_force(select_card_up_to_force)
				return can_selected_cards_pay_force(select_card_require_force)
			UISubState.UISubState_SelectCards_GaugeForEffect:
				if select_card_must_be_max_or_min:
					var effect = game_wrapper.get_decision_info().effect
					var can_confirm_zero_cost_death_exceed = effect.get("decline_on_death_game_over", false) \
							and select_card_require_min == 0 \
							and select_card_require_max == 0
					if instructions_cancel_allowed and len(selected_cards) == 0 \
							and not can_confirm_zero_cost_death_exceed:
						return false
					# 「要么付最少、要么付最多」：怒气卡可弹性支付，所以两个目标分别看能否达成。
					var gauge_range = get_gauge_generated_range()
					var can_pay_min = gauge_range[0] <= select_card_require_min and gauge_range[1] >= select_card_require_min
					var can_pay_max = gauge_range[0] <= select_card_require_max and gauge_range[1] >= select_card_require_max
					return can_pay_min or can_pay_max
				else:
					# 怒气卡可弹性支付 1..面值 点，判定「可支付区间」与「需求区间」是否有交集。
					return gauge_selection_meets_requirement()
			UISubState.UISubState_SelectCards_PlayBoost:
				return selected_cards_between_min_and_max()
			UISubState.UISubState_SelectCards_ForceForBoost:
				return can_selected_cards_pay_force(select_card_require_force)
			UISubState.UISubState_SelectCards_GaugeForBoost:
				return can_selected_cards_pay_force(select_card_require_max)
	else: # Some other non-select cards state.
		match ui_sub_state:
			UISubState.UISubState_PickNumberFromRange:
				return true
	return false

func begin_select_arena_location(valid_moves):
	arena_locations_clickable = valid_moves
	enable_instructions_ui("选择一个位置", false, true)
	change_ui_state(UIState.UIState_SelectArenaLocation, UISubState.UISubState_SelectCards_MoveActionGenerateForce)

func _on_choose_arena_location_for_effect(event):
	var player = event['event_player']
	var decision_info = game_wrapper.get_decision_info()
	var effect_type = decision_info.effect_type
	var can_pass = decision_info.limitation[0] == 0
	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		if prepared_character_action_data_available("place_buddy_effect"):
			var choice = prepared_character_action_data['choice']
			var success = game_wrapper.submit_choice(Enums.PlayerId.PlayerId_Player, choice)
			if success:
				prepared_character_action_data = {}
				change_ui_state(UIState.UIState_WaitForGameServer)
			return

		arena_locations_clickable = decision_info.limitation
		var instruction_str = "选择一个位置"
		match effect_type:
			"place_boost_in_space":
				var boost_name = decision_info.source
				instruction_str = "选择一个位置来放置 %s" % boost_name
			"place_buddy_into_space":
				var buddy_name = decision_info.source
				instruction_str = "选择一个位置来放置 %s" % buddy_name
			"place_lightningrod":
				instruction_str = "选择一个位置来放置避雷针"
			"place_next_buddy":
				var must_remove = decision_info.extra_info
				var buddy_name = decision_info.source
				if must_remove:
					instruction_str = "选择要移动哪一个 %s" % buddy_name
				else:
					instruction_str = "放置 %s，或选择一个来移动" % buddy_name
			"move_to_space":
				var extra_info = decision_info.extra_info
				if extra_info:
					extra_info = "\n" + extra_info
				instruction_str = "选择要移动到的位置%s" % extra_info
			"remove_buddy_near_opponent":
				var buddy_name = decision_info.source
				instruction_str = "选择要移除的 %s" % buddy_name
		enable_instructions_ui(instruction_str, false, can_pass)
		change_ui_state(UIState.UIState_SelectArenaLocation, UISubState.UISubState_SelectArena_EffectChoice)
	else:
		ai_choose_arena_location_for_effect(decision_info.limitation)

func _on_pick_number_from_range(event):
	var player = event['event_player']
	var decision_info = game_wrapper.get_decision_info()
	var min_value = decision_info.amount_min
	var max_value = decision_info.amount
	var additional_choices = []
	if decision_info.valid_zones:
		# Extra options outside of the number picker.
		# Add these as extra choice buttons.
		for i in range(decision_info.valid_zones.size()):
			var extra_choice = decision_info.valid_zones[i]
			additional_choices.append({
				"_choice_value": i + max_value + 1,
				"_choice_text": extra_choice,
			})

	if player == Enums.PlayerId.PlayerId_Player and not observer_mode:
		# effect_type 是内部标识；抽牌类决策换成可读的中文提示（「摸至多N张」用数字选择器）。
		var pick_prompt_verb = str(decision_info.effect_type)
		if decision_info.effect_type == StrikeEffects.Draw:
			pick_prompt_verb = "抽牌"
		enable_instructions_ui(
			"从 %s-%s 中选择一个数字来 %s" % [str(min_value), str(max_value), pick_prompt_verb],
			true,
			false,
			{},
			false,
			additional_choices,
			true
		)
		change_ui_state(UIState.UIState_MakeChoice, UISubState.UISubState_PickNumberFromRange)
	else:
		ai_pick_number_from_range(decision_info.limitation, decision_info.choice)

func handle_pick_range_ok():
	var decision_info = game_wrapper.get_decision_info()
	var choice_index = 0
	var chosen_number = action_menu.get_current_number_picker_value()
	for i in range(decision_info.limitation.size()):
		if decision_info.limitation[i] == chosen_number:
			choice_index = i
			break

	_on_choice_pressed(choice_index)

	# Return false, _on_choice_pressed handles UI state.
	return false

##
## Button Handlers
##

func _wrap_with_confirmation(action_text: String, action: Callable) -> Callable:
	if GlobalSettings.ActionConfirmationEnabled:
		return func(): _show_action_confirmation(action_text, action)
	return action

func _should_show_chaos_direct_strike_prompt() -> bool:
	if ui_state != UIState.UIState_PickTurnAction:
		return false
	if game_wrapper.get_active_player() != Enums.PlayerId.PlayerId_Player:
		return false
	var current_player = game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	return current_player and current_player.deck_def.get("id") == "chaos"

func _wrap_with_chaos_direct_strike_confirmation(action: Callable) -> Callable:
	return func(): _show_chaos_direct_strike_confirmation(action)

func _show_chaos_direct_strike_confirmation(action: Callable) -> void:
	var on_confirm = func(): action.call()
	var on_cancel = func(): _update_buttons()
	var confirm_choices = [
		{"text": "确定", "action": on_confirm},
		{"text": "取消", "action": on_cancel},
	]
	current_action_menu_choices = confirm_choices
	action_menu.set_choices(
		"是否直接攻击？（不使用UA）。",
		confirm_choices,
		false, -1, -1, false, false, false, 2
	)
	action_menu.visible = true

func _show_action_confirmation(action_text: String, action: Callable) -> void:
	var on_confirm = func(): action.call()
	var on_cancel = func(): _update_buttons()
	var confirm_choices = [
		{"text": "确认", "action": on_confirm},
		{"text": "取消", "action": on_cancel},
	]
	current_action_menu_choices = confirm_choices
	action_menu.set_choices(
		"你确认要进行\"%s\"?" % action_text,
		confirm_choices,
		false, -1, -1, false, false, false, 2
	)
	action_menu.visible = true

func _on_prepare_button_pressed():
	var success = game_wrapper.submit_prepare(Enums.PlayerId.PlayerId_Player)
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	_update_buttons()

func _on_move_button_pressed():
	var valid_moves = []
	for i in range(1, 10):
		if game_wrapper.can_move_to(Enums.PlayerId.PlayerId_Player, i):
			valid_moves.append(i)

	begin_select_arena_location(valid_moves)

func _on_change_button_pressed():
	change_ui_state(null, UISubState.UISubState_SelectCards_ForceForChange)
	begin_generate_force_selection(-1)

func _on_exceed_button_pressed():
	begin_gauge_selection(game_wrapper.get_player_exceed_cost(Enums.PlayerId.PlayerId_Player), false, UISubState.UISubState_SelectCards_Exceed)

func _on_reshuffle_button_pressed():
	var success = game_wrapper.submit_reshuffle(Enums.PlayerId.PlayerId_Player)
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	_update_buttons()

func _on_boost_button_pressed():
	var valid_zones = ['hand']
	if game_wrapper.can_player_boost_from_extra(Enums.PlayerId.PlayerId_Player):
		# Renea: briefcase boost limited to once per turn
		var renea_bp = game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
		if renea_bp.deck_def.get("id") != "renea" or not renea_bp.exceeded or not renea_bp.renea_boost_from_briefcase_used:
			valid_zones.append('extra')
	if game_wrapper.can_player_boost_from_gauge(Enums.PlayerId.PlayerId_Player):
		valid_zones.append('gauge')
	begin_boost_choosing(true, valid_zones, "", false, 1)

func _show_boost_placement_choice():
	# Renea: choose face-up or face-down placement for continuous boosts
	current_action_menu_choices = [
		{"action": func(): pass},
		{"action": func(): pass}
	]
	action_menu.set_choices("Place boost:", [
		{"text": "Face-up (normal)"},
		{"text": "Face-down (hidden)"}
	], false, -1, -1, false, false, true)
	action_menu.visible = true
	var idx = await action_menu.choice_selected
	close_popout()
	return idx

func _get_renea_boost_placement_choice(player_id : Enums.PlayerId, card_id : int) -> int:
	var renea_player = game_wrapper._get_player(player_id)
	if renea_player.deck_def.get("id") != "renea" or renea_player.exceeded:
		return -2
	var logic_card = game_wrapper.get_card_database().get_card(card_id)
	if logic_card == null or logic_card.definition['boost']['boost_type'] != "continuous":
		return -2
	return await _show_boost_placement_choice()

func _renea_has_facedown_boosts() -> bool:
	var renea_p = game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	if renea_p.deck_def.get("id") != "renea":
		return false
	for bc in renea_p.continuous_boosts:
		if bc.definition["boost"].get("facedown"):
			return true
	return false

func _renea_process_facedown_boosts():
	deselect_all_cards()
	# Send this transition in online games so both local engines resolve the same
	# facedown effects before the attack card is selected.
	if game_wrapper.submit_renea_pre_strike_reveal(Enums.PlayerId.PlayerId_Player):
		change_ui_state(UIState.UIState_WaitForGameServer)

func _on_strike_button_pressed():
	# Minato Outrun the Past: auto-trigger before strike if Outrun transform exists
	var minato_p = game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	if minato_p.deck_def.get("id") == "minato" and not minato_p.minato_outrun_triggered_before_strike:
		for minato_otp_tf in minato_p.transforms:
			if minato_otp_tf.definition.get("id") == "minato_flight_13":
				if minato_p.discards.size() + minato_p.gauge.size() == 0:
					# Nothing to seal; Outrun cannot do anything this strike.
					minato_p.minato_outrun_triggered_before_strike = true
					break
				# Networked in online games: both local engines must resolve the
				# same Outrun seal decision before the attack card is selected.
				deselect_all_cards()
				if game_wrapper.submit_minato_outrun_before_strike(Enums.PlayerId.PlayerId_Player):
					change_ui_state(UIState.UIState_WaitForGameServer)
				return
	# Renea: Minato pattern - if facedown boosts exist, process them and return
	if _renea_has_facedown_boosts():
		_renea_process_facedown_boosts()
		return
	begin_strike_choosing(false, true)

func _on_bonus_action_pressed(index : int):
	if game_wrapper.submit_bonus_turn_action(Enums.PlayerId.PlayerId_Player, index):
		# TODO _note_visible_turn_progress()
		change_ui_state(UIState.UIState_WaitForGameServer)
	_update_buttons()

func _on_character_action_pressed(action_idx : int = 0):
	var character_action = game_wrapper.get_player_character_action(Enums.PlayerId.PlayerId_Player, action_idx)
	if not character_action:
		assert(false, "Character action button should not be visible")
		return

	var force_cost = character_action['force_cost']
	var gauge_cost = character_action['gauge_cost']
	selected_character_action = action_idx
	if force_cost > 0:
		change_ui_state(null, UISubState.UISubState_SelectCards_CharacterAction_Force)
		begin_generate_force_selection(force_cost)
	elif gauge_cost > 0:
		begin_gauge_selection(gauge_cost, false, UISubState.UISubState_SelectCards_CharacterAction_Gauge)
	else:
		var shortcut_effect = game_wrapper.get_player_character_action_shortcut_effect(Enums.PlayerId.PlayerId_Player, action_idx)
		if shortcut_effect:
			preparing_character_action = true
			prepared_character_action_data = {
				'effect_type': shortcut_effect['effect_type'],
				'action_idx': action_idx,
				'action_name': "角色主行动"
			}
			if 'action_name' in character_action:
				prepared_character_action_data['action_name'] = character_action['action_name']

			match shortcut_effect['effect_type']:
				"strike":
					_on_strike_button_pressed()
				"gauge_from_hand":
					select_card_destination = shortcut_effect.get("destination", "gauge")
					var card_type_limitation = shortcut_effect.get("card_type_limitation", ["normal", "special", "ultra"])
					var restriction_list = game_wrapper.get_player_cards_in_hand_matching_types(
						Enums.PlayerId.PlayerId_Player,
						card_type_limitation
					)
					var restriction_ids = []
					for card in restriction_list:
						restriction_ids.append(card.id)
					begin_discard_cards_selection(
						shortcut_effect['min_amount'],
						shortcut_effect['max_amount'],
						UISubState.UISubState_SelectCards_DiscardCardsToGauge,
						true,
						restriction_ids,
						false
					)
				"choice":
					var instruction_text = "为%s选择一个效果：" % prepared_character_action_data['action_name']
					begin_effect_choice(shortcut_effect['choice'], instruction_text, [], true)
				"boost_from_gauge":
					var valid_zones = ['gauge']
					var limitation = ""
					if 'limitation' in shortcut_effect:
						limitation = shortcut_effect['limitation']
					begin_boost_choosing(true, valid_zones, limitation, false, 1)
				"self_discard_choose":
					prepared_character_action_data['destination'] = "discard"
					var min_amount = shortcut_effect['amount']
					var max_amount = shortcut_effect['amount']
					if shortcut_effect['amount'] == -1:
						min_amount = 0
						max_amount = game_wrapper.get_player_hand_size(Enums.PlayerId.PlayerId_Player)
					begin_discard_cards_selection(min_amount, max_amount, UISubState.UISubState_SelectCards_DiscardCards_Choose, true)
				"place_buddy_in_any_space", "move_buddy", "place_buddy_at_range":
					var locations = game_wrapper.get_valid_locations_for_buddy_effect(Enums.PlayerId.PlayerId_Player, shortcut_effect)
					prepared_character_action_data['locations'] = locations
					arena_locations_clickable = locations
					var buddy_name = shortcut_effect['buddy_name']
					var instruction_str = "选择一个位置来放置 %s" % buddy_name
					enable_instructions_ui(instruction_str, false, true)
					change_ui_state(UIState.UIState_SelectArenaLocation, UISubState.UISubState_SelectArena_EffectChoice)
				"move_any_boost":
					var locations = game_wrapper.get_valid_locations_for_buddy_effect(Enums.PlayerId.PlayerId_Player, shortcut_effect)
					prepared_character_action_data['locations'] = locations
					arena_locations_clickable = locations
					var boost_name = shortcut_effect['boost_name']
					var instruction_str = "选择一个 %s 加成来移动" % boost_name
					enable_instructions_ui(instruction_str, false, true)
					change_ui_state(UIState.UIState_SelectArenaLocation, UISubState.UISubState_SelectArena_EffectChoice)
				"gauge_for_effect":
					prepared_character_action_data['effect'] = shortcut_effect
					select_card_require_min = 0
					if 'required' in shortcut_effect and shortcut_effect['required']:
						select_card_require_min = shortcut_effect['gauge_max']
					select_card_require_max = shortcut_effect['gauge_max']
					if _effect_has_overall_effect(shortcut_effect) and not _effect_allows_partial_gauge_selection(shortcut_effect):
						select_card_must_be_max_or_min = true
					else:
						select_card_must_be_max_or_min = false
					select_gauge_require_card_id = ""
					select_gauge_require_card_name = ""
					select_gauge_valid_card_types = []
					if 'require_specific_card_id' in shortcut_effect:
						select_gauge_require_card_id = shortcut_effect['require_specific_card_id']
						select_gauge_require_card_name = shortcut_effect['require_specific_card_name']
					if 'valid_card_types' in shortcut_effect:
						select_gauge_valid_card_types = shortcut_effect['valid_card_types']
					begin_gauge_selection(-1, false, UISubState.UISubState_SelectCards_GaugeForEffect)
				"force_for_effect":
					prepared_character_action_data['effect'] = shortcut_effect
					change_ui_state(null, UISubState.UISubState_SelectCards_ForceForEffect)
					select_card_up_to_force = shortcut_effect['force_max']
					if 'per_force_effect' in shortcut_effect and shortcut_effect['per_force_effect']:
						assert(false, "Per-Force effect action shortcuts not supported")
					begin_generate_force_selection(select_card_up_to_force, true)
				_:
					assert(false, "Unexpected shortcut character action type")
					return
		else:
			complete_character_action_pressed(action_idx)

func finish_preparing_character_action(selections):
	var single_card_id = -1
	var ex_card_id = -1
	if len(selections) == 1:
		single_card_id = selections[0]
	if len(selections) == 2:
		single_card_id = selections[0]
		ex_card_id = selections[1]

	match prepared_character_action_data['effect_type']:
		"strike":
			prepared_character_action_data['card_id'] = single_card_id
			prepared_character_action_data['ex_card_id'] = ex_card_id
		"gauge_from_hand":
			prepared_character_action_data['hand_to_gauge_cards'] = selections
		"choice":
			prepared_character_action_data['choice'] = selections[0]
		"boost_from_gauge":
			if 'boost_card' in prepared_character_action_data and prepared_character_action_data['boost_card']:
				# Returning after paying force cost
				prepared_character_action_data['boost_force'] = selections
			else:
				prepared_character_action_data['boost_card'] = single_card_id
				prepared_character_action_data['boost_force'] = []
				var gauge_cost = game_wrapper.get_card_database().get_card_boost_gauge_cost(single_card_id)
				var force_cost = game_wrapper.get_card_database().get_card_boost_force_cost(single_card_id)
				if gauge_cost > 0:
					selected_boost_to_pay_for = single_card_id
					change_ui_state(null, UISubState.UISubState_SelectCards_GaugeForBoost)
					begin_gauge_selection(gauge_cost, false, UISubState.UISubState_SelectCards_GaugeForBoost)
					_update_buttons()
					return
				if force_cost > 0:
					selected_boost_to_pay_for = single_card_id
					change_ui_state(null, UISubState.UISubState_SelectCards_ForceForBoost)
					begin_generate_force_selection(force_cost)
					_update_buttons()
					return
		"self_discard_choose":
			prepared_character_action_data['discard_ids'] = selections
		"place_buddy_in_any_space", "move_buddy", "place_buddy_at_range", "move_any_boost":
			var location = selections[0]
			var location_options = prepared_character_action_data['locations']
			for i in range(location_options.size()):
				if location_options[i] == location:
					prepared_character_action_data['choice'] = i
					break
			prepared_character_action_data['effect_type'] = 'place_buddy_effect'
		"gauge_for_effect":
			prepared_character_action_data['gauge_ids'] = selections
		"force_for_effect":
			prepared_character_action_data['force_ids'] = selections
			prepared_character_action_data['treat_ultras_as_single_force'] = treat_ultras_as_single_force
		_:
			assert(false, "Unexpected prepared character action type")
			return

	complete_character_action_pressed(prepared_character_action_data['action_idx'])

func complete_character_action_pressed(action_idx : int = 0):
	preparing_character_action = false
	var sealed_gauge_player = game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	if minato_sealed_gauge > 0:
		sealed_gauge_player.free_gauge += minato_sealed_gauge
	var success = game_wrapper.submit_character_action(Enums.PlayerId.PlayerId_Player, [], action_idx, use_free_force)
	if minato_sealed_gauge > 0:
		sealed_gauge_player.free_gauge -= minato_sealed_gauge
		minato_sealed_gauge = 0
	if success:
		popout_instruction_info = null
		change_ui_state(UIState.UIState_WaitForGameServer)
	_update_buttons()

func prepared_character_action_data_available(effect_type):
	return prepared_character_action_data and prepared_character_action_data['effect_type'] == effect_type and not preparing_character_action

func _on_choice_pressed(choice):
	if preparing_character_action:
		current_effect_choices = []
		current_effect_extra_choice_text = []
		instructions_number_picker_min = -1
		instructions_number_picker_max = -1
		finish_preparing_character_action([choice])
	else:
		var success = game_wrapper.submit_choice(Enums.PlayerId.PlayerId_Player, choice)
		if success:
			current_effect_choices = []
			current_effect_extra_choice_text = []
			instructions_number_picker_min = -1
			instructions_number_picker_max = -1
			change_ui_state(UIState.UIState_WaitForGameServer)
		elif game_wrapper.get_game_state() != Enums.GameState.GameState_PlayerDecision:
			current_effect_choices = []
			current_effect_extra_choice_text = []
			instructions_number_picker_min = -1
			instructions_number_picker_max = -1
			change_ui_state(UIState.UIState_WaitForGameServer)
	_update_buttons()

func _on_instructions_ok_button_pressed(index : int):
	var seal_player = game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	var minato_sealed_force = 0
	minato_sealed_gauge = 0
	var using_remote_game = game_wrapper.current_game is RemoteGame
	var force_sub_states = [UISubState.UISubState_SelectCards_ForceForBoost, UISubState.UISubState_SelectCards_StrikeForce, UISubState.UISubState_SelectCards_ForceForEffect, UISubState.UISubState_SelectCards_ForceForChange, UISubState.UISubState_SelectCards_ForceForArmor, UISubState.UISubState_SelectCards_MoveActionGenerateForce, UISubState.UISubState_SelectCards_CharacterAction_Force]
	var gauge_sub_states = [UISubState.UISubState_SelectCards_StrikeGauge, UISubState.UISubState_SelectCards_GaugeForBoost, UISubState.UISubState_SelectCards_GaugeForEffect, UISubState.UISubState_SelectCards_CharacterAction_Gauge, UISubState.UISubState_SelectCards_BoostCancel, UISubState.UISubState_SelectCards_Exceed]
	if seal_player.deck_def.get("id") == "minato" and not seal_player.exceeded and ui_sub_state in force_sub_states:
		var seal_ct = mini(action_menu.number_panel_current_number, seal_player.discards.size())
		if seal_ct > 0:
			minato_sealed_force = seal_ct
			if not using_remote_game:
				seal_player.seal_top_n_discards(seal_ct)
	elif seal_player.deck_def.get("id") == "minato" and not seal_player.exceeded and ui_sub_state in gauge_sub_states:
		var seal_ct_gauge = int(action_menu.number_panel_current_number / 3.0) * 3
		if seal_ct_gauge > 0 and seal_player.discards.size() >= seal_ct_gauge:
			minato_sealed_gauge = int(seal_ct_gauge / 3.0)
			if not using_remote_game:
				seal_player.seal_top_n_discards(seal_ct_gauge)
	if can_press_ok():
		if using_remote_game and (minato_sealed_force > 0 or minato_sealed_gauge > 0):
			game_wrapper.set_pending_minato_seal_payment(minato_sealed_force, minato_sealed_gauge)
		var selected_card_ids : Array = get_selected_card_ids()
		var single_card_id = -1
		var ex_card_id = -1
		if len(selected_card_ids) == 1:
			single_card_id = selected_card_ids[0]
		if len(selected_card_ids) == 2:
			single_card_id = selected_card_ids[0]
			ex_card_id = selected_card_ids[1]
		deselect_all_cards()
		close_popout()
		var success = false

		var spent_life_for_force = get_spent_life_for_force()
		var spent_life_for_gauge = get_spent_life_for_gauge()
		if can_spend_life_for_force:
			instructions_number_picker_min = -1
			instructions_number_picker_max = -1
			can_spend_life_for_force = false

		if can_spend_life_for_gauge:
			instructions_number_picker_min = -1
			instructions_number_picker_max = -1
			can_spend_life_for_gauge = false

		if can_seal_for_force or can_seal_for_gauge:
			instructions_number_picker_min = -1
			instructions_number_picker_max = -1
		can_seal_for_force = false
		can_seal_for_gauge = false

		if minato_sealed_force > 0 and not using_remote_game:
			seal_player.seal_force_bonus_tmp = minato_sealed_force
		if minato_sealed_gauge > 0 and not preparing_character_action and not using_remote_game:
			seal_player.free_gauge += minato_sealed_gauge

		if preparing_character_action:
			finish_preparing_character_action(selected_card_ids)
			return

		match ui_sub_state:
			UISubState.UISubState_SelectCards_BoostCancel:
				success = game_wrapper.submit_boost_cancel(Enums.PlayerId.PlayerId_Player, selected_card_ids, true)
			UISubState.UISubState_SelectCards_ChooseFromTopdeck:
				var topdeck_decision_info = game_wrapper.get_decision_info()
				var action_choices = topdeck_decision_info.action
				var chosen_action = action_choices[index]
				_clear_choice_zone_remaining_labels()
				if topdeck_decision_info.select_multiple:
					# 「任意数量」：提交整个选择。这些牌仍留在棋盘上（随后由
					# AddToHand / AddToDiscard / Boost_Played 事件搬走），所以这里
					# 绝不能清空/释放选择区的控件。
					success = game_wrapper.submit_choose_multiple_from_topdeck(Enums.PlayerId.PlayerId_Player, selected_card_ids, chosen_action)
				else:
					success = game_wrapper.submit_choose_from_topdeck(Enums.PlayerId.PlayerId_Player, single_card_id, chosen_action)
			UISubState.UISubState_SelectCards_ChooseOpponentCardToDiscard:
				var adjusted_id = single_card_id - ChoiceCopyIdRangeStart
				success = game_wrapper.submit_choose_to_discard(Enums.PlayerId.PlayerId_Player, [adjusted_id])
				clear_choice_zone()
			UISubState.UISubState_SelectCards_ChooseDiscardToDestination:
				success = game_wrapper.submit_choose_from_discard(Enums.PlayerId.PlayerId_Player, selected_card_ids)
			UISubState.UISubState_SelectCards_CharacterAction_Force, UISubState.UISubState_SelectCards_CharacterAction_Gauge:
				success = game_wrapper.submit_character_action(Enums.PlayerId.PlayerId_Player, selected_card_ids, selected_character_action, use_free_force)
			UISubState.UISubState_SelectCards_DiscardContinuousBoost, UISubState.UISubState_SelectCards_DiscardOpponentGauge:
				select_card_name_boost_restriction = ""
				success = game_wrapper.submit_boost_name_card_choice_effect(Enums.PlayerId.PlayerId_Player, single_card_id)
			UISubState.UISubState_SelectCards_DiscardFromReference:
				success = game_wrapper.submit_boost_name_card_choice_effect(Enums.PlayerId.PlayerId_Player, single_card_id - ReferenceScreenIdRangeStart)
			UISubState.UISubState_SelectCards_DiscardCards:
				success = game_wrapper.submit_discard_to_max(Enums.PlayerId.PlayerId_Player, selected_card_ids)
			UISubState.UISubState_SelectCards_DiscardCards_Choose:
				success = game_wrapper.submit_choose_to_discard(Enums.PlayerId.PlayerId_Player, selected_card_ids)
			UISubState.UISubState_SelectCards_ChooseBoostsToSustain:
				success = game_wrapper.submit_choose_from_boosts(Enums.PlayerId.PlayerId_Player, selected_card_ids)
			UISubState.UISubState_SelectCards_DiscardCardsToGauge:
				success = game_wrapper.submit_relocate_card_from_hand(Enums.PlayerId.PlayerId_Player, selected_card_ids)
			UISubState.UISubState_SelectCards_StrikeForce:
				success = game_wrapper.submit_pay_strike_cost(Enums.PlayerId.PlayerId_Player, selected_card_ids, false, discard_ex_first_for_strike, use_free_force, spent_life_for_force, false)
			UISubState.UISubState_SelectCards_StrikeGauge:
				success = game_wrapper.submit_pay_strike_cost(Enums.PlayerId.PlayerId_Player, selected_card_ids, false, discard_ex_first_for_strike, false, 0, false, spent_life_for_gauge)
			UISubState.UISubState_SelectCards_Exceed:
				success = game_wrapper.submit_exceed(Enums.PlayerId.PlayerId_Player, selected_card_ids, spent_life_for_gauge)
			UISubState.UISubState_SelectCards_ForceForEffect:
				success = game_wrapper.submit_force_for_effect(Enums.PlayerId.PlayerId_Player, selected_card_ids, treat_ultras_as_single_force, false, use_free_force, spent_life_for_force)
			UISubState.UISubState_SelectCards_GaugeForEffect:
				success = game_wrapper.submit_gauge_for_effect(Enums.PlayerId.PlayerId_Player, selected_card_ids)
			UISubState.UISubState_SelectCards_MoveActionGenerateForce:
				success = game_wrapper.submit_move(Enums.PlayerId.PlayerId_Player, selected_card_ids, selected_arena_location, use_free_force, spent_life_for_force)
			UISubState.UISubState_SelectCards_ForceForChange:
				success = game_wrapper.submit_change(Enums.PlayerId.PlayerId_Player, selected_card_ids, treat_ultras_as_single_force, use_free_force, spent_life_for_force)
			UISubState.UISubState_SelectCards_StrikeCard, UISubState.UISubState_SelectCards_StrikeResponseCard, UISubState.UISubState_SelectCards_StrikeCard_FromGauge, UISubState.UISubState_SelectCards_StrikeCard_FromSealed:
				success = game_wrapper.submit_strike(Enums.PlayerId.PlayerId_Player, single_card_id, false, ex_card_id)
			UISubState.UISubState_SelectCards_OpponentSetsFirst_StrikeCard, UISubState.UISubState_SelectCards_OpponentSetsFirst_StrikeResponseCard:
				success = game_wrapper.submit_strike(Enums.PlayerId.PlayerId_Player, single_card_id, false, ex_card_id, true)
			UISubState.UISubState_SelectCards_ForceForArmor:
				success = game_wrapper.submit_force_for_armor(Enums.PlayerId.PlayerId_Player, selected_card_ids, use_free_force, spent_life_for_force)
			UISubState.UISubState_SelectCards_GaugeForArmor:
				success = game_wrapper.submit_force_for_armor(Enums.PlayerId.PlayerId_Player, selected_card_ids, false, 0)
			UISubState.UISubState_SelectCards_Mulligan:
				success = game_wrapper.submit_mulligan(Enums.PlayerId.PlayerId_Player, selected_card_ids)
			UISubState.UISubState_SelectCards_PlayBoost:
				var logic_card = game_wrapper.get_card_database().get_card(single_card_id)
				var facedown_override = null
				if logic_card.definition['boost']['boost_type'] != "transform":
					var placement_choice = await _get_renea_boost_placement_choice(Enums.PlayerId.PlayerId_Player, single_card_id)
					if placement_choice == -1:
						return
					if placement_choice >= 0:
						facedown_override = placement_choice == 1
				if logic_card.definition['boost']['boost_type'] == "transform":
					var ex_transform_id = -1
					if select_boost_options['limitation'] != "transform": # makes sure it's an EX transform action
						ex_transform_id = game_wrapper.get_ex_transform_copy(Enums.PlayerId.PlayerId_Player, single_card_id)
					success = game_wrapper.submit_boost(Enums.PlayerId.PlayerId_Player, single_card_id, [ex_transform_id], false, spent_life_for_force, [])
				else:
					var gauge_cost = game_wrapper.get_card_database().get_card_boost_gauge_cost(single_card_id)
					var force_cost = game_wrapper.get_card_database().get_card_boost_force_cost(single_card_id)
					if not select_boost_options['ignore_costs'] and gauge_cost > 0:
						assert(select_boost_options['boost_amount'] <= 1, "WARNING: Can't currently handle gauge costs for multiple boosts")
						selected_boost_to_pay_for = single_card_id
						selected_boost_facedown_override = facedown_override
						change_ui_state(null, UISubState.UISubState_SelectCards_GaugeForBoost)
						begin_gauge_selection(gauge_cost, false, UISubState.UISubState_SelectCards_GaugeForBoost)
					elif not select_boost_options['ignore_costs'] and force_cost > 0:
						assert(select_boost_options['boost_amount'] <= 1, "WARNING: Can't currently handle force costs for multiple boosts")
						selected_boost_to_pay_for = single_card_id
						selected_boost_facedown_override = facedown_override
						change_ui_state(null, UISubState.UISubState_SelectCards_ForceForBoost)
						begin_generate_force_selection(force_cost)
					else:
						var additional_boost_ids = selected_card_ids.slice(1)
						success = game_wrapper.submit_boost(Enums.PlayerId.PlayerId_Player, single_card_id, [], use_free_force, spent_life_for_force, additional_boost_ids, facedown_override)
			UISubState.UISubState_SelectCards_ForceForBoost:
				success = game_wrapper.submit_boost(Enums.PlayerId.PlayerId_Player, selected_boost_to_pay_for, selected_card_ids, use_free_force, spent_life_for_force, [], selected_boost_facedown_override)
			UISubState.UISubState_SelectCards_GaugeForBoost:
				success = game_wrapper.submit_boost(Enums.PlayerId.PlayerId_Player, selected_boost_to_pay_for, selected_card_ids, false, false, [], selected_boost_facedown_override)
			UISubState.UISubState_PickNumberFromRange:
				success = handle_pick_range_ok()

		if minato_sealed_gauge > 0:
			if not using_remote_game:
				seal_player.free_gauge -= minato_sealed_gauge
			minato_sealed_gauge = 0

		if success:
			popout_instruction_info = null
			change_ui_state(UIState.UIState_WaitForGameServer)
		_update_buttons()

func _on_instructions_cancel_button_pressed():
	if observer_mode:
		return
	game_wrapper.clear_pending_minato_seal_payment()

	var success = false

	if can_spend_life_for_force:
		instructions_number_picker_min = -1
		instructions_number_picker_max = -1
		can_spend_life_for_force = false

	if can_spend_life_for_gauge:
		instructions_number_picker_min = -1
		instructions_number_picker_max = -1
		can_spend_life_for_gauge = false

	if can_seal_for_force or can_seal_for_gauge:
		instructions_number_picker_min = -1
		instructions_number_picker_max = -1
	can_seal_for_force = false
	can_seal_for_gauge = false

	if preparing_character_action:
		deselect_all_cards()
		close_popout()
		preparing_character_action = false
		prepared_character_action_data = {}
		current_effect_choices = []
		current_effect_extra_choice_text = []
		instructions_number_picker_min = -1
		instructions_number_picker_max = -1
		change_ui_state(UIState.UIState_PickTurnAction, UISubState.UISubState_None)
		_update_buttons()
		return

	match ui_sub_state:
		UISubState.UISubState_SelectCards_ForceForArmor:
			deselect_all_cards()
			close_popout()
			success = game_wrapper.submit_force_for_armor(Enums.PlayerId.PlayerId_Player, [], false, 0)
		UISubState.UISubState_SelectCards_ForceForEffect:
			deselect_all_cards()
			close_popout()
			success = game_wrapper.submit_force_for_effect(Enums.PlayerId.PlayerId_Player, [], false, true, false)
			if success:
				popout_instruction_info = null
				change_ui_state(UIState.UIState_WaitForGameServer, UISubState.UISubState_None)
				_update_buttons()
				return
		UISubState.UISubState_SelectCards_GaugeForArmor:
			deselect_all_cards()
			close_popout()
			success = game_wrapper.submit_force_for_armor(Enums.PlayerId.PlayerId_Player, [], false, 0)
		UISubState.UISubState_SelectCards_GaugeForEffect:
			deselect_all_cards()
			close_popout()
			success = game_wrapper.submit_gauge_for_effect(Enums.PlayerId.PlayerId_Player, [])
		UISubState.UISubState_SelectCards_Mulligan:
			deselect_all_cards()
			close_popout()
			success = game_wrapper.submit_mulligan(Enums.PlayerId.PlayerId_Player, [])
		UISubState.UISubState_SelectCards_DiscardCardsToGauge:
			deselect_all_cards()
			close_popout()
			success = game_wrapper.submit_relocate_card_from_hand(Enums.PlayerId.PlayerId_Player, [])
		UISubState.UISubState_SelectCards_ChooseBoostsToSustain:
			deselect_all_cards()
			close_popout()
			if is_tournelouse_ouroboros_transform_return_choice():
				success = game_wrapper.submit_cancel_tournelouse_ouroboros_transform_choice(Enums.PlayerId.PlayerId_Player)
			elif is_tournelouse_transform_bonus_choice():
				success = game_wrapper.submit_cancel_tournelouse_transform_bonus_choice(Enums.PlayerId.PlayerId_Player)
			else:
				success = game_wrapper.submit_choose_from_boosts(Enums.PlayerId.PlayerId_Player, [])
		UISubState.UISubState_SelectCards_ChooseDiscardToDestination:
			deselect_all_cards()
			close_popout()
			success = game_wrapper.submit_choose_from_discard(Enums.PlayerId.PlayerId_Player, [])
		UISubState.UISubState_SelectCards_DiscardContinuousBoost:
			select_card_name_boost_restriction = ""
			deselect_all_cards()
			close_popout()
			success = game_wrapper.submit_boost_name_card_choice_effect(Enums.PlayerId.PlayerId_Player, -1)
		UISubState.UISubState_SelectCards_ChooseFromTopdeck:
			deselect_all_cards()
			_clear_choice_zone_remaining_labels()
			close_popout()
			success = game_wrapper.submit_choose_from_topdeck(Enums.PlayerId.PlayerId_Player, -1, "pass")
		UISubState.UISubState_SelectCards_DiscardCards_Choose:
			deselect_all_cards()
			close_popout()
			if is_tournelouse_ouroboros_hand_choice():
				success = game_wrapper.submit_cancel_tournelouse_ouroboros_hand_choice(Enums.PlayerId.PlayerId_Player)
			else:
				success = game_wrapper.submit_choose_to_discard(Enums.PlayerId.PlayerId_Player, [])
		UISubState.UISubState_SelectCards_DiscardFromReference:
			deselect_all_cards()
			close_popout()
			success = game_wrapper.submit_boost_name_card_choice_effect(Enums.PlayerId.PlayerId_Player, -1)
		UISubState.UISubState_SelectCards_ForceForBoost:
			deselect_all_cards()
			close_popout()
			if select_boost_options:
				var can_cancel = select_boost_options["can_cancel"]
				var valid_zones = select_boost_options["valid_zones"]
				var limitation = select_boost_options["limitation"]
				var ignore_costs = select_boost_options["ignore_costs"]
				var boost_amount = select_boost_options["boost_amount"]
				begin_boost_choosing(can_cancel, valid_zones, limitation, ignore_costs, boost_amount)
			else:
				change_ui_state(UIState.UIState_PickTurnAction, UISubState.UISubState_None)
		UISubState.UISubState_SelectCards_GaugeForBoost:
			deselect_all_cards()
			close_popout()
			if select_boost_options:
				var can_cancel = select_boost_options["can_cancel"]
				var valid_zones = select_boost_options["valid_zones"]
				var limitation = select_boost_options["limitation"]
				var ignore_costs = select_boost_options["ignore_costs"]
				var boost_amount = select_boost_options["boost_amount"]
				begin_boost_choosing(can_cancel, valid_zones, limitation, ignore_costs, boost_amount)
			else:
				change_ui_state(UIState.UIState_PickTurnAction, UISubState.UISubState_None)
		UISubState.UISubState_SelectCards_GaugeForEffect:
			deselect_all_cards()
			close_popout()
			success = game_wrapper.submit_gauge_for_effect(Enums.PlayerId.PlayerId_Player, [])
		_:
			match ui_state:
				UIState.UIState_SelectArenaLocation:
					if instructions_cancel_allowed:
						if ui_sub_state == UISubState.UISubState_SelectArena_EffectChoice:
							success = game_wrapper.submit_choice(Enums.PlayerId.PlayerId_Player, 0)
						else:
							change_ui_state(UIState.UIState_PickTurnAction, UISubState.UISubState_None)
				UIState.UIState_SelectCards:
					if instructions_cancel_allowed:
						deselect_all_cards()
						close_popout()
						if ui_sub_state == UISubState.UISubState_SelectCards_BoostCancel:
							success = game_wrapper.submit_boost_cancel(Enums.PlayerId.PlayerId_Player, [], false)
						else:
							change_ui_state(UIState.UIState_PickTurnAction, UISubState.UISubState_None)
	if success:
		popout_instruction_info = null
		change_ui_state(UIState.UIState_WaitForGameServer)
	_update_buttons()

func _on_wild_swing_button_pressed():
	var success = false
	if ui_state == UIState.UIState_SelectCards:
		if preparing_character_action:
			prepared_character_action_data['wild_swing'] = true
			complete_character_action_pressed(prepared_character_action_data['action_idx'])
			deselect_all_cards()
			_update_buttons()
			return

		if ui_sub_state == UISubState.UISubState_SelectCards_StrikeCard or ui_sub_state == UISubState.UISubState_SelectCards_StrikeResponseCard:
			success = game_wrapper.submit_strike(Enums.PlayerId.PlayerId_Player, -1, true, -1)
		elif ui_sub_state == UISubState.UISubState_SelectCards_OpponentSetsFirst_StrikeCard or ui_sub_state == UISubState.UISubState_SelectCards_OpponentSetsFirst_StrikeResponseCard:
			success = game_wrapper.submit_strike(Enums.PlayerId.PlayerId_Player, -1, true, -1, true)
		elif ui_sub_state == UISubState.UISubState_SelectCards_StrikeGauge:
			close_popout()
			success = game_wrapper.submit_pay_strike_cost(Enums.PlayerId.PlayerId_Player, [], true, false, false, 0, false)
		elif ui_sub_state == UISubState.UISubState_SelectCards_StrikeForce:
			close_popout()
			success = game_wrapper.submit_pay_strike_cost(Enums.PlayerId.PlayerId_Player, [], true, false, false, 0, false)
	if success:
		deselect_all_cards()
		change_ui_state(UIState.UIState_WaitForGameServer)
	_update_buttons()

func _on_extra_strike_button_pressed(index : int):
	var success = false
	if ui_state == UIState.UIState_SelectCards:
		if ui_sub_state == UISubState.UISubState_SelectCards_StrikeCard or ui_sub_state == UISubState.UISubState_SelectCards_StrikeResponseCard:
			success = game_wrapper.submit_strike(Enums.PlayerId.PlayerId_Player, -1, true, index)
		elif ui_sub_state == UISubState.UISubState_SelectCards_OpponentSetsFirst_StrikeCard or ui_sub_state == UISubState.UISubState_SelectCards_OpponentSetsFirst_StrikeResponseCard:
			success = game_wrapper.submit_strike(Enums.PlayerId.PlayerId_Player, -1, true, index, true)
	if success:
		deselect_all_cards()
		change_ui_state(UIState.UIState_WaitForGameServer)
	_update_buttons()

func _on_pay_alternative_life_cost_button_pressed():
	var success = false
	if ui_state == UIState.UIState_SelectCards:
		if ui_sub_state == UISubState.UISubState_SelectCards_StrikeGauge:
			close_popout()
			success = game_wrapper.submit_pay_strike_cost(Enums.PlayerId.PlayerId_Player, [], false, false, false, 0, true)

	if success:
		deselect_all_cards()
		change_ui_state(UIState.UIState_WaitForGameServer)
	_update_buttons()

func _on_face_attack_button_pressed():
	var success = false
	if ui_state == UIState.UIState_SelectCards:
		if ui_sub_state == UISubState.UISubState_SelectCards_StrikeCard or ui_sub_state == UISubState.UISubState_SelectCards_StrikeResponseCard:
			success = game_wrapper.submit_strike(Enums.PlayerId.PlayerId_Player, -1, false, -1, false, true)
		elif ui_sub_state == UISubState.UISubState_SelectCards_OpponentSetsFirst_StrikeCard or ui_sub_state == UISubState.UISubState_SelectCards_OpponentSetsFirst_StrikeResponseCard:
			success = game_wrapper.submit_strike(Enums.PlayerId.PlayerId_Player, -1, false, -1, true, true)
	if success:
		deselect_all_cards()
		change_ui_state(UIState.UIState_WaitForGameServer)
	_update_buttons()

func _on_shortcut_strike_pressed():
	# Minato Outrun the Past: auto-trigger before strike if Outrun transform exists
	var minato_sp = game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	if minato_sp.deck_def.get("id") == "minato" and not minato_sp.minato_outrun_triggered_before_strike:
		for minato_otp_tf in minato_sp.transforms:
			if minato_otp_tf.definition.get("id") == "minato_flight_13":
				if minato_sp.discards.size() + minato_sp.gauge.size() == 0:
					# Nothing to seal; Outrun cannot do anything this strike.
					minato_sp.minato_outrun_triggered_before_strike = true
					break
				# Networked in online games: both local engines must resolve the
				# same Outrun seal decision before the attack card is selected.
				deselect_all_cards()
				if game_wrapper.submit_minato_outrun_before_strike(Enums.PlayerId.PlayerId_Player):
					change_ui_state(UIState.UIState_WaitForGameServer)
				return
	if _renea_has_facedown_boosts():
		_renea_process_facedown_boosts()
		return
	var selected_card_ids : Array = []
	for card in selected_cards:
		selected_card_ids.append(card.card_id)
	deselect_all_cards()

	var success = false
	if len(selected_card_ids) == 1:
		success = game_wrapper.submit_strike(Enums.PlayerId.PlayerId_Player, selected_card_ids[0], false, -1)
	elif len(selected_card_ids) == 2:
		success = game_wrapper.submit_strike(Enums.PlayerId.PlayerId_Player, selected_card_ids[0], false, selected_card_ids[1])
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	_update_buttons()

func _on_shortcut_boost_pressed():
	var selected_card_ids = []
	for card in selected_cards:
		selected_card_ids.append(card.card_id)
	var card_id : int = selected_card_ids[0]
	deselect_all_cards()

	# Renea: briefcase boost limited to once per turn
	var renea_p = game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	if renea_p.deck_def.get("id") == "renea" and renea_p.exceeded and renea_p.renea_boost_from_briefcase_used and renea_p.is_card_in_set_aside(card_id):
		spawn_damage_popup("公文包本回合已使用！", Enums.PlayerId.PlayerId_Player)
		return

	var success = false

	var logic_card = game_wrapper.get_card_database().get_card(card_id)
	var facedown_override = null
	var placement_choice = await _get_renea_boost_placement_choice(Enums.PlayerId.PlayerId_Player, card_id)
	if placement_choice == -1:
		return
	if placement_choice >= 0:
		facedown_override = placement_choice == 1
	var should_ex_transform = game_wrapper.can_player_ex_transform(Enums.PlayerId.PlayerId_Player, card_id) and (logic_card.definition['boost']['boost_type'] == "transform" or len(selected_card_ids) > 1)
	if should_ex_transform:
		var ex_transform_id = -1
		if len(selected_card_ids) > 1:
			ex_transform_id = selected_card_ids[1]
		else:
			ex_transform_id = game_wrapper.get_ex_transform_copy(Enums.PlayerId.PlayerId_Player, card_id)
		success = game_wrapper.submit_boost(Enums.PlayerId.PlayerId_Player, card_id, [ex_transform_id], false, 0)
	else:
		var gauge_cost = game_wrapper.get_card_database().get_card_boost_gauge_cost(card_id)
		var force_cost = game_wrapper.get_card_database().get_card_boost_force_cost(card_id)
		if gauge_cost > 0:
			select_boost_options = {}
			selected_boost_to_pay_for = card_id
			selected_boost_facedown_override = facedown_override
			change_ui_state(null, UISubState.UISubState_SelectCards_GaugeForBoost)
			begin_gauge_selection(gauge_cost, false, UISubState.UISubState_SelectCards_GaugeForBoost)
		elif force_cost > 0:
			select_boost_options = null
			selected_boost_to_pay_for = card_id
			selected_boost_facedown_override = facedown_override
			change_ui_state(null, UISubState.UISubState_SelectCards_ForceForBoost)
			begin_generate_force_selection(force_cost)
		else:
			success = game_wrapper.submit_boost(Enums.PlayerId.PlayerId_Player, card_id, [], use_free_force, 0, [], facedown_override)

	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	_update_buttons()

func _on_shortcut_character_action_pressed(action_idx : int = 0):
	var selected_card_ids : Array = []
	for card in selected_cards:
		selected_card_ids.append(card.card_id)
	deselect_all_cards()

	var shortcut_effect = game_wrapper.get_player_character_action_shortcut_effect(Enums.PlayerId.PlayerId_Player, action_idx)
	prepared_character_action_data = {
		'effect_type': shortcut_effect['effect_type'],
		'action_idx': action_idx,
	}
	finish_preparing_character_action(selected_card_ids)

func _on_shortcut_change_pressed():
	change_ui_state(null, UISubState.UISubState_SelectCards_ForceForChange)
	select_card_require_force = -1

	treat_ultras_as_single_force = false
	var p = game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	if p.zsolt_force_pool > 0 and not game_wrapper.has_active_strike():
		await _choose_zsolt_free_force_from_pool(p)
	use_free_force = game_wrapper.get_player_free_force(Enums.PlayerId.PlayerId_Player, "CHANGE_CARDS") > 0
	can_spend_life_for_force = game_wrapper.get_life_for_force_amount(Enums.PlayerId.PlayerId_Player) > 0
	can_seal_for_force = p.deck_def.get("id") == "minato" and not p.exceeded and p.discards.size() > 0
	action_menu.set_force_ultra_toggle(false)
	action_menu.set_free_force_toggle(use_free_force)

	enable_instructions_ui("", true, true, {})
	change_ui_state(UIState.UIState_SelectCards)

func _on_shortcut_cancel_pressed():
	deselect_all_cards()
	_update_buttons()

func _on_arena_location_pressed(location):
	selected_arena_location = location
	if ui_state == UIState.UIState_SelectArenaLocation:
		if ui_sub_state == UISubState.UISubState_SelectCards_MoveActionGenerateForce:
			begin_generate_force_selection(game_wrapper.get_force_to_move_to(Enums.PlayerId.PlayerId_Player, location))
		elif ui_sub_state == UISubState.UISubState_SelectArena_EffectChoice:
			if preparing_character_action:
				finish_preparing_character_action([location])
				return
			var decision_info = game_wrapper.get_decision_info()
			var choice_index = 0
			for i in range(decision_info.limitation.size()):
				if decision_info.limitation[i] == location:
					choice_index = i
					break
			_on_choice_pressed(choice_index)

#
# AI Functions
#
func _on_ai_move_button_pressed():
	if not game_wrapper.is_ai_game(): return
	var game_state = game_wrapper.get_game_state()
	if game_wrapper.get_active_player() == Enums.PlayerId.PlayerId_Opponent and game_state == Enums.GameState.GameState_PickAction:
		ai_take_turn()

func ai_handle_prepare():
	var success = game_wrapper.submit_prepare(Enums.PlayerId.PlayerId_Opponent)
	if not success:
		printlog("FAILED AI PREPARE")
	return success

func ai_handle_move(action : AIPlayer.MoveAction):
	var location = action.location
	var card_ids = action.force_card_ids
	var do_use_free_force = action.use_free_force
	var success = game_wrapper.submit_move(Enums.PlayerId.PlayerId_Opponent, card_ids, location, do_use_free_force, 0)
	if not success:
		printlog("FAILED AI MOVE")
	return success

func ai_handle_change_cards(action : AIPlayer.ChangeCardsAction):
	var card_ids = action.card_ids
	var do_use_free_force = action.use_free_force
	var success = game_wrapper.submit_change(Enums.PlayerId.PlayerId_Opponent, card_ids, false, do_use_free_force, 0)
	if not success:
		printlog("FAILED AI CHANGE CARDS")
	return success

func ai_handle_exceed(action : AIPlayer.ExceedAction):
	var card_ids = action.card_ids
	var success = game_wrapper.submit_exceed(Enums.PlayerId.PlayerId_Opponent, card_ids)
	if not success:
		printlog("FAILED AI EXCEED")
	return success

func ai_handle_reshuffle():
	var success = game_wrapper.submit_reshuffle(Enums.PlayerId.PlayerId_Opponent)
	if not success:
		printlog("FAILED AI RESHUFFLE")
	return success

func ai_handle_boost(action : AIPlayer.BoostAction):
	var card_id = action.card_id
	var payment_card_ids = action.payment_card_ids
	var do_use_free_force = action.use_free_force
	var additional_boost_ids = action.additional_boost_ids
	var success = game_wrapper.submit_boost(Enums.PlayerId.PlayerId_Opponent, card_id, payment_card_ids, do_use_free_force, 0, additional_boost_ids)
	if not success:
		printlog("FAILED AI BOOST")
	return success

func ai_effect_do_boost(card_id : int):
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var success = game_wrapper.submit_boost(Enums.PlayerId.PlayerId_Opponent, card_id, [], false, 0)
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	else:
		print("FAILED AI EFFECT CAUSED BOOST")

func ai_handle_strike(action : AIPlayer.StrikeAction):
	var card_id = action.card_id
	var ex_card_id = action.ex_card_id
	var wild_swing = action.wild_swing
	#var opponent_sets_first = action.opponent_strikes_first
	var success = game_wrapper.submit_strike(Enums.PlayerId.PlayerId_Opponent, card_id, wild_swing, ex_card_id)
	if not success:
		printlog("FAILED AI STRIKE")
	return success

func ai_handle_character_action(action : AIPlayer.CharacterActionAction):
	var success = game_wrapper.submit_character_action(Enums.PlayerId.PlayerId_Opponent, action.card_ids, action.action_idx, action.use_free_force, 0)
	if not success:
		printlog("FAILED AI CHARACTER ACTION")
	return success

func ai_take_turn():
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var success = false
	var turn_action = ai_player.take_turn()
	if turn_action is AIPlayer.PrepareAction:
		success = ai_handle_prepare()
	elif turn_action is AIPlayer.MoveAction:
		success = ai_handle_move(turn_action)
	elif turn_action is AIPlayer.ChangeCardsAction:
		success = ai_handle_change_cards(turn_action)
	elif turn_action is AIPlayer.ExceedAction:
		success = ai_handle_exceed(turn_action)
	elif turn_action is AIPlayer.ReshuffleAction:
		success = ai_handle_reshuffle()
	elif turn_action is AIPlayer.BoostAction:
		success = ai_handle_boost(turn_action)
	elif turn_action is AIPlayer.StrikeAction:
		success = ai_handle_strike(turn_action)
	elif turn_action is AIPlayer.CharacterActionAction:
		success = ai_handle_character_action(turn_action)
	else:
		assert(false, "Unknown turn action: %s" % turn_action)

	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	else:
		print("FAILED AI TURN")

func ai_do_boost(valid_zones : Array, limitation : String, ignore_costs : bool = false, boost_amount : int = 1):
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var boost_action = ai_player.take_boost(valid_zones, limitation, ignore_costs, boost_amount)
	var success = ai_handle_boost(boost_action)
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	else:
		print("FAILED AI DO BOOST")

func ai_pay_cost(cost, is_force_cost : bool, alternative_life_cost : int = 0):
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var can_wild = game_wrapper.get_decision_info().type == Enums.DecisionType.DecisionType_PayStrikeCost_CanWild
	var pay_action
	if is_force_cost:
		pay_action = ai_player.pay_strike_force_cost(cost, can_wild, alternative_life_cost)
	else:
		pay_action = ai_player.pay_strike_gauge_cost(cost, can_wild, alternative_life_cost)
	var success = game_wrapper.submit_pay_strike_cost(Enums.PlayerId.PlayerId_Opponent, pay_action.card_ids, pay_action.wild_swing, false, pay_action.use_free_force, 0, false)
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	else:
		print("FAILED AI PAY COST")

func ai_effect_choice(_event):
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var effect_action = ai_player.pick_effect_choice()
	var success = game_wrapper.submit_choice(Enums.PlayerId.PlayerId_Opponent, effect_action.choice)
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	else:
		print("FAILED AI EFFECT CHOICE")

func ai_force_for_armor(_event):
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var decision_info = game_wrapper.get_decision_info()
	var use_gauge_instead = decision_info.limitation == "gauge"
	var forceforarmor_action = ai_player.pick_force_for_armor(use_gauge_instead)
	var success = game_wrapper.submit_force_for_armor(Enums.PlayerId.PlayerId_Opponent, forceforarmor_action.card_ids, forceforarmor_action.use_free_force, 0)
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	else:
		print("FAILED AI FORCE FOR ARMOR")

func ai_force_for_effect(effect):
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var options = []
	if effect['per_force_effect'] != null:
		for i in range(effect['force_max'] + 1):
			options.append(i)
	else:
		var required = 'required' in effect and effect['required']
		if not required:
			options.append(0)
		options.append(effect['force_max'])
	var forceforeffect_action = ai_player.pick_force_for_effect(options)
	var success = game_wrapper.submit_force_for_effect(Enums.PlayerId.PlayerId_Opponent, forceforeffect_action.card_ids, false, false, forceforeffect_action.use_free_force)
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	else:
		print("FAILED AI FORCE FOR EFFECT")

func ai_gauge_for_effect(effect):
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var options = []
	if effect['per_gauge_effect'] != null:
		for i in range(effect['gauge_max'] + 1):
			options.append(i)
	else:
		if not 'required' in effect or not effect['required']:
			options.append(0)
		options.append(effect['gauge_max'])
	var require_specific_card_id = effect.get("require_specific_card_id", "")
	var valid_card_types = effect.get("valid_card_types", [])
	var gauge_action = ai_player.pick_gauge_for_effect(options, require_specific_card_id, valid_card_types)
	var success = game_wrapper.submit_gauge_for_effect(Enums.PlayerId.PlayerId_Opponent, gauge_action.card_ids)
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	else:
		print("FAILED AI GAUGE FOR EFFECT")

func ai_strike_response(opponent_set_first_flag : bool = false):
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var response_action = ai_player.pick_strike_response()
	var success = game_wrapper.submit_strike(
		Enums.PlayerId.PlayerId_Opponent,
		response_action.card_id,
		response_action.wild_swing,
		response_action.ex_card_id,
		opponent_set_first_flag
	)
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	else:
		print("FAILED AI STRIKE RESPONSE")

func ai_strike_effect_do_strike(card_id : int, wild_swing : bool, ex_card_id : int):
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var success = game_wrapper.submit_strike(Enums.PlayerId.PlayerId_Opponent, card_id, wild_swing, ex_card_id)
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	else:
		print("FAILED AI EFFECT CAUSED STRIKE")

func ai_discard(event):
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var discard_action = ai_player.pick_discard_to_max(event['number'])
	var success = game_wrapper.submit_discard_to_max(Enums.PlayerId.PlayerId_Opponent, discard_action.card_ids)
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	else:
		print("FAILED AI DISCARD")

func ai_forced_strike(disable_wild_swing : bool = false, disable_ex : bool = false, require_ex : bool = false):
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var strike_action = ai_player.pick_strike("", disable_wild_swing, disable_ex, require_ex)
	ai_handle_strike(strike_action)

func ai_strike_from_gauge(source : String):
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var strike_action = ai_player.pick_strike(source)
	ai_handle_strike(strike_action)

func ai_boost_cancel_decision(gauge_cost):
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var cancel_action = ai_player.pick_cancel(gauge_cost)
	var success = game_wrapper.submit_boost_cancel(Enums.PlayerId.PlayerId_Opponent, cancel_action.card_ids, cancel_action.cancel)
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	else:
		print("FAILED AI BOOST CANCEL")

func ai_discard_continuous_boost(limitation, can_pass, boost_name_restriction):
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var pick_action = ai_player.pick_discard_continuous(limitation, can_pass, boost_name_restriction)
	var success = game_wrapper.submit_boost_name_card_choice_effect(Enums.PlayerId.PlayerId_Opponent, pick_action.card_id)
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	else:
		print("FAILED AI DISCARD CONTINUOUS")

func ai_discard_opponent_gauge():
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var pick_action = ai_player.pick_discard_opponent_gauge()
	var success = game_wrapper.submit_boost_name_card_choice_effect(Enums.PlayerId.PlayerId_Opponent, pick_action.card_id)
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	else:
		print("FAILED AI DISCARD OPPONENT GAUGE")

func ai_name_opponent_card(normal_only : bool, can_use_own_reference : bool):
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var pick_action = ai_player.pick_name_opponent_card(normal_only, can_use_own_reference)
	var success = game_wrapper.submit_boost_name_card_choice_effect(Enums.PlayerId.PlayerId_Opponent, pick_action.card_id)
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	else:
		print("FAILED AI NAME OPPONENT CARD")

func ai_choose_card_hand_to_gauge(min_amount, max_amount, restricted_to_card_ids):
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var cardfromhandtogauge_action = ai_player.pick_card_hand_to_gauge(min_amount, max_amount, restricted_to_card_ids)
	var success = game_wrapper.submit_relocate_card_from_hand(Enums.PlayerId.PlayerId_Opponent, cardfromhandtogauge_action.card_ids)
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	else:
		print("FAILED AI CHOOSE CARD HAND TO GAUGE")

func ai_choose_from_boosts(amount : int):
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var choose_action = ai_player.pick_choose_from_boosts(amount)
	var success = game_wrapper.submit_choose_from_boosts(Enums.PlayerId.PlayerId_Opponent, choose_action.card_ids)
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	else:
		print("FAILED AI CHOOSE FROM BOOSTS")

func ai_choose_from_discard(amount : int):
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var discard_action = ai_player.pick_choose_from_discard(amount)
	var success = game_wrapper.submit_choose_from_discard(Enums.PlayerId.PlayerId_Opponent, discard_action.card_ids)
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	else:
		print("FAILED AI CHOOSE FROM DISCARD")

func ai_mulligan_decision():
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var mulligan_action = ai_player.pick_mulligan()
	var success = game_wrapper.submit_mulligan(Enums.PlayerId.PlayerId_Opponent, mulligan_action.card_ids)
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	else:
		print("FAILED AI MULLIGAN")
	test_init()

func ai_choose_to_discard(amount, limitation, can_pass, allow_fewer):
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var discard_action = ai_player.pick_choose_to_discard(amount, limitation, can_pass, allow_fewer)
	var success = game_wrapper.submit_choose_to_discard(Enums.PlayerId.PlayerId_Opponent, discard_action.card_ids)
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	else:
		print("FAILED AI CHOOSE TO DISCARD")

func ai_choose_from_topdeck(action_choices : Array, look_amount : int, can_pass : bool):
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var ai_decision_info = game_wrapper.get_decision_info()
	if ai_decision_info.select_multiple:
		# 「任意数量」决策：这些牌是免费打出的，AI 直接拿走所有符合条件的看牌。
		var ai_chosen_ids = []
		var ai_card_db = game_wrapper.get_card_database()
		for ai_card_id in game_wrapper.get_player_top_cards(Enums.PlayerId.PlayerId_Opponent, look_amount):
			var ai_logic_card = ai_card_db.get_card(ai_card_id)
			if card_meets_boost_limitation(ai_logic_card, ai_decision_info.limitation):
				ai_chosen_ids.append(ai_card_id)
		var ai_multi_success = game_wrapper.submit_choose_multiple_from_topdeck(Enums.PlayerId.PlayerId_Opponent, ai_chosen_ids, action_choices[0])
		if ai_multi_success:
			change_ui_state(UIState.UIState_WaitForGameServer)
		else:
			print("FAILED AI CHOOSE MULTIPLE FROM TOPDECK")
		return
	var choose_topdeck_action = ai_player.pick_choose_from_topdeck(action_choices, look_amount, can_pass)
	var success = game_wrapper.submit_choose_from_topdeck(Enums.PlayerId.PlayerId_Opponent, choose_topdeck_action.card_id, choose_topdeck_action.action)
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	else:
		print("FAILED AI CHOOSE FROM TOPDECK")

func ai_choose_opponent_card_to_discard(card_ids : Array):
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var discard_action = ai_player.pick_choose_opponent_card_to_discard(card_ids)
	var success = game_wrapper.submit_choose_to_discard(Enums.PlayerId.PlayerId_Opponent, discard_action.card_ids)
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	else:
		print("FAILED AI CHOOSE OPPONENT CARD TO DISCARD")

func ai_choose_arena_location_for_effect(location_choices : Array):
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var choose_location_action = ai_player.pick_choose_arena_location_for_effect(location_choices)
	var chosen_location = choose_location_action.location
	var choice_index = 0
	for i in range(len(location_choices)):
		if location_choices[i] == chosen_location:
			choice_index = i
			break
	var success = game_wrapper.submit_choice(Enums.PlayerId.PlayerId_Opponent, choice_index)
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	else:
		print("FAILED AI CHOOSE ARENA LOCATION FOR EFFECT")

func ai_pick_number_from_range(choices : Array, effects : Array):
	change_ui_state(UIState.UIState_WaitForGameServer)
	if not game_wrapper.is_ai_game(): return
	var choose_action = ai_player.pick_number_from_range_for_effect(choices, effects)
	var chosen_number = choose_action.number
	var choice_index = 0
	for i in range(len(choices)):
		if choices[i] == chosen_number:
			choice_index = i
			break

	var success = game_wrapper.submit_choice(Enums.PlayerId.PlayerId_Opponent, choice_index)
	if success:
		change_ui_state(UIState.UIState_WaitForGameServer)
	else:
		print("FAILED AI CHOOSE NUMBER FROM RANGE")

# Popout Functions
func card_in_selected_cards(card):
	for selected_card in selected_cards:
		if selected_card.card_id == card.card_id:
			return true
	return false

func _update_popout_cards(cards_in_popout : Array, filtering_allowed : bool = false, show_amount : bool = true, card_popout = null, total_slot_count : int = -1):
	if card_popout == null:
		if card_popout_parent.get_child_count() == 0:
			return
		card_popout = card_popout_parent.get_child(0)
	if not is_instance_valid(card_popout) or card_popout.get_parent() == null:
		return
	if show_amount:
		card_popout.set_amount(str(len(cards_in_popout)))
	else:
		card_popout.set_amount("")

	var cards = []
	for card in cards_in_popout:
		if filtering_allowed and popout_show_normal_only() and not game_wrapper.get_card_database().is_normal_card(card.card_id - ReferenceScreenIdRangeStart):
			continue
		cards.append(card)

	card_popout.show_cards(cards, total_slot_count)
	for card in selected_cards:
		card_popout.modify_card_selection(card.card_id, true)

func close_popout():
	while card_popout_parent.get_child_count() > 0:
		var child = card_popout_parent.get_child(0)
		card_popout_parent.remove_child(child)
		child.queue_free()

func clear_choice_zone():
	while choice_zone_parent.get_child_count() > 0:
		var child = choice_zone_parent.get_child(0)
		choice_zone_parent.remove_child(child)
		child.queue_free()

func update_popout_instructions():
	if card_popout_parent.get_child_count() == 0:
		return
	var popout = card_popout_parent.get_child(0)
	if popout_instruction_info and popout_type_showing == popout_instruction_info['popout_type']:
		popout.set_instructions(popout_instruction_info)
	else:
		popout.set_instructions(null)

func popout_show_normal_only() -> bool:
	if popout_instruction_info and 'normal_only' in popout_instruction_info:
		return popout_instruction_info['normal_only']
	return false

func _should_open_or_refresh_popout(open_popout : bool, popout_type : CardPopoutType) -> bool:
	return open_popout or (card_popout_parent.get_child_count() > 0 and popout_type_showing == popout_type)

func show_popout(popout_type : CardPopoutType, popout_title : String, card_node,
		show_amount : bool = true, force_hide_reshuffle = false, extra_only_show_boosts = false):
	close_popout()

	var card_popout = CardPopoutScene.instantiate()
	card_popout_parent.add_child(card_popout)
	card_popout.close_window.connect(_on_popout_close_window)
	card_popout.pressed_ok.connect(_on_card_popout_pressed_ok)
	card_popout.pressed_cancel.connect(_on_card_popout_pressed_cancel)
	card_popout.pressed_toggle.connect(_on_card_popout_pressed_toggle)
	card_popout.card_clicked.connect(_on_card_popout_card_clicked)

	popout_type_showing = popout_type

	var toggle_text = ""
	var toggle_visible = false
	if popout_type == CardPopoutType.CardPopoutType_ReferenceOpponent and not force_hide_reshuffle:
		toggle_visible = true
		if reference_popout_toggle_enabled:
			if reference_popout_toggle:
				toggle_text = "展示当前卡牌"
			else:
				toggle_text = "展示重洗前的卡牌"
	card_popout.set_reference_toggle(toggle_text, toggle_visible)

	update_popout_instructions()
	card_popout.set_title(popout_title)
	var cards = card_node.get_children()

	# Handling filtering for the extra card popout; checks which cards haven't already been played
	var check_player = Enums.PlayerId.PlayerId_Unassigned
	if popout_type == CardPopoutType.CardPopoutType_BuddyPlayer:
		check_player = Enums.PlayerId.PlayerId_Player
		# This is used when showing cards that can be played as boosts
		if extra_only_show_boosts:
			cards = cards.filter(func(card): return game_wrapper.can_player_boost(Enums.PlayerId.PlayerId_Player, card.card_id, ['extra'], "", true))
	elif popout_type == CardPopoutType.CardPopoutType_BuddyOpponent:
		check_player = Enums.PlayerId.PlayerId_Opponent

	if check_player != Enums.PlayerId.PlayerId_Unassigned:
		# If this was set, then the extra card popout is being opened
		# For all buddy cards linked to a specific game card, only include them if they're still
		#  in the set-aside area
		var filtered_cards = []
		for card in cards:
			if card.card_id != CardBase.BuddyCardReferenceId:
				if not game_wrapper.is_card_set_aside(check_player, card.card_id):
					continue
			filtered_cards.append(card)
		cards = filtered_cards

	# Do any sorting of cards for specific zones.
	# Overdrive - speed only sort
	# Sealed - sort but mix ultras/specials
	match popout_type:
		CardPopoutType.CardPopoutType_OverdrivePlayer, CardPopoutType.CardPopoutType_OverdrivePlayer:
			sort_cards(cards, false, true)
		CardPopoutType.CardPopoutType_SealedPlayer, CardPopoutType.CardPopoutType_SealedOpponent:
			sort_cards(cards, true, false)

	var filtering_allowed = popout_type == CardPopoutType.CardPopoutType_ReferenceOpponent
	if popout_type in [CardPopoutType.CardPopoutType_ReferencePlayer, CardPopoutType.CardPopoutType_ReferenceOpponent]:
		_update_popout_cards(cards, filtering_allowed, show_amount, card_popout)
	else:
		await _update_popout_cards_chunked(card_popout, cards, filtering_allowed, show_amount)

func _update_popout_cards_chunked(card_popout, cards : Array, filtering_allowed : bool, show_amount : bool):
	if not is_instance_valid(card_popout) or card_popout.get_parent() == null:
		return
	if not _is_web_runtime() or cards.size() <= WebRuntimeLoadYieldBatchSize:
		_update_popout_cards(cards, filtering_allowed, show_amount, card_popout)
		return
	var total_slot_count = cards.size()
	var cards_to_show = []
	for card in cards:
		if filtering_allowed and popout_show_normal_only() and not game_wrapper.get_card_database().is_normal_card(card.card_id - ReferenceScreenIdRangeStart):
			continue
		cards_to_show.append(card)
	if is_instance_valid(card_popout) and card_popout.get_parent() != null:
		if show_amount:
			card_popout.set_amount("%s" % len(cards_to_show))
		else:
			card_popout.set_amount("")
		var batch_size = get_runtime_load_yield_batch_size(_is_mobile_web_runtime())
		await card_popout.show_cards_chunked(cards_to_show, total_slot_count, batch_size)
		if not is_instance_valid(card_popout) or card_popout.get_parent() == null:
			return
		for card in selected_cards:
			card_popout.modify_card_selection(card.card_id, true)

func get_boost_zone_center(zone):
	var pos = zone.global_position + CardBase.get_hand_card_size() / 2
	pos.x += CardBase.get_hand_card_size().x / 2
	return pos

func _on_player_gauge_gauge_clicked(open_popout : bool = true):
	if _should_open_or_refresh_popout(open_popout, CardPopoutType.CardPopoutType_GaugePlayer):
		show_popout(CardPopoutType.CardPopoutType_GaugePlayer, "你的怒气", $AllCards/PlayerGauge)

func _on_opponent_gauge_gauge_clicked(open_popout : bool = true):
	if _should_open_or_refresh_popout(open_popout, CardPopoutType.CardPopoutType_GaugeOpponent):
		show_popout(CardPopoutType.CardPopoutType_GaugeOpponent, "对手的怒气", $AllCards/OpponentGauge)

func _on_player_sealed_clicked(open_popout : bool = true):
	if _should_open_or_refresh_popout(open_popout, CardPopoutType.CardPopoutType_SealedPlayer):
		show_popout(CardPopoutType.CardPopoutType_SealedPlayer, "你的封印区", $AllCards/PlayerSealed)

func _on_opponent_sealed_clicked(open_popout : bool = true):
	if _should_open_or_refresh_popout(open_popout, CardPopoutType.CardPopoutType_SealedOpponent):
		show_popout(CardPopoutType.CardPopoutType_SealedOpponent, "对手的封印区", $AllCards/OpponentSealed)

func _on_player_bleach_clicked(open_popout : bool = true):
	if _should_open_or_refresh_popout(open_popout, CardPopoutType.CardPopoutType_BleachPlayer):
		show_popout(CardPopoutType.CardPopoutType_BleachPlayer, "你的%s" % game_wrapper.get_player_bleach_zone_name(Enums.PlayerId.PlayerId_Player), $AllCards/PlayerBleach)

func _on_opponent_bleach_clicked(open_popout : bool = true):
	if _should_open_or_refresh_popout(open_popout, CardPopoutType.CardPopoutType_BleachOpponent):
		show_popout(CardPopoutType.CardPopoutType_BleachOpponent, "对手的%s" % game_wrapper.get_player_bleach_zone_name(Enums.PlayerId.PlayerId_Opponent), $AllCards/OpponentBleach)

func _on_player_overdrive_gauge_clicked(open_popout : bool = true):
	if _should_open_or_refresh_popout(open_popout, CardPopoutType.CardPopoutType_OverdrivePlayer):
		show_popout(CardPopoutType.CardPopoutType_OverdrivePlayer, "你的超驱", $AllCards/PlayerOverdrive)

func _on_opponent_overdrive_gauge_clicked(open_popout : bool = true):
	if _should_open_or_refresh_popout(open_popout, CardPopoutType.CardPopoutType_OverdriveOpponent):
		show_popout(CardPopoutType.CardPopoutType_OverdriveOpponent, "对手的超驱", $AllCards/OpponentOverdrive)

func _on_player_discard_button_pressed(open_popout : bool = true):
	if _should_open_or_refresh_popout(open_popout, CardPopoutType.CardPopoutType_DiscardPlayer):
		show_popout(CardPopoutType.CardPopoutType_DiscardPlayer, "你的弃牌堆", $AllCards/PlayerDiscards)

func _on_opponent_discard_button_pressed(open_popout : bool = true):
	if _should_open_or_refresh_popout(open_popout, CardPopoutType.CardPopoutType_DiscardOpponent):
		show_popout(CardPopoutType.CardPopoutType_DiscardOpponent, "对手的弃牌堆", $AllCards/OpponentDiscards)

func _on_player_boost_zone_clicked_zone(open_popout : bool = true):
	var sustained_card_ids = game_wrapper.get_player_sustained_boosts(Enums.PlayerId.PlayerId_Player)
	var boost_zone_player = game_wrapper._get_player(Enums.PlayerId.PlayerId_Player)
	for card in $AllCards/PlayerBoosts.get_children():
		# 场地加成（如诺艾尔的地面炸弹）标出所在格：可能同时存在 2 张，
		# 靠位置才能分辨该点选哪一张发起战斗（弹窗会复制标签，所以这里设好即可）。
		var label_parts : Array[String] = []
		var boost_location = boost_zone_player.get_boost_location(card.card_id)
		if boost_location != -1:
			label_parts.append("位置%d" % boost_location)
		if card.card_id in sustained_card_ids:
			label_parts.append("已维持")
		if label_parts.size() > 0:
			card.set_label(" · ".join(PackedStringArray(label_parts)))
		else:
			card.clear_label()
	if _should_open_or_refresh_popout(open_popout, CardPopoutType.CardPopoutType_BoostPlayer):
		show_popout(CardPopoutType.CardPopoutType_BoostPlayer, "你的加成", $AllCards/PlayerBoosts)

func _on_opponent_boost_zone_clicked_zone(open_popout : bool = true):
	if _should_open_or_refresh_popout(open_popout, CardPopoutType.CardPopoutType_BoostOpponent):
		show_popout(CardPopoutType.CardPopoutType_BoostOpponent, "对手的加成", $AllCards/OpponentBoosts)

func _on_popout_close_window():
	close_popout()

func _try_reopen_special_search_deck_popout() -> bool:
	if ui_state != UIState.UIState_SelectCards:
		return false
	if ui_sub_state not in [UISubState.UISubState_SelectCards_ChooseFromTopdeck, UISubState.UISubState_SelectCards_PlayBoost]:
		return false
	if choice_zone_parent.get_child_count() == 0:
		return false
	if choice_popout_title not in ["牌库", "牌库顶", "牌库顶（一次确认一张）"]:
		return false
	_on_choice_popout_show_button_pressed()
	return true

func _on_player_reference_button_pressed(open_popout : bool = true):
	if _try_reopen_special_search_deck_popout():
		return
	await _refresh_problematic_reference_normals(player_deck['image_resources'])
	await rebuild_reference_copy_zone(
		game_wrapper.get_player_deck_list(Enums.PlayerId.PlayerId_Player),
		$AllCards/PlayerAllCopy,
		[],
		$AllCards/PlayerBuddyCopy,
		player_deck.get("link_extra_cards_to_buddies", false),
		false,
		player_deck['image_resources'],
		player_deck)
	var topdeck_seen_card_id = game_wrapper.get_player_seen_topdeck(Enums.PlayerId.PlayerId_Player)
	var topdeck_seen_card_definition_id = ""
	if topdeck_seen_card_id != -1:
		var topdeck_seen_card = game_wrapper.get_card_database().get_card(topdeck_seen_card_id)
		topdeck_seen_card_definition_id = topdeck_seen_card.definition['id']
	for card in $AllCards/PlayerAllCopy.get_children():
		if card.card_id < 0:
			continue
		var id = card.card_id - ReferenceScreenIdRangeStart
		var logic_card = game_wrapper.get_card_database().get_card(id)
		var card_str_id = logic_card.definition['id']
		var count = game_wrapper.count_cards_in_deck_and_hand(Enums.PlayerId.PlayerId_Player, card_str_id)
		card.set_remaining_count(count)
		var on_topdeck = topdeck_seen_card_definition_id != "" and topdeck_seen_card_definition_id == card_str_id
		card.update_hand_icons(0, 0, on_topdeck, false)
	var reference_title = "你的牌库参考（显示牌库+手牌中剩余卡牌数量"
	if game_wrapper.is_player_sealed_area_secret(Enums.PlayerId.PlayerId_Player):
		reference_title += "+封印区"
	if game_wrapper.has_facedown_boosts(Enums.PlayerId.PlayerId_Player):
		reference_title += "+盖放加成"
	reference_title += "）"
	if _should_open_or_refresh_popout(open_popout, CardPopoutType.CardPopoutType_ReferencePlayer):
		show_popout(CardPopoutType.CardPopoutType_ReferencePlayer, reference_title, $AllCards/PlayerAllCopy, false)

func _on_opponent_reference_button_pressed(switch_toggle : bool = false, hide_reshuffle : bool = false, open_popout : bool = true):
	if _try_reopen_special_search_deck_popout():
		return
	var selected_card_ids : Array = []
	if ui_state == UIState.UIState_SelectCards and ui_sub_state == UISubState.UISubState_SelectCards_DiscardFromReference:
		selected_card_ids = get_selected_card_ids()
		clear_selected_cards()
	if switch_toggle:
		reference_popout_toggle = not reference_popout_toggle
	else:
		reference_popout_toggle = false

	await _refresh_problematic_reference_normals(opponent_deck['image_resources'])
	await rebuild_reference_copy_zone(
		game_wrapper.get_player_deck_list(Enums.PlayerId.PlayerId_Opponent),
		$AllCards/OpponentAllCopy,
		[],
		$AllCards/OpponentBuddyCopy,
		opponent_deck.get("link_extra_cards_to_buddies", false),
		true,
		opponent_deck['image_resources'],
		opponent_deck)

	var public_hand_info = game_wrapper.get_player_public_hand_info(Enums.PlayerId.PlayerId_Opponent)

	for card in $AllCards/OpponentAllCopy.get_children():
		if card.card_id < 0:
			continue
		var id = card.card_id - ReferenceScreenIdRangeStart
		var logic_card = game_wrapper.get_card_database().get_card(id)
		var card_str_id = logic_card.definition['id']
		var count = 0
		var hide_icons = false
		if reference_popout_toggle:
			hide_icons = true
			count = game_wrapper.count_cards_in_deck_and_hand(Enums.PlayerId.PlayerId_Opponent, card_str_id, opponent_cards_before_reshuffle)
		else:
			count = game_wrapper.count_cards_in_deck_and_hand(Enums.PlayerId.PlayerId_Opponent, card_str_id)
		card.set_remaining_count(count)
		var known_count = 0
		var questionable_count = 0
		var on_topdeck = false
		if not hide_icons:
			if card_str_id in public_hand_info['known']:
				known_count = public_hand_info['known'][card_str_id]
			if card_str_id in public_hand_info['questionable']:
				questionable_count = public_hand_info['questionable'][card_str_id]
			on_topdeck = card_str_id == public_hand_info['topdeck']
		card.update_hand_icons(known_count, questionable_count, on_topdeck, false)
	var popout_title = "对手的牌库参考（显示牌库+手牌中剩余卡牌数量"
	if reference_popout_toggle:
		popout_title = "对手洗牌前的卡牌（牌库+手牌中剩余"
	if game_wrapper.is_player_sealed_area_secret(Enums.PlayerId.PlayerId_Opponent):
		popout_title += "+封印区"
	if game_wrapper.has_facedown_boosts(Enums.PlayerId.PlayerId_Opponent):
		popout_title += "+盖放加成"
	popout_title += "）"
	if _should_open_or_refresh_popout(open_popout, CardPopoutType.CardPopoutType_ReferenceOpponent):
		if selected_card_ids.size() > 0:
			_restore_selected_cards_by_ids(selected_card_ids)
		show_popout(CardPopoutType.CardPopoutType_ReferenceOpponent, popout_title, $AllCards/OpponentAllCopy, false, hide_reshuffle)

func _on_player_buddy_button_pressed(only_show_boosts = false, open_popout : bool = true):
	var card_zone = $AllCards/PlayerBuddyCopy
	var zone_header = "你的额外卡牌"
	if player_deck.get("buddy_link_to_zone"):
		match player_deck.get("buddy_link_to_zone"):
			"set_aside":
				card_zone = $AllCards/PlayerSetAside
				var stored_zone_info = player_deck["stored_zone_info"]
				if game_wrapper.is_player_exceeded(Enums.PlayerId.PlayerId_Player):
					stored_zone_info = player_deck["stored_zone_info_exceeded"]
				zone_header = stored_zone_info["name"]
	if _should_open_or_refresh_popout(open_popout, CardPopoutType.CardPopoutType_BuddyPlayer):
		show_popout(CardPopoutType.CardPopoutType_BuddyPlayer, zone_header, card_zone, true, false, only_show_boosts)

func _on_opponent_buddy_button_pressed(open_popout : bool = true):
	var card_zone = $AllCards/OpponentBuddyCopy
	var zone_header = "对手的额外卡牌"
	if opponent_deck.get("buddy_link_to_zone"):
		match opponent_deck.get("buddy_link_to_zone"):
			"set_aside":
				card_zone = $AllCards/OpponentSetAside
				var stored_zone_info = opponent_deck["stored_zone_info"]
				if game_wrapper.is_player_exceeded(Enums.PlayerId.PlayerId_Player):
					stored_zone_info = opponent_deck["stored_zone_info_exceeded"]
				zone_header = stored_zone_info["name"]
	if _should_open_or_refresh_popout(open_popout, CardPopoutType.CardPopoutType_BuddyOpponent):
		show_popout(CardPopoutType.CardPopoutType_BuddyOpponent, zone_header, card_zone)

func _on_exit_to_menu_pressed():
	modal_dialog.set_text_fields("你确定要退出吗？", "退出到\n菜单", "取消")
	modal_dialog_type = ModalDialogType.ModalDialogType_ExitToMenu

func _on_surrender_button_pressed():
	if surrender_in_progress or observer_mode or replay_mode or ui_state == UIState.UIState_GameOver:
		return
	modal_dialog.set_text_fields("确定投降吗？", "确定", "取消")
	modal_dialog_type = ModalDialogType.ModalDialogType_Surrender

func _quit_to_menu():
	exiting = true
	_update_surrender_button_visibility()
	_release_match_resources()
	NetworkManager.leave_room()
	returning_from_game.emit()
	queue_free()

func abandon_match_after_disconnect():
	if exiting:
		return
	_quit_to_menu()

func _on_revealed_cards_button_pressed(open_popout : bool = true):
	reset_revealed_cards()
	var public_hand_info = game_wrapper.get_player_public_hand_info(Enums.PlayerId.PlayerId_Opponent)
	var card_ids = []
	var opponent_deck_list = game_wrapper.get_player_deck_list(Enums.PlayerId.PlayerId_Opponent)
	for card_str_id in public_hand_info['all']:
		# Find a card id that matches this card definition str.
		# It doesn't matter which one for the purposes of this UI.
		for deck_card in opponent_deck_list:
			var logic_card = game_wrapper.get_card_database().get_card(deck_card.id)
			if logic_card.definition['id'] == card_str_id:
				card_ids.append(deck_card.id)
				break

	# Create cards for all of these and add them to the OpponentRevealed node.
	var created_revealed_count = 0
	for card_id in card_ids:
		await add_revealed_card(card_id)
		created_revealed_count += 1
		await runtime_yield_for_loading_batch(created_revealed_count)

	# Update the hand icons for all cards here.
	for card in $AllCards/OpponentRevealed.get_children():
		var id = card.card_id - RevealCopyIdRangeStart
		var logic_card = game_wrapper.get_card_database().get_card(id)
		var card_str_id = logic_card.definition['id']
		var known_count = 0
		var questionable_count = 0
		var on_topdeck = false
		if card_str_id in public_hand_info['known']:
			known_count = public_hand_info['known'][card_str_id]
		if card_str_id in public_hand_info['questionable']:
			questionable_count = public_hand_info['questionable'][card_str_id]
		on_topdeck = card_str_id == public_hand_info['topdeck']
		card.update_hand_icons(known_count, questionable_count, on_topdeck, false)

	if open_popout:
		show_popout(CardPopoutType.CardPopoutType_RevealedOpponent, "已知卡牌", $AllCards/OpponentRevealed)

func _on_card_popout_pressed_ok(index):
	_on_instructions_ok_button_pressed(index)

func _on_card_popout_pressed_cancel():
	_on_instructions_cancel_button_pressed()

func _on_card_popout_pressed_toggle():
	_on_opponent_reference_button_pressed(true)


func _on_combat_log_button_pressed():
	_refresh_combat_log(true)
	combat_log.visible = true

func _refresh_combat_log_if_visible():
	if combat_log.visible:
		_refresh_combat_log()

func _refresh_combat_log(force_refresh : bool = false):
	if not force_refresh and not combat_log.visible:
		return
	var log_size = game_wrapper.get_combat_log_size()
	var rebuild_log = force_refresh or combat_log_rendered_entries > log_size \
		or log_size - combat_log_rendered_start_index > CombatLogVisibleEntryLimit
	var start_index = combat_log_rendered_entries
	if rebuild_log:
		start_index = maxi(0, log_size - CombatLogVisibleEntryLimit)
	var log_text = game_wrapper.get_combat_log(
		combat_log.get_filters(),
		combat_log.log_player_color,
		combat_log.log_opponent_color,
		combat_log.log_card_color,
		start_index)
	if rebuild_log:
		combat_log.set_text(log_text)
		combat_log_rendered_start_index = start_index
	else:
		combat_log.append_text(log_text)
	combat_log_rendered_entries = log_size

func _on_combat_log_close_button_pressed():
	combat_log.visible = false

func _build_replay_start_message() -> Dictionary:
	var replay_start_message = starting_message.duplicate(true)
	replay_start_message.erase("restore_log")
	replay_start_message.erase("observer_log")
	replay_start_message.erase("observer_mode")
	replay_start_message.erase("replay_mode")
	replay_start_message.erase("replay_seek_target")
	replay_start_message.erase("replay_step_rebuild")
	return replay_start_message

func generate_replay_string():
	var messages_list = [_build_replay_start_message()] + game_wrapper.get_message_history()
	var replay_log = {
		'messages': messages_list,
		'version': GlobalSettings.get_client_version(),
		'replay_version': GlobalSettings.ReplayVersion,
	}
	return JSON.stringify(replay_log)

func _is_android_runtime() -> bool:
	return OS.has_feature("android") or OS.get_name() == "Android"

func _sanitize_replay_filename(filename : String) -> String:
	var sanitized = filename
	for invalid_char in ["/", "\\", ":", "*", "?", '"', "<", ">", "|"]:
		sanitized = sanitized.replace(invalid_char, "_")
	return sanitized

func get_replay_filename():
	var filename = Time.get_datetime_string_from_system(false, true).substr(2, 14).replace(":","h")
	filename = filename + " %s (%s) vs %s (%s).txt" % [
		player_deck["id"],
		game_wrapper.get_player_name(Enums.PlayerId.PlayerId_Player),
		opponent_deck["id"],
		game_wrapper.get_player_name(Enums.PlayerId.PlayerId_Opponent)]
	return _sanitize_replay_filename(filename)

func _save_replay_to_path(path : String) -> bool:
	var file_access = FileAccess.open(path, FileAccess.WRITE)
	if file_access == null:
		modal_dialog.set_text_fields("无法保存回放。", "OK", "")
		return false
	file_access.store_string(generate_replay_string())
	file_access.close()
	return true

func _save_replay_to_android_directory() -> bool:
	if not DirAccess.dir_exists_absolute(ReplaySaveDirectory):
		var make_dir_error = DirAccess.make_dir_absolute(ReplaySaveDirectory)
		if make_dir_error != OK:
			modal_dialog.set_text_fields("无法创建回放保存目录。", "OK", "")
			return false
	return _save_replay_to_path(ReplaySaveDirectory.path_join(get_replay_filename()))

func _on_save_replay_button_pressed():
	save_current_replay()

func _download_web_replay(replay_string : String, filename : String) -> bool:
	var window = JavaScriptBridge.get_interface("window")
	if window != null and window.downloadGameReplay != null:
		return bool(window.downloadGameReplay(replay_string, filename))
	JavaScriptBridge.download_buffer(replay_string.to_utf8_buffer(), filename, "text/plain")
	return true

func _show_replay_save_status(message : String):
	modal_dialog_type = ModalDialogType.ModalDialogType_None
	modal_dialog.set_text_fields(message, "确定", "")

func _on_matchlog_upload_finished(success : bool, uploaded : bool, error_message : String):
	save_replay_button.disabled = false
	if success and uploaded:
		_show_replay_save_status("回放已上传到 OSS。\n请在系统分享面板选择‘存储到文件’，或在 UC 下载内容中查看本地文件。")
	elif success:
		_show_replay_save_status("回放上传请求已登记，将在服务器完成对局结算后上传。\n本地文件保存也已触发。")
	else:
		var failure_text := "回放本地保存已触发，但上传 OSS 失败。"
		if not error_message.is_empty():
			failure_text += "\n" + error_message
		_show_replay_save_status(failure_text)

func save_current_replay():
	var should_upload : bool = not bool(game_wrapper.is_ai_game()) and not observer_mode and not replay_mode
	var upload_requested := false
	if should_upload:
		upload_requested = NetworkManager.request_matchlog_upload()
	if OS.has_feature("web"):
		var replay_string = generate_replay_string()
		var local_save_started := _download_web_replay(replay_string, get_replay_filename())
		if should_upload and upload_requested:
			save_replay_button.disabled = true
			_show_replay_save_status("已触发本地回放保存，正在上传到 OSS……")
		elif should_upload:
			_show_replay_save_status("已触发本地回放保存，但上传请求发送失败。")
		elif local_save_started:
			_show_replay_save_status("已触发本地回放保存。")
		else:
			_show_replay_save_status("无法触发本地回放保存。")
		replay_save_finished.emit()
	elif _is_android_runtime():
		if _save_replay_to_android_directory():
			modal_dialog.set_text_fields("回放已保存到应用本地目录。", "OK", "")
		replay_save_finished.emit()
	else:
		file_dialog.current_file = get_replay_filename()
		file_dialog.visible = true

func _on_file_dialog_file_selected(path):
	_save_replay_to_path(path)
	replay_save_finished.emit()

func _on_file_dialog_canceled():
	replay_save_finished.emit()

func _on_action_menu_choice_selected(choice_index):
	var action = current_action_menu_choices[choice_index]['action']
	action.call()

func _on_choice_popout_show_button_pressed(open_popout : bool = true):
	if _should_open_or_refresh_popout(open_popout, CardPopoutType.CardPopoutType_ChoiceZone):
		show_popout(CardPopoutType.CardPopoutType_ChoiceZone, choice_popout_title, choice_zone_parent)

func _on_modal_dialog_accept_button_pressed():
	match modal_dialog_type:
		ModalDialogType.ModalDialogType_ExitToMenu:
			_quit_to_menu()
		ModalDialogType.ModalDialogType_Surrender:
			if game_wrapper.submit_quit(Enums.PlayerId.PlayerId_Player, Enums.GameOverReason.GameOverReason_Quit):
				surrender_in_progress = true
				_update_surrender_button_visibility()

func _on_emote_button_pressed():
	emote_dialog.visible = true

func _on_emote_dialog_close_button_pressed():
	emote_dialog.visible = false

func _on_emote_dialog_emote_selected(is_image_emote : bool, emote : String):
	if observer_mode:
		return
	emote_dialog.visible = false
	game_wrapper.submit_emote(Enums.PlayerId.PlayerId_Player, is_image_emote, emote)

func _on_action_menu_ultra_force_toggled(new_value):
	treat_ultras_as_single_force = new_value
	_update_buttons()

func _on_action_menu_discard_ex_first_toggled(new_value):
	discard_ex_first_for_strike = new_value
	_update_buttons()

func _on_action_menu_free_force_toggled(new_value):
	use_free_force = new_value
	_update_buttons()

func _update_replay_step_buttons():
	if not replay_mode or not observer_previous_button:
		return
	observer_previous_button.disabled = game_wrapper == null \
		or game_wrapper.current_game == null \
		or game_wrapper.get_message_history().is_empty()

func _is_replay_emote_message(message : Dictionary) -> bool:
	return message.get("action_type", "") == "action_emote"

func _process_next_replay_step() -> bool:
	var processed_something = false
	while true:
		var next_message = game_wrapper.get_next_observer_message()
		if next_message.is_empty():
			break
		var is_emote = _is_replay_emote_message(next_message)
		if not game_wrapper.observer_process_next_message_from_queue():
			break
		processed_something = true
		if not is_emote:
			break
	return processed_something

func _get_previous_replay_step_target(processed_messages : Array) -> int:
	var message_index = processed_messages.size() - 1
	while message_index >= 0 and _is_replay_emote_message(processed_messages[message_index]):
		message_index -= 1
	if message_index < 0:
		return 0

	var target = message_index
	while target > 0 and _is_replay_emote_message(processed_messages[target - 1]):
		target -= 1
	return target

func _build_previous_replay_start_data(processed_messages : Array, pending_messages : Array) -> Dictionary:
	var replay_log := processed_messages.duplicate(true)
	replay_log.append_array(pending_messages)
	var replay_start_data : Dictionary = starting_message.duplicate(true)
	replay_start_data["restore_log"] = replay_log
	replay_start_data["observer_log"] = replay_log
	replay_start_data["observer_mode"] = true
	replay_start_data["replay_mode"] = true
	replay_start_data["replay_seek_target"] = _get_previous_replay_step_target(processed_messages)
	replay_start_data["replay_step_rebuild"] = true
	replay_start_data["your_player_id"] = replay_start_data.get("your_player_id", replay_start_data.get("player1_id", 0))
	return replay_start_data

func _on_observer_next_button_pressed():
	if ui_state == UIState.UIState_WaitForGameServer or ui_state == UIState.UIState_WaitingOnOpponent:
		var processed_something = _process_next_replay_step() if replay_mode \
			else game_wrapper.observer_process_next_message_from_queue()
		_update_replay_step_buttons()
		if not processed_something:
			# Caught up to live play.
			observer_next_button.disabled = true
			if replay_mode:
				observer_next_button.text = "GAME OVER"
			else:
				observer_next_button.text = "LIVE"
			observer_live = true
			observer_play_to_live_button.text = "Pause"

func _on_observer_previous_button_pressed():
	if not replay_mode or not starting_message:
		return
	if ui_state not in [UIState.UIState_WaitForGameServer, UIState.UIState_WaitingOnOpponent, UIState.UIState_GameOver]:
		return

	var processed_messages : Array = game_wrapper.get_message_history().duplicate(true)
	if processed_messages.is_empty():
		return
	var replay_start_data := _build_previous_replay_start_data(
		processed_messages,
		game_wrapper.get_pending_observer_messages())

	var vs_info = {
		'player_name': game_wrapper.get_player_name(Enums.PlayerId.PlayerId_Player),
		'player_deck': game_wrapper.get_player_deck_definition(Enums.PlayerId.PlayerId_Player),
		'player_random_tag': "",
		'opponent_name': game_wrapper.get_player_name(Enums.PlayerId.PlayerId_Opponent),
		'opponent_deck': game_wrapper.get_player_deck_definition(Enums.PlayerId.PlayerId_Opponent),
		'opponent_random_tag': "",
		'randomize_first_vs_ai': false,
	}

	observer_previous_button.disabled = true
	var main_scene = get_parent()
	if main_scene and main_scene.has_method("_on_main_menu_start_remote_game"):
		main_scene.call_deferred("_on_main_menu_start_remote_game", vs_info, replay_start_data)

func _on_observer_play_to_live_pressed():
	if observer_live:
		observer_next_button.disabled = false
		observer_next_button.text = "Next Event"
		observer_live = false
		observer_play_to_live_button.text = "Go To Live"
	else:
		observer_next_button.disabled = true
		observer_next_button.text = "LIVE"
		observer_live = true
		observer_play_to_live_button.text = "Pause"

func _on_action_menu_number_picker_updated(_new_value: int) -> void:
	if can_spend_life_for_force or can_spend_life_for_gauge or can_seal_for_force or can_seal_for_gauge:
		_update_buttons(true)

func get_spent_life_for_force() -> int:
	if can_spend_life_for_force:
		return action_menu.number_panel_current_number
	else:
		return 0

func get_spent_life_for_gauge() -> int:
	if can_spend_life_for_gauge:
		return action_menu.number_panel_current_number
	else:
		return 0

func get_gauge_from_spent_life() -> int:
	if can_spend_life_for_gauge:
		var life_per_gauge = game_wrapper.get_life_for_gauge_amount(Enums.PlayerId.PlayerId_Player)
		if life_per_gauge > 0:
			return action_menu.get_current_number_picker_value() / life_per_gauge
	return 0

func _on_slideout_dialog_action_pressed(accept: bool, optional: bool) -> void:
	if accept:
		_quit_to_menu()
	else:
		slideout_dialog.visible = false
		if optional:
			ignore_queue_notifications = true
