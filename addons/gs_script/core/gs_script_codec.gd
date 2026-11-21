class_name GSScriptCodec
extends RefCounted

## Text in, document out. A script travels as JSON; this is the one place it is parsed, so the size limit
## applies before any parsing work is done.


## Parses JSON text and validates it. Success carries the document Dictionary; failure says why, with
## every validation problem listed. `actions` and `cfg` are the runner's, so the result is what that runner would accept.
static func parse(text: String, actions: GSScriptActions, cfg: GSScriptConfig) -> GSResult:
	if cfg != null and cfg.max_document_bytes > 0:
		var n := text.to_utf8_buffer().size()
		if n > cfg.max_document_bytes:
			return GSResult.fail(GSError.CODE_INVALID, "script is %d bytes, over max_document_bytes %d" % [n, cfg.max_document_bytes])
	var json := JSON.new()
	if json.parse(text) != OK:
		return GSResult.fail(GSError.CODE_PARSE, "script is not valid JSON: %s (line %d)" % [json.get_error_message(), json.get_error_line()])
	return GSScriptDocument.validate(json.data, actions, cfg)


## A document as indented JSON, keys sorted so two equal documents give equal text.
static func stringify(doc: Dictionary) -> String:
	return JSON.stringify(doc, "  ", true)
