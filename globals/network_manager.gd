extends Node

signal disconnected_from_server
signal connected_to_server(server_name)
signal room_join_failed(error_message)
signal request_failed(error_message)
signal game_started(data)
signal game_message_received(message)
signal observe_started(data)
signal other_player_quit(is_disconnect)
signal players_update(players, matches, queues, newly_available_match)
signal customs_update(customs)
signal name_update(name)
signal reconnect_state_changed(state)
signal waiting_for_opponent_reconnect_changed(is_waiting, seconds)
signal session_restore_requested(context)
signal session_restore_succeeded(data)
signal session_restore_failed(reason)
signal matchlog_upload_finished(success, uploaded, error_message)

enum NetworkState {
	NetworkState_NotConnected,
	NetworkState_Connecting,
	NetworkState_Connected,
}

var network_state = NetworkState.NetworkState_NotConnected
var cached_players = []
var cached_matches = []
var cached_queues = []
var cached_customs = {}

const AUTO_RECONNECT_INTERVAL_SECONDS = 5.0
const AUTO_RECONNECT_MANUAL_THRESHOLD_SECONDS = 100
const SERVER_KEEPALIVE_TIMEOUT_SECONDS = 15.0

enum RestoreContextType {
	RestoreContextType_None,
	RestoreContextType_Lobby,
	RestoreContextType_Room,
	RestoreContextType_Matchmaking,
	RestoreContextType_Game,
	RestoreContextType_Observe,
}

var reconnect_state = {
	"is_auto_reconnecting": false,
	"auto_retry_enabled": false,
	"reconnect_seconds": 0,
	"last_reconnect_attempt_time": -1.0,
	"is_manual_reconnect": false,
	"pre_disconnect_state": RestoreContextType.RestoreContextType_None,
	"was_in_game": false,
	"is_waiting_for_opponent_reconnect": false,
	"waiting_for_opponent_reconnect_seconds": 0,
	"user_cancelled": false,
	"disconnect_reason": "",
}

var _reconnect_elapsed := 0.0
var _next_auto_reconnect_in := AUTO_RECONNECT_INTERVAL_SECONDS
var _is_expected_disconnect := false
var _pending_restore_context = {}
var _waiting_for_opponent_reconnect_elapsed := 0.0
var _last_connected_server_name := ""
var _restore_request_sent := false
var _awaiting_name_sync := false
var _current_server_player_id = null
var _previous_server_player_id = null
var _current_server_session_id = ""
var _previous_server_session_id = ""
var _current_server_session_token = ""
var _previous_server_session_token = ""
var _last_server_keepalive_time := -1.0
var _server_keepalive_tracking := false
var _web_page_hidden := false
var _web_page_lifecycle_initialized := false
var _web_pagehide_callback
var _web_pageshow_callback
var _web_visibility_callback
var _web_document
var _waiting_for_restore_name_sync := false
var _pending_disconnect_confirmation_player_id = null
var _waiting_for_disconnect_confirmation = false
var _active_remote_match_finished := false

const ecs_url = "wss://exceedcntyd.com"
const local_url = "ws://localhost:8080"

var _socket = null

# Called when the node enters the scene tree for the first time.
func _ready():
	_setup_web_page_lifecycle()

static func should_pause_server_keepalive(page_hidden : bool, state : NetworkState) -> bool:
	return page_hidden or state != NetworkState.NetworkState_Connected

func _setup_web_page_lifecycle():
	if _web_page_lifecycle_initialized or not OS.has_feature("web"):
		return
	var window = JavaScriptBridge.get_interface("window")
	_web_document = JavaScriptBridge.get_interface("document")
	if window == null or _web_document == null:
		return
	_web_pagehide_callback = JavaScriptBridge.create_callback(_on_web_pagehide)
	_web_pageshow_callback = JavaScriptBridge.create_callback(_on_web_pageshow)
	_web_visibility_callback = JavaScriptBridge.create_callback(_on_web_visibility_changed)
	window.addEventListener("pagehide", _web_pagehide_callback)
	window.addEventListener("pageshow", _web_pageshow_callback)
	_web_document.addEventListener("visibilitychange", _web_visibility_callback)
	_web_page_lifecycle_initialized = true
	_web_page_hidden = bool(_web_document.hidden)

func _on_web_pagehide(_args = null):
	_web_page_hidden = true

func _on_web_pageshow(_args = null):
	if not _web_page_hidden:
		return
	_web_page_hidden = false
	_handle_sockets()
	if network_state == NetworkState.NetworkState_Connected and _is_socket_open():
		_record_server_keepalive()
		return
	if _socket == null and not is_reconnect_active():
		attempt_manual_reconnect()

func _on_web_visibility_changed(_args = null):
	if _web_document == null:
		return
	if bool(_web_document.hidden):
		_on_web_pagehide()
	else:
		_on_web_pageshow()

func _clear_lobby_cache(emit_update := true):
	cached_players = []
	cached_matches = []
	cached_queues = []
	if emit_update:
		players_update.emit(cached_players, cached_matches, cached_queues, false)

func get_restore_context() -> Dictionary:
	return _pending_restore_context.duplicate(true)

func is_server_connected() -> bool:
	return _socket != null

