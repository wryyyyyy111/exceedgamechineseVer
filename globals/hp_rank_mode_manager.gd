class_name HpRankModeManager
extends RefCounted

const MODE_QUEUE_ID := "hp_rank_mode"
const CONFIG_PATH := "res://data/hp_rank_mode_manager.json"
const DEFAULT_LIFE_CAP := 30

var _loaded := false
var _config_path := CONFIG_PATH
var _loaded_config_signature := ""
var _banned_characters : Dictionary = {}
var _tier_by_character : Dictionary = {}
var _specify_hp_start_adjust_enabled : Dictionary = {}
var _common_rule_hp : Dictionary = {}
var _common_hp_adjust : Dictionary = {}
var _specify_hp_start_adjust : Dictionary = {}

func set_config_path_for_testing(config_path : String) -> void:
	_config_path = config_path
	_loaded = false
	_loaded_config_signature = ""

func is_hp_rank_queue(queue_id : String) -> bool:
	return queue_id == MODE_QUEUE_ID

func build_match_starting_hp(queue_id : String, player1_deck_id : String, player2_deck_id : String) -> Dictionary:
	if not is_hp_rank_queue(queue_id):
		return {"enabled": false}
	if not _ensure_loaded():
		return {
			"enabled": true,
			"valid": false,
			"error": "hp_rank_config_load_failed",
		}

	var player1_character = _resolve_mode_character_id(player1_deck_id)
	var player2_character = _resolve_mode_character_id(player2_deck_id)

	if _is_banned(player1_character) or _is_banned(player2_character):
		return {
			"enabled": true,
			"valid": false,
			"error": "banned_character",
			"player1_character": player1_character,
			"player2_character": player2_character,
		}

	var player1_tier = str(_tier_by_character.get(player1_character, ""))
	var player2_tier = str(_tier_by_character.get(player2_character, ""))
	if player1_tier.is_empty() or player2_tier.is_empty():
		return {
			"enabled": true,
			"valid": false,
			"error": "tier_missing",
			"player1_character": player1_character,
			"player2_character": player2_character,
			"player1_tier": player1_tier,
			"player2_tier": player2_tier,
		}

	var common_hp = _get_common_rule_hp(player1_tier, player2_tier)
	if common_hp.size() != 2:
		return {
			"enabled": true,
			"valid": false,
			"error": "common_rule_missing",
			"player1_tier": player1_tier,
			"player2_tier": player2_tier,
		}

	var player1_hp = int(common_hp[0])
	var player2_hp = int(common_hp[1])

	player1_hp = _apply_specify_start_hp(player1_character, player2_tier, player1_hp)
	player2_hp = _apply_specify_start_hp(player2_character, player1_tier, player2_hp)

	player1_hp = _apply_common_hp_adjust(player1_character, player1_hp)
	player2_hp = _apply_common_hp_adjust(player2_character, player2_hp)

	player1_hp = max(player1_hp, 1)
	player2_hp = max(player2_hp, 1)

	var player1_life_cap = player1_hp
	var player2_life_cap = player2_hp
	if _uses_default_life_cap(player1_character):
		player1_life_cap = DEFAULT_LIFE_CAP
	if _uses_default_life_cap(player2_character):
		player2_life_cap = DEFAULT_LIFE_CAP

	return {
		"enabled": true,
		"valid": true,
		"player1_character": player1_character,
		"player2_character": player2_character,
		"player1_tier": player1_tier,
		"player2_tier": player2_tier,
		"player1_starting_life": player1_hp,
		"player2_starting_life": player2_hp,
		"player1_life_cap": player1_life_cap,
		"player2_life_cap": player2_life_cap,
	}

func apply_starting_hp_to_deck(deck_def : Dictionary, starting_life : int, life_cap : int) -> Dictionary:
	var patched = deck_def.duplicate(true)
	patched["starting_life"] = int(starting_life)
	patched["life_cap"] = int(life_cap)
	patched["hp_rank_mode_enabled"] = true
	return patched

