@tool
extends VBoxContainer
## Debugger panel UI for the Scene Resource Debugger.
## Lists scenes by size and shows embedded resource breakdown.

const SceneAnalyzer := preload(
	"res://addons/scene_resource_debugger/scene_analyzer.gd"
)
const ResourceExporter := preload(
	"res://addons/scene_resource_debugger/resource_exporter.gd"
)
const SceneResImporter := preload(
	"res://addons/scene_resource_debugger/resource_importer.gd"
)

var _analyzer: SceneAnalyzer
var _exporter: ResourceExporter
var _importer: SceneResourceImporter
var _scene_analyses: Array = [] # Array[SceneAnalysis]
var _current_analysis: RefCounted = null # SceneAnalysis

# Toolbar
var _scan_button: Button
var _refresh_button: Button
var _addons_check: CheckBox
var _status_label: Label

# Scene list (left)
var _scene_filter: LineEdit
var _scene_tree: Tree

# Detail view (right)
var _detail_title: Label
var _resource_tree: Tree

# Export controls
var _export_all_button: Button
var _export_dir_input: LineEdit
var _browse_dir_button: Button
var _export_selected_button: Button
var _import_all_button: Button
var _log_output: RichTextLabel


func _ready() -> void:
	_analyzer = SceneAnalyzer.new()
	_exporter = ResourceExporter.new()
	_importer = SceneResImporter.new()
	_build_ui()


func on_session_started() -> void:
	_log("Session started. Click 'Scan Project' to analyze.")


func on_session_stopped() -> void:
	_log("Session stopped.")


func _build_ui() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_build_toolbar()
	_build_main_content()


func _build_toolbar() -> void:
	var toolbar := HBoxContainer.new()
	add_child(toolbar)

	_scan_button = Button.new()
	_scan_button.text = "Scan Project"
	_scan_button.pressed.connect(_on_scan_pressed)
	toolbar.add_child(_scan_button)

	_refresh_button = Button.new()
	_refresh_button.text = "Refresh"
	_refresh_button.pressed.connect(_on_scan_pressed)
	toolbar.add_child(_refresh_button)

	_addons_check = CheckBox.new()
	_addons_check.text = "Include addons"
	_addons_check.button_pressed = false
	toolbar.add_child(_addons_check)

	_status_label = Label.new()
	_status_label.text = "Click 'Scan Project' to analyze scenes"
	_status_label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	_status_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	toolbar.add_child(_status_label)


func _build_main_content() -> void:
	var main_split := HSplitContainer.new()
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(main_split)

	_build_scene_list(main_split)
	_build_detail_panel(main_split)


func _build_scene_list(parent: Control) -> void:
	var container := VBoxContainer.new()
	container.custom_minimum_size = Vector2(350, 0)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(container)

	var header := Label.new()
	header.text = "Scenes by Size"
	container.add_child(header)

	_scene_filter = LineEdit.new()
	_scene_filter.placeholder_text = "Filter scenes..."
	_scene_filter.text_changed.connect(_on_filter_changed)
	container.add_child(_scene_filter)

	_scene_tree = Tree.new()
	_scene_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scene_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scene_tree.columns = 3
	_scene_tree.set_column_title(0, "Scene")
	_scene_tree.set_column_title(1, "Size")
	_scene_tree.set_column_title(2, "Sub-Resources")
	_scene_tree.column_titles_visible = true
	_scene_tree.set_column_expand(0, true)
	_scene_tree.set_column_expand(1, false)
	_scene_tree.set_column_custom_minimum_width(1, 80)
	_scene_tree.set_column_expand(2, false)
	_scene_tree.set_column_custom_minimum_width(2, 100)
	_scene_tree.item_selected.connect(_on_scene_selected)
	container.add_child(_scene_tree)


