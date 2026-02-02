@tool
class_name TresParser
extends RefCounted
## Parses a .tres text file into its component sections:
## ext_resources, sub_resources, and main resource lines.

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


## Parse a .tres file into ext_resources, sub_resources,
## and the main [resource] properties.
func parse_tres(tres_text: String) -> Dictionary:
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
