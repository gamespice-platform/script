class_name GSScriptRunner
extends RefCounted

## Runs a validated document. Events go in with [method fire], [method tick] runs what the budget allows,
## and whatever does not fit waits for the next tick, in order. Actions an event emits are queued for the
## next tick, so a rule that emits its own event costs a tick per round, not a hang.
##
## Hot path: rules are indexed by event at load, a rule's cost is summed once, and enabled flags and
## cooldowns are flat arrays, so a tick allocates nothing beyond the queue entry an event already made.

signal message(text: String, rule_id: String)
## An event or action was turned away; `reason` says why.
signal refused(event: String, reason: String)
## A rule ran; for logging or a debug overlay.
signal rule_ran(rule_id: String, event: String)

var config: GSScriptConfig = GSScriptConfig.new()
var actions: GSScriptActions = GSScriptActions.new()
## Variables the document reads and writes; a game sets them too.
var vars: Dictionary = {}
## Events refused because the queue was full, since the last [method load_document].
var dropped: int = 0
## Cost spent by the last [method tick].
var last_spent: int = 0
## Events still waiting after the last [method tick].
var last_waiting: int = 0
## Rules run, since the last [method load_document].
var rules_run: int = 0

var _rules: Array = []
var _index: Dictionary = {}
var _by_event: Dictionary = {}
var _cost: PackedInt32Array = PackedInt32Array()
var _enabled: PackedByteArray = PackedByteArray()
var _cool: PackedFloat32Array = PackedFloat32Array()
var _cooling: int = 0
var _queue: Array = []


## Validates and loads a document (a Dictionary, or see [method load_text]). Success carries the rule count.
func load_document(doc: Variant) -> GSResult:
	var ok := GSScriptDocument.validate(doc, actions, config)
	if not ok.ok:
		return ok
	_rules = (doc as Dictionary)["rules"] as Array
	var n := _rules.size()
	_index.clear()
	_by_event.clear()
	_cost.resize(n)
	_enabled.resize(n)
	_cool.resize(n)
	for i in n:
		var r: Dictionary = _rules[i]
		_index[str(r["id"])] = i
		var c := 0
		for a: Dictionary in r["do"]:
			c += actions.cost_of(str(a["action"]))
		_cost[i] = c
		var ev := str(r["on"])
		var list: PackedInt32Array = _by_event.get(ev, PackedInt32Array())
		list.append(i)
		_by_event[ev] = list
	_queue.clear()
	dropped = 0
	rules_run = 0
	_reset_flags()
	return GSResult.success(n)


## Parses JSON text with [GSScriptCodec] and loads it.
func load_text(text: String) -> GSResult:
	var parsed := GSScriptCodec.parse(text, actions, config)
	if not parsed.ok:
		return parsed
	return load_document(parsed.value)


func rule_count() -> int:
	return _rules.size()


func rule_enabled(id: String) -> bool:
	return _index.has(id) and _enabled[int(_index[id])] != 0


## Turns a rule on or off. False when there is no such rule.
func set_rule_enabled(id: String, on: bool) -> bool:
	if not _index.has(id):
		return false
	_enabled[int(_index[id])] = 1 if on else 0
	return true


## Seconds left before a rule may run again; 0 when ready or unknown.
func cooldown_left(id: String) -> float:
	return _cool[int(_index[id])] if _index.has(id) else 0.0


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


## Counts cooldowns down. Call from the same loop as [method tick]; it is a no-op while nothing cools.
func advance(dt: float) -> void:
	if _cooling == 0:
		return
	for i in _cool.size():
		var left := _cool[i]
		if left > 0.0:
			left -= dt
			if left <= 0.0:
				left = 0.0
				_cooling -= 1
			_cool[i] = left