func connect_to_server():
	if _socket != null: return
	_socket = WebSocketPeer.new()
	var server_url = GlobalSettings.get_server_url()
	var result = _socket.connect_to_url(server_url)
	if result != OK:
		_socket = null
		network_state = NetworkState.NetworkState_NotConnected
		_reset_server_keepalive_tracking()
		if reconnect_state["is_auto_reconnecting"] or reconnect_state["is_manual_reconnect"]:
			_mark_reconnect_attempt_failed("Failed to connect to server: %s" % error_string(result))
		else:
			request_failed.emit("Failed to connect to server: %s" % error_string(result))
		return
	print("Connecting to server...")
	network_state = NetworkState.NetworkState_Connecting
	if reconnect_state["is_auto_reconnecting"] or reconnect_state["is_manual_reconnect"]:
		reconnect_state["last_reconnect_attempt_time"] = Time.get_ticks_msec() / 1000.0
		_emit_reconnect_state_changed()

func attempt_manual_reconnect():
	if _socket != null or network_state == NetworkState.NetworkState_Connecting:
		return false
	if reconnect_state["user_cancelled"]:
		reconnect_state["user_cancelled"] = false
	_reconnect_elapsed = 0.0
	_next_auto_reconnect_in = 0.0
	reconnect_state["is_auto_reconnecting"] = true
	reconnect_state["auto_retry_enabled"] = true
	reconnect_state["is_manual_reconnect"] = false
	reconnect_state["reconnect_seconds"] = 1
	reconnect_state["last_reconnect_attempt_time"] = -1.0
	_awaiting_name_sync = false
	_emit_reconnect_state_changed()
	return true

func get_reconnect_state() -> Dictionary:
	return reconnect_state.duplicate(true)

func is_reconnect_active() -> bool:
	return reconnect_state["is_auto_reconnecting"] or reconnect_state["is_manual_reconnect"]

func is_waiting_for_opponent_reconnect() -> bool:
	return reconnect_state["is_waiting_for_opponent_reconnect"]

func set_restore_context(state_type : RestoreContextType, context : Dictionary = {}):
	_pending_restore_context = context.duplicate(true)
	_pending_restore_context["state_type"] = state_type
	if not _pending_restore_context.has("player_name"):
		_pending_restore_context["player_name"] = _get_preferred_player_name()
	reconnect_state["pre_disconnect_state"] = state_type
	reconnect_state["was_in_game"] = state_type == RestoreContextType.RestoreContextType_Game
	_emit_reconnect_state_changed()

func clear_restore_context(clear_game_flag := true):
	_pending_restore_context = {}
	reconnect_state["pre_disconnect_state"] = RestoreContextType.RestoreContextType_None
	if clear_game_flag:
		reconnect_state["was_in_game"] = false
	_emit_reconnect_state_changed()

func begin_waiting_for_opponent_reconnect():
	if reconnect_state["is_waiting_for_opponent_reconnect"]:
		return
	reconnect_state["is_waiting_for_opponent_reconnect"] = true
	reconnect_state["waiting_for_opponent_reconnect_seconds"] = 1
	_waiting_for_opponent_reconnect_elapsed = 0.0
	waiting_for_opponent_reconnect_changed.emit(true, 1)
	_emit_reconnect_state_changed()
	if _pending_disconnect_confirmation_player_id != null:
		_acknowledge_disconnect_seen(_pending_disconnect_confirmation_player_id)

func end_waiting_for_opponent_reconnect():
	if not reconnect_state["is_waiting_for_opponent_reconnect"]:
		return
	reconnect_state["is_waiting_for_opponent_reconnect"] = false
	reconnect_state["waiting_for_opponent_reconnect_seconds"] = 0
	_waiting_for_opponent_reconnect_elapsed = 0.0
	waiting_for_opponent_reconnect_changed.emit(false, 0)
	_emit_reconnect_state_changed()
	_pending_disconnect_confirmation_player_id = null
	_waiting_for_disconnect_confirmation = false

func cancel_reconnect():
	_abort_reconnect_socket()
	reconnect_state["user_cancelled"] = true
	reconnect_state["is_auto_reconnecting"] = false
	reconnect_state["auto_retry_enabled"] = false
	reconnect_state["is_manual_reconnect"] = true
	reconnect_state["last_reconnect_attempt_time"] = -1.0
	_next_auto_reconnect_in = AUTO_RECONNECT_INTERVAL_SECONDS
	_awaiting_name_sync = false
	_emit_reconnect_state_changed()

func _abort_reconnect_socket():
	if _socket:
		_socket.close()
		_socket = null
	network_state = NetworkState.NetworkState_NotConnected
	_reset_server_keepalive_tracking()

func quit_waiting_for_opponent():
	end_waiting_for_opponent_reconnect()
	leave_room()

func _emit_reconnect_state_changed():
	reconnect_state_changed.emit(get_reconnect_state())

func _mark_reconnect_attempt_failed(reason : String):
	if reason:
		reconnect_state["disconnect_reason"] = reason
	reconnect_state["last_reconnect_attempt_time"] = Time.get_ticks_msec() / 1000.0
	_emit_reconnect_state_changed()

func _begin_unexpected_disconnect(reason := ""):
	if _is_expected_disconnect:
		_is_expected_disconnect = false
		return
	if reconnect_state["is_auto_reconnecting"] or reconnect_state["is_manual_reconnect"]:
		return
	_reconnect_elapsed = 0.0
	_next_auto_reconnect_in = 0.0
	reconnect_state["is_auto_reconnecting"] = true
	reconnect_state["auto_retry_enabled"] = true
	reconnect_state["is_manual_reconnect"] = false
	reconnect_state["reconnect_seconds"] = 1
	reconnect_state["last_reconnect_attempt_time"] = -1.0
	reconnect_state["user_cancelled"] = false
	reconnect_state["disconnect_reason"] = reason
	reconnect_state["was_in_game"] = reconnect_state["pre_disconnect_state"] == RestoreContextType.RestoreContextType_Game
	_previous_server_player_id = _current_server_player_id
	_previous_server_session_id = _current_server_session_id
	_previous_server_session_token = _current_server_session_token
	_restore_request_sent = false
	_awaiting_name_sync = false
	_waiting_for_restore_name_sync = false
	_emit_reconnect_state_changed()

