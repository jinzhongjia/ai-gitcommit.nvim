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

			-- Check amend: compare COMMIT_EDITMSG content with HEAD message.
			-- This avoids locale-dependent string matching on git comment text.
			-- Note: COMMIT_EDITMSG is pre-populated by git before the user edits,
			-- so at auto-generation time (before save) the content matches HEAD
			-- for amend commits. If the user has already edited the message, the
			-- content won't match and we'll classify as "normal", which is acceptable
			-- since the user is actively writing their own message.
			-- Limitation: comment stripping assumes default commit.cleanup mode
			-- (lines starting with #). Scissors mode or custom cleanup is not handled.
			local commit_msg_file = git_dir .. "/COMMIT_EDITMSG"
			if vim.fn.filereadable(commit_msg_file) == 1 then
				local content = vim.fn.readfile(commit_msg_file)
				local msg_lines = {}
				for _, line in ipairs(content) do
					if not line:match("^#") then
						table.insert(msg_lines, line)
					end
				end
				local editmsg = vim.trim(table.concat(msg_lines, "\n"))
				if editmsg ~= "" then
					run_git({ "log", "-1", "--format=%B" }, function(head_msg, log_code)
						if log_code == 0 and vim.trim(head_msg) == editmsg then
							run_git({ "rev-parse", "HEAD~" }, function(_, parent_code)
								if parent_code ~= 0 then
									callback("initial", git_dir)
								else
									callback("amend", git_dir)
								end
							end)
						else
							callback("normal", git_dir)
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

---@param filepath string
---@param callback fun(data: string?)
local function async_read_file(filepath, callback)
	vim.uv.fs_stat(filepath, function(err, stat)
		if err or not stat then
			callback(nil)
			return
		end

		vim.uv.fs_open(filepath, "r", 438, function(open_err, fd)
			if open_err or not fd then
				callback(nil)
				return
			end

			vim.uv.fs_read(fd, stat.size, 0, function(read_err, data)
				vim.uv.fs_close(fd, function() end)
				callback((not read_err) and data or nil)
			end)
		end)
	end)
end

---@param git_dir string
---@param callback fun(messages: string?)
function M.get_squash_messages(git_dir, callback)
	local rebase_dir = git_dir .. "/rebase-merge"
	local candidates = { "message-squash", "message" }

	local function try_next(i)
		if i > #candidates then
			vim.schedule(function()
				callback(nil)
			end)
			return
		end

		async_read_file(rebase_dir .. "/" .. candidates[i], function(data)
			if data then
				vim.schedule(function()
					callback(data)
				end)
			else
				try_next(i + 1)
			end
		end)
	end

	try_next(1)
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
