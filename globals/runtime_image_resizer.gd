class_name RuntimeImageResizer
extends RefCounted

static func resize_to(image: Image, target_width: int, target_height: int) -> Image:
	var resized = image.duplicate()
	resized.resize(target_width, target_height, Image.INTERPOLATE_LANCZOS)
	return resized

static func resize_in_place(image: Image, target_width: int, target_height: int) -> Image:
	if image.get_width() == target_width and image.get_height() == target_height:
		return image
	image.resize(target_width, target_height, Image.INTERPOLATE_LANCZOS)
	return image