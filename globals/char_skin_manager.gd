extends Node

const DEFAULT_SKIN_LABEL := "原皮"
const DEFAULT_EXTRA_SKIN_LABEL := "皮肤%d"
const FALLBACK_PORTRAIT_PATH := "res://assets/portraits/custom.png"

# Manually register skin availability here.
# Template:
# "xxx": {
# 	"count": 1,
# 	"skins": {
# 		1: {
# 			"label": "皮肤1",
# 			"portraits_skin": true,
# 			"portraits_url": "res://assets/portraits_skin/xxx_1.png",
# 			"animations_skin": false,
# 			"exceed_change_skin": false,
# 			"buddy_skin": false,
# 		},
# 	},
# },
# Set "portraits_skin" to false to use the original character portrait. Any
# "portraits_url" provided for that skin will then be ignored.
# Example: specter_1 with false uses "res://assets/portraits/specter.png";
# with true it uses the configured "res://assets/portraits_skin/specter_1.png".
# Missing configured or original portrait files safely use FALLBACK_PORTRAIT_PATH.
# Set "animations_skin" to true to use
# "res://assets/character_animations_skin/xxx_1/animations.tres".
# When false or omitted, the original character animation folder is used.
# Set "exceed_change_skin" to true to use the strictly corresponding
# "res://assets/character_animations_skin/xxx_1_exceed/animations.tres"
# while exceeded. When false or omitted, the normal skin animation remains.
# Set "buddy_skin" to true to use matching buddy resources such as
# "res://assets/character_animations_skin/rachel_georgexiii_1/animations.tres"
# for the skin's buddy graphics ids. When false or omitted, buddy graphics use
# the original character animation folders.
var CHARACTER_SKINS := {

	"devis": {
		"Note":"S1 START",
		"count": 1,
		"skins": {
			1: {
				"label": "皮肤1:卢卡尔",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
		},
	},

	"carlswangee": {
		"Note":"S2 START",
        "count": 1,
		"skins": {
			1: {
				"label": "皮肤1:牙神幻十郎",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
        },
    },

	"pooky": {
        "count": 3,
		"skins": {
			1: {
				"label": "皮肤1",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": true,
 			    "buddy_skin": false,
			},
			2: {
				"label": "皮肤2:杰米(觉醒加强1攻) A",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": true,
 			    "buddy_skin": false,
			},
			3: {
				"label": "皮肤3:狄奧多拉",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": true,
 			    "buddy_skin": false,
			}
        },
    },

	"eugenia": {
		"Note":"S2 START",
        "count": 3,
		"skins": {
			1: {
				"label": "皮肤1:新立绘",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
			2:{
				"label": "皮肤2:新立绘",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
			3: {
				"label": "皮肤3:改版(觉醒面加强)",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": false,
				"exceed_change_skin": false,
				"buddy_skin": false,
			},
        },
    },

	"akuma": {
		"Note":"S3 START",
        "count": 1,
		"skins": {
			1: {
				"label": "皮肤1",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
        },
    },

	"bison": {
        "count": 1,
		"skins": {
			1: {
				"label": "皮肤1",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
        },
    },

	"cammy": {
        "count": 1,
		"skins": {
			1: {
				"label": "皮肤1",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": false,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
        },
    },

	"chunli": {
        "count": 1,
		"skins": {
			1: {
				"label": "皮肤1",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": false,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
        },
    },

	"cviper": {
        "count": 1,
		"skins": {
			1: {
				"label": "皮肤1",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
        },
    },

	"dan": {
        "count": 1,
		"skins": {
			1: {
				"label": "皮肤1",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": false,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
        },
    },

	"guile": {
        "count": 1,
		"skins": {
			1: {
				"label": "皮肤1",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": false,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
        },
    },

    "ken": {
        "count": 1,
		"skins": {
			1: {
				"label": "皮肤1",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
        },
    },

	"ryu": {
        "count": 1,
		"skins": {
			1: {
				"label": "皮肤1",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
        },
    },

	"sagat": {
        "count": 1,
		"skins": {
			1: {
				"label": "皮肤1",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": false,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
        },
    },

	"vega": {
        "count": 1,
		"skins": {
			1: {
				"label": "皮肤1",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
        },
    },

	"zangief": {
        "count": 1,
		"skins": {
			1: {
				"label": "皮肤1",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": false,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
        },
		"Note":"S3 END"
    },

	"specter": {
		"Note":"S4 START",
        "count": 1,
		"skins": {
			1: {
				"label": "皮肤1:橘右京(觉醒加强3G A+)",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
        },
    },

	"enchantress": {
        "count": 1,
		"skins": {
			1: {
				"label": "皮肤1:夏米尔",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
        },
    },

	"tinker": {
        "count": 1,
		"skins": {
			1: {
				"label": "原皮(加强):20HP开局",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": false,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
        },
    },

	"ragna": {
		"Note":"S5 START",
		"count": 1,
		"skins": {
			1: {
				"label": "皮肤1:八神庵",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
		},
	},

	"jin": {
		"Note":"S5 START",
		"count": 1,
		"skins": {
			1: {
				"label": "皮肤1:草T京",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
		},
	},

	"rachel": {
		"count": 1,
		"skins": {
			1: {
				"label": "皮肤1:僵尸泪泪道士灵灵",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": true,
 			    "buddy_skin": true,
			},
		},
	},
	
	"noel": {
		"count": 1,
		"skins": {
			1: {
				"label": "皮肤1:不知火舞(加强A)",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
		},
	},

	"taokaka": {
		"count": 1,
		"skins": {
			1: {
				"label": "皮肤1:丽安娜(觉醒加强1攻)",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
		},
	},

	"mika": {
		"Note":"S4 START",
        "count": 1,
		"skins": {
			1: {
				"label": "原皮(加强):34HP开局",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": false,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
        },
    },


	"ino": {
		"Note":"S7 START",
        "count": 1,
		"skins": {
			1: {
				"label": "皮肤1:gg新立绘",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
        },
    },
	"potemkin": {
        "count": 1,
		"skins": {
			1: {
				"label": "皮肤1:gg新立绘",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
        },
    },
	"millia": {
        "count": 1,
		"skins": {
			1: {
				"label": "皮肤1:gg新立绘",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
        },
    },

	"zacoal": {
		"Note":"S8 START",
        "count": 1,
		"skins": {
			1: {
				"label": "皮肤1: 塞恩",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
        },
    },
	"akimo": {
        "count": 1,
		"skins": {
			1: {
				"label": "皮肤1: 孙悟空",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": true,
 			    "buddy_skin": false,
			},
        },
    },
	"astryda": {
        "count": 1,
		"skins": {
			1: {
				"label": "皮肤1: 娜美",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
        },
    },
	"kohai": {
        "count": 1,
		"skins": {
			1: {
				"label": "皮肤1: 派克",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
        },
    },
	"doomies": {
        "count": 1,
		"skins": {
			1: {
				"label": "皮肤1: 亚索",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
        },
    },
	"shafathi": {
        "count": 1,
		"skins": {
			1: {
				"label": "皮肤1: 艾克",
				"portraits_skin": false,
				"portraits_url": "",
				"animations_skin": true,
 			    "exceed_change_skin": false,
 			    "buddy_skin": false,
			},
        },
    },
}

func get_skin_count(char_id: String) -> int:
	var skin_info = _get_skin_info(char_id)
	return max(int(skin_info.get("count", 0)), 0)

func get_total_button_count(char_id: String) -> int:
	return get_skin_count(char_id) + 1

func get_button_label(char_id: String, skin_index: int) -> String:
	if skin_index <= 0:
		return DEFAULT_SKIN_LABEL

	var skin = _get_skin(char_id, skin_index)
	return str(skin.get("label", DEFAULT_EXTRA_SKIN_LABEL % skin_index))

func get_portrait_override_path(char_id: String, skin_index: int) -> String:
	if skin_index <= 0 or skin_index > get_skin_count(char_id):
		return ""

	var skin = _get_skin(char_id, skin_index)
	if skin.get("portraits_skin", false) != true:
		return ""
	var portrait_override = str(skin.get("portraits_url", ""))
	if portrait_override.is_empty():
		portrait_override = "res://assets/portraits_skin/%s.png" % get_skin_deck_id(char_id, skin_index)
	return portrait_override

func get_portrait_path(char_id: String, skin_index: int) -> String:
	var portrait_override = get_portrait_override_path(char_id, skin_index)
	if portrait_override and ResourceLoader.exists(portrait_override, "Texture2D"):
		return portrait_override
	return _get_existing_portrait_or_fallback(ImageCache.get_local_portrait_path(char_id))

func get_base_character_id(deck_id: String) -> String:
	for char_id in CHARACTER_SKINS:
		for skin_index in range(1, get_skin_count(char_id) + 1):
			if get_skin_deck_id(char_id, skin_index) == deck_id:
				return char_id
	return deck_id

func get_portrait_override_path_for_deck_id(deck_id: String) -> String:
	for char_id in CHARACTER_SKINS:
		for skin_index in range(1, get_skin_count(char_id) + 1):
			if get_skin_deck_id(char_id, skin_index) == deck_id:
				return get_portrait_override_path(char_id, skin_index)
	return ""

func get_portrait_path_for_deck_id(deck_id: String) -> String:
	var split_index = deck_id.find("#")
	if split_index != -1:
		deck_id = deck_id.substr(split_index + 1)
	for char_id in CHARACTER_SKINS:
		for skin_index in range(1, get_skin_count(char_id) + 1):
			if get_skin_deck_id(char_id, skin_index) == deck_id:
				return get_portrait_path(char_id, skin_index)
	return _get_existing_portrait_or_fallback(ImageCache.get_local_portrait_path(deck_id))

func load_portrait_texture_for_deck_id(deck_id: String) -> Texture2D:
	return load(get_portrait_path_for_deck_id(deck_id)) as Texture2D

func _get_existing_portrait_or_fallback(portrait_path: String) -> String:
	if ResourceLoader.exists(portrait_path, "Texture2D"):
		return portrait_path
	return FALLBACK_PORTRAIT_PATH

func get_animation_path_for_deck_id(deck_id: String) -> String:
	return get_animation_path_for_deck_and_animation_id(deck_id, deck_id)

func get_animation_path_for_deck_and_animation_id(deck_id: String, animation_id: String) -> String:
	for char_id in CHARACTER_SKINS:
		for skin_index in range(1, get_skin_count(char_id) + 1):
			var skin_deck_id = get_skin_deck_id(char_id, skin_index)
			var skin = _get_skin(char_id, skin_index)
			if deck_id == skin_deck_id + "_exceed" and \
					skin.get("animations_skin", false) == true and \
					skin.get("exceed_change_skin", false) == true:
				return "res://assets/character_animations_skin/%s/animations.tres" % deck_id
			if skin_deck_id != deck_id:
				continue
			var animations_skin_enabled = skin.get("animations_skin", false) == true
			if animation_id != deck_id and animations_skin_enabled and skin.get("buddy_skin", false) == true:
				var exact_buddy_skin_path = "res://assets/character_animations_skin/%s/animations.tres" % animation_id
				if _animation_resource_exists(exact_buddy_skin_path):
					return exact_buddy_skin_path
				var buddy_skin_path = "res://assets/character_animations_skin/%s_%d/animations.tres" % [animation_id, skin_index]
				if _animation_resource_exists(buddy_skin_path):
					return buddy_skin_path
				var normalized_buddy_id = _remove_skin_suffix_if_matches(animation_id, skin_index)
				if normalized_buddy_id != animation_id:
					var normalized_buddy_skin_path = "res://assets/character_animations_skin/%s_%d/animations.tres" % [normalized_buddy_id, skin_index]
					if _animation_resource_exists(normalized_buddy_skin_path):
						return normalized_buddy_skin_path
			if animations_skin_enabled:
				if animation_id == deck_id:
					return "res://assets/character_animations_skin/%s/animations.tres" % deck_id
				if animation_id == "%s_exceed" % deck_id:
					if skin.get("exceed_change_skin", false) == true:
						return "res://assets/character_animations_skin/%s/animations.tres" % animation_id
					return "res://assets/character_animations_skin/%s/animations.tres" % deck_id
			if animation_id == deck_id:
				return "res://assets/character_animations/%s/animations.tres" % char_id
			var normalized_animation_id = _remove_skin_suffix_if_matches(animation_id, skin_index)
			return "res://assets/character_animations/%s/animations.tres" % normalized_animation_id
	var official_path = "res://assets/character_animations/%s/animations.tres" % animation_id
	var custom_path = "res://assets/character_animations_custom/%s/animations.tres" % animation_id
	if ResourceLoader.exists(custom_path, "SpriteFrames"):
		return custom_path
	if _animation_resource_exists(official_path):
		return official_path
	return official_path

func _animation_resource_exists(resource_path: String) -> bool:
	return ResourceLoader.exists(resource_path, "SpriteFrames") or CdnAssetLoader.is_cdn_mapped_res_path(resource_path)

func get_skin_index_for_deck_id(deck_id: String) -> int:
	for char_id in CHARACTER_SKINS:
		for skin_index in range(1, get_skin_count(char_id) + 1):
			if get_skin_deck_id(char_id, skin_index) == deck_id:
				return skin_index
	return 0

func uses_skin_animation_for_deck_id(deck_id: String) -> bool:
	for char_id in CHARACTER_SKINS:
		for skin_index in range(1, get_skin_count(char_id) + 1):
			if get_skin_deck_id(char_id, skin_index) == deck_id:
				return _get_skin(char_id, skin_index).get("animations_skin", false) == true
	return false

func exceed_changes_skin_for_deck_id(deck_id: String) -> bool:
	for char_id in CHARACTER_SKINS:
		for skin_index in range(1, get_skin_count(char_id) + 1):
			if get_skin_deck_id(char_id, skin_index) == deck_id:
				var skin = _get_skin(char_id, skin_index)
				return skin.get("animations_skin", false) == true and \
						skin.get("exceed_change_skin", false) == true
	return false

func get_skin_deck_id(char_id: String, skin_index: int) -> String:
	if skin_index <= 0:
		return char_id
	if char_id.begins_with("random") or char_id.begins_with("custom_"):
		return char_id
	if skin_index > get_skin_count(char_id):
		return char_id
	return "%s_%d" % [char_id, skin_index]

func _get_skin_info(char_id: String) -> Dictionary:
	return CHARACTER_SKINS.get(char_id, {})

func _get_skin(char_id: String, skin_index: int) -> Dictionary:
	var skins: Dictionary = _get_skin_info(char_id).get("skins", {})
	return skins.get(skin_index, {})

func _remove_skin_suffix_if_matches(animation_id: String, skin_index: int) -> String:
	var suffix = "_%d" % skin_index
	if animation_id.ends_with(suffix):
		return animation_id.substr(0, animation_id.length() - suffix.length())
	return animation_id