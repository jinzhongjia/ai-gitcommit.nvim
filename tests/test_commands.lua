local new_set = MiniTest.new_set

local T = new_set()

local commands = require("ai-gitcommit.commands")

T["is idempotent"] = function()
	local original_create = vim.api.nvim_create_user_command
	local original_del = vim.api.nvim_del_user_command

	vim.api.nvim_create_user_command = function(_, _, _) end
	vim.api.nvim_del_user_command = function(_) end

	local ok1 = pcall(commands.setup)
	local ok2 = pcall(commands.setup)

	vim.api.nvim_create_user_command = original_create
	vim.api.nvim_del_user_command = original_del

	MiniTest.expect.equality(ok1, true)
	MiniTest.expect.equality(ok2, true)
end

T["completion"] = new_set()

T["completion"]["handles special pattern chars safely"] = function()
	local original_create = vim.api.nvim_create_user_command
	local captured = nil

	vim.api.nvim_create_user_command = function(_, _, opts)
		captured = opts.complete
	end

	commands.setup()
	vim.api.nvim_create_user_command = original_create

	local ok, result = pcall(captured, "", "AICommit [")
	MiniTest.expect.equality(ok, true)
	MiniTest.expect.equality(type(result), "table")
	MiniTest.expect.equality(#result, 0)
end

return T
