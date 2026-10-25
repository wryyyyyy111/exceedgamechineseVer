class_name CardPopout
extends Control

signal close_window
signal pressed_ok(index)
signal pressed_cancel
signal pressed_toggle
signal card_clicked(card_id)

const RuntimeImageResizerScript = preload("res://globals/runtime_image_resizer.gd")

const ColsAtMaxSize = 5
const SlotsAtExpectedCols = 10
const MaxCols = 20
const MaxSlotCount = 40
const DefaultSeparation = 0
const MinSeparation = -120
const MinVisibleOverlapWidth = 1.0
const CLOSE_BUTTON_BACKGROUND_COLOR = Color("#f5941eaa")

var used_slots = 0
var total_cols = 0
var close_on_outside_click : bool = true
var fill_viewport : bool = false
var preview_card_scale_multiplier : float = 1.0
var preview_label_color : Color = Color(1, 1, 1, 1)
var close_button_background_color : Color = CLOSE_BUTTON_BACKGROUND_COLOR
var enable_card_label_count_click_update : bool = false
var allow_hover_focus : bool = true
var custom_content : Control = null
var content_source_image : Image = null
var content_resize_generation : int = 0
var card_render_generation : int = 0
var pending_title := ""
var pending_amount := ""
var pending_instruction_info = null
var has_pending_instructions := false
var pending_toggle_text := ""
var pending_toggle_visible := false
var has_pending_toggle := false

const CardBaseScene = preload("res://scenes/card/card_base.tscn")

@onready var instruction_box = $PopoutContainer/PopoutVBox/RestOfThing
@onready var instruction_label = $PopoutContainer/PopoutVBox/RestOfThing/InstructionLabel
@onready var instruction_button_ok = $PopoutContainer/PopoutVBox/RestOfThing/InstructionButtonOk
@onready var instruction_button_ok2 = $PopoutContainer/PopoutVBox/RestOfThing/InstructionButtonOk2
@onready var instruction_button_ok3 = $PopoutContainer/PopoutVBox/RestOfThing/InstructionButtonOk3
@onready var instruction_button_cancel = $PopoutContainer/PopoutVBox/RestOfThing/InstructionButtonCancel
@onready var toggle_container = $PopoutContainer/PopoutVBox/ToggleContainer
@onready var toggle_button = $PopoutContainer/PopoutVBox/ToggleContainer/WithBuffer/ReshuffleToggle
@onready var popout_vbox = $PopoutContainer/PopoutVBox
@onready var close_window_row = $PopoutContainer/PopoutVBox/CloseWindowRow
@onready var title_row = $PopoutContainer/PopoutVBox/HBoxContainer
@onready var title_label = $PopoutContainer/PopoutVBox/HBoxContainer/TitleLabel
@onready var title_amount = $PopoutContainer/PopoutVBox/HBoxContainer/TitleAmount
@onready var rows = $PopoutContainer/PopoutVBox/Margin/Rows
@onready var content_margin = $PopoutContainer/PopoutVBox/Margin
@onready var popout_container = $PopoutContainer
@onready var close_window_button = $PopoutContainer/PopoutVBox/CloseWindowRow/CloseWindowButton

func _ready():
	if get_viewport() and not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	_configure_card_slot_mouse_filters()
	_apply_close_button_background_color()
	_sync_to_viewport_size()
	_apply_pending_configuration()

func _apply_pending_configuration() -> void:
	set_title(pending_title)
	set_amount(pending_amount)
	if has_pending_instructions:
		set_instructions(pending_instruction_info)
	if has_pending_toggle:
		set_reference_toggle(pending_toggle_text, pending_toggle_visible)

func _configure_card_slot_mouse_filters():
	content_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for row in rows.get_children():
		if row is Control:
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			for col in row.get_children():
				if col is Control:
					col.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _input(event):
	if not close_on_outside_click:
		return
	if (event is InputEventMouseButton) and event.pressed:
		var evLocal = make_input_local(event)
		if !Rect2(Vector2(0,0),popout_container.size).has_point(evLocal.position):
			close_window.emit()

