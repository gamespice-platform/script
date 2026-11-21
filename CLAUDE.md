# GameSpice Script

Godot 4.7+ addon for sandboxed, data-driven scripting on community servers: triggers, conditions and a whitelist of actions in a document, a per-tick cost budget, and no arbitrary code. Read the family [CLAUDE.md](../../CLAUDE.md) first. **The distributable is `addons/gs_script/`**; it requires [GameSpice Core](../gs-core) only (`ln -s ../../gs-core/addons/gs_core addons/gs_core`, gitignored).

| Path | What |
| --- | --- |
| `core/gs_script_config.gd` | `GSScriptConfig`: every tunable, `from_files()` |
| `core/gs_script_actions.gd` | `GSScriptActions`: the whitelist (message, set_var, add_var, toggle_var, enable_rule, disable_rule, emit) and `register()` for the game's own, each with typed args and a cost |
| `core/gs_script_conditions.gd` | `GSScriptConditions`: static, allocation-free `when` evaluation, `ctx.` reads |
| `core/gs_script_codec.gd` | `GSScriptCodec`: JSON text in and out, size limit |
| `core/gs_script_document.gd` | `GSScriptDocument.validate()`: the whole document checked, every error listed |
| `runtime/gs_script_runner.gd` | `GSScriptRunner`: `fire()` queues, `advance()` cools, `tick()` runs under the cost budget, `snapshot()`/`restore()`; `vars`, `message`, `refused` |
| `examples/script_selftest.tscn` | the suite (68 checks plus the two summary checks); `examples/script_demo.gd` is the walk-through |

- **Boundary.** gs-script is the community-authored, sandboxed rule document: event, conditions, whitelisted actions, cost budget. It is NOT `GSMapScript` (gs-map's replay of converted `lua_run` calls through a fixed OPS table), NOT gs-game's `GSGameMapScripts` (`script.*` events), NOT entity I/O (gs-logic generic, gs-map Source entities). **Hard rules:** no `eval`, no `Expression`, no code from a string, no method names from data; actions are registered ids only; the selftest scans the sources for banned text and must stay green. Shipped pack scripts use no `uid://` and no `class_name` reliance.
- **No hard caps**: every limit is a config field, 0 means unlimited, and a refusal says why. Nothing is clamped silently.
- **No autoloads, no scene paths**, no class_name reliance in shipped scripts.
- **Validate**: `--import`, parse every `.gd`, run the suite through `hv`.
