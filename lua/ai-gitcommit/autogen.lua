local buffer_state = require("ai-gitcommit.buffer_state")
local config = require("ai-gitcommit.config")
local buffer = require("ai-gitcommit.buffer")
local providers = require("ai-gitcommit.providers")

local M = {}

local AUTOGEN_GROUP = vim.api.nvim_create_augroup("AIGitCommitAutogen", { clear = true })

---@param bufnr integer
local function cancel_pending_autogen(bufnr)
	local state = buffer_state.get(bufnr)
	if state.generated or state.generating then
		return
	end

	buffer_state.stop_timer(bufnr)
end

---@param language string
---@param bufnr integer
local function run_generator(language, bufnr)
	require("ai-gitcommit.generator").run(language, nil, bufnr, false)
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
			local bufnr = args.buf
			local state = buffer_state.get(bufnr)
			local initial_tick = vim.api.nvim_buf_get_changedtick(bufnr)
			local initial_message = buffer.get_existing_message(bufnr)

			buffer_state.stop_timer(bufnr)

			vim.api.nvim_create_autocmd({ "InsertEnter", "TextChanged", "TextChangedI" }, {
				group = AUTOGEN_GROUP,
				buffer = bufnr,
				callback = function()
					cancel_pending_autogen(bufnr)
				end,
			})

			state.timer = vim.defer_fn(function()
				state.timer = nil

				if not vim.api.nvim_buf_is_valid(bufnr) then
					return
				end

				if state.generated or state.generating then
					return
				end

				if vim.api.nvim_buf_get_changedtick(bufnr) ~= initial_tick then
					return
				end

				if buffer.get_existing_message(bufnr) ~= initial_message then
					return
				end

				if initial_message ~= "" or buffer.get_existing_message(bufnr) ~= "" then
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
		end,
	})
end

return M
