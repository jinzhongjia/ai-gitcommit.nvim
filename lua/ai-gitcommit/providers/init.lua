local M = {}

local providers = {
	openai = "ai-gitcommit.providers.openai",
	anthropic = "ai-gitcommit.providers.anthropic",
	copilot = "ai-gitcommit.providers.copilot",
}

---@param name string
---@return table?
function M.get(name)
	local module_path = providers[name]
	if not module_path then
		return nil
	end
	return require(module_path)
end

return M
