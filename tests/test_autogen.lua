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

T["schedules autogen for current gitcommit buffer during setup"] = function()
	local original_defer_fn = vim.defer_fn
	local original_schedule = vim.schedule
	local pending_cb = nil
	local scheduled_cb = nil
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

	vim.schedule = function(fn)
		scheduled_cb = fn
	end

	local bufnr = helpers.create_gitcommit_buffer()
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "" })
	autogen.setup({ enabled = true, debounce_ms = 1 })

	if scheduled_cb then
		scheduled_cb()
	end

	if pending_cb then
		pending_cb()
	end

	vim.defer_fn = original_defer_fn
	vim.schedule = original_schedule
	package.loaded["ai-gitcommit.generator"] = original_generator
	package.loaded["ai-gitcommit.providers"] = original_providers
	helpers.cleanup_buffer(bufnr)

	MiniTest.expect.equality(ran, true)
end

return T
