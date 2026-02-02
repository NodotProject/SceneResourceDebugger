@tool
class_name PanelLogger
extends RefCounted
## Handles logging output for the debugger panel,
## including verification result formatting.

var _log_output: RichTextLabel


func _init(log_output: RichTextLabel) -> void:
	_log_output = log_output


## Append a message to the log output.
func log_message(message: String) -> void:
	if _log_output:
		_log_output.append_text(message + "\n")


## Format a byte count as a human-readable string.
func format_bytes(bytes: int) -> String:
	if bytes >= 1048576:
		return "%.1f MB" % (bytes / 1048576.0)
	if bytes >= 1024:
		return "%.1f KB" % (bytes / 1024.0)
	return "%d B" % bytes


## Log export verification results.
func log_verification(result) -> void:
	var before: int = result.sub_resources_before
	var after: int = result.sub_resources_after
	if before < 0 or after < 0:
		log_message(
			"[color=yellow]Verification: could not read "
			+ "scene file for sub_resource count.[/color]"
		)
		return

	var removed: int = before - after
	if removed > 0:
		log_message(
			("[color=green]Verified: %d sub_resources "
			+ "removed (%d -> %d).[/color]")
			% [removed, before, after]
		)
	elif removed == 0 and result.exported_count > 0:
		log_message(
			("[color=yellow]Warning: sub_resource count "
			+ "unchanged (%d). Resources may still be "
			+ "embedded in the scene.[/color]") % before
		)
	else:
		log_message(
			"Sub_resources: %d before, %d after."
			% [before, after]
		)
	if not result.error_message.is_empty():
		log_message(
			"[color=yellow]%s[/color]"
			% result.error_message
		)


## Log import verification results.
func log_import_verification(result) -> void:
	var before: int = result.ext_resources_before
	var after: int = result.ext_resources_after
	if before < 0 or after < 0:
		log_message(
			"[color=yellow]Verification: could not read "
			+ "scene file for ext_resource count.[/color]"
		)
		return

	var removed: int = before - after
	if removed > 0:
		log_message(
			("[color=green]Verified: %d ext_resources "
			+ "removed (%d -> %d).[/color]")
			% [removed, before, after]
		)
	elif removed == 0 and result.imported_count > 0:
		log_message(
			("[color=yellow]Warning: ext_resource count "
			+ "unchanged (%d). Resources may not have "
			+ "been fully embedded.[/color]") % before
		)
	else:
		log_message(
			"Ext_resources: %d before, %d after."
			% [before, after]
		)
	if not result.error_message.is_empty():
		log_message(
			"[color=yellow]%s[/color]"
			% result.error_message
		)
