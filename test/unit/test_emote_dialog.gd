extends GutTest

const EmoteDialogScene = preload("res://scenes/game/emote_dialog.tscn")

func test_text_emote_options_include_recent_additions():
	# 当前产品列表为权威；必须逐项验证真实按钮而非旧版文案。
	var dlg = EmoteDialogScene.instantiate()
	add_child_autofree(dlg)
	await wait_frames(2)

	var texts := []
	for btn in dlg.text_buttons.get_children():
		texts.append(btn.text)

	assert_eq(texts.size(), EmoteDialog.emote_text_strings.size(),
		"文本表情按钮数应与 emote_text_strings 一致")
	for index in range(EmoteDialog.emote_text_strings.size()):
		assert_eq(texts[index], EmoteDialog.emote_text_strings[index])
	assert_true(texts.has("点错了;-;"))
	assert_false(texts.has("这把怎么赢？"))
	assert_false(texts.has("这把怎么输？"))
	assert_false(texts.has("点错了"))

func test_pressing_new_text_emote_emits_selection():
	var dlg = EmoteDialogScene.instantiate()
	add_child_autofree(dlg)
	await wait_frames(2)
	watch_signals(dlg)

	for index in range(dlg.text_buttons.get_child_count()):
		var btn = dlg.text_buttons.get_child(index)
		assert_eq(get_signal_emit_count(dlg, "emote_selected"), index)
		btn.pressed.emit()
		assert_signal_emit_count(dlg, "emote_selected", index + 1)
		assert_eq(get_signal_parameters(dlg, "emote_selected", index),
				[false, EmoteDialog.emote_text_strings[index]])
