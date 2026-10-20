class_name MatchQueueItem
extends MarginContainer

const QUEUE_NOTIFY_COOLDOWN_SECONDS := 120
const HP_RANK_QUEUE_ID := "hp_rank_mode"
const DEFAULT_QUEUE_LABEL_COLOR := Color(0.15, 1, 1, 1)
const HP_RANK_LABEL_COLOR := Color(1, 0.72, 0.72, 1)
static var _last_queue_notify_unix_time : int = -999999

const WAITING_CHARACTER_MAP := {
	"豪鬼": "Akuma",
	"暗慈": "Anji Mito",
	"亚拉酷泥": "Arakune",
	"阿克塞尔": "Axl Low",
	"梅喧": "Baiken",
	"白夜": "Byakuya",
	"腥红毒蛇": "C. Viper",
	"嘉米": "Cammy",
	"卡路路": "Carl Clover",
	"卡尔": "Carl Swangee",
	"卡门": "Carmine",
	"赛琳卡": "Celinka",
	"凯亚斯": "Chaos",
	"奇普": "Chipp Zanuff",
	"春丽": "Chun-Li",
	"弹": "Dan Hibiki",
	"德詹妮特": "D'Janette",
	"伊莫金": "Emogine",
	"恩奇都": "Enkidu",
	"尤金尼娅": "Eugenia",
	"浮士德": "Faust",
	"战斗": "Fight",
	"加尔德雷德": "Galdred",
	"杰弗里": "Geoffrey",
	"乔凡娜": "Giovanna",
	"戈德刘易斯": "Goldlewis Dickinson",
	"戈鲁多": "Gordeau",
	"古烈": "Guile",
	"白面": "Hakumen",
	"哈皮": "Happy Chaos",
	"哈扎马": "Hazama",
	"希尔妲": "Hilda",
	"灰都": "Hyde Kido",
	"伊奎斯": "Iaquis",
	"伊诺": "I-No",
	"帝卡": "Iron Tager",
	"露西娅": "Luciya",
	"婕克": "Jack-O",
	"琴恩": "Jin Kisaragi",
	"肯": "Ken Masters",
	"国王骑士": "King Knight",
	"九重": "Kokonoe Mercury",
	"凯": "Ky Kiske",
	"雷奥": "Leo Whitefang",
	"凛音": "Linne",
	"莉琪": "Litchi Faye Ling",
	"隆德雷奇亚": "Londrekia Light",
	"拜森": "M. Bison",
	"梅伊": "May",
	"梅莲": "Mei Lian",
	"梅尔卡瓦": "Merkava",
	"美香": "Mika Returna",
	"米莉亚": "Millia Rage",
	"南户": "Minato",
	"瓦格娜": "Miyashiro Wagner",
	"鼹鼠骑士": "Mole Knight",
	"莫拉西": "Morathi",
	"名残雪": "Nagoriyuki",
	"七濑": "Nanase",
	"奈特莉": "Nehtali",
	"奈茵": "Nine the Phantom",
	"诺艾儿": "Noel Vermillion",
	"No.13": "Nu-13",
	"织江": "Orie Ballardiae",
	"芙诺": "Phonon",
	"瘟疫骑士": "Plague Knight",
	"白金": "Platinum the Trinity",
	"极地骑士": "Polar Knight",
	"波乔姆金": "Potemkin",
	"螺旋桨骑士": "Propeller Knight",
	"雷其儿": "Rachel Alucard",
	"拉格纳": "Ragna the Bloodedge",
	"拉姆蕾萨尔": "Ramlethal Valentine",
	"蕾米莉丝": "Remiliss",
	"蕾尼娅": "Renea",
	"隆": "Ryu",
	"沙加特": "Sagat",
	"清顺": "Seijun",
	"赛特": "Seth",
	"狮子神": "Shishigami Bang",
	"铲子骑士&圆盾骑士铲子骑士": "Shovel & Shield Knight",
	"铲子骑士&圆盾骑士": "Shovel & Shield Knight",
	"铲子骑士": "Shovel Knight",
	"索尔": "Sol Badguy",
	"幽灵骑士": "Specter Knight",
	"超级骨头侠33": "Super Skull Man 33",
	"西德尼&塞丽娜": "Sydney & Serena",
	"塞勒斯": "Syrus",
	"大成": "Taisei",
	"桃儿卡卡": "Taokaka",
	"泰斯塔门特": "Testament",
	"被斩首者": "The Beheaded",
	"远古魔女": "The Enchantress",
	"工匠骑士": "Tinker Knight",
	"宝藏骑士": "Treasure Knight",
	"托内鲁斯": "Tournelouse",
	"芭荻斯塔": "Vatista",
	"维嘉": "Vega",
	"文森特": "Vincent",
	"瓦伦斯坦": "Waldstein",
	"让叶": "Yuzuriha",
	"桑吉尔夫": "Zangief",
	"萨度": "Zato-1",
	"佐尔特": "Zsolt",
}

