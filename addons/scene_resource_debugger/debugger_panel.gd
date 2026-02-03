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
var _logger: PanelLogger


func _ready() -> void:
	_analyzer = SceneAnalyzer.new()
	_exporter = ResourceExporter.new()
	_importer = SceneResImporter.new()
	_build_ui()
	_logger = PanelLogger.new(_log_output)


func on_session_started() -> void:
	_logger.log_message("Session started. Click 'Scan Project' to analyze.")


func on_session_stopped() -> void:
	_logger.log_message("Session stopped.")


func _build_ui() -> void:
	var controls := PanelBuilder.build(self)
	_scan_button = controls["scan_button"]
	_refresh_button = controls["refresh_button"]
	_addons_check = controls["addons_check"]
	_status_label = controls["status_label"]
	_scene_filter = controls["scene_filter"]
	_scene_tree = controls["scene_tree"]
	_detail_title = controls["detail_title"]
	_resource_tree = controls["resource_tree"]
	_export_all_button = controls["export_all_button"]
	_export_dir_input = controls["export_dir_input"]
	_browse_dir_button = controls["browse_dir_button"]
	_export_selected_button = controls["export_selected_button"]
	_import_all_button = controls["import_all_button"]
	_log_output = controls["log_output"]

	# Connect signals
	_scan_button.pressed.connect(_on_scan_pressed)
	_refresh_button.pressed.connect(_on_scan_pressed)
	_scene_filter.text_changed.connect(_on_filter_changed)
	_scene_tree.item_selected.connect(_on_scene_selected)
	_export_all_button.pressed.connect(_on_export_all_pressed)
	_browse_dir_button.pressed.connect(_on_browse_dir_pressed)
	_export_selected_button.pressed.connect(
		_on_export_selected_pressed
	)
	_import_all_button.pressed.connect(
		_on_import_all_pressed
	)


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
	_logger.log_message(
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
		_logger.log_message("[color=red]ERROR: No scene selected.[/color]")
		return

	var target_dir: String = _export_dir_input.text.strip_edges()
	if target_dir.is_empty():
		target_dir = _current_analysis.file_path.get_base_dir()

	var scene_name: String = (
		_current_analysis.file_path.get_file()
	)
	_logger.log_message(
		"Exporting sub_resources from %s to %s..."
		% [scene_name, target_dir]
	)
	_export_all_button.disabled = true

	var result := _exporter.export_all_resources(
		_current_analysis.file_path, target_dir
	)
	if result.success:
		_logger.log_message(
			"[color=green]Exported %d resources.[/color]"
			% result.exported_count
		)
		for p in result.exported_paths:
			_logger.log_message("  -> %s" % p)
		_logger.log_verification(result)
		_refresh_editor_filesystem()
		# Refresh analysis for the modified scene
		_on_scan_pressed()
	else:
		_logger.log_message(
			"[color=red]ERROR: %s[/color]"
			% result.error_message
		)

	_export_all_button.disabled = false


func _on_export_selected_pressed() -> void:
	if not _current_analysis:
		_logger.log_message("[color=red]ERROR: No scene selected.[/color]")
		return

	var selected: TreeItem = _resource_tree.get_selected()
	if not selected:
		_logger.log_message(
			"[color=red]ERROR: Select a resource first.[/color]"
		)
		return

	var sub_res_id: String = selected.get_metadata(0) as String
	if sub_res_id.is_empty():
		_logger.log_message(
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
				_logger.log_message(
					"[color=green]Exported to %s[/color]"
					% path
				)
				_logger.log_verification(result)
				_refresh_editor_filesystem()
				_on_scan_pressed()
			else:
				_logger.log_message(
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
		_logger.log_message("[color=red]ERROR: No scene selected.[/color]")
		return

	var scene_name: String = (
		_current_analysis.file_path.get_file()
	)
	_logger.log_message(
		"Importing external resources back into %s..."
		% scene_name
	)
	_import_all_button.disabled = true

	var result: RefCounted = _importer.import_all_resources(
		_current_analysis.file_path
	)
	if result.success:
		_logger.log_message(
			"[color=green]Imported %d resources.[/color]"
			% result.imported_count
		)
		for p: String in result.imported_paths:
			_logger.log_message("  <- %s" % p)
		if not result.deleted_files.is_empty():
			_logger.log_message(
				"[color=green]Deleted %d unreferenced "
				% result.deleted_files.size()
				+ "files:[/color]"
			)
			for p: String in result.deleted_files:
				_logger.log_message("  x %s" % p)
		if not result.kept_files.is_empty():
			_logger.log_message(
				"Kept %d files (still referenced "
				% result.kept_files.size()
				+ "by other scenes):"
			)
			for p: String in result.kept_files:
				_logger.log_message("  ~ %s" % p)
		_logger.log_import_verification(result)
		_refresh_editor_filesystem()
		_on_scan_pressed()
	else:
		_logger.log_message(
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
		item.set_text(1, _logger.format_bytes(analysis.file_size))
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
			2, _logger.format_bytes(info["bytes"])
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
					2, _logger.format_bytes(sub_res.byte_size)
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


# ── Editor filesystem ────────────────────────────────────────


func _refresh_editor_filesystem() -> void:
	if not Engine.is_editor_hint():
		return
	var efs := EditorInterface.get_resource_filesystem()
	if efs:
		efs.scan()


# ── Utilities ────────────────────────────────────────────────


func _has_importable_ext_resources(
	analysis: RefCounted
) -> bool:
	if not analysis:
		return false
	for ext_res in analysis.ext_resources:
		if ImportFileUtils.is_importable_path(
			ext_res.path
		):
			return true
	return false
