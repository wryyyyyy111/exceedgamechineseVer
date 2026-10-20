class_name Character
extends Node2D

enum AnimationState {
	AnimationState_Idle,
	AnimationState_Moving,
}

const RuntimeImageResizerScript = preload("res://globals/runtime_image_resizer.gd")

@onready var animation : AnimatedSprite2D = $Animation
@onready var exceed_icon = $ExceedIcon
@onready var base_scale = scale
@onready var base_exceed_icon_scale = exceed_icon.scale * maxf(0.01, GlobalSettings.exceed_char_bg_size)

var animation_state = AnimationState.AnimationState_Idle
var current_position
var target_position

var is_wide : bool = false
var vertical_offset : float = 0
var horizontal_offset : float = 0
var horizontal_offset_buddy : float = 0
var use_buddy_extra_offset : bool = false
var runtime_texture_scale_compensation := 1.0
var mobile_texture_scale_for_display := MOBILE_WEB_CHARACTER_TEXTURE_SCALE
var mobile_display_scale_initialized := false
var debug_mobile_scale_trace_enabled := false
var debug_mobile_scale_trace_label := ""

var remaining_animation_time : float = -1
const MoveTime : float = 1.0
const HitTime : float = 1.0
const MOBILE_WEB_CHARACTER_TEXTURE_SCALE := 0.5
const DEBUG_MOBILE_SCALE_TRACE_CHARACTER_ID := ""
const CHARACTER_ANIMATION_ROOT := "res://assets/character_animations/"
const PHONE_CHARACTER_ANIMATION_ROOT := "res://assets/phone/character_animations/"
const PHONE_CHARACTER_ANIMATION_SCALE_REPORT := "res://assets/phone/character_animations/zoom_scale_ref.txt"
const CHARACTER_ANIMATION_SKIN_ROOT := "res://assets/character_animations_skin/"
const PHONE_CHARACTER_ANIMATION_SKIN_ROOT := "res://assets/phone/character_animations_skin/"
const PHONE_CHARACTER_ANIMATION_SKIN_SCALE_REPORT := "res://assets/phone/character_animations_skin/zoom_scale_ref.txt"
const CHARACTER_ANIMATION_CUSTOM_ROOT := "res://assets/character_animations_custom/"
const PHONE_CHARACTER_ANIMATION_CUSTOM_ROOT := "res://assets/phone/character_animations_custom/"
const PHONE_CHARACTER_ANIMATION_CUSTOM_SCALE_REPORT := "res://assets/phone/character_animations_custom/zoom_scale_ref.txt"
const CHARACTER_PORTRAIT_ROOT := "res://assets/portraits/"
const PHONE_CHARACTER_PORTRAIT_ROOT := "res://assets/phone/portraits/"
const CHARACTER_PORTRAIT_SKIN_ROOT := "res://assets/portraits_skin/"
const PHONE_CHARACTER_PORTRAIT_SKIN_ROOT := "res://assets/phone/portraits_skin/"
const CHARACTER_PORTRAIT_CUSTOM_ROOT := "res://assets/portraits_custom/"
const PHONE_CHARACTER_PORTRAIT_CUSTOM_ROOT := "res://assets/phone/portraits_custom/"

static var phone_animation_scale_by_path : Dictionary = {}
static var phone_animation_source_size_by_path : Dictionary = {}
static var phone_animation_output_size_by_path : Dictionary = {}
static var phone_animation_scale_report_loaded_by_path : Dictionary = {}

const RELATIVE_SCALE_EXCEED_ANIMATIONS := {
	"carlswangee_exceed": true,
	"emogine_exceed": true,
	"sydney_exceed": true,
}
const RELATIVE_SCALE_WIDE_ANIMATIONS := {
	"tinker_tank": true,
}

enum CharacterAnim {
	CharacterAnim_None,
	CharacterAnim_DashBack,
	CharacterAnim_Hit,
	CharacterAnim_Pulled,
	CharacterAnim_Pushed,
	CharacterAnim_Run,
	CharacterAnim_Stunned,
	CharacterAnim_WalkForward,
	CharacterAnim_WalkBackward,
}

var animation_map = {
	CharacterAnim.CharacterAnim_None: func():
		play_animation("idle"),
	CharacterAnim.CharacterAnim_DashBack: func():
		play_animation("dash_back"),
	CharacterAnim.CharacterAnim_Hit: func():
		play_animation("hit"),
	CharacterAnim.CharacterAnim_Pulled: func():
		play_animation("pulled"),
	CharacterAnim.CharacterAnim_Pushed: func():
		play_animation("pushed"),
	CharacterAnim.CharacterAnim_Run: func():
		play_animation("run"),
	CharacterAnim.CharacterAnim_Stunned: func():
		play_animation("stunned"),
	CharacterAnim.CharacterAnim_WalkForward: func():
		play_animation("walk_forward"),
	CharacterAnim.CharacterAnim_WalkBackward: func():
		play_animation("walk_backward"),
}

var buddy_id : String = ""

# Called when the node enters the scene tree for the first time.
func _ready():
	exceed_icon.visible = false

