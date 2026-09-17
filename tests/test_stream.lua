local new_set = MiniTest.new_set

local T = new_set()

local stream

T["setup"] = function()
	stream = require("ai-gitcommit.stream")
end

T["cancel"] = new_set()

T["request"] = new_set()

T["request"]["parses SSE events with CRLF line endings"] = function()
	local original_system = vim.system
	local chunks = {}
	local errors = {}
	local done_called = false

	vim.system = function(_, opts, cb)
		opts.stdout(nil, 'data: {"choices":[{"delta":{"content":"feat:"}}]}\r\n\r\n')
		opts.stdout(nil, 'data: {"choices":[{"delta":{"content":" add tests"}}]}\r\n\r\n')
		opts.stdout(nil, "data: [DONE]\r\n\r\n")
		cb({ code = 0 })
		return {
			is_closing = function()
				return false
			end,
			kill = function(_, _) end,
		}
	end

	stream.request({
		url = "https://example.com",
	}, function(chunk)
		table.insert(chunks, chunk)
	end, function()
		done_called = true
	end, function(err)
		table.insert(errors, err)
	end)

	vim.wait(500, function()
		return done_called
	end)

	vim.system = original_system

	MiniTest.expect.equality(#errors, 0)
	MiniTest.expect.equality(done_called, true)
	MiniTest.expect.equality(#chunks, 2)
	MiniTest.expect.equality(chunks[1].choices[1].delta.content, "feat:")
	MiniTest.expect.equality(chunks[2].choices[1].delta.content, " add tests")
end

T["request"]["returns parse error when stream payload is invalid"] = function()
	local original_system = vim.system
	local chunks = {}
	local errors = {}
	local done_called = false

	vim.system = function(_, opts, cb)
		opts.stdout(nil, "data: {invalid-json}\n\n")
		cb({ code = 0 })
		return {
			is_closing = function()
				return false
			end,
			kill = function(_, _) end,
		}
	end

	stream.request({
		url = "https://example.com",
	}, function(chunk)
		table.insert(chunks, chunk)
	end, function()
		done_called = true
	end, function(err)
		table.insert(errors, err)
	end)

	vim.wait(500, function()
		return done_called or #errors > 0
	end)

	vim.system = original_system

	MiniTest.expect.equality(done_called, false)
	MiniTest.expect.equality(#chunks, 0)
	MiniTest.expect.equality(#errors, 1)
	MiniTest.expect.equality(errors[1], "Failed to parse streaming response")
end

---@param payload string
---@param cancel boolean?
---@param exit_code integer?
---@return table[]
local function collect_stream_events(payload, cancel, exit_code)
	local original_system, original_schedule = vim.system, vim.schedule
	local callbacks, events = {}, {}
	vim.schedule = function(fn)
		table.insert(callbacks, fn)
	end
	vim.system = function(_, opts, cb)
		opts.stdout(nil, payload)
		cb({ code = exit_code or 0 })
		return {
			is_closing = function()
				return false
			end,
			kill = function() end,
		}
	end

	local ok, err = pcall(function()
		local handle = stream.request({ url = "https://example.com" }, function(chunk)
			table.insert(events, { "chunk", chunk })
		end, function()
			table.insert(events, { "done" })
		end, function(message)
			table.insert(events, { "error", message })
		end)
		if cancel then
			stream.cancel(handle)
		end
		local i = 1
		while callbacks[i] do
			callbacks[i]()
			i = i + 1
		end
	end)
	vim.system, vim.schedule = original_system, original_schedule
	if not ok then
		error(err)
	end
	return events
end

T["cancel"]["suppresses queued chunks and errors"] = function()
	local events = collect_stream_events('data: {"text":"late"}\n\ndata: {"error":{"message":"late error"}}\n\n', true)
	MiniTest.expect.equality(events, {})
end

T["request"]["delivers final unterminated SSE event before completion"] = function()
	local events = collect_stream_events('data: {"text":"last"}\n')
	MiniTest.expect.equality(events, { { "chunk", { text = "last" } }, { "done" } })
end

T["request"]["preserves final line without newline"] = function()
	local events = collect_stream_events('data: {"text":"last"}')
	MiniTest.expect.equality(events, { { "chunk", { text = "last" } }, { "done" } })
end

T["request"]["stops callbacks after first API error"] = function()
	local events = collect_stream_events(
		'data: {"error":{"message":"first"}}\n\ndata: {"error":{"message":"second"}}\n\ndata: {"text":"late"}\n\n'
	)
	MiniTest.expect.equality(events, { { "error", "first" } })
end

T["request"]["reports flat Responses error events"] = function()
	local events = collect_stream_events('data: {"type":"error","message":"quota exhausted","code":"insufficient_quota"}\n\n')
	MiniTest.expect.equality(events, { { "error", "quota exhausted" } })
end

T["request"]["rejects scalar JSON without throwing"] = function()
	local events = collect_stream_events("data: 42\n\n")
	MiniTest.expect.equality(events, { { "error", "Failed to parse streaming response" } })
end

T["request"]["reports string HTTP errors without a trailing newline"] = function()
	local events = collect_stream_events('{"error":"upstream unavailable"}', false, 22)
	MiniTest.expect.equality(events, { { "error", "upstream unavailable" } })
end

return T
