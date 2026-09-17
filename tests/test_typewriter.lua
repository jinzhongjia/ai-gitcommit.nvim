local helpers = require("tests.helpers")
local new_set = MiniTest.new_set

local T = new_set()

T["before_update prevents buffer overwrite"] = function()
	local typewriter = require("ai-gitcommit.typewriter")
	local bufnr = helpers.create_gitcommit_buffer()
	local calls = 0

	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "existing", "# comment" })

	local tw = typewriter.new({
		bufnr = bufnr,
		interval_ms = 1,
		chars_per_tick = 32,
		before_update = function()
			calls = calls + 1
			return false
		end,
	})

	tw:push("feat: add tests")
	vim.wait(200, function()
		return not tw.running
	end)

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	helpers.cleanup_buffer(bufnr)

	MiniTest.expect.equality(calls > 0, true)
	MiniTest.expect.equality(lines, { "existing", "# comment" })
end

T["generated comment-like lines do not duplicate or replace git comments"] = function()
	local typewriter = require("ai-gitcommit.typewriter")
	local bufnr = helpers.create_gitcommit_buffer()
	vim.bo[bufnr].commentstring = "# %s"
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "old message", "", "# original git status" })

	local tw = typewriter.new({ bufnr = bufnr, interval_ms = 1, chars_per_tick = 4 })
	local done = false
	tw:push("feat: change\n\n# details\nbody")
	tw:finish(function()
		done = true
	end)
	local completed = vim.wait(2000, function()
		return done
	end)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	tw:stop()
	helpers.cleanup_buffer(bufnr)

	MiniTest.expect.equality(completed, true)
	MiniTest.expect.equality(lines, { "feat: change", "", "# details", "body", "", "# original git status" })
end

return T
