@tool
class_name PanelBuilder
extends RefCounted
## Builds the debugger panel UI and returns references to
## all created controls in a dictionary.


## Build the full panel UI inside the given VBoxContainer.
## Returns a Dictionary of control references:
##   scan_button, refresh_button, addons_check, status_label,
##   scene_filter, scene_tree, detail_title, resource_tree,
##   export_all_button, export_dir_input, browse_dir_button,
##   export_selected_button, import_all_button, log_output.
static func build(panel: VBoxContainer) -> Dictionary:
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var controls: Dictionary = {}
	_build_toolbar(panel, controls)
	_build_main_content(panel, controls)
	return controls


static func _build_toolbar(
	panel: VBoxContainer, controls: Dictionary
) -> void:
	var toolbar := HBoxContainer.new()
	panel.add_child(toolbar)

	var scan_button := Button.new()
	scan_button.text = "Scan Project"
	toolbar.add_child(scan_button)
	controls["scan_button"] = scan_button

	var refresh_button := Button.new()
	refresh_button.text = "Refresh"
	toolbar.add_child(refresh_button)
	controls["refresh_button"] = refresh_button

	var addons_check := CheckBox.new()
	addons_check.text = "Include addons"
	addons_check.button_pressed = false
	toolbar.add_child(addons_check)
	controls["addons_check"] = addons_check

	var status_label := Label.new()
	status_label.text = (
		"Click 'Scan Project' to analyze scenes"
	)
	status_label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	status_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	toolbar.add_child(status_label)
	controls["status_label"] = status_label


static func _build_main_content(
	panel: VBoxContainer, controls: Dictionary
) -> void:
	var main_split := HSplitContainer.new()
	main_split.size_flags_vertical = (
		Control.SIZE_EXPAND_FILL
	)
	main_split.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	panel.add_child(main_split)

	_build_scene_list(main_split, controls)
	_build_detail_panel(main_split, controls)


static func _build_scene_list(
	parent: Control, controls: Dictionary
) -> void:
	var container := VBoxContainer.new()
	container.custom_minimum_size = Vector2(350, 0)
	container.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	parent.add_child(container)

	var header := Label.new()
	header.text = "Scenes by Size"
	container.add_child(header)

	var scene_filter := LineEdit.new()
	scene_filter.placeholder_text = "Filter scenes..."
	container.add_child(scene_filter)
	controls["scene_filter"] = scene_filter

	var scene_tree := Tree.new()
	scene_tree.size_flags_vertical = (
		Control.SIZE_EXPAND_FILL
	)
	scene_tree.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	scene_tree.columns = 3
	scene_tree.set_column_title(0, "Scene")
	scene_tree.set_column_title(1, "Size")
	scene_tree.set_column_title(2, "Sub-Resources")
	scene_tree.column_titles_visible = true
	scene_tree.set_column_expand(0, true)
	scene_tree.set_column_expand(1, false)
	scene_tree.set_column_custom_minimum_width(1, 80)
	scene_tree.set_column_expand(2, false)
	scene_tree.set_column_custom_minimum_width(2, 100)
	container.add_child(scene_tree)
	controls["scene_tree"] = scene_tree


static func _build_detail_panel(
	parent: Control, controls: Dictionary
) -> void:
	var container := VBoxContainer.new()
	container.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	parent.add_child(container)

	var detail_title := Label.new()
	detail_title.text = (
		"Select a scene to view resource breakdown"
	)
	container.add_child(detail_title)
	controls["detail_title"] = detail_title

	var resource_tree := Tree.new()
	resource_tree.size_flags_vertical = (
		Control.SIZE_EXPAND_FILL
	)
	resource_tree.columns = 3
	resource_tree.set_column_title(0, "Type / ID")
	resource_tree.set_column_title(1, "Count")
	resource_tree.set_column_title(2, "Est. Size")
	resource_tree.column_titles_visible = true
	resource_tree.set_column_expand(0, true)
	resource_tree.set_column_expand(1, false)
	resource_tree.set_column_custom_minimum_width(1, 60)
	resource_tree.set_column_expand(2, false)
	resource_tree.set_column_custom_minimum_width(2, 80)
	container.add_child(resource_tree)
	controls["resource_tree"] = resource_tree

	var separator := HSeparator.new()
	container.add_child(separator)

	_build_export_controls(container, controls)

	var log_output := RichTextLabel.new()
	log_output.custom_minimum_size = Vector2(0, 100)
	log_output.size_flags_vertical = (
		Control.SIZE_EXPAND_FILL
	)
	log_output.bbcode_enabled = true
	log_output.scroll_following = true
	log_output.selection_enabled = true
	log_output.context_menu_enabled = true
	container.add_child(log_output)
	controls["log_output"] = log_output


static func _build_export_controls(
	parent: Control, controls: Dictionary
) -> void:
	# Export all row
	var export_all_row := HBoxContainer.new()
	parent.add_child(export_all_row)

	var export_all_button := Button.new()
	export_all_button.text = "Export All to Binary (.res)"
	export_all_button.disabled = true
	export_all_row.add_child(export_all_button)
	controls["export_all_button"] = export_all_button

	var export_dir_input := LineEdit.new()
	export_dir_input.placeholder_text = "(scene directory)"
	export_dir_input.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	export_all_row.add_child(export_dir_input)
	controls["export_dir_input"] = export_dir_input

	var browse_dir_button := Button.new()
	browse_dir_button.text = "Browse..."
	export_all_row.add_child(browse_dir_button)
	controls["browse_dir_button"] = browse_dir_button

	# Export selected row
	var export_sel_row := HBoxContainer.new()
	parent.add_child(export_sel_row)

	var export_selected_button := Button.new()
	export_selected_button.text = (
		"Export Selected Resource..."
	)
	export_selected_button.disabled = true
	export_sel_row.add_child(export_selected_button)
	controls["export_selected_button"] = export_selected_button

	# Import row
	var import_row := HBoxContainer.new()
	parent.add_child(import_row)

	var import_all_button := Button.new()
	import_all_button.text = (
		"Import All External Resources Into Scene"
	)
	import_all_button.disabled = true
	import_row.add_child(import_all_button)
	controls["import_all_button"] = import_all_button
