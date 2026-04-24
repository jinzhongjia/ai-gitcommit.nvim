local autogen = require("ai-gitcommit.autogen")
local buffer_state = require("ai-gitcommit.buffer_state")
local commands = require("ai-gitcommit.commands")
local config = require("ai-gitcommit.config")
local generator = require("ai-gitcommit.generator")

local M = {}

---@param opts? AIGitCommit.Config
function M.setup(opts)
	config.setup(opts)
	commands.setup()

	local cfg = config.get()

	if cfg.keymap then
		vim.keymap.set("n", cfg.keymap, function()
			M.generate()
		end, { desc = "AI Generate Commit Message" })
	end

	autogen.setup(cfg.auto)

	vim.api.nvim_create_autocmd("BufDelete", {
		callback = function(args)
			buffer_state.clear(args.buf)
		end,
	})
end

---@param extra_context? string
function M.generate(extra_context)
	generator.generate(extra_context)
end

return M
