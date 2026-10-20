class_name CardImageLoader
extends Node2D

var loaded_images = {}
var phone_cached_slice_signature_by_url = {}
var phone_debug_dumped_urls = {}
var image_load_queue = []
var image_load_atlas_map = {}
var image_load_requested_indices = {}
var processing_queue = false
var test_mode : bool = false
var http_request : HTTPRequest
var is_tearing_down : bool = false
var defer_registered_card_images : bool = false
var lazy_multi_card_textures : bool = false

const RuntimeImageResizerScript = preload("res://globals/runtime_image_resizer.gd")

signal finished_loading_image(image)
signal image_queue_advanced

const CARD_WIDTH = 750.0
const CARD_HEIGHT = 1024.0
const ATLAS_DIMENSION_TOLERANCE = 8
const HTTP_TIMEOUT_SECONDS := 20.0
const CDN_IMAGE_ROOT := "https://cdn.exceedcntyd.com/"
const CDN_PHONE_IMAGE_ROOT := CDN_IMAGE_ROOT + "phone/"
const PHONE_SCALE_REPORT_PATH := "res://data/zoom_scale_ref.txt"
const PHONE_CARD_GRID_RULES_PATH := "res://data/phone_card_grid_rules.json"
const PHONE_DEBUG_DUMP_DIR := "user://phone_slice_debug"
const PHONE_DEBUG_DUMP_MAX_TILES := 24

var runtime_card_scale : float = -1.0
var phone_image_scale_by_path : Dictionary = {}
var phone_image_output_size_by_path : Dictionary = {}
var phone_image_original_size_by_path : Dictionary = {}
var phone_image_scale_report_loaded := false
var phone_card_grid_rules: Dictionary = {}
var phone_card_grid_rules_loaded := false

func _get_effective_mobile_card_scale() -> float:
	return 1.0

func _is_mobile_web() -> bool:
	return MobileRuntimeFlags.is_mobile_resource_runtime()

func _is_phone_cdn_url(image_url: String) -> bool:
	return image_url.begins_with(CDN_PHONE_IMAGE_ROOT)

func _get_target_card_size() -> Vector2i:
	return Vector2i(
		int(round(CARD_WIDTH)),
		int(round(CARD_HEIGHT))
	)

func _get_scaled_card_size(card_width : float, card_height : float, _scale_override : float = -1.0) -> Vector2i:
	return Vector2i(
		maxi(1, int(round(card_width))),
		maxi(1, int(round(card_height))))

func set_runtime_card_scale(scale_factor : float):
	runtime_card_scale = maxf(scale_factor, 0.1)

func _should_resize_single_card_for_runtime(image_atlas_details, _loaded_image: Image) -> bool:
	var is_season7 = image_atlas_details.get('season', 0) == 7
	var is_season6 = image_atlas_details.get('season', 0) == 6
	var is_season1 = image_atlas_details.get('season', 0) == 1
	if is_season1 or is_season6 or is_season7:
		return true
	return false

func _should_avoid_full_atlas_texture(image_atlas_details, _loaded_image: Image) -> bool:
	if _is_phone_cdn_url(str(image_atlas_details.get("url", ""))) and image_atlas_details.get('multiple_cards', false):
		return true
	if _is_mobile_web() and image_atlas_details.get('multiple_cards', false):
		return true
	var is_season7 = image_atlas_details.get('season', 0) == 7
	var is_season6 = image_atlas_details.get('season', 0) == 6
	var is_season1 = image_atlas_details.get('season', 0) == 1
	if is_season1 or is_season6 or is_season7:
		return true
	if image_atlas_details.get('recalculate_card_sizes', false):
		return true
	return false

func _create_card_texture_from_image(source_image: Image, _target_size := Vector2i.ZERO) -> Texture2D:
	return ImageTexture.create_from_image(source_image)

func _get_scaled_mobile_atlas_size(source_image: Image) -> Vector2i:
	var scale_factor = _get_effective_mobile_card_scale()
	return Vector2i(
		max(1, int(round(source_image.get_width() * scale_factor))),
		max(1, int(round(source_image.get_height() * scale_factor))))

func _get_scaled_mobile_atlas_layout(grid_w: int, grid_h: int, card_width: float, card_height: float, offset_x: int, offset_y: int) -> Dictionary:
	var scale_factor = _get_effective_mobile_card_scale()
	var scaled_offset_x = int(round(offset_x * scale_factor))
	var scaled_offset_y = int(round(offset_y * scale_factor))
	var scaled_card_width = max(1, int(round(card_width * scale_factor)))
	var scaled_card_height = max(1, int(round(card_height * scale_factor)))
	return {
		"offset_x": scaled_offset_x,
		"offset_y": scaled_offset_y,
		"card_width": scaled_card_width,
		"card_height": scaled_card_height,
		"atlas_size": Vector2i(
			scaled_offset_x + grid_w * scaled_card_width,
			scaled_offset_y + grid_h * scaled_card_height)
	}

func _should_use_scaled_mobile_atlas_texture(image_atlas_details, _source_image: Image) -> bool:
	if lazy_multi_card_textures or not _is_mobile_web() or not image_atlas_details.get('multiple_cards', false):
		return false
	return false

func _normalize_image_url(raw_url: String) -> String:
	if raw_url.begins_with("http://"):
		raw_url = "https://" + raw_url.trim_prefix("http://")
	if _is_mobile_web() and raw_url.begins_with(CDN_IMAGE_ROOT) and not raw_url.begins_with(CDN_PHONE_IMAGE_ROOT):
		return CDN_PHONE_IMAGE_ROOT + raw_url.trim_prefix(CDN_IMAGE_ROOT)
	return raw_url

func _get_phone_image_scale(image_url: String) -> float:
	if not _is_phone_cdn_url(image_url):
		return 1.0
	_load_phone_image_scale_report()
	var report_path := _resolve_phone_report_path_alias(image_url.trim_prefix(CDN_PHONE_IMAGE_ROOT))
	return phone_image_scale_by_path.get(report_path, 1.0)

func _get_phone_image_output_size(image_url: String) -> Vector2i:
	if not _is_phone_cdn_url(image_url):
		return Vector2i.ZERO
	_load_phone_image_scale_report()
	var report_path := _resolve_phone_report_path_alias(image_url.trim_prefix(CDN_PHONE_IMAGE_ROOT))
	return phone_image_output_size_by_path.get(report_path, Vector2i.ZERO)

func _get_phone_image_original_size(image_url: String) -> Vector2i:
	if not _is_phone_cdn_url(image_url):
		return Vector2i.ZERO
	_load_phone_image_scale_report()
	var report_path := _resolve_phone_report_path_alias(image_url.trim_prefix(CDN_PHONE_IMAGE_ROOT))
	return phone_image_original_size_by_path.get(report_path, Vector2i.ZERO)

