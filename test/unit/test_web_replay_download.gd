extends GutTest

const WebExportPresetPath := "res://export_presets.cfg"

func test_web_export_keeps_ios_replay_download_bridge():
	var preset_text := FileAccess.get_file_as_string(WebExportPresetPath)

	assert_true(preset_text.contains("function downloadGameReplay(replayText, filename)"))
	assert_true(preset_text.contains("navigator.canShare({ files: [file] })"))
	assert_true(preset_text.contains("if (isIOS && navigator.share && canShareFile)"))
	assert_true(preset_text.contains("anchor.click()"))
	assert_true(preset_text.contains("setTimeout(() => urlApi.revokeObjectURL(url), 60000)"))

func _create_upload_status_ui() -> Game:
	var game_ui : Game = load("res://scenes/game/game.tscn").instantiate()
	autofree(game_ui)
	autofree(game_ui.game_wrapper)
	return game_ui

func test_upload_failure_dialog_keeps_reason_and_distinguishes_local_replay():
	var game_ui := _create_upload_status_ui()
	var text := game_ui._get_replay_upload_status_text(false, false,
		"[SERVER_UPLOAD_FAILED]\nerror: AccessDenied\nrequest_id: test-request")
	assert_string_contains(text, "不影响已保存的本地回放")
	assert_string_contains(text, "AccessDenied")
	assert_string_contains(text, "request_id: test-request")

func test_upload_failure_dialog_without_reason_is_explicit():
	var game_ui := _create_upload_status_ui()
	var text := game_ui._get_replay_upload_status_text(false, false, "")
	assert_string_contains(text, "[UPLOAD_REASON_MISSING]")

func test_upload_success_dialog_does_not_claim_local_download_completed():
	var game_ui := _create_upload_status_ui()
	var text := game_ui._get_replay_upload_status_text(true, true, "")
	assert_string_contains(text, "回放已上传OSS")
	assert_string_contains(text, "请以下载或保存结果为准")
	assert_string_contains(game_ui._get_replay_upload_status_text(true, false, ""), "该局结算后上传")