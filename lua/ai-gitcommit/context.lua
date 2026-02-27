local M = {}

---@param filename string
---@param rules string[]
---@return boolean
local function matches_any_rule(filename, rules)
	for _, rule in ipairs(rules or {}) do
		if filename:match(rule) then
			return true
		end
	end

	return false
end

---@param text string
---@return number
function M.estimate_tokens(text)
	return math.ceil(#text / 4)
end

---@param filename string
---@param patterns string[]
---@return boolean
function M.should_exclude_file(filename, patterns)
	return matches_any_rule(filename, patterns)
end

---@param filename string
---@param config AIGitCommit.Config
---@return boolean
local function should_keep_file(filename, config)
	local filter = config.filter or {}
	local include_only = filter.include_only or {}
	local exclude_paths = filter.exclude_paths or {}
	local exclude_patterns = filter.exclude_patterns or {}

	if #include_only > 0 and not matches_any_rule(filename, include_only) then
		return false
	end

	if matches_any_rule(filename, exclude_paths) then
		return false
	end

	if M.should_exclude_file(filename, exclude_patterns) then
		return false
	end

	return true
end

---@param diff string
---@param config AIGitCommit.Config
---@return string
function M.filter_diff(diff, config)
	local lines = vim.split(diff, "\n")
	local result = {}
	local skip_file = false

	for _, line in ipairs(lines) do
		local file = line:match("^diff %-%-git a/(.-) b/")
		if file then
			skip_file = not should_keep_file(file, config)
		end

		if not skip_file then
			table.insert(result, line)
		end
	end

	return table.concat(result, "\n")
end

---@param diff string
---@param max_lines number?
---@return string
function M.truncate_diff_lines(diff, max_lines)
	if type(max_lines) ~= "number" or max_lines <= 0 then
		return diff
	end

	local lines = vim.split(diff, "\n", { plain = true })
	if #lines <= max_lines then
		return diff
	end

	local kept = {}
	for i = 1, max_lines do
		kept[i] = lines[i]
	end

	table.insert(kept, "")
	table.insert(kept, "[... diff truncated due to line limit ...]")

	return table.concat(kept, "\n")
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
---@param config AIGitCommit.Config
---@return string
function M.build_context(diff, config)
	local filtered = M.filter_diff(diff, config)
	local by_lines = M.truncate_diff_lines(filtered, config.context.max_diff_lines)
	return M.truncate_diff(by_lines, config.context.max_diff_chars)
end

return M
