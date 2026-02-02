# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Scene Resource Debugger is a Godot 4.6 editor plugin (GDScript) that analyzes large `.tscn` scene files, exports embedded sub_resources to external binary `.res` files, and can re-import them. It runs as an `EditorDebuggerPlugin` inside the Godot editor.

## Commands

### Run tests
```bash
./run_tests.sh
# Or with a custom Godot binary:
GODOT=/path/to/godot ./run_tests.sh
```

Tests use the GUT (Godot Unit Testing) framework. Test files live in `test/unit/` and follow the `test_*.gd` naming convention. Test classes extend `GutTest` and use `assert_eq()`, `assert_not_null()`, `assert_has()`, etc. Setup/teardown uses `before_each()`/`after_each()`.

Test fixtures (sample `.tscn` files) are in `test/fixtures/`.

### Run a single test file
```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/unit/ -gprefix=test_ -gtest=test_scene_analyzer.gd -gexit
```

## Architecture

All plugin source lives in `addons/scene_resource_debugger/`. Every script uses `@tool` and `class_name`.

### Core flow

**Plugin entry point**: `plugin.gd` (`SceneResourceDebuggerPlugin extends EditorDebuggerPlugin`) manages debugger sessions and creates the panel.

**UI**: `debugger_panel.gd` (`DebuggerPanel`) is the main VBoxContainer panel. `panel_builder.gd` constructs all UI controls programmatically. `panel_logger.gd` handles formatted log output.

**Analysis**: `scene_analyzer.gd` (`SceneResourceAnalyzer`) parses `.tscn` text files with RegEx to extract sub_resource/ext_resource metadata, sizes, and node counts.

**Export workflow** (embed → external):
1. `resource_collector.gd` walks the instantiated scene tree, collects embedded resources, and topologically sorts them (leaf-first)
2. `resource_exporter.gd` saves each resource as binary `.res` (filters out resources < 100 KB)
3. `export_scene_rewriter.gd` text-rewrites the `.tscn` to replace `[sub_resource]` blocks with `[ext_resource]` references

**Import workflow** (external → embed):
1. `resource_importer.gd` loads external `.res` files and serializes to temporary `.tres`
2. `tres_parser.gd` parses `.tres` into sections
3. `import_scene_rewriter.gd` text-rewrites the `.tscn` to embed resources back, remapping IDs to avoid conflicts
4. `import_file_utils.gd` handles backup, cleanup, and orphaned file deletion

### Key design decisions

- Scene files are manipulated via **text rewriting** (RegEx-based), not Godot's resource API, to preserve formatting and handle UID references
- Export/import operations **backup the scene file** before modification and verify sub_resource counts before/after
- Resources are topologically sorted by dependency order before export
