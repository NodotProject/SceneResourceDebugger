extends GutTest
## Tests for SceneResourceAnalyzer — scene file analysis
## using fixture .tscn files.

const SceneAnalyzer := preload(
	"res://addons/scene_resource_debugger/scene_analyzer.gd"
)

var _analyzer: SceneResourceAnalyzer


func before_each() -> void:
	_analyzer = SceneAnalyzer.new()


func test_analyze_empty_scene() -> void:
	var a := _analyzer.analyze_scene(
		"res://test/fixtures/simple_scene.tscn"
	)
	assert_not_null(a, "analysis should not be null")
	assert_eq(a.sub_resources.size(), 0)
	assert_eq(a.ext_resources.size(), 0)


func test_analyze_scene_with_sub_resources() -> void:
	var a := _analyzer.analyze_scene(
		"res://test/fixtures/scene_with_subs.tscn"
	)
	assert_not_null(a)
	assert_eq(a.sub_resources.size(), 2)
	# Check types
	var types: PackedStringArray = []
	for sub in a.sub_resources:
		types.append(sub.type)
	assert_has(types, "Gradient")
	assert_has(types, "GradientTexture1D")
	# Each block should have non-zero byte size
	for sub in a.sub_resources:
		assert_gt(sub.byte_size, 0,
			"byte_size should be > 0 for %s" % sub.id)
	# line_start <= line_end
	for sub in a.sub_resources:
		assert_lte(sub.line_start, sub.line_end,
			"line_start <= line_end for %s" % sub.id)


func test_analyze_scene_with_ext_resources() -> void:
	var a := _analyzer.analyze_scene(
		"res://test/fixtures/scene_with_ext.tscn"
	)
	assert_not_null(a)
	assert_eq(a.ext_resources.size(), 1)
	assert_eq(a.ext_resources[0].type, "Texture2D")
	assert_eq(a.ext_resources[0].path, "res://icon.svg")
	assert_eq(a.ext_resources[0].id, "Texture2D_abc")


func test_analyze_scene_type_summary() -> void:
	var a := _analyzer.analyze_scene(
		"res://test/fixtures/scene_with_subs.tscn"
	)
	assert_not_null(a)
	assert_has(a.type_summary, "Gradient")
	assert_has(a.type_summary, "GradientTexture1D")
	assert_eq(a.type_summary["Gradient"]["count"], 1)
	assert_eq(a.type_summary["GradientTexture1D"]["count"], 1)


func test_analyze_nonexistent_file() -> void:
	var a := _analyzer.analyze_scene(
		"res://test/fixtures/does_not_exist.tscn"
	)
	assert_null(a)
	assert_engine_error("Cannot open")


func test_analyze_node_count() -> void:
	var a := _analyzer.analyze_scene(
		"res://test/fixtures/scene_with_both.tscn"
	)
	assert_not_null(a)
	# scene_with_both.tscn has 2 [node] entries
	assert_eq(a.node_count, 2)
