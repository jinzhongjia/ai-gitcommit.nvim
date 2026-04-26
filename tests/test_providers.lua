local new_set = MiniTest.new_set
local helpers = require("tests.helpers")

local T = new_set()

local providers

T["setup"] = function()
	providers = require("ai-gitcommit.providers")
end

T["get"] = new_set()

T["get"]["returns openai provider"] = function()
	local provider = providers.get("openai")

	MiniTest.expect.equality(type(provider), "table")
	MiniTest.expect.equality(type(provider.generate), "function")
end

T["get"]["returns copilot provider"] = function()
	local provider = providers.get("copilot")

	MiniTest.expect.equality(type(provider), "table")
	MiniTest.expect.equality(type(provider.generate), "function")
end

T["get"]["throws on unsupported provider"] = function()
	local ok = pcall(providers.get, "invalid")
	MiniTest.expect.equality(ok, false)
end

T["openai generate"] = new_set()

T["openai generate"]["sends completion request with stream options"] = function()
	local original_stream = package.loaded["ai-gitcommit.stream"]
	helpers.unload_module("ai-gitcommit.providers.openai")
	helpers.unload_module("ai-gitcommit.providers.openai_compat")

	local captured = nil
	package.loaded["ai-gitcommit.stream"] = {
		request = function(opts, _, on_done, _)
			captured = opts
			on_done()
			return { system_obj = nil }
		end,
	}

	local ok, err = pcall(function()
		local openai = require("ai-gitcommit.providers.openai")
		openai.generate("hello", {
			model = "gpt-4o-mini",
			max_tokens = 500,
			endpoint = "https://api.openai.com/v1/chat/completions",
			api_key = "test-key",
		}, function(_) end, function() end, function(_) end)
	end)

	package.loaded["ai-gitcommit.stream"] = original_stream
	helpers.unload_module("ai-gitcommit.providers.openai")
	helpers.unload_module("ai-gitcommit.providers.openai_compat")

	MiniTest.expect.equality(ok, true)
	MiniTest.expect.equality(err, nil)
	MiniTest.expect.equality(captured.url, "https://api.openai.com/v1/chat/completions")
	MiniTest.expect.equality(captured.headers["Authorization"], "Bearer test-key")
	MiniTest.expect.equality(captured.body.stream, true)
	MiniTest.expect.equality(captured.body.stream_options.include_usage, true)
	MiniTest.expect.equality(captured.body.messages[1].role, "user")
	MiniTest.expect.equality(captured.body.messages[1].content, "hello")
	MiniTest.expect.equality(captured.body.tools, nil)
end

T["openai generate"]["supports openai-compatible endpoints without bearer auth"] = function()
	local original_stream = package.loaded["ai-gitcommit.stream"]
	helpers.unload_module("ai-gitcommit.providers.openai")
	helpers.unload_module("ai-gitcommit.providers.openai_compat")

	local captured = nil
	package.loaded["ai-gitcommit.stream"] = {
		request = function(opts, _, on_done, _)
			captured = opts
			on_done()
			return { system_obj = nil }
		end,
	}

	local ok, err = pcall(function()
		local openai = require("ai-gitcommit.providers.openai")
		openai.generate("hello", {
			model = "qwen2.5-coder",
			max_tokens = 500,
			endpoint = "http://localhost:11434/v1/chat/completions",
			api_key = "",
			api_key_required = false,
			stream_options = false,
			extra_headers = {
				["X-Test-Header"] = "1",
			},
		}, function(_) end, function() end, function(_) end)
	end)

	package.loaded["ai-gitcommit.stream"] = original_stream
	helpers.unload_module("ai-gitcommit.providers.openai")
	helpers.unload_module("ai-gitcommit.providers.openai_compat")

	MiniTest.expect.equality(ok, true)
	MiniTest.expect.equality(err, nil)
	MiniTest.expect.equality(captured.url, "http://localhost:11434/v1/chat/completions")
	MiniTest.expect.equality(captured.headers["Authorization"], nil)
	MiniTest.expect.equality(captured.headers["X-Test-Header"], "1")
	MiniTest.expect.equality(captured.body.stream, true)
	MiniTest.expect.equality(captured.body.stream_options, nil)
	MiniTest.expect.equality(captured.body.messages[1].content, "hello")
end

T["copilot generate"] = new_set()

T["copilot generate"]["sends completion-only headers and payload"] = function()
	local original_stream = package.loaded["ai-gitcommit.stream"]
	helpers.unload_module("ai-gitcommit.providers.copilot")
	helpers.unload_module("ai-gitcommit.providers.openai_compat")

	local captured = nil
	package.loaded["ai-gitcommit.stream"] = {
		request = function(opts, _, on_done, _)
			captured = opts
			on_done()
			return { system_obj = nil }
		end,
	}

	local ok, err = pcall(function()
		local copilot = require("ai-gitcommit.providers.copilot")
		copilot.generate("hello", {
			model = "gpt-4o",
			max_tokens = 500,
			endpoint = "https://api.githubcopilot.com/chat/completions",
			api_key = "test-token",
		}, function(_) end, function() end, function(_) end)
	end)

	package.loaded["ai-gitcommit.stream"] = original_stream
	helpers.unload_module("ai-gitcommit.providers.copilot")
	helpers.unload_module("ai-gitcommit.providers.openai_compat")

	MiniTest.expect.equality(ok, true)
	MiniTest.expect.equality(err, nil)
	MiniTest.expect.equality(captured.url, "https://api.githubcopilot.com/chat/completions")
	MiniTest.expect.equality(captured.headers["Authorization"], "Bearer test-token")
	MiniTest.expect.equality(captured.headers["Copilot-Integration-Id"], "vscode-chat")
	MiniTest.expect.equality(type(captured.headers["Editor-Version"]), "string")
	MiniTest.expect.equality(captured.headers["Editor-Version"]:find("^Neovim/") ~= nil, true)
	MiniTest.expect.equality(captured.headers["Openai-Intent"], nil)
	MiniTest.expect.equality(captured.headers["x-initiator"], nil)
	MiniTest.expect.equality(captured.body.stream, true)
	MiniTest.expect.equality(captured.body.messages[1].content, "hello")
	MiniTest.expect.equality(captured.body.tools, nil)
end

return T
