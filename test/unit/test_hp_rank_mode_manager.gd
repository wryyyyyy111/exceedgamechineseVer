extends GutTest

const HpRankModeManagerScript = preload("res://globals/hp_rank_mode_manager.gd")


func test_build_match_starting_hp_uses_configured_pair_and_life_caps():
	var manager = HpRankModeManagerScript.new()
	var result = manager.build_match_starting_hp("hp_rank_mode", "pooky", "axl")

	assert_true(result.get("enabled", false))
	assert_true(result.get("valid", false))
	assert_eq(int(result.get("player1_starting_life", -1)), 31)
	assert_eq(int(result.get("player2_starting_life", -1)), 25)
	assert_eq(int(result.get("player1_life_cap", -1)), 31)
	assert_eq(int(result.get("player2_life_cap", -1)), 25)


func test_build_match_starting_hp_uses_specified_starting_hp_for_taisei():
	var manager = HpRankModeManagerScript.new()
	var result = manager.build_match_starting_hp("hp_rank_mode", "taisei", "ryu")

	assert_true(result.get("valid", false))
	assert_eq(int(result.get("player1_starting_life", -1)), 14)
	assert_eq(int(result.get("player1_life_cap", -1)), 30)
	assert_eq(int(result.get("player2_starting_life", -1)), 30)


func test_build_match_starting_hp_marks_banned_character_invalid():
	var manager = HpRankModeManagerScript.new()
	var result = manager.build_match_starting_hp("hp_rank_mode", "mika_1", "ryu")

	assert_true(result.get("enabled", false))
	assert_false(result.get("valid", true))
	assert_eq(result.get("error", ""), "banned_character")


func test_apply_starting_hp_to_deck_sets_starting_life_and_life_cap():
	var manager = HpRankModeManagerScript.new()
	var deck = {"id": "ryu", "display_name": "Ryu", "cards": []}
	var patched = manager.apply_starting_hp_to_deck(deck, 27, 27)

	assert_eq(int(patched.get("starting_life", -1)), 27)
	assert_eq(int(patched.get("life_cap", -1)), 27)
	assert_true(bool(patched.get("hp_rank_mode_enabled", false)))


func test_get_taisei_exceed_life_uses_taisei_exceed_table():
	var manager = HpRankModeManagerScript.new()

	assert_eq(manager.get_taisei_exceed_life("taisei", "A"), 9)
	assert_eq(manager.get_taisei_exceed_life("taisei", "B"), 10)
	assert_eq(manager.get_taisei_exceed_life("taisei", "EX"), 11)


func test_current_tier_rules_apply_without_axl_hp_adjust():
	var manager = HpRankModeManagerScript.new()

	var vs_a_tier = manager.build_match_starting_hp("hp_rank_mode", "axl", "mika")
	assert_true(vs_a_tier.get("valid", false))
	assert_eq(int(vs_a_tier.get("player1_starting_life", -1)), 25)

	var vs_ex_minus_tier = manager.build_match_starting_hp("hp_rank_mode", "axl", "minato")
	assert_true(vs_ex_minus_tier.get("valid", false))
	assert_eq(int(vs_ex_minus_tier.get("player1_starting_life", -1)), 30)
	assert_eq(int(vs_ex_minus_tier.get("player2_starting_life", -1)), 26)


func test_reloads_when_config_json_changes():
	var manager = HpRankModeManagerScript.new()
	var temp_path = "user://hp_rank_mode_manager_reload_test.json"
	manager.set_config_path_for_testing(temp_path)

	var config_v1 = {
		"banned_character": [],
		"tier": [
			{"character": "pooky", "tier": "A"},
			{"character": "axl", "tier": "A"}
		],
		"common_rule": [
			{"rule": "A vs A", "hp_start": "30 - 30"}
		],
		"common_hp_adjust": [
			{"character": "pooky", "hp": "+1"}
		],
		"specify_hp_start_adjust": {}
	}
	_write_json_file(temp_path, config_v1)
	var result_v1 = manager.build_match_starting_hp("hp_rank_mode", "pooky", "axl")
	assert_true(result_v1.get("valid", false))
	assert_eq(int(result_v1.get("player1_starting_life", -1)), 31)

	var config_v2 = {
		"banned_character": [],
		"tier": [
			{"character": "pooky", "tier": "A"},
			{"character": "axl", "tier": "A"}
		],
		"common_rule": [
			{"rule": "A vs A", "hp_start": "30 - 30"}
		],
		"common_hp_adjust": [
			{"character": "pooky", "hp": "+3"}
		],
		"specify_hp_start_adjust": {}
	}
	_write_json_file(temp_path, config_v2)
	var result_v2 = manager.build_match_starting_hp("hp_rank_mode", "pooky", "axl")
	assert_true(result_v2.get("valid", false))
	assert_eq(int(result_v2.get("player1_starting_life", -1)), 33)

	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(temp_path)


func _write_json_file(path : String, content : Dictionary) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	file.store_string(JSON.stringify(content))
	file.close()