func load_character(
		image_loader: CardImageLoader,
		character_data: Dictionary,
		char_id: String,
		yield_between_textures := true):
	# Original logic kept for reference:
	# var check_ids = [char_id]
	# if char_id.begins_with("custom_"):
	# 	check_ids.append(char_id.substr(7))
	# for check_id in check_ids:
	# 	if 'custom_animations' in character_data and check_id in character_data['custom_animations']:
	# 		return await load_character_custom_anims(image_loader, character_data['custom_animations'][check_id])
	#
	# var path = "res://assets/character_animations/" + char_id + "/animations.tres"
	# animation.sprite_frames = load(path)
	# if not animation.sprite_frames:
	# 	path = "res://assets/character_animations/custom/animations.tres"
	# 	animation.sprite_frames = load(path)
	MobileResourceBudget.unregister_owner(_get_budget_owner())
	var previous_mobile_texture_scale := mobile_texture_scale_for_display if mobile_display_scale_initialized else 1.0
	if not mobile_display_scale_initialized:
		mobile_texture_scale_for_display = MOBILE_WEB_CHARACTER_TEXTURE_SCALE

	var skin_manager = get_node("/root/CharSkinManager")
	var path = skin_manager.get_animation_path_for_deck_and_animation_id(str(character_data.get("id", "")), char_id)
	debug_mobile_scale_trace_enabled = _should_log_mobile_scale_trace(char_id)
	debug_mobile_scale_trace_label = char_id
	if debug_mobile_scale_trace_enabled:
		print("[CharacterScaleTrace] load_character begin char=%s requested_path=%s" % [char_id, path])
	var use_cdn_animation_textures := CdnAssetLoader.is_cdn_mapped_res_path(path)
	var local_sprite_frames := load(path) as SpriteFrames if not use_cdn_animation_textures and ResourceLoader.exists(path, "SpriteFrames") else null
	if use_cdn_animation_textures:
		animation.sprite_frames = await _load_cdn_sprite_frames(path, yield_between_textures)
		if animation.sprite_frames == null and _is_complete_local_sprite_frames(path):
			animation.sprite_frames = await _prepare_sprite_frames_for_runtime(load(path) as SpriteFrames, yield_between_textures)
	elif local_sprite_frames != null:
		animation.sprite_frames = await _prepare_sprite_frames_for_runtime(local_sprite_frames, yield_between_textures)
	elif CdnAssetLoader.is_cdn_mapped_res_path(path):
		animation.sprite_frames = await _load_cdn_sprite_frames(path, yield_between_textures)
	else:
		var check_ids = [char_id]
		if char_id.begins_with("custom_"):
			check_ids.append(char_id.substr(7))
		for check_id in check_ids:
			if 'custom_animations' in character_data and check_id in character_data['custom_animations']:
				return await load_character_custom_anims(image_loader, character_data['custom_animations'][check_id])

		path = "res://assets/character_animations/custom/animations.tres"
		var use_cdn_custom_animation_textures := CdnAssetLoader.is_cdn_mapped_res_path(path)
		var local_custom_sprite_frames := load(path) as SpriteFrames if not use_cdn_custom_animation_textures and ResourceLoader.exists(path, "SpriteFrames") else null
		if use_cdn_custom_animation_textures:
			animation.sprite_frames = await _load_cdn_sprite_frames(path, yield_between_textures)
			if animation.sprite_frames == null and _is_complete_local_sprite_frames(path):
				animation.sprite_frames = await _prepare_sprite_frames_for_runtime(load(path) as SpriteFrames, yield_between_textures)
		elif local_custom_sprite_frames != null:
			animation.sprite_frames = await _prepare_sprite_frames_for_runtime(local_custom_sprite_frames, yield_between_textures)
		elif CdnAssetLoader.is_cdn_mapped_res_path(path):
			animation.sprite_frames = await _load_cdn_sprite_frames(path, yield_between_textures)

	if animation.sprite_frames == null or not animation.sprite_frames.has_animation("idle") or animation.sprite_frames.get_frame_count("idle") == 0:
		var fallback_texture := await CdnAssetLoader.load_texture("res://assets/portraits/custom.png", _get_budget_owner(), "visible")
		if fallback_texture == null and ResourceLoader.exists("res://assets/portraits/custom.png", "Texture2D"):
			fallback_texture = load("res://assets/portraits/custom.png") as Texture2D
		if fallback_texture != null:
			animation.sprite_frames = SpriteFrames.new()
			animation.sprite_frames.add_animation("idle")
			animation.sprite_frames.add_frame("idle", fallback_texture)
		
	animation.scale = Vector2.ONE
	if _is_mobile_web():
		animation.scale *= maxf(0.01, GlobalSettings.phone_animation_final_scaling_adjust)
	play_animation("idle")
	scale /= runtime_texture_scale_compensation
	exceed_icon.scale *= runtime_texture_scale_compensation
	runtime_texture_scale_compensation = 1.0
	var scaling = animation.sprite_frames.get_meta("scaling") if animation.sprite_frames.has_meta("scaling") else 1
	if scaling:
		if _uses_relative_scale(char_id):
			var relative_scaling := float(scaling)
			if _is_mobile_web():
				relative_scaling *= previous_mobile_texture_scale
			scale *= relative_scaling
			exceed_icon.scale /= relative_scaling
		else:
			scale = base_scale * scaling
			exceed_icon.scale = base_exceed_icon_scale / scaling
	vertical_offset = animation.sprite_frames.get_meta("vertical_offset") if animation.sprite_frames.has_meta("vertical_offset") else 0
	if _is_mobile_web():
		vertical_offset = _adjust_animation_vertical_offset_for_final_scale(
			vertical_offset,
			get_size().y * scale.y,
			GlobalSettings.phone_animation_final_scaling_adjust)
	horizontal_offset = animation.sprite_frames.get_meta("horizontal_offset") if animation.sprite_frames.has_meta("horizontal_offset") else 0
	horizontal_offset_buddy = animation.sprite_frames.get_meta("horizontal_offset_buddy") if animation.sprite_frames.has_meta("horizontal_offset_buddy") else 0
	if debug_mobile_scale_trace_enabled:
		_print_mobile_animation_layout_trace(char_id, path, scaling)
	set_facing(animation.flip_h)

static func _adjust_animation_vertical_offset_for_final_scale(
		authored_offset: float,
		unadjusted_display_height: float,
		final_scaling_adjust: float) -> float:
	var applied_scaling_adjust := maxf(0.01, final_scaling_adjust)
	return authored_offset + unadjusted_display_height * (applied_scaling_adjust - 1.0) / 2.0

func _is_complete_local_sprite_frames(resource_path: String) -> bool:
	var resource_text := FileAccess.get_file_as_string(resource_path) if FileAccess.file_exists(resource_path) else ""
	if resource_text.is_empty():
		return false
	for line in resource_text.split("\n"):
		if line.begins_with("[ext_resource") and "type=\"Texture2D\"" in line:
			# CDN SpriteFrames keep an import-ready placeholder in path and store the
			# real texture in cdn_path. Comparing that placeholder with a phone image
			# produces a false desktop-size ratio and breaks display compensation.
			if "cdn_path=" in line:
				return false
			var path_start := line.find("path=\"")
			if path_start == -1:
				continue
			var texture_path := line.substr(path_start + 6).split("\"")[0]
			# Only use local SpriteFrames fallback when referenced textures are import-ready.
			if not ResourceLoader.exists(texture_path, "Texture2D"):
				return false
	return true

func _is_mobile_web() -> bool:
	return MobileRuntimeFlags.is_mobile_resource_runtime()

static func get_mobile_web_character_texture_size(source_size : Vector2i) -> Vector2i:
	return Vector2i(
		maxi(1, int(round(source_size.x * MOBILE_WEB_CHARACTER_TEXTURE_SCALE))),
		maxi(1, int(round(source_size.y * MOBILE_WEB_CHARACTER_TEXTURE_SCALE))))

func _prepare_sprite_frames_for_runtime(source_frames : SpriteFrames, yield_between_textures := true) -> SpriteFrames:
	if source_frames == null or not _is_mobile_web():
		return source_frames
	mobile_texture_scale_for_display = _get_mobile_texture_scale_for_frames(source_frames)

	var optimized_frames := SpriteFrames.new()
	if optimized_frames.has_animation(&"default"):
		optimized_frames.remove_animation(&"default")
	for metadata_name in source_frames.get_meta_list():
		optimized_frames.set_meta(metadata_name, source_frames.get_meta(metadata_name))
	_apply_mobile_animation_scaling_metadata(optimized_frames, mobile_texture_scale_for_display)
	for animation_name in source_frames.get_animation_names():
		optimized_frames.add_animation(animation_name)
		optimized_frames.set_animation_loop(animation_name, source_frames.get_animation_loop(animation_name))
		optimized_frames.set_animation_speed(animation_name, source_frames.get_animation_speed(animation_name))

	var scaled_texture_cache := {}
	for animation_name in source_frames.get_animation_names():
		for frame_index in range(source_frames.get_frame_count(animation_name)):
			var source_texture := source_frames.get_frame_texture(animation_name, frame_index)
			var optimized_texture := await _create_mobile_web_frame_texture(
				source_texture,
				scaled_texture_cache,
				yield_between_textures,
					mobile_texture_scale_for_display)
			optimized_frames.add_frame(
				animation_name,
				optimized_texture,
				source_frames.get_frame_duration(animation_name, frame_index))
	return optimized_frames

