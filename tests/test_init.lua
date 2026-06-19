local new_set = MiniTest.new_set
local helpers = require("tests.helpers")

local T = new_set()

T["setup"] = new_set()

T["setup"]["can be called twice without error"] = function()
	helpers.reset_config()
	local ai = require("ai-gitcommit")

	local ok1 = pcall(ai.setup, helpers.get_test_config())
	local ok2 = pcall(ai.setup, helpers.get_test_config())

	MiniTest.expect.equality(ok1, true)
	MiniTest.expect.equality(ok2, true)
end

return T
