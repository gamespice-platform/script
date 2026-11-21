class_name DotScriptRunner
extends RefCounted

## Runs a validated document. Events go in with [method fire], [method tick] runs what the budget allows,
## and whatever does not fit waits for the next tick, in order. Actions an event emits are queued for the
## next tick, so a rule that emits its own event costs a tick per round, not a hang.

signal message(text: String, rule_id: String)
signal refused(event: String, reason: String)

var config: DotScriptConfig = DotScriptConfig.new()
var actions: DotScriptActions = DotScriptActions.new()
## Variables the document reads and writes; a game sets them too.
var vars: Dictionary = {}
## Events refused because the queue was full, since the last [method load_document].
var dropped: int = 0

var _rules: Array = []
var _queue: Array = []
var _enabled: Dictionary = {}
var _spent: Dictionary = {}


func load_document(doc: Variant) -> DotResult:
	var ok := DotScriptDocument.validate(doc, actions, config)
	if not ok.ok:
		return ok
	_rules = (doc as Dictionary)["rules"] as Array
	_queue.clear()
	_enabled.clear()
	_spent.clear()
	dropped = 0
	for r: Dictionary in _rules:
		_enabled[str(r["id"])] = bool(r.get("enabled", true))
	return DotResult.success(_rules.size())


func rule_enabled(id: String) -> bool:
	return bool(_enabled.get(id, false))


func queued() -> int:
	return _queue.size()


## Queues an event. False (and `refused`) when scripting is off or the queue is full.
func fire(event: String, ctx: Dictionary = {}) -> bool:
	if not config.enabled:
		refused.emit(event, "scripting is disabled")
		return false
	if config.max_queued_events > 0 and _queue.size() >= config.max_queued_events:
		dropped += 1
		refused.emit(event, "event queue is full (%d)" % config.max_queued_events)
		return false
	_queue.append({"event": event, "ctx": ctx, "next": 0})
	return true


## Runs queued events until the budget is spent. Returns {ran, spent, waiting}.
func tick() -> Dictionary:
	var spent := 0
	var ran := 0
	var budget := config.tick_budget
	var round_len := _queue.size()
	while round_len > 0 and not _queue.is_empty():
		var entry: Dictionary = _queue[0]
		var event := str(entry["event"])
		var ctx: Dictionary = entry["ctx"]
		var blocked := false
		while int(entry["next"]) < _rules.size():
			var rule: Dictionary = _rules[int(entry["next"])]
			if str(rule["on"]) != event or not bool(_enabled.get(str(rule["id"]), false)) or not _passes(rule):
				entry["next"] = int(entry["next"]) + 1
				continue
			var cost := _cost(rule)
			if budget > 0 and spent + cost > budget:
				blocked = true
				break
			spent += cost
			ran += 1
			_run(rule, ctx)
			entry["next"] = int(entry["next"]) + 1
		if blocked:
			break
		_queue.pop_front()
		round_len -= 1
	return {"ran": ran, "spent": spent, "waiting": _queue.size()}


func _cost(rule: Dictionary) -> int:
	var c := 0
	for a: Dictionary in rule["do"]:
		c += actions.cost_of(str(a["action"]))
	return c


func _passes(rule: Dictionary) -> bool:
	for c: Dictionary in rule.get("when", []):
		var have: Variant = vars.get(str(c["var"]), 0)
		var want: Variant = c["value"]
		var numeric := (have is int or have is float) and (want is int or want is float)
		var op := str(c["op"])
		var ok := false
		if numeric:
			var a := float(have)
			var b := float(want)
			match op:
				"==": ok = a == b
				"!=": ok = a != b
				"<": ok = a < b
				"<=": ok = a <= b
				">": ok = a > b
				">=": ok = a >= b
		else:
			match op:
				"==": ok = typeof(have) == typeof(want) and have == want
				"!=": ok = not (typeof(have) == typeof(want) and have == want)
		if not ok:
			return false
	return true


func _run(rule: Dictionary, ctx: Dictionary) -> void:
	var id := str(rule["id"])
	if bool(rule.get("once", false)):
		_enabled[id] = false
	for a: Dictionary in rule["do"]:
		match str(a["action"]):
			"message": message.emit(str(a["text"]), id)
			"set_var": vars[str(a["name"])] = float(a["value"])
			"add_var": vars[str(a["name"])] = float(vars.get(str(a["name"]), 0.0)) + float(a["amount"])
			"enable_rule": _enabled[str(a["rule"])] = true
			"disable_rule": _enabled[str(a["rule"])] = false
			"emit": fire(str(a["event"]), ctx)
			_:
				var h: Callable = (actions.specs[str(a["action"])] as Dictionary).get("handler", Callable())
				if h.is_valid():
					h.call(a, ctx)
