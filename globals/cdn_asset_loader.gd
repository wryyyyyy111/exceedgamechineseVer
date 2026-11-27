class_name CdnAssetLoader
extends RefCounted

const CDN_ROOT := "https://cdn.exceedcntyd.com/"
const CDN_ASSET_ROOT := CDN_ROOT + "assets/"
const CDN_PHONE_ASSET_ROOT := CDN_ASSET_ROOT + "phone/"
const CDN_ASSET_CACHE_BUSTER := "mobile-layout-260905-1"
const ANIMATION_MANIFEST_PATH := "res://data/animation_resource_manifest.json"
const PHONE_OSS_SCALE_REPORT_PATH := "res://data/zoom_scale_ref.txt"
const PHONE_ASSET_SCALE_REPORTS := {
	"res://assets/phone/character_animations/": "res://assets/phone/character_animations/zoom_scale_ref.txt",
	"res://assets/phone/character_animations_custom/": "res://assets/phone/character_animations_custom/zoom_scale_ref.txt",
	"res://assets/phone/character_animations_skin/": "res://assets/phone/character_animations_skin/zoom_scale_ref.txt",
	"res://assets/phone/mainmenu_picture/": "res://assets/phone/mainmenu_picture/zoom_scale_ref.txt",
	"res://assets/phone/ui/": "res://assets/phone/ui/zoom_scale_ref.txt",
}
const CDN_MAPPED_ROOTS := [
	"res://assets/character_animations/",
	"res://assets/character_animations_custom/",
	"res://assets/character_animations_skin/",
	"res://assets/portraits/",
	"res://assets/portraits_custom/",
	"res://assets/portraits_skin/",
	"res://assets/mainmenu_picture/",
	"res://assets/ui/",
	"res://assets/phone/character_animations/",
	"res://assets/phone/character_animations_custom/",
	"res://assets/phone/character_animations_skin/",
	"res://assets/phone/portraits/",
	"res://assets/phone/portraits_custom/",
	"res://assets/phone/portraits_skin/",
	"res://assets/phone/mainmenu_picture/",
	"res://assets/phone/ui/",
]

static var loaded_textures := {}
static var texture_cache_entries := {}
static var loaded_text := {}
static var animation_resource_manifest := {}
static var animation_resource_manifest_loaded := false
static var phone_scale_report_entries_by_path := {}
static var phone_scale_reports_loaded := {}
static var cache_soft_limit_override_bytes := -1
static var cache_hard_limit_override_bytes := -1
static var _cache_access_serial := 0
const HTTP_TIMEOUT_SECONDS := 20.0
const DECODED_TEXTURE_BYTES_PER_PIXEL := 4
const MOBILE_CACHE_SOFT_LIMIT_BYTES := 96 * 1024 * 1024
const MOBILE_CACHE_HARD_LIMIT_BYTES := 160 * 1024 * 1024
const WEB_CACHE_SOFT_LIMIT_BYTES := 256 * 1024 * 1024
const WEB_CACHE_HARD_LIMIT_BYTES := 384 * 1024 * 1024
const NATIVE_CACHE_SOFT_LIMIT_BYTES := 384 * 1024 * 1024
const NATIVE_CACHE_HARD_LIMIT_BYTES := 640 * 1024 * 1024

static func is_cdn_mapped_res_path(resource_path: String) -> bool:
	for root_path in CDN_MAPPED_ROOTS:
		if resource_path.begins_with(root_path):
			return true
	return false

static func res_path_to_cdn_url(resource_path: String) -> String:
	var asset_url := ""
	if resource_path.begins_with("res://assets/phone/"):
		asset_url = CDN_PHONE_ASSET_ROOT + _encode_path(resource_path.trim_prefix("res://assets/phone/"))
	elif resource_path.begins_with("res://assets/"):
		asset_url = CDN_ASSET_ROOT + _encode_path(resource_path.trim_prefix("res://assets/"))
	else:
		return resource_path
	# Animation definitions and textures are deployed independently from the web
	# export. Version the request so a new export cannot reuse an old CDN object.
	return asset_url + "?v=" + CDN_ASSET_CACHE_BUSTER + "-" + GlobalSettings.ClientVersionString

