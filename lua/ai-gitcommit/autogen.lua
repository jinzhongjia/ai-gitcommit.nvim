local buffer_state = require("ai-gitcommit.buffer_state")
local config = require("ai-gitcommit.config")
local providers = require("ai-gitcommit.providers")

local M = {}

local AUTOGEN_GROUP = vim.api.nvim_create_augroup("AIGitCommitAutogen", { clear = true })

---@param language string
---@param bufnr integer
local function run_generator(language, bufnr)
	require("ai-gitcommit.generator").run(language, nil, bufnr, false)
end

---@param bufnr integer
---@param debounce_ms integer
local function schedule_autogen(bufnr, debounce_ms)
	local state = buffer_state.get(bufnr)

	buffer_state.stop_timer(bufnr)

	state.timer = vim.defer_fn(function()
		state.timer = nil

		if not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end

		if state.generated or state.generating then
			return
		end

		if not providers.has_current_credentials() then
			return
		end

		local languages = config.get().languages

		if #languages == 0 then
			return
		end

		if #languages == 1 then
			run_generator(languages[1], bufnr)
			return
		end

		vim.ui.select(languages, { prompt = "Select language:" }, function(choice)
			if not choice then
				return
			end

			run_generator(choice, bufnr)
		end)
	end, debounce_ms)
end

---@param auto_cfg AIGitCommit.AutoConfig
function M.setup(auto_cfg)
	buffer_state.stop_all_timers()
	vim.api.nvim_clear_autocmds({ group = AUTOGEN_GROUP })

	if not auto_cfg or not auto_cfg.enabled then
		return
	end

	local debounce_ms = auto_cfg.debounce_ms or 300

	vim.api.nvim_create_autocmd("FileType", {
		group = AUTOGEN_GROUP,
		pattern = "gitcommit",
		callback = function(args)
			schedule_autogen(args.buf, debounce_ms)
		end,
	})

	local current_buf = vim.api.nvim_get_current_buf()
	if vim.api.nvim_get_option_value("filetype", { buf = current_buf }) == "gitcommit" then
		vim.schedule(function()
			if vim.api.nvim_buf_is_valid(current_buf) and vim.api.nvim_get_option_value("filetype", { buf = current_buf }) == "gitcommit" then
				schedule_autogen(current_buf, debounce_ms)
			end
		end)
	end
end

return M
