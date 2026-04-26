local M = {}

---@param bufnr? number
---@return string
local function get_comment_prefix(bufnr)
	bufnr = bufnr or 0
	local commentstring = vim.api.nvim_get_option_value("commentstring", { buf = bufnr })
	if type(commentstring) ~= "string" or commentstring == "" then
		return "#"
	end

	local prefix = commentstring:match("^(.*)%%s")
	if not prefix or prefix == "" then
		return "#"
	end

	return vim.trim(prefix)
end

---@param line string
---@param bufnr? number
---@return boolean
local function is_comment_line(line, bufnr)
	local prefix = get_comment_prefix(bufnr)
	return prefix ~= "" and line:sub(1, #prefix) == prefix
end

---@param bufnr? number
---@return boolean
function M.is_gitcommit_buffer(bufnr)
	bufnr = bufnr or 0
	local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
	return ft == "gitcommit"
end

---@param bufnr? number
---@return number
function M.find_first_comment_line(bufnr)
	bufnr = bufnr or 0
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	for i, line in ipairs(lines) do
		if is_comment_line(line, bufnr) then
			return i
		end
	end
	return #lines + 1
end

---@param bufnr? number
---@return string
function M.get_existing_message(bufnr)
	bufnr = bufnr or 0
	local first_comment = M.find_first_comment_line(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, first_comment - 1, false)

	while #lines > 0 and lines[#lines] == "" do
		table.remove(lines)
	end

	return table.concat(lines, "\n")
end

---@param message string
---@param bufnr? number
function M.set_commit_message(message, bufnr)
	bufnr = bufnr or 0
	local first_comment = M.find_first_comment_line(bufnr)
	local message_lines = vim.split(message, "\n")

	if #message_lines > 0 and message_lines[#message_lines] ~= "" then
		table.insert(message_lines, "")
	end

	vim.api.nvim_buf_set_lines(bufnr, 0, first_comment - 1, false, message_lines)

	local win = vim.fn.bufwinid(bufnr)
	if win ~= -1 then
		vim.api.nvim_win_set_cursor(win, { 1, 0 })
	end
end

return M
