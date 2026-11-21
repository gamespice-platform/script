extends Node
## Walk-through: load a document, fire events, tick, save and restore. Run it as a scene script.


func _ready() -> void:
	var run := GSScriptRunner.new()
	run.message.connect(func(text: String, rule: String) -> void: print("[%s] %s" % [rule, text]))
	var r := run.load_text('{"version":1,"rules":[{"id":"pick","on":"pickup","do":[{"action":"add_var","name":"keys","amount":1}]},{"id":"open","on":"use","when":[{"var":"keys","op":">=","value":1}],"do":[{"action":"message","text":"vault open"}],"cooldown":5}]}')
	if not r.ok:
		push_error(r.error.message)
		return
	run.fire("pickup")
	run.fire("use")
	run.tick()
	var saved := run.snapshot()
	run.reset(true)
	run.restore(saved)
	print("keys after restore: ", run.vars.get("keys", 0))
