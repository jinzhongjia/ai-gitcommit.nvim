local M = {}

function M.is_authenticated()
	return false
end

---@param callback fun(data: table?, err: string?)
function M.get_token(callback)
	callback(nil, "OpenAI Codex OAuth not yet implemented")
end

---@param callback fun(data: table?, err: string?)
function M.login(callback)
	callback(nil, "OpenAI Codex OAuth not yet implemented")
end

function M.logout()
	vim.notify("OpenAI Codex OAuth not yet implemented", vim.log.levels.WARN)
end

return M
