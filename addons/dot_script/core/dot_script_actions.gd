class_name DotScriptActions
extends RefCounted

## The whitelist. A document names an action by id and gives it typed arguments; nothing else runs.
## There is no way to put code or an expression in a document: an argument is a string, a number or a
## bool, an id outside this table is refused when the document is loaded, and a game adds its own ids
## with [method register] (a Callable it owns), never by text.

const ID_PATTERN := "^[a-z][a-z0-9_]*$"
const T_STRING := "string"
const T_NUMBER := "number"
const T_BOOL := "bool"

## id to {args: {name: type}, cost: int, handler: Callable (empty for a built-in the runner applies itself)}.
var specs: Dictionary = {}


func _init() -> void:
	specs = {
		"message": {"args": {"text": T_STRING}, "cost": 1},
		"set_var": {"args": {"name": T_STRING, "value": T_NUMBER}, "cost": 1},
		"add_var": {"args": {"name": T_STRING, "amount": T_NUMBER}, "cost": 1},
		"toggle_var": {"args": {"name": T_STRING}, "cost": 1},
		"enable_rule": {"args": {"rule": T_STRING}, "cost": 1},
		"disable_rule": {"args": {"rule": T_STRING}, "cost": 1},
		"emit": {"args": {"event": T_STRING}, "cost": 2},
	}


## Adds a game action. The handler is called as handler(args: Dictionary, ctx: Dictionary).
func register(id: String, args: Dictionary, cost: int, handler: Callable) -> DotResult:
	var re := RegEx.new()
	re.compile(ID_PATTERN)
	if re.search(id) == null:
		return DotResult.fail(DotError.CODE_INVALID, "action id '%s' must match %s" % [id, ID_PATTERN])
	if specs.has(id):
		return DotResult.fail(DotError.CODE_CONFLICT, "action '%s' is already registered" % id)
	if cost < 0 or not handler.is_valid():
		return DotResult.fail(DotError.CODE_INVALID, "action '%s' needs a cost of 0 or more and a valid handler" % id)
	for a: String in args:
		if not [T_STRING, T_NUMBER, T_BOOL].has(str(args[a])):
			return DotResult.fail(DotError.CODE_INVALID, "action '%s' argument '%s' has unknown type '%s'" % [id, a, args[a]])
	specs[id] = {"args": args.duplicate(), "cost": cost, "handler": handler}
	return DotResult.success(id)


## Every action id, sorted; for an editor's palette or a document's reference.
func ids() -> PackedStringArray:
	var out := PackedStringArray(specs.keys())
	out.sort()
	return out


## One line per action: `id(arg: type, ...) cost N`, sorted. For docs and error messages.
func describe() -> PackedStringArray:
	var out := PackedStringArray()
	for id in ids():
		var args: Dictionary = (specs[id] as Dictionary)["args"]
		var parts := PackedStringArray()
		for a: String in args:
			parts.append("%s: %s" % [a, args[a]])
		out.append("%s(%s) cost %d" % [id, ", ".join(parts), cost_of(id)])
	return out


func has(id: String) -> bool:
	return specs.has(id)


func cost_of(id: String) -> int:
	return int((specs.get(id, {}) as Dictionary).get("cost", 0))


## Checks one action dictionary ({action: id, ...arguments}) against the table and the config.
func check(action: Variant, cfg: DotScriptConfig) -> DotResult:
	if not action is Dictionary:
		return DotResult.fail(DotError.CODE_INVALID, "an action must be an object")
	var d: Dictionary = action
	var id := str(d.get("action", ""))
	if not specs.has(id):
		return DotResult.fail(DotError.CODE_FORBIDDEN, "action '%s' is not whitelisted" % id)
	if cfg != null and not cfg.allowed_actions.is_empty() and not cfg.allowed_actions.has(id):
		return DotResult.fail(DotError.CODE_FORBIDDEN, "action '%s' is not allowed on this server" % id)
	var spec: Dictionary = specs[id]
	var args: Dictionary = spec["args"]
	for k: Variant in d:
		if str(k) != "action" and not args.has(str(k)):
			return DotResult.fail(DotError.CODE_INVALID, "action '%s' has no argument '%s'" % [id, k])
	for a: String in args:
		if not d.has(a):
			return DotResult.fail(DotError.CODE_INVALID, "action '%s' is missing argument '%s'" % [id, a])
		var v: Variant = d[a]
		var ok := false
		match str(args[a]):
			T_STRING: ok = v is String
			T_NUMBER: ok = (v is float or v is int) and not (v is float and (is_nan(v) or is_inf(v)))
			T_BOOL: ok = v is bool
		if not ok:
			return DotResult.fail(DotError.CODE_INVALID, "action '%s' argument '%s' must be a %s" % [id, a, args[a]])
		if v is String and cfg != null and cfg.max_text_length > 0 and (v as String).length() > cfg.max_text_length:
			return DotResult.fail(DotError.CODE_INVALID, "action '%s' argument '%s' is longer than %d characters" % [id, a, cfg.max_text_length])
	return DotResult.success(d)