const WAITING_CHARACTER_ENGLISH_ALIASES := {
	"Ky Kiske": "凯",
	"Ky Kisuke": "凯",
	"Meilian / Meilien": "梅莲",
	"Mei Lian": "梅莲",
	"Shovel & Shield Knight": "铲子骑士&圆盾骑士",
	"Tournelouse": "托内鲁斯",
	"Luciya": "露西娅",
	"Renea": "蕾尼娅",
	"Syrus": "塞勒斯",
}

signal on_join_queue(id, match_available)

@onready var queue_label = $QueueVBox/QueueLabel
@onready var join_button = $QueueVBox/JoinButton
@onready var play_button = $QueueVBox/PlayContainer/PlayButton
@onready var play_container = $QueueVBox/PlayContainer
@onready var waiting_character_label = $QueueVBox/WaitingCharacterLabel

var	queue_id : String
var _queue_name : String

static var _waiting_character_keywords := WAITING_CHARACTER_MAP.keys()
static var _waiting_character_english_keywords := []
static var _waiting_character_mapped_english_keywords := []

static func get_waiting_character_display(queue_info : Dictionary) -> String:
	if str(queue_info.get("id", "")) == HP_RANK_QUEUE_ID:
		return ""
	return _convert_english_to_chinese(_resolve_waiting_character_name(_get_waiting_character_value(queue_info)))

func initialize_queue(id : String, queue_name : String, match_available : bool, waiting_character = null):
	queue_id = id
	_queue_name = queue_name
	queue_label.text = queue_name
	_apply_queue_visual_style()
	_set_waiting_character(waiting_character)
	
	set_match_available(match_available)

func _apply_queue_visual_style() -> void:
	if queue_id == HP_RANK_QUEUE_ID:
		queue_label.add_theme_color_override("font_color", HP_RANK_LABEL_COLOR)
	else:
		queue_label.add_theme_color_override("font_color", DEFAULT_QUEUE_LABEL_COLOR)

func set_enabled(enable : bool):
	join_button.disabled = not enable
	play_button.disabled = not enable

func get_match_available() -> bool:
	return play_button.visible

func set_match_available(match_available : bool):
	join_button.visible = not match_available
	play_button.visible = match_available
	play_container.visible = match_available
	waiting_character_label.visible = match_available and waiting_character_label.text != ""

func _set_waiting_character(waiting_character) -> void:
	if queue_id == HP_RANK_QUEUE_ID:
		waiting_character_label.text = ""
		return
	var display_name = _convert_english_to_chinese(_resolve_waiting_character_name(waiting_character))
	if display_name == "":
		waiting_character_label.text = ""
	else:
		waiting_character_label.text = "等待匹配: %s" % display_name

static func _get_waiting_character_value(queue_info : Dictionary):
	for key in ["waiting_character", "waiting_deck", "waiting_deck_id"]:
		if not queue_info.has(key):
			continue
		var value = queue_info[key]
		if value == null:
			continue
		if str(value).strip_edges() != "":
			return value
	return null

