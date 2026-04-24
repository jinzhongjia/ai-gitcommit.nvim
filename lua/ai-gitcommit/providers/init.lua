local config = require("ai-gitcommit.config")

local M = {}

local registry = {
	openai = "ai-gitcommit.providers.openai",
	copilot = "ai-gitcommit.providers.copilot",
}

---@param provider string
---@return table
function M.get(provider)
	local mod_path = registry[provider]
	if not mod_path then
		error("Unsupported provider: " .. tostring(provider))
	end
	return require(mod_path)
end

---@return boolean
function M.has_current_credentials()
	local info, _ = config.get_provider()
	if not info then
		return false
	end
	return M.get(info.name).has_credentials(info.config)
end

---@param name string
---@return string
function M.status(name)
	local cfg = config.get()
	local provider_config = cfg.providers and cfg.providers[name]
	if not provider_config then
		return "not configured"
	end
	return M.get(name).credential_status(provider_config)
end

return M
