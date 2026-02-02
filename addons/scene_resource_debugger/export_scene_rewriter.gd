@tool
class_name ExportSceneRewriter
extends RefCounted
## Rewrites a .tscn file to replace embedded [sub_resource]
## blocks with [ext_resource] references pointing to
## exported .res files.


## Rewrite the .tscn file: remove sub_resource blocks,
## add ext_resource lines, replace SubResource() refs.
func rewrite_scene_text(
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
	result_text = update_load_steps(result_text)

	# Write the modified file
	var out_file := FileAccess.open(
		scene_path, FileAccess.WRITE
	)
	if not out_file:
		return ERR_FILE_CANT_WRITE
	out_file.store_string(result_text)
	out_file.close()
	return OK


## Recount ext_resource + sub_resource entries and update
## load_steps in the gd_scene header.
func update_load_steps(content: String) -> String:
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


# ── Private helpers ──────────────────────────────────────


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
