local new_set = MiniTest.new_set

local T = new_set()

local auth

T["setup"] = function()
	auth = require("ai-gitcommit.auth")
end

T["is_authenticated"] = new_set()

T["is_authenticated"]["returns boolean"] = function()
	local result = auth.is_authenticated("anthropic")
	MiniTest.expect.equality(type(result), "boolean")
end

T["get_token"] = new_set()

T["get_token"]["calls callback for openai error"] = function()
	local done = false

	auth.get_token("openai", function(_, _)
		done = true
	end)

	vim.wait(1000, function()
		return done
	end)

	MiniTest.expect.equality(done, true)
end

T["logout"] = new_set()

T["logout"]["returns error for openai"] = function()
	local ok, err = auth.logout("openai")
	MiniTest.expect.equality(ok, false)
	MiniTest.expect.equality(type(err), "string")
end

return T
