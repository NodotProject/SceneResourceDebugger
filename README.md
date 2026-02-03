# Scene Resource Debugger

A Godot 4.6 editor plugin that analyzes large `.tscn` scene files, exports embedded sub-resources to external binary `.res` files, and can re-import them. Helps reduce scene file bloat and improve version control diffs for projects with heavily embedded resources.

## Features

- **Scene scanning** -- Scan your project for `.tscn` files and list them by size and embedded resource count
- **Resource analysis** -- Break down embedded sub-resources by type (textures, materials, styles, etc.) with size estimates
- **Export to external `.res`** -- Extract embedded sub-resources into standalone binary `.res` files (filters out resources < 100 KB)
- **Re-import** -- Merge exported external resources back into the scene file
- **Verification** -- Sub-resource counts are compared before and after operations to catch errors

## Installation

1. Copy the `addons/scene_resource_debugger/` directory into your project's `addons/` folder
2. Enable the plugin in **Project > Project Settings > Plugins**
3. The debugger panel appears in the editor's **Debugger** bottom panel

## Usage

1. Click **Scan** to find all `.tscn` files in your project
2. Select a scene from the list to see its embedded resource breakdown
3. Choose an export directory and click **Export All** or select individual resources to export
4. Exported resources are saved as binary `.res` files and the scene is rewritten to reference them as external resources
5. To reverse the process, select a scene and click **Import All** to re-embed external resources

## How It Works

Scene files are manipulated via RegEx-based text rewriting rather than Godot's resource API. This preserves formatting, comments, and UID references.

**Export workflow:**
1. Walk the instantiated scene tree and collect embedded resources
2. Topologically sort resources by dependency order (leaf-first)
3. Save each resource as a binary `.res` file
4. Rewrite the `.tscn` to replace `[sub_resource]` blocks with `[ext_resource]` references

**Import workflow:**
1. Load external `.res` files and serialize to temporary `.tres`
2. Parse `.tres` sections and remap IDs to avoid conflicts
3. Rewrite the `.tscn` to embed the resources back inline
4. Clean up temporary files and optionally delete orphaned `.res` files

## Development

### Project structure

```
addons/scene_resource_debugger/
  plugin.gd                 # Entry point (EditorDebuggerPlugin)
  debugger_panel.gd         # Main UI panel
  panel_builder.gd          # Programmatic UI construction
  panel_logger.gd           # Formatted log output
  scene_analyzer.gd         # .tscn parser, extracts resource metadata
  resource_collector.gd     # Walks scene tree, collects resources
  resource_exporter.gd      # Saves resources as binary .res
  export_scene_rewriter.gd  # Rewrites .tscn for export
  resource_importer.gd      # Loads .res, serializes to .tres
  tres_parser.gd            # Parses .tres into sections
  import_scene_rewriter.gd  # Rewrites .tscn for import
  import_file_utils.gd      # Backup, cleanup, orphaned file deletion
```

### Running tests

Tests use the [GUT](https://gut.readthedocs.io/) framework. Test files are in `test/unit/` and fixtures in `test/fixtures/`.

```bash
./run_tests.sh
```

To use a custom Godot binary:

```bash
GODOT=/path/to/godot ./run_tests.sh
```

To run a single test file:

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/unit/ -gprefix=test_ -gtest=test_scene_analyzer.gd -gexit
```

## License

MIT
