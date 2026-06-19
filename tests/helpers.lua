local M = {}

---@param opts? table
---@return table
function M.get_test_config(opts)
	return vim.tbl_deep_extend("force", {
		provider = "openai",
		providers = {
			openai = { model = "gpt-4o-mini" },
		},
		languages = { "English" },
		prompt_template = nil,
		context = {
			max_diff_chars = 15000,
		},
		filter = {
			exclude_patterns = {},
		},
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
