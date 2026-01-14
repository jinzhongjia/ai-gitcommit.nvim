local M = {}

---@return table
function M.get()
	return require("ai-gitcommit.providers.anthropic")
end

return M
