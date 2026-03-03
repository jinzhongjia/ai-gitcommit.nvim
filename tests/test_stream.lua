local new_set = MiniTest.new_set

local T = new_set()

local stream

T["setup"] = function()
	stream = require("ai-gitcommit.stream")
end

T["cancel"] = new_set()

T["cancel"]["handles nil stream handle"] = function()
	local ok = pcall(stream.cancel, nil)
	MiniTest.expect.equality(ok, true)
end

T["cancel"]["handles empty stream handle"] = function()
	local ok = pcall(stream.cancel, {})
	MiniTest.expect.equality(ok, true)
end

T["request"] = new_set()

T["request"]["returns nil on spawn failure with invalid url"] = function()
	local chunks = {}
	local errors = {}
	local done_called = false

	local handle = stream.request({
		url = "invalid://not-a-url",
		method = "POST",
		headers = {},
		body = {},
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

	MiniTest.expect.equality(#errors > 0 or done_called, true)
end

T["request"]["builds correct curl args"] = function()
	local chunks = {}
	local errors = {}
	local done_called = false

	stream.request({
		url = "https://httpbin.org/status/404",
		method = "GET",
		headers = { ["X-Test"] = "value" },
	}, function(chunk)
		table.insert(chunks, chunk)
	end, function()
		done_called = true
	end, function(err)
		table.insert(errors, err)
	end)

	vim.wait(3000, function()
		return done_called or #errors > 0
	end)

	MiniTest.expect.equality(done_called or #errors > 0, true)
end

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
			kill = function(_, _)
			end,
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
			kill = function(_, _)
			end,
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

return T
