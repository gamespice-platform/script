class_name GSScriptConditions
extends RefCounted

## Evaluates a rule's `when` list. Every condition is {var, op, value}; all must hold. A name starting with
## `ctx.` reads the event's context instead of the runner's variables, so a rule can ask who fired it.
## Static and allocation-free: a tick calls it once per candidate rule.

const CTX_PREFIX := "ctx."


## True when every condition holds. An empty list holds.
static func passes(conditions: Array, vars: Dictionary, ctx: Dictionary) -> bool:
	for c: Dictionary in conditions:
		if not holds(c, vars, ctx):
			return false
	return true


## One condition. A missing variable reads as 0, a missing context key likewise.
static func holds(c: Dictionary, vars: Dictionary, ctx: Dictionary) -> bool:
	var name := str(c["var"])
	var have: Variant
	if name.begins_with(CTX_PREFIX):
		have = ctx.get(name.substr(CTX_PREFIX.length()), 0)
	else:
		have = vars.get(name, 0)
	return compare(have, str(c["op"]), c["value"])


## `have op want`. Numbers compare as numbers; anything else supports only == and !=, and a type mismatch is never equal.
static func compare(have: Variant, op: String, want: Variant) -> bool:
	var numeric := (have is int or have is float) and (want is int or want is float)
	if numeric:
		var a := float(have)
		var b := float(want)
		match op:
			"==": return a == b
			"!=": return a != b
			"<": return a < b
			"<=": return a <= b
			">": return a > b
			">=": return a >= b
		return false
	var same: bool = typeof(have) == typeof(want) and have == want
	match op:
		"==": return same
		"!=": return not same
	return false
