extends GutTest

const RuntimeResourceCleanupScript = preload("res://globals/runtime_resource_cleanup.gd")

func _make_texture() -> Texture2D:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)

func test_release_node_texture_references_clears_nested_visual_resources():
	var root := Node2D.new()
	add_child_autofree(root)
	var container := Node.new()
	root.add_child(container)

	var texture_rect := TextureRect.new()
	texture_rect.texture = _make_texture()
	container.add_child(texture_rect)

	var sprite := Sprite2D.new()
	sprite.texture = _make_texture()
	container.add_child(sprite)

	var animated_sprite := AnimatedSprite2D.new()
	var frames := SpriteFrames.new()
	frames.add_frame(&"default", _make_texture())
	animated_sprite.sprite_frames = frames
	container.add_child(animated_sprite)

	var texture_button := TextureButton.new()
	texture_button.texture_normal = _make_texture()
	texture_button.texture_hover = _make_texture()
	container.add_child(texture_button)

	RuntimeResourceCleanupScript.release_node_texture_references(root)

	assert_null(texture_rect.texture)
	assert_null(sprite.texture)
	assert_null(animated_sprite.sprite_frames)
	assert_null(texture_button.texture_normal)
	assert_null(texture_button.texture_hover)

func test_character_release_drops_cdn_owner_and_sprite_frames():
	var character := Character.new()
	character.process_mode = Node.PROCESS_MODE_DISABLED
	var animated_sprite := AnimatedSprite2D.new()
	animated_sprite.name = "Animation"
	character.add_child(animated_sprite)
	var exceed_icon := Sprite2D.new()
	exceed_icon.name = "ExceedIcon"
	character.add_child(exceed_icon)
	add_child_autofree(character)
	await get_tree().process_frame

	var frames := SpriteFrames.new()
	frames.add_frame(&"default", _make_texture())
	character.animation.sprite_frames = frames
	var resource_owner := "Character:%s" % character.get_instance_id()
	CdnAssetLoader._cache_texture("character-texture", _make_texture(), resource_owner, "visible")

	character.release_resources()

	assert_null(character.animation.sprite_frames)
	assert_false(CdnAssetLoader.loaded_textures.has("character-texture"))

func test_character_reparent_preserves_sprite_frames():
	var first_parent := Node2D.new()
	var second_parent := Node2D.new()
	add_child_autofree(first_parent)
	add_child_autofree(second_parent)
	var character := Character.new()
	character.process_mode = Node.PROCESS_MODE_DISABLED
	var animated_sprite := AnimatedSprite2D.new()
	animated_sprite.name = "Animation"
	character.add_child(animated_sprite)
	var exceed_icon := Sprite2D.new()
	exceed_icon.name = "ExceedIcon"
	character.add_child(exceed_icon)
	first_parent.add_child(character)
	await get_tree().process_frame

	var frames := SpriteFrames.new()
	frames.add_frame(&"default", _make_texture())
	character.animation.sprite_frames = frames

	first_parent.remove_child(character)
	second_parent.add_child(character)

	assert_eq(character.animation.sprite_frames, frames)
	character.queue_free()
	await get_tree().process_frame

func test_character_deletion_releases_cdn_owner():
	var character := Character.new()
	character.process_mode = Node.PROCESS_MODE_DISABLED
	var animated_sprite := AnimatedSprite2D.new()
	animated_sprite.name = "Animation"
	character.add_child(animated_sprite)
	var exceed_icon := Sprite2D.new()
	exceed_icon.name = "ExceedIcon"
	character.add_child(exceed_icon)
	add_child(character)
	await get_tree().process_frame

	var resource_owner := "Character:%s" % character.get_instance_id()
	CdnAssetLoader._cache_texture("deleted-character-texture", _make_texture(), resource_owner, "visible")
	character.queue_free()
	await get_tree().process_frame

	assert_false(CdnAssetLoader.loaded_textures.has("deleted-character-texture"))
