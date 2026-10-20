extends GutTest

const EmoteDialogScene = preload("res://scenes/game/emote_dialog.tscn")

func test_text_emote_options_include_recent_additions():
	# 文本表情按钮与 emote_text_strings 一一对应，且包含后加的两条
	var dlg = EmoteDialogScene.instantiate()
	add_child_autofree(dlg)
	await wait_frames(2)

	var texts := []
	for btn in dlg.text_buttons.get_children():
		texts.append(btn.text)

	assert_eq(texts.size(), EmoteDialog.emote_text_strings.size(),
		"文本表情按钮数应与 emote_text_strings 一致")
	assert_true(texts.has("这把怎么赢？"), "应包含「这把怎么赢？」")
	assert_true(texts.has("点错了"), "应包含「点错了」")
	assert_true(texts.has("这把怎么输？"), "既有的「这把怎么输？」不应被移除")

func test_pressing_new_text_emote_emits_selection():
	var dlg = EmoteDialogScene.instantiate()
	add_child_autofree(dlg)
	await wait_frames(2)
	watch_signals(dlg)

	for btn in dlg.text_buttons.get_children():
		if btn.text == "点错了":
			btn.pressed.emit()
			break
	assert_signal_emitted_with_parameters(dlg, "emote_selected", [false, "点错了"])
