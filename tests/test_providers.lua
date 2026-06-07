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

---@param config table
---@return table captured
local function capture_copilot_request(config)
	local original_stream = package.loaded["ai-gitcommit.stream"]
	helpers.unload_module("ai-gitcommit.providers.copilot")
	helpers.unload_module("ai-gitcommit.providers.openai_compat")
	helpers.unload_module("ai-gitcommit.providers.openai_responses")

	local captured = nil
	package.loaded["ai-gitcommit.stream"] = {
		request = function(opts, _, on_done, _)
			captured = opts
			on_done()
			return { system_obj = nil }
		end,
	}

	local copilot = require("ai-gitcommit.providers.copilot")
	copilot.generate("hello", config, function(_) end, function() end, function(_) end)

	package.loaded["ai-gitcommit.stream"] = original_stream
	helpers.unload_module("ai-gitcommit.providers.copilot")
	helpers.unload_module("ai-gitcommit.providers.openai_compat")
	helpers.unload_module("ai-gitcommit.providers.openai_responses")

	return captured
end

T["copilot generate"]["routes /responses endpoint through responses provider"] = function()
	local captured = capture_copilot_request({
		model = "gpt-5.3-codex",
		max_tokens = 80,
		endpoint = "https://api.githubcopilot.com/responses",
		api_key = "test-token",
	})

	MiniTest.expect.equality(captured.url, "https://api.githubcopilot.com/responses")
	-- Responses API uses `input`, NOT `messages`
	MiniTest.expect.equality(captured.body.messages, nil)
	MiniTest.expect.equality(type(captured.body.input), "table")
	MiniTest.expect.equality(captured.body.input[1].role, "user")
	MiniTest.expect.equality(captured.body.input[1].content, "hello")
	MiniTest.expect.equality(captured.body.store, false)
	MiniTest.expect.equality(captured.body.max_output_tokens, 80)
	MiniTest.expect.equality(captured.headers["Authorization"], "Bearer test-token")
end

T["copilot generate"]["treats /responses with trailing slash as responses"] = function()
	local captured = capture_copilot_request({
		model = "gpt-5.3-codex",
		max_tokens = 60,
		endpoint = "https://api.githubcopilot.com/responses/",
		api_key = "test-token",
	})

	-- Should still dispatch to responses provider, NOT chat/completions
	MiniTest.expect.equality(captured.body.messages, nil)
	MiniTest.expect.equality(type(captured.body.input), "table")
end

T["copilot generate"]["routes /chat/completions endpoint through chat provider"] = function()
	local captured = capture_copilot_request({
		model = "gpt-4o",
		max_tokens = 80,
		endpoint = "https://api.githubcopilot.com/chat/completions",
		api_key = "test-token",
	})

	-- Chat path: expect messages, NOT input
	MiniTest.expect.equality(captured.body.input, nil)
	MiniTest.expect.equality(type(captured.body.messages), "table")
	MiniTest.expect.equality(captured.body.messages[1].content, "hello")
end

T["copilot resolve_credentials"] = new_set()

---@param config table
---@return table result {creds, err}
local function resolve_with_mock_token(config, token_data)
	helpers.unload_module("ai-gitcommit.providers.copilot")
	helpers.unload_module("ai-gitcommit.auth")

	local original_auth = package.loaded["ai-gitcommit.auth"]
	package.loaded["ai-gitcommit.auth"] = {
		get_token = function(_, cb)
			cb(token_data, nil)
		end,
		is_authenticated = function(_)
			return true
		end,
	}

	local result = { creds = nil, err = nil }
	local copilot = require("ai-gitcommit.providers.copilot")
	copilot.resolve_credentials(config, function(creds, err)
		result.creds = creds
		result.err = err
	end)

	package.loaded["ai-gitcommit.auth"] = original_auth
	helpers.unload_module("ai-gitcommit.providers.copilot")

	return result
end

T["copilot resolve_credentials"]["preserves user endpoint when model is pinned"] = function()
	-- User explicitly pinned a codex model + /responses endpoint.
	-- creds.endpoint must stay nil so generator.lua doesn't overwrite
	-- the user's provider_config.endpoint.
	local result = resolve_with_mock_token({
		model = "gpt-5.3-codex",
		endpoint = "https://api.githubcopilot.com/responses",
	}, {
		token = "copilot_token_xyz",
		endpoint = "https://api.githubcopilot.com/chat/completions",
		endpoint_base = "https://api.githubcopilot.com",
	})

	MiniTest.expect.equality(result.err, nil)
	MiniTest.expect.equality(result.creds.api_key, "copilot_token_xyz")
	MiniTest.expect.equality(result.creds.endpoint, nil)
	MiniTest.expect.equality(result.creds.model, nil)
end

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