func _load_cdn_sprite_frames(animation_resource_path: String, yield_between_textures := true) -> SpriteFrames:
	var tres_text := await CdnAssetLoader.load_text(animation_resource_path, false, false)
	if tres_text.is_empty():
		return null
	var resource_directory := animation_resource_path.get_base_dir()
	var parsed := _parse_sprite_frames_tres(tres_text, resource_directory)
	var authored_frames := load(animation_resource_path) as SpriteFrames if ResourceLoader.exists(animation_resource_path, "SpriteFrames") else null
	if authored_frames != null:
		for metadata_name in authored_frames.get_meta_list():
			parsed["metadata"][metadata_name] = authored_frames.get_meta(metadata_name)
	var texture_paths : Dictionary = parsed["texture_paths"]
	var atlas_defs : Dictionary = parsed["atlas_defs"]
	var loaded_textures := {}
	var desktop_fallback_by_texture_id := {}
	var texture_scales := {}
	var target_texture_scale := 1.0
	for texture_id in texture_paths.keys():
		var source_texture_path : String = texture_paths[texture_id]
		var texture_path := source_texture_path
		var phone_path := ""
		var desktop_source_texture_path := _get_desktop_texture_resource_path(source_texture_path)
		var texture_scale := 1.0
		var reported_scale := -1.0
		var measured_texture_scale := -1.0
		var scale_resolution_reason := "not-mobile-runtime"
		desktop_fallback_by_texture_id[texture_id] = false
		if _is_mobile_web():
			reported_scale = await _get_phone_character_texture_scale_async(desktop_source_texture_path)
			texture_scale = reported_scale if reported_scale > 0.0 else 1.0
			phone_path = source_texture_path if source_texture_path != desktop_source_texture_path else _get_phone_character_texture_path(source_texture_path)
			if not phone_path.is_empty() and _character_texture_exists(phone_path):
				texture_path = phone_path
				scale_resolution_reason = "report-scale"
			else:
				scale_resolution_reason = "phone-texture-missing-use-default"
				desktop_fallback_by_texture_id[texture_id] = true
		loaded_textures[texture_id] = await CdnAssetLoader.load_texture(
			texture_path,
			_get_budget_owner(),
			"visible",
			true)
		if _is_mobile_web() and loaded_textures[texture_id] == null and texture_path != desktop_source_texture_path:
			loaded_textures[texture_id] = await CdnAssetLoader.load_texture(
				desktop_source_texture_path,
				_get_budget_owner(),
				"visible",
				true)
			if loaded_textures[texture_id] != null:
				texture_path = desktop_source_texture_path
				reported_scale = -1.0
				texture_scale = 1.0
				scale_resolution_reason = "phone-download-failed-use-desktop"
				desktop_fallback_by_texture_id[texture_id] = true
		if _is_mobile_web() and loaded_textures[texture_id] != null:
			if not desktop_fallback_by_texture_id.get(texture_id, false):
				loaded_textures[texture_id] = _normalize_mobile_web_texture_to_report_size(
					loaded_textures[texture_id],
					desktop_source_texture_path)
			measured_texture_scale = _measure_runtime_texture_scale(desktop_source_texture_path, loaded_textures[texture_id])
			if measured_texture_scale <= 0.0:
				var report_source_size_scale := _measure_runtime_texture_scale_from_report_source_size(
					desktop_source_texture_path,
					loaded_textures[texture_id])
				if report_source_size_scale > 0.0:
					measured_texture_scale = report_source_size_scale

			# Prefer report scale for deterministic parity with authored/mobile reference tables.
			# Measured scale is used only as fallback when report data is unavailable.
			if reported_scale > 0.0:
				texture_scale = reported_scale
				if measured_texture_scale > 0.0 and abs(measured_texture_scale - reported_scale) >= 0.001:
					scale_resolution_reason = "report-scale-preferred-over-measured"
				else:
					scale_resolution_reason = "report-scale"
			elif measured_texture_scale > 0.0:
				texture_scale = measured_texture_scale
				scale_resolution_reason = "measured-scale-fallback-no-report"
			elif scale_resolution_reason == "phone-texture-missing-use-default":
				scale_resolution_reason = "fallback-default-measure-failed"
			else:
				scale_resolution_reason = "fallback-report-missing-and-measure-failed"
		if debug_mobile_scale_trace_enabled and _is_mobile_web():
			var runtime_size := Vector2.ZERO
			if loaded_textures[texture_id] != null:
				runtime_size = loaded_textures[texture_id].get_size()
			print("[CharacterScaleTrace] texture char=%s tex_id=%s source=%s phone=%s used=%s desktop=%s report_scale=%s measured_scale=%s final_scale=%s reason=%s" % [
				debug_mobile_scale_trace_label,
				texture_id,
				source_texture_path,
				phone_path,
				texture_path,
				_get_desktop_texture_resource_path(source_texture_path),
				str(reported_scale),
				str(measured_texture_scale),
				str(texture_scale),
				scale_resolution_reason,
			])
			print("[CharacterScaleTrace] texture_runtime_size char=%s tex_id=%s runtime_size=%s report_source_size=%s" % [
				debug_mobile_scale_trace_label,
				texture_id,
				str(runtime_size),
				str(phone_animation_source_size_by_path.get(_get_desktop_texture_resource_path(source_texture_path), Vector2i.ZERO)),
			])
		texture_scales[texture_id] = texture_scale
		if yield_between_textures:
			await get_tree().process_frame

	if _is_mobile_web():
		target_texture_scale = _get_minimum_texture_scale(texture_scales)
		mobile_texture_scale_for_display = target_texture_scale
		mobile_display_scale_initialized = true
		if debug_mobile_scale_trace_enabled:
			print("[CharacterScaleTrace] target-display-scale char=%s target=%s texture_scales=%s" % [
				debug_mobile_scale_trace_label,
				str(target_texture_scale),
				str(texture_scales),
			])
		for texture_id in loaded_textures.keys():
			var loaded_texture: Texture2D = loaded_textures[texture_id]
			var texture_scale := float(texture_scales.get(texture_id, target_texture_scale))
			if loaded_texture != null and abs(texture_scale - target_texture_scale) >= 0.001:
				loaded_textures[texture_id] = _normalize_mobile_web_base_texture(loaded_texture, texture_scale, target_texture_scale)
	var atlas_source_sizes := _get_parsed_atlas_source_sizes(atlas_defs, texture_paths)
	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	for metadata_name in parsed["metadata"].keys():
		frames.set_meta(metadata_name, parsed["metadata"][metadata_name])
	_apply_mobile_animation_scaling_metadata(frames, target_texture_scale)
	for animation_def in parsed["animations"]:
		var animation_name : String = animation_def["name"]
		frames.add_animation(animation_name)
		frames.set_animation_loop(animation_name, animation_def.get("loop", true))
		frames.set_animation_speed(animation_name, animation_def.get("speed", 5.0))
		for frame_def in animation_def["frames"]:
			var atlas_id : String = frame_def.get("atlas_id", "")
			var texture_id : String = frame_def.get("texture_id", "")
			var atlas_def : Dictionary = atlas_defs.get(atlas_id, {})
			if texture_id.is_empty():
				texture_id = atlas_def.get("texture_id", "")
			var base_texture : Texture2D = loaded_textures.get(texture_id, null)
			if base_texture == null:
				continue
			var frame_texture : Texture2D = base_texture
			if not atlas_id.is_empty():
				var atlas_texture := AtlasTexture.new()
				atlas_texture.atlas = base_texture
				var region : Rect2 = atlas_def.get("region", Rect2())
				var source_atlas_size : Vector2 = atlas_source_sizes.get(atlas_id, Vector2.ZERO)
				var is_desktop_fallback : bool = desktop_fallback_by_texture_id.get(texture_id, false)
				var final_region := region if is_desktop_fallback else _scale_mobile_web_rect_to_atlas(region, source_atlas_size, base_texture.get_size()) if _is_mobile_web() else region
				atlas_texture.region = final_region
				if debug_mobile_scale_trace_enabled and _is_mobile_web():
					print("[CharacterLayoutTrace] region char=%s texture_id=%s atlas_id=%s source_region=%s source_atlas=%s target_atlas=%s final_region=%s desktop_fallback=%s" % [
						debug_mobile_scale_trace_label,
						texture_id,
						atlas_id,
						str(region),
						str(source_atlas_size),
						str(base_texture.get_size()),
						str(final_region),
						str(is_desktop_fallback)])
				frame_texture = atlas_texture
			frames.add_frame(animation_name, frame_texture, frame_def.get("duration", 1.0))
	return frames

