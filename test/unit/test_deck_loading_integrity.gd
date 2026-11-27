extends GutTest

## data/decks 与 data/decks_skin 下的卡组文件完整性。
##
## 回归背景：CardDataManager._load_decks_from_path 用 DirAccess 枚举目录并逐个解析，
## 原本不过滤扩展名。放在同目录的备份文件（如 carcass.json.bak_20260929）会被当成卡组加载，
## 且因为按文件名字典序排在 .json 之后，会用旧内容**覆盖同名的正式卡组定义**。
## 症状：改完卡定义后行为不变、日志里出现「Unhandled effect type」。
## 备份请放到项目根的 _backups/，不要留在 data/decks(_skin) 下。

const DECK_DIRS := ["res://data/decks", "res://data/decks_skin"]

func _find_blank_effect_order_options(value: Variant, source: String, failures: Array[String]):
	if value is Array:
		for item in value:
			_find_blank_effect_order_options(item, source, failures)
	elif value is Dictionary:
		if value.has("id"):
			source += ":" + str(value["id"])
		var timing: String = value.get("timing", "").trim_prefix("both_players_").trim_prefix("opponent_")
		if value.has("effect_type") and timing in ["on_strike_reveal", "before", "hit", "after", "cleanup", "endofstrike"]:
			if not LocalGame.is_automatic_simultaneous_effect(value) \
					and GameStrings.get_effect_text(value, false, true).strip_edges().is_empty():
				failures.append("%s: %s" % [source, JSON.stringify(value)])
		for key in value:
			_find_blank_effect_order_options(value[key], source, failures)

func test_all_card_and_character_effect_order_options_have_text_or_resolve_automatically():
	var failures: Array[String] = []
	_find_blank_effect_order_options(CardDataManager.card_data, "cards", failures)
	_find_blank_effect_order_options(CardDataManager.decks, "decks", failures)
	for file in DirAccess.get_files_at("res://data/decks_EnVersion"):
		if file.ends_with(".json"):
			var path = "res://data/decks_EnVersion".path_join(file)
			var data = CardDataManager.load_json_file(path)
			assert_not_null(data, path)
			_find_blank_effect_order_options(data, path, failures)
	assert_eq(failures, [], "Blank simultaneous-effect options must not reach the client")


func test_deck_dirs_contain_only_json_and_card_name_index_files():
	for dir_path in DECK_DIRS:
		var offenders := []
		for f in DirAccess.get_files_at(dir_path):
			if dir_path == "res://data/decks" and f in ["_card_name_index.gd", "_card_name_index.gd.uid"]:
				continue
			if not f.ends_with(".json"):
				offenders.append(f)
		assert_eq(offenders.size(), 0,
			"%s 下存在未授权的非 .json 文件：%s（备份请放到项目根的 _backups/）"
			% [dir_path, str(offenders)])


func test_every_deck_file_parses():
	for dir_path in DECK_DIRS:
		for f in DirAccess.get_files_at(dir_path):
			if not f.ends_with(".json"):
				continue
			var full_path = dir_path + "/" + f
			var parsed = CardDataManager.load_json_file(full_path)
			assert_true(parsed != null, "卡组文件无法被解析：%s" % full_path)
			if parsed is Dictionary:
				assert_true(parsed.has("id"), "卡组文件缺少 id 字段：%s" % full_path)


func test_loaded_decks_match_json_files():
	# 反向确认：每个已加载的卡组都能对应到 data/decks(_skin) 下的某个 .json 文件，
	# 避免「从非 .json 文件加载进来的卡组」再次出现。
	var json_names := {}
	for dir_path in DECK_DIRS:
		for f in DirAccess.get_files_at(dir_path):
			if f.ends_with(".json"):
				json_names[f.get_basename()] = true
	for deck_key in CardDataManager.decks.keys():
		var deck_data = CardDataManager.decks[deck_key]
		var base_id = str(deck_data.get("base_id", deck_key))
		assert_true(json_names.has(deck_key) or json_names.has(base_id),
			"卡组 %s 在 data/decks(_skin) 下找不到对应的 .json 文件" % deck_key)
