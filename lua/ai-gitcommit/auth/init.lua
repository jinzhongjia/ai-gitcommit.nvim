local M = {}

local registry = {
	copilot = "ai-gitcommit.auth.copilot",
}

---@param provider string
---@return table?, string?
local function get_auth_module(provider)
	local mod_path = registry[provider]
	if mod_path then
		return require(mod_path), nil
	end
	return nil, "Provider has no auth module: " .. tostring(provider)
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
