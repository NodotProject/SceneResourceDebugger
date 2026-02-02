@tool
class_name ResourceCollector
extends RefCounted
## Walks a node tree collecting embedded sub_resources and
## sorts them by dependency order for export.


## Walk a node tree recursively collecting embedded resources.
func walk_node_resources(
	node: Node, collected: Dictionary
) -> void:
	_inspect_node_properties(node, collected)
	for child in node.get_children():
		walk_node_resources(child, collected)


## Sort collected resources by dependency order:
## leaf resources first, composites last.
func dependency_sort(collected: Dictionary) -> Array:
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


## Extract the sub_resource ID from a resource's embedded
## path. Godot sets paths like "res://scene.tscn::Type_id"
## for embedded sub_resources. Returns the part after "::".
func extract_sub_resource_id(resource: Resource) -> String:
	var rpath: String = resource.resource_path
	var sep_pos: int = rpath.find("::")
	if sep_pos >= 0:
		return rpath.substr(sep_pos + 2)
	return ""


## Find a resource in the collected dict by sub_resource id.
## Matches via the embedded path suffix (::Type_id).
func find_resource_by_id(
	collected: Dictionary, sub_id: String
) -> Resource:
	for key in collected:
		var entry: Dictionary = collected[key]
		var res: Resource = entry["resource"]
		if extract_sub_resource_id(res) == sub_id:
			return res
	return null


# ── Private helpers ──────────────────────────────────────


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
