class_name DotScriptConfig
extends DotConfig

## Every tunable of Script. Layered like any config: defaults, `cfg/addon/dot_script/*.yml`, the game tier, `DOT_SCRIPT_*` environment, then `--script-*` flags. A value of 0 on a limit means unlimited.

const ADDON := "dot-script"

## Master switch: off, a runner accepts no events and runs nothing.
@export var enabled: bool = true

@export_group("Document")
## The most rules a document may hold. 0 is unlimited.
@export_range(0, 100000, 1) var max_rules: int = 256
## The most actions one rule may run. 0 is unlimited.
@export_range(0, 1000, 1) var max_actions_per_rule: int = 16
## The longest text argument, in characters. 0 is unlimited.
@export_range(0, 100000, 1) var max_text_length: int = 200

@export_group("Runtime")
## Cost units a runner spends per tick; what is left waits for the next tick. 0 is unlimited. A document is refused when one rule alone costs more than this.
@export_range(0, 1000000, 1) var tick_budget: int = 200
## The most events waiting at once; an event past it is refused and counted. 0 is unlimited.
@export_range(0, 1000000, 1) var max_queued_events: int = 1024

@export_group("Actions")
## Action ids a document may use; empty allows every registered action.
@export var allowed_actions: PackedStringArray = PackedStringArray()

func env_prefix() -> String:
	return "DOT_SCRIPT_"


func cli_prefix() -> String:
	return "--script-"


func validate() -> DotResult:
	for k in ["max_rules", "max_actions_per_rule", "max_text_length", "tick_budget", "max_queued_events"]:
		if int(get(k)) < 0:
			return DotResult.fail(DotError.CODE_INVALID, "script %s must be 0 (unlimited) or more, got %d" % [k, int(get(k))])
	return DotResult.success(self)

func describe() -> String:
	return "script %s rules<=%d actions<=%d budget %d queue<=%d allow %d" % [
		"on" if enabled else "disabled", max_rules, max_actions_per_rule, tick_budget, max_queued_events, allowed_actions.size()]


## The `script` profile schema (the shape of GameSpice Profile's field()), read from the exports so it cannot drift; GameSpice Profile's profile_check finds it here.
static func schema() -> Array:
	var out: Array = []
	var cfg := DotScriptConfig.new()
	for prop: Dictionary in cfg.get_property_list():
		if not (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (int(prop["usage"]) & PROPERTY_USAGE_EDITOR):
			continue
		var type := ""
		match int(prop["type"]):
			TYPE_BOOL: type = "bool"
			TYPE_INT: type = "int"
			TYPE_FLOAT: type = "float"
			TYPE_STRING: type = "string"
			TYPE_PACKED_STRING_ARRAY: type = "list"
		if type == "":
			continue
		var key := str(prop["name"])
		var def: Variant = cfg.get(key)
		var f := {"name": key, "type": type, "default": Array(def) if def is PackedStringArray else def}
		if int(prop["hint"]) == PROPERTY_HINT_RANGE and type != "string":
			var parts := str(prop["hint_string"]).split(",")
			f["min"] = parts[0].to_int() if type == "int" else parts[0].to_float()
			f["max"] = parts[1].to_int() if type == "int" else parts[1].to_float()
		out.append(f)
	return out


## Kind to schema for GameSpice Profile's profile_check (a game's `cfg/game/<game>/script/game.yml`).
static func profile_schemas() -> Dictionary:
	return {"script": {"schema": schema(), "children": {}}}


## Defaults, then `cfg/addon/dot_script/*.yml` and the game tier, then environment and command line.
static func from_files() -> DotResult:
	var cfg := DotScriptConfig.new()
	var files := DotAddonConfig.load_dir(ADDON)
	if not files.ok:
		return files
	cfg.apply_dictionary(files.value as Dictionary, "yml")
	return cfg.load_layered()