func _apply_mobile_animation_scaling_metadata(frames : SpriteFrames, texture_scale : float):
	if frames == null or not _is_mobile_web():
		return
	var desktop_scaling := float(frames.get_meta("scaling", 1.0))
	frames.set_meta("scaling", desktop_scaling / maxf(texture_scale, 0.1))

static func _scale_mobile_web_rect_for_animation(source_rect : Rect2, authored_scaling : float, final_scaling : float) -> Rect2:
	var scaling_ratio := authored_scaling / maxf(final_scaling, 0.0001)
	return _scale_mobile_web_rect(source_rect, scaling_ratio)

static func _scale_mobile_web_rect_to_atlas(source_rect : Rect2, source_atlas_size : Vector2, target_atlas_size : Vector2) -> Rect2:
	if source_atlas_size.x <= 0.0 or source_atlas_size.y <= 0.0:
		return source_rect
	var source_end := source_rect.position + source_rect.size
	var mapped_position := Vector2(
		round(source_rect.position.x * target_atlas_size.x / source_atlas_size.x),
		round(source_rect.position.y * target_atlas_size.y / source_atlas_size.y))
	var target_end := Vector2(
		round(source_end.x * target_atlas_size.x / source_atlas_size.x),
		round(source_end.y * target_atlas_size.y / source_atlas_size.y))
	return Rect2(
		mapped_position,
		target_end - mapped_position)

static func _get_parsed_atlas_source_sizes(atlas_defs : Dictionary, texture_paths : Dictionary) -> Dictionary:
	var atlas_sizes := {}
	var inferred_sizes_by_texture_id := {}
	for atlas_def_value in atlas_defs.values():
		var atlas_def : Dictionary = atlas_def_value
		var texture_id := str(atlas_def.get("texture_id", ""))
		var region : Rect2 = atlas_def.get("region", Rect2())
		var extent := region.position + region.size
		var inferred_size : Vector2 = inferred_sizes_by_texture_id.get(texture_id, Vector2.ZERO)
		inferred_sizes_by_texture_id[texture_id] = Vector2(
			maxf(inferred_size.x, extent.x),
			maxf(inferred_size.y, extent.y))
	for atlas_id in atlas_defs.keys():
		var atlas_def : Dictionary = atlas_defs[atlas_id]
		var texture_id := str(atlas_def.get("texture_id", ""))
		var source_path := _get_desktop_texture_resource_path(str(texture_paths.get(texture_id, "")))
		var source_size : Vector2i = phone_animation_source_size_by_path.get(source_path, Vector2i.ZERO)
		if source_size.x > 0 and source_size.y > 0:
			atlas_sizes[atlas_id] = Vector2(source_size)
			continue
		atlas_sizes[atlas_id] = inferred_sizes_by_texture_id.get(texture_id, Vector2.ZERO)
	return atlas_sizes

static func _get_minimum_texture_scale(texture_scales: Dictionary) -> float:
	if texture_scales.is_empty():
		return MOBILE_WEB_CHARACTER_TEXTURE_SCALE
	var target_scale := -1.0
	for key in texture_scales.keys():
		var scale_value := float(texture_scales[key])
		if scale_value <= 0.0:
			continue
		if target_scale < 0.0:
			target_scale = scale_value
		else:
			target_scale = minf(target_scale, scale_value)
	if target_scale < 0.0:
		return MOBILE_WEB_CHARACTER_TEXTURE_SCALE
	return maxf(target_scale, 0.1)

static func _measure_runtime_texture_scale(source_texture_path: String, runtime_texture: Texture2D) -> float:
	if runtime_texture == null:
		return -1.0
	if not ResourceLoader.exists(source_texture_path, "Texture2D"):
		return -1.0
	var source_texture := load(source_texture_path) as Texture2D
	if source_texture == null:
		return -1.0
	var source_size := source_texture.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return -1.0
	var runtime_size := runtime_texture.get_size()
	if runtime_size.x <= 0.0 or runtime_size.y <= 0.0:
		return -1.0
	var scale_x := runtime_size.x / source_size.x
	var scale_y := runtime_size.y / source_size.y
	if scale_x <= 0.0 or scale_y <= 0.0:
		return -1.0
	return minf(scale_x, scale_y)

func _get_mobile_texture_scale_for_remote_texture_paths(texture_paths: Array) -> float:
	var texture_scales := []
	for source_path in texture_paths:
		var source_path_string := str(source_path)
		var phone_path := _get_phone_character_texture_path(source_path_string)
		if phone_path.is_empty() or not _character_texture_exists(phone_path):
			texture_scales.append(MOBILE_WEB_CHARACTER_TEXTURE_SCALE)
		else:
			texture_scales.append(await _get_phone_character_texture_scale_async(source_path_string))
	if texture_scales.is_empty():
		return MOBILE_WEB_CHARACTER_TEXTURE_SCALE
	var target_scale := float(texture_scales[0])
	for texture_scale in texture_scales:
		target_scale = minf(target_scale, float(texture_scale))
	return maxf(target_scale, 0.1)

static func _parse_sprite_frames_tres(tres_text: String, resource_directory: String) -> Dictionary:
	var texture_paths := {}
	var atlas_defs := {}
	var metadata := {}
	var lines := tres_text.split("\n")
	var current_atlas_id := ""
	for raw_line in lines:
		var line := raw_line.strip_edges()
		if line.begins_with("[ext_resource") and "type=\"Texture2D\"" in line:
			var id := _extract_quoted_after(line, " id=\"")
			var path := _extract_quoted_after(line, "path=\"")
			var cdn_path := _extract_quoted_after(line, "cdn_path=\"")
			if not cdn_path.is_empty():
				path = cdn_path
			if not id.is_empty() and not path.is_empty():
				texture_paths[id] = _resolve_tres_resource_path(resource_directory, path)
		elif line.begins_with("[sub_resource") and "type=\"AtlasTexture\"" in line:
			current_atlas_id = _extract_quoted_after(line, "id=\"")
			if not current_atlas_id.is_empty():
				atlas_defs[current_atlas_id] = {}
		elif not current_atlas_id.is_empty() and line.begins_with("atlas = ExtResource(\""):
			atlas_defs[current_atlas_id]["texture_id"] = _extract_between(line, "ExtResource(\"", "\")")
		elif not current_atlas_id.is_empty() and line.begins_with("region = Rect2("):
			atlas_defs[current_atlas_id]["region"] = _parse_rect2(line)
		elif line.begins_with("[resource]"):
			current_atlas_id = ""
		elif line.begins_with("metadata/"):
			var parts := line.split("=", true, 1)
			if parts.size() == 2:
				metadata[parts[0].trim_prefix("metadata/").strip_edges()] = _parse_tres_value(parts[1].strip_edges())
	return {
		"texture_paths": texture_paths,
		"atlas_defs": atlas_defs,
		"animations": _parse_tres_animations(tres_text),
		"metadata": metadata,
	}

static func _parse_tres_animations(tres_text: String) -> Array:
	var marker := "animations = ["
	var start := tres_text.find(marker)
	if start < 0:
		return []
	start += marker.length()
	var end := tres_text.find("metadata/", start)
	var animation_text := tres_text.substr(start, end - start if end >= 0 else tres_text.length() - start)
	var animations := []
	var search_from := 0
	while true:
		var name_pos := animation_text.find("\"name\": &\"", search_from)
		if name_pos < 0:
			break
		var block_start := animation_text.rfind("\"frames\": [{", name_pos)
		if block_start < 0:
			search_from = name_pos + 1
			continue
		var block_end := animation_text.find("\"frames\": [{", name_pos + 1)
		if block_end < 0:
			block_end = animation_text.length()
		var block := animation_text.substr(block_start, block_end - block_start)
		var animation_name := _extract_between(block, "\"name\": &\"", "\"")
		var loop := _extract_bool_property(block, "\"loop\":", true)
		var speed := _extract_float_property(block, "\"speed\":", 5.0)
		animations.append({
			"name": animation_name,
			"loop": loop,
			"speed": speed,
			"frames": _parse_tres_animation_frames(block),
		})
		search_from = name_pos + 1
	return animations