func get_taisei_exceed_life(character_id : String, opponent_tier : String, fallback : int = 10) -> int:
	if not _ensure_loaded():
		return fallback
	var resolved_character = _resolve_mode_character_id(character_id)
	if _get_base_character_id(resolved_character) != "taisei":
		return fallback

	var taisei_data = _specify_hp_start_adjust.get("taisei", null)
	if not (taisei_data is Dictionary):
		return fallback
	var taisei_exceed_table = taisei_data.get("taisei_exceed", [])
	if not (taisei_exceed_table is Array):
		return fallback

	for entry in taisei_exceed_table:
		if not (entry is Dictionary):
			continue
		if str(entry.get("tier", "")).strip_edges() != opponent_tier:
			continue
		return max(_parse_signed_int(str(entry.get("hp_start", fallback))), 1)
	return fallback

func _ensure_loaded() -> bool:
	var file := FileAccess.open(_config_path, FileAccess.READ)
	if file == null:
		if _loaded:
			# Keep using the last valid snapshot if hot-reload source is temporarily unavailable.
			return true
		push_error("HpRankModeManager: failed to open %s" % _config_path)
		return false

	var json_text = file.get_as_text()
	file.close()
	var current_signature = json_text.md5_text()
	if _loaded and current_signature == _loaded_config_signature:
		return true

	var parser := JSON.new()
	if parser.parse(json_text) != OK:
		if _loaded:
			push_warning("HpRankModeManager: failed to parse updated config %s, keeping last valid config" % _config_path)
			return true
		push_error("HpRankModeManager: failed to parse %s" % _config_path)
		return false

	var root = parser.data
	if not (root is Dictionary):
		if _loaded:
			push_warning("HpRankModeManager: updated config root is invalid, keeping last valid config")
			return true
		push_error("HpRankModeManager: root object is invalid")
		return false

	var parsed_banned_characters : Dictionary = {}
	for char_id in root.get("banned_character", []):
		parsed_banned_characters[str(char_id)] = true

	var parsed_tier_by_character : Dictionary = {}
	var parsed_specify_hp_start_adjust_enabled : Dictionary = {}
	for tier_entry in root.get("tier", []):
		if not (tier_entry is Dictionary):
			continue
		var character = str(tier_entry.get("character", "")).strip_edges()
		var tier = str(tier_entry.get("tier", "")).strip_edges()
		if character.is_empty() or tier.is_empty():
			continue
		parsed_tier_by_character[character] = tier
		if bool(tier_entry.get("specify_hp_start_adjust", false)):
			parsed_specify_hp_start_adjust_enabled[character] = true

	var parsed_common_rule_hp : Dictionary = {}
	for rule_entry in root.get("common_rule", []):
		if not (rule_entry is Dictionary):
			continue
		var rule_key = str(rule_entry.get("rule", "")).strip_edges()
		if rule_key.is_empty():
			continue
		var parsed_hp = _parse_hp_pair(str(rule_entry.get("hp_start", "")))
		if parsed_hp.size() == 2:
			parsed_common_rule_hp[rule_key] = parsed_hp

	var parsed_common_hp_adjust : Dictionary = {}
	for adjust_entry in root.get("common_hp_adjust", []):
		if not (adjust_entry is Dictionary):
			continue
		var character = str(adjust_entry.get("character", "")).strip_edges()
		if character.is_empty():
			continue
		parsed_common_hp_adjust[character] = _parse_signed_int(str(adjust_entry.get("hp", "0")))

	var parsed_specify_hp_start_adjust = root.get("specify_hp_start_adjust", {})
	if not (parsed_specify_hp_start_adjust is Dictionary):
		parsed_specify_hp_start_adjust = {}

	_banned_characters = parsed_banned_characters
	_tier_by_character = parsed_tier_by_character
	_specify_hp_start_adjust_enabled = parsed_specify_hp_start_adjust_enabled
	_common_rule_hp = parsed_common_rule_hp
	_common_hp_adjust = parsed_common_hp_adjust
	_specify_hp_start_adjust = parsed_specify_hp_start_adjust
	_loaded_config_signature = current_signature

	_loaded = true
	return true

