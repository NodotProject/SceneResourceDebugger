@tool
class_name SceneResourceImporter
extends RefCounted
## Imports external .res/.tres resources back into a .tscn
## scene as embedded sub_resources. This is the reverse
## operation of SceneResourceExporter.
##
## Uses a text-based approach: serializes each resource file
## to a temporary .tres to obtain its text representation,
## then rewrites the .tscn to embed the resources.

const _TresParserScript := preload(
	"res://addons/scene_resource_debugger/tres_parser.gd"
)
const _ImportSceneRewriter := preload(
	"res://addons/scene_resource_debugger/import_scene_rewriter.gd"
)
const _ImportFileUtils := preload(
	"res://addons/scene_resource_debugger/import_file_utils.gd"
)

const _TEMP_PATH: String = (
	"res://.scene_res_import_temp.tres"
)


class ImportResult extends RefCounted:
	var success: bool = false
	var imported_count: int = 0
	var imported_paths: Array[String] = []
	var deleted_files: Array[String] = []
	var kept_files: Array[String] = []
	var error_message: String = ""
	var scene_path: String = ""
	var ext_resources_before: int = -1
	var ext_resources_after: int = -1


var _ext_res_regex: RegEx
var _sub_res_regex: RegEx
var _tres_parser: TresParser
var _scene_rewriter: ImportSceneRewriter
var _file_utils: ImportFileUtils


func _init() -> void:
	_ext_res_regex = RegEx.new()
	_ext_res_regex.compile(
		'\\[ext_resource type="([^"]+)"'
		+ '(?:\\s+uid="([^"]*)")?'
		+ '\\s+path="([^"]+)"'
		+ '\\s+id="([^"]+)"\\]'
	)
	_sub_res_regex = RegEx.new()
	_sub_res_regex.compile(
		'\\[sub_resource type="([^"]+)" id="([^"]+)"\\]'
	)
	_tres_parser = _TresParserScript.new()
	_scene_rewriter = _ImportSceneRewriter.new()
	_file_utils = _ImportFileUtils.new()


## Import all external .res/.tres resources referenced by
## the scene back as embedded sub_resources.
func import_all_resources(
	scene_path: String
) -> ImportResult:
	var result := ImportResult.new()
	result.scene_path = scene_path

	var file := FileAccess.open(
		scene_path, FileAccess.READ
	)
	if not file:
		result.error_message = (
			"Cannot open scene: %s" % scene_path
		)
		return result
	var content: String = file.get_as_text()
	file.close()

	var all_ext := _parse_ext_resources(content)
	var res_ext: Array = []
	for info: Dictionary in all_ext:
		if ImportFileUtils.is_importable_path(info["path"]):
			res_ext.append(info)

	if res_ext.is_empty():
		result.success = true
		result.error_message = (
			"No importable external resources found."
		)
		return result

	result.ext_resources_before = all_ext.size()

	var importing_ids: PackedStringArray = []
	for info: Dictionary in res_ext:
		importing_ids.append(info["id"])

	var existing_sub_ids := _collect_sub_resource_ids(
		content
	)

	var all_import_data: Array = []
	var failed_paths: PackedStringArray = []
	for info: Dictionary in res_ext:
		var data := _generate_import_data(
			info, existing_sub_ids,
			all_ext, importing_ids
		)
		if data.is_empty():
			failed_paths.append(info["path"])
			continue
		all_import_data.append(data)
		for new_id: String in data.get(
			"new_sub_ids", []
		):
			existing_sub_ids.append(new_id)

	if all_import_data.is_empty():
		result.error_message = (
			"Failed to generate import data for .res "
			+ "resources."
		)
		return result

	var new_content := _scene_rewriter.rewrite_scene_for_import(
		content, all_import_data, importing_ids
	)

	var out_file := FileAccess.open(
		scene_path, FileAccess.WRITE
	)
	if not out_file:
		result.error_message = (
			"Cannot write scene: %s" % scene_path
		)
		return result
	out_file.store_string(new_content)
	out_file.close()

	result.imported_count = all_import_data.size()
	for data: Dictionary in all_import_data:
		result.imported_paths.append(data["source_path"])
	result.success = true

	result.ext_resources_after = (
		new_content.count("[ext_resource ")
	)

	_file_utils.delete_unreferenced_files(
		result.imported_paths, scene_path, result
	)

	if not failed_paths.is_empty():
		var warn := (
			"Failed to import: %s"
			% ", ".join(failed_paths)
		)
		if result.error_message.is_empty():
			result.error_message = warn
		else:
			result.error_message += " | " + warn

	return result


# ── Parsing helpers ─────────────────────────────────────


## Parse all [ext_resource] lines from content.
func _parse_ext_resources(content: String) -> Array:
	var results: Array = []
	var lines := content.split("\n")
	for i in range(lines.size()):
		var m := _ext_res_regex.search(lines[i])
		if m:
			results.append({
				"type": m.get_string(1),
				"uid": m.get_string(2),
				"path": m.get_string(3),
				"id": m.get_string(4),
				"line": i,
			})
	return results


## Collect all existing sub_resource IDs from content.
func _collect_sub_resource_ids(
	content: String
) -> PackedStringArray:
	var ids: PackedStringArray = []
	for m in _sub_res_regex.search_all(content):
		ids.append(m.get_string(2))
	return ids


