class_name MobileResourceBudget
extends RefCounted

const BYTES_PER_RGBA_PIXEL := 4.0
const RESOURCE_BUDGET_LIMIT_MB := 50.0
const GREEN_LIMIT_MB := 25.0
const WARNING_LIMIT_MB := 35.0
const ESTIMATED_MEMORY_MULTIPLIER := 2.0

static var enabled_override = null
static var entries := {}
static var warning_messages: Array[String] = []

static func is_mobile_runtime() -> bool:
	if enabled_override != null:
		return enabled_override
	return MobileRuntimeFlags.is_mobile_resource_runtime()

static func reset():
	entries.clear()
	warning_messages.clear()

static func estimate_decoded_mb(width: int, height: int) -> float:
	return float(width) * float(height) * BYTES_PER_RGBA_PIXEL / 1024.0 / 1024.0

static func estimate_budget_mb(width: int, height: int) -> float:
	return estimate_decoded_mb(width, height) * ESTIMATED_MEMORY_MULTIPLIER

static func get_total_budget_mb() -> float:
	var total := 0.0
	for entry in entries.values():
		total += float(entry.get("budget_mb", 0.0))
	return total

static func get_state() -> String:
	var total := get_total_budget_mb()
	if total > RESOURCE_BUDGET_LIMIT_MB:
		return "red"
	if total > WARNING_LIMIT_MB:
		return "orange"
	if total > GREEN_LIMIT_MB:
		return "yellow"
	return "green"

static func can_load(_resource_key: String, width: int, height: int, priority := "visible") -> bool:
	if not is_mobile_runtime():
		return true
	var projected_total := get_total_budget_mb() + estimate_budget_mb(width, height)
	if priority in ["critical", "visible"]:
		return true
	return projected_total <= RESOURCE_BUDGET_LIMIT_MB

static func register_texture(resource_key: String, width: int, height: int, owner := "unknown", priority := "visible") -> bool:
	if not is_mobile_runtime():
		return true
	var decoded_mb := estimate_decoded_mb(width, height)
	var budget_mb := decoded_mb * ESTIMATED_MEMORY_MULTIPLIER
	entries[resource_key] = {
		"owner": owner,
		"priority": priority,
		"width": width,
		"height": height,
		"decoded_mb": decoded_mb,
		"budget_mb": budget_mb,
	}
	var total := get_total_budget_mb()
	if total > WARNING_LIMIT_MB:
		var message := "[MobileResourceBudget] %s %.2fMB after %s" % [get_state(), total, resource_key]
		warning_messages.append(message)
		push_warning(message)
	return total <= RESOURCE_BUDGET_LIMIT_MB or priority in ["critical", "visible"]

static func unregister(resource_key: String):
	entries.erase(resource_key)

static func unregister_owner(owner: String):
	for resource_key in entries.keys():
		if entries[resource_key].get("owner", "") == owner:
			entries.erase(resource_key)

static func get_debug_text() -> String:
	return "资源预算: %s %.1fMB/%sMB 条目:%d" % [
		get_state(),
		get_total_budget_mb(),
		RESOURCE_BUDGET_LIMIT_MB,
		entries.size(),
	]
