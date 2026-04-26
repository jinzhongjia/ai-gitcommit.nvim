local M = {}

---@param path string
---@return string?
function M.read_file(path)
	if vim.fn.filereadable(path) ~= 1 then
		return nil
	end
	local lines = vim.fn.readfile(path)
	return table.concat(lines, "\n")
end

---@param path string
---@param content string
function M.write_file(path, content)
	vim.fn.writefile({ content }, path)
end

---@param path string
function M.ensure_dir(path)
	vim.fn.mkdir(path, "p")
end

return M