static func _parse_tres_animation_frames(block: String) -> Array:
	var frames := []
	var pending_duration := 1.0
	for raw_line in block.split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with("\"duration\":"):
			pending_duration = _extract_float_property(line, "\"duration\":", 1.0)
		elif line.begins_with("\"texture\":"):
			frames.append({
				"duration": pending_duration,
				"atlas_id": _extract_between(line, "SubResource(\"", "\")"),
				"texture_id": _extract_between(line, "ExtResource(\"", "\")"),
			})
	return frames

static func _resolve_tres_resource_path(resource_directory: String, path: String) -> String:
	if path.begins_with("res://"):
		return path
	return resource_directory.path_join(path).simplify_path()

static func _extract_quoted_after(text: String, prefix: String) -> String:
	var start := text.find(prefix)
	if start < 0:
		return ""
	start += prefix.length()
	var end := text.find("\"", start)
	return "" if end < 0 else text.substr(start, end - start)

static func _extract_between(text: String, prefix: String, suffix: String) -> String:
	var start := text.find(prefix)
	if start < 0:
		return ""
	start += prefix.length()
	var end := text.find(suffix, start)
	return "" if end < 0 else text.substr(start, end - start)

static func _extract_float_property(text: String, prefix: String, default_value: float) -> float:
	var start := text.find(prefix)
	if start < 0:
		return default_value
	start += prefix.length()
	var end := text.find("\n", start)
	if end < 0:
		end = text.length()
	return text.substr(start, end - start).strip_edges().trim_suffix(",").to_float()

static func _extract_bool_property(text: String, prefix: String, default_value: bool) -> bool:
	var start := text.find(prefix)
	if start < 0:
		return default_value
	start += prefix.length()
	var end := text.find("\n", start)
	if end < 0:
		end = text.length()
	var value := text.substr(start, end - start).strip_edges().trim_suffix(",")
	return value == "true"

static func _parse_rect2(text: String) -> Rect2:
	var value := _extract_between(text, "Rect2(", ")")
	var numbers := value.split(",", false)
	if numbers.size() < 4:
		return Rect2()
	return Rect2(
		numbers[0].strip_edges().to_float(),
		numbers[1].strip_edges().to_float(),
		numbers[2].strip_edges().to_float(),
		numbers[3].strip_edges().to_float())

static func _parse_tres_value(text: String):
	var value := text.trim_suffix(",").strip_edges()
	if value == "true":
		return true
	if value == "false":
		return false
	if value.is_valid_float():
		return value.to_float()
	if value.begins_with("\"") and value.ends_with("\""):
		return value.substr(1, value.length() - 2)
	return value

func _get_mobile_texture_scale_for_frames(source_frames : SpriteFrames) -> float:
	var texture_scales := []
	var seen_texture_paths := {}
	for animation_name in source_frames.get_animation_names():
		for frame_index in range(source_frames.get_frame_count(animation_name)):
			var source_texture := source_frames.get_frame_texture(animation_name, frame_index)
			var base_texture := _get_source_base_texture(source_texture)
			if base_texture == null:
				continue
			var texture_path := base_texture.resource_path
			if texture_path.is_empty() or seen_texture_paths.has(texture_path):
				continue
			seen_texture_paths[texture_path] = true
			var phone_path := _get_phone_character_texture_path(texture_path)
			if phone_path.is_empty() or not _character_texture_exists(phone_path):
				texture_scales.append(MOBILE_WEB_CHARACTER_TEXTURE_SCALE)
			else:
				texture_scales.append(_get_phone_character_texture_scale(texture_path))
	if texture_scales.is_empty():
		return MOBILE_WEB_CHARACTER_TEXTURE_SCALE
	var target_scale := float(texture_scales[0])
	for texture_scale in texture_scales:
		target_scale = minf(target_scale, float(texture_scale))
	return maxf(target_scale, 0.1)

static func _get_source_base_texture(source_texture : Texture2D) -> Texture2D:
	if source_texture is AtlasTexture:
		return source_texture.atlas
	return source_texture

func _create_mobile_web_frame_texture(
		source_texture : Texture2D,
		scaled_texture_cache : Dictionary,
		yield_between_textures : bool,
		target_texture_scale := MOBILE_WEB_CHARACTER_TEXTURE_SCALE) -> Texture2D:
	if source_texture == null:
		return null

	if source_texture is AtlasTexture:
		var source_atlas : Texture2D = source_texture.atlas
		if source_atlas == null:
			return source_texture
		var phone_atlas := await _load_phone_character_texture(source_atlas)
		var atlas_scale := _get_phone_character_texture_scale(source_atlas.resource_path) if phone_atlas != null else target_texture_scale
		var atlas_key : String = source_atlas.resource_path + ":" + str(target_texture_scale)
		if not scaled_texture_cache.has(atlas_key):
			scaled_texture_cache[atlas_key] = _normalize_mobile_web_base_texture(phone_atlas, atlas_scale, target_texture_scale) if phone_atlas != null else _create_mobile_web_base_texture(source_atlas, target_texture_scale)
			if yield_between_textures:
				await get_tree().process_frame
		var optimized_atlas := AtlasTexture.new()
		optimized_atlas.atlas = scaled_texture_cache[atlas_key]
		optimized_atlas.region = _scale_mobile_web_rect_to_atlas(
			source_texture.region,
			source_atlas.get_size(),
			optimized_atlas.atlas.get_size())
		optimized_atlas.margin = _scale_mobile_web_rect_to_atlas(
			source_texture.margin,
			source_atlas.get_size(),
			optimized_atlas.atlas.get_size())
		optimized_atlas.filter_clip = source_texture.filter_clip
		return optimized_atlas

	var phone_texture := await _load_phone_character_texture(source_texture)
	if phone_texture != null:
		var phone_scale := _get_phone_character_texture_scale(source_texture.resource_path)
		return _normalize_mobile_web_base_texture(phone_texture, phone_scale, target_texture_scale)
	var texture_key := str(source_texture.get_instance_id()) + ":" + str(target_texture_scale)
	if not scaled_texture_cache.has(texture_key):
		scaled_texture_cache[texture_key] = _create_mobile_web_base_texture(source_texture, target_texture_scale)
		if yield_between_textures:
			await get_tree().process_frame
	return scaled_texture_cache[texture_key]

func _create_mobile_web_base_texture(source_texture : Texture2D, texture_scale := MOBILE_WEB_CHARACTER_TEXTURE_SCALE) -> Texture2D:
	var source_image := source_texture.get_image()
	if source_image == null or source_image.is_empty():
		return source_texture
	var target_size := Vector2i(
		maxi(1, int(round(source_image.get_width() * texture_scale))),
		maxi(1, int(round(source_image.get_height() * texture_scale))))
	RuntimeImageResizerScript.resize_in_place(source_image, target_size.x, target_size.y)
	var optimized_texture := ImageTexture.create_from_image(source_image)
	MobileResourceBudget.register_texture(
		source_texture.resource_path,
		target_size.x,
		target_size.y,
		_get_budget_owner(),
		"visible")
	return optimized_texture

