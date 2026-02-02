extends GutTest
## Tests for TresParser — .tres text parsing into sections.


var _parser: TresParser


func before_each() -> void:
	_parser = TresParser.new()


func test_parse_empty_tres() -> void:
	var result := _parser.parse_tres("")
	assert_eq(result["ext_resources"].size(), 0)
	assert_eq(result["sub_resources"].size(), 0)
	assert_eq(result["resource_lines"].size(), 0)


func test_parse_ext_resources_only() -> void:
	var text := (
		'[gd_resource type="Resource" format=3]\n'
		+ '[ext_resource type="Texture2D" uid="uid://abc"'
		+ ' path="res://icon.svg" id="Texture2D_1"]\n'
	)
	var result := _parser.parse_tres(text)
	assert_eq(result["ext_resources"].size(), 1)
	var ext: Dictionary = result["ext_resources"][0]
	assert_eq(ext["type"], "Texture2D")
	assert_eq(ext["uid"], "uid://abc")
	assert_eq(ext["path"], "res://icon.svg")
	assert_eq(ext["id"], "Texture2D_1")
	assert_eq(result["sub_resources"].size(), 0)


func test_parse_sub_resources_only() -> void:
	var text := (
		'[gd_resource type="Resource" format=3]\n'
		+ '[sub_resource type="Gradient" id="Gradient_1"]\n'
		+ 'colors = PackedColorArray(0, 0, 0, 1)\n'
		+ '\n'
		+ '[resource]\n'
		+ 'gradient = SubResource("Gradient_1")\n'
	)
	var result := _parser.parse_tres(text)
	assert_eq(result["sub_resources"].size(), 1)
	var sub: Dictionary = result["sub_resources"][0]
	assert_eq(sub["type"], "Gradient")
	assert_eq(sub["id"], "Gradient_1")
	assert_eq(sub["lines"].size(), 1)
	assert_string_contains(sub["lines"][0], "PackedColorArray")


func test_parse_all_sections() -> void:
	var text := (
		'[gd_resource type="Resource" format=3]\n'
		+ '[ext_resource type="Texture2D" uid="uid://x"'
		+ ' path="res://icon.svg" id="Tex_1"]\n'
		+ '[sub_resource type="Gradient" id="Grad_1"]\n'
		+ 'colors = PackedColorArray(1, 1, 1, 1)\n'
		+ '[resource]\n'
		+ 'texture = ExtResource("Tex_1")\n'
		+ 'gradient = SubResource("Grad_1")\n'
	)
	var result := _parser.parse_tres(text)
	assert_eq(result["ext_resources"].size(), 1)
	assert_eq(result["sub_resources"].size(), 1)
	assert_eq(result["resource_lines"].size(), 2)


func test_parse_multiple_sub_resources() -> void:
	var text := (
		'[gd_resource type="Resource" format=3]\n'
		+ '[sub_resource type="Gradient" id="Grad_a"]\n'
		+ 'colors = PackedColorArray(0, 0, 0, 1)\n'
		+ '\n'
		+ '[sub_resource type="GradientTexture1D" id="GTex_b"]\n'
		+ 'gradient = SubResource("Grad_a")\n'
		+ 'width = 256\n'
		+ '\n'
		+ '[resource]\n'
		+ 'texture = SubResource("GTex_b")\n'
	)
	var result := _parser.parse_tres(text)
	assert_eq(result["sub_resources"].size(), 2)
	assert_eq(result["sub_resources"][0]["id"], "Grad_a")
	assert_eq(result["sub_resources"][0]["type"], "Gradient")
	assert_eq(result["sub_resources"][1]["id"], "GTex_b")
	assert_eq(
		result["sub_resources"][1]["type"],
		"GradientTexture1D"
	)
	assert_eq(result["sub_resources"][1]["lines"].size(), 2)


func test_parse_resource_lines() -> void:
	var text := (
		'[gd_resource type="Resource" format=3]\n'
		+ '[resource]\n'
		+ 'some_prop = 42\n'
		+ 'another_prop = "hello"\n'
	)
	var result := _parser.parse_tres(text)
	assert_eq(result["resource_lines"].size(), 2)
	assert_string_contains(
		result["resource_lines"][0], "some_prop"
	)
	assert_string_contains(
		result["resource_lines"][1], "another_prop"
	)
