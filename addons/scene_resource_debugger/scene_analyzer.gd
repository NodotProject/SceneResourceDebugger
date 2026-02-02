@tool
class_name SceneResourceAnalyzer
extends RefCounted
## Scans project .tscn files and parses embedded sub_resources
## for size analysis and categorization.


class SubResourceInfo extends RefCounted:
	var type: String = ""
	var id: String = ""
	var byte_size: int = 0
	var line_start: int = 0
	var line_end: int = 0
	var properties: PackedStringArray = []


class ExtResourceInfo extends RefCounted:
	var type: String = ""
	var path: String = ""
	var id: String = ""
	var uid: String = ""
	var line_number: int = -1


class SceneAnalysis extends RefCounted:
	var file_path: String = ""
	var file_size: int = 0
	var sub_resources: Array = [] # Array[SubResourceInfo]
	var ext_resources: Array = [] # Array[ExtResourceInfo]
	var ext_resource_count: int = 0
	var node_count: int = 0
	var total_sub_resource_bytes: int = 0
	var type_summary: Dictionary = {}
	# { "ShaderMaterial": { "count": N, "bytes": N } }


var _sub_resource_regex: RegEx
var _ext_resource_regex: RegEx


func _init() -> void:
	_sub_resource_regex = RegEx.new()
	_sub_resource_regex.compile(
		'\\[sub_resource type="([^"]+)" id="([^"]+)"\\]'
	)
	_ext_resource_regex = RegEx.new()
	_ext_resource_regex.compile(
		'\\[ext_resource type="([^"]+)"'
		+ '(?:\\s+uid="([^"]*)")?'
		+ '\\s+path="([^"]+)"'
		+ '\\s+id="([^"]+)"\\]'
	)


## Scan the project for .tscn files and return analyses
## sorted by file size descending.
func scan_project(
	root_path: String = "res://",
	include_addons: bool = false
) -> Array:
	var tscn_paths: PackedStringArray = []
	_find_tscn_files(root_path, tscn_paths, include_addons)

	var results: Array = [] # Array[SceneAnalysis]
	for path in tscn_paths:
		var analysis := analyze_scene(path)
		if analysis:
			results.append(analysis)

	results.sort_custom(
		func(a: SceneAnalysis, b: SceneAnalysis) -> bool:
			return a.file_size > b.file_size
	)
	return results


## Analyze a single .tscn file by parsing its text content.
func analyze_scene(file_path: String) -> SceneAnalysis:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_warning(
			"SceneResourceAnalyzer: Cannot open %s" % file_path
		)
		return null

	var analysis := SceneAnalysis.new()
	analysis.file_path = file_path
	analysis.file_size = file.get_length()

	var content: String = file.get_as_text()
	file.close()

	analysis.sub_resources = _parse_sub_resources(content)
	analysis.ext_resources = _parse_ext_resources(content)
	analysis.ext_resource_count = analysis.ext_resources.size()
	analysis.node_count = _count_pattern(content, "[node ")

	var total_bytes: int = 0
	for sub_res: SubResourceInfo in analysis.sub_resources:
		total_bytes += sub_res.byte_size
	analysis.total_sub_resource_bytes = total_bytes

	analysis.type_summary = _build_type_summary(
		analysis.sub_resources
	)
	return analysis


## Parse sub_resource blocks from .tscn text content.
func _parse_sub_resources(content: String) -> Array:
	var results: Array = [] # Array[SubResourceInfo]
	var lines: PackedStringArray = content.split("\n")
	var line_count: int = lines.size()

	var current_info: SubResourceInfo = null
	var block_lines: PackedStringArray = []
	var block_start: int = -1

	for i in range(line_count):
		var line: String = lines[i]

		# Check if this line starts a new section
		var is_section_header: bool = (
			line.length() > 0 and line[0] == "["
		)

		if is_section_header:
			# Finalize previous sub_resource block if any
			if current_info:
				current_info.line_end = i - 1
				current_info.properties = block_lines.duplicate()
				current_info.byte_size = (
					_compute_block_bytes(current_info, block_lines)
				)
				results.append(current_info)
				current_info = null
				block_lines = []

			# Check if this header is a sub_resource
			var match_result := _sub_resource_regex.search(line)
			if match_result:
				current_info = SubResourceInfo.new()
				current_info.type = match_result.get_string(1)
				current_info.id = match_result.get_string(2)
				current_info.line_start = i
				block_start = i
				block_lines = []
		elif current_info:
			# Accumulate property lines for current block
			if not line.strip_edges().is_empty():
				block_lines.append(line)

	# Handle last block if file ends with a sub_resource
	if current_info:
		current_info.line_end = line_count - 1
		current_info.properties = block_lines.duplicate()
		current_info.byte_size = _compute_block_bytes(
			current_info, block_lines
		)
		results.append(current_info)

	return results


## Parse ext_resource lines from .tscn text content.
func _parse_ext_resources(content: String) -> Array:
	var results: Array = [] # Array[ExtResourceInfo]
	var lines: PackedStringArray = content.split("\n")

	for i in range(lines.size()):
		var match_result := _ext_resource_regex.search(
			lines[i]
		)
		if match_result:
			var info := ExtResourceInfo.new()
			info.type = match_result.get_string(1)
			info.uid = match_result.get_string(2)
			info.path = match_result.get_string(3)
			info.id = match_result.get_string(4)
			info.line_number = i
			results.append(info)

	return results


## Build a type summary dictionary from sub_resource list.
func _build_type_summary(sub_resources: Array) -> Dictionary:
	var summary: Dictionary = {}
	for sub_res: SubResourceInfo in sub_resources:
		if not summary.has(sub_res.type):
			summary[sub_res.type] = {"count": 0, "bytes": 0}
		summary[sub_res.type]["count"] += 1
		summary[sub_res.type]["bytes"] += sub_res.byte_size
	return summary


## Recursively find all .tscn files using DirAccess.
func _find_tscn_files(
	path: String,
	results: PackedStringArray,
	include_addons: bool
) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			if file_name != "." and file_name != "..":
				var skip: bool = (
					not include_addons
					and file_name == "addons"
					and path == "res://"
				)
				if not skip:
					var sub_path: String = (
						path.path_join(file_name)
					)
					_find_tscn_files(
						sub_path, results, include_addons
					)
		elif file_name.ends_with(".tscn"):
			results.append(path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()


## Compute byte size of a sub_resource block.
func _compute_block_bytes(
	info: SubResourceInfo, prop_lines: PackedStringArray
) -> int:
	# Reconstruct the block text: header + properties
	var header: String = (
		'[sub_resource type="%s" id="%s"]' % [info.type, info.id]
	)
	var block_text: String = header + "\n"
	for line in prop_lines:
		block_text += line + "\n"
	return block_text.to_utf8_buffer().size()


## Count occurrences of a pattern in text.
func _count_pattern(content: String, pattern: String) -> int:
	var count: int = 0
	var search_from: int = 0
	while true:
		var pos: int = content.find(pattern, search_from)
		if pos == -1:
			break
		count += 1
		search_from = pos + pattern.length()
	return count
