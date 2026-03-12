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

---@param stdout string
---@param stderr string?
---@param fallback string
---@return string
local function build_git_error(stdout, stderr, fallback)
	local err = stderr and vim.trim(stderr) or ""
	if err ~= "" then
		return err
	end

	local out = stdout and vim.trim(stdout) or ""
	if out ~= "" then
		return out
	end

	return fallback
end

---@alias AIGitCommit.CommitType "normal"|"amend"|"squash"|"initial"

---@param callback fun(git_dir: string?)
function M.get_git_dir(callback)
	run_git({ "rev-parse", "--git-dir" }, function(stdout, code)
		if code == 0 and stdout ~= "" then
			callback(vim.trim(stdout))
		else
			callback(nil)
		end
	end)
end

---@param callback fun(commit_type: AIGitCommit.CommitType, git_dir: string?)
function M.detect_commit_type(callback)
	M.get_git_dir(function(git_dir)
		if not git_dir then
			callback("normal", nil)
			return
		end

		-- Check squash/rebase: .git/rebase-merge/ directory exists
		local squash_dir = git_dir .. "/rebase-merge"
		if vim.fn.isdirectory(squash_dir) == 1 then
			callback("squash", git_dir)
			return
		end

		-- Check initial commit (no HEAD)
		run_git({ "rev-parse", "HEAD" }, function(_, head_code)
			if head_code ~= 0 then
				callback("initial", git_dir)
				return
			end

			-- Check amend: read COMMIT_EDITMSG for amend marker comment
			local commit_msg_file = git_dir .. "/COMMIT_EDITMSG"
			if vim.fn.filereadable(commit_msg_file) == 1 then
				local content = vim.fn.readfile(commit_msg_file)
				if table.concat(content, "\n"):find("\n# This is an amend commit", 1, true) then
					-- Verify HEAD~ exists (not amend on initial commit)
					run_git({ "rev-parse", "HEAD~" }, function(_, parent_code)
						if parent_code ~= 0 then
							callback("initial", git_dir)
						else
							callback("amend", git_dir)
						end
					end)
					return
				end
			end

			callback("normal", git_dir)
		end)
	end)
end

---@param commit_type AIGitCommit.CommitType
---@param callback fun(diff: string, err: string?)
function M.get_staged_diff(commit_type, callback)
	local cmd = (commit_type == "amend") and { "diff", "HEAD~", "--cached" } or { "diff", "--cached" }

	run_git(cmd, function(stdout, code, stderr)
		if code ~= 0 then
			callback("", build_git_error(stdout, stderr, "Failed to get staged diff"))
			return
		end

		callback(stdout, nil)
	end)
end

---@class AIGitCommit.StagedFile
---@field status string
---@field file string

---@param commit_type AIGitCommit.CommitType
---@param callback fun(files: AIGitCommit.StagedFile[], err: string?)
function M.get_staged_files(commit_type, callback)
	local cmd = (commit_type == "amend") and { "diff", "HEAD~", "--cached", "--name-status" }
		or { "diff", "--cached", "--name-status" }

	run_git(cmd, function(stdout, code, stderr)
		if code ~= 0 then
			callback({}, build_git_error(stdout, stderr, "Failed to get staged files"))
			return
		end

		local files = {}
		for line in stdout:gmatch("[^\n]+") do
			local status, file = line:match("^(%S+)%s+(.+)$")
			if status and file then
				table.insert(files, { status = status, file = file })
			end
		end
		callback(files, nil)
	end)
end

---@param git_dir string
---@param callback fun(messages: string?)
function M.get_squash_messages(git_dir, callback)
	local rebase_dir = git_dir .. "/rebase-merge"
	-- Try message-squash first, then fall back to message
	for _, filename in ipairs({ "message-squash", "message" }) do
		local filepath = rebase_dir .. "/" .. filename
		if vim.fn.filereadable(filepath) == 1 then
			local content = vim.fn.readfile(filepath)
			callback(table.concat(content, "\n"))
			return
		end
	end

	callback(nil)
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
