local helpers = require("tests.helpers")
local new_set = MiniTest.new_set

local T = new_set()

local autogen

T["setup"] = function()
	require("ai-gitcommit.config").setup({ languages = { "English" } })
	helpers.unload_module("ai-gitcommit.autogen")
	autogen = require("ai-gitcommit.autogen")
end

T["skips generator when buffer changes before debounce"] = function()
	local original_defer_fn = vim.defer_fn
	local original_loaded = package.loaded["ai-gitcommit.generator"]
	local pending_cb = nil
	local ran = false

	package.loaded["ai-gitcommit.generator"] = {
		run = function()
			ran = true
		end,
	}

	vim.defer_fn = function(fn, _)
		pending_cb = fn
		return 1
	end

	local bufnr = helpers.create_gitcommit_buffer()
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "" })
	autogen.setup({ enabled = true, debounce_ms = 1 })
	vim.api.nvim_exec_autocmds("FileType", { buffer = bufnr })

	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "feat: typed edit" })
	vim.api.nvim_exec_autocmds("TextChanged", { buffer = bufnr })

	if pending_cb then
		pending_cb()
	end

	vim.defer_fn = original_defer_fn
	package.loaded["ai-gitcommit.generator"] = original_loaded
	helpers.cleanup_buffer(bufnr)

	MiniTest.expect.equality(ran, false)
end

T["runs generator when buffer stays untouched"] = function()
	local original_defer_fn = vim.defer_fn
	local original_loaded = package.loaded["ai-gitcommit.generator"]
	local pending_cb = nil
	local ran = false

	package.loaded["ai-gitcommit.generator"] = {
		run = function()
			ran = true
		end,
	}

	vim.defer_fn = function(fn, _)
		pending_cb = fn
		return 1
	end

	local bufnr = helpers.create_gitcommit_buffer()
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "" })
	autogen.setup({ enabled = true, debounce_ms = 1 })
	vim.api.nvim_exec_autocmds("FileType", { buffer = bufnr })

	if pending_cb then
		pending_cb()
	end

	vim.defer_fn = original_defer_fn
	package.loaded["ai-gitcommit.generator"] = original_loaded
	helpers.cleanup_buffer(bufnr)

	MiniTest.expect.equality(ran, true)
end

return T