## Runs queued events until the budget is spent and returns how many rules ran. Cost spent and events
## left are in [member last_spent] and [member last_waiting].
func tick() -> int:
	var spent := 0
	var ran := 0
	var budget := config.tick_budget
	var round_len := _queue.size()
	while round_len > 0 and not _queue.is_empty():
		var entry: Dictionary = _queue[0]
		var event := str(entry["event"])
		var ctx: Dictionary = entry["ctx"]
		var blocked := false
		if _by_event.has(event):
			var list: PackedInt32Array = _by_event[event]
			while int(entry["next"]) < list.size():
				var i := list[int(entry["next"])]
				var rule: Dictionary = _rules[i]
				if _enabled[i] == 0 or _cool[i] > 0.0 or not GSScriptConditions.passes(rule.get("when", []), vars, ctx):
					entry["next"] = int(entry["next"]) + 1
					continue
				var cost := _cost[i]
				if budget > 0 and spent + cost > budget:
					blocked = true
					break
				spent += cost
				ran += 1
				_run(i, rule, event, ctx)
				entry["next"] = int(entry["next"]) + 1
		if blocked:
			break
		_queue.pop_front()
		round_len -= 1
	last_spent = spent
	last_waiting = _queue.size()
	rules_run += ran
	return ran


## Back to the document as loaded: rules on or off as written, cooldowns cleared, queue emptied.
## Variables are kept unless `clear_vars`.
func reset(clear_vars: bool = false) -> void:
	_queue.clear()
	_reset_flags()
	if clear_vars:
		vars.clear()


## What a save needs: variables, which rules are on, cooldowns still running.
func snapshot() -> Dictionary:
	var on := {}
	var cool := {}
	for id: String in _index:
		var i: int = _index[id]
		on[id] = _enabled[i] != 0
		if _cool[i] > 0.0:
			cool[id] = _cool[i]
	return {"vars": vars.duplicate(true), "enabled": on, "cooldowns": cool}


## Puts a [method snapshot] back. Ids the loaded document does not have are ignored and counted in the result.
func restore(snap: Dictionary) -> GSResult:
	if not snap.get("vars", {}) is Dictionary or not snap.get("enabled", {}) is Dictionary or not snap.get("cooldowns", {}) is Dictionary:
		return GSResult.fail(GSError.CODE_INVALID, "a snapshot needs vars, enabled and cooldowns objects")
	vars = (snap.get("vars", {}) as Dictionary).duplicate(true)
	var unknown := 0
	var on: Dictionary = snap.get("enabled", {})
	for id: Variant in on:
		if _index.has(str(id)):
			_enabled[int(_index[str(id)])] = 1 if bool(on[id]) else 0
		else:
			unknown += 1
	_cool.fill(0.0)
	_cooling = 0
	var cool: Dictionary = snap.get("cooldowns", {})
	for id: Variant in cool:
		if _index.has(str(id)) and float(cool[id]) > 0.0:
			_cool[int(_index[str(id)])] = float(cool[id])
			_cooling += 1
		elif not _index.has(str(id)):
			unknown += 1
	return GSResult.success(unknown)


func _reset_flags() -> void:
	_cool.fill(0.0)
	_cooling = 0
	for i in _rules.size():
		_enabled[i] = 1 if bool((_rules[i] as Dictionary).get("enabled", true)) else 0


func _var_ok(name: String, event: String) -> bool:
	if config.max_vars > 0 and not vars.has(name) and vars.size() >= config.max_vars:
		refused.emit(event, "variable '%s' would pass max_vars %d" % [name, config.max_vars])
		return false
	return true


func _run(i: int, rule: Dictionary, event: String, ctx: Dictionary) -> void:
	var id := str(rule["id"])
	if bool(rule.get("once", false)):
		_enabled[i] = 0
	var cd := float(rule.get("cooldown", 0.0))
	if cd > 0.0:
		if _cool[i] <= 0.0:
			_cooling += 1
		_cool[i] = cd
	rule_ran.emit(id, event)
	for a: Dictionary in rule["do"]:
		match str(a["action"]):
			"message": message.emit(str(a["text"]), id)
			"set_var":
				if _var_ok(str(a["name"]), event):
					vars[str(a["name"])] = float(a["value"])
			"add_var":
				if _var_ok(str(a["name"]), event):
					vars[str(a["name"])] = float(vars.get(str(a["name"]), 0.0)) + float(a["amount"])
			"toggle_var":
				if _var_ok(str(a["name"]), event):
					vars[str(a["name"])] = 0.0 if float(vars.get(str(a["name"]), 0.0)) != 0.0 else 1.0
			"enable_rule": _enabled[int(_index[str(a["rule"])])] = 1
			"disable_rule": _enabled[int(_index[str(a["rule"])])] = 0
			"emit": fire(str(a["event"]), ctx)
			_:
				var h: Callable = (actions.specs[str(a["action"])] as Dictionary).get("handler", Callable())
				if h.is_valid():
					h.call(a, ctx)
