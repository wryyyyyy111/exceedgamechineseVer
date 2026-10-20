extends ExceedGutTest


func who_am_i():
	var deck = CardDataManager.get_deck_from_str_id("solbadguy").duplicate(true)
	deck["stored_bleach_info"] = {
		"name": "测试专属区",
		"facedown": false
	}
	return deck


func test_bleach_zone_uses_character_configuration():
	assert_true(player1.has_bleach_zone())
	assert_eq(player1.get_bleach_zone_name(), "测试专属区")
	assert_false(player1.is_bleach_zone_facedown())
	assert_eq(player1.bleach_zone.size(), 0)


func test_add_to_bleach_moves_card_to_independent_zone_and_emits_event():
	var card = player1.deck.pop_front()
	player1.add_to_bleach(card)

	assert_true(player1.is_card_in_bleach(card.id))
	assert_false(player1.is_card_in_gauge(card.id))
	assert_eq(player1.bleach_zone.size(), 1)
	validate_has_event(game_logic.get_latest_events(), Enums.EventType.EventType_AddToBleach, player1, card.id)


func test_move_from_gauge_to_bleach_removes_gauge_resource():
	var card_ids = give_gauge(player1, 1)
	player1.move_card_from_gauge_to_bleach(card_ids[0])

	assert_false(player1.is_card_in_gauge(card_ids[0]))
	assert_true(player1.is_card_in_bleach(card_ids[0]))
