local M = {}

local auth_modules = {
	copilot = "ai-gitcommit.auth.copilot",
	codex = "ai-gitcommit.auth.codex",
	claude = "ai-gitcommit.auth.claude",
}

---@param provider_name string
---@return table?
local function get_auth_module(provider_name)
	local module_path = auth_modules[provider_name]
	if not module_path then
		return nil
	end
	local ok, module = pcall(require, module_path)
	if not ok then
		return nil
	end
	return module
end

---@param provider_name string
---@param callback fun(result: table?, err: string?)
function M.get_token(provider_name, callback)
	local auth_module = get_auth_module(provider_name)
	if not auth_module then
		callback(nil, "No auth module for provider: " .. provider_name)
		return
	end
	auth_module.get_token(callback)
end

---@param provider_name string
---@return boolean
function M.is_authenticated(provider_name)
	local auth_module = get_auth_module(provider_name)
	if not auth_module then
		return false
	end
	return auth_module.is_authenticated()
end

---@param provider_name string
---@param callback fun(result: table?, err: string?)
function M.login(provider_name, callback)
	local auth_module = get_auth_module(provider_name)
	if not auth_module then
		callback(nil, "No auth module for provider: " .. provider_name)
		return
	end
	auth_module.login(callback)
end

---@param provider_name string
function M.logout(provider_name)
	local auth_module = get_auth_module(provider_name)
	if auth_module then
		auth_module.logout()
	end
end

return M
