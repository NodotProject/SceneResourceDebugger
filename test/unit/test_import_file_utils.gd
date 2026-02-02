extends GutTest
## Tests for ImportFileUtils — importable path detection.


func test_is_importable_res() -> void:
	assert_true(
		ImportFileUtils.is_importable_path("res://material.res")
	)


func test_is_importable_tres() -> void:
	assert_true(
		ImportFileUtils.is_importable_path("res://data.tres")
	)


func test_is_not_importable_tscn() -> void:
	assert_false(
		ImportFileUtils.is_importable_path("res://scene.tscn")
	)


func test_is_not_importable_png() -> void:
	assert_false(
		ImportFileUtils.is_importable_path("res://icon.png")
	)


func test_is_not_importable_empty() -> void:
	assert_false(ImportFileUtils.is_importable_path(""))
