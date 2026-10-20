extends GutTest

const WebExportPresetPath := "res://export_presets.cfg"

func test_web_export_keeps_ios_replay_download_bridge():
	var preset_text := FileAccess.get_file_as_string(WebExportPresetPath)

	assert_true(preset_text.contains("function downloadGameReplay(replayText, filename)"))
	assert_true(preset_text.contains("navigator.canShare({ files: [file] })"))
	assert_true(preset_text.contains("if (isIOS && navigator.share && canShareFile)"))
	assert_true(preset_text.contains("anchor.click()"))
	assert_true(preset_text.contains("setTimeout(() => urlApi.revokeObjectURL(url), 60000)"))