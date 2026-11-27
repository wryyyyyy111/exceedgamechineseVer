class_name StreamingFrameAnimation
extends AnimatedSprite2D

const INITIAL_PRELOAD_FRAME_COUNT := 6
const PREFETCH_AHEAD_FRAME_COUNT := 4

var _animation_name: StringName
var _frame_path_pattern := ""
var _frame_count := 0
var _fps := 10.0
var _frame_duration := 0.1
var _elapsed := 0.0
var _stream_playing := false
var _requested_frames := {}
var _failed_frames := {}
var _load_generation := 0

func prepare(
		animation_name: StringName,
		frame_path_pattern: String,
		frame_count: int,
		fps: float) -> bool:
	if frame_path_pattern.is_empty() or frame_count <= 0 or fps <= 0.0:
		push_error("[StreamingFrameAnimation] Invalid animation configuration.")
		return false
	add_to_group(&"streaming_frame_animations")
	_animation_name = animation_name
	_frame_path_pattern = frame_path_pattern
	_frame_count = frame_count
	_fps = fps
	_frame_duration = 1.0 / fps
	_elapsed = 0.0
	_stream_playing = false
	_load_generation += 1
	var load_generation := _load_generation
	_requested_frames.clear()
	_failed_frames.clear()

	sprite_frames = SpriteFrames.new()
	if sprite_frames.has_animation(&"default") and animation_name != &"default":
		sprite_frames.remove_animation(&"default")
	if not sprite_frames.has_animation(animation_name):
		sprite_frames.add_animation(animation_name)
	sprite_frames.set_animation_loop(animation_name, false)
	sprite_frames.set_animation_speed(animation_name, fps)
	for _index in range(frame_count):
		sprite_frames.add_frame(animation_name, null)

	var preload_count := mini(frame_count, INITIAL_PRELOAD_FRAME_COUNT)
	for index in range(preload_count):
		_request_frame(index)
	while load_generation == _load_generation and not _are_frames_resolved(0, preload_count):
		_collect_ready_frames()
		await get_tree().process_frame
	if load_generation != _load_generation:
		return false
	_collect_ready_frames()
	if _failed_frames.has(0) or sprite_frames.get_frame_texture(animation_name, 0) == null:
		push_error("[StreamingFrameAnimation] Failed to load first frame: %s" % _get_frame_path(0))
		release_stream()
		return false
	frame = 0
	set_process(false)
	return true

func start():
	if sprite_frames == null or _frame_count <= 0:
		return
	_elapsed = 0.0
	_stream_playing = true
	frame = 0
	speed_scale = 0.0
	play(_animation_name)
	set_process(true)

func get_frame_size() -> Vector2:
	if sprite_frames == null or _frame_count <= 0:
		return Vector2.ZERO
	var first_texture := sprite_frames.get_frame_texture(_animation_name, 0)
	return first_texture.get_size() if first_texture != null else Vector2.ZERO

func get_loaded_frame_count() -> int:
	if sprite_frames == null:
		return 0
	var loaded_count := 0
	for index in range(_frame_count):
		if sprite_frames.get_frame_texture(_animation_name, index) != null:
			loaded_count += 1
	return loaded_count

func is_preparing() -> bool:
	return _frame_count > 0 and not _stream_playing

func release_stream():
	_load_generation += 1
	_stream_playing = false
	set_process(false)
	stop()
	if sprite_frames != null and sprite_frames.has_animation(_animation_name):
		for index in range(sprite_frames.get_frame_count(_animation_name)):
			sprite_frames.set_frame(_animation_name, index, null)
	_requested_frames.clear()
	_failed_frames.clear()
	_frame_path_pattern = ""
	_frame_count = 0

func _exit_tree():
	release_stream()

func _process(delta: float):
	_collect_ready_frames()
	if not _stream_playing:
		return
	_request_window(frame)
	if _failed_frames.has(frame + 1):
		push_error("[StreamingFrameAnimation] Failed to load frame: %s" % _get_frame_path(frame + 1))
		_finish_stream()
		return

	_elapsed += delta
	while _elapsed >= _frame_duration:
		var next_frame := frame + 1
		if next_frame >= _frame_count:
			_finish_stream()
			return
		if sprite_frames.get_frame_texture(_animation_name, next_frame) == null:
			_elapsed = minf(_elapsed, _frame_duration)
			return
		frame = next_frame
		_elapsed -= _frame_duration
		_prune_loaded_frames()
		_request_window(frame)

func _finish_stream():
	_stream_playing = false
	set_process(false)
	stop()
	release_stream()
	animation_finished.emit()

func _request_window(current_frame: int):
	var last_index := mini(_frame_count - 1, current_frame + PREFETCH_AHEAD_FRAME_COUNT)
	for index in range(current_frame, last_index + 1):
		_request_frame(index)

func _request_frame(index: int):
	if index < 0 or index >= _frame_count:
		return
	if _requested_frames.has(index) or _failed_frames.has(index):
		return
	if sprite_frames.get_frame_texture(_animation_name, index) != null:
		return
	var path := _get_frame_path(index)
	var error := ResourceLoader.load_threaded_request(
		path,
		"Texture2D",
		true,
		ResourceLoader.CACHE_MODE_IGNORE)
	if error != OK and error != ERR_BUSY:
		_failed_frames[index] = error
		push_error("[StreamingFrameAnimation] Unable to request frame (%d): %s" % [error, path])
		return
	_requested_frames[index] = true

func _collect_ready_frames():
	if sprite_frames == null:
		return
	for index in _requested_frames.keys():
		var path := _get_frame_path(index)
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var texture := ResourceLoader.load_threaded_get(path) as Texture2D
			_requested_frames.erase(index)
			if texture == null:
				_failed_frames[index] = ERR_CANT_ACQUIRE_RESOURCE
			else:
				sprite_frames.set_frame(_animation_name, index, texture)
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_requested_frames.erase(index)
			_failed_frames[index] = ERR_CANT_ACQUIRE_RESOURCE

func _are_frames_resolved(first_index: int, end_index: int) -> bool:
	for index in range(first_index, end_index):
		if _requested_frames.has(index):
			return false
	return true

func _prune_loaded_frames():
	if sprite_frames == null:
		return
	var last_kept_index := mini(_frame_count - 1, frame + PREFETCH_AHEAD_FRAME_COUNT)
	for index in range(_frame_count):
		if index < frame or index > last_kept_index:
			sprite_frames.set_frame(_animation_name, index, null)

func _get_frame_path(index: int) -> String:
	return _frame_path_pattern % index
