extends RefCounted

const DEFAULT_BACKGROUND_ID := "classic"
const DEFAULT_MAIN_MENU_BACKGROUND_ID := "MP1"
const STANDARD_ARENA_DIRECTORY := "res://assets/ui/standard_arena"
const BACKGROUND_ROOT_DIRECTORY := "res://assets/ui"
const PHONE_BACKGROUND_ROOT_DIRECTORY := "res://assets/phone/ui"
const PHONE_STANDARD_ARENA_DIRECTORY := "res://assets/phone/ui/standard_arena"
const MAIN_MENU_BACKGROUND_ROOT_DIRECTORY := "res://assets/mainmenu_picture"
const PHONE_MAIN_MENU_BACKGROUND_ROOT_DIRECTORY := "res://assets/phone/mainmenu_picture"

const MainMenu_BACKGROUNDS := {
	"MP1": {
		"label": "纯色1",
		"url_id": "mp1",
		"image_id": "1.jpg",
	},
	"MP7": {
		"label": "纯色2",
		"url_id": "mp7",
		"image_id": "7.jpg",
	},
	"MP2": {
		"label": "2全1",
		"url_id": "mp2",
		"image_id": "2_2.jpg",
	},
	"MP3": {
		"label": "3卡普空1",
		"url_id": "mp3",
		"image_id": "3.jpg",
	},
	"MP4": {
		"label": "4卡普空2",
		"url_id": "mp4",
		"image_id": "4.jpg",
	},
	"MP5": {
		"label": "5卡普空3",
		"url_id": "mp5",
		"image_id": "5.jpg",
	},
	"MP6": {
		"label": "6春丽1",
		"url_id": "mp6",
		"image_id": "6.jpg",
	},
	"MP8": {
		"label": "8第七十字",
		"url_id": "mp8",
		"image_id": "8.jpg",
	},
	"MP9": {
		"label": "9春丽2",
		"url_id": "mp9",
		"image_id": "9.jpg",
	},
	"MP10": {
		"label": "10春丽VS嘉米",
		"url_id": "mp10",
		"image_id": "10.jpg",
	},
}

const BACKGROUNDS := {
	"random": {
		"label": "每场随机",
	},
	"classic": {
		"label": "BG0 经典",
		"url_id": "",
		"image_id": "",
		"standard_arena": false,
	},
	"BG1": {
		"label": "BG1 森林",
		"url_id": "BG1",
		"image_id": "BG1.jpg",
		"standard_arena": false,
	},
	"BG2": {
		"label": "BG2 遗迹",
		"url_id": "BG2",
		"image_id": "BG2.jpg",
		"standard_arena": true,
	},
	"BG3": {
		"label": "BG3 遗迹2",
		"url_id": "BG3",
		"image_id": "BG3.jpg",
		"standard_arena": true,
	},
	"BG4": {
		"label": "BG4 峡谷",
		"url_id": "BG4",
		"image_id": "BG4.jpg",
		"standard_arena": true,
	},
	"BG5": {
		"label": "BG5 街头",
		"url_id": "BG5",
		"image_id": "BG5.jpg",
		"standard_arena": true,
	},
	"BG6": {
		"label": "BG6 夜港",
		"url_id": "BG6",
		"image_id": "BG6.jpg",
		"standard_arena": true,
	},
	"BG7": {
		"label": "BG7 冥门",
		"url_id": "BG7",
		"image_id": "BG7.jpg",
		"standard_arena": true,
	},
	"BG8": {
		"label": "BG8 幽谷",
		"url_id": "BG8",
		"image_id": "BG8.jpg",
		"standard_arena": true,
	},                    
	"BG9": {
		"label": "BG9 街头2",
		"url_id": "BG9",
		"image_id": "BG9.jpg",
		"standard_arena": true,
	},
	"BG10": {
		"label": "BG10 红莲寺",
		"url_id": "BG10",
		"image_id": "BG10.jpg",
		"standard_arena": true,
	},    
	"BG11": {
		"label": "BG11 伪-三途川",
		"url_id": "BG11",
		"image_id": "BG11.jpg",
		"standard_arena": true,
	},
	"BG22": {
		"label": "BG22 真-三途川",
		"url_id": "BG22",
		"image_id": "BG22.jpg",
		"standard_arena": true,
	},
	"BG12": {
		"label": "BG12 遗迹3",
		"url_id": "BG12",
		"image_id": "BG12_1.jpg",
		"standard_arena": true,
	},
	"BG13": {
		"label": "BG13 甲板",
		"url_id": "BG13",
		"image_id": "BG13.jpg",
		"standard_arena": true,
	},
	"BG14": {
		"label": "BG14 舞台",
		"url_id": "BG14",
		"image_id": "BG14.jpg",
		"standard_arena": true,
	},
	"BG15": {
		"label": "BG15 熔岩",
		"url_id": "BG15",
		"image_id": "BG15.jpg",
		"standard_arena": true,
	},
	"BG16": {
		"label": "BG16 街头3",
		"url_id": "BG16",
		"image_id": "BG16.jpg",
		"standard_arena": true,
	},
	"BG17": {
		"label": "BG17 能源",
		"url_id": "BG17",
		"image_id": "BG17.jpg",
		"standard_arena": true,
	},
	"BG18": {
		"label": "BG18 道场",
		"url_id": "BG18",
		"image_id": "BG18.jpg",
		"standard_arena": true,
	},
	"BG19": {
		"label": "BG19 雪村",
		"url_id": "BG19",
		"image_id": "BG19.jpg",
		"standard_arena": true,
	},
	"BG20": {
		"label": "BG20 街机",
		"url_id": "BG20",
		"image_id": "BG20.jpg",
		"standard_arena": true,
	},
	"BG21": {
		"label": "BG21 街头4",
		"url_id": "BG21",
		"image_id": "BG21.jpg",
		"standard_arena": true,
	},
}

