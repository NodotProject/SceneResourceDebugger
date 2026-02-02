@tool
class_name ImportFileUtils
extends RefCounted
## File utility helpers for the scene resource importer:
## backup, cleanup, file discovery, and reference checking.

const _TEMP_PATH: String = (
	"res://.scene_res_import_temp.tres"
)


## Check if an ext_resource path is an importable resource.
static func is_importable_path(path: String) -> bool:
	return path.ends_with(".res") or path.ends_with(".tres")


## Delete imported files that are no longer referenced by
## any other .tscn file in the project.
func delete_unreferenced_files(
	imported_paths: Array[String],
	scene_path: String,
	result: RefCounted
) -> void:
	var tscn_paths: PackedStringArray = []
	find_tscn_files("res://", tscn_paths)

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
func find_tscn_files(
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
				find_tscn_files(
					path.path_join(file_name), results
				)
		elif file_name.ends_with(".tscn"):
			results.append(path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()


## Remove the temporary .tres file.
func cleanup_temp() -> void:
	if FileAccess.file_exists(_TEMP_PATH):
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(_TEMP_PATH)
		)


## Create a backup copy of a scene file.
func backup_scene(scene_path: String) -> Error:
	var backup_path: String = scene_path + ".backup"
	var abs_src: String = ProjectSettings.globalize_path(
		scene_path
	)
	var abs_dst: String = ProjectSettings.globalize_path(
		backup_path
	)
	return DirAccess.copy_absolute(abs_src, abs_dst)