func _end_reconnect_flow(restored : bool):
	_reconnect_elapsed = 0.0
	_next_auto_reconnect_in = AUTO_RECONNECT_INTERVAL_SECONDS
	_restore_request_sent = false
	reconnect_state["is_auto_reconnecting"] = false
	reconnect_state["auto_retry_enabled"] = false
	reconnect_state["is_manual_reconnect"] = false
	reconnect_state["reconnect_seconds"] = 0
	reconnect_state["last_reconnect_attempt_time"] = -1.0
	_awaiting_name_sync = false
	_waiting_for_restore_name_sync = false
	if restored:
		reconnect_state["disconnect_reason"] = ""
	_emit_reconnect_state_changed()

func _request_session_restore():
	if _restore_request_sent:
		return
	if reconnect_state["pre_disconnect_state"] == RestoreContextType.RestoreContextType_None and not _has_previous_restore_identity():
		_end_reconnect_flow(true)
		return
	var context = _pending_restore_context.duplicate(true)
	context["last_connected_server_name"] = _last_connected_server_name
	context["player_name"] = context.get("player_name", _get_preferred_player_name())
	if _previous_server_player_id != null:
		context["previous_player_id"] = _previous_server_player_id
	if _current_server_player_id != null:
		context["current_player_id"] = _current_server_player_id
	if _previous_server_session_id:
		context["previous_session_id"] = _previous_server_session_id
	if _current_server_session_id:
		context["current_session_id"] = _current_server_session_id
	if _previous_server_session_token:
		context["previous_session_token"] = _previous_server_session_token
	if _current_server_session_token:
		context["current_session_token"] = _current_server_session_token
	session_restore_requested.emit(context)
	var restore_message = {
		"type": "restore_session",
		"version": GlobalSettings.get_client_version(),
		"context": context,
	}
	if not _is_socket_open():
		_handle_restore_failed("socket_not_open")
		return
	_log_identity_checkpoint("restore_session_send", {
		"server_player_name": _last_connected_server_name,
		"expected_player_name": context.get("player_name", ""),
	})
	_restore_request_sent = true
	_send_socket_text(JSON.stringify(restore_message), "restore session")

func _has_previous_restore_identity() -> bool:
	return _previous_server_player_id != null or _previous_server_session_id or _previous_server_session_token

func _apply_server_identity(message : Dictionary):
	if message.has("player_id"):
		_current_server_player_id = message["player_id"]
	elif message.has("restored_player_id"):
		_current_server_player_id = message["restored_player_id"]
	elif message.has("old_player_id"):
		_current_server_player_id = message["old_player_id"]
	if message.has("session_id"):
		_current_server_session_id = str(message["session_id"])
	if message.has("session_token"):
		_current_server_session_token = str(message["session_token"])
	if message.has("player_name"):
		_last_connected_server_name = str(message["player_name"])
		_pending_restore_context["player_name"] = _last_connected_server_name

func _apply_restored_server_identity(message : Dictionary):
	if message.has("restored_player_id"):
		_current_server_player_id = message["restored_player_id"]
	elif message.has("old_player_id"):
		_current_server_player_id = message["old_player_id"]
	elif message.has("player_id"):
		_current_server_player_id = message["player_id"]
	if message.has("session_id"):
		_current_server_session_id = str(message["session_id"])
	if message.has("session_token"):
		_current_server_session_token = str(message["session_token"])
	if message.has("player_name"):
		_last_connected_server_name = str(message["player_name"])
		_pending_restore_context["player_name"] = _last_connected_server_name

func _get_preferred_player_name() -> String:
	if _pending_restore_context.has("player_name") and _pending_restore_context["player_name"]:
		return _pending_restore_context["player_name"]
	if GlobalSettings.DefaultPlayerName:
		return GlobalSettings.DefaultPlayerName
	return _last_connected_server_name

func _log_identity_checkpoint(label : String, extra : Dictionary = {}):
	var expected_player_name = str(extra.get("expected_player_name", _get_preferred_player_name()))
	var server_player_name = str(extra.get("server_player_name", _last_connected_server_name))
	var restored_player_id = extra.get("restored_player_id", null)
	var restored_player_id_text = "n/a" if restored_player_id == null else str(restored_player_id)
	var reason_text = str(extra.get("reason", ""))
	var reason_suffix = ""
	if reason_text != "":
		reason_suffix = " reason=%s" % reason_text
	print("[identity] %s prev_player=%s current_player=%s restored_player=%s prev_session=%s current_session=%s expected_name=%s server_name=%s%s" % [
		label,
		str(_previous_server_player_id),
		str(_current_server_player_id),
		restored_player_id_text,
		_previous_server_session_id,
		_current_server_session_id,
		expected_player_name,
		server_player_name,
		reason_suffix,
	])

func _is_restore_message_for_active_session() -> bool:
	return (is_reconnect_active() or _awaiting_name_sync) and reconnect_state["pre_disconnect_state"] in [
		RestoreContextType.RestoreContextType_Game,
		RestoreContextType.RestoreContextType_Observe,
	]

func _restore_context_from_server(data):
	session_restore_succeeded.emit(data)
	_apply_restore_waiting_state(data)
	_active_remote_match_finished = false
	_end_reconnect_flow(true)

