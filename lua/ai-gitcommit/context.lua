local M = {}

---@param text string
---@return number
function M.estimate_tokens(text)
	return math.ceil(#text / 4)
end

---@param filename string
---@param patterns string[]
---@return boolean
function M.should_exclude_file(filename, patterns)
	for _, pattern in ipairs(patterns) do
		if filename:match(pattern) then
			return true
		end
	end
	return false
end

---@param diff string
---@param config AIGitCommit.Config
---@return string
function M.filter_diff(diff, config)
	local patterns = config.filter.exclude_patterns or {}
	local lines = vim.split(diff, "\n")
	local result = {}
	local skip_file = false

	for _, line in ipairs(lines) do
		local file = line:match("^diff %-%-git a/(.-) b/")
		if file then
			skip_file = M.should_exclude_file(file, patterns)
		end

		if not skip_file then
			table.insert(result, line)
		end
	end

	return table.concat(result, "\n")
end

---@param diff string
---@param max_chars number
---@return string
function M.truncate_diff(diff, max_chars)
	if #diff <= max_chars then
		return diff
	end

	local truncated = diff:sub(1, max_chars)
	local last_newline = truncated:match(".*\n()")
	if last_newline then
		truncated = truncated:sub(1, last_newline - 1)
	end

	return truncated .. "\n\n[... diff truncated due to size limit ...]"
end

---@param diff string
---@param files AIGitCommit.StagedFile[]
---@param config AIGitCommit.Config
---@return string
function M.build_context(diff, files, config)
	local filtered = M.filter_diff(diff, config)
	return M.truncate_diff(filtered, config.context.max_diff_chars)
end

return M
