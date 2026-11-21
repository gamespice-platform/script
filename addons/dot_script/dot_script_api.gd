extends RefCounted

## GameSpice Script's API level. The rule for bumping it is on [DotAddonApi].

# 1: DotScriptRunner, DotScriptDocument, DotScriptActions, DotScriptConfig.
# 2: DotScriptCodec, DotScriptConditions, cooldowns, toggle_var, snapshot/restore, max_vars, max_document_bytes.
const LEVEL := 2
const OLDEST := 1
