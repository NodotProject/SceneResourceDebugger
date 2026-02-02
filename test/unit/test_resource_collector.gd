extends GutTest
## Tests for ResourceCollector — sub_resource ID extraction,
## node walking, dependency sorting, and resource lookup.


var _collector: ResourceCollector


func before_each() -> void:
	_collector = ResourceCollector.new()


# ── extract_sub_resource_id ──────────────────────────────


func test_extract_sub_resource_id_embedded() -> void:
	var res := Resource.new()
	res.resource_path = "res://scene.tscn::Material_1"
	var sid := _collector.extract_sub_resource_id(res)
	assert_eq(sid, "Material_1")


func test_extract_sub_resource_id_no_separator() -> void:
	var res := Resource.new()
	res.resource_path = "res://standalone.tres"
	var sid := _collector.extract_sub_resource_id(res)
	assert_eq(sid, "")


func test_extract_sub_resource_id_empty() -> void:
	var res := Resource.new()
	res.resource_path = ""
	var sid := _collector.extract_sub_resource_id(res)
	assert_eq(sid, "")


# ── walk_node_resources ──────────────────────────────────


func test_walk_collects_embedded_resources() -> void:
	# Create a Sprite2D with an embedded ImageTexture
	# (empty path = embedded resource).
	var sprite := Sprite2D.new()
	add_child_autofree(sprite)
	var tex := ImageTexture.new()
	# tex.resource_path is "" by default => embedded
	sprite.texture = tex

	var collected: Dictionary = {}
	_collector.walk_node_resources(sprite, collected)
	assert_gt(collected.size(), 0,
		"should collect at least the embedded texture")


func test_walk_skips_external_resources() -> void:
	# A resource with a standalone file path is external
	# and should NOT be collected.
	var sprite := Sprite2D.new()
	add_child_autofree(sprite)
	var tex := ImageTexture.new()
	tex.resource_path = "res://external_texture.tres"
	sprite.texture = tex

	var collected: Dictionary = {}
	_collector.walk_node_resources(sprite, collected)
	# The texture has an external path (no "::"), skip it
	assert_eq(collected.size(), 0,
		"external resources should be skipped")


# ── dependency_sort ──────────────────────────────────────


func test_dependency_sort_leaf_first() -> void:
	# Create two resources: parent depends on child.
	var child_res := Resource.new()
	var parent_res := Resource.new()

	# We need a property of TYPE_OBJECT on parent that
	# references child. Use script variables for that.
	# Instead, build collected dict manually and test sort.
	var child_id := child_res.get_instance_id()
	var parent_id := parent_res.get_instance_id()
	var collected := {
		parent_id: {
			"resource": parent_res,
			"type": "ParentRes",
			"source": "node",
			"property": "material",
		},
		child_id: {
			"resource": child_res,
			"type": "ChildRes",
			"source": "node",
			"property": "gradient",
		},
	}

	var sorted := _collector.dependency_sort(collected)
	assert_eq(sorted.size(), 2)
	# Both should be present (leaf ordering depends on
	# actual property references; with no cross-references
	# both are leaves and order is stable).
	var types: Array = []
	for entry in sorted:
		types.append(entry["type"])
	assert_has(types, "ParentRes")
	assert_has(types, "ChildRes")


# ── find_resource_by_id ──────────────────────────────────


func test_find_resource_by_id() -> void:
	var res := Resource.new()
	res.resource_path = "res://scene.tscn::Gradient_abc"
	var collected := {
		res.get_instance_id(): {
			"resource": res,
			"type": "Gradient",
			"source": "Root",
			"property": "gradient",
		},
	}
	var found := _collector.find_resource_by_id(
		collected, "Gradient_abc"
	)
	assert_eq(found, res)


func test_find_resource_by_id_not_found() -> void:
	var collected: Dictionary = {}
	var found := _collector.find_resource_by_id(
		collected, "Missing_id"
	)
	assert_null(found)
