extends GutTest
## Tests for PanelLogger — byte formatting and log output.


var _logger: PanelLogger
var _rtl: RichTextLabel


func before_each() -> void:
	_rtl = RichTextLabel.new()
	_rtl.bbcode_enabled = true
	add_child_autofree(_rtl)
	_logger = PanelLogger.new(_rtl)


# ── format_bytes ─────────────────────────────────────────


func test_format_bytes_zero() -> void:
	assert_eq(_logger.format_bytes(0), "0 B")


func test_format_bytes_bytes_range() -> void:
	assert_eq(_logger.format_bytes(512), "512 B")
	assert_eq(_logger.format_bytes(1), "1 B")
	assert_eq(_logger.format_bytes(1023), "1023 B")


func test_format_bytes_kb_range() -> void:
	assert_eq(_logger.format_bytes(2048), "2.0 KB")
	assert_eq(_logger.format_bytes(512000), "500.0 KB")


func test_format_bytes_mb_range() -> void:
	assert_eq(_logger.format_bytes(1048576), "1.0 MB")
	assert_eq(_logger.format_bytes(5242880), "5.0 MB")


func test_format_bytes_exact_boundaries() -> void:
	assert_eq(_logger.format_bytes(1024), "1.0 KB")
	assert_eq(_logger.format_bytes(1048576), "1.0 MB")


# ── log ──────────────────────────────────────────────────


func test_log_appends_to_output() -> void:
	_logger.log_message("Hello world")
	var text: String = _rtl.get_parsed_text()
	assert_string_contains(text, "Hello world")


# ── log_verification (export) ────────────────────────────


func test_log_verification_success() -> void:
	var result := _make_export_result(5, 2, 3)
	_logger.log_verification(result)
	var text: String = _rtl.get_parsed_text()
	assert_string_contains(text, "Verified")
	assert_string_contains(text, "3 sub_resources removed")


func test_log_verification_unchanged() -> void:
	var result := _make_export_result(5, 5, 2)
	_logger.log_verification(result)
	var text: String = _rtl.get_parsed_text()
	assert_string_contains(text, "Warning")
	assert_string_contains(text, "unchanged")


func test_log_verification_unreadable() -> void:
	var result := _make_export_result(-1, -1, 0)
	_logger.log_verification(result)
	var text: String = _rtl.get_parsed_text()
	assert_string_contains(text, "could not read")


# ── log_import_verification ──────────────────────────────


func test_log_import_verification_success() -> void:
	var result := _make_import_result(3, 1, 2)
	_logger.log_import_verification(result)
	var text: String = _rtl.get_parsed_text()
	assert_string_contains(text, "Verified")
	assert_string_contains(text, "2 ext_resources removed")


func test_log_import_verification_unchanged() -> void:
	var result := _make_import_result(3, 3, 1)
	_logger.log_import_verification(result)
	var text: String = _rtl.get_parsed_text()
	assert_string_contains(text, "Warning")
	assert_string_contains(text, "unchanged")


# ── Helpers ──────────────────────────────────────────────


func _make_export_result(
	before: int, after: int, exported: int
) -> RefCounted:
	var r := RefCounted.new()
	r.set_meta("sub_resources_before", before)
	r.set_meta("sub_resources_after", after)
	r.set_meta("exported_count", exported)
	r.set_meta("error_message", "")
	# Make properties accessible via dot notation using a
	# script with those vars. Use a plain object instead.
	return _ExportResultStub.new(before, after, exported)


func _make_import_result(
	before: int, after: int, imported: int
) -> RefCounted:
	return _ImportResultStub.new(before, after, imported)


class _ExportResultStub extends RefCounted:
	var sub_resources_before: int
	var sub_resources_after: int
	var exported_count: int
	var error_message: String = ""
	func _init(b: int, a: int, e: int) -> void:
		sub_resources_before = b
		sub_resources_after = a
		exported_count = e


class _ImportResultStub extends RefCounted:
	var ext_resources_before: int
	var ext_resources_after: int
	var imported_count: int
	var error_message: String = ""
	func _init(b: int, a: int, i: int) -> void:
		ext_resources_before = b
		ext_resources_after = a
		imported_count = i
