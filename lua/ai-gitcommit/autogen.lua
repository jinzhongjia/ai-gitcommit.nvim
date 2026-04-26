local buffer_state = require("ai-gitcommit.buffer_state")
local config = require("ai-gitcommit.config")
local generator = require("ai-gitcommit.generator")
local providers = require("ai-gitcommit.providers")

local M = {}

---@param auto_cfg AIGitCommit.AutoConfig
function M.setup(auto_cfg)
	if not auto_cfg or not auto_cfg.enabled then
		return
	end

	local debounce_ms = auto_cfg.debounce_ms or 300

	vim.api.nvim_create_autocmd("FileType", {
		pattern = "gitcommit",
		callback = function(args)
			local bufnr = args.buf
			local state = buffer_state.get(bufnr)

			if state.timer then
				pcall(function()
					state.timer:stop()
					state.timer:close()
				end)
			end

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
					generator.run(languages[1], nil, bufnr, false)
					return
				end

				vim.ui.select(languages, { prompt = "Select language:" }, function(choice)
					if not choice then
						return
					end
					generator.run(choice, nil, bufnr, false)
				end)
			end, debounce_ms)
		end,
	})
end

return M
