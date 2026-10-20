extends GutTest

## data/decks 与 data/decks_skin 下的卡组文件完整性。
##
## 回归背景：CardDataManager._load_decks_from_path 用 DirAccess 枚举目录并逐个解析，
## 原本不过滤扩展名。放在同目录的备份文件（如 carcass.json.bak_20260929）会被当成卡组加载，
## 且因为按文件名字典序排在 .json 之后，会用旧内容**覆盖同名的正式卡组定义**。
## 症状：改完卡定义后行为不变、日志里出现「Unhandled effect type」。
## 备份请放到项目根的 _backups/，不要留在 data/decks(_skin) 下。

const DECK_DIRS := ["res://data/decks", "res://data/decks_skin"]


func test_deck_dirs_contain_only_json_files():
	for dir_path in DECK_DIRS:
		var offenders := []
		for f in DirAccess.get_files_at(dir_path):
			if not f.ends_with(".json"):
				offenders.append(f)
		assert_eq(offenders.size(), 0,
			"%s 下存在非 .json 文件，会被加载器误当成卡组并覆盖正式定义：%s（备份请放到项目根的 _backups/）"
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
