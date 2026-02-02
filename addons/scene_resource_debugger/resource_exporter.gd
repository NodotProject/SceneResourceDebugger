@tool
class_name SceneResourceExporter
extends RefCounted
## Exports embedded sub_resources from .tscn scenes to
## external binary .res files and re-links the scene.
##
## Uses a hybrid approach: runtime instantiation to save
## .res files, then direct text rewriting of the .tscn to
## replace [sub_resource] blocks with [ext_resource] refs.

const SceneAnalyzer := preload(
	"res://addons/scene_resource_debugger/scene_analyzer.gd"
)
const _ResourceCollector := preload(
	"res://addons/scene_resource_debugger/resource_collector.gd"
)
const _ExportSceneRewriter := preload(
	"res://addons/scene_resource_debugger/export_scene_rewriter.gd"
)

## Minimum file size (bytes) for a resource to be exported.
## Resources smaller than this stay embedded in the scene.
const _MIN_EXPORT_BYTES: int = 102400 # 100 KB

var _collector: ResourceCollector
var _rewriter: ExportSceneRewriter


class ExportResult extends RefCounted:
	var success: bool = false
	var exported_count: int = 0
	var exported_paths: Array[String] = []
	var error_message: String = ""
	var scene_path: String = ""
	var sub_resources_before: int = -1
	var sub_resources_after: int = -1


func _init() -> void:
	_collector = _ResourceCollector.new()
	_rewriter = _ExportSceneRewriter.new()


## Export all embedded resources from a scene to binary
## .res files in target_dir. Defaults to the scene's own
## directory if target_dir is empty.
func export_all_resources(
	scene_path: String, target_dir: String = ""
) -> ExportResult:
	var result := ExportResult.new()
	result.scene_path = scene_path

	if target_dir.is_empty():
		target_dir = scene_path.get_base_dir()

	# Validate and prepare
	var prep_err := _prepare_target_dir(target_dir)
	if prep_err.is_empty():
		prep_err = _backup_scene_safe(scene_path)
	if not prep_err.is_empty():
		result.error_message = prep_err
		return result

	# Count sub_resources before export for verification
	result.sub_resources_before = _count_sub_resources(
		scene_path
	)

	# Load, collect, export
	var root: Node = _load_and_instantiate(
		scene_path, result
	)
	if not root:
		return result

	var collected: Dictionary = {}
	_collector.walk_node_resources(root, collected)

	if collected.is_empty():
		root.free()
		result.success = true
		result.error_message = "No embedded resources found."
		return result

	# exported_map: sub_resource_id -> output_path
	var exported_map: Dictionary = {}
	_export_collected_resources(
		collected, scene_path, target_dir, result,
		exported_map
	)

	# Build mapping and rewrite the .tscn text
	_finalize_scene(
		scene_path, root, result, exported_map
	)
	root.free()
	return result


## Export a single embedded resource by matching its class
## and saving to target_path.
func export_single_resource(
	scene_path: String,
	sub_resource_id: String,
	target_path: String
) -> ExportResult:
	var result := ExportResult.new()
	result.scene_path = scene_path

	var prep_err := _backup_scene_safe(scene_path)
	if not prep_err.is_empty():
		result.error_message = prep_err
		return result

	# Count sub_resources before export for verification
	result.sub_resources_before = _count_sub_resources(
		scene_path
	)

	var root: Node = _load_and_instantiate(
		scene_path, result
	)
	if not root:
		return result

	var collected: Dictionary = {}
	_collector.walk_node_resources(root, collected)

	var target_res := _collector.find_resource_by_id(
		collected, sub_resource_id
	)
	if not target_res:
		root.free()
		result.error_message = (
			"Could not find resource matching id: %s"
			% sub_resource_id
		)
		return result

	var exported_map: Dictionary = {}
	var save_err := _save_resource_binary(
		target_res, target_path
	)
	if save_err == OK:
		var sub_id: String = _collector.extract_sub_resource_id(
			target_res
		)
		target_res.take_over_path(target_path)
		if not sub_id.is_empty():
			exported_map[sub_id] = target_path
		result.exported_paths.append(target_path)
		result.exported_count = 1
	else:
		result.error_message = (
			"Failed to save resource to %s" % target_path
		)

	_finalize_scene(
		scene_path, root, result, exported_map
	)
	root.free()
	return result


# ── Helpers ──────────────────────────────────────────────


## Prepare target directory, return error string or empty.
func _prepare_target_dir(target_dir: String) -> String:
	if DirAccess.dir_exists_absolute(target_dir):
		return ""
	var err := DirAccess.make_dir_recursive_absolute(
		target_dir
	)
	if err != OK:
		return "Cannot create directory: %s" % target_dir
	return ""


## Backup scene file, return error string or empty.
func _backup_scene_safe(scene_path: String) -> String:
	var err := _backup_scene(scene_path)
	if err != OK:
		return "Cannot create backup of %s" % scene_path
	return ""


## Load a PackedScene and instantiate its root node.
## Sets result.error_message on failure, returns null.
func _load_and_instantiate(
	scene_path: String, result: ExportResult
) -> Node:
	var packed := ResourceLoader.load(
		scene_path
	) as PackedScene
	if not packed:
		result.error_message = (
			"Cannot load scene: %s" % scene_path
		)
		return null

	var root: Node = packed.instantiate()
	if not root:
		result.error_message = (
			"Cannot instantiate scene: %s" % scene_path
		)
		return null
	return root