func _apply_restore_waiting_state(data : Dictionary):
	var has_authoritative_waiting_state = data.has("opponent_disconnected") \
		or data.has("opponent_waiting_for_reconnect") \
		or data.has("opponent_connected")
	if not has_authoritative_waiting_state:
		end_waiting_for_opponent_reconnect()
		return
	var should_wait_for_opponent = false
	if data.has("opponent_connected"):
		should_wait_for_opponent = not _message_flag_is_true(data.get("opponent_connected", true))
	if data.has("opponent_disconnected"):
		should_wait_for_opponent = _message_flag_is_true(data.get("opponent_disconnected", false))
	if data.has("opponent_waiting_for_reconnect"):
		should_wait_for_opponent = _message_flag_is_true(data.get("opponent_waiting_for_reconnect", false))
	if should_wait_for_opponent:
		begin_waiting_for_opponent_reconnect()
	else:
		end_waiting_for_opponent_reconnect()

func _handle_restore_failed(reason):
	_log_identity_checkpoint("session_restore_failed", {
		"reason": reason,
	})
	clear_restore_context()
	_clear_lobby_cache()
	_waiting_for_restore_name_sync = false
	session_restore_failed.emit(reason)
	_end_reconnect_flow(false)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	_update_reconnect_timers(_delta)
	_update_server_keepalive_timeout()
	_handle_sockets()

func _begin_server_keepalive_tracking():
	_server_keepalive_tracking = true
	_last_server_keepalive_time = Time.get_ticks_msec() / 1000.0

func _reset_server_keepalive_tracking():
	_server_keepalive_tracking = false
	_last_server_keepalive_time = -1.0

func _record_server_keepalive():
	_server_keepalive_tracking = true
	_last_server_keepalive_time = Time.get_ticks_msec() / 1000.0

func _update_server_keepalive_timeout():
	if should_pause_server_keepalive(_web_page_hidden, network_state):
		return
	if not _server_keepalive_tracking:
		return
	var elapsed = Time.get_ticks_msec() / 1000.0 - _last_server_keepalive_time
	if elapsed >= SERVER_KEEPALIVE_TIMEOUT_SECONDS:
		_handle_server_keepalive_timeout(elapsed)

func _handle_server_keepalive_timeout(elapsed : float):
	var reason = "Server keepalive timed out after %.1f seconds." % elapsed
	print(reason)
	if _socket:
		_socket.close()
		_socket = null
	network_state = NetworkState.NetworkState_NotConnected
	_reset_server_keepalive_tracking()
	_clear_lobby_cache()
	disconnected_from_server.emit()
	if reconnect_state["is_auto_reconnecting"] or reconnect_state["is_manual_reconnect"]:
		_mark_reconnect_attempt_failed(reason)
	else:
		_begin_unexpected_disconnect(reason)

func _update_reconnect_timers(delta):
	if _web_page_hidden:
		return
	if reconnect_state["is_auto_reconnecting"]:
		_reconnect_elapsed += delta
		var next_seconds = int(floor(_reconnect_elapsed)) + 1
		if reconnect_state["reconnect_seconds"] != next_seconds:
			reconnect_state["reconnect_seconds"] = next_seconds
			if next_seconds >= AUTO_RECONNECT_MANUAL_THRESHOLD_SECONDS:
				_abort_reconnect_socket()
				reconnect_state["is_auto_reconnecting"] = false
				reconnect_state["auto_retry_enabled"] = false
				reconnect_state["is_manual_reconnect"] = true
			_emit_reconnect_state_changed()
		if reconnect_state["auto_retry_enabled"]:
			_next_auto_reconnect_in -= delta
			if _next_auto_reconnect_in <= 0.0 and _socket == null and network_state != NetworkState.NetworkState_Connecting:
				_next_auto_reconnect_in = AUTO_RECONNECT_INTERVAL_SECONDS
				connect_to_server()
	if reconnect_state["is_waiting_for_opponent_reconnect"]:
		_waiting_for_opponent_reconnect_elapsed += delta
		var waiting_seconds = int(floor(_waiting_for_opponent_reconnect_elapsed)) + 1
		if reconnect_state["waiting_for_opponent_reconnect_seconds"] != waiting_seconds:
			reconnect_state["waiting_for_opponent_reconnect_seconds"] = waiting_seconds
			waiting_for_opponent_reconnect_changed.emit(true, waiting_seconds)
			_emit_reconnect_state_changed()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _socket:
			_is_expected_disconnect = true
			_socket.close()

func _handle_sockets():
	if _socket:
		_socket.poll()
		var state = _socket.get_ready_state()
		match state:
			WebSocketPeer.STATE_OPEN:
				if network_state == NetworkState.NetworkState_Connecting:
					print("Connected to server")
					_begin_server_keepalive_tracking()
				network_state = NetworkState.NetworkState_Connected
				while _socket.get_available_packet_count():
					var packet = _socket.get_packet()
					if _socket.was_string_packet():
						var strpacket = packet.get_string_from_utf8()
						_handle_server_response(strpacket)
			WebSocketPeer.STATE_CLOSING:
				pass
			WebSocketPeer.STATE_CLOSED:
				var code = _socket.get_close_code()
				var reason = _socket.get_close_reason()
				var is_expected_disconnect = _is_expected_disconnect
				_handle_socket_closed(code, reason, is_expected_disconnect)

