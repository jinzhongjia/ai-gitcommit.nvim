local autogen = require("ai-gitcommit.autogen")
local buffer_state = require("ai-gitcommit.buffer_state")
local commands = require("ai-gitcommit.commands")
local config = require("ai-gitcommit.config")
local generator = require("ai-gitcommit.generator")

local M = {}

local CLEANUP_GROUP = vim.api.nvim_create_augroup("AIGitCommitLifecycle", { clear = true })
local active_keymap ---@type string?

---@param opts? AIGitCommit.Config
function M.setup(opts)
	config.setup(opts)
	commands.setup()

	local cfg = config.get()

	if active_keymap then
		pcall(vim.keymap.del, "n", active_keymap)
		active_keymap = nil
	end

	if cfg.keymap then
		active_keymap = cfg.keymap
		vim.keymap.set("n", cfg.keymap, function()
			M.generate()
		end, { desc = "AI Generate Commit Message" })
	end

	autogen.setup(cfg.auto)
	vim.api.nvim_clear_autocmds({ group = CLEANUP_GROUP })

	vim.api.nvim_create_autocmd({ "BufDelete", "BufUnload" }, {
		group = CLEANUP_GROUP,
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