func set_close_on_outside_click(enabled : bool):
	close_on_outside_click = enabled

func set_preview_card_scale(multiplier : float):
	preview_card_scale_multiplier = max(0.1, multiplier)

func set_preview_label_color(color : Color):
	preview_label_color = color

func set_close_button_background_color(color : Color):
	close_button_background_color = color
	_apply_close_button_background_color()

func set_enable_card_label_count_click_update(enabled : bool):
	enable_card_label_count_click_update = enabled

func set_allow_hover_focus(enabled : bool):
	allow_hover_focus = enabled

func _apply_close_button_background_color():
	if close_window_button == null:
		return
	var style_names = ["normal", "hover", "pressed", "focus"]
	for style_name in style_names:
		var base_style = close_window_button.get_theme_stylebox(style_name)
		var style = base_style.duplicate() if base_style else StyleBoxFlat.new()
		if style is StyleBoxFlat:
			style.bg_color = close_button_background_color
		else:
			var flat_style = StyleBoxFlat.new()
			flat_style.bg_color = close_button_background_color
			style = flat_style
		close_window_button.add_theme_stylebox_override(style_name, style)


func set_fill_viewport(enabled : bool):
	fill_viewport = enabled
	_sync_to_viewport_size()

func _on_viewport_size_changed():
	_sync_to_viewport_size()
	if content_source_image != null:
		_schedule_content_resize()

func _schedule_content_resize():
	content_resize_generation += 1
	var resize_generation := content_resize_generation
	if custom_content != null:
		custom_content.visible = false
	_rebuild_content_after_resize(resize_generation)

func _rebuild_content_after_resize(resize_generation : int):
	await get_tree().process_frame
	await get_tree().process_frame
	if resize_generation != content_resize_generation or content_source_image == null:
		return
	_show_image_now(content_source_image)

func _sync_to_viewport_size():
	if not fill_viewport:
		return
	if not is_inside_tree():
		return
	var viewport_size = get_viewport_rect().size
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = viewport_size
	popout_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popout_container.custom_minimum_size = viewport_size

func set_title(text : String):
	pending_title = text
	if title_label == null:
		return
	title_label.text = text

func set_amount(text : String):
	pending_amount = text
	if title_amount == null:
		return
	title_amount.text = text

func set_instructions(instruction_info):
	pending_instruction_info = instruction_info
	has_pending_instructions = true
	if instruction_box == null:
		return
	if instruction_info == null:
		instruction_box.visible = false
	else:
		instruction_box.visible = true
		var instruction_text = instruction_info['instruction_text']
		var ok_text = instruction_info['ok_text']
		var cancel_text = instruction_info['cancel_text']
		var ok_enabled = instruction_info['ok_enabled']
		var cancel_visible = instruction_info['cancel_visible']
		var ok2_text = ""
		if 'ok2_text' in instruction_info:
			ok2_text = instruction_info['ok2_text']
		var ok3_text = ""
		if 'ok3_text' in instruction_info:
			ok3_text = instruction_info['ok3_text']

		instruction_label.text = instruction_text
		instruction_button_ok.text = ok_text
		instruction_button_ok.disabled = not ok_enabled
		instruction_button_ok2.visible = ok2_text != ""
		instruction_button_ok2.text = ok2_text
		instruction_button_ok2.disabled = not ok_enabled
		instruction_button_ok3.visible = ok3_text != ""
		instruction_button_ok3.text = ok3_text
		instruction_button_ok3.disabled = not ok_enabled
		instruction_button_cancel.visible = cancel_visible
		instruction_button_cancel.text = cancel_text

func set_reference_toggle(toggle_text, toggle_visible):
	pending_toggle_text = toggle_text
	pending_toggle_visible = toggle_visible
	has_pending_toggle = true
	if toggle_container == null or toggle_button == null:
		return
	toggle_container.visible = toggle_visible
	if toggle_text == "":
		toggle_button.text = "Show cards before reshuffle"
		toggle_button.disabled = true
	else:
		toggle_button.text = toggle_text
		toggle_button.disabled = false