static var _texture_cache := {}
static var _mobile_web_runtime_override = null
const MATCH_TEXTURE_OWNER := "BackgroundManager:match"
const MAIN_MENU_TEXTURE_OWNER := "BackgroundManager:main_menu"

static func _is_mobile_web_runtime() -> bool:
	if _mobile_web_runtime_override != null:
		return _mobile_web_runtime_override
	return MobileRuntimeFlags.is_mobile_resource_runtime()

static func is_random_background_id(background_id: String) -> bool:
	return background_id == "random"

static func get_main_menu_background_ids() -> Array[String]:
	var background_ids: Array[String] = []
	for background_id in MainMenu_BACKGROUNDS:
		background_ids.append(background_id)
	return background_ids

static func normalize_main_menu_background_id(background_id: String) -> String:
	if MainMenu_BACKGROUNDS.has(background_id):
		return background_id
	return DEFAULT_MAIN_MENU_BACKGROUND_ID

static func get_main_menu_background_definition(background_id: String) -> Dictionary:
	return MainMenu_BACKGROUNDS[normalize_main_menu_background_id(background_id)]

static func get_main_menu_background_label(background_id: String) -> String:
	return get_main_menu_background_definition(background_id).get("label", background_id)

static func get_main_menu_background_texture(background_id: String) -> Texture2D:
	var resource_path := get_main_menu_background_resource_path(background_id)
	return _load_texture(resource_path)

static func load_main_menu_background_texture(background_id: String) -> Texture2D:
	var resource_path := get_main_menu_background_resource_path(background_id)
	return await _load_texture_async(resource_path)

static func get_main_menu_background_resource_path(background_id: String) -> String:
	var definition := get_main_menu_background_definition(background_id)
	var url_id: String = definition.get("url_id", "")
	var image_id: String = definition.get("image_id", "")
	if url_id.is_empty() or image_id.is_empty():
		return ""
	var desktop_path := "%s/%s/%s" % [MAIN_MENU_BACKGROUND_ROOT_DIRECTORY, url_id, image_id]
	if _is_mobile_web_runtime():
		var phone_path := "%s/%s/%s" % [PHONE_MAIN_MENU_BACKGROUND_ROOT_DIRECTORY, url_id, image_id]
		if _resource_or_cdn_exists(phone_path):
			return phone_path
	return desktop_path

