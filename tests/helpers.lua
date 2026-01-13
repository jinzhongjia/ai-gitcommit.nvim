local M = {}

---@param opts? table
---@return table
function M.get_test_config(opts)
	return vim.tbl_deep_extend("force", {
		provider = "openai",
		providers = {
			openai = { model = "gpt-4o-mini" },
			anthropic = { model = "claude-sonnet-4-20250514" },
		},
		language = "en",
		commit_style = "conventional",
		max_diff_lines = 500,
		max_diff_size = 32000,
		filter_patterns = {},
		keymap = nil,
	}, opts or {})
end

---@return string
function M.get_sample_diff()
	return [[
diff --git a/src/main.lua b/src/main.lua
index abc1234..def5678 100644
--- a/src/main.lua
+++ b/src/main.lua
@@ -1,5 +1,7 @@
 local M = {}

+local utils = require("utils")
+
 function M.hello()
-  print("hello")
+  utils.log("hello world")
 end

 return M
]]
end

---@return string[]
function M.get_sample_files()
	return { "src/main.lua" }
end

---@return string
function M.get_large_diff()
	local lines = {}
	for i = 1, 1000 do
		table.insert(lines, string.format("+line %d added", i))
	end
	return table.concat(lines, "\n")
end

---@param bufnr integer
---@return string[]
function M.get_buffer_lines(bufnr)
	return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

---@return integer
function M.create_gitcommit_buffer()
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.bo[bufnr].filetype = "gitcommit"
	vim.api.nvim_set_current_buf(bufnr)
	return bufnr
end

function M.cleanup_buffer(bufnr)
	if vim.api.nvim_buf_is_valid(bufnr) then
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end
end

---@param module_name string
function M.unload_module(module_name)
	package.loaded[module_name] = nil
end

function M.reset_config()
	M.unload_module("ai-gitcommit.config")
	M.unload_module("ai-gitcommit")
end

return M