func _build_detail_panel(parent: Control) -> void:
	var container := VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(container)

	_detail_title = Label.new()
	_detail_title.text = "Select a scene to view resource breakdown"
	container.add_child(_detail_title)

	_resource_tree = Tree.new()
	_resource_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_resource_tree.columns = 3
	_resource_tree.set_column_title(0, "Type / ID")
	_resource_tree.set_column_title(1, "Count")
	_resource_tree.set_column_title(2, "Est. Size")
	_resource_tree.column_titles_visible = true
	_resource_tree.set_column_expand(0, true)
	_resource_tree.set_column_expand(1, false)
	_resource_tree.set_column_custom_minimum_width(1, 60)
	_resource_tree.set_column_expand(2, false)
	_resource_tree.set_column_custom_minimum_width(2, 80)
	container.add_child(_resource_tree)

	var separator := HSeparator.new()
	container.add_child(separator)

	_build_export_controls(container)

	_log_output = RichTextLabel.new()
	_log_output.custom_minimum_size = Vector2(0, 100)
	_log_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_output.bbcode_enabled = true
	_log_output.scroll_following = true
	_log_output.selection_enabled = true
	_log_output.context_menu_enabled = true
	container.add_child(_log_output)


func _build_export_controls(parent: Control) -> void:
	# Export all row
	var export_all_row := HBoxContainer.new()
	parent.add_child(export_all_row)

	_export_all_button = Button.new()
	_export_all_button.text = "Export All to Binary (.res)"
	_export_all_button.disabled = true
	_export_all_button.pressed.connect(_on_export_all_pressed)
	export_all_row.add_child(_export_all_button)

	_export_dir_input = LineEdit.new()
	_export_dir_input.placeholder_text = "(scene directory)"
	_export_dir_input.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	export_all_row.add_child(_export_dir_input)

	_browse_dir_button = Button.new()
	_browse_dir_button.text = "Browse..."
	_browse_dir_button.pressed.connect(_on_browse_dir_pressed)
	export_all_row.add_child(_browse_dir_button)

	# Export selected row
	var export_sel_row := HBoxContainer.new()
	parent.add_child(export_sel_row)

	_export_selected_button = Button.new()
	_export_selected_button.text = "Export Selected Resource..."
	_export_selected_button.disabled = true
	_export_selected_button.pressed.connect(
		_on_export_selected_pressed
	)
	export_sel_row.add_child(_export_selected_button)

	# Import row
	var import_row := HBoxContainer.new()
	parent.add_child(import_row)

	_import_all_button = Button.new()
	_import_all_button.text = (
		"Import All External Resources Into Scene"
	)
	_import_all_button.disabled = true
	_import_all_button.pressed.connect(
		_on_import_all_pressed
	)
	import_row.add_child(_import_all_button)


# ── Signal handlers ──────────────────────────────────────────


func _on_scan_pressed() -> void:
	_status_label.text = "Scanning project..."
	var include_addons: bool = _addons_check.button_pressed
	_scene_analyses = _analyzer.scan_project(
		"res://", include_addons
	)
	_populate_scene_tree()

	var scenes_with_subs: int = 0
	for a in _scene_analyses:
		if a.sub_resources.size() > 0:
			scenes_with_subs += 1

	_status_label.text = (
		"Found %d scenes (%d with embedded resources)"
		% [_scene_analyses.size(), scenes_with_subs]
	)
	_log(
		"Scan complete: %d scenes found."
		% _scene_analyses.size()
	)


func _on_filter_changed(_new_text: String) -> void:
	_populate_scene_tree()


func _on_scene_selected() -> void:
	var selected: TreeItem = _scene_tree.get_selected()
	if not selected:
		return

	_current_analysis = selected.get_metadata(0)
	if not _current_analysis:
		return

	var path: String = _current_analysis.file_path
	_detail_title.text = (
		"Resources in: %s" % path.get_file()
	)
	_populate_resource_tree()

	_export_dir_input.placeholder_text = path.get_base_dir()
	_export_all_button.disabled = (
		_current_analysis.sub_resources.is_empty()
	)
	_export_selected_button.disabled = true
	_import_all_button.disabled = (
		not _has_importable_ext_resources(_current_analysis)
	)


func _on_export_all_pressed() -> void:
	if not _current_analysis:
		_log("[color=red]ERROR: No scene selected.[/color]")
		return

	var target_dir: String = _export_dir_input.text.strip_edges()
	if target_dir.is_empty():
		target_dir = _current_analysis.file_path.get_base_dir()

	var scene_name: String = (
		_current_analysis.file_path.get_file()
	)
	_log(
		"Exporting sub_resources from %s to %s..."
		% [scene_name, target_dir]
	)
	_export_all_button.disabled = true

	var result := _exporter.export_all_resources(
		_current_analysis.file_path, target_dir
	)
	if result.success:
		_log(
			"[color=green]Exported %d resources.[/color]"
			% result.exported_count
		)
		for p in result.exported_paths:
			_log("  -> %s" % p)
		_log_verification(result)
		# Refresh analysis for the modified scene
		_on_scan_pressed()
	else:
		_log(
			"[color=red]ERROR: %s[/color]"
			% result.error_message
		)

	_export_all_button.disabled = false


