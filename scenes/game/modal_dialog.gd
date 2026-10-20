class_name ModalDialog
extends CenterContainer

signal accept_button_pressed
signal secondary_button_pressed
signal close_button_pressed

@onready var message_label: Label = $PanelContainer/OuterMargin/VerticalLayout/MessageLabel
@onready var accept_button : Button = $PanelContainer/OuterMargin/VerticalLayout/ChoiceButtons/AcceptButton
@onready var secondary_button : Button = $PanelContainer/OuterMargin/VerticalLayout/ChoiceButtons/SecondaryButton
@onready var cancel_button : Button = $PanelContainer/OuterMargin/VerticalLayout/ChoiceButtons/CancelButton

func set_text_fields(message_text, accept_text, cancel_text):
	message_label.text = message_text
	accept_button.text = accept_text
	accept_button.visible = accept_text != ""
	secondary_button.visible = false
	cancel_button.text = cancel_text
	cancel_button.visible = cancel_text != ""
	visible = true

func set_choice_fields(message_text, accept_text, secondary_text, cancel_text):
	set_text_fields(message_text, accept_text, cancel_text)
	secondary_button.text = secondary_text
	secondary_button.visible = secondary_text != ""

func _on_close_button_pressed():
	visible = false
	close_button_pressed.emit()

func _on_accept_button_pressed():
	visible = false
	accept_button_pressed.emit()

func _on_secondary_button_pressed():
	visible = false
	secondary_button_pressed.emit()