func show_cards(cards : Array, total_slot_count : int = -1):
	card_render_generation += 1
	var render_info = _prepare_card_slots(cards, total_slot_count)
	var display_scale = render_info["display_scale"]
	var total_cards = render_info["total_cards"]

	var rendered_cards : Array[CardBase] = []
	for i in range(cards.size()):
		rendered_cards.append(_render_card_slot(cards[i], i, display_scale))

	_finish_rendered_cards(rendered_cards, display_scale, total_cards)

func show_cards_chunked(cards : Array, total_slot_count : int = -1, batch_size : int = 1):
	card_render_generation += 1
	var render_generation = card_render_generation
	var render_info = _prepare_card_slots(cards, total_slot_count)
	var display_scale = render_info["display_scale"]
	var total_cards = render_info["total_cards"]

	var rendered_cards : Array[CardBase] = []
	for i in range(cards.size()):
		if render_generation != card_render_generation or not is_inside_tree():
			return
		rendered_cards.append(_render_card_slot(cards[i], i, display_scale))
		if batch_size > 0 and (i + 1) % batch_size == 0:
			await get_tree().process_frame

	if render_generation != card_render_generation or not is_inside_tree():
		return
	_finish_rendered_cards(rendered_cards, display_scale, total_cards)

func _prepare_card_slots(cards : Array, total_slot_count : int) -> Dictionary:
	content_source_image = null
	_clear_custom_content()
	_clear_card_slots()
	rows.visible = true
	content_margin.size_flags_horizontal = 0
	content_margin.size_flags_vertical = 0
	var total_cards = len(cards)
	if total_slot_count > 0:
		total_cards = total_slot_count
	used_slots = total_cards
	total_cols = min(ceil(total_cards / 2.0), MaxCols)
	var display_scale = CardBase.ReferenceCardScale * preview_card_scale_multiplier
	var display_card_size = CardBase.ActualCardSize * display_scale
	for i in range(total_cards):
		var slot = get_spot(i)
		slot.custom_minimum_size = display_card_size
	return {
		"display_scale": display_scale,
		"total_cards": total_cards,
	}

func _render_card_slot(card : CardBase, slot_index : int, display_scale : Vector2) -> CardBase:
	var new_card : CardBase = CardBaseScene.instantiate()
	# Character card and buddy placeholder reference cards are display-only and must never be clickable.
	if card.card_id not in [CardBase.CharacterCardReferenceId, CardBase.BuddyCardReferenceId]:
		new_card.clicked_card.connect(on_card_clicked)
	var spot = get_spot(slot_index)
	spot.add_child(new_card)
	new_card.initialize_simple(card.card_id, card.card_url_loaded_image, card.card_url_loaded_cardback, card.card_attack_name, card.card_boost_name, card.card_definition)
	new_card.set_hover_focus_enabled(allow_hover_focus)
	new_card.flip_card_to_front(card.card_front.visible)
	new_card.remaining_count_label.add_theme_color_override("font_color", preview_label_color)
	new_card.backup_label_text.set("theme_override_colors/default_color", preview_label_color)

	var label = card.get_label()
	if label:
		new_card.set_label(label)

	var remaining_count = card.get_remaining_count()
	if remaining_count != -1:
		new_card.set_remaining_count(remaining_count)
		if enable_card_label_count_click_update:
			var initial_count : int = remaining_count
			new_card.clicked_card.connect(func(_clicked : CardBase):
				var cur = _clicked.get_remaining_count()
				if cur > 0:
					_clicked.set_remaining_count(cur - 1)
				else:
					_clicked.set_remaining_count(initial_count)
			)

	var icon_state = card.get_hand_icon_state()
	if icon_state:
		new_card.update_hand_icons_from_state(icon_state)
	_position_rendered_card(new_card, display_scale)
	return new_card

