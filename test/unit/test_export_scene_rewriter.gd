extends GutTest
## Tests for ExportSceneRewriter — load_steps recalculation.


var _rewriter: ExportSceneRewriter


func before_each() -> void:
	_rewriter = ExportSceneRewriter.new()


func test_update_load_steps_with_resources() -> void:
	# 2 ext + 1 sub = 3 resources => load_steps=4
	var content := (
		'[gd_scene load_steps=2 format=3]\n'
		+ '[ext_resource type="Texture2D" path="res://a.png"'
		+ ' id="T_1"]\n'
		+ '[ext_resource type="Script" path="res://b.gd"'
		+ ' id="S_1"]\n'
		+ '[sub_resource type="Gradient" id="G_1"]\n'
		+ 'colors = PackedColorArray(1,1,1,1)\n'
		+ '[node name="Root" type="Node2D"]\n'
	)
	var result := _rewriter.update_load_steps(content)
	assert_string_contains(result, "load_steps=4")


func test_update_load_steps_no_resources() -> void:
	var content := (
		'[gd_scene load_steps=3 format=3]\n'
		+ '[node name="Root" type="Node2D"]\n'
	)
	var result := _rewriter.update_load_steps(content)
	# load_steps should be removed entirely
	_assert_text_excludes(result, "load_steps")


func test_update_load_steps_mixed() -> void:
	# 1 ext + 2 sub = 3 resources => load_steps=4
	var content := (
		'[gd_scene load_steps=99 format=3]\n'
		+ '[ext_resource type="Texture2D" path="res://a.png"'
		+ ' id="T_1"]\n'
		+ '[sub_resource type="Gradient" id="G_1"]\n'
		+ 'colors = PackedColorArray(1,1,1,1)\n'
		+ '[sub_resource type="GradientTexture1D"'
		+ ' id="GT_1"]\n'
		+ 'gradient = SubResource("G_1")\n'
		+ '[node name="Root" type="Node2D"]\n'
	)
	var result := _rewriter.update_load_steps(content)
	assert_string_contains(result, "load_steps=4")
	_assert_text_excludes(result, "load_steps=99")


# ── Helpers ──────────────────────────────────────────────


## Inverse of assert_string_contains: fails if needle found.
func _assert_text_excludes(
	text: String, needle: String
) -> void:
	assert_eq(
		text.find(needle), -1,
		"Expected '%s' NOT to contain '%s'" % [
			text.substr(0, 80), needle
		]
	)