func _resolve_phone_report_path_alias(resource_path: String) -> String:
	if (
		phone_image_scale_by_path.has(resource_path)
		or phone_image_output_size_by_path.has(resource_path)
		or phone_image_original_size_by_path.has(resource_path)
	):
		return resource_path
	if resource_path.contains("/byakuya/"):
		var by_alias := resource_path.replace("/byakuya/", "/bayakuya/")
		if (
			phone_image_scale_by_path.has(by_alias)
			or phone_image_output_size_by_path.has(by_alias)
			or phone_image_original_size_by_path.has(by_alias)
		):
			return by_alias
	if resource_path.contains("/bayakuya/"):
		var ba_alias := resource_path.replace("/bayakuya/", "/byakuya/")
		if (
			phone_image_scale_by_path.has(ba_alias)
			or phone_image_output_size_by_path.has(ba_alias)
			or phone_image_original_size_by_path.has(ba_alias)
		):
			return ba_alias
	return resource_path

func _parse_report_size(size_text: String) -> Vector2i:
	var cleaned := size_text.strip_edges().to_lower()
	if cleaned.is_empty() or not cleaned.contains("x"):
		return Vector2i.ZERO
	var parts := cleaned.split("x")
	if parts.size() != 2:
		return Vector2i.ZERO
	var parsed_width := parts[0].to_int()
	var parsed_height := parts[1].to_int()
	if parsed_width <= 0 or parsed_height <= 0:
		return Vector2i.ZERO
	return Vector2i(parsed_width, parsed_height)

