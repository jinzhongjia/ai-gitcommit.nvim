local uv = vim.uv

local M = {}

---@param cmd string[]
---@param callback fun(stdout: string, code: integer, err: string?)
local function run_git(cmd, callback)
	local stdout_pipe = uv.new_pipe()
	local stderr_pipe = uv.new_pipe()
	if not stdout_pipe or not stderr_pipe then
		vim.schedule(function()
			callback("", 1, "failed to create pipe")
		end)
		return
	end

	local stdout_chunks = {}
	local stderr_chunks = {}

	---@diagnostic disable-next-line: missing-fields
	local handle, spawn_err = uv.spawn("git", {
		args = cmd,
		stdio = { nil, stdout_pipe, stderr_pipe },
	}, function(code)
		stdout_pipe:close()
		stderr_pipe:close()
		local stdout = table.concat(stdout_chunks, "")
		local stderr = table.concat(stderr_chunks, "")
		vim.schedule(function()
			callback(stdout, code, stderr ~= "" and stderr or nil)
		end)
	end)

	if not handle then
		stdout_pipe:close()
		stderr_pipe:close()
		vim.schedule(function()
			callback("", 1, spawn_err --[[@as string?]] or "failed to spawn git")
		end)
		return
	end

	stdout_pipe:read_start(function(_, data)
		if data then
			table.insert(stdout_chunks, data)
		end
	end)

	stderr_pipe:read_start(function(_, data)
		if data then
			table.insert(stderr_chunks, data)
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

---@param callback fun(is_repo: boolean)
function M.is_git_repo(callback)
	run_git({ "rev-parse", "--git-dir" }, function(_, code)
		callback(code == 0)
	end)
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
