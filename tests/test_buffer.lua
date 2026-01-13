local helpers = require("tests.helpers")
local new_set = MiniTest.new_set

local T = new_set()

local buffer

T["setup"] = function()
	buffer = require("ai-gitcommit.buffer")
end

T["is_gitcommit_buffer"] = new_set()

T["is_gitcommit_buffer"]["returns true for gitcommit filetype"] = function()
	local bufnr = helpers.create_gitcommit_buffer()

	local result = buffer.is_gitcommit_buffer(bufnr)
	MiniTest.expect.equality(result, true)

	helpers.cleanup_buffer(bufnr)
end

T["is_gitcommit_buffer"]["returns false for other filetypes"] = function()
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.bo[bufnr].filetype = "lua"

	local result = buffer.is_gitcommit_buffer(bufnr)
	MiniTest.expect.equality(result, false)

	helpers.cleanup_buffer(bufnr)
end

T["find_first_comment_line"] = new_set()

T["find_first_comment_line"]["finds comment line"] = function()
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
		"",
		"# Please enter the commit message",
		"# Lines starting with '#' will be ignored",
	})

	local line = buffer.find_first_comment_line(bufnr)
	MiniTest.expect.equality(line, 2)

	helpers.cleanup_buffer(bufnr)
end

T["find_first_comment_line"]["returns line count + 1 when no comments"] = function()
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
		"line 1",
		"line 2",
	})

	local line = buffer.find_first_comment_line(bufnr)
	MiniTest.expect.equality(line, 3)

	helpers.cleanup_buffer(bufnr)
end

T["set_commit_message"] = new_set()

T["set_commit_message"]["sets message before comments"] = function()
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(bufnr)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
		"# Comment line",
	})

	buffer.set_commit_message("feat: new feature", bufnr)

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	MiniTest.expect.equality(lines[1], "feat: new feature")
	MiniTest.expect.equality(lines[3], "# Comment line")

	helpers.cleanup_buffer(bufnr)
end

T["get_current_message"] = new_set()

T["get_current_message"]["returns message before comments"] = function()
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
		"fix: bug fix",
		"",
		"# Comment",
	})

	local msg = buffer.get_current_message(bufnr)
	MiniTest.expect.equality(msg, "fix: bug fix\n")

	helpers.cleanup_buffer(bufnr)
end

return T
