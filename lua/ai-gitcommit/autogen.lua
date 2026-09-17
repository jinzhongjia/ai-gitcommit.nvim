local buffer_state = require("ai-gitcommit.buffer_state")
local config = require("ai-gitcommit.config")
local providers = require("ai-gitcommit.providers")

local M = {}

local AUTOGEN_GROUP = vim.api.nvim_create_augroup("AIGitCommitAutogen", { clear = true })


---@param bufnr integer
---@param debounce_ms integer
---@return nil
local function schedule_autogen(bufnr, debounce_ms)
	local state = buffer_state.get(bufnr)
	local expected_changedtick = vim.api.nvim_buf_get_changedtick(bufnr)

	---@return boolean
	local function can_generate()
		return vim.api.nvim_buf_is_valid(bufnr)
			and vim.api.nvim_buf_is_loaded(bufnr)
			and vim.api.nvim_buf_get_changedtick(bufnr) == expected_changedtick
			and not state.generated
			and not state.generating
	end

	buffer_state.stop_timer(bufnr)

	state.timer = vim.defer_fn(function()
		state.timer = nil

		if not can_generate() then
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
			require("ai-gitcommit.generator").run(languages[1], nil, bufnr, false)
			return
		end

		vim.ui.select(languages, { prompt = "Select language:" }, function(choice)
			if not choice or not can_generate() then
				return
			end

			require("ai-gitcommit.generator").run(choice, nil, bufnr, false)
		end)
	end, debounce_ms)
end

---@param auto_cfg AIGitCommit.AutoConfig
---@return nil
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
end

return M
