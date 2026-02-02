extends GutTest
## Tests for ImportSceneRewriter — reference remapping
## and scene rewriting for import operations.


var _rewriter: ImportSceneRewriter


func before_each() -> void:
	_rewriter = ImportSceneRewriter.new()


# ── remap_references ─────────────────────────────────────


func test_remap_sub_resource_references() -> void:
	var text := 'gradient = SubResource("Old_1")'
	var result := _rewriter.remap_references(
		text,
		{"Old_1": "New_1"},
		{},
		{}
	)
	assert_eq(result, 'gradient = SubResource("New_1")')


func test_remap_ext_resource_references() -> void:
	var text := 'texture = ExtResource("Old_1")'
	var result := _rewriter.remap_references(
		text,
		{},
		{"Old_1": "New_1"},
		{}
	)
	assert_eq(result, 'texture = ExtResource("New_1")')


func test_remap_ext_to_sub_references() -> void:
	var text := 'texture = ExtResource("Ext_1")'
	var result := _rewriter.remap_references(
		text,
		{},
		{},
		{"Ext_1": "Sub_1"}
	)
	assert_eq(result, 'texture = SubResource("Sub_1")')


func test_remap_combined() -> void:
	var text := (
		'a = SubResource("S_old")\n'
		+ 'b = ExtResource("E_old")\n'
		+ 'c = ExtResource("EtoS_old")\n'
	)
	var result := _rewriter.remap_references(
		text,
		{"S_old": "S_new"},
		{"E_old": "E_new"},
		{"EtoS_old": "Sub_new"}
	)
	assert_string_contains(result, 'SubResource("S_new")')
	assert_string_contains(result, 'ExtResource("E_new")')
	assert_string_contains(result, 'SubResource("Sub_new")')
	# Originals gone
	assert_eq(result.find('SubResource("S_old")'), -1)
	assert_eq(result.find('ExtResource("E_old")'), -1)
	assert_eq(result.find('ExtResource("EtoS_old")'), -1)


func test_remap_no_match() -> void:
	var text := 'texture = ExtResource("Unrelated")'
	var result := _rewriter.remap_references(
		text,
		{"X": "Y"},
		{"A": "B"},
		{"C": "D"}
	)
	assert_eq(result, text)


# ── update_load_steps ────────────────────────────────────


func test_update_load_steps() -> void:
	# 1 ext + 1 sub => load_steps=3
	var content := (
		'[gd_scene load_steps=99 format=3]\n'
		+ '[ext_resource type="Texture2D" path="res://a.png"'
		+ ' id="T_1"]\n'
		+ '[sub_resource type="Gradient" id="G_1"]\n'
		+ '[node name="Root" type="Node2D"]\n'
	)
	var result := _rewriter.update_load_steps(content)
	assert_string_contains(result, "load_steps=3")
	assert_eq(result.find("load_steps=99"), -1)


# ── rewrite_scene_for_import ─────────────────────────────


func test_rewrite_removes_imported_ext_resource() -> void:
	var content := (
		'[gd_scene load_steps=2 format=3]\n'
		+ '\n'
		+ '[ext_resource type="Texture2D"'
		+ ' path="res://icon.res" id="Tex_1"]\n'
		+ '\n'
		+ '[node name="Root" type="Sprite2D"]\n'
		+ 'texture = ExtResource("Tex_1")\n'
	)
	var import_data := [{
		"source_path": "res://icon.res",
		"ext_id": "Tex_1",
		"sub_blocks": [
			'[sub_resource type="Texture2D" id="Tex_1"]\ndata = 123',
		],
		"new_ext_lines": [],
		"new_sub_ids": [],
	}]
	var result := _rewriter.rewrite_scene_for_import(
		content, import_data,
		PackedStringArray(["Tex_1"])
	)
	# The ext_resource line for Tex_1 should be gone
	assert_eq(result.find('[ext_resource'), -1)


func test_rewrite_inserts_sub_blocks_before_nodes() -> void:
	var content := (
		'[gd_scene load_steps=2 format=3]\n'
		+ '\n'
		+ '[ext_resource type="Resource"'
		+ ' path="res://my.res" id="Res_1"]\n'
		+ '\n'
		+ '[node name="Root" type="Node2D"]\n'
	)
	var import_data := [{
		"source_path": "res://my.res",
		"ext_id": "Res_1",
		"sub_blocks": [
			'[sub_resource type="Resource" id="Res_1"]\nprop = 42',
		],
		"new_ext_lines": [],
		"new_sub_ids": [],
	}]
	var result := _rewriter.rewrite_scene_for_import(
		content, import_data,
		PackedStringArray(["Res_1"])
	)
	# sub_resource block should appear before [node]
	var sub_pos := result.find("[sub_resource")
	var node_pos := result.find("[node")
	assert_gt(node_pos, sub_pos,
		"sub_resource should appear before [node]")


func test_rewrite_replaces_ext_with_sub_references() -> void:
	var content := (
		'[gd_scene load_steps=2 format=3]\n'
		+ '\n'
		+ '[ext_resource type="Resource"'
		+ ' path="res://my.res" id="Res_1"]\n'
		+ '\n'
		+ '[node name="Root" type="Node2D"]\n'
		+ 'data = ExtResource("Res_1")\n'
	)
	var import_data := [{
		"source_path": "res://my.res",
		"ext_id": "Res_1",
		"sub_blocks": [
			'[sub_resource type="Resource" id="Res_1"]',
		],
		"new_ext_lines": [],
		"new_sub_ids": [],
	}]
	var result := _rewriter.rewrite_scene_for_import(
		content, import_data,
		PackedStringArray(["Res_1"])
	)
	assert_string_contains(result, 'SubResource("Res_1")')
	assert_eq(result.find('ExtResource("Res_1")'), -1)


func test_rewrite_updates_load_steps() -> void:
	var content := (
		'[gd_scene load_steps=2 format=3]\n'
		+ '\n'
		+ '[ext_resource type="Resource"'
		+ ' path="res://my.res" id="Res_1"]\n'
		+ '\n'
		+ '[node name="Root" type="Node2D"]\n'
	)
	var import_data := [{
		"source_path": "res://my.res",
		"ext_id": "Res_1",
		"sub_blocks": [
			'[sub_resource type="Resource" id="Res_1"]',
		],
		"new_ext_lines": [],
		"new_sub_ids": [],
	}]
	var result := _rewriter.rewrite_scene_for_import(
		content, import_data,
		PackedStringArray(["Res_1"])
	)
	# ext_resource removed, 1 sub_resource added => load_steps=2
	assert_string_contains(result, "load_steps=2")
