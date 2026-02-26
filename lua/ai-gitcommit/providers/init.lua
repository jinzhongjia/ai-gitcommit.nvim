local M = {}

---@param provider string
---@return table
function M.get(provider)
	if provider == "openai" then
		return require("ai-gitcommit.providers.openai")
	end

	if provider == "anthropic" then
		return require("ai-gitcommit.providers.anthropic")
	end

	if provider == "copilot" then
		return require("ai-gitcommit.providers.copilot")
	end

	error("Unsupported provider: " .. tostring(provider))
end

return M
