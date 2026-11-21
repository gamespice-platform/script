extends Node

## gs-script's headless suite (res://examples/script_selftest.tscn).
## Counts sections run to their last line as well as checks, because a script error
## aborts a section and not the run.

const EXPECTED_SECTIONS := 6
const EXPECTED_CHECKS := 68

var _passed := 0
var _failed := 0
var _sections := 0


func _ready() -> void:
	print("gs-script")
	_config()
	_whitelist()
	_document()
	_runner()
	_sandbox()
	_features()
	print("")
	_check(_sections == EXPECTED_SECTIONS, "every section ran to its last line (%d of %d)" % [_sections, EXPECTED_SECTIONS])
	_check(_passed + _failed == EXPECTED_CHECKS, "and the suite ran all %d of its checks (%d)" % [EXPECTED_CHECKS, _passed + _failed])
	print("%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _doc(rules: Array) -> Dictionary:
	return {"version": 1, "rules": rules}


func _config() -> void:
	var c := GSScriptConfig.new()
	_check(c.validate().ok, "defaults validate")
	_check(c.max_rules == 256 and c.tick_budget == 200, "shipped limits")
	c.tick_budget = -1
	_check(not c.validate().ok, "a negative limit is refused, 0 means unlimited")
	var names: Array = GSScriptConfig.profile_schemas()["script"]["schema"].map(func(f: Dictionary) -> Variant: return f["name"])
	_check(names.has("tick_budget") and names.has("allowed_actions") and names.size() == c.config_keys().size(), "profile schema lists every key", str(names.size()))
	var applied := c.apply_dictionary({"max_rules": 5, "allowed_actions": ["message"]})
	_check(applied.size() == 2 and c.max_rules == 5 and c.allowed_actions.size() == 1, "a dictionary layer sets ints and lists", str(applied))
	_check(c.env_prefix() == "GS_SCRIPT_" and c.cli_prefix() == "--script-", "env and command-line prefixes")
	var r := GSScriptConfig.from_files()
	_check(r.ok and (r.value as GSScriptConfig).describe().begins_with("script"), "from_files returns a config")
	_sections += 1


func _whitelist() -> void:
	var a := GSScriptActions.new()
	var c := GSScriptConfig.new()
	_check(a.check({"action": "message", "text": "hi"}, c).ok, "a whitelisted action with typed arguments passes")
	_check(a.check({"action": "eval", "text": "1+1"}, c).error.code == GSError.CODE_FORBIDDEN, "an id outside the table is forbidden")
	_check(not a.check({"action": "message", "text": 5}, c).ok, "a wrong argument type is refused")
	_check(not a.check({"action": "message", "text": "x", "extra": 1}, c).ok, "an extra argument is refused")
	_check(not a.check({"action": "set_var", "name": "a"}, c).ok, "a missing argument is refused")
	_check(not a.check({"action": "set_var", "name": "a", "value": NAN}, c).ok, "NaN is not a number here")
	_check(not a.check("message", c).ok, "an action must be an object")
	c.max_text_length = 5
	_check(not a.check({"action": "message", "text": "toolong"}, c).ok, "text over max_text_length is refused")
	c.max_text_length = 0
	_check(a.check({"action": "message", "text": "x".repeat(5000)}, c).ok, "0 is unlimited text")
	c.allowed_actions = PackedStringArray(["message"])
	_check(not a.check({"action": "set_var", "name": "a", "value": 1}, c).ok, "allowed_actions narrows the whitelist")
	_check(not a.register("Bad Id", {}, 1, func(_x: Dictionary, _y: Dictionary) -> void: pass).ok, "a registered id must be a plain lowercase id")
	_check(not a.register("message", {}, 1, func(_x: Dictionary, _y: Dictionary) -> void: pass).ok, "a built-in id cannot be replaced")
	_check(a.register("open_door", {"door": "string"}, 3, func(_x: Dictionary, _y: Dictionary) -> void: pass).ok and a.cost_of("open_door") == 3, "a game registers its own action with a cost")
	_sections += 1


func _document() -> void:
	var a := GSScriptActions.new()
	var c := GSScriptConfig.new()
	var ok := _doc([{"id": "a", "on": "go", "do": [{"action": "message", "text": "x"}]}])
	_check(GSScriptDocument.validate(ok, a, c).ok, "a minimal document passes")
	_check(not GSScriptDocument.validate([], a, c).ok, "a list is not a document")
	_check(not GSScriptDocument.validate({"version": 2, "rules": []}, a, c).ok, "another version is refused")
	var bad := _doc([{"id": "a", "on": "go", "do": []}, {"id": "a", "on": "", "do": [{"action": "nope"}], "x": 1}])
	var r := GSScriptDocument.validate(bad, a, c)
	_check(not r.ok and r.error.message.split("\n").size() >= 4, "every problem is listed, not just the first", r.error.message if not r.ok else "")
	_check(not GSScriptDocument.validate(_doc([{"id": "a", "on": "e", "when": [{"var": "v", "op": "=~", "value": 1}], "do": [{"action": "message", "text": "x"}]}]), a, c).ok, "an unknown comparison operator is refused")
	_check(not GSScriptDocument.validate(_doc([{"id": "a", "on": "e", "do": [{"action": "enable_rule", "rule": "ghost"}]}]), a, c).ok, "enable_rule must name a rule that exists")
	c.max_rules = 1
	var two := _doc([{"id": "a", "on": "e", "do": [{"action": "message", "text": "x"}]}, {"id": "b", "on": "e", "do": [{"action": "message", "text": "x"}]}])
	_check(not GSScriptDocument.validate(two, a, c).ok, "max_rules is enforced")
	c.max_rules = 0
	_check(GSScriptDocument.validate(two, a, c).ok, "max_rules 0 is unlimited")
	c.tick_budget = 1
	_check(not GSScriptDocument.validate(_doc([{"id": "a", "on": "e", "do": [{"action": "emit", "event": "e"}]}]), a, c).ok, "a rule dearer than the whole budget is refused at load")
	c.tick_budget = 200
	c.max_actions_per_rule = 1
	_check(not GSScriptDocument.validate(_doc([{"id": "a", "on": "e", "do": [{"action": "message", "text": "1"}, {"action": "message", "text": "2"}]}]), a, c).ok, "max_actions_per_rule is enforced")
	var parsed: Variant = JSON.parse_string(JSON.stringify(ok))
	_check(GSScriptDocument.validate(parsed, a, GSScriptConfig.new()).ok, "a JSON round trip still validates")
	_sections += 1


func _runner() -> void:
	var run := GSScriptRunner.new()
	var said: Array = []
	run.message.connect(func(t: String, _id: String) -> void: said.append(t))
	var r := run.load_document(_doc([
		{"id": "pick", "on": "pickup", "do": [{"action": "add_var", "name": "keys", "amount": 1}]},
		{"id": "open", "on": "use", "when": [{"var": "keys", "op": ">=", "value": 2}], "do": [{"action": "message", "text": "open"}], "once": true},
		{"id": "locked", "on": "use", "when": [{"var": "keys", "op": "<", "value": 2}], "do": [{"action": "message", "text": "locked"}]},
	]))
	_check(r.ok and r.value == 3, "a document loads")
	run.fire("use")
	run.tick()
	_check(said == ["locked"], "a condition on a variable picks the rule", str(said))
	run.fire("pickup")
	run.fire("pickup")
	run.fire("use")
	run.tick()
	_check(run.vars["keys"] == 2.0 and said == ["locked", "open"], "variables carry between events", str(said))
	run.fire("use")
	run.tick()
	_check(said.size() == 2 and not run.rule_enabled("open"), "a once rule runs once")
	var chain := GSScriptRunner.new()
	var order: Array = []
	chain.message.connect(func(t: String, _id: String) -> void: order.append(t))
	chain.load_document(_doc([
		{"id": "a", "on": "start", "do": [{"action": "message", "text": "a"}, {"action": "emit", "event": "next"}]},
		{"id": "b", "on": "next", "do": [{"action": "message", "text": "b"}]},
	]))
	chain.fire("start")
	chain.tick()
	_check(order == ["a"] and chain.queued() == 1, "an emitted event waits for the next tick")
	chain.tick()
	_check(order == ["a", "b"] and chain.queued() == 0, "and runs on it")
	var loop := GSScriptRunner.new()
	loop.load_document(_doc([{"id": "l", "on": "x", "do": [{"action": "emit", "event": "x"}]}]))
	loop.fire("x")
	for i in 50:
		loop.tick()
	_check(loop.queued() == 1, "a rule that emits its own event costs a tick per round and never hangs")
	var b := GSScriptRunner.new()
	b.config.tick_budget = 3
	var n: Array = [0]
	b.message.connect(func(_t: String, _id: String) -> void: n[0] += 1)
	b.load_document(_doc([{"id": "m", "on": "e", "do": [{"action": "message", "text": "x"}]}]))
	for i in 7:
		b.fire("e")
	var s1 := b.tick()
	_check(s1 == 3 and b.last_spent == 3 and b.last_waiting == 4 and n[0] == 3, "the tick budget caps what runs and the rest waits", "%d %d %d" % [s1, b.last_spent, b.last_waiting])
	b.tick()
	b.tick()
	_check(n[0] == 7 and b.queued() == 0, "waiting events run in order on later ticks", str(n))
	b.config.tick_budget = 0
	for i in 100:
		b.fire("e")
	b.tick()
	_check(n[0] == 107, "budget 0 is unlimited")
	b.config.max_queued_events = 2
	var refused: Array = []
	b.refused.connect(func(e: String, why: String) -> void: refused.append(why))
	_check(b.fire("e") and b.fire("e") and not b.fire("e") and b.dropped == 1 and refused.size() == 1, "a full queue refuses loudly and counts", str(refused))
	b.config.enabled = false
	_check(not b.fire("e"), "a disabled runner refuses events")
	var custom := GSScriptRunner.new()
	var got: Array = []
	custom.actions.register("open_door", {"door": "string"}, 2, func(args: Dictionary, ctx: Dictionary) -> void: got.append([args["door"], ctx.get("who")]))
	custom.load_document(_doc([{"id": "d", "on": "e", "do": [{"action": "open_door", "door": "front"}]}]))
	custom.fire("e", {"who": 7})
	custom.tick()
	_check(got == [["front", 7]], "a game action runs through its handler with the event context", str(got))
	_check(not custom.load_document({"version": 1, "rules": [{"id": "x", "on": "e", "do": [{"action": "nope"}]}]}).ok, "a refused document leaves the loaded one in place and rules still run")
	custom.fire("e", {"who": 8})
	custom.tick()
	_check(got.size() == 2, "the previous document still runs")
	_sections += 1


func _sandbox() -> void:
	var bad := 0
	var files := 0
	for dir in ["res://addons/gs_script/core", "res://addons/gs_script/runtime"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				files += 1
				var src := FileAccess.get_file_as_string(dir + "/" + f)
				for banned in ["Expre" + "ssion", "eval" + "(", "execute" + "(", "OS." + "shell", "GDScript" + ".new", "source_code"]:
					if src.contains(banned):
						bad += 1
						print("  banned text ", banned, " in ", f)
	_check(files >= 4 and bad == 0, "no source in the addon builds or runs code from a string", "%d files, %d hits" % [files, bad])
	var run := GSScriptRunner.new()
	var r := run.load_document({"version": 1, "rules": [{"id": "x", "on": "e", "when": [{"var": "a", "op": "==", "value": 1}], "do": [{"action": "message", "text": "OS.shell_open('x')"}]}]})
	var said: Array = []
	run.message.connect(func(t: String, _id: String) -> void: said.append(t))
	run.vars["a"] = 1
	run.fire("e")
	run.tick()
	_check(r.ok and said == ["OS.shell_open('x')"], "text that looks like code is only ever text")
	_sections += 1


func _features() -> void:
	var run := GSScriptRunner.new()
	var log: Array = []
	run.message.connect(func(t: String, _id: String) -> void: log.append(t))
	var ran: Array = []
	run.rule_ran.connect(func(id: String, ev: String) -> void: ran.append(id + "@" + ev))
	var r := run.load_document(_doc([
		{"id": "hit", "on": "hit", "when": [{"var": "ctx.team", "op": "==", "value": "red"}], "do": [{"action": "message", "text": "red hit"}], "cooldown": 2.0},
		{"id": "flip", "on": "flip", "do": [{"action": "toggle_var", "name": "lamp"}]},
		{"id": "off", "on": "x", "enabled": false, "do": [{"action": "message", "text": "off"}]},
	]))
	_check(r.ok, "a document with cooldown, ctx and a disabled rule loads")
	run.fire("hit", {"team": "blue"})
	run.tick()
	_check(log.is_empty(), "a ctx. condition reads the event context")
	run.fire("hit", {"team": "red"})
	run.tick()
	run.fire("hit", {"team": "red"})
	run.tick()
	_check(log == ["red hit"] and run.cooldown_left("hit") == 2.0 and ran == ["hit@hit"], "a cooldown keeps a rule quiet and rule_ran reports it", str(log))
	run.advance(1.5)
	run.advance(0.6)
	run.fire("hit", {"team": "red"})
	run.tick()
	_check(log.size() == 2 and run.rules_run == 2, "after the cooldown it runs again", str(log))
	run.fire("flip")
	run.tick()
	_check(run.vars["lamp"] == 1.0, "toggle_var turns a variable on")
	run.fire("flip")
	run.tick()
	_check(run.vars["lamp"] == 0.0, "and off again")
	_check(not run.rule_enabled("off") and run.set_rule_enabled("off", true) and run.rule_enabled("off") and not run.set_rule_enabled("ghost", true), "rules switch on and off by id, unknown ids say so")
	run.fire("hit", {"team": "red"})
	run.tick()
	var snap := run.snapshot()
	var other := GSScriptRunner.new()
	other.load_document(_doc([
		{"id": "hit", "on": "hit", "do": [{"action": "message", "text": "x"}], "cooldown": 2.0},
		{"id": "flip", "on": "flip", "do": [{"action": "message", "text": "x"}]},
		{"id": "off", "on": "x", "enabled": false, "do": [{"action": "message", "text": "x"}]},
	]))
	snap["enabled"]["gone"] = true
	var rr := other.restore(JSON.parse_string(JSON.stringify(snap)))
	_check(rr.ok and rr.value == 1 and other.vars["lamp"] == 0.0 and other.rule_enabled("off") and other.cooldown_left("hit") == 2.0, "a snapshot survives JSON and restores state, counting unknown ids", str(rr.value))
	_check(not other.restore({"vars": 1}).ok, "a malformed snapshot is refused")
	other.reset()
	_check(not other.rule_enabled("off") and other.cooldown_left("hit") == 0.0 and other.vars.has("lamp"), "reset returns flags to the document and keeps variables")
	other.reset(true)
	_check(other.vars.is_empty(), "reset(true) clears variables too")
	var cap := GSScriptRunner.new()
	cap.config.max_vars = 1
	var why: Array = []
	cap.refused.connect(func(_e: String, w: String) -> void: why.append(w))
	cap.load_document(_doc([{"id": "v", "on": "e", "do": [{"action": "set_var", "name": "a", "value": 1}, {"action": "set_var", "name": "b", "value": 1}, {"action": "add_var", "name": "a", "amount": 1}]}]))
	cap.fire("e")
	cap.tick()
	_check(cap.vars.size() == 1 and cap.vars["a"] == 2.0 and why.size() == 1, "max_vars refuses a new variable loudly and still lets existing ones change", str(why))
	var c := GSScriptConfig.new()
	var acts := GSScriptActions.new()
	var good := GSScriptCodec.parse('{"version": 1, "rules": [{"id": "a", "on": "e", "do": [{"action": "message", "text": "hi"}]}]}', acts, c)
	_check(good.ok and GSScriptCodec.parse(GSScriptCodec.stringify(good.value), acts, c).ok, "the codec parses JSON and round-trips")
	_check(GSScriptCodec.parse("{nope", acts, c).error.code == GSError.CODE_PARSE, "bad JSON is a parse error")
	c.max_document_bytes = 10
	_check(not GSScriptCodec.parse('{"version": 1, "rules": []}', acts, c).ok, "max_document_bytes refuses before parsing")
	c.max_document_bytes = 0
	_check(GSScriptCodec.parse('{"version": 1, "rules": []}', acts, c).ok, "max_document_bytes 0 is unlimited")
	_check(run.load_text("not json").error.code == GSError.CODE_PARSE and run.load_text('{"version": 1, "rules": []}').ok, "load_text goes through the codec")
	_check(acts.ids().has("toggle_var") and acts.ids()[0] <= acts.ids()[1] and acts.describe()[0].contains("cost"), "actions list their ids and signatures")
	_check(GSScriptConditions.compare("a", "==", "a") and not GSScriptConditions.compare("a", "<", "b") and not GSScriptConditions.compare(1, "==", "1") and GSScriptConditions.compare(2, ">=", 2.0), "compare: strings only equal, numbers ordered, no coercion")
	_sections += 1


func _check(ok: bool, what: String, extra: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    ", what)
	else:
		_failed += 1
		print("  FAIL  ", what, "  ", extra)
