@tool
extends EditorPlugin

const DebuggerPanel := preload(
	"res://addons/scene_resource_debugger/debugger_panel.gd"
)


class SceneResourceDebuggerPlugin extends EditorDebuggerPlugin:
	var _panels: Dictionary = {} # session_id -> Control


	func _has_capture(capture: String) -> bool:
		return capture == "scene_resource_debugger"


	func _capture(
		_message: String, _data: Array, _session_id: int
	) -> bool:
		return false


	func _setup_session(session_id: int) -> void:
		var panel: Control = DebuggerPanel.new()
		panel.name = "Scene Resources"

		var session: EditorDebuggerSession = get_session(
			session_id
		)
		session.started.connect(
			func() -> void:
				_on_session_started(session_id)
		)
		session.stopped.connect(
			func() -> void:
				_on_session_stopped(session_id)
		)
		session.add_session_tab(panel)
		_panels[session_id] = panel


	func _on_session_started(session_id: int) -> void:
		var panel := _panels.get(session_id) as Control
		if panel and panel.has_method("on_session_started"):
			panel.on_session_started()


	func _on_session_stopped(session_id: int) -> void:
		var panel := _panels.get(session_id) as Control
		if panel and panel.has_method("on_session_stopped"):
			panel.on_session_stopped()


var _debugger_plugin: SceneResourceDebuggerPlugin


func _enter_tree() -> void:
	_debugger_plugin = SceneResourceDebuggerPlugin.new()
	add_debugger_plugin(_debugger_plugin)


func _exit_tree() -> void:
	remove_debugger_plugin(_debugger_plugin)
	_debugger_plugin = null
