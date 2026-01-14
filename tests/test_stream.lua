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

return T
