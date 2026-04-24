local M = {}

--- One-shot curl invocation (non-streaming). Collects stdout into a single
--- string and yields it with the exit code on the main loop.
---@param args string[]
---@param callback fun(stdout: string, code: integer)
function M.curl(args, callback)
	local full_cmd = { "curl" }
	vim.list_extend(full_cmd, args)

	vim.system(full_cmd, { text = true }, function(obj)
		vim.schedule(function()
			callback(obj.stdout or "", obj.code)
		end)
	end)
end

return M
