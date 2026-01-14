local M = {}

local function get_auth_module()
	return require("ai-gitcommit.auth.anthropic")
end

---@param callback fun(result: table?, err: string?)
function M.get_token(callback)
	get_auth_module().get_token(callback)
end

---@return boolean
function M.is_authenticated()
	return get_auth_module().is_authenticated()
end

---@param callback fun(result: table?, err: string?)
function M.login(callback)
	get_auth_module().login(callback)
end

function M.logout()
	get_auth_module().logout()
end

return M