## Export all collected resources to target_dir.
## Populates exported_map: sub_resource_id -> output_path.
## The sub_resource ID is extracted from the resource's
## embedded path (e.g. "res://scene.tscn::Type_id" -> "Type_id").
func _export_collected_resources(
	collected: Dictionary,
	scene_path: String,
	target_dir: String,
	result: ExportResult,
	exported_map: Dictionary
) -> void:
	var sorted_entries: Array = _collector.dependency_sort(collected)
	var scene_name: String = (
		scene_path.get_file().get_basename()
	)
	var type_counters: Dictionary = {}

	for entry in sorted_entries:
		var resource: Resource = entry["resource"]
		var res_type: String = entry["type"]

		# Extract sub_resource ID from embedded path
		var sub_id: String = _collector.extract_sub_resource_id(
			resource
		)
		if sub_id.is_empty():
			push_warning(
				"SceneResourceExporter: Cannot determine "
				+ "sub_resource ID for %s" % res_type
			)
			continue

		if not type_counters.has(res_type):
			type_counters[res_type] = 0
		var idx: int = type_counters[res_type]
		type_counters[res_type] += 1

		var filename: String = "%s_%s_%d.res" % [
			scene_name,
			res_type.to_snake_case(),
			idx,
		]
		var output_path: String = (
			target_dir.path_join(filename)
		)

		var save_err := _save_resource_binary(
			resource, output_path
		)
		if save_err != OK:
			push_warning(
				"SceneResourceExporter: Failed to save %s"
				% output_path
			)
			continue

		# Skip resources smaller than 100 KB — not worth
		# externalizing. Delete the file we just wrote.
		var file_size: int = _get_file_size(output_path)
		if file_size < _MIN_EXPORT_BYTES:
			DirAccess.remove_absolute(
				ProjectSettings.globalize_path(output_path)
			)
			continue

		# Set external path so nested resource saves
		# reference children by path instead of embedding.
		resource.take_over_path(output_path)
		exported_map[sub_id] = output_path

		result.exported_paths.append(output_path)
		result.exported_count += 1


# ── Finalization: text-based .tscn rewrite ───────────────


## Rewrite the .tscn file to replace embedded sub_resources
## with ext_resource references pointing to exported .res
## files. PackedScene.pack() does not reliably convert
## sub_resources to ext_resources, so we edit the text
## directly.
func _finalize_scene(
	scene_path: String,
	_root: Node,
	result: ExportResult,
	exported_map: Dictionary
) -> void:
	if exported_map.is_empty():
		result.success = result.error_message.is_empty()
		return

	# exported_map is already sub_resource_id -> output_path
	# (IDs extracted from resource.resource_path during export)

	# Parse all sub_resource blocks in the .tscn
	var analyzer := SceneAnalyzer.new()
	var analysis := analyzer.analyze_scene(scene_path)
	if not analysis:
		result.error_message = (
			"Exported %d resources but failed to analyze "
			+ "scene for rewrite. Backup at %s.backup"
		) % [result.exported_count, scene_path]
		result.success = false
		return

	# Rewrite the scene file text
	var rewrite_err := _rewriter.rewrite_scene_text(
		scene_path, exported_map, analysis
	)
	if rewrite_err != OK:
		result.error_message = (
			"Exported %d resources but failed to rewrite "
			+ "scene. Backup at %s.backup"
		) % [result.exported_count, scene_path]
		result.success = false
		return
	if result.error_message.is_empty():
		result.success = true

	# Post-export verification
	result.sub_resources_after = _count_sub_resources(
		scene_path
	)
	if (
		result.sub_resources_before >= 0
		and result.sub_resources_after
			>= result.sub_resources_before
		and result.exported_count > 0
	):
		var warn := (
			"Warning: sub_resource count did not decrease "
			+ "(%d before, %d after). The scene file may "
			+ "still contain embedded resources."
		) % [
			result.sub_resources_before,
			result.sub_resources_after,
		]
		if result.error_message.is_empty():
			result.error_message = warn
		else:
			result.error_message += " | " + warn


## Save a resource to binary .res format.
func _save_resource_binary(
	resource: Resource, output_path: String
) -> Error:
	return ResourceSaver.save(resource, output_path)


## Count [sub_resource] blocks in a .tscn file using text
## analysis. Returns -1 if the file cannot be read.
func _count_sub_resources(scene_path: String) -> int:
	var analyzer := SceneAnalyzer.new()
	var analysis := analyzer.analyze_scene(scene_path)
	if not analysis:
		return -1
	return analysis.sub_resources.size()


## Create a backup copy of a scene file.
func _backup_scene(scene_path: String) -> Error:
	var backup_path: String = scene_path + ".backup"
	var abs_src: String = ProjectSettings.globalize_path(
		scene_path
	)
	var abs_dst: String = ProjectSettings.globalize_path(
		backup_path
	)
	return DirAccess.copy_absolute(abs_src, abs_dst)


## Get the size of a file in bytes. Returns 0 on error.
func _get_file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return 0
	var size: int = file.get_length()
	file.close()
	return size