func _handle_socket_closed(code : int, reason : String, is_expected_disconnect : bool):
	if _socket:
		_socket.close()
	_socket = null
	network_state = NetworkState.NetworkState_NotConnected
	_reset_server_keepalive_tracking()
	_clear_lobby_cache()
	disconnected_from_server.emit()
	print("WebSocket closed with code: %d, reason %s. Clean: %s" % [code, reason, code != -1])
	_is_expected_disconnect = false
	if code != -1:
		var close_message = "Disconnected from server"
		if reason:
			close_message += ": %s" % reason
		else:
			close_message += " (code %d)" % code
		if is_expected_disconnect:
			request_failed.emit(close_message)
		else:
			_begin_unexpected_disconnect(close_message)
	else:
		if not is_expected_disconnect:
			_begin_unexpected_disconnect(reason)

func _is_socket_open():
	return _socket and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN

func _send_socket_text(json : String, action : String) -> bool:
	if not _is_socket_open():
		_handle_socket_send_failed("Cannot %s: socket is not open." % action)
		return false
	var result = _socket.send_text(json)
	if result != OK:
		_handle_socket_send_failed("Cannot %s: %s" % [action, error_string(result)])
		return false
	return true

func _handle_socket_send_failed(reason : String):
	if reconnect_state["is_auto_reconnecting"] or reconnect_state["is_manual_reconnect"]:
		_mark_reconnect_attempt_failed(reason)
		return
	if _socket:
		_socket.close()
		_socket = null
	network_state = NetworkState.NetworkState_NotConnected
	_clear_lobby_cache()
	disconnected_from_server.emit()
	_begin_unexpected_disconnect(reason)

func _emit_not_connected_error(action : String):
	request_failed.emit("Cannot %s: not connected to server." % action)

func _handle_server_response(data):
	var parser = JSON.new()
	var result = parser.parse(data)
	if result != OK:
		print("Error parsing JSON from server: ", data)
		return

	var data_obj = CardDataManager.convert_floats_to_ints(parser.get_data())
	var type = data_obj["type"]
	match type:
		"server_keepalive", "keepalive", "heartbeat":
			_handle_server_keepalive(data_obj)
		"server_hello":
			_handle_server_hello(data_obj)
		"room_waiting_for_opponent":
			_handle_room_waiting_for_opponent(data_obj)
		"room_join_failed":
			_handle_room_join_failed(data_obj)
		"game_start":
			_handle_game_start(data_obj)
		"game_message":
			_handle_game_message(data_obj)
		"name_update":
			_handle_name_update(data_obj)
		"observe_start":
			_handle_observe_start(data_obj)
		"player_disconnect":
			_handle_player_disconnect(data_obj)
		"player_quit":
			_handle_player_quit(data_obj)
		"players_update":
			_handle_players_update(data_obj)
		"customs_update":
			_handle_customs_update(data_obj)
		"session_restored":
			_handle_session_restored(data_obj)
		"session_restore_failed":
			_handle_session_restore_failed(data_obj)
		"player_reconnect":
			_handle_player_reconnect(data_obj)
		"disconnect_confirmation_required":
			_handle_disconnect_confirmation_required(data_obj)
		"matchlog_upload_result":
			matchlog_upload_finished.emit(
				bool(data_obj.get("success", false)),
				bool(data_obj.get("uploaded", false)),
				str(data_obj.get("error", "")))

func _handle_server_keepalive(_message):
	_record_server_keepalive()

func _handle_server_hello(hello_message):
	var player_name = hello_message["player_name"]
	_apply_server_identity(hello_message)
	_last_connected_server_name = player_name
	_log_identity_checkpoint("server_hello", {
		"server_player_name": player_name,
	})
	print("Connected to server as : ", player_name)
	connected_to_server.emit(player_name)
	if is_reconnect_active():
		var preferred_player_name = _get_preferred_player_name().strip_edges()
		if preferred_player_name != "" and preferred_player_name != player_name:
			_waiting_for_restore_name_sync = true
			set_player_name(preferred_player_name)
		else:
			_waiting_for_restore_name_sync = false
			_request_session_restore()

func _handle_room_waiting_for_opponent(_waiting_message):
	print("Waiting for opponent in room")
	if _pending_restore_context.get("state_type", RestoreContextType.RestoreContextType_None) != RestoreContextType.RestoreContextType_Matchmaking:
		set_restore_context(RestoreContextType.RestoreContextType_Room, _pending_restore_context)
	request_players_update()

func _handle_room_join_failed(failed_message):
	var reason = failed_message["reason"]
	var error_message = "ERROR: Failed to join room:\n"
	var invalid_deck = false
	match reason:
		"invalid_custom_deck":
			error_message += "Custom deck is invalid."
			invalid_deck = true
		"invalid_deck_for_queue":
			error_message = "Character not allowed in this queue."
			invalid_deck = true
		"room_full":
			error_message += "Room is full."
		"version_mismatch":
			error_message += "Client Version Mismatch\nCheck for new client version."
		_:
			error_message += "Join Error\n" + reason
	print(error_message)
	room_join_failed.emit(error_message, invalid_deck)

