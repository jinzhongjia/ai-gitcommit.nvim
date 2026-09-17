local helpers = require("tests.helpers")
local new_set = MiniTest.new_set

local T = new_set()

T["setup"] = function()
	require("ai-gitcommit.config").setup({ languages = { "English" } })
end

---@return table, table|nil, table|nil
local function setup_autogen_mocks()
	local original_generator = package.loaded["ai-gitcommit.generator"]
	local original_providers = package.loaded["ai-gitcommit.providers"]

	package.loaded["ai-gitcommit.providers"] = {
		has_current_credentials = function()
			return true
		end,
	}

	helpers.unload_module("ai-gitcommit.autogen")
	return require("ai-gitcommit.autogen"), original_generator, original_providers
end

T["runs generator when buffer stays untouched"] = function()
	local original_defer_fn = vim.defer_fn
	local pending_cb = nil
	local ran = false
	local autogen, original_generator, original_providers = setup_autogen_mocks()

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
	package.loaded["ai-gitcommit.generator"] = original_generator
	package.loaded["ai-gitcommit.providers"] = original_providers
	helpers.cleanup_buffer(bufnr)

	MiniTest.expect.equality(ran, true)
end

T["preserves edits made before the debounce expires"] = function()
	local original_defer_fn = vim.defer_fn
	local pending_cb
	local autogen, original_generator, original_providers = setup_autogen_mocks()
	require("ai-gitcommit.config").setup({ languages = { "English" } })
	package.loaded["ai-gitcommit.generator"] = {
		run = function(_, _, bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "generated overwrite" })
		end,
	}
	vim.defer_fn = function(fn, _)
		pending_cb = fn
	end

	local bufnr = helpers.create_gitcommit_buffer()
	autogen.setup({ enabled = true, debounce_ms = 1 })
	vim.api.nvim_exec_autocmds("FileType", { buffer = bufnr })
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "user draft" })
	pending_cb()
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	autogen.setup({ enabled = false })
	vim.defer_fn = original_defer_fn
	package.loaded["ai-gitcommit.generator"] = original_generator
	package.loaded["ai-gitcommit.providers"] = original_providers
	helpers.cleanup_buffer(bufnr)
	MiniTest.expect.equality(lines, { "user draft" })
end

T["preserves edits made while the language picker is open"] = function()
	local original_defer_fn = vim.defer_fn
	local original_select = vim.ui.select
	local pending_cb
	local on_choice
	local autogen, original_generator, original_providers = setup_autogen_mocks()
	require("ai-gitcommit.config").setup({ languages = { "English", "中文" } })
	package.loaded["ai-gitcommit.generator"] = {
		run = function(_, _, bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "generated overwrite" })
		end,
	}
	vim.defer_fn = function(fn, _)
		pending_cb = fn
	end
	vim.ui.select = function(_, _, callback)
		on_choice = callback
	end

	local bufnr = helpers.create_gitcommit_buffer()
	autogen.setup({ enabled = true, debounce_ms = 1 })
	vim.api.nvim_exec_autocmds("FileType", { buffer = bufnr })
	pending_cb()
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "user draft" })
	on_choice("English")
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	autogen.setup({ enabled = false })
	vim.defer_fn = original_defer_fn
	vim.ui.select = original_select
	package.loaded["ai-gitcommit.generator"] = original_generator
	package.loaded["ai-gitcommit.providers"] = original_providers
	require("ai-gitcommit.config").setup({ languages = { "English" } })
	helpers.cleanup_buffer(bufnr)
	MiniTest.expect.equality(lines, { "user draft" })
end

T["offers generation when setup follows the gitcommit FileType event"] = function()
	local original_select = vim.ui.select
	local autogen, original_generator, original_providers = setup_autogen_mocks()
	local bufnr = helpers.create_gitcommit_buffer()
	local choices
	local on_choice
	require("ai-gitcommit.config").setup({ languages = { "English", "中文" } })
	package.loaded["ai-gitcommit.generator"] = {
		run = function(_, _, target)
			vim.api.nvim_buf_set_lines(target, 0, -1, false, { "generated message" })
		end,
	}
	vim.ui.select = function(items, _, callback)
		choices = items
		on_choice = callback
	end

	autogen.setup({ enabled = true, debounce_ms = 1 })
	vim.wait(200, function()
		return on_choice ~= nil
	end, 5)
	if on_choice then
		on_choice("English")
	end
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	autogen.setup({ enabled = false })
	vim.ui.select = original_select
	package.loaded["ai-gitcommit.generator"] = original_generator
	package.loaded["ai-gitcommit.providers"] = original_providers
	require("ai-gitcommit.config").setup({ languages = { "English" } })
	require("ai-gitcommit.buffer_state").clear(bufnr)
	helpers.cleanup_buffer(bufnr)

	MiniTest.expect.equality(choices, { "English", "中文" })
	MiniTest.expect.equality(lines, { "generated message" })
end

T["offers generation after the editor inserts help comments"] = function()
	local original_defer_fn = vim.defer_fn
	local original_select = vim.ui.select
	local pending_cb
	local choices
	local autogen, original_generator, original_providers = setup_autogen_mocks()
	require("ai-gitcommit.config").setup({ languages = { "English", "中文" } })
	vim.defer_fn = function(fn, _)
		pending_cb = fn
	end
	vim.ui.select = function(items, _, callback)
		choices = items
		callback(nil)
	end

	local bufnr = helpers.create_gitcommit_buffer()
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "", "#", "# staged changes" })
	autogen.setup({ enabled = true, debounce_ms = 1 })
	vim.api.nvim_exec_autocmds("FileType", { buffer = bufnr })
	vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { "# Commands:", "#   q Close", "#   <c-c> Submit" })
	pending_cb()
	local message = require("ai-gitcommit.buffer").get_existing_message(bufnr)

	autogen.setup({ enabled = false })
	vim.defer_fn = original_defer_fn
	vim.ui.select = original_select
	package.loaded["ai-gitcommit.generator"] = original_generator
	package.loaded["ai-gitcommit.providers"] = original_providers
	require("ai-gitcommit.config").setup({ languages = { "English" } })
	require("ai-gitcommit.buffer_state").clear(bufnr)
	helpers.cleanup_buffer(bufnr)

	MiniTest.expect.equality(choices, { "English", "中文" })
	MiniTest.expect.equality(message, "")
end

return T
