# Script document format

A document is a Dictionary (or JSON text) with `version` and `rules`.

```json
{"version": 1, "rules": [
  {"id": "pick", "on": "pickup", "do": [{"action": "add_var", "name": "keys", "amount": 1}]},
  {"id": "open", "on": "use", "when": [{"var": "keys", "op": ">=", "value": 2}],
   "do": [{"action": "message", "text": "open"}], "once": true, "cooldown": 0}
]}
```

## Rule fields

| Field | Meaning |
| --- | --- |
| `id` | Unique string. |
| `on` | Event name that triggers the rule. |
| `when` | Optional list of `{var, op, value}`; all must hold. `ctx.key` reads the event context. A missing variable reads as 0. |
| `do` | List of actions, each `{action: id, ...args}`. |
| `once` | Run once, then switch off. |
| `cooldown` | Seconds the rule stays quiet after running; `advance(dt)` counts it down. |
| `enabled` | Start off with `false`. |

## Built-in actions

| Action | Args | Cost |
| --- | --- | --- |
| `message` | text | 1 |
| `set_var` | name, value | 1 |
| `add_var` | name, amount | 1 |
| `toggle_var` | name | 1 |
| `enable_rule` / `disable_rule` | rule | 1 |
| `emit` | event | 2 |

The game adds its own with `actions.register(id, {arg: type}, cost, handler)`. A tick spends at most `tick_budget`; events that do not fit wait, in order. An emitted event waits for the next tick.

Validation lists every problem at once (unknown action, wrong arg type, duplicate id, unknown rule reference, limits) and nothing half-loads.