func _load_phone_card_grid_rules():
	if phone_card_grid_rules_loaded:
		return
	phone_card_grid_rules_loaded = true
	var rules_file := FileAccess.open(PHONE_CARD_GRID_RULES_PATH, FileAccess.READ)
	if rules_file == null:
		push_warning("[CardImageLoader] 未找到 phone 切图规则配置: %s" % PHONE_CARD_GRID_RULES_PATH)
		return
	var parsed = JSON.parse_string(rules_file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[CardImageLoader] phone 切图规则配置格式错误: %s" % PHONE_CARD_GRID_RULES_PATH)
		return
	phone_card_grid_rules = parsed

func _get_grid_from_rule(rule_data: Dictionary, fallback_grid_w: int = 0, fallback_grid_h: int = 0) -> Dictionary:
	var grid_w := int(rule_data.get("grid_w", fallback_grid_w))
	var grid_h := int(rule_data.get("grid_h", fallback_grid_h))
	if grid_w <= 0 or grid_h <= 0:
		return {}
	return {
		"grid_w": grid_w,
		"grid_h": grid_h,
	}

func _get_runtime_deck_id(image_atlas_details: Dictionary) -> String:
	var asset_deck_id := str(image_atlas_details.get("asset_deck_id", "")).to_lower()
	if not asset_deck_id.is_empty():
		return asset_deck_id
	return str(image_atlas_details.get("deck_id", "")).to_lower()

func _get_phone_expected_grid_from_config(image_atlas_details: Dictionary, image_url: String) -> Dictionary:
	_load_phone_card_grid_rules()
	if phone_card_grid_rules.is_empty():
		return {}

	var resource_path := image_url.trim_prefix(CDN_PHONE_IMAGE_ROOT)
	var file_name := resource_path.get_file().to_lower()
	var global_path_rules = phone_card_grid_rules.get("path_rules", [])
	if typeof(global_path_rules) == TYPE_ARRAY:
		for path_rule_variant in global_path_rules:
			if typeof(path_rule_variant) != TYPE_DICTIONARY:
				continue
			var path_rule: Dictionary = path_rule_variant
			var path_prefix := str(path_rule.get("path_begins_with", "")).to_lower()
			if path_prefix.is_empty() or not resource_path.to_lower().begins_with(path_prefix):
				continue
			var rule_image_name := str(path_rule.get("image_name", "")).to_lower()
			if not rule_image_name.is_empty() and str(image_atlas_details.get("image_name", "")).to_lower() != rule_image_name:
				continue
			var contains_keyword := str(path_rule.get("contains", "")).to_lower()
			var not_contains_keyword := str(path_rule.get("not_contains", "")).to_lower()
			if not contains_keyword.is_empty() and not file_name.contains(contains_keyword):
				continue
			if not not_contains_keyword.is_empty() and file_name.contains(not_contains_keyword):
				continue
			var path_grid := _get_grid_from_rule(path_rule)
			if not path_grid.is_empty():
				return path_grid

	var seasons_data = phone_card_grid_rules.get("seasons", {})
	if typeof(seasons_data) != TYPE_DICTIONARY:
		return {}

	var season := int(image_atlas_details.get("season", 0))
	var season_rule = seasons_data.get(str(season), {})
	if typeof(season_rule) != TYPE_DICTIONARY:
		return {}

	var deck_id := _get_runtime_deck_id(image_atlas_details)

	var base_grid := _get_grid_from_rule(season_rule.get("default", {}))
	if base_grid.is_empty():
		return {}

	var file_rules = season_rule.get("file_rules", [])
	if typeof(file_rules) == TYPE_ARRAY:
		for file_rule_variant in file_rules:
			if typeof(file_rule_variant) != TYPE_DICTIONARY:
				continue
			var file_rule: Dictionary = file_rule_variant
			var rule_image_name := str(file_rule.get("image_name", "")).to_lower()
			if not rule_image_name.is_empty() and str(image_atlas_details.get("image_name", "")).to_lower() != rule_image_name:
				continue
			var contains_keyword := str(file_rule.get("contains", "")).to_lower()
			var not_contains_keyword := str(file_rule.get("not_contains", "")).to_lower()
			if not contains_keyword.is_empty() and not file_name.contains(contains_keyword):
				continue
			if not not_contains_keyword.is_empty() and file_name.contains(not_contains_keyword):
				continue
			var file_grid := _get_grid_from_rule(file_rule, int(base_grid["grid_w"]), int(base_grid["grid_h"]))
			if not file_grid.is_empty():
				base_grid = file_grid
				break

	var deck_overrides = season_rule.get("deck_overrides", {})
	if typeof(deck_overrides) == TYPE_DICTIONARY and deck_overrides.has(deck_id):
		var deck_rule_variant = deck_overrides[deck_id]
		if typeof(deck_rule_variant) == TYPE_DICTIONARY:
			var deck_rule: Dictionary = deck_rule_variant
			var deck_grid := _get_grid_from_rule(deck_rule, int(base_grid["grid_w"]), int(base_grid["grid_h"]))
			if not deck_grid.is_empty():
				base_grid = deck_grid
			var deck_file_rules = deck_rule.get("file_rules", [])
			if typeof(deck_file_rules) == TYPE_ARRAY:
				for deck_file_rule_variant in deck_file_rules:
					if typeof(deck_file_rule_variant) != TYPE_DICTIONARY:
						continue
					var deck_file_rule: Dictionary = deck_file_rule_variant
					var rule_image_name := str(deck_file_rule.get("image_name", "")).to_lower()
					if not rule_image_name.is_empty() and str(image_atlas_details.get("image_name", "")).to_lower() != rule_image_name:
						continue
					var contains_keyword := str(deck_file_rule.get("contains", "")).to_lower()
					var not_contains_keyword := str(deck_file_rule.get("not_contains", "")).to_lower()
					if not contains_keyword.is_empty() and not file_name.contains(contains_keyword):
						continue
					if not not_contains_keyword.is_empty() and file_name.contains(not_contains_keyword):
						continue
					var deck_file_grid := _get_grid_from_rule(deck_file_rule, int(base_grid["grid_w"]), int(base_grid["grid_h"]))
					if not deck_file_grid.is_empty():
						base_grid = deck_file_grid
						break

	return base_grid

func _get_phone_expected_grid(image_atlas_details: Dictionary, image_url: String) -> Dictionary:
	if not _is_phone_cdn_url(image_url):
		return {}
	if not image_atlas_details.get("multiple_cards", false):
		return {}
	var season := int(image_atlas_details.get("season", 0))
	var image_name := str(image_atlas_details.get("image_name", "")).to_lower()
	var deck_id := _get_runtime_deck_id(image_atlas_details)
	var resource_path := image_url.trim_prefix(CDN_PHONE_IMAGE_ROOT)
	var file_name := resource_path.get_file().to_lower()
	var is_skin_resource := resource_path.begins_with("character_skin/") or resource_path.begins_with("decks_skin/")
	var configured_grid := _get_phone_expected_grid_from_config(image_atlas_details, image_url)
	if not configured_grid.is_empty():
		return configured_grid
	# S2 官方部分角色会把 normals 复用到 specials 合图。
	# 仅在没有显式角色/资源规则时，对 normals->specials 合图使用 4x5。
	if season == 2 and not is_skin_resource and image_name == "normals" and file_name.contains("special"):
		return {
			"grid_w": 4,
			"grid_h": 5,
		}
	match season:
		7:
			return {
				"grid_w": 6,
				"grid_h": 3 if deck_id in ["happychaos", "jacko", "may", "nago", "testament"] else 4,
			}
		6:
			return {
				"grid_w": 4,
				"grid_h": 2,
			}
		5:
			return {
				"grid_w": 4,
				"grid_h": 5,
			}
		4:
			return {
				"grid_w": 4,
				"grid_h": 4,
			}
		3:
			return {
				"grid_w": 4,
				"grid_h": 2,
			}
		2:
			# S2 部分角色将 normals/specials 复用到同一张 specials 合图（索引可达 14+），
			# phone 端必须按 4x5 切图，否则会出现第二排起点错位与索引越界重切。
			if file_name.contains("special") and image_name in ["normals", "specials"]:
				return {
					"grid_w": 4,
					"grid_h": 5,
				}
			if file_name.contains("normals") and not file_name.contains("special"):
				return {
					"grid_w": 4,
					"grid_h": 3,
				}
			return {
				"grid_w": 4,
				"grid_h": 2,
			}
		1:
			return {
				"grid_w": 4,
				"grid_h": 2,
			}
		0:
			return {
				"grid_w": 4,
				"grid_h": 2,
			}

	return {}

func _should_use_phone_top_aligned_vertical_trim(image_atlas_details: Dictionary, image_url: String, grid_h_override: int) -> bool:
	if not _is_phone_cdn_url(image_url):
		return false
	var resource_path := image_url.trim_prefix(CDN_PHONE_IMAGE_ROOT)
	var is_skin_resource := resource_path.begins_with("character_skin/") or resource_path.begins_with("decks_skin/")
	if int(image_atlas_details.get("season", 0)) != 2 and not is_skin_resource:
		return false
	var image_name := str(image_atlas_details.get("image_name", "")).to_lower()
	if not (image_name in ["normals", "specials"]):
		return false
	var file_name := resource_path.get_file().to_lower()
	if is_skin_resource:
		# 皮肤资源统一复用 S2 定位策略：纵向裁边按顶对齐处理。
		return file_name.contains("normal") or file_name.contains("special")
	if grid_h_override < 5:
		return false
	return image_name == "normals" and file_name.contains("special")

func _load_phone_image_scale_report():
	if phone_image_scale_report_loaded:
		return
	phone_image_scale_report_loaded = true
	var report_file := FileAccess.open(PHONE_SCALE_REPORT_PATH, FileAccess.READ)
	if report_file == null:
		push_warning("[CardImageLoader] 未找到移动端缩放比例报告: %s" % PHONE_SCALE_REPORT_PATH)
		return
	while not report_file.eof_reached():
		var columns: PackedStringArray = report_file.get_line().split("\t")
		if columns.size() < 5:
			continue
		var report_path := _normalize_phone_report_path(columns[1])
		if report_path.is_empty() or report_path == "相对路径":
			continue
		var image_scale: float = columns[4].to_float()
		if image_scale > 0.0:
			phone_image_scale_by_path[report_path] = image_scale
		if columns.size() >= 3:
			var original_size := _parse_report_size(columns[2])
			if original_size != Vector2i.ZERO:
				phone_image_original_size_by_path[report_path] = original_size
		if columns.size() >= 4:
			var output_size := _parse_report_size(columns[3])
			if output_size != Vector2i.ZERO:
				phone_image_output_size_by_path[report_path] = output_size

func _normalize_phone_report_path(raw_path: String) -> String:
	var normalized := raw_path.strip_edges().replace("\\", "/")
	if normalized.begins_with("res://"):
		normalized = normalized.trim_prefix("res://")
		if normalized.begins_with("assets/phone/"):
			normalized = normalized.trim_prefix("assets/phone/")
	return normalized.trim_prefix("/")

func _detect_image_type(headers, body: PackedByteArray) -> String:
	if body.size() >= 8 and body[0] == 0x89 and body[1] == 0x50 and body[2] == 0x4E and body[3] == 0x47 and body[4] == 0x0D and body[5] == 0x0A and body[6] == 0x1A and body[7] == 0x0A:
		return "png"
	if body.size() >= 3 and body[0] == 0xFF and body[1] == 0xD8 and body[2] == 0xFF:
		return "jpg"

	for header in headers:
		var header_lower = header.to_lower()
		if header_lower.begins_with("content-type"):
			print("[CardImageLoader] Content-Type: ", header)
			var mime_part = header_lower.split("/")[-1].split(";")[0].strip_edges()
			if mime_part == "png":
				return "png"
			if mime_part in ["jpeg", "jpg"]:
				return "jpg"
			break

	return "jpg"

func _init(testing_mode = false):
	test_mode = testing_mode
	http_request = HTTPRequest.new()
	http_request.timeout = HTTP_TIMEOUT_SECONDS
	add_child(http_request)
	http_request.request_completed.connect(self._image_request_completed)

func teardown():
	is_tearing_down = true
	MobileResourceBudget.unregister_owner(_get_budget_owner())
	image_load_queue.clear()
	image_load_atlas_map.clear()
	image_load_requested_indices.clear()
	loaded_images.clear()
	phone_cached_slice_signature_by_url.clear()
	phone_debug_dumped_urls.clear()
	processing_queue = false
	finished_loading_image.emit(null)
	image_queue_advanced.emit()
	if http_request:
		http_request.cancel_request()
		if http_request.request_completed.is_connected(self._image_request_completed):
			http_request.request_completed.disconnect(self._image_request_completed)
		http_request.queue_free()
		http_request = null

func _process(_delta):
	if is_tearing_down:
		return
	if not processing_queue and len(image_load_queue) > 0:
		_process_request_queue()

func _register_requested_index(image_url : String, image_index : int):
	if image_url not in image_load_requested_indices:
		image_load_requested_indices[image_url] = {}
	image_load_requested_indices[image_url][image_index] = true

func _should_rebuild_phone_cached_slices(image_url: String, image_atlas_details: Dictionary) -> bool:
	if not _is_phone_cdn_url(image_url):
		return false
	if not image_atlas_details.get("multiple_cards", false):
		return false
	if image_url not in loaded_images:
		return false
	var cached = loaded_images[image_url]
	if cached == null:
		return false
	var expected_grid := _get_phone_expected_grid(image_atlas_details, image_url)
	if expected_grid.is_empty():
		return false
	var expected_count := int(expected_grid.get("grid_w", 0)) * int(expected_grid.get("grid_h", 0))
	if expected_count <= 0:
		return false
	if cached.size() != expected_count:
		print("[CardImageLoader] phone 缓存切片数量不匹配，触发重切。URL: %s，cached=%d，expected=%d" % [image_url, cached.size(), expected_count])
		return true
	var expected_signature := _build_phone_slice_signature(image_url, image_atlas_details, expected_grid)
	if not expected_signature.is_empty():
		var cached_signature := str(phone_cached_slice_signature_by_url.get(image_url, ""))
		if cached_signature.is_empty():
			print("[CardImageLoader] phone 缓存缺少切图签名，触发重切。URL: %s" % image_url)
			return true
		if cached_signature != expected_signature:
			print("[CardImageLoader] phone 缓存签名变化，触发重切。URL: %s，old=%s，new=%s" % [image_url, cached_signature, expected_signature])
			return true
	for texture in cached:
		# phone 多图必须使用裁切后的独立纹理，避免旧 AtlasTexture 浮点采样错位。
		if texture is AtlasTexture:
			print("[CardImageLoader] phone 缓存含 AtlasTexture，触发重切。URL: %s" % image_url)
			return true
	return false

func _build_phone_slice_signature(image_url: String, image_atlas_details: Dictionary, expected_grid: Dictionary = {}) -> String:
	if not _is_phone_cdn_url(image_url):
		return ""
	if not image_atlas_details.get("multiple_cards", false):
		return ""
	var grid := expected_grid
	if grid.is_empty():
		grid = _get_phone_expected_grid(image_atlas_details, image_url)
	if grid.is_empty():
		return ""
	var season := int(image_atlas_details.get("season", 0))
	var deck_id := _get_runtime_deck_id(image_atlas_details)
	var image_name := str(image_atlas_details.get("image_name", ""))
	var output_size := _get_phone_image_output_size(image_url)
	var original_size := _get_phone_image_original_size(image_url)
	var report_scale := _get_phone_image_scale(image_url)
	return "%d|%s|%s|%dx%d|%dx%d|%dx%d|%.6f" % [
		season,
		deck_id,
		image_name,
		int(grid.get("grid_w", 0)),
		int(grid.get("grid_h", 0)),
		output_size.x,
		output_size.y,
		original_size.x,
		original_size.y,
		report_scale,
	]

func _sanitize_debug_file_name(file_name: String) -> String:
	var sanitized := file_name
	for token in ["/", "\\", ":", "?", "*", "\"", "<", ">", "|"]:
		sanitized = sanitized.replace(token, "_")
	return sanitized

func _maybe_dump_phone_slice_tile(image_url: String, image_index: int, cropped: Image):
	if not OS.is_debug_build():
		return
	if cropped == null or cropped.is_empty():
		return
	if image_index < 0 or image_index >= PHONE_DEBUG_DUMP_MAX_TILES:
		return
	var dump_key := "%s|%d" % [image_url, image_index]
	if phone_debug_dumped_urls.get(dump_key, false):
		return
	var err := DirAccess.make_dir_recursive_absolute(PHONE_DEBUG_DUMP_DIR)
	if err != OK:
		return
	var rel_path := image_url.trim_prefix(CDN_PHONE_IMAGE_ROOT)
	if rel_path == image_url:
		rel_path = image_url.trim_prefix(CDN_IMAGE_ROOT)
	var safe_rel_path := _sanitize_debug_file_name(rel_path)
	var output_path := "%s/%s_idx%02d.png" % [PHONE_DEBUG_DUMP_DIR, safe_rel_path, image_index]
	err = cropped.save_png(output_path)
	if err == OK:
		phone_debug_dumped_urls[dump_key] = true
		if image_index == 0:
			print("[CardImageLoader] phone 调试切片已导出到: %s（最多前%d张）" % [PHONE_DEBUG_DUMP_DIR, PHONE_DEBUG_DUMP_MAX_TILES])

static func merge_image_atlas_details(existing_details: Dictionary, incoming_details: Dictionary) -> Dictionary:
	var merged_details = existing_details.duplicate(true)
	for key in incoming_details.keys():
		var incoming_value = incoming_details[key]
		if not merged_details.has(key):
			merged_details[key] = incoming_value
			continue

		if key == "multiple_cards":
			merged_details[key] = merged_details[key] or incoming_value
			continue
		if key == "force_cropped_textures":
			merged_details[key] = merged_details[key] or incoming_value
			continue

		var existing_value = merged_details[key]
		if existing_value == null:
			merged_details[key] = incoming_value
		elif typeof(existing_value) == TYPE_STRING and existing_value == "":
			merged_details[key] = incoming_value
		elif typeof(existing_value) == TYPE_BOOL and not existing_value and incoming_value != false:
			merged_details[key] = incoming_value
		elif typeof(existing_value) == TYPE_INT and existing_value == 0 and incoming_value != 0:
			merged_details[key] = incoming_value
	return merged_details

static func should_materialize_all_multi_card_textures(_mobile_web_runtime: bool, _image_atlas_details: Dictionary) -> bool:
	return false

static func should_create_atlas_texture(requested_indices : Dictionary, image_index : int) -> bool:
	return requested_indices.has(-1) or requested_indices.has(image_index)

static func should_yield_after_atlas_texture(
		_mobile_web_runtime : bool, _image_atlas_details : Dictionary, _image_index : int) -> bool:
	return false

static func _is_integer_like(value: float, epsilon: float = 0.001) -> bool:
	return absf(value - round(value)) <= epsilon

static func try_trim_edges_for_divisible_grid(
		region_width: int,
		region_height: int,
		card_width: float,
		card_height: float,
		max_trim_px: int = ATLAS_DIMENSION_TOLERANCE) -> Dictionary:
	var result := {
		"trimmed": false,
		"region_width": region_width,
		"region_height": region_height,
		"grid_width": float(region_width) / card_width if card_width > 0.0 else 0.0,
		"grid_height": float(region_height) / card_height if card_height > 0.0 else 0.0,
		"trim_right": 0,
		"trim_bottom": 0,
	}
	if card_width <= 0.0 or card_height <= 0.0:
		return result

	var grid_w_floor := int(floor(float(region_width) / card_width))
	var grid_h_floor := int(floor(float(region_height) / card_height))
	if grid_w_floor <= 0 or grid_h_floor <= 0:
		return result

	var target_region_width := int(floor(grid_w_floor * card_width))
	var target_region_height := int(floor(grid_h_floor * card_height))
	var trim_right := region_width - target_region_width
	var trim_bottom := region_height - target_region_height

	if trim_right < 0 or trim_bottom < 0:
		return result
	if trim_right == 0 and trim_bottom == 0:
		return result
	if trim_right > max_trim_px or trim_bottom > max_trim_px:
		return result

	result["trimmed"] = true
	result["region_width"] = target_region_width
	result["region_height"] = target_region_height
	result["grid_width"] = float(grid_w_floor)
	result["grid_height"] = float(grid_h_floor)
	result["trim_right"] = trim_right
	result["trim_bottom"] = trim_bottom
	return result

static func get_latest_image_atlas_details(
		atlas_map : Dictionary, image_url : String, fallback : Dictionary) -> Dictionary:
	return atlas_map.get(image_url, fallback)

# Loads card images if they haven't yet been accessed
func load_image_page(image_atlas):
	load_image_page_indexed(image_atlas, -1)

func ensure_image_page(image_atlas) -> bool:
	if test_mode:
		return true
	if is_tearing_down:
		return false
	load_image_page(image_atlas)
	var image_url = _normalize_image_url(image_atlas['url'])
	while image_url not in loaded_images:
		if is_tearing_down:
			return false
		await image_queue_advanced
	var image_set = loaded_images[image_url]
	return image_set != null and not image_set.is_empty()

func invalidate_loaded_image(image_url : String):
	image_url = _normalize_image_url(image_url)
	loaded_images.erase(image_url)
	phone_cached_slice_signature_by_url.erase(image_url)

func load_image_page_indexed(image_atlas, image_index : int):
	if test_mode or is_tearing_down:
		return

	var image_url = _normalize_image_url(image_atlas['url'])
	var normalized_image_atlas = image_atlas.duplicate(true)
	normalized_image_atlas['url'] = image_url
	normalized_image_atlas['phone_image_scale'] = _get_phone_image_scale(image_url)
	_register_requested_index(image_url, image_index)

	if image_url in image_load_atlas_map:
		image_load_atlas_map[image_url] = merge_image_atlas_details(image_load_atlas_map[image_url], normalized_image_atlas)
	else:
		image_load_atlas_map[image_url] = normalized_image_atlas

	if _should_rebuild_phone_cached_slices(image_url, image_load_atlas_map[image_url]):
		loaded_images.erase(image_url)
		phone_cached_slice_signature_by_url.erase(image_url)
		phone_debug_dumped_urls.clear()
		ImageCache.release_image(image_url)

	var requested_texture_missing = false
	if image_url in loaded_images and loaded_images[image_url] != null and image_index >= 0:
		var loaded_texture_set = loaded_images[image_url]
		requested_texture_missing = image_index >= loaded_texture_set.size() or loaded_texture_set[image_index] == null
	if (image_url not in loaded_images or requested_texture_missing) and image_url not in image_load_queue:
		image_load_queue.append(image_url)

func _process_request_queue():
	if is_tearing_down or image_load_queue.is_empty():
		return
	processing_queue = true
	var image_url = image_load_queue[0]
	print("[CardImageLoader] 开始加载: ", image_url)
	var image_atlas_details = image_load_atlas_map[image_url]

	var loaded_image = ImageCache.load_image(image_url)
	if not loaded_image: # not found in cache; send http request
		print("[CardImageLoader] 缓存未命中，发送 HTTP 请求: ", image_url)
		var error = http_request.request(image_url)
		if error != OK:
			push_error("[CardImageLoader] HTTP 请求发起失败，错误码 %d，URL: %s" % [error, image_url])
			loaded_images[image_url] = null
			image_load_queue.pop_at(0)
			processing_queue = false
			image_queue_advanced.emit()
			return
		loaded_image = await finished_loading_image
		if is_tearing_down:
			return
		if loaded_image:
			print("[CardImageLoader] 图片下载成功，尺寸: %dx%d，URL: %s" % [loaded_image.get_width(), loaded_image.get_height(), image_url])
			_register_loaded_image_budget(image_url, loaded_image, image_atlas_details)
			ImageCache.cache_image(image_url, loaded_image)
		else:
			push_error("[CardImageLoader] 图片解码失败，URL: " + image_url)
	else:
		print("[CardImageLoader] 从缓存加载成功: ", image_url)
		if loaded_image:
			_register_loaded_image_budget(image_url, loaded_image, image_atlas_details)

	# HTTP 等待期间，同 URL 的后续请求可能补齐 season、image_name 和裁切策略。
	# merge_image_atlas_details 会替换 map 中的 Dictionary，因此必须重新获取最新对象。
	image_atlas_details = get_latest_image_atlas_details(
			image_load_atlas_map, image_url, image_atlas_details)
	var is_multiple = image_atlas_details['multiple_cards']

	var image_texture = null
	if loaded_image:
		var is_season7 = image_atlas_details.get('season', 0) == 7
		var is_season6 = image_atlas_details.get('season', 0) == 6
		var is_season1 = image_atlas_details.get('season', 0) == 1
		var target_card_size = _get_target_card_size()
		if not is_multiple and _should_resize_single_card_for_runtime(image_atlas_details, loaded_image):
			loaded_image = RuntimeImageResizerScript.resize_in_place(loaded_image, target_card_size.x, target_card_size.y)
			print("[CardImageLoader] 单卡缩放至 %dx%d，URL: %s" % [target_card_size.x, target_card_size.y, image_url])
		if is_multiple:
			var card_width = CARD_WIDTH
			var card_height = CARD_HEIGHT
			var season := int(image_atlas_details.get("season", 0))
			var region_width = loaded_image.get_width()
			var region_height = loaded_image.get_height()
			var phone_image_scale := float(image_atlas_details.get("phone_image_scale", 1.0))
			var phone_image_output_size := _get_phone_image_output_size(image_url)
			var phone_image_original_size := _get_phone_image_original_size(image_url)
			var offset_x = image_atlas_details.get('sprite_offset_x', 0)
			var offset_y = image_atlas_details.get('sprite_offset_y', 0)
			print("[CardImageLoader] 图集原始尺寸: %dx%d，URL: %s" % [region_width, region_height, image_url])
			var explicit_expected_grid := _get_grid_from_rule(image_atlas_details)
			var phone_expected_grid := _get_phone_expected_grid(image_atlas_details, image_url)
			var fixed_expected_grid := phone_expected_grid if not phone_expected_grid.is_empty() else explicit_expected_grid
			var has_fixed_grid_override := not fixed_expected_grid.is_empty()
			if has_fixed_grid_override:
				var grid_w_override := int(fixed_expected_grid["grid_w"])
				var grid_h_override := int(fixed_expected_grid["grid_h"])
				if grid_w_override > 0 and grid_h_override > 0:
					var top_align_vertical_trim := _should_use_phone_top_aligned_vertical_trim(image_atlas_details, image_url, grid_h_override)
					# 显式网格图集按固定行列切图；phone 端仍结合缩放报告处理裁边。
					var layout_width: int = region_width
					var layout_height: int = region_height
					if phone_image_output_size != Vector2i.ZERO:
						var output_width_gap: int = abs(region_width - phone_image_output_size.x)
						var output_height_gap: int = abs(region_height - phone_image_output_size.y)
						if output_width_gap <= ATLAS_DIMENSION_TOLERANCE and output_height_gap <= ATLAS_DIMENSION_TOLERANCE:
							layout_width = mini(layout_width, phone_image_output_size.x)
							layout_height = mini(layout_height, phone_image_output_size.y)
					var report_trim_x_total: int = max(0, region_width - layout_width)
					var report_trim_y_total: int = max(0, region_height - layout_height)
					offset_x += int(floor(float(report_trim_x_total) * 0.5))
					offset_y += 0 if top_align_vertical_trim else int(floor(float(report_trim_y_total) * 0.5))
					region_width = layout_width
					region_height = layout_height

					var effective_phone_scale := phone_image_scale
					if phone_image_original_size != Vector2i.ZERO:
						var observed_scale_w := float(region_width) / float(phone_image_original_size.x)
						var observed_scale_h := float(region_height) / float(phone_image_original_size.y)
						if observed_scale_w > 0.0 and observed_scale_h > 0.0 and abs(observed_scale_w - observed_scale_h) <= 0.05:
							effective_phone_scale = (observed_scale_w + observed_scale_h) * 0.5

					var preferred_card_width := int(round(CARD_WIDTH * effective_phone_scale))
					var preferred_card_height := int(round(CARD_HEIGHT * effective_phone_scale))
					var preferred_region_width := preferred_card_width * grid_w_override
					var preferred_region_height := preferred_card_height * grid_h_override
					var used_scale_layout := false
					var allow_scale_target_layout := season != 6
					if allow_scale_target_layout and preferred_card_width > 0 and preferred_card_height > 0 and preferred_region_width <= region_width and preferred_region_height <= region_height:
						var scale_trim_x_total: int = max(0, region_width - preferred_region_width)
						var scale_trim_y_total: int = max(0, region_height - preferred_region_height)
						offset_x += int(floor(float(scale_trim_x_total) * 0.5))
						offset_y += 0 if top_align_vertical_trim else int(floor(float(scale_trim_y_total) * 0.5))
						region_width = preferred_region_width
						region_height = preferred_region_height
						used_scale_layout = true
					else:
						var divisible_width := int(floor(float(region_width) / float(grid_w_override))) * grid_w_override
						var divisible_height := int(floor(float(region_height) / float(grid_h_override))) * grid_h_override
						var divisible_trim_x_total: int = max(0, region_width - divisible_width)
						var divisible_trim_y_total: int = max(0, region_height - divisible_height)
						offset_x += int(floor(float(divisible_trim_x_total) * 0.5))
						offset_y += 0 if top_align_vertical_trim else int(floor(float(divisible_trim_y_total) * 0.5))
						region_width = max(1, divisible_width)
						region_height = max(1, divisible_height)

					card_width = float(region_width) / float(grid_w_override)
					card_height = float(region_height) / float(grid_h_override)
					print("[CardImageLoader] 固定网格切图 %dx%d（输出尺寸%s，原尺寸%s，scale=%.3f->%.3f，按%s，单卡尺寸: %.1fx%.1f，偏移(%d,%d)），URL: %s" % [
						grid_w_override,
						grid_h_override,
						str(phone_image_output_size),
						str(phone_image_original_size),
						phone_image_scale,
						effective_phone_scale,
						"scale目标区域" if used_scale_layout else "整除裁边",
						card_width,
						card_height,
						offset_x,
						offset_y,
						image_url,
					])
			elif image_atlas_details.get('recalculate_card_sizes', false):
				if image_atlas_details['sprite_region_width'] > 0:
					region_width = int(round(image_atlas_details['sprite_region_width'] * phone_image_scale))
				if image_atlas_details['sprite_region_height'] > 0:
					region_height = int(round(image_atlas_details['sprite_region_height'] * phone_image_scale))
				offset_x = int(round(offset_x * phone_image_scale))
				offset_y = int(round(offset_y * phone_image_scale))
				card_width = region_width / image_atlas_details['sprite_count_width']
				card_height = region_height / image_atlas_details['sprite_count_height']
				print("[CardImageLoader] 重新计算单卡尺寸: %.1fx%.1f" % [card_width, card_height])
			elif is_season7:
				# Season 7：根据角色固定行列数从大图尺寸反算单卡尺寸
				var deck_id = image_atlas_details.get('deck_id', '')
				var s7_rows = 3 if deck_id in ["happychaos", "jacko", "may", "nago", "testament"] else 4
				card_width = float(region_width) / 6.0
				card_height = float(region_height) / float(s7_rows)
				print("[CardImageLoader] Season7 角色 '%s' 使用 %d排6列，单卡尺寸: %.1fx%.1f，URL: %s" % [deck_id, s7_rows, card_width, card_height, image_url])
			elif is_season6:
				# Season 6：固定按 2 排 4 列从大图尺寸反算单卡尺寸
				card_width = float(region_width) / 4.0
				card_height = float(region_height) / 2.0
				print("[CardImageLoader] Season6 使用 2排4列，单卡尺寸: %.1fx%.1f，URL: %s" % [card_width, card_height, image_url])
			elif is_season1:
				var deck_id = str(image_atlas_details.get('deck_id', ''))
				var season1_rows = 4 if deck_id == "devis" else 2
				card_width = float(region_width) / 4.0
				card_height = float(region_height) / float(season1_rows)
				print("[CardImageLoader] Season1 角色 '%s' 使用 %d排4列，单卡尺寸: %.1fx%.1f，URL: %s" % [deck_id, season1_rows, card_width, card_height, image_url])
			elif not has_fixed_grid_override and phone_image_scale != 1.0:
				# 普通图集按原始 750x1024 卡格切分；移动端 CDN 图已按报告比例缩放。
				card_width *= phone_image_scale
				card_height *= phone_image_scale
				offset_x = int(round(offset_x * phone_image_scale))
				offset_y = int(round(offset_y * phone_image_scale))

			var grid_width = region_width / card_width
			var grid_height = region_height / card_height
			if has_fixed_grid_override:
				grid_width = int(fixed_expected_grid["grid_w"])
				grid_height = int(fixed_expected_grid["grid_h"])
			elif not (is_season7 or is_season6 or is_season1):
				var rounded_grid_width = int(round(grid_width))
				var rounded_grid_height = int(round(grid_height))
				var width_difference = abs(region_width - rounded_grid_width * card_width)
				var height_difference = abs(region_height - rounded_grid_height * card_height)
				if rounded_grid_width > 0 and width_difference > 0 and width_difference <= ATLAS_DIMENSION_TOLERANCE:
					card_width = float(region_width) / rounded_grid_width
					grid_width = rounded_grid_width
					print("[CardImageLoader] 吸收图集宽度偏差 %.1fpx，单卡宽度调整为 %.1f，URL: %s" % [width_difference, card_width, image_url])
				if rounded_grid_height > 0 and height_difference > 0 and height_difference <= ATLAS_DIMENSION_TOLERANCE:
					card_height = float(region_height) / rounded_grid_height
					grid_height = rounded_grid_height
					print("[CardImageLoader] 吸收图集高度偏差 %.1fpx，单卡高度调整为 %.1f，URL: %s" % [height_difference, card_height, image_url])

				if not (_is_integer_like(grid_width) and _is_integer_like(grid_height)):
					var trimmed_layout := try_trim_edges_for_divisible_grid(
							region_width,
							region_height,
							card_width,
							card_height,
							ATLAS_DIMENSION_TOLERANCE)
					if trimmed_layout["trimmed"]:
						region_width = trimmed_layout["region_width"]
						region_height = trimmed_layout["region_height"]
						grid_width = trimmed_layout["grid_width"]
						grid_height = trimmed_layout["grid_height"]
						print("[CardImageLoader] 裁切图集边缘像素(%d,%d)以保证整除切图，URL: %s" % [
							trimmed_layout["trim_right"],
							trimmed_layout["trim_bottom"],
							image_url,
						])
			print("[CardImageLoader] 切图网格: %.0fx%.0f（单卡 %.1fx%.1f），偏移(%d,%d)，URL: %s" % [grid_width, grid_height, card_width, card_height, offset_x, offset_y, image_url])

			if not (is_season7 or is_season6 or is_season1) and (grid_width <= 0 or grid_height <= 0 or not _is_integer_like(grid_width) or not _is_integer_like(grid_height)):
				push_error("[CardImageLoader] 图集尺寸(%dx%d)无法被单卡尺寸(%.1fx%.1f)整除，切图将出错！URL: %s" % [region_width, region_height, card_width, card_height, image_url])

			var grid_w = int(round(grid_width))
			var grid_h = int(round(grid_height))
			var scaled_card_size = _get_scaled_card_size(
					card_width, card_height, image_atlas_details.get("runtime_card_scale", -1.0))
			var s6_mobile_max_card_size := Vector2i.ZERO
			if is_season6 and _is_mobile_web():
				var s6_phone_scale := clampf(phone_image_scale, 0.1, 1.0)
				s6_mobile_max_card_size = Vector2i(
					maxi(1, int(round(CARD_WIDTH * s6_phone_scale))),
					maxi(1, int(round(CARD_HEIGHT * s6_phone_scale))))
				print("[CardImageLoader] Season6 手机端切片尺寸上限: %dx%d，URL: %s" % [
					s6_mobile_max_card_size.x,
					s6_mobile_max_card_size.y,
					image_url,
				])
			var image_grid = loaded_images.get(image_url, [])
			image_grid.resize(grid_w * grid_h)
			var requested_indices = image_load_requested_indices.get(image_url, {})
			var force_cropped_textures = image_atlas_details.get('force_cropped_textures', false)
			var use_scaled_mobile_atlas_texture = not force_cropped_textures and _should_use_scaled_mobile_atlas_texture(image_atlas_details, loaded_image)
			var use_cropped_textures = not use_scaled_mobile_atlas_texture and _should_avoid_full_atlas_texture(image_atlas_details, loaded_image)
			var materialize_all_textures = not lazy_multi_card_textures and should_materialize_all_multi_card_textures(_is_mobile_web(), image_atlas_details)
			var scaled_layout = {}
			if use_scaled_mobile_atlas_texture:
				scaled_layout = _get_scaled_mobile_atlas_layout(grid_w, grid_h, card_width, card_height, offset_x, offset_y)
				var scaled_atlas_size = scaled_layout["atlas_size"]
				var scaled_atlas_image = RuntimeImageResizerScript.resize_to(loaded_image, scaled_atlas_size.x, scaled_atlas_size.y)
				image_texture = ImageTexture.create_from_image(scaled_atlas_image)
				scaled_atlas_image = null
			elif not use_cropped_textures:
				image_texture = ImageTexture.create_from_image(loaded_image)
			for y in range(grid_h):
				for x in range(grid_w):
					var image_index = y * grid_w + x
					if image_grid[image_index] != null:
						continue
					if not materialize_all_textures and not should_create_atlas_texture(requested_indices, image_index):
						continue
					if use_scaled_mobile_atlas_texture:
						var atlas_texture = AtlasTexture.new()
						atlas_texture.atlas = image_texture
						atlas_texture.region = Rect2(
							scaled_layout["offset_x"] + x * scaled_layout["card_width"],
							scaled_layout["offset_y"] + y * scaled_layout["card_height"],
							scaled_layout["card_width"],
							scaled_layout["card_height"])
						image_grid[image_index] = atlas_texture
					elif use_cropped_textures:
						# 避免先上传整张大图到 GPU，直接按子图裁切后再创建纹理，以降低移动端峰值和超大纹理风险。
						var rx = 0
						var ry = 0
						var rw = 0
						var rh = 0
						if is_season6 or is_season1:
							# S1/S6 图集可能无法被 4x2 整除（如 2000x1365）。
							# 每格宽高和起点都使用 floor 后的固定整数：1365 / 2 取 682，
							# 将多出的 1px 留在图集最右/最下边。这样各切片尺寸一致，
							# 且不会因分数边界取整而产生重叠或越界。
							var source_width = loaded_image.get_width()
							var source_height = loaded_image.get_height()
							rw = max(1, int(floor(card_width)))
							rh = max(1, int(floor(card_height)))
							rx = clampi(offset_x + x * rw, 0, max(0, source_width - rw))
							ry = clampi(offset_y + y * rh, 0, max(0, source_height - rh))
						else:
							rx = int(round(offset_x + x * card_width))
							ry = int(round(offset_y + y * card_height))
							rw = int(round(card_width))
							rh = int(round(card_height))
						var cropped = loaded_image.get_region(Rect2i(rx, ry, rw, rh))
						if s6_mobile_max_card_size != Vector2i.ZERO and (
								cropped.get_width() > s6_mobile_max_card_size.x
								or cropped.get_height() > s6_mobile_max_card_size.y):
							RuntimeImageResizerScript.resize_in_place(
									cropped,
									s6_mobile_max_card_size.x,
									s6_mobile_max_card_size.y)
						if _is_phone_cdn_url(image_url):
							_maybe_dump_phone_slice_tile(image_url, image_index, cropped)
						if is_season7 or is_season6 or is_season1 or _is_mobile_web():
							image_grid[image_index] = _create_card_texture_from_image(cropped, scaled_card_size)
						else:
							image_grid[image_index] = ImageTexture.create_from_image(cropped)
						cropped = null
					else:
						var atlas_texture = AtlasTexture.new()
						atlas_texture.atlas = image_texture
						atlas_texture.region = Rect2(
							offset_x + (x * card_width), offset_y + (y * card_height),
							card_width, card_height)
						image_grid[image_index] = atlas_texture
					if should_yield_after_atlas_texture(_is_mobile_web(), image_atlas_details, image_index):
						await get_tree().process_frame
						if is_tearing_down:
							return
			print("[CardImageLoader] 切图完成，共 %d 张子图，URL: %s" % [image_grid.size(), image_url])
			loaded_images[image_url] = image_grid
			var phone_slice_signature := _build_phone_slice_signature(image_url, image_atlas_details)
			if not phone_slice_signature.is_empty():
				phone_cached_slice_signature_by_url[image_url] = phone_slice_signature
			else:
				phone_cached_slice_signature_by_url.erase(image_url)
		else:
			loaded_images[image_url] = [_create_card_texture_from_image(loaded_image)]
			phone_cached_slice_signature_by_url.erase(image_url)
	else:
		push_error("[CardImageLoader] 最终图片为空，跳过加载，URL: " + image_url)
		loaded_images[image_url] = null
		phone_cached_slice_signature_by_url.erase(image_url)
	loaded_image = null
	image_texture = null
	image_load_queue.pop_at(0)
	processing_queue = false
	image_queue_advanced.emit()

func _image_request_completed(result, response_code, headers, body):
	if is_tearing_down:
		return
	print("[CardImageLoader] HTTP 响应 — result: %d, response_code: %d, body_size: %d bytes" % [result, response_code, body.size()])

	# result != OK 表示网络层错误（如连接失败、超时、SSL 错误）
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("[CardImageLoader] 网络请求失败，HTTPRequest result=%d（0=成功，参见 HTTPRequest.Result 枚举）" % result)
		finished_loading_image.emit(null)
		return

	# 非 200 状态码通常意味着权限问题、重定向未跟随或资源不存在
	if response_code != 200:
		push_error("[CardImageLoader] HTTP 状态码异常: %d，响应体(前256字节): %s" % [response_code, body.slice(0, min(256, body.size())).get_string_from_utf8()])
		finished_loading_image.emit(null)
		return

	var image_type = _detect_image_type(headers, body)
	print("[CardImageLoader] 识别图片格式: ", image_type)

	var image = Image.new()
	var load_success = false

	if image_type == "png":
		var error = image.load_png_from_buffer(body)
		if error == OK:
			load_success = true
		else:
			push_error("[CardImageLoader] PNG 解码失败，error=%d，body_size=%d" % [error, body.size()])
	else:
		var error = image.load_jpg_from_buffer(body)
		if error == OK:
			load_success = true
		else:
			push_error("[CardImageLoader] JPG 解码失败，error=%d，body_size=%d，前4字节(hex): %s" % [error, body.size(), body.slice(0, min(4, body.size())).hex_encode()])

	if load_success:
		finished_loading_image.emit(image)
	else:
		finished_loading_image.emit(null)

func get_card_image(image_url, image_index, image_atlas_details = {}):
	if test_mode:
		var placeholder = Image.create(1, 1, false, Image.FORMAT_RGBA8)
		placeholder.fill(Color(1, 1, 1, 1))
		return ImageTexture.create_from_image(placeholder)
	if is_tearing_down:
		return null
	image_url = _normalize_image_url(image_url)
	_register_requested_index(image_url, image_index)
	if image_atlas_details:
		var normalized_image_atlas = image_atlas_details.duplicate(true)
		normalized_image_atlas['url'] = image_url
		normalized_image_atlas['phone_image_scale'] = _get_phone_image_scale(image_url)
		if image_url in image_load_atlas_map:
			image_load_atlas_map[image_url] = merge_image_atlas_details(image_load_atlas_map[image_url], normalized_image_atlas)
		else:
			image_load_atlas_map[image_url] = normalized_image_atlas
	if image_url in loaded_images and loaded_images[image_url] != null and image_index >= 0:
		var loaded_texture_set = loaded_images[image_url]
		if image_index >= loaded_texture_set.size() or loaded_texture_set[image_index] == null:
			if image_url not in image_load_queue:
				image_load_queue.append(image_url)

	while image_url not in loaded_images or (
			image_index >= 0 and loaded_images[image_url] != null and (
				image_index >= loaded_images[image_url].size() or loaded_images[image_url][image_index] == null)):
		if is_tearing_down:
			return null
		if image_url not in image_load_queue:
			image_load_queue.append(image_url)
			if image_url not in image_load_atlas_map:
				image_load_atlas_map[image_url] = {
					"url": image_url,
					"multiple_cards": false,
					"phone_image_scale": _get_phone_image_scale(image_url)
				}
		await image_queue_advanced
		if is_tearing_down:
			return null

	var image_set = loaded_images[image_url]
	if image_set:
		return image_set[image_index]
	else:
		return null

func get_animation_images(
		image_url,
		sprite_offset_x,
		sprite_offset_y,
		sprite_region_width,
		sprite_region_height,
		sprite_count_width,
		sprite_count_height):
	if test_mode:
		return []
	if is_tearing_down:
		return []
	image_url = _normalize_image_url(image_url)
	_register_requested_index(image_url, -1)

	while image_url not in loaded_images:
		if is_tearing_down:
			return []
		if image_url not in image_load_queue:
			image_load_queue.append(image_url)
			image_load_atlas_map[image_url] = {
				"url": image_url,
				"multiple_cards": true,
				"phone_image_scale": _get_phone_image_scale(image_url),
				"recalculate_card_sizes": true,
				"sprite_offset_x": sprite_offset_x,
				"sprite_offset_y": sprite_offset_y,
				"sprite_region_width": sprite_region_width,
				"sprite_region_height": sprite_region_height,
				"sprite_count_width": sprite_count_width,
				"sprite_count_height": sprite_count_height
			}
		await image_queue_advanced
		if is_tearing_down:
			return []

	return loaded_images[image_url]

func _get_budget_owner() -> String:
	return "CardImageLoader:%s" % get_instance_id()

func _register_loaded_image_budget(image_url: String, loaded_image: Image, image_atlas_details: Dictionary):
	if loaded_image == null:
		return
	var priority := str(get_meta("resource_budget_priority", "preview" if image_atlas_details.get("reference_preview", false) else "visible"))
	MobileResourceBudget.register_texture(
		image_url,
		loaded_image.get_width(),
		loaded_image.get_height(),
		_get_budget_owner(),
		priority)
