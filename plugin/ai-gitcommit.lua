if vim.g.loaded_ai_gitcommit then
	return
end
vim.g.loaded_ai_gitcommit = true

vim.api.nvim_create_autocmd("FileType", {
	pattern = "gitcommit",
	callback = function()
		local ok, ai_gitcommit = pcall(require, "ai-gitcommit")
		if not ok then
			return
		end

		vim.api.nvim_buf_create_user_command(0, "AICommit", function(opts)
			local extra = opts.args ~= "" and opts.args or nil
			ai_gitcommit.generate(extra)
		end, {
			nargs = "*",
			desc = "Generate commit message using AI",
		})
	end,
})
