local M = {}

---@class AIGitCommit.GitCommandOpts
---@field bufnr? integer


---@param cmd string[]
---@param opts? AIGitCommit.GitCommandOpts
---@param callback fun(stdout: string, code: integer, err: string?)
local function run_git(cmd, opts, callback)
	opts = opts or {}
	local full_cmd = { "git" }
	vim.list_extend(full_cmd, cmd)
	local cwd = vim.uv.cwd()

	if opts.bufnr and vim.api.nvim_buf_is_valid(opts.bufnr) then
		local name = vim.api.nvim_buf_get_name(opts.bufnr)
		if name ~= "" and not name:match("^%w[%w+.-]*://") then
			local root = vim.fs.root(name, ".git")
			if root then
				cwd = root
			end
		end
	end

	vim.system(full_cmd, { text = true, cwd = cwd }, function(obj)
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

---@param stdout string
---@return AIGitCommit.StagedFile[]
local function parse_name_status(stdout)
	---@type AIGitCommit.StagedFile[]
	local files = {}
	local parts = vim.split(stdout, "\0", { plain = true, trimempty = true })
	local i = 1

	while i <= #parts do
		local status = parts[i]
		if status == nil or status == "" then
			break
		end

		if status:match("^[RC]") then
			local old_file = parts[i + 1]
			local new_file = parts[i + 2]
			if old_file and new_file then
				table.insert(files, {
					status = status,
					file = string.format("%s -> %s", old_file, new_file),
					old_file = old_file,
					new_file = new_file,
				})
			end
			i = i + 3
		else
			local file = parts[i + 1]
			if file then
				table.insert(files, { status = status, file = file })
			end
			i = i + 2
		end
	end
	return files
end

---@param bufnr integer?
---@param callback fun(diff: string, err: string?)
function M.get_staged_diff(bufnr, callback)
	run_git({ "diff", "--cached" }, { bufnr = bufnr }, function(stdout, code, stderr)
		if code ~= 0 then
			callback("", build_git_error(stdout, stderr, "Failed to get staged diff"))
			return
		end

		callback(stdout, nil)
	end)
end

---@param bufnr integer?
---@param callback fun(diff: string, err: string?)
function M.get_head_diff(bufnr, callback)
	run_git({ "show", "--format=", "--no-ext-diff", "HEAD" }, { bufnr = bufnr }, function(stdout, code, stderr)
		if code ~= 0 then
			callback("", build_git_error(stdout, stderr, "Failed to get HEAD diff"))
			return
		end

		callback(stdout, nil)
	end)
end

---@class AIGitCommit.StagedFile
---@field status string
---@field file string
---@field old_file? string
---@field new_file? string

---@param bufnr integer?
---@param callback fun(files: AIGitCommit.StagedFile[], err: string?)
function M.get_staged_files(bufnr, callback)
	run_git({ "diff", "--cached", "--name-status", "-z" }, { bufnr = bufnr }, function(stdout, code, stderr)
		if code ~= 0 then
			callback({}, build_git_error(stdout, stderr, "Failed to get staged files"))
			return
		end

		callback(parse_name_status(stdout), nil)
	end)
end

---@param bufnr integer?
---@param callback fun(files: AIGitCommit.StagedFile[], err: string?)
function M.get_head_files(bufnr, callback)
	run_git(
		{ "diff-tree", "--no-commit-id", "--name-status", "-z", "-r", "--root", "HEAD" },
		{ bufnr = bufnr },
		function(stdout, code, stderr)
			if code ~= 0 then
				callback({}, build_git_error(stdout, stderr, "Failed to get HEAD files"))
				return
			end

			callback(parse_name_status(stdout), nil)
		end
	)
end


return M
