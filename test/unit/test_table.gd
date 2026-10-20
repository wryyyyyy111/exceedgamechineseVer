extends GutTest

const TableScene = preload("res://scenes/menu/table.tscn")

func test_missing_row_icon_is_hidden_without_loading_error():
	var table : Table = TableScene.instantiate()
	add_child_autofree(table)
	await get_tree().process_frame

	table.set_rows(
		[["Player", "Opponent", "Version", "0", "Join", "Observe"]],
		[["res://assets/portraits/does_not_exist.png"]],
	)

	var icon : TextureRect = table.rows.get_child(0).get_child(0).find_child("Icon")
	assert_false(icon.visible)
	assert_null(icon.texture)