func _normalize_mobile_web_base_texture(source_texture: Texture2D, source_texture_scale: float, target_texture_scale: float) -> Texture2D:
	if source_texture == null:
		return null
	if abs(source_texture_scale - target_texture_scale) < 0.001:
		return source_texture
	var source_image := source_texture.get_image()
	if source_image == null or source_image.is_empty():
		return source_texture
	var resize_ratio := target_texture_scale / source_texture_scale
	var target_size := Vector2i(
		maxi(1, int(round(source_image.get_width() * resize_ratio))),
		maxi(1, int(round(source_image.get_height() * resize_ratio))))
	RuntimeImageResizerScript.resize_in_place(source_image, target_size.x, target_size.y)
	var normalized_texture := ImageTexture.create_from_image(source_image)
	MobileResourceBudget.register_texture(
		source_texture.resource_path,
		target_size.x,
		target_size.y,
		_get_budget_owner(),
		"visible")
	return normalized_texture

static func _normalize_mobile_web_texture_to_report_size(source_texture: Texture2D, source_texture_path: String) -> Texture2D:
	if source_texture == null:
		return null
	var expected_size : Vector2i = phone_animation_output_size_by_path.get(source_texture_path, Vector2i.ZERO)
	if expected_size.x <= 0 or expected_size.y <= 0 or source_texture.get_size() == Vector2(expected_size):
		return source_texture
	var source_image := source_texture.get_image()
	if source_image == null or source_image.is_empty():
		return source_texture
	RuntimeImageResizerScript.resize_in_place(source_image, expected_size.x, expected_size.y)
	return ImageTexture.create_from_image(source_image)

func _should_log_mobile_scale_trace(char_id: String) -> bool:
	if not _is_mobile_web():
		return false
	if not GlobalSettings.is_logging_enabled():
		return false
	return DEBUG_MOBILE_SCALE_TRACE_CHARACTER_ID.is_empty() or char_id.to_lower().find(DEBUG_MOBILE_SCALE_TRACE_CHARACTER_ID) != -1

func _print_mobile_animation_layout_trace(char_id: String, animation_path: String, scaling) -> void:
	var viewport_size := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2.ZERO
	var parent_global_scale : Vector2 = get_parent().global_scale if get_parent() is Node2D else Vector2.ONE
	print("[CharacterLayoutTrace] node char=%s path=%s position=%s global_position=%s character_scale=%s global_scale=%s parent_global_scale=%s animation_scale=%s animation_global_position=%s animation_offset=%s metadata_scaling=%s size=%s viewport=%s flip_h=%s" % [
		char_id,
		animation_path,
		str(position),
		str(global_position),
		str(scale),
		str(global_scale),
		str(parent_global_scale),
		str(animation.scale),
		str(animation.global_position),
		str(animation.offset),
		str(scaling),
		str(get_size()),
		str(viewport_size),
		str(animation.flip_h)])
	for animation_name in animation.sprite_frames.get_animation_names():
		var frame_count := animation.sprite_frames.get_frame_count(animation_name)
		for frame_index in range(mini(frame_count, 3)):
			var frame_texture := animation.sprite_frames.get_frame_texture(animation_name, frame_index)
			var frame_size := frame_texture.get_size() if frame_texture != null else Vector2.ZERO
			var atlas_size := Vector2.ZERO
			var region := Rect2()
			var texture_kind := "direct"
			if frame_texture is AtlasTexture:
				var atlas_texture := frame_texture as AtlasTexture
				atlas_size = atlas_texture.atlas.get_size() if atlas_texture.atlas != null else Vector2.ZERO
				region = atlas_texture.region
				texture_kind = "atlas"
			print("[CharacterLayoutTrace] frame char=%s animation=%s index=%d kind=%s frame_size=%s atlas_size=%s region=%s" % [
				char_id, animation_name, frame_index, texture_kind, str(frame_size), str(atlas_size), str(region)])

func _compute_mobile_display_compensation_from_desktop_reference(current_frames: SpriteFrames, animation_resource_path: String) -> float:
	var fallback_compensation := 1.0 / maxf(mobile_texture_scale_for_display, 0.1)
	if current_frames == null:
		return fallback_compensation
	if not current_frames.has_animation("idle") or current_frames.get_frame_count("idle") == 0:
		return fallback_compensation
	var current_frame := current_frames.get_frame_texture("idle", 0)
	if current_frame == null:
		return fallback_compensation
	var current_size := current_frame.get_size()
	if current_size.x <= 0.0 or current_size.y <= 0.0:
		return fallback_compensation

	var desktop_animation_path := _get_desktop_animation_resource_path(animation_resource_path)
	if desktop_animation_path.is_empty() or not ResourceLoader.exists(desktop_animation_path, "SpriteFrames"):
		return fallback_compensation
	# If desktop animation depends on textures not available locally,
	# frame size may degrade to placeholder values and cause severe under-scaling.
	# In that case, trust report-driven fallback compensation.
	if not _is_complete_local_sprite_frames(desktop_animation_path):
		return fallback_compensation
	var desktop_frames := load(desktop_animation_path) as SpriteFrames
	if desktop_frames == null:
		return fallback_compensation
	if not desktop_frames.has_animation("idle") or desktop_frames.get_frame_count("idle") == 0:
		return fallback_compensation
	var desktop_frame := desktop_frames.get_frame_texture("idle", 0)
	if desktop_frame == null:
		return fallback_compensation
	var desktop_size := desktop_frame.get_size()
	if desktop_size.x <= 0.0 or desktop_size.y <= 0.0:
		return fallback_compensation

	var width_ratio := desktop_size.x / current_size.x
	var height_ratio := desktop_size.y / current_size.y
	if width_ratio <= 0.0 or height_ratio <= 0.0:
		return fallback_compensation
	# Favor the smaller axis ratio to avoid over-scaling if one axis is cropped.
	return clampf(minf(width_ratio, height_ratio), 0.1, 10.0)

static func _get_desktop_animation_resource_path(animation_resource_path: String) -> String:
	if animation_resource_path.begins_with(PHONE_CHARACTER_ANIMATION_ROOT):
		return CHARACTER_ANIMATION_ROOT + animation_resource_path.trim_prefix(PHONE_CHARACTER_ANIMATION_ROOT)
	if animation_resource_path.begins_with(PHONE_CHARACTER_ANIMATION_SKIN_ROOT):
		return CHARACTER_ANIMATION_SKIN_ROOT + animation_resource_path.trim_prefix(PHONE_CHARACTER_ANIMATION_SKIN_ROOT)
	if animation_resource_path.begins_with(PHONE_CHARACTER_ANIMATION_CUSTOM_ROOT):
		return CHARACTER_ANIMATION_CUSTOM_ROOT + animation_resource_path.trim_prefix(PHONE_CHARACTER_ANIMATION_CUSTOM_ROOT)
	return animation_resource_path

static func _get_desktop_texture_resource_path(texture_resource_path: String) -> String:
	if texture_resource_path.begins_with(PHONE_CHARACTER_ANIMATION_ROOT):
		return CHARACTER_ANIMATION_ROOT + texture_resource_path.trim_prefix(PHONE_CHARACTER_ANIMATION_ROOT)
	if texture_resource_path.begins_with(PHONE_CHARACTER_ANIMATION_SKIN_ROOT):
		return CHARACTER_ANIMATION_SKIN_ROOT + texture_resource_path.trim_prefix(PHONE_CHARACTER_ANIMATION_SKIN_ROOT)
	if texture_resource_path.begins_with(PHONE_CHARACTER_ANIMATION_CUSTOM_ROOT):
		return CHARACTER_ANIMATION_CUSTOM_ROOT + texture_resource_path.trim_prefix(PHONE_CHARACTER_ANIMATION_CUSTOM_ROOT)
	if texture_resource_path.begins_with(PHONE_CHARACTER_PORTRAIT_ROOT):
		return CHARACTER_PORTRAIT_ROOT + texture_resource_path.trim_prefix(PHONE_CHARACTER_PORTRAIT_ROOT)
	if texture_resource_path.begins_with(PHONE_CHARACTER_PORTRAIT_SKIN_ROOT):
		return CHARACTER_PORTRAIT_SKIN_ROOT + texture_resource_path.trim_prefix(PHONE_CHARACTER_PORTRAIT_SKIN_ROOT)
	if texture_resource_path.begins_with(PHONE_CHARACTER_PORTRAIT_CUSTOM_ROOT):
		return CHARACTER_PORTRAIT_CUSTOM_ROOT + texture_resource_path.trim_prefix(PHONE_CHARACTER_PORTRAIT_CUSTOM_ROOT)
	return texture_resource_path

