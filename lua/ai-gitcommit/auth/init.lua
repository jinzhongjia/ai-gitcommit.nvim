local M = {}

---@param provider string
---@return table?, string?
local function get_auth_module(provider)
	if provider == "anthropic" then
		return require("ai-gitcommit.auth.anthropic"), nil
	end

	if provider == "copilot" then
		return require("ai-gitcommit.auth.copilot"), nil
	end

	if provider == "openai" then
		return nil, "OpenAI does not support OAuth login. Configure providers.openai.api_key"
	end

	return nil, "Unsupported provider: " .. tostring(provider)
end

---@param provider string
---@param callback fun(result: table?, err: string?)
function M.get_token(provider, callback)
	local mod, err = get_auth_module(provider)
	if not mod then
		callback(nil, err)
		return
	end
	mod.get_token(callback)
end

---@param provider string
---@return boolean
function M.is_authenticated(provider)
	local mod = get_auth_module(provider)
	if not mod then
		return false
	end
	return mod.is_authenticated()
end

---@param provider string
---@param callback fun(result: table?, err: string?)
function M.login(provider, callback)
	local mod, err = get_auth_module(provider)
	if not mod then
		callback(nil, err)
		return
	end
	mod.login(callback)
end

---@param provider string
---@return boolean, string?
function M.logout(provider)
	local mod, err = get_auth_module(provider)
	if not mod then
		return false, err
	end
	mod.logout()
	return true, nil
end

return M