func _position_rendered_card(card : CardBase, display_scale : Vector2):
	var adjusted_pos = display_scale * CardBase.ActualCardSize / 2
	card.change_state(CardBase.CardState.CardState_InPopout)
	card.set_card_and_focus(adjusted_pos, 0, display_scale)
	card.set_resting_position(adjusted_pos, 0)
	card.resting_scale = display_scale
	card.set_card_and_focus(adjusted_pos, 0, display_scale)

func _finish_rendered_cards(rendered_cards : Array[CardBase], display_scale : Vector2, total_cards : int):
	var display_card_size = CardBase.ActualCardSize * display_scale
	adjust_spacing(display_card_size, total_cards)
	popout_container.reset_size()
	_sync_to_viewport_size()

	for card in rendered_cards:
		_position_rendered_card(card, display_scale)

func show_texture(texture: Texture2D):
	if texture == null:
		return
	show_image(texture.get_image())

func show_image(image: Image):
	if image == null or image.is_empty():
		return
	content_source_image = image
	_show_image_now(image)

func _show_image_now(image: Image):
	_clear_card_slots()
	_clear_custom_content()
	rows.visible = false
	var display_texture = _get_resized_texture_for_content_image(image)

	var texture_rect := TextureRect.new()
	texture_rect.texture = display_texture
	texture_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texture_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	texture_rect.custom_minimum_size = display_texture.get_size()
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_margin.add_child(texture_rect)
	custom_content = texture_rect
	popout_container.reset_size()
	_sync_to_viewport_size()

