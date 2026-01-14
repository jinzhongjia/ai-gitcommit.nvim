local new_set = MiniTest.new_set

local T = new_set()

local providers

T["setup"] = function()
	providers = require("ai-gitcommit.providers")
end

T["get"] = new_set()

T["get"]["returns anthropic provider"] = function()
	local provider = providers.get()

	MiniTest.expect.equality(type(provider), "table")
	MiniTest.expect.equality(type(provider.generate), "function")
end

return T