# ── Import data generation ──────────────────────────────


## Generate import data for a single ext_resource.
## Returns empty Dictionary on failure.
func _generate_import_data(
	ext_info: Dictionary,
	existing_sub_ids: PackedStringArray,
	scene_ext_resources: Array,
	importing_ids: PackedStringArray
) -> Dictionary:
	var res_path: String = ext_info["path"]
	var resource: Resource = ResourceLoader.load(res_path)
	if not resource:
		push_warning(
			"SceneResourceImporter: Cannot load %s"
			% res_path
		)
		return {}

	var save_err := ResourceSaver.save(
		resource, _TEMP_PATH
	)
	if save_err != OK:
		push_warning(
			"SceneResourceImporter: Cannot serialize "
			+ "%s to .tres" % res_path
		)
		return {}

	var temp_file := FileAccess.open(
		_TEMP_PATH, FileAccess.READ
	)
	if not temp_file:
		_file_utils.cleanup_temp()
		return {}
	var tres_text: String = temp_file.get_as_text()
	temp_file.close()
	_file_utils.cleanup_temp()

	var parsed := _tres_parser.parse_tres(tres_text)
	if parsed.is_empty():
		return {}

	# Remap nested sub_resource IDs to avoid conflicts
	var id_remap: Dictionary = {}
	var new_sub_ids: PackedStringArray = []
	for sub_block: Dictionary in parsed["sub_resources"]:
		var old_id: String = sub_block["id"]
		var new_id := _generate_unique_id(
			old_id, existing_sub_ids
		)
		id_remap[old_id] = new_id
		new_sub_ids.append(new_id)

	# Reconcile .tres ext_resource deps with the scene
	var ext_remap: Dictionary = {}
	var ext_to_sub: Dictionary = {}
	var new_ext_lines: PackedStringArray = []
	var used_ids: PackedStringArray = []
	for info: Dictionary in scene_ext_resources:
		used_ids.append(info["id"])

	for tres_ext: Dictionary in parsed["ext_resources"]:
		var dep_path: String = tres_ext["path"]
		var tres_id: String = tres_ext["id"]
		var scene_match := _find_ext_by_path(
			scene_ext_resources, dep_path
		)
		if scene_match and scene_match["id"] in importing_ids:
			ext_to_sub[tres_id] = scene_match["id"]
			continue
		if scene_match:
			ext_remap[tres_id] = scene_match["id"]
			continue
		var new_id := _generate_unique_ext_id(
			tres_ext["type"], used_ids
		)
		used_ids.append(new_id)
		ext_remap[tres_id] = new_id
		var uid_attr: String = ""
		if not tres_ext["uid"].is_empty():
			uid_attr = ' uid="%s"' % tres_ext["uid"]
		new_ext_lines.append(
			'[ext_resource type="%s"%s path="%s"'
			% [tres_ext["type"], uid_attr, dep_path]
			+ ' id="%s"]' % new_id
		)

	# Build sub_resource block texts
	var sub_blocks: PackedStringArray = []
	for sub_block: Dictionary in parsed["sub_resources"]:
		var new_id: String = id_remap[sub_block["id"]]
		var header: String = (
			'[sub_resource type="%s" id="%s"]'
			% [sub_block["type"], new_id]
		)
		var props: String = "\n".join(
			sub_block["lines"]
		)
		props = _scene_rewriter.remap_references(
			props, id_remap, ext_remap, ext_to_sub
		)
		if props.strip_edges().is_empty():
			sub_blocks.append(header)
		else:
			sub_blocks.append(header + "\n" + props)

	# Main resource becomes a sub_resource
	var main_header: String = (
		'[sub_resource type="%s" id="%s"]'
		% [ext_info["type"], ext_info["id"]]
	)
	var main_props: String = "\n".join(
		parsed["resource_lines"]
	)
	main_props = _scene_rewriter.remap_references(
		main_props, id_remap, ext_remap, ext_to_sub
	)
	if main_props.strip_edges().is_empty():
		sub_blocks.append(main_header)
	else:
		sub_blocks.append(main_header + "\n" + main_props)

	return {
		"source_path": res_path,
		"ext_id": ext_info["id"],
		"sub_blocks": sub_blocks,
		"new_ext_lines": new_ext_lines,
		"new_sub_ids": new_sub_ids,
	}


# ── Utility helpers ────────────────────────────────────


## Find an ext_resource entry by path.
func _find_ext_by_path(
	ext_resources: Array, path: String
) -> Dictionary:
	for info: Dictionary in ext_resources:
		if info["path"] == path:
			return info
	return {}


## Generate a unique sub_resource ID.
func _generate_unique_id(
	base_id: String,
	existing_ids: PackedStringArray
) -> String:
	if base_id not in existing_ids:
		return base_id
	var counter: int = 0
	var candidate: String = base_id
	while candidate in existing_ids:
		counter += 1
		candidate = "%s_%d" % [base_id, counter]
	return candidate


## Generate a unique ext_resource ID.
func _generate_unique_ext_id(
	type_name: String,
	existing_ids: PackedStringArray
) -> String:
	var counter: int = 1
	var candidate: String = "%s_imp_%d" % [
		type_name, counter
	]
	while candidate in existing_ids:
		counter += 1
		candidate = "%s_imp_%d" % [
			type_name, counter
		]
	return candidate


