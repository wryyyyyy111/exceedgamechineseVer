extends RefCounted

const NORMAL_CARD_NAMES_CN = {
	"grasp": "投技",
	"cross": "游击",
	"assault": "突袭",
	"dive": "飞踢",
	"spike": "刺拳",
	"sweep": "横扫",
	"focus": "专注",
	"block": "格挡",
}
const MAX_CONTEXT_MATCHERS := 64

class NameMatcher:
	var name_hints: Dictionary
	var id_hints: Dictionary
	var regex: RegEx
	var existing_hint_regex: RegEx

	func annotate(text: String) -> String:
		if text.is_empty() or (name_hints.is_empty() and id_hints.is_empty()):
			return text
		var result := ""
		var previous_end := 0
		for token in regex.search_all(text):
			var card_name := token.get_string(1)
			if card_name.is_empty():
				continue
			var suffix: String = name_hints.get(card_name, id_hints.get(card_name, ""))
			if suffix.is_empty() or existing_hint_regex.search(text.substr(token.get_end())):
				continue
			result += text.substr(previous_end, token.get_end() - previous_end) + suffix
			previous_end = token.get_end()
		return result + text.substr(previous_end)

var speed_hints_by_deck: Dictionary = {}
var _duplicate_speed_card_ids: Dictionary = {}
var _card_stats: Dictionary = {}
var _id_hints: Dictionary = {}
var _global_matcher: NameMatcher
var _context_matchers: Dictionary = {}
var _existing_hint_regex := RegEx.create_from_string(
	"^(?:\\[/[^\\]]+\\]|\\s)*[（(][普特必](?:[^）)\\r\\n]+速(?:[^）)\\r\\n]+攻)?|速[^）)\\r\\n]+攻[^）)\\r\\n]+)[）)]"
)

func rebuild(card_definitions: Dictionary, decks: Dictionary):
	speed_hints_by_deck = {}
	_duplicate_speed_card_ids = {}
	_card_stats = {}
	_id_hints = {}
	_context_matchers.clear()
	for deck_id in decks:
		var deck: Dictionary = decks[deck_id]
		var custom_definitions := {}
		for definition in deck.get("custom_card_definitions", []):
			custom_definitions[definition["id"]] = definition
		var definitions := {}
		var groups := {}
		for card in deck.get("cards", []):
			var card_id: String = card.get("definition_id", "")
			if definitions.has(card_id):
				continue
			var definition = card_definitions.get(card_id, custom_definitions.get(card_id))
			if not definition:
				continue
			definitions[card_id] = definition
			if definition.get("speed") == null:
				continue
			var key := "%s:%s" % [definition.get("type", ""), _format_number(definition["speed"])]
			if not groups.has(key):
				groups[key] = []
			groups[key].append(card_id)
		var duplicate_ids := {}
		for group in groups.values():
			if group.size() > 1:
				for card_id in group:
					duplicate_ids[card_id] = true
					_duplicate_speed_card_ids[card_id] = true
		var deck_hints := {}
		for card_id in definitions:
			deck_hints[card_id] = _build_speed_description(definitions[card_id], duplicate_ids)
		speed_hints_by_deck[deck_id] = deck_hints

	for card_id in card_definitions:
		var definition: Dictionary = card_definitions[card_id]
		_card_stats[card_id] = {
			"type": definition.get("type", ""),
			"speed": definition.get("speed"),
			"power": definition.get("power", 0),
		}
		_id_hints[card_id] = _build_speed_description(definition, _duplicate_speed_card_ids)
	_global_matcher = _build_matcher(card_definitions.values())

func get_speed_description(definition: Variant) -> String:
	if not definition:
		return ""
	var card_id: String = definition.get("id", "")
	if _card_stats.has(card_id):
		var stats: Dictionary = _card_stats[card_id]
		if stats["type"] == definition.get("type", "") \
				and stats["speed"] == definition.get("speed") \
				and stats["power"] == definition.get("power", 0):
			return _id_hints[card_id]
	# Ad-hoc display definitions may share an ID but have different printed stats.
	return _build_speed_description(definition, _duplicate_speed_card_ids)