# Accepts a message from the game server indicating a game started.
# Rebroadcasts the message to our scripts.
func _handle_game_start(game_start_message):
	if _is_restore_message_for_active_session():
		_restore_context_from_server(game_start_message)
		return
	_active_remote_match_finished = false
	var player1_id = game_start_message["player1_id"]
	var player1_name = game_start_message["player1_name"]
	var player2_id = game_start_message["player2_id"]
	var player2_name = game_start_message["player2_name"]
	print("Game started between [%s] %s and [%s] %s" % [player1_id, player1_name, player2_id, player2_name])
	var local_player_name = player1_name
	if game_start_message.get("your_player_id", 0) == player2_id:
		local_player_name = player2_name
	set_restore_context(RestoreContextType.RestoreContextType_Game, {
		"room_id": game_start_message.get("room_id", _pending_restore_context.get("room_id", "")),
		"game_id": game_start_message.get("game_id", ""),
		"player_name": local_player_name,
		"previous_player_id": _previous_server_player_id,
		"current_player_id": _current_server_player_id,
		"previous_session_id": _previous_server_session_id,
		"current_session_id": _current_server_session_id,
		"previous_session_token": _previous_server_session_token,
		"current_session_token": _current_server_session_token,
		"your_player_id": game_start_message.get("your_player_id", 0),
	})
	end_waiting_for_opponent_reconnect()
	game_started.emit(game_start_message)

func _handle_name_update(name_update_message):
	var new_name = name_update_message["name"]
	_apply_server_identity(name_update_message)
	_last_connected_server_name = new_name
	_log_identity_checkpoint("name_update", {
		"server_player_name": new_name,
	})
	if _pending_restore_context:
		_pending_restore_context["player_name"] = new_name
	name_update.emit(new_name)
	if (_awaiting_name_sync or _waiting_for_restore_name_sync) and is_reconnect_active():
		_awaiting_name_sync = false
		_waiting_for_restore_name_sync = false
		_request_session_restore()

func _handle_observe_start(observe_start_message):
	if _is_restore_message_for_active_session():
		_restore_context_from_server(observe_start_message)
		return
	set_restore_context(RestoreContextType.RestoreContextType_Observe, {
		"player_name": _get_preferred_player_name(),
		"room_id": observe_start_message.get("room_id", ""),
		"game_id": observe_start_message.get("game_id", ""),
	})
	observe_started.emit(observe_start_message)

func _get_message_player_id(message : Dictionary):
	return message.get("id", message.get("player_id", 0))

func _get_message_player_name(message : Dictionary) -> String:
	return str(message.get("name", message.get("player_name", "")))

func _message_flag_is_true(value) -> bool:
	if value is bool:
		return value
	if value is int or value is float:
		return value != 0
	if value is String:
		return value.to_lower() in ["true", "1", "yes"]
	return false

func _message_is_disconnect(message : Dictionary) -> bool:
	return _message_flag_is_true(message.get("disconnect", false)) or _message_flag_is_true(message.get("is_disconnect", false))

func _handle_player_disconnect(message):
	if _active_remote_match_finished:
		return
	var id = _get_message_player_id(message)
	var player_name = _get_message_player_name(message)
	print("Player [%s] %s disconnected" % [id, player_name])
	_pending_disconnect_confirmation_player_id = id
	begin_waiting_for_opponent_reconnect()
	other_player_quit.emit(true)

func _handle_player_quit(message):
	if _active_remote_match_finished:
		return
	var id = _get_message_player_id(message)
	var player_name = _get_message_player_name(message)
	if _message_is_disconnect(message):
		print("Player [%s] %s disconnected" % [id, player_name])
		begin_waiting_for_opponent_reconnect()
		other_player_quit.emit(true)
		return
	print("Player [%s] %s quit" % [id, player_name])
	end_waiting_for_opponent_reconnect()
	other_player_quit.emit(false)

func _handle_player_reconnect(message):
	var id = _get_message_player_id(message)
	var player_name = _get_message_player_name(message)
	print("Player [%s] %s reconnected" % [id, player_name])
	if _waiting_for_disconnect_confirmation and _pending_disconnect_confirmation_player_id == id:
		return
	end_waiting_for_opponent_reconnect()

func _handle_disconnect_confirmation_required(message):
	_pending_disconnect_confirmation_player_id = _get_message_player_id(message)
	_waiting_for_disconnect_confirmation = true
	if reconnect_state["is_waiting_for_opponent_reconnect"]:
		_acknowledge_disconnect_seen(_pending_disconnect_confirmation_player_id)

func _acknowledge_disconnect_seen(disconnected_player_id) -> bool:
	if disconnected_player_id == null:
		return false
	if not _is_socket_open():
		return false
	var acknowledge_message = {
		"type": "acknowledge_disconnect_seen",
		"disconnected_player_id": disconnected_player_id,
	}
	var sent = _send_socket_text(JSON.stringify(acknowledge_message), "acknowledge disconnect seen")
	if sent:
		_waiting_for_disconnect_confirmation = false
	return sent

func _handle_session_restored(message):
	_apply_restored_server_identity(message)
	_log_identity_checkpoint("session_restored", {
		"restored_player_id": message.get("restored_player_id", message.get("old_player_id", message.get("player_id", null))),
		"server_player_name": message.get("player_name", _last_connected_server_name),
	})
	if message.has("player_name"):
		name_update.emit(message["player_name"])
	_restore_context_from_server(message)
	if _message_flag_is_true(message.get("opponent_left_game", false)) or _message_flag_is_true(message.get("opponent_quit", false)):
		end_waiting_for_opponent_reconnect()
		other_player_quit.emit(false)

func _handle_session_restore_failed(message):
	var reason = message.get("reason", "restore_failed")
	if reason == "waiting_for_disconnect_confirmation":
		return
	_handle_restore_failed(reason)

func _handle_game_message(game_message):
	game_message_received.emit(game_message)

func get_stripped_room_name(room_name : String):
	# If the room name starts with "custom_" remove that from the string.
	if room_name.find("custom_") == 0:
		room_name = room_name.substr(7)
	return room_name