static func load_texture(resource_path: String, owner := "CdnAssetLoader", priority := "visible", force_remote := false) -> Texture2D:
	if resource_path.is_empty():
		return null
	if not force_remote and ResourceLoader.exists(resource_path, "Texture2D"):
		var local_texture := load(resource_path) as Texture2D
		_register_texture_budget(resource_path, local_texture, owner, priority)
		return local_texture
	if not is_cdn_mapped_res_path(resource_path):
		return null
	var image_url := res_path_to_cdn_url(resource_path)
	if loaded_textures.has(image_url):
		_touch_texture_cache_entry(image_url, owner, priority)
		return loaded_textures[image_url]
	var image : Image = ImageCache.load_image(image_url)
	if image == null:
		image = await _download_image(image_url)
		if image != null:
			ImageCache.cache_image(image_url, image)
	if image == null:
		push_error("[CdnAssetLoader] Failed to load texture: %s" % image_url)
		return null
	var texture := ImageTexture.create_from_image(image)
	_cache_texture(image_url, texture, owner, priority)
	_register_texture_budget(image_url, texture, owner, priority)
	return texture

static func load_text(resource_path: String, force_remote := false, report_failure := true) -> String:
	if resource_path.is_empty():
		return ""
	if not force_remote and FileAccess.file_exists(resource_path):
		var local_file := FileAccess.open(resource_path, FileAccess.READ)
		return local_file.get_as_text() if local_file != null else ""
	if not force_remote and resource_path.ends_with("/animations.tres"):
		var manifest_text := _get_animation_manifest_text(resource_path)
		if not manifest_text.is_empty():
			return manifest_text
	if not is_cdn_mapped_res_path(resource_path):
		return ""
	var text_url := res_path_to_cdn_url(resource_path)
	if loaded_text.has(text_url):
		return loaded_text[text_url]
	var response := await _download_bytes(text_url, report_failure)
	if not response.get("success", false):
		if report_failure:
			push_error("[CdnAssetLoader] Failed to load text: %s" % text_url)
		loaded_text[text_url] = ""
		return ""
	var text := (response.get("body", PackedByteArray()) as PackedByteArray).get_string_from_utf8()
	loaded_text[text_url] = text
	return text

static func _get_animation_manifest_text(resource_path: String) -> String:
	_load_animation_resource_manifest()
	return str(animation_resource_manifest.get(resource_path, ""))

