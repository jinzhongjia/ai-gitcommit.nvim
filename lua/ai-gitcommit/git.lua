local M = {}

---@param cmd string[]
---@param callback fun(stdout: string, code: integer, err: string?)
local function run_git(cmd, callback)
	local full_cmd = { "git" }
	vim.list_extend(full_cmd, cmd)

	vim.system(full_cmd, { text = true }, function(obj)
		vim.schedule(function()
			local stderr = (obj.stderr and obj.stderr ~= "") and obj.stderr or nil
			callback(obj.stdout or "", obj.code, stderr)
		end)
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
