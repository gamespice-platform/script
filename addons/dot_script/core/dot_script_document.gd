class_name GSScriptDocument
extends RefCounted

## The script document: a Dictionary (JSON on disk or on the wire) of rules. Validation is the only
## door; a runner never loads a document that has not passed it.
##
##   {"version": 1, "rules": [
##     {"id": "open", "on": "button.pressed", "when": [{"var": "keys", "op": ">=", "value": 2}],
##      "do": [{"action": "message", "text": "Door open"}], "once": true, "cooldown": 5.0}]}
##
## `cooldown` is seconds a rule stays quiet after it runs; a runner counts it down in [method GSScriptRunner.advance].

const VERSION := 1
const OPS := ["==", "!=", "<", "<=", ">", ">="]
const RULE_KEYS := ["id", "on", "when", "do", "once", "enabled", "cooldown"]
const ID_PATTERN := "^[A-Za-z0-9_.-]{1,64}$"


## Success carries the document; failure lists every problem, one per line.
static func validate(doc: Variant, actions: GSScriptActions, cfg: GSScriptConfig) -> GSResult:
	var errs := PackedStringArray()
	if not doc is Dictionary:
		return GSResult.fail(GSError.CODE_PARSE, "a script document must be an object")
	var d: Dictionary = doc
	if int(d.get("version", 0)) != VERSION:
		errs.append("version must be %d" % VERSION)
	var rules: Variant = d.get("rules")
	if not rules is Array:
		errs.append("rules must be a list")
		return GSResult.fail(GSError.CODE_INVALID, "\n".join(errs))
	var list: Array = rules
	if cfg != null and cfg.max_rules > 0 and list.size() > cfg.max_rules:
		errs.append("%d rules is over max_rules %d" % [list.size(), cfg.max_rules])
	var ids := {}
	var re := RegEx.new()
	re.compile(ID_PATTERN)
	for r: Variant in list:
		if r is Dictionary and re.search(str((r as Dictionary).get("id", ""))) != null:
			ids[str((r as Dictionary)["id"])] = true
	var seen := {}
	for i in list.size():
		errs.append_array(_rule(list[i], i, actions, cfg, ids, seen, re))
	if not errs.is_empty():
		return GSResult.fail(GSError.CODE_INVALID, "\n".join(errs))
	return GSResult.success(d)


static func _rule(r: Variant, i: int, actions: GSScriptActions, cfg: GSScriptConfig, ids: Dictionary, seen: Dictionary, re: RegEx) -> PackedStringArray:
	var errs := PackedStringArray()
	var at := "rule %d" % i
	if not r is Dictionary:
		errs.append("%s must be an object" % at)
		return errs
	var d: Dictionary = r
	var id := str(d.get("id", ""))
	if re.search(id) == null:
		errs.append("%s needs an id of letters, digits, _ . - (1 to 64)" % at)
	elif seen.has(id):
		errs.append("%s: duplicate id '%s'" % [at, id])
	else:
		seen[id] = true
		at = "rule '%s'" % id
	for k: Variant in d:
		if not RULE_KEYS.has(str(k)):
			errs.append("%s has unknown key '%s'" % [at, k])
	if not (d.get("on") is String) or str(d["on"]).is_empty():
		errs.append("%s needs a non-empty 'on' event name" % at)
	for key in ["once", "enabled"]:
		if d.has(key) and not d[key] is bool:
			errs.append("%s: '%s' must be true or false" % [at, key])
	if d.has("cooldown") and not ((d["cooldown"] is int or d["cooldown"] is float) and float(d["cooldown"]) >= 0.0):
		errs.append("%s: 'cooldown' must be a number of seconds, 0 or more" % at)
	var when: Variant = d.get("when", [])
	if not when is Array:
		errs.append("%s: 'when' must be a list" % at)
	else:
		for c: Variant in when:
			errs.append_array(_condition(c, at))
	var todo: Variant = d.get("do")
	if not todo is Array or (todo as Array).is_empty():
		errs.append("%s needs a non-empty 'do' list" % at)
		return errs
	var acts: Array = todo
	if cfg != null and cfg.max_actions_per_rule > 0 and acts.size() > cfg.max_actions_per_rule:
		errs.append("%s has %d actions, over max_actions_per_rule %d" % [at, acts.size(), cfg.max_actions_per_rule])
	var cost := 0
	for a: Variant in acts:
		var ok := actions.check(a, cfg)
		if not ok.ok:
			errs.append("%s: %s" % [at, ok.error.message])
			continue
		var aid := str((a as Dictionary)["action"])
		cost += actions.cost_of(aid)
		if (aid == "enable_rule" or aid == "disable_rule") and not ids.has(str((a as Dictionary)["rule"])):
			errs.append("%s: %s names unknown rule '%s'" % [at, aid, (a as Dictionary)["rule"]])
	if cfg != null and cfg.tick_budget > 0 and cost > cfg.tick_budget:
		errs.append("%s costs %d, more than tick_budget %d, so it could never run" % [at, cost, cfg.tick_budget])
	return errs


static func _condition(c: Variant, at: String) -> PackedStringArray:
	var errs := PackedStringArray()
	if not c is Dictionary:
		errs.append("%s: a condition must be an object" % at)
		return errs
	var d: Dictionary = c
	for k: Variant in d:
		if not ["var", "op", "value"].has(str(k)):
			errs.append("%s: a condition has unknown key '%s'" % [at, k])
	if not d.get("var") is String or str(d["var"]).is_empty():
		errs.append("%s: a condition needs a 'var' name" % at)
	if not OPS.has(str(d.get("op", ""))):
		errs.append("%s: condition op '%s' is not one of %s" % [at, d.get("op", ""), ", ".join(OPS)])
	var v: Variant = d.get("value")
	if not (v is String or v is bool or v is int or v is float):
		errs.append("%s: a condition value must be a string, number or bool" % at)
	return errs