func _get_budget_owner() -> String:
	return "Character:%s" % get_instance_id()

static func _scale_mobile_web_rect(source_rect : Rect2, scale_factor := MOBILE_WEB_CHARACTER_TEXTURE_SCALE) -> Rect2:
	return Rect2(
		source_rect.position * scale_factor,
		source_rect.size * scale_factor)

static func _get_phone_character_texture_path(source_path: String) -> String:
	if source_path.begins_with(CHARACTER_ANIMATION_ROOT):
		return PHONE_CHARACTER_ANIMATION_ROOT + source_path.trim_prefix(CHARACTER_ANIMATION_ROOT)
	if source_path.begins_with(CHARACTER_ANIMATION_SKIN_ROOT):
		return PHONE_CHARACTER_ANIMATION_SKIN_ROOT + source_path.trim_prefix(CHARACTER_ANIMATION_SKIN_ROOT)
	if source_path.begins_with(CHARACTER_ANIMATION_CUSTOM_ROOT):
		return PHONE_CHARACTER_ANIMATION_CUSTOM_ROOT + source_path.trim_prefix(CHARACTER_ANIMATION_CUSTOM_ROOT)
	if source_path.begins_with(CHARACTER_PORTRAIT_ROOT):
		return PHONE_CHARACTER_PORTRAIT_ROOT + source_path.trim_prefix(CHARACTER_PORTRAIT_ROOT)
	if source_path.begins_with(CHARACTER_PORTRAIT_SKIN_ROOT):
		return PHONE_CHARACTER_PORTRAIT_SKIN_ROOT + source_path.trim_prefix(CHARACTER_PORTRAIT_SKIN_ROOT)
	if source_path.begins_with(CHARACTER_PORTRAIT_CUSTOM_ROOT):
		return PHONE_CHARACTER_PORTRAIT_CUSTOM_ROOT + source_path.trim_prefix(CHARACTER_PORTRAIT_CUSTOM_ROOT)
	return ""

static func _apply_phone_animation_scale_report_text(report_text: String, source_root: String):
	for line in report_text.split("\n"):
		var columns: PackedStringArray = line.split("\t")
		if columns.size() < 5:
			continue
		var relative_path := _normalize_phone_report_path(columns[1])
		if relative_path.is_empty() or relative_path == "相对路径":
			continue
		var image_scale: float = columns[4].to_float()
		var source_size := _parse_report_size(columns[2]) if columns.size() >= 3 else Vector2i.ZERO
		var output_size := _parse_report_size(columns[3]) if columns.size() >= 4 else Vector2i.ZERO
		var source_path := source_root + relative_path
		if source_size.x > 0 and source_size.y > 0:
			phone_animation_source_size_by_path[source_path] = source_size
		if output_size.x > 0 and output_size.y > 0:
			phone_animation_output_size_by_path[source_path] = output_size
		if image_scale > 0.0:
			phone_animation_scale_by_path[source_path] = image_scale

static func _load_phone_animation_scale_report(report_path: String, source_root: String):
	if phone_animation_scale_report_loaded_by_path.get(report_path, false):
		return
	phone_animation_scale_report_loaded_by_path[report_path] = true
	var report_file := FileAccess.open(report_path, FileAccess.READ)
	if report_file == null:
		push_warning("[Character] 未找到移动端角色动画缩放比例报告: %s" % report_path)
		return
	_apply_phone_animation_scale_report_text(report_file.get_as_text(), source_root)

static func _get_phone_character_texture_scale(source_path: String) -> float:
	if source_path.begins_with(CHARACTER_ANIMATION_ROOT):
		_load_phone_animation_scale_report(PHONE_CHARACTER_ANIMATION_SCALE_REPORT, CHARACTER_ANIMATION_ROOT)
		return phone_animation_scale_by_path.get(source_path, 1.0)
	if source_path.begins_with(CHARACTER_ANIMATION_SKIN_ROOT):
		_load_phone_animation_scale_report(PHONE_CHARACTER_ANIMATION_SKIN_SCALE_REPORT, CHARACTER_ANIMATION_SKIN_ROOT)
		return phone_animation_scale_by_path.get(source_path, 1.0)
	if source_path.begins_with(CHARACTER_ANIMATION_CUSTOM_ROOT):
		_load_phone_animation_scale_report(PHONE_CHARACTER_ANIMATION_CUSTOM_SCALE_REPORT, CHARACTER_ANIMATION_CUSTOM_ROOT)
		return phone_animation_scale_by_path.get(source_path, 1.0)
	return 1.0

static func _get_phone_character_texture_scale_async(source_path: String) -> float:
	if source_path.begins_with(CHARACTER_ANIMATION_ROOT):
		await _load_phone_animation_scale_report_async(PHONE_CHARACTER_ANIMATION_SCALE_REPORT, CHARACTER_ANIMATION_ROOT)
		return phone_animation_scale_by_path.get(source_path, 1.0)
	if source_path.begins_with(CHARACTER_ANIMATION_SKIN_ROOT):
		await _load_phone_animation_scale_report_async(PHONE_CHARACTER_ANIMATION_SKIN_SCALE_REPORT, CHARACTER_ANIMATION_SKIN_ROOT)
		return phone_animation_scale_by_path.get(source_path, 1.0)
	if source_path.begins_with(CHARACTER_ANIMATION_CUSTOM_ROOT):
		await _load_phone_animation_scale_report_async(PHONE_CHARACTER_ANIMATION_CUSTOM_SCALE_REPORT, CHARACTER_ANIMATION_CUSTOM_ROOT)
		return phone_animation_scale_by_path.get(source_path, 1.0)
	return 1.0

static func _load_phone_animation_scale_report_async(report_path: String, source_root: String):
	if phone_animation_scale_report_loaded_by_path.get(report_path, false):
		return
	phone_animation_scale_report_loaded_by_path[report_path] = true
	if FileAccess.file_exists(report_path):
		var local_file := FileAccess.open(report_path, FileAccess.READ)
		if local_file != null:
			_apply_phone_animation_scale_report_text(local_file.get_as_text(), source_root)
			return
	# Reports are export metadata and are bundled with the web PCK. Do not request
	# the Chinese-named report from CDN when an old export is missing it.
	push_warning("[Character] 未找到移动端角色动画缩放比例报告: %s，使用原尺寸 fallback" % report_path)

static func _parse_report_size(size_text: String) -> Vector2i:
	var parts := size_text.strip_edges().split("x")
	if parts.size() != 2:
		return Vector2i.ZERO
	if not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	return Vector2i(parts[0].to_int(), parts[1].to_int())

static func _normalize_phone_report_path(raw_path: String) -> String:
	var normalized := raw_path.strip_edges().replace("\\", "/")
	if normalized.begins_with("res://"):
		normalized = normalized.trim_prefix("res://")
		if normalized.begins_with("assets/phone/"):
			normalized = normalized.trim_prefix("assets/phone/")
	return normalized.trim_prefix("/")

