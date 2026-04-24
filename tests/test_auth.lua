local new_set = MiniTest.new_set

local T = new_set()

local auth

T["setup"] = function()
	auth = require("ai-gitcommit.auth")
end

T["is_authenticated"] = new_set()

T["is_authenticated"]["returns boolean for copilot"] = function()
	local result = auth.is_authenticated("copilot")
	MiniTest.expect.equality(type(result), "boolean")
end

T["is_authenticated"]["returns false for provider without auth module"] = function()
	MiniTest.expect.equality(auth.is_authenticated("openai"), false)
end

T["get_token"] = new_set()

T["get_token"]["errors for provider without auth module"] = function()
	local result_err
	auth.get_token("openai", function(_, err)
		result_err = err
	end)

	MiniTest.expect.equality(type(result_err), "string")
end

T["logout"] = new_set()

T["logout"]["errors for provider without auth module"] = function()
	local ok, err = auth.logout("openai")
	MiniTest.expect.equality(ok, false)
	MiniTest.expect.equality(type(err), "string")
end

return T