static func _load_animation_resource_manifest() -> void:
	if animation_resource_manifest_loaded:
		return
	animation_resource_manifest_loaded = true
	if not FileAccess.file_exists(ANIMATION_MANIFEST_PATH):
		push_error("[CdnAssetLoader] Missing animation manifest: %s" % ANIMATION_MANIFEST_PATH)
		return
	var manifest_file := FileAccess.open(ANIMATION_MANIFEST_PATH, FileAccess.READ)
	if manifest_file == null:
		return
	var parsed = JSON.parse_string(manifest_file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		animation_resource_manifest = parsed
	else:
		push_error("[CdnAssetLoader] Invalid animation manifest: %s" % ANIMATION_MANIFEST_PATH)

static func get_cached_texture(
		resource_path: String,
		owner := "CdnAssetLoader",
		priority := "visible") -> Texture2D:
	if resource_path.is_empty():
		return null
	if ResourceLoader.exists(resource_path, "Texture2D"):
		return load(resource_path) as Texture2D
	var image_url := res_path_to_cdn_url(resource_path)
	if loaded_textures.has(image_url):
		_touch_texture_cache_entry(image_url, owner, priority)
	return loaded_textures.get(image_url, null)

static func get_phone_texture_original_size(resource_path: String) -> Vector2i:
	var report_path := _get_phone_scale_report_path(resource_path)
	if report_path.is_empty():
		return Vector2i.ZERO
	_load_phone_scale_report(report_path)
	return phone_scale_report_entries_by_path.get(resource_path, {}).get("original_size", Vector2i.ZERO)

static func get_phone_texture_display_scale(resource_path: String) -> float:
	var report_path := _get_phone_scale_report_path(resource_path)
	if report_path.is_empty():
		return 1.0
	_load_phone_scale_report(report_path)
	return float(phone_scale_report_entries_by_path.get(resource_path, {}).get("scale", 1.0))

static func _get_phone_scale_report_path(resource_path: String) -> String:
	for phone_root in PHONE_ASSET_SCALE_REPORTS:
		if resource_path.begins_with(phone_root):
			return PHONE_ASSET_SCALE_REPORTS[phone_root]
	if resource_path.begins_with("res://assets/phone/decks_official/") or resource_path.begins_with("res://assets/phone/decks_custom/") or resource_path.begins_with("res://assets/phone/character_skin/"):
		return PHONE_OSS_SCALE_REPORT_PATH
	return ""

static func _load_phone_scale_report(report_path: String) -> void:
	if phone_scale_reports_loaded.get(report_path, false):
		return
	phone_scale_reports_loaded[report_path] = true
	var report_file := FileAccess.open(report_path, FileAccess.READ)
	if report_file == null:
		push_warning("[CdnAssetLoader] Missing phone scale report: %s" % report_path)
		return
	var resource_root := _get_phone_resource_root_for_report(report_path)
	if resource_root.is_empty():
		return
	for line in report_file.get_as_text().split("\n"):
		var columns: PackedStringArray = line.split("\t")
		if columns.size() < 5:
			continue
		var relative_path := _normalize_phone_report_path(columns[1])
		if relative_path.is_empty() or relative_path == "相对路径":
			continue
		var original_size := _parse_report_size(columns[2])
		if original_size == Vector2i.ZERO:
			continue
		phone_scale_report_entries_by_path[resource_root + relative_path] = {
			"original_size": original_size,
			"scale": columns[4].to_float(),
		}

static func _get_phone_resource_root_for_report(report_path: String) -> String:
	for phone_root in PHONE_ASSET_SCALE_REPORTS:
		if PHONE_ASSET_SCALE_REPORTS[phone_root] == report_path:
			return phone_root
	if report_path == PHONE_OSS_SCALE_REPORT_PATH:
		return "res://assets/phone/"
	return ""

static func _parse_report_size(size_text: String) -> Vector2i:
	var dimensions := size_text.strip_edges().to_lower().split("x")
	if dimensions.size() != 2:
		return Vector2i.ZERO
	var width := dimensions[0].to_int()
	var height := dimensions[1].to_int()
	return Vector2i(width, height) if width > 0 and height > 0 else Vector2i.ZERO

static func _normalize_phone_report_path(raw_path: String) -> String:
	var normalized := raw_path.strip_edges().replace("\\", "/")
	if normalized.begins_with("res://"):
		normalized = normalized.trim_prefix("res://")
		if normalized.begins_with("assets/phone/"):
			normalized = normalized.trim_prefix("assets/phone/")
	return normalized.trim_prefix("/")

static func clear_texture(resource_path: String):
	_erase_texture_cache_entry(resource_path)
	if is_cdn_mapped_res_path(resource_path):
		_erase_texture_cache_entry(res_path_to_cdn_url(resource_path))

static func clear_texture_prefix(resource_prefix: String):
	var cdn_prefix := res_path_to_cdn_url(resource_prefix)
	for texture_key in loaded_textures.keys():
		if str(texture_key).begins_with(resource_prefix) or str(texture_key).begins_with(cdn_prefix):
			_erase_texture_cache_entry(texture_key)

static func release_owner(owner: String, evict_unused := true):
	if owner.is_empty():
		return
	for texture_key in texture_cache_entries.keys():
		var entry: Dictionary = texture_cache_entries[texture_key]
		var owners: Dictionary = entry.get("owners", {})
		owners.erase(owner)
		entry["owners"] = owners
		texture_cache_entries[texture_key] = entry
		if evict_unused and owners.is_empty():
			_erase_texture_cache_entry(texture_key)

static func clear_all_textures():
	for texture_key in loaded_textures.keys():
		_erase_texture_cache_entry(texture_key)
	texture_cache_entries.clear()

static func get_texture_cache_estimated_bytes() -> int:
	var total := 0
	for entry in texture_cache_entries.values():
		total += int(entry.get("estimated_bytes", 0))
	return total

static func get_texture_cache_debug_info() -> Dictionary:
	return {
		"entries": loaded_textures.size(),
		"estimated_bytes": get_texture_cache_estimated_bytes(),
		"soft_limit_bytes": _get_cache_soft_limit_bytes(),
		"hard_limit_bytes": _get_cache_hard_limit_bytes(),
	}

static func trim_texture_cache():
	_trim_texture_cache("")

static func _cache_texture(
		texture_key: String,
		texture: Texture2D,
		owner: String,
		priority: String):
	if texture == null:
		return
	loaded_textures[texture_key] = texture
	_cache_access_serial += 1
	var owners := {}
	if not owner.is_empty():
		owners[owner] = true
	texture_cache_entries[texture_key] = {
		"estimated_bytes": _estimate_texture_bytes(texture),
		"last_access": _cache_access_serial,
		"owners": owners,
		"priority": priority,
	}
	_trim_texture_cache(texture_key)

static func _touch_texture_cache_entry(
		texture_key: String,
		owner: String,
		priority: String):
	if not loaded_textures.has(texture_key):
		return
	_cache_access_serial += 1
	var entry: Dictionary = texture_cache_entries.get(texture_key, {})
	if entry.is_empty():
		entry = {
			"estimated_bytes": _estimate_texture_bytes(loaded_textures[texture_key]),
			"owners": {},
		}
	var owners: Dictionary = entry.get("owners", {})
	if not owner.is_empty():
		owners[owner] = true
	entry["owners"] = owners
	entry["last_access"] = _cache_access_serial
	entry["priority"] = _higher_priority(str(entry.get("priority", "preview")), priority)
	texture_cache_entries[texture_key] = entry

static func _trim_texture_cache(protected_key: String):
	var total_bytes := get_texture_cache_estimated_bytes()
	var soft_limit := _get_cache_soft_limit_bytes()
	var hard_limit := _get_cache_hard_limit_bytes()
	if total_bytes <= soft_limit:
		return

	var candidates := texture_cache_entries.keys()
	candidates.sort_custom(func(left, right):
		var left_entry: Dictionary = texture_cache_entries[left]
		var right_entry: Dictionary = texture_cache_entries[right]
		var left_owned := not (left_entry.get("owners", {}) as Dictionary).is_empty()
		var right_owned := not (right_entry.get("owners", {}) as Dictionary).is_empty()
		if left_owned != right_owned:
			return not left_owned
		var left_priority := _priority_rank(str(left_entry.get("priority", "preview")))
		var right_priority := _priority_rank(str(right_entry.get("priority", "preview")))
		if left_priority != right_priority:
			return left_priority < right_priority
		return int(left_entry.get("last_access", 0)) < int(right_entry.get("last_access", 0))
	)

	for texture_key in candidates:
		if total_bytes <= soft_limit:
			break
		if str(texture_key) == protected_key:
			continue
		var entry: Dictionary = texture_cache_entries.get(texture_key, {})
		var is_owned := not (entry.get("owners", {}) as Dictionary).is_empty()
		if is_owned and total_bytes <= hard_limit:
			continue
		total_bytes -= int(entry.get("estimated_bytes", 0))
		_erase_texture_cache_entry(texture_key)

	if total_bytes > hard_limit and texture_cache_entries.has(protected_key):
		push_warning(
			"[CdnAssetLoader] Texture cache exceeds hard limit because the newly loaded texture alone is too large: %.1fMB"
			% (float(total_bytes) / 1024.0 / 1024.0))

static func _erase_texture_cache_entry(texture_key):
	loaded_textures.erase(texture_key)
	texture_cache_entries.erase(texture_key)
	MobileResourceBudget.unregister(str(texture_key))

static func _estimate_texture_bytes(texture: Texture2D) -> int:
	return maxi(0, texture.get_width()) * maxi(0, texture.get_height()) * DECODED_TEXTURE_BYTES_PER_PIXEL

static func _get_cache_soft_limit_bytes() -> int:
	if cache_soft_limit_override_bytes >= 0:
		return cache_soft_limit_override_bytes
	if MobileRuntimeFlags.is_mobile_resource_runtime():
		return MOBILE_CACHE_SOFT_LIMIT_BYTES
	if OS.has_feature("web"):
		return WEB_CACHE_SOFT_LIMIT_BYTES
	return NATIVE_CACHE_SOFT_LIMIT_BYTES

static func _get_cache_hard_limit_bytes() -> int:
	if cache_hard_limit_override_bytes >= 0:
		return cache_hard_limit_override_bytes
	if MobileRuntimeFlags.is_mobile_resource_runtime():
		return MOBILE_CACHE_HARD_LIMIT_BYTES
	if OS.has_feature("web"):
		return WEB_CACHE_HARD_LIMIT_BYTES
	return NATIVE_CACHE_HARD_LIMIT_BYTES

static func _priority_rank(priority: String) -> int:
	match priority:
		"critical":
			return 2
		"visible":
			return 1
		_:
			return 0

static func _higher_priority(current_priority: String, incoming_priority: String) -> String:
	return incoming_priority if _priority_rank(incoming_priority) > _priority_rank(current_priority) else current_priority

static func _download_image(image_url: String) -> Image:
	var response := await _download_bytes(image_url)
	if not response.get("success", false):
		return null
	var headers: PackedStringArray = response.get("headers", PackedStringArray())
	var body: PackedByteArray = response.get("body", PackedByteArray())
	var image := Image.new()
	var image_type := _detect_image_type(headers, body)
	var load_error := OK
	if image_type == "png":
		load_error = image.load_png_from_buffer(body)
	else:
		load_error = image.load_jpg_from_buffer(body)
	if load_error != OK:
		push_error("[CdnAssetLoader] Image decode failed error=%d url=%s" % [load_error, image_url])
		return null
	return image

static func _download_bytes(url: String, report_failure := true) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return {"success": false, "headers": PackedStringArray(), "body": PackedByteArray()}
	var request := HTTPRequest.new()
	request.timeout = HTTP_TIMEOUT_SECONDS
	print("[CdnAssetLoader] GET ", url)
	tree.root.call_deferred("add_child", request)
	await tree.process_frame
	if not is_instance_valid(request) or not request.is_inside_tree():
		push_error("[CdnAssetLoader] HTTP request node could not be added: %s" % url)
		return {"success": false, "headers": PackedStringArray(), "body": PackedByteArray()}
	var error := request.request(url)
	if error != OK:
		request.queue_free()
		if report_failure:
			push_error("[CdnAssetLoader] HTTP request failed to start (%d): %s" % [error, url])
		return {"success": false, "headers": PackedStringArray(), "body": PackedByteArray()}
	var result = await request.request_completed
	request.queue_free()
	var request_result: int = result[0]
	var response_code: int = result[1]
	var headers: PackedStringArray = result[2]
	var body: PackedByteArray = result[3]
	if request_result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		if report_failure:
			push_error("[CdnAssetLoader] HTTP failed result=%d status=%d url=%s" % [request_result, response_code, url])
		return {"success": false, "headers": headers, "body": body}
	return {"success": true, "headers": headers, "body": body}

static func _detect_image_type(headers: PackedStringArray, body: PackedByteArray) -> String:
	if body.size() >= 8 and body[0] == 0x89 and body[1] == 0x50 and body[2] == 0x4E and body[3] == 0x47:
		return "png"
	if body.size() >= 3 and body[0] == 0xFF and body[1] == 0xD8 and body[2] == 0xFF:
		return "jpg"
	for header in headers:
		var header_lower := header.to_lower()
		if header_lower.begins_with("content-type"):
			if "png" in header_lower:
				return "png"
			if "jpeg" in header_lower or "jpg" in header_lower:
				return "jpg"
	return "jpg"

static func _encode_path(path: String) -> String:
	var segments := path.split("/", false)
	var encoded_segments := []
	for segment in segments:
		encoded_segments.append(segment.uri_encode())
	return "/".join(encoded_segments)

static func _register_texture_budget(resource_key: String, texture: Texture2D, owner: String, priority: String):
	if texture == null:
		return
	MobileResourceBudget.register_texture(
		resource_key,
		int(texture.get_width()),
		int(texture.get_height()),
		owner,
		priority)
