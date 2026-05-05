local M = {}

---@class AIGitCommit.BufferState
---@field generated boolean
---@field generating boolean
---@field timer userdata?
---@field stream_handle AIGitCommit.StreamHandle?

---@type table<integer, AIGitCommit.BufferState>
local states = {}

---@param timer userdata?
local function stop_timer(timer)
	if not timer then
		return
	end

	pcall(function()
		timer:stop()
		timer:close()
	end)
end

---@param stream_handle AIGitCommit.StreamHandle?
local function cancel_stream(stream_handle)
	if not stream_handle then
		return
	end

	require("ai-gitcommit.stream").cancel(stream_handle)
end

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
function M.stop_timer(bufnr)
	local s = states[bufnr]
	if not s then
		return
	end

	stop_timer(s.timer)
	s.timer = nil
end

---@param bufnr integer
function M.cancel_stream(bufnr)
	local s = states[bufnr]
	if not s then
		return
	end

	cancel_stream(s.stream_handle)
	s.stream_handle = nil
	s.generating = false
end

function M.stop_all_timers()
	for bufnr, _ in pairs(states) do
		M.stop_timer(bufnr)
	end
end

---@param bufnr integer
function M.clear(bufnr)
	M.stop_timer(bufnr)
	M.cancel_stream(bufnr)
	states[bufnr] = nil
end

return M
