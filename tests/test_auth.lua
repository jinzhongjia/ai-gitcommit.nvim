local new_set = MiniTest.new_set

local T = new_set()

local auth

T["setup"] = function()
	auth = require("ai-gitcommit.auth")
end

T["is_authenticated"] = new_set()

T["is_authenticated"]["returns boolean"] = function()
	local result = auth.is_authenticated()
	MiniTest.expect.equality(type(result), "boolean")
end

T["get_token"] = new_set()

T["get_token"]["calls callback with error when not authenticated"] = function()
	local done = false
	local result_data = nil
	local result_err = nil

	auth.get_token(function(data, err)
		result_data = data
		result_err = err
		done = true
	end)

	vim.wait(1000, function()
		return done
	end)

	MiniTest.expect.equality(done, true)
	if not auth.is_authenticated() then
		MiniTest.expect.equality(result_data, nil)
		MiniTest.expect.equality(result_err ~= nil, true)
	end
end

T["logout"] = new_set()

T["logout"]["executes without error"] = function()
	local ok = pcall(auth.logout)
	MiniTest.expect.equality(ok, true)
end

return T
