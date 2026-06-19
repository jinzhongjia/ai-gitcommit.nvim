local M = {}

---@class AIGitCommit.BufferState
---@field generated boolean
---@field generating boolean
---@field timer userdata?
---@field stream_handle AIGitCommit.StreamHandle?

---@type table<integer, AIGitCommit.BufferState>
local states = {}


---@param bufnr integer
---@return AIGitCommit.BufferState
function M.get(bufnr)
	states[bufnr] = states[bufnr]
		or {
			generated = false,
			generating = false,
			timer = nil,
			stream_handle = nil,
		}
	return states[bufnr]
end

---@param bufnr integer
---@return nil
function M.stop_timer(bufnr)
	local s = states[bufnr]
	if not s then
		return
	end

	if s.timer then
		pcall(function()
			s.timer:stop()
			s.timer:close()
		end)
	end
	s.timer = nil
end

---@param bufnr integer
---@return nil
function M.cancel_stream(bufnr)
	local s = states[bufnr]
	if not s then
		return
	end

	if s.stream_handle then
		require("ai-gitcommit.stream").cancel(s.stream_handle)
	end
	s.stream_handle = nil
	s.generating = false
end

---@return nil
function M.stop_all_timers()
	for bufnr, _ in pairs(states) do
		M.stop_timer(bufnr)
	end
end

---@param bufnr integer
---@return nil
function M.clear(bufnr)
	M.stop_timer(bufnr)
	M.cancel_stream(bufnr)
	states[bufnr] = nil
end

return M