func _handle_players_update(message):
	var players = message["players"]
	var rooms = message["rooms"]
	var queues = message['queues']
	var player_list = []
	for player in players:
		var id = player["player_id"]
		var version = player["player_version"]
		var player_name = player["player_name"]
		var room_name = player["room_name"]
		var player_deck = player["player_deck"]
		room_name = get_stripped_room_name(room_name)
		player_list.append({
			"player_id": id,
			"player_deck": player_deck,
			"player_version": version,
			"player_name": player_name,
			"room_name": room_name,
		})
	cached_players = player_list
	var queue_list = []
	for queue in queues:
		var queue_info = {
			"id": queue["id"],
			"name": queue["name"],
			"match_available": queue["match_available"],
		}
		if queue.has("waiting_character"):
			queue_info["waiting_character"] = queue["waiting_character"]
		if queue.has("waiting_deck"):
			queue_info["waiting_deck"] = queue["waiting_deck"]
		if queue.has("waiting_deck_id"):
			queue_info["waiting_deck_id"] = queue["waiting_deck_id"]
		queue_list.append(queue_info)
	var newly_available_match = false
	for old_queue in cached_queues:
		var new_queue = null
		for queue in queue_list:
			if old_queue['id'] == queue['id']:
				new_queue = queue
				break
		if new_queue and new_queue['match_available'] and not old_queue['match_available']:
			newly_available_match = true
			break
	cached_queues = queue_list

	# Process rooms
	var match_list = []
	for room in rooms:
		var room_name = room['room_name']
		var room_version = room['room_version']
		room_name = get_stripped_room_name(room_name)
		var player_count = int(room.get('player_count', 0))
		var observer_count = int(room['observer_count'])
		var started = room['game_started']
		var game_over = room.get("game_over", false)
		var joinable = room.get("joinable", not started)
		var reconnect_joinable = room.get("reconnect_joinable", started and joinable)
		var reconnectable_seats = []
		for seat in room.get("reconnectable_seats", []):
			reconnectable_seats.append(int(seat))
		var player_names = room['player_names']
		if player_count == 0 and observer_count == 0:
			push_warning("Ignoring empty room from players_update: %s" % room_name)
			continue
		if not started and (player_names.size() == 0 or not player_names[0]):
			push_warning("Ignoring unstarted room without host from players_update: %s" % room_name)
			continue
		if started and player_count < 2 and not joinable and not game_over:
			push_warning("Ignoring started room with fewer than two players from players_update: %s" % room_name)
			continue
		var host = "<EMPTY>"
		var opponent = "<EMPTY>"
		if player_names.size() > 0 and player_names[0]:
			host = player_names[0]
		if player_names.size() > 1 and player_names[1]:
			opponent = player_names[1]
		var decks = room["player_decks"]
		var seat_decks = room.get("seat_decks", decks)
		var host_deck_icon_path = ""
		var opponent_deck_icon_path = ""
		if decks.size() > 0 and decks[0]:
			host_deck_icon_path = CardDataManager.get_portrait_asset_path(decks[0])
		if decks.size() > 1 and decks[1]:
			opponent_deck_icon_path = CardDataManager.get_portrait_asset_path(decks[1])
		var match_info = {
			"name": room_name,
			"host": host,
			"host_deck_icon": host_deck_icon_path,
			"opponent": opponent,
			"opponent_deck_icon": opponent_deck_icon_path,
			"version": room_version,
			"observer_count": observer_count,
			"joinable": joinable,
			"reconnect_joinable": reconnect_joinable,
			"reconnectable_seats": reconnectable_seats,
			"seat_decks": seat_decks,
			"observable": started,
			"game_over": game_over
		}
		match_list.append(match_info)
	cached_matches = match_list

	players_update.emit(player_list, match_list, queue_list, newly_available_match)

func _handle_customs_update(message):
	# Read the new customs dict from the message.
	var new_customs = message["customs"]
	# Update all keys in cached_customs.
	for key in new_customs.keys():
		cached_customs[key] = CardDataManager.convert_floats_to_ints(new_customs[key])
	customs_update.emit(cached_customs)

### Commands ###

func join_room(player_name, room_name, deck_id_str : String,
		starting_timer : int, enforce_timer : bool, minimum_time_per_choice : int, custom_deck_definition):
	return _join_room_internal(player_name, room_name, deck_id_str,
		starting_timer, enforce_timer, minimum_time_per_choice, custom_deck_definition, false, -1, GlobalSettings.CustomHpRankModeEnabled)

func join_reconnect_room(player_name, room_name, deck_id_str : String,
		starting_timer : int, enforce_timer : bool, minimum_time_per_choice : int, custom_deck_definition,
		reconnect_seat : int = -1):
	return _join_room_internal(player_name, room_name, deck_id_str,
		starting_timer, enforce_timer, minimum_time_per_choice, custom_deck_definition, true, reconnect_seat, false)