static func _resolve_waiting_character_name(waiting_character) -> String:
	if waiting_character == null:
		return ""

	var raw_name = str(waiting_character).strip_edges()
	if raw_name == "":
		return ""

	var normalized_deck_id = raw_name
	var split_index = normalized_deck_id.find("#")
	if split_index != -1:
		normalized_deck_id = normalized_deck_id.substr(split_index + 1)
	elif normalized_deck_id.begins_with("random"):
		return "Random"

	var deck = null
	if CardDataManager.decks.has(normalized_deck_id):
		deck = CardDataManager.get_deck(normalized_deck_id)
	if deck:
		return deck.get("display_name", raw_name)

	for keyword in _get_waiting_character_keywords():
		if keyword in raw_name:
			return WAITING_CHARACTER_MAP[keyword]

	return raw_name

static func _convert_english_to_chinese(english_name : String) -> String:
	var normalized_name = english_name.strip_edges()
	if normalized_name == "":
		return ""

	if WAITING_CHARACTER_ENGLISH_ALIASES.has(normalized_name):
		return WAITING_CHARACTER_ENGLISH_ALIASES[normalized_name]

	var normalized_lower = normalized_name.to_lower()
	for english_keyword in _get_waiting_character_english_keywords():
		if english_keyword.to_lower() in normalized_lower:
			return WAITING_CHARACTER_ENGLISH_ALIASES[english_keyword]

	for chinese_keyword in _get_waiting_character_mapped_english_keywords():
		var mapped_english_name = WAITING_CHARACTER_MAP[chinese_keyword]
		if mapped_english_name.to_lower() in normalized_lower:
			return chinese_keyword

	return normalized_name

static func _get_waiting_character_keywords() -> Array:
	if _waiting_character_keywords.is_empty():
		_waiting_character_keywords = WAITING_CHARACTER_MAP.keys()
		_waiting_character_keywords.sort_custom(func(a, b): return a.length() > b.length())
	return _waiting_character_keywords

static func _get_waiting_character_english_keywords() -> Array:
	if _waiting_character_english_keywords.is_empty():
		_waiting_character_english_keywords = WAITING_CHARACTER_ENGLISH_ALIASES.keys()
		_waiting_character_english_keywords.sort_custom(func(a, b): return a.length() > b.length())
	return _waiting_character_english_keywords

static func _get_waiting_character_mapped_english_keywords() -> Array:
	if _waiting_character_mapped_english_keywords.is_empty():
		_waiting_character_mapped_english_keywords = WAITING_CHARACTER_MAP.keys()
		_waiting_character_mapped_english_keywords.sort_custom(func(a, b):
			return WAITING_CHARACTER_MAP[a].length() > WAITING_CHARACTER_MAP[b].length())
	return _waiting_character_mapped_english_keywords

func _can_send_queue_notification() -> bool:
	var now_unix = int(Time.get_unix_time_from_system())
	if now_unix - _last_queue_notify_unix_time < QUEUE_NOTIFY_COOLDOWN_SECONDS:
		return false
	_last_queue_notify_unix_time = now_unix
	return true

func _send_queue_notification() -> void:
	if not _can_send_queue_notification():
		return
	var t = Time.get_time_dict_from_system()
	var time_str = "%02d:%02d" % [t["hour"], t["minute"]]
	var msg = "-----------有人正在队列%s等待 %s-----------\n-----------有人正在队列%s等待 %s-----------\n-----------有人正在队列%s等待 %s-----------" % [queue_id, time_str, queue_id, time_str, queue_id, time_str]
	var body = JSON.stringify({"group_id": 1064964514, "message": msg})
	var headers := PackedStringArray()
	headers.append("Content-Type: application/json")
	headers.append("Authorization: Bearer my_secret_token_mdl123")
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_result, response_code, _headers, body_bytes):
		if response_code != 200:
			push_warning("QQ通知发送失败，HTTP状态码: %d，返回: %s" % [response_code, body_bytes.get_string_from_utf8()])
		http.queue_free()
	)
	var err = http.request("https://exceedcntyd.com/bot/send_group_msg", headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		push_error("发送QQ通知请求失败，错误码: %d" % err)
		http.queue_free()

func _on_join_button_pressed() -> void:
	on_join_queue.emit(queue_id, false)

func _on_play_button_pressed() -> void:
	on_join_queue.emit(queue_id, true)