static func get_background_ids() -> Array[String]:
	var background_ids: Array[String] = []
	for background_id in BACKGROUNDS:
		background_ids.append(background_id)
	return background_ids

static func get_randomizable_background_ids() -> Array[String]:
	var background_ids: Array[String] = []
	for background_id in get_background_ids():
		if not is_random_background_id(background_id):
			background_ids.append(background_id)
	return background_ids

static func resolve_background_id(background_id: String) -> String:
	var normalized_id := normalize_background_id(background_id)
	if not is_random_background_id(normalized_id):
		return normalized_id
	var randomizable_ids := get_randomizable_background_ids()
	if randomizable_ids.is_empty():
		return DEFAULT_BACKGROUND_ID
	return randomizable_ids.pick_random()

static func normalize_background_id(background_id: String) -> String:
	if BACKGROUNDS.has(background_id):
		return background_id
	return DEFAULT_BACKGROUND_ID

static func get_background_definition(background_id: String) -> Dictionary:
	return BACKGROUNDS[normalize_background_id(background_id)]

static func get_background_label(background_id: String) -> String:
	return get_background_definition(background_id).get("label", background_id)

static func uses_classic_arena(background_id: String) -> bool:
	var definition := get_background_definition(background_id)
	return definition.get("url_id", "").is_empty() or definition.get("image_id", "").is_empty()

static func get_background_texture(background_id: String) -> Texture2D:
	var resource_path := get_background_resource_path(background_id)
	return _load_texture(resource_path)

static func get_arena_texture(background_id: String, prefix: String, location: int) -> Texture2D:
	var resource_path := get_arena_resource_path(background_id, prefix, location)
	return _load_texture(resource_path, false)

static func load_background_texture(background_id: String) -> Texture2D:
	var resource_path := get_background_resource_path(background_id)
	return await _load_texture_async(resource_path)

static func load_arena_texture(background_id: String, prefix: String, location: int, keep_cached := false) -> Texture2D:
	var resource_path := get_arena_resource_path(background_id, prefix, location)
	return await _load_texture_async(resource_path, keep_cached)

static func preload_all_arena_tiles(background_id: String) -> void:
	if uses_classic_arena(background_id):
		return
	for prefix in ["B", "R"]:
		for location in range(1, 10):
			await load_arena_texture(background_id, prefix, location, true)

static func get_background_resource_path(background_id: String) -> String:
	var definition := get_background_definition(background_id)
	var url_id: String = definition.get("url_id", "")
	var image_id: String = definition.get("image_id", "")
	if url_id.is_empty() or image_id.is_empty():
		return ""
	var desktop_path := "%s/%s/%s" % [BACKGROUND_ROOT_DIRECTORY, url_id, image_id]
	if _is_mobile_web_runtime():
		var phone_path := "%s/%s/%s" % [PHONE_BACKGROUND_ROOT_DIRECTORY, url_id, image_id]
		if _resource_or_cdn_exists(phone_path):
			return phone_path
	return desktop_path

static func get_arena_resource_path(background_id: String, prefix: String, location: int) -> String:
	if prefix != "B" and prefix != "R":
		return ""
	if location < 1 or location > 9:
		return ""
	var definition := get_background_definition(background_id)
	var arena_directory := STANDARD_ARENA_DIRECTORY
	if not definition.get("standard_arena", true):
		var url_id: String = definition.get("url_id", "")
		if url_id.is_empty():
			return ""
		arena_directory = "%s/%s/arena" % [BACKGROUND_ROOT_DIRECTORY, url_id]
	var desktop_path := "%s/%s%d.png" % [arena_directory, prefix, location]
	if _is_mobile_web_runtime():
		var phone_arena_directory := PHONE_STANDARD_ARENA_DIRECTORY
		if not definition.get("standard_arena", true):
			var phone_url_id: String = definition.get("url_id", "")
			if phone_url_id.is_empty():
				return ""
			phone_arena_directory = "%s/%s/arena" % [PHONE_BACKGROUND_ROOT_DIRECTORY, phone_url_id]
		var phone_path := "%s/%s%d.png" % [phone_arena_directory, prefix, location]
		if _resource_or_cdn_exists(phone_path):
			return phone_path
	return desktop_path

