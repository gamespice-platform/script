extends RefCounted

## GameSpice Script's API level. The rule for bumping it is on [GSAddonApi].

# 1: GSScriptRunner, GSScriptDocument, GSScriptActions, GSScriptConfig.
# 2: GSScriptCodec, GSScriptConditions, cooldowns, toggle_var, snapshot/restore, max_vars, max_document_bytes.
const LEVEL := 2
const OLDEST := 1