static func _measure_runtime_texture_scale_from_report_source_size(source_texture_path: String, runtime_texture: Texture2D) -> float:
	if runtime_texture == null:
		return -1.0
	var source_size: Vector2i = phone_animation_source_size_by_path.get(source_texture_path, Vector2i.ZERO)
	if source_size.x <= 0 or source_size.y <= 0:
		return -1.0
	var runtime_size := runtime_texture.get_size()
	if runtime_size.x <= 0.0 or runtime_size.y <= 0.0:
		return -1.0
	var scale_x := runtime_size.x / float(source_size.x)
	var scale_y := runtime_size.y / float(source_size.y)
	if scale_x <= 0.0 or scale_y <= 0.0:
		return -1.0
	return minf(scale_x, scale_y)

static func _character_texture_exists(resource_path: String) -> bool:
	return ResourceLoader.exists(resource_path, "Texture2D") or CdnAssetLoader.is_cdn_mapped_res_path(resource_path)

func _load_phone_character_texture(source_texture: Texture2D) -> Texture2D:
	if source_texture == null:
		return null
	var phone_path := _get_phone_character_texture_path(source_texture.resource_path)
	if phone_path.is_empty() or not _character_texture_exists(phone_path):
		return null
	var phone_texture := await CdnAssetLoader.load_texture(
		phone_path,
		"Character:%s" % get_instance_id(),
		"visible",
		true)
	if phone_texture != null:
		MobileResourceBudget.register_texture(
			phone_path,
			int(phone_texture.get_width()),
			int(phone_texture.get_height()),
			"Character:%s" % get_instance_id(),
			"visible")
	return phone_texture

func _uses_relative_scale(animation_id: String) -> bool:
	return RELATIVE_SCALE_EXCEED_ANIMATIONS.has(animation_id) or \
			RELATIVE_SCALE_WIDE_ANIMATIONS.has(animation_id)

func load_character_custom_anims(image_loader : CardImageLoader, animation_data):
	var sprite_frames = SpriteFrames.new()
	var anim_metadata = {}

	for animation_name in animation_data:
		if animation_name == "metadata":
			anim_metadata = animation_data[animation_name]
			continue
		var anim = animation_data[animation_name]

		var image_url = anim["url"]
		var frame_count = anim.get("frame_count", 1)
		var sprite_offset_x = anim.get("sprite_offset_x", 0)
		var sprite_offset_y = anim.get("sprite_offset_y", 0)
		var sprite_region_width = anim.get("sprite_region_width", -1)
		var sprite_region_height = anim.get("sprite_region_height", -1)
		var sprite_count_width = anim.get("sprite_count_width", frame_count)
		var sprite_count_height = anim.get("sprite_count_height", 1)

		var animation_images = await image_loader.get_animation_images(
			image_url,
			sprite_offset_x,
			sprite_offset_y,
			sprite_region_width,
			sprite_region_height,
			sprite_count_width,
			sprite_count_height
		)

		if animation_images:
			sprite_frames.add_animation(animation_name)
			for i in range(frame_count):
				sprite_frames.add_frame(animation_name, animation_images[i])

	# default
	if !sprite_frames.has_animation("idle"):
		sprite_frames.add_animation("idle")
		sprite_frames.add_frame("idle", load("res://assets/portraits/custom.png").duplicate())

	animation.sprite_frames = sprite_frames
	if anim_metadata:
		var scaling = anim_metadata.get("scaling", 1)
		sprite_frames.set_meta("scaling", scaling)
		scale = base_scale * scaling
		exceed_icon.scale = base_exceed_icon_scale / scaling

		sprite_frames.set_meta("vertical_offset", anim_metadata.get("vertical_offset", 0))
		vertical_offset = anim_metadata.get("vertical_offset", 0)

		sprite_frames.set_meta("horizontal_offset", anim_metadata.get("horizontal_offset", 0))
		horizontal_offset = anim_metadata.get("horizontal_offset", 0)
		animation.offset.x = horizontal_offset

		sprite_frames.set_meta("horizontal_offset_buddy", anim_metadata.get("horizontal_offset_buddy", 0))
		horizontal_offset_buddy = anim_metadata.get("horizontal_offset_buddy", 0)

		sprite_frames.set_meta("flip", anim_metadata.get("flip", false))
		set_facing(animation.flip_h)

	play_animation("idle")

func set_facing(to_left : bool):
	animation.flip_h = to_left
	if animation.sprite_frames.has_meta("flip") and animation.sprite_frames.get_meta("flip"):
		animation.flip_h = not animation.flip_h
	var offset_sign = 1 if to_left else -1
	animation.offset.x = horizontal_offset * offset_sign

func set_exceed(
		is_exceed : bool,
		image_loader: CardImageLoader = null,
		character_data: Dictionary = {},
		new_animation : String = ""):
	exceed_icon.visible = is_exceed
	var deck_id = str(character_data.get("id", ""))
	if deck_id:
		var skin_manager = get_node("/root/CharSkinManager")
		if skin_manager.exceed_changes_skin_for_deck_id(deck_id):
			var skin_animation_id = deck_id + "_exceed" if is_exceed else deck_id
			await load_character(image_loader, character_data, skin_animation_id, false)
			return
		if skin_manager.uses_skin_animation_for_deck_id(deck_id):
			return
	if new_animation:
		await load_character(image_loader, character_data, new_animation, false)

func get_size():
	if animation.sprite_frames == null or not animation.sprite_frames.has_animation("idle"):
		return Vector2.ZERO
	if animation.sprite_frames.get_frame_count("idle") == 0:
		return Vector2.ZERO
	var frame_texture := animation.sprite_frames.get_frame_texture("idle", 0)
	return frame_texture.get_size() if frame_texture != null else Vector2.ZERO

func set_buddy_id(id : String):
	buddy_id = id

func get_buddy_id():
	return buddy_id

func set_buddy_extra_offset(use_buddy_extra_offset_value : bool):
	use_buddy_extra_offset = use_buddy_extra_offset_value

func play_animation(named_animation : String):
	if animation.sprite_frames == null:
		return
	var animation_name := named_animation
	if not animation.sprite_frames.has_animation(animation_name):
		if animation_name == "run" or animation_name == "dash_back":
			animation_name = "walk_forward" if animation_name == "run" else "walk_backward"
	if not animation.sprite_frames.has_animation(animation_name):
		if animation.sprite_frames.has_animation("idle"):
			animation_name = "idle"
		else:
			return
	animation.play(animation_name)

func play_hit():
	current_position = position
	target_position = position
	remaining_animation_time = HitTime
	animation_state = AnimationState.AnimationState_Moving
	play_animation("hit")

func play_stunned():
	current_position = position
	target_position = position
	remaining_animation_time = HitTime
	animation_state = AnimationState.AnimationState_Moving
	play_animation("stunned")

func snap_to(pos : Vector2):
	position = pos
	current_position = pos
	target_position = pos
	remaining_animation_time = -1
	animation_state = AnimationState.AnimationState_Idle
	play_animation("idle")

func move_to(pos : Vector2, move_type : CharacterAnim):
	current_position = position
	target_position = pos
	remaining_animation_time = MoveTime
	animation_state = AnimationState.AnimationState_Moving
	var selected_func = animation_map[move_type]
	selected_func.call()

func finish_movement():
	if animation_state != AnimationState.AnimationState_Moving:
		return
	position = target_position
	current_position = target_position
	remaining_animation_time = -1
	animation_state = AnimationState.AnimationState_Idle
	play_animation("idle")

func _physics_process(delta):
	exceed_icon.rotation_degrees += 0.01 / delta
	if animation_state == AnimationState.AnimationState_Moving:
		remaining_animation_time -= delta
		if remaining_animation_time < 0:
			remaining_animation_time = -1
			animation_state = AnimationState.AnimationState_Idle
			position = target_position
			play_animation("idle")
		else:
			position = current_position.lerp(target_position, (MoveTime - remaining_animation_time) / MoveTime)