func _resolve_mode_character_id(deck_id : String) -> String:
	var normalized = _normalize_deck_id(deck_id)
	if _tier_by_character.has(normalized) or _banned_characters.has(normalized):
		return normalized

	var base_id = _get_base_character_id(normalized)
	if _tier_by_character.has(base_id) or _banned_characters.has(base_id):
		return base_id
	return normalized

func _normalize_deck_id(deck_id : String) -> String:
	var normalized = str(deck_id).strip_edges()
	if normalized.begins_with("random") and normalized.find("#") != -1:
		normalized = normalized.split("#", false, 1)[1]
	return normalized

func _get_base_character_id(deck_id : String) -> String:
	var char_skin_manager = _get_char_skin_manager()
	if char_skin_manager and char_skin_manager.has_method("get_base_character_id"):
		return str(char_skin_manager.call("get_base_character_id", deck_id))

	# Fallback for tests where the autoload may be unavailable.
	var skin_match = RegEx.new()
	skin_match.compile("^(.+)_([1-9]\\d*)$")
	var result = skin_match.search(deck_id)
	if result:
		return result.get_string(1)
	return deck_id

func _get_char_skin_manager() -> Node:
	var main_loop = Engine.get_main_loop()
	if main_loop == null or not (main_loop is SceneTree):
		return null
	var root = (main_loop as SceneTree).root
	if root == null:
		return null
	return root.get_node_or_null("CharSkinManager")

func _is_banned(character_id : String) -> bool:
	return _banned_characters.has(character_id)

func _get_common_rule_hp(player_tier : String, opponent_tier : String) -> Array:
	var key = "%s vs %s" % [player_tier, opponent_tier]
	if _common_rule_hp.has(key):
		return _common_rule_hp[key]

	var reverse_key = "%s vs %s" % [opponent_tier, player_tier]
	if _common_rule_hp.has(reverse_key):
		var reverse_values = _common_rule_hp[reverse_key]
		if reverse_values.size() == 2:
			return [int(reverse_values[1]), int(reverse_values[0])]
	return []

func _apply_specify_start_hp(character_id : String, opponent_tier : String, fallback_hp : int) -> int:
	if not _specify_hp_start_adjust_enabled.has(character_id):
		return fallback_hp

	var base_character = _get_base_character_id(character_id)
	var specify_data = _specify_hp_start_adjust.get(base_character, null)
	if not (specify_data is Dictionary):
		return fallback_hp

	var default_key = "%s_default" % base_character
	var default_table = specify_data.get(default_key, [])
	if not (default_table is Array):
		return fallback_hp

	for entry in default_table:
		if not (entry is Dictionary):
			continue
		if str(entry.get("tier", "")).strip_edges() != opponent_tier:
			continue
		return max(_parse_signed_int(str(entry.get("hp_start", fallback_hp))), 1)

	return fallback_hp

func _apply_common_hp_adjust(character_id : String, base_hp : int) -> int:
	# common_hp_adjust must always apply after base/specify hp is resolved.
	return base_hp + int(_common_hp_adjust.get(character_id, 0))

func _uses_default_life_cap(character_id : String) -> bool:
	var base_character = _get_base_character_id(character_id)
	return base_character == "taisei" or base_character == "tinker"

func _parse_hp_pair(value : String) -> Array:
	var parts = value.split("-")
	if parts.size() != 2:
		return []
	return [_parse_signed_int(parts[0]), _parse_signed_int(parts[1])]

func _parse_signed_int(value) -> int:
	var normalized = str(value).strip_edges()
	if normalized.is_empty():
		return 0
	return int(normalized)
