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

## Minimum file size (bytes) for a resource to be exported.
## Resources smaller than this stay embedded in the scene.
const _MIN_EXPORT_BYTES: int = 102400 # 100 KB


class ExportResult extends RefCounted:
	var success: bool = false
	var exported_count: int = 0
	var exported_paths: Array[String] = []
	var error_message: String = ""
	var scene_path: String = ""
	var sub_resources_before: int = -1
	var sub_resources_after: int = -1


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
	_walk_node_resources(root, collected)

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
	_walk_node_resources(root, collected)

	var target_res := _find_resource_by_id(
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
		var sub_id: String = _extract_sub_resource_id(
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
	var sorted_entries: Array = _dependency_sort(collected)
	var scene_name: String = (
		scene_path.get_file().get_basename()
	)
	var type_counters: Dictionary = {}

	for entry in sorted_entries:
		var resource: Resource = entry["resource"]
		var res_type: String = entry["type"]

		# Extract sub_resource ID from embedded path
		var sub_id: String = _extract_sub_resource_id(
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
	var rewrite_err := _rewrite_scene_text(
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


## Extract the sub_resource ID from a resource's embedded
## path. Godot sets paths like "res://scene.tscn::Type_id"
## for embedded sub_resources. Returns the part after "::".
func _extract_sub_resource_id(resource: Resource) -> String:
	var rpath: String = resource.resource_path
	var sep_pos: int = rpath.find("::")
	if sep_pos >= 0:
		return rpath.substr(sep_pos + 2)
	return ""


## Rewrite the .tscn file: remove sub_resource blocks,
## add ext_resource lines, replace SubResource() refs.
func _rewrite_scene_text(
	scene_path: String,
	id_mapping: Dictionary,
	analysis: RefCounted
) -> Error:
	var file := FileAccess.open(
		scene_path, FileAccess.READ
	)
	if not file:
		return ERR_FILE_CANT_OPEN
	var content: String = file.get_as_text()
	file.close()

	var lines: PackedStringArray = content.split("\n")

	# Step 1: identify line ranges to remove — ONLY blocks
	# that were successfully mapped to external files.
	# Unmapped sub_resource blocks must stay in the .tscn.
	var remove_lines: Dictionary = {}
	for sub_res in analysis.sub_resources:
		if not id_mapping.has(sub_res.id):
			continue
		for i in range(sub_res.line_start, sub_res.line_end + 1):
			remove_lines[i] = true
		# Also remove trailing blank lines after block
		var next: int = sub_res.line_end + 1
		while (
			next < lines.size()
			and lines[next].strip_edges().is_empty()
		):
			remove_lines[next] = true
			next += 1

	# Step 2: build ext_resource lines to insert
	var ext_lines: PackedStringArray = []
	for sid: String in id_mapping:
		var res_path: String = id_mapping[sid]
		var res_type: String = _type_for_sub_id(
			sid, analysis
		)
		var uid_attr: String = _get_uid_attr(res_path)
		ext_lines.append(
			'[ext_resource type="%s"%s path="%s" id="%s"]'
			% [res_type, uid_attr, res_path, sid]
		)

	# Step 3: find insertion point (after last existing
	# ext_resource, or after the gd_scene header).
	var insert_after: int = 0
	for i in range(lines.size()):
		if lines[i].begins_with("[ext_resource "):
			insert_after = i
		elif lines[i].begins_with("[gd_scene "):
			if insert_after == 0:
				insert_after = i

	# Step 4: build output, inserting ext_resources and
	# skipping removed sub_resource blocks.
	var output: PackedStringArray = []
	for i in range(lines.size()):
		if remove_lines.has(i):
			continue
		output.append(lines[i])
		if i == insert_after and not ext_lines.is_empty():
			for ext_line in ext_lines:
				output.append(ext_line)

	# Step 5: replace SubResource("id") -> ExtResource("id")
	# for all mapped IDs.
	var result_text: String = "\n".join(output)
	for sid: String in id_mapping:
		result_text = result_text.replace(
			'SubResource("%s")' % sid,
			'ExtResource("%s")' % sid
		)

	# Step 6: update load_steps in the header
	result_text = _update_load_steps(result_text)

	# Write the modified file
	var out_file := FileAccess.open(
		scene_path, FileAccess.WRITE
	)
	if not out_file:
		return ERR_FILE_CANT_WRITE
	out_file.store_string(result_text)
	out_file.close()
	return OK


## Get the resource type for a sub_resource ID from the
## analysis data.
func _type_for_sub_id(
	sid: String, analysis: RefCounted
) -> String:
	for sub_res in analysis.sub_resources:
		if sub_res.id == sid:
			return sub_res.type
	return "Resource"


## Build a UID attribute string for an ext_resource line.
## Returns ' uid="uid://..."' or empty if unavailable.
func _get_uid_attr(res_path: String) -> String:
	var uid: int = ResourceLoader.get_resource_uid(
		res_path
	)
	if uid >= 0:
		var uid_text: String = ResourceUID.id_to_text(uid)
		return ' uid="%s"' % uid_text
	return ""


## Recount ext_resource + sub_resource entries and update
## load_steps in the gd_scene header.
func _update_load_steps(content: String) -> String:
	var ext_count: int = content.count("[ext_resource ")
	var sub_count: int = content.count("[sub_resource ")
	var total: int = ext_count + sub_count
	if total <= 0:
		# Remove load_steps entirely if no resources
		var re := RegEx.new()
		re.compile(
			' load_steps=\\d+'
		)
		return re.sub(content, "")
	var re := RegEx.new()
	re.compile('load_steps=\\d+')
	# load_steps = resource count + 1 (for the scene)
	return re.sub(
		content,
		"load_steps=%d" % (total + 1)
	)


## Find a resource in the collected dict by sub_resource id.
## Matches via the embedded path suffix (::Type_id).
func _find_resource_by_id(
	collected: Dictionary, sub_id: String
) -> Resource:
	for key in collected:
		var entry: Dictionary = collected[key]
		var res: Resource = entry["resource"]
		if _extract_sub_resource_id(res) == sub_id:
			return res
	return null


# ── Internal methods ──────────────────────────────────────


## Walk a node tree recursively collecting embedded resources.
func _walk_node_resources(
	node: Node, collected: Dictionary
) -> void:
	_inspect_node_properties(node, collected)
	for child in node.get_children():
		_walk_node_resources(child, collected)


## Inspect all properties of a node for embedded Resources.
func _inspect_node_properties(
	node: Node, collected: Dictionary
) -> void:
	for prop in node.get_property_list():
		if prop["type"] == TYPE_OBJECT:
			var value: Variant = node.get(prop["name"])
			if value is Resource:
				_collect_resource(
					value, collected, node.name,
					prop["name"]
				)


## Collect a resource if it is embedded in the scene.
## Embedded sub_resources have paths like
## "res://scene.tscn::Type_id" or empty paths.
## External resources have standalone file paths.
func _collect_resource(
	resource: Resource,
	collected: Dictionary,
	source_name: String,
	property_name: String
) -> void:
	if not is_instance_valid(resource):
		return
	var rpath: String = resource.resource_path
	if not rpath.is_empty() and "::" not in rpath:
		return

	var key: int = resource.get_instance_id()
	if collected.has(key):
		return

	collected[key] = {
		"resource": resource,
		"type": resource.get_class(),
		"source": source_name,
		"property": property_name,
	}

	_inspect_resource_properties(resource, collected)


## Recursively inspect a Resource's properties for nested
## embedded resources.
func _inspect_resource_properties(
	resource: Resource, collected: Dictionary
) -> void:
	for prop in resource.get_property_list():
		if prop["type"] == TYPE_OBJECT:
			var value: Variant = resource.get(prop["name"])
			if value is Resource:
				_collect_resource(
					value, collected,
					resource.get_class(),
					prop["name"]
				)


## Sort collected resources by dependency order:
## leaf resources first, composites last.
func _dependency_sort(collected: Dictionary) -> Array:
	var entries: Array = collected.values()
	var id_set: Dictionary = {}
	for entry in entries:
		var res: Resource = entry["resource"]
		id_set[res.get_instance_id()] = entry

	var deps: Dictionary = {}
	for entry in entries:
		var res: Resource = entry["resource"]
		var res_id: int = res.get_instance_id()
		deps[res_id] = []
		for prop in res.get_property_list():
			if prop["type"] == TYPE_OBJECT:
				var val: Variant = res.get(prop["name"])
				if val is Resource:
					var val_id: int = val.get_instance_id()
					if id_set.has(val_id):
						deps[res_id].append(val_id)

	# Topological sort (Kahn's algorithm)
	var in_degree: Dictionary = {}
	for res_id in deps:
		if not in_degree.has(res_id):
			in_degree[res_id] = 0
		for dep_id in deps[res_id]:
			if not in_degree.has(dep_id):
				in_degree[dep_id] = 0
			in_degree[res_id] += 1

	var queue: Array = []
	for res_id in in_degree:
		if in_degree[res_id] == 0:
			queue.append(res_id)

	var sorted_ids: Array = []
	while not queue.is_empty():
		var current: int = queue.pop_front()
		sorted_ids.append(current)
		for res_id in deps:
			if current in deps[res_id]:
				in_degree[res_id] -= 1
				if in_degree[res_id] == 0:
					queue.append(res_id)

	var sorted_entries: Array = []
	for res_id in sorted_ids:
		if id_set.has(res_id):
			sorted_entries.append(id_set[res_id])

	# Circular deps fallback
	for entry in entries:
		var res: Resource = entry["resource"]
		if res.get_instance_id() not in sorted_ids:
			sorted_entries.append(entry)

	return sorted_entries


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
