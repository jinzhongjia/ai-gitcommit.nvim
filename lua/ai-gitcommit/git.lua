local uv = vim.uv

local M = {}

---@param cmd string[]
---@param callback fun(stdout: string, code: integer)
local function run_git(cmd, callback)
	local stdout_pipe = uv.new_pipe()
	local stdout_chunks = {}

	local handle, pid = uv.spawn("git", {
		args = cmd,
		stdio = { nil, stdout_pipe, nil },
	}, function(code)
		stdout_pipe:close()
		local stdout = table.concat(stdout_chunks, "")
		vim.schedule(function()
			callback(stdout, code)
		end)
	end)

	if not handle then
		vim.schedule(function()
			callback("", 1)
		end)
		return
	end

	stdout_pipe:read_start(function(err, data)
		if data then
			table.insert(stdout_chunks, data)
		end
	end)
end

---@param callback fun(diff: string)
function M.get_staged_diff(callback)
	run_git({ "diff", "--cached" }, function(stdout)
		callback(stdout)
	end)
end

---@class AIGitCommit.StagedFile
---@field status string
---@field file string

---@param callback fun(files: AIGitCommit.StagedFile[])
function M.get_staged_files(callback)
	run_git({ "diff", "--cached", "--name-status" }, function(stdout)
		local files = {}
		for line in stdout:gmatch("[^\n]+") do
			local status, file = line:match("^(%S+)%s+(.+)$")
			if status and file then
				table.insert(files, { status = status, file = file })
			end
		end
		callback(files)
	end)
end

---@return boolean
function M.is_git_repo()
	local stdout_pipe = uv.new_pipe()
	local done = false
	local result_code = 1

	local handle = uv.spawn("git", {
		args = { "rev-parse", "--git-dir" },
		stdio = { nil, stdout_pipe, nil },
	}, function(code)
		stdout_pipe:close()
		result_code = code
		done = true
	end)

	if not handle then
		return false
	end

	while not done do
		uv.run("once")
	end

	return result_code == 0
end

---@param callback fun(root: string?)
function M.get_repo_root(callback)
	run_git({ "rev-parse", "--show-toplevel" }, function(stdout, code)
		if code == 0 and stdout ~= "" then
			callback(vim.trim(stdout))
		else
			callback(nil)
		end
	end)
end

return M
