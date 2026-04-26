local M = {}

---@class AIGitCommit.BufferState
---@field generated boolean
---@field generating boolean
---@field timer userdata?

---@type table<integer, AIGitCommit.BufferState>
local states = {}

---@param bufnr integer
---@return AIGitCommit.BufferState
function M.get(bufnr)
	states[bufnr] = states[bufnr] or { generated = false, generating = false, timer = nil }
	return states[bufnr]
end

---@param bufnr integer
function M.clear(bufnr)
	local s = states[bufnr]
	if s and s.timer then
		pcall(function()
			s.timer:stop()
			s.timer:close()
		end)
	end
	states[bufnr] = nil
end

return M
