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

T["find_first_comment_line"]["respects custom git comment prefix"] = function()
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.bo[bufnr].commentstring = "; %s"
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
		"feat: existing message",
		"",
		"; Please enter the commit message",
	})

	local line = buffer.find_first_comment_line(bufnr)
	MiniTest.expect.equality(line, 3)

	helpers.cleanup_buffer(bufnr)
end

T["get_existing_message"] = new_set()

T["get_existing_message"]["returns message before comments"] = function()
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
		"feat: existing message",
		"",
		"# Comment line",
	})

	local message = buffer.get_existing_message(bufnr)
	MiniTest.expect.equality(message, "feat: existing message")

	helpers.cleanup_buffer(bufnr)
end

T["is_amend_message_buffer"] = new_set()

T["is_amend_message_buffer"]["returns true for commit editmsg with Date comment"] = function()
	local tmp = vim.fn.tempname()
	vim.fn.writefile({}, tmp)
	local editmsg = vim.fs.joinpath(vim.fn.fnamemodify(tmp, ":h"), "COMMIT_EDITMSG")
	vim.fn.rename(tmp, editmsg)

	local bufnr = vim.fn.bufadd(editmsg)
	vim.fn.bufload(bufnr)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
		"feat: existing message",
		"",
		"# Date: Sun Apr 26 12:00:00 2026 +0000",
	})

	MiniTest.expect.equality(buffer.is_amend_message_buffer(bufnr), true)

	vim.api.nvim_buf_delete(bufnr, { force = true })
	vim.fn.delete(editmsg)
end

T["is_amend_message_buffer"]["returns false without amend metadata"] = function()
	local tmp = vim.fn.tempname()
	vim.fn.writefile({}, tmp)
	local editmsg = vim.fs.joinpath(vim.fn.fnamemodify(tmp, ":h"), "COMMIT_EDITMSG")
	vim.fn.rename(tmp, editmsg)

	local bufnr = vim.fn.bufadd(editmsg)
	vim.fn.bufload(bufnr)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
		"feat: existing message",
		"",
		"# Please enter the commit message for your changes.",
	})

	MiniTest.expect.equality(buffer.is_amend_message_buffer(bufnr), false)

	vim.api.nvim_buf_delete(bufnr, { force = true })
	vim.fn.delete(editmsg)
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

return T
