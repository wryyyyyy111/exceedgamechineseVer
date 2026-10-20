extends GutTest

const MatchQueueItemScene = preload("res://scenes/menu/match_queue_item.tscn")


func test_waiting_character_display_prefers_waiting_character():
	var display = MatchQueueItem.get_waiting_character_display({
		"waiting_character": "隆德雷奇亚",
		"waiting_deck": "Ryu",
		"waiting_deck_id": "ryu",
	})

	assert_eq(display, "隆德雷奇亚")


func test_waiting_character_display_falls_back_to_waiting_deck():
	var display = MatchQueueItem.get_waiting_character_display({
		"waiting_character": "",
		"waiting_deck": "ryu",
		"waiting_deck_id": "kykisuke",
	})

	assert_eq(display, "隆")


func test_waiting_character_display_falls_back_to_waiting_deck_id():
	var display = MatchQueueItem.get_waiting_character_display({
		"waiting_deck_id": "random_s3#ryu",
	})

	assert_eq(display, "隆")


func test_waiting_character_display_handles_unresolved_random_without_fake_character():
	var display = MatchQueueItem.get_waiting_character_display({
		"waiting_deck_id": "random_s3",
	})

	assert_eq(display, "Random")


func test_waiting_character_display_handles_missing_fields():
	var display = MatchQueueItem.get_waiting_character_display({
		"match_available": false,
	})

	assert_eq(display, "")


func test_waiting_character_display_translates_english_keyword_to_chinese():
	var display = MatchQueueItem.get_waiting_character_display({
		"waiting_deck": "Goldlewis Dickinson",
	})

	assert_eq(display, "戈德刘易斯")


func test_waiting_character_display_uses_longest_english_keyword_match():
	var display = MatchQueueItem.get_waiting_character_display({
		"waiting_deck": "Shovel & Shield Knight",
	})

	assert_eq(display, "铲子骑士&圆盾骑士")


func test_waiting_character_display_does_not_match_happy_chaos_as_chaos():
	var display = MatchQueueItem.get_waiting_character_display({
		"waiting_deck": "Happy Chaos",
	})

	assert_eq(display, "哈皮")


func test_waiting_character_display_resolves_happychaos_deck_id():
	var display = MatchQueueItem.get_waiting_character_display({
		"waiting_deck_id": "happychaos",
	})

	assert_eq(display, "哈皮")


func test_initialize_queue_keeps_waiting_label_in_chinese():
	var queue_item = MatchQueueItemScene.instantiate()
	add_child_autofree(queue_item)

	queue_item.initialize_queue("s3to7", "Season 3-7 Only", true, "春丽")

	assert_eq(queue_item.waiting_character_label.text, "等待匹配: 春丽")