func _on_export_selected_pressed() -> void:
	if not _current_analysis:
		_log("[color=red]ERROR: No scene selected.[/color]")
		return

	var selected: TreeItem = _resource_tree.get_selected()
	if not selected:
		_log(
			"[color=red]ERROR: Select a resource first.[/color]"
		)
		return

	var sub_res_id: String = selected.get_metadata(0) as String
	if sub_res_id.is_empty():
		_log(
			"[color=red]Select an individual resource, "
			+ "not a type group.[/color]"
		)
		return

	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.add_filter("*.res", "Binary Resource")
	dialog.current_file = sub_res_id + ".res"
	dialog.file_selected.connect(
		func(path: String) -> void:
			var result := _exporter.export_single_resource(
				_current_analysis.file_path, sub_res_id, path
			)
			if result.success:
				_log(
					"[color=green]Exported to %s[/color]"
					% path
				)
				_log_verification(result)
				_on_scan_pressed()
			else:
				_log(
					"[color=red]ERROR: %s[/color]"
					% result.error_message
				)
			dialog.queue_free()
	)
	dialog.canceled.connect(
		func() -> void:
			dialog.queue_free()
	)
	add_child(dialog)
	dialog.popup_centered(Vector2i(700, 500))


func _on_import_all_pressed() -> void:
	if not _current_analysis:
		_log("[color=red]ERROR: No scene selected.[/color]")
		return

	var scene_name: String = (
		_current_analysis.file_path.get_file()
	)
	_log(
		"Importing external resources back into %s..."
		% scene_name
	)
	_import_all_button.disabled = true

	var result: RefCounted = _importer.import_all_resources(
		_current_analysis.file_path
	)
	if result.success:
		_log(
			"[color=green]Imported %d resources.[/color]"
			% result.imported_count
		)
		for p: String in result.imported_paths:
			_log("  <- %s" % p)
		if not result.deleted_files.is_empty():
			_log(
				"[color=green]Deleted %d unreferenced "
				% result.deleted_files.size()
				+ "files:[/color]"
			)
			for p: String in result.deleted_files:
				_log("  x %s" % p)
		if not result.kept_files.is_empty():
			_log(
				"Kept %d files (still referenced "
				% result.kept_files.size()
				+ "by other scenes):"
			)
			for p: String in result.kept_files:
				_log("  ~ %s" % p)
		_log_import_verification(result)
		_on_scan_pressed()
	else:
		_log(
			"[color=red]ERROR: %s[/color]"
			% result.error_message
		)

	_import_all_button.disabled = false


func _on_browse_dir_pressed() -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.dir_selected.connect(
		func(dir: String) -> void:
			_export_dir_input.text = dir
			dialog.queue_free()
	)
	dialog.canceled.connect(
		func() -> void:
			dialog.queue_free()
	)
	add_child(dialog)
	dialog.popup_centered(Vector2i(700, 500))


# ── Tree population ──────────────────────────────────────────


func _populate_scene_tree() -> void:
	_scene_tree.clear()
	var root: TreeItem = _scene_tree.create_item()
	root.set_text(0, "Project Scenes")
	var filter_text: String = _scene_filter.text.to_lower()

	for analysis in _scene_analyses:
		var path: String = analysis.file_path
		if not filter_text.is_empty():
			if path.to_lower().find(filter_text) == -1:
				continue

		var item: TreeItem = _scene_tree.create_item(root)
		item.set_text(0, path.get_file())
		item.set_tooltip_text(0, path)
		item.set_text(1, _format_bytes(analysis.file_size))
		item.set_text(
			2, str(analysis.sub_resources.size())
		)
		item.set_metadata(0, analysis)

	_current_analysis = null
	_detail_title.text = (
		"Select a scene to view resource breakdown"
	)
	_resource_tree.clear()
	_export_all_button.disabled = true
	_export_selected_button.disabled = true
	_import_all_button.disabled = true


