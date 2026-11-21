# GameSpice Script

Godot 4.7+ addon for sandboxed, data-driven scripting on community servers: triggers, conditions and a whitelist of actions in a document, a per-tick cost budget, and no arbitrary code. Read the family [CLAUDE.md](../../CLAUDE.md) first. **The distributable is `addons/dot_script/`**; it requires [GameSpice Core](../dot-core) only (`ln -s ../../dot-core/addons/dot_core addons/dot_core`, gitignored).

| Path | What |
| --- | --- |
| `core/dot_script_config.gd` | `DotScriptConfig`: every tunable, `from_files()` |
| `core/dot_script_actions.gd` | `DotScriptActions`: the whitelist (message, set_var, add_var, toggle_var, enable_rule, disable_rule, emit) and `register()` for the game's own, each with typed args and a cost |
| `core/dot_script_conditions.gd` | `DotScriptConditions`: static, allocation-free `when` evaluation, `ctx.` reads |
| `core/dot_script_codec.gd` | `DotScriptCodec`: JSON text in and out, size limit |
| `core/dot_script_document.gd` | `DotScriptDocument.validate()`: the whole document checked, every error listed |
| `runtime/dot_script_runner.gd` | `DotScriptRunner`: `fire()` queues, `advance()` cools, `tick()` runs under the cost budget, `snapshot()`/`restore()`; `vars`, `message`, `refused` |
| `examples/script_selftest.tscn` | the suite (68 checks plus the two summary checks); `examples/script_demo.gd` is the walk-through |

- **Boundary.** dot-script is the community-authored, sandboxed rule document: event, conditions, whitelisted actions, cost budget. It is NOT `DotMapScript` (dot-map's replay of converted `lua_run` calls through a fixed OPS table), NOT dot-game's `DotGameMapScripts` (`script.*` events), NOT entity I/O (dot-logic generic, dot-map Source entities). **Hard rules:** no `eval`, no `Expression`, no code from a string, no method names from data; actions are registered ids only; the selftest scans the sources for banned text and must stay green. Shipped pack scripts use no `uid://` and no `class_name` reliance.
- **No hard caps**: every limit is a config field, 0 means unlimited, and a refusal says why. Nothing is clamped silently.
- **No autoloads, no scene paths**, no class_name reliance in shipped scripts.
- **Validate**: `--import`, parse every `.gd`, run the suite through `hv`.
