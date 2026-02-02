@tool
class_name ImportSceneRewriter
extends RefCounted
## Rewrites a .tscn file to embed external resources as
## sub_resources and remap all references accordingly.

var _ext_res_regex: RegEx


func _init() -> void:
	_ext_res_regex = RegEx.new()
	_ext_res_regex.compile(
		'\\[ext_resource type="([^"]+)"'
		+ '(?:\\s+uid="([^"]*)")?'
		+ '\\s+path="([^"]+)"'
		+ '\\s+id="([^"]+)"\\]'
	)


## Rewrite scene text: remove imported ext_resource lines,
## insert sub_resource blocks, update references.
func rewrite_scene_for_import(
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

	result_text = update_load_steps(result_text)
	return result_text


## Remap SubResource() and ExtResource() references.
func remap_references(
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


## Recount resources and update load_steps in the header.
func update_load_steps(content: String) -> String:
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


# ── Private helpers ──────────────────────────────────────


## Check if the output array has any ext_resource lines.
func _had_ext_resource(output: Array) -> bool:
	for i in range(output.size() - 1, -1, -1):
		if output[i].begins_with("[ext_resource "):
			return true
		if output[i].begins_with("[gd_scene "):
			return true
	return false
