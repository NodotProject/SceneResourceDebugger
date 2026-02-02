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


## Import all external .res/.tres resources referenced by
## the scene back as embedded sub_resources.
func import_all_resources(
	scene_path: String
) -> ImportResult:
	var result := ImportResult.new()
	result.scene_path = scene_path

	var backup_err := _backup_scene(scene_path)
	if backup_err != OK:
		result.error_message = (
			"Cannot create backup of %s" % scene_path
		)
		return result

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
		if _is_importable_path(info["path"]):
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

	var new_content := _rewrite_scene_for_import(
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

	_delete_unreferenced_files(
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
		_cleanup_temp()
		return {}
	var tres_text: String = temp_file.get_as_text()
	temp_file.close()
	_cleanup_temp()

	var parsed := _parse_tres(tres_text)
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
		props = _remap_references(
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
	main_props = _remap_references(
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


## Parse a .tres file into ext_resources, sub_resources,
## and the main [resource] properties.
func _parse_tres(tres_text: String) -> Dictionary:
	var lines := tres_text.split("\n")
	var ext_resources: Array = []
	var sub_resources: Array = []
	var resource_lines: PackedStringArray = []

	var section: String = ""
	var cur_sub: Dictionary = {}
	var cur_lines: PackedStringArray = []

	for line: String in lines:
		if line.begins_with("[gd_resource "):
			section = "header"
			continue

		if line.begins_with("[ext_resource "):
			_flush_sub(section, cur_sub, cur_lines,
				sub_resources)
			section = "ext"
			var m := _ext_res_regex.search(line)
			if m:
				ext_resources.append({
					"type": m.get_string(1),
					"uid": m.get_string(2),
					"path": m.get_string(3),
					"id": m.get_string(4),
				})
			continue

		if line.begins_with("[sub_resource "):
			_flush_sub(section, cur_sub, cur_lines,
				sub_resources)
			var m := _sub_res_regex.search(line)
			if m:
				section = "sub"
				cur_sub = {
					"type": m.get_string(1),
					"id": m.get_string(2),
				}
				cur_lines = []
			continue

		if line.begins_with("[resource]"):
			_flush_sub(section, cur_sub, cur_lines,
				sub_resources)
			section = "resource"
			cur_lines = []
			continue

		if not line.strip_edges().is_empty():
			cur_lines.append(line)

	if section == "resource":
		resource_lines = cur_lines
	elif section == "sub":
		cur_sub["lines"] = cur_lines.duplicate()
		sub_resources.append(cur_sub)

	return {
		"ext_resources": ext_resources,
		"sub_resources": sub_resources,
		"resource_lines": resource_lines,
	}


## Flush a pending sub_resource block during parsing.
func _flush_sub(
	section: String,
	sub: Dictionary,
	lines: PackedStringArray,
	sub_resources: Array
) -> void:
	if section == "sub" and not sub.is_empty():
		sub["lines"] = lines.duplicate()
		sub_resources.append(sub)


# ── Reference remapping ────────────────────────────────


## Remap SubResource() and ExtResource() references.
func _remap_references(
	text: String,
	sub_id_remap: Dictionary,
	ext_id_remap: Dictionary,
	ext_to_sub_remap: Dictionary
) -> String:
	var result: String = text
	for old_id: String in sub_id_remap:
		result = result.replace(
			'SubResource("%s")' % old_id,
			'SubResource("%s")' % sub_id_remap[old_id]
		)
	for old_id: String in ext_id_remap:
		result = result.replace(
			'ExtResource("%s")' % old_id,
			'ExtResource("%s")' % ext_id_remap[old_id]
		)
	for old_id: String in ext_to_sub_remap:
		result = result.replace(
			'ExtResource("%s")' % old_id,
			'SubResource("%s")' % ext_to_sub_remap[old_id]
		)
	return result


# ── Scene text rewriting ───────────────────────────────


## Rewrite scene text: remove imported ext_resource lines,
## insert sub_resource blocks, update references.
func _rewrite_scene_for_import(
	content: String,
	import_data_list: Array,
	importing_ids: PackedStringArray
) -> String:
	var lines: PackedStringArray = content.split("\n")

	# Collect all new content to insert
	var new_ext_lines: Array = []
	var new_sub_blocks: Array = []
	for data: Dictionary in import_data_list:
		new_ext_lines.append_array(
			data["new_ext_lines"]
		)
		new_sub_blocks.append_array(
			data["sub_blocks"]
		)

	# Build output, skipping removed ext_resource lines
	var output: Array = []
	var inserted_ext: bool = new_ext_lines.is_empty()
	var inserted_sub: bool = new_sub_blocks.is_empty()

	for i in range(lines.size()):
		var line: String = lines[i]

		# Skip ext_resource lines being imported
		if line.begins_with("[ext_resource "):
			var m := _ext_res_regex.search(line)
			if m and m.get_string(4) in importing_ids:
				continue
			output.append(line)
			continue

		# Insert new ext_resource lines after last one
		if (
			not inserted_ext
			and not line.begins_with("[ext_resource ")
			and _had_ext_resource(output)
		):
			for ext_line: String in new_ext_lines:
				output.append(ext_line)
			inserted_ext = true

		# Insert sub_resource blocks before first [node]
		if (
			not inserted_sub
			and line.begins_with("[node ")
		):
			for block: String in new_sub_blocks:
				output.append("")
				output.append(block)
			output.append("")
			inserted_sub = true

		output.append(line)

	# Edge case: no [node] section found
	if not inserted_sub:
		for block: String in new_sub_blocks:
			output.append("")
			output.append(block)
	if not inserted_ext:
		# Insert after first line as fallback
		for j in range(new_ext_lines.size()):
			output.insert(1 + j, new_ext_lines[j])

	# Replace ExtResource -> SubResource for imported IDs
	var result_text: String = "\n".join(
		PackedStringArray(output)
	)
	for ext_id: String in importing_ids:
		result_text = result_text.replace(
			'ExtResource("%s")' % ext_id,
			'SubResource("%s")' % ext_id
		)

	result_text = _update_load_steps(result_text)
	return result_text


## Check if the output array has any ext_resource lines.
func _had_ext_resource(output: Array) -> bool:
	for i in range(output.size() - 1, -1, -1):
		if output[i].begins_with("[ext_resource "):
			return true
		if output[i].begins_with("[gd_scene "):
			return true
	return false


## Recount resources and update load_steps in the header.
func _update_load_steps(content: String) -> String:
	var ext_count: int = content.count("[ext_resource ")
	var sub_count: int = content.count("[sub_resource ")
	var total: int = ext_count + sub_count
	var re := RegEx.new()
	if total <= 0:
		re.compile(' load_steps=\\d+')
		return re.sub(content, "")
	re.compile('load_steps=\\d+')
	return re.sub(
		content,
		"load_steps=%d" % (total + 1)
	)


# ── Utility helpers ────────────────────────────────────


## Check if an ext_resource path is an importable resource.
static func _is_importable_path(path: String) -> bool:
	return path.ends_with(".res") or path.ends_with(".tres")


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


## Delete imported files that are no longer referenced by
## any other .tscn file in the project.
func _delete_unreferenced_files(
	imported_paths: Array[String],
	scene_path: String,
	result: ImportResult
) -> void:
	var tscn_paths: PackedStringArray = []
	_find_tscn_files("res://", tscn_paths)

	# Read all scene files except the one just modified.
	var other_contents: PackedStringArray = []
	for path: String in tscn_paths:
		if path == scene_path:
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file:
			other_contents.append(file.get_as_text())
			file.close()

	for res_path: String in imported_paths:
		var referenced := false
		for content: String in other_contents:
			if content.find(res_path) != -1:
				referenced = true
				break
		if referenced:
			result.kept_files.append(res_path)
		else:
			var abs_p: String = (
				ProjectSettings.globalize_path(res_path)
			)
			if DirAccess.remove_absolute(abs_p) == OK:
				result.deleted_files.append(res_path)
			else:
				result.kept_files.append(res_path)


## Recursively find all .tscn files in the project.
func _find_tscn_files(
	path: String, results: PackedStringArray
) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			if file_name != "." and file_name != "..":
				_find_tscn_files(
					path.path_join(file_name), results
				)
		elif file_name.ends_with(".tscn"):
			results.append(path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()


## Remove the temporary .tres file.
func _cleanup_temp() -> void:
	if FileAccess.file_exists(_TEMP_PATH):
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(_TEMP_PATH)
		)