func _populate_resource_tree() -> void:
	_resource_tree.clear()
	if not _current_analysis:
		return

	var root: TreeItem = _resource_tree.create_item()
	root.set_text(0, "Embedded Resources")

	var summary: Dictionary = _current_analysis.type_summary
	# Sort types by total bytes descending
	var type_keys: Array = summary.keys()
	type_keys.sort_custom(
		func(a: String, b: String) -> bool:
			return summary[a]["bytes"] > summary[b]["bytes"]
	)

	for type_name: String in type_keys:
		var info: Dictionary = summary[type_name]
		var type_item: TreeItem = (
			_resource_tree.create_item(root)
		)
		type_item.set_text(0, type_name)
		type_item.set_text(1, str(info["count"]))
		type_item.set_text(
			2, _format_bytes(info["bytes"])
		)
		# Type group has no export metadata
		type_item.set_metadata(0, "")

		# Add individual sub_resources as children
		for sub_res in _current_analysis.sub_resources:
			if sub_res.type == type_name:
				var child: TreeItem = (
					_resource_tree.create_item(type_item)
				)
				child.set_text(0, sub_res.id)
				child.set_text(1, "1")
				child.set_text(
					2, _format_bytes(sub_res.byte_size)
				)
				# Store the sub_resource id for export
				child.set_metadata(0, sub_res.id)

	if not _resource_tree.item_selected.is_connected(
		_on_resource_tree_selected
	):
		_resource_tree.item_selected.connect(
			_on_resource_tree_selected,
			CONNECT_DEFERRED
		)


func _on_resource_tree_selected() -> void:
	var selected: TreeItem = _resource_tree.get_selected()
	if not selected:
		_export_selected_button.disabled = true
		return

	var meta: String = selected.get_metadata(0) as String
	_export_selected_button.disabled = meta.is_empty()


# ── Utilities ────────────────────────────────────────────────


func _format_bytes(bytes: int) -> String:
	if bytes >= 1048576:
		return "%.1f MB" % (bytes / 1048576.0)
	if bytes >= 1024:
		return "%.1f KB" % (bytes / 1024.0)
	return "%d B" % bytes


func _log_verification(result) -> void:
	var before: int = result.sub_resources_before
	var after: int = result.sub_resources_after
	if before < 0 or after < 0:
		_log(
			"[color=yellow]Verification: could not read "
			+ "scene file for sub_resource count.[/color]"
		)
		return

	var removed: int = before - after
	if removed > 0:
		_log(
			("[color=green]Verified: %d sub_resources "
			+ "removed (%d -> %d).[/color]")
			% [removed, before, after]
		)
	elif removed == 0 and result.exported_count > 0:
		_log(
			("[color=yellow]Warning: sub_resource count "
			+ "unchanged (%d). Resources may still be "
			+ "embedded in the scene.[/color]") % before
		)
	else:
		_log(
			"Sub_resources: %d before, %d after."
			% [before, after]
		)
	if not result.error_message.is_empty():
		_log(
			"[color=yellow]%s[/color]"
			% result.error_message
		)


func _has_importable_ext_resources(
	analysis: RefCounted
) -> bool:
	if not analysis:
		return false
	for ext_res in analysis.ext_resources:
		if SceneResourceImporter._is_importable_path(
			ext_res.path
		):
			return true
	return false


func _log_import_verification(result) -> void:
	var before: int = result.ext_resources_before
	var after: int = result.ext_resources_after
	if before < 0 or after < 0:
		_log(
			"[color=yellow]Verification: could not read "
			+ "scene file for ext_resource count.[/color]"
		)
		return

	var removed: int = before - after
	if removed > 0:
		_log(
			("[color=green]Verified: %d ext_resources "
			+ "removed (%d -> %d).[/color]")
			% [removed, before, after]
		)
	elif removed == 0 and result.imported_count > 0:
		_log(
			("[color=yellow]Warning: ext_resource count "
			+ "unchanged (%d). Resources may not have "
			+ "been fully embedded.[/color]") % before
		)
	else:
		_log(
			"Ext_resources: %d before, %d after."
			% [before, after]
		)
	if not result.error_message.is_empty():
		_log(
			"[color=yellow]%s[/color]"
			% result.error_message
		)


func _log(message: String) -> void:
	if _log_output:
		_log_output.append_text(message + "\n")
