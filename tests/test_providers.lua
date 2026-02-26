local new_set = MiniTest.new_set

local T = new_set()

local providers

T["setup"] = function()
	providers = require("ai-gitcommit.providers")
end

T["get"] = new_set()

T["get"]["returns anthropic provider"] = function()
	local provider = providers.get("anthropic")

	MiniTest.expect.equality(type(provider), "table")
	MiniTest.expect.equality(type(provider.generate), "function")
end

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

return T
