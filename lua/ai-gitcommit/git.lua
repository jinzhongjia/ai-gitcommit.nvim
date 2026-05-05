local M = {}

---@class AIGitCommit.GitCommandOpts
---@field bufnr? integer

---@param bufnr_or_callback? integer|function
---@param callback? function
---@return integer?, function
local function normalize_args(bufnr_or_callback, callback)
	if type(bufnr_or_callback) == "function" then
		return nil, bufnr_or_callback
	end

	return bufnr_or_callback, callback
end

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
			local candidate = vim.fs.dirname(name)
			local stat = candidate and vim.uv.fs_stat(candidate) or nil
			if stat and stat.type == "directory" then
				cwd = candidate
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

---@param bufnr_or_callback? integer|fun(diff: string, err: string?)
---@param callback fun(diff: string, err: string?)
function M.get_staged_diff(bufnr_or_callback, callback)
	local bufnr
	bufnr, callback = normalize_args(bufnr_or_callback, callback)
	run_git({ "diff", "--cached" }, { bufnr = bufnr }, function(stdout, code, stderr)
		if code ~= 0 then
			callback("", build_git_error(stdout, stderr, "Failed to get staged diff"))
			return
		end

		callback(stdout, nil)
	end)
end

---@param bufnr_or_callback? integer|fun(diff: string, err: string?)
---@param callback fun(diff: string, err: string?)
function M.get_head_diff(bufnr_or_callback, callback)
	local bufnr
	bufnr, callback = normalize_args(bufnr_or_callback, callback)
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

---@param bufnr_or_callback? integer|fun(files: AIGitCommit.StagedFile[], err: string?)
---@param callback fun(files: AIGitCommit.StagedFile[], err: string?)
function M.get_staged_files(bufnr_or_callback, callback)
	local bufnr
	bufnr, callback = normalize_args(bufnr_or_callback, callback)
	run_git({ "diff", "--cached", "--name-status", "-z" }, { bufnr = bufnr }, function(stdout, code, stderr)
		if code ~= 0 then
			callback({}, build_git_error(stdout, stderr, "Failed to get staged files"))
			return
		end

		callback(parse_name_status(stdout), nil)
	end)
end

---@param bufnr_or_callback? integer|fun(files: AIGitCommit.StagedFile[], err: string?)
---@param callback fun(files: AIGitCommit.StagedFile[], err: string?)
function M.get_head_files(bufnr_or_callback, callback)
	local bufnr
	bufnr, callback = normalize_args(bufnr_or_callback, callback)
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

---@param bufnr_or_callback? integer|fun(is_repo: boolean)
---@param callback fun(is_repo: boolean)
function M.is_git_repo(bufnr_or_callback, callback)
	local bufnr
	bufnr, callback = normalize_args(bufnr_or_callback, callback)
	run_git({ "rev-parse", "--git-dir" }, { bufnr = bufnr }, function(_, code)
		callback(code == 0)
	end)
end

---@param bufnr_or_callback? integer|fun(root: string?)
---@param callback fun(root: string?)
function M.get_repo_root(bufnr_or_callback, callback)
	local bufnr
	bufnr, callback = normalize_args(bufnr_or_callback, callback)
	run_git({ "rev-parse", "--show-toplevel" }, { bufnr = bufnr }, function(stdout, code)
		if code == 0 and stdout ~= "" then
			callback(vim.trim(stdout))
		else
			callback(nil)
		end
	end)
end

return M