func _get_resized_texture_for_content(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var source_image = texture.get_image()
	if source_image == null or source_image.is_empty():
		return texture
	return _get_resized_texture_for_content_image(source_image)

func _get_resized_texture_for_content_image(source_image: Image) -> Texture2D:
	if source_image == null or source_image.is_empty():
		return null

	var source_size = Vector2(source_image.get_width(), source_image.get_height())
	if source_size.x <= 0 or source_size.y <= 0:
		return ImageTexture.create_from_image(source_image)

	var available_size = _get_texture_content_size()
	if available_size.x <= 0 or available_size.y <= 0:
		return ImageTexture.create_from_image(source_image)

	var image_ratio = source_size.x / source_size.y
	var available_ratio = available_size.x / available_size.y
	var target_width : int
	var target_height : int
	if image_ratio >= available_ratio:
		target_width = max(1, int(round(available_size.x)))
		target_height = max(1, int(round(target_width / image_ratio)))
	else:
		target_height = max(1, int(round(available_size.y)))
		target_width = max(1, int(round(target_height * image_ratio)))

	if target_width == int(source_size.x) and target_height == int(source_size.y):
		return ImageTexture.create_from_image(source_image)

	var resized_image = RuntimeImageResizerScript.resize_to(source_image, target_width, target_height)
	return ImageTexture.create_from_image(resized_image)

func _get_texture_content_size() -> Vector2:
	var viewport_size = get_viewport_rect().size
	var margin_left = float(content_margin.get_theme_constant("margin_left"))
	var margin_right = float(content_margin.get_theme_constant("margin_right"))
	var margin_top = float(content_margin.get_theme_constant("margin_top"))
	var margin_bottom = float(content_margin.get_theme_constant("margin_bottom"))
	var vertical_chrome = close_window_row.get_combined_minimum_size().y + title_row.get_combined_minimum_size().y
	if instruction_box.visible:
		vertical_chrome += instruction_box.get_combined_minimum_size().y
	if toggle_container.visible:
		vertical_chrome += toggle_container.get_combined_minimum_size().y

	var spacing = float(popout_vbox.get_theme_constant("separation")) * 4.0
	var width = max(1.0, viewport_size.x - margin_left - margin_right)
	var height = max(1.0, viewport_size.y - margin_top - margin_bottom - vertical_chrome - spacing)
	return Vector2(width, height)

func _clear_custom_content():
	if custom_content != null and is_instance_valid(custom_content):
		custom_content.queue_free()
	custom_content = null

func _clear_card_slots():
	used_slots = 0
	total_cols = 0
	for row in rows.get_children():
		row.add_theme_constant_override("separation", DefaultSeparation)
		for col in row.get_children():
			while col.get_child_count() > 0:
				var child = col.get_child(0)
				col.remove_child(child)
				child.queue_free()
			col.visible = false
			col.custom_minimum_size = Vector2.ZERO

func modify_card_selection(card_id, selected):
	for row in rows.get_children():
		for spot in row.get_children():
			if spot.get_child_count() == 0:
				continue
			var card : CardBase = spot.get_child(0)
			if card.card_id == card_id:
				card.set_selected(selected)

func adjust_spacing(display_card_size: Vector2, total_cards: int):
	if not fill_viewport:
		_apply_legacy_spacing()
		return

	var top_row_count = min(total_cards, total_cols)
	var bottom_row_count = max(0, total_cards - total_cols)
	_apply_row_fill_spacing(rows.get_child(0), top_row_count, display_card_size)
	_apply_row_fill_spacing(rows.get_child(1), bottom_row_count, display_card_size)

func _apply_legacy_spacing():
	for child in rows.get_children():
		if used_slots > SlotsAtExpectedCols:
			var extra_cols = floor((used_slots - SlotsAtExpectedCols) / 2.0) + 1
			var percent : float = float(extra_cols) / (MaxCols - ColsAtMaxSize)
			var sep = floor(lerpf(DefaultSeparation, MinSeparation, percent))
			child.add_theme_constant_override("separation", sep)
		else:
			child.add_theme_constant_override("separation", DefaultSeparation)

func _apply_row_fill_spacing(row: Control, row_count: int, display_card_size: Vector2): #!参考卡界面运行
	if row_count <= 0:
		row.add_theme_constant_override("separation", DefaultSeparation)
		return

	# 让每个槽位尺寸与卡牌显示尺寸一致，便于精确计算横向铺满。
	for i in range(row.get_child_count()):
		var col = row.get_child(i)
		if i < row_count:
			col.custom_minimum_size = display_card_size

	var margin_left = float(content_margin.get_theme_constant("margin_left"))
	var margin_right = float(content_margin.get_theme_constant("margin_right"))
	var available_width = get_fill_viewport_available_width(
			get_viewport_rect().size.x, margin_left, margin_right)

	if row_count == 1:
		row.add_theme_constant_override("separation", DefaultSeparation)
		return

	row.add_theme_constant_override("separation", get_fill_viewport_row_spacing(row_count, display_card_size.x, available_width))

static func get_fill_viewport_available_width(
		viewport_width : float, margin_left : float, margin_right : float) -> float:
	return maxf(0.0, viewport_width - margin_left - margin_right)

static func get_fill_viewport_row_spacing(row_count : int, display_card_width : float, available_width : float) -> int:
	if row_count <= 1:
		return DefaultSeparation
	var total_card_width = display_card_width * float(row_count)
	var required_spacing = (available_width - total_card_width) / float(row_count - 1)
	var minimum_spacing = minf(float(MinSeparation), MinVisibleOverlapWidth - display_card_width)
	var spacing = clampf(required_spacing, minimum_spacing, float(DefaultSeparation))
	return int(floor(spacing))

func get_spot(slot_index):
	var row_num = 0
	var col_num = slot_index
	if slot_index >= total_cols:
		row_num = 1
		col_num = slot_index - total_cols
	var row = rows.get_child(row_num)
	var col = row.get_child(col_num)
	col.visible = true
	return col

func on_card_clicked(card : CardBase):
	card_clicked.emit(card.card_id)

func _on_close_window_button_pressed():
	close_window.emit()

func _on_instruction_button_ok_pressed():
	pressed_ok.emit(0)

func _on_instruction_button_ok2_pressed():
	pressed_ok.emit(1)

func _on_instruction_button_ok3_pressed():
	pressed_ok.emit(2)

func _on_instruction_button_cancel_pressed():
	pressed_cancel.emit()

func _on_reshuffle_toggle_pressed():
	pressed_toggle.emit()