func _join_room_internal(player_name, room_name, deck_id_str : String,
		starting_timer : int, enforce_timer : bool, minimum_time_per_choice : int, custom_deck_definition,
	reconnect_join : bool, reconnect_seat : int, hp_rank_mode_enabled : bool):
	if not _is_socket_open():
		_emit_not_connected_error("join room")
		return false
	set_restore_context(RestoreContextType.RestoreContextType_Room, {
		"player_name": player_name,
		"lobby_state": "Room",
		"room_id": room_name,
		"deck_id": deck_id_str,
		"starting_timer": starting_timer,
		"enforce_timer": enforce_timer,
		"minimum_time_per_choice": minimum_time_per_choice,
		"custom_deck_definition": custom_deck_definition,
		"reconnect_join": reconnect_join,
		"reconnect_seat": reconnect_seat,
		"hp_rank_mode_enabled": hp_rank_mode_enabled,
	})
	var join_room_message = {
		"version": GlobalSettings.get_client_version(),
		"value": "join_room",
		"type": "join_room",
		"player_name": player_name,
		"room_id": room_name,
		"deck_id": deck_id_str,
		"starting_timer": starting_timer,
		"enforce_timer": enforce_timer,
		"minimum_time_per_choice": minimum_time_per_choice,
		"custom_deck_definition": custom_deck_definition,
		"reconnect_join": reconnect_join,
		"hp_rank_mode_enabled": hp_rank_mode_enabled,
	}
	if reconnect_seat >= 0:
		join_room_message["reconnect_seat"] = reconnect_seat
	var json = JSON.stringify(join_room_message)
	return _send_socket_text(json, "join room")

func observe_room(player_name, room_name):
	if not _is_socket_open():
		_emit_not_connected_error("observe room")
		return false
	set_restore_context(RestoreContextType.RestoreContextType_Observe, {
		"player_name": player_name,
		"lobby_state": "Observe",
		"room_id": room_name,
	})
	var observe_room_message = {
		"version": GlobalSettings.get_client_version(),
		"type": "observe_room",
		"player_name": player_name,
		"room_id": room_name,
	}
	var json = JSON.stringify(observe_room_message)
	return _send_socket_text(json, "observe room")

func join_matchmaking(player_name, deck_id_str : String, queue_id : String, custom_deck_definition):
	if not _is_socket_open():
		_emit_not_connected_error("join matchmaking")
		return false
	set_restore_context(RestoreContextType.RestoreContextType_Matchmaking, {
		"player_name": player_name,
		"lobby_state": "Matchmaking",
		"deck_id": deck_id_str,
		"queue_id": queue_id,
		"starting_timer": GlobalSettings.MatchmakingStartingTimer,
		"enforce_timer": GlobalSettings.MatchmakingEnforceTimer,
		"minimum_time_per_choice": GlobalSettings.MatchmakingMinimumTimePerChoice,
		"custom_deck_definition": custom_deck_definition,
	})
	var message = {
		"version": GlobalSettings.get_client_version(),
		"value": "join_room",
		"type": "join_matchmaking",
		"queue_id": queue_id,
		"player_name": player_name,
		"deck_id": deck_id_str,
		"starting_timer": GlobalSettings.MatchmakingStartingTimer,
		"enforce_timer": GlobalSettings.MatchmakingEnforceTimer,
		"minimum_time_per_choice": GlobalSettings.MatchmakingMinimumTimePerChoice,
		"custom_deck_definition": custom_deck_definition
	}
	var json = JSON.stringify(message)
	return _send_socket_text(json, "join matchmaking")

func leave_room():
	if not _is_socket_open(): return
	_is_expected_disconnect = false
	var normal_game_over = _active_remote_match_finished
	end_waiting_for_opponent_reconnect()
	set_restore_context(RestoreContextType.RestoreContextType_Lobby, {
		"player_name": _get_preferred_player_name(),
		"lobby_state": "Lobby",
	})
	var leave_room_message = {
		"type": "leave_room",
		"normal_game_over": normal_game_over,
	}
	_active_remote_match_finished = false
	var json = JSON.stringify(leave_room_message)
	_send_socket_text(json, "leave room")

func submit_game_message(message):
	if not _is_socket_open(): return
	if is_reconnect_active() or _waiting_for_restore_name_sync:
		return
	message['type'] = "game_message"
	var json = JSON.stringify(message)
	_send_socket_text(json, "submit game message")

func set_player_name(player_name):
	if not _is_socket_open(): return
	_pending_restore_context["player_name"] = player_name
	var message = {
		"version": GlobalSettings.get_client_version(),
		"type": "set_name",
		"player_name": player_name,
	}
	var json = JSON.stringify(message)
	_send_socket_text(json, "set player name")

func set_lobby_state(lobby_state : String):
	if not _is_socket_open(): return
	if lobby_state == "Lobby":
		set_restore_context(RestoreContextType.RestoreContextType_Lobby, {
			"player_name": _get_preferred_player_name(),
			"lobby_state": lobby_state,
		})
	else:
		_pending_restore_context["lobby_state"] = lobby_state
	var message = {
		"type": "set_lobby_state",
		"lobby_state": lobby_state,
	}
	var json = JSON.stringify(message)
	_send_socket_text(json, "set lobby state")

func get_customs():
	if not _is_socket_open(): return
	var message = {
		"type": "get_customs",
	}
	var json = JSON.stringify(message)
	_send_socket_text(json, "get customs")

func set_active_remote_match_finished(is_finished : bool):
	_active_remote_match_finished = is_finished
	if is_finished:
		end_waiting_for_opponent_reconnect()

func request_players_update():
	if not _is_socket_open():
		return false
	var message = {
		"type": "request_players_update",
	}
	var json = JSON.stringify(message)
	return _send_socket_text(json, "request players update")

func request_matchlog_upload():
	if not _is_socket_open():
		return false
	var message = {
		"type": "request_matchlog_upload",
	}
	return _send_socket_text(JSON.stringify(message), "request matchlog upload")

### Getters ###

func get_player_list():
	return cached_players

func get_match_list():
	return cached_matches

func get_queue_list():
	return cached_queues

func get_customs_dict():
	return cached_customs

func any_available_match():
	for queue in cached_queues:
		if queue['match_available']:
			return true
	return false
