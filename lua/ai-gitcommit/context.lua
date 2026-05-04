local M = {}

---@param file AIGitCommit.StagedFile
---@return string[]
local function file_candidates(file)
	local candidates = {}

	if type(file.file) == "string" and file.file ~= "" then
		candidates[#candidates + 1] = file.file
	end

	if type(file.old_file) == "string" and file.old_file ~= "" then
		candidates[#candidates + 1] = file.old_file
	end

	if type(file.new_file) == "string" and file.new_file ~= "" then
		candidates[#candidates + 1] = file.new_file
	end

	return candidates
end

---@param old_file string
---@param new_file string
---@return string
local function diff_file_display(old_file, new_file)
	if old_file == new_file then
		return old_file
	end

	return string.format("%s -> %s", old_file, new_file)
end

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

---@param file AIGitCommit.StagedFile
---@param config AIGitCommit.Config
---@return boolean
local function should_keep_staged_file(file, config)
	for _, candidate in ipairs(file_candidates(file)) do
		if should_keep_file(candidate, config) then
			return true
		end
	end

	return false
end

---@param files AIGitCommit.StagedFile[]
---@param config AIGitCommit.Config
---@return AIGitCommit.StagedFile[]
function M.filter_files(files, config)
	---@type AIGitCommit.StagedFile[]
	local filtered = {}

	for _, file in ipairs(files or {}) do
		if should_keep_staged_file(file, config) then
			filtered[#filtered + 1] = file
		end
	end

	return filtered
end

---@param diff string
---@param config AIGitCommit.Config
---@return string
function M.filter_diff(diff, config)
	local lines = vim.split(diff, "\n")
	local result = {}
	local skip_file = false

	for _, line in ipairs(lines) do
		local old_file, new_file = line:match("^diff %-%-git a/(.-) b/(.-)$")
		if old_file and new_file then
			skip_file = not (
				should_keep_file(old_file, config)
				or should_keep_file(new_file, config)
				or should_keep_file(diff_file_display(old_file, new_file), config)
			)
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