static func _resource_or_cdn_exists(resource_path: String) -> bool:
	return ResourceLoader.exists(resource_path) or CdnAssetLoader.is_cdn_mapped_res_path(resource_path)

static func clear_match_texture_cache():
	for resource_path in _texture_cache.keys():
		if resource_path.begins_with(BACKGROUND_ROOT_DIRECTORY + "/") or resource_path.begins_with(PHONE_BACKGROUND_ROOT_DIRECTORY + "/"):
			MobileResourceBudget.unregister(resource_path)
			CdnAssetLoader.clear_texture(resource_path)
			_texture_cache.erase(resource_path)
	CdnAssetLoader.release_owner(MATCH_TEXTURE_OWNER)

static func clear_main_menu_texture_cache():
	for resource_path in _texture_cache.keys():
		if resource_path.begins_with(MAIN_MENU_BACKGROUND_ROOT_DIRECTORY + "/") or resource_path.begins_with(PHONE_MAIN_MENU_BACKGROUND_ROOT_DIRECTORY + "/"):
			MobileResourceBudget.unregister(resource_path)
			CdnAssetLoader.clear_texture(resource_path)
			_texture_cache.erase(resource_path)
	CdnAssetLoader.release_owner(MAIN_MENU_TEXTURE_OWNER)

static func _load_texture(resource_path: String, keep_cached := true) -> Texture2D:
	if resource_path.is_empty() or not ResourceLoader.exists(resource_path):
		var cached_texture := CdnAssetLoader.get_cached_texture(
			resource_path,
			_get_texture_owner(resource_path),
			"visible")
		if cached_texture != null:
			return cached_texture
		return null
	if not keep_cached:
		var uncached_texture := load(resource_path) as Texture2D
		_register_texture_budget(resource_path, uncached_texture)
		return uncached_texture
	if not _texture_cache.has(resource_path):
		_texture_cache[resource_path] = load(resource_path) as Texture2D
		_register_texture_budget(resource_path, _texture_cache[resource_path])
	return _texture_cache[resource_path]

static func _load_texture_async(resource_path: String, keep_cached := true) -> Texture2D:
	if resource_path.is_empty():
		return null
	if keep_cached and _texture_cache.has(resource_path):
		return _texture_cache[resource_path]
	var texture_owner := _get_texture_owner(resource_path)
	var texture := await CdnAssetLoader.load_texture(resource_path, texture_owner, "visible")
	if texture == null and resource_path.begins_with("res://assets/phone/"):
		var desktop_path := "res://assets/" + resource_path.trim_prefix("res://assets/phone/")
		texture = await CdnAssetLoader.load_texture(
			desktop_path,
			_get_texture_owner(desktop_path),
			"visible")
	# Background and track TextureRects use a fixed 1280x720 covered display box.
	# Keep phone textures decoded at their optimized size; the report records their
	# desktop visual size, which the fixed box already restores without upsampling.
	if texture != null:
		CdnAssetLoader.get_phone_texture_original_size(resource_path)
	if keep_cached and texture != null:
		_texture_cache[resource_path] = texture
	return texture

static func _get_texture_owner(resource_path: String) -> String:
	if resource_path.begins_with(MAIN_MENU_BACKGROUND_ROOT_DIRECTORY + "/") \
			or resource_path.begins_with(PHONE_MAIN_MENU_BACKGROUND_ROOT_DIRECTORY + "/"):
		return MAIN_MENU_TEXTURE_OWNER
	return MATCH_TEXTURE_OWNER

static func _register_texture_budget(resource_path: String, texture: Texture2D):
	if texture == null:
		return
	MobileResourceBudget.register_texture(
		resource_path,
		int(texture.get_width()),
		int(texture.get_height()),
		"BackgroundManager",
		"visible")
