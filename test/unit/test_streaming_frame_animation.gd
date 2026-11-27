extends ExceedGutTest

const StreamingFrameAnimationScript = preload("res://scenes/game/streaming_frame_animation.gd")
const FRAME_PATTERN := "res://assets/entrance_animations/eugenia/frame_%02d.png"

func who_am_i():
	return "renea"

func test_prepare_holds_only_initial_streaming_window():
	var animation := StreamingFrameAnimationScript.new() as StreamingFrameAnimation
	add_child(animation)
	var prepared := await animation.prepare(&"test", FRAME_PATTERN, 14, 12.0)
	assert_true(prepared)
	assert_eq(animation.sprite_frames.get_frame_count(&"test"), 14)
	assert_eq(animation.get_loaded_frame_count(), 6)
	assert_ne(animation.get_frame_size(), Vector2.ZERO)
	animation.queue_free()
	await get_tree().process_frame

func test_release_stream_drops_all_texture_references_and_is_idempotent():
	var animation := StreamingFrameAnimationScript.new() as StreamingFrameAnimation
	add_child(animation)
	var prepared := await animation.prepare(&"test", FRAME_PATTERN, 14, 12.0)
	assert_true(prepared)
	animation.release_stream()
	animation.release_stream()
	assert_eq(animation.get_loaded_frame_count(), 0)
	assert_false(animation.is_playing())
	animation.queue_free()
	await get_tree().process_frame

func test_cleanup_during_prepare_cancels_playback():
	var animation := StreamingFrameAnimationScript.new() as StreamingFrameAnimation
	add_child(animation)
	animation.prepare(&"test", FRAME_PATTERN, 14, 12.0)
	animation.release_stream()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(animation.get_loaded_frame_count(), 0)
	assert_false(animation.is_playing())
	animation.queue_free()
	await get_tree().process_frame
