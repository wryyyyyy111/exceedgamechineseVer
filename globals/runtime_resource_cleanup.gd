class_name RuntimeResourceCleanup
extends RefCounted

static func release_node_texture_references(root: Node):
	if root.has_method("release_stream"):
		root.release_stream()
	if root is AnimatedSprite2D:
		root.stop()
		root.sprite_frames = null
	elif root is TextureRect:
		root.texture = null
	elif root is Sprite2D:
		root.texture = null
	elif root is TextureButton:
		root.texture_normal = null
		root.texture_pressed = null
		root.texture_hover = null
		root.texture_disabled = null
		root.texture_focused = null

	for child in root.get_children():
		release_node_texture_references(child)

static func release_character_resources(root: Node):
	if root is Character:
		root.release_resources()
	for child in root.get_children():
		release_character_resources(child)