func get_matcher(card_definitions: Array = []) -> NameMatcher:
	if card_definitions.is_empty():
		return _global_matcher
	var definition_keys := {}
	for definition in card_definitions:
		var key := JSON.stringify([
			definition.get("id", ""), definition.get("display_name", ""),
			definition.get("type", ""), definition.get("speed"), definition.get("power", 0),
		])
		definition_keys[key] = true
	var keys: Array = definition_keys.keys()
	keys.sort()
	var context_key := "\n".join(keys)
	if not _context_matchers.has(context_key):
		if _context_matchers.size() >= MAX_CONTEXT_MATCHERS:
			_context_matchers.erase(_context_matchers.keys()[0])
		_context_matchers[context_key] = _build_matcher(card_definitions)
	return _context_matchers[context_key]

func _build_matcher(definitions: Array) -> NameMatcher:
	var matcher := NameMatcher.new()
	matcher.name_hints = {}
	matcher.id_hints = _id_hints
	matcher.existing_hint_regex = _existing_hint_regex
	for definition in definitions:
		var display_name: String = definition.get("display_name", "")
		if display_name.is_empty():
			continue
		var suffix := get_speed_description(definition)
		_add_name_hint(matcher.name_hints, display_name, suffix)
		var normal_name := display_name.to_lower()
		if normal_name in NORMAL_CARD_NAMES_CN:
			_add_name_hint(matcher.name_hints, NORMAL_CARD_NAMES_CN[normal_name], suffix)
			_add_name_hint(matcher.name_hints, normal_name.capitalize(), suffix)
	for card_name in matcher.name_hints:
		if _id_hints.has(card_name) and _id_hints[card_name] != matcher.name_hints[card_name]:
			matcher.name_hints[card_name] = ""
	var names: Array = _id_hints.keys()
	for card_name in matcher.name_hints:
		if not _id_hints.has(card_name):
			names.append(card_name)
	names.sort_custom(func(a: String, b: String): return a.length() > b.length())
	var escaped_names := PackedStringArray()
	for card_name in names:
		for character in ["\\", ".", "^", "$", "*", "+", "?", "(", ")", "[", "]", "{", "}", "|"]:
			card_name = card_name.replace(character, "\\" + character)
		escaped_names.append(card_name)
	matcher.regex = RegEx.new()
	var pattern := "\\[[^\\]]*\\]"
	if not escaped_names.is_empty():
		pattern += "|((?<![A-Za-z0-9_])(?:%s)(?![A-Za-z0-9_]))" % "|".join(escaped_names)
	var error := matcher.regex.compile(pattern)
	if error != OK:
		push_error("Unable to compile card-name index matcher: %s" % error)
	assert(error == OK, "Unable to compile card-name index matcher: %s" % error)
	return matcher

func _add_name_hint(hints: Dictionary, card_name: String, suffix: String):
	if hints.has(card_name) and hints[card_name] != suffix:
		hints[card_name] = ""
	else:
		hints[card_name] = suffix

func _build_speed_description(definition: Dictionary, duplicate_ids: Dictionary) -> String:
	var speed = definition.get("speed")
	if speed == null:
		return ""
	var prefix := ""
	match definition.get("type", ""):
		"normal": prefix = "普"
		"special": prefix = "特"
		"ultra": prefix = "必"
		_: return ""
	if duplicate_ids.has(definition.get("id", "")):
		return "（%s%s速%s攻）" % [prefix, _format_number(speed), _format_number(definition.get("power", 0))]
	return "（%s%s速）" % [prefix, _format_number(speed)]

func _format_number(value: Variant) -> String:
	if value is float and value == int(value):
		return str(int(value))
	return str(value